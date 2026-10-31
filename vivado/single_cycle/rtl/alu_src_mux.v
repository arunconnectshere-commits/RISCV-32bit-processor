module ALU_SRC_MUX(
    input [31:0] rs1_data,
    input [31:0] rs2_data,
    input [31:0] immediate,
    input        alu_src,

    output [31:0] alu_a,
    output [31:0] alu_b
);

assign alu_b = alu_src ? immediate : rs2_data;

endmodule
