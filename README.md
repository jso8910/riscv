## RISC-V Core

This core implements RV64I with M-, S-, and U-mode, Sv39 translation, Svade
page-fault behavior, and Sstc supervisor timer compare support.

## Synthesis

The Cadence Genus flow is in `synth/genus.tcl`.  Supply your technology
Liberty file or files as a Tcl list, then invoke Genus from the repository
root:

```sh
export GENUS_LIB_FILES="/path/to/standard_cells_ss.lib"
genus -files synth/genus.tcl |& tee build/genus/genus.log
```

Alternatively, copy `synth/genus_config.tcl.example` to
`synth/genus_config.tcl` for local PDK paths and timing overrides.  The flow
uses the RTL order in `sim/rtl.f`, constrains `clk` at 1.0 ns by default, and
writes the mapped netlist, SDC, reports, and Innovus handoff data to
`build/genus/`.  Replace `synth/constraints.sdc` with integration constraints
when the core is placed in an SoC.

To find the maximum timing-closing frequency for a library/constraint set, run
the binary-search flow:

```sh
export GENUS_LIB_FILES="/path/to/standard_cells_ss.lib"
genus -files synth/genus_max_freq.tcl |& tee build/genus/max_freq.log
```

It searches between 0.100 ns and 10.000 ns (override these bounds in the local
Genus config), and leaves the final implementation in a directory named for
its highest closing period and frequency under `build/genus/max_frequency/`.
That directory includes QoR, area, power, gate, timing-lint, and error reports,
an unconstrained-path check, plus the 100 worst setup and hold timing paths by
default.
