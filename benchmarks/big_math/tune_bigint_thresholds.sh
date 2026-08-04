#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
LOG=${LOG:-"$ROOT/runtime/generated/bigint_thresholds.last.txt"}

REPS=${REPS:-9}
RANGES=${RANGES:-"8:512:8 640:4096:128"}

mkdir -p "$(dirname -- "$LOG")"

# shellcheck disable=SC2086
if "$DIR/run_toom_sweep.sh" --ntt --reps "$REPS" $RANGES > "$LOG"; then
  cat "$LOG"
else
  cat "$LOG"
  exit 1
fi

printf 'recorded forced-kernel sweep in %s\n' "$LOG"
printf '%s\n' 'No threshold header was generated. Validate each candidate cutoff with boxed affected-cell A/Bs.'
