#!/usr/bin/env bash
# Strict benchmark-only gate for the BigArray#size source candidates. This
# script never edits core/big_array.w or the production IC table.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
GATE="${GATE:-1.10}"
PATH_MODE="${PATH_MODE:-v2}"
CHECK_ONLY="${CHECK_ONLY:-0}"
STATIC_ONLY="${STATIC_ONLY:-0}"
INLINE_ITERS="${INLINE_ITERS:-50000000}"
OVERFLOW_ITERS="${OVERFLOW_ITERS:-2000000}"
INLINE_WARMUP="${INLINE_WARMUP:-500000}"
OVERFLOW_WARMUP="${OVERFLOW_WARMUP:-50000}"

case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$PATH_MODE" in v1|v2) ;; *) echo "PATH_MODE must be v1 or v2" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$STATIC_ONLY" in 0|1) ;; *) echo "STATIC_ONLY must be 0 or 1" >&2; exit 2 ;; esac
for value in "$INLINE_ITERS" "$OVERFLOW_ITERS" "$INLINE_WARMUP" "$OVERFLOW_WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;; esac
done
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

if [ "$STATIC_ONLY" = 1 ]; then
  grep -Fq -- '-> __w_big_array_size_v1' "$SCRIPT_DIR/big_array_size_candidates.w"
  grep -Fq -- '-> __w_big_array_size_v2' "$SCRIPT_DIR/big_array_size_candidates.w"
  grep -Fq 'w_ref_big_array_size' "$SCRIPT_DIR/big_array_size_ref.c"
  grep -Fq 'RESULT|size.' "$SCRIPT_DIR/big_array_size_ab.w"
  echo "STATIC_ONLY=1: candidate, exact C mirror, signed-i64 fixtures, balanced harness, and strict gate are present; no compiler or benchmark was run."
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-big-array-size-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/big-array-size-ab"
WIRE="$TMP/big-array-size-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/big_array_size_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/big_array_size_ab.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function $1(/,/^$/p" "$WIRE"
}

require_wire() {
  local fn="$1" pattern="$2"
  if ! wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}

reject_wire() {
  local fn="$1" pattern="$2"
  if wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn unexpectedly contains /$pattern/" >&2
    exit 1
  fi
}

C_FN="__w_BigArray___c_big_array_size__a1"
V1_FN="__w_BigArray___w_big_array_size_v1__a1"
V2_FN="__w_BigArray___w_big_array_size_v2__a1"

require_wire "$C_FN" 'call_direct_i64 .*@w_ref_big_array_size'
for fn in "$V1_FN" "$V2_FN"; do
  require_wire "$fn" 'view_load_field'
  reject_wire "$fn" '@w_ref_big_array_size|@w_big_array_size|call_method_i64|w_u64'
done
require_wire "$V1_FN" 'call_direct_i64 .*@w_int'
require_wire "$V2_FN" 'and_i64'
require_wire "$V2_FN" 'or_i64'
require_wire "$V2_FN" 'call_direct_i64 .*@w_int'
require_wire "$V2_FN" 'cond_br'
echo "WIRE: ok (signed field load; v1 checked boxing call; v2 inline i48 tag/mask plus exact w_int overflow fallback; no dynamic/C-size fallback)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/big_array_size_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/big_array_size_ab.w" \
  --release --out "$BIN" >/dev/null

echo "Checking C/v1/v2/public numeric and representation parity..."
"$BIN" check

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: WIRE, release, signed-i64 boundary, Int/BigInt representation, arity/block, and receiver-stability gates passed; timings skipped."
  exit 0
fi

: > "$RAW"
for stratum in inline overflow; do
  if [ "$stratum" = inline ]; then
    iters="$INLINE_ITERS"
    warmup="$INLINE_WARMUP"
  else
    iters="$OVERFLOW_ITERS"
    warmup="$OVERFLOW_WARMUP"
  fi
  sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    parity=$((sample % 2))
    echo "  $PATH_MODE/$stratum sample $((sample + 1))/$RUNS x $iters (parity $parity)" >&2
    "$BIN" bench "$stratum" "$iters" "$warmup" "$parity" "$PATH_MODE" >> "$RAW"
    sample=$((sample + 1))
  done
done

median_stream() {
  sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) print values[(NR + 1) / 2]
      else print (values[NR / 2] + values[NR / 2 + 1]) / 2
    }
  '
}

echo
printf '%-24s %12s %12s %10s %8s\n' "method/stratum" "C ns" "$PATH_MODE ns" "W/C" "gate"
printf '%-24s %12s %12s %10s %8s\n' "------------------------" "------------" "------------" "----------" "--------"

failed=0
for stratum in inline overflow; do
  name="size.$PATH_MODE.$stratum"
  c_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  if [ "$decision" != PASS ]; then failed=1; fi
  printf '%-24s %12.3f %12.3f %10.3f %8s\n' "$stratum" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS balanced C/W/W/C samples; strict retention requires both strata at W/C <= $GATE and an independent repeat at or below $GATE."
if [ "$failed" -ne 0 ]; then
  echo "Strict gate: BigArray#size $PATH_MODE is SKIP; production must remain unchanged." >&2
  exit 1
fi
