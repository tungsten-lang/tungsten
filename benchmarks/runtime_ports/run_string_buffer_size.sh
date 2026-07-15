#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-9}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-0.97}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-strbuf-size-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/string-buffer-size-ab"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
"$TUNGSTEN" compile "$SCRIPT_DIR/string_buffer_size_ab.w" --release --out "$BIN" >/dev/null

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

echo
printf '%-12s %12s %12s %10s %8s\n' "candidate" "C-method ns" "W-method ns" "W/C" "gate"
printf '%-12s %12s %12s %10s %8s\n' "------------" "------------" "------------" "----------" "--------"

for fn in 'size'; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  printf '%-12s %12.3f %12.3f %10.3f %8s\n' "$fn" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS paired alternating samples; retention requires W/C <= $GATE and an independent repeat below 1.00."
