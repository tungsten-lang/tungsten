#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-program-index.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$TUNGSTEN" ]]; then
  echo "missing compiler: $TUNGSTEN" >&2
  exit 1
fi

fixtures=(
  compiler/test/fixtures/simple.w
  compiler/test/fixtures/capture.w
  compiler/test/fixtures/elsif.w
  compiler/test/fixtures/generic_constraint_valid_inherited.w
  compiler/test/fixtures/core_abi_stable_b.w
  compiler/test/fixtures/locked_return_class_sets.w
)

for fixture in "${fixtures[@]}"; do
  name="$(basename "$fixture" .w)"
  for mode in 0 1; do
    env \
      TUNGSTEN_ROOT="$ROOT" \
      TUNGSTEN_INCREMENTAL=0 \
      TUNGSTEN_FRONTEND_DISK_CACHE=0 \
      TUNGSTEN_PROGRAM_INDEX="$mode" \
      TUNGSTEN_LL_PATH="$TMP/$name-$mode.ll" \
      "$TUNGSTEN" compile "$ROOT/$fixture" --emit-ll \
        --release --native --fast --no-debug >"$TMP/$name-$mode.log" 2>&1
  done
  cmp "$TMP/$name-0.ll" "$TMP/$name-1.ll"
done

# The index is analysis-only: debug builds retain their physical backtrace
# frame contract and remain byte-identical to the legacy discovery walks.
for mode in 0 1; do
  env \
    TUNGSTEN_ROOT="$ROOT" \
    TUNGSTEN_INCREMENTAL=0 \
    TUNGSTEN_FRONTEND_DISK_CACHE=0 \
    TUNGSTEN_PROGRAM_INDEX="$mode" \
    TUNGSTEN_LL_PATH="$TMP/debug-$mode.ll" \
    "$TUNGSTEN" compile "$ROOT/compiler/test/fixtures/core_abi_stable_b.w" \
      --emit-ll --debug --frame-pointers --native --fast \
      >"$TMP/debug-$mode.log" 2>&1
done
cmp "$TMP/debug-0.ll" "$TMP/debug-1.ll"
grep -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-1.ll"
grep -q 'uwtable "frame-pointer"="all"' "$TMP/debug-1.ll"

echo "one-pass program index: PASS"
