module PC_MUX_PIPELINED(
    input  [31:0] pc,
    input  [31:0] pc_plus_4,
    input  [31:0] branch_target,
    input         pcSrc,
    input [31:0]  jalr_target,
    input         jalr,
    input         jal,
    input [31:0]  jal_target,
    input         stall,

    output reg [31:0] next_pc
);

always @(*) begin
    if (stall)
        next_pc = pc;
    else if (jalr)
        next_pc = jalr_target;
    else if (jal)
        next_pc = jal_target;
    else if (pcSrc)
        next_pc = branch_target;
    else
        next_pc = pc_plus_4;
end

endmodule
