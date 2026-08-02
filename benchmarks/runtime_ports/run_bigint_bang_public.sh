#!/usr/bin/env bash
# Compile and sample the true public BigInt#neg!/abs! dispatch path. Run this
# unchanged before and after the port; use LABEL to identify the campaign.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-20000000}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-bang-${LABEL}.txt}"

case "$RUNS" in ''|*[!0-9]*|0) echo "RUNS must be positive" >&2; exit 2 ;; esac
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-bang.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-bang-public"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_bang_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_bang_public.w" \
  --release --native --fast --out "$BIN" >/dev/null

"$BIN" check
: > "$OUT"
for name in neg abs-positive neg-abs-pair; do
  i=1
  while [ "$i" -le "$RUNS" ]; do
    echo "  $LABEL $name sample $i/$RUNS" >&2
    "$BIN" bench "$name" "$ITERS" >> "$OUT"
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

printf '%-18s %14s\n' "operation" "median ns/call"
printf '%-18s %14s\n' "------------------" "--------------"
for name in neg abs-positive neg-abs-pair; do
  median="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $3 / $4 }' "$OUT" | median_stream)"
  printf '%-18s %14.4f\n' "$name" "$median"
done
echo "raw samples: $OUT"
