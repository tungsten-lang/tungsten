#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-compiler/test/fixtures/core_abi_stable_b.w}"
COUNT="${COUNT:-150}"
RUNS="${RUNS:-5}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-function-emit-cache-bench.XXXXXX")"
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
export TUNGSTEN_LL_DIR="$TMP/ll"
flags=(--release --native --fast --no-debug --emit-ll)

# Keep Core-WIRE population outside both measured modes.
"$TUNGSTEN" compile "${sources[0]}" --out "$TMP/warm" "${flags[@]}" \
  >/dev/null 2>&1

off_times=()
on_times=()
run_once() {
  local mode="$1"
  local started finished
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  TUNGSTEN_FUNCTION_EMIT_CACHE="$mode" \
    "$TUNGSTEN" compile-batch "${sources[@]}" "${flags[@]}" \
    >/dev/null 2>&1
  finished="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  ruby -e 'printf "%.6f", ARGV[1].to_f - ARGV[0].to_f' "$started" "$finished"
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    off="$(run_once 0)"
    on="$(run_once 1)"
  else
    on="$(run_once 1)"
    off="$(run_once 0)"
  fi
  off_times+=("$off")
  on_times+=("$on")
  printf 'pair %02d: cache-off=%ss cache-on=%ss\n' "$pair" "$off" "$on"
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
awk -v off="$off_median" -v on="$on_median" -v count="$COUNT" '
  BEGIN {
    printf "median (%d programs): cache-off=%.6fs cache-on=%.6fs improvement=%.2f%% speedup=%.3fx saved=%.6fs\n",
      count, off, on, (off - on) * 100.0 / off, off / on, off - on
  }'
