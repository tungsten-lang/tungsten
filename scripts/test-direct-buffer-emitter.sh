#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-direct-buffer-emitter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_DISK_CACHE=0
# Exercise the renderer itself even when the fixture has reusable Core.
export TUNGSTEN_FUNCTION_EMIT_CACHE=0

fixtures=(
  compiler/test/fixtures/simple.w
  compiler/test/fixtures/core_abi_stable_b.w
  compiler/test/fixtures/locked_return_class_sets.w
  benchmarks/big_math/program_loops.w
)

i=0
while [[ $i -lt ${#fixtures[@]} ]]; do
  for mode in 0 1; do
    TUNGSTEN_DIRECT_BUFFER_EMIT="$mode" TUNGSTEN_LL_PATH="$TMP/$i-$mode.ll" \
      "$TUNGSTEN" compile "${fixtures[$i]}" --out "$TMP/$i-$mode" \
      --emit-ll --release --native --fast >/dev/null
  done
  cmp "$TMP/$i-0.ll" "$TMP/$i-1.ll"
  cmp "$TMP/$i-0.sidemap" "$TMP/$i-1.sidemap"
  i=$((i + 1))
done

# Debug builds preserve exact physical source frames on the direct path.
for mode in 0 1; do
  TUNGSTEN_DIRECT_BUFFER_EMIT="$mode" TUNGSTEN_LL_PATH="$TMP/debug-$mode.ll" \
    "$TUNGSTEN" compile compiler/test/fixtures/core_abi_stable_b.w \
    --out "$TMP/debug-$mode" --emit-ll --debug --frame-pointers \
    --native --fast >/dev/null
done
cmp "$TMP/debug-0.ll" "$TMP/debug-1.ll"
cmp "$TMP/debug-0.sidemap" "$TMP/debug-1.sidemap"
rg -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-1.ll"
rg -q 'uwtable "frame-pointer"="all"' "$TMP/debug-1.ll"

echo "direct-buffer emitter: OK"
