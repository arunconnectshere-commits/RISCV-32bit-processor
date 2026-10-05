module IF_ID(
    input clk,
    input reset,
    input flush,
    input stall,

    input [31:0] pc,
    input [31:0] instruction,

    output reg [31:0] if_id_pc,
    output reg [31:0] if_id_instruction
);

always @(posedge clk) begin
    if(reset || flush) begin
        if_id_pc <= 32'b0;
        if_id_instruction <= 32'b0;
    end

    else if(stall) begin
        // hold
    end

    else begin
        if_id_pc <= pc;
        if_id_instruction <= instruction;
    end
end
endmodule
