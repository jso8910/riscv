#!/usr/bin/env bash
set -euo pipefail

# Run the multiplier-only binary-search timing flow from a predictable
# directory, matching synth/run_genus.sh and synth/run_genus_max_freq.sh.
# Pass any additional Genus arguments through unchanged.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$script_dir/.." && pwd)
output_dir=${GENUS_OUTPUT_DIR:-"$root_dir/build/genus"}

mkdir -p "$output_dir"
cd "$output_dir"
export GENUS_PROJECT_ROOT="$root_dir"
exec genus -files "$script_dir/genus_imul_timing.tcl" -log imul_timing.log "$@"
