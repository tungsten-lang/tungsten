#!/usr/bin/env bash
# Matched self-host gate for in-place release metadata stripping.
#
# BASELINE_ROOT and CANDIDATE_ROOT must be isolated roots whose compiler
# executables differ only by the strip_enhanced_stacktrace_metadata trial.
# Both executables compile the exact same candidate-tree compiler source in
# --release/--emit-ll mode. Every pair must emit byte-identical LLVM before a
# timing result is accepted.
#
# A read-only lowered-WIRE census of /tmp/tungsten-audit.wire found:
#   2,149 functions, 37,611 blocks, 224,764 instructions
#   137 call_loc_set_col removals in 137 blocks; 224,627 survivors
# A retained release LLVM artifact has 36,559 blocks, while its matching debug
# artifact contains 138 location hooks, so this is a close pre-pass proxy rather
# than an exact post-analysis count. For the WIRE shape, the old pass allocates
# 37,611 replacement arrays and pushes every survivor; the in-place pass needs
# only 274 survivor moves plus 137 pops. The candidate loop keeps compaction
# inactive until the first hook, so marker-free blocks do not maintain a
# second boxed index across their instructions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
GATE="${GATE:-0.97}"
RESULTS_OUT="${RESULTS_OUT:-}"

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

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must be different isolated roots" >&2
  exit 2
fi
for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  if [ ! -x "$root/bin/tungsten-compiler" ]; then
    echo "missing executable $root/bin/tungsten-compiler" >&2
    exit 2
  fi
done

PAYLOAD="${PAYLOAD:-$CANDIDATE_ROOT/compiler/tungsten.w}"
if [ ! -f "$PAYLOAD" ]; then
  echo "missing compiler payload $PAYLOAD" >&2
  exit 2
fi
PAYLOAD="$(cd "$(dirname "$PAYLOAD")" && pwd)/$(basename "$PAYLOAD")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-strip-metadata.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
RAW="$TMP/results.txt"

run_once() {
  local root="$1"
  local label="$2"
  local ll_path="$3"
  local log_path="$TMP/$label.log"
  local time_path="$TMP/$label.time"
  local total wall user

  if ! (
    cd "$CANDIDATE_ROOT"
    /usr/bin/time -lp sh -c '
      TUNGSTEN_LL_PATH="$1" "$2" compile "$3" \
        --release --emit-ll --verbose --out "$4" >"$5" 2>&1
    ' sh "$ll_path" "$root/bin/tungsten-compiler" "$PAYLOAD" \
      "$TMP/$label" "$log_path" 2>"$time_path"
  ); then
    echo "compiler run failed for $label" >&2
    sed -n '1,220p' "$log_path" >&2
    sed -n '1,220p' "$time_path" >&2
    return 1
  fi

  total="$(awk '/TOTAL COMPILE TIME/ { value=$1; sub(/s$/, "", value); print value }' "$log_path" | tail -1)"
  wall="$(awk '$1=="real" {print $2; exit} $2=="real" {print $1; exit}' "$time_path")"
  user="$(awk '$1=="user" {print $2; exit} $2=="user" {print $1; exit}' "$time_path")"
  if [ -z "$total" ] || [ -z "$wall" ] || [ -z "$user" ] || [ ! -s "$ll_path" ]; then
    echo "missing compiler, wall, user, or LLVM output for $label" >&2
    sed -n '1,220p' "$log_path" >&2
    sed -n '1,220p' "$time_path" >&2
    return 1
  fi
  printf '%s|%s|%s\n' "$total" "$wall" "$user"
}

check_identity() {
  local baseline_ll="$1"
  local candidate_ll="$2"
  local label="$3"
  if ! cmp -s "$baseline_ll" "$candidate_ll"; then
    echo "FAIL $label: baseline/candidate LLVM differs" >&2
    shasum -a 256 "$baseline_ll" "$candidate_ll" >&2
    return 1
  fi
}

echo "Warming matched compiler executables (excluded from samples)..."
baseline_warm_ll="$TMP/baseline-warm.ll"
candidate_warm_ll="$TMP/candidate-warm.ll"
run_once "$BASELINE_ROOT" baseline-warm "$baseline_warm_ll" >/dev/null
run_once "$CANDIDATE_ROOT" candidate-warm "$candidate_warm_ll" >/dev/null
check_identity "$baseline_warm_ll" "$candidate_warm_ll" warmup

echo "Running $RUNS balanced release self-host pairs with per-pair LLVM identity checks..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  baseline_ll="$TMP/baseline-$i.ll"
  candidate_ll="$TMP/candidate-$i.ll"
  if [ $((i % 2)) -eq 1 ]; then
    echo "  pair $i/$RUNS (baseline/candidate)" >&2
    baseline_metrics="$(run_once "$BASELINE_ROOT" "baseline-$i" "$baseline_ll")"
    candidate_metrics="$(run_once "$CANDIDATE_ROOT" "candidate-$i" "$candidate_ll")"
  else
    echo "  pair $i/$RUNS (candidate/baseline)" >&2
    candidate_metrics="$(run_once "$CANDIDATE_ROOT" "candidate-$i" "$candidate_ll")"
    baseline_metrics="$(run_once "$BASELINE_ROOT" "baseline-$i" "$baseline_ll")"
  fi
  check_identity "$baseline_ll" "$candidate_ll" "pair $i"
  IFS='|' read -r baseline_total baseline_wall baseline_user <<< "$baseline_metrics"
  IFS='|' read -r candidate_total candidate_wall candidate_user <<< "$candidate_metrics"
  total_ratio="$(awk -v candidate="$candidate_total" -v baseline="$baseline_total" 'BEGIN { print candidate / baseline }')"
  wall_ratio="$(awk -v candidate="$candidate_wall" -v baseline="$baseline_wall" 'BEGIN { print candidate / baseline }')"
  user_ratio="$(awk -v candidate="$candidate_user" -v baseline="$baseline_user" 'BEGIN { print candidate / baseline }')"
  printf 'PAIR|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$baseline_total" "$candidate_total" "$total_ratio" \
    "$baseline_wall" "$candidate_wall" "$wall_ratio" \
    "$baseline_user" "$candidate_user" "$user_ratio" >> "$RAW"
  printf '  result total %.3f/%.3f (%.3f), wall %.3f/%.3f (%.3f), user %.3f/%.3f (%.3f)\n' \
    "$baseline_total" "$candidate_total" "$total_ratio" \
    "$baseline_wall" "$candidate_wall" "$wall_ratio" \
    "$baseline_user" "$candidate_user" "$user_ratio" >&2
  i=$((i + 1))
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

baseline_median="$(awk -F'|' '$1=="PAIR" {print $2}' "$RAW" | median_stream)"
candidate_median="$(awk -F'|' '$1=="PAIR" {print $3}' "$RAW" | median_stream)"
ratio_median="$(awk -F'|' '$1=="PAIR" {print $4}' "$RAW" | median_stream)"
baseline_wall_median="$(awk -F'|' '$1=="PAIR" {print $5}' "$RAW" | median_stream)"
candidate_wall_median="$(awk -F'|' '$1=="PAIR" {print $6}' "$RAW" | median_stream)"
wall_ratio_median="$(awk -F'|' '$1=="PAIR" {print $7}' "$RAW" | median_stream)"
baseline_user_median="$(awk -F'|' '$1=="PAIR" {print $8}' "$RAW" | median_stream)"
candidate_user_median="$(awk -F'|' '$1=="PAIR" {print $9}' "$RAW" | median_stream)"
user_ratio_median="$(awk -F'|' '$1=="PAIR" {print $10}' "$RAW" | median_stream)"
decision="$(awk -v total="$ratio_median" -v wall="$wall_ratio_median" -v user="$user_ratio_median" -v gate="$GATE" \
  'BEGIN {print (total <= gate && wall <= 1.0 && user <= 1.0) ? "PASS" : "SKIP"}')"

echo
printf '%-16s %12s %12s %10s\n' metric baseline candidate ratio
printf '%-16s %12.3f %12.3f %10.3f\n' 'compiler total s' "$baseline_median" "$candidate_median" "$ratio_median"
printf '%-16s %12.3f %12.3f %10.3f\n' 'real wall s' "$baseline_wall_median" "$candidate_wall_median" "$wall_ratio_median"
printf '%-16s %12.3f %12.3f %10.3f\n' 'user CPU s' "$baseline_user_median" "$candidate_user_median" "$user_ratio_median"
printf '%-16s %12s\n' 'retention gate' "$decision"
echo "All warmup and measured LLVM pairs were byte-identical."
echo "Retention requires compiler-total <= $GATE, no wall/user median regression, and an independent repeat below 1.00."
if [ -n "$RESULTS_OUT" ]; then
  cp "$RAW" "$RESULTS_OUT"
  echo "Raw paired metrics saved to $RESULTS_OUT"
fi
