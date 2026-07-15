#!/usr/bin/env bash
# Compile once, verify the full IEEE classification corpus, then apply the
# runtime-port performance gate to the uniquely named Tungsten candidate.

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
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-float-infinite-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/float-infinite-ab"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/float_infinite_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/float_infinite_ab.w" --release --out "$BIN" >/dev/null

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

c_med="$(awk -F'|' '$1 == "RESULT" && $2 == "infinite?" { print $3 }' "$RAW" | median_stream)"
w_med="$(awk -F'|' '$1 == "RESULT" && $2 == "infinite?" { print $4 }' "$RAW" | median_stream)"
ratio_med="$(awk -F'|' '$1 == "RESULT" && $2 == "infinite?" { print $5 }' "$RAW" | median_stream)"
decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"

echo
printf '%-12s %12s %12s %10s %8s\n' "function" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-12s %12s %12s %10s %8s\n' "------------" "------------" "------------" "----------" "--------"
printf '%-12s %12.3f %12.3f %10.3f %8s\n' "infinite?" "$c_med" "$w_med" "$ratio_med" "$decision"

echo
echo "Median of $RUNS paired alternating samples; retention requires W/C <= $GATE and an independent repeat below 1.00."
echo "Every timed pair checks an identical checksum; a SKIP result must not be migrated into production."
