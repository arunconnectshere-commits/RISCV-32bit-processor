module CPU(
    input clk,
    input reset
);
wire control_hazard = pcSrc || id_ex_jal || id_ex_jalr;
// ID stage
wire [31:0] if_id_pc;
wire [31:0] if_id_instruction;

assign if_id_rs1 = if_id_instruction[19:15];
assign if_id_rs2 = if_id_instruction[24:20];
assign if_id_rd  = if_id_instruction[11:7];

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
wire [2:0] if_id_funct3;
wire [31:0] if_id_pc_plus_4;

assign if_id_funct3 = if_id_instruction[14:12];
assign if_id_pc_plus_4 = if_id_pc + 32'd4;

// EX stage

wire [4:0] id_ex_rs1;
wire [4:0] id_ex_rs2;
wire [4:0] id_ex_rd;

wire [31:0] id_ex_rs1_data;
wire [31:0] id_ex_rs2_data;

wire [31:0] id_ex_pc;
wire [31:0] id_ex_immediate;

wire id_ex_regWrite;
wire id_ex_branch;
wire [3:0] id_ex_alu_control;
wire id_ex_alu_src;
wire id_ex_mem_write;
wire id_ex_mem_read;
wire [1:0] id_ex_data_size;
wire [1:0] id_ex_write_back_select;
wire id_ex_auipc;
wire id_ex_jalr;
wire id_ex_jal;
wire [2:0] id_ex_funct3;
wire [31:0] id_ex_pc_plus_4;

wire branch_condition;
wire pcSrc;

assign branch_condition =
       (id_ex_funct3 == 3'b000) ? zero :
       (id_ex_funct3 == 3'b001) ? ~zero :
       (id_ex_funct3 == 3'b100) ? less :
       (id_ex_funct3 == 3'b101) ? ~less :
       (id_ex_funct3 == 3'b110) ? less_unsigned :
       (id_ex_funct3 == 3'b111) ? ~less_unsigned :
       1'b0;

assign pcSrc = id_ex_branch && branch_condition;

ID_EX id_Ex_Reg (
    .clk(clk),
    .reset(reset),
    .flush(control_hazard),
    .stall(stall),

    // from ID
    .pc(if_id_pc),

    // from reg file
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),

    // from immediate generator
    .immediate(immediate),

    // from assignment/ID
    .rs1(if_id_rs1),
    .rs2(if_id_rs2),
    .rd(if_id_rd),

    // from Control unit
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

    // from assignment
    .if_id_funct3(if_id_funct3),
    .if_id_pc_plus_4(if_id_pc_plus_4),

    // outputs
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


// MEMORY stage
wire [31:0] ex_mem_alu_result;
wire [31:0] ex_mem_rs2_data;
wire [4:0] ex_mem_rd;
wire ex_mem_mem_write;
wire ex_mem_mem_read;
wire [1:0] ex_mem_data_size;
wire ex_mem_regWrite;
wire [1:0] ex_mem_write_back_select;
wire [2:0] ex_mem_funct3;
wire [31:0] ex_mem_pc_plus_4;

EX_MEM ex_Mem (
    .clk(clk),
    .reset(reset),

    // Data from EX stage
    .alu_result(alu_result),
    .rs2_data(forwarded_rs2),
    .rd(id_ex_rd),
    .id_ex_funct3(id_ex_funct3),
    .id_ex_pc_plus_4(id_ex_pc_plus_4),
    // Memory controls
    .mem_write(id_ex_mem_write),
    .mem_read(id_ex_mem_read),
    .data_size(id_ex_data_size),

    // Write-back controls
    .regWrite(id_ex_regWrite),
    .write_back_select(id_ex_write_back_select),

    // Registered outputs
    .ex_mem_alu_result(ex_mem_alu_result),
    .ex_mem_rs2_data(ex_mem_rs2_data),
    .ex_mem_rd(ex_mem_rd),

    .ex_mem_mem_write(ex_mem_mem_write),
    .ex_mem_mem_read(ex_mem_mem_read),
    .ex_mem_data_size(ex_mem_data_size),

    .ex_mem_regWrite(ex_mem_regWrite),
    .ex_mem_write_back_select(ex_mem_write_back_select),

    // funct3 forwarding
    .ex_mem_funct3(ex_mem_funct3),
    .ex_mem_pc_plus_4(ex_mem_pc_plus_4)
);

// WRITE BACK stage
wire [31:0] mem_wb_mem_data;
wire [31:0] mem_wb_alu_result;
wire [4:0]  mem_wb_rd;

wire        mem_wb_regWrite;
wire [1:0]  mem_wb_write_back_select;

wire [31:0] mem_wb_pc_plus_4;

MEM_WB mem_Wb(
    .clk(clk),
    .reset(reset),

    // Data from MEM stage
    .mem_data(load_data),
    .alu_result(ex_mem_alu_result),
    .rd(ex_mem_rd),
    .ex_mem_pc_plus_4(ex_mem_pc_plus_4),

    .regWrite(ex_mem_regWrite),
    .write_back_select(ex_mem_write_back_select),

    // Registered outputs
    .mem_wb_mem_data(mem_wb_mem_data),
    .mem_wb_alu_result(mem_wb_alu_result),
    .mem_wb_rd(mem_wb_rd),

    .mem_wb_regWrite(mem_wb_regWrite),
    .mem_wb_write_back_select(mem_wb_write_back_select),
    
    .mem_wb_pc_plus_4(mem_wb_pc_plus_4)
);

wire [1:0] forward_a;
wire [1:0] forward_b;
FORWARDING_UNIT forwarding_Unit(
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

wire stall;

HAZARD_UNIT hazard_Unit(
    .id_ex_mem_read(id_ex_mem_read),
    .id_ex_rd(id_ex_rd),

    .if_id_rs1(if_id_rs1),
    .if_id_rs2(if_id_rs2),

    .stall(stall)
);

// pc MUX
wire [31:0] pc_plus_4;
wire [31:0] branch_target;
wire [31:0] jalr_target;
wire [31:0] jal_target;
assign jalr_target = (alu_result & 32'hFFFFFFFE);
assign jal_target = alu_result;

// pc
wire [31:0] pc;
wire [31:0] next_pc;

// Instructin memory
wire [31:0] instruction;

// Control Unit
wire        alu_src;
wire [3:0]  alu_control;
wire        regWrite;
wire        branch;
wire        less;  
wire        less_unsigned;
wire        auipc;
wire        jalr;
wire        jal;

// alu Source MUX
wire [31:0] alu_b;
wire [31:0] forwarded_rs2;

// alu
wire [31:0] alu_result;
wire zero;
wire [31:0] alu_a;



// Register File
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [4:0] if_id_rs1;
wire [4:0] if_id_rs2;
wire [4:0] if_id_rd;

// Immediate Generator
wire [31:0] immediate;

assign pc_plus_4 = pc + 32'd4;
assign branch_target = id_ex_pc + id_ex_immediate;

// Data Memory
wire mem_read;
wire mem_write;
wire [1:0] data_size;

wire [31:0] read_data;


// Load Data Unit
wire [1:0] write_back_select;
wire [31:0] load_data;
reg [31:0] write_back_data;

always @(*) begin
    case (mem_wb_write_back_select)
        2'b00: write_back_data = mem_wb_alu_result;
        2'b01: write_back_data = mem_wb_mem_data;
        2'b10: write_back_data = mem_wb_pc_plus_4;
        default: write_back_data = 32'b0;
    endcase
end



// Module Instantiations

PC_MUX_PIPELINED program_Counter_Mux_Piplined(
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

PROGRAM_COUNTER program_Counter(
    .clk(clk),
    .reset(reset),
    .pc(pc),
    .next_pc(next_pc)
);

INSTRUCTION_MEMORY instruction_Memory(
    .instruction(instruction),
    .pc(pc)
);

CONTROL_UNIT1 control_Unit(
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

REG_FILE_PIPELINED reg_File_Pipelined(
    .clk(clk),
    .read_addr1(if_id_rs1),
    .read_addr2(if_id_rs2),
    .write_addr(mem_wb_rd),

    .write_enable(mem_wb_regWrite),
    .write_data(write_back_data),

    .read_data1(rs1_data),
    .read_data2(rs2_data)
);

IMMEDIATE_GENERATOR immediate_Generator(
    .instruction(if_id_instruction),
    .immediate(immediate)
);

ALU_SRC_MUX_PIPELINED alu_Src_Mux_Pipelined(
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

ALU alu(
    .A(alu_a),
    .B(alu_b),
    .alu_control(id_ex_alu_control),

    .result(alu_result),
    .zero(zero),
    .less(less),
    .less_unsigned(less_unsigned)
);

DATA_MEMORY data_Memory(
    .clk(clk),
    .write_data(ex_mem_rs2_data),
    .data_mem_address(ex_mem_alu_result),
    .mem_read(ex_mem_mem_read),
    .mem_write(ex_mem_mem_write),
    .data_size(ex_mem_data_size),

    .read_data(read_data)
);

LOAD_DATA_UNIT load_Data_Unit(
    .read_data(read_data),
    .funct3(ex_mem_funct3),
    .data_mem_address(ex_mem_alu_result),
    .load_data(load_data)
);

endmodule
