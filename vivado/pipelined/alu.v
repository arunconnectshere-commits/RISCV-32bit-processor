module ALU(
    input [31:0] A,
    input [31:0] B,
    input [3:0] alu_control,

    output reg [31:0] result,
    output zero,
    output less,
    output less_unsigned

);

assign zero = (result == 32'b0);
assign less = ($signed(A) < $signed(B));
assign less_unsigned = (A < B);

always @(*) begin
    result = 32'b0;
    
    case (alu_control)
        4'b0000: result = A + B;                    // ADD
        4'b0001: result = A - B;                    // SUB
        4'b0010: result = A & B;                    // AND
        4'b0011: result = A | B;                    // OR
        4'b0100: result = A ^ B;                    // XOR
        4'b0101: result = A << B[4:0];              // SLL
        4'b0110: result = A >> B[4:0];              // SRL
        4'b0111: result = $signed(A) >>> B[4:0];    // SRA
        4'b1000: result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0; // SLT
        4'b1001: result = (A < B) ? 32'd1 : 32'd0;                   // SLTU
        4'b1010: result = B;                        // LUI
        default: result = 32'b0;
    endcase
end

endmodule
