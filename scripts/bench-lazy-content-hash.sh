#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-benchmarks/big_math/program_loops.w}"
RUNS="${RUNS:-20}"
LINK="${LINK:-0}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-lazy-content-hash-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CORE_REACHABILITY=1
flags=(--release --native --fast --no-debug)
if [[ "$LINK" != "1" ]]; then
  flags+=(--emit-ll)
fi

# Publish the complete Core snapshot and warm shared native-link inputs outside
# the measured series.
TUNGSTEN_LAZY_CONTENT_HASH=1 TUNGSTEN_LL_PATH="$TMP/warm.ll" \
  "$TUNGSTEN" compile "$PROGRAM" --out "$TMP/warm" "${flags[@]}" \
  >/dev/null 2>&1

off_times=()
on_times=()
run_once() {
  local mode="$1"
  local sample="$2"
  local started finished
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  TUNGSTEN_LAZY_CONTENT_HASH="$mode" \
    TUNGSTEN_LL_PATH="$TMP/program-$mode-$sample.ll" \
    "$TUNGSTEN" compile "$PROGRAM" --out "$TMP/program-$mode-$sample" \
      "${flags[@]}" >/dev/null 2>&1
  finished="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  ruby -e 'printf "%.6f", ARGV[1].to_f - ARGV[0].to_f' "$started" "$finished"
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    off="$(run_once 0 "$pair")"
    on="$(run_once 1 "$pair")"
  else
    on="$(run_once 1 "$pair")"
    off="$(run_once 0 "$pair")"
  fi
  off_times+=("$off")
  on_times+=("$on")
  printf 'pair %02d: full-graph=%ss cached-only=%ss\n' "$pair" "$off" "$on"
  pair=$((pair + 1))
done

median() {
  printf '%s\n' "$@" | sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2) print values[(NR + 1) / 2]
      else printf "%.6f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
    }'
}

off_median="$(median "${off_times[@]}")"
on_median="$(median "${on_times[@]}")"
awk -v off="$off_median" -v on="$on_median" '
  BEGIN {
    printf "median: full-graph=%.6fs cached-only=%.6fs improvement=%.2f%% speedup=%.3fx saved=%.6fs\n",
      off, on, (off - on) * 100.0 / off, off / on, off - on
  }'
