module ID_EX (
    input clk,
    input reset,
    input flush,
    input stall,

    // Data from ID stage
    input [31:0] pc,
    input [31:0] rs1_data,
    input [31:0] rs2_data,
    input [31:0] immediate,

    // Register identifiers
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,

    // Control signals
    input regWrite,
    input branch,
    input [3:0] alu_control,
    input alu_src,
    input mem_write,
    input mem_read,
    input [1:0] data_size,
    input [1:0] write_back_select,
    input auipc,
    input jalr,
    input jal,
    input [2:0] if_id_funct3,
    input [31:0] if_id_pc_plus_4,

    // Registered outputs
    output reg [31:0] id_ex_pc,
    output reg [31:0] id_ex_rs1_data,
    output reg [31:0] id_ex_rs2_data,
    output reg [31:0] id_ex_immediate,

    output reg [4:0] id_ex_rs1,
    output reg [4:0] id_ex_rs2,
    output reg [4:0] id_ex_rd,

    output reg id_ex_regWrite,
    output reg id_ex_branch,
    output reg [3:0] id_ex_alu_control,
    output reg id_ex_alu_src,
    output reg id_ex_mem_write,
    output reg id_ex_mem_read,
    output reg [1:0] id_ex_data_size,
    output reg [1:0] id_ex_write_back_select,
    output reg id_ex_auipc,
    output reg id_ex_jalr,
    output reg id_ex_jal,
    output reg [2:0] id_ex_funct3,
    output reg [31:0] id_ex_pc_plus_4
);

always @(posedge clk) begin
    if (reset) begin

        id_ex_pc                <= 32'b0;
        id_ex_rs1_data          <= 32'b0;
        id_ex_rs2_data          <= 32'b0;
        id_ex_immediate         <= 32'b0;

        id_ex_rs1               <= 5'b0;
        id_ex_rs2               <= 5'b0;
        id_ex_rd                <= 5'b0;

        id_ex_regWrite          <= 1'b0;
        id_ex_branch            <= 1'b0;
        id_ex_alu_control       <= 4'b0;
        id_ex_alu_src            <= 1'b0;
        id_ex_mem_write         <= 1'b0;
        id_ex_mem_read          <= 1'b0;
        id_ex_data_size         <= 2'b0;
        id_ex_write_back_select <= 2'b0;
        id_ex_auipc              <= 1'b0;
        id_ex_jalr               <= 1'b0;
        id_ex_jal                <= 1'b0;
        id_ex_funct3             <= 3'b0;
        id_ex_pc_plus_4          <= 32'b0;
    end
    else if (flush) begin

        id_ex_pc                <= 32'b0;
        id_ex_rs1_data          <= 32'b0;
        id_ex_rs2_data          <= 32'b0;
        id_ex_immediate         <= 32'b0;

        id_ex_rs1               <= 5'b0;
        id_ex_rs2               <= 5'b0;
        id_ex_rd                <= 5'b0;

        id_ex_regWrite          <= 1'b0;
        id_ex_branch            <= 1'b0;
        id_ex_alu_control       <= 4'b0;
        id_ex_alu_src            <= 1'b0;
        id_ex_mem_write         <= 1'b0;
        id_ex_mem_read          <= 1'b0;
        id_ex_data_size         <= 2'b0;
        id_ex_write_back_select <= 2'b0;
        id_ex_auipc              <= 1'b0;
        id_ex_jalr               <= 1'b0;
        id_ex_jal                <= 1'b0;
        id_ex_funct3             <= 3'b0;
        id_ex_pc_plus_4          <= 32'b0;
    end

    else if (stall) begin
        // Insert bubble
        id_ex_regWrite <= 1'b0;
        id_ex_branch <= 1'b0;
        id_ex_mem_write <= 1'b0;
        id_ex_mem_read <= 1'b0;
        id_ex_auipc <= 1'b0;
        id_ex_jalr <= 1'b0;
        id_ex_jal <= 1'b0;
    end

    else begin

        id_ex_pc                <= pc;
        id_ex_rs1_data          <= rs1_data;
        id_ex_rs2_data          <= rs2_data;
        id_ex_immediate         <= immediate;

        id_ex_rs1               <= rs1;
        id_ex_rs2               <= rs2;
        id_ex_rd                <= rd;

        id_ex_regWrite          <= regWrite;
        id_ex_branch            <= branch;
        id_ex_alu_control       <= alu_control;
        id_ex_alu_src            <= alu_src;
        id_ex_mem_write         <= mem_write;
        id_ex_mem_read          <= mem_read;
        id_ex_data_size         <= data_size;
        id_ex_write_back_select <= write_back_select;
        id_ex_auipc              <= auipc;
        id_ex_jalr               <= jalr;
        id_ex_jal                <= jal;
        id_ex_funct3             <= if_id_funct3;
        id_ex_pc_plus_4          <= if_id_pc_plus_4;
    end
end

endmodule
