module LOAD_DATA_UNIT(
    input [31:0] read_data,
    input [2:0] funct3,
    input [31:0] data_mem_address,
    
    output reg [31:0] load_data
);
wire upper_half = data_mem_address[1];
wire [1:0] byte_position = data_mem_address[1:0];
always @(*) begin
    load_data = 32'b0;
    case(funct3)
        3'b000: begin
            // LB
            case(byte_position)
                2'b00: begin
                    load_data = {{24{read_data[7]}} , read_data[7:0]};
                end
                2'b01: begin
                    load_data = {{24{read_data[15]}} , read_data[15:8]};
                end
                2'b10: begin
                    load_data = {{24{read_data[23]}} , read_data[23:16]};
                end
                2'b11: begin
                    load_data = {{24{read_data[31]}} , read_data[31:24]};
                end
            endcase

        end
        3'b001: begin
            // LH
            if(upper_half) begin // upper half
                load_data = {{16{read_data[31]}} , read_data[31:16]};
            end
            else begin              // lower half
                load_data = {{16{read_data[15]}} , read_data[15:0]};
            end
        end
        3'b010: begin
            // LW
            load_data = read_data;
        end

        3'b100: begin
            // LBU
            case(byte_position)
                2'b00: begin
                    load_data = {24'b0 , read_data[7:0]};
                end
                2'b01: begin
                    load_data = {24'b0 , read_data[15:8]};
                end
                2'b10: begin
                    load_data = {24'b0 , read_data[23:16]};
                end
                2'b11: begin
                    load_data = {24'b0 , read_data[31:24]};
                end
            endcase

        end
        3'b101: begin
            // LHU
            if(upper_half) begin // upper half
                load_data = {16'b0 , read_data[31:16]};
            end
            else begin           // lower half
                load_data = {16'b0 , read_data[15:0]};
            end
        end
	
	default: begin
		// ignore
	end
    endcase
end
endmodule
