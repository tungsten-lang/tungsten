#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-compiler/test/fixtures/core_abi_stable_b.w}"
COUNT="${COUNT:-150}"
RUNS="${RUNS:-5}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-persistent-function-emit-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/cache"
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
export TUNGSTEN_FRONTEND_DISK_CACHE=0
flags=(--release --native --fast --emit-ll)

# Populate the lowered-Core/target caches, then the persistent rendered bucket;
# neither warmup belongs to a measured mode.
TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=0 TUNGSTEN_LL_PATH="$TMP/warm-core.ll" \
  "$TUNGSTEN" compile "${sources[0]}" --out "$TMP/warm-core" \
  "${flags[@]}" >/dev/null 2>&1
TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=1 TUNGSTEN_LL_PATH="$TMP/warm-render.ll" \
  "$TUNGSTEN" compile "${sources[0]}" --out "$TMP/warm-render" \
  "${flags[@]}" >/dev/null 2>&1

run_once() {
  local mode="$1"
  local disk="$2"
  local started finished
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  for source in "${sources[@]}"; do
    TUNGSTEN_FUNCTION_EMIT_DISK_CACHE="$disk" \
      TUNGSTEN_LL_PATH="$TMP/$mode.ll" \
      "$TUNGSTEN" compile "$source" --out "$TMP/$mode" \
      "${flags[@]}" >/dev/null 2>&1
  done
  finished="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  ruby -e 'printf "%.6f", ARGV[1].to_f - ARGV[0].to_f' "$started" "$finished"
}

off_times=()
on_times=()
pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    off="$(run_once off 0)"
    on="$(run_once on 1)"
  else
    on="$(run_once on 1)"
    off="$(run_once off 0)"
  fi
  cmp "$TMP/off.ll" "$TMP/on.ll"
  cmp "$TMP/off.sidemap" "$TMP/on.sidemap"
  off_times+=("$off")
  on_times+=("$on")
  printf 'pair %02d: disk-off=%ss disk-on=%ss\n' "$pair" "$off" "$on"
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
    printf "median (%d fresh processes): disk-off=%.6fs disk-on=%.6fs improvement=%.2f%% speedup=%.3fx saved=%.6fs\n",
      count, off, on, (off - on) * 100.0 / off, off / on, off - on
  }'
