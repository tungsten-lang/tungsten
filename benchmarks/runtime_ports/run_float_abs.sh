#!/usr/bin/env bash
# Exact correctness and strict balanced-ABBA gate for a source Float#abs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-1.10}"
CHECK_ONLY="${CHECK_ONLY:-0}"

case "$RUNS" in
  ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;;
esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$CHECK_ONLY" in
  0|1) ;;
  *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-float-abs-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/float-abs-ab"
WIRE="$TMP/float-abs-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Inspecting unique source candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/float_abs_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/float_abs_ab.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function __w_Float___w_abs__a1(/,/^$/p" "$WIRE"
}
if ! wire_body | rg -q 'and_i64'; then
  echo "WIRE check failed: Float#__w_abs lacks the raw sign-mask operation" >&2
  exit 1
fi
if ! wire_body | rg -q 'icmp_i64'; then
  echo "WIRE check failed: Float#__w_abs lacks the NaN canonicalization guard" >&2
  exit 1
fi
if wire_body | rg -q 'call_(method|direct)_i64.*abs'; then
  echo "WIRE check failed: Float#__w_abs recursively calls an abs method" >&2
  exit 1
fi
echo "WIRE: ok (unbias, sign mask, NaN guard, and rebias remain source-native)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/float_abs_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/float_abs_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W/public behavior..."
"$BIN" check

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: compile, WIRE, and exact correctness gates passed; timings skipped."
  exit 0
fi

strata=(finite edge nan)
: > "$RAW"
echo "Running $RUNS balanced ABBA samples per stratum x $ITERS iterations/leg..."
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  for stratum in "${strata[@]}"; do
    if [ "$parity" -eq 0 ]; then orientation="C/W/W/C"; else orientation="W/C/C/W"; fi
    echo "  sample $i/$RUNS $stratum ($orientation)" >&2
    "$BIN" bench "$ITERS" "$parity" "$stratum" >> "$RAW"
  done
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
printf '%-12s %12s %12s %10s %8s\n' "stratum" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-12s %12s %12s %10s %8s\n' "------------" "------------" "------------" "----------" "--------"

failed=0
for stratum in "${strata[@]}"; do
  c_med="$(awk -F'|' -v s="$stratum" '$1 == "RESULT" && $2 == s { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v s="$stratum" '$1 == "RESULT" && $2 == s { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v s="$stratum" '$1 == "RESULT" && $2 == s { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  if [ "$decision" = "SKIP" ]; then failed=1; fi
  printf '%-12s %12.3f %12.3f %10.3f %8s\n' "$stratum" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS samples with balanced ABBA/BAAB orientations."
echo "Retention requires every stratum W/C <= $GATE and a fresh rebuild/run with every stratum at or below $GATE."

if [ "$failed" -ne 0 ]; then
  echo "Strict gate: at least one important stratum is SKIP; keep Float#abs in C." >&2
  exit 3
fi
