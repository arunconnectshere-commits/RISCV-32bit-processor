module FORWARDING_UNIT(
    input [4:0] id_ex_rs1,
    input [4:0] id_ex_rs2,

    input [4:0] ex_mem_rd,
    input       ex_mem_regWrite,
    input       ex_mem_mem_read,

    input [4:0] mem_wb_rd,
    input       mem_wb_regWrite,

    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);

always @(*) begin

    // Default: use register-file value
    forward_a = 2'b00;
    forward_b = 2'b00;

    // Forward MUX A
    if (ex_mem_regWrite &&
        !ex_mem_mem_read &&
        ex_mem_rd != 0 &&
        ex_mem_rd == id_ex_rs1) begin

        forward_a = 2'b01;

    end
    else if (mem_wb_regWrite &&
             mem_wb_rd != 0 &&
             mem_wb_rd == id_ex_rs1) begin

        forward_a = 2'b10;

    end

    // Forward MUX B
    if (ex_mem_regWrite &&
        !ex_mem_mem_read &&
        ex_mem_rd != 0 &&
        ex_mem_rd == id_ex_rs2) begin

        forward_b = 2'b01;

    end
    else if (mem_wb_regWrite &&
             mem_wb_rd != 0 &&
             mem_wb_rd == id_ex_rs2) begin

        forward_b = 2'b10;

    end

end

endmodule
