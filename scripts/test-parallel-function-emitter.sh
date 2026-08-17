#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parallel-function-emitter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_DISK_CACHE=0
export TUNGSTEN_FUNCTION_EMIT_CACHE=0

# The full compiler is large enough to exercise the worker threshold and has
# loop/alias metadata, embedded bodies, and ordinary instruction rendering.
for jobs in 1 2 4 8; do
  parallel=1
  if [[ "$jobs" == 1 ]]; then
    parallel=0
  fi
  TUNGSTEN_PARALLEL_FUNCTION_EMIT="$parallel" \
    TUNGSTEN_EMITTER_JOBS="$jobs" \
    TUNGSTEN_LL_PATH="$TMP/release-$jobs.ll" \
    "$TUNGSTEN" compile compiler/tungsten.w --out "$TMP/release-$jobs" \
      --emit-ll --release --native --fast --verbose \
      >"$TMP/release-$jobs.log" 2>&1
  if [[ "$jobs" != 1 ]]; then
    cmp "$TMP/release-1.ll" "$TMP/release-$jobs.ll"
    cmp "$TMP/release-1.sidemap" "$TMP/release-$jobs.sidemap"
    grep -q "function emit workers: $jobs deterministic threads" \
      "$TMP/release-$jobs.log"
  fi
done

# --release itself is the non-debug profile; no paired --no-debug flag is
# needed to reach the parallel path.
if grep -q "function emit workers" "$TMP/release-1.log"; then
  echo "serial release unexpectedly reported emitter workers" >&2
  exit 1
fi

# Debug builds deliberately stay serial and retain physical backtrace frames,
# even when parallel emission is requested.
for mode in serial requested; do
  parallel=0
  if [[ "$mode" == requested ]]; then
    parallel=1
  fi
  TUNGSTEN_PARALLEL_FUNCTION_EMIT="$parallel" \
    TUNGSTEN_EMITTER_JOBS=8 \
    TUNGSTEN_LL_PATH="$TMP/debug-$mode.ll" \
    "$TUNGSTEN" compile compiler/test/fixtures/core_abi_stable_b.w \
      --out "$TMP/debug-$mode" --emit-ll --debug --frame-pointers \
      --native --fast --verbose >"$TMP/debug-$mode.log" 2>&1
done
cmp "$TMP/debug-serial.ll" "$TMP/debug-requested.ll"
cmp "$TMP/debug-serial.sidemap" "$TMP/debug-requested.sidemap"
if grep -q "function emit workers" "$TMP/debug-requested.log"; then
  echo "debug build unexpectedly used parallel function emission" >&2
  exit 1
fi
rg -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-requested.ll"
rg -q 'uwtable "frame-pointer"="all"' "$TMP/debug-requested.ll"

# Process-parallel compile-batch children must not create nested thread teams.
TUNGSTEN_BATCH_WORKER_PROCESS=1 \
  TUNGSTEN_PARALLEL_FUNCTION_EMIT=1 \
  TUNGSTEN_EMITTER_JOBS=8 \
  TUNGSTEN_LL_PATH="$TMP/batch-child.ll" \
  "$TUNGSTEN" compile compiler/tungsten.w --out "$TMP/batch-child" \
    --emit-ll --release --native --fast --verbose \
    >"$TMP/batch-child.log" 2>&1
cmp "$TMP/release-1.ll" "$TMP/batch-child.ll"
if grep -q "function emit workers" "$TMP/batch-child.log"; then
  echo "batch child unexpectedly created nested emitter workers" >&2
  exit 1
fi

echo "parallel function emitter: OK"
