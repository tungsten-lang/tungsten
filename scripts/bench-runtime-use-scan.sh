#!/usr/bin/env bash
# Matched self-host benchmark for the fused ARGV/builtin-runtime-use AST walk.
#
# Both compiler executables consume one immutable snapshot of SOURCE_ROOT and
# every warmup/measured pair must emit byte-identical LLVM. The benchmark is
# intentionally separate from compiler construction: build both executables
# from one common bootstrap before invoking this script.

set -euo pipefail

BASELINE_COMPILER="${BASELINE_COMPILER:-}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-}"
SOURCE_ROOT="${SOURCE_ROOT:-}"
PAIRS="${PAIRS:-8}"
GATE="${GATE:-1.10}"
RESULTS_OUT="${RESULTS_OUT:-}"

for name in BASELINE_COMPILER CANDIDATE_COMPILER SOURCE_ROOT; do
  value="${!name}"
  if [ -z "$value" ]; then
    echo "set $name" >&2
    exit 2
  fi
done
for compiler in "$BASELINE_COMPILER" "$CANDIDATE_COMPILER"; do
  if [ ! -x "$compiler" ]; then
    echo "missing executable compiler: $compiler" >&2
    exit 2
  fi
done
if [ ! -f "$SOURCE_ROOT/compiler/tungsten.w" ]; then
  echo "missing compiler payload under SOURCE_ROOT: $SOURCE_ROOT" >&2
  exit 2
fi
case "$PAIRS" in
  ''|*[!0-9]*|0)
    echo "PAIRS must be a positive integer" >&2
    exit 2
    ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-runtime-use-scan.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FIXED="$TMP/fixed"
mkdir -p "$FIXED/languages"
cp -R "$SOURCE_ROOT/compiler" "$FIXED/compiler"
cp -R "$SOURCE_ROOT/core" "$FIXED/core"
cp -R "$SOURCE_ROOT/languages/tungsten" "$FIXED/languages/tungsten"
PAYLOAD="$FIXED/compiler/tungsten.w"
RAW="$TMP/results.txt"

source_digest="$(
  cd "$FIXED"
  {
    find compiler core languages/tungsten -type f | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done
  } | shasum -a 256 | awk '{print $1}'
)"
echo "Fixed source snapshot: $source_digest"

run_once() {
  local compiler="$1"
  local label="$2"
  local ll="$TMP/$label.ll"
  local log="$TMP/$label.log"
  local timing="$TMP/$label.time"
  local lowering total wall user

  if ! (
    cd "$FIXED"
    /usr/bin/time -lp env \
      -u TUNGSTEN_LL_DIR \
      -u TUNGSTEN_LL_DONE_MARKER \
      -u TUNGSTEN_STOP_AFTER_LOAD_PARSE \
      TUNGSTEN_ROOT="$FIXED" \
      TUNGSTEN_GPU_DIALECTS=none \
      TUNGSTEN_LL_PATH="$ll" \
      "$compiler" compile "$PAYLOAD" --release --emit-ll --verbose \
        --out "$TMP/$label.out" >"$log" 2>"$timing"
  ); then
    echo "compiler run failed: $label" >&2
    sed -n '1,220p' "$log" >&2
    sed -n '1,120p' "$timing" >&2
    return 1
  fi

  lowering="$(awk '$2=="lowering" && $3=="to" && $4=="wire" {v=$1; sub(/s$/, "", v); print v}' "$log" | tail -1)"
  total="$(awk '/TOTAL COMPILE TIME/ {v=$1; sub(/s$/, "", v); print v}' "$log" | tail -1)"
  wall="$(awk '$1=="real" {print $2; exit} $2=="real" {print $1; exit}' "$timing")"
  user="$(awk '$1=="user" {print $2; exit} $2=="user" {print $1; exit}' "$timing")"
  if [ -z "$lowering" ] || [ -z "$total" ] || [ -z "$wall" ] || [ -z "$user" ] || [ ! -s "$ll" ]; then
    echo "missing metric or LLVM artifact: $label" >&2
    return 1
  fi
  printf '%s|%s|%s|%s|%s\n' "$lowering" "$total" "$wall" "$user" "$ll"
}

check_identity() {
  local baseline_ll="$1"
  local candidate_ll="$2"
  local label="$3"
  if ! cmp -s "$baseline_ll" "$candidate_ll"; then
    echo "FAIL $label: LLVM output differs" >&2
    shasum -a 256 "$baseline_ll" "$candidate_ll" >&2
    return 1
  fi
}

echo "Warming both compilers (excluded from samples)..."
baseline_warm="$(run_once "$BASELINE_COMPILER" baseline-warm)"
candidate_warm="$(run_once "$CANDIDATE_COMPILER" candidate-warm)"
IFS='|' read -r _ _ _ _ baseline_warm_ll <<< "$baseline_warm"
IFS='|' read -r _ _ _ _ candidate_warm_ll <<< "$candidate_warm"
check_identity "$baseline_warm_ll" "$candidate_warm_ll" warmup

: > "$RAW"
i=1
while [ "$i" -le "$PAIRS" ]; do
  if [ $((i % 2)) -eq 1 ]; then
    baseline="$(run_once "$BASELINE_COMPILER" "baseline-$i")"
    candidate="$(run_once "$CANDIDATE_COMPILER" "candidate-$i")"
  else
    candidate="$(run_once "$CANDIDATE_COMPILER" "candidate-$i")"
    baseline="$(run_once "$BASELINE_COMPILER" "baseline-$i")"
  fi
  IFS='|' read -r bl bt bw bu bll <<< "$baseline"
  IFS='|' read -r cl ct cw cu cll <<< "$candidate"
  check_identity "$bll" "$cll" "pair $i"
  printf 'PAIR|%s|%s|%s|%s|%s|%s|%s|%s\n' "$bl" "$cl" "$bt" "$ct" "$bw" "$cw" "$bu" "$cu" >> "$RAW"
  printf 'pair %d/%d lowering %.3f/%.3f total %.3f/%.3f wall %.3f/%.3f user %.3f/%.3f\n' \
    "$i" "$PAIRS" "$bl" "$cl" "$bt" "$ct" "$bw" "$cw" "$bu" "$cu" >&2
  i=$((i + 1))
done

median_field() {
  local field="$1"
  awk -F'|' -v field="$field" '$1=="PAIR" {print $field}' "$RAW" | sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2) print values[(NR + 1) / 2]
      else print (values[NR / 2] + values[NR / 2 + 1]) / 2
    }'
}

bl="$(median_field 2)"
cl="$(median_field 3)"
bt="$(median_field 4)"
ct="$(median_field 5)"
bw="$(median_field 6)"
cw="$(median_field 7)"
bu="$(median_field 8)"
cu="$(median_field 9)"
lr="$(awk -v c="$cl" -v b="$bl" 'BEGIN {print c / b}')"
tr="$(awk -v c="$ct" -v b="$bt" 'BEGIN {print c / b}')"
wr="$(awk -v c="$cw" -v b="$bw" 'BEGIN {print c / b}')"
ur="$(awk -v c="$cu" -v b="$bu" 'BEGIN {print c / b}')"
decision="$(awk -v l="$lr" -v t="$tr" -v w="$wr" -v u="$ur" -v gate="$GATE" 'BEGIN {print (l <= gate && t <= gate && w <= gate && u <= gate) ? "PASS" : "SKIP"}')"

printf '%-18s %10s %10s %8s\n' metric baseline candidate ratio
printf '%-18s %10.3f %10.3f %8.3f\n' 'lowering s' "$bl" "$cl" "$lr"
printf '%-18s %10.3f %10.3f %8.3f\n' 'compiler total s' "$bt" "$ct" "$tr"
printf '%-18s %10.3f %10.3f %8.3f\n' 'wall s' "$bw" "$cw" "$wr"
printf '%-18s %10.3f %10.3f %8.3f\n' 'user s' "$bu" "$cu" "$ur"
echo "retention gate: $decision (all ratios <= $GATE)"
echo "All warmup and measured LLVM pairs were byte-identical."

if [ -n "$RESULTS_OUT" ]; then
  cp "$RAW" "$RESULTS_OUT"
fi

if [ "$decision" != "PASS" ]; then
  exit 1
fi
