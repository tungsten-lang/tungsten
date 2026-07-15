#!/usr/bin/env bash
# Strict benchmark-only gate for the Array#join source candidates.  Production
# core/runtime dispatch is never edited by this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
GATE="${GATE:-0.97}"
CHECK_ONLY="${CHECK_ONLY:-0}"
PATH_MODE="${PATH_MODE:-v2}"
BASE_PATH="${BASE_PATH:-c}"
WORKLOADS="${WORKLOADS:-empty singleton pair four eight medium large huge utf8 typed}"
ITERS="${ITERS:-}"
INTERPRETER_CHECK="${INTERPRETER_CHECK:-1}"

case "$RUNS" in
  ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;;
esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$INTERPRETER_CHECK" in 0|1) ;; *) echo "INTERPRETER_CHECK must be 0 or 1" >&2; exit 2 ;; esac
case "$PATH_MODE" in v1|v2|v3|v4|v5|v6|public) ;; *) echo "PATH_MODE must be v1, v2, v3, v4, v5, v6, or public" >&2; exit 2 ;; esac
case "$BASE_PATH" in c|v1) ;; *) echo "BASE_PATH must be c or v1" >&2; exit 2 ;; esac
if [ "$BASE_PATH" = "$PATH_MODE" ]; then
  echo "BASE_PATH and PATH_MODE must differ" >&2
  exit 2
fi
if [ -n "$ITERS" ]; then
  case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;; esac
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

valid_workload() {
  case "$1" in
    empty|singleton|pair|four|eight|medium|large|huge|utf8|typed) return 0 ;;
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
    empty)     echo 2000000 ;;
    singleton) echo 1000000 ;;
    pair)      echo 750000 ;;
    four)      echo 400000 ;;
    eight)     echo 200000 ;;
    medium)    echo 30000 ;;
    large)     echo 8000 ;;
    huge)      echo 2000 ;;
    utf8)      echo 30000 ;;
    typed)     echo 30000 ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-join-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/array-join-ab"
WIRE="$TMP/array-join-ab.wire"
RAW="$TMP/results.txt"

cd "$ROOT"

if [ "$INTERPRETER_CHECK" = "1" ]; then
  echo "Checking tree-walk valid-path semantics..."
  "$TUNGSTEN" run "$SCRIPT_DIR/array_join_interpreter.w"
  echo "Checking tree-walk fatal error surface in isolated processes..."
  for fatal_case in integer-empty explicit-nil bad-to-s; do
    err="$TMP/interpreter-fatal-$fatal_case.txt"
    set +e
    ARRAY_JOIN_INTERPRETER_FATAL="$fatal_case" \
      "$TUNGSTEN" run "$SCRIPT_DIR/array_join_interpreter.w" >"$TMP/interpreter-fatal.out" 2>"$err"
    status=$?
    set -e
    if [ "$status" -ne 1 ]; then
      echo "interpreter fatal gate failed: $fatal_case exited $status, expected 1" >&2
      exit 1
    fi
    if ! grep -Fq 'runtime error: expected string or symbol' "$err"; then
      echo "interpreter fatal gate failed: $fatal_case lacks the exact runtime error" >&2
      sed -n '1,4p' "$err" >&2
      exit 1
    fi
  done
  echo "interpreter fatal errors: ok (eager empty/nil separator and invalid to_s return)"
fi

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_join_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_join_ab.w" --emit-wire > "$WIRE"

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

require_count() {
  fn="$1"
  pattern="$2"
  expected="$3"
  count="$(wire_body "$fn" | grep -Ec "$pattern" || true)"
  if [ "$count" -ne "$expected" ]; then
    echo "WIRE check failed: $fn has $count /$pattern/ sites, expected $expected" >&2
    exit 1
  fi
}

C0_FN="__w_Array___c_join__a1"
C1_FN="__w_Array___c_join__a2"
V1_WRAP="__w_Array___w_join_v1__a2"
V2_WRAP="__w_Array___w_join_v2__a2"
V3_WRAP="__w_Array___w_join_v3__a2"
V4_WRAP="__w_Array___w_join_v4__a2"
V5_WRAP="__w_Array___w_join_v5__a2"
V6_WRAP="__w_Array___w_join_v6__a2"
V1_FN="__w_Array___w_join_v1_impl__a2"
V2_FN="__w_Array___w_join_v2_impl__a2"
V3_FN="__w_Array___w_join_v3_impl__a2"
V4_FN="__w_Array___w_join_v4_impl__a2"
V5_FN="__w_Array___w_join_v5_impl__a2"
V6_FN="__w_Array___w_join_v6_impl__a2"
PUBLIC0_FN="__w_Array_join__a1"
PUBLIC1_FN="__w_Array_join__a2"

require_wire "$C0_FN" 'call_direct_i64 .*@w_ref_array_join0'
require_wire "$C1_FN" 'call_direct_i64 .*@w_ref_array_join1'
# Source-to-source method calls remain IC calls in WIRE even when the method
# name is unique.  Pin the single delegation site and independently inspect
# the named implementation bodies below.
require_count "$V1_WRAP" 'call_method_i64' 1
require_count "$V2_WRAP" 'call_method_i64' 1
require_count "$V3_WRAP" 'call_method_i64' 1
require_count "$V4_WRAP" 'call_method_i64' 1
require_count "$V5_WRAP" 'call_method_i64' 1
require_count "$V6_WRAP" 'call_method_i64' 1
reject_wire "$V1_WRAP" 'w_ref_array_join|w_ic_array_join'
reject_wire "$V2_WRAP" 'w_ref_array_join|w_ic_array_join'
reject_wire "$V3_WRAP" 'w_ref_array_join|w_ic_array_join'
reject_wire "$V4_WRAP" 'w_ref_array_join|w_ic_array_join'
reject_wire "$V5_WRAP" 'w_ref_array_join|w_ic_array_join'
reject_wire "$V6_WRAP" 'w_ref_array_join|w_ic_array_join'
require_count "$PUBLIC0_FN" 'call_method_i64' 1
reject_wire "$PUBLIC0_FN" 'w_ref_array_join|w_ic_array_join'

for fn in "$V1_FN" "$V2_FN" "$V3_FN" "$V4_FN" "$V5_FN"; do
  require_count "$fn" 'call_direct_i64 .*@w_to_s' 2
  require_count "$fn" 'call_direct_i64 .*@w_strbuf_append' 4
  require_count "$fn" 'call_direct_i64 .*@w_array_idx' 2
  require_count "$fn" 'view_load_field' 2
  require_wire "$fn" 'call_direct_i64 .*@w_strbuf_to_s'
  require_wire "$fn" 'call_direct_i64 .*@w_slab_is_frozen'
  require_wire "$fn" 'call_direct_i64 .*@w_str_append'
  require_wire "$fn" 'call_recycle_strbuf'
  reject_wire "$fn" 'call_reuse_or_new_strbuf'
  reject_wire "$fn" 'w_ref_array_join|w_ic_array_join'
done
require_count "$V6_FN" 'call_direct_i64 .*@w_to_s' 2
require_count "$V6_FN" 'call_direct_i64 .*@w_bench_as_str_length' 2
require_count "$V6_FN" 'call_direct_i64 .*@w_strbuf_append' 2
require_count "$V6_FN" 'call_direct_i64 .*@w_array_idx' 2
require_count "$V6_FN" 'view_load_field' 2
require_wire "$V6_FN" 'call_direct_i64 .*@w_strbuf_to_s'
require_wire "$V6_FN" 'call_direct_i64 .*@w_slab_is_frozen'
require_wire "$V6_FN" 'call_direct_i64 .*@w_str_append'
require_wire "$V6_FN" 'call_recycle_strbuf'
reject_wire "$V6_FN" 'call_reuse_or_new_strbuf|w_ref_array_join|w_ic_array_join'
require_count "$PUBLIC1_FN" 'call_direct_i64 .*@w_to_s' 2
require_count "$PUBLIC1_FN" 'call_direct_i64 .*@w_stringy_c_length' 2
require_count "$PUBLIC1_FN" 'call_direct_i64 .*@w_strbuf_append' 2
require_count "$PUBLIC1_FN" 'call_direct_i64 .*@w_array_idx' 2
require_count "$PUBLIC1_FN" 'view_load_field' 2
require_wire "$PUBLIC1_FN" 'call_direct_i64 .*@w_strbuf_to_s'
require_wire "$PUBLIC1_FN" 'call_direct_i64 .*@w_slab_is_frozen'
require_wire "$PUBLIC1_FN" 'call_direct_i64 .*@w_str_append'
require_wire "$PUBLIC1_FN" 'call_recycle_strbuf'
reject_wire "$PUBLIC1_FN" 'call_reuse_or_new_strbuf|w_ref_array_join|w_ic_array_join'
for fn in "$V1_FN" "$V2_FN" "$V3_FN"; do
  require_count "$fn" 'call_recycle_or_new_strbuf' 3
  require_count "$fn" 'cleanup_push_strbuf' 3
done
require_count "$V4_FN" 'call_recycle_or_new_strbuf' 2
require_count "$V4_FN" 'cleanup_push_strbuf' 2
require_count "$V5_FN" 'call_recycle_or_new_strbuf' 1
require_count "$V5_FN" 'cleanup_push_strbuf' 1
require_count "$V6_FN" 'call_recycle_or_new_strbuf' 1
require_count "$V6_FN" 'cleanup_push_strbuf' 1
require_count "$PUBLIC1_FN" 'call_recycle_or_new_strbuf' 1
require_count "$PUBLIC1_FN" 'cleanup_push_strbuf' 1
require_wire "$V2_FN" 'mul_i64'
require_count "$V3_FN" 'call_direct_i64 .*@w_bench_strbuf_reset' 1
require_count "$V5_FN" 'call_direct_i64 .*@w_bench_strbuf_reset' 1
reject_wire "$V1_FN" 'w_bench_strbuf_reset'
reject_wire "$V2_FN" 'w_bench_strbuf_reset'
reject_wire "$V4_FN" 'w_bench_strbuf_reset'
reject_wire "$V6_FN" 'w_bench_strbuf_reset'
reject_wire "$PUBLIC1_FN" 'w_bench_strbuf_reset'
for fn in "$V1_FN" "$V2_FN" "$V3_FN" "$V4_FN" "$V5_FN" "$PUBLIC1_FN"; do
  reject_wire "$fn" 'w_bench_as_str_length'
done
for fn in "$V1_FN" "$V2_FN" "$V3_FN" "$V4_FN" "$V5_FN" "$V6_FN"; do
  reject_wire "$fn" 'w_stringy_c_length'
done
echo "WIRE: ok (v1-v6 controls plus optimized public two-pass shape; v6/public have two raw validations, two output appends, one buffer, and no reset)"

echo "Compiling release benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/array_join_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/array_join_ab.w" --release --out "$BIN" >/dev/null

echo "Checking compiled C/v1-v6/public behavior, representation, and validation boundaries..."
"$BIN" check

echo "Checking production-fatal error surface in isolated processes..."
for fatal_case in integer-empty explicit-nil bad-to-s; do
  for path in c v1 v2 v3 v4 v5 v6 public; do
    err="$TMP/fatal-$fatal_case-$path.txt"
    set +e
    "$BIN" fatal "$fatal_case" "$path" >"$TMP/fatal.out" 2>"$err"
    status=$?
    set -e
    if [ "$status" -ne 1 ]; then
      echo "fatal gate failed: $fatal_case/$path exited $status, expected 1" >&2
      exit 1
    fi
    if ! grep -Fq 'runtime error: expected string or symbol' "$err"; then
      echo "fatal gate failed: $fatal_case/$path lacks the exact runtime error" >&2
      sed -n '1,4p' "$err" >&2
      exit 1
    fi
  done
done
echo "fatal errors: ok (eager empty/nil separator and invalid to_s return across C/v1-v6/public)"

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: interpreter, WIRE, release, correctness, cleanup, and fatal-error gates passed; timings skipped."
  exit 0
fi

echo "Running $RUNS balanced ABBA samples for $PATH_MODE versus $BASE_PATH across: $WORKLOADS"
: > "$RAW"
for workload in $WORKLOADS; do
  workload_iters="$(iters_for "$workload")"
  i=1
  while [ "$i" -le "$RUNS" ]; do
    parity=$(( (i - 1) % 2 ))
    echo "  $workload sample $i/$RUNS x $workload_iters (parity $parity)" >&2
    "$BIN" bench "$workload_iters" "$parity" "$PATH_MODE" "$workload" "$BASE_PATH" >> "$RAW"
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

echo
printf '%-24s %12s %12s %10s %8s\n' "function/workload" "$BASE_PATH ns" "$PATH_MODE ns" "$PATH_MODE/$BASE_PATH" "gate"
printf '%-24s %12s %12s %10s %8s\n' "------------------------" "------------" "------------" "----------" "--------"

overall=PASS
for workload in $WORKLOADS; do
  name="join.$PATH_MODE.$workload"
  c_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $3 }' "$RAW" | median_stream)"
  w_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $4 }' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v fn="$name" '$1 == "RESULT" && $2 == fn { print $5 }' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
  if [ "$decision" != "PASS" ]; then overall=SKIP; fi
  printf '%-24s %12.3f %12.3f %10.3f %8s\n' "$name" "$c_med" "$w_med" "$ratio_med" "$decision"
done

echo
echo "Each sample is base/candidate/candidate/base or its reverse; both legs are summed per implementation."
echo "Heap outputs are released in bounded batches outside timed intervals."
echo "Retention requires every independent stratum median $PATH_MODE/$BASE_PATH <= $GATE, then a separate repeat below 1.00."

if [ "$overall" != "PASS" ]; then
  echo "Strict gate: Array#join $PATH_MODE does not improve on $BASE_PATH and must not replace it." >&2
  exit 3
fi
if [ "$BASE_PATH" = "v1" ]; then
  echo "Optimization gate passed once; production replacement still requires an independent rebuild/repeat with every median below 1.00."
fi
