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
That directory includes QoR, area, power, gate, and timing-intent reports,
plus the 100 worst setup timing paths by default.

### Integer multiplier timing

The multiplier-only flow uses a small registered harness around the multiplier's
three existing pipeline stages.  It therefore measures register-to-register
paths for Booth generation plus Dadda stages 1--2, Dadda stages 3--6, and Dadda
stages 7--8 plus the final adder, without timing the rest of the core:

```sh
export GENUS_LIB_FILES="/path/to/standard_cells_ss.lib"
synth/run_genus_imul_timing.sh
```

The flow binary-searches the period from 0.100 ns through 10.000 ns to a 5 ps
resolution; override `SEARCH_MIN_PERIOD_NS`, `SEARCH_MAX_PERIOD_NS`, or
`SEARCH_RESOLUTION_NS` in `synth/genus_config.tcl` if necessary.  Its final
period and frequency are in `max_frequency_summary.rpt`, and every trial is
logged in `search_*.rpt`.  The stage-specific reports in
`build/genus/imul_timing/timing_cycle{1,2,3}.rpt` show each stage's worst
paths; compare their data-arrival times or slacks to judge balance.
`timing_all_reg_to_reg.rpt` contains the 100 overall longest paths, including
the endpoint bits and mapped cells on each path.

For a single implementation pass rather than a frequency search, set
`IMUL_CLOCK_PERIOD_NS` in `synth/genus_config.tcl` and run:

```sh
synth/run_genus_imul_fixed_timing.sh
```

Its reports are written to `build/genus/imul_fixed_timing/`; this is the
preferred flow while iterating on the multiplier RTL.

### Individual multiplier-stage frequency searches

To measure the maximum closing frequency of each existing multiplier pipeline
stage independently, run these three shell scripts in parallel if licenses and
machine capacity permit:

```sh
synth/run_genus_imul_cycle1_max_freq.sh &
synth/run_genus_imul_cycle2_max_freq.sh &
synth/run_genus_imul_cycle3_max_freq.sh &
wait
```

They share one Tcl implementation but use separate tops with flop banks on
only the selected stage's inputs and outputs.  Every invocation writes to a
new `build/genus/imul_stage_max_frequency/<stage>/run_<timestamp>_<pid>/`
directory and a unique log file, so parallel or repeated runs do not overwrite
one another.  The search bounds use the same `SEARCH_*` configuration values
as the core max-frequency flow.

## CoreMark and Embench

The CoreMark and Embench-IoT sources are pinned in `third_party/` as Git
submodules. Initialize them after cloning:

```sh
git submodule update --init --recursive
```

The ports target the implemented ISA, `rv64i_zicsr_zicntr` with the `lp64`
ABI. They deliberately do not enable the RISC-V M, F, D, or C extensions.
Both share a bare-metal mailbox at the top of the testbench RAM; it reports
`mcycle` and `minstret` around each benchmark's timed region.

CoreMark configuration begins with literal copies of upstream
`barebones/core_portme.c`, `core_portme.h`, and `ee_printf.c`; Embench begins
with its `riscv32/rv32wallyverilog` board-support, linker, and startup
templates. The copied files preserve their upstream license headers and only
the target-specific sections are adapted. The small `bench/platform/` layer is
project-owned glue for the memory mailbox and RV64I-only compiler helpers.

Build and run CoreMark (the default is a short, fixed 10-iteration simulation
run, not an official ten-second score):

```sh
make bench-coremark
make bench-coremark-run
```

Set `ITERATIONS` and `CLOCK_HZ` when building if needed, for example
`make bench-coremark ITERATIONS=100 CLOCK_HZ=1000000`. The runner prints JSON
including cycle and instruction deltas; CoreMark/MHz is
`iterations * 1000000 / cycles`.

Embench requires SCons in addition to the RISC-V GCC toolchain and Verilator.
Build the suite, then collect absolute cycle-counter-derived timings:

```sh
make bench-embench
make bench-embench-run
```

`GSF`, `BUILD_DIR`, `CPU_MHZ`, and `MAX_CYCLES` can be supplied as environment
variables for the Embench scripts. At the default `GSF=1`, several workloads
need more than the default two-million-cycle architectural-test limit; the
benchmark runner defaults to twenty million cycles.
