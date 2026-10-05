module PC_MUX(
    input  [31:0] pc_plus_4,
    input  [31:0] branch_target,
    input         pcSrc,
    input [31:0]  jalr_target,
    input         jalr,
    input         jal,
    input [31:0]  jal_target,

    output reg [31:0] next_pc
);

always @(*) begin
    if (jalr)
        next_pc = jalr_target;
    else if (jal)
        next_pc = jal_target;
    else if (pcSrc)
        next_pc = branch_target;
    else
        next_pc = pc_plus_4;
end

endmodule
