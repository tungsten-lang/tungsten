#!/usr/bin/env bash
# Same-binary public-source/C-oracle gate for BigInt#lcm. Each pair balances
# C/W/W/C with W/C/C/W and reports the median paired source/C ratio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
PAIRS="${PAIRS:-8}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-lcm-${LABEL}.txt}"
ROWS="${ROWS:-one-big:3000000 one-share:3000000 one-int:3000000 multi-co:2000000 multi-share:100000 big-share:20000}"

case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-lcm-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-lcm-public"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_lcm_public.w" \
  --release --native --fast --out "$BIN" >/dev/null

"$BIN" check
: > "$OUT"

run_leg() {
  local lane="$1" stratum="$2" iters="$3"
  local wire_lane="w"
  if [ "$lane" = C ]; then wire_lane="c"; fi
  printf '%s|%s\n' "$lane" "$("$BIN" bench "$wire_lane" "$stratum" "$iters")" >> "$OUT"
}

for row in $ROWS; do
  stratum="${row%%:*}"
  iters="${row##*:}"
  pair=1
  while [ "$pair" -le "$PAIRS" ]; do
    echo "  $LABEL lcm-$stratum pair $pair/$PAIRS" >&2
    if [ $((pair % 2)) -eq 1 ]; then
      run_leg C "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
    else
      run_leg W "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
    fi
    pair=$((pair + 1))
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
for row in $ROWS; do
  stratum="${row%%:*}"
  name="lcm-$stratum"
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
echo "raw samples: $OUT"
