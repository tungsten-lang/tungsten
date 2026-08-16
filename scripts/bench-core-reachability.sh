#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-benchmarks/big_math/program_loops.w}"
RUNS="${RUNS:-8}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-core-reachability-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
flags=(--release --native --fast --no-debug)
off_times=()
on_times=()

run_once() {
  local mode="$1"
  local sample="$2"
  local started finished
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  TUNGSTEN_CACHE_DIR="$TMP/cache" \
    TUNGSTEN_INCREMENTAL=0 \
    TUNGSTEN_CORE_REACHABILITY="$mode" \
    "$TUNGSTEN" compile "$PROGRAM" \
      --out "$TMP/program-$mode-$sample" "${flags[@]}" \
      >/dev/null 2>&1
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
  printf 'pair %02d: full-core=%ss reachable-core=%ss\n' "$pair" "$off" "$on"
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
    printf "median: full-core=%.6fs reachable-core=%.6fs improvement=%.2f%% speedup=%.3fx saved=%.6fs\n",
      off, on, (off - on) * 100.0 / off, off / on, off - on
  }'
