# 32-bit RISC-V Processor: Single-Cycle and 5-Stage Pipelined

A 32-bit RV32I processor in Verilog, built in two versions: a single-cycle baseline and a 5-stage pipelined design with data forwarding and hazard handling. Both were verified in simulation, then synthesized in Xilinx Vivado for static timing analysis, critical-path identification and RTL-level timing optimization.

| | Single-Cycle | 5-Stage Pipelined |
|---|---|---|
| WNS @ 10 ns (post-synthesis) | -0.232 ns | +0.501 ns |
| Est. Fmax* | ~97.7 MHz | ~105.3 MHz |
| Meets 10 ns timing | No | Yes |

\*Fmax = 1 / (clock period − WNS), from post-synthesis timing. It is not a post-implementation result.

## Contents

- [Architecture](#architecture)
- [Design Overview](#design-overview)
- [Supported ISA](#supported-isa)
- [Hazard Handling](#hazard-handling)
- [Verification](#verification)
- [Synthesis and Timing](#synthesis-and-timing)
- [RTL Timing Optimization](#rtl-timing-optimization)
- [Single-Cycle vs. Pipelined](#single-cycle-vs-pipelined)
- [Limitations and Future Work](#limitations-and-future-work)
- [Repository Structure](#repository-structure)
- [Running the Simulation](#running-the-simulation)
- [License](#license)

## Architecture

### Single-Cycle

Each instruction is fetched, decoded, executed, memory-accessed and written back in one clock cycle.

![Single-cycle architecture](docs/single_cycle/architecture_schematic.png)

High-resolution version: [`architecture_schematic_high_res.pdf`](docs/single_cycle/architecture_schematic_high_res.pdf)

### 5-Stage Pipeline

The single-cycle design was extended into an `IF → ID → EX → MEM → WB` pipeline with `IF/ID`, `ID/EX`, `EX/MEM` and `MEM/WB` registers, plus forwarding, hazard detection, and a dedicated branch comparator in EX.

![Pipelined architecture](docs/pipelined/architecture_schematic.png)

High-resolution version: [`architecture_schematic_high_res.pdf`](docs/pipelined/architecture_schematic_high_res.pdf)

## Design Overview

Both versions are built from the same blocks:

- **Control unit:** decodes opcode and funct fields into ALU, memory, write-back and jump controls
- **ALU:** arithmetic, logic, shifts, set-less-than, and LUI pass-through
- **Register file:** 32×32 registers, two read ports, x0 hardwired to zero, write-through bypass
- **Immediate generator:** I, S, B, U and J immediates with sign extension
- **PC logic:** PC register and next-PC selection (sequential, branch, JAL, JALR)
- **Load/store interface:** byte, halfword and word stores with byte-lane merging; sign- and zero-extended loads

The pipelined version adds the four pipeline registers, a forwarding unit and a hazard unit.

## Supported ISA

37 instructions from the RV32I base integer ISA:

| Type | Instructions |
|---|---|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| I-type (ALU) | ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI |
| I-type (load) | LB, LH, LW, LBU, LHU |
| I-type (jump) | JALR |
| S-type | SB, SH, SW |
| B-type | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| U-type | LUI, AUIPC |
| J-type | JAL |

**Not implemented:** `FENCE`, `ECALL`, `EBREAK`, and the M extension. An early pipelined version included `MUL`, which was removed to improve timing.

## Hazard Handling

| Hazard | Mechanism | Cost |
|---|---|---|
| Data (producer in EX/MEM or MEM/WB) | Forwarding into the ALU operand muxes | 0 cycles |
| Data (producer in WB, consumer in ID) | Register-file write-through | 0 cycles |
| Load-use | Stall PC and `IF/ID`, bubble into `ID/EX` | 1 cycle |
| Control (taken branch, JAL, JALR) | Resolved in EX; `IF/ID` and `ID/EX` flushed | 2 cycles |

Branches use static not-taken prediction.

![Hazard handling](docs/pipelined/hazard_handling.png)

## Verification

Both processors were verified in simulation with Icarus Verilog and GTKWave, using test programs that exercise ALU, load/store, branch and jump instructions, including data-forwarding, load-use and control-hazard cases. Testbenches are in `simulation/single_cycle/` and `simulation/pipelined/`.

![Single-cycle waveform](docs/single_cycle/simulation_waveform.png)
![Pipelined waveform](docs/pipelined/simulation_waveform.png)

A separate SystemVerilog verification environment is planned (see [Future Work](#limitations-and-future-work)).

## Synthesis and Timing

Both designs were synthesized in Xilinx Vivado for the Basys3 FPGA (Artix-7 `xc7a35tcpg236-1`) under a 10 ns clock constraint.

> **These are post-synthesis results, not post-place-and-route.** Synthesis uses estimated net delays, so implementation numbers will differ.

| Metric | Single-Cycle | 5-Stage Pipelined |
|---|---|---|
| LUTs | 842 | 913 |
| Flip-flops | 32 | 504 |
| Distributed RAM LUTs | 48 | 48 |
| WNS (setup) | -0.232 ns | +0.501 ns |
| TNS (setup) | -4.821 ns | 0 ns |
| Failing setup endpoints | 54 / 100 | 0 |
| Est. Fmax* | ~97.7 MHz | ~105.3 MHz |

\*Calculated as `1 / (clock period − WNS)`.

**Methodology.** The `CPU` module was synthesized out-of-context, with the instruction and data memories outside the module and no input or output delay constraints. The results therefore cover the internal register-to-register paths of the core only. In particular, the single-cycle number does not include instruction-fetch or data-memory access time, so it understates a real single-cycle cycle time, and the Fmax gap shown here is smaller than it would be with memories in the loop. Both designs used the same part, clock constraint and flow, so the comparison between them is like-for-like.

![Single-cycle timing](docs/single_cycle/timing_summary_post_synthesis.png)
![Pipelined timing](docs/pipelined/timing_summary_post_synthesis.png)
![Single-cycle utilization](docs/single_cycle/utilization_summary_post_synthesis.png)
![Pipelined utilization](docs/pipelined/utilization_summary_post_synthesis.png)

## RTL Timing Optimization

The pipelined design first failed timing badly. Post-synthesis WNS at each step:

| Step | WNS |
|---|---|
| Original pipelined CPU with MUL | -8.901 ns |
| Removed MUL | -3.300 ns |
| Added a separate branch comparator | -0.169 ns |
| Restructured comparator selection (select on `funct3[2:1]`, invert with `funct3[0]`) | +0.501 ns |

### Branch Comparator

Branch decisions no longer go through the main ALU. A dedicated comparator in EX computes equality, signed less-than and unsigned less-than, selects one with `funct3[2:1]`, and inverts it with `funct3[0]` for BNE, BGE and BGEU:

```verilog
wire [31:0] cmp_a = alu_a;
wire [31:0] cmp_b = forwarded_rs2;
wire [31:0] cmp_sub_result = cmp_a - cmp_b;

wire eq           = ~|(cmp_a ^ cmp_b);
wire signs_differ = cmp_a[31] ^ cmp_b[31];
wire slt = signs_differ ? cmp_a[31] : cmp_sub_result[31];  // BLT / BGE
wire ult = signs_differ ? cmp_b[31] : cmp_sub_result[31];  // BLTU / BGEU

reg cmp_out;
always @(*) begin
    case (id_ex_funct3[2:1])
        2'b00:   cmp_out = eq;    // BEQ / BNE
        2'b10:   cmp_out = slt;   // BLT / BGE
        2'b11:   cmp_out = ult;   // BLTU / BGEU
        default: cmp_out = 1'b0;
    endcase
end

wire branch_condition = cmp_out ^ id_ex_funct3[0];
wire pcSrc = id_ex_branch && branch_condition;
```

The comparator covers all six conditional branches.

## Single-Cycle vs. Pipelined

- **Timing:** the single-cycle design misses the 10 ns constraint (WNS -0.232 ns, 54 failing endpoints). The pipelined design meets it (WNS +0.501 ns, 0 failing endpoints).
- **Fmax:** ~97.7 MHz → ~105.3 MHz, about 8% higher.
- **Flip-flops:** 32 → 504, from the four pipeline registers.
- **LUTs:** 842 → 913.
- **Distributed RAM:** unchanged at 48 LUTs.

Fmax is not the same as performance. Load-use stalls and branch flushes push the pipelined design's CPI above 1. See [`docs/comparison.md`](docs/comparison.md) for the side-by-side summary.

## Limitations and Future Work

- Timing is post-synthesis and core-only (memories excluded). Post-implementation results with memories in the timed loop are future work.
- No `FENCE`, `ECALL`, `EBREAK` or M extension.
- Static not-taken branch prediction with a 2-cycle taken penalty.
- A SystemVerilog verification environment (constrained-random stimulus, reference model, assertions, functional coverage) is planned as a separate repository.
- A throughput comparison (cycles × clock period) on a benchmark program is not yet done.

## Repository Structure

```
RISCV-32bit-processor/
├── README.md
├── LICENSE
├── docs/
│   ├── single_cycle/
│   ├── pipelined/
│   └── comparison.md
├── simulation/
│   ├── single_cycle/
│   └── pipelined/
└── vivado/
    ├── single_cycle/
    └── pipelined/
```

- `docs/`: architecture diagrams, waveforms, post-synthesis timing and utilization summaries
- `simulation/`: RTL and testbench for each version
- `vivado/`: Vivado project sources and constraints

## Running the Simulation

```bash
cd simulation/pipelined          # or simulation/single_cycle
iverilog -g2012 -o cpu_sim *.v
vvp cpu_sim
gtkwave dump.vcd                 # waveform output
```

Memory initialization files use relative paths (for example `sim/program.hex`), so run from the directory that contains them.

## Tools

Verilog · Icarus Verilog · GTKWave · Xilinx Vivado

## License

Released under the [MIT License](LICENSE).
