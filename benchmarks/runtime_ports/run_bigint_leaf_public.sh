#!/usr/bin/env bash
# Compile and sample the true public BigInt#prev/succ/next dispatch path.
# Run this unchanged before and after the port; use LABEL to identify the
# campaign. Rows are method-stratum pairs; medians print at the end.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-10000000}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-leaf-${LABEL}.txt}"
METHODS="${METHODS:-prev succ next}"
STRATA="${STRATA:-one two four crossover}"

case "$RUNS" in ''|*[!0-9]*|0) echo "RUNS must be positive" >&2; exit 2 ;; esac
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-leaf-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-leaf-public"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_leaf_public.w" \
  --release --native --fast --out "$BIN" >/dev/null

"$BIN" check
: > "$OUT"
for method in $METHODS; do
  for stratum in $STRATA; do
    i=1
    while [ "$i" -le "$RUNS" ]; do
      echo "  $LABEL $method-$stratum sample $i/$RUNS" >&2
      "$BIN" bench "$method" "$stratum" "$ITERS" >> "$OUT"
      i=$((i + 1))
    done
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
for method in $METHODS; do
  for stratum in $STRATA; do
    name="$method-$stratum"
    median="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $3 / $4 }' "$OUT" | median_stream)"
    printf '%-20s %14.4f\n' "$name" "$median"
  done
done
echo "raw samples: $OUT"
