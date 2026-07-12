# Lowering / types — pure type predicates, dispatch keys, and lookup
# tables. Depends on `pass_registry.w`. Imports no other lowering
# worker modules.
#
# This file deliberately has no `use` directives: from
# `compiler/lib/lowering/`, `use wire` would resolve to
# `compiler/lib/lowering/wire.w` rather than the real file. All names
# referenced here live in the flat top-level namespace once
# lowering.w's worker imports are merged.

# ccall_nobox helpers that return an already-boxed WValue (slab node
# handles, slot loads, sparse-store reads) rather than a raw machine int.
# Two consumers must agree on this list:
#   - lower_call's ccall_nobox result typing (lowering/calls.w): tagging
#     these :raw_int would have downstream storage nanbox the result,
#     clobbering the tag bits (the 0xFFFA trap).
#   - infer_type's ccall_nobox branch (lowering.w): typing these :i64
#     poisons fn return inference for any function whose tail expression
#     is one of these calls — ast_get's sparse tail made every
#     `ast_get(...).each` chain lower as a machine-int receiver and
#     corrupt the WValue.
-> ccall_nobox_returns_wvalue?(fn_name)
  fn_name in ("w_node_alloc" "w_node_field_load" "w_node_singleton" "w_ast_bool_cached" "w_node_inline_payload" "w_make_token_extern" "w_location_file" "w_location_file_offset" "w_ast_sparse_set" "w_ast_sparse_get" "w_ast_sparse_copy" "w_ast_intern_node" "w_ast_intern_str_of" "w_ast_freeze_if_array" "w_body_arena_get")

# -- Operator maps --

-> init_op_map
  m = {}

  m[:PLUS]      = "w_add"
  m[:MINUS]     = "w_sub"
  m[:STAR]      = "w_mul"
  m[:POW]       = "w_pow"
  m[:SLASH]     = "w_div"
  m[:PERCENT]   = "w_mod"
  m[:EQ]        = "w_eq"
  m[:NEQ]       = "w_neq"
  m[:MATCH]     = "w_regex_match"
  m[:LT]        = "w_lt"
  m[:GT]        = "w_gt"
  m[:LTE]       = "w_lte"
  m[:GTE]       = "w_gte"
  m[:AMPERSAND] = "w_bit_and"
  m[:PIPE]      = "w_bit_or"
  m[:CARET]     = "w_bit_xor"
  m[:LSHIFT]    = "w_bit_shl"
  m[:RSHIFT]    = "w_bit_shr"
  m

builtin_runtime_classes = ["Socket", "Response", "TLS", "StringBuffer", "StandardError", "Tungsten:AST:Node"]
-> type_dispatch_key(class_name)
  case class_name
    "Atomic"        => 0x01 # Phase 6i.2: promoted to W_SUBTAG_ATOMIC
    "Hash"          => 0x05
    "Closure"       => 0x06
    "Regex"         => 0x07
    "Range"         => 0x08
    "Array"         => 0x0A
    "StringBuffer"  => 0x0B # Phase 6i.2: promoted to W_SUBTAG_STRBUF
    "Class"         => 0x0C
    "UUID"          => 0x0D
    # Phase 4f: TypedArray collapsed into Array (single subtag 0x0A); the
    # tier is now distinguished by the `ebits` byte, not the subtag.
    "TypedArray"    => 0x0A
    "ByteArray"     => 0x0A # Phase 6i.1: ByteArray is WArray<u8>
    "BoolArray"     => 0x0A # Phase 6i.1b: BoolArray is WArray<u1>
    "BigArray"      => 0x92 # Phase 3: 0x80 | W_TYPE_BIG_ARRAY (18)
    "SmallArray"    => 0x09 # Phase 6h: own subtag (W_SUBTAG_SMALL_ARRAY); no type byte
    "BigInt"        => 0x8B # Phase 6i.2: 0x80 | W_TYPE_BIGINT (11)
    "Error"         => 0x93 # Phase 6i.2: 0x80 | W_TYPE_ERROR (19)
    "IPv6"          => 0x86 # Phase 6i.2: 0x80 | W_TYPE_IPV6 (6)
    "Mac"           => 0x85 # Phase 6i.2: 0x80 | W_TYPE_MAC (5)
    "Encoded"       => 0x88 # Phase 6i.2: 0x80 | W_TYPE_ENCODED (8)
    "Float"         => 0xFF
    "String"        => 0xF9
    "Integer"       => 0xFA
    "Instant"       => 0xFB
    # W_TAG_CHAR subtypes — runtime's w_dispatch_key returns 0xD0|subtype
    # when v >> 48 == 0xFFFC so each lexical kind can register its own
    # class. The Token + Slice slots back the source-driven AST migration;
    # LexChar remains free for an explicit class binding later.
    "Token"          => 0xD0
    "Char"           => 0xD3
    # W_PACKED subtypes — runtime's w_dispatch_key returns 0xE0|subtype
    # when v >> 48 == 0xFFFE so each packed kind can register its own class.
    "Tungsten:AST:Node"      => 0xE3
    "Date"          => 0xE4
    "IPv4"          => 0xE5
    "Tungsten:AST:Body"      => 0xE6
    "MAC"           => 0x85
    "Mac"           => 0x85
    => nil

-> mark_builtin_class_used(mod, name)
  builtin_names = mod[:builtin_class_names]
  if builtin_names == nil || builtin_names[name] != true
    return false

  existing = mod[:known_classes][name]
  # A user-declared class (AST class_def node) takes precedence: don't
  # mark this name as a builtin if the user already declared it.
  if is_ast_node?(existing)
    return false
  if existing != nil && existing[:builtin] != true
    return false

  mod[:used_builtin_classes][name] = true
  if existing == nil
    mod[:known_classes][name] = {name: name, body: nil, superclass: nil, builtin: true}
  true

# Names that we treat as impure (allocators, syscalls, mutators) when
# they appear as the first arg of a `ccall(...)`. Memoization-suppression
# uses this so a fn whose body is just a ccall to one of these doesn't
# get registered as pure (which would alias every call to the same
# cached return value — see Metal dispatch_n smoke).
-> init_known_impure_ccall_targets
  # IMPORTANT: this list is consulted by fn_body_calls_impure_ccall?
  # to decide whether a `fn` whose body is `ccall(...)` may be memoized.
  # If a ccall is NOT listed here, the compiler treats it as pure and
  # caches the result across identical-argument calls. That cache-collapse
  # silently aliases independent allocations to the same memory.
  #
  # Allowlist-by-mistake-of-omission: 2026-06-05 incident — `w_array_new_aligned`
  # wasn't listed, so `fn f64_array(n) = ccall("w_array_new_aligned", -64, n)`
  # got memoized; two callers of f64_array(N) received the SAME pointer.
  #
  # Architectural follow-up: switch this from deny-list to allowlist,
  # i.e. only known-pure ccalls (like `w_str_concat`) are eligible for
  # memoization; everything else (allocators, IO, mutations, anything
  # that creates an Obj-C object, anything that returns a fresh resource)
  # is impure by default. Pending compiler refactor.
  m = {}
  # ---- typed-array allocators / wrappers ----
  m["w_array_new_aligned"] = true       # mmap-backed allocator
  m["w_array_new"] = true                # bumps an arena
  m["w_ipv6_storage_clone"] = true       # allocates a WNetAddr clone
  m["w_ipv6_storage_from_words"] = true  # allocates a WNetAddr from four u32 words
  m["w_array_view_raw"] = true           # builds a new view wrapper
  m["w_array_as_metal_buffer"] = true    # creates an MTLBuffer wrap

  # ---- BLAS / LAPACK / FFT bridges (write to caller's C buffer) ----
  m["w_blas_sgemm_nn"] = true
  m["w_blas_dgemm_nn"] = true
  m["w_blas_dgesv"] = true
  m["w_blas_dpotrf"] = true
  m["w_blas_fft_f32"] = true
  m["w_blas_sum_f32"] = true
  m["w_blas_dot_f32"] = true
  m["w_blas_sumsq_f32"] = true
  m["w_blas_vsin_f32"] = true
  m["w_blas_vcos_f32"] = true
  m["w_blas_vexp_f32"] = true
  m["w_blas_vtanh_f32"] = true
  m["w_blas_vlog_f32"] = true
  m["w_blas_vsqrt_f32"] = true
  m["w_blas_saxpy"] = true
  m["w_blas_sgemv_n"] = true
  m["w_blas_vadd_f32"] = true
  m["w_blas_vmul_f32"] = true
  m["w_blas_vsmul_f32"] = true
  m["w_blas_vfill_f32"] = true
  m["w_mat4_mul_f32"] = true
  m["w_vec4_add_f32"] = true
  m["w_vec4_mul_f32"] = true
  m["w_vec4_dot_f32"] = true

  m["w_sparse_spmv_f32"] = true
  m["w_sparse_solve_qr_f64"] = true
  m["w_sparse_solve_chol_f64"] = true

  m["w_sci_fits_f32_be"] = true
  m["w_sci_mat_level5_ok"] = true
  m["w_sci_hdf5_superblock"] = true
  m["w_sci_hdf5_write_f32_1d"] = true
  m["w_sci_hdf5_read_f32_1d"] = true
  m["w_sci_netcdf_write_f32_1d"] = true
  m["w_sci_netcdf_read_f32_1d"] = true
  m["w_sci_zarr_read_f32_1d"] = true
  m["w_sci_zarr_write_f32_1d"] = true
  m["w_sci_parquet_read_f32"] = true
  m["w_sci_parquet_write_f32"] = true
  m["w_sci_hdf5_read_named"] = true
  m["w_sci_hdf5_list"] = true
  m["w_sci_hdf5_write_datasets"] = true
  m["w_tensor_zeros_f32"] = true
  m["w_tensor_at_f32"] = true
  m["w_tensor_set_f32"] = true
  m["w_tensor_shape"] = true
  m["w_tensor_rank"] = true
  m["w_tensor_view_f32"] = true
  m["w_tensor_slice0_f32"] = true

  # ---- CUDA host bridge ----
  m["w_cuda_available"] = true
  m["w_cuda_device_count"] = true
  m["w_cuda_malloc"] = true
  m["w_cuda_free"] = true
  m["w_cuda_memcpy_h2d"] = true
  m["w_cuda_memcpy_d2h"] = true
  m["w_cuda_synchronize"] = true
  m["w_cuda_device_name"] = true
  m["w_cuda_launch"] = true

  # ---- MLX bridges (graph nodes / GPU dispatches with side effects) ----
  m["w_mlx_sgemm_nn"] = true
  m["w_mlx_sgemm_nn_no_readback"] = true
  m["w_mlx_sgemm_batch"] = true
  m["w_mlx_dgemm_nn"] = true
  m["w_mlx_hgemm_nn"] = true
  m["w_mlx_bgemm_nn"] = true
  m["w_f32_to_bf16_array"] = true
  m["w_mlxb_load_safetensors"] = true
  m["w_mlxb_quantized_matmul_nvfp4"] = true
  m["w_mlxb_tensor_count"] = true
  m["w_mlx_add_f32"] = true
  m["w_mlx_mul_f32"] = true
  m["w_mlx_sub_f32"] = true
  m["w_mlx_div_f32"] = true
  m["w_mlx_exp_f32"] = true
  m["w_mlx_log_f32"] = true
  m["w_mlx_sqrt_f32"] = true
  m["w_mlx_tanh_f32"] = true
  m["w_mlx_sum_f32"] = true
  m["w_mlx_max_f32"] = true
  m["w_mlx_softmax_rows_f32"] = true
  m["w_mlx_fft_f32"] = true
  m["w_mlx_random_uniform_f32"] = true
  m["w_mlx_random_normal_f32"] = true
  m["w_mlx_eval"] = true
  m["w_mlx_compile_begin"] = true
  m["w_mlx_compile_end"] = true

  # ---- MPS / MPSGraph bridges ----
  m["w_mps_sgemm_nn"] = true
  m["w_mps_sgemm_batch"] = true
  m["w_mpsg_sgemm_nn"] = true
  m["w_mpsg_sgemm_batch"] = true

  # ---- Metal compute bridge ----
  m["w_metal_device_default"] = true
  m["w_metal_buffer_new"] = true
  m["w_metal_buffer_length"] = true
  m["w_metal_buffer_write_f32"] = true
  m["w_metal_buffer_write_i32"] = true
  m["w_metal_buffer_write_f16"] = true
  m["w_metal_buffer_read_f32"] = true
  m["w_metal_buffer_read_i32"] = true
  m["w_metal_buffer_read_f16"] = true
  m["w_metal_compile_source"] = true
  m["w_metal_compile_source_opts"] = true
  m["w_metal_pipeline_for"] = true
  m["w_metal_queue_new"] = true
  m["w_metal_dispatch1"] = true
  m["w_metal_dispatch_n"] = true
  m["w_metal_dispatch_groups"] = true
  m["w_metal_batch_begin"] = true
  m["w_metal_batch_commit"] = true
  m["w_metal_batch_commit_ms"] = true
  m["w_metal_batch_commit_async"] = true
  m["w_metal_command_buffer_wait"] = true
  m["w_metal_batch_begin_concurrent"] = true
  m["w_metal_batch_barrier"] = true
  m["w_metal_set_threadgroup_memory"] = true
  m["w_metal_pipeline_for_with_int_constants"] = true
  m["w_metal_binary_archive_new"] = true
  m["w_metal_batch_barrier_resources"] = true
  m["w_metal_buffer_write_from_mmap"] = true

  # ---- Crypto / UUID helpers that allocate mutable data or use entropy/time ----
  m["w_crypto_random_bytes"] = true
  m["w_crypto_md5_bytes"] = true
  m["w_crypto_sha1_bytes"] = true
  m["w_crypto_sha224_bytes"] = true
  m["w_crypto_sha256_bytes"] = true
  m["w_crypto_sha384_bytes"] = true
  m["w_crypto_sha512_bytes"] = true
  m["w_crypto_sha512_224_bytes"] = true
  m["w_crypto_sha512_256_bytes"] = true
  m["w_uuid_bytes"] = true
  m["w_uuid_v1"] = true
  m["w_uuid_v2"] = true
  m["w_uuid_v4"] = true
  m["w_uuid_v6"] = true
  m["w_uuid_v7"] = true
  m["w_uuid_v8"] = true

  m["w_q8_split_blocks"] = true
  m["w_q8_dequant_row"] = true
  m

known_impure_ccall_targets = init_known_impure_ccall_targets()

-> is_known_impure_ccall_target?(name)
  known_impure_ccall_targets[name] == true

-> fn_body_calls_impure_ccall?(node)
  if node == nil
    return false
  node_type = type(node)
  if node_type == "Array"
    i = 0
    while i < node.size()
      if fn_body_calls_impure_ccall?(node[i])
        return true
      i += 1
    return false
  # Slab-AST nodes report type() == "Unknown", not "Hash" — the legacy
  # `type(node) != "Hash"` guard here silently rejected every node post-slab
  # migration, making this whole impure-ccall detection a no-op (so impure
  # `fn` wrappers like metal_buffer_read_f32 got memoized → stale reads). Use
  # the canonical node test instead.
  if !is_ast_node?(node)
    return false

  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    return fn_body_calls_impure_ccall?(node[:body])

  case t
  when :call
    if node.name == "ccall" && node.args != nil && node.args.size() >= 1
      target = node.args[0]
      if target != nil && ast_kind(target) == :string && is_known_impure_ccall_target?(target.value)
        return true
    if fn_body_calls_impure_ccall?(node.receiver)
      return true
    if fn_body_calls_impure_ccall?(node.args)
      return true
    if fn_body_calls_impure_ccall?(node.block)
      return true

  when :program
    return fn_body_calls_impure_ccall?(node.expressions)

  when :array
    return fn_body_calls_impure_ccall?(node.elements)

  when :hash_literal
    return fn_body_calls_impure_ccall?(node.entries)

  when :string_interp, :byte_array_interp
    return fn_body_calls_impure_ccall?(node.parts)

  when :typed_array_new, :typed_array, :view_access
    return fn_body_calls_impure_ccall?(node.size) || fn_body_calls_impure_ccall?(node.index)

  when :assign, :compound_assign
    return fn_body_calls_impure_ccall?(node.target) || fn_body_calls_impure_ccall?(node.value)

  when :multi_assign
    return fn_body_calls_impure_ccall?(node.targets) || fn_body_calls_impure_ccall?(node.value)

  when :binary_op, :and, :or, :target_and, :target_or
    return fn_body_calls_impure_ccall?(node.left) || fn_body_calls_impure_ccall?(node.right)

  when :unary_op, :not
    return fn_body_calls_impure_ccall?(node.operand)

  when :target_not
    return fn_body_calls_impure_ccall?(node.expression)

  when :in_test
    return fn_body_calls_impure_ccall?(node.lhs) || fn_body_calls_impure_ccall?(node.elements)

  when :passthrough
    return fn_body_calls_impure_ccall?(node.expression) || fn_body_calls_impure_ccall?(node.value)

  when :range
    return fn_body_calls_impure_ccall?(node.from) || fn_body_calls_impure_ccall?(node.to)

  when :if
    if fn_body_calls_impure_ccall?(node.condition)
      return true
    if fn_body_calls_impure_ccall?(node.then_body)
      return true
    if fn_body_calls_impure_ccall?(node.elsif_clauses)
      return true
    return fn_body_calls_impure_ccall?(node.else_body)

  when :while
    return fn_body_calls_impure_ccall?(node.condition) || fn_body_calls_impure_ccall?(node.body)

  when :with, :parallel_with
    return fn_body_calls_impure_ccall?(node.bindings) || fn_body_calls_impure_ccall?(node.body)

  when :case
    return fn_body_calls_impure_ccall?(node.whens) || fn_body_calls_impure_ccall?(node.else_body)

  when :when
    return fn_body_calls_impure_ccall?(node.conditions) || fn_body_calls_impure_ccall?(node.body)

  when :case_value
    if fn_body_calls_impure_ccall?(node.subject)
      return true
    if fn_body_calls_impure_ccall?(node.arms)
      return true
    return fn_body_calls_impure_ccall?(node.else_body)

  when :case_arm
    if fn_body_calls_impure_ccall?(node.pattern)
      return true
    if fn_body_calls_impure_ccall?(node.guard)
      return true
    return fn_body_calls_impure_ccall?(node.body)

  when :safe_nav
    if fn_body_calls_impure_ccall?(node.receiver)
      return true
    if fn_body_calls_impure_ccall?(node.args)
      return true
    return fn_body_calls_impure_ccall?(node.block)

  when :rescue_expr
    return fn_body_calls_impure_ccall?(node.body) || fn_body_calls_impure_ccall?(node.fallback)

  when :puts
    vals = node.value
    i = 0
    while i < vals.size()
      if fn_body_calls_impure_ccall?(vals[i])
        return true
      i += 1
    return false

  when :return, :print, :raise, :recase
    return fn_body_calls_impure_ccall?(node.value)

  when :class_def, :module_def, :trait_def
    return fn_body_calls_impure_ccall?(node.superclass) || fn_body_calls_impure_ccall?(node.body)

  when :method_def, :fn_def, :gpu_kernel_def
    return fn_body_calls_impure_ccall?(node.params) || fn_body_calls_impure_ccall?(node.body)

  when :param
    return fn_body_calls_impure_ccall?(node.default)

  when :block
    return fn_body_calls_impure_ccall?(node.params) || fn_body_calls_impure_ccall?(node.body)

  when :begin
    if fn_body_calls_impure_ccall?(node.body)
      return true
    if fn_body_calls_impure_ccall?(node.rescue_body)
      return true
    return fn_body_calls_impure_ccall?(node.ensure_body)

  when :yield, :super
    return fn_body_calls_impure_ccall?(node.args)

  when :go
    return fn_body_calls_impure_ccall?(node.body)

  when :schedule_def, :layout_def
    return fn_body_calls_impure_ccall?(node.directives)

  when :on_guard
    return fn_body_calls_impure_ccall?(node.predicate) || fn_body_calls_impure_ccall?(node.body)

  when :regex_match
    return fn_body_calls_impure_ccall?(node.regex) || fn_body_calls_impure_ccall?(node.subject)

  when :cidr_match
    return fn_body_calls_impure_ccall?(node.subject) || fn_body_calls_impure_ccall?(node.cidr)

  else
    false
  false

-> ast_uses_argv(node)
  if node == nil
    return false

  node_type = type(node)
  if node_type == "Array"
    i = 0
    while i < node.size()
      if ast_uses_argv(node[i])
        return true
      i += 1
    return false

  if !is_ast_node?(node)
    return false

  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    return ast_uses_argv(node[:body])

  case t
  when :var
    node.name == "ARGV"

  when :call
    if node.receiver == nil && node.name == "argv"
      return true
    if ast_uses_argv(node.receiver)
      return true
    if ast_uses_argv(node.args)
      return true
    ast_uses_argv(node.block)

  when :program
    ast_uses_argv(node.expressions)

  when :array
    ast_uses_argv(node.elements)

  when :hash_literal
    ast_uses_argv(node.entries)

  when :string_interp, :byte_array_interp
    ast_uses_argv(node.parts)

  when :typed_array_new, :typed_array, :view_access
    ast_uses_argv(node.size) || ast_uses_argv(node.index)

  when :assign, :compound_assign
    ast_uses_argv(node.target) || ast_uses_argv(node.value)

  when :multi_assign
    ast_uses_argv(node.targets) || ast_uses_argv(node.value)

  when :binary_op, :and, :or, :target_and, :target_or
    ast_uses_argv(node.left) || ast_uses_argv(node.right)

  when :unary_op, :not
    ast_uses_argv(node.operand)

  when :target_not
    ast_uses_argv(node.expression)

  when :in_test
    ast_uses_argv(node.lhs) || ast_uses_argv(node.elements)

  when :passthrough
    ast_uses_argv(node.expression) || ast_uses_argv(node.value)

  when :range
    ast_uses_argv(node.from) || ast_uses_argv(node.to)

  when :if
    if ast_uses_argv(node.condition)
      return true
    if ast_uses_argv(node.then_body)
      return true
    if ast_uses_argv(node.elsif_clauses)
      return true
    ast_uses_argv(node.else_body)

  when :while
    ast_uses_argv(node.condition) || ast_uses_argv(node.body)

  when :with, :parallel_with
    ast_uses_argv(node.bindings) || ast_uses_argv(node.body)

  when :case
    ast_uses_argv(node.whens) || ast_uses_argv(node.else_body)

  when :when
    ast_uses_argv(node.conditions) || ast_uses_argv(node.body)

  when :case_value
    if ast_uses_argv(node.subject)
      return true
    if ast_uses_argv(node.arms)
      return true
    ast_uses_argv(node.else_body)

  when :case_arm
    if ast_uses_argv(node.pattern)
      return true
    if ast_uses_argv(node.guard)
      return true
    ast_uses_argv(node.body)

  when :safe_nav
    if ast_uses_argv(node.receiver)
      return true
    if ast_uses_argv(node.args)
      return true
    ast_uses_argv(node.block)

  when :rescue_expr
    ast_uses_argv(node.body) || ast_uses_argv(node.fallback)

  when :puts
    vals = node.value
    found = false
    i = 0
    while i < vals.size()
      if ast_uses_argv(vals[i])
        found = true
      i += 1
    found

  when :return, :print, :raise, :recase
    ast_uses_argv(node.value)

  when :class_def, :module_def, :trait_def
    ast_uses_argv(node.superclass) || ast_uses_argv(node.body)

  when :method_def, :fn_def, :gpu_kernel_def
    ast_uses_argv(node.params) || ast_uses_argv(node.body)

  when :param
    ast_uses_argv(node.default)

  when :block
    ast_uses_argv(node.params) || ast_uses_argv(node.body)

  when :begin
    if ast_uses_argv(node.body)
      return true
    if ast_uses_argv(node.rescue_body)
      return true
    ast_uses_argv(node.ensure_body)

  when :yield, :super
    ast_uses_argv(node.args)

  when :go
    ast_uses_argv(node.body)

  when :schedule_def, :layout_def
    ast_uses_argv(node.directives)

  when :on_guard
    ast_uses_argv(node.predicate) || ast_uses_argv(node.body)

  when :regex_match
    ast_uses_argv(node.regex) || ast_uses_argv(node.subject)

  when :cidr_match
    ast_uses_argv(node.subject) || ast_uses_argv(node.cidr)

  else
    false

-> mark_builtin_runtime_class_uses(node, mod)
  if node == nil
    return

  node_type = type(node)
  if node_type == "Array"
    i = 0
    while i < node.size()
      mark_builtin_runtime_class_uses(node[i], mod)
      i += 1
    return

  if !is_ast_node?(node)
    return

  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    mark_builtin_runtime_class_uses(node[:body], mod)
    return

  if t in (:var :class_ref)
    name = node.name
    if mod[:builtin_class_names][name] == true
      mark_builtin_class_used(mod, name)
    return

  case t
  when :call
    mark_builtin_runtime_class_uses(node.receiver, mod)
    mark_builtin_runtime_class_uses(node.args, mod)
    mark_builtin_runtime_class_uses(node.block, mod)

  when :program
    mark_builtin_runtime_class_uses(node.expressions, mod)

  when :array
    mark_builtin_runtime_class_uses(node.elements, mod)

  when :hash_literal
    mark_builtin_runtime_class_uses(node.entries, mod)

  when :string_interp, :byte_array_interp
    mark_builtin_runtime_class_uses(node.parts, mod)

  when :typed_array_new, :typed_array, :view_access
    mark_builtin_runtime_class_uses(node.size, mod)
    mark_builtin_runtime_class_uses(node.index, mod)

  when :assign, :compound_assign
    mark_builtin_runtime_class_uses(node.target, mod)
    mark_builtin_runtime_class_uses(node.value, mod)

  when :multi_assign
    mark_builtin_runtime_class_uses(node.targets, mod)
    mark_builtin_runtime_class_uses(node.value, mod)

  when :binary_op, :and, :or, :target_and, :target_or
    mark_builtin_runtime_class_uses(node.left, mod)
    mark_builtin_runtime_class_uses(node.right, mod)

  when :unary_op, :not
    mark_builtin_runtime_class_uses(node.operand, mod)

  when :target_not
    mark_builtin_runtime_class_uses(node.expression, mod)

  when :in_test
    mark_builtin_runtime_class_uses(node.lhs, mod)
    mark_builtin_runtime_class_uses(node.elements, mod)

  when :passthrough
    mark_builtin_runtime_class_uses(node.expression, mod)
    mark_builtin_runtime_class_uses(node.value, mod)

  when :range
    mark_builtin_runtime_class_uses(node.from, mod)
    mark_builtin_runtime_class_uses(node.to, mod)

  when :if
    mark_builtin_runtime_class_uses(node.condition, mod)
    mark_builtin_runtime_class_uses(node.then_body, mod)
    mark_builtin_runtime_class_uses(node.elsif_clauses, mod)
    mark_builtin_runtime_class_uses(node.else_body, mod)

  when :while
    mark_builtin_runtime_class_uses(node.condition, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :with, :parallel_with
    mark_builtin_runtime_class_uses(node.bindings, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :case
    mark_builtin_runtime_class_uses(node.whens, mod)
    mark_builtin_runtime_class_uses(node.else_body, mod)

  when :when
    mark_builtin_runtime_class_uses(node.conditions, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :case_value
    mark_builtin_runtime_class_uses(node.subject, mod)
    mark_builtin_runtime_class_uses(node.arms, mod)
    mark_builtin_runtime_class_uses(node.else_body, mod)

  when :case_arm
    mark_builtin_runtime_class_uses(node.pattern, mod)
    mark_builtin_runtime_class_uses(node.guard, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :safe_nav
    mark_builtin_runtime_class_uses(node.receiver, mod)
    mark_builtin_runtime_class_uses(node.args, mod)
    mark_builtin_runtime_class_uses(node.block, mod)

  when :rescue_expr
    mark_builtin_runtime_class_uses(node.body, mod)
    mark_builtin_runtime_class_uses(node.fallback, mod)

  when :puts
    vals = node.value
    i = 0
    while i < vals.size()
      mark_builtin_runtime_class_uses(vals[i], mod)
      i += 1

  when :return, :print, :raise, :recase
    mark_builtin_runtime_class_uses(node.value, mod)

  when :class_def, :module_def, :trait_def
    mark_builtin_runtime_class_uses(node.superclass, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :method_def, :fn_def, :gpu_kernel_def
    mark_builtin_runtime_class_uses(node.params, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :param
    mark_builtin_runtime_class_uses(node.default, mod)

  when :block
    mark_builtin_runtime_class_uses(node.params, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :begin
    mark_builtin_runtime_class_uses(node.body, mod)
    mark_builtin_runtime_class_uses(node.rescue_body, mod)
    mark_builtin_runtime_class_uses(node.ensure_body, mod)

  when :yield, :super
    mark_builtin_runtime_class_uses(node.args, mod)

  when :go
    mark_builtin_runtime_class_uses(node.body, mod)

  when :schedule_def, :layout_def
    mark_builtin_runtime_class_uses(node.directives, mod)

  when :on_guard
    mark_builtin_runtime_class_uses(node.predicate, mod)
    mark_builtin_runtime_class_uses(node.body, mod)

  when :regex_match
    mark_builtin_runtime_class_uses(node.regex, mod)
    mark_builtin_runtime_class_uses(node.subject, mod)

  when :cidr_match
    mark_builtin_runtime_class_uses(node.subject, mod)
    mark_builtin_runtime_class_uses(node.cidr, mod)

# Check if an int operation is safe to inline (no overflow risk).
# Bitwise ops are always safe. Arithmetic is only safe when one operand
# is a small literal (e.g., i + 1) that can't cause overflow.
# Find variables safe to keep unboxed through a while loop:
# must be :int in var_types, only modified via compound_assign, never full-assigned,
# and only use compound ops that cannot overflow the raw i64 slot representation.

# -- Type predicates (Phase 4 / Phase 6) --

-> is_int_expr?(node)
  if node == nil
    return false
  t = ast_kind(node)
  case t
  when :int
    return true
  when :var
    return true
  when :binary_op
    return is_int_expr?(node.left) && is_int_expr?(node.right)
  when :compound_assign
    return is_int_expr?(node.value)
  else
    false

-> is_i64_type(t)
  t in (:i64 :raw_i64 :raw_int)

-> is_u64_type(t)
  t == :u64

-> is_i128_type(t)
  t == :i128

-> is_u128_type(t)
  t == :u128

-> is_machine_int128_type(t)
  is_i128_type(t) || is_u128_type(t)

-> is_machine_int_type(t)
  is_i64_type(t) || is_u64_type(t) || is_i128_type(t) || is_u128_type(t)

-> is_machine_int64_type(t)
  is_machine_int_type(t) && !is_machine_int128_type(t)

-> raw_machine_value_type(t)
  case t
  when :u64
    :raw_u64
  when :i128
    :raw_i128
  when :u128
    :raw_u128
  else
    :raw_i64

-> raw_value_machine_type(t)
  case t
  when :raw_int, :raw_i64
    :i64
  when :raw_u64
    :u64
  when :raw_i128
    :i128
  when :raw_u128
    :u128
  else
    nil

-> canonical_machine_int_type(t)
  raw_type = raw_value_machine_type(t)
  if raw_type != nil
    return raw_type
  if is_machine_int_type(t)
    return t
  if is_small_int_type(t)
    return t
  nil

-> is_integer_like_type(t)
  t in (:int :raw_int :raw_i64 :raw_u64 :u4 :u8 :u16 :u32 :i4 :i8 :i16 :i32 :char) || is_machine_int_type(t)

# `:char` is a narrow-int type representing an ASCII byte. It flows
# through arithmetic like `:u8` (same machine width, same zero-extend
# rules), but is kept distinct at the type level so downstream
# features (.to_s producing "A" instead of "65", char + int preserving
# char-ness) can dispatch on it.
-> is_small_int_type(t)
  t in (:u4 :u8 :u16 :u32 :i4 :i8 :i16 :i32 :char)

-> is_raw_int_storage_type(t)
  is_machine_int_type(t) || is_small_int_type(t)

# Opt-in auto-promoting BigInt accumulator type. Set by the `## big`
# (a.k.a. `## bigint` / `## bignum`) inline annotation. A :bigint var is
# deliberately NOT integer-like, NOT machine-int, NOT raw — so it is
# excluded from loop-var unboxing (find_unboxable_loop_vars) and its
# arithmetic flows through the boxed, bigint-PROMOTING runtime path
# (w_add/w_mul) every iteration instead of native silent-wrap mul_i64.
# This is the language-level opt-in: default int +/-/* stay fast native
# i64; `## big` keeps an accumulator (e.g. a factorial) exact.
-> is_bigint_type(t)
  t == :bigint

-> is_char_type(t)
  t == :char

-> is_typed_array_type?(t)
  t in (:typed_array :typed_array_bool :typed_array_u4 :typed_array_i4 :typed_array_u8 :typed_array_i8 :typed_array_u16 :typed_array_i16 :typed_array_u32 :typed_array_i32 :typed_array_u64 :typed_array_i64 :typed_array_f32 :typed_array_f64 :typed_array_bf16 :typed_array_f8_e4m3 :typed_array_f8_e5m2 :typed_array_f4_e2m1 :typed_array_w64)

# Phase 3: tier × ebits type symbols for the unified Array hierarchy.
# Recognized variants per tier: u4 i4 u8 i8 u16 i16 u32 i32 u64 i64 f32 f64
# w64 bf16 f8_e4m3 f8_e5m2 f4_e2m1. Phase 5 monomorphization uses
# (tier, ebits) as the cache key for specialized method instances.
-> is_big_array_type?(t)
  t in (:big_array :big_array_u4 :big_array_i4 :big_array_u8 :big_array_i8 :big_array_u16 :big_array_i16 :big_array_u32 :big_array_i32 :big_array_u64 :big_array_i64 :big_array_f32 :big_array_f64 :big_array_w64 :big_array_bf16 :big_array_f8_e4m3 :big_array_f8_e5m2 :big_array_f4_e2m1)

-> is_small_array_type?(t)
  t in (:small_array :small_array_u4 :small_array_i4 :small_array_u8 :small_array_i8 :small_array_u16 :small_array_i16 :small_array_u32 :small_array_i32 :small_array_u64 :small_array_i64 :small_array_f32 :small_array_f64 :small_array_w64 :small_array_bf16 :small_array_f8_e4m3 :small_array_f8_e5m2 :small_array_f4_e2m1)

# Tier-agnostic predicate: matches anything in the WTypedArray / WBigArray /
# WSmallArray family. Phase 4 unification will collapse the Array tier into
# this one too. Used by lowering paths that don't care which tier they're
# operating on (e.g. monomorphic specialization detection in Phase 5 only
# needs to know "this is some kind of typed array").
-> is_array_type?(t)
  t == :array || is_typed_array_type?(t) || is_big_array_type?(t) || is_small_array_type?(t)

# Phase 5: map an array variant type back to the source class name whose
# user-defined methods get specialized for that variant. Phase 4 collapsed
# typed-and-poly arrays under "Array"; the big/small tiers have their own
# class names. nil if t isn't an array variant.
-> source_class_for_array_type(t)
  if is_typed_array_type?(t)
    return "Array"
  if is_big_array_type?(t)
    return "BigArray"
  if is_small_array_type?(t)
    return "SmallArray"
  nil

# Phase 6f: translate a small_array_* / big_array_* type symbol to
# the equivalent typed_array_* symbol, so the typed-array element-bits
# and signed? helpers can be reused. nil for non-array types.
-> small_array_to_typed_array_type(t)
  if t == nil
    return nil
  s = t.to_s()
  suffix = nil
  if s.starts_with?("small_array_")
    suffix = s.slice(12, s.size() - 12)
  elsif s == "small_array"
    suffix = "w64"
  elsif s.starts_with?("big_array_")
    suffix = s.slice(10, s.size() - 10)
  elsif s == "big_array"
    suffix = "w64"
  if suffix == nil
    return nil
  case suffix
  when "bool", "u1" then :typed_array_bool
  when "u4"   then :typed_array_u4
  when "i4"   then :typed_array_i4
  when "u8"   then :typed_array_u8
  when "i8"   then :typed_array_i8
  when "u16"  then :typed_array_u16
  when "i16"  then :typed_array_i16
  when "u32"  then :typed_array_u32
  when "i32"  then :typed_array_i32
  when "u64"  then :typed_array_u64
  when "i64"  then :typed_array_i64
  when "f32"  then :typed_array_f32
  when "f64"  then :typed_array_f64
  when "bf16" then :typed_array_bf16
  when "w64"  then :typed_array_w64
  else nil

-> typed_array_element_value_type(t)
  if t == :bool_array
    return :bool
  elem_t = t
  if is_big_array_type?(t) || is_small_array_type?(t)
    elem_t = small_array_to_typed_array_type(t)
  if elem_t == :typed_array_bool
    return :bool
  if elem_t == :typed_array_u4
    return :u4
  if elem_t == :typed_array_i4
    return :i4
  if elem_t == :typed_array_i8
    return :i8
  if elem_t == :typed_array_u8
    return :u8
  if elem_t == :typed_array_i16
    return :i16
  if elem_t == :typed_array_u16
    return :u16
  if elem_t == :typed_array_i32
    return :i32
  if elem_t == :typed_array_u32
    return :u32
  if elem_t == :typed_array_i64
    return :i64
  if elem_t == :typed_array_u64
    return :u64
  if elem_t == :typed_array_f32
    return :f32
  if elem_t == :typed_array_f64
    return :f64
  if elem_t == :typed_array_bf16
    return :bf16
  if elem_t == :typed_array_f8_e4m3
    return :f8_e4m3
  if elem_t == :typed_array_f8_e5m2
    return :f8_e5m2
  if elem_t == :typed_array_f4_e2m1
    return :f4_e2m1
  nil

-> iterator_block_param_types(recv_type, method_name)
  elem_t = typed_array_element_value_type(recv_type)
  if elem_t == nil
    return nil
  if method_name in ("each" "map" "select" "reject" "find" "detect" "all?" "any?" "none?" "count" "flat_map" "group_by" "partition" "find_index")
    return [elem_t]
  if method_name in ("each_with_index" "map_with_index")
    return [elem_t, :i64]
  if method_name == "reduce"
    return [nil, elem_t]
  nil

# -- Iterator method lookup tables --

-> inline_array_iterator_method?(method_name)
  method_name in ("each" "find" "detect" "all?" "any?" "none?")

-> inline_closure_arg_iterator_method?(method_name)
  method_name in ("each" "map" "select" "reject" "find" "detect" "all?" "any?" "none?" "count" "reduce" "flat_map" "each_with_index" "map_with_index" "group_by" "partition" "find_index" "each_slice" "each_cons")

# True when a trailing block on `recv.name` should iterate the call's RESULT
# (implicit `.each`) rather than be passed to `name` as a block — i.e. `name`
# takes no block of its own. Block-taking methods are excluded three ways:
# declared-in-`.w` (mod[:block_method_names], gathers `&`/yield from every
# def), the inline iterator list, and the runtime iteration builtins that have
# no `.w` signature (times/upto/sort_by/…). Operators and `new` never qualify.
-> method_takes_no_block?(mod, mname)
  if mname == nil
    return false
  # Only plain lowercase-identifier method names are candidates; operators
  # (`+`, `<<`, `[]`, `-@`, …) and constructors never take an implicit-each block.
  c0 = mname[0]
  if !((c0 >= "a" && c0 <= "z") || c0 == "_")
    return false
  if mname == "new"
    return false
  if mod[:block_method_names][mname] == true
    return false
  if inline_closure_arg_iterator_method?(mname)
    return false
  if mname in ("each" "map" "select" "reject" "filter" "filter_map" "find" "find_index" "detect" "all?" "any?" "none?" "count" "reduce" "inject" "flat_map" "each_with_index" "map_with_index" "group_by" "partition" "each_slice" "each_cons" "each_with_object" "chunk_while" "take_while" "drop_while" "sort" "sort_by" "min_by" "max_by" "sum" "zip" "times" "upto" "downto" "step" "cycle" "tap" "then" "loop")
    return false
  true
