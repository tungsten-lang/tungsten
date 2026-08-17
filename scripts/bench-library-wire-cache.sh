#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
PROGRAM="${PROGRAM:-compiler/test/fixtures/library_wire_cache/entry_a.w}"
RUNS="${RUNS:-8}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-library-wire-cache-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FUNCTION_EMIT_CACHE=0
flags=(--emit-ll --release --native --fast --verbose)

# Publish Core, then library WIRE, and warm unrelated target/frontend probes
# before either measured mode.
TUNGSTEN_LL_PATH="$TMP/prime-core.ll" \
  "$TUNGSTEN" compile "$PROGRAM" --out "$TMP/prime-core" "${flags[@]}" \
  >/dev/null 2>&1
TUNGSTEN_LL_PATH="$TMP/prime-library.ll" \
  "$TUNGSTEN" compile "$PROGRAM" --out "$TMP/prime-library" "${flags[@]}" \
  >/dev/null 2>&1
TUNGSTEN_LL_PATH="$TMP/prime-hit.ll" \
  "$TUNGSTEN" compile "$PROGRAM" --out "$TMP/prime-hit" "${flags[@]}" \
  >/dev/null 2>&1

run_once() {
  local label="$1"
  local pair="$2"
  local toggle="$3"
  TUNGSTEN_LIBRARY_WIRE_CACHE="$toggle" \
    TUNGSTEN_LL_PATH="$TMP/$label-$pair.ll" \
    /usr/bin/time -lp "$TUNGSTEN" compile "$PROGRAM" \
      --out "$TMP/$label-$pair" "${flags[@]}" \
      >"$TMP/$label-$pair.log" 2>&1
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    run_once off "$pair" 0
    run_once on "$pair" 1
  else
    run_once on "$pair" 1
    run_once off "$pair" 0
  fi
  cmp "$TMP/off-$pair.ll" "$TMP/on-$pair.ll"
  cmp "$TMP/off-$pair.sidemap" "$TMP/on-$pair.sidemap"
  off="$(sed -nE 's/^[[:space:]]*([0-9.]+)s TOTAL COMPILE TIME/\1/p' "$TMP/off-$pair.log")"
  on="$(sed -nE 's/^[[:space:]]*([0-9.]+)s TOTAL COMPILE TIME/\1/p' "$TMP/on-$pair.log")"
  printf 'pair %02d: cache-off=%ss cache-on=%ss\n' "$pair" "$off" "$on"
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
    lowering: /([0-9.]+)s lowering to wire/,
    total: /([0-9.]+)s TOTAL COMPILE TIME/,
    wall: /^real ([0-9.]+)/,
    rss: /([0-9]+)  maximum resident set size/,
    instructions: /([0-9]+)  instructions retired/
  }
  patterns.each do |name, pattern|
    off = (1..runs).map { |i| File.read("#{dir}/off-#{i}.log")[pattern, 1].to_f }
    on = (1..runs).map { |i| File.read("#{dir}/on-#{i}.log")[pattern, 1].to_f }
    before = median(off)
    after = median(on)
    printf "%s: %.4f -> %.4f (%+.2f%%)\n", name, before, after,
      (after - before) * 100.0 / before
  end
' "$TMP" "$RUNS"
