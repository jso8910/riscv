#!/usr/bin/env bash
set -euo pipefail

# Run the three independently constrained multiplier pipeline-stage searches
# concurrently.  Each child creates its own Genus and result directories.
# Extra arguments are forwarded unchanged to every Genus invocation.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$script_dir/.." && pwd)
output_dir=${GENUS_OUTPUT_DIR:-"$root_dir/build/genus"}
console_log_dir="$output_dir/imul_stage_logs"
run_tag=$(date +%Y%m%d_%H%M%S)_$$
stages=(cycle1 cycle2 cycle3)
declare -a pids=()

mkdir -p "$console_log_dir"

cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup INT TERM

for stage in "${stages[@]}"; do
  console_log="$console_log_dir/${stage}_max_freq_${run_tag}.console.log"
  echo "Starting $stage (console: $console_log)"
  "$script_dir/run_genus_imul_stage_max_freq.sh" "$stage" "$@" \
    >"$console_log" 2>&1 &
  pids+=("$!")
done

status=0
for index in "${!stages[@]}"; do
  if wait "${pids[$index]}"; then
    echo "${stages[$index]}: completed"
  else
    echo "${stages[$index]}: FAILED (see $console_log_dir/${stages[$index]}_max_freq_${run_tag}.console.log)" >&2
    status=1
  fi
done

exit "$status"
