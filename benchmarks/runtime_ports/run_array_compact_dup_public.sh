#!/usr/bin/env bash
# Cross-build public-dispatch gate for Array#compact and Array#dup. This script
# does not edit either root. Prepare isolated roots only after the corresponding
# unique-name candidate has passed the current gate and its independent repeat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/array_compact_dup_public_hot.w"
REFERENCE="$SCRIPT_DIR/array_compact_dup_ref.c"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"
REPEAT="${REPEAT:-0}"
ITERS="${ITERS:-}"
COMPACT_WORKLOADS="${COMPACT_WORKLOADS:-empty all-nil singleton small-dense small-sparse medium-dense medium-sparse large-dense large-sparse typed shifted}"
DUP_WORKLOADS="${DUP_WORKLOADS:-empty singleton small medium large typed shifted}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-migration Tungsten root" >&2
  exit 2
fi
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ONLY" in ''|compact|dup) ;; *) echo "ONLY must be compact or dup" >&2; exit 2 ;; esac
case "$REPEAT" in 0|1) ;; *) echo "REPEAT must be 0 or 1" >&2; exit 2 ;; esac
if [ -n "$ITERS" ]; then
  case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;; esac
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must be different isolated roots" >&2
  exit 2
fi
for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  if [ ! -x "$root/bin/tungsten" ]; then
    echo "missing executable $root/bin/tungsten" >&2
    exit 2
  fi
  if [ ! -f "$root/core/array.w" ] || [ ! -f "$root/runtime/runtime.c" ]; then
    echo "root lacks core/array.w or runtime/runtime.c: $root" >&2
    exit 2
  fi
done

operations=()
if [ -z "$ONLY" ] || [ "$ONLY" = compact ]; then operations+=(compact); fi
if [ -z "$ONLY" ] || [ "$ONLY" = dup ]; then operations+=(dup); fi

# Pin the intended production shape before paying compilation cost: baseline
# has the native table entry and no Array source body; candidate is the inverse.
for operation in "${operations[@]}"; do
  case "$operation" in
    compact) ic_name=WN_compact; handler=w_ic_array_compact ;;
    dup) ic_name=WN_dup; handler=w_ic_array_dup ;;
  esac
  method_pattern="^[[:space:]]*->[[:space:]]+$operation[[:space:]]*$"
  assignment_pattern="[.]name[[:space:]]*=[[:space:]]*$ic_name[[:space:]]*;"
  table_pattern="[{]0,[[:space:]]*$handler[}]"

  if grep -Eq "$method_pattern" "$BASELINE_ROOT/core/array.w"; then
    echo "shape audit failed: baseline already defines Array#$operation" >&2
    exit 1
  fi
  if ! grep -Eq "$assignment_pattern" "$BASELINE_ROOT/runtime/runtime.c" || \
     ! grep -Eq "$table_pattern" "$BASELINE_ROOT/runtime/runtime.c"; then
    echo "shape audit failed: baseline lacks the installed $operation IC" >&2
    exit 1
  fi
  if ! grep -Eq "$method_pattern" "$CANDIDATE_ROOT/core/array.w"; then
    echo "shape audit failed: candidate lacks public Array#$operation source" >&2
    exit 1
  fi
  if grep -Eq "$assignment_pattern" "$CANDIDATE_ROOT/runtime/runtime.c" || \
     grep -Eq "$table_pattern" "$CANDIDATE_ROOT/runtime/runtime.c"; then
    echo "shape audit failed: candidate still installs the $operation IC" >&2
    exit 1
  fi
done
echo "shape audit: baseline native IC / candidate public source are isolated for: ${operations[*]}"

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
  if [ -n "$ITERS" ]; then echo "$ITERS"; return; fi
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-compact-dup-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SOURCE_COPY="$TMP/array_compact_dup_public_hot.w"
REFERENCE_COPY="$TMP/array_compact_dup_ref.c"
BASELINE_BIN="$TMP/baseline"
CANDIDATE_BIN="$TMP/candidate"
BASELINE_WIRE="$TMP/baseline.wire"
CANDIDATE_WIRE="$TMP/candidate.wire"
RAW="$TMP/results.txt"
cp "$SOURCE" "$SOURCE_COPY"
cp "$REFERENCE" "$REFERENCE_COPY"

echo "Compiling isolated WIRE and release binaries (excluded from timings)..."
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$REFERENCE_COPY" \
    "$BASELINE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --emit-wire > "$BASELINE_WIRE"
  TUNGSTEN_C_INCLUDES="$REFERENCE_COPY" \
    "$BASELINE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$BASELINE_BIN" >/dev/null
)
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$REFERENCE_COPY" \
    "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --emit-wire > "$CANDIDATE_WIRE"
  TUNGSTEN_C_INCLUDES="$REFERENCE_COPY" \
    "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$CANDIDATE_BIN" >/dev/null
)

wire_body() {
  local path="$1" fn="$2"
  sed -n "/^function $fn(/,/^$/p" "$path"
}
for operation in "${operations[@]}"; do
  fn="__w_Array_${operation}__a1"
  if wire_body "$BASELINE_WIRE" "$fn" | grep -q .; then
    echo "WIRE audit failed: baseline unexpectedly emits public source $fn" >&2
    exit 1
  fi
  body="$(wire_body "$CANDIDATE_WIRE" "$fn")"
  for pattern in 'call_direct_i64 .*@w_array_new_empty' 'call_direct_i64 .*@w_array_idx' \
                 'call_direct_i64 .*@w_array_push' 'view_load_field'; do
    if ! grep -Eq "$pattern" <<< "$body"; then
      echo "WIRE audit failed: candidate $fn lacks /$pattern/" >&2
      exit 1
    fi
  done
  if grep -Eq 'w_ref_array_|w_ic_array_|call_method_i64|call_recycle_or_new_array|call_reuse_or_new_array' <<< "$body"; then
    echo "WIRE audit failed: candidate $fn retained a forbidden fallback" >&2
    exit 1
  fi
done
echo "WIRE audit: candidate public bodies are direct allocation/decode/push loops"

echo "Checking exact public behavior in both isolated builds..."
for operation in "${operations[@]}"; do
  "$BASELINE_BIN" check "$operation"
  "$CANDIDATE_BIN" check "$operation"
done

measure() {
  local binary="$1" operation="$2" workload="$3" iters="$4" warmup="$5"
  local output line
  output="$("$binary" bench "$operation" "$workload" "$iters" "$warmup")"
  line="$(printf '%s\n' "$output" | awk -F'|' -v name="public.$operation.$workload" '$1 == "RESULT" && $2 == name { print $3 "|" $4 }')"
  if [ -z "$line" ]; then
    echo "missing RESULT for $operation/$workload from $binary" >&2
    return 1
  fi
  printf '%s\n' "$line"
}

echo "Running $RUNS balanced baseline/candidate pairs..."
: > "$RAW"
for operation in "${operations[@]}"; do
  if [ "$operation" = compact ]; then workloads="$COMPACT_WORKLOADS"; else workloads="$DUP_WORKLOADS"; fi
  for workload in $workloads; do
    workload_iters="$(iters_for "$operation" "$workload")"
    warmup_iters="$(warmup_for "$operation" "$workload")"
    sample=0
    while [ "$sample" -lt "$RUNS" ]; do
      if [ $((sample % 2)) -eq 0 ]; then
        echo "  $operation/$workload pair $((sample + 1))/$RUNS (baseline/candidate)" >&2
        baseline_result="$(measure "$BASELINE_BIN" "$operation" "$workload" "$workload_iters" "$warmup_iters")"
        candidate_result="$(measure "$CANDIDATE_BIN" "$operation" "$workload" "$workload_iters" "$warmup_iters")"
      else
        echo "  $operation/$workload pair $((sample + 1))/$RUNS (candidate/baseline)" >&2
        candidate_result="$(measure "$CANDIDATE_BIN" "$operation" "$workload" "$workload_iters" "$warmup_iters")"
        baseline_result="$(measure "$BASELINE_BIN" "$operation" "$workload" "$workload_iters" "$warmup_iters")"
      fi
      baseline_ns="${baseline_result%%|*}"
      baseline_checksum="${baseline_result#*|}"
      candidate_ns="${candidate_result%%|*}"
      candidate_checksum="${candidate_result#*|}"
      if [ "$baseline_checksum" != "$candidate_checksum" ]; then
        echo "checksum mismatch for $operation/$workload: $baseline_checksum != $candidate_checksum" >&2
        exit 1
      fi
      ratio="$(awk -v candidate="$candidate_ns" -v baseline="$baseline_ns" 'BEGIN { print candidate / baseline }')"
      printf 'PAIR|%s.%s|%s|%s|%s|%s\n' "$operation" "$workload" \
        "$baseline_ns" "$candidate_ns" "$ratio" "$baseline_checksum" >> "$RAW"
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
printf '%-24s %12s %12s %10s %8s\n' "method/workload" "native ns" "source ns" "source/C" "gate"
failed=0
for operation in "${operations[@]}"; do
  if [ "$operation" = compact ]; then workloads="$COMPACT_WORKLOADS"; else workloads="$DUP_WORKLOADS"; fi
  for workload in $workloads; do
    name="$operation.$workload"
    baseline_med="$(awk -F'|' -v name="$name" '$1 == "PAIR" && $2 == name { print $3 }' "$RAW" | median_stream)"
    candidate_med="$(awk -F'|' -v name="$name" '$1 == "PAIR" && $2 == name { print $4 }' "$RAW" | median_stream)"
    ratio_med="$(awk -F'|' -v name="$name" '$1 == "PAIR" && $2 == name { print $5 }' "$RAW" | median_stream)"
    decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN { print (ratio <= gate) ? "PASS" : "SKIP" }')"
    if [ "$decision" != PASS ]; then failed=1; fi
    printf '%-24s %12.3f %12.3f %10.3f %8s\n' "$name" "$baseline_med" "$candidate_med" "$ratio_med" "$decision"
  done
done

echo
echo "Compact and dup remain independent decisions; every selected stratum must pass."
if [ "$REPEAT" = 1 ]; then
  echo "Public repeat requires every ratio at or below $GATE after a fresh isolated-root rebuild."
else
  echo "Public first pass requires every ratio <= $GATE, followed by an independent REPEAT=1 campaign at or below $GATE."
fi
if [ "$failed" -ne 0 ]; then
  echo "Public source migration failed at least one strict stratum; restore/retain that IC." >&2
  exit 3
fi
