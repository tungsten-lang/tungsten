#!/usr/bin/env bash
# Strict gate for the benchmark-only IPv4#octets source candidate.  This does
# not modify production dispatch: PATH_MODE=unique measures the uniquely named
# body; PATH_MODE=public is reserved for the later isolated IC-removal trial.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-5000000}"
GATE="${GATE:-0.97}"
CHECK_ONLY="${CHECK_ONLY:-0}"
PATH_MODE="${PATH_MODE:-unique}"
INTERPRETER_CHECK="${INTERPRETER_CHECK:-1}"

case "$RUNS" in
  ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;;
esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$CHECK_ONLY" in
  0|1) ;;
  *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
case "$INTERPRETER_CHECK" in
  0|1) ;;
  *) echo "INTERPRETER_CHECK must be 0 or 1" >&2; exit 2 ;;
esac
case "$PATH_MODE" in
  unique|public) ;;
  *) echo "PATH_MODE must be unique or public" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-ipv4-octets-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/ipv4-octets-ab"
WIRE="$TMP/ipv4-octets-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

if [ "$INTERPRETER_CHECK" = "1" ]; then
  echo "Checking tree-walk correctness and representation..."
  "$TUNGSTEN" run "$SCRIPT_DIR/ipv4_octets_ab.w" -- interpreter-check
fi

echo "Inspecting candidate/public WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/ipv4_octets_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/ipv4_octets_ab.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function $1(/,/^$/p" "$WIRE"
}

require_wire() {
  fn="$1"
  pattern="$2"
  if ! wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}

reject_wire() {
  fn="$1"
  pattern="$2"
  if wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn unexpectedly contains /$pattern/" >&2
    exit 1
  fi
}

C_FN="__w_IPv4___c_octets__a1"
W_FN="__w_IPv4___w_octets__a1"
PUBLIC_FN="__w_IPv4_octets__a1"

require_wire "$C_FN" 'call_direct_i64 .*@w_ref_ipv4_octets'
require_wire "$W_FN" '(ashr_i64|lshr_i64)'
require_wire "$W_FN" 'and_i64'
require_wire "$W_FN" 'call_direct_i64 .*@w_array_new_empty'
require_wire "$W_FN" 'call_direct_i64 .*@w_array_push'
reject_wire  "$W_FN" 'w_(ref_)?ipv4_octets'
reject_wire  "$W_FN" 'call_method_i64'
require_wire "$PUBLIC_FN" 'call_direct_i64 .*@w_ipv4_octets'

push_count="$(wire_body "$W_FN" | grep -Ec 'call_direct_i64 .*@w_array_push')"
if [ "$push_count" -ne 4 ]; then
  echo "WIRE check failed: $W_FN has $push_count array pushes, expected 4" >&2
  exit 1
fi
echo "WIRE: ok (C reference, raw unique source, and public ccall are distinct)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/ipv4_octets_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/ipv4_octets_ab.w" --release --out "$BIN" >/dev/null

echo "Checking compiled C/W/public behavior and representation..."
"$BIN" check

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: interpreter, WIRE, release compile, and correctness gates passed; timings skipped."
  exit 0
fi

if [ "$PATH_MODE" = "public" ]; then
  echo "PATH_MODE=public: use only for an isolated production-shaped IC-removal trial." >&2
fi

echo "Running $RUNS balanced ABBA samples x $ITERS iterations ($PATH_MODE path)..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" "$PATH_MODE" >> "$RAW"
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

name="octets.$PATH_MODE"
c_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
w_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
ratio_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"

echo
printf '%-16s %12s %12s %10s %8s\n' "function" "C-method ns" "W-candidate" "W/C" "gate"
printf '%-16s %12s %12s %10s %8s\n' "----------------" "------------" "------------" "----------" "--------"
printf '%-16s %12.3f %12.3f %10.3f %8s\n' "$name" "$c_med" "$w_med" "$ratio_med" "$decision"

echo
echo "Each sample is C/W/W/C or W/C/C/W; the two legs are summed per implementation."
echo "Retention requires median W/C <= $GATE and an independent repeat below 1.00."
echo "Result-array cleanup happens in bounded batches outside every timed interval."

if [ "$decision" != "PASS" ]; then
  echo "Strict gate: IPv4#octets is SKIP and must remain in C." >&2
  exit 3
fi
