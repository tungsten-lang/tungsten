#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-core-reachability-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
program="benchmarks/compiler/method_lock_locked.w"
release_flags=(--release --native --fast --no-debug --emit-ll)

TUNGSTEN_CORE_REACHABILITY=0 TUNGSTEN_LL_PATH="$TMP/full.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/full" \
  "${release_flags[@]}" -v >"$TMP/full.log" 2>&1
TUNGSTEN_CORE_REACHABILITY=1 TUNGSTEN_LL_PATH="$TMP/reachable.ll" \
  "$TUNGSTEN" compile "$program" --out "$TMP/reachable" \
  "${release_flags[@]}" -v >"$TMP/reachable.log" 2>&1

if ! grep -E 'core reachability: [0-9]+/[0-9]+ kept \([1-9][0-9]* pruned\)' \
    "$TMP/reachable.log" >/dev/null; then
  echo "FAIL: locked protected program did not select a nonempty Core slice" >&2
  cat "$TMP/reachable.log" >&2
  exit 1
fi
full_defines="$(grep -c '^define ' "$TMP/full.ll")"
reachable_defines="$(grep -c '^define ' "$TMP/reachable.ll")"
if (( reachable_defines >= full_defines )); then
  echo "FAIL: reachable module has $reachable_defines definitions; full module has $full_defines" >&2
  exit 1
fi

TUNGSTEN_CORE_REACHABILITY=1 \
  "$TUNGSTEN" compile compiler/test/fixtures/closed_world_dispatch.w \
  --out "$TMP/closed" --dev --native --fast --no-debug >/dev/null 2>&1
if [[ "$("$TMP/closed")" != "42" ]]; then
  echo "FAIL: reachable closed-world executable returned unexpected output" >&2
  exit 1
fi

TUNGSTEN_CORE_REACHABILITY=1 \
  "$TUNGSTEN" compile compiler/test/fixtures/core_reachability_reflection.w \
  --out "$TMP/reflection" --dev --native --fast --no-debug -v \
  >"$TMP/reflection.log" 2>&1
if ! grep -E 'core reachability: fallback \(live reflective method access' \
    "$TMP/reflection.log" >/dev/null; then
  echo "FAIL: reflective method access did not fail closed" >&2
  cat "$TMP/reflection.log" >&2
  exit 1
fi
if [[ "$("$TMP/reflection")" != $'true\n42' ]]; then
  echo "FAIL: reflective fallback executable returned unexpected output" >&2
  exit 1
fi

echo "Core reachability: ok ($reachable_defines/$full_defines LLVM definitions)"
