#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 {cycle1|cycle2|cycle3} [Genus arguments...]" >&2
  exit 2
fi
stage=$1
shift
case "$stage" in
  cycle1|cycle2|cycle3) ;;
  *) echo "error: stage must be cycle1, cycle2, or cycle3" >&2; exit 2 ;;
esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$script_dir/.." && pwd)
output_dir=${GENUS_OUTPUT_DIR:-"$root_dir/build/genus"}
log_dir="$output_dir/imul_stage_logs"
run_tag=$(date +%Y%m%d_%H%M%S)_$$
log_file="$log_dir/${stage}_max_freq_${run_tag}.log"

mkdir -p "$log_dir"
if [[ -e "$log_file" ]]; then
  echo "error: refusing to overwrite existing Genus log: $log_file" >&2
  exit 1
fi
cd "$output_dir"
export GENUS_PROJECT_ROOT="$root_dir"
export IMUL_TIMING_STAGE="$stage"
exec genus -files "$script_dir/genus_imul_stage_max_freq.tcl" \
  -log "$log_file" "$@"
