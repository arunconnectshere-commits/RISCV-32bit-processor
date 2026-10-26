# 32-bit RISC-V Processor: Single-Cycle and 5-Stage Pipelined

A 32-bit RV32I processor in Verilog, built in two versions: a single-cycle baseline and a 5-stage pipelined design with data forwarding and hazard handling. Both were verified in simulation, then synthesized in Xilinx Vivado for static timing analysis, critical-path identification and RTL-level timing optimization.

| | Single-Cycle | 5-Stage Pipelined |
|---|---|---|
| WNS @ 10 ns (post-synthesis) | -1.300 ns | +0.501 ns |
| Est. Fmax* | ~88.5 MHz | ~105.3 MHz |
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
- [Running the Project](#running-the-project)

## Architecture

### Single-Cycle

Each instruction is fetched, decoded, executed, memory-accessed and written back in one clock cycle. The path from instruction fetch through the ALU and data memory to register write-back sets the clock period.

![Single-cycle architecture](docs/single_cycle/architecture_schematic.png)

High-resolution version: [`architecture_schematic_high_res.pdf`](docs/single_cycle/architecture_schematic_high_res.pdf)

### 5-Stage Pipeline

The single-cycle design was extended into an `IF → ID → EX → MEM → WB` pipeline with `IF/ID`, `ID/EX`, `EX/MEM` and `MEM/WB` registers, plus forwarding, hazard detection, and a dedicated branch comparator in EX.

![Pipelined architecture](docs/pipelined/architecture_schematic.png)

High-resolution version: [`architecture_schematic_high_res.pdf`](docs/pipelined/architecture_schematic_high_res.pdf)

## Design Overview

Both versions share the same building blocks:

| Block | Module | Role |
|---|---|---|
| Control unit | `CONTROL_UNIT1` | Decodes opcode/funct fields into ALU, memory, write-back and jump controls |
| ALU | `ALU` | Arithmetic, logic, shifts, compares, LUI pass-through; also drives the zero/less flags used for branches in the single-cycle design |
| Register file | `REG_FILE_PIPELINED` | 32×32 registers, two read ports, x0 hardwired to 0, write-through bypass |
| Immediate generator | `IMMEDIATE_GENERATOR` | I, S, B, U and J immediates with sign extension |
| PC logic | `PROGRAM_COUNTER`, `PC_MUX_PIPELINED` | PC register and next-PC selection (sequential, branch, JAL, JALR, stall) |
| Load/store interface | `DATA_MEMORY`, `LOAD_DATA_UNIT` | Byte, halfword and word stores with byte-lane merging; sign/zero-extended loads |
| Instruction memory | `INSTRUCTION_MEMORY` | Word-addressed ROM |

The pipelined version adds `IF_ID`, `ID_EX`, `EX_MEM`, `MEM_WB`, `FORWARDING_UNIT` and `HAZARD_UNIT`.

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

**Not implemented:** `FENCE`, `ECALL`, `EBREAK`, and the M extension (an early pipelined version included `MUL`, which was removed to improve timing).

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

Both processors were verified with Icarus Verilog and GTKWave.

- **Testbenches:** `simulation/single_cycle/` and `simulation/pipelined/`
- **Test program:** TODO: list what it covers (instruction classes, byte/half loads and stores, branches taken and not taken, JAL/JALR)
- **Hazard coverage:** TODO: RAW at distance 1, 2 and 3, load-use, link-register read right after JAL/JALR
- **Pass criteria:** TODO: for example, final register and memory contents match expected values

![Single-cycle waveform](docs/single_cycle/simulation_waveform.png)
![Pipelined waveform](docs/pipelined/simulation_waveform.png)

## Synthesis and Timing

Both designs were synthesized in Xilinx Vivado under a 10 ns clock constraint.

> **These are post-synthesis results, not post-place-and-route.** Synthesis uses estimated net delays, so implementation numbers will differ.

| Metric | Single-Cycle | 5-Stage Pipelined |
|---|---|---|
| LUTs | 842 | TODO: 913 or 1082, verify against the utilization report |
| Flip-flops | 32 | 504 |
| Distributed RAM LUTs | 48 | 48 |
| WNS | -1.300 ns | +0.501 ns |
| TNS | -105.872 ns | 0 ns |
| Failing endpoints | 100 | 0 |
| Fmax* | ~88.5 MHz | ~105.3 MHz |

**Setup used:**

- Part: TODO (for example `xc7a35tcpg236-1`)
- Vivado version: TODO
- Synthesis mode: TODO (default or out-of-context)
- I/O constraints: TODO (were input/output delays set?)
- Memories: TODO (inside the timed design or external to `CPU`?). If external, the single-cycle path excludes instruction fetch and data-memory access, so its WNS understates the true single-cycle cycle time.

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

After this change, the critical path is TODO: name it (for example forwarding → comparator → `pcSrc` → PC mux).

## Single-Cycle vs. Pipelined

- **Timing:** the single-cycle design misses 10 ns (WNS -1.300 ns, 100 failing endpoints). The pipelined design meets it (WNS +0.501 ns, 0 failing endpoints).
- **Flip-flops:** 32 → 504, from the four pipeline registers.
- **LUTs:** 842 → TODO.
- **Distributed RAM:** unchanged at 48 LUTs.

Fmax is not the same as performance. Load-use stalls and branch flushes push the pipelined design's CPI above 1. See `docs/comparison.md` for the side-by-side summary.

## Limitations and Future Work

- Timing is post-synthesis. Post-implementation results are future work.
- No `FENCE`, `ECALL`, `EBREAK` or M extension.
- Static not-taken branch prediction with a 2-cycle taken penalty.
- Verification is directed simulation. Constrained-random testing against a reference model, assertions and hazard coverage would strengthen it.
- Add a throughput comparison (cycles × clock period) on a benchmark program.

## Repository Structure

```
RISCV-32bit-processor/
├── README.md
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

## Running the Project

```bash
# TODO: confirm directory and file names
cd simulation/pipelined
iverilog -g2012 -o cpu_sim *.v
vvp cpu_sim
gtkwave dump.vcd
```

The memory initialization files use relative paths (for example `sim/program.hex`), so run from the directory the testbench expects. TODO: state it.

## Tools

Verilog · Icarus Verilog · GTKWave · Xilinx Vivado

## License

TODO: add a `LICENSE` file.
