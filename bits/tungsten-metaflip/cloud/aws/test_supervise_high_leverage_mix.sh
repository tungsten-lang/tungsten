#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUPERVISOR="$SCRIPT_DIR/supervise_high_leverage_mix.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-aws-high-leverage.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM HUP

RUNTIME="$TMP_ROOT/runtime"
SEEDS="$RUNTIME/seeds/gf2"
STATE="$TMP_ROOT/state-not-created"
LOG="$TMP_ROOT/log-not-created"
FAKE_BINARY="$TMP_ROOT/metaflip"
OUTPUT="$TMP_ROOT/dry-run.txt"

mkdir -p "$SEEDS"
cat > "$RUNTIME/fleet.w" <<'EOF'
value_options = [
  "--rect", "--rect-shapes", "--rect-epoch-rounds",
  "--rect-portfolio-child", "--rect-restart-nonce", "--rect-door-ticket",
  "--seed-nonce"
]
message = "--rect-epoch-rounds must be 1 through 256"
EOF
cat > "$FAKE_BINARY" <<'EOF'
#!/bin/sh
# --rect --rect-shapes --rect-epoch-rounds --rect-portfolio-child
# --rect-restart-nonce --rect-door-ticket --seed-nonce
# --rect-epoch-rounds must be 1 through 256
exit 0
EOF
chmod +x "$FAKE_BINARY"

SEED="$SEEDS/matmul_7x7_rank247_fixture_gf2.txt"
printf '247\n' > "$SEED"
row=0
while [ "$row" -lt 247 ]; do
  printf '1 1 1\n' >> "$SEED"
  row=$((row + 1))
done

"$SUPERVISOR" \
  --dry-run \
  --binary "$FAKE_BINARY" \
  --runtime-root "$RUNTIME" \
  --state-root "$STATE" \
  --log-root "$LOG" \
  --seconds 77 \
  --campaign-tag test-high-leverage \
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

expect 'preset summary pins the five high-leverage rectangular shapes' \
  grep -q -- 'rect_shapes=4x4x5,4x5x7,4x6x7,3x4x6,2x5x6' "$OUTPUT"
expect 'rectangular supervisor receives nodes zero through four' \
  grep -q -- 'shapes=4x4x5,4x5x7,4x6x7,3x4x6,2x5x6 nodes=0,1,2,3,4' "$OUTPUT"
parent_count=$(grep -c '^DRY_RUN parent=' "$OUTPUT" || true)
expect 'preset emits five rectangular NUMA parents' test "$parent_count" -eq 5
expect 'rectangular children use the 256-round leased-door cadence' \
  grep -q -- 'lease_rounds=256' "$OUTPUT"
expect 'wrapper disables the rectangular supervisor shutdown owner' \
  grep -q -- 'DRY_RUN campaign=test-high-leverage_rect .* shutdown=0' "$OUTPUT"
expect 'square supervisor receives exactly node five' \
  grep -q -- 'campaign=test-high-leverage_7x7 .*children=1 nodes=5 ' "$OUTPUT"
expect 'square child receives a distinct seed nonce' \
  grep -q -- '--tensor 7x7 .* --seed-nonce 1' "$OUTPUT"
expect 'shared wall deadline reaches both child supervisors' \
  sh -c 'test "$(grep -c "seconds=77" "$1")" -eq 3' sh "$OUTPUT"
expect 'dry-run writes no state root' test ! -e "$STATE"
expect 'dry-run writes no log root' test ! -e "$LOG"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d high-leverage preset assertion(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: high-leverage mixed preset dry-run contract\n'
