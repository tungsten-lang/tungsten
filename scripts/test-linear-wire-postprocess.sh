#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-linear-wire-postprocess.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
release_flags=(--release --native --fast --no-debug --emit-ll)

# Warm the persistent Core snapshot so the comparison also exercises frozen
# Core functions and their stable string-id prefix.
TUNGSTEN_LL_PATH="$TMP/warm.ll" \
  "$TUNGSTEN" compile benchmarks/big_math/program_loops.w \
  --out "$TMP/warm" "${release_flags[@]}" >/dev/null

programs=(
  benchmarks/big_math/program_loops.w
  benchmarks/big_math/interprocedural_constant.w
)
i=0
while [[ $i -lt ${#programs[@]} ]]; do
  program="${programs[$i]}"
  TUNGSTEN_LINEAR_WIRE_POSTPROCESS=0 TUNGSTEN_LL_PATH="$TMP/$i-legacy.ll" \
    "$TUNGSTEN" compile "$program" --out "$TMP/$i-legacy" \
    "${release_flags[@]}" >/dev/null
  TUNGSTEN_LINEAR_WIRE_POSTPROCESS=1 TUNGSTEN_LL_PATH="$TMP/$i-linear.ll" \
    "$TUNGSTEN" compile "$program" --out "$TMP/$i-linear" \
    "${release_flags[@]}" >/dev/null
  cmp "$TMP/$i-legacy.ll" "$TMP/$i-linear.ll"
  cmp "$TMP/$i-legacy.sidemap" "$TMP/$i-linear.sidemap"
  i=$((i + 1))
done

# Debug modules do not strip location metadata, but they still use the
# composed name rewrite. Preserve exact IR and the physical-frame contract.
TUNGSTEN_LINEAR_WIRE_POSTPROCESS=0 TUNGSTEN_LL_PATH="$TMP/debug-legacy.ll" \
  "$TUNGSTEN" compile compiler/test/fixtures/core_abi_stable_b.w \
  --out "$TMP/debug-legacy" --debug --frame-pointers --native --fast \
  --emit-ll >/dev/null
TUNGSTEN_LINEAR_WIRE_POSTPROCESS=1 TUNGSTEN_LL_PATH="$TMP/debug-linear.ll" \
  "$TUNGSTEN" compile compiler/test/fixtures/core_abi_stable_b.w \
  --out "$TMP/debug-linear" --debug --frame-pointers --native --fast \
  --emit-ll >/dev/null
cmp "$TMP/debug-legacy.ll" "$TMP/debug-linear.ll"
cmp "$TMP/debug-legacy.sidemap" "$TMP/debug-linear.sidemap"
rg -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-linear.ll"
rg -q 'uwtable "frame-pointer"="all"' "$TMP/debug-linear.ll"

echo "linear WIRE postprocess: OK"
