module CPU(
    input clk,
    input reset
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
wire        pcSrc;
wire        less;  
wire        less_unsigned;
wire        auipc;
wire        jalr;
wire        jal;

// alu Source MUX
wire [31:0] alu_b;

// alu
wire [31:0] alu_result;
wire zero;
wire [31:0] alu_a;
assign alu_a = (auipc||jal) ? pc : rs1_data;

// Register File
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rd;

assign rs1 = instruction[19:15];
assign rs2 = instruction[24:20];
assign rd  = instruction[11:7];

// Immediate Generator
wire [31:0] immediate;

assign pc_plus_4 = pc + 32'd4;
assign branch_target = pc + immediate;

// Data Memory
wire mem_read;
wire mem_write;
wire [1:0] data_size;

wire [31:0] read_data;


// Load Data Unit
wire [1:0] write_back_select;
wire [31:0] load_data;
reg [31:0] write_back_data;
wire [2:0] funct3;

always @(*) begin
    case (write_back_select)
        2'b00: write_back_data = alu_result;
        2'b01: write_back_data = load_data;
        2'b10: write_back_data = pc_plus_4;
        default: write_back_data = 32'b0;
    endcase
end

assign funct3 = instruction[14:12];



// Module Instantiations

PC_MUX program_Counter_Mux(
    .pc_plus_4(pc_plus_4),
    .branch_target(branch_target),
    .next_pc(next_pc),
    .pcSrc(pcSrc),
    .jalr(jalr),
    .jalr_target(jalr_target),
    .jal(jal),
    .jal_target(jal_target)
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

CONTROL_UNIT control_Unit(
    .instruction(instruction),
    .zero(zero),
    .less(less),
    .less_unsigned(less_unsigned),
    .alu_src(alu_src),
    .alu_control(alu_control),
    .regWrite(regWrite),
    .branch(branch),
    .pcSrc(pcSrc),

    .mem_write(mem_write),
    .mem_read(mem_read),
    .write_back_select(write_back_select),
    .data_size(data_size),
    .auipc(auipc),
    .jalr(jalr),
    .jal(jal)
);

REG_FILE reg_File(
    .clk(clk),
    .read_addr1(rs1),
    .read_addr2(rs2),
    .write_addr(rd),

    .write_enable(regWrite),
    .write_data(write_back_data),

    .read_data1(rs1_data),
    .read_data2(rs2_data)
);

IMMEDIATE_GENERATOR immediate_Generator(
    .instruction(instruction),
    .immediate(immediate)
);

ALU_SRC_MUX alu_Src_Mux(
    .rs2_data(rs2_data),
    .immediate(immediate),
    .alu_src(alu_src),
    .alu_b(alu_b)
);

ALU alu(
    .A(alu_a),
    .B(alu_b),
    .alu_control(alu_control),

    .result(alu_result),
    .zero(zero),
    .less(less),
    .less_unsigned(less_unsigned)
);

DATA_MEMORY data_Memory(
    .clk(clk),
    .write_data(rs2_data),
    .data_mem_address(alu_result),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .data_size(data_size),

    .read_data(read_data)
);

LOAD_DATA_UNIT load_Data_Unit(
    .read_data(read_data),
    .funct3(funct3),
    .data_mem_address(alu_result),
    .load_data(load_data)
);

endmodule
