#!/usr/bin/env bash
# Isolated relaxed gate for moving BigArray#cap and #empty? out of the C IC
# table. By default this performs static audit only and refuses every build or
# timing action. Set ALLOW_HEAVY=1 after the benchmark lane is explicitly free.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-bigarray-cap-empty-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-/Users/erik/tungsten/bin/tungsten-compiler}"
ALLOW_HEAVY="${ALLOW_HEAVY:-0}"
CHECK_ONLY="${CHECK_ONLY:-0}"
RUNS="${RUNS:-10}"
CAMPAIGNS="${CAMPAIGNS:-2}"
GATE="${GATE:-1.10}"
INLINE_ITERS="${INLINE_ITERS:-30000000}"
INLINE_WARMUP="${INLINE_WARMUP:-300000}"
OVERFLOW_ITERS="${OVERFLOW_ITERS:-1500000}"
OVERFLOW_WARMUP="${OVERFLOW_WARMUP:-30000}"
EMPTY_ITERS="${EMPTY_ITERS:-30000000}"
EMPTY_WARMUP="${EMPTY_WARMUP:-300000}"

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"

case "$ALLOW_HEAVY" in 0|1) ;; *) echo "ALLOW_HEAVY must be 0 or 1" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
case "$CAMPAIGNS" in ''|*[!0-9]*) echo "CAMPAIGNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
if [ "$CAMPAIGNS" -lt 2 ]; then
  echo "CAMPAIGNS must be at least 2 (independent rebuild/repeat is mandatory)" >&2
  exit 2
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi
for value in "$INLINE_ITERS" "$INLINE_WARMUP" "$OVERFLOW_ITERS" \
             "$OVERFLOW_WARMUP" "$EMPTY_ITERS" "$EMPTY_WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;; esac
done

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -f "$root/core/big_array.w"
  test -f "$root/runtime/runtime.c"
  test -f "$root/compiler/lib/loader.w"
  test -f "$root/compiler/lib/interpreter.w"
done
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "baseline and candidate must start at the same commit" >&2
  exit 2
fi

DRIVER_SOURCE="$SCRIPT_DIR/big_array_cap_empty_revisit_public.w"
REF_SOURCE="$SCRIPT_DIR/big_array_cap_empty_revisit_ref.c"
INTERPRETER_SPEC="$CANDIDATE_ROOT/spec/interpreter/big_array_cap_empty_revisit_spec.w"
NO_USE_SPECS=(
  "$CANDIDATE_ROOT/spec/compiler/big_array_cap_empty_no_use_new_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/big_array_cap_empty_no_use_view_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/big_array_cap_empty_no_use_subview_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/big_array_cap_empty_no_use_range_spec.w"
)
test -f "$DRIVER_SOURCE"
test -f "$REF_SOURCE"
test -f "$INTERPRETER_SPEC"
for spec in "${NO_USE_SPECS[@]}"; do test -f "$spec"; done

echo "Static source/layout/IC/autoload audit..."
# Both roots include the already-retained size port. This keeps the benchmark
# delta strictly cap/empty and pins the boxing implementation cap must mirror.
grep -Fq -- '-> size' "$BASELINE_ROOT/core/big_array.w"
grep -Fq -- 'n = $size ## i64' "$BASELINE_ROOT/core/big_array.w"
grep -Fq -- 'call("w_int", n)' "$BASELINE_ROOT/core/big_array.w"
grep -Fq -- '-> cap' "$CANDIDATE_ROOT/core/big_array.w"
grep -Fq -- 'n = $cap ## i64' "$CANDIDATE_ROOT/core/big_array.w"
grep -Fq -- '-> empty?' "$CANDIDATE_ROOT/core/big_array.w"

# WBigArray's public view begins at C offset 1; the compiler's implicit type
# byte adjustment therefore lands source $size/$cap on C offsets 16/24.
grep -Fq 'offsetof(WBigArray, size)  == 16' "$CANDIDATE_ROOT/runtime/runtime.h"
grep -Fq 'offsetof(WBigArray, cap)   == 24' "$CANDIDATE_ROOT/runtime/runtime.h"

grep -Fq 'static WValue w_ic_big_array_cap' "$BASELINE_ROOT/runtime/runtime.c"
grep -Fq 'static WValue w_ic_big_array_empty' "$BASELINE_ROOT/runtime/runtime.c"
if grep -Eq 'static WValue w_ic_big_array_(size|cap|empty)' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate retains a migrated BigArray native IC handler" >&2
  exit 1
fi
if grep -Eq 'w_ic_big_array_table\[[0-9]+\]\.name[[:space:]]*=[[:space:]]*WN_(size|cap|empty_q)' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate BigArray IC table still names size/cap/empty?" >&2
  exit 1
fi
remaining_names=(idx idxset get set push subview)
remaining_index=0
for method in "${remaining_names[@]}"; do
  grep -Eq "w_ic_big_array_table\[$remaining_index\]\.name[[:space:]]*=[[:space:]]*WN_${method}" \
    "$CANDIDATE_ROOT/runtime/runtime.c"
  remaining_index=$((remaining_index + 1))
done

grep -Fq 'call_name in ("ccall" "ccall_rawargs")' "$CANDIDATE_ROOT/compiler/lib/loader.w"
grep -Fq '"w_big_array_new" "w_big_array_view" "w_big_array_subview" "w_big_array_view_range"' \
  "$CANDIDATE_ROOT/compiler/lib/loader.w"
grep -Fq 'when "w_int"' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"
grep -Fq 'when "w_big_array_view"' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"
grep -Fq 'native_name = ccall("w_class_name", recv)' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"
grep -Fq 'if (w_is_big_array(v)) return w_string("BigArray")' "$CANDIDATE_ROOT/runtime/runtime.c"
factory_names=(w_big_array_new w_big_array_view w_big_array_subview w_big_array_view_range)
factory_index=0
for factory in "${factory_names[@]}"; do
  spec="${NO_USE_SPECS[$factory_index]}"
  if grep -Eq '^[[:space:]]*use[[:space:]]' "$spec"; then
    echo "no-use factory spec unexpectedly contains a use directive: $spec" >&2
    exit 1
  fi
  grep -Fq "\"$factory\"" "$spec"
  factory_index=$((factory_index + 1))
done

if [ "$ALLOW_HEAVY" != 1 ]; then
  echo "Static audit: ok. ALLOW_HEAVY=0; no compiler, linker, executable, or timing command was run."
  exit 0
fi

test -x "$BOOTSTRAP_COMPILER"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigarray-cap-empty-revisit.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DRIVER="$TMP/public.w"
REF_C="$TMP/ref.c"
cp "$DRIVER_SOURCE" "$DRIVER"
cp "$REF_SOURCE" "$REF_C"

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

method_iters() {
  case "$1" in
    cap.overflow.*) echo "$OVERFLOW_ITERS $OVERFLOW_WARMUP" ;;
    cap.*) echo "$INLINE_ITERS $INLINE_WARMUP" ;;
    empty.*) echo "$EMPTY_ITERS $EMPTY_WARMUP" ;;
  esac
}

methods=(
  cap.inline.valid
  cap.inline.synthetic
  cap.overflow.positive
  cap.overflow.negative
  empty.zero
  empty.nonzero.positive
  empty.nonzero.negative
)

run_observation() {
  local campaign="$1" sample="$2" label="$3" bin="$4" method="$5" iters="$6" warmup="$7" raw="$8"
  "$bin" bench "$method" "$iters" "$warmup" |
    awk -F'|' -v campaign="$campaign" -v sample="$sample" -v label="$label" \
      '$1 == "RESULT" { print campaign "|" sample "|" label "|" $0 }' >> "$raw"
}

summarize_campaign() {
  local campaign="$1" raw="$2"
  local failed=0
  printf '\nCampaign %s\n' "$campaign"
  printf '%-26s %11s %11s %9s %9s %9s %8s\n' \
    method native_ns source_ns med_ratio pair_med pair_max gate
  for method in "${methods[@]}"; do
    base_med="$(awk -F'|' -v m="$method" '$3=="BASE" && $5==m {print $6}' "$raw" | median_stream)"
    cand_med="$(awk -F'|' -v m="$method" '$3=="CAND" && $5==m {print $6}' "$raw" | median_stream)"
    base_sum="$(awk -F'|' -v m="$method" '$3=="BASE" && $5==m {print $7}' "$raw" | sort -u)"
    cand_sum="$(awk -F'|' -v m="$method" '$3=="CAND" && $5==m {print $7}' "$raw" | sort -u)"
    if [ "$base_sum" != "$cand_sum" ]; then
      echo "checksum mismatch for campaign $campaign $method" >&2
      exit 1
    fi
    median_ratio="$(awk -v c="$cand_med" -v b="$base_med" 'BEGIN { print c / b }')"
    ratios="$(awk -F'|' -v m="$method" '
      $5==m && $3=="BASE" { b[$2]=$6 }
      $5==m && $3=="CAND" { c[$2]=$6 }
      END { for (i in b) if (i in c) print c[i] / b[i] }
    ' "$raw")"
    pair_med="$(printf '%s\n' "$ratios" | median_stream)"
    pair_max="$(printf '%s\n' "$ratios" | sort -n | tail -n 1)"
    decision="$(awk -v a="$median_ratio" -v b="$pair_med" -v limit="$GATE" \
      'BEGIN { metric=(a>b?a:b); print (metric <= limit ? "PASS" : "SKIP") }')"
    if [ "$decision" != PASS ]; then failed=1; fi
    printf '%-26s %11.3f %11.3f %9.3f %9.3f %9.3f %8s\n' \
      "$method" "$base_med" "$cand_med" "$median_ratio" "$pair_med" "$pair_max" "$decision"
  done
  if [ "$failed" -ne 0 ]; then
    : > "$TMP/campaign-$campaign/GATE_FAILED"
  fi
  return 0
}

run_campaign() {
  local campaign="$1"
  local dir="$TMP/campaign-$campaign"
  local compiler="$dir/tungsten-compiler"
  local base_wire="$dir/baseline.wire"
  local cand_wire="$dir/candidate.wire"
  local base_bin="$dir/baseline"
  local cand_bin="$dir/candidate"
  local raw="$dir/results.txt"
  mkdir -p "$dir"

  echo "Campaign $campaign: building a fresh matched compiler (setup; excluded from timings)..."
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/compiler-cache" \
      "$BOOTSTRAP_COMPILER" compile compiler/tungsten.w --release --out "$compiler" >/dev/null
  )
  chmod +x "$compiler"
  echo "Campaign $campaign compiler SHA-256: $(shasum -a 256 "$compiler" | awk '{print $1}')"

  echo "Campaign $campaign: inspecting WIRE (setup; excluded from timings)..."
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-wire-cache" \
      "$compiler" compile "$DRIVER" --emit-wire > "$base_wire"
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-wire-cache" \
      "$compiler" compile "$DRIVER" --emit-wire > "$cand_wire"
  )

  require_wire "$cand_wire" __w_BigArray_cap__a1 'view_load_field'
  require_wire "$cand_wire" __w_BigArray_cap__a1 'icmp_i64'
  require_wire "$cand_wire" __w_BigArray_cap__a1 'and_i64'
  require_wire "$cand_wire" __w_BigArray_cap__a1 'or_i64'
  require_wire "$cand_wire" __w_BigArray_cap__a1 'call_direct_i64 .*@w_int'
  reject_wire "$cand_wire" __w_BigArray_cap__a1 'call_method_i64|w_big_array_(size|cap)'
  require_wire "$cand_wire" __w_BigArray_empty_Q__a1 'view_load_field'
  require_wire "$cand_wire" __w_BigArray_empty_Q__a1 'icmp_i64'
  reject_wire "$cand_wire" __w_BigArray_empty_Q__a1 'call_method_i64|call_direct_i64 .*@w_(eq|int)|w_big_array_(size|empty)'
  # Baseline still emits a generated data-field accessor named cap and the
  # inherited Enumerable#empty? body, but its native ICs shadow both at public
  # dispatch. Distinguish those expected bodies from the candidate's explicit
  # raw-field implementations instead of incorrectly requiring absence.
  require_wire "$base_wire" __w_BigArray_cap__a1 'ivar_get'
  reject_wire "$base_wire" __w_BigArray_cap__a1 'view_load_field|call_direct_i64 .*@w_int'
  require_wire "$base_wire" __w_BigArray_empty_Q__a1 'call_method_i64'
  reject_wire "$base_wire" __w_BigArray_empty_Q__a1 'view_load_field'
  for fn in __w_time_cap_inline __w_time_cap_overflow __w_time_empty; do
    require_wire "$cand_wire" "$fn" 'call_method_i64'
  done

  echo "Campaign $campaign: compiling fresh release/LTO binaries from each runtime source..."
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-build-cache" \
    TUNGSTEN_C_INCLUDES="$REF_C" \
      "$compiler" compile "$DRIVER" --release --out "$base_bin" >/dev/null
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-build-cache" \
    TUNGSTEN_C_INCLUDES="$REF_C" \
      "$compiler" compile "$DRIVER" --release --out "$cand_bin" >/dev/null
  )

  "$base_bin" check > "$dir/base-check.out"
  "$cand_bin" check > "$dir/cand-check.out"
  diff -u "$dir/base-check.out" "$dir/cand-check.out"
  cat "$dir/cand-check.out"

  for label in base cand; do
    bin="$base_bin"
    if [ "$label" = cand ]; then bin="$cand_bin"; fi
    set +e
    "$bin" empty-block-fatal > "$dir/$label-fatal.out" 2> "$dir/$label-fatal.err"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] || ! grep -Fq "undefined method 'each' for Boolean" "$dir/$label-fatal.err"; then
      echo "$label empty?-with-block fatal surface changed" >&2
      exit 1
    fi
  done

  if [ "$campaign" -eq 1 ]; then
    echo "Checking each exact no-use factory autoload independently..."
    no_use_index=0
    for spec in "${NO_USE_SPECS[@]}"; do
      no_use_index=$((no_use_index + 1))
      no_use_wire="$dir/no-use-$no_use_index.wire"
      no_use_bin="$dir/no-use-$no_use_index"
      (
        cd "$CANDIDATE_ROOT"
        TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/no-use-wire-$no_use_index-cache" \
          "$compiler" compile "$spec" --emit-wire > "$no_use_wire"
        TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/no-use-build-$no_use_index-cache" \
        TUNGSTEN_C_INCLUDES="$REF_C" \
          "$compiler" compile "$spec" --release --out "$no_use_bin" >/dev/null
      )
      require_wire "$no_use_wire" __w_BigArray_cap__a1 'view_load_field'
      require_wire "$no_use_wire" __w_BigArray_empty_Q__a1 'view_load_field'
      "$no_use_bin"
    done

    echo "Checking candidate tree-walker source behavior..."
    (
      cd "$CANDIDATE_ROOT"
      TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$compiler" run "$INTERPRETER_SPEC"
    )
  fi

  if [ "$CHECK_ONLY" = 1 ]; then
    return 0
  fi

  : > "$raw"
  sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    for method in "${methods[@]}"; do
      read -r iters warmup <<< "$(method_iters "$method")"
      echo "  campaign $campaign $method sample $((sample + 1))/$RUNS x $iters" >&2
      if [ $((sample % 2)) -eq 0 ]; then
        run_observation "$campaign" "$sample" BASE "$base_bin" "$method" "$iters" "$warmup" "$raw"
        run_observation "$campaign" "$sample" CAND "$cand_bin" "$method" "$iters" "$warmup" "$raw"
      else
        run_observation "$campaign" "$sample" CAND "$cand_bin" "$method" "$iters" "$warmup" "$raw"
        run_observation "$campaign" "$sample" BASE "$base_bin" "$method" "$iters" "$warmup" "$raw"
      fi
    done
    sample=$((sample + 1))
  done
  summarize_campaign "$campaign" "$raw"
}

if [ "$CHECK_ONLY" = 1 ]; then
  run_campaign 1
  echo "CHECK_ONLY=1: fresh matched compiler, source/IC/WIRE, release/LTO, exact representation, extras, blocks, views, all four no-use factory hooks, and interpreter checks passed; CPU timings skipped."
  exit 0
fi

failed=0
campaign=1
while [ "$campaign" -le "$CAMPAIGNS" ]; do
  run_campaign "$campaign"
  if [ -f "$TMP/campaign-$campaign/GATE_FAILED" ]; then failed=1; fi
  campaign=$((campaign + 1))
done

echo "Thread CPU clock; $RUNS alternating adjacent pairs per campaign. Each campaign rebuilt its matched compiler and both release/LTO binaries from fresh caches."
echo "Retention requires ratio-of-medians and paired-ratio median <= $GATE in every stratum of every independent campaign. Pair maxima are diagnostic only."
if [ "$failed" -ne 0 ]; then
  echo "Gate failed: retain the regressing native IC(s), evaluated per method/stratum." >&2
  exit 3
fi
