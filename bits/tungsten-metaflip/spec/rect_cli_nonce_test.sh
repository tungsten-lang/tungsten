#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd)
COMPILER=${TUNGSTEN_COMPILER:-$REPO_ROOT/bin/tungsten-compiler}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-rect-cli-nonce.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM HUP

BINARY="$TMP_ROOT/metaflip"
RUNTIME="$PACKAGE_ROOT/lib/metaflip"

"$COMPILER" compile "$RUNTIME/fleet.w" --out "$BINARY" --release --native --lto

run_rect() {
  local name=$1
  shift
  local state="$TMP_ROOT/$name"
  mkdir -p "$state"
  "$BINARY" \
    --tensor 3x3x4 \
    --runtime-root "$RUNTIME" \
    --state-dir "$state" \
    --best "$state/best.txt" \
    --status "$state/status.txt" \
    --run-tag "$name" \
    -J 2 \
    --steps 20 \
    --rounds 1 \
    --no-gpu \
    --no-tui \
    --quiet \
    "$@" \
    > "$state/output.txt"
}

run_rect public_nonce --seed-nonce 17
grep -q 'cpu_seed_nonce=17 cpu_door_ticket=-1' "$TMP_ROOT/public_nonce/status.txt"
grep -q 'cpu_leader_lanes=1 cpu_side_lanes=1' "$TMP_ROOT/public_nonce/status.txt"
grep -q 'RECT_RESULT tensor=3x3x4 rank=29 bits=204 exact=1' "$TMP_ROOT/public_nonce/output.txt"

run_rect explicit_schedule --rect-restart-nonce 19 --rect-door-ticket 3
grep -q 'cpu_seed_nonce=19 cpu_door_ticket=3' "$TMP_ROOT/explicit_schedule/status.txt"
grep -q 'RECT_RESULT tensor=3x3x4 rank=29 bits=204 exact=1' "$TMP_ROOT/explicit_schedule/output.txt"
grep -Eq 'side_archive_saved=[1-9][0-9]*' "$TMP_ROOT/explicit_schedule/status.txt"

run_rect explicit_schedule --rect-restart-nonce 20 --rect-door-ticket 4
grep -q 'cpu_seed_nonce=20 cpu_door_ticket=4' "$TMP_ROOT/explicit_schedule/status.txt"
grep -Eq 'side_archive_loaded=[1-9][0-9]*' "$TMP_ROOT/explicit_schedule/status.txt"
grep -Eq 'side_archive_seeded=[1-9][0-9]*' "$TMP_ROOT/explicit_schedule/status.txt"

wide_state="$TMP_ROOT/wide_schedule"
mkdir -p "$wide_state"
"$BINARY" \
  --tensor 3x3x4 \
  --runtime-root "$RUNTIME" \
  --state-dir "$wide_state" \
  --best "$wide_state/best.txt" \
  --status "$wide_state/status.txt" \
  --run-tag wide_schedule \
  -J 64 \
  --steps 20 \
  --rounds 1 \
  --no-gpu \
  --no-tui \
  --quiet \
  --rect-restart-nonce 23 \
  --rect-door-ticket 5 \
  > "$wide_state/output.txt"
grep -q 'cpu_leader_lanes=32 cpu_side_lanes=32' "$wide_state/status.txt"
grep -q 'RECT_RESULT tensor=3x3x4 rank=29 bits=204 exact=1' "$wide_state/output.txt"

if "$BINARY" \
  --tensor 3x3x4 \
  --runtime-root "$RUNTIME" \
  --state-dir "$TMP_ROOT/conflict" \
  --seed-nonce 17 \
  --rect-restart-nonce 19 \
  --no-gpu \
  --no-tui \
  --quiet \
  > "$TMP_ROOT/conflict.txt" 2>&1; then
  printf 'expected conflicting rectangular nonce controls to fail\n' >&2
  exit 1
fi
grep -q 'conflicting --seed-nonce and --rect-restart-nonce values' "$TMP_ROOT/conflict.txt"

if "$BINARY" \
  --tensor 3x3 \
  --runtime-root "$RUNTIME" \
  --state-dir "$TMP_ROOT/square" \
  --rect-restart-nonce 3 \
  --no-gpu \
  --no-tui \
  --quiet \
  > "$TMP_ROOT/square.txt" 2>&1; then
  printf 'expected square use of --rect-restart-nonce to fail\n' >&2
  exit 1
fi
grep -q -- '--rect-restart-nonce requires one explicit rectangular --tensor' "$TMP_ROOT/square.txt"

printf 'PASS rectangular CLI nonce and door schedule\n'
