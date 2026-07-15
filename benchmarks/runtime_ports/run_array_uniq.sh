#!/usr/bin/env bash
# Strict benchmark-only gate for Array#uniq source candidates. This script
# never edits core/array.w or the production Array IC table.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
GATE="${GATE:-0.97}"
CHECK_ONLY="${CHECK_ONLY:-0}"
PATH_MODE="${PATH_MODE:-v2}"
WORKLOADS="${WORKLOADS:-empty singleton small-text small-mixed text-low text-unique text-large numeric mixed typed}"
ITERS="${ITERS:-}"
INTERPRETER_CHECK="${INTERPRETER_CHECK:-1}"

case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$INTERPRETER_CHECK" in 0|1) ;; *) echo "INTERPRETER_CHECK must be 0 or 1" >&2; exit 2 ;; esac
case "$PATH_MODE" in v1|v2) ;; *) echo "PATH_MODE must be v1 or v2" >&2; exit 2 ;; esac
if [ -n "$ITERS" ]; then
  case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;; esac
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

valid_workload() {
  case "$1" in
    empty|singleton|small-text|small-mixed|text-low|text-unique|text-large|numeric|mixed|typed) return 0 ;;
    *) return 1 ;;
  esac
}

for workload in $WORKLOADS; do
  if ! valid_workload "$workload"; then
    echo "invalid workload: $workload" >&2
    exit 2
  fi
done

iters_for() {
  if [ -n "$ITERS" ]; then
    echo "$ITERS"
    return
  fi
  case "$1" in
    empty)       echo 200000 ;;
    singleton)   echo 150000 ;;
    small-text)  echo 100000 ;;
    small-mixed) echo 100000 ;;
    text-low)    echo 12000 ;;
    text-unique) echo 6000 ;;
    text-large)  echo 1000 ;;
    numeric)     echo 5000 ;;
    mixed)       echo 5000 ;;
    typed)       echo 5000 ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-uniq-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/array-uniq-ab"
WIRE="$TMP/array-uniq-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

if [ "$INTERPRETER_CHECK" = "1" ]; then
  echo "Checking tree-walk candidate semantics and valid Hash bridge use..."
  "$TUNGSTEN" run "$SCRIPT_DIR/array_uniq_interpreter.w"
  echo "Checking tree-walk Hash bridge fatal surface in isolated processes..."
  for fatal_case in has-key-arity has-key-receiver set-arity set-receiver; do
    case "$fatal_case" in
      has-key-arity) expected='w_hash_has_key expects two arguments' ;;
      has-key-receiver) expected='w_hash_has_key expects a Hash receiver' ;;
      set-arity) expected='w_hash_set expects three arguments' ;;
      set-receiver) expected='w_hash_set expects a Hash receiver' ;;
    esac
    err="$TMP/interpreter-fatal-$fatal_case.txt"
    set +e
    ARRAY_UNIQ_INTERPRETER_FATAL="$fatal_case" \
      "$TUNGSTEN" run "$SCRIPT_DIR/array_uniq_interpreter.w" >"$TMP/interpreter-fatal.out" 2>"$err"
    status=$?
    set -e
    if [ "$status" -ne 1 ]; then
      echo "interpreter fatal gate failed: $fatal_case exited $status, expected 1" >&2
      exit 1
    fi
    if ! grep -Fq "$expected" "$err"; then
      echo "interpreter fatal gate failed: $fatal_case lacks '$expected'" >&2
      sed -n '1,4p' "$err" >&2
      exit 1
    fi
  done
  echo "interpreter fatal errors: ok (Hash ccall arity and receiver guards)"
fi

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_uniq_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_uniq_ab.w" --emit-wire > "$WIRE"

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

C_FN="__w_Array___c_uniq__a1"
V1_FN="__w_Array___w_uniq_v1__a1"
V2_FN="__w_Array___w_uniq_v2__a1"
PRED_FN="__w_array_uniq_text_hash_safe_Q"

require_wire "$C_FN" 'call_direct_i64 .*@w_ref_array_uniq'
for fn in "$V1_FN" "$V2_FN"; do
  require_wire "$fn" 'call_direct_i64 .*@w_array_new_empty'
  require_wire "$fn" 'call_direct_i64 .*@w_array_idx'
  require_wire "$fn" 'call_direct_i64 .*@w_eq'
  require_wire "$fn" 'call_direct_i64 .*@w_array_push'
  require_wire "$fn" 'view_load_field'
  reject_wire "$fn" 'w_ref_array_uniq|w_ic_array_uniq'
done
require_wire "$PRED_FN" 'ashr_i64'
require_wire "$PRED_FN" 'and_i64'
require_wire "$PRED_FN" 'load_u8_ptr'
require_wire "$PRED_FN" 'cond_br'
reject_wire "$PRED_FN" 'call_direct|call_method|__w_type|w_class_name|w_bench_uniq_text_hash_safe'
reject_wire "$V1_FN" 'w_hash_has_key|w_hash_set|array_uniq_text_hash_safe|call_recycle_or_new_hash'
require_wire "$V2_FN" 'call_direct_i64 .*@__w_array_uniq_text_hash_safe_Q'
require_wire "$V2_FN" 'call_direct_i64 .*@w_hash_has_key'
require_wire "$V2_FN" 'call_direct_i64 .*@w_hash_set'
require_wire "$V2_FN" 'call_recycle_or_new_hash'
require_wire "$V2_FN" 'cleanup_push_hash'
require_wire "$V2_FN" 'call_recycle_hash'
reject_wire "$V2_FN" 'call_reuse_or_new_hash'
echo "WIRE: ok (v1 exact quadratic w_eq loop; v2 call-free WValue/rope classifier, text-only Hash accelerator with cleanup, and non-text w_eq fallback)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_uniq_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_uniq_ab.w" --release --out "$BIN" >/dev/null

echo "Checking exact C/v1/v2/public behavior and output capacity..."
"$BIN" check

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: interpreter/fatal, WIRE, release, semantic, representation/capacity, typed-decoding, and cleanup gates passed; timings skipped."
  exit 0
fi

echo "Running $RUNS balanced ABBA samples for $PATH_MODE across: $WORKLOADS"
: > "$RAW"
for workload in $WORKLOADS; do
  workload_iters="$(iters_for "$workload")"
  sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    parity=$((sample % 2))
    echo "  $workload sample $((sample + 1))/$RUNS (parity $parity)" >&2
    "$BIN" bench "$workload_iters" "$parity" "$PATH_MODE" "$workload" >> "$RAW"
    sample=$((sample + 1))
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
printf '%-24s %12s %12s %10s %8s\n' "workload" "C ns" "W ns" "W/C" "gate"
printf '%-24s %12s %12s %10s %8s\n' "------------------------" "------------" "------------" "----------" "--------"

failed=0
for workload in $WORKLOADS; do
  name="uniq.$PATH_MODE.$workload"
  c_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v name="$name" '$1 == "RESULT" && $2 == name { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  if [ "$decision" != "PASS" ]; then failed=1; fi
  printf '%-24s %12.3f %12.3f %10.3f %8s\n' "$workload" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Median of $RUNS paired ABBA samples; strict retention requires every workload at W/C <= $GATE."
if [ "$failed" -ne 0 ]; then
  echo "Strict gate: Array#uniq candidate is SKIP; production must remain unchanged." >&2
  exit 1
fi
