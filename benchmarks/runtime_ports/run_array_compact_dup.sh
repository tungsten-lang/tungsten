#!/usr/bin/env bash
# Strict benchmark-only gate for Array#compact and Array#dup source ports.
# Production core/array.w and the Array IC table are never edited here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
GATE="${GATE:-0.97}"
CHECK_ONLY="${CHECK_ONLY:-0}"
INTERPRETER_CHECK="${INTERPRETER_CHECK:-1}"
PATH_MODE="${PATH_MODE:-v2}"
ONLY="${ONLY:-}"
REPEAT="${REPEAT:-0}"
ITERS="${ITERS:-}"
COMPACT_WORKLOADS="${COMPACT_WORKLOADS:-empty all-nil singleton small-dense small-sparse medium-dense medium-sparse large-dense large-sparse typed shifted}"
DUP_WORKLOADS="${DUP_WORKLOADS:-empty singleton small medium large typed shifted}"

case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$INTERPRETER_CHECK" in 0|1) ;; *) echo "INTERPRETER_CHECK must be 0 or 1" >&2; exit 2 ;; esac
case "$PATH_MODE" in v1|v2) ;; *) echo "PATH_MODE must be v1 or v2" >&2; exit 2 ;; esac
case "$ONLY" in ''|compact|dup) ;; *) echo "ONLY must be compact or dup" >&2; exit 2 ;; esac
case "$REPEAT" in 0|1) ;; *) echo "REPEAT must be 0 or 1" >&2; exit 2 ;; esac
if [ -n "$ITERS" ]; then
  case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;; esac
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

valid_workload() {
  local operation="$1" workload="$2"
  if [ "$operation" = compact ]; then
    case "$workload" in
      empty|all-nil|singleton|small-dense|small-sparse|medium-dense|medium-sparse|large-dense|large-sparse|typed|shifted) return 0 ;;
    esac
  else
    case "$workload" in
      empty|singleton|small|medium|large|typed|shifted) return 0 ;;
    esac
  fi
  return 1
}

for workload in $COMPACT_WORKLOADS; do
  valid_workload compact "$workload" || { echo "invalid compact workload: $workload" >&2; exit 2; }
done
for workload in $DUP_WORKLOADS; do
  valid_workload dup "$workload" || { echo "invalid dup workload: $workload" >&2; exit 2; }
done

iters_for() {
  local operation="$1" workload="$2"
  if [ -n "$ITERS" ]; then
    echo "$ITERS"
    return
  fi
  if [ "$operation" = compact ]; then
    case "$workload" in
      empty) echo 5000000 ;;
      all-nil) echo 750000 ;;
      singleton) echo 2500000 ;;
      small-dense|small-sparse) echo 1000000 ;;
      medium-dense|medium-sparse|typed|shifted) echo 150000 ;;
      large-dense|large-sparse) echo 10000 ;;
    esac
  else
    case "$workload" in
      empty) echo 5000000 ;;
      singleton) echo 2500000 ;;
      small) echo 1000000 ;;
      medium|typed|shifted) echo 150000 ;;
      large) echo 10000 ;;
    esac
  fi
}

warmup_for() {
  local operation="$1" workload="$2"
  case "$workload" in
    empty) echo 100000 ;;
    singleton) echo 50000 ;;
    small|small-dense|small-sparse) echo 20000 ;;
    all-nil|medium|medium-dense|medium-sparse|typed|shifted) echo 3000 ;;
    large|large-dense|large-sparse) echo 300 ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-compact-dup-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/array-compact-dup-ab"
WIRE="$TMP/array-compact-dup-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

if [ "$INTERPRETER_CHECK" = 1 ]; then
  echo "Checking tree-walker v1/v2 candidate parity..."
  "$TUNGSTEN" run "$SCRIPT_DIR/array_compact_dup_interpreter.w"
fi

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_compact_dup_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_compact_dup_ab.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function $1(/,/^$/p" "$WIRE"
}

require_wire() {
  local fn="$1" pattern="$2"
  if ! wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}

reject_wire() {
  local fn="$1" pattern="$2"
  if wire_body "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn unexpectedly contains /$pattern/" >&2
    exit 1
  fi
}

require_count() {
  local fn="$1" pattern="$2" expected="$3" count
  count="$(wire_body "$fn" | grep -Ec "$pattern" || true)"
  if [ "$count" -ne "$expected" ]; then
    echo "WIRE check failed: $fn has $count /$pattern/ sites, expected $expected" >&2
    exit 1
  fi
}

C_COMPACT="__w_Array___c_compact__a1"
C_DUP="__w_Array___c_dup__a1"
V1_COMPACT="__w_Array___w_compact_v1__a1"
V2_COMPACT="__w_Array___w_compact_v2__a1"
V1_DUP="__w_Array___w_dup_v1__a1"
V2_DUP="__w_Array___w_dup_v2__a1"

require_wire "$C_COMPACT" 'call_direct_i64 .*@w_ref_array_compact'
require_wire "$C_DUP" 'call_direct_i64 .*@w_ref_array_dup'
for fn in "$V1_COMPACT" "$V2_COMPACT" "$V1_DUP" "$V2_DUP"; do
  require_count "$fn" 'call_direct_i64 .*@w_array_new_empty' 1
  require_count "$fn" 'call_direct_i64 .*@w_array_idx' 1
  require_count "$fn" 'call_direct_i64 .*@w_array_push' 1
  require_count "$fn" 'view_load_field' 1
  reject_wire "$fn" 'w_ref_array_|w_ic_array_|call_method_i64|call_recycle_or_new_array|call_reuse_or_new_array|cleanup_push_array|w_array_recycle'
done
for fn in "$V1_COMPACT" "$V2_COMPACT"; do
  require_wire "$fn" 'icmp_i64'
  reject_wire "$fn" 'call_direct_i64 .*@w_(eq|neq)'
done
echo "WIRE: ok (one ordinary result allocation, one decoded-load/push loop site, raw size field, raw nil test for compact, and no C/cached-method/reuse fallback)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_compact_dup_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_compact_dup_ab.w" \
  --release --out "$BIN" >/dev/null

echo "Checking exact C/v1/v2/public behavior, layout, capacity, and cleanup..."
"$BIN" check

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: interpreter, WIRE, release, semantic, representation/capacity, typed/view decoding, arity/block, and cleanup gates passed; timings skipped."
  exit 0
fi

operations=()
if [ -z "$ONLY" ] || [ "$ONLY" = compact ]; then operations+=(compact); fi
if [ -z "$ONLY" ] || [ "$ONLY" = dup ]; then operations+=(dup); fi

echo "Running $RUNS balanced C/W/W/C samples for $PATH_MODE..."
: > "$RAW"
for operation in "${operations[@]}"; do
  if [ "$operation" = compact ]; then workloads="$COMPACT_WORKLOADS"; else workloads="$DUP_WORKLOADS"; fi
  for workload in $workloads; do
    workload_iters="$(iters_for "$operation" "$workload")"
    warmup_iters="$(warmup_for "$operation" "$workload")"
    sample=0
    while [ "$sample" -lt "$RUNS" ]; do
      parity=$((sample % 2))
      echo "  $operation/$workload sample $((sample + 1))/$RUNS x $workload_iters (parity $parity)" >&2
      "$BIN" bench "$operation" "$workload" "$workload_iters" \
        "$warmup_iters" "$parity" "$PATH_MODE" >> "$RAW"
      sample=$((sample + 1))
    done
  done
done

median_stream() {
  sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) print values[(NR + 1) / 2]
      else print (values[NR / 2] + values[NR / 2 + 1]) / 2
    }
  '
}

echo
printf '%-28s %12s %12s %10s %8s\n' "method/workload" "C ns" "$PATH_MODE ns" "W/C" "gate"
printf '%-28s %12s %12s %10s %8s\n' "----------------------------" "------------" "------------" "----------" "--------"

failed=0
for operation in "${operations[@]}"; do
  if [ "$operation" = compact ]; then workloads="$COMPACT_WORKLOADS"; else workloads="$DUP_WORKLOADS"; fi
  for workload in $workloads; do
    name="$operation.$PATH_MODE.$workload"
    c_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $3 }' "$RAW" | median_stream)"
    w_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $4 }' "$RAW" | median_stream)"
    ratio_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $5 }' "$RAW" | median_stream)"
    if [ "$REPEAT" = 1 ]; then
      decision="$(awk -v ratio="$ratio_med" 'BEGIN { print (ratio < 1.00) ? "PASS" : "SKIP" }')"
    else
      decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
    fi
    if [ "$decision" != PASS ]; then failed=1; fi
    printf '%-28s %12.3f %12.3f %10.3f %8s\n' "$name" "$c_med" "$w_med" "$ratio_med" "$decision"
  done
done

echo
echo "Each sample sums C/W/W/C or W/C/C/W legs; bounded result cleanup is outside timed intervals."
if [ "$REPEAT" = 1 ]; then
  echo "Repeat mode requires every stratum below 1.00 and is valid only after a prior <= $GATE campaign plus an independent compiler rebuild."
else
  echo "First-pass retention requires every independent stratum at W/C <= $GATE; compact and dup are decided separately."
  echo "A passing method must then be rebuilt independently and rerun with REPEAT=1 before any public trial."
fi
if [ "$failed" -ne 0 ]; then
  echo "Strict gate failed for at least one selected method/stratum; keep that production IC installed." >&2
  exit 3
fi
