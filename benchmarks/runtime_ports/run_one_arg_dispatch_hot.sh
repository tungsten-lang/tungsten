#!/usr/bin/env bash
# Production-shaped cross-build gate for a compiler-emitted argc-one helper.
#
# The baseline and candidate roots must be isolated copies that differ only by
# the production trial. The candidate is expected to expose
# w_method_call_cached_1 and emit it for every argc-one dynamic call. This
# runner copies the shared source to /tmp before compiling so each root's
# TUNGSTEN_ROOT, core library, compiler, and runtime remain isolated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/one_arg_dispatch_hot.w"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-trial Tungsten root" >&2
  exit 2
fi

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive even integer" >&2; exit 2 ;;
esac
if [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be even so baseline-first and candidate-first pairs balance" >&2
  exit 2
fi
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$ONLY" in
  ''|source1|native1) ;;
  *) echo "ONLY must be source1 or native1" >&2; exit 2 ;;
esac

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
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-one-arg-hot.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SOURCE_COPY="$TMP/one_arg_dispatch_hot.w"
BASELINE_BIN="$TMP/baseline"
CANDIDATE_BIN="$TMP/candidate"
BASELINE_LL="$TMP/baseline.ll"
CANDIDATE_LL="$TMP/candidate.ll"
RAW="$TMP/results.txt"
cp "$SOURCE" "$SOURCE_COPY"

echo "Compiling isolated release binaries and LLVM audits (excluded from timings)..."
(
  cd "$TMP"
  TUNGSTEN_LL_PATH="$BASELINE_LL" \
    "$BASELINE_ROOT/bin/tungsten" compile "$SOURCE_COPY" \
    --release --out "$BASELINE_BIN" >/dev/null
)
(
  cd "$TMP"
  TUNGSTEN_LL_PATH="$CANDIDATE_LL" \
    "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" \
    --release --out "$CANDIDATE_BIN" >/dev/null
)

count_ir() {
  local pattern="$1"
  local path="$2"
  grep -Ec "$pattern" "$path" || true
}

generic_pattern='^[[:space:]]+%[^=]+=[[:space:]]+(tail[[:space:]]+)?call i64 @w_method_call_cached\(.*i32 1, ptr'
helper_pattern='^[[:space:]]+%[^=]+=[[:space:]]+(tail[[:space:]]+)?call i64 @w_method_call_cached_1\('
alloca_pattern='^[[:space:]]+%__mcall_args = alloca i64'
first_store_pattern='^[[:space:]]+store i64 .* ptr %__mcall_args(,|$)'

baseline_generic="$(count_ir "$generic_pattern" "$BASELINE_LL")"
candidate_generic="$(count_ir "$generic_pattern" "$CANDIDATE_LL")"
baseline_helper="$(count_ir "$helper_pattern" "$BASELINE_LL")"
candidate_helper="$(count_ir "$helper_pattern" "$CANDIDATE_LL")"
baseline_allocas="$(count_ir "$alloca_pattern" "$BASELINE_LL")"
candidate_allocas="$(count_ir "$alloca_pattern" "$CANDIDATE_LL")"
baseline_first_stores="$(count_ir "$first_store_pattern" "$BASELINE_LL")"
candidate_first_stores="$(count_ir "$first_store_pattern" "$CANDIDATE_LL")"

if [ "$baseline_generic" -le 0 ]; then
  echo "IR audit failed: baseline has no generic argc-one calls" >&2
  exit 1
fi
if [ "$candidate_generic" -ne 0 ]; then
  echo "IR audit failed: candidate retained $candidate_generic generic argc-one calls" >&2
  exit 1
fi
if [ "$baseline_helper" -ne 0 ]; then
  echo "IR audit failed: baseline already has $baseline_helper argc-one helper calls" >&2
  exit 1
fi
if [ "$candidate_helper" -ne "$baseline_generic" ]; then
  echo "IR audit failed: helper calls=$candidate_helper, baseline argc-one calls=$baseline_generic" >&2
  exit 1
fi
removed_stores=$((baseline_first_stores - candidate_first_stores))
if [ "$removed_stores" -ne "$baseline_generic" ]; then
  echo "IR audit failed: removed first-argument stores=$removed_stores, expected=$baseline_generic" >&2
  exit 1
fi
if [ "$candidate_allocas" -ge "$baseline_allocas" ]; then
  echo "IR audit failed: scratch allocas did not fall ($baseline_allocas -> $candidate_allocas)" >&2
  exit 1
fi

echo "IR audit: argc-one generic $baseline_generic -> 0; helper $baseline_helper -> $candidate_helper"
echo "IR audit: first-argument stores $baseline_first_stores -> $candidate_first_stores; scratch allocas $baseline_allocas -> $candidate_allocas"

echo "Checking exact baseline/candidate behavior..."
"$BASELINE_BIN" check 1027
"$CANDIDATE_BIN" check 1027

if [ -n "$ONLY" ]; then
  targets=("$ONLY")
else
  targets=(source1 native1)
fi

measure_ns() {
  local binary="$1"
  local target="$2"
  local output ns
  output="$("$binary" "$target" "$ITERS")"
  ns="$(printf '%s\n' "$output" | awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $3}')"
  if [ -z "$ns" ]; then
    echo "missing RESULT for $target from $binary" >&2
    return 1
  fi
  printf '%s\n' "$ns"
}

echo "Running $RUNS balanced cross-build pairs x $ITERS varying-argument calls${ONLY:+ ($ONLY only)}..."
: > "$RAW"
for target in "${targets[@]}"; do
  i=1
  while [ "$i" -le "$RUNS" ]; do
    if [ $((i % 2)) -eq 1 ]; then
      echo "  $target pair $i/$RUNS (baseline/candidate)" >&2
      baseline_ns="$(measure_ns "$BASELINE_BIN" "$target")"
      candidate_ns="$(measure_ns "$CANDIDATE_BIN" "$target")"
    else
      echo "  $target pair $i/$RUNS (candidate/baseline)" >&2
      candidate_ns="$(measure_ns "$CANDIDATE_BIN" "$target")"
      baseline_ns="$(measure_ns "$BASELINE_BIN" "$target")"
    fi
    ratio="$(awk -v candidate="$candidate_ns" -v baseline="$baseline_ns" 'BEGIN {print candidate / baseline}')"
    printf 'PAIR|%s|%s|%s|%s\n' "$target" "$baseline_ns" "$candidate_ns" "$ratio" >> "$RAW"
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
printf '%-10s %12s %12s %10s %8s\n' target 'baseline ns' 'argc-1 ns' ratio gate
for target in "${targets[@]}"; do
  baseline_med="$(awk -F'|' -v target="$target" '$1=="PAIR" && $2==target {print $3}' "$RAW" | median_stream)"
  candidate_med="$(awk -F'|' -v target="$target" '$1=="PAIR" && $2==target {print $4}' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v target="$target" '$1=="PAIR" && $2==target {print $5}' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN {print (ratio <= gate) ? "PASS" : "SKIP"}')"
  printf '%-10s %12.3f %12.3f %10.3f %8s\n' \
    "$target" "$baseline_med" "$candidate_med" "$ratio_med" "$decision"
done

echo "Production retention requires every target to clear $GATE and an independent repeat at or below $GATE."
