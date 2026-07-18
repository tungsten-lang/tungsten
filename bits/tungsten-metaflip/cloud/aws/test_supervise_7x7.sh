#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUPERVISOR="$SCRIPT_DIR/supervise_7x7.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-aws-supervisor.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM HUP

RUNTIME="$TMP_ROOT/runtime"
SEEDS="$RUNTIME/seeds/gf2"
STATE="$TMP_ROOT/state-not-created"
LOG="$TMP_ROOT/log-not-created"
FAKE_BINARY="$TMP_ROOT/metaflip"
OUTPUT="$TMP_ROOT/dry-run.txt"
NONCE_OUTPUT="$TMP_ROOT/dry-run-nonce.txt"
MISMATCH_OUTPUT="$TMP_ROOT/dry-run-mismatch.txt"

mkdir -p "$SEEDS"
: > "$RUNTIME/fleet.w"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BINARY"
chmod +x "$FAKE_BINARY"

# Structural fixtures exercise both accepted scheme serializations: a rank
# header plus 247 rows, and 247 raw rows with no header.
seed=0
while [ "$seed" -lt 3 ]; do
  path=$(printf '%s/matmul_7x7_rank247_fixture%02d_gf2.txt' "$SEEDS" "$seed")
  if [ $((seed % 2)) -eq 0 ]; then
    printf '247\n' > "$path"
  else
    : > "$path"
  fi
  row=0
  while [ "$row" -lt 247 ]; do
    printf '1 1 1\n' >> "$path"
    row=$((row + 1))
  done
  seed=$((seed + 1))
done

"$SUPERVISOR" \
  --dry-run \
  --binary "$FAKE_BINARY" \
  --runtime-root "$RUNTIME" \
  --state-root "$STATE" \
  --log-root "$LOG" \
  --seconds 17 \
  --campaign-tag test-campaign \
  > "$OUTPUT"

failures=0
expect() {
  local label=$1
  shift
  if "$@"; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

count=$(grep -c '^DRY_RUN shard=' "$OUTPUT" || true)
expect 'default topology emits three NUMA-sized shards' test "$count" -eq 3
expect 'node 3 is CPU- and memory-bound' grep -q -- '--cpunodebind=3 --membind=3' "$OUTPUT"
expect 'node 4 is CPU- and memory-bound' grep -q -- '--cpunodebind=4 --membind=4' "$OUTPUT"
expect 'node 5 is CPU- and memory-bound' grep -q -- '--cpunodebind=5 --membind=5' "$OUTPUT"
expect 'default walker count is J64' grep -q -- '-J 64' "$OUTPUT"
expect 'node 3 has distinct productive fallback budget' grep -q -- '--steps 48000011' "$OUTPUT"
expect 'node 4 has distinct productive fallback budget' grep -q -- '--steps 50000021' "$OUTPUT"
expect 'node 5 has distinct productive fallback budget' grep -q -- '--steps 52000031' "$OUTPUT"
expect 'explicit seeds are passed' grep -q -- '--seed ' "$OUTPUT"
unique_seeds=$(grep '^DRY_RUN shard=' "$OUTPUT" | sed 's/.* seed=\([^ ]*\) state=.*/\1/' | sort -u | wc -l | tr -d ' ')
expect 'three nodes receive three distinct anchors' test "$unique_seeds" -eq 3
expect 'children are CPU-only and stop below r247' grep -q -- '--no-gpu --no-tui --stop-on-record' "$OUTPUT"
expect 'state, best, status, near, and log paths are separate' \
  grep -q -- 'state=.*/state/.* best=.*/best/.* status=.*/status/.* near=.*/near/.* log=.*/log-not-created/' "$OUTPUT"
expect 'dry-run writes no state root' test ! -e "$STATE"
expect 'dry-run writes no log root' test ! -e "$LOG"

# Auto mode must require support in both the runtime parser and native binary.
# A newly synced runtime paired with an older binary keeps the safe fallback.
printf 'value_options = ["--seed-nonce"]\n' > "$RUNTIME/fleet.w"
"$SUPERVISOR" \
  --dry-run \
  --binary "$FAKE_BINARY" \
  --runtime-root "$RUNTIME" \
  --state-root "$STATE" \
  --log-root "$LOG" \
  --campaign-tag mismatch-campaign \
  > "$MISMATCH_OUTPUT"
expect 'runtime/binary mismatch does not pass an unsupported nonce flag' \
  grep -q -- 'diversity=per-node-steps' "$MISMATCH_OUTPUT"

# With both markers present, use a common adaptive nominal budget plus unique
# shard nonces.
printf '#!/bin/sh\n# parser marker: --seed-nonce\nexit 0\n' > "$FAKE_BINARY"
"$SUPERVISOR" \
  --dry-run \
  --binary "$FAKE_BINARY" \
  --runtime-root "$RUNTIME" \
  --state-root "$STATE" \
  --log-root "$LOG" \
  --campaign-tag nonce-campaign \
  > "$NONCE_OUTPUT"
expect 'auto mode detects square seed nonce in runtime and binary' \
  grep -q -- 'diversity=seed-nonce' "$NONCE_OUTPUT"
nonce_count=$(grep -c -- '--seed-nonce ' "$NONCE_OUTPUT" || true)
expect 'all three shards receive unique nonce arguments' test "$nonce_count" -eq 3
common_count=$(grep -c -- '--steps 500000' "$NONCE_OUTPUT" || true)
expect 'nonce mode uses common adaptive nominal steps' test "$common_count" -eq 3

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d supervisor dry-run assertion(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: supervisor dry-run contract\n'
