#!/usr/bin/env bash
# Compile once, verify exact behavior, then time individual collection methods.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-5}"
ITERS="${ITERS:-10000}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-enumerable-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/enumerable-ab"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/enumerable_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/enumerable_ab.w" --release --out "$BIN" >/dev/null

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
    { value[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) print value[(NR + 1) / 2]
      else print (value[NR / 2] + value[NR / 2 + 1]) / 2
    }
  '
}

echo
printf '%-17s %12s %12s %10s\n' "function" "C-method ns" "W-method ns" "W/C"
printf '%-17s %12s %12s %10s\n' "-----------------" "------------" "------------" "----------"

for fn in 'array.map' 'hash.map' 'select' 'reject' 'find' 'detect' 'reduce' \
          'each_with_index' 'group_by' 'partition' 'tally' 'flat_map'; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  printf '%-17s %12.3f %12.3f %10.3f\n' "$fn" "$c_med" "$w_med" "$ratio_med"
done

echo
echo "Median of $RUNS paired samples on i16[64] (Hash uses 64 entries); every timed pair verifies an identical checksum."
