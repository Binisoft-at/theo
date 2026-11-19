#!/usr/bin/env bash
# Every two minutes, publishes how far a TestFlight run has got to the `ci-testflight` branch:
# the minutes since it started, the newest build log's last lines, free disk and memory, and
# the biggest processes. A run whose Mac dies before its last step still leaves a trace.
# Stops when "$RUNNER_TEMP/progress.stop" exists; the final publish step creates it.
# usage: progress-reports.sh <label>      env: GH_TOKEN GITHUB_REPOSITORY RUNNER_TEMP
set -uo pipefail
label=$1
workspace=$PWD
start=$(date +%s)
stop="$RUNNER_TEMP/progress.stop"
while true; do
  for _ in $(seq 1 24); do
    sleep 5
    [ -f "$stop" ] && exit 0
  done
  out="$RUNNER_TEMP/progress"
  rm -rf "$out"
  mkdir -p "$out"
  minutes=$(( ($(date +%s) - start) / 60 ))
  newest=$(ls -t "$workspace"/*.log 2>/dev/null | head -1)
  {
    echo "running $label, $minutes min in"
    echo "newest log: ${newest:+$(basename "$newest")}"
    echo
    df -h / "$RUNNER_TEMP" 2>/dev/null
    echo
    memory_pressure 2>/dev/null | tail -1
    vm_stat 2>/dev/null | grep -E "free|compressor|Swapouts"
    echo
    ps -axm -o rss=,etime=,comm= 2>/dev/null | head -12
  } > "$out/status.txt"
  [ -n "$newest" ] && tail -120 "$newest" > "$out/newest-log-tail.txt"
  [ -f "$stop" ] && exit 0
  "$workspace/scripts/ci/publish-ci-output.sh" "$out" "testflight progress: $minutes min" ci-testflight >/dev/null 2>&1 || true
done
