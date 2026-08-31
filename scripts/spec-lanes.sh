#!/usr/bin/env bash
# Spec-lane classification for tracked spec/**/*_spec.w files.
#
# Classification is separate from execution: this file can be sourced for the
# lane arrays, or executed to fail closed on an unclassified file without
# compiling. Discovery uses `git ls-files`, so uncommitted scratch specs do
# not change the suite. A newly tracked *_spec.w must be added to a named
# lane below (a default lane, an existing opt-in gate, or exclude).
#
# Usage:
#   scripts/spec-lanes.sh
#   scripts/spec-lanes.sh --files PATH...
#   scripts/spec-lanes.sh --print-default
#   scripts/spec-lanes.sh --print-lane LANE

spec_normalize_path() {
  local path="$1"
  local root="${SPEC_LANES_ROOT:-}"
  path="${path#./}"
  if [[ -n "$root" && "$path" == "$root/"* ]]; then
    path="${path#"$root"/}"
  fi
  printf '%s\n' "$path"
}

spec_discover_tracked() {
  git ls-files | awk '/^spec\/.*_spec\.w$/'
}

spec_emit_classified_paths() {
  local path
  for path in \
    "${compiled_specs[@]+"${compiled_specs[@]}"}" \
    "${compiled_reject_specs[@]+"${compiled_reject_specs[@]}"}" \
    "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" \
    "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" \
    "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" \
    "${interpreter_specs[@]+"${interpreter_specs[@]}"}" \
    "${interpreter_reject_specs[@]+"${interpreter_reject_specs[@]}"}" \
    "${core_specs[@]+"${core_specs[@]}"}" \
    "${metal_specs[@]+"${metal_specs[@]}"}" \
    "${api_specs[@]+"${api_specs[@]}"}" \
    "${exclude_specs[@]+"${exclude_specs[@]}"}"
  do
    printf '%s\n' "$path"
  done
}

spec_emit_default_spec_w() {
  local path
  for path in \
    "${compiled_specs[@]+"${compiled_specs[@]}"}" \
    "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" \
    "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" \
    "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" \
    "${interpreter_specs[@]+"${interpreter_specs[@]}"}"
  do
    case "$path" in
      spec/*_spec.w) printf '%s\n' "$path" ;;
    esac
  done
}

spec_print_lane() {
  local lane="$1"
  local path
  case "$lane" in
    compiled)
      printf '%s\n' "${compiled_specs[@]+"${compiled_specs[@]}"}" ;;
    compiled-priority)
      printf '%s\n' "${compiled_priority_specs[@]+"${compiled_priority_specs[@]}"}" ;;
    compiled-reject)
      printf '%s\n' "${compiled_reject_specs[@]+"${compiled_reject_specs[@]}"}" ;;
    cuda|cuda-emit)
      printf '%s\n' "${cuda_emit_specs[@]+"${cuda_emit_specs[@]}"}" ;;
    wgsl|wgsl-emit)
      printf '%s\n' "${wgsl_emit_specs[@]+"${wgsl_emit_specs[@]}"}" ;;
    cuda-reject)
      printf '%s\n' "${cuda_reject_specs[@]+"${cuda_reject_specs[@]}"}" ;;
    interpreter|interp)
      printf '%s\n' "${interpreter_specs[@]+"${interpreter_specs[@]}"}" ;;
    interpreter-reject|interp-reject)
      printf '%s\n' "${interpreter_reject_specs[@]+"${interpreter_reject_specs[@]}"}" ;;
    core)
      printf '%s\n' "${core_specs[@]+"${core_specs[@]}"}" ;;
    metal)
      printf '%s\n' "${metal_specs[@]+"${metal_specs[@]}"}" ;;
    api)
      printf '%s\n' "${api_specs[@]+"${api_specs[@]}"}" ;;
    wassat)
      printf '%s\n' "${wassat_specs[@]+"${wassat_specs[@]}"}" ;;
    wrat)
      printf '%s\n' "${wrat_specs[@]+"${wrat_specs[@]}"}" ;;
    exclude)
      printf '%s\n' "${exclude_specs[@]+"${exclude_specs[@]}"}" ;;
    fast-compiled)
      printf '%s\n' "${fast_compiled[@]+"${fast_compiled[@]}"}" ;;
    fast-interp)
      printf '%s\n' "${fast_interp[@]+"${fast_interp[@]}"}" ;;
    default)
      spec_emit_default_spec_w | LC_ALL=C sort -u ;;
    *)
      echo "unknown spec lane: $lane" >&2
      return 2
      ;;
  esac
}

# Classify PATH... (or tracked spec/**/*_spec.w when no paths are given).
# Prints a one-line summary on success. Unclassified paths fail closed.
spec_classify_files() {
  local tmp input classified unclassified_file path count
  tmp="${SPEC_LANES_TMP:-${TMPDIR:-/tmp}/spec-lanes-classify.$$}"
  mkdir -p "$tmp"
  input="$tmp/input"
  classified="$tmp/classified"
  unclassified_file="$tmp/unclassified"
  : >"$input"
  if [[ $# -gt 0 ]]; then
    for path in "$@"; do
      spec_normalize_path "$path"
    done >"$input"
  else
    spec_discover_tracked >"$input"
  fi
  spec_emit_classified_paths | LC_ALL=C sort -u >"$classified"
  LC_ALL=C sort -u "$input" | comm -23 - "$classified" >"$unclassified_file"
  if [[ -s "$unclassified_file" ]]; then
    echo "unclassified specs:" >&2
    sed 's/^/  /' "$unclassified_file" >&2
    echo "classify each as a default lane, an opt-in gate, or an explicit exclude" >&2
    rm -rf "$tmp"
    return 1
  fi
  count="$(grep -c . "$input" || true)"
  printf 'spec lanes: %s classified\n' "$count"
  rm -rf "$tmp"
  return 0
}

spec_classify_tracked() {
  spec_classify_files
}

spec_lanes_main() {
  case "${1:-}" in
    --files)
      shift
      spec_classify_files "$@"
      ;;
    --print-default)
      spec_print_lane default
      ;;
    --print-lane)
      shift
      spec_print_lane "${1:-}"
      ;;
    --help|-h)
      echo "Usage: spec-lanes.sh [--files PATH...] [--print-default] [--print-lane LANE]"
      ;;
    "")
      spec_classify_tracked
      ;;
    *)
      echo "Usage: spec-lanes.sh [--files PATH...] [--print-default] [--print-lane LANE]" >&2
      return 2
      ;;
  esac
}

compiled_specs=(
  compiler/test/regex_features.w
  spec/core/date_calendar_surface_spec.w
  spec/compiler/date_dynamic_receiver_spec.w
  spec/compiler/decimal_dynamic_receiver_spec.w
  spec/compiler/float_dynamic_receiver_spec.w
  spec/compiler/ast_body_native_spec.w
  spec/compiler/ast_typed_sidecar_spec.w
  spec/compiler/strip_stacktrace_metadata_spec.w
  spec/compiler/ast_typed_visitor_spec.w
  spec/compiler/array_compact_autoload_spec.w
  spec/compiler/array_constructor_parity_spec.w
  spec/compiler/array_dynamic_receiver_spec.w
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
  spec/compiler/bigint_isqrt_reopen_source_seam_spec.w
  spec/compiler/bigint_small_mut_lowering_spec.w
  spec/compiler/bigint_to_i_autoload_spec.w
  spec/compiler/block_passthrough_spec.w
  spec/compiler/block_presence_parity_spec.w
  spec/compiler/carry_intrinsics_parity_spec.w
  spec/compiler/cfg_ssa_pruning_spec.w
  spec/compiler/elementwise_fusion_spec.w
  spec/compiler/forward_typed_raw_call_spec.w
  spec/compiler/poly_ranged_sum_big_bounds_spec.w
  spec/compiler/range_immediate_spec.w
  spec/compiler/function_replacement_index_spec.w
  benchmarks/runtime_ports/float_remaining_no_use_literal.w
  spec/compiler/indexed_compound_assignment_parameter_spec.w
  spec/compiler/int_integer_dynamic_receiver_spec.w
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
  spec/compiler/lexer_lexchar_storage_spec.w
  spec/compiler/raw_int_candidate_map_spec.w
  spec/compiler/raw_machine_expression_context_spec.w
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
  spec/compiler/fused_destination_reuse_spec.w
  spec/core/pipeline_typed_array_spec.w
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
  spec/compiler/string_sso_attrs_spec.w
  spec/compiler/string_free_escape_spec.w
  spec/compiler/constructor_arity_spec.w
  spec/compiler/ctor_inline_cache_nested_spec.w
  spec/compiler/global_demotion_scopes_spec.w
  spec/compiler/strbuf_bytes_spec.w
  spec/compiler/string_buffer_dynamic_append_spec.w
  spec/compiler/string_buffer_dynamic_receiver_spec.w
  spec/compiler/quantity_control_flow_parity_spec.w
  spec/core/quantity_dispatch_spec.w
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
  spec/compiler/regex_capture_storage_spec.w
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
  spec/core/filesystem_mutation_spec.w
  spec/core/filesystem_walk_spec.w
  spec/core/clock_ms_spec.w
  spec/core/csv_stream_spec.w
  spec/core/json_parse_spec.w
  spec/core/string_to_i_bignum_spec.w
  spec/core/string_native_spec.w
  spec/core/ascii_string_spec.w
  spec/core/string_unicode_spec.w
  spec/compiler/string_scan_spec.w
  spec/core/control_flow_spec.w
  spec/core/classes_spec.w
  spec/core/arrays_hashes_spec.w
  spec/core/hash_insertion_order_spec.w
  spec/core/hash_mutation_spec.w
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
  spec/numeric/big_decimal_spec.w
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
  spec/core/date_native_spec.w
)
compiled_priority_specs=(
  spec/core/algebra_c_ab_divisors_spec.w
  spec/core/expression_solve_spec.w
  spec/core/algebra_c_ab_spec.w
  spec/core/algebra_p_adic_number_field_spec.w
  spec/core/algebra_s_units_spec.w
  spec/core/algebra_shell_width_degree12_artifact_spec.w
  spec/core/expression_spec.w
  spec/core/algebra_p_adic_dyadic_spec.w
  spec/core/algebra_s_class_group_spec.w
  spec/core/algebra_divisors_spec.w
  spec/core/algebra_ideal_arithmetic_spec.w
  spec/core/algebra_lattice_reduction_spec.w
  spec/core/algebra_prime_subspace_spec.w
  spec/core/algebra_projective_heights_spec.w
  spec/core/algebra_real_roots_spec.w
  spec/core/algebra_autoload_spec.w
  spec/core/expression_algebra_spec.w
  spec/core/algebra_shell_width_degree6_artifact_spec.w
  spec/core/algebra_shell_width_degree9_artifact_spec.w
  spec/core/algebraic_real_spec.w
  spec/core/algebra_shell_width_s_unit_artifacts_spec.w
  compiler/test/regex_features.w
  spec/compiler/strip_stacktrace_metadata_spec.w
)
compiled_reject_specs=(
  spec/compiler/date_invalid_constructor.w
  spec/compiler/decimal_invalid_constructor.w
  spec/compiler/decimal_invalid_zero_constructor.w
)
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
  compiler/test/regex_features.w
  benchmarks/runtime_ports/bigint_predicate_relaxed_autoload.w
  spec/core/date_calendar_surface_spec.w
  spec/compiler/date_dynamic_receiver_spec.w
  spec/compiler/decimal_dynamic_receiver_spec.w
  spec/compiler/float_dynamic_receiver_spec.w
  # Engine-parity pins: these compiler specs assert values that must hold
  # identically interpreted (compiled-only verification has missed clobbered
  # interpreter.w hunks before).
  spec/compiler/block_presence_parity_spec.w
  spec/compiler/array_constructor_parity_spec.w
  spec/compiler/array_dynamic_receiver_spec.w
  spec/compiler/heredoc_opaque_lexer_spec.w
  spec/compiler/method_fallthrough_parity_spec.w
  spec/compiler/int_bigint_promotion_spec.w
  spec/compiler/bigint_literal_cache_spec.w
  spec/compiler/carry_intrinsics_parity_spec.w
  spec/compiler/ivar_param_type_spec.w
  spec/compiler/llvm_name_mangling_injective_spec.w
  spec/compiler/top_level_method_name_hygiene_spec.w
  spec/compiler/string_buffer_dynamic_append_spec.w
  spec/compiler/string_buffer_dynamic_receiver_spec.w
  spec/compiler/string_dynamic_dispatch_spec.w
  spec/compiler/quantity_control_flow_parity_spec.w
  spec/core/quantity_dispatch_spec.w
  spec/compiler/static_method_block_dispatch_spec.w
  spec/compiler/static_method_overload_spec.w
  # clock_ms had to be registered in BOTH lowering.w and builtins.w; pin the
  # interpreted side so a compiled-only fix cannot pass again.
  spec/core/clock_ms_spec.w
  spec/core/csv_stream_spec.w
  spec/core/channel_spec.w
  spec/core/channel_timeout_spec.w
  spec/core/atomic_spec.w
  spec/core/mutex_spec.w
  spec/core/timer_validation_spec.w
  spec/core/future_promise_validation_spec.w
  spec/core/env_spec.w
  spec/core/integer_tower_spec.w
  spec/core/url_spec.w
  spec/core/http_spec.w
  spec/core/filesystem_walk_spec.w
  spec/core/file_stat_tempfile_spec.w
  spec/core/filesystem_mutation_spec.w
  spec/core/hash_mutation_spec.w
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
  spec/numeric/big_decimal_spec.w
  spec/numeric/rational_spec.w
  spec/interpreter/slab_decl_spec.w
  spec/interpreter/string_buffer_size_revisit_spec.w
  spec/interpreter/string_empty_native_spec.w
  spec/core/ascii_string_spec.w
  spec/core/string_unicode_spec.w
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
  spec/core/date_native_spec.w
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
interpreter_reject_specs=(
  spec/compiler/date_invalid_constructor.w
  spec/compiler/decimal_invalid_constructor.w
  spec/compiler/decimal_invalid_zero_constructor.w
)
core_specs=(
  spec/core/atomic_spec.w
  spec/core/byte_array_equality_spec.w
  spec/core/crypto_accel_spec.w
  spec/core/crypto_hmac_scram_spec.w
  spec/core/channel_spec.w
  spec/core/channel_unbuffered_spec.w
  spec/core/channel_timeout_spec.w
  spec/core/channel_timeout_thread_spec.w
  spec/core/mutex_spec.w
  spec/core/mutex_thread_spec.w
  spec/core/timer_spec.w
  spec/core/timer_validation_spec.w
  spec/core/future_promise_spec.w
  spec/core/future_promise_validation_spec.w
  spec/core/env_spec.w
  spec/core/integer_tower_spec.w
  spec/core/url_spec.w
  spec/core/http_spec.w
  spec/core/http_socket_spec.w
  spec/core/socket_repeated_connect_spec.w
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
api_specs=(
  spec/api/api_exec_spec.w
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
wrat_specs=(
  bits/tungsten-wrat/spec/checker_spec.w
)
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
exclude_specs=(
  spec/compiler/bigint_addmul_fusion_spec.w
  spec/compiler/bigint_literal_typing_spec.w
  spec/compiler/bigint_mul12_reopen_source_seam_spec.w
  spec/compiler/bigint_mul12_source_c_differential_spec.w
  spec/compiler/bigint_mul15_reopen_source_seam_spec.w
  spec/compiler/bigint_mul15_source_c_differential_spec.w
  spec/compiler/bigint_mul16_reopen_source_seam_spec.w
  spec/compiler/bigint_mul16_source_c_differential_spec.w
  spec/compiler/bigint_mul17_reopen_source_seam_spec.w
  spec/compiler/bigint_mul17_source_c_differential_spec.w
  spec/compiler/bigint_mul1_16_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_16_source_c_differential_spec.w
  spec/compiler/bigint_mul1_1_locked_direct_spec.w
  spec/compiler/bigint_mul1_1_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_24_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_24_source_c_differential_spec.w
  spec/compiler/bigint_mul1_2_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_32_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_32_source_c_differential_spec.w
  spec/compiler/bigint_mul1_3_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_40_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_40_source_c_differential_spec.w
  spec/compiler/bigint_mul1_48_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_48_source_c_differential_spec.w
  spec/compiler/bigint_mul1_4_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_5_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_64_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_64_source_c_differential_spec.w
  spec/compiler/bigint_mul1_6_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_7_reopen_source_seam_spec.w
  spec/compiler/bigint_mul1_8_reopen_source_seam_spec.w
  spec/compiler/bigint_mul21_reopen_source_seam_spec.w
  spec/compiler/bigint_mul21_source_c_differential_spec.w
  spec/compiler/bigint_mul24_reopen_source_seam_spec.w
  spec/compiler/bigint_mul24_source_c_differential_spec.w
  spec/compiler/bigint_mul2_reopen_source_seam_spec.w
  spec/compiler/bigint_mul2_source_c_differential_spec.w
  spec/compiler/bigint_mul3_reopen_source_seam_spec.w
  spec/compiler/bigint_mul3_source_c_differential_spec.w
  spec/compiler/bigint_mul4_reopen_source_seam_spec.w
  spec/compiler/bigint_mul4_source_c_differential_spec.w
  spec/compiler/bigint_mul5_reopen_source_seam_spec.w
  spec/compiler/bigint_mul5_source_c_differential_spec.w
  spec/compiler/bigint_mul6_reopen_source_seam_spec.w
  spec/compiler/bigint_mul6_source_c_differential_spec.w
  spec/compiler/bigint_mul7_reopen_source_seam_spec.w
  spec/compiler/bigint_mul7_source_c_differential_spec.w
  spec/compiler/bigint_mul8_reopen_source_seam_spec.w
  spec/compiler/bigint_mul8_source_c_differential_spec.w
  spec/compiler/bigint_mul_locked_direct_spec.w
  spec/compiler/bigint_mutate_grow_spec.w
  spec/compiler/bigint_pow2_lowering_spec.w
  spec/compiler/bigint_reopen_default_dispatch_spec.w
  spec/compiler/bigint_signature_type_fact_spec.w
  spec/compiler/bigint_sqr16_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr16_source_c_differential_spec.w
  spec/compiler/bigint_sqr1_1_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr2_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr3_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr3_source_c_differential_spec.w
  spec/compiler/bigint_sqr4_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr4_source_c_differential_spec.w
  spec/compiler/bigint_sqr5_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr5_source_c_differential_spec.w
  spec/compiler/bigint_sqr6_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr6_source_c_differential_spec.w
  spec/compiler/bigint_sqr7_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr7_source_c_differential_spec.w
  spec/compiler/bigint_sqr8_reopen_source_seam_spec.w
  spec/compiler/bigint_sqr8_source_c_differential_spec.w
  spec/compiler/bigint_sub1_1_reopen_source_seam_spec.w
  spec/compiler/bigint_sub1_2_reopen_source_seam_spec.w
  spec/compiler/bigint_word_dest_matrix_spec.w
  spec/compiler/bigint_word_dest_spec.w
  spec/compiler/bigint_zero_compare_spec.w
  spec/compiler/content_hash_value_encoding_spec.w
  spec/compiler/dotted_no_arg_postfix_index_spec.w
  spec/compiler/embedded_class_kernel_spec.w
  spec/compiler/embedded_ll_asm_spec.w
  spec/compiler/fast_setjmp_emitter_spec.w
  spec/compiler/go_concurrency_spec.w
  spec/compiler/gpu_spirv_emit_spec.w
  spec/compiler/int_pair_tag_emitter_spec.w
  spec/compiler/interpreter_w_u64_spec.w
  spec/compiler/lexer_long_token_spec.w
  spec/compiler/lexer_type_map_direct_spec.w
  spec/compiler/magic_dir_absolute_spec.w
  spec/compiler/mmap_wrapper_bigarray_result_autoload_spec.w
  spec/compiler/mmap_wrapper_no_use_byte_at_spec.w
  spec/compiler/mmap_wrapper_no_use_close_spec.w
  spec/compiler/mmap_wrapper_no_use_factory_spec.w
  spec/compiler/mmap_wrapper_no_use_file_spec.w
  spec/compiler/mmap_wrapper_no_use_idx_spec.w
  spec/compiler/mmap_wrapper_no_use_native_spec.w
  spec/compiler/mmap_wrapper_no_use_view_at_spec.w
  spec/compiler/namespaced_bit_submodule_spec.w
  spec/compiler/nested_type_ascription_spec.w
  spec/compiler/no_space_identifier_division_spec.w
  spec/compiler/parser_at_type_direct_spec.w
  spec/compiler/source_argc1_exact_ivar_soundness_spec.w
  spec/compiler/source_argc1_namespaced_reopen_spec.w
  spec/compiler/string_length_no_use_rope_spec.w
  spec/compiler/string_length_symbol_proc_count_no_use_spec.w
  spec/compiler/string_length_symbol_proc_map_no_use_spec.w
  spec/compiler/string_length_symbol_proc_reject_no_use_spec.w
  spec/compiler/string_length_symbol_proc_select_no_use_spec.w
  spec/compiler/string_size_no_use_native_spec.w
  spec/compiler/string_size_symbol_proc_count_no_use_spec.w
  spec/compiler/string_size_symbol_proc_map_no_use_spec.w
  spec/compiler/string_size_symbol_proc_reject_no_use_spec.w
  spec/compiler/string_size_symbol_proc_select_no_use_spec.w
  spec/compiler/string_slice_direct_spec.w
  spec/compiler/string_symbol_class_identity_spec.w
  spec/compiler/symbol_length_no_use_native_spec.w
  spec/compiler/symbol_size_no_use_native_spec.w
  spec/compiler/typed_array_only_raw_call_spec.w
  spec/compiler/view_field_store_spec.w
  spec/core/algebra_arithmetic_circuit_spec.w
  spec/core/algebra_automorphisms_spec.w
  spec/core/algebra_cayley_octads_spec.w
  spec/core/algebra_descent_spec.w
  spec/core/algebra_divided_power_spec.w
  spec/core/algebra_eigenpackets_spec.w
  spec/core/algebra_elliptic_arithmetic_spec.w
  spec/core/algebra_engine_spec.w
  spec/core/algebra_etale_algebra_spec.w
  spec/core/algebra_f2_linear_spec.w
  spec/core/algebra_finite_factor_spec.w
  spec/core/algebra_polynomial_factor_multivariate_spec.w
  spec/core/algebra_finite_field_spec.w
  spec/core/algebra_frey_spec.w
  spec/core/algebra_galois_spec.w
  spec/core/algebra_geometry_spec.w
  spec/core/algebra_groebner_certificate_spec.w
  spec/core/algebra_groebner_length_spec.w
  spec/core/algebra_groebner_spec.w
  spec/core/algebra_hecke_spec.w
  spec/core/algebra_lattice_polytope_spec.w
  spec/core/algebra_local_geometry_spec.w
  spec/core/algebra_local_intersection_spec.w
  spec/core/algebra_local_invariants_spec.w
  spec/core/algebra_local_normalization_spec.w
  spec/core/algebra_local_singularity_spec.w
  spec/core/algebra_maximal_orders_spec.w
  spec/core/algebra_modular_forms_spec.w
  spec/core/algebra_modular_symbols_spec.w
  spec/core/algebra_newforms_spec.w
  spec/core/algebra_number_field_spec.w
  spec/core/algebra_number_field_tower_spec.w
  spec/core/algebra_old_new_spec.w
  spec/core/algebra_orders_spec.w
  spec/core/algebra_p_adic_geometry_spec.w
  spec/core/algebra_p_adic_spec.w
  spec/core/algebra_parity_lattice_spec.w
  spec/core/algebra_permutation_groups_spec.w
  spec/core/algebra_point_search_spec.w
  spec/core/algebra_polynomial_resultant_multivariate_spec.w
  spec/core/algebra_polynomial_gcd_modular_spec.w
  spec/core/algebra_polynomial_matrix_spec.w
  spec/core/algebra_polynomial_specialize_spec.w
  spec/core/algebra_polynomial_spec.w
  spec/core/algebra_prime_ideals_spec.w
  spec/core/algebra_projective_spec.w
  spec/core/algebra_q_expansion_spec.w
  spec/core/algebra_quartic_invariants_spec.w
  spec/core/algebra_quartics_spec.w
  spec/core/algebra_relative_irreducibility_spec.w
  spec/core/algebra_residue_algebra_spec.w
  spec/core/algebra_rewrite_spec.w
  spec/core/algebra_shell_width_quartic_spec.w
  spec/core/algebra_simple_extension_spec.w
  spec/core/algebra_spec.w
  spec/core/algebra_tate_spec.w
  spec/core/algebra_theta_actions_spec.w
  spec/core/algebra_theta_fibers_spec.w
  spec/core/algebra_theta_galois_spec.w
  spec/core/algebra_theta_spec.w
  spec/core/algebra_theta_subdegrees_spec.w
  spec/core/algebra_toric_polytope_spec.w
  spec/core/algebra_zeta_spec.w
  spec/core/array_sort_order_spec.w
  spec/core/autodiff_spec.w
  spec/core/block_destructure_spec.w
  spec/core/calculus_certified_transcendentals_spec.w
  spec/core/calculus_laurent_spec.w
  spec/core/calculus_puiseux_spec.w
  spec/core/calculus_radial_mellin_spec.w
  spec/core/combinatorics_spec.w
  spec/core/decimal_array_spec.w
  spec/core/decimal_ordering_spec.w
  spec/core/digest64_spec.w
  spec/core/doc_taught_surface_spec.w
  spec/core/dynamics_spec.w
  spec/core/expression_exact_division_spec.w
  spec/core/expression_gamma_spec.w
  spec/core/f16_array_native_spec.w
  spec/core/f16_array_spec.w
  spec/core/gaussian_integer_spec.w
  spec/core/geometry_flat_torus_spec.w
  spec/core/geometry_measure_spec.w
  spec/core/geometry_spec.w
  spec/core/geometry_warped_cone_spec.w
  spec/core/gsub_replacement_spec.w
  spec/core/http_tls_socket_spec.w
  spec/core/increment_assign_spec.w
  spec/core/lattice_geometry_spec.w
  spec/core/location_range_mode11_spec.w
  spec/core/manuscript_math_autoload_spec.w
  spec/core/math_constants_spec.w
  spec/core/math_expm1_log1p_spec.w
  spec/core/math_globals_spec.w
  spec/core/math_native_intrinsics_spec.w
  spec/core/matrix_add_mut_spec.w
  spec/core/metal_atomic_spec.w
  spec/core/metal_i64_buffer_spec.w
  spec/core/metal_metallib_spec.w
  spec/core/metal_mmap_buffer_spec.w
  spec/core/physics_spec.w
  spec/core/plus_type_error_spec.w
  spec/core/polygon_lattice_spec.w
  spec/core/polyomino_spec.w
  spec/core/proof_artifact_spec.w
  spec/core/puiseux_autoload_spec.w
  spec/core/quantum_spec.w
  spec/core/relativity_geometry_spec.w
  spec/core/scientific_surface_spec.w
  spec/core/simd_vector_wvalue_spec.w
  spec/core/smith_eisenstein_spec.w
  spec/core/sockaddr_wvalue_spec.w
  spec/core/solve_dp45_spec.w
  spec/core/solve_native_spec.w
  spec/core/special_transcendentals_spec.w
  spec/core/tensor_add_mut_spec.w
  spec/core/thread_loop_capture_spec.w
  spec/core/thread_string_slab_spec.w
  spec/core/typed_array_annotation_spec.w
  spec/interpreter/method_overload_spec.w
  spec/interpreter/mmap_wrapper_revisit_spec.w
  spec/interpreter/plus_type_error_spec.w
  spec/interpreter/range_block_fastpath_spec.w
  spec/interpreter/string_length_revisit_spec.w
  spec/numeric/approx_eq_spec.w
  spec/numeric/bigint_add1_1_source_spec.w
  spec/numeric/bigint_add1_2_source_spec.w
  spec/numeric/bigint_add1_4_source_spec.w
  spec/numeric/bigint_add1_5_source_spec.w
  spec/numeric/bigint_add1_6_source_spec.w
  spec/numeric/bigint_add1_7_source_spec.w
  spec/numeric/bigint_add1_8_source_spec.w
  spec/numeric/bigint_add1_source_spec.w
  spec/numeric/bigint_add1_wide_source_spec.w
  spec/numeric/bigint_bitwise_spec.w
  spec/numeric/bigint_divmod_spec.w
  spec/numeric/bigint_identity_spec.w
  spec/numeric/bigint_limb_index_spec.w
  spec/numeric/bigint_mul12_source_spec.w
  spec/numeric/bigint_mul15_source_spec.w
  spec/numeric/bigint_mul16_source_spec.w
  spec/numeric/bigint_mul17_source_spec.w
  spec/numeric/bigint_mul1_16_source_spec.w
  spec/numeric/bigint_mul1_1_source_spec.w
  spec/numeric/bigint_mul1_24_source_spec.w
  spec/numeric/bigint_mul1_2_source_spec.w
  spec/numeric/bigint_mul1_32_source_spec.w
  spec/numeric/bigint_mul1_3_source_spec.w
  spec/numeric/bigint_mul1_40_source_spec.w
  spec/numeric/bigint_mul1_48_source_spec.w
  spec/numeric/bigint_mul1_4_source_spec.w
  spec/numeric/bigint_mul1_5_source_spec.w
  spec/numeric/bigint_mul1_64_source_spec.w
  spec/numeric/bigint_mul1_6_source_spec.w
  spec/numeric/bigint_mul1_7_source_spec.w
  spec/numeric/bigint_mul1_8_source_spec.w
  spec/numeric/bigint_mul21_source_spec.w
  spec/numeric/bigint_mul24_source_spec.w
  spec/numeric/bigint_mul2_source_spec.w
  spec/numeric/bigint_mul3_source_spec.w
  spec/numeric/bigint_mul4_source_spec.w
  spec/numeric/bigint_mul5_source_spec.w
  spec/numeric/bigint_mul6_source_spec.w
  spec/numeric/bigint_mul7_source_spec.w
  spec/numeric/bigint_mul8_source_spec.w
  spec/numeric/bigint_powmod_spec.w
  spec/numeric/bigint_prime_spec.w
  spec/numeric/bigint_shift_source_spec.w
  spec/numeric/bigint_sqr16_source_spec.w
  spec/numeric/bigint_sqr1_1_source_spec.w
  spec/numeric/bigint_sqr2_source_spec.w
  spec/numeric/bigint_sqr3_source_spec.w
  spec/numeric/bigint_sqr4_source_spec.w
  spec/numeric/bigint_sqr5_source_spec.w
  spec/numeric/bigint_sqr6_source_spec.w
  spec/numeric/bigint_sqr7_source_spec.w
  spec/numeric/bigint_sqr8_source_spec.w
  spec/numeric/bigint_sub1_1_source_spec.w
  spec/numeric/bigint_sub1_2_source_spec.w
  spec/numeric/bigint_sub1_3_source_spec.w
  spec/numeric/bigint_sub1_4_source_spec.w
  spec/numeric/bigint_sub1_5_source_spec.w
  spec/numeric/bigint_sub1_6_source_spec.w
  spec/numeric/bigint_sub1_7_source_spec.w
  spec/numeric/bigint_sub1_8_source_spec.w
  spec/numeric/bigint_sub1_wide_source_spec.w
  spec/numeric/bigint_succ_prev_spec.w
  spec/numeric/bigint_thread_isolation_spec.w
  spec/numeric/bigint_to_f_spec.w
  spec/numeric/bigint_to_s_spec.w
  spec/numeric/complex_array_spec.w
  spec/numeric/complex_scalar_spec.w
  spec/numeric/exact_equality_spec.w
  spec/numeric/integer_factorization_spec.w
  spec/numeric/pi_quantity_spec.w
  spec/sci/formats_spec.w
  spec/sci/io_native_spec.w
  spec/sci/smoke_spec.w
  spec/sci/sparse_accel_spec.w
  spec/sci/sparse_solve_spec.w
  spec/sci/tensor_cpu_spec.w
  spec/sci/tensor_unit_spec.w
  spec/sci/wtensor_slice_spec.w
  spec/sci/wtensor_spec.w
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  SPEC_LANES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$SPEC_LANES_ROOT"
  spec_lanes_main "$@"
fi
