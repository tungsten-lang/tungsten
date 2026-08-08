#!/usr/bin/env bash
# Compile and sample the true public bigint `&` dispatch path. Same-binary
# A/B: run once with LABEL=src (TUNGSTEN_BIGINT_SRC_OPS unset) and once with
# LABEL=c TUNGSTEN_BIGINT_SRC_OPS=0, using SKIP_COMPILE/BIN to share the
# binary, or simply invoke twice and compare medians.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-opand-${LABEL}.txt}"
ROWS="${ROWS:-one:5000000 int-arg:5000000 four:2000000 fortyeight:300000 sixtyfour:300000 skew:500000 neg:2000000}"

case "$RUNS" in ''|*[!0-9]*|0) echo "RUNS must be positive" >&2; exit 2 ;; esac

BIN="${BIN:-}"
if [ -z "$BIN" ]; then
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-opand-public.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  BIN="$TMP/bigint-opand-public"
fi

cd "$ROOT"
if [ -z "${SKIP_COMPILE:-}" ]; then
  echo "Compiling $LABEL with --release --native --fast..."
  TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
    "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_opand_public.w" \
    --release --native --fast --out "$BIN" >/dev/null
fi

"$BIN" check
: > "$OUT"
for row in $ROWS; do
  stratum="${row%%:*}"
  iters="${row##*:}"
  i=1
  while [ "$i" -le "$RUNS" ]; do
    echo "  $LABEL and-$stratum sample $i/$RUNS" >&2
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
  name="and-$stratum"
  median="$(awk -F'|' -v n="$name" '$1 == "RESULT" && $2 == n { printf "%.9f\n", $3 / $4 }' "$OUT" | median_stream)"
  printf '%-20s %14.4f\n' "$name" "$median"
done
echo "raw samples: $OUT"
