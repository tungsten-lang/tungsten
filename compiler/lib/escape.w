# Escape analysis — per-function summaries of which parameters escape.
# Bottom-up walk: leaf functions first, callers use callee summaries.
# Stores results in mod[:fn_escs] keyed by function name.

# Known impure operations (I/O, syscalls, mutation)
-> init_escape_impure_calls_map()
  m = {}
  names = [
    "w_puts", "w_print", "w_write_file", "w_read_file",
    "w_system", "w_exit", "w_raise", "w_env",
    "w_goroutine_spawn", "w_thread_spawn", "w_thread_spawn_slots", "w_flush", "w_read_bytes", "w_read_line_stdin",
    "w_slab_freeze_safe",
    "__w_print", "__w_read_file", "__w_read_file_bytes", "__w_write_file", "__w_system",
    "__w_capture", "__w_exit", "__w_env", "__w_file_mtime_ns",
    "__w_file_exists", "__w_cache_read", "__w_cache_write",
    "__w_clock", "__w_clock_ms", "__w_sleep_ms",
    "w_metal_device_default", "w_metal_buffer_new", "w_metal_buffer_length",
    "w_metal_buffer_write_f32", "w_metal_buffer_write_i32", "w_metal_buffer_write_f16",
    "w_metal_buffer_read_f32", "w_metal_buffer_read_i32", "w_metal_buffer_read_f16",
    "w_metal_compile_source", "w_metal_compile_source_opts", "w_metal_library_from_file", "w_metal_pipeline_for", "w_metal_queue_new",
    "w_metal_dispatch1", "w_metal_dispatch_n", "w_metal_dispatch_groups",
    "w_metal_batch_begin", "w_metal_batch_commit", "w_metal_batch_commit_ms",
    "w_metal_batch_commit_async", "w_metal_command_buffer_wait",
    "w_metal_batch_begin_concurrent", "w_metal_batch_barrier",
    "w_metal_set_threadgroup_memory",
    "w_metal_pipeline_for_with_int_constants",
    "w_metal_binary_archive_new",
    "w_metal_batch_barrier_resources",
    "w_metal_buffer_write_from_mmap", "w_metal_fp8_e4m3_gather_rows", "w_q8_split_blocks", "w_q8_dequant_row"
  ]
  i = 0
  while i < names.size()
    m[names[i]] = true
    i += 1
  m

escape_impure_calls_map = init_escape_impure_calls_map()

-> is_impure_call(name)
  escape_impure_calls_map[name] == true

# Builtins whose ARGUMENTS never escape into the result or globals. Most
# are read-only; the w_str_concat_free_* variants additionally RELEASE an
# operand (a side effect), so this list must never be used to justify
# dead-call elimination, reordering, or CSE — only escape marking.
-> init_escape_pure_builtins_map()
  m = {}
  names = [
    "__w_add_fast", "__w_sub_fast", "__w_mul_fast", "__w_div_fast", "__w_mod_fast",
    "__w_shl_fast", "__w_shr_fast", "__w_band_fast", "__w_bor_fast", "__w_bxor_fast",
    "w_bigint_shr", "w_bigint_shl", "w_bigint_add", "w_bigint_sub", "w_bigint_div", "w_bigint_mod", "w_bigint_mul_builtin_exact",
    "w_add", "w_sub", "w_mul", "w_div", "w_mod",
    "w_eq", "w_neq", "w_eq_lit", "w_neq_lit", "w_lt", "w_gt", "w_lte", "w_gte",
    "__w_eq_fast", "__w_neq_fast", "__w_eq_lit_fast", "__w_neq_lit_fast",
    "__w_lt_fast", "__w_gt_fast", "__w_lte_fast", "__w_gte_fast",
    "__w_streq_fast", "__w_streq2_fast", "__w_switch_canonical_fast", "w_switch_canonical",
    "w_bit_and", "w_bit_or", "w_bit_xor", "w_bit_shl", "w_bit_shr",
    "w_negate", "w_not", "w_to_s", "w_int_to_s", "w_to_i", "w_to_f",
    "w_string", "w_str_to_sym", "w_str_concat", "w_str_concat_free_rhs", "w_str_concat_free_lhs",
    "w_str_length", "w_string_byte_length", "__w_type", "w_hash_new", "w_array_new",
    "w_box_int_checked", "w_wire_sequence_from_array"
  ]
  i = 0
  while i < names.size()
    m[names[i]] = true
    i += 1
  m

escape_pure_builtins_map = init_escape_pure_builtins_map()

-> is_pure_builtin(name)
  escape_pure_builtins_map[name] == true

# Param index for a WIRE value: a parameter register itself, or a temp the
# forward derivation walk below traced back to one. nil when unrelated.
# param_idx is keyed by the exact register (naming.w llvm_param_reg), never by
# a stripped spelling: a temporary `%t0` is not the parameter `t0`.
-> escape_param_source(value, temp_from_param, param_idx = nil)
  if value == nil
    return nil
  temp_from_param[value]

# Record that `value` (if param-derived) escapes. `stored` distinguishes a
# value retained somewhere that outlives the call (ivar, global, container,
# closure, unknown callee) from one that merely flows out through `ret`.
-> escape_mark_value(value, stored, state)
  src = escape_param_source(value, state[:temp_from_param], state[:param_idx])
  if src == nil
    return nil
  state[:param_escaped][src] = true
  if stored
    state[:param_stored][src] = true
    state[:param_int_stored][src] = true
    state[:param_kind_stored][:array][src] = true
    state[:param_kind_stored][:string][src] = true
    state[:param_kind_stored][:hash][src] = true
  else
    state[:param_returned][src] = true
  nil

-> escape_mark_args(args, stored, state)
  if args == nil
    return nil
  ai = 0
  while ai < wire_sequence_size(args)
    escape_mark_value(wire_sequence_get(args, ai), stored, state)
    ai += 1
  nil

# The result of `inst` may alias any param-derived argument: pure builtins
# such as w_to_s return their argument for string inputs, w_str_concat retains
# both sides in a rope, and a callee whose summary says it returns parameter
# i hands the caller that same value under a new temp.
-> escape_derive_result_from_args(inst, args, state)
  temp = wire_get(inst, :temp)
  if temp == nil || args == nil
    return nil
  ai = 0
  while ai < wire_sequence_size(args)
    src = escape_param_source(wire_sequence_get(args, ai), state[:temp_from_param], state[:param_idx])
    if src != nil
      state[:temp_from_param][temp] = src
      return nil
    ai += 1
  nil

escape_derive_fields = [:value, :boxed, :raw, :arr, :base, :ptr, :lhs, :rhs]

# Alias-carrying operand fields of value-producing ops the main walk has no
# specific rule for: conversions (:value, :boxed, :raw), container and
# pointer bases (:arr, :base, :ptr), and arithmetic that may be pointer
# arithmetic (:lhs, :rhs). The result inherits the first param derivation
# found among them.
-> escape_derive_result_from_fields(inst, state)
  temp = wire_get(inst, :temp)
  if temp == nil
    return nil
  fi = 0
  while fi < escape_derive_fields.size()
    src = escape_param_source(wire_get(inst, escape_derive_fields[fi]), state[:temp_from_param], state[:param_idx])
    if src != nil
      state[:temp_from_param][temp] = src
      return nil
    fi += 1
  nil

# Concat variants that RELEASE or take ownership of an operand: an argument
# handed to one of these is consumed, never merely read.
-> init_escape_consuming_builtins_map()
  m = {}
  names = ["w_str_concat_free_lhs", "w_str_concat_free_rhs", "w_str_concat_own", "w_str_concat_i64", "w_i64_concat_str", "w_str_concat_int_wv", "w_int_wv_concat_str"]
  i = 0
  while i < names.size()
    m[names[i]] = true
    i += 1
  m

escape_consuming_builtins_map = init_escape_consuming_builtins_map()

-> is_consuming_builtin(name)
  escape_consuming_builtins_map[name] == true

# Analyze one function: which parameters escape (stored somewhere that
# outlives the call, or returned) and whether the function is pure.
#
# Instruction coverage mirrors ownership.w's mark_escapes op-for-op. The
# ownership pass consumes these summaries to avoid pinning a caller's
# argument (or the fresh object a guarded `Cls.new` produced) as escaped, so
# every instruction that can retain a value there must mark a param-derived
# value here. Derivation is tracked forward through phis, selects, results
# of pure builtins, and results of callees that return a parameter.
-> escape_analyze(func, mod, fn_escs, strings = nil)
  params = func[:params]
  if params == nil
    return nil

  param_escaped = []
  param_stored = []
  # Stored assuming the argument is an Integer: a read-only Integer method
  # called on it (`v.bit_length`) then keeps nothing (ownership.w,
  # int_temp_releases, decides when an argument is known to be one).
  param_int_stored = []
  # Stored assuming the argument is a core Array / String / Hash: read-only
  # core methods (runtime_types.w container_reader_method?) keep nothing.
  param_kind_stored = {array: [], string: [], hash: []}
  # Flows into the result (returned or derived into it).
  param_returned = []
  param_idx = {}
  temp_from_param = {}
  pi = 0
  while pi < params.size()
    param_escaped.push(false)
    param_stored.push(false)
    param_int_stored.push(false)
    param_kind_stored[:array].push(false)
    param_kind_stored[:string].push(false)
    param_kind_stored[:hash].push(false)
    param_returned.push(false)
    preg = llvm_param_reg(params[pi])
    param_idx[preg] = pi
    temp_from_param[preg] = pi
    pi += 1

  has_side_effects = false
  if params.size() == 0
    bi = 0
    while bi < func[:blocks].size() && !has_side_effects
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        op = wire_kind(inst)
        if op == :call_direct_i64 || op == :call_direct_void
          call_name = wire_get(inst, :name)
          if !(call_name in ("w_array_get" "w_array_get_i64" "w_array_idx_i64" "__w_array_get_i64_fast" "__w_array_idx_i64_fast")) && container_store_first_kept(call_name) == nil && !is_consuming_builtin(call_name) && !is_pure_builtin(call_name)
            if is_impure_call(call_name)
              has_side_effects = true
              break
        elsif op == :load_i64 || op == :store_i64 || op == :br || op == :cond_br || op == :call_loc_set_col || op == :phi_ssa
          ignored = nil
        elsif op in (:call_method_i64 :ivar_set :ivar_set_idx :store_global :store_cvar :class_store :puts_i64 :print_i64 :class_add_method :class_add_static_method :class_add_ivar :type_class_register :node_kind_class_register :class_new)
          has_side_effects = true
          break
        elsif (wire_get(inst, :args) != nil || wire_get(inst, :receiver) != nil) && !(op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64 :call_direct_i128 :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_direct_ptr :call_fused_out_reuse))
          has_side_effects = true
          break
        ii += 1
      bi += 1
    fn_escs[func[:name]] = {
      escs: param_escaped,
      stored_escs: param_stored,
      int_stored_escs: param_int_stored,
      kind_stored_escs: param_kind_stored,
      ret_escs: param_returned,
      pure: !has_side_effects,
      param_count: 0
    }
    return fn_escs[func[:name]]

  state = {param_escaped: param_escaped, param_stored: param_stored, param_int_stored: param_int_stored, param_kind_stored: param_kind_stored, param_returned: param_returned, param_idx: param_idx, temp_from_param: temp_from_param}
  # temp -> text of the string/symbol constant it holds (method names)
  name_texts = {}

  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = wire_kind(inst)

      if op == :call_direct_i64 || op == :call_direct_void
        call_name = wire_get(inst, :name)
        args = wire_get(inst, :args)
        kept = container_store_first_kept(call_name)
        if call_name in ("w_array_get" "w_array_get_i64" "w_array_idx_i64" "__w_array_get_i64_fast" "__w_array_idx_i64_fast")
          # an element read: the container is neither kept nor returned
          ignored = nil
        elsif kept != nil
          # The container keeps the stored key/value, not itself; the result
          # (nil or the stored value) may alias the value.
          ai = kept
          while args != nil && ai < wire_sequence_size(args)
            escape_mark_value(wire_sequence_get(args, ai), true, state)
            ai += 1
        elsif is_consuming_builtin(call_name)
          escape_mark_args(args, true, state)
          escape_derive_result_from_args(inst, args, state)
        elsif is_pure_builtin(call_name)
          escape_derive_result_from_args(inst, args, state)
        else
          callee_escs = fn_escs[call_name]
          if args != nil
            ai = 0
            while ai < wire_sequence_size(args)
              arg = wire_sequence_get(args, ai)
              src = escape_param_source(arg, temp_from_param, param_idx)
              if src != nil
                known = false
                if callee_escs != nil && callee_escs[:escs] != nil && ai < callee_escs[:escs].size()
                  known = true
                  stored_list = callee_escs[:stored_escs]
                  int_list = callee_escs[:int_stored_escs]
                  if int_list == nil || ai >= int_list.size() || int_list[ai] == true
                    param_int_stored[src] = true
                  kl = callee_escs[:kind_stored_escs]
                  if kl == nil
                    param_kind_stored[:array][src] = true
                    param_kind_stored[:string][src] = true
                    param_kind_stored[:hash][src] = true
                  else
                    kv_a = kl[:array]
                    if kv_a == nil || ai >= kv_a.size() || kv_a[ai] == true
                      param_kind_stored[:array][src] = true
                    kv_s = kl[:string]
                    if kv_s == nil || ai >= kv_s.size() || kv_s[ai] == true
                      param_kind_stored[:string][src] = true
                    kv_h = kl[:hash]
                    if kv_h == nil || ai >= kv_h.size() || kv_h[ai] == true
                      param_kind_stored[:hash][src] = true
                  if stored_list == nil || ai >= stored_list.size() || stored_list[ai] == true
                    param_escaped[src] = true
                    param_stored[src] = true
                  elsif callee_escs[:escs][ai] == true
                    # Returned by the callee, not stored: the result aliases it.
                    if wire_get(inst, :temp) != nil
                      temp_from_param[wire_get(inst, :temp)] = src
                if !known
                  param_escaped[src] = true
                  param_stored[src] = true
                  param_int_stored[src] = true
                  param_kind_stored[:array][src] = true
                  param_kind_stored[:string][src] = true
                  param_kind_stored[:hash][src] = true
              ai += 1
          if is_impure_call(call_name)
            has_side_effects = true

      elsif op == :load_i64 || op == :load_ptr
        src = escape_param_source(wire_get(inst, :ptr), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op == :store_i64 || op == :store_ptr || op == :view_store_field || op == :store_memo_ptr || op == :slab_node_set_idx
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:br :cond_br :call_loc_set_col :scope_push :scope_pop :alloca_i64 :ret_void :ret_i32 :unreachable :load_global :load_class :free_value)
        ignored = nil

      elsif op == :ret_i64
        escape_mark_value(wire_get(inst, :value), false, state)

      elsif op == :call_method_i64
        has_side_effects = true
        escape_mark_args(wire_get(inst, :args), true, state)
        receiver = wire_get(inst, :receiver)
        mv = wire_get(inst, :method_name_val)
        mname = name_texts[mv]
        if mname == nil && strings != nil && type(mv) == "String" && mv.starts_with?("u0x")
          mname = strings[mv]
        src = escape_param_source(receiver, temp_from_param, param_idx)
        if src != nil
          # Stored for any receiver kind, but a read-only method of an
          # Integer or a core container keeps nothing: those flags stay clear.
          param_escaped[src] = true
          param_stored[src] = true
          param_int_stored[src] = true if mname == nil || !int_temp_reader_method?(mname)
          param_kind_stored[:array][src] = true if mname == nil || !container_reader_method?(:array, mname)
          param_kind_stored[:string][src] = true if mname == nil || !container_reader_method?(:string, mname)
          param_kind_stored[:hash][src] = true if mname == nil || !container_reader_method?(:hash, mname)

      elsif op == :string_i64 || op == :symbol_i64
        if wire_get(inst, :temp) != nil && strings != nil
          name_texts[wire_get(inst, :temp)] = strings[wire_get(inst, :string_id)]

      elsif op in (:truthy_inline :nanbox_bool :not_i1 :zext_i1_i64)
        src = escape_param_source(wire_get(inst, :value), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op == :nanbox_int
        src = escape_param_source(wire_get(inst, :raw), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op == :nanunbox_int
        src = escape_param_source(wire_get(inst, :boxed), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op in (:icmp_i64 :add_i64 :sub_i64 :mul_i64 :sdiv_i64 :srem_i64 :and_i64 :or_i64 :xor_i64 :shl_i64 :ashr_i64 :lshr_i64 :and_i1 :or_i1)
        src = escape_param_source(wire_get(inst, :lhs), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(wire_get(inst, :rhs), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op == :phi_ssa
        incoming = wire_get(inst, :incoming)
        if incoming != nil
          pi = 0
          while pi < wire_sequence_size(incoming)
            src = escape_param_source(wire_sequence_get(incoming, pi), temp_from_param, param_idx)
            if src != nil
              temp_from_param[wire_get(inst, :temp)] = src
            pi += 2

      elsif op == :phi_i64
        src = escape_param_source(wire_get(inst, :a_value), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(wire_get(inst, :b_value), temp_from_param, param_idx)
        if src != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op == :select_i64
        src = escape_param_source(wire_get(inst, :then_val), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(wire_get(inst, :else_val), temp_from_param, param_idx)
        if src != nil
          temp_from_param[wire_get(inst, :temp)] = src

      elsif op in (:ivar_set :ivar_set_idx :store_global :store_cvar :class_store)
        has_side_effects = true
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:small_array_set_inline :typed_array_set_inline :typed_array_compound_op_inline)
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:bool_array_set_inline :bool_array_set_byte_inline)
        escape_mark_value(wire_get(inst, :val), true, state)

      elsif op in (:cleanup_push_hash :cleanup_push_array :cleanup_push_typed :cleanup_push_strbuf :call_recycle_hash :call_recycle_array :call_recycle_typed :call_recycle_strbuf)
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op == :closure_new
        escape_mark_value(wire_get(inst, :captures_ptr), true, state)

      elsif op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
        escape_mark_args(wire_get(inst, :args), true, state)

      elsif op in (:puts_i64 :print_i64)
        has_side_effects = true
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:call_direct_i128 :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_direct_ptr :call_fused_out_reuse)
        # The ptr1 kinds carry their single payload in :arg, not :args.
        escape_mark_args(wire_get(inst, :args), true, state)
        escape_mark_value(wire_get(inst, :arg), true, state)

      elsif op == :slab_alloc_init
        # Packed AST node constructor: every field value is frozen into the
        # AST arena and stored in the node (w_ast_freeze_if_array keeps the
        # array it is handed) — the node retains all of them.
        escape_mark_args(wire_get(inst, :fields), true, state)

      elsif op in (:typed_array_store_u64 :view_store_inline_elem)
        # Raw stores whose slot may hold a boxed WValue (w64[] arrays,
        # `- data` inline element slots).
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:class_add_method :class_add_static_method :class_add_ivar :type_class_register :node_kind_class_register)
        has_side_effects = true
        escape_mark_value(wire_get(inst, :class_temp), true, state)

      elsif op == :class_new
        has_side_effects = true
        escape_mark_value(wire_get(inst, :super_reg), true, state)

      elsif op in (:switch_i64 :cleanup_pop :load_cvar :ivar_get :ivar_get_idx :bigint_literal_i64 :const_float :const_decimal :const_rational :const_char :fn_addr_i64)
        ignored = nil

      elsif op in (:icmp_ne_zero :inttoptr_i64 :ptr_to_i64 :i64_to_ptr)
        src = escape_param_source(wire_get(inst, :value), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      else
        # Catch-all for every other instruction shape. Any op that carries
        # an argument list or a receiver is a call the rules above do not
        # know (typed raw-ABI ccall_rawargs targets are emitted through
        # wire_make_dynamic_N with a return-type-specific kind, for one):
        # the callee may retain anything, so every param-derived operand is
        # stored. Any other op that yields a temp from an operand (pointer
        # and box conversions, guards, pointer arithmetic, data-address
        # takes) may alias that operand, so the result inherits its
        # derivation. Missing a case here silently makes a caller free a
        # value the callee still holds — err towards escape.
        catch_args = wire_get(inst, :args)
        catch_recv = wire_get(inst, :receiver)
        if catch_args != nil || catch_recv != nil
          has_side_effects = true
          escape_mark_args(catch_args, true, state)
          escape_mark_value(catch_recv, true, state)
        elsif wire_get(inst, :temp) != nil
          escape_derive_result_from_fields(inst, state)

      ii += 1
    bi += 1

  fn_escs[func[:name]] = {
    escs: param_escaped,
    stored_escs: param_stored,
    int_stored_escs: param_int_stored,
    kind_stored_escs: param_kind_stored,
    ret_escs: param_returned,
    pure: !has_side_effects,
    param_count: params.size()
  }

-> escape_parallel_job_count(mod)
  if env("TUNGSTEN_PARALLEL_MIDEND") == "0" || env("TUNGSTEN_PARALLEL_ESCAPE") == "0" || env("TUNGSTEN_BATCH_WORKER_PROCESS") == "1" || runtime_identity() != "compiled-runtime" || mod[:functions].size() < 512
    return 1
  requested = 0
  configured = env("TUNGSTEN_MIDEND_JOBS")
  if configured != nil && configured != "" && configured != "auto"
    requested = configured.to_i()
  if requested < 1
    requested = ccall("w_cpu_count")
    if requested > 8
      requested = 8
  if requested < 1
    requested = 1
  if requested > mod[:functions].size()
    requested = mod[:functions].size()
  if requested > 32
    requested = 32
  requested

-> escape_scan_one(fi, functions, fn_map, mod, strings, calls_to, precomputed)
  func = functions[fi]
  blocks = func[:blocks]
  params = func[:params]
  if blocks.size() == 0 || params == nil
    calls_to[fi] = []
    return nil
  if params.size() == 0
    calls_to[fi] = []
    local_escs = {}
    escape_analyze(func, mod, local_escs, strings)
    precomputed[fi] = local_escs[func[:name]]
    return nil
  edges = []
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if wire_kind(inst) in (:call_direct_i64 :call_direct_void)
        callee_idx = fn_map[wire_get(inst, :name)]
        if callee_idx != nil
          found = false
          ei = 0
          while ei < edges.size()
            if edges[ei] == callee_idx
              found = true
              break
            ei += 1
          if !found
            edges.push(callee_idx)
      ii += 1
    bi += 1
  calls_to[fi] = edges
  if edges.size() == 0
    local_escs = {}
    escape_analyze(func, mod, local_escs, strings)
    precomputed[fi] = local_escs[func[:name]]
  nil

-> escape_parallel_worker(state)
  functions = state[:functions]
  fn_map = state[:fn_map]
  mod = state[:mod]
  strings = state[:strings]
  calls_to = state[:calls_to]
  precomputed = state[:precomputed]
  n_funcs = functions.size()
  index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  while index < n_funcs
    escape_scan_one(index, functions, fn_map, mod, strings, calls_to, precomputed)
    index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  true

# Build a call graph and process functions bottom-up.
# Leaf functions (no calls to other user-defined functions) first.
-> escape_pass(mod)
  fn_escs = {}
  functions = mod[:functions]
  n_funcs = functions.size()

  strings = mod[:string_texts]
  if strings == nil
    strings = int_temp_string_texts(mod)
    mod[:string_texts] = strings

  # Build name → function index map
  fn_map = {}
  calls_to = []
  precomputed = []
  fi = 0
  while fi < n_funcs
    fn_map[functions[fi][:name]] = fi
    calls_to.push(nil)
    precomputed.push(nil)
    fi += 1

  jobs = escape_parallel_job_count(mod)
  if jobs > 1
    naming_cache_state[:frozen] = true
    state = {
      functions: functions,
      fn_map: fn_map,
      mod: mod,
      strings: strings,
      calls_to: calls_to,
      precomputed: precomputed,
      cursor: ccall("w_atomic_new", u0xFFFA000000000000)
    }
    workers = []
    worker = 1
    while worker < jobs
      workers.push(Thread.new ->
        escape_parallel_worker(state))
      worker += 1
    escape_parallel_worker(state)
    worker = 0
    while worker < workers.size()
      ccall("w_thread_join_release", workers[worker])
      worker += 1
    naming_cache_state[:frozen] = false
  else
    fi = 0
    while fi < n_funcs
      escape_scan_one(fi, functions, fn_map, mod, strings, calls_to, precomputed)
      fi += 1

  processed = []
  pending = []
  fi = 0
  while fi < n_funcs
    pre = precomputed[fi]
    if pre != nil
      fn_escs[functions[fi][:name]] = pre
      processed.push(true)
    elsif functions[fi][:blocks].size() == 0 || functions[fi][:params] == nil
      processed.push(true)
    else
      processed.push(false)
      pending.push(fi)
    fi += 1

  # Topological sort on remaining non-leaf functions
  order = []
  remaining = pending.size()
  n_pending = pending.size()
  while remaining > 0
    progress = false
    pi = 0
    while pi < n_pending
      fi = pending[pi]
      if !processed[fi]
        edges = calls_to[fi]
        all_done = true
        ei = 0
        while ei < edges.size()
          if !processed[edges[ei]]
            all_done = false
            break
          ei += 1
        if all_done
          order.push(fi)
          processed[fi] = true
          remaining = remaining - 1
          progress = true
      pi += 1
    if !progress
      # Cycle detected (recursion): process remaining in any order
      pi = 0
      while pi < n_pending
        fi = pending[pi]
        if !processed[fi]
          order.push(fi)
          processed[fi] = true
          remaining = remaining - 1
        pi += 1

  # Analyze remaining non-leaf functions in topological order
  oi = 0
  while oi < order.size()
    func = functions[order[oi]]
    if func[:blocks].size() > 0
      escape_analyze(func, mod, fn_escs, strings)
    oi += 1

  mod[:fn_escs] = fn_escs
