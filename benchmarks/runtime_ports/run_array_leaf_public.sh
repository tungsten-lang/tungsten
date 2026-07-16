#!/usr/bin/env bash
# Matched cross-root public-dispatch gate for Array size/cap/empty?/first/last.
# CHECK_ONLY=1 performs static, WIRE, release/LTO, exact behavior, isolated
# autoload, and interpreter checks without entering a thread-CPU timing loop.

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
ONLY="${ONLY:-}"
HEADER_ITERS="${HEADER_ITERS:-50000000}"
ELEMENT_ITERS="${ELEMENT_ITERS:-50000000}"
EMPTY_ELEMENT_ITERS="${EMPTY_ELEMENT_ITERS:-50000000}"
HEADER_WARMUP="${HEADER_WARMUP:-500000}"
ELEMENT_WARMUP="${ELEMENT_WARMUP:-500000}"
EMPTY_ELEMENT_WARMUP="${EMPTY_ELEMENT_WARMUP:-500000}"

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
for value in "$HEADER_ITERS" "$ELEMENT_ITERS" "$EMPTY_ELEMENT_ITERS" \
             "$HEADER_WARMUP" "$ELEMENT_WARMUP" "$EMPTY_ELEMENT_WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;; esac
done
if ! awk -v limit="$GATE" 'BEGIN { exit !(limit ~ /^[0-9]+([.][0-9]+)?$/ && limit > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -f "$root/core/array.w"
  test -f "$root/runtime/runtime.c"
done
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "baseline and candidate must start at the same commit" >&2
  exit 2
fi
test -x "$BOOTSTRAP_COMPILER"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-array-leaf-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DRIVER="$TMP/public-hot.w"
INTERPRETER_DRIVER="$TMP/interpreter.w"
REF_C="$TMP/public-ref.c"
BASE_WIRE="$TMP/baseline.wire"
CAND_WIRE="$TMP/candidate.wire"
BASE_BIN="$TMP/baseline"
CAND_BIN="$TMP/candidate"
RAW="$TMP/results.txt"

cp "$SCRIPT_DIR/array_leaf_public_hot.w" "$DRIVER"
cp "$SCRIPT_DIR/array_leaf_interpreter.w" "$INTERPRETER_DRIVER"
cp "$SCRIPT_DIR/array_leaf_public_ref.c" "$REF_C"

AUTO_NAMES=(literal typed factories argv_call argv_constant)
for name in "${AUTO_NAMES[@]}"; do
  cp "$SCRIPT_DIR/array_leaf_no_use_${name}.w" "$TMP/no-use-${name}.w"
done

echo "Checking production-shaped source/IC edits..."
for handler in length cap empty first last; do
  grep -Fq "static WValue w_ic_array_${handler}" "$BASELINE_ROOT/runtime/runtime.c"
done
if grep -Eq 'static WValue w_ic_array_(length|cap|empty|first|last)[[:space:]]*\(' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate still contains a migrated Array native IC handler" >&2
  exit 1
fi
ARRAY_INIT="$(sed -n '/^[[:space:]]*\/\* Array \*\//,/^[[:space:]]*\/\* String \*\//p' "$CANDIDATE_ROOT/runtime/runtime.c")"
if printf '%s\n' "$ARRAY_INIT" | grep -Eq 'WN_(size|cap|empty_q|first|last)[[:space:]]*;'; then
  echo "candidate Array IC table still names a migrated public leaf" >&2
  exit 1
fi
for method in size cap 'empty?' first last; do
  grep -Fq -- "-> $method" "$CANDIDATE_ROOT/core/array.w"
done

# Build one compiler containing the candidate loader/interpreter changes and
# use that exact executable for both roots. This setup is outside CPU timings.
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
  for name in "${AUTO_NAMES[@]}"; do
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/no-use-${name}-wire-cache" \
      "$TMP/tungsten-compiler" compile "$TMP/no-use-${name}.w" --emit-wire \
      > "$TMP/no-use-${name}.wire"
  done
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

for fn in __w_Array_size__a1 __w_Array_cap__a1; do
  require_wire "$CAND_WIRE" "$fn" 'view_load_field'
  require_wire "$CAND_WIRE" "$fn" 'or_i64'
  reject_wire "$CAND_WIRE" "$fn" 'w_int|nanbox_int|call_method_i64|w_array_(size|cap)'
done
require_wire "$CAND_WIRE" __w_Array_empty_Q__a1 'view_load_field'
require_wire "$CAND_WIRE" __w_Array_empty_Q__a1 'icmp_i64'
reject_wire "$CAND_WIRE" __w_Array_empty_Q__a1 'w_eq|nanbox_int|call_method_i64|w_array_size'

for fn in __w_Array_first__a1 __w_Array_last__a1; do
  require_wire "$CAND_WIRE" "$fn" 'view_load_field'
  require_wire "$CAND_WIRE" "$fn" 'icmp_i64'
  require_wire "$CAND_WIRE" "$fn" 'call_direct_i64 .*@w_array_idx'
  reject_wire "$CAND_WIRE" "$fn" 'call_method_i64|w_array_size'
done

for fn in __w_time_size __w_time_cap __w_time_empty __w_time_first __w_time_last; do
  require_wire "$CAND_WIRE" "$fn" 'call_method_i64'
done

# Each no-use unit is isolated: seeing all five bodies proves that its one
# trigger (literal, typed constructor, factory map, argv(), or ARGV) scheduled
# Array.
for name in "${AUTO_NAMES[@]}"; do
  for fn in __w_Array_size__a1 __w_Array_cap__a1 __w_Array_empty_Q__a1 \
            __w_Array_first__a1 __w_Array_last__a1; do
    require_wire "$TMP/no-use-${name}.wire" "$fn" 'view_load_field'
  done
done
echo "WIRE: ok (raw header/tag paths, ebits-aware indexed loads, dynamic public calls, and five isolated no-use triggers)"

echo "Compiling isolated release/LTO binaries from each runtime source (setup; excluded from timings)..."
# Release/LTO compiles runtime.c directly. Avoid --no-lto: the global dev
# runtime archive cache is too coarse for two dirty roots and can contaminate
# a cross-root native/source comparison.
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
  for name in "${AUTO_NAMES[@]}"; do
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/no-use-${name}-build-cache" \
      "$TMP/tungsten-compiler" compile "$TMP/no-use-${name}.w" --release \
      --out "$TMP/no-use-${name}" >/dev/null
  done
)

echo "Checking exact public behavior and representation..."
"$BASE_BIN" check > "$TMP/base-check.out"
"$CAND_BIN" check > "$TMP/cand-check.out"
diff -u "$TMP/base-check.out" "$TMP/cand-check.out"
cat "$TMP/cand-check.out"

for mode in empty-block-fatal first-block-fatal last-block-fatal; do
  for label in base cand; do
    bin="$BASE_BIN"
    if [ "$label" = cand ]; then bin="$CAND_BIN"; fi
    set +e
    "$bin" "$mode" > "$TMP/$label-$mode.out" 2> "$TMP/$label-$mode.err"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] || ! grep -Fq "undefined method 'each'" "$TMP/$label-$mode.err"; then
      echo "$label $mode fatal surface changed" >&2
      exit 1
    fi
  done
  base_error="$(grep -m1 "undefined method 'each'" "$TMP/base-$mode.err")"
  cand_error="$(grep -m1 "undefined method 'each'" "$TMP/cand-$mode.err")"
  if [ "$base_error" != "$cand_error" ]; then
    echo "$mode fatal message differs across roots" >&2
    exit 1
  fi
done

for name in literal typed factories argv_call argv_constant; do
  case "$name" in
    argv_*) "$TMP/no-use-${name}" alpha beta gamma > "$TMP/no-use-${name}.out" ;;
    *) "$TMP/no-use-${name}" > "$TMP/no-use-${name}.out" ;;
  esac
  grep -Fq "autoload.${name}: ok" "$TMP/no-use-${name}.out"
  cat "$TMP/no-use-${name}.out"
done

if [ "$INTERPRETER_CHECK" = 1 ]; then
  echo "Checking candidate tree-walker source behavior..."
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" \
      "$TMP/tungsten-compiler" run "$INTERPRETER_DRIVER"
  )
fi

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: matched compiler, static IC removal, WIRE, release/LTO, exact representation/decoding, extras, block surfaces, shifted/views, five isolated no-use triggers, and interpreter checks passed; CPU timings skipped."
  exit 0
fi

method_iters() {
  case "$1" in
    size.*|cap.*|empty.*) echo "$HEADER_ITERS $HEADER_WARMUP" ;;
    first.empty|last.empty) echo "$EMPTY_ELEMENT_ITERS $EMPTY_ELEMENT_WARMUP" ;;
    *) echo "$ELEMENT_ITERS $ELEMENT_WARMUP" ;;
  esac
}

run_observation() {
  local sample="$1" label="$2" bin="$3" method="$4" iters="$5" warmup="$6"
  "$bin" bench "$method" "$iters" "$warmup" |
    awk -F'|' -v sample="$sample" -v label="$label" \
      '$1 == "RESULT" {print sample "|" label "|" $0}' >> "$RAW"
}

all_methods=(size.mixed cap.mixed empty.empty empty.nonempty \
             first.w64 first.typed first.shifted_view first.empty \
             last.w64 last.typed last.shifted_view last.empty)
methods=("${all_methods[@]}")
if [ -n "$ONLY" ]; then
  found=0
  for method in "${all_methods[@]}"; do
    if [ "$method" = "$ONLY" ]; then found=1; fi
  done
  if [ "$found" -ne 1 ]; then
    echo "ONLY must name one complete timing stratum" >&2
    exit 2
  fi
  methods=("$ONLY")
fi
: > "$RAW"
sample=0
while [ "$sample" -lt "$RUNS" ]; do
  for method in "${methods[@]}"; do
    read -r iters warmup <<< "$(method_iters "$method")"
    echo "  $method sample $((sample + 1))/$RUNS x $iters" >&2
    if [ $((sample % 2)) -eq 0 ]; then
      run_observation "$sample" BASE "$BASE_BIN" "$method" "$iters" "$warmup"
      run_observation "$sample" CAND "$CAND_BIN" "$method" "$iters" "$warmup"
    else
      run_observation "$sample" CAND "$CAND_BIN" "$method" "$iters" "$warmup"
      run_observation "$sample" BASE "$BASE_BIN" "$method" "$iters" "$warmup"
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

max_stream() {
  sort -n | awk 'END { if (NR == 0) exit 1; print $1 }'
}

printf '\n%-22s %11s %11s %9s %9s %8s\n' stratum native_ns source_ns pair_med max_pair gate
failed=0
for method in "${methods[@]}"; do
  base_med="$(awk -F'|' -v m="$method" '$2=="BASE" && $4==m {print $5 / $6}' "$RAW" | median_stream)"
  cand_med="$(awk -F'|' -v m="$method" '$2=="CAND" && $4==m {print $5 / $6}' "$RAW" | median_stream)"
  base_sum="$(awk -F'|' -v m="$method" '$2=="BASE" && $4==m {print $7}' "$RAW" | sort -u)"
  cand_sum="$(awk -F'|' -v m="$method" '$2=="CAND" && $4==m {print $7}' "$RAW" | sort -u)"
  if [ "$base_sum" != "$cand_sum" ]; then
    echo "checksum mismatch for $method" >&2
    exit 1
  fi
  pair_ratios="$(awk -F'|' -v m="$method" '
    $4 == m && $2 == "BASE" { base[$1] = $5 }
    $4 == m && $2 == "CAND" { cand[$1] = $5 }
    END { for (i in base) if (i in cand) print cand[i] / base[i] }
  ' "$RAW")"
  ratio="$(printf '%s\n' "$pair_ratios" | median_stream)"
  max_pair="$(printf '%s\n' "$pair_ratios" | max_stream)"
  decision="$(awk -v ratio="$ratio" -v limit="$GATE" 'BEGIN { print (ratio <= limit ? "PASS" : "SKIP") }')"
  if [ "$decision" != PASS ]; then failed=1; fi
  printf '%-22s %11.3f %11.3f %9.3f %9.3f %8s\n' \
    "$method" "$base_med" "$cand_med" "$ratio" "$max_pair" "$decision"
done

echo "Thread CPU clock; $RUNS alternating cross-build observations. Retention requires every paired public source/native median <= $GATE and an independent repeat; max_pair is diagnostic only."
if [ "$failed" -ne 0 ]; then
  echo "Gate failed: keep the native IC for every method with a regressing stratum." >&2
  exit 3
fi
