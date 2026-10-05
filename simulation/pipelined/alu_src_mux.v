module ALU_SRC_MUX_PIPELINED(
    input  [31:0] rs1_data,
    input  [31:0] rs2_data,
    input  [31:0] immediate,
    input         alu_src_b,
    input         auipc,
    input         jal,
    input  [31:0] pc,

    input  [1:0]  forward_a,
    input  [1:0]  forward_b,
    input  [31:0] ex_mem_result,
    input  [31:0] mem_wb_result,

    output [31:0] alu_a,
    output [31:0] alu_b,
    output [31:0] forwarded_rs2
);

wire [31:0] forwarded_rs1;

assign forwarded_rs1 =
    (forward_a == 2'b01) ? ex_mem_result :
    (forward_a == 2'b10) ? mem_wb_result :
                           rs1_data;

assign forwarded_rs2 =
    (forward_b == 2'b01) ? ex_mem_result :
    (forward_b == 2'b10) ? mem_wb_result :
                           rs2_data;

assign alu_a = (auipc || jal) ? pc : forwarded_rs1;

assign alu_b = alu_src_b ? immediate : forwarded_rs2;

endmodule
