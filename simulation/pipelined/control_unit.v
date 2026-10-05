module CONTROL_UNIT1(
    input [31:0] instruction,

    output reg regWrite,
    output reg branch,
    output reg [3:0] alu_control,
    output reg alu_src,
    output reg mem_write,
    output reg mem_read,
    output reg [1:0] data_size,
    output reg [1:0] write_back_select,
    output reg auipc,
    output reg jalr,
    output reg jal
);

wire [6:0] opcode = instruction[6:0];
wire [2:0] funct3 = instruction[14:12];
wire [6:0] funct7 = instruction[31:25];
wire [11:0] imm   = instruction[31:20];


always @(*) begin
    //default values
    regWrite = 0;
    branch = 0;
    alu_src = 0;
    // pcSrc = 0;
    alu_control = 4'b0000;
    mem_write = 1'b0;
    mem_read = 1'b0;
    data_size = 2'b00;
    write_back_select = 2'b00;
    auipc = 1'b0;
    jalr = 1'b0;
    jal = 1'b0;
    // R-type instructions
    case(opcode)
        7'b0110011: begin
            // R-type
            regWrite = 1;
            alu_src = 0;
        
            case ({funct7, funct3})
        
                10'b0000000_000: alu_control = 4'b0000; // ADD
                10'b0100000_000: alu_control = 4'b0001; // SUB
                10'b0000000_001: alu_control = 4'b0101; // SLL
                10'b0000000_010: alu_control = 4'b1000; // SLT
                10'b0000000_011: alu_control = 4'b1001; // SLTU
                10'b0000000_100: alu_control = 4'b0100; // XOR
                10'b0000000_101: alu_control = 4'b0110; // SRL
                10'b0100000_101: alu_control = 4'b0111; // SRA
                10'b0000000_110: alu_control = 4'b0011; // OR
                10'b0000000_111: alu_control = 4'b0010; // AND
        
                10'b0000001_000: alu_control = 4'b1011; // MUL
        
                default: begin
                    alu_control = 4'b0000;
                    regWrite = 0;
                end
        
            endcase
        end

        7'b0010011: begin
            // I-type
            regWrite = 1;
            branch = 0;
            alu_src = 1;
            case(funct3)
                3'b000 :                          alu_control = 4'b0000; // ADDI               
                3'b001 :                          alu_control = 4'b0101; // SLLI
                3'b010 :                          alu_control = 4'b1000; // SLTI
                3'b011 :                          alu_control = 4'b1001; // SLTIU
                3'b100 :                          alu_control = 4'b0100; // XOR
                3'b101 : begin 
                            if(imm[11:5] == 7'b0000000) begin
                                                  alu_control = 4'b0110; // SRLI
                            end
                            else if (imm[11:5] == 7'b0100000)begin
                                                  alu_control = 4'b0111; // SRAI
                            end
                        end
                
                3'b110 :                          alu_control = 4'b0011; // ORI
                3'b111 :                          alu_control = 4'b0010; // ANDI
    
                default:                          alu_control = 4'b0000; // Default
            
            endcase
        end

        7'b1100011: begin
            // B-type
        branch = 1;
        alu_control = 4'b0001;

        end

        7'b0100011: begin
            // S-type
            case (funct3)
                3'b000: begin
                    // SB
                    mem_write = 1; 
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b00; // byte
                end
                3'b001: begin
                    // SH
                    mem_write = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b01; // half
                end
                3'b010: begin 
                    // SW
                    mem_write = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b10; // word
                end
		
		default: begin
			// ignore
		end
            endcase

        end

        7'b0000011: begin
            // L-type

            case(funct3) 
                3'b000: begin
                    // LB
                    regWrite = 1;
                    write_back_select = 2'b01;
                    mem_read = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b00;
                end
                3'b001: begin
                    // LH
                    regWrite = 1;
                    write_back_select = 2'b01;
                    mem_read = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b01;
                end
                3'b010: begin 
                    // LW
                    regWrite = 1;
                    write_back_select = 2'b01;
                    mem_read = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b10;
                end
                3'b100: begin
                    // LBU
                    regWrite = 1;
                    write_back_select = 2'b01;
                    mem_read = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b00;
                end
                3'b101: begin
                    // LHU
                    regWrite = 1;
                    write_back_select = 2'b01;
                    mem_read = 1;
                    alu_control = 4'b0000;
                    alu_src = 1;
                    data_size = 2'b01;
                end
		
		default: begin
			// ignore
		end
            endcase
        end

        7'b0110111: begin
            // LUI
            regWrite = 1;
            write_back_select = 2'b00;
            mem_read = 0;
            alu_control = 4'b1010;
            alu_src = 1;
            data_size = 2'b00;
        end

        7'b0010111: begin
            // AUIPC
            regWrite = 1;
            alu_control = 4'b0000;
            alu_src = 1;
            auipc = 1;
        end

        7'b1100111: begin
            if(funct3 == 3'b0) begin
            // JALR
            regWrite = 1;
            alu_control = 4'b0000;
            alu_src = 1; // alu_b = immediate
            jalr = 1;
            auipc = 0;  // alu_a = rs1_data
            write_back_select = 2'b10;
            end
        end
        7'b1101111: begin
            // JAL
            regWrite = 1;
            alu_control = 4'b0000;
            alu_src = 1; // alu_b = immediate
            jal = 1;
            auipc = 1; // alu_a = pc
            write_back_select = 2'b10;
        end
        

        default: begin
            // do nothing
        end



    endcase
end
endmodule
