#!/usr/bin/env bash
# Isolated correctness, LLVM-identity, and matched-performance gate for
# routing Lexer#emit and Lexer#emit_at through direct symbol-to-id helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREP_ROOT="${PREP_ROOT:-/tmp/tungsten-lexer-type-map-prep}"
BASELINE_ROOT="${BASELINE_ROOT:-$PREP_ROOT/baseline}"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$PREP_ROOT/candidate}"
SOURCE_ROOT="${SOURCE_ROOT:-$CANDIDATE_ROOT}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
BASELINE_BIN="${BASELINE_BIN:-$BASELINE_ROOT/bin/tungsten-lexer-type-map-trial}"
CANDIDATE_BIN="${CANDIDATE_BIN:-$CANDIDATE_ROOT/bin/tungsten-lexer-type-map-trial}"
PAIRS="${PAIRS:-5}"
GATE="${GATE:-0.97}"
STATIC_ONLY="${STATIC_ONLY:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CHECK_ONLY="${CHECK_ONLY:-0}"
RESULTS_OUT="${RESULTS_OUT:-}"

absolute_dir() {
  (cd "$1" && pwd)
}

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT" "$SOURCE_ROOT"; do
  if [ ! -d "$root" ]; then
    echo "missing isolated root: $root" >&2
    exit 2
  fi
done

BASELINE_ROOT="$(absolute_dir "$BASELINE_ROOT")"
CANDIDATE_ROOT="$(absolute_dir "$CANDIDATE_ROOT")"
SOURCE_ROOT="$(absolute_dir "$SOURCE_ROOT")"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "baseline and candidate roots must differ" >&2
  exit 2
fi
case "$PAIRS" in
  ''|*[!0-9]*|0)
    echo "PAIRS must be a positive integer (use 5 for the declared 5+5 gate)" >&2
    exit 2
    ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-lexer-type-map.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

static_audit() {
  local compiler_diff

  ruby "$ROOT/scripts/audit-lexer-type-map.rb" "$BASELINE_ROOT" "$CANDIDATE_ROOT"
  diff -qr "$BASELINE_ROOT/core" "$CANDIDATE_ROOT/core" >/dev/null
  diff -qr "$BASELINE_ROOT/runtime" "$CANDIDATE_ROOT/runtime" >/dev/null
  diff -qr "$BASELINE_ROOT/languages/tungsten" "$CANDIDATE_ROOT/languages/tungsten" >/dev/null
  diff -qr "$BASELINE_ROOT/spec" "$CANDIDATE_ROOT/spec" >/dev/null

  compiler_diff="$(diff -qr "$BASELINE_ROOT/compiler" "$CANDIDATE_ROOT/compiler" || true)"
  if [ "$(printf '%s\n' "$compiler_diff" | awk 'NF {n += 1} END {print n + 0}')" -ne 1 ] ||
     ! printf '%s\n' "$compiler_diff" | grep -Fq '/compiler/lib/lexer.w'; then
    echo "compiler trees differ outside the single lexer candidate:" >&2
    printf '%s\n' "$compiler_diff" >&2
    return 1
  fi

  cmp "$BASELINE_ROOT/spec/compiler/lexer_type_map_direct_spec.w" \
      "$CANDIDATE_ROOT/spec/compiler/lexer_type_map_direct_spec.w"
  echo "PASS matched roots: only compiler/lib/lexer.w differs"
}

static_audit
if [ "$STATIC_ONLY" = "1" ]; then
  exit 0
fi

TRIAL_BUILD_SOURCE="$TMP/trial-build-source"
TRIAL_BUILD_OUTPUT="$TMP/trial-compiler"
TRIAL_BUILD_LL="$TMP/trial-build.ll"

build_trial_compiler() {
  local label="$1"
  local root="$2"
  local output="$3"
  local ll="$TMP/$label-build.ll"
  local log="$TMP/$label-build.log"

  echo "Building $label trial compiler with the common bootstrap..."
  rm -rf "$TRIAL_BUILD_SOURCE"
  rm -f "$TRIAL_BUILD_OUTPUT" "$TRIAL_BUILD_OUTPUT.sidemap" "$TRIAL_BUILD_LL"
  mkdir -p "$TRIAL_BUILD_SOURCE/languages"
  cp -R "$root/compiler" "$TRIAL_BUILD_SOURCE/compiler"
  cp -R "$root/core" "$TRIAL_BUILD_SOURCE/core"
  cp -R "$root/runtime" "$TRIAL_BUILD_SOURCE/runtime"
  cp -R "$root/languages/tungsten" "$TRIAL_BUILD_SOURCE/languages/tungsten"
  if ! (
    cd "$TRIAL_BUILD_SOURCE"
    TUNGSTEN_ROOT="$TRIAL_BUILD_SOURCE" TUNGSTEN_LL_PATH="$TRIAL_BUILD_LL" \
      "$BOOTSTRAP_COMPILER" compile "$TRIAL_BUILD_SOURCE/compiler/tungsten.w" \
      --release --no-lto --verbose --out "$TRIAL_BUILD_OUTPUT" >"$log" 2>&1
  ); then
    echo "$label trial compiler build failed" >&2
    sed -n '1,240p' "$log" >&2
    return 1
  fi
  if [ ! -x "$TRIAL_BUILD_OUTPUT" ] || [ ! -s "$TRIAL_BUILD_LL" ]; then
    echo "$label trial build did not produce its compiler and LLVM artifact" >&2
    return 1
  fi
  if [ "$(uname -s)" = "Darwin" ] && command -v codesign >/dev/null 2>&1; then
    codesign --force -s - "$TRIAL_BUILD_OUTPUT" >/dev/null 2>&1
  fi
  cp "$TRIAL_BUILD_OUTPUT" "$output"
  if [ -f "$TRIAL_BUILD_OUTPUT.sidemap" ]; then
    cp "$TRIAL_BUILD_OUTPUT.sidemap" "$output.sidemap"
  else
    rm -f "$output.sidemap"
  fi
  cp "$TRIAL_BUILD_LL" "$ll"
}

if [ "$SKIP_BUILD" != "1" ]; then
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set BOOTSTRAP_COMPILER to one executable used for both trial builds" >&2
    exit 2
  fi
  BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"
  echo "Common bootstrap: $(shasum -a 256 "$BOOTSTRAP_COMPILER" | awk '{print $1}')"
  build_trial_compiler baseline "$BASELINE_ROOT" "$BASELINE_BIN"
  build_trial_compiler candidate "$CANDIDATE_ROOT" "$CANDIDATE_BIN"
else
  echo "Skipping builds; using retained isolated trial binaries."
fi

for bin in "$BASELINE_BIN" "$CANDIDATE_BIN"; do
  if [ ! -x "$bin" ]; then
    echo "missing trial compiler: $bin" >&2
    exit 2
  fi
done

run_focus_for_root() {
  local label="$1"
  local root="$2"
  local compiler="$3"
  local spec="$root/spec/compiler/lexer_type_map_direct_spec.w"
  local interpreter_out="$TMP/$label.interpreter.out"
  local compiled_out="$TMP/$label.compiled.out"
  local output="$TMP/$label-lexer-type-map-spec"
  local ll="$TMP/$label-lexer-type-map-spec.ll"
  local log="$TMP/$label-lexer-type-map-spec.compile.log"

  if ! (cd "$root" && TUNGSTEN_ROOT="$root" "$compiler" run "$spec") >"$interpreter_out" 2>&1; then
    echo "$label interpreter focused spec failed" >&2
    sed -n '1,240p' "$interpreter_out" >&2
    return 1
  fi
  if grep -Eq '^FAIL([ :]|$)' "$interpreter_out"; then
    echo "$label interpreter emitted a failed check" >&2
    sed -n '1,240p' "$interpreter_out" >&2
    return 1
  fi

  if ! (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_LL_PATH="$ll" \
      "$compiler" compile "$spec" --no-lto --out "$output" >"$log" 2>&1
  ); then
    echo "$label compiled focused spec failed to build" >&2
    sed -n '1,240p' "$log" >&2
    return 1
  fi
  if ! "$output" >"$compiled_out" 2>&1; then
    echo "$label compiled focused spec failed" >&2
    sed -n '1,240p' "$compiled_out" >&2
    return 1
  fi
  if grep -Eq '^FAIL([ :]|$)' "$compiled_out"; then
    echo "$label compiled focused spec emitted a failed check" >&2
    sed -n '1,240p' "$compiled_out" >&2
    return 1
  fi
}

echo "Running focused compiled and interpreter gates..."
run_focus_for_root baseline "$BASELINE_ROOT" "$BASELINE_BIN"
run_focus_for_root candidate "$CANDIDATE_ROOT" "$CANDIDATE_BIN"
cmp "$TMP/baseline.interpreter.out" "$TMP/candidate.interpreter.out"
cmp "$TMP/baseline.compiled.out" "$TMP/candidate.compiled.out"
echo "PASS focused semantics: baseline/candidate compiled and interpreter outputs match"

if [ "$CHECK_ONLY" = "1" ]; then
  exit 0
fi

# Freeze one source tree. Both compilers consume the same absolute files from
# the same working directory, so every emitted-LLVM comparison is meaningful.
FIXED="$TMP/fixed-source"
mkdir -p "$FIXED/languages"
cp -R "$SOURCE_ROOT/compiler" "$FIXED/compiler"
cp -R "$SOURCE_ROOT/core" "$FIXED/core"
cp -R "$SOURCE_ROOT/languages/tungsten" "$FIXED/languages/tungsten"
PAYLOAD="$FIXED/compiler/tungsten.w"

source_digest="$({
  find "$FIXED/compiler" "$FIXED/core" "$FIXED/languages/tungsten" -type f | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done
} | shasum -a 256 | awk '{print $1}')"
echo "Fixed source snapshot: $source_digest"

run_once() {
  local compiler="$1"
  local label="$2"
  local ll_path="$3"
  local log_path="$TMP/$label.log"
  local time_path="$TMP/$label.time"
  local load total wall user

  if ! (
    cd "$FIXED"
    /usr/bin/time -lp env \
      -u TUNGSTEN_LL_DIR \
      -u TUNGSTEN_LL_DONE_MARKER \
      -u TUNGSTEN_STOP_AFTER_LOAD_PARSE \
      TUNGSTEN_ROOT="$FIXED" \
      TUNGSTEN_GPU_DIALECTS=none \
      TUNGSTEN_LL_PATH="$ll_path" \
      "$compiler" compile "$PAYLOAD" --release --emit-ll --verbose \
      --out "$TMP/fixed-output" >"$log_path" 2>"$time_path"
  ); then
    echo "compiler run failed for $label" >&2
    sed -n '1,240p' "$log_path" >&2
    sed -n '1,120p' "$time_path" >&2
    return 1
  fi

  load="$(awk '$2=="load+parse" {v=$1; sub(/s$/, "", v); print v}' "$log_path" | tail -1)"
  total="$(awk '/TOTAL COMPILE TIME/ {v=$1; sub(/s$/, "", v); print v}' "$log_path" | tail -1)"
  wall="$(awk '$1=="real" {print $2; exit} $2=="real" {print $1; exit}' "$time_path")"
  user="$(awk '$1=="user" {print $2; exit} $2=="user" {print $1; exit}' "$time_path")"
  if [ -z "$load" ] || [ -z "$total" ] || [ -z "$wall" ] || [ -z "$user" ] || [ ! -s "$ll_path" ]; then
    echo "missing timing metric or LLVM output for $label" >&2
    sed -n '1,240p' "$log_path" >&2
    sed -n '1,120p' "$time_path" >&2
    return 1
  fi
  printf '%s|%s|%s|%s\n' "$load" "$total" "$wall" "$user"
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

echo "Warming both compilers (excluded from samples)..."
baseline_warm_ll="$TMP/baseline-warm.ll"
candidate_warm_ll="$TMP/candidate-warm.ll"
run_once "$BASELINE_BIN" baseline-warm "$baseline_warm_ll" >/dev/null
run_once "$CANDIDATE_BIN" candidate-warm "$candidate_warm_ll" >/dev/null
check_identity "$baseline_warm_ll" "$candidate_warm_ll" warmup

RAW="$TMP/results.txt"
: > "$RAW"
echo "Running $PAIRS matched pairs ($PAIRS baseline + $PAIRS candidate legs)..."
i=1
while [ "$i" -le "$PAIRS" ]; do
  baseline_ll="$TMP/baseline-$i.ll"
  candidate_ll="$TMP/candidate-$i.ll"
  if [ $((i % 2)) -eq 1 ]; then
    echo "  pair $i/$PAIRS (baseline/candidate)" >&2
    baseline_metrics="$(run_once "$BASELINE_BIN" "baseline-$i" "$baseline_ll")"
    candidate_metrics="$(run_once "$CANDIDATE_BIN" "candidate-$i" "$candidate_ll")"
  else
    echo "  pair $i/$PAIRS (candidate/baseline)" >&2
    candidate_metrics="$(run_once "$CANDIDATE_BIN" "candidate-$i" "$candidate_ll")"
    baseline_metrics="$(run_once "$BASELINE_BIN" "baseline-$i" "$baseline_ll")"
  fi
  check_identity "$baseline_ll" "$candidate_ll" "pair $i"

  IFS='|' read -r baseline_load baseline_total baseline_wall baseline_user <<< "$baseline_metrics"
  IFS='|' read -r candidate_load candidate_total candidate_wall candidate_user <<< "$candidate_metrics"
  load_ratio="$(awk -v c="$candidate_load" -v b="$baseline_load" 'BEGIN {print c / b}')"
  total_ratio="$(awk -v c="$candidate_total" -v b="$baseline_total" 'BEGIN {print c / b}')"
  wall_ratio="$(awk -v c="$candidate_wall" -v b="$baseline_wall" 'BEGIN {print c / b}')"
  user_ratio="$(awk -v c="$candidate_user" -v b="$baseline_user" 'BEGIN {print c / b}')"
  printf 'PAIR|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$baseline_load" "$candidate_load" "$load_ratio" \
    "$baseline_total" "$candidate_total" "$total_ratio" \
    "$baseline_wall" "$candidate_wall" "$wall_ratio" \
    "$baseline_user" "$candidate_user" "$user_ratio" >> "$RAW"
  printf '    load %.3f/%.3f (%.3f), total %.3f/%.3f (%.3f), wall %.3f/%.3f (%.3f), user %.3f/%.3f (%.3f)\n' \
    "$baseline_load" "$candidate_load" "$load_ratio" \
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

summarize_metric() {
  local name="$1"
  local base_col="$2"
  local candidate_col="$3"
  local ratio_col="$4"
  local baseline_median candidate_median ratio_median aggregate_ratio wins

  baseline_median="$(awk -F'|' -v c="$base_col" '$1=="PAIR" {print $c}' "$RAW" | median_stream)"
  candidate_median="$(awk -F'|' -v c="$candidate_col" '$1=="PAIR" {print $c}' "$RAW" | median_stream)"
  ratio_median="$(awk -F'|' -v c="$ratio_col" '$1=="PAIR" {print $c}' "$RAW" | median_stream)"
  aggregate_ratio="$(awk -F'|' -v b="$base_col" -v c="$candidate_col" '$1=="PAIR" {bs += $b; cs += $c} END {print cs / bs}' "$RAW")"
  wins="$(awk -F'|' -v b="$base_col" -v c="$candidate_col" '$1=="PAIR" && $c < $b {n += 1} END {print n + 0}' "$RAW")"
  printf '%-14s %10.3f %10.3f %10.3f %10.3f %5s\n' \
    "$name" "$baseline_median" "$candidate_median" "$ratio_median" "$aggregate_ratio" "$wins/$PAIRS"
  printf '%s|%s\n' "$ratio_median" "$aggregate_ratio" > "$TMP/$name.summary"
}

echo
printf '%-14s %10s %10s %10s %10s %5s\n' metric baseline candidate paired aggregate wins
summarize_metric load_parse 2 3 4
summarize_metric total 5 6 7
summarize_metric wall 8 9 10
summarize_metric user 11 12 13

IFS='|' read -r load_paired load_aggregate < "$TMP/load_parse.summary"
IFS='|' read -r total_paired total_aggregate < "$TMP/total.summary"
IFS='|' read -r wall_paired wall_aggregate < "$TMP/wall.summary"
IFS='|' read -r user_paired user_aggregate < "$TMP/user.summary"
decision="$(awk \
  -v lp="$load_paired" -v la="$load_aggregate" \
  -v tp="$total_paired" -v ta="$total_aggregate" \
  -v wp="$wall_paired" -v wa="$wall_aggregate" \
  -v up="$user_paired" -v ua="$user_aggregate" \
  -v gate="$GATE" \
  'BEGIN {
    print (lp <= gate && la <= gate &&
           tp <= 1.0 && ta <= 1.0 &&
           wp <= 1.0 && wa <= 1.0 &&
           up <= 1.0 && ua <= 1.0) ? "PASS" : "SKIP"
  }')"

echo "Retention gate: $decision"
echo "Warmup and all measured LLVM pairs were byte-identical."
echo "PASS still requires an independent repeat with every aggregate ratio below 1.00."
if [ -n "$RESULTS_OUT" ]; then
  cp "$RAW" "$RESULTS_OUT"
  echo "Raw paired metrics saved to $RESULTS_OUT"
fi
