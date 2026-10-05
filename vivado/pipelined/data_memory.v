module DATA_MEMORY(
    input clk,
    input [31:0] write_data,
    input [31:0] data_mem_address,
    input mem_read,
    input mem_write,
    input [1:0] data_size,

    output [31:0] read_data
);
reg [31:0] data_memory [0:255];

integer i;

initial begin
    for (i = 0; i < 256; i = i + 1)
        data_memory[i] = 32'b0;
end

// $readmemh is a simulation-only construct -- see instruction_memory.v for
// why this is guarded the same way.
`ifndef SYNTHESIS
initial begin
    $readmemh("data.hex", data_memory);
end
`endif

wire [1:0] half_position = data_mem_address[1:0];
wire [1:0] byte_position = data_mem_address[1:0];


assign read_data = mem_read ? data_memory[data_mem_address >> 2] : 32'b0;


always @(posedge clk) begin
    if(mem_write) begin
        case(data_size)
            2'b00: begin
                // SB
                case(byte_position)
                    2'b00: begin
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'hFFFFFF00)
                    | {24'b0, write_data[7:0]};
                    end
                    2'b01: begin
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'hFFFF00FF)
                    | {16'b0, write_data[7:0], 8'b0};
                    end
                    2'b10: begin
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'hFF00FFFF)
                    | {8'b0, write_data[7:0],16'b0};
                    end
                    2'b11: begin
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'h00FFFFFF)
                    | {write_data[7:0], 24'b0};
                    end
                endcase
            end

            2'b01: begin
                // SH
                if(half_position ==2'b00) begin
                    // Lower half
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'hFFFF0000)
                    | {{16'b0}, write_data[15:0]};
                end
                else if(half_position == 2'b10) begin
                    // Upper half
                    data_memory[data_mem_address >> 2] <=
                    (data_memory[data_mem_address >> 2] & 32'h0000FFFF)
                    | {write_data[15:0], 16'b0};
                end
            end
            2'b10: begin
                // SW
                data_memory[data_mem_address >> 2] <= write_data;
            end

	    default: begin
		// ignore
	    end
        endcase
    end
end
endmodule
