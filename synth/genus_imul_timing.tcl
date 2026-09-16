# Find the highest timing-closing frequency of the pipelined integer multiplier.
#
# Example:
#   export GENUS_LIB_FILES="/path/to/standard_cells_ss.lib"
#   genus -files synth/genus_imul_timing.tcl |& tee build/genus/imul_timing.log
#
# The search bounds and resolution use the same SEARCH_* variables as
# genus_max_freq.tcl.  The output reports are in build/genus/imul_timing/.

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

set TOP              imul_timing_wrapper
set SEARCH_MIN_PERIOD_NS 0.100
set SEARCH_MAX_PERIOD_NS 10.000
set SEARCH_RESOLUTION_NS 0.005
set MAX_TIMING_PATHS 100
set CONSTRAINTS_FILE [file join $script_dir imul_timing_constraints.sdc]
set out_dir          [file join $root_dir build genus imul_timing]

# Reuse the normal local configuration solely for LIB_FILES.  Restore this
# flow's top and constraints afterwards so core-specific overrides cannot
# accidentally alter the harness.
set local_config [file join $script_dir genus_config.tcl]
if {[file exists $local_config]} {
    puts "INFO: reading local Genus configuration: $local_config"
    source $local_config
}
set TOP              imul_timing_wrapper
set CONSTRAINTS_FILE [file join $script_dir imul_timing_constraints.sdc]

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
if {$SEARCH_MIN_PERIOD_NS <= 0.0 || $SEARCH_MAX_PERIOD_NS <= 0.0 ||
    $SEARCH_MIN_PERIOD_NS >= $SEARCH_MAX_PERIOD_NS || $SEARCH_RESOLUTION_NS <= 0.0} {
    error "Require 0 < SEARCH_MIN_PERIOD_NS < SEARCH_MAX_PERIOD_NS and SEARCH_RESOLUTION_NS > 0."
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

# Elaborate once, then restore this pre-SDC database for every candidate.  A
# trial is consequently optimized for its own period rather than inheriting a
# mapped netlist from the preceding candidate.
set run_tag [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set elaborated_db [file join $out_dir elaborated_${run_tag}.db]
set search_report [file join $out_dir search_${run_tag}.rpt]
set search_fh [open $search_report w]
puts $search_fh "# period_ns wns_ns setup_closed"

read_hdl -sv $imul_sources
elaborate $TOP
check_design -unresolved
write_db -to_file $elaborated_db

# Genus 18.14 Common UI lacks get_timing_paths.  Parse the one-path setup
# report instead; retain the report if this Genus release changes its format.
proc reported_setup_wns {timing_report} {
    set fh [open $timing_report r]
    set found 0
    set wns 0.0
    while {[gets $fh line] >= 0} {
        if {[regexp -nocase {slack[^0-9+\-]*([-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)} $line -> value]} {
            set wns $value
            set found 1
        }
    }
    close $fh
    if {!$found} {
        error "Could not find setup slack in $timing_report. Inspect that report and update reported_setup_wns if this Genus version uses a different format."
    }
    return $wns
}

proc run_setup_trial {period_ns constraints_file search_fh} {
    global CLOCK_PERIOD_NS elaborated_db out_dir

    reset_design
    read_db $elaborated_db
    set CLOCK_PERIOD_NS $period_ns
    read_sdc $constraints_file
    check_timing_intent
    syn_generic
    syn_map
    syn_opt

    set timing_report [file join $out_dir trial_setup_timing.rpt]
    # The default report is the late/setup report.  Do not pass -late here:
    # older Genus Common UI releases (including 18.1x) do not implement that
    # option even though newer releases do.
    report_timing -max_paths 1 > $timing_report
    set wns [reported_setup_wns $timing_report]
    file delete -force $timing_report
    set closed [expr {$wns >= 0.0}]
    puts $search_fh [format "%.6f %.6f %s" $period_ns $wns $closed]
    flush $search_fh
    puts [format "INFO: multiplier trial %.6f ns: WNS %.6f ns (%s)" $period_ns $wns [expr {$closed ? "closed" : "failed"}]]
    return $wns
}

# A valid binary-search bracket requires a closing slow period and a failing
# fast period.  Do not infer a bound from WNS: synthesis is rerun for each
# candidate and the I/O-independent internal paths can change with mapping.
set slow_period $SEARCH_MAX_PERIOD_NS
set slow_wns [run_setup_trial $slow_period $CONSTRAINTS_FILE $search_fh]
if {$slow_wns < 0.0} {
    close $search_fh
    error "Timing does not close at SEARCH_MAX_PERIOD_NS=${SEARCH_MAX_PERIOD_NS} ns; increase the maximum period."
}

set fast_period $SEARCH_MIN_PERIOD_NS
set fast_wns [run_setup_trial $fast_period $CONSTRAINTS_FILE $search_fh]
if {$fast_wns >= 0.0} {
    close $search_fh
    error "Timing closes at SEARCH_MIN_PERIOD_NS=${SEARCH_MIN_PERIOD_NS} ns; decrease the minimum period to bound the maximum frequency."
}

while {[expr {$slow_period - $fast_period}] > $SEARCH_RESOLUTION_NS} {
    set trial_period [expr {($slow_period + $fast_period) / 2.0}]
    set trial_wns [run_setup_trial $trial_period $CONSTRAINTS_FILE $search_fh]
    if {$trial_wns >= 0.0} {
        set slow_period $trial_period
        set slow_wns $trial_wns
    } else {
        set fast_period $trial_period
    }
}
close $search_fh

# Rebuild the winning candidate and retain its detailed reports.  The final
# stage reports are the balance check; compare data-arrival times or slack.
set best_period_ns $slow_period
set best_freq_mhz [expr {1000.0 / $best_period_ns}]
set final_wns [run_setup_trial $best_period_ns $CONSTRAINTS_FILE stdout]
if {$final_wns < 0.0} {
    error "Winning candidate no longer closes during final rebuild (WNS ${final_wns} ns)."
}

report_qor                                              > [file join $out_dir qor_timing.rpt]
report_timing -max_paths $MAX_TIMING_PATHS              > [file join $out_dir timing_all_reg_to_reg.rpt]
# Genus 18.14 flattens the RTL instances, but keeps their names as prefixes on
# mapped cells.  Select those cells rather than the removed hierarchy instance.
report_timing -through [get_cells *u_imul_cycle1*] -max_paths 20 > [file join $out_dir timing_cycle1.rpt]
report_timing -through [get_cells *u_imul_cycle2*] -max_paths 20 > [file join $out_dir timing_cycle2.rpt]
report_timing -through [get_cells *u_imul_cycle3*] -max_paths 20 > [file join $out_dir timing_cycle3.rpt]
report_area                                             > [file join $out_dir area.rpt]
report_gates                                            > [file join $out_dir gates.rpt]
report_msg -error                                       > [file join $out_dir errors.rpt]

write_hdl > [file join $out_dir ${TOP}_mapped.v]
write_sdc > [file join $out_dir ${TOP}_mapped.sdc]
file delete -force $elaborated_db

set summary_fh [open [file join $out_dir max_frequency_summary.rpt] w]
puts $summary_fh "Top: $TOP"
puts $summary_fh [format "Best closing period: %.6f ns" $best_period_ns]
puts $summary_fh [format "Maximum closing frequency: %.3f MHz" $best_freq_mhz]
puts $summary_fh [format "Final setup WNS: %.6f ns" $final_wns]
puts $summary_fh [format "Search resolution: %.6f ns" $SEARCH_RESOLUTION_NS]
puts $summary_fh "Trial log: $search_report"
puts $summary_fh "Stage timing: timing_cycle1.rpt, timing_cycle2.rpt, timing_cycle3.rpt"
close $summary_fh

puts [format "INFO: multiplier maximum closing frequency: %.3f MHz (%.6f ns)" $best_freq_mhz $best_period_ns]
puts "INFO: compare timing_cycle1.rpt, timing_cycle2.rpt, and timing_cycle3.rpt to assess pipeline balance."
puts "INFO: results are in $out_dir"
exit
