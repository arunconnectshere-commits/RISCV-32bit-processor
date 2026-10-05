module MEM_WB (
    input clk,
    input reset,

    // Data from MEM stage
    input [31:0] mem_data,
    input [31:0] alu_result,
    input [4:0] rd,
    input [31:0] ex_mem_pc_plus_4,

    // Write-back controls
    input regWrite,
    input [1:0] write_back_select,

    // Registered outputs
    output reg [31:0] mem_wb_mem_data,
    output reg [31:0] mem_wb_alu_result,
    output reg [4:0] mem_wb_rd,

    output reg mem_wb_regWrite,
    output reg [1:0] mem_wb_write_back_select,
    output reg [31:0] mem_wb_pc_plus_4
);

always @(posedge clk) begin
    if (reset) begin
        mem_wb_mem_data          <= 32'b0;
        mem_wb_alu_result        <= 32'b0;
        mem_wb_rd                <= 5'b0;

        mem_wb_regWrite          <= 1'b0;
        mem_wb_write_back_select <= 2'b0;
        mem_wb_pc_plus_4         <= 32'b0;
    end
    else begin
        mem_wb_mem_data          <= mem_data;
        mem_wb_alu_result        <= alu_result;
        mem_wb_rd                <= rd;

        mem_wb_regWrite          <= regWrite;
        mem_wb_write_back_select <= write_back_select;
        mem_wb_pc_plus_4         <= ex_mem_pc_plus_4;
    end
end

endmodule
