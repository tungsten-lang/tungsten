#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-compiler/test/fixtures/core_abi_stable_b.w}"
COUNT="${COUNT:-150}"
RUNS="${RUNS:-5}"
JOBS="${JOBS:-8}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parallel-batch-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/cache" "$TMP/ll"
sources=()
i=0
while [[ $i -lt $COUNT ]]; do
  path="$TMP/src/program-$(printf '%03d' "$i").w"
  cp "$PROGRAM" "$path"
  sources+=("$path")
  i=$((i + 1))
done

export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_PARSE_CACHE=1
flags=(--release --native --fast --no-debug --emit-ll)

TUNGSTEN_LL_PATH="$TMP/warm.ll" \
  "$TUNGSTEN" compile "${sources[0]}" --out "$TMP/warm" "${flags[@]}" \
  >/dev/null 2>&1

serial_times=()
parallel_times=()
run_once() {
  local jobs="$1"
  local started finished
  rm -rf "$TMP/ll"
  mkdir -p "$TMP/ll"
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  TUNGSTEN_LL_DIR="$TMP/ll" \
    "$TUNGSTEN" compile-batch --jobs "$jobs" "${sources[@]}" \
    "${flags[@]}" >/dev/null 2>&1
  finished="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  ruby -e 'printf "%.6f", ARGV[1].to_f - ARGV[0].to_f' "$started" "$finished"
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    serial="$(run_once 1)"
    parallel="$(run_once "$JOBS")"
  else
    parallel="$(run_once "$JOBS")"
    serial="$(run_once 1)"
  fi
  serial_times+=("$serial")
  parallel_times+=("$parallel")
  printf 'pair %02d: jobs-1=%ss jobs-%s=%ss\n' \
    "$pair" "$serial" "$JOBS" "$parallel"
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

serial_median="$(median "${serial_times[@]}")"
parallel_median="$(median "${parallel_times[@]}")"
awk -v serial="$serial_median" -v parallel="$parallel_median" \
    -v count="$COUNT" -v jobs="$JOBS" '
  BEGIN {
    printf "median (%d programs): jobs-1=%.6fs jobs-%d=%.6fs improvement=%.2f%% speedup=%.3fx saved=%.6fs\n",
      count, serial, jobs, parallel,
      (serial - parallel) * 100.0 / serial, serial / parallel,
      serial - parallel
  }'
