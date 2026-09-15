# Find the highest clock frequency at which riscv_core closes setup timing.
#
# This script performs a binary search over clock *period*.  Each trial starts
# from elaborated RTL after reset_design, so its implementation is optimized for
# that candidate period rather than reusing the previous trial's mapped netlist.
# The final, timing-clean candidate is rebuilt into an output directory named
# for the achieved period and frequency.
#
# Example:
#   export GENUS_LIB_FILES="/path/to/standard_cells_ss.lib"
#   genus -files synth/genus_max_freq.tcl |& tee build/genus/max_freq.log

if {[info exists ::env(GENUS_PROJECT_ROOT)]} {
    set root_dir [file normalize $::env(GENUS_PROJECT_ROOT)]
    set script_dir [file join $root_dir synth]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    # Older Genus "-files" invocations can lose the synth/ component from
    # [info script]; recover it before looking up the local configuration.
    if {![file isfile [file join $script_dir constraints.sdc]] &&
        [file isfile [file join $script_dir synth constraints.sdc]]} {
        set script_dir [file join $script_dir synth]
    }
    set root_dir [file dirname $script_dir]
}

set TOP                    riscv_core
set CONSTRAINTS_FILE       [file join $script_dir constraints.sdc]
set SEARCH_MIN_PERIOD_NS   0.100
set SEARCH_MAX_PERIOD_NS   10.000
set SEARCH_RESOLUTION_NS   0.005
set MAX_TIMING_PATHS       100
set results_root           [file join $root_dir build genus max_frequency]

set local_config [file join $script_dir genus_config.tcl]
if {[file exists $local_config]} {
    puts "INFO: reading local Genus configuration: $local_config"
    source $local_config
}

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
if {![file isfile $CONSTRAINTS_FILE]} {
    error "Constraints file does not exist: $CONSTRAINTS_FILE"
}
if {$SEARCH_MIN_PERIOD_NS <= 0.0 || $SEARCH_MAX_PERIOD_NS <= 0.0 ||
    $SEARCH_MIN_PERIOD_NS >= $SEARCH_MAX_PERIOD_NS || $SEARCH_RESOLUTION_NS <= 0.0} {
    error "Require 0 < SEARCH_MIN_PERIOD_NS < SEARCH_MAX_PERIOD_NS and SEARCH_RESOLUTION_NS > 0."
}

proc read_project_filelist {filelist root_dir} {
    set sources {}
    set fh [open $filelist r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} {
            continue
        }
        if {[string match "-f *" $line]} {
            set child [string trim [string range $line 2 end]]
            set sources [concat $sources [read_project_filelist [file normalize [file join $root_dir $child]] $root_dir]]
        } elseif {[string match "+incdir+*" $line]} {
            continue
        } elseif {[string index $line 0] ne "-"} {
            lappend sources [file normalize [file join $root_dir $line]]
        }
    }
    close $fh
    return $sources
}

set rtl_sources [read_project_filelist [file join $root_dir sim rtl.f] $root_dir]
foreach source $rtl_sources {
    if {![file isfile $source]} {
        error "RTL source listed in sim/rtl.f does not exist: $source"
    }
}

file mkdir $results_root
set run_tag [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set search_report [file join $results_root search_${run_tag}.rpt]
set search_fh [open $search_report w]
puts $search_fh "# period_ns wns_ns setup_closed"

set_db library         $LIB_FILES
set_db hdl_search_path [list [file join $root_dir rtl]]
set_db information_level 5

# Return the worst setup slack after mapping and optimization at a candidate
# period.  get_timing_paths is ordered worst-first, so its first path is WNS.
proc run_setup_trial {period_ns rtl_sources top constraints_file search_fh} {
    global CLOCK_PERIOD_NS

    reset_design
    read_hdl -sv $rtl_sources
    elaborate $top
    check_design -unresolved

    set CLOCK_PERIOD_NS $period_ns
    read_sdc $constraints_file
    check_timing_intent
    syn_generic
    syn_map
    syn_opt

    set worst_path [get_timing_paths -late -max_paths 1]
    set wns_values [get_db $worst_path .slack]
    if {[llength $wns_values] == 0} {
        error "No setup timing paths were found at ${period_ns} ns. Check synth/constraints.sdc."
    }
    set wns [lindex $wns_values 0]
    set closed [expr {$wns >= 0.0}]
    puts $search_fh [format "%.6f %.6f %s" $period_ns $wns $closed]
    flush $search_fh
    puts [format "INFO: trial period %.6f ns: WNS %.6f ns (%s)" $period_ns $wns [expr {$closed ? "closed" : "failed"}]]
    return $wns
}

# The slow bound must close and the fast bound must fail, otherwise a binary
# search cannot prove the highest frequency inside the requested search range.
set slow_period $SEARCH_MAX_PERIOD_NS
set slow_wns [run_setup_trial $slow_period $rtl_sources $TOP $CONSTRAINTS_FILE $search_fh]
if {$slow_wns < 0.0} {
    close $search_fh
    error "Timing does not close at SEARCH_MAX_PERIOD_NS=${SEARCH_MAX_PERIOD_NS} ns; increase the maximum period."
}

set fast_period $SEARCH_MIN_PERIOD_NS
set fast_wns [run_setup_trial $fast_period $rtl_sources $TOP $CONSTRAINTS_FILE $search_fh]
if {$fast_wns >= 0.0} {
    close $search_fh
    error "Timing closes at SEARCH_MIN_PERIOD_NS=${SEARCH_MIN_PERIOD_NS} ns; decrease the minimum period to bound the maximum frequency."
}

while {[expr {$slow_period - $fast_period}] > $SEARCH_RESOLUTION_NS} {
    set trial_period [expr {($slow_period + $fast_period) / 2.0}]
    set trial_wns [run_setup_trial $trial_period $rtl_sources $TOP $CONSTRAINTS_FILE $search_fh]
    if {$trial_wns >= 0.0} {
        set slow_period $trial_period
        set slow_wns $trial_wns
    } else {
        set fast_period $trial_period
    }
}
close $search_fh

set best_period_ns $slow_period
set best_freq_mhz [expr {1000.0 / $best_period_ns}]
set period_tag [string map {. p} [format "%.6f" $best_period_ns]]
set freq_tag   [string map {. p} [format "%.3f" $best_freq_mhz]]
set out_dir [file join $results_root period_${period_tag}ns_${freq_tag}MHz]
if {[file exists $out_dir]} {
    error "Refusing to overwrite existing result directory: $out_dir"
}
file mkdir $out_dir

# Rebuild the winning candidate and preserve its complete implementation and
# reports.  The setup report lists the longest (worst-slack) paths first.
set final_wns [run_setup_trial $best_period_ns $rtl_sources $TOP $CONSTRAINTS_FILE stdout]
if {$final_wns < 0.0} {
    error "Winning candidate no longer closes during final rebuild (WNS ${final_wns} ns)."
}

report_qor                                      > [file join $out_dir qor.rpt]
report_timing -late -max_paths $MAX_TIMING_PATHS > [file join $out_dir timing_setup_longest_paths.rpt]
report_timing -early -max_paths $MAX_TIMING_PATHS > [file join $out_dir timing_hold_longest_paths.rpt]
report_timing -lint                             > [file join $out_dir timing_lint.rpt]
check_timing_intent                             > [file join $out_dir timing_intent.rpt]
report_area                                     > [file join $out_dir area.rpt]
report_power                                    > [file join $out_dir power.rpt]
report_gates                                    > [file join $out_dir gates.rpt]
report_messages -severity error                 > [file join $out_dir errors.rpt]
write_hdl                                       > [file join $out_dir ${TOP}_mapped.v]
write_sdc                                       > [file join $out_dir ${TOP}_mapped.sdc]
write_design -innovus -base_name [file join $out_dir $TOP]

set summary_fh [open [file join $out_dir max_frequency_summary.rpt] w]
puts $summary_fh "Top: $TOP"
puts $summary_fh [format "Best closing period: %.6f ns" $best_period_ns]
puts $summary_fh [format "Maximum closing frequency: %.3f MHz" $best_freq_mhz]
puts $summary_fh [format "Final setup WNS: %.6f ns" $final_wns]
puts $summary_fh [format "Search resolution: %.6f ns" $SEARCH_RESOLUTION_NS]
puts $summary_fh "Trial log: $search_report"
puts $summary_fh "Longest setup paths: timing_setup_longest_paths.rpt"
puts $summary_fh "Longest hold paths: timing_hold_longest_paths.rpt"
puts $summary_fh "Timing intent checks: timing_intent.rpt"
close $summary_fh

puts [format "INFO: maximum closing frequency: %.3f MHz (%.6f ns)" $best_freq_mhz $best_period_ns]
puts "INFO: final reports and implementation are in $out_dir"
exit
