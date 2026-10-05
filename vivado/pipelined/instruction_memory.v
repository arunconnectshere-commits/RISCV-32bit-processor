module INSTRUCTION_MEMORY(
    output [31:0] instruction,
    input  [31:0] pc
);

reg [31:0] memory [0:255];

assign instruction = memory[pc >> 2];

// $readmemh is a simulation-only construct. `SYNTHESIS` is predefined by
// Vivado during synthesis, so this block is skipped there and the tool
// infers an uninitialized block RAM instead (fine for timing/utilization/
// PnR analysis, since instruction content doesn't affect the netlist
// structure). Simulation (where SYNTHESIS is undefined) is unaffected --
// testbenches that poke DUT.instruction_Memory.memory[] directly still work.
`ifndef SYNTHESIS
initial begin
    $readmemh("D:\vivado_projects\projects\RISCV_FPGA\RISCV_FPGA.srcs\sources_1\imports\sim\program.hex", memory);
end
`endif

endmodule
