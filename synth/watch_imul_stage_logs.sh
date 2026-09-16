#!/usr/bin/env bash
set -euo pipefail

# Run this from build/genus/imul_stage_logs (or pass that directory as $1).
# It prints every completed binary-search trial already present in the logs,
# then prints each new one as Genus finishes it.  The watcher keeps offsets in
# memory only; it neither creates nor changes files in the log directory.

log_dir=${1:-.}
interval_seconds=${WATCH_INTERVAL_SECONDS:-1}

if [[ ! -d "$log_dir" ]]; then
  echo "error: log directory does not exist: $log_dir" >&2
  exit 2
fi
if ! [[ "$interval_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
   ! awk -v value="$interval_seconds" 'BEGIN { exit !(value > 0) }'; then
  echo "error: WATCH_INTERVAL_SECONDS must be a positive number" >&2
  exit 2
fi

shopt -s nullglob
declare -A seen_lines

emit_trial_lines() {
  local log_file=$1
  local first_line=$2
  local last_line=$3

  if (( first_line > last_line )); then
    return
  fi

  # Stage searches print "INFO: cycleN trial ...".  The other two patterns
  # also make the watcher useful for the existing core/multiplier searches.
  sed -n "${first_line},${last_line}p" "$log_file" | awk '
    /INFO: cycle[123] trial [0-9.]+ ns:/ ||
    /INFO: multiplier trial [0-9.]+ ns:/ ||
    /INFO: trial period [0-9.]+ ns:/ { print }
  '
}

while :; do
  for log_file in "$log_dir"/*.log; do
    [[ -f "$log_file" ]] || continue

    total_lines=$(wc -l < "$log_file")
    previous_lines=${seen_lines["$log_file"]:-0}

    # A newly created log is emitted in full.  If a tool replaces/truncates a
    # log, reread it from the beginning rather than silently skipping trials.
    if (( total_lines < previous_lines )); then
      previous_lines=0
    fi
    emit_trial_lines "$log_file" "$((previous_lines + 1))" "$total_lines"
    seen_lines["$log_file"]=$total_lines
  done
  sleep "$interval_seconds"
done
