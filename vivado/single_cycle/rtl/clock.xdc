# ============================================================
# Minimal timing constraint for the pipelined CPU (top module: CPU)
#
# Without this, Vivado will synthesize/implement with no target clock
# period, so the timing report is meaningless (no setup/hold slack to
# measure against). This defines a 100 MHz clock on `clk`; lower it
# (larger period) if the design doesn't close timing at 100 MHz, or
# raise it once you start optimizing and want to push the Fmax.
#
# `reset` has no timing-critical path of its own (it's a plain
# synchronous reset sampled on clk), so no separate constraint is
# needed for it.
# ============================================================

create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
