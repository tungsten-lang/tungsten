#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-compiler/tungsten.w}"
RUNS="${RUNS:-8}"
JOBS="${JOBS:-8}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parallel-function-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_DISK_CACHE=0
export TUNGSTEN_FUNCTION_EMIT_CACHE=0
flags=(--emit-ll --release --native --fast --verbose)

run_once() {
  local mode="$1"
  local pair="$2"
  local toggle="$3"
  local jobs="$4"
  TUNGSTEN_PARALLEL_FUNCTION_EMIT="$toggle" \
    TUNGSTEN_EMITTER_JOBS="$jobs" \
    TUNGSTEN_LL_PATH="$TMP/$mode-$pair.ll" \
    /usr/bin/time -lp "$TUNGSTEN" compile "$PROGRAM" \
      --out "$TMP/$mode-$pair" "${flags[@]}" \
      >"$TMP/$mode-$pair.log" 2>&1
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    run_once serial "$pair" 0 1
    run_once parallel "$pair" 1 "$JOBS"
  else
    run_once parallel "$pair" 1 "$JOBS"
    run_once serial "$pair" 0 1
  fi
  cmp "$TMP/serial-$pair.ll" "$TMP/parallel-$pair.ll"
  cmp "$TMP/serial-$pair.sidemap" "$TMP/parallel-$pair.sidemap"
  serial="$(sed -nE 's/^[[:space:]]*([0-9.]+)s TOTAL COMPILE TIME/\1/p' "$TMP/serial-$pair.log")"
  parallel="$(sed -nE 's/^[[:space:]]*([0-9.]+)s TOTAL COMPILE TIME/\1/p' "$TMP/parallel-$pair.log")"
  printf 'pair %02d: serial=%ss parallel-%s=%ss\n' \
    "$pair" "$serial" "$JOBS" "$parallel"
  pair=$((pair + 1))
done

ruby -e '
  dir = ARGV[0]
  runs = ARGV[1].to_i
  def median(values)
    sorted = values.sort
    n = sorted.size
    n.odd? ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
  end
  patterns = {
    emit: /([0-9.]+)s emit llvm ir/,
    total: /([0-9.]+)s TOTAL COMPILE TIME/,
    wall: /^real ([0-9.]+)/,
    rss: /([0-9]+)  maximum resident set size/,
    instructions: /([0-9]+)  instructions retired/
  }
  patterns.each do |name, pattern|
    serial = (1..runs).map { |i| File.read("#{dir}/serial-#{i}.log")[pattern, 1].to_f }
    parallel = (1..runs).map { |i| File.read("#{dir}/parallel-#{i}.log")[pattern, 1].to_f }
    before = median(serial)
    after = median(parallel)
    printf "%s: %.4f -> %.4f (%+.2f%%)\n", name, before, after,
      (after - before) * 100.0 / before
  end
' "$TMP" "$RUNS"
