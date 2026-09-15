# Cadence Genus synthesis flow for the RV64 core.
#
# Run from any directory, for example:
#   export GENUS_LIB_FILES="/path/to/slow.lib /path/to/fast.lib"
#   genus -files synth/genus.tcl |& tee build/genus/genus.log
#
# GENUS_LIB_FILES must be a Tcl list of Liberty timing libraries.  A local
# synth/genus_config.tcl may instead set LIB_FILES (and optionally TOP,
# CLOCK_PERIOD_NS, or CONSTRAINTS_FILE); it is intentionally gitignored so
# PDK-specific paths remain local.

set script_dir [file dirname [file normalize [info script]]]
# Older Genus releases invoked with "-files synth/genus.tcl" can report
# [info script] as only "genus.tcl".  Then script_dir is the project root,
# so recover synth/ before resolving local configuration and constraints.
if {![file isfile [file join $script_dir constraints.sdc]] &&
    [file isfile [file join $script_dir synth constraints.sdc]]} {
    set script_dir [file join $script_dir synth]
}
set root_dir   [file dirname $script_dir]

set TOP               riscv_core
set CLOCK_PERIOD_NS   1.000
set CONSTRAINTS_FILE  [file join $script_dir constraints.sdc]
set out_dir           [file join $root_dir build genus]

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

# sim/rtl.f is nested; resolve its entries from the project root, matching the
# existing Makefile/Verilator flow.  Keep this procedure so the source of truth
# for RTL order remains the same for simulation and synthesis.
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
            # Include paths are configured below.  This branch is retained for
            # compatibility with simulator-style file lists.
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

file mkdir $out_dir

# Full library paths make the flow independent of a particular PDK directory
# layout.  The HDL search path permits package includes from the RTL directory.
set_db library         $LIB_FILES
set_db hdl_search_path [list [file join $root_dir rtl]]
set_db information_level 5

read_hdl -sv $rtl_sources
elaborate $TOP
check_design -unresolved

# CLOCK_PERIOD_NS is visible while the SDC is read, so a local configuration
# can override the default 1 GHz target without editing the shared constraint.
read_sdc $CONSTRAINTS_FILE
check_timing -unconstrained

syn_generic
syn_map
syn_opt

report_qor                     > [file join $out_dir qor.rpt]
report_timing -max_paths 20    > [file join $out_dir timing.rpt]
report_area                    > [file join $out_dir area.rpt]
report_power                   > [file join $out_dir power.rpt]
report_gates                   > [file join $out_dir gates.rpt]
report_messages -severity error > [file join $out_dir errors.rpt]

write_hdl > [file join $out_dir ${TOP}_mapped.v]
write_sdc > [file join $out_dir ${TOP}_mapped.sdc]
write_design -innovus -base_name [file join $out_dir $TOP]

puts "INFO: Genus synthesis completed. Results are in $out_dir"
exit
