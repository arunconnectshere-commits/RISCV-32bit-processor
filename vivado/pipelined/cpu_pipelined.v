module CPU(
    input  wire        clk,
    input  wire        reset,

    // =========================================================================
    // DATA MEMORY INTERFACE
    // =========================================================================
    output wire [31:0] dmem_wd,
    input  wire [31:0] dmem_rd,
    output wire [31:0] dmem_addr,
    output wire        dmem_mr,
    output wire        dmem_mw,
    output wire [1:0]  dmem_ds,

    // =========================================================================
    // INSTRUCTION MEMORY INTERFACE
    // =========================================================================
    input  wire [31:0] imem_instr,
    output wire [31:0] imem_pc
);


// =============================================================================
// 1. PROGRAM COUNTER / IF STAGE
// =============================================================================

wire [31:0] pc;
wire [31:0] next_pc;
wire [31:0] pc_plus_4;

wire [31:0] instruction;

wire [31:0] branch_target;
wire [31:0] jalr_target;
wire [31:0] jal_target;


// =============================================================================
// 2. IF/ID PIPELINE REGISTER
// =============================================================================

wire [31:0] if_id_pc;
wire [31:0] if_id_instruction;

wire [4:0]  if_id_rs1;
wire [4:0]  if_id_rs2;
wire [4:0]  if_id_rd;

wire [2:0]  if_id_funct3;
wire [31:0] if_id_pc_plus_4;


// =============================================================================
// 3. ID STAGE / CONTROL UNIT
// =============================================================================

wire        alu_src;
wire [3:0]  alu_control;

wire        regWrite;
wire        branch;

wire        mem_write;
wire        mem_read;

wire [1:0]  data_size;
wire [1:0]  write_back_select;

wire        auipc;
wire        jalr;
wire        jal;


// =============================================================================
// 4. REGISTER FILE / IMMEDIATE GENERATOR
// =============================================================================

wire [31:0] rs1_data;
wire [31:0] rs2_data;

wire [31:0] immediate;


// =============================================================================
// 5. HAZARD DETECTION
// =============================================================================

wire stall;


// =============================================================================
// 6. ID/EX PIPELINE REGISTER
// =============================================================================

wire [31:0] id_ex_pc;

wire [31:0] id_ex_rs1_data;
wire [31:0] id_ex_rs2_data;
wire [31:0] id_ex_immediate;

wire [4:0]  id_ex_rs1;
wire [4:0]  id_ex_rs2;
wire [4:0]  id_ex_rd;

wire        id_ex_regWrite;
wire        id_ex_branch;

wire [3:0]  id_ex_alu_control;
wire        id_ex_alu_src;

wire        id_ex_mem_write;
wire        id_ex_mem_read;

wire [1:0]  id_ex_data_size;
wire [1:0]  id_ex_write_back_select;

wire        id_ex_auipc;
wire        id_ex_jalr;
wire        id_ex_jal;

wire [2:0]  id_ex_funct3;
wire [31:0] id_ex_pc_plus_4;


// =============================================================================
// 7. FORWARDING UNIT
// =============================================================================

wire [1:0]  forward_a;
wire [1:0]  forward_b;

wire [31:0] forwarded_rs2;


// =============================================================================
// 8. EX STAGE / ALU
// =============================================================================

wire [31:0] alu_a;
wire [31:0] alu_b;
wire [31:0] alu_result;

wire        zero;
wire        less;
wire        less_unsigned;


// =============================================================================
// 9. EX STAGE / BRANCH COMPARATOR
// =============================================================================

// Branch comparator operands
wire [31:0] cmp_a;
wire [31:0] cmp_b;

// Comparison intermediate signals
wire [31:0] cmp_sub_result;

wire        eq;
wire        signs_differ;
wire        slt;
wire        ult;

// Final selected comparison result
reg         cmp_out;

// Final branch condition
wire        branch_condition;


// =============================================================================
// 10. BRANCH / CONTROL HAZARD
// =============================================================================

wire pcSrc;
wire control_hazard;


// =============================================================================
// 11. EX/MEM PIPELINE REGISTER
// =============================================================================

wire [31:0] ex_mem_alu_result;
wire [31:0] ex_mem_rs2_data;

wire [4:0]  ex_mem_rd;

wire        ex_mem_mem_write;
wire        ex_mem_mem_read;

wire [1:0]  ex_mem_data_size;

wire        ex_mem_regWrite;
wire [1:0]  ex_mem_write_back_select;

wire [2:0]  ex_mem_funct3;
wire [31:0] ex_mem_pc_plus_4;


// =============================================================================
// 12. DATA MEMORY / LOAD DATA
// =============================================================================

wire [31:0] read_data;
wire [31:0] load_data;


// =============================================================================
// 13. MEM/WB PIPELINE REGISTER
// =============================================================================

wire [31:0] mem_wb_mem_data;
wire [31:0] mem_wb_alu_result;

wire [4:0]  mem_wb_rd;

wire        mem_wb_regWrite;
wire [1:0]  mem_wb_write_back_select;

wire [31:0] mem_wb_pc_plus_4;


// =============================================================================
// 14. WRITE-BACK
// =============================================================================

reg [31:0] write_back_data;


// =============================================================================
// 15. IF STAGE / INSTRUCTION CONNECTIONS
// =============================================================================

assign imem_pc = pc;
assign instruction = imem_instr;

assign pc_plus_4 = pc + 32'd4;


// =============================================================================
// 16. IF/ID DECODE CONNECTIONS
// =============================================================================

assign if_id_rs1 = if_id_instruction[19:15];
assign if_id_rs2 = if_id_instruction[24:20];
assign if_id_rd  = if_id_instruction[11:7];

assign if_id_funct3   = if_id_instruction[14:12];
assign if_id_pc_plus_4 = if_id_pc + 32'd4;


// =============================================================================
// 17. BRANCH TARGET GENERATION
// =============================================================================

assign branch_target = id_ex_pc + id_ex_immediate;

assign jalr_target = alu_result & 32'hFFFFFFFE;

assign jal_target = alu_result;


// =============================================================================
// 18. BRANCH COMPARATOR
// =============================================================================
//
// The comparator operates independently of the main ALU.
//
// A = forwarded rs1 operand
// B = forwarded rs2 operand
//
// funct3 determines:
//      000 -> BEQ
//      001 -> BNE
//      100 -> BLT
//      101 -> BGE
//      110 -> BLTU
//      111 -> BGEU
//
// =============================================================================

// Use the same operands that are available to the ALU.
assign cmp_a = alu_a;
assign cmp_b = forwarded_rs2;


// -----------------------------------------------------------------------------
// Equality comparison
// -----------------------------------------------------------------------------

assign eq = ~|(cmp_a ^ cmp_b);


// -----------------------------------------------------------------------------
// Subtraction used for magnitude comparison
// -----------------------------------------------------------------------------

assign cmp_sub_result = cmp_a - cmp_b;


// -----------------------------------------------------------------------------
// Signed comparison
//
// If signs differ:
//     A negative -> A < B
//     A positive -> A >= B
//
// If signs are equal:
//     sign of A-B determines the result.
// -----------------------------------------------------------------------------

assign signs_differ = cmp_a[31] ^ cmp_b[31];

assign slt = signs_differ ?
             cmp_a[31] :
             cmp_sub_result[31];


// -----------------------------------------------------------------------------
// Unsigned comparison
//
// When the sign bits differ, the unsigned number with MSB = 0
// is smaller.
//
// Otherwise, subtraction determines the result.
// -----------------------------------------------------------------------------

assign ult = signs_differ ?
             cmp_b[31] :
             cmp_sub_result[31];


// -----------------------------------------------------------------------------
// Select comparison type
//
// funct3[2:1]:
//
//     00 -> equality      (BEQ/BNE)
//     10 -> signed       (BLT/BGE)
//     11 -> unsigned     (BLTU/BGEU)
//
// funct3[0] is used below to invert the result for BNE/BGE/BGEU.
// -----------------------------------------------------------------------------

wire cmp_out = (~id_ex_funct3[2] & ~id_ex_funct3[1] & eq)  |
               ( id_ex_funct3[2] & ~id_ex_funct3[1] & slt) |
               ( id_ex_funct3[2] &  id_ex_funct3[1] & ult);


// -----------------------------------------------------------------------------
// Final branch condition
//
// BEQ  -> comparison result
// BNE  -> inverted comparison result
// BLT  -> comparison result
// BGE  -> inverted comparison result
// BLTU -> comparison result
// BGEU -> inverted comparison result
// -----------------------------------------------------------------------------

assign branch_condition = cmp_out ^ id_ex_funct3[0];


// -----------------------------------------------------------------------------
// Branch taken decision
// -----------------------------------------------------------------------------

assign pcSrc = id_ex_branch && branch_condition;


// -----------------------------------------------------------------------------
// Control hazard
//
// A taken branch/jump flushes instructions currently in the pipeline.
// -----------------------------------------------------------------------------

assign control_hazard = pcSrc || id_ex_jal || id_ex_jalr;


// =============================================================================
// 19. WRITE-BACK MUX
// =============================================================================

always @(*) begin

    case (mem_wb_write_back_select)

        2'b00: begin
            write_back_data = mem_wb_alu_result;
        end

        2'b01: begin
            write_back_data = mem_wb_mem_data;
        end

        2'b10: begin
            write_back_data = mem_wb_pc_plus_4;
        end

        default: begin
            write_back_data = 32'b0;
        end

    endcase

end


// =============================================================================
// 20. IF/ID PIPELINE REGISTER
// =============================================================================

IF_ID if_Id_Reg (

    .clk(clk),
    .reset(reset),
    .flush(control_hazard),
    .stall(stall),

    .pc(pc),
    .instruction(instruction),

    .if_id_pc(if_id_pc),
    .if_id_instruction(if_id_instruction)

);


// =============================================================================
// 21. ID/EX PIPELINE REGISTER
// =============================================================================

ID_EX id_Ex_Reg (

    .clk(clk),
    .reset(reset),
    .flush(control_hazard),
    .stall(stall),

    // -------------------------------------------------------------------------
    // ID stage data
    // -------------------------------------------------------------------------

    .pc(if_id_pc),

    .rs1_data(rs1_data),
    .rs2_data(rs2_data),

    .immediate(immediate),

    .rs1(if_id_rs1),
    .rs2(if_id_rs2),
    .rd(if_id_rd),

    // -------------------------------------------------------------------------
    // Control signals
    // -------------------------------------------------------------------------

    .regWrite(regWrite),
    .branch(branch),

    .alu_control(alu_control),
    .alu_src(alu_src),

    .mem_write(mem_write),
    .mem_read(mem_read),

    .data_size(data_size),

    .write_back_select(write_back_select),

    .auipc(auipc),
    .jalr(jalr),
    .jal(jal),

    // -------------------------------------------------------------------------
    // Additional ID information
    // -------------------------------------------------------------------------

    .if_id_funct3(if_id_funct3),
    .if_id_pc_plus_4(if_id_pc_plus_4),

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    .id_ex_pc(id_ex_pc),

    .id_ex_rs1_data(id_ex_rs1_data),
    .id_ex_rs2_data(id_ex_rs2_data),

    .id_ex_immediate(id_ex_immediate),

    .id_ex_rs1(id_ex_rs1),
    .id_ex_rs2(id_ex_rs2),
    .id_ex_rd(id_ex_rd),

    .id_ex_regWrite(id_ex_regWrite),
    .id_ex_branch(id_ex_branch),

    .id_ex_alu_control(id_ex_alu_control),
    .id_ex_alu_src(id_ex_alu_src),

    .id_ex_mem_write(id_ex_mem_write),
    .id_ex_mem_read(id_ex_mem_read),

    .id_ex_data_size(id_ex_data_size),

    .id_ex_write_back_select(id_ex_write_back_select),

    .id_ex_auipc(id_ex_auipc),
    .id_ex_jalr(id_ex_jalr),
    .id_ex_jal(id_ex_jal),

    .id_ex_funct3(id_ex_funct3),
    .id_ex_pc_plus_4(id_ex_pc_plus_4)

);


// =============================================================================
// 22. FORWARDING UNIT
// =============================================================================

FORWARDING_UNIT forwarding_Unit (

    .id_ex_rs1(id_ex_rs1),
    .id_ex_rs2(id_ex_rs2),

    .ex_mem_rd(ex_mem_rd),
    .ex_mem_regWrite(ex_mem_regWrite),

    .mem_wb_rd(mem_wb_rd),
    .mem_wb_regWrite(mem_wb_regWrite),

    .ex_mem_mem_read(ex_mem_mem_read),

    .forward_a(forward_a),
    .forward_b(forward_b)

);


// =============================================================================
// 23. HAZARD UNIT
// =============================================================================

HAZARD_UNIT hazard_Unit (

    .id_ex_mem_read(id_ex_mem_read),
    .id_ex_rd(id_ex_rd),

    .if_id_rs1(if_id_rs1),
    .if_id_rs2(if_id_rs2),

    .stall(stall)

);


// =============================================================================
// 24. EX STAGE / ALU SOURCE MUX
// =============================================================================

ALU_SRC_MUX_PIPELINED alu_Src_Mux_Pipelined (

    .rs1_data(id_ex_rs1_data),
    .rs2_data(id_ex_rs2_data),

    .immediate(id_ex_immediate),

    .alu_src_b(id_ex_alu_src),

    .auipc(id_ex_auipc),
    .jal(id_ex_jal),

    .pc(id_ex_pc),

    .forward_a(forward_a),
    .forward_b(forward_b),

    .ex_mem_result(ex_mem_alu_result),
    .mem_wb_result(write_back_data),

    .alu_a(alu_a),
    .alu_b(alu_b),

    .forwarded_rs2(forwarded_rs2)

);


// =============================================================================
// 25. ALU
// =============================================================================

ALU alu (

    .A(alu_a),
    .B(alu_b),

    .alu_control(id_ex_alu_control),

    .result(alu_result),

    .zero(zero),
    .less(less),
    .less_unsigned(less_unsigned)

);


// =============================================================================
// 26. EX/MEM PIPELINE REGISTER
// =============================================================================

EX_MEM ex_Mem (

    .clk(clk),
    .reset(reset),

    // -------------------------------------------------------------------------
    // EX stage data
    // -------------------------------------------------------------------------

    .alu_result(alu_result),
    .rs2_data(forwarded_rs2),

    .rd(id_ex_rd),

    .id_ex_funct3(id_ex_funct3),
    .id_ex_pc_plus_4(id_ex_pc_plus_4),

    // -------------------------------------------------------------------------
    // Memory controls
    // -------------------------------------------------------------------------

    .mem_write(id_ex_mem_write),
    .mem_read(id_ex_mem_read),
    .data_size(id_ex_data_size),

    // -------------------------------------------------------------------------
    // Write-back controls
    // -------------------------------------------------------------------------

    .regWrite(id_ex_regWrite),
    .write_back_select(id_ex_write_back_select),

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    .ex_mem_alu_result(ex_mem_alu_result),
    .ex_mem_rs2_data(ex_mem_rs2_data),

    .ex_mem_rd(ex_mem_rd),

    .ex_mem_mem_write(ex_mem_mem_write),
    .ex_mem_mem_read(ex_mem_mem_read),

    .ex_mem_data_size(ex_mem_data_size),

    .ex_mem_regWrite(ex_mem_regWrite),
    .ex_mem_write_back_select(ex_mem_write_back_select),

    .ex_mem_funct3(ex_mem_funct3),
    .ex_mem_pc_plus_4(ex_mem_pc_plus_4)

);


// =============================================================================
// 27. MEM/WB PIPELINE REGISTER
// =============================================================================

MEM_WB mem_Wb (

    .clk(clk),
    .reset(reset),

    // -------------------------------------------------------------------------
    // MEM stage data
    // -------------------------------------------------------------------------

    .mem_data(load_data),
    .alu_result(ex_mem_alu_result),

    .rd(ex_mem_rd),

    .ex_mem_pc_plus_4(ex_mem_pc_plus_4),

    // -------------------------------------------------------------------------
    // Write-back controls
    // -------------------------------------------------------------------------

    .regWrite(ex_mem_regWrite),
    .write_back_select(ex_mem_write_back_select),

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    .mem_wb_mem_data(mem_wb_mem_data),
    .mem_wb_alu_result(mem_wb_alu_result),

    .mem_wb_rd(mem_wb_rd),

    .mem_wb_regWrite(mem_wb_regWrite),
    .mem_wb_write_back_select(mem_wb_write_back_select),

    .mem_wb_pc_plus_4(mem_wb_pc_plus_4)

);


// =============================================================================
// 28. PC MUX
// =============================================================================

PC_MUX_PIPELINED program_Counter_Mux_Piplined (

    .pc(pc),

    .pc_plus_4(pc_plus_4),
    .branch_target(branch_target),

    .next_pc(next_pc),

    .pcSrc(pcSrc),

    .jalr(id_ex_jalr),
    .jalr_target(jalr_target),

    .jal(id_ex_jal),
    .jal_target(jal_target),

    .stall(stall)

);


// =============================================================================
// 29. PROGRAM COUNTER
// =============================================================================

PROGRAM_COUNTER program_Counter (

    .clk(clk),
    .reset(reset),

    .pc(pc),
    .next_pc(next_pc)

);


// =============================================================================
// 30. CONTROL UNIT
// =============================================================================

CONTROL_UNIT1 control_Unit (

    .instruction(if_id_instruction),

    .alu_src(alu_src),
    .alu_control(alu_control),

    .regWrite(regWrite),
    .branch(branch),

    .mem_write(mem_write),
    .mem_read(mem_read),

    .write_back_select(write_back_select),
    .data_size(data_size),

    .auipc(auipc),
    .jalr(jalr),
    .jal(jal)

);


// =============================================================================
// 31. REGISTER FILE
// =============================================================================

REG_FILE_PIPELINED reg_File_Pipelined (

    .clk(clk),

    .read_addr1(if_id_rs1),
    .read_addr2(if_id_rs2),

    .write_addr(mem_wb_rd),

    .write_enable(mem_wb_regWrite),
    .write_data(write_back_data),

    .read_data1(rs1_data),
    .read_data2(rs2_data)

);


// =============================================================================
// 32. IMMEDIATE GENERATOR
// =============================================================================

IMMEDIATE_GENERATOR immediate_Generator (

    .instruction(if_id_instruction),
    .immediate(immediate)

);


// =============================================================================
// 33. DATA MEMORY CONNECTIONS
// =============================================================================

assign dmem_wd   = ex_mem_rs2_data;
assign dmem_addr = ex_mem_alu_result;

assign dmem_mr = ex_mem_mem_read;
assign dmem_mw = ex_mem_mem_write;

assign dmem_ds = ex_mem_data_size;

assign read_data = dmem_rd;


// =============================================================================
// 34. LOAD DATA UNIT
// =============================================================================

LOAD_DATA_UNIT load_Data_Unit (

    .read_data(read_data),

    .funct3(ex_mem_funct3),

    .data_mem_address(ex_mem_alu_result),

    .load_data(load_data)

);


endmodule