`timescale 1ns/1ps

// Dedicated regression testbench for the 5-stage pipelined RV32 CPU.
//
// This testbench is intentionally separate from the single-cycle regression.
// It focuses on:
//   - normal ALU / immediate execution
//   - load/store operations
//   - EX/MEM and MEM/WB forwarding
//   - load-use stalls
//   - store-data forwarding
//   - taken/not-taken branches and pipeline flushing
//   - JAL/JALR flushing and link values
//   - LUI/AUIPC
//
// IMPORTANT:
// Every test clears instruction memory, data memory, and registers.
// This prevents instructions from a previous test from remaining in the
// instruction memory and executing later.

module cpu_pipelined_tb;

    reg clk;
    reg reset;

    integer pass_count;
    integer fail_count;
    integer stall_count;

    CPU dut (
        .clk(clk),
        .reset(reset)
    );

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // RV32 instruction encoders
    // ------------------------------------------------------------------------

    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
        end
    endfunction

    function [31:0] enc_i;
        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            enc_i = {imm[11:0], rs1, funct3, rd, 7'b0010011};
        end
    endfunction

    function [31:0] enc_i_load;
        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            enc_i_load = {imm[11:0], rs1, funct3, rd, 7'b0000011};
        end
    endfunction

    function [31:0] enc_i_jalr;
        input integer imm;
        input [4:0] rs1;
        input [4:0] rd;
        begin
            enc_i_jalr = {imm[11:0], rs1, 3'b000, rd, 7'b1100111};
        end
    endfunction

    function [31:0] enc_s;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_b;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        reg [12:0] bimm;
    
        begin
            bimm = imm[12:0];
    
            enc_b = {
                bimm[12],
                bimm[10:5],
                rs2,
                rs1,
                funct3,
                bimm[4:1],
                bimm[11],
                7'b1100011
            };
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_u = {imm20, rd, opcode};
        end
    endfunction

    function [31:0] enc_j;
        input integer imm;
        input [4:0] rd;
        reg [20:0] jimm;
        begin
            jimm = imm[20:0];
            enc_j = {
                jimm[20],
                jimm[10:1],
                jimm[11],
                jimm[19:12],
                rd,
                7'b1101111
            };
        end
    endfunction

    // ------------------------------------------------------------------------
    // Testbench helpers
    // ------------------------------------------------------------------------

    task clear_instruction_memory;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                dut.instruction_Memory.memory[i] = 32'b0;
        end
    endtask

    task clear_data_memory;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                dut.data_Memory.data_memory[i] = 32'b0;
        end
    endtask

    task clear_registers;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                dut.reg_File_Pipelined.registers[i] = 32'b0;
        end
    endtask

    task reset_cpu;
        begin
            reset = 1'b1;
            #12;
            reset = 1'b0;
        end
    endtask

    task begin_test;
        begin
            clear_instruction_memory;
            clear_data_memory;
            clear_registers;
            reset_cpu;
        end
    endtask

    // A normal short straight-line program needs about 5 cycles to drain.
    // 12 cycles gives comfortable margin while keeping tests quick.
    task run_program;
        input integer cycles;
        begin
            #(cycles * 10);
        end
    endtask

    task check_reg;
        input [4:0] reg_num;
        input [31:0] expected;
        input [255:0] name;
        reg [31:0] actual;
        begin
            actual = dut.reg_File_Pipelined.registers[reg_num];

            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %s = %08h", name, actual);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s = %08h, expected %08h",
                         name, actual, expected);
            end
        end
    endtask

    task check_mem;
        input integer byte_address;
        input [31:0] expected;
        input [255:0] name;
        reg [31:0] actual;
        begin
            actual = dut.data_Memory.data_memory[byte_address >> 2];

            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %s = %08h", name, actual);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s = %08h, expected %08h",
                         name, actual, expected);
            end
        end
    endtask

    task check_stall_seen;
        input [255:0] name;
        begin
            if (stall_count > 0) begin
                pass_count = pass_count + 1;
                $display("PASS: %s (stall observed %0d time(s))",
                         name, stall_count);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s (no stall observed)", name);
            end
        end
    endtask

    // Count actual load-use stalls while the test is running.
    always @(posedge clk) begin
        if (!reset && dut.stall)
            stall_count = stall_count + 1;
    end

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------
    integer i;
    initial begin
        pass_count = 0;
        fail_count = 0;
        stall_count = 0;
        reset = 1'b1;

        // ====================================================================
        // 1. Basic ALU + immediate operations
        // ====================================================================
        $display("\n=== TEST 1: BASIC ALU / IMMEDIATE ===");

        begin_test;
        dut.instruction_Memory.memory[0] = enc_i(5, 0, 3'b000, 1);  // ADDI x1,x0,5
        dut.instruction_Memory.memory[1] = enc_i(3, 0, 3'b000, 2);  // ADDI x2,x0,3
        dut.instruction_Memory.memory[2] = enc_r(7'b0000000, 2, 1, 3'b000, 3); // ADD x3, x1, x2
        dut.instruction_Memory.memory[3] = enc_r(7'b0100000, 2, 1, 3'b000, 4); // SUB x4, x2, x1
        dut.instruction_Memory.memory[4] = enc_r(7'b0000000, 2, 1, 3'b111, 5); // AND x5, x1, x2
        dut.instruction_Memory.memory[5] = enc_r(7'b0000000, 2, 1, 3'b110, 6); // OR x6, x1, x2
        dut.instruction_Memory.memory[6] = enc_r(7'b0000000, 2, 1, 3'b100, 7); // XOR x7, x1, x2
        dut.instruction_Memory.memory[7] = enc_r(7'b0000000, 2, 1, 3'b001, 8); // SLL x8, x1, x2
        dut.instruction_Memory.memory[8] = enc_r(7'b0000000, 2, 1, 3'b101, 9); // SRL x9, x1, x2
        dut.instruction_Memory.memory[9] = enc_r(7'b0100000, 2, 1, 3'b101, 10); // SRA x10, x1, x2
        dut.instruction_Memory.memory[10] = enc_r(7'b0000000, 1, 2, 3'b010, 11); // SLT x11, x2, x1s
        dut.instruction_Memory.memory[11] = enc_r(7'b0000000, 1, 2, 3'b011, 12); // SLTU x12, x2, x1
        dut.instruction_Memory.memory[12] = enc_i(12, 0, 3'b000, 13); // ADDI x13, x0, 12

        for(i = 1; i <= 20; i = i + 1) begin
            
            $display(i);
            run_program(1);
//            $display("ex_mem_rd: %h", dut.ex_mem_rd);
//            $display("mem_wb_rd: %h", dut.mem_wb_rd);
//            $display("id_ex_rd: %h", dut.id_ex_rd);
//            $display("id_ex_rs1: %h", dut.id_ex_rs1);
//            $display("id_ex_rs2: %h", dut.id_ex_rs2);
//            $display("forward_a: %b", dut.forward_a);
//            $display("forward_b: %b", dut.forward_b);
//            $display("forwarded_rs1: %h", dut.forwarded_rs1);
//            $display("forwarded_rs2: %h", dut.forwarded_rs2);
//            $display("alu_a: %h", dut.alu_a);
//            $display("alu_b: %h", dut.alu_b);
//            $display("alu_src_b: %h", dut.alu_Src_Mux_Pipelined.alu_src_b);
//            $display("id_ex_rs2_data: %h", dut.id_ex_rs2_data);
//            $display("reset: %b", dut.reset);
//            $display("flush: %b", dut.control_hazard);
//
//            $display("if_id_rs1: %h", dut.if_id_rs1);
//            $display("if_id_rs2: %h", dut.if_id_rs2);
//            $display("if_id_rd: %h", dut.if_id_rd);
//            $display("rs1_data: %h", dut.alu_Src_Mux_Pipelined.rs1_data);
//            $display("rs2_data: %h", dut.alu_Src_Mux_Pipelined.rs2_data);
//
//            $display("x1: %h", dut.reg_File_Pipelined.registers[1]);
//            $display("x2: %h", dut.reg_File_Pipelined.registers[2]);

            //$display("alu_src_b: %b", dut.alu_Src_Mux_Pipelined.alu_src_b);
            //$display("auipc || jal: %b", (dut.alu_Src_Mux_Pipelined.auipc||dut.alu_Src_Mux_Pipelined.jal));
            
        end
        check_reg(1, 32'd5,  "ADDI x1");
        check_reg(2, 32'd3,  "ADDI x2");
        check_reg(3, 32'd8,  "ADD x3");
        check_reg(4, 32'd2,  "SUB x4");
        check_reg(5, 32'd1,  "AND x5");
        check_reg(6, 32'd7,  "OR x6");
        check_reg(7, 32'd6,  "XOR x7");
        check_reg(8, 32'd40, "SLL x8");
        check_reg(9, 32'd0,  "SRL x9");
        check_reg(10, 32'd0, "SRA x10");
        check_reg(11, 32'd1, "SLT x11");
        check_reg(12, 32'd1, "SLTU x12");
        check_reg(13, 32'd12, "ADDI x13");

        // ====================================================================
        // 2. Forwarding: EX/MEM -> operands
        // ====================================================================
        $display("\n=== TEST 2: EX/MEM FORWARDING ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_i(10, 0, 3'b000, 1); // x1=10
        dut.instruction_Memory.memory[1] = enc_i(7,  0, 3'b000, 2); // x2=7
        dut.instruction_Memory.memory[2] = enc_r(7'b0000000, 2, 1, 3'b000, 3); // x3=x1+x2
        dut.instruction_Memory.memory[3] = enc_r(7'b0000000, 2, 3, 3'b000, 4); // x4=x3+x2
        dut.instruction_Memory.memory[4] = enc_r(7'b0000000, 3, 4, 3'b000, 5); // x5=x4+x3

        run_program(14);

        check_reg(3, 17, "EX/MEM fwd x3");
        check_reg(4, 24, "EX/MEM fwd x4");
        check_reg(5, 41, "EX/MEM fwd x5");

        // ====================================================================
        // 3. MEM/WB forwarding
        // ====================================================================
        $display("\n=== TEST 3: MEM/WB FORWARDING ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_i(21, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i(5,  0, 3'b000, 2);
        dut.instruction_Memory.memory[2] = enc_i(9,  0, 3'b000, 3);
        dut.instruction_Memory.memory[3] = enc_r(7'b0000000, 1, 3, 3'b000, 4);

        run_program(13);

        check_reg(4, 30, "MEM/WB fwd x4");

        // ====================================================================
        // 4. Forwarding priority: EX/MEM must beat MEM/WB
        // ====================================================================
        $display("\n=== TEST 4: FORWARDING PRIORITY ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_i(10, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i(20, 1, 3'b000, 1); // x1=30
        dut.instruction_Memory.memory[2] = enc_r(7'b0000000, 0, 1, 3'b000, 2);

        run_program(11);

        check_reg(1, 30, "priority x1");
        check_reg(2, 30, "EX/MEM priority");

        // ====================================================================
        // 5. Load-use stall + MEM/WB forwarding
        // ====================================================================
        $display("\n=== TEST 5: LOAD-USE HAZARD ===");
        begin_test;

        dut.data_Memory.data_memory[0] = 32'd10;

        dut.instruction_Memory.memory[0] = enc_i_load(0, 2, 3'b010, 1); // lw x1,0(x2)
        dut.instruction_Memory.memory[1] = enc_r(7'b0000000, 4, 1, 3'b000, 3); // add x3,x1,x4

        dut.reg_File_Pipelined.registers[2] = 0;
        dut.reg_File_Pipelined.registers[4] = 5;

        stall_count = 0;
        run_program(12);

        check_reg(1, 10, "LW x1");
        check_reg(3, 15, "LW->ADD x3");
        check_stall_seen("load-use stall");

        // ====================================================================
        // 6. Store-data forwarding from EX/MEM
        // ====================================================================
        $display("\n=== TEST 6: STORE DATA EX/MEM FORWARDING ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_i(42, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_s(0, 1, 2, 3'b010); // sw x1,0(x2)

        dut.reg_File_Pipelined.registers[2] = 0;

        run_program(10);

        check_mem(0, 42, "EX/MEM -> SW data");

        // ====================================================================
        // 7. Store-data forwarding from MEM/WB
        // ====================================================================
        $display("\n=== TEST 7: STORE DATA MEM/WB FORWARDING ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_i(55, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i(10, 0, 3'b000, 3);
        dut.instruction_Memory.memory[2] = enc_s(4, 1, 2, 3'b010); // sw x1,4(x2)

        dut.reg_File_Pipelined.registers[2] = 0;

        run_program(11);

        check_mem(4, 55, "MEM/WB -> SW data");

        // ====================================================================
        // 8. LW -> SW: stall followed by forwarding
        // ====================================================================
        $display("\n=== TEST 8: LW -> SW ===");
        begin_test;

        dut.data_Memory.data_memory[0] = 32'd99;

        dut.instruction_Memory.memory[0] = enc_i_load(0, 2, 3'b010, 1); // lw x1,0(x2)
        dut.instruction_Memory.memory[1] = enc_s(4, 1, 2, 3'b010);      // sw x1,4(x2)

        dut.reg_File_Pipelined.registers[2] = 0;

        stall_count = 0;
        run_program(12);

        check_mem(4, 99, "LW -> SW");
        check_stall_seen("LW->SW stall");

        // ====================================================================
        // 9. Byte / halfword / word loads and stores
        // ====================================================================
        $display("\n=== TEST 9: LOAD / STORE SIZES ===");
        begin_test;

        dut.data_Memory.data_memory[0] = 32'hFF80_7F01;

        dut.instruction_Memory.memory[0] = enc_i_load(0, 2, 3'b010, 1); // LW
        dut.instruction_Memory.memory[1] = enc_i_load(0, 2, 3'b000, 3); // LB
        dut.instruction_Memory.memory[2] = enc_i_load(0, 2, 3'b100, 4); // LBU
        dut.instruction_Memory.memory[3] = enc_i_load(1, 2, 3'b000, 5); // LB
        dut.instruction_Memory.memory[4] = enc_i_load(2, 2, 3'b000, 6); // LB
        dut.instruction_Memory.memory[5] = enc_i_load(2, 2, 3'b100, 7); // LBU
        dut.instruction_Memory.memory[6] = enc_i_load(0, 2, 3'b001, 8); // LH
        dut.instruction_Memory.memory[7] = enc_i_load(2, 2, 3'b001, 9); // LH
        dut.instruction_Memory.memory[8] = enc_i_load(2, 2, 3'b101, 10); // LHU

        dut.reg_File_Pipelined.registers[2] = 0;

        run_program(20);

        check_reg(1, 32'hFF80_7F01, "LW");
        check_reg(3, 32'h0000_0001, "LB byte0");
        check_reg(4, 32'h0000_0001, "LBU byte0");
        check_reg(5, 32'h0000_007F, "LB byte1");
        check_reg(6, 32'hFFFF_FF80, "LB byte2");
        check_reg(7, 32'h0000_0080, "LBU byte2");
        check_reg(8, 32'h0000_7F01, "LH half0");
        check_reg(9, 32'hFFFF_FF80, "LH half1");
        check_reg(10, 32'h0000_FF80, "LHU half1");

        // ====================================================================
        // 10. Branches: taken and not taken + flush
        // ====================================================================
        $display("\n=== TEST 10: BRANCHES / FLUSH ===");
        begin_test;

        // BEQ taken: skip instruction at index 3.
        dut.instruction_Memory.memory[0] = enc_i(1, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i(1, 0, 3'b000, 2);
        dut.instruction_Memory.memory[2] = enc_b(8, 2, 1, 3'b000); // beq x1,x2,+8
        dut.instruction_Memory.memory[3] = enc_i(99, 0, 3'b000, 5); // wrong path
        dut.instruction_Memory.memory[4] = enc_i(7, 0, 3'b000, 6);  // target

        // BNE not taken.
        dut.instruction_Memory.memory[5] = enc_b(8, 2, 1, 3'b001);
        dut.instruction_Memory.memory[6] = enc_i(8, 0, 3'b000, 7);

        run_program(18);

        check_reg(5, 0, "BEQ wrong-path x5");
        check_reg(6, 7, "BEQ target x6");
        check_reg(7, 8, "BNE not-taken x7");

        // ====================================================================
        // 11. Remaining branch types
        // ====================================================================
        $display("\n=== TEST 11: SIGNED / UNSIGNED BRANCHES ===");
        begin_test;

        // x1 = -1, x2 = +1
        dut.instruction_Memory.memory[0] = enc_i(-1, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i(1, 0, 3'b000, 2);

        // BLT x1,x2,+8 => taken, skips x5.
        dut.instruction_Memory.memory[2] = enc_b(8, 2, 1, 3'b100);
        dut.instruction_Memory.memory[3] = enc_i(99, 0, 3'b000, 5);
        dut.instruction_Memory.memory[4] = enc_i(10, 0, 3'b000, 6);

        // BGE x1,x2,+8 => not taken.
        dut.instruction_Memory.memory[5] = enc_b(8, 2, 1, 3'b101);
        dut.instruction_Memory.memory[6] = enc_i(11, 0, 3'b000, 7);

        // BLTU x1,x2,+8 => not taken (-1 is large unsigned).
        dut.instruction_Memory.memory[7] = enc_b(8, 2, 1, 3'b110);
        dut.instruction_Memory.memory[8] = enc_i(12, 0, 3'b000, 8);

        // BGEU x1,x2,+8 => taken, skips x9.
        dut.instruction_Memory.memory[9]  = enc_b(8, 2, 1, 3'b111);
        dut.instruction_Memory.memory[10] = enc_i(99, 0, 3'b000, 9);
        dut.instruction_Memory.memory[11] = enc_i(13, 0, 3'b000, 10);

        run_program(24);

        check_reg(5, 0, "BLT wrong-path");
        check_reg(6, 10, "BLT target");
        check_reg(7, 11, "BGE not-taken");
        check_reg(8, 12, "BLTU not-taken");
        check_reg(9, 0, "BGEU wrong-path");
        check_reg(10, 13, "BGEU target");

        // ====================================================================
        // 12. JAL: link + target + flush
        // ====================================================================
        $display("\n=== TEST 12: JAL ===");
        begin_test;

        // JAL at PC=0 jumps to PC=12.
        dut.instruction_Memory.memory[0] = enc_j(12, 5); // jal x5,+12
        dut.instruction_Memory.memory[1] = enc_i(99, 0, 3'b000, 6); // flushed
        dut.instruction_Memory.memory[2] = enc_i(98, 0, 3'b000, 7); // flushed
        dut.instruction_Memory.memory[3] = enc_i(42, 0, 3'b000, 8); // target

        run_program(12);

        check_reg(5, 4, "JAL link x5");
        check_reg(6, 0, "JAL flushed x6");
        check_reg(7, 0, "JAL flushed x7");
        check_reg(8, 42, "JAL target x8");

        // ====================================================================
        // 13. JALR: link + target + flush
        // ====================================================================
        $display("\n=== TEST 13: JALR ===");
        begin_test;

        // x1 = 16, JALR at PC=4 jumps to byte address 16 (instruction 4).
        dut.instruction_Memory.memory[0] = enc_i(16, 0, 3'b000, 1);
        dut.instruction_Memory.memory[1] = enc_i_jalr(0, 1, 5); // jalr x5,0(x1)
        dut.instruction_Memory.memory[2] = enc_i(99, 0, 3'b000, 6); // flushed
        dut.instruction_Memory.memory[3] = enc_i(98, 0, 3'b000, 7); // flushed
        dut.instruction_Memory.memory[4] = enc_i(42, 0, 3'b000, 8); // target

        run_program(14);

        check_reg(5, 8, "JALR link x5");
        check_reg(6, 0, "JALR flushed x6");
        check_reg(7, 0, "JALR flushed x7");
        check_reg(8, 42, "JALR target x8");

        // ====================================================================
        // 14. LUI / AUIPC
        // ====================================================================
        $display("\n=== TEST 14: LUI / AUIPC ===");
        begin_test;

        dut.instruction_Memory.memory[0] = enc_u(20'h12345, 1, 7'b0110111); // LUI
        dut.instruction_Memory.memory[1] = enc_u(20'h00001, 2, 7'b0010111); // AUIPC

        run_program(10);

        check_reg(1, 32'h12345_000, "LUI x1");
        check_reg(2, 32'h00001_004, "AUIPC x2");

        // ====================================================================
        // Final result
        // ====================================================================
        $display("\n========================================");
        $display("PIPELINE REGRESSION COMPLETE");
        $display("PASS count = %0d", pass_count);
        $display("FAIL count = %0d", fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("PIPELINE REGRESSION PASS");
        else
            $display("PIPELINE REGRESSION FAIL");
        

        $finish;
    end
// ============================================================
// VCD
// ============================================================

initial begin
    $dumpfile("sim/cpu_pipelined.vcd");
    $dumpvars(0, CPU_tb);
end

endmodule
