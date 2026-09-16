# Synthesize the pipelined integer multiplier once at a configured period.
#
# Run through synth/run_genus_imul_fixed_timing.sh.  Set LIB_FILES and,
# optionally, IMUL_CLOCK_PERIOD_NS in synth/genus_config.tcl.  Unlike the
# binary-search flow, this script runs syn_generic/syn_map/syn_opt once.

if {[info exists ::env(GENUS_PROJECT_ROOT)]} {
    set root_dir [file normalize $::env(GENUS_PROJECT_ROOT)]
    set script_dir [file join $root_dir synth]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    if {![file isfile [file join $script_dir imul_timing_wrapper.sv]] &&
        [file isfile [file join $script_dir synth imul_timing_wrapper.sv]]} {
        set script_dir [file join $script_dir synth]
    }
    set root_dir [file dirname $script_dir]
}

set TOP                 imul_timing_wrapper
set IMUL_CLOCK_PERIOD_NS 1.000
set CONSTRAINTS_FILE    [file join $script_dir imul_timing_constraints.sdc]
set MAX_TIMING_PATHS    100
set out_dir             [file join $root_dir build genus imul_fixed_timing]

# Read the normal local config for LIB_FILES and this flow's period override.
# Restore the top and constraints so core-specific overrides cannot change the
# multiplier harness.
set local_config [file join $script_dir genus_config.tcl]
if {[file exists $local_config]} {
    puts "INFO: reading local Genus configuration: $local_config"
    source $local_config
}
set TOP              imul_timing_wrapper
set CONSTRAINTS_FILE [file join $script_dir imul_timing_constraints.sdc]
set CLOCK_PERIOD_NS  $IMUL_CLOCK_PERIOD_NS

if {![info exists LIB_FILES]} {
    if {[info exists ::env(GENUS_LIB_FILES)]} {
        set LIB_FILES $::env(GENUS_LIB_FILES)
    } else {
        error "Set GENUS_LIB_FILES to a Tcl list of Liberty files, or create synth/genus_config.tcl from genus_config.tcl.example."
    }
}
if {[llength $LIB_FILES] == 0} {
    error "LIB_FILES is empty."
}
foreach lib $LIB_FILES {
    if {![file isfile $lib]} {
        error "Liberty file does not exist: $lib"
    }
}
if {$CLOCK_PERIOD_NS <= 0.0} {
    error "IMUL_CLOCK_PERIOD_NS must be positive."
}

set imul_sources [list \
    [file join $root_dir rtl riscv.svh] \
    [file join $root_dir rtl backend imul imul_pkg.svh] \
    [file join $root_dir rtl backend imul booth_partial_products.sv] \
    [file join $root_dir rtl backend imul dadda_stage.sv] \
    [file join $root_dir rtl backend imul imul.sv] \
    [file join $script_dir imul_timing_wrapper.sv] \
]
foreach source $imul_sources {
    if {![file isfile $source]} {
        error "Multiplier timing source does not exist: $source"
    }
}

file mkdir $out_dir
set_db library         $LIB_FILES
set_db hdl_search_path [list [file join $root_dir rtl]]
set_db information_level 5

read_hdl -sv $imul_sources
elaborate $TOP
check_design -unresolved
read_sdc $CONSTRAINTS_FILE
check_timing_intent

# This is intentionally the sole implementation pass in this flow.
syn_generic
syn_map
syn_opt

# The default report_timing mode is the setup/late report and is compatible
# with the repository's older Genus release, which does not accept -late.
report_qor                                              > [file join $out_dir qor_timing.rpt]
report_timing -max_paths $MAX_TIMING_PATHS              > [file join $out_dir timing_all_reg_to_reg.rpt]
# Scope reports by their capture-register bank, rather than internal instance
# names.  These are the actual pipeline boundaries and remain named after
# Genus flattens the combinational hierarchy.
report_timing -to [get_cells stage1_q_reg*] -max_paths 20 > [file join $out_dir timing_cycle1.rpt]
report_timing -to [get_cells stage2_q_reg*] -max_paths 20 > [file join $out_dir timing_cycle2.rpt]
report_timing -to [get_cells stage3_q_reg*] -max_paths 20 > [file join $out_dir timing_cycle3.rpt]
report_area                                             > [file join $out_dir area.rpt]
report_gates                                            > [file join $out_dir gates.rpt]
report_power                                            > [file join $out_dir power.rpt]

write_hdl > [file join $out_dir ${TOP}_mapped.v]
write_sdc > [file join $out_dir ${TOP}_mapped.sdc]

set summary_fh [open [file join $out_dir timing_summary.rpt] w]
puts $summary_fh "Top: $TOP"
puts $summary_fh [format "Target clock period: %.6f ns" $CLOCK_PERIOD_NS]
puts $summary_fh [format "Target clock frequency: %.3f MHz" [expr {1000.0 / $CLOCK_PERIOD_NS}]]
puts $summary_fh "Overall setup paths: timing_all_reg_to_reg.rpt"
puts $summary_fh "Stage setup paths: timing_cycle1.rpt, timing_cycle2.rpt, timing_cycle3.rpt"
puts $summary_fh "QoR: qor_timing.rpt"
close $summary_fh

puts [format "INFO: fixed-period multiplier synthesis completed at %.6f ns (%.3f MHz)." $CLOCK_PERIOD_NS [expr {1000.0 / $CLOCK_PERIOD_NS}]]
puts "INFO: results are in $out_dir"
exit
