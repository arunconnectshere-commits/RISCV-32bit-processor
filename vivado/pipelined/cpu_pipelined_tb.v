`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.10.2026 16:43:40
// Design Name: 
// Module Name: cpu_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module CPU_TB;

    reg clk;
    reg reset;


    // =========================================================================
    // CPU <-> INSTRUCTION MEMORY
    // =========================================================================

    wire [31:0] imem_instr;
    wire [31:0] imem_pc;


    // =========================================================================
    // CPU <-> DATA MEMORY
    // =========================================================================

    wire [31:0] dmem_wd;
    wire [31:0] dmem_rd;
    wire [31:0] dmem_addr;

    wire        dmem_mr;
    wire        dmem_mw;

    wire [1:0]  dmem_ds;


    // =========================================================================
    // CPU
    // =========================================================================
    reg clk;


    CPU DUT (

        .clk(clk),
        .reset(reset),

        .dmem_wd(dmem_wd),
        .dmem_rd(dmem_rd),
        .dmem_addr(dmem_addr),
        .dmem_mr(dmem_mr),
        .dmem_mw(dmem_mw),
        .dmem_ds(dmem_ds),

        .imem_instr(imem_instr),
        .imem_pc(imem_pc)

    );


    // =========================================================================
    // INSTRUCTION MEMORY
    // =========================================================================

    INSTRUCTION_MEMORY instruction_Memory (

        .pc(imem_pc),
        .instruction(imem_instr)

    );


    // =========================================================================
    // DATA MEMORY
    // =========================================================================

    DATA_MEMORY data_memory (

        .clk(clk),

        .data_mem_address(dmem_addr),
        .write_data(dmem_wd),

        .mem_read(dmem_mr),
        .mem_write(dmem_mw),

        .data_size(dmem_ds),

        .read_data(dmem_rd)

    );


    // =========================================================================
    // CLOCK
    // =========================================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end
    integer i;
    integer DEPTH = 256;

initial begin

    #1;

    instruction_Memory.memory[0] = 32'h00500093; // ADDI x1, x0, 5  -- x1 = 5  (op_a)
    instruction_Memory.memory[1] = 32'h00300113; // ADDI x2, x0, 3  -- x2 = 3  (op_b)
    instruction_Memory.memory[2] = 32'h002081B3; // ADD  x3, x1, x2  -- x3 = 8
    instruction_Memory.memory[3] = 32'h40208233; // SUB  x4, x1, x2  -- x4 = 2
    instruction_Memory.memory[4] = 32'h0020F2B3; // AND  x5, x1, x2  -- x5 = 1
    instruction_Memory.memory[5] = 32'h0020E333; // OR   x6, x1, x2  -- x6 = 7
    instruction_Memory.memory[6] = 32'h0020C3B3; // XOR  x7, x1, x2  -- x7 = 6
    instruction_Memory.memory[7] = 32'h00209433; // SLL  x8, x1, x2  -- x8 = 40
    instruction_Memory.memory[8] = 32'h0020D4B3; // SRL  x9, x1, x2  -- x9 = 0
    instruction_Memory.memory[9] = 32'h00112533; // SLT  x10, x2, x1  -- x10 = 1
    instruction_Memory.memory[10] = 32'h001135B3; // SLTU x11, x2, x1  -- x11 = 1
    instruction_Memory.memory[11] = 32'hFF800613; // ADDI x12, x0, -8  -- x12 = 0xFFFFFFF8 (neg_val)
    instruction_Memory.memory[12] = 32'h402656B3; // SRA  x13, x12, x2  -- x13 = -1
    instruction_Memory.memory[13] = 32'h00261713; // SLLI x14, x12, 2  -- x14 = -32
    instruction_Memory.memory[14] = 32'h00465793; // SRLI x15, x12, 4  -- x15 = 0x0FFFFFFF
    instruction_Memory.memory[15] = 32'h40465813; // SRAI x16, x12, 4  -- x16 = -1
    instruction_Memory.memory[16] = 32'h00A12893; // SLTI  x17, x2, 10  -- x17 = 1
    instruction_Memory.memory[17] = 32'h00A0B913; // SLTIU x18, x1, 10  -- x18 = 1
    instruction_Memory.memory[18] = 32'h0FF0C993; // XORI  x19, x1, 0xFF  -- x19 = 250
    instruction_Memory.memory[19] = 32'h0F00EA13; // ORI   x20, x1, 0xF0  -- x20 = 245
    instruction_Memory.memory[20] = 32'h00F0FA93; // ANDI  x21, x1, 0x0F  -- x21 = 5
    instruction_Memory.memory[21] = 32'h06400B13; // ADDI x22, x0, 100  -- x22 = 100 (base_addr)
    instruction_Memory.memory[22] = 32'hF8000B93; // ADDI x23, x0, -128  -- x23 = 0xFFFFFF80
    instruction_Memory.memory[23] = 32'h017B0023; // SB   x23, 0(x22)  -- mem byte0 = 0x80
    instruction_Memory.memory[24] = 32'h000B0C03; // LB   x24, 0(x22)  -- x24 = 0xFFFFFF80
    instruction_Memory.memory[25] = 32'h000B4C83; // LBU  x25, 0(x22)  -- x25 = 0x00000080
    instruction_Memory.memory[26] = 32'hED400B93; // ADDI x23, x0, -300  -- x23 = 0xFFFFFED4
    instruction_Memory.memory[27] = 32'h017B1223; // SH   x23, 4(x22)  -- mem half = 0xFED4
    instruction_Memory.memory[28] = 32'h004B1D03; // LH   x26, 4(x22)  -- x26 = 0xFFFFFED4
    instruction_Memory.memory[29] = 32'h004B5D83; // LHU  x27, 4(x22)  -- x27 = 0x0000FED4
    instruction_Memory.memory[30] = 32'h30900B93; // ADDI x23, x0, 777  -- x23 = 777
    instruction_Memory.memory[31] = 32'h017B2423; // SW   x23, 8(x22)  -- mem word = 777
    instruction_Memory.memory[32] = 32'h008B2E03; // LW   x28, 8(x22)  -- x28 = 777
    instruction_Memory.memory[33] = 32'h00000F13; // ADDI x30, x0, 0  -- x30 = 0 (fail_cnt)
    instruction_Memory.memory[34] = 32'h00000F93; // ADDI x31, x0, 0  -- x31 = 0 (pass_cnt)
    instruction_Memory.memory[35] = 32'h3E700B93; // ADDI x23, x0, 999  -- EDGE: value to store
    instruction_Memory.memory[36] = 32'h017B2A23; // SW   x23, 20(x22)  -- EDGE: store 999 @ addr120
    instruction_Memory.memory[37] = 32'h050B0B93; // ADDI x23, x22, 80  -- EDGE: x23 = 180 (temp base)
    instruction_Memory.memory[38] = 32'hFC4BAB83; // LW x23, -60(x23)  -- EDGE: NEGATIVE offset load, addr=120
    instruction_Memory.memory[39] = 32'h3E7BCB93; // XORI x23,x23,999  -- EDGE: diff
    instruction_Memory.memory[40] = 32'h000B8663; // BEQ x23,x0,+12  -- A1 negative-offset LW : assert zero
    instruction_Memory.memory[41] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A1 negative-offset LW
    instruction_Memory.memory[42] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[43] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A1 negative-offset LW
    instruction_Memory.memory[44] = 32'h00200BB3; // ADD  x23, x0, x2  -- EDGE: rs1=x0 -> 3
    instruction_Memory.memory[45] = 32'h003BCB93; // XORI x23,x23,3  -- EDGE: diff
    instruction_Memory.memory[46] = 32'h000B8663; // BEQ x23,x0,+12  -- A2 rs1=x0 (ADD) : assert zero
    instruction_Memory.memory[47] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A2 rs1=x0 (ADD)
    instruction_Memory.memory[48] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[49] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A2 rs1=x0 (ADD)
    instruction_Memory.memory[50] = 32'h40008BB3; // SUB  x23, x1, x0  -- EDGE: rs2=x0 -> 5
    instruction_Memory.memory[51] = 32'h005BCB93; // XORI x23,x23,5  -- EDGE: diff
    instruction_Memory.memory[52] = 32'h000B8663; // BEQ x23,x0,+12  -- A3 rs2=x0 (SUB) : assert zero
    instruction_Memory.memory[53] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A3 rs2=x0 (SUB)
    instruction_Memory.memory[54] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[55] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A3 rs2=x0 (SUB)
    instruction_Memory.memory[56] = 32'h00009B93; // SLLI x23, x1, 0  -- EDGE: shift0 -> 5
    instruction_Memory.memory[57] = 32'h005BCB93; // XORI x23,x23,5  -- EDGE: diff
    instruction_Memory.memory[58] = 32'h000B8663; // BEQ x23,x0,+12  -- A4 SLLI shamt=0 : assert zero
    instruction_Memory.memory[59] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A4 SLLI shamt=0
    instruction_Memory.memory[60] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[61] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A4 SLLI shamt=0
    instruction_Memory.memory[62] = 32'h01F09B93; // SLLI x23, x1, 31  -- EDGE: 5<<31 = 0x80000000
    instruction_Memory.memory[63] = 32'h80000EB7; // LUI  x29, 0x80000  -- EDGE: expected
    instruction_Memory.memory[64] = 32'h01DBCBB3; // XOR x23,x23,x29  -- EDGE: diff
    instruction_Memory.memory[65] = 32'h000B8663; // BEQ x23,x0,+12  -- A5 SLLI shamt=31 : assert zero
    instruction_Memory.memory[66] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A5 SLLI shamt=31
    instruction_Memory.memory[67] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[68] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A5 SLLI shamt=31
    instruction_Memory.memory[69] = 32'h0010ABB3; // SLT  x23, x1, x1  -- EDGE: 5<5 -> 0
    instruction_Memory.memory[70] = 32'h000B8663; // BEQ x23,x0,+12  -- A6 SLT equal operands : assert zero
    instruction_Memory.memory[71] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A6 SLT equal operands
    instruction_Memory.memory[72] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[73] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A6 SLT equal operands
    instruction_Memory.memory[74] = 32'h0010BBB3; // SLTU x23, x1, x1  -- EDGE: 5<5u -> 0
    instruction_Memory.memory[75] = 32'h000B8663; // BEQ x23,x0,+12  -- A7 SLTU equal operands : assert zero
    instruction_Memory.memory[76] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A7 SLTU equal operands
    instruction_Memory.memory[77] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[78] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A7 SLTU equal operands
    instruction_Memory.memory[79] = 32'h80000BB7; // LUI  x23, 0x80000  -- EDGE: 0x80000000
    instruction_Memory.memory[80] = 32'hFFFB8B93; // ADDI x23, x23, -1  -- EDGE: 0x7FFFFFFF
    instruction_Memory.memory[81] = 32'h001B8B93; // ADDI x23, x23, 1  -- EDGE: wraps -> 0x80000000
    instruction_Memory.memory[82] = 32'h80000EB7; // LUI  x29, 0x80000  -- EDGE: expected
    instruction_Memory.memory[83] = 32'h01DBCBB3; // XOR x23,x23,x29  -- EDGE: diff
    instruction_Memory.memory[84] = 32'h000B8663; // BEQ x23,x0,+12  -- A8 signed ADD overflow wraparound : assert zero
    instruction_Memory.memory[85] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - A8 signed ADD overflow wraparound
    instruction_Memory.memory[86] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[87] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - A8 signed ADD overflow wraparound
    instruction_Memory.memory[88] = 32'hF9D00B93; // ADDI x23, x0, -99  -- B1: byte value = 0xFFFFFF9D
    instruction_Memory.memory[89] = 32'h0D7B04A3; // SB   x23, 201(x22)  -- B1: store @ addr301 (byte_pos=1)
    instruction_Memory.memory[90] = 32'h0C9B0B83; // LB x23, 201(x22)  -- B1: load back (sign ext)
    instruction_Memory.memory[91] = 32'hF9DBCB93; // XORI x23,x23,-99  -- B1: diff
    instruction_Memory.memory[92] = 32'h000B8663; // BEQ x23,x0,+12  -- B1 SB/LB byte_position=1 : assert zero
    instruction_Memory.memory[93] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - B1 SB/LB byte_position=1
    instruction_Memory.memory[94] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[95] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - B1 SB/LB byte_position=1
    instruction_Memory.memory[96] = 32'h04200B93; // ADDI x23, x0, 66  -- B2: byte value = 0x42
    instruction_Memory.memory[97] = 32'h0D7B0523; // SB   x23, 202(x22)  -- B2: store @ addr302 (byte_pos=2)
    instruction_Memory.memory[98] = 32'h0CAB4B83; // LBU x23, 202(x22)  -- B2: load back (zero ext)
    instruction_Memory.memory[99] = 32'h042BCB93; // XORI x23,x23,66  -- B2: diff
    instruction_Memory.memory[100] = 32'h000B8663; // BEQ x23,x0,+12  -- B2 SB/LBU byte_position=2 : assert zero
    instruction_Memory.memory[101] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - B2 SB/LBU byte_position=2
    instruction_Memory.memory[102] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[103] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - B2 SB/LBU byte_position=2
    instruction_Memory.memory[104] = 32'hFFB00B93; // ADDI x23, x0, -5  -- B3: byte value = 0xFFFFFFFB
    instruction_Memory.memory[105] = 32'h0D7B05A3; // SB   x23, 203(x22)  -- B3: store @ addr303 (byte_pos=3)
    instruction_Memory.memory[106] = 32'h0CBB0B83; // LB x23, 203(x22)  -- B3: load back (sign ext)
    instruction_Memory.memory[107] = 32'hFFBBCB93; // XORI x23,x23,-5  -- B3: diff
    instruction_Memory.memory[108] = 32'h000B8663; // BEQ x23,x0,+12  -- B3 SB/LB byte_position=3 : assert zero
    instruction_Memory.memory[109] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - B3 SB/LB byte_position=3
    instruction_Memory.memory[110] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[111] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - B3 SB/LB byte_position=3
    instruction_Memory.memory[112] = 32'hC1800B93; // ADDI x23, x0, -1000  -- B4: half value = 0xFFFFFC18
    instruction_Memory.memory[113] = 32'h0D7B1723; // SH   x23, 206(x22)  -- B4: store @ addr306 (half upper)
    instruction_Memory.memory[114] = 32'h0CEB1B83; // LH x23, 206(x22)  -- B4: load back (sign ext)
    instruction_Memory.memory[115] = 32'hC18BCB93; // XORI x23,x23,-1000  -- B4: diff
    instruction_Memory.memory[116] = 32'h000B8663; // BEQ x23,x0,+12  -- B4 SH/LH half_position=upper : assert zero
    instruction_Memory.memory[117] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - B4 SH/LH half_position=upper
    instruction_Memory.memory[118] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[119] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - B4 SH/LH half_position=upper
    instruction_Memory.memory[120] = 32'h02208BB3; // MUL x23, x1, x2  -- C1: 5*3 = 15
    instruction_Memory.memory[121] = 32'h00FBCB93; // XORI x23,x23,15  -- C1: diff
    instruction_Memory.memory[122] = 32'h000B8663; // BEQ x23,x0,+12  -- C1 MUL 5*3=15 : assert zero
    instruction_Memory.memory[123] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - C1 MUL 5*3=15
    instruction_Memory.memory[124] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[125] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - C1 MUL 5*3=15
    instruction_Memory.memory[126] = 32'h02260BB3; // MUL x23, x12, x2  -- C2: -8*3 = -24
    instruction_Memory.memory[127] = 32'hFE8BCB93; // XORI x23,x23,-24  -- C2: diff
    instruction_Memory.memory[128] = 32'h000B8663; // BEQ x23,x0,+12  -- C2 MUL -8*3=-24 : assert zero
    instruction_Memory.memory[129] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - C2 MUL -8*3=-24
    instruction_Memory.memory[130] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[131] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - C2 MUL -8*3=-24
    instruction_Memory.memory[132] = 32'h00500B93; // ADDI x23,x0,5  -- LOOP SETUP: counter = 5
    instruction_Memory.memory[133] = 32'h00000E93; // ADDI x29,x0,0  -- LOOP SETUP: iter_count = 0
    instruction_Memory.memory[134] = 32'h001E8E93; // ADDI x29,x29,1  -- LOOP: iter_count++
    instruction_Memory.memory[135] = 32'hFFFB8B93; // ADDI x23,x23,-1  -- LOOP: counter--
    instruction_Memory.memory[136] = 32'hFE0B9CE3; // BNE x23,x0,-8  -- LOOP: branch back if counter!=0
    instruction_Memory.memory[137] = 32'h000B8663; // BEQ x23,x0,+12  -- D1 loop exit counter == 0 : assert zero
    instruction_Memory.memory[138] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - D1 loop exit counter == 0
    instruction_Memory.memory[139] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[140] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - D1 loop exit counter == 0
    instruction_Memory.memory[141] = 32'h005ECE93; // XORI x29,x29,5  -- LOOP: diff (expect exactly 5 iterations)
    instruction_Memory.memory[142] = 32'h000E8663; // BEQ x29,x0,+12  -- D2 loop ran exactly 5 iterations : assert zero
    instruction_Memory.memory[143] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - D2 loop ran exactly 5 iterations
    instruction_Memory.memory[144] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[145] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - D2 loop ran exactly 5 iterations
    instruction_Memory.memory[146] = 32'h25400B93; // ADDI x23,x0,596  -- E1 JALR rd=x29 : target addr (even)
    instruction_Memory.memory[147] = 32'h001B8EE7; // JALR x29,1(x23)  -- E1 JALR rd=x29 : sum ODD -> must mask bit0
    instruction_Memory.memory[148] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - E1 JALR rd=x29
    instruction_Memory.memory[149] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - E1 JALR rd=x29
    instruction_Memory.memory[150] = 32'h250ECE93; // XORI x29,x29,592  -- E1 link check: diff
    instruction_Memory.memory[151] = 32'h000E8663; // BEQ x29,x0,+12  -- E1 JALR link value (rd=pc+4) : assert zero
    instruction_Memory.memory[152] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - E1 JALR link value (rd=pc+4)
    instruction_Memory.memory[153] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[154] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - E1 JALR link value (rd=pc+4)
    instruction_Memory.memory[155] = 32'h27800B93; // ADDI x23,x0,632  -- E2 JALR rd=x0 (ret-style) : target addr (even)
    instruction_Memory.memory[156] = 32'h001B8067; // JALR x0,1(x23)  -- E2 JALR rd=x0 (ret-style) : sum ODD -> must mask bit0
    instruction_Memory.memory[157] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - E2 JALR rd=x0 (ret-style)
    instruction_Memory.memory[158] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - E2 JALR rd=x0 (ret-style)
    instruction_Memory.memory[159] = 32'h00800EEF; // JAL x29,+8  -- F1 JAL rd=x29 : forward jump
    instruction_Memory.memory[160] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - F1 JAL rd=x29
    instruction_Memory.memory[161] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - F1 JAL rd=x29
    instruction_Memory.memory[162] = 32'h280ECE93; // XORI x29,x29,640  -- F1 link check: diff
    instruction_Memory.memory[163] = 32'h000E8663; // BEQ x29,x0,+12  -- F1 JAL link value (rd=pc+4) : assert zero
    instruction_Memory.memory[164] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - F1 JAL link value (rd=pc+4)
    instruction_Memory.memory[165] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[166] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - F1 JAL link value (rd=pc+4)
    instruction_Memory.memory[167] = 32'h0080006F; // JAL x0,+8  -- F2 JAL rd=x0 (unconditional jump idiom) : forward jump
    instruction_Memory.memory[168] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL - F2 JAL rd=x0 (unconditional jump idiom)
    instruction_Memory.memory[169] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS - F2 JAL rd=x0 (unconditional jump idiom)
    instruction_Memory.memory[170] = 32'h12345BB7; // LUI x23, 0x12345  -- x23 = 0x12345000 (REAL TEST)
    instruction_Memory.memory[171] = 32'h00001E97; // AUIPC x29, 0x00001  -- x29 = pc+0x1000 (REAL TEST)
    instruction_Memory.memory[172] = 32'hABCDE037; // LUI x0, 0xABCDE  -- x0-write attempt
    instruction_Memory.memory[173] = 32'h00001017; // AUIPC x0, 0x00001  -- x0-write attempt
    instruction_Memory.memory[174] = 32'h00108663; // BEQ  x1,x1, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[175] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[176] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[177] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[178] = 32'h00209663; // BNE  x1,x2, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[179] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[180] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[181] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[182] = 32'h00264663; // BLT  x12,x2, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[183] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[184] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[185] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[186] = 32'h0020D663; // BGE  x1,x2, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[187] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[188] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[189] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[190] = 32'h00116663; // BLTU x2,x1, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[191] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[192] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[193] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[194] = 32'h0020F663; // BGEU x1,x2, +12  -- taken -> skip FAIL, land on PASS
    instruction_Memory.memory[195] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (skipped if branch works)
    instruction_Memory.memory[196] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of PASS
    instruction_Memory.memory[197] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly taken)
    instruction_Memory.memory[198] = 32'h00208663; // BEQ  x1,x2, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[199] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[200] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[201] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[202] = 32'h00109663; // BNE  x1,x1, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[203] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[204] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[205] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[206] = 32'h00C14663; // BLT  x2,x12, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[207] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[208] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[209] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[210] = 32'h00265663; // BGE  x12,x2, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[211] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[212] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[213] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[214] = 32'h0020E663; // BLTU x1,x2, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[215] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[216] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[217] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[218] = 32'h00117663; // BGEU x2,x1, +12  -- not taken -> fall through to PASS
    instruction_Memory.memory[219] = 32'h001F8F93; // ADDI x31,x31,1  -- PASS (executed if branch correctly NOT taken)
    instruction_Memory.memory[220] = 32'h00000463; // BEQ x0,x0,+8  -- unconditional skip of FAIL
    instruction_Memory.memory[221] = 32'h001F0F13; // ADDI x30,x30,1  -- FAIL (only hit if branch incorrectly taken)
    instruction_Memory.memory[222] = 32'h07B00013; // ADDI x0,x0,123  -- x0 must stay 0
    instruction_Memory.memory[223] = 32'h00000013; // NOP
    instruction_Memory.memory[224] = 32'h00000013; // NOP

end


    // =========================================================================
    // RESET
    // =========================================================================

    initial begin

        reset = 1'b1;

        #20;

        reset = 1'b0;

    end

endmodule