# Default timing constraints for riscv_core.
# CLOCK_PERIOD_NS is supplied by synth/genus.tcl and may be overridden by a
# local genus_config.tcl.  The interface has no declared asynchronous clocks.

if {![info exists CLOCK_PERIOD_NS]} {
    set CLOCK_PERIOD_NS 1.000
}

set core_clock [get_ports clk]
create_clock -name core_clk -period $CLOCK_PERIOD_NS $core_clock
set_clock_uncertainty 0.050 [get_clocks core_clk]
set_clock_transition  0.050 [get_clocks core_clk]

# The external memory interface is synchronous to clk.  Use a conservative
# 20% of the cycle for board/SoC interface timing; replace these with the
# integration-level interface constraints when the core is instantiated.
set io_delay [expr {$CLOCK_PERIOD_NS * 0.20}]
set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  $io_delay -clock core_clk $data_inputs
set_output_delay $io_delay -clock core_clk [all_outputs]

# Reset is asynchronous assertion and is not a timed data path.
set_false_path -from [get_ports rst_n]
