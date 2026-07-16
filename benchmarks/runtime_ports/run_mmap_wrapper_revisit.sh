#!/usr/bin/env bash
# Matched public-dispatch gate for the ten zero-argument Mmap#as_* wrappers.
# Static-only by default. Heavy compiler/IR/executable/timing work requires an
# explicit ALLOW_HEAVY=1 after the shared exclusive benchmark lane is released.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-mmap-wrapper-revisit-baseline}"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-/tmp/tungsten-mmap-wrapper-revisit-candidate}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-/Users/erik/tungsten/bin/tungsten-compiler}"
ALLOW_HEAVY="${ALLOW_HEAVY:-0}"
CHECK_ONLY="${CHECK_ONLY:-0}"
KEEP_TMP="${KEEP_TMP:-0}"
RUNS="${RUNS:-10}"
CAMPAIGNS="${CAMPAIGNS:-2}"
GATE="${GATE:-1.10}"
VIEW_ITERS="${VIEW_ITERS:-10000000}"
VIEW_WARMUP="${VIEW_WARMUP:-200000}"

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
DRIVER="$CANDIDATE_ROOT/benchmarks/runtime_ports/mmap_wrapper_revisit_public.w"
REF_C="$CANDIDATE_ROOT/benchmarks/runtime_ports/mmap_wrapper_revisit_ref.c"
TYPED_TEMPLATE="$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_typed_template.w.in"
INTERPRETER_SPEC="$CANDIDATE_ROOT/spec/interpreter/mmap_wrapper_revisit_spec.w"

case "$ALLOW_HEAVY" in 0|1) ;; *) echo "ALLOW_HEAVY must be 0 or 1" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$KEEP_TMP" in 0|1) ;; *) echo "KEEP_TMP must be 0 or 1" >&2; exit 2 ;; esac
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
case "$CAMPAIGNS" in ''|*[!0-9]*) echo "CAMPAIGNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
if [ "$CAMPAIGNS" -lt 2 ] && [ "$CHECK_ONLY" != 1 ]; then
  echo "at least two independently rebuilt campaigns are mandatory" >&2
  exit 2
fi
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi
for value in "$VIEW_ITERS" "$VIEW_WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;; esac
done

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -f "$root/core/mmap.w"
  test -f "$root/runtime/runtime.c"
  test -f "$root/runtime/runtime.h"
  test -f "$root/compiler/lib/loader.w"
  test -f "$root/compiler/lib/interpreter.w"
  test -f "$root/compiler/lib/emitter.w"
done
test -f "$DRIVER"
test -f "$REF_C"
test -f "$TYPED_TEMPLATE"
test -f "$INTERPRETER_SPEC"
grep -Fq 'int64_t w_mwr_consume_release_view(WValue value)' "$REF_C"
grep -Fq 'ccall_nobox("w_mwr_consume_release_view", mapping.as_' "$DRIVER"

baseline_head="$(git -C "$BASELINE_ROOT" rev-parse HEAD)"
candidate_head="$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)"
if [ "$baseline_head" != "$candidate_head" ]; then
  echo "baseline and candidate roots do not share a starting commit" >&2
  exit 1
fi

echo "Static Mmap wrapper source/ABI/IC/autoload audit..."

body_of() {
  local file="$1" method="$2"
  awk -v header="  -> $method" '
    $0 == header { inside=1; next }
    inside && /^  -> / { exit }
    inside { print }
  ' "$file"
}

typed_methods=(as_u8 as_u16 as_u32 as_u64 as_i8 as_i16 as_i32 as_i64 as_f32 as_f64)
typed_constants=(8 16 32 64 108 116 32 64 -32 -64)
typed_sizes=(64 32 16 8 64 32 16 8 16 8)
for i in "${!typed_methods[@]}"; do
  method="${typed_methods[$i]}"
  constant="${typed_constants[$i]}"
  grep -Fq -- "-> $method" "$CANDIDATE_ROOT/core/mmap.w"
  body_code="$(body_of "$CANDIDATE_ROOT/core/mmap.w" "$method" | sed -E '/^[[:space:]]*(#.*)?$/d')"
  if [ "$body_code" != "    ccall(\"__w_mmap_as_typed\", self, $constant)" ]; then
    echo "candidate Mmap#$method is not the exact one-call source leaf" >&2
    exit 1
  fi
done

# Error-sensitive, common-spelling, or representation-unsafe leaves stay
# declarations and retain their native ICs.
for method in 'byte_at(i)' '[](i)' 'view_at(byte_offset, ebits, n_elements)' close; do
  if body_of "$CANDIDATE_ROOT/core/mmap.w" "$method" | grep -Eqv '^[[:space:]]*(#.*)?$'; then
    echo "native-only Mmap#$method unexpectedly has a source body" >&2
    exit 1
  fi
done

grep -Fq 'WValue __w_mmap_as_typed(WValue mmap, int element_bits)' "$BASELINE_ROOT/runtime/runtime.h"
grep -Fq 'WValue __w_mmap_as_typed(WValue mmap, int64_t element_bits)' "$CANDIDATE_ROOT/runtime/runtime.h"
grep -Fq 'WValue __w_mmap_as_typed(WValue mmap_val, int64_t element_bits)' "$CANDIDATE_ROOT/runtime/runtime.c"
grep -Fq 'declare_fn("__w_mmap_as_typed", wv, wv2)' "$CANDIDATE_ROOT/compiler/lib/emitter.w"

baseline_handlers=(close byte_at idx as_u8 as_u16 as_u32 as_u64 as_i8 as_i16 as_i32 as_i64 as_f32 as_f64 view_at)
for handler in "${baseline_handlers[@]}"; do
  grep -Fq "static WValue w_ic_mmap_$handler" "$BASELINE_ROOT/runtime/runtime.c"
done
for handler in as_u8 as_u16 as_u32 as_u64 as_i8 as_i16 as_i32 as_i64 as_f32 as_f64; do
  if grep -Fq "w_ic_mmap_$handler" "$CANDIDATE_ROOT/runtime/runtime.c"; then
    echo "candidate retains migrated w_ic_mmap_$handler" >&2
    exit 1
  fi
done
for handler in close byte_at idx view_at; do
  grep -Fq "static WValue w_ic_mmap_$handler" "$CANDIDATE_ROOT/runtime/runtime.c"
done
table_rows="$(sed -n '/^static WICEntry w_ic_mmap_table\[\]/,/^};/p' "$CANDIDATE_ROOT/runtime/runtime.c" | grep -c '{0, w_ic_mmap_')"
if [ "$table_rows" -ne 4 ]; then
  echo "candidate Mmap IC table has $table_rows live rows, expected 4" >&2
  exit 1
fi
if grep -Fq 'WN_as_' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate retains unused typed-view IC name interning" >&2
  exit 1
fi
grep -Eq 'w_ic_mmap_table\[0\]\.name[[:space:]]*=[[:space:]]*WN_close' "$CANDIDATE_ROOT/runtime/runtime.c"
grep -Eq 'w_ic_mmap_table\[1\]\.name[[:space:]]*=[[:space:]]*WN_byte_at' "$CANDIDATE_ROOT/runtime/runtime.c"
grep -Eq 'w_ic_mmap_table\[2\]\.name[[:space:]]*=[[:space:]]*WN_idx' "$CANDIDATE_ROOT/runtime/runtime.c"
grep -Eq 'w_ic_mmap_table\[3\]\.name[[:space:]]*=[[:space:]]*WN_view_at' "$CANDIDATE_ROOT/runtime/runtime.c"

grep -Fq '@mmap_size_unresolved' "$CANDIDATE_ROOT/compiler/lib/loader.w"
grep -Fq '@mmap_typed_view_unresolved' "$CANDIDATE_ROOT/compiler/lib/loader.w"
grep -Fq 'consider_autoload_name("BigArray", defined, registry, seen, pending)' "$CANDIDATE_ROOT/compiler/lib/loader.w"
grep -Fq '"as_u8" "as_u16" "as_u32" "as_u64" "as_i8" "as_i16" "as_i32" "as_i64" "as_f32" "as_f64"' "$CANDIDATE_ROOT/compiler/lib/loader.w"
if grep -Fq '@mmap_byte_at_unresolved' "$CANDIDATE_ROOT/compiler/lib/loader.w" || \
   grep -Fq 'call_name == "byte_at"' "$CANDIDATE_ROOT/compiler/lib/loader.w" || \
   grep -E '@mmap_.*call_name.*("\\\[\]"|"\[\]"|"close"|"view_at")' "$CANDIDATE_ROOT/compiler/lib/loader.w" >/dev/null; then
  echo "candidate has a forbidden Mmap native-control call-name gate" >&2
  exit 1
fi
grep -Fq '"loader-ast-v17"' "$CANDIDATE_ROOT/compiler/lib/loader.w"

if grep -Fq 'when "__w_mmap_byte_at"' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"; then
  echo "candidate unexpectedly bridges retained-native Mmap#byte_at in source" >&2
  exit 1
fi
grep -Fq 'when "__w_mmap_as_typed"' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"
grep -Fq 'ccall_rawargs("__w_mmap_as_typed", args[1], ebits)' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"
grep -Fq 'name in ("close" "byte_at" "\[]" "[]" "view_at")' "$CANDIDATE_ROOT/compiler/lib/interpreter.w"

migrated_no_use_specs=(
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_file_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_native_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_factory_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_bigarray_result_autoload_spec.w"
)
native_control_specs=(
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_byte_at_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_idx_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_close_spec.w"
  "$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_view_at_spec.w"
)
for spec in "${migrated_no_use_specs[@]}" "${native_control_specs[@]}"; do
  test -f "$spec"
  if grep -Eq '^[[:space:]]*use[[:space:]]' "$spec"; then
    echo "no-use spec contains a use directive: $spec" >&2
    exit 1
  fi
done
grep -Fq '__METHOD__' "$TYPED_TEMPLATE"
grep -Fq '__SIZE__' "$TYPED_TEMPLATE"

if [ "$ALLOW_HEAVY" != 1 ]; then
  echo "Static audit: ok. ALLOW_HEAVY=0; no compiler, IR emitter, linker, executable, or timer was run."
  exit 0
fi

test -x "$BOOTSTRAP_COMPILER"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-mmap-wrapper-revisit.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" = 1 ]; then
    echo "retained temp: $TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

wire_body() {
  local wire="$1" fn="$2"
  sed -n "/^function $fn(/,/^$/p" "$wire"
}

llvm_body() {
  local llvm="$1" fn="$2"
  sed -n "/^define .*@$fn(/,/^}/p" "$llvm"
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

require_llvm() {
  local llvm="$1" fn="$2" pattern="$3"
  if ! llvm_body "$llvm" "$fn" | grep -Eq "$pattern"; then
    echo "LLVM check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}

file_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then
    stat -f '%z' "$1"
  else
    stat -c '%s' "$1"
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

methods=(as_u8 as_u16 as_u32 as_u64 as_i8 as_i16 as_i32 as_i64 as_f32 as_f64)

method_counts() {
  echo "$VIEW_ITERS $VIEW_WARMUP"
}

compile_program() {
  local root="$1" compiler="$2" cache="$3" source="$4" output="$5"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$cache" TUNGSTEN_C_INCLUDES="$REF_C" \
      "$compiler" compile "$source" --release --out "$output" >/dev/null
  )
}

timed_compile_program() {
  local root="$1" compiler="$2" cache="$3" source="$4" output="$5" timing="$6"
  TIMEFORMAT='%3R'
  {
    time compile_program "$root" "$compiler" "$cache" "$source" "$output"
  } 2> "$timing"
}

run_observation() {
  local campaign="$1" sample="$2" label="$3" bin="$4" method="$5" iters="$6" warmup="$7" raw="$8"
  "$bin" bench "$method" "$iters" "$warmup" |
    awk -F'|' -v campaign="$campaign" -v sample="$sample" -v label="$label" \
      '$1 == "RESULT" { print campaign "|" sample "|" label "|" $0 }' >> "$raw"
}

summarize_campaign() {
  local campaign="$1" raw="$2" failed=0
  printf '\nCampaign %s\n' "$campaign"
  printf '%-10s %11s %11s %9s %9s %9s %8s\n' method native_ns source_ns med_ratio pair_med pair_max gate
  for method in "${methods[@]}"; do
    base_elapsed_med="$(awk -F'|' -v m="$method" '$3=="BASE" && $5==m {print $6}' "$raw" | median_stream)"
    cand_elapsed_med="$(awk -F'|' -v m="$method" '$3=="CAND" && $5==m {print $6}' "$raw" | median_stream)"
    base_sum="$(awk -F'|' -v m="$method" '$3=="BASE" && $5==m {print $7}' "$raw" | sort -u)"
    cand_sum="$(awk -F'|' -v m="$method" '$3=="CAND" && $5==m {print $7}' "$raw" | sort -u)"
    if [ "$base_sum" != "$cand_sum" ]; then
      echo "checksum mismatch for campaign $campaign $method" >&2
      exit 1
    fi
    base_med="$(awk -v elapsed="$base_elapsed_med" -v iters="$VIEW_ITERS" 'BEGIN { print elapsed / iters }')"
    cand_med="$(awk -v elapsed="$cand_elapsed_med" -v iters="$VIEW_ITERS" 'BEGIN { print elapsed / iters }')"
    med_ratio="$(awk -v c="$cand_elapsed_med" -v b="$base_elapsed_med" 'BEGIN { print c / b }')"
    ratios="$(awk -F'|' -v m="$method" '
      $5==m && $3=="BASE" { b[$2]=$6 }
      $5==m && $3=="CAND" { c[$2]=$6 }
      END { for (i in b) if (i in c) print c[i] / b[i] }
    ' "$raw")"
    pair_med="$(printf '%s\n' "$ratios" | median_stream)"
    pair_max="$(printf '%s\n' "$ratios" | sort -n | tail -n 1)"
    decision="$(awk -v a="$med_ratio" -v b="$pair_med" -v limit="$GATE" \
      'BEGIN { metric=(a>b?a:b); print (metric <= limit ? "PASS" : "SKIP") }')"
    if [ "$decision" != PASS ]; then failed=1; fi
    printf '%-10s %11.3f %11.3f %9.3f %9.3f %9.3f %8s\n' \
      "$method" "$base_med" "$cand_med" "$med_ratio" "$pair_med" "$pair_max" "$decision"
  done
  if [ "$failed" -ne 0 ]; then : > "$TMP/campaign-$campaign/GATE_FAILED"; fi
}

run_campaign() {
  local campaign="$1"
  local dir="$TMP/campaign-$campaign"
  local base_compiler="$dir/baseline-compiler"
  local cand_compiler="$dir/candidate-compiler"
  local base_wire="$dir/baseline.wire"
  local cand_wire="$dir/candidate.wire"
  local cand_llvm="$dir/candidate.ll"
  local base_bin="$dir/baseline"
  local cand_bin="$dir/candidate"
  local raw="$dir/results.txt"
  mkdir -p "$dir"

  echo "Campaign $campaign: rebuilding independent baseline/candidate compilers..."
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-compiler-cache" \
      "$BOOTSTRAP_COMPILER" compile compiler/tungsten.w --release --out "$base_compiler" >/dev/null
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-compiler-cache" \
      "$BOOTSTRAP_COMPILER" compile compiler/tungsten.w --release --out "$cand_compiler" >/dev/null
  )
  chmod +x "$base_compiler" "$cand_compiler"
  shasum -a 256 "$base_compiler" "$cand_compiler" > "$dir/compiler-sha256.txt"

  echo "Campaign $campaign: emitting WIRE/LLVM and matched release binaries..."
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-wire-cache" \
      "$base_compiler" compile "$DRIVER" --emit-wire > "$base_wire"
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-wire-cache" \
      "$cand_compiler" compile "$DRIVER" --emit-wire > "$cand_wire"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-llvm-cache" \
      TUNGSTEN_LL_PATH="$cand_llvm" \
      "$cand_compiler" compile "$DRIVER" --emit-ll >/dev/null
  )

  for i in "${!typed_methods[@]}"; do
    method="${typed_methods[$i]}"
    constant="${typed_constants[$i]}"
    fn="__w_Mmap_${method}__a1"
    require_wire "$cand_wire" "$fn" 'call_direct_i64 .*@__w_mmap_as_typed'
    reject_wire "$cand_wire" "$fn" 'call_method_i64|nanbox_int'
  done
  # LLVM content hashing merges methods with identical bodies (u32/i32 and
  # u64/i64) and renames source functions to __wy_*. WIRE above pins every
  # public method; emitted LLVM must contain one exact raw wrapper for each
  # distinct element-bits constant.
  for constant in 8 16 32 64 108 116 -32 -64; do
    if ! grep -Fq -- "call i64 @__w_mmap_as_typed(i64 %__self, i64 $constant)" "$cand_llvm"; then
      echo "LLVM check failed: missing hashed typed-view wrapper constant $constant" >&2
      exit 1
    fi
  done
  if ! grep -Eq '^declare i64 @__w_mmap_as_typed\(i64, i64\)' "$cand_llvm"; then
    echo "LLVM check failed: missing raw-i64 __w_mmap_as_typed declaration" >&2
    exit 1
  fi
  for wire in "$base_wire" "$cand_wire"; do
    for method in "${typed_methods[@]}"; do
      fn="__w_time_$method"
      public_calls="$(wire_body "$wire" "$fn" | awk '/call_method_i64/ { n += 1 } END { print n + 0 }')"
      if [ "$public_calls" -ne 1 ]; then
        echo "WIRE check failed: $fn has $public_calls public calls, expected 1" >&2
        exit 1
      fi
      require_wire "$wire" "$fn" 'call_direct_i64 .*@w_mwr_consume_release_view'
      reject_wire "$wire" "$fn" 'call_direct_i64 .*@w_add'
    done
  done

  compile_program "$BASELINE_ROOT" "$base_compiler" "$dir/base-build-cache" "$DRIVER" "$base_bin"
  compile_program "$CANDIDATE_ROOT" "$cand_compiler" "$dir/cand-build-cache" "$DRIVER" "$cand_bin"
  "$base_bin" check > "$dir/base-check.out"
  "$cand_bin" check > "$dir/cand-check.out"
  diff -u "$dir/base-check.out" "$dir/cand-check.out"
  cat "$dir/cand-check.out"

  for label in base cand; do
    bin="$base_bin"
    if [ "$label" = cand ]; then bin="$cand_bin"; fi
    set +e
    "$bin" close-block-fatal > "$dir/$label-close-block.out" 2> "$dir/$label-close-block.err"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "$label retained-native close block unexpectedly returned" >&2
      exit 1
    fi
    for fatal_mode in byte-missing-fatal byte-nil-fatal; do
      set +e
      "$bin" "$fatal_mode" > "$dir/$label-$fatal_mode.out" 2> "$dir/$label-$fatal_mode.err"
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then
        echo "$label $fatal_mode unexpectedly returned" >&2
        exit 1
      fi
    done
    grep -Fq 'Mmap#byte_at requires 1 argument' "$dir/$label-byte-missing-fatal.err"
    grep -Fq 'expected int, got nil' "$dir/$label-byte-nil-fatal.err"
  done

  if [ "$campaign" -eq 1 ]; then
    echo "Checking candidate no-use provenance and interpreter behavior..."
    compile_index=0
    for spec in "${migrated_no_use_specs[@]}"; do
      compile_index=$((compile_index + 1))
      out="$dir/no-use-$compile_index"
      compile_program "$CANDIDATE_ROOT" "$cand_compiler" "$dir/no-use-$compile_index-cache" "$spec" "$out"
      "$out"
    done

    for i in "${!typed_methods[@]}"; do
      method="${typed_methods[$i]}"
      expected_size="${typed_sizes[$i]}"
      source="$dir/no-use-$method.w"
      sed -e "s/__METHOD__/$method/g" -e "s/__SIZE__/$expected_size/g" "$TYPED_TEMPLATE" > "$source"
      out="$dir/no-use-$method"
      wire="$dir/no-use-$method.wire"
      (
        cd "$CANDIDATE_ROOT"
        TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/no-use-$method-wire-cache" \
          "$cand_compiler" compile "$source" --emit-wire > "$wire"
      )
      require_wire "$wire" "__w_Mmap_${method}__a1" 'call_direct_i64 .*@__w_mmap_as_typed'
      compile_program "$CANDIDATE_ROOT" "$cand_compiler" "$dir/no-use-$method-cache" "$source" "$out"
      "$out"
    done

    # Pin every retained native boundary. These opaque controls must contain no
    # Mmap source functions in either root; record fresh compile wall time and
    # binary size so a future broad autoload gate cannot slip in unnoticed.
    impact="$dir/native-control-impact.txt"
    : > "$impact"
    for control in byte_at idx close view_at; do
      spec="$CANDIDATE_ROOT/spec/compiler/mmap_wrapper_no_use_${control}_spec.w"
      for label in base cand; do
        root="$BASELINE_ROOT"; compiler="$base_compiler"
        if [ "$label" = cand ]; then root="$CANDIDATE_ROOT"; compiler="$cand_compiler"; fi
        wire="$dir/$label-$control-control.wire"
        (
          cd "$root"
          TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$dir/$label-$control-wire-cache" \
            "$compiler" compile "$spec" --emit-wire > "$wire"
        )
        if grep -Fq 'function __w_Mmap_' "$wire"; then
          echo "$label $control control unexpectedly autoloaded Mmap source" >&2
          exit 1
        fi
        out="$dir/$label-$control-control"
        timing="$dir/$label-$control-control.time"
        timed_compile_program "$root" "$compiler" "$dir/$label-$control-build-cache" "$spec" "$out" "$timing"
        "$out"
        elapsed="$(tail -n 1 "$timing")"
        echo "$control|$label|compile_wall_s|$elapsed|binary_bytes|$(file_size "$out")" >> "$impact"
      done
    done
    cat "$impact"

    (
      cd "$CANDIDATE_ROOT"
      TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$cand_compiler" run "$INTERPRETER_SPEC"
    )
  fi

  if [ "$CHECK_ONLY" = 1 ]; then return 0; fi

  : > "$raw"
  sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    method_index=0
    for method in "${methods[@]}"; do
      read -r iters warmup <<< "$(method_counts "$method")"
      echo "  campaign $campaign $method sample $((sample + 1))/$RUNS x $iters" >&2
      # Alternate adjacent A/B order across samples.
      if [ $((sample % 2)) -eq 0 ]; then
        run_observation "$campaign" "$sample" BASE "$base_bin" "$method" "$iters" "$warmup" "$raw"
        run_observation "$campaign" "$sample" CAND "$cand_bin" "$method" "$iters" "$warmup" "$raw"
      else
        run_observation "$campaign" "$sample" CAND "$cand_bin" "$method" "$iters" "$warmup" "$raw"
        run_observation "$campaign" "$sample" BASE "$base_bin" "$method" "$iters" "$warmup" "$raw"
      fi
      method_index=$((method_index + 1))
    done
    sample=$((sample + 1))
  done
  summarize_campaign "$campaign" "$raw"
}

if [ "$CHECK_ONLY" = 1 ]; then
  run_campaign 1
  echo "CHECK_ONLY=1: rebuilt baseline/candidate compilers, WIRE/LLVM raw-ABI constants, release correctness, errors/extras/blocks, exact independent autoload names, no-broad-gate controls, and interpreter checks passed; timings skipped."
  exit 0
fi

failed=0
campaign=1
while [ "$campaign" -le "$CAMPAIGNS" ]; do
  run_campaign "$campaign"
  if [ -f "$TMP/campaign-$campaign/GATE_FAILED" ]; then failed=1; fi
  campaign=$((campaign + 1))
done

echo "Thread CPU timings; $RUNS alternating matched samples per method and campaign. Every campaign rebuilt both compilers and both release/LTO binaries from fresh caches."
if [ "$failed" -ne 0 ]; then exit 3; fi
