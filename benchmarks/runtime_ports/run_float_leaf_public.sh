#!/usr/bin/env bash
# Isolated native-IC versus public source-method gate for Float leaves.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/float_leaf_public.w"
INTERPRETER_CHECK="$ROOT/spec/interpreter/float_leaf_native_spec.w"
REF="$SCRIPT_DIR/float_leaf_public_ref.c"
CLOCK_REF="$SCRIPT_DIR/runtime_port_clock_ref.c"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-1.10}"
CHECK_ONLY="${CHECK_ONLY:-0}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-migration Tungsten root" >&2
  exit 2
fi
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be positive" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must differ" >&2
  exit 2
fi
for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -x "$root/bin/tungsten" || { echo "missing $root/bin/tungsten" >&2; exit 2; }
  test -d "$root/benchmarks/runtime_ports" || { echo "missing benchmark directory in $root" >&2; exit 2; }
done

for handler in w_ic_float_abs w_ic_float_nan_q w_ic_float_infinite_q; do
  grep -q "static WValue $handler" "$BASELINE_ROOT/runtime/runtime.c" || { echo "baseline lacks $handler" >&2; exit 1; }
  if grep -q "static WValue $handler" "$CANDIDATE_ROOT/runtime/runtime.c"; then
    echo "candidate still contains $handler" >&2
    exit 1
  fi
done
echo "shape audit: three baseline native ICs / three candidate source methods"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-float-leaf-public.XXXXXX")"
BASE_SOURCE="$(mktemp "$BASELINE_ROOT/benchmarks/runtime_ports/.float-leaf-public.XXXXXX.w")"
CAND_SOURCE="$(mktemp "$CANDIDATE_ROOT/benchmarks/runtime_ports/.float-leaf-public.XXXXXX.w")"
trap 'rm -rf "$TMP"; rm -f "$BASE_SOURCE" "$CAND_SOURCE"' EXIT
cp "$SOURCE" "$BASE_SOURCE"
cp "$SOURCE" "$CAND_SOURCE"

BASE_BIN="$TMP/baseline"
CAND_BIN="$TMP/candidate"
WIRE="$TMP/candidate.wire"
RAW="$TMP/results.txt"
INCLUDES="$REF:$CLOCK_REF"

echo "Compiling matched public binaries (excluded from timings)..."
(
  cd "$BASELINE_ROOT"
  TUNGSTEN_C_INCLUDES="$INCLUDES" bin/tungsten compile "$BASE_SOURCE" --release --out "$BASE_BIN" >/dev/null
)
(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_C_INCLUDES="$INCLUDES" bin/tungsten compile "$CAND_SOURCE" --emit-wire > "$WIRE"
  TUNGSTEN_C_INCLUDES="$INCLUDES" bin/tungsten compile "$CAND_SOURCE" --release --out "$CAND_BIN" >/dev/null
)

wire_body() { sed -n "/^function $1(/,/^$/p" "$WIRE"; }
for fn in __w_Float_abs__a1 __w_Float_nan_Q__a1 __w_Float_infinite_Q__a1; do
  body="$(wire_body "$fn")"
  test -n "$body" || { echo "WIRE missing $fn" >&2; exit 1; }
  printf '%s\n' "$body" | grep -q 'sub_i64' || { echo "WIRE $fn lacks unbias" >&2; exit 1; }
  printf '%s\n' "$body" | grep -q 'and_i64' || { echo "WIRE $fn lacks magnitude mask" >&2; exit 1; }
  printf '%s\n' "$body" | grep -q 'icmp_i64' || { echo "WIRE $fn lacks comparison" >&2; exit 1; }
  if printf '%s\n' "$body" | grep -Eq 'w_ic_float|call_method_i64'; then
    echo "WIRE $fn retained a C/generic fallback" >&2
    exit 1
  fi
done
echo "WIRE audit: public leaves are biased-word source operations with no C fallback"

"$BASE_BIN" check
"$CAND_BIN" check
(
  cd "$CANDIDATE_ROOT"
  bin/tungsten run "$INTERPRETER_CHECK"
)
if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: shape, WIRE, compiled, and tree-walker gates passed."
  exit 0
fi

run_leg() {
  local bin="$1" kind="$2" line
  line="$("$bin" bench "$kind" "$ITERS")"
  printf '%s\n' "$line" | awk -F'|' '$1 == "RESULT" { print $3 "|" $4 }'
}

kinds=(abs-finite abs-edge abs-nan 'nan?' 'infinite?')
: > "$RAW"
sample=1
while [ "$sample" -le "$RUNS" ]; do
  parity=$(( (sample - 1) % 2 ))
  for kind in "${kinds[@]}"; do
    if [ "$parity" -eq 0 ]; then order=(B C C B); else order=(C B B C); fi
    b_sum=0
    c_sum=0
    checksum=""
    for side in "${order[@]}"; do
      if [ "$side" = B ]; then bin="$BASE_BIN"; else bin="$CAND_BIN"; fi
      result="$(run_leg "$bin" "$kind")"
      elapsed="${result%%|*}"
      got_checksum="${result#*|}"
      if [ -n "$checksum" ] && [ "$got_checksum" != "$checksum" ]; then
        echo "checksum mismatch for $kind: $got_checksum != $checksum" >&2
        exit 1
      fi
      checksum="$got_checksum"
      if [ "$side" = B ]; then b_sum=$((b_sum + elapsed)); else c_sum=$((c_sum + elapsed)); fi
    done
    ratio="$(awk -v c="$c_sum" -v b="$b_sum" 'BEGIN { print c/b }')"
    printf 'PAIR|%s|%s|%s|%s|%s|%s|%s\n' "$kind" "$b_sum" "$c_sum" "$ratio" "$checksum" "$sample" "$parity" >> "$RAW"
  done
  sample=$((sample + 1))
done

median_stream() { sort -n | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'; }
printf '\n%-12s %14s %14s %10s %8s\n' stratum baseline-ns candidate-ns C/B gate
failed=0
for kind in "${kinds[@]}"; do
  b_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $3}' "$RAW" | median_stream)"
  c_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $4}' "$RAW" | median_stream)"
  r_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $5}' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$r_med" -v gate="$GATE" 'BEGIN {print ratio<=gate ? "PASS" : "SKIP"}')"
  test "$decision" = PASS || failed=1
  printf '%-12s %14.0f %14.0f %10.3f %8s\n' "$kind" "$b_med" "$c_med" "$r_med" "$decision"
done
echo "Thread CPU time excludes competing-process scheduling; repeat independently before retention."
if [ "$failed" -ne 0 ]; then exit 3; fi
