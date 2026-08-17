#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-parallel-midend.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cache"
export TUNGSTEN_CACHE_DIR="$TMP/cache"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_FRONTEND_DISK_CACHE=0
export TUNGSTEN_FUNCTION_EMIT_CACHE=0
flags=(--emit-ll --release --native --fast --verbose)

# Workers only build read-only CFG/promotability summaries and independent
# ownership summaries. The parent performs every SSA/WIRE mutation in source
# function order, so 1/2/4/8 jobs must produce the same module and SSA roster.
for jobs in 1 2 4 8; do
  parallel=1
  if [[ "$jobs" == 1 ]]; then
    parallel=0
  fi
  TUNGSTEN_PARALLEL_MIDEND="$parallel" \
    TUNGSTEN_MIDEND_JOBS="$jobs" \
    TUNGSTEN_SSA_REPORT="$TMP/ssa-$jobs.txt" \
    TUNGSTEN_LL_PATH="$TMP/midend-$jobs.ll" \
    "$TUNGSTEN" compile compiler/tungsten.w --out "$TMP/midend-$jobs" \
      "${flags[@]}" >"$TMP/midend-$jobs.log" 2>&1
  if [[ "$jobs" != 1 ]]; then
    cmp "$TMP/midend-1.ll" "$TMP/midend-$jobs.ll"
    cmp "$TMP/midend-1.sidemap" "$TMP/midend-$jobs.sidemap"
    cmp "$TMP/ssa-1.txt" "$TMP/ssa-$jobs.txt"
    grep -q "cfg analysis workers: $jobs deterministic threads" \
      "$TMP/midend-$jobs.log"
    grep -q "ownership workers: $jobs deterministic threads" \
      "$TMP/midend-$jobs.log"
  fi
done

# Mid-end workers are also semantic-only in debug mode. Source-level
# backtraces must keep the exact noinline, no-tail, and frame-pointer policy.
for mode in serial parallel; do
  enabled=0
  if [[ "$mode" == parallel ]]; then
    enabled=1
  fi
  TUNGSTEN_PARALLEL_MIDEND="$enabled" \
    TUNGSTEN_MIDEND_JOBS=8 \
    TUNGSTEN_LL_PATH="$TMP/debug-$mode.ll" \
    "$TUNGSTEN" compile compiler/tungsten.w --out "$TMP/debug-$mode" \
      --emit-ll --debug --frame-pointers --native --fast --verbose \
      >"$TMP/debug-$mode.log" 2>&1
done
cmp "$TMP/debug-serial.ll" "$TMP/debug-parallel.ll"
cmp "$TMP/debug-serial.sidemap" "$TMP/debug-parallel.sidemap"
rg -q 'noinline "disable-tail-calls"="true"' "$TMP/debug-parallel.ll"
rg -q 'uwtable "frame-pointer"="all"' "$TMP/debug-parallel.ll"

# Process-parallel batches already have an outer worker pool and must not
# multiply it with a nested thread team.
TUNGSTEN_BATCH_WORKER_PROCESS=1 \
  TUNGSTEN_PARALLEL_MIDEND=1 \
  TUNGSTEN_MIDEND_JOBS=8 \
  TUNGSTEN_LL_PATH="$TMP/batch-child.ll" \
  "$TUNGSTEN" compile compiler/tungsten.w --out "$TMP/batch-child" \
    "${flags[@]}" >"$TMP/batch-child.log" 2>&1
cmp "$TMP/midend-1.ll" "$TMP/batch-child.ll"
cmp "$TMP/midend-1.sidemap" "$TMP/batch-child.sidemap"
if grep -q 'cfg analysis workers\|ownership workers' "$TMP/batch-child.log"; then
  echo "batch child unexpectedly created nested mid-end workers" >&2
  exit 1
fi

echo "parallel mid-end: OK"
