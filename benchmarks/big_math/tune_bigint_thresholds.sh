#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
LOG=${LOG:-"$ROOT/runtime/generated/bigint_thresholds.last.txt"}

REPS=${REPS:-9}
RANGES=${RANGES:-"8:512:8 640:4096:128"}
SQR_RANGES=${SQR_RANGES:-"8:512:8 640:4096:128"}
# GENERATE=1 (default): after recording, run the sound generate step —
# conservative crossover proposals from the best-of-9 sweep, each validated
# with the boxed affected-cell A/B before it may replace a default.
# GENERATE=0 restores the record-only behavior.
GENERATE=${GENERATE:-1}

mkdir -p "$(dirname -- "$LOG")"

# shellcheck disable=SC2086
{
  "$DIR/run_toom_sweep.sh" --ntt --reps "$REPS" $RANGES &&
  "$DIR/run_toom_sweep.sh" --square --reps "$REPS" $SQR_RANGES
} > "$LOG" || { cat "$LOG"; exit 1; }
cat "$LOG"

printf 'recorded forced-kernel sweep in %s\n' "$LOG"

if [ "$GENERATE" = "1" ]; then
  python3 "$DIR/generate_bigint_thresholds.py" --sweep-log "$LOG" "$@"
else
  printf '%s\n' 'No threshold header was generated (GENERATE=0). Validate each candidate cutoff with boxed affected-cell A/Bs.'
fi
