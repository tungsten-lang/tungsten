#!/usr/bin/env bash
# Compile and sample the true public BigInt#prime? dispatch path. Run this
# unchanged before and after the port; use LABEL to identify the campaign.
# Per-stratum iteration counts keep every leg near or above 0.2s.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-prime-${LABEL}.txt}"
ROWS="${ROWS:-one-prime:200000 one-comp:1000000 semiprime:50000 big-prime:2000 mersenne:5000}"

case "$RUNS" in ''|*[!0-9]*|0) echo "RUNS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-prime-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-prime-public"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_prime_public.w" \
  --release --native --fast --out "$BIN" >/dev/null

"$BIN" check
: > "$OUT"
for row in $ROWS; do
  stratum="${row%%:*}"
  iters="${row##*:}"
  i=1
  while [ "$i" -le "$RUNS" ]; do
    echo "  $LABEL prime-$stratum sample $i/$RUNS" >&2
    "$BIN" bench "$stratum" "$iters" >> "$OUT"
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

printf '%-20s %14s\n' "operation" "median ns/call"
printf '%-20s %14s\n' "--------------------" "--------------"
for row in $ROWS; do
  stratum="${row%%:*}"
  name="prime-$stratum"
  median="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $3 / $4 }' "$OUT" | median_stream)"
  printf '%-20s %14.4f\n' "$name" "$median"
done
echo "raw samples: $OUT"
