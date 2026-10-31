`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Self-checking constrained-random testbench for the RV32I CPU (single-cycle,
// imem/dmem exposed as ports).
//
// Covers all 37 implemented instructions:
//   R : ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
//   I : ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
//   L : LB LH LW LBU LHU          S : SB SH SW
//   B : BEQ BNE BLT BGE BLTU BGEU
//   J : JAL JALR                  U : LUI AUIPC
// NOT covered (not implemented): ECALL, EBREAK, FENCE.
//
// How it works
//   encoder      transaction -> 32-bit instruction word
//   rv32i_model  golden reference (ISS). Decodes the RAW instruction word itself,
//                independently of the generator and encoder, straight from the
//                RISC-V reference card.
//   scoreboard   counts checks / failures
//   test         builds a random program, then runs the DUT and the model in
//                LOCKSTEP, comparing every cycle:
//                  - fetched PC and instruction   (catches wrong branch/jump decisions)
//                  - regWrite / rd                (catches missing or spurious writes)
//                  - the data-memory bus          (address, data, size, read/write strobes)
//                  - ALL 32 registers after each instruction (catches stray writes, x0)
//                  - the stored word after each store, whole memory at the end
//                Then it checks that the stimulus actually hit every instruction,
//                both outcomes of every branch, backward branch/JAL, JALR bit-0
//                masking, and every byte/half lane of loads and stores.
//
// Program shape (all legality is enforced by construction, not by luck)
//   * x31 is a reserved, constant data base pointer (=512). It is never a destination.
//     Loads/stores use x31 + small aligned offset, so every access stays in range.
//   * Branches / JAL jump FORWARD by 1..4 instructions; JALR is emitted as
//     "AUIPC t,0 ; JALR rd,imm(t)" so its target is known without knowing t's value.
//     Directed macros add a counted BACKWARD loop and a BACKWARD JAL.
//   * The program ends in NOPs and a self-loop (JAL x0,0) that marks "done".
//
// Run:  +seed=<n> to change the random program (default 1), +trace for a per-
//       instruction log, +dump to print the generated program as hex.
//
// Needs: CPU (ports below, internal names dut.rd, dut.regWrite, dut.reg_File.registers)
//        and DATA_MEMORY (array named data_memory), as in the previous testbench.
//////////////////////////////////////////////////////////////////////////////////

// ---------------------------------------------------------------------------
// All 37 instructions
// ---------------------------------------------------------------------------
typedef enum int {
    ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND,
    ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
    LB, LH, LW, LBU, LHU,
    SB, SH, SW,
    BEQ, BNE, BLT, BGE, BLTU, BGEU,
    JAL, JALR, LUI, AUIPC
} op_t;

localparam int NUM_OPS = 37;

typedef enum bit [2:0] {
    R, I, S, B, U, J
} instruction_type;

localparam bit [31:0] NOP_INSTR  = 32'h00000013;   // addi x0,x0,0
localparam bit [31:0] HALT_INSTR = 32'h0000006F;   // jal  x0,0  (self loop = program done)
localparam bit [4:0]  BASE_REG   = 5'd31;          // reserved constant data pointer
localparam int        BASE_ADDR  = 512;
localparam int        PROG_WORDS = 524288;   // 2 MB: room for long-range jump macros

// ---------------------------------------------------------------------------
// Interface (signals between CPU and the testbench)
// ---------------------------------------------------------------------------
interface cpu_if(input logic clk);
    logic reset;

    // CPU <-> INSTRUCTION MEMORY
    logic [31:0] imem_instr, imem_pc;

    // CPU <-> DATA MEMORY
    logic [31:0] dmem_wd, dmem_rd, dmem_addr;
    logic        dmem_mr, dmem_mw;
    logic [1:0]  dmem_ds;

    // Internal CPU signals mirrored here for observation
    logic [4:0]  dut_rd;
    logic        dut_regWrite;
endinterface

// ---------------------------------------------------------------------------
// Helpers: instruction encoding (formats from the RISC-V reference card)
// ---------------------------------------------------------------------------
function automatic bit [31:0] enc_r(input bit [6:0] f7, input bit [4:0] rs2, input bit [4:0] rs1, input bit [2:0] f3, input bit [4:0] rd, input bit [6:0] opc);
    return {f7, rs2, rs1, f3, rd, opc};
endfunction

function automatic bit [31:0] enc_i(input int imm, input bit [4:0] rs1, input bit [2:0] f3, input bit [4:0] rd, input bit [6:0] opc);
    bit [11:0] i12 = imm[11:0];
    return {i12, rs1, f3, rd, opc};
endfunction

function automatic bit [31:0] enc_s(input int imm, input bit [4:0] rs2, input bit [4:0] rs1, input bit [2:0] f3);
    bit [11:0] i12 = imm[11:0];
    return {i12[11:5], rs2, rs1, f3, i12[4:0], 7'b0100011};
endfunction

function automatic bit [31:0] enc_b(input int off, input bit [4:0] rs2, input bit [4:0] rs1, input bit [2:0] f3);
    bit [12:0] o = off[12:0];
    return {o[12], o[10:5], rs2, rs1, f3, o[4:1], o[11], 7'b1100011};
endfunction

function automatic bit [31:0] enc_u(input int imm20, input bit [4:0] rd, input bit [6:0] opc);
    bit [19:0] i20 = imm20[19:0];
    return {i20, rd, opc};
endfunction

function automatic bit [31:0] enc_j(input int off, input bit [4:0] rd);
    bit [20:0] o = off[20:0];
    return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
endfunction

// ---------------------------------------------------------------------------
// transaction : one randomly generated instruction (fields only)
// ---------------------------------------------------------------------------
class transaction;
    op_t op;
    bit [4:0] rd, rs1, rs2;
    int imm;                 // I/S: signed 12-bit, B/J: byte offset, U: 20-bit field, shifts: shamt
    int skip;                // B/J/JALR: number of instructions jumped over (1 + skip words ahead)
    instruction_type instr_type;

    // x0 about 10% of the time, otherwise x1..x30 (x31 is the reserved base pointer)
    function bit [4:0] pick_rd();
        if ($urandom_range(0, 9) == 0) return 5'd0;
        return 5'($urandom_range(1, 30));
    endfunction

    // 12-bit signed immediate, biased toward edge values
    function int pick_imm12();
        case ($urandom_range(0, 9))
            0: return 0;
            1: return -1;
            2: return 2047;
            3: return -2048;
            4: return 1;
            default: return int'($urandom_range(0, 4095)) - 2048;
        endcase
    endfunction

    function int pick_shamt();
        case ($urandom_range(0, 7))
            0: return 0;
            1: return 31;
            default: return int'($urandom_range(0, 31));
        endcase
    endfunction

    function int pick_imm20();
        case ($urandom_range(0, 7))
            0: return 0;
            1: return 20'hFFFFF;
            2: return 20'h80000;
            default: return int'($urandom_range(0, 20'hFFFFF));
        endcase
    endfunction

    function void gen(op_t o);
        op  = o;
        rd  = pick_rd();
        rs1 = 5'($urandom_range(0, 31));
        rs2 = 5'($urandom_range(0, 31));
        if ($urandom_range(0, 6) == 0) rs2 = rs1;          // equal-operand cases
        imm = 0;
        skip = $urandom_range(0, 3);
        case (o)
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND: instr_type = R;
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI:               begin instr_type = I; imm = pick_imm12(); end
            SLLI, SRLI, SRAI:                                 begin instr_type = I; imm = pick_shamt(); end
            LB, LBU: begin instr_type = I; rs1 = BASE_REG; imm = int'($urandom_range(0, 255)) - 128; end
            LH, LHU: begin instr_type = I; rs1 = BASE_REG; imm = (int'($urandom_range(0, 127)) - 64) * 2; end
            LW:      begin instr_type = I; rs1 = BASE_REG; imm = (int'($urandom_range(0, 63)) - 32) * 4; end
            SB:      begin instr_type = S; rs1 = BASE_REG; imm = int'($urandom_range(0, 255)) - 128; end
            SH:      begin instr_type = S; rs1 = BASE_REG; imm = (int'($urandom_range(0, 127)) - 64) * 2; end
            SW:      begin instr_type = S; rs1 = BASE_REG; imm = (int'($urandom_range(0, 63)) - 32) * 4; end
            BEQ, BNE, BLT, BGE, BLTU, BGEU: begin
                instr_type = B;
                imm = 4 * (1 + skip);                            // forward only
                case ($urandom_range(0, 9))
                    0, 1, 2: rs2 = rs1;                          // equal operands -> BEQ/BGE/BGEU taken
                    3:       rs2 = 5'd0;
                    4:       rs1 = 5'd0;
                    default: ;
                endcase
            end
            JAL:   begin instr_type = J; imm = 4 * (1 + skip); end
            JALR:  begin instr_type = I; imm = 8 + 4 * skip + $urandom_range(0, 1); end  // used after AUIPC t,0
            LUI, AUIPC: begin instr_type = U; imm = pick_imm20(); end
        endcase
    endfunction
endclass

// ---------------------------------------------------------------------------
// encoder : transaction -> instruction word
// ---------------------------------------------------------------------------
class encoder;
    function bit [31:0] encode(transaction tr);
        case (tr.op)
            ADD:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h0, tr.rd, 7'b0110011);
            SUB:   return enc_r(7'h20, tr.rs2, tr.rs1, 3'h0, tr.rd, 7'b0110011);
            SLL:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h1, tr.rd, 7'b0110011);
            SLT:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h2, tr.rd, 7'b0110011);
            SLTU:  return enc_r(7'h00, tr.rs2, tr.rs1, 3'h3, tr.rd, 7'b0110011);
            XOR:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h4, tr.rd, 7'b0110011);
            SRL:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h5, tr.rd, 7'b0110011);
            SRA:   return enc_r(7'h20, tr.rs2, tr.rs1, 3'h5, tr.rd, 7'b0110011);
            OR:    return enc_r(7'h00, tr.rs2, tr.rs1, 3'h6, tr.rd, 7'b0110011);
            AND:   return enc_r(7'h00, tr.rs2, tr.rs1, 3'h7, tr.rd, 7'b0110011);
            ADDI:  return enc_i(tr.imm, tr.rs1, 3'h0, tr.rd, 7'b0010011);
            SLTI:  return enc_i(tr.imm, tr.rs1, 3'h2, tr.rd, 7'b0010011);
            SLTIU: return enc_i(tr.imm, tr.rs1, 3'h3, tr.rd, 7'b0010011);
            XORI:  return enc_i(tr.imm, tr.rs1, 3'h4, tr.rd, 7'b0010011);
            ORI:   return enc_i(tr.imm, tr.rs1, 3'h6, tr.rd, 7'b0010011);
            ANDI:  return enc_i(tr.imm, tr.rs1, 3'h7, tr.rd, 7'b0010011);
            SLLI:  return enc_i(tr.imm,          tr.rs1, 3'h1, tr.rd, 7'b0010011);
            SRLI:  return enc_i(tr.imm,          tr.rs1, 3'h5, tr.rd, 7'b0010011);
            SRAI:  return enc_i(tr.imm | 12'h400, tr.rs1, 3'h5, tr.rd, 7'b0010011);   // imm[11:5] = 0x20
            LB:    return enc_i(tr.imm, tr.rs1, 3'h0, tr.rd, 7'b0000011);
            LH:    return enc_i(tr.imm, tr.rs1, 3'h1, tr.rd, 7'b0000011);
            LW:    return enc_i(tr.imm, tr.rs1, 3'h2, tr.rd, 7'b0000011);
            LBU:   return enc_i(tr.imm, tr.rs1, 3'h4, tr.rd, 7'b0000011);
            LHU:   return enc_i(tr.imm, tr.rs1, 3'h5, tr.rd, 7'b0000011);
            SB:    return enc_s(tr.imm, tr.rs2, tr.rs1, 3'h0);
            SH:    return enc_s(tr.imm, tr.rs2, tr.rs1, 3'h1);
            SW:    return enc_s(tr.imm, tr.rs2, tr.rs1, 3'h2);
            BEQ:   return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h0);
            BNE:   return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h1);
            BLT:   return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h4);
            BGE:   return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h5);
            BLTU:  return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h6);
            BGEU:  return enc_b(tr.imm, tr.rs2, tr.rs1, 3'h7);
            JAL:   return enc_j(tr.imm, tr.rd);
            JALR:  return enc_i(tr.imm, tr.rs1, 3'h0, tr.rd, 7'b1100111);
            LUI:   return enc_u(tr.imm, tr.rd, 7'b0110111);
            AUIPC: return enc_u(tr.imm, tr.rd, 7'b0010111);
            default: return NOP_INSTR;
        endcase
    endfunction
endclass

// ---------------------------------------------------------------------------
// program_builder : lays out the random program in memory
// ---------------------------------------------------------------------------
class program_builder;
    bit [31:0] mem [PROG_WORDS];
    int n;
    transaction tr, ftr;
    encoder enc;

    function new();
        tr  = new();
        ftr = new();
        enc = new();
        n   = 0;
        foreach (mem[k]) mem[k] = NOP_INSTR;
    endfunction

    function void emit_word(input bit [31:0] w);
        if (n >= PROG_WORDS - 1) $fatal(1, "program memory full");
        mem[n] = w;
        n = n + 1;
    endfunction

    // Forward jumps skip over `skip` filler words. Fillers are always plain single-word
    // ops (never branches/jumps/macros), so a jump can only land on the start of the
    // next item -- never in the middle of a macro, where a stale register would turn
    // the loop/JALR into a runaway.
    function void emit_filler();
        int r = $urandom_range(0, 3);
        case (r)
            0: ftr.gen(op_t'($urandom_range(ADD,  AND)));
            1: ftr.gen(op_t'($urandom_range(ADDI, SRAI)));
            2: ftr.gen(op_t'($urandom_range(LB,   LHU)));
            3: ftr.gen(op_t'($urandom_range(SB,   SW)));
        endcase
        emit_word(enc.encode(ftr));
    endfunction

    // one instruction of kind o; JALR is emitted as AUIPC t,0 ; JALR rd,imm(t)
    function void emit_op(op_t o);
        bit [4:0] t;
        tr.gen(o);
        if (o == JALR) begin
            t = 5'($urandom_range(1, 30));
            emit_word(enc_u(0, t, 7'b0010111));          // auipc t,0  -> t = pc of this instruction
            tr.rs1 = t;
        end
        emit_word(enc.encode(tr));
        case (o)
            BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR:
                repeat (tr.skip) emit_filler();
            default: ;
        endcase
    endfunction

    // counted backward loop:  addi t,x0,cnt ; L: addi t,t,-1 ; bne t,x0,L
    function void emit_loop();
        bit [4:0] t = 5'($urandom_range(1, 30));
        emit_word(enc_i($urandom_range(2, 5), 5'd0, 3'h0, t, 7'b0010011));
        emit_word(enc_i(-1, t, 3'h0, t, 7'b0010011));
        emit_word(enc_b(-4, 5'd0, t, 3'h1));
    endfunction

    // backward JAL:  i0: jal x0,+12 -> i3 ; i1: jal x0,+12 -> i4 ; i2: poison ; i3: jal rd,-8 -> i1 ; i4:
    function void emit_jal_back();
        bit [4:0] link = tr.pick_rd();
        emit_word(enc_j(12, 5'd0));
        emit_word(enc_j(12, 5'd0));
        emit_word(enc_i(12'h7FF, 5'd0, 3'h0, 5'($urandom_range(1, 30)), 7'b0010011));  // poison: must never execute
        emit_word(enc_j(-8, link));
    endfunction

    // Long-range forward + backward branches (B-type reaches +-4 KB). Small offsets can never
    // tell imm[11] / imm[12] apart from the sign bit, so a wrong wire there would go
    // unnoticed. Layout (k+2 words):  w0: br +4(k+1) -> c ; b: br +4(k+1) -> d ; NOPs ; c: br -4k -> b
    // Path is w0 -> c -> b -> d. All three branches compare x0 with x0 (always taken).
    function void emit_long_b(input int k);
        bit [2:0] f3;
        case ($urandom_range(0, 2)) 0: f3 = 3'h0; 1: f3 = 3'h5; default: f3 = 3'h7; endcase   // BEQ / BGE / BGEU
        emit_word(enc_b(4 * (k + 1), 5'd0, 5'd0, f3));
        emit_word(enc_b(4 * (k + 1), 5'd0, 5'd0, f3));
        repeat (k - 1) emit_word(NOP_INSTR);
        emit_word(enc_b(-4 * k, 5'd0, 5'd0, f3));
    endfunction

    // same trampoline with JAL (J-type reaches +-1 MB): exercises imm[19:12], imm[11], imm[20]
    function void emit_long_j(input int k);
        emit_word(enc_j(4 * (k + 1), tr.pick_rd()));
        emit_word(enc_j(4 * (k + 1), tr.pick_rd()));
        repeat (k - 1) emit_word(NOP_INSTR);
        emit_word(enc_j(-4 * k, tr.pick_rd()));
    endfunction

    // x = full 32-bit constant via LUI + ADDI (ADDI sign-extends, so LUI compensates)
    function void load_const(input bit [4:0] r, input bit [31:0] v);
        bit [31:0] lo = {{20{v[11]}}, v[11:0]};
        bit [31:0] hi = v - lo;
        emit_word(enc_u(hi[31:12], r, 7'b0110111));
        emit_word(enc_i(int'($signed(lo)), r, 3'h0, r, 7'b0010011));
    endfunction

    // Corner-value operand pairs: signed/unsigned boundaries, equal, zero, shift amounts 0/31
    function void corner_pair(input int p, output bit [31:0] a, output bit [31:0] b);
        case (p)
            0: begin a = 32'hFFFFFFFF; b = 32'h00000001; end
            1: begin a = 32'h00000001; b = 32'hFFFFFFFF; end
            2: begin a = 32'h00000000; b = 32'h00000000; end
            3: begin a = 32'h80000000; b = 32'h7FFFFFFF; end
            4: begin a = 32'h7FFFFFFF; b = 32'h80000000; end
            5: begin a = 32'h12345678; b = 32'h12345678; end
            6: begin a = 32'h80000001; b = 32'h0000001F; end
            default: begin a = 32'hDEADBEEF; b = 32'h00000000; end
        endcase
    endfunction

    // R-type op on corner operands: rs1/rs2 loaded with exact constants first
    function void emit_corner_r(op_t o, input int p);
        bit [31:0] a, b;
        bit [4:0] t1 = 5'($urandom_range(1, 15)), t2 = 5'($urandom_range(16, 30));
        corner_pair(p, a, b);
        load_const(t1, a); load_const(t2, b);
        tr.gen(o);
        tr.rs1 = t1; tr.rs2 = t2;
        emit_word(enc.encode(tr));
    endfunction

    // branch on corner operands (guarantees both outcomes of every branch type, incl.
    // signed-vs-unsigned disagreement), +8 offset over one filler
    function void emit_corner_br(op_t o, input int p);
        bit [31:0] a, b;
        bit [4:0] t1 = 5'($urandom_range(1, 15)), t2 = 5'($urandom_range(16, 30));
        corner_pair(p, a, b);
        load_const(t1, a); load_const(t2, b);
        tr.gen(o);
        tr.rs1 = t1; tr.rs2 = t2; tr.imm = 8; tr.skip = 1;
        emit_word(enc.encode(tr));
        emit_filler();
    endfunction

    // every load/store flavour at every legal byte lane, 4 random words each
    // (data comes from the 16 seeded words, so sign bits / byte values vary)
    function void emit_lane_sweep();
        for (int k = LB; k <= SW; k++)
            for (int l = 0; l < 4; l++) begin
                bit legal = (k == LB || k == LBU || k == SB) ? 1 :
                            (k == LH || k == LHU || k == SH) ? (l % 2 == 0) : (l == 0);
                if (legal) repeat (4) begin
                    tr.gen(op_t'(k));
                    tr.imm = 4 * $urandom_range(0, 15) + l;
                    emit_word(enc.encode(tr));
                end
            end
    endfunction

    function void build(input int n_random);
        int r;
        // 1) preamble: random 32-bit values into x1..x30 (LUI + ADDI), base pointer into x31
        for (int k = 1; k <= 30; k++) begin
            emit_word(enc_u($urandom_range(0, 20'hFFFFF), 5'(k), 7'b0110111));
            emit_word(enc_i(int'($urandom_range(0, 4095)) - 2048, 5'(k), 3'h0, 5'(k), 7'b0010011));
        end
        emit_word(enc_i(BASE_ADDR, 5'd0, 3'h0, BASE_REG, 7'b0010011));
        // 2) seed 16 words of data memory so early loads see non-zero data
        for (int k = 1; k <= 16; k++)
            emit_word(enc_s(4 * (k - 1), 5'(k), BASE_REG, 3'h2));
        // 3) directed sweep: every instruction at least once, plus both macros
        for (int k = 0; k < NUM_OPS; k++) emit_op(op_t'(k));
        emit_loop();
        emit_jal_back();
        emit_lane_sweep();
        // 3a) corner-value operands: every R-type op and every branch on 8 boundary pairs
        for (int p = 0; p < 8; p++) begin
            for (int k = ADD; k <= AND; k++)    emit_corner_r(op_t'(k), p);
            for (int k = BEQ; k <= BGEU; k++)   emit_corner_br(op_t'(k), p);
        end
        // 3b) long-range jumps: 3 short + 3 beyond 2 KB for branches; JAL from tiny up to
        //     beyond 512 KB (sets imm[19]); k is chosen so each offset has random bit patterns
        for (int q = 0; q < 3; q++) emit_long_b($urandom_range(2, 511));
        for (int q = 0; q < 3; q++) emit_long_b($urandom_range(512, 1022));
        for (int q = 0; q < 8; q++) emit_long_j($urandom_range(1 << (2 + q), (1 << (3 + q)) - 1) + 1);
        emit_long_j($urandom_range(1 << 17, (1 << 17) + (1 << 16)));
        // 4) random body, weighted
        repeat (n_random) begin
            r = $urandom_range(0, 99);
            if      (r < 18) emit_op(op_t'($urandom_range(ADD,  AND)));
            else if (r < 38) emit_op(op_t'($urandom_range(ADDI, SRAI)));
            else if (r < 50) emit_op(op_t'($urandom_range(LB,   LHU)));
            else if (r < 62) emit_op(op_t'($urandom_range(SB,   SW)));
            else if (r < 78) emit_op(op_t'($urandom_range(BEQ,  BGEU)));
            else if (r < 83) emit_op(JAL);
            else if (r < 88) emit_op(JALR);
            else if (r < 91) emit_op(LUI);
            else if (r < 94) emit_op(AUIPC);
            else if (r < 97) emit_loop();
            else             emit_jal_back();
        end
        // 5) tail: NOP landing pad for forward jumps, then the "done" self-loop
        repeat (8) emit_word(NOP_INSTR);
        emit_word(HALT_INSTR);
    endfunction
endclass

// ---------------------------------------------------------------------------
// rv32i_model : golden reference model. Decodes the instruction word itself.
// ---------------------------------------------------------------------------
class rv32i_model;
    bit [31:0] regs [32];
    bit [31:0] mem  [256];          // 1 KB, same size as DATA_MEMORY
    bit [31:0] pc;

    // results of the last step()
    op_t       op;
    bit        writes_rd;           // instruction format writes a register (even if rd == x0)
    bit [4:0]  rd;
    bit [31:0] rd_val;
    bit        st_en, ld_en;
    bit [31:0] mem_addr, st_data;
    bit [1:0]  mem_size;            // 0 byte, 1 half, 2 word (DUT dmem_ds encoding)
    bit        is_branch, taken, backward, jalr_odd;

    function new();
        foreach (regs[k]) regs[k] = 0;
        foreach (mem[k])  mem[k]  = 0;
        pc = 0;
    endfunction

    function bit [31:0] sext(input bit [31:0] v, input int bits);
        bit [31:0] sh = 32 - bits;
        return $signed(v << sh) >>> sh;
    endfunction

    function void step(input bit [31:0] ins);
        bit [6:0]  opc = ins[6:0];
        bit [2:0]  f3  = ins[14:12];
        bit [6:0]  f7  = ins[31:25];
        bit [4:0]  rs1 = ins[19:15], rs2 = ins[24:20];
        bit [31:0] a = regs[rs1], b = regs[rs2];
        bit [31:0] imm_i = sext(ins[31:20], 12);
        bit [31:0] imm_s = sext({ins[31:25], ins[11:7]}, 12);
        bit [31:0] imm_b = sext({ins[31], ins[7], ins[30:25], ins[11:8], 1'b0}, 13);
        bit [31:0] imm_u = {ins[31:12], 12'b0};
        bit [31:0] imm_j = sext({ins[31], ins[19:12], ins[20], ins[30:21], 1'b0}, 21);
        bit [31:0] next = pc + 4;
        bit [31:0] w, v;
        bit        cond;
        int        sh;

        rd = ins[11:7]; rd_val = 0; writes_rd = 0; st_en = 0; ld_en = 0;
        is_branch = 0; taken = 0; backward = 0; jalr_odd = 0; mem_addr = 0; st_data = 0; mem_size = 0;

        case (opc)
            7'b0110011: begin                                   // R-type
                writes_rd = 1;
                case ({f7, f3})
                    {7'h00, 3'h0}: begin op = ADD;  rd_val = a + b; end
                    {7'h20, 3'h0}: begin op = SUB;  rd_val = a - b; end
                    {7'h00, 3'h1}: begin op = SLL;  rd_val = a << b[4:0]; end
                    {7'h00, 3'h2}: begin op = SLT;  rd_val = ($signed(a) < $signed(b)) ? 1 : 0; end
                    {7'h00, 3'h3}: begin op = SLTU; rd_val = (a < b) ? 1 : 0; end
                    {7'h00, 3'h4}: begin op = XOR;  rd_val = a ^ b; end
                    {7'h00, 3'h5}: begin op = SRL;  rd_val = a >> b[4:0]; end
                    {7'h20, 3'h5}: begin op = SRA;  rd_val = $signed(a) >>> b[4:0]; end
                    {7'h00, 3'h6}: begin op = OR;   rd_val = a | b; end
                    {7'h00, 3'h7}: begin op = AND;  rd_val = a & b; end
                    default: $fatal(1, "model: illegal R-type %h at pc %h", ins, pc);
                endcase
            end
            7'b0010011: begin                                   // I-type ALU
                writes_rd = 1;
                case (f3)
                    3'h0: begin op = ADDI;  rd_val = a + imm_i; end
                    3'h2: begin op = SLTI;  rd_val = ($signed(a) < $signed(imm_i)) ? 1 : 0; end
                    3'h3: begin op = SLTIU; rd_val = (a < imm_i) ? 1 : 0; end
                    3'h4: begin op = XORI;  rd_val = a ^ imm_i; end
                    3'h6: begin op = ORI;   rd_val = a | imm_i; end
                    3'h7: begin op = ANDI;  rd_val = a & imm_i; end
                    3'h1: begin op = SLLI;  rd_val = a << ins[24:20]; end
                    3'h5: begin
                        if (f7 == 7'h20) begin op = SRAI; rd_val = $signed(a) >>> ins[24:20]; end
                        else             begin op = SRLI; rd_val = a >> ins[24:20]; end
                    end
                endcase
            end
            7'b0000011: begin                                   // loads
                writes_rd = 1; ld_en = 1;
                mem_addr = a + imm_i;
                if (mem_addr > 1023) $fatal(1, "model: load address %h out of range at pc %h", mem_addr, pc);
                w  = mem[mem_addr[9:2]];
                sh = 8 * mem_addr[1:0];
                case (f3)
                    3'h0: begin op = LB;  mem_size = 0; rd_val = sext((w >> sh) & 32'hFF, 8); end
                    3'h1: begin op = LH;  mem_size = 1; rd_val = sext((w >> sh) & 32'hFFFF, 16); end
                    3'h2: begin op = LW;  mem_size = 2; rd_val = w; end
                    3'h4: begin op = LBU; mem_size = 0; rd_val = (w >> sh) & 32'hFF; end
                    3'h5: begin op = LHU; mem_size = 1; rd_val = (w >> sh) & 32'hFFFF; end
                    default: $fatal(1, "model: illegal load %h at pc %h", ins, pc);
                endcase
            end
            7'b0100011: begin                                   // stores
                st_en = 1;
                mem_addr = a + imm_s;
                if (mem_addr > 1023) $fatal(1, "model: store address %h out of range at pc %h", mem_addr, pc);
                w  = mem[mem_addr[9:2]];
                sh = 8 * mem_addr[1:0];
                st_data = b;
                case (f3)
                    3'h0: begin op = SB; mem_size = 0; w = (w & ~(32'hFF   << sh)) | ((b & 32'hFF)   << sh); end
                    3'h1: begin op = SH; mem_size = 1; w = (w & ~(32'hFFFF << sh)) | ((b & 32'hFFFF) << sh); end
                    3'h2: begin op = SW; mem_size = 2; w = b; end
                    default: $fatal(1, "model: illegal store %h at pc %h", ins, pc);
                endcase
                mem[mem_addr[9:2]] = w;
            end
            7'b1100011: begin                                   // branches
                is_branch = 1;
                case (f3)
                    3'h0: begin op = BEQ;  cond = (a == b); end
                    3'h1: begin op = BNE;  cond = (a != b); end
                    3'h4: begin op = BLT;  cond = ($signed(a) <  $signed(b)); end
                    3'h5: begin op = BGE;  cond = ($signed(a) >= $signed(b)); end
                    3'h6: begin op = BLTU; cond = (a <  b); end
                    3'h7: begin op = BGEU; cond = (a >= b); end
                    default: $fatal(1, "model: illegal branch %h at pc %h", ins, pc);
                endcase
                taken = cond;
                if (cond) begin next = pc + imm_b; backward = ($signed(imm_b) < 0); end
            end
            7'b1101111: begin                                   // JAL
                op = JAL; writes_rd = 1; rd_val = pc + 4; next = pc + imm_j; backward = ($signed(imm_j) < 0);
            end
            7'b1100111: begin                                   // JALR
                op = JALR; writes_rd = 1; rd_val = pc + 4;
                v = a + imm_i;
                jalr_odd = v[0];
                next = v & 32'hFFFFFFFE;
            end
            7'b0110111: begin op = LUI;   writes_rd = 1; rd_val = imm_u;      end
            7'b0010111: begin op = AUIPC; writes_rd = 1; rd_val = pc + imm_u; end
            default: $fatal(1, "model: illegal/unsupported instruction %h at pc %h", ins, pc);
        endcase

        if (writes_rd && rd != 0) regs[rd] = rd_val;
        pc = next;
    endfunction
endclass

// ---------------------------------------------------------------------------
// scoreboard : counts checks and failures
// ---------------------------------------------------------------------------
class scoreboard;
    int checks = 0;
    int errors = 0;

    function bit score(input logic [31:0] actual_result, expected_result);
        checks++;
        if (actual_result === expected_result) return 1;
        errors++;
        return 0;
    endfunction
endclass

// ---------------------------------------------------------------------------
// test
// ---------------------------------------------------------------------------
module test;
    logic clk;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    cpu_if intf(clk);

    CPU dut (
        .clk(clk),
        .reset(intf.reset),
        .dmem_wd(intf.dmem_wd),
        .dmem_rd(intf.dmem_rd),
        .dmem_addr(intf.dmem_addr),
        .dmem_mr(intf.dmem_mr),
        .dmem_mw(intf.dmem_mw),
        .dmem_ds(intf.dmem_ds),
        .imem_instr(intf.imem_instr),
        .imem_pc(intf.imem_pc)
    );

    DATA_MEMORY dmem (
        .clk(clk),
        .write_data(intf.dmem_wd),
        .data_mem_address(intf.dmem_addr),
        .mem_read(intf.dmem_mr),
        .mem_write(intf.dmem_mw),
        .data_size(intf.dmem_ds),
        .read_data(intf.dmem_rd)
    );

    assign intf.dut_rd       = dut.rd;
    assign intf.dut_regWrite = dut.regWrite;

    bit [31:0] program_mem [PROG_WORDS];
    assign intf.imem_instr = program_mem[intf.imem_pc[31:2] % PROG_WORDS];

    program_builder pb;
    rv32i_model     ref_model;
    scoreboard      sb;

    // ---- stimulus coverage ----
    int op_count   [NUM_OPS];
    int br_taken   [6];
    int br_not     [6];
    int back_br_taken, back_jal, jalr_odd_cnt, rd0_writes;
    int lane_cov [NUM_OPS][4];   // [load/store op][byte lane = addr[1:0]]
    int cycles;

    bit trace, dump;
    int seed;
    int n_random;
    int seed_dummy;
    
    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        trace = $test$plusargs("trace");
        dump  = $test$plusargs("dump");
        if (!$value$plusargs("n=%d", n_random)) n_random = 600;
        seed_dummy = $urandom(seed);

        pb = new();
        pb.build(n_random);
        foreach (pb.mem[k]) program_mem[k] = pb.mem[k];
        $display("Program built: %0d instructions (seed %0d)", pb.n, seed);
        if (dump) for (int k = 0; k < pb.n; k++) $display("  [%0d] %h", k, pb.mem[k]);
    end

    initial begin
        intf.reset = 1;
        @(negedge clk)
        intf.reset = 0;
    end

    // watchdog
    initial begin
        #2000000;
        $fatal(1, "TIMEOUT: program did not reach the halt loop");
    end

    // ---- lockstep checker ----
    bit [31:0] ins, exp_mask_data;
    int halt_wait;
    bit done;

    initial begin
        ref_model = new();
        sb        = new();
        wait (intf.reset == 0);
        done = 0; halt_wait = 0;

        forever begin
            // ===== pre-edge: everything the DUT is about to execute this cycle =====
            @(posedge clk);
            cycles++;

            ins = program_mem[ref_model.pc[31:2]];
            if (!sb.score(intf.imem_pc, ref_model.pc))
                $fatal(1, "PC mismatch: DUT %h model %h (cycle %0d)", intf.imem_pc, ref_model.pc, cycles);
            if (!sb.score(intf.imem_instr, ins))
                $fatal(1, "Instruction fetch mismatch at PC %h: DUT %h expected %h", ref_model.pc, intf.imem_instr, ins);

            ref_model.step(ins);          // model executes it now

            // register-write intent
            if (!sb.score({31'b0, intf.dut_regWrite}, {31'b0, ref_model.writes_rd}))
                $fatal(1, "regWrite mismatch (%s) PC %h: DUT %b expected %b",
                       ref_model.op.name(), intf.imem_pc, intf.dut_regWrite, ref_model.writes_rd);
            if (ref_model.writes_rd)
                if (!sb.score({27'b0, intf.dut_rd}, {27'b0, ref_model.rd}))
                    $fatal(1, "rd mismatch (%s) PC %h: DUT x%0d expected x%0d",
                           ref_model.op.name(), intf.imem_pc, intf.dut_rd, ref_model.rd);

            // data-memory bus
            if (!sb.score({31'b0, intf.dmem_mw}, {31'b0, ref_model.st_en}))
                $fatal(1, "dmem_mw mismatch (%s) PC %h: DUT %b expected %b",
                       ref_model.op.name(), intf.imem_pc, intf.dmem_mw, ref_model.st_en);
            if (ref_model.ld_en)
                if (!sb.score({31'b0, intf.dmem_mr}, 32'd1))
                    $fatal(1, "dmem_mr not asserted for %s at PC %h", ref_model.op.name(), intf.imem_pc);
            if (ref_model.st_en || ref_model.ld_en) begin
                if (!sb.score(intf.dmem_addr, ref_model.mem_addr))
                    $fatal(1, "dmem_addr mismatch (%s) PC %h: DUT %h expected %h",
                           ref_model.op.name(), intf.imem_pc, intf.dmem_addr, ref_model.mem_addr);
                if (!sb.score({30'b0, intf.dmem_ds}, {30'b0, ref_model.mem_size}))
                    $fatal(1, "dmem_ds mismatch (%s) PC %h: DUT %0d expected %0d",
                           ref_model.op.name(), intf.imem_pc, intf.dmem_ds, ref_model.mem_size);
            end
            if (ref_model.st_en) begin
                exp_mask_data = (ref_model.mem_size == 0) ? (ref_model.st_data & 32'hFF) :
                                (ref_model.mem_size == 1) ? (ref_model.st_data & 32'hFFFF) : ref_model.st_data;
                if (!sb.score(intf.dmem_wd & ((ref_model.mem_size == 0) ? 32'hFF : (ref_model.mem_size == 1) ? 32'hFFFF : 32'hFFFFFFFF),
                              exp_mask_data))
                    $fatal(1, "store data mismatch (%s) PC %h: DUT %h expected %h",
                           ref_model.op.name(), intf.imem_pc, intf.dmem_wd, exp_mask_data);
            end

            // ---- stimulus coverage bookkeeping ----
            op_count[ref_model.op]++;
            if (ref_model.is_branch) begin
                if (ref_model.taken) br_taken[ref_model.op - BEQ]++; else br_not[ref_model.op - BEQ]++;
                if (ref_model.taken && ref_model.backward) back_br_taken++;
            end
            if (ref_model.op == JAL && ref_model.backward) back_jal++;
            if (ref_model.op == JALR && ref_model.jalr_odd) jalr_odd_cnt++;
            if (ref_model.writes_rd && ref_model.rd == 0) rd0_writes++;
            if (ref_model.ld_en || ref_model.st_en) lane_cov[ref_model.op][ref_model.mem_addr[1:0]]++;

            if (trace)
                $display("%0t PC=%h INSTR=%h %-5s rd=x%0d val=%h next=%h",
                         $time, intf.imem_pc, ins, ref_model.op.name(), ref_model.rd, ref_model.rd_val, ref_model.pc);

            // ===== post-edge: architectural state after the instruction =====
            @(negedge clk);
            for (int k = 0; k < 32; k++)
                if (!sb.score(dut.reg_File.registers[k], ref_model.regs[k]))
                    $fatal(1, "Register x%0d mismatch after %s at PC-1 (instr %h): DUT %h expected %h (cycle %0d)",
                           k, ref_model.op.name(), ins, dut.reg_File.registers[k], ref_model.regs[k], cycles);
            if (ref_model.st_en)
                if (!sb.score(dmem.data_memory[ref_model.mem_addr[9:2]], ref_model.mem[ref_model.mem_addr[9:2]]))
                    $fatal(1, "Memory word %0d mismatch after %s: DUT %h expected %h",
                           ref_model.mem_addr[9:2], ref_model.op.name(),
                           dmem.data_memory[ref_model.mem_addr[9:2]], ref_model.mem[ref_model.mem_addr[9:2]]);

            // ===== finished? (model sits on the self-loop) =====
            if (ins == HALT_INSTR) begin
                halt_wait++;
                if (halt_wait == 3) break;
            end
        end

        // ---- final full-state comparison ----
        for (int k = 0; k < 256; k++)
            if (!sb.score(dmem.data_memory[k], ref_model.mem[k]))
                $fatal(1, "Final memory mismatch at word %0d: DUT %h expected %h", k, dmem.data_memory[k], ref_model.mem[k]);

        // ---- did the stimulus actually exercise everything? ----
        begin
            int holes = 0;
            op_t o;
            $display("");
            $display("---- instruction coverage ----");
            for (int k = 0; k < NUM_OPS; k++) begin
                o = op_t'(k);
                if (op_count[k] == 0) begin holes++; $display("  HOLE: %s never executed", o.name()); end
            end
            for (int k = 0; k < 6; k++) begin
                o = op_t'(BEQ + k);
                if (br_taken[k] == 0) begin holes++; $display("  HOLE: %s never taken", o.name()); end
                if (br_not[k]   == 0) begin holes++; $display("  HOLE: %s never not-taken", o.name()); end
            end
            if (back_br_taken == 0) begin holes++; $display("  HOLE: no backward branch taken"); end
            if (back_jal      == 0) begin holes++; $display("  HOLE: no backward JAL"); end
            if (jalr_odd_cnt  == 0) begin holes++; $display("  HOLE: no JALR with odd target (bit-0 masking untested)"); end
            if (rd0_writes    == 0) begin holes++; $display("  HOLE: no write attempt to x0"); end
            // every load/store flavour at every legal byte lane
            for (int k = LB; k <= SW; k++) begin
                o = op_t'(k);
                for (int l = 0; l < 4; l++) begin
                    bit legal = (o == LB || o == LBU || o == SB) ? 1 :
                                (o == LH || o == LHU || o == SH) ? (l % 2 == 0) : (l == 0);
                    if (legal && lane_cov[k][l] == 0) begin
                        holes++; $display("  HOLE: %s never executed at byte lane %0d", o.name(), l);
                    end
                end
            end
            begin
                int hit = 0;
                for (int k = 0; k < NUM_OPS; k++) if (op_count[k] != 0) hit++;
                $display("  instructions executed: %0d   opcodes hit: %0d/%0d", cycles, hit, NUM_OPS);
            end
            $display("  branches taken/not-taken : BEQ %0d/%0d BNE %0d/%0d BLT %0d/%0d BGE %0d/%0d BLTU %0d/%0d BGEU %0d/%0d",
                     br_taken[0], br_not[0], br_taken[1], br_not[1], br_taken[2], br_not[2],
                     br_taken[3], br_not[3], br_taken[4], br_not[4], br_taken[5], br_not[5]);
            $display("  backward branches taken  : %0d   backward JAL: %0d   JALR odd targets: %0d   x0 write attempts: %0d",
                     back_br_taken, back_jal, jalr_odd_cnt, rd0_writes);
            if (holes != 0) $fatal(1, "STIMULUS COVERAGE HOLES: %0d (try another +seed or larger +n)", holes);
        end

        $display("");
        $display("PASS: %0d checks, %0d errors, %0d instructions, all 37 opcodes covered", sb.checks, sb.errors, cycles);
        $finish;
    end
endmodule