#!/usr/bin/env bash
# Compile once, verify exact current-C/candidate-W behavior, then gate the
# String#empty? candidate on the median paired W/C ratio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-1.10}"

case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-string-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/string-ab"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/string_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/string_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

echo "Running $RUNS balanced C/W/W/C samples x $ITERS iterations per leg..."
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

c_med="$(awk -F'|' '$1 == "RESULT" { print $3 }' "$RAW" | median_stream)"
w_med="$(awk -F'|' '$1 == "RESULT" { print $4 }' "$RAW" | median_stream)"
ratio_med="$(awk -F'|' '$1 == "RESULT" { print $5 }' "$RAW" | median_stream)"
decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"

echo
printf '%-10s %12s %12s %10s %8s\n' "function" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-10s %12s %12s %10s %8s\n' "----------" "------------" "------------" "----------" "--------"
printf '%-10s %12.3f %12.3f %10.3f %8s\n' "empty?" "$c_med" "$w_med" "$ratio_med" "$decision"

echo
echo "Median of $RUNS balanced four-leg samples; PASS requires W/C <= $GATE. Every pair verifies an identical checksum."
