module IMMEDIATE_GENERATOR(
    input [31:0] instruction,
    output reg [31:0] immediate
);

wire [6:0] opcode = instruction[6:0];

always @(*) begin
    immediate = 32'd0;

    case(opcode)

        7'b0010011:
            immediate = {{20{instruction[31]}}, instruction[31:20]}; // I-type

        7'b1100011:
            immediate = {
                {19{instruction[31]}},
                instruction[31],
                instruction[7],
                instruction[30:25],
                instruction[11:8],
                1'b0
            }; // B-type
            
        7'b0100011: 
            immediate = {
                {20{instruction[31]}},
                instruction[31:25],
                instruction[11:7]
            }; // S-type

        7'b0000011:
            immediate = {{20{instruction[31]}}, instruction[31:20]}; // L-type
        
        7'b0110111:
            immediate = {instruction[31:12], 12'b0}; // LUI

        7'b0010111:
            immediate = {instruction[31:12], 12'b0}; // AUIPC

        7'b1100111:
            immediate = {{20{instruction[31]}}, instruction[31:20]}; // JALR
        
        7'b1101111:
            immediate = {
            {11{instruction[31]}},
            instruction[31],
            instruction[19:12],
            instruction[20],
            instruction[30:21],
            1'b0
        }; // JAL
            
        default:
            immediate = 32'b0;
        

    endcase
end

endmodule
