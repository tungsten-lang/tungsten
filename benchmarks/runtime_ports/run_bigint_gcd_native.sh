#!/usr/bin/env bash
# Same-binary public-source/C-oracle gate for BigInt#gcd. Each pair balances
# C/W/W/C with W/C/C/W and reports the median paired source/C ratio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
PAIRS="${PAIRS:-8}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-gcd-native-${LABEL}.txt}"
ROWS="${ROWS:-one-big:2000000 one-int:2000000 two:1000000 two-share:1000000 near:1000000 skew:500000 big-share:10000}"

case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-gcd-native.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-gcd-native"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_gcd_public.w" \
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
    echo "  $LABEL gcd-$stratum pair $pair/$PAIRS" >&2
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
  name="gcd-$stratum"
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
