#!/usr/bin/env bash
# Strict balanced C-reference/native-source A/B for BigInt#neg!/abs! bodies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-20000000}"
GATE="${GATE:-1.10}"
OUT="${OUT:-/tmp/tungsten-bigint-bang-ab.txt}"

case "$RUNS" in ''|*[!0-9]*|0) echo "RUNS must be positive" >&2; exit 2 ;; esac
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-bang-ab.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-bang-ab"
WIRE="$TMP/bigint-bang-ab.wire"
RAW="$OUT"

cd "$ROOT"
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_bang_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_bang_ab.w" --emit-wire > "$WIRE"

for fn in __w_BigInt___w_neg_bang__a1 __w_BigInt___w_abs_bang__a1; do
  if ! sed -n "/^function $fn(/,/^$/p" "$WIRE" | rg -q 'view_store_field'; then
    echo "WIRE check failed: $fn lacks native view_store_field" >&2
    exit 1
  fi
done
echo "WIRE: ok (both source kernels contain a typed native field store)"

TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_bang_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_bang_ab.w" \
  --release --native --fast --out "$BIN" >/dev/null
"$BIN" check

: > "$RAW"
for name in neg abs-positive neg-abs-pair; do
  i=1
  while [ "$i" -le "$RUNS" ]; do
    parity=$(( (i - 1) % 2 ))
    echo "  $name sample $i/$RUNS parity=$parity" >&2
    "$BIN" bench "$name" "$ITERS" "$parity" >> "$RAW"
    i=$((i + 1))
  done
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

printf '%-18s %12s %12s %9s %8s\n' "operation" "C ns/call" "W ns/call" "W/C" "gate"
printf '%-18s %12s %12s %9s %8s\n' "------------------" "------------" "------------" "---------" "--------"
failed=0
for name in neg abs-positive neg-abs-pair; do
  c_med="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $3 / $5 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $4 / $5 }' "$RAW" | median_stream)"
  ratio="$(awk -v c="$c_med" -v w="$w_med" 'BEGIN { printf "%.6f", w / c }')"
  decision="$(awk -v r="$ratio" -v g="$GATE" 'BEGIN { print (r <= g) ? "PASS" : "SKIP" }')"
  if [ "$decision" = "SKIP" ]; then failed=1; fi
  printf '%-18s %12.4f %12.4f %9.3f %8s\n' "$name" "$c_med" "$w_med" "$ratio" "$decision"
done
echo "raw samples: $RAW"
if [ "$failed" -ne 0 ]; then
  echo "strict gate failed: keep the losing operation in C" >&2
  exit 3
fi
