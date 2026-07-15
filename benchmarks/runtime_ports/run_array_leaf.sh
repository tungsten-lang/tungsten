#!/usr/bin/env bash
# Compile once, verify exact current-C/candidate-W behavior, then gate each
# Array leaf candidate on the median paired W/C ratio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-7}"
ITERS="${ITERS:-10000000}"
GATE="${GATE:-0.97}"
ONLY="${ONLY:-}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$ONLY" in
  ''|size|cap|empty\?|first|last) ;;
  *) echo "ONLY must be one of: size cap empty? first last" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-leaf-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/array-leaf-ab"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_leaf_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_leaf_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

echo "Running $RUNS samples x $ITERS iterations per function and implementation${ONLY:+ ($ONLY only)}..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" "$ONLY" >> "$RAW"
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
printf '%-10s %12s %12s %10s %8s\n' "function" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-10s %12s %12s %10s %8s\n' "----------" "------------" "------------" "----------" "--------"

if [ -n "$ONLY" ]; then
  functions=("$ONLY")
else
  functions=(size cap 'empty?' first last)
fi
for fn in "${functions[@]}"; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  printf '%-10s %12.3f %12.3f %10.3f %8s\n' "$fn" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS paired alternating samples; PASS requires W/C <= $GATE. Every pair verifies an identical checksum."
