#!/usr/bin/env bash
# Compile once, verify exact behavior, then time String#empty? only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS="${RUNS:-5}"
ITERS="${ITERS:-2000000}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
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
  bin/tungsten compile "$SCRIPT_DIR/string_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

echo "Running $RUNS samples x $ITERS iterations per implementation..."
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

echo
printf '%-10s %12s %12s %10s\n' "function" "C-method ns" "W-method ns" "W/C"
printf '%-10s %12s %12s %10s\n' "----------" "------------" "------------" "----------"
printf '%-10s %12.3f %12.3f %10.3f\n' "empty?" "$c_med" "$w_med" "$ratio_med"

echo
echo "Median of $RUNS paired, alternating samples; every timed loop checks an identical checksum."
