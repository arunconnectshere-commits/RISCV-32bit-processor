module REG_FILE_PIPELINED(
    input clk,
    input [4:0] read_addr1,
    input [4:0] read_addr2,
    input [4:0] write_addr,

    input [31:0] write_data,
    input write_enable,

    output [31:0] read_data1,
    output [31:0] read_data2
);

reg [31:0] registers [0:31];

integer i;
initial begin
    for (i = 0; i < 32; i = i + 1)
        registers[i] = 32'd0;
end

always @(posedge clk) begin
    if (write_enable && write_addr != 0) begin
        registers[write_addr] <= write_data;
    end
end

assign read_data1 =
    (read_addr1 == 0) ? 32'b0 :
    (write_enable && write_addr == read_addr1) ? write_data :
    registers[read_addr1];

assign read_data2 =
    (read_addr2 == 0) ? 32'b0 :
    (write_enable && write_addr == read_addr2) ? write_data :
    registers[read_addr2];

endmodule