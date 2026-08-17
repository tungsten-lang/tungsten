#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-function-emit-cache-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src" "$TMP/cache" "$TMP/off-ll" "$TMP/on-ll" \
  "$TMP/off-save" "$TMP/on-save" "$TMP/debug-ll" "$TMP/disk-cache"
cp compiler/test/fixtures/core_abi_stable_a.w "$TMP/src/a.w"
cp compiler/test/fixtures/core_abi_stable_b.w "$TMP/src/b.w"

export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=0
flags=(--release --native --fast --no-debug --emit-ll)

# Publish the persistent Core snapshot first so both render modes start from
# the same frozen WIRE graph.
TUNGSTEN_LL_PATH="$TMP/warm.ll" \
  "$TUNGSTEN" compile "$TMP/src/a.w" --out "$TMP/warm" "${flags[@]}" \
  >/dev/null

TUNGSTEN_FUNCTION_EMIT_CACHE=0 TUNGSTEN_LL_DIR="$TMP/off-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 "$TMP/src/a.w" "$TMP/src/b.w" \
  "${flags[@]}" -v >"$TMP/off.log" 2>&1

for name in a b; do
  ll="$(find "$TMP/off-ll" -type f -name "$name.ll" | head -1)"
  test -n "$ll"
  cp "$ll" "$TMP/off-save/$name.ll"
  cp "$TMP/src/$name.wc.sidemap" "$TMP/off-save/$name.sidemap"
done

TUNGSTEN_FUNCTION_EMIT_CACHE=1 TUNGSTEN_LL_DIR="$TMP/on-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 "$TMP/src/a.w" "$TMP/src/b.w" \
  "${flags[@]}" -v >"$TMP/on.log" 2>&1

for name in a b; do
  ll="$(find "$TMP/on-ll" -type f -name "$name.ll" | head -1)"
  test -n "$ll"
  cp "$ll" "$TMP/on-save/$name.ll"
  cp "$TMP/src/$name.wc.sidemap" "$TMP/on-save/$name.sidemap"
  cmp "$TMP/off-save/$name.ll" "$TMP/on-save/$name.ll"
  cmp "$TMP/off-save/$name.sidemap" "$TMP/on-save/$name.sidemap"
done

# Program two must reuse at least one frozen Core body and have no eligible
# misses. Render-order-dependent functions remain visible as bypasses.
rg -q 'function emit cache: [1-9][0-9]* hits, 0 misses, [0-9]+ bypassed' \
  "$TMP/on.log"

# Debug output deliberately bypasses rendered-body reuse. Keep the explicit
# physical-frame attributes that source backtraces require.
TUNGSTEN_FUNCTION_EMIT_CACHE=1 TUNGSTEN_LL_DIR="$TMP/debug-ll" \
  "$TUNGSTEN" compile-batch --jobs 1 "$TMP/src/a.w" "$TMP/src/b.w" \
  --debug --frame-pointers --emit-ll -v >"$TMP/debug.log" 2>&1
if rg -q 'function emit cache:' "$TMP/debug.log"; then
  echo "FAIL: debug compilation used the release function emit cache" >&2
  exit 1
fi
debug_ll="$(find "$TMP/debug-ll" -type f -name 'b.ll' | head -1)"
test -n "$debug_ll"
rg -q 'noinline "disable-tail-calls"="true"' "$debug_ll"
rg -q 'uwtable "frame-pointer"="all"' "$debug_ll"

# A fresh compiler process can restore the same rendered Core bucket from
# disk. Populate only the lowered-Core snapshot first, render/store from a
# second invocation, then prove a third invocation is an exact disk hit.
TUNGSTEN_CACHE_DIR="$TMP/disk-cache" TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=0 \
  TUNGSTEN_LL_PATH="$TMP/disk-direct.ll" \
  "$TUNGSTEN" compile "$TMP/src/b.w" --out "$TMP/disk-direct" \
  "${flags[@]}" >/dev/null
TUNGSTEN_CACHE_DIR="$TMP/disk-cache" TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=1 \
  TUNGSTEN_LL_PATH="$TMP/disk-store.ll" \
  "$TUNGSTEN" compile "$TMP/src/a.w" --out "$TMP/disk-store" \
  "${flags[@]}" -v >"$TMP/disk-store.log" 2>&1
rg -q 'function emit cache: .*; disk stored' "$TMP/disk-store.log"
TUNGSTEN_CACHE_DIR="$TMP/disk-cache" TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=1 \
  TUNGSTEN_LL_PATH="$TMP/disk-hit.ll" \
  "$TUNGSTEN" compile "$TMP/src/b.w" --out "$TMP/disk-hit" \
  "${flags[@]}" -v >"$TMP/disk-hit.log" 2>&1
rg -q 'function emit cache: [1-9][0-9]* hits, 0 misses, [0-9]* bypassed; disk hit' \
  "$TMP/disk-hit.log"
cmp "$TMP/disk-direct.ll" "$TMP/disk-hit.ll"
cmp "$TMP/disk-direct.sidemap" "$TMP/disk-hit.sidemap"

# The checksummed graph reader must treat a corrupt rendered bucket as an
# ordinary miss, rerender safely, and atomically replace it.
render_bucket="$(find "$TMP/disk-cache" -maxdepth 1 -name 'core-render-v1-*.twc' | head -1)"
test -n "$render_bucket"
printf 'broken' >"$render_bucket"
TUNGSTEN_CACHE_DIR="$TMP/disk-cache" TUNGSTEN_FUNCTION_EMIT_DISK_CACHE=1 \
  TUNGSTEN_LL_PATH="$TMP/disk-repair.ll" \
  "$TUNGSTEN" compile "$TMP/src/b.w" --out "$TMP/disk-repair" \
  "${flags[@]}" -v >"$TMP/disk-repair.log" 2>&1
rg -q 'function emit cache: 0 hits, [1-9][0-9]* misses, [0-9]* bypassed; disk stored' \
  "$TMP/disk-repair.log"
cmp "$TMP/disk-direct.ll" "$TMP/disk-repair.ll"
cmp "$TMP/disk-direct.sidemap" "$TMP/disk-repair.sidemap"

echo "function emit cache: OK"
