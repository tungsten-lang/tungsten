#!/usr/bin/env bash
# Compile once, verify exact MAC/IPv6 C/W behavior, then time each migrated
# function through the same type-class dispatch shape.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS="${RUNS:-5}"
ITERS="${ITERS:-100000}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer" >&2; exit 2 ;;
esac
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-network-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/network-ab"
RAW="$TMP/results.txt"

cd "$ROOT"
echo "Compiling benchmark (excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/network_ref.c" \
  "$ROOT/bin/tungsten" compile "$SCRIPT_DIR/network_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/W behavior..."
"$BIN" check

echo "Running $RUNS paired samples x $ITERS iterations per function..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" >> "$RAW"
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
printf '%-22s %12s %12s %10s\n' "function" "C-method ns" "W-method ns" "W/C"
printf '%-22s %12s %12s %10s\n' "----------------------" "------------" "------------" "----------"

functions=(
  ipv6.prefix ipv6.cidr? ipv6.with_prefix ipv6.byte 'ipv6.[]' ipv6.bytes
  ipv6.network ipv6.include? ipv6.contains? ipv6.unspecified? ipv6.loopback?
  ipv6.multicast? ipv6.link_local? ipv6.unique_local? ipv6.private? ipv6.global?
  mac.byte 'mac.[]' mac.bytes mac.multicast? mac.unicast? mac.local? mac.universal?
  mac.broadcast?
)

for fn in "${functions[@]}"; do
  c_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$fn" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  printf '%-22s %12.3f %12.3f %10.3f\n' "$fn" "$c_med" "$w_med" "$ratio_med"
done

echo
echo "Median of $RUNS; order alternates and every paired loop verifies an identical checksum."
