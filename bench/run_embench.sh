#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
embench_dir="$root_dir/third_party/embench-iot"
build_dir=${BUILD_DIR:-"$root_dir/build/bench/embench-speed"}
cpu_mhz=${CPU_MHZ:-1}
max_cycles=${MAX_CYCLES:-500000000}
gsf=${GSF:-1}

PYTHONPATH="$root_dir/bench/embench${PYTHONPATH:+:$PYTHONPATH}" \
  python3 "$embench_dir/benchmark_speed.py" \
    --builddir="$build_dir" \
    --target-module=run_riscv_core \
    --absolute --cpu-mhz="$cpu_mhz" --gsf="$gsf" --max-cycles="$max_cycles" "$@"
