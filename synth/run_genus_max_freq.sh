#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$script_dir/.." && pwd)
output_dir=${GENUS_OUTPUT_DIR:-"$root_dir/build/genus"}

mkdir -p "$output_dir"
cd "$output_dir"
export GENUS_PROJECT_ROOT="$root_dir"
exec genus -files "$script_dir/genus_max_freq.tcl" -log max_freq.log "$@"
