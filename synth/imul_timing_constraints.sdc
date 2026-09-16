# Timing constraints for synth/imul_timing_wrapper.sv.
#
# The wrapper has flops before and after every multiplier stage.  Its external
# ports are intentionally excluded so the reports contain only the three
# internal register-to-register multiplier paths.

if {![info exists CLOCK_PERIOD_NS]} {
    set CLOCK_PERIOD_NS 1.000
}

create_clock -name imul_clk -period $CLOCK_PERIOD_NS [get_ports clk]
set_clock_uncertainty 0.050 [get_clocks imul_clk]
set_clock_transition  0.050 [get_clocks imul_clk]

set non_clock_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_false_path -from $non_clock_inputs
set_false_path -to [all_outputs]
