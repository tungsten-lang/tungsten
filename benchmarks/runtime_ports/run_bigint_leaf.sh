#!/usr/bin/env bash
# Strict gate for cheap BigInt IC-to-source candidates. Compile/WIRE/correctness
# are setup; only the paired method loops are timed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
ARITH_ITERS="${ARITH_ITERS:-5000000}"
GATE="${GATE:-0.97}"
ONLY="${ONLY:-}"
CHECK_ONLY="${CHECK_ONLY:-0}"
DIRECT_ONLY="${DIRECT_ONLY:-0}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$ARITH_ITERS" in
  ''|*[!0-9]*|0) echo "ARITH_ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$ONLY" in
  ''|to_i|prev|succ|next|zero\?|even\?|odd\?|negative\?|positive\?|direct-zero\?|direct-even\?|direct-odd\?|direct-negative\?|direct-positive\?) ;;
  *) echo "ONLY names an unknown BigInt leaf candidate" >&2; exit 2 ;;
esac
case "$CHECK_ONLY" in
  0|1) ;;
  *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
case "$DIRECT_ONLY" in
  0|1) ;;
  *) echo "DIRECT_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-leaf-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-leaf-ab"
WIRE="$TMP/bigint-leaf-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_leaf_ab.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function $1(/,/^$/p" "$WIRE"
}

require_wire() {
  fn="$1"
  pattern="$2"
  if ! wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}

reject_wire() {
  fn="$1"
  pattern="$2"
  if wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn unexpectedly contains /$pattern/" >&2
    exit 1
  fi
}

require_wire "__w_BigInt___w_to_i__a1" 'ret_i64 %__self'
reject_wire  "__w_BigInt___w_to_i__a1" 'call_(method|direct)_i64'
require_wire "__w_BigInt___w_prev__a1" 'call_direct_i64 .*@w_sub'
require_wire "__w_BigInt___w_succ__a1" 'call_direct_i64 .*@w_add'
require_wire "__w_BigInt___w_next__a1" 'call_direct_i64 .*@w_add'

# Generic predicate candidates must remain explicit numeric operations with no
# call through their public names. Direct controls separately prove corrected
# signed length loads and raw limb-0 access for a future interpreter-safe port.
for fn in zero_Q even_Q odd_Q negative_Q positive_Q; do
  reject_wire "__w_BigInt___w_${fn}__a1" 'call_method_i64'
done
require_wire "__w_BigInt___w_zero_Q__a1" 'call_direct_i64 .*@w_eq'
require_wire "__w_BigInt___w_even_Q__a1" 'call_direct_i64 .*@w_mod'
require_wire "__w_BigInt___w_odd_Q__a1" 'call_direct_i64 .*@w_mod'
require_wire "__w_BigInt___w_negative_Q__a1" 'call_direct_i64 .*@w_lt'
require_wire "__w_BigInt___w_positive_Q__a1" 'call_direct_i64 .*@w_gt'

for fn in zero_Q even_Q odd_Q negative_Q positive_Q; do
  direct="__w_BigInt___w_direct_${fn}__a1"
  require_wire "$direct" 'view_load_field'
  reject_wire "$direct" 'call_(method|direct)_i64'
done
require_wire "__w_BigInt___w_direct_even_Q__a1" 'and_i64'
require_wire "__w_BigInt___w_direct_odd_Q__a1" 'and_i64'
echo "WIRE: ok (unique source names; generic operators; raw direct controls)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_leaf_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: compile, WIRE, and correctness gates passed; timings skipped."
  exit 0
fi

if [ -n "$ONLY" ]; then
  functions=("$ONLY")
elif [ "$DIRECT_ONLY" = "1" ]; then
  functions=('direct-zero?' 'direct-even?' 'direct-odd?' 'direct-negative?' 'direct-positive?')
else
  functions=(to_i prev succ next 'zero?' 'even?' 'odd?' 'negative?' 'positive?')
fi

echo "Running $RUNS alternating paired samples per candidate..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  for fn in "${functions[@]}"; do
    fn_iters="$ITERS"
    case "$fn" in
      prev|succ|next) fn_iters="$ARITH_ITERS" ;;
    esac
    echo "  sample $i/$RUNS $fn x $fn_iters (parity $parity)" >&2
    "$BIN" bench "$fn_iters" "$parity" "$fn" >> "$RAW"
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
printf '%-12s %12s %12s %10s %8s\n' "function" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-12s %12s %12s %10s %8s\n' "------------" "------------" "------------" "----------" "--------"

skipped=0
for fn in "${functions[@]}"; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  if [ "$decision" = "SKIP" ]; then skipped=1; fi
  printf '%-12s %12.3f %12.3f %10.3f %8s\n' "$fn" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS paired alternating samples; retention requires W/C <= $GATE for each candidate and an independent repeat below 1.00."
echo "Predicate/to_i loops use $ITERS iterations; allocating arithmetic loops use $ARITH_ITERS and consume each fresh result."

if [ "$skipped" -ne 0 ]; then
  echo "Strict gate: at least one candidate is SKIP and must remain in C." >&2
  exit 3
fi
