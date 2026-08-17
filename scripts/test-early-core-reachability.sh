#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-early-core-reachability.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_DISK_CACHE=0
program="benchmarks/compiler/return_class_set_scc.w"
release_flags=(--release --native --fast --emit-ll)

# Publish the complete post-mid-end Core artifact. Early slicing is
# intentionally a warm-hit optimization; a cold entry must remain reusable by
# a different program.
TUNGSTEN_EARLY_CORE_REACHABILITY=1 TUNGSTEN_LL_PATH="$TMP/cold.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/cold" \
  "${release_flags[@]}" -v >"$TMP/cold.log" 2>&1
grep -q 'core cache: miss' "$TMP/cold.log"

for mode in 0 1; do
  TUNGSTEN_EARLY_CORE_REACHABILITY="$mode" \
    TUNGSTEN_LL_PATH="$TMP/release-$mode.ll" \
    "$TUNGSTEN" compile "$program" --out "$TMP/release-$mode" \
    "${release_flags[@]}" -v >"$TMP/release-$mode.log" 2>&1
done
cmp "$TMP/release-0.ll" "$TMP/release-1.ll"
cmp "$TMP/release-0.sidemap" "$TMP/release-1.sidemap"

full_total="$(sed -nE 's/.*content hash work set: [0-9]+\/([0-9]+) functions.*/\1/p' "$TMP/release-0.log")"
live_total="$(sed -nE 's/.*content hash work set: [0-9]+\/([0-9]+) functions.*/\1/p' "$TMP/release-1.log")"
if [[ -z "$full_total" || -z "$live_total" || "$live_total" -ge "$full_total" ]]; then
  echo "FAIL: early Core reachability did not shrink the warm pipeline ($live_total/$full_total)" >&2
  cat "$TMP/release-0.log" "$TMP/release-1.log" >&2
  exit 1
fi

# Debug uses a separate Core cache key. Warm it, then prove the early slice is
# representation-only: physical source backtrace frames and exact LLVM remain.
debug_flags=(--debug --frame-pointers --native --fast --emit-ll)
TUNGSTEN_EARLY_CORE_REACHABILITY=1 TUNGSTEN_LL_PATH="$TMP/debug-cold.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/debug-cold" \
  "${debug_flags[@]}" >/dev/null 2>&1
for mode in 0 1; do
  TUNGSTEN_EARLY_CORE_REACHABILITY="$mode" \
    TUNGSTEN_LL_PATH="$TMP/debug-$mode.ll" \
    "$TUNGSTEN" compile "$program" --out "$TMP/debug-$mode" \
    "${debug_flags[@]}" >/dev/null 2>&1
done
cmp "$TMP/debug-0.ll" "$TMP/debug-1.ll"
grep -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-1.ll"
grep -q 'uwtable "frame-pointer"="all"' "$TMP/debug-1.ll"

echo "early Core reachability: ok ($live_total/$full_total warm functions)"
