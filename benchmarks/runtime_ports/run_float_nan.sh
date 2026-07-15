#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-0.97}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-float-nan-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/float-nan-ab"
RAW="$TMP/results.txt"
cd "$ROOT"
echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/float_nan_ref.c" bin/tungsten compile "$SCRIPT_DIR/float_nan_ab.w" --release --out "$BIN" >/dev/null
echo "Checking exact C/W behavior..."
"$BIN" check
echo "Running $RUNS alternating paired samples x $ITERS iterations..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" >> "$RAW"
  i=$((i + 1))
done
median_stream() { sort -n | awk '{ v[NR]=$1 } END { if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2 }'; }
c_med="$(awk -F'|' '$1=="RESULT" {print $3}' "$RAW" | median_stream)"
w_med="$(awk -F'|' '$1=="RESULT" {print $4}' "$RAW" | median_stream)"
ratio_med="$(awk -F'|' '$1=="RESULT" {print $5}' "$RAW" | median_stream)"
decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
printf '\n%-12s %12s %12s %10s %8s\n' function 'C-method ns' W-candidate W/C gate
printf '%-12s %12.3f %12.3f %10.3f %8s\n' 'nan?' "$c_med" "$w_med" "$ratio_med" "$decision"
echo "Retention requires W/C <= $GATE and an independent repeat below 1.00."
