#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd)
COMPILER=${TUNGSTEN_COMPILER:-$REPO_ROOT/bin/tungsten-compiler}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-rect-cli-rounds.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM HUP

BINARY="$TMP_ROOT/metaflip"
RUNTIME="$PACKAGE_ROOT/lib/metaflip"

"$COMPILER" compile "$RUNTIME/fleet.w" --out "$BINARY" --release --native --lto

run_portfolio() {
  local name=$1
  shift
  local state="$TMP_ROOT/$name"
  mkdir -p "$state"
  "$BINARY" \
    --rect \
    --rect-shapes 3x3x4 \
    --runtime-root "$RUNTIME" \
    --state-dir "$state" \
    --status "$state/status.txt" \
    --run-tag "$name" \
    -J 1 \
    --steps 1 \
    --rounds 1 \
    --secs 0 \
    --no-gpu \
    --no-tui \
    --quiet \
    "$@" \
    > "$state/output.txt"
}

# Raising the accepted ceiling must not silently raise the generic portfolio
# default: one worker, one step, and one default epoch still means 16 moves.
run_portfolio default_rounds
grep -Eq '(^| )epoch=1( |$)' "$TMP_ROOT/default_rounds/status.txt"
grep -Eq '(^| )total_moves=16( |$)' "$TMP_ROOT/default_rounds/status.txt"

# The AWS single-shape parent can explicitly amortize its process boundary all
# the way through the new inclusive ceiling.
run_portfolio maximum_rounds --rect-epoch-rounds 256
grep -Eq '(^| )epoch=1( |$)' "$TMP_ROOT/maximum_rounds/status.txt"
grep -Eq '(^| )total_moves=256( |$)' "$TMP_ROOT/maximum_rounds/status.txt"
grep -Eq '(^| )failures=0( |$)' "$TMP_ROOT/maximum_rounds/status.txt"

if "$BINARY" \
  --rect \
  --rect-shapes 3x3x4 \
  --runtime-root "$RUNTIME" \
  --state-dir "$TMP_ROOT/above_maximum" \
  --rect-epoch-rounds 257 \
  --rounds 1 \
  --no-gpu \
  --no-tui \
  --quiet \
  > "$TMP_ROOT/above_maximum.txt" 2>&1; then
  printf 'expected --rect-epoch-rounds 257 to fail\n' >&2
  exit 1
fi
grep -q -- '--rect-epoch-rounds must be 1 through 256' "$TMP_ROOT/above_maximum.txt"

printf 'PASS rectangular CLI epoch-round boundaries and default\n'
