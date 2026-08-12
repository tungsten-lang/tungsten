#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-"$ROOT/bin/tungsten"}"
COMPILER="$ROOT/bin/tungsten-compiler"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-specs.$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$TMP_ROOT"
fail=0

if [[ ! -x "$COMPILER" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

# Per-spec compiles land at PID-unique $TMP_ROOT paths, so caching them only
# mints garbage cache entries — keep the incremental binary cache off for the
# whole suite. The cache lifecycle test below re-enables it per step against
# an isolated TUNGSTEN_CACHE_DIR.
export TUNGSTEN_INCREMENTAL=0

# Parallelism: specs are independent (per-spec temp outputs), so the
# compile+run stages fan out across JOBS workers via self-exec (--job-*
# modes below). Results land in a shared directory and are aggregated in
# list order, so output and failure attribution stay deterministic. The
# cache-lifecycle test and the gated tails (metal, PTY, api) stay serial.
# JOBS=1 restores fully serial behavior. FAST=1 runs the curated inner-
# loop slice only (see fast_* lists) and skips the serial tails.
JOBS="${JOBS:-auto}"
if [[ "$JOBS" == "auto" ]]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  JOBS=$(( JOBS - 2 ))
  (( JOBS < 1 )) && JOBS=1
fi
if [[ -n "${TUNGSTEN_SPECS_JOBS_DIR:-}" ]]; then
  JOB_RESULT_DIR="$TUNGSTEN_SPECS_JOBS_DIR"
else
  JOB_RESULT_DIR=""
  export TUNGSTEN_SPECS_JOBS_DIR="$TMP_ROOT/job-results"
  mkdir -p "$TUNGSTEN_SPECS_JOBS_DIR"
fi

record_result() {
  local name="$1"
  local output="$2"
  local status="$3"

  # Job mode: persist for the parent's ordered aggregation instead of
  # printing/flagging here.
  if [[ -n "$JOB_RESULT_DIR" ]]; then
    local key="${TUNGSTEN_SPECS_KEY_PREFIX:-}${name//\//__}"
    printf '%s\n' "$output" > "$JOB_RESULT_DIR/$key.out"
    echo "$status" > "$JOB_RESULT_DIR/$key.status"
    return
  fi

  printf '%s\n' "$output"

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL [$name] exited $status" >&2
    fail=1
  elif printf '%s\n' "$output" | grep -Eq '^FAIL([ :]|$)'; then
    echo "FAIL [$name] emitted failing checks" >&2
    fail=1
  fi
}

# Early-exit failures (compile failed, ...) that bypass record_result:
# in job mode persist a note the parent replays verbatim, so failure
# lines keep their exact serial-mode format.
record_failure_note() {
  local name="$1"
  local why="$2"
  if [[ -n "$JOB_RESULT_DIR" ]]; then
    printf '%s\n' "$why" > "$JOB_RESULT_DIR/${TUNGSTEN_SPECS_KEY_PREFIX:-}${name//\//__}.note"
    return
  fi
  echo "FAIL [$name] $why" >&2
  fail=1
}

# Aggregate one job's captured result through the normal reporting path.
# Results are CONSUMED: the same spec name can run in more than one lane
# (compiled and interpreted), and a stale note or output from an earlier
# lane must never shadow the next lane's fresh result.
finish_job() {
  local name="$1"
  local key="${2:-}${name//\//__}"
  local out status
  if [[ -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.note" ]]; then
    echo "FAIL [$name] $(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.note")" >&2
    fail=1
    rm -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.note" "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" "$TUNGSTEN_SPECS_JOBS_DIR/$key.status"
    return
  fi
  out="$(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" 2>/dev/null || echo "MISSING JOB OUTPUT for $name")"
  status="$(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.status" 2>/dev/null || echo 99)"
  rm -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" "$TUNGSTEN_SPECS_JOBS_DIR/$key.status"
  record_result "$name" "$out" "$status"
}

# Fan a spec list out across JOBS self-exec workers, then aggregate in
# the original order. Extra args after the mode are forwarded to every
# job (the wassat CLI path rides this).
run_parallel() {
  local mode="$1"; shift
  local -a specs=()
  local -a extra=()
  local seen_sep=0 a
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then seen_sep=1; continue; fi
    if [[ "$seen_sep" -eq 1 ]]; then extra+=("$a"); else specs+=("$a"); fi
  done
  [[ ${#specs[@]} -eq 0 ]] && return 0
  printf '%s\n' "${specs[@]}" | TUNGSTEN_SPECS_KEY_PREFIX="$mode." xargs -P "$JOBS" -I{} "$0" "--job-$mode" {} "${extra[@]:-}"
  run_parallel_aggregate "$mode" "${specs[@]}"
}

# Launch a lane without blocking (results aggregated later); pair every
# call with run_parallel_aggregate after wait. Keys are mode-prefixed, so
# overlapping lanes never collide even when spec names repeat.
run_parallel_launch() {
  local mode="$1"; shift
  [[ $# -eq 0 ]] && return 0
  printf '%s\n' "$@" | TUNGSTEN_SPECS_KEY_PREFIX="$mode." xargs -P "$JOBS" -I{} "$0" "--job-$mode" {} &
}

run_parallel_aggregate() {
  local mode="$1"; shift
  local spec name
  for spec in "$@"; do
    name="$(basename "${spec%.w}")"
    if [[ "$mode" == "wassat" ]]; then
      name="wassat/$name"
    fi
    finish_job "$name" "$mode."
  done
}

run_compiled_spec() {
  local path="$1"
  local name
  local out
  local output
  local status
  local -a compile_cmd

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"

  echo "compile+run $path"
  if [[ "$path" == spec/compiler/big_array_cap_empty_no_use_*_spec.w ]]; then
    compile_cmd=(env "TUNGSTEN_C_INCLUDES=$ROOT/benchmarks/runtime_ports/big_array_cap_empty_revisit_ref.c" "$TUNGSTEN")
  else
    compile_cmd=("$TUNGSTEN")
  fi
  if ! "${compile_cmd[@]}" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed"
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

run_interpreter_spec() {
  local path="$1"
  local name
  local output
  local status

  name="$(basename "${path%.w}")"
  echo "run $path"
  set +e
  output="$(TUNGSTEN_INTERPRETED_SPEC=1 "$TUNGSTEN" run "$path" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

run_wassat_spec() {
  local path="$1"
  local wassat_bin="$2"
  local name
  local spec_bin
  local output
  local status
  local summary
  local total
  local passed
  local failed

  name="$(basename "${path%.w}")"
  # Compile-and-run set, mirroring benchmarks/gate.sh: these exercise the
  # native DIMACS parser, process portfolio, or atomic-cancellation ABI that
  # exist only in compiled programs. solver_spec belongs here too: its native
  # CAS/conflict-ticket regressions are part of the default correctness gate,
  # and compiling avoids the interpreter's tens-of-minutes runtime. The
  # interpreted remainder (sls, incremental, trim, explain,
  # algebra_certificate) stays interpreted here.
  case "$name" in
    solver_spec|cli_spec|preprocess_spec|portfolio_spec|multiplier_spec|ternary_affine_spec|ais_spec|coloring_spec|covering_spec|directed_kernel_spec|local_core_spec|latin_csp_spec|fermat_spec|sum_of_three_cubes_spec|mdp_spec|automata_sync_spec|edge_matching_spec|sliding_puzzle_spec|stedman_spec|hantzsche_wendt_spec|knight_tour_spec)
      compile_wassat_spec=1 ;;
    *)
      compile_wassat_spec=0 ;;
  esac
  if [[ "$compile_wassat_spec" == "1" ]]; then
    spec_bin="$TMP_ROOT/wassat-$name"
    echo "compile+run $path (WASSAT_TEST_BIN=$wassat_bin)"
    if ! "$TUNGSTEN" compile "$path" --out "$spec_bin" --no-lto >/dev/null; then
      record_failure_note "wassat/$name" "compile failed"
      return
    fi
    set +e
    output="$(WASSAT_TEST_BIN="$wassat_bin" "$spec_bin" 2>&1)"
    status=$?
    set -e
  else
    echo "run $path (WASSAT_TEST_BIN=$wassat_bin)"
    set +e
    output="$(WASSAT_TEST_BIN="$wassat_bin" "$TUNGSTEN" run "$path" 2>&1)"
    status=$?
    set -e
  fi

  # A compiler/runtime failure has previously produced an executable that
  # silently exited zero. Do not let that look like a green spec: a successful
  # Wassat job must report an internally consistent, zero-failure summary.
  if [[ "$status" -eq 0 ]]; then
    summary="$(printf '%s\n' "$output" | grep -E '^[0-9]+ examples: [0-9]+ passed, [0-9]+ failed$' | tail -1 || true)"
    if [[ -z "$summary" ]]; then
      output="${output}${output:+$'\n'}FAIL: missing valid Wassat spec summary"
      status=1
    else
      total="$(printf '%s\n' "$summary" | sed -nE 's/^([0-9]+) examples:.*/\1/p')"
      passed="$(printf '%s\n' "$summary" | sed -nE 's/^[0-9]+ examples: ([0-9]+) passed,.*/\1/p')"
      failed="$(printf '%s\n' "$summary" | sed -nE 's/.*, ([0-9]+) failed$/\1/p')"
      if [[ "$failed" -ne 0 || "$total" -ne $((passed + failed)) ]]; then
        output="${output}${output:+$'\n'}FAIL: inconsistent or failing Wassat spec summary"
        status=1
      fi
    fi
  fi
  record_result "wassat/$name" "$output" "$status"
}

run_metal_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"

  echo "compile+run $path"
  if ! TUNGSTEN_LL_PATH="$ll_path" "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    echo "FAIL [$name] compile failed" >&2
    fail=1
    rm -f "$ll_path" "$ll_path.done" "$metal_path"
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path"
}

# Emit-only CUDA dialect check: compiles with TUNGSTEN_GPU_DIALECTS=cuda so a
# sibling .cu is written next to the source; the binary reads that text. No
# CUDA toolkit or GPU is required. Always cleans metal/cu/ll sidecars.
run_cuda_emit_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"

  echo "compile+run $path (TUNGSTEN_GPU_DIALECTS=cuda)"
  if ! TUNGSTEN_GPU_DIALECTS=cuda TUNGSTEN_LL_PATH="$ll_path" \
      "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed"
    rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path"
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path"
}

# WGSL dialect check. The binary pins expected source markers; when NAGA_BIN is
# set (CI pins naga-cli), Naga also parses and semantically validates the actual
# emitted sidecar. No browser, WebGPU implementation, or GPU is required.
run_wgsl_emit_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local wgsl_path
  local output
  local status
  local validator

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"
  wgsl_path="$ROOT/${path%.w}.wgsl"

  echo "compile+run $path (TUNGSTEN_GPU_DIALECTS=wgsl)"
  if ! TUNGSTEN_GPU_DIALECTS=wgsl TUNGSTEN_LL_PATH="$ll_path" \
      "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed"
    rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
    return
  fi

  validator="${NAGA_BIN:-}"
  if [[ -z "$validator" ]] && command -v naga >/dev/null 2>&1; then
    validator="$(command -v naga)"
  fi
  if [[ -n "$validator" ]]; then
    if [[ ! -x "$validator" ]]; then
      record_failure_note "$name" "NAGA_BIN is not executable: $validator"
      rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
      return
    fi
    set +e
    output="$("$validator" "$wgsl_path" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
      record_result "$name" "$output" "$status"
      rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
      return
    fi
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
}

# CUDA expected-rejection checks. These prove a Metal-only intrinsic fails in
# Tungsten's dialect emitter with a useful diagnostic, before an invalid .cu
# reaches nvcc. No CUDA toolkit or GPU is required.
run_cuda_reject_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local needle
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"
  case "$name" in
    gpu_cuda_tg_reduce_reject_spec) needle='`tg_sum` is not supported by the CUDA dialect' ;;
    gpu_cuda_simdgroup_reject_spec) needle='`simdgroup_load` is Metal-only' ;;
    *) record_failure_note "$name" "missing expected CUDA diagnostic"; return ;;
  esac

  echo "compile-reject $path (TUNGSTEN_GPU_DIALECTS=cuda)"
  set +e
  output="$(TUNGSTEN_GPU_DIALECTS=cuda TUNGSTEN_LL_PATH="$ll_path" \
    "$TUNGSTEN" compile "$path" --out "$out" 2>&1)"
  status=$?
  set -e
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$out"

  if [[ "$status" -eq 0 ]]; then
    record_failure_note "$name" "compile unexpectedly accepted Metal-only CUDA intrinsic"
  elif ! grep -Fq "$needle" <<<"$output"; then
    record_result "$name" "$output" 1
  else
    record_result "$name" "PASS $name" 0
  fi
}

# ── Incremental binary cache lifecycle ────────────────────────────────────
# One compile step of the lifecycle test: expects a cache hit ("(cache)" in
# the driver output) or a miss, with TUNGSTEN_INCREMENTAL set explicitly so
# the suite-wide export above does not leak in.
cache_lifecycle_step() {
  local label="$1"
  local expect="$2"   # yes|no — whether "(cache)" must appear
  local inc="$3"      # TUNGSTEN_INCREMENTAL value for this step
  local src="$4"
  local out="$5"
  local output
  local status
  local hit

  set +e
  output="$(TUNGSTEN_CACHE_DIR="$cache_lifecycle_dir" TUNGSTEN_INCREMENTAL="$inc" \
    "$TUNGSTEN" compile "$src" --out "$out" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL [cache_lifecycle] $label: compile exited $status" >&2
    printf '%s\n' "$output" >&2
    fail=1
    return
  fi
  hit="no"
  if printf '%s\n' "$output" | grep -qF "(cache)"; then
    hit="yes"
  fi
  if [[ "$hit" != "$expect" ]]; then
    echo "FAIL [cache_lifecycle] $label: expected cache=$expect, got cache=$hit" >&2
    fail=1
  else
    echo "PASS [cache_lifecycle] $label (cache=$hit)"
  fi
}

run_cache_lifecycle_test() {
  local dir="$TMP_ROOT/cache-test"
  local src="$dir/prog.w"
  local out="$dir/prog"
  local deep
  local i

  cache_lifecycle_dir="$dir/cache"
  mkdir -p "$dir"
  printf '<< "cache lifecycle probe"\n' > "$src"
  echo "cache lifecycle test (TUNGSTEN_CACHE_DIR=$cache_lifecycle_dir)"

  cache_lifecycle_step "cold compile misses" no 1 "$src" "$out"
  cache_lifecycle_step "identical recompile hits" yes 1 "$src" "$out"

  touch "$src"
  cache_lifecycle_step "touched source misses" no 1 "$src" "$out"

  touch "$ROOT/runtime/runtime.c"
  cache_lifecycle_step "touched runtime source misses" no 1 "$src" "$out"

  cache_lifecycle_step "TUNGSTEN_INCREMENTAL=0 misses" no 0 "$src" "$out"

  # A ~200-char nested output path: slot names hash the absolute paths, so
  # storing must not overflow NAME_MAX and the second compile must hit.
  deep="$dir"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    deep="$deep/deep-cache-path-seg"
  done
  mkdir -p "$deep"
  cache_lifecycle_step "deep output path cold compile misses" no 1 "$src" "$deep/prog"
  cache_lifecycle_step "deep output path recompile hits" yes 1 "$src" "$deep/prog"
}

# Self-exec worker entry: run exactly one spec, persist its result for
# the parent, and exit 0 (pass/fail travels through the status file).
if [[ "${1:-}" == --job-* ]]; then
  case "$1" in
    --job-compiled) run_compiled_spec "$2" ;;
    --job-interp)   run_interpreter_spec "$2" ;;
    --job-cuda)     run_cuda_emit_spec "$2" ;;
    --job-wgsl)     run_wgsl_emit_spec "$2" ;;
    --job-cuda-reject) run_cuda_reject_spec "$2" ;;
    --job-wassat)   run_wassat_spec "$2" "$3" ;;
    *) echo "unknown job mode $1" >&2; exit 2 ;;
  esac
  exit 0
fi

compiled_specs=(
  spec/compiler/ast_body_native_spec.w
  spec/compiler/ast_typed_sidecar_spec.w
  spec/compiler/ast_typed_visitor_spec.w
  spec/compiler/array_compact_autoload_spec.w
  spec/compiler/array_constructor_parity_spec.w
  spec/compiler/heredoc_opaque_lexer_spec.w
  spec/compiler/array_dup_autoload_spec.w
  spec/compiler/array_join_autoload_spec.w
  spec/compiler/argv_nested_scan_spec.w
  spec/compiler/big_array_cap_empty_no_use_new_spec.w
  spec/compiler/big_array_cap_empty_no_use_range_spec.w
  spec/compiler/big_array_cap_empty_no_use_subview_spec.w
  spec/compiler/big_array_cap_empty_no_use_view_spec.w
  benchmarks/runtime_ports/bigint_predicate_relaxed_autoload.w
  spec/compiler/bigint_bitwise_mut_source_seam_spec.w
  spec/compiler/bigint_bitwise_native_support_spec.w
  spec/compiler/bigint_bitwise_reopen_source_seam_spec.w
  spec/compiler/bigint_small_mut_lowering_spec.w
  spec/compiler/bigint_to_i_autoload_spec.w
  spec/compiler/block_passthrough_spec.w
  spec/compiler/block_presence_parity_spec.w
  spec/compiler/carry_intrinsics_parity_spec.w
  spec/compiler/cfg_ssa_pruning_spec.w
  spec/compiler/elementwise_fusion_spec.w
  spec/compiler/forward_typed_raw_call_spec.w
  spec/compiler/poly_ranged_sum_big_bounds_spec.w
  spec/compiler/function_replacement_index_spec.w
  benchmarks/runtime_ports/float_remaining_no_use_literal.w
  spec/compiler/indexed_compound_assignment_parameter_spec.w
  spec/compiler/int_to_i_autoload_spec.w
  spec/compiler/ivar_typed_return_spec.w
  spec/compiler/lambda_puts_body_spec.w
  spec/compiler/mmap_size_relaxed_autoload_spec.w
  spec/compiler/mmap_size_relaxed_native_autoload_spec.w
  spec/compiler/nested_closure_counted_capture_spec.w
  spec/compiler/nested_i64_array_boxed_store_spec.w
  spec/compiler/one_arg_cached_dispatch_emitter_spec.w
  spec/compiler/ownership_phi_escape_spec.w
  spec/compiler/parser_packed_token_access_spec.w
  spec/compiler/raw_int_candidate_map_spec.w
  spec/compiler/raw_machine_helper_control_flow_spec.w
  spec/compiler/raw_static_machine_return_spec.w
  spec/compiler/recase_spec.w
  spec/compiler/recycle_inline_iterator_validation_spec.w
  spec/compiler/recycle_nonlocal_block_return_spec.w
  spec/compiler/recycle_terminated_scope_spec.w
  spec/compiler/source_argc1_constructor_exclusion_spec.w
  spec/compiler/source_argc1_exact_ivar_spec.w
  spec/compiler/source_argc1_hint_compat_spec.w
  spec/compiler/string_dynamic_dispatch_spec.w
  spec/compiler/string_buffer_size_revisit_autoload_spec.w
  spec/compiler/string_escape_backslash_spec.w
  spec/compiler/string_interp_esc_bracket_spec.w
  spec/compiler/machine_int_subscript_fused_spec.w
  spec/compiler/machine_int_subscript_store_spec.w
  spec/compiler/method_fallthrough_parity_spec.w
  spec/compiler/small_array_stack_escape_spec.w
  spec/compiler/small_array_stack_zero_init_spec.w
  spec/compiler/small_array_generic_spec.w
  spec/compiler/small_array_wide_element_boxing_spec.w
  spec/compiler/typed_array_boxed_read_family_spec.w
  spec/compiler/masked_index_loop_spec.w
  spec/compiler/loop_version_array_spec.w
  spec/compiler/devirt_method_call_spec.w
  spec/compiler/boxed_arith_fast_spec.w
  spec/compiler/typed_receiver_string_routes_spec.w
  spec/compiler/string_free_escape_spec.w
  spec/compiler/constructor_arity_spec.w
  spec/compiler/ctor_inline_cache_nested_spec.w
  spec/compiler/global_demotion_scopes_spec.w
  spec/compiler/strbuf_bytes_spec.w
  spec/compiler/string_buffer_dynamic_append_spec.w
  spec/compiler/quantity_control_flow_parity_spec.w
  spec/compiler/static_method_block_dispatch_spec.w
  spec/compiler/static_method_overload_spec.w
  spec/compiler/splat_parameter_parity_spec.w
  spec/compiler/int_bigint_promotion_spec.w
  spec/compiler/bigint_literal_cache_spec.w
  spec/compiler/ivar_param_type_spec.w
  spec/compiler/llvm_name_mangling_injective_spec.w
  spec/compiler/top_level_method_name_hygiene_spec.w
  spec/compiler/u64_raw_multiply_spec.w
  spec/compiler/conditional_reassign_param_spec.w
  spec/compiler/promotion_determinism_spec.w
  spec/compiler/begin_rescue_value_spec.w
  spec/compiler/wide_params_calls_spec.w
  spec/compiler/typed_array_param_width_spec.w
  spec/compiler/typed_helper_array_signature_spec.w
  spec/compiler/typed_overload_spec.w
  spec/compiler/overload_exact_tag_parity_spec.w
  spec/compiler/typed_overload_hosts_spec.w
  spec/numeric/bigint_seam_disjoint_spec.w
  spec/compiler/bigint_compare_native_support_spec.w
  spec/compiler/uuid_byte_revisit_autoload_spec.w
  spec/compiler/autoload_walker_fields_spec.w
  spec/compiler/view_field_var_spec.w
  spec/compiler/zero_arg_cached_dispatch_spec.w
  spec/interpreter/hash_size_view_field_spec.w
  spec/interpreter/float_leaf_native_spec.w
  spec/interpreter/implicit_block_param_shadow_spec.w
  spec/interpreter/ipv4_octets_native_spec.w
  spec/core/basics_spec.w
  spec/core/base64_native_spec.w
  spec/core/global_sleep_spec.w
  spec/core/system_cpu_count_spec.w
  spec/core/sandbox_spec.w
  spec/core/file_stat_tempfile_spec.w
  spec/core/filesystem_walk_spec.w
  spec/core/clock_ms_spec.w
  spec/core/csv_stream_spec.w
  spec/core/json_parse_spec.w
  spec/core/string_to_i_bignum_spec.w
  spec/core/string_native_spec.w
  spec/core/control_flow_spec.w
  spec/core/classes_spec.w
  spec/core/arrays_hashes_spec.w
  spec/core/hash_insertion_order_spec.w
  spec/core/container_equality_spec.w
  spec/core/calculus_spec.w
  spec/core/calculus_complex_spec.w
  spec/core/expression_spec.w
  spec/core/expression_autoload_spec.w
  spec/core/expression_calculus_spec.w
  spec/core/expression_algebra_spec.w
  spec/core/expression_exact_spec.w
  spec/core/expression_special_spec.w
  spec/core/expression_transcendental_spec.w
  spec/core/expression_solve_spec.w
  spec/core/algebra_autoload_spec.w
  spec/core/algebra_projective_heights_spec.w
  spec/core/algebra_prime_subspace_spec.w
  spec/core/algebra_c_ab_spec.w
  spec/core/algebra_divisors_spec.w
  # The full KM order certificate is intentionally native: the interpreter's
  # boxed exact-linear-algebra path is prohibitively memory hungry.
  spec/core/algebra_c_ab_divisors_spec.w
  spec/core/algebra_real_roots_spec.w
  spec/core/algebra_ideal_arithmetic_spec.w
  spec/core/algebra_lattice_reduction_spec.w
  spec/core/algebra_p_adic_number_field_spec.w
  spec/core/algebra_p_adic_dyadic_spec.w
  spec/core/algebra_s_class_group_spec.w
  spec/core/algebra_s_units_spec.w
  spec/core/algebra_shell_width_degree6_artifact_spec.w
  spec/core/algebra_shell_width_degree9_artifact_spec.w
  spec/core/algebra_shell_width_degree12_artifact_spec.w
  spec/core/algebra_shell_width_s_unit_artifacts_spec.w
  spec/core/algebraic_real_spec.w
  spec/core/formal_series_spec.w
  spec/core/formal_series_autoload_spec.w
  spec/core/enumerable_native_spec.w
  spec/core/hash_identity_probe_spec.w
  spec/core/network_native_spec.w
  spec/core/system_spec.w
  benchmarks/runtime_ports/array_leaf_no_use_factories.w
  benchmarks/runtime_ports/array_leaf_no_use_literal.w
  benchmarks/runtime_ports/array_leaf_no_use_typed.w
  benchmarks/runtime_ports/small_big_array_no_use_autoload.w
  benchmarks/runtime_ports/sync_wrapper_revisit_exact_factory.w
  spec/numeric/bigint_bang_spec.w
  spec/numeric/bigint_limb_sweep_spec.w
  spec/numeric/bigint_tag_sign_spec.w
  spec/compiler/bigint_shared_bit_spec.w
  spec/compiler/bigint_mutate_unique_spec.w
  spec/compiler/bigint_mod_pow2_context_spec.w
  spec/compiler/postfix_rescue_loader_spec.w
  spec/numeric/bigint_view_field_write_spec.w
  spec/compiler/hash_free_escape_spec.w
  spec/numeric/bit_ops_spec.w
  spec/numeric/complex_spec.w
  spec/numeric/fp_math_mode_spec.w
  spec/numeric/gcd_spec.w
  spec/numeric/hypercomplex_mul_spec.w
  spec/numeric/int_spec.w
  spec/numeric/interval_spec.w
  spec/numeric/matrix_spec.w
  spec/numeric/operator_overload_spec.w
  spec/numeric/rational_spec.w
  spec/numeric/vector_spec.w
)

# Emit-only GPU dialect specs (no hardware). Run always with make specs.
cuda_emit_specs=(
  spec/compiler/gpu_cuda_emit_spec.w
)

wgsl_emit_specs=(
  spec/compiler/gpu_wgsl_emit_spec.w
)

cuda_reject_specs=(
  spec/compiler/gpu_cuda_tg_reduce_reject_spec.w
  spec/compiler/gpu_cuda_simdgroup_reject_spec.w
)

interpreter_specs=(
  # Engine-parity pins: these compiler specs assert values that must hold
  # identically interpreted (compiled-only verification has missed clobbered
  # interpreter.w hunks before).
  spec/compiler/block_presence_parity_spec.w
  spec/compiler/array_constructor_parity_spec.w
  spec/compiler/heredoc_opaque_lexer_spec.w
  spec/compiler/method_fallthrough_parity_spec.w
  spec/compiler/int_bigint_promotion_spec.w
  spec/compiler/bigint_literal_cache_spec.w
  spec/compiler/carry_intrinsics_parity_spec.w
  spec/compiler/ivar_param_type_spec.w
  spec/compiler/llvm_name_mangling_injective_spec.w
  spec/compiler/top_level_method_name_hygiene_spec.w
  spec/compiler/string_buffer_dynamic_append_spec.w
  spec/compiler/quantity_control_flow_parity_spec.w
  spec/compiler/static_method_block_dispatch_spec.w
  spec/compiler/static_method_overload_spec.w
  # clock_ms had to be registered in BOTH lowering.w and builtins.w; pin the
  # interpreted side so a compiled-only fix cannot pass again.
  spec/core/clock_ms_spec.w
  spec/core/csv_stream_spec.w
  spec/core/channel_spec.w
  spec/core/atomic_spec.w
  spec/core/mutex_spec.w
  spec/core/timer_validation_spec.w
  spec/core/env_spec.w
  spec/core/integer_tower_spec.w
  spec/core/url_spec.w
  spec/core/filesystem_walk_spec.w
  spec/core/file_stat_tempfile_spec.w
  spec/compiler/splat_parameter_parity_spec.w
  # JSON.parse was compiled-only until the interpreter learned to resolve bare
  # calls to sibling class methods; pin the interpreted side.
  spec/core/json_parse_spec.w
  spec/interpreter/float_leaf_native_spec.w
  spec/interpreter/big_array_cap_empty_revisit_spec.w
  spec/interpreter/hash_size_view_field_spec.w
  spec/interpreter/implicit_block_param_shadow_spec.w
  spec/interpreter/int_to_i_native_spec.w
  spec/interpreter/ipv4_octets_native_spec.w
  spec/interpreter/mmap_size_relaxed_spec.w
  spec/compiler/source_argc1_constructor_exclusion_spec.w
  spec/numeric/gcd_spec.w
  spec/interpreter/range_primitive_dispatch_spec.w
  # BigInt bang methods + the writable native view-field bridge and the
  # 1..64 limb sweep are engine-parity pins: the interpreter reaches the
  # same header through native_data_field_writable?, so a compiled-only
  # fix must not pass alone.
  spec/numeric/bigint_bang_spec.w
  spec/numeric/bigint_limb_sweep_spec.w
  spec/numeric/bigint_tag_sign_spec.w
  # Exact-tag overload gate (B3): the interpreter's
  # overload_matches_args? carries a HAND-COPIED mirror of lowering's
  # tag-table rule; pin the interpreted side so a compiled-only change
  # cannot drift the copy.
  spec/compiler/overload_exact_tag_parity_spec.w
  spec/compiler/typed_overload_spec.w
  # Host-parity pin: the implicit-self (bare sibling call) route must run
  # typed-overload selection like the explicit-receiver route — it
  # silently took the last-registered arm before args were threaded
  # through implicit_self_method.
  spec/compiler/typed_overload_hosts_spec.w
  # B6 one-way disjointness of the bigint source-op seam: a pair the
  # source bodies bail on must never be re-admitted by bigint_src_shape
  # (w_add → src → w_add recursion presents as a segfault). Exercises
  # every boundary of both sets on both engines.
  spec/numeric/bigint_seam_disjoint_spec.w
  spec/compiler/bigint_shared_bit_spec.w
  spec/compiler/bigint_mutate_unique_spec.w
  spec/compiler/bigint_mod_pow2_context_spec.w
  spec/compiler/postfix_rescue_loader_spec.w
  spec/numeric/bigint_view_field_write_spec.w
  spec/compiler/hash_free_escape_spec.w
  spec/numeric/bit_ops_spec.w
  spec/numeric/rational_spec.w
  spec/interpreter/slab_decl_spec.w
  spec/interpreter/string_buffer_size_revisit_spec.w
  spec/interpreter/string_empty_native_spec.w
  spec/interpreter/string_to_s_native_spec.w
  spec/interpreter/typed_array_signed_header_spec.w
  spec/interpreter/uuid_byte_revisit_spec.w
  spec/interpreter/dot_elementwise_spec.w
  spec/core/base64_native_spec.w
  spec/core/calculus_spec.w
  spec/core/calculus_complex_spec.w
  spec/core/expression_spec.w
  spec/core/expression_autoload_spec.w
  spec/core/expression_calculus_spec.w
  spec/core/expression_algebra_spec.w
  spec/core/expression_exact_spec.w
  spec/core/expression_special_spec.w
  spec/core/expression_transcendental_spec.w
  spec/core/expression_solve_spec.w
  # The exhaustive real-root/ideal/lattice/S-class/S-unit programs are gated
  # above in the compiled lane. Repeating them in the tree walker consumed the
  # entire suite tail (multiple full cores for 10+ minutes) without adding a
  # distinct assertion; the focused expression/formal-series parity specs stay
  # interpreted below.
  spec/core/algebra_shell_width_degree6_artifact_spec.w
  spec/core/algebra_shell_width_degree9_artifact_spec.w
  spec/core/algebra_shell_width_degree12_artifact_spec.w
  spec/core/algebra_shell_width_s_unit_artifacts_spec.w
  spec/core/formal_series_spec.w
  spec/core/formal_series_autoload_spec.w
  spec/core/enumerable_native_spec.w
  spec/core/system_spec.w
  spec/numeric/complex_spec.w
  spec/numeric/hypercomplex_mul_spec.w
  spec/numeric/matrix_spec.w
  spec/numeric/operator_overload_spec.w
  spec/numeric/vector_spec.w
  benchmarks/runtime_ports/array_leaf_interpreter.w
  benchmarks/runtime_ports/bigint_predicate_relaxed_interpreter.w
  benchmarks/runtime_ports/float_remaining_interpreter.w
  benchmarks/runtime_ports/identity_leaf_interpreter.w
  benchmarks/runtime_ports/small_big_array_interpreter.w
  benchmarks/runtime_ports/sync_wrapper_revisit_interpreter.w
)

core_specs=(
  spec/core/atomic_spec.w
  spec/core/byte_array_equality_spec.w
  spec/core/crypto_accel_spec.w
  spec/core/crypto_hmac_scram_spec.w
  spec/core/channel_spec.w
  spec/core/channel_unbuffered_spec.w
  spec/core/mutex_spec.w
  spec/core/mutex_thread_spec.w
  spec/core/timer_spec.w
  spec/core/timer_validation_spec.w
  spec/core/env_spec.w
  spec/core/integer_tower_spec.w
  spec/core/url_spec.w
  spec/core/socket_read_into_spec.w
  spec/core/byte_array_slice_spec.w
  spec/core/byte_array_view_flatten_spec.w
  spec/core/byte_array_view_reallocation_spec.w
  spec/core/memory_mapped_view_spec.w
  spec/core/process_spawn_argv_ownership_spec.w
)

metal_specs=(
  spec/core/metal_dispatch_n_spec.w
  spec/core/metal_f16_buffer_spec.w
  spec/core/metal_kernel_spec.w
  spec/core/metal_q8_matvec_spec.w
  spec/core/metal_signed_array_bridge_spec.w
  spec/core/schedule_unroll_spec.w
)

wassat_specs=(
  bits/tungsten-wassat/spec/solver_spec.w
  bits/tungsten-wassat/spec/cli_spec.w
  bits/tungsten-wassat/spec/preprocess_spec.w
  bits/tungsten-wassat/spec/incremental_spec.w
  bits/tungsten-wassat/spec/sls_spec.w
  bits/tungsten-wassat/spec/trim_spec.w
  bits/tungsten-wassat/spec/explain_spec.w
  bits/tungsten-wassat/spec/algebra_certificate_spec.w
  bits/tungsten-wassat/spec/portfolio_spec.w
  bits/tungsten-wassat/spec/multiplier_spec.w
  bits/tungsten-wassat/spec/ternary_affine_spec.w
  bits/tungsten-wassat/spec/ais_spec.w
  bits/tungsten-wassat/spec/coloring_spec.w
  bits/tungsten-wassat/spec/covering_spec.w
  bits/tungsten-wassat/spec/directed_kernel_spec.w
  bits/tungsten-wassat/spec/local_core_spec.w
  bits/tungsten-wassat/spec/latin_csp_spec.w
  bits/tungsten-wassat/spec/fermat_spec.w
  bits/tungsten-wassat/spec/sum_of_three_cubes_spec.w
  bits/tungsten-wassat/spec/mdp_spec.w
  bits/tungsten-wassat/spec/automata_sync_spec.w
  bits/tungsten-wassat/spec/edge_matching_spec.w
  bits/tungsten-wassat/spec/sliding_puzzle_spec.w
  bits/tungsten-wassat/spec/stedman_spec.w
  bits/tungsten-wassat/spec/hantzsche_wendt_spec.w
  bits/tungsten-wassat/spec/knight_tour_spec.w
)

# The independent proof checker ships as its own bit with no shared parsing
# or checking code; its checker_spec runs through the interpreter (it needs
# no compiled runtime builtins).
wrat_specs=(
  bits/tungsten-wrat/spec/checker_spec.w
)

run_special_bit_specs() {
  # Wassat has a deliberate compiled/interpreted split: its native parser,
  # process portfolio, and atomic ABI are not meaningful through the
  # interpreter, while a few proof-library specs intentionally stay there.
  # Keep this lane here, but let `rake spec:bits` own when it runs so every bit
  # spec is executed exactly once by the default root suite.
  local wassat_bin="$TMP_ROOT/wassat"
  echo "compile bits/tungsten-wassat/bin/wassat.w"
  if "$TUNGSTEN" compile bits/tungsten-wassat/bin/wassat.w --out "$wassat_bin" --no-lto >/dev/null; then
    run_parallel wassat "${wassat_specs[@]}" -- "$wassat_bin"
  else
    echo "FAIL [wassat] CLI compile failed" >&2
    fail=1
  fi

  # The independent proof checker has no shared parsing/checking code and does
  # not need compiled runtime builtins, so its contract stays interpreted.
  run_parallel interp "${wrat_specs[@]}"
}

# Narrow entry point used by `rake spec:bits`. All ordinary bit suites are run
# by scripts/test-bit-specs.sh; this file retains the two suites that need its
# specialized execution modes and result validation.
if [[ "${BIT_SPECS_ONLY:-0}" == "1" ]]; then
  run_special_bit_specs
  if [[ "$fail" -ne 0 ]]; then
    echo "test-specs: FAIL (special bit specs)"
    exit 1
  fi
  echo "test-specs: PASS (special bit specs)"
  exit 0
fi

# FAST=1: the curated inner-loop slice — the engine-parity and bignum
# pins that gate day-to-day compiler work — in parallel, skipping the
# serial tails. The full battery remains the commit gate.
if [[ "${FAST:-0}" == "1" ]]; then
  fast_compiled=(
    spec/compiler/typed_overload_spec.w
    spec/compiler/overload_exact_tag_parity_spec.w
    spec/compiler/typed_overload_hosts_spec.w
    spec/numeric/bigint_seam_disjoint_spec.w
    spec/numeric/bigint_bang_spec.w
    spec/numeric/bigint_tag_sign_spec.w
    spec/numeric/bigint_limb_sweep_spec.w
    spec/compiler/int_bigint_promotion_spec.w
    spec/compiler/bigint_mutate_unique_spec.w
    spec/compiler/devirt_method_call_spec.w
    spec/numeric/rational_spec.w
    spec/numeric/fp_math_mode_spec.w
  )
  fast_interp=(
    spec/compiler/overload_exact_tag_parity_spec.w
    spec/compiler/typed_overload_hosts_spec.w
    spec/numeric/bigint_seam_disjoint_spec.w
    spec/numeric/bigint_bang_spec.w
    spec/numeric/bigint_tag_sign_spec.w
    spec/numeric/rational_spec.w
  )
  run_parallel_launch compiled "${fast_compiled[@]}"
  run_parallel_launch interp "${fast_interp[@]}"
  wait
  run_parallel_aggregate compiled "${fast_compiled[@]}"
  run_parallel_aggregate interp "${fast_interp[@]}"
  if [[ "$fail" -ne 0 ]]; then
    echo "test-specs: FAIL (fast tier)"
    exit 1
  fi
  echo "test-specs: OK (fast tier)"
  exit 0
fi

run_parallel compiled "${compiled_specs[@]}"

run_cache_lifecycle_test

run_parallel cuda "${cuda_emit_specs[@]}"
run_parallel wgsl "${wgsl_emit_specs[@]}"
run_parallel cuda-reject "${cuda_reject_specs[@]}"

run_parallel interp "${interpreter_specs[@]}"

if [[ "${RUN_CORE_SPECS:-0}" == "1" ]]; then
  # High-bit words pin the SIGNED view encodings (as_i32/as_i64 vs as_u32):
  # a positive-only fixture decodes identically under the old unsigned
  # encodings and cannot catch a sign-extension regression.
  ruby -e 'File.binwrite("/tmp/tungsten-mmap-view-smoke.bin", [1, 2, 3, 4, 0xFFFFFFFF, 0xFFFFFFFE, 0x89ABCDEF, 0x01234567].pack("V*"))'
  run_parallel compiled "${core_specs[@]}"
else
  echo "skip core runtime specs (set RUN_CORE_SPECS=1 to run)"
fi

if [[ "${RUN_METAL_SPECS:-0}" == "1" ]]; then
  for spec in "${metal_specs[@]}"; do
    run_metal_spec "$spec"
  done
  echo "bin/tungsten gpu-bench (hardware smoke)"
  set +e
  output="$("$TUNGSTEN" gpu-bench --elements 65536 --runs 3 --warmup 1 \
    --output "$TMP_ROOT/gpu-bench.json" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]] && ! ruby -rjson -e \
      'r = JSON.parse(File.read(ARGV.fetch(0))); exit(r.dig("verification", "passed") ? 0 : 1)' \
      "$TMP_ROOT/gpu-bench.json"; then
    output="${output}${output:+$'\n'}FAIL: gpu-bench result did not verify"
    status=1
  fi
  record_result "gpu-bench" "$output" "$status"
else
  echo "skip Metal specs (set RUN_METAL_SPECS=1 to run)"
fi

if [[ "${RUN_REPL_SPECS:-0}" == "1" ]]; then
  echo "python3 spec/repl/scrub_pty_spec.py"
  set +e
  output="$(python3 spec/repl/scrub_pty_spec.py 2>&1)"
  status=$?
  set -e
  record_result "scrub_pty_spec.py" "$output" "$status"
else
  echo "skip REPL PTY spec (set RUN_REPL_SPECS=1 to run)"
fi

# Response-shape contract for the /api/run + /api/check engine
# (services/api/lib/exec.w). Opt-in because each check compiles and runs a small
# program of its own, so it is slower than a normal spec.
if [[ "${RUN_API_SPECS:-0}" == "1" ]]; then
  run_compiled_spec spec/api/api_exec_spec.w
else
  echo "skip API contract spec (set RUN_API_SPECS=1 to run)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-specs: FAIL"
  exit 1
fi

echo "test-specs: PASS"
