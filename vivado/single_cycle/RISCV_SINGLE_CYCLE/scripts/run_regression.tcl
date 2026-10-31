# =============================================================================
# run_regression.tcl - constrained-random regression for the RV32I CPU (xsim)
#
#   GUI Tcl console :  source {<path>/run_regression.tcl}
#   Batch / CI      :  vivado -mode batch -source run_regression.tcl
#                      (set exit_when_done 1 below so the exit code reflects PASS/FAIL)
#
# Output (next to this script):  regress_<timestamp>/summary.log
#                                regress_<timestamp>/sim_n<N>_seed<S>.log  (one per run)
# =============================================================================

# ---------------- configuration ----------------
set script_dir [file dirname [file normalize [info script]]]
set proj_file [file normalize [file join $script_dir .. RISCV_SINGLE_CYCLE RISCV_SINGLE_CYCLE.xpr]]

set test_sizes   {100 500 1000 2000 5000}
set num_seeds    3          ;# seeds 1..num_seeds are run for every size
set stop_on_fail 0           ;# 1 = stop at the first failing run
set exit_when_done 0         ;# 1 = call "exit 0/1" at the end (batch only; closes the GUI!)
set pass_pattern {PASS: ([0-9]+) checks, ([0-9]+) errors, ([0-9]+) instructions}

# ---------------- where am I / where do logs go ----------------
set script_path [info script]
if {$script_path eq ""} {
    set script_dir [pwd]
} else {
    set script_dir [file dirname [file normalize $script_path]]
}
set run_dir "$script_dir/regress_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
file mkdir $run_dir
set sumf [open "$run_dir/summary.log" w]

# print to the console AND to summary.log
proc logmsg {msg} {
    global sumf
    puts $msg
    puts $sumf $msg
    flush $sumf
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

set seeds {}
for {set s 1} {$s <= $num_seeds} {incr s} { lappend seeds $s }

set total   0
set failed  {}
set abort   0
set t_start [clock seconds]
array set prog_words {}      ;# prog_words(n,seed) = program size, to prove seeds differ

logmsg "Regression started [clock format $t_start]"
logmsg "Project : $proj_file"
logmsg "Sizes   : $test_sizes    Seeds: 1..$num_seeds"
logmsg ""

# ---------------- main loop ----------------
foreach n $test_sizes {
    foreach seed $seeds {
        incr total
        logmsg "----------------------------------------"
        logmsg "Run $total: n_random=$n seed=$seed"

        # a stale log from the previous run must never be mistaken for this run's result
        catch {file delete -force $log_file}

        set_property -name {xsim.simulate.xsim.more_options} \
                     -value "-testplusarg n=$n -testplusarg seed=$seed" \
                     -objects [get_filesets sim_1]

        set status FAIL
        set reason ""
        set words  "-"
        set instrs "-"
        set checks "-"

        if {[catch {launch_simulation -simset sim_1 -mode behavioral} lerr]} {
            set reason "launch_simulation failed: $lerr"
        } else {
            catch {run all}
        }
        catch {close_sim}

        # ---- judge the run from its own simulate.log ----
        set txt ""
        if {[file exists $log_file]} {
            set fh [open $log_file r]
            set txt [read $fh]
            close $fh
            file copy -force $log_file "$run_dir/sim_n${n}_seed${seed}.log"
        }

        if {$reason ne ""} {
            ;# launch already failed
        } elseif {$txt eq ""} {
            set reason "no simulate.log produced"
        } else {
            regexp {Program built: ([0-9]+) instructions} $txt -> words
            if {[regexp -line {^.*(?:Fatal:|FATAL_ERROR|ERROR:).*$} $txt first_err]} {
                set reason "error in log: [string trim $first_err]"
            } elseif {[string first "HOLE:" $txt] >= 0} {
                set reason "stimulus coverage holes reported"
            } elseif {![regexp $pass_pattern $txt -> checks errs instrs]} {
                set reason "no PASS summary line (timeout / crash / early finish)"
            } elseif {$errs != 0} {
                set reason "$errs checker errors"
            } elseif {$checks == 0 || $instrs == 0} {
                set reason "PASS line but nothing was checked"
            } else {
                set status PASS
            }
        }

        if {$words ne "-"} { set prog_words($n,$seed) $words }

        logmsg [format ">>> n=%-5s seed=%-3s %-4s  program=%s words  executed=%s  checks=%s" \
                       $n $seed $status $words $instrs $checks]
        if {$status ne "PASS"} {
            logmsg "    reason: $reason"
            logmsg "    log   : $run_dir/sim_n${n}_seed${seed}.log"
            lappend failed "n=$n seed=$seed"
            if {$stop_on_fail} { set abort 1; break }
        }
    }
    if {$abort} { break }
}

# ---------------- did different seeds really give different programs? ----------------
logmsg ""
logmsg "---- seed diversity check ----"
foreach n $test_sizes {
    set sizes {}
    foreach seed $seeds {
        if {[info exists prog_words($n,$seed)]} { lappend sizes $prog_words($n,$seed) }
    }
    if {[llength $sizes] > 1} {
        set uniq [llength [lsort -unique $sizes]]
        if {$uniq < [llength $sizes]} {
            logmsg "  WARNING n=$n: only $uniq distinct program sizes in [llength $sizes] runs (seeds may not be changing the program)"
        } else {
            logmsg "  n=$n: all [llength $sizes] programs differ"
        }
    }
}

# ---------------- verdict ----------------
set npass [expr {$total - [llength $failed]}]
logmsg ""
logmsg "========================================"
logmsg "Regression: $npass/$total passed   ([expr {[clock seconds] - $t_start}] s)"
if {[llength $failed]} {
    logmsg "FAILED RUNS: $failed"
    logmsg "Reproduce one with its plusargs, e.g.  -testplusarg n=<N> -testplusarg seed=<S> -testplusarg trace"
}
logmsg "Logs: $run_dir"
logmsg "========================================"
close $sumf

if {$opened_here} { catch {close_project} }
if {$exit_when_done} { exit [expr {[llength $failed] > 0}] }