#!/usr/bin/env bash
# Compile once, verify Date C/W behavior, then measure individual functions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS="${RUNS:-5}"
ITERS="${ITERS:-10000000}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-date-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/date-ab"
RAW="$TMP/results.txt"
if [ -n "${TUNGSTEN_COMPILER:-}" ]; then
  COMPILE=("$TUNGSTEN_COMPILER" compile)
else
  COMPILE=("$ROOT/bin/tungsten" compile)
fi

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/date_ref.c" \
  "${COMPILE[@]}" "$SCRIPT_DIR/date_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

echo "Running $RUNS samples x $ITERS iterations per function and implementation..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" >> "$RAW"
  i=$((i + 1))
done

median_stream() {
  sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) print v[(NR + 1) / 2]
      else print (v[NR / 2] + v[NR / 2 + 1]) / 2
    }
  '
}

echo
printf '%-16s %12s %12s %10s\n' "function" "C-method ns" "W-method ns" "W/C"
printf '%-16s %12s %12s %10s\n' "----------------" "------------" "------------" "----------"

for fn in year month day hour minute second wday day_of_week day_of_month \
          day_of_year yday cweek cwday days_in_month days_in_year 'leap?' \
          jd quarter tz; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  printf '%-16s %12.3f %12.3f %10.3f\n' "$fn" "$c_med" "$w_med" "$ratio_med"
done

echo
echo "Median of $RUNS; W/C is the median paired sample ratio. Every loop verifies an identical checksum."
