# Binary-search the maximum closing frequency of one imul pipeline stage.
# IMUL_TIMING_STAGE must be cycle1, cycle2, or cycle3; the shell launchers set
# it automatically.  Every run has its own stage/timestamp/PID result tree.

if {[info exists ::env(GENUS_PROJECT_ROOT)]} {
    set root_dir [file normalize $::env(GENUS_PROJECT_ROOT)]
    set script_dir [file join $root_dir synth]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    if {![file isfile [file join $script_dir imul_stage_timing_wrappers.sv]] &&
        [file isfile [file join $script_dir synth imul_stage_timing_wrappers.sv]]} {
        set script_dir [file join $script_dir synth]
    }
    set root_dir [file dirname $script_dir]
}

if {![info exists ::env(IMUL_TIMING_STAGE)]} {
    error "Set IMUL_TIMING_STAGE to cycle1, cycle2, or cycle3; use one of the synth/run_genus_imul_cycle*_max_freq.sh launchers."
}
set stage $::env(IMUL_TIMING_STAGE)
switch -- $stage {
    cycle1 { set TOP imul_cycle1_timing_wrapper }
    cycle2 { set TOP imul_cycle2_timing_wrapper }
    cycle3 { set TOP imul_cycle3_timing_wrapper }
    default { error "IMUL_TIMING_STAGE must be cycle1, cycle2, or cycle3, not '$stage'." }
}

set SEARCH_MIN_PERIOD_NS 0.100
set SEARCH_MAX_PERIOD_NS 10.000
set SEARCH_RESOLUTION_NS 0.005
set MAX_TIMING_PATHS 100
set CONSTRAINTS_FILE [file join $script_dir imul_timing_constraints.sdc]

set local_config [file join $script_dir genus_config.tcl]
if {[file exists $local_config]} {
    puts "INFO: reading local Genus configuration: $local_config"
    source $local_config
}
# Do not permit core config overrides to change this stage-specific top/SDC.
switch -- $stage {
    cycle1 { set TOP imul_cycle1_timing_wrapper }
    cycle2 { set TOP imul_cycle2_timing_wrapper }
    cycle3 { set TOP imul_cycle3_timing_wrapper }
}
set CONSTRAINTS_FILE [file join $script_dir imul_timing_constraints.sdc]

if {![info exists LIB_FILES]} {
    if {[info exists ::env(GENUS_LIB_FILES)]} {
        set LIB_FILES $::env(GENUS_LIB_FILES)
    } else {
        error "Set GENUS_LIB_FILES to a Tcl list of Liberty files, or create synth/genus_config.tcl from genus_config.tcl.example."
    }
}
if {[llength $LIB_FILES] == 0} { error "LIB_FILES is empty." }
foreach lib $LIB_FILES {
    if {![file isfile $lib]} { error "Liberty file does not exist: $lib" }
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
    [file join $script_dir imul_stage_timing_wrappers.sv] \
]
foreach source $imul_sources {
    if {![file isfile $source]} { error "Multiplier timing source does not exist: $source" }
}

# pid prevents same-second parallel invocations from sharing any artifact.
set run_tag "[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]_[pid]"
set results_root [file join $root_dir build genus imul_stage_max_frequency $stage run_$run_tag]
if {[file exists $results_root]} { error "Refusing to overwrite existing result directory: $results_root" }
file mkdir $results_root

set_db library         $LIB_FILES
set_db hdl_search_path [list [file join $root_dir rtl]]
set_db information_level 5

set elaborated_db [file join $results_root elaborated.db]
set search_report [file join $results_root search.rpt]
set search_fh [open $search_report w]
puts $search_fh "# period_ns wns_ns setup_closed"

read_hdl -sv $imul_sources
elaborate $TOP
check_design -unresolved
write_db -to_file $elaborated_db

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
    global CLOCK_PERIOD_NS elaborated_db results_root stage
    reset_design
    read_db $elaborated_db
    set CLOCK_PERIOD_NS $period_ns
    read_sdc $constraints_file
    check_timing_intent
    syn_generic
    syn_map
    syn_opt

    set timing_report [file join $results_root trial_setup_timing.rpt]
    # Default report_timing is the setup report in Genus 18.14.
    report_timing -max_paths 1 > $timing_report
    set wns [reported_setup_wns $timing_report]
    file delete -force $timing_report
    set closed [expr {$wns >= 0.0}]
    puts $search_fh [format "%.6f %.6f %s" $period_ns $wns $closed]
    flush $search_fh
    puts [format "INFO: %s trial %.6f ns: WNS %.6f ns (%s)" $stage $period_ns $wns [expr {$closed ? "closed" : "failed"}]]
    return $wns
}

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
    } else {
        set fast_period $trial_period
    }
}
close $search_fh

set best_period_ns $slow_period
set best_freq_mhz [expr {1000.0 / $best_period_ns}]
set final_wns [run_setup_trial $best_period_ns $CONSTRAINTS_FILE stdout]
if {$final_wns < 0.0} {
    error "Winning candidate no longer closes during final rebuild (WNS ${final_wns} ns)."
}

report_qor                                 > [file join $results_root qor.rpt]
report_timing -max_paths $MAX_TIMING_PATHS > [file join $results_root timing_setup_longest_paths.rpt]
check_timing_intent                        > [file join $results_root timing_intent.rpt]
report_area                                > [file join $results_root area.rpt]
report_power                               > [file join $results_root power.rpt]
report_gates                               > [file join $results_root gates.rpt]
write_hdl                                  > [file join $results_root ${TOP}_mapped.v]
write_sdc                                  > [file join $results_root ${TOP}_mapped.sdc]
file delete -force $elaborated_db

set summary_fh [open [file join $results_root max_frequency_summary.rpt] w]
puts $summary_fh "Stage: $stage"
puts $summary_fh "Top: $TOP"
puts $summary_fh [format "Best closing period: %.6f ns" $best_period_ns]
puts $summary_fh [format "Maximum closing frequency: %.3f MHz" $best_freq_mhz]
puts $summary_fh [format "Final setup WNS: %.6f ns" $final_wns]
puts $summary_fh [format "Search resolution: %.6f ns" $SEARCH_RESOLUTION_NS]
puts $summary_fh "Trial log: search.rpt"
puts $summary_fh "Longest setup paths: timing_setup_longest_paths.rpt"
close $summary_fh

puts [format "INFO: %s maximum closing frequency: %.3f MHz (%.6f ns)" $stage $best_freq_mhz $best_period_ns]
puts "INFO: results are in $results_root"
exit
