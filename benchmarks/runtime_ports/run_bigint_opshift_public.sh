#!/usr/bin/env bash
# Same-binary C/source gate for the BigInt << and >> source seams. Each
# observation balances C/W/W/C with W/C/C/W and reports the median paired
# source/C ratio. `one13` exercises the native i48-demotion arm; `oneheap`
# is the one-limb C-retained control.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
PAIRS="${PAIRS:-8}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-opshift-${LABEL}.txt}"
OPS="${OPS:-shl shr}"
ROWS="${ROWS:-one13:30000000 oneheap:30000000 four13:10000000 four64:10000000 sf13:5000000 sf200:5000000 big1000:4000000 neg:10000000 overpos:30000000 overneg:30000000}"

case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-opshift-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-opshift-public"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_opshift_public.w" \
  --release --native --fast --out "$BIN" >/dev/null

"$BIN" check
: > "$OUT"

run_leg() {
  local lane="$1" op="$2" stratum="$3" iters="$4"
  local line
  if [ "$lane" = C ]; then
    line="$(TUNGSTEN_BIGINT_SRC_OPS=0 "$BIN" "$op" "$stratum" "$iters")"
  else
    line="$(TUNGSTEN_BIGINT_SRC_OPS=1 "$BIN" "$op" "$stratum" "$iters")"
  fi
  printf '%s|%s\n' "$lane" "$line" >> "$OUT"
}

for op in $OPS; do
  for row in $ROWS; do
    stratum="${row%%:*}"
    iters="${row##*:}"
    pair=1
    while [ "$pair" -le "$PAIRS" ]; do
      echo "  $LABEL $op-$stratum pair $pair/$PAIRS" >&2
      if [ $((pair % 2)) -eq 1 ]; then
        run_leg C "$op" "$stratum" "$iters"
        run_leg W "$op" "$stratum" "$iters"
        run_leg W "$op" "$stratum" "$iters"
        run_leg C "$op" "$stratum" "$iters"
      else
        run_leg W "$op" "$stratum" "$iters"
        run_leg C "$op" "$stratum" "$iters"
        run_leg C "$op" "$stratum" "$iters"
        run_leg W "$op" "$stratum" "$iters"
      fi
      pair=$((pair + 1))
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

printf '%-20s %14s\n' "operation" "median W/C"
printf '%-20s %14s\n' "--------------------" "--------------"
for op in $OPS; do
  for row in $ROWS; do
    stratum="${row%%:*}"
    name="$op-$stratum"
    median="$(awk -F'|' -v n="$name" '
      $2 == "RESULT" && $3 == n {
        if ($1 == "C") c += $4; else w += $4
        legs++
        if (legs == 4) {
          printf "%.12f\n", w / c
          c = 0; w = 0; legs = 0
        }
      }
    ' "$OUT" | median_stream)"
    printf '%-20s %14.4f\n' "$name" "$median"
  done
done
echo "raw samples: $OUT"
