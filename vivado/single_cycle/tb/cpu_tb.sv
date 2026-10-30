
 typedef enum bit {
    ADD_OP;
    SUB_OP;
  } alu_op_t;

 class transaction;
    rand bit [4:0] rs1;
    rand bit [4:0] rs2;
    rand bit [4:0] rd;
    rand alu_op_t op;
 endclass

module test;
    transaction tr;

    initial begin
        tr = new();

        repeat (5) begin
            if (tr.randomize()) begin
                $display("rs1=%0d, rs2=%0d, rd=%0d, op=%s",
                         tr.rs1, tr.rs2, tr.rd, tr.op.name());
            end
            else begin
                $display("Randomization failed!");
            end
        end

        $finish;
    end
endmodule