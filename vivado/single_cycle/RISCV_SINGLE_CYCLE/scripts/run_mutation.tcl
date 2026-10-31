# =============================================================================
# run_mutation.tcl - mutation test of the CPU testbench (Vivado xsim)
#
# Idea: break the RTL on purpose, one small change at a time, and check that the
# regression FAILS. A mutant that still passes is either a hole in the testbench
# or an "equivalent" change (same behaviour). Every mutant below is labelled
#   KILL  = the testbench should catch it
#   EQUIV = behaviour is identical (redundant logic), the testbench should NOT care
#
# SAFETY - read before running
#   * Run on a COPY of the project (File > Save Project As...) with git committed.
#   * Close open source-editor tabs (Vivado may pop up "file changed on disk").
#   * Each source file is backed up to mutation_<timestamp>/orig/ and restored,
#     then verified byte-for-byte, after every mutant. If the script dies mid-
#     mutant it leaves an IN_PROGRESS marker; the next run refuses to start until
#     you restore the files from orig/ and delete that marker.
#   * A mutation is applied only if its text is found EXACTLY ONCE in the file.
#
# Usage : source {<path>/run_mutation.tcl}
# Output: mutation_<timestamp>/summary.log  + one simulate log per run
# =============================================================================

# ---------------- configuration ----------------
set script_dir [file dirname [file normalize [info script]]]
set proj_file [file normalize [file join $script_dir .. RISCV_SINGLE_CYCLE RISCV_SINGLE_CYCLE.xpr]]

set kill_runs  {{300 1} {1000 2}}   ;# {n_random seed} pairs; a mutant must be caught by one of them
set only_ids   {}                   ;# e.g. {A01 P05} to run a subset; empty = all mutants
set exit_when_done 0                ;# 1 = exit with 0/1 at the end (batch only)

# ---------------- location, safety check, logging ----------------
set script_path [info script]
if {$script_path eq ""} {
    set script_dir [pwd]
} else {
    set script_dir [file dirname [file normalize $script_path]]
}

set stale [glob -nocomplain -directory $script_dir mutation_*/IN_PROGRESS]
if {[llength $stale] > 0} {
    puts "ERROR: an earlier mutation run did not finish - a source file may still be mutated."
    foreach s $stale { puts "  marker: $s   originals: [file dirname $s]/orig" }
    return -code error "restore the originals, delete the IN_PROGRESS marker, then re-run"
}

set run_dir "$script_dir/mutation_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
file mkdir "$run_dir/orig"
set sumf [open "$run_dir/summary.log" w]

proc logmsg {msg} {
    global sumf
    puts $msg
    puts $sumf $msg
    flush $sumf
}

# ---------------- helpers ----------------
proc read_text {path} {
    set fh [open $path r]
    fconfigure $fh -translation binary
    set d [read $fh]
    close $fh
    return $d
}

proc write_text {path data} {
    set fh [open $path w]
    fconfigure $fh -translation binary
    puts -nonewline $fh $data
    close $fh
}

proc count_sub {text sub} {
    set c 0
    set i 0
    while {1} {
        set i [string first $sub $text $i]
        if {$i < 0} { break }
        incr c
        incr i [string length $sub]
    }
    return $c
}

# one simulation; returns {PASS|FAIL|INVALID detail}
proc run_one {n seed copy_to} {
    global log_file
    catch {file delete -force $log_file}
    set_property -name {xsim.simulate.xsim.more_options} \
                 -value "-testplusarg n=$n -testplusarg seed=$seed" \
                 -objects [get_filesets sim_1]
    if {[catch {launch_simulation -simset sim_1 -mode behavioral} err]} {
        catch {close_sim}
        set err [string map [list "\n" " "] $err]
        return [list INVALID "compile/launch error: [string range $err 0 150]"]
    }
    catch {run all}
    catch {close_sim}
    if {![file exists $log_file]} { return [list INVALID "no simulate.log produced"] }
    set txt [read_text $log_file]
    catch {file copy -force $log_file $copy_to}
    if {[regexp -line {^.*(?:Fatal:|FATAL_ERROR|ERROR:).*$} $txt first]} {
        return [list FAIL [string range [string trim $first] 0 140]]
    }
    if {[regexp {PASS: ([0-9]+) checks, ([0-9]+) errors} $txt -> c e] && $e == 0 && $c > 0} {
        return [list PASS "$c checks"]
    }
    return [list FAIL "no PASS summary line (timeout or crash)"]
}

# ---------------- project ----------------
set opened_here 0
if {[current_project -quiet] eq ""} {
    open_project $proj_file
    set opened_here 1
}
catch {close_sim}
set proj_dir  [get_property DIRECTORY [current_project]]
set proj_name [get_property NAME [current_project]]
set log_file  "$proj_dir/$proj_name.sim/sim_1/behav/xsim/simulate.log"

array set src_path {}
foreach f [get_files -quiet] {
    set t [file tail $f]
    if {![info exists src_path($t)]} { set src_path($t) $f }
}

# ---------------- mutant list: mut <id> <file> <old text> <new text> <KILL|EQUIV> <description> ----------------
set mutants {}
proc mut {id file old new expect desc} {
    global mutants
    lappend mutants [list $id $file $old $new $expect $desc]
}
mut A01 alu.v {result = $signed(A) >>> B[4:0];} {result = A >> B[4:0];} KILL {SRA acts as logical shift}
mut A02 alu.v {result = A << B[4:0];} {result = A << B;} KILL {SLL uses all 32 bits of rs2}
mut A03 alu.v {result = ($signed(A) < $signed(B)) ? 32'd1} {result = (A < B) ? 32'd1} KILL {SLT compares unsigned}
mut A04 alu.v {result = (A < B) ? 32'd1} {result = ($signed(A) < $signed(B)) ? 32'd1} KILL {SLTU compares signed}
mut A05 alu.v {result = A - B;} {result = A + B;} KILL {SUB acts as ADD}
mut R01 reg_file.v {if (write_enable && write_addr != 0) begin} {if (write_enable) begin} KILL {x0 is writable}
mut R02 reg_file.v {assign read_data1 = (read_addr1 == 0) ? 32'b0 : registers[read_addr1];} {assign read_data1 = registers[read_addr1];} EQUIV {x0 read mask removed (redundant: x0 write already blocked)}
mut R03 reg_file.v {: registers[read_addr2];} {: registers[read_addr1];} KILL {read port 2 reads rs1}
mut R04 reg_file.v {if (write_enable && write_addr != 0) begin} {if (write_addr != 0) begin} KILL {register write ignores regWrite}
mut I01 immediate_generator.v {{{20{instruction[31]}}, instruction[31:20]}; // I-type} {{20'b0, instruction[31:20]}; // I-type} KILL {I-immediate not sign-extended}
mut I02 immediate_generator.v {instruction[7],} {instruction[8],} KILL {B-type imm[11] wired from wrong bit (long branches)}
mut I03 immediate_generator.v {instruction[19:12],} {instruction[18:11],} KILL {JAL imm[19:12] mis-wired (far jumps)}
mut I04 immediate_generator.v {instruction[11:7]} {{instruction[11:8], 1'b0}} KILL {S-type imm[0] forced to 0 (odd store offsets)}
mut I05 immediate_generator.v {immediate = {instruction[31:12], 12'b0}; // LUI} {immediate = {instruction[31:12], 12'b1}; // LUI} KILL {LUI low bit set}
mut I06 immediate_generator.v {instruction[20],} {instruction[21],} KILL {JAL imm[11] wired from wrong bit}
mut D01 data_memory.v {& 32'hFF00FFFF)} {& 32'hFF000000)} KILL {SB lane 2 clobbers lower bytes}
mut D02 data_memory.v {else if(half_position == 2'b10) begin} {else if(half_position == 2'b11) begin} KILL {SH upper half never written}
mut D03 data_memory.v {data_memory[data_mem_address >> 2] <= write_data;} {data_memory[(data_mem_address >> 2) + 1] <= write_data;} KILL {SW writes the next word}
mut D04 data_memory.v {assign read_data = mem_read ? data_memory[data_mem_address >> 2] : 32'b0;} {assign read_data = data_memory[data_mem_address >> 2];} EQUIV {read gating removed (read data only used by loads)}
mut D05 data_memory.v {& 32'hFFFF00FF} {& 32'hFFFFFFFF} KILL {SB lane 1 does not clear the old byte}
mut L01 load_data_unit.v {{{24{read_data[15]}} , read_data[15:8]}} {{{24{read_data[7]}} , read_data[15:8]}} KILL {LB lane 1 sign bit from wrong byte}
mut L02 load_data_unit.v {{24'b0 , read_data[31:24]}} {{24'b0 , read_data[23:16]}} KILL {LBU lane 3 reads lane 2}
mut L03 load_data_unit.v {{16'b0 , read_data[15:0]}} {{{16{read_data[15]}} , read_data[15:0]}} KILL {LHU sign-extends}
mut L04 load_data_unit.v {{{16{read_data[31]}} , read_data[31:16]}} {{16'b0 , read_data[31:16]}} KILL {LH upper half zero-extends}
mut C01 control_unit.v {10'b0100000_101: alu_control = 4'b0111;} {10'b0100000_101: alu_control = 4'b0110;} KILL {SRA decoded as SRL}
mut C02 control_unit.v {alu_control = 4'b0111; // SRAI} {alu_control = 4'b0110; // SRAI} KILL {SRAI decoded as SRLI}
mut C03 control_unit.v {10'b0100000_000: alu_control = 4'b0001;} {10'b0100000_000: alu_control = 4'b0000;} KILL {SUB decoded as ADD}
mut C04 control_unit.v {data_size = 2'b10; // word} {data_size = 2'b01; // word} KILL {SW reports halfword size}
mut C05 control_unit.v {auipc = 1; // alu_a = pc} {auipc = 0; // alu_a = pc} EQUIV {JAL no longer sets auipc (CPU also ORs in jal)}
mut C06 control_unit.v {alu_control = 4'b1010;} {alu_control = 4'b0000;} KILL {LUI does rs1+imm instead of imm}
mut P01 cpu.v {signs_differ ? cmp_b[31]} {signs_differ ? cmp_a[31]} KILL {BLTU/BGEU sign logic wrong}
mut P02 cpu.v {signs_differ ? cmp_a[31]} {signs_differ ? cmp_b[31]} KILL {BLT/BGE sign logic wrong}
mut P03 cpu.v {wire branch_condition = cmp_out ^ funct3[0];} {wire branch_condition = cmp_out;} KILL {BNE/BGE/BGEU not inverted}
mut P04 cpu.v {cmp_out = ult;} {cmp_out = slt;} KILL {BLTU/BGEU use signed compare}
mut P05 cpu.v {32'hFFFFFFFE} {32'hFFFFFFFF} KILL {JALR does not clear bit 0}
mut P06 cpu.v {branch_target = pc + immediate} {branch_target = pc_plus_4 + immediate} KILL {branch target relative to pc+4}
mut P07 cpu.v {write_back_data = pc_plus_4;} {write_back_data = pc + 32'd8;} KILL {JAL/JALR link value wrong}
mut P08 cpu.v {dmem_wd = rs2_data} {dmem_wd = rs1_data} KILL {store data taken from rs1}
mut P09 cpu.v {dmem_addr = alu_result} {dmem_addr = alu_result + 32'd4} KILL {data address off by one word}
mut P10 cpu.v {~|(cmp_a ^ cmp_b)} {~&(cmp_a ^ cmp_b)} KILL {equality comparator wrong}

# ---------------- baseline: the unmodified design must pass, or nothing below means anything ----------------
logmsg "Mutation test started [clock format [clock seconds]]"
logmsg "Project: $proj_file"
logmsg "Detection runs per mutant: $kill_runs"
logmsg ""
logmsg "== Baseline (unmodified design) =="
foreach r $kill_runs {
    lassign $r n seed
    lassign [run_one $n $seed "$run_dir/baseline_n${n}_seed${seed}.log"] res det
    logmsg "  n=$n seed=$seed : $res ($det)"
    if {$res ne "PASS"} {
        close $sumf
        return -code error "baseline does not pass - fix the design/testbench first"
    }
}

# ---------------- mutation loop ----------------
set results {}
set t_start [clock seconds]
foreach m $mutants {
    lassign $m id file old new expect desc
    if {[llength $only_ids] > 0 && [lsearch -exact $only_ids $id] < 0} { continue }
    logmsg ""
    logmsg "== $id  ($file)  $desc  (expect: $expect) =="

    set outcome ""
    set detail  ""

    if {![info exists src_path($file)]} {
        set outcome NOT_APPLIED
        set detail  "file $file not found in the project"
    } else {
        set path $src_path($file)
        set orig [read_text $path]
        set cnt  [count_sub $orig $old]
        if {$cnt != 1} {
            set outcome NOT_APPLIED
            set detail  "pattern found $cnt times (need exactly 1) in $path"
        } else {
            write_text "$run_dir/orig/$file" $orig
            write_text "$run_dir/IN_PROGRESS" "$path\n"
            set i [string first $old $orig]
            set mutated [string replace $orig $i [expr {$i + [string length $old] - 1}] $new]
            write_text $path $mutated

            set outcome SURVIVED
            set err [catch {
                foreach r $kill_runs {
                    lassign $r n seed
                    lassign [run_one $n $seed "$run_dir/mut_${id}_n${n}_seed${seed}.log"] res det
                    logmsg "   run n=$n seed=$seed : $res"
                    if {$res eq "FAIL"}    { set outcome KILLED;  set detail $det; break }
                    if {$res eq "INVALID"} { set outcome INVALID; set detail $det; break }
                }
            } emsg]

            # always restore, then prove it
            write_text $path $orig
            if {[read_text $path] ne $orig} {
                logmsg "!!! RESTORE FAILED for $path - originals are in $run_dir/orig"
                close $sumf
                return -code error "restore failed"
            }
            file delete -force "$run_dir/IN_PROGRESS"
            if {$err} { set outcome ERROR; set detail $emsg }
        }
    }

    switch -- $outcome {
        KILLED {
            if {$expect eq "KILL"} { set verdict ok } else { set verdict "NOTE: expected equivalent but it was caught" }
        }
        SURVIVED {
            if {$expect eq "EQUIV"} { set verdict "ok (equivalent mutant)" } else { set verdict "!! SURVIVED - testbench hole" }
        }
        INVALID     { set verdict "mutant did not compile - fix the mutation text" }
        NOT_APPLIED { set verdict "not applied - fix the pattern" }
        default     { set verdict "script error" }
    }
    logmsg "   -> $outcome   $verdict"
    if {$detail ne ""} { logmsg "      $detail" }
    lappend results [list $id $file $desc $expect $outcome $verdict $detail]
}

# ---------------- final sanity: the restored design must pass again ----------------
logmsg ""
logmsg "== Post-restore sanity run =="
set r [lindex $kill_runs 0]
lassign $r n seed
lassign [run_one $n $seed "$run_dir/post_restore.log"] res det
logmsg "  n=$n seed=$seed : $res ($det)"
set restore_ok [expr {$res eq "PASS"}]

# ---------------- report ----------------
set killed 0; set survivors 0; set equiv_ok 0; set bad 0
logmsg ""
logmsg "======================== MUTATION REPORT ========================"
foreach x $results {
    lassign $x id file desc expect outcome verdict detail
    logmsg [format "%-4s %-24s %-11s %s" $id $file $outcome $verdict]
    switch -- $outcome {
        KILLED   { if {$expect eq "KILL"} { incr killed } }
        SURVIVED { if {$expect eq "EQUIV"} { incr equiv_ok } else { incr survivors } }
        default  { incr bad }
    }
}
set denom [expr {$killed + $survivors}]
logmsg "-----------------------------------------------------------------"
logmsg "Killed: $killed   Unexpected survivors: $survivors   Equivalent (fine): $equiv_ok   Invalid/not applied/error: $bad"
if {$denom > 0} {
    logmsg [format "Mutation score: %d/%d = %.0f%%   (%d s)" $killed $denom \
            [expr {100.0 * $killed / $denom}] [expr {[clock seconds] - $t_start}]]
}
if {!$restore_ok} { logmsg "!!! post-restore run did NOT pass - check the sources against $run_dir/orig" }
logmsg "Logs: $run_dir"
logmsg "================================================================="
close $sumf

if {$opened_here} { catch {close_project} }
if {$exit_when_done} { exit [expr {$survivors > 0 || $bad > 0 || !$restore_ok}] }