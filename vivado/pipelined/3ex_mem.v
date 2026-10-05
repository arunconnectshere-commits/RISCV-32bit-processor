module EX_MEM (
    input clk,
    input reset,

    // Data produced/carried from EX
    input [31:0] alu_result,
    input [31:0] rs2_data,
    input [4:0] rd,
    input [2:0] id_ex_funct3,
    input [31:0] id_ex_pc_plus_4,

    // Memory controls
    input mem_write,
    input mem_read,
    input [1:0] data_size,

    // Write-back controls
    input regWrite,
    input [1:0] write_back_select,

    // Registered outputs
    output reg [31:0] ex_mem_alu_result,
    output reg [31:0] ex_mem_rs2_data,
    output reg [4:0] ex_mem_rd,

    output reg ex_mem_mem_write,
    output reg ex_mem_mem_read,
    output reg [1:0] ex_mem_data_size,

    output reg ex_mem_regWrite,
    output reg [1:0] ex_mem_write_back_select,
    output reg [2:0] ex_mem_funct3,
    output reg[31:0] ex_mem_pc_plus_4
);

always @(posedge clk) begin
    if (reset) begin
        ex_mem_alu_result        <= 32'b0;
        ex_mem_rs2_data          <= 32'b0;
        ex_mem_rd                <= 5'b0;

        ex_mem_mem_write         <= 1'b0;
        ex_mem_mem_read          <= 1'b0;
        ex_mem_data_size         <= 2'b0;

        ex_mem_regWrite          <= 1'b0;
        ex_mem_write_back_select <= 2'b0;
        ex_mem_funct3            <= 3'b0;
        ex_mem_pc_plus_4         <= 32'b0;

    end
    else begin
        ex_mem_alu_result        <= alu_result;
        ex_mem_rs2_data          <= rs2_data;
        ex_mem_rd                <= rd;

        ex_mem_mem_write         <= mem_write;
        ex_mem_mem_read          <= mem_read;
        ex_mem_data_size         <= data_size;

        ex_mem_regWrite          <= regWrite;
        ex_mem_write_back_select <= write_back_select;
        ex_mem_funct3            <= id_ex_funct3;
        ex_mem_pc_plus_4         <= id_ex_pc_plus_4;
    end
end

endmodule
