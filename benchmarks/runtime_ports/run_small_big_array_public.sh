#!/usr/bin/env bash
# Matched cross-root public-dispatch gate for SmallArray size/cap/empty? and
# BigArray size. CHECK_ONLY=1 performs every build/correctness/WIRE/autoload
# check without entering a thread-CPU timing loop.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-/Users/erik/tungsten/bin/tungsten-compiler}"
MATCHED_COMPILER="${MATCHED_COMPILER:-}"
CHECK_ONLY="${CHECK_ONLY:-0}"
INTERPRETER_CHECK="${INTERPRETER_CHECK:-1}"
RUNS="${RUNS:-10}"
GATE="${GATE:-1.10}"
SMALL_ITERS="${SMALL_ITERS:-50000000}"
BIG_INLINE_ITERS="${BIG_INLINE_ITERS:-50000000}"
BIG_OVERFLOW_ITERS="${BIG_OVERFLOW_ITERS:-2000000}"
SMALL_WARMUP="${SMALL_WARMUP:-500000}"
BIG_INLINE_WARMUP="${BIG_INLINE_WARMUP:-500000}"
BIG_OVERFLOW_WARMUP="${BIG_OVERFLOW_WARMUP:-50000}"

if [ -z "$BASELINE_ROOT" ]; then
  echo "BASELINE_ROOT must name an isolated pre-port Tungsten root" >&2
  exit 2
fi
BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"

case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$INTERPRETER_CHECK" in 0|1) ;; *) echo "INTERPRETER_CHECK must be 0 or 1" >&2; exit 2 ;; esac
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$SMALL_ITERS" "$BIG_INLINE_ITERS" "$BIG_OVERFLOW_ITERS" \
             "$SMALL_WARMUP" "$BIG_INLINE_WARMUP" "$BIG_OVERFLOW_WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;; esac
done
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -f "$root/core/small_array.w"
  test -f "$root/core/big_array.w"
  test -f "$root/runtime/runtime.c"
done
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "baseline and candidate must start at the same commit" >&2
  exit 2
fi
test -x "$BOOTSTRAP_COMPILER"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-small-big-array-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DRIVER="$TMP/public-hot.w"
NO_USE_DRIVER="$TMP/no-use-autoload.w"
INTERPRETER_DRIVER="$TMP/interpreter.w"
REF_C="$TMP/public-ref.c"
BASE_WIRE="$TMP/baseline.wire"
CAND_WIRE="$TMP/candidate.wire"
NO_USE_WIRE="$TMP/no-use.wire"
BASE_BIN="$TMP/baseline"
CAND_BIN="$TMP/candidate"
NO_USE_BIN="$TMP/no-use"
RAW="$TMP/results.txt"

cp "$SCRIPT_DIR/small_big_array_public_hot.w" "$DRIVER"
cp "$SCRIPT_DIR/small_big_array_no_use_autoload.w" "$NO_USE_DRIVER"
cp "$SCRIPT_DIR/small_big_array_interpreter.w" "$INTERPRETER_DRIVER"
cp "$SCRIPT_DIR/small_big_array_public_ref.c" "$REF_C"

echo "Checking production-shaped source/IC edits..."
grep -Fq 'static WValue w_ic_small_array_size' "$BASELINE_ROOT/runtime/runtime.c"
grep -Fq 'static WValue w_ic_small_array_empty' "$BASELINE_ROOT/runtime/runtime.c"
grep -Fq 'static WValue w_ic_big_array_size' "$BASELINE_ROOT/runtime/runtime.c"
if grep -Eq 'w_ic_small_array_(size|empty)|w_ic_big_array_size' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate still contains a migrated native IC handler" >&2
  exit 1
fi
if grep -Eq 'w_ic_small_array_table\[[0-9]+\]\.name[[:space:]]*=[[:space:]]*WN_(size|cap|empty_q)' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate SmallArray IC table still names a migrated public leaf" >&2
  exit 1
fi
if grep -Eq 'w_ic_big_array_table\[[0-9]+\]\.name[[:space:]]*=[[:space:]]*WN_size' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate BigArray IC table still names size" >&2
  exit 1
fi
grep -Fq -- '-> size' "$CANDIDATE_ROOT/core/small_array.w"
grep -Fq -- '-> cap' "$CANDIDATE_ROOT/core/small_array.w"
grep -Fq -- '-> empty?' "$CANDIDATE_ROOT/core/small_array.w"
grep -Fq -- '-> size' "$CANDIDATE_ROOT/core/big_array.w"

# Build one compiler containing the candidate loader/autoload and interpreter
# support, then use that exact executable for both public release binaries.
if [ -n "$MATCHED_COMPILER" ]; then
  test -x "$MATCHED_COMPILER"
  cp "$MATCHED_COMPILER" "$TMP/tungsten-compiler"
else
  echo "Building one matched compiler (setup; excluded from timings)..."
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" \
    TUNGSTEN_CACHE_DIR="$TMP/compiler-cache" \
      "$BOOTSTRAP_COMPILER" compile compiler/tungsten.w --release \
      --out "$TMP/tungsten-compiler" >/dev/null
  )
fi
chmod +x "$TMP/tungsten-compiler"
COMPILER_SHA="$(shasum -a 256 "$TMP/tungsten-compiler" | awk '{print $1}')"
echo "Matched compiler SHA-256: $COMPILER_SHA"

echo "Inspecting candidate WIRE (setup; excluded from timings)..."
(
  cd "$BASELINE_ROOT"
  TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/base-wire-cache" \
    "$TMP/tungsten-compiler" compile "$DRIVER" --emit-wire > "$BASE_WIRE"
)
(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cand-wire-cache" \
    "$TMP/tungsten-compiler" compile "$DRIVER" --emit-wire > "$CAND_WIRE"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/no-use-wire-cache" \
    "$TMP/tungsten-compiler" compile "$NO_USE_DRIVER" --emit-wire > "$NO_USE_WIRE"
)

wire_body() {
  local wire="$1" fn="$2"
  sed -n "/^function $fn(/,/^$/p" "$wire"
}
require_wire() {
  local wire="$1" fn="$2" pattern="$3"
  if ! wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}
reject_wire() {
  local wire="$1" fn="$2" pattern="$3"
  if wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn unexpectedly contains /$pattern/" >&2
    exit 1
  fi
}

for fn in __w_SmallArray_size__a1 __w_SmallArray_cap__a1; do
  require_wire "$CAND_WIRE" "$fn" 'view_load_field'
  require_wire "$CAND_WIRE" "$fn" 'or_i64'
  reject_wire "$CAND_WIRE" "$fn" 'w_int|nanbox_int|call_method_i64|w_small_array_size'
done
require_wire "$CAND_WIRE" __w_SmallArray_empty_Q__a1 'view_load_field'
require_wire "$CAND_WIRE" __w_SmallArray_empty_Q__a1 'icmp_i64'
reject_wire "$CAND_WIRE" __w_SmallArray_empty_Q__a1 'w_eq|nanbox_int|call_method_i64|w_small_array_(size|empty)'

require_wire "$CAND_WIRE" __w_BigArray_size__a1 'view_load_field'
require_wire "$CAND_WIRE" __w_BigArray_size__a1 'icmp_i64'
require_wire "$CAND_WIRE" __w_BigArray_size__a1 'and_i64'
require_wire "$CAND_WIRE" __w_BigArray_size__a1 'or_i64'
require_wire "$CAND_WIRE" __w_BigArray_size__a1 'call_direct_i64 .*@w_int'
reject_wire "$CAND_WIRE" __w_BigArray_size__a1 'call_method_i64|w_big_array_size'

for fn in __w_time_small_size __w_time_small_cap __w_time_small_empty \
          __w_time_big_inline __w_time_big_overflow; do
  require_wire "$CAND_WIRE" "$fn" 'call_method_i64'
  reject_wire "$CAND_WIRE" "$fn" 'w_small_array_(size|empty)|w_big_array_size'
done

# The no-use file is copied outside the root and contains no `use`; seeing all
# four bodies proves the exact native-factory loader hooks scheduled both core
# classes. Its execution below proves dynamic dispatch has no C fallback.
for fn in __w_SmallArray_size__a1 __w_SmallArray_cap__a1 \
          __w_SmallArray_empty_Q__a1 __w_BigArray_size__a1; do
  require_wire "$NO_USE_WIRE" "$fn" 'view_load_field'
done
echo "WIRE: ok (raw field/tag paths, canonical BigInt fallback, dynamic public calls, and no-use factory autoload)"

echo "Compiling isolated release/LTO binaries from each runtime source (setup; excluded from timings)..."
# Do not use --no-lto here. The dev-runtime archive cache is intentionally
# global and keyed too coarsely for two dirty roots; release/LTO compiles each
# root's runtime.c directly and prevents native-IC cross-contamination.
(
  cd "$BASELINE_ROOT"
  TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/base-build-cache" \
  TUNGSTEN_C_INCLUDES="$REF_C" \
    "$TMP/tungsten-compiler" compile "$DRIVER" --release --out "$BASE_BIN" >/dev/null
)
(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cand-build-cache" \
  TUNGSTEN_C_INCLUDES="$REF_C" \
    "$TMP/tungsten-compiler" compile "$DRIVER" --release --out "$CAND_BIN" >/dev/null
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/no-use-build-cache" \
    "$TMP/tungsten-compiler" compile "$NO_USE_DRIVER" --release --out "$NO_USE_BIN" >/dev/null
)

echo "Checking exact public behavior and representation..."
"$BASE_BIN" check > "$TMP/base-check.out"
"$CAND_BIN" check > "$TMP/cand-check.out"
diff -u "$TMP/base-check.out" "$TMP/cand-check.out"
cat "$TMP/cand-check.out"

for label in base cand; do
  bin="$BASE_BIN"
  if [ "$label" = cand ]; then bin="$CAND_BIN"; fi
  set +e
  "$bin" empty-block-fatal > "$TMP/$label-fatal.out" 2> "$TMP/$label-fatal.err"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] || ! grep -Fq "undefined method 'each' for Boolean" "$TMP/$label-fatal.err"; then
    echo "$label empty?-with-block fatal surface changed" >&2
    exit 1
  fi
done
"$NO_USE_BIN" > "$TMP/no-use.out"
grep -Fq 'autoload: ok' "$TMP/no-use.out"
cat "$TMP/no-use.out"

if [ "$INTERPRETER_CHECK" = 1 ]; then
  echo "Checking candidate tree-walker source behavior..."
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" \
      "$TMP/tungsten-compiler" run "$INTERPRETER_DRIVER"
  )
fi

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: matched compiler, static IC removal, WIRE, release/LTO, exact representation/overflow, extras, blocks, views, no-use autoload, and interpreter checks passed; CPU timings skipped."
  exit 0
fi

method_iters() {
  case "$1" in
    small.*) echo "$SMALL_ITERS $SMALL_WARMUP" ;;
    big.size.inline) echo "$BIG_INLINE_ITERS $BIG_INLINE_WARMUP" ;;
    big.size.overflow) echo "$BIG_OVERFLOW_ITERS $BIG_OVERFLOW_WARMUP" ;;
  esac
}

run_observation() {
  local label="$1" bin="$2" method="$3" iters="$4" warmup="$5"
  "$bin" bench "$method" "$iters" "$warmup" |
    awk -F'|' -v label="$label" '$1 == "RESULT" {print label "|" $0}' >> "$RAW"
}

methods=(small.size small.cap small.empty big.size.inline big.size.overflow)
: > "$RAW"
sample=0
while [ "$sample" -lt "$RUNS" ]; do
  for method in "${methods[@]}"; do
    read -r iters warmup <<< "$(method_iters "$method")"
    echo "  $method sample $((sample + 1))/$RUNS x $iters" >&2
    if [ $((sample % 2)) -eq 0 ]; then
      run_observation BASE "$BASE_BIN" "$method" "$iters" "$warmup"
      run_observation CAND "$CAND_BIN" "$method" "$iters" "$warmup"
    else
      run_observation CAND "$CAND_BIN" "$method" "$iters" "$warmup"
      run_observation BASE "$BASE_BIN" "$method" "$iters" "$warmup"
    fi
  done
  sample=$((sample + 1))
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

printf '\n%-20s %12s %12s %10s %8s\n' method native_ns source_ns source/native gate
failed=0
for method in "${methods[@]}"; do
  base_med="$(awk -F'|' -v m="$method" '$1=="BASE" && $3==m {print $4}' "$RAW" | median_stream)"
  cand_med="$(awk -F'|' -v m="$method" '$1=="CAND" && $3==m {print $4}' "$RAW" | median_stream)"
  base_sum="$(awk -F'|' -v m="$method" '$1=="BASE" && $3==m {print $5}' "$RAW" | sort -u)"
  cand_sum="$(awk -F'|' -v m="$method" '$1=="CAND" && $3==m {print $5}' "$RAW" | sort -u)"
  if [ "$base_sum" != "$cand_sum" ]; then
    echo "checksum mismatch for $method" >&2
    exit 1
  fi
  ratio="$(awk -v c="$cand_med" -v b="$base_med" 'BEGIN { print c / b }')"
  decision="$(awk -v ratio="$ratio" -v limit="$GATE" 'BEGIN { print (ratio <= limit ? "PASS" : "SKIP") }')"
  if [ "$decision" != PASS ]; then failed=1; fi
  printf '%-20s %12.3f %12.3f %10.3f %8s\n' "$method" "$base_med" "$cand_med" "$ratio" "$decision"
done

echo "Thread CPU clock; $RUNS alternating cross-build observations. Retention requires every public source/native median <= $GATE and an independent repeat."
if [ "$failed" -ne 0 ]; then
  echo "Gate failed: keep the regressing native IC(s)." >&2
  exit 3
fi
