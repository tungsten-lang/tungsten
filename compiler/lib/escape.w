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
    "w_box_int_checked", "w_wire_sequence_from_array", "w_check_array_ebits"
  ]
  i = 0
  while i < names.size()
    m[names[i]] = true
    i += 1
  m

escape_pure_builtins_map = init_escape_pure_builtins_map()

-> is_pure_builtin(name)
  escape_pure_builtins_map[name] == true

-> init_escape_array_read_calls_map()
  m = {}
  names = [
    "w_array_get", "w_array_get_i64", "w_array_idx_i64", "__w_array_get_i64_fast", "__w_array_idx_i64_fast",
    "__w_ta_bounds_check", "__w_ta_bounds_check_boxed",
    "w_array_size", "w_bool_array_size", "w_bool_array_get", "w_bytes_length", "w_bytes_get",
    "w_array_min_signed", "w_array_min_unsigned", "w_array_min_float",
    "w_array_max_signed", "w_array_max_unsigned", "w_array_max_float",
    "w_array_sum_signed", "w_array_sum_unsigned", "w_array_sum_float",
    "w_array_fastsum_float", "w_array_sumsq_float", "w_array_dot_i8", "w_array_dot_float",
    "w_value_is_a"
  ]
  i = 0
  while i < names.size()
    m[names[i]] = true
    i += 1
  m

escape_array_read_calls_map = init_escape_array_read_calls_map()

-> is_escape_array_read_call(name)
  escape_array_read_calls_map[name] == true

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
  names = ["w_str_concat_free_lhs", "w_str_concat_free_rhs", "w_str_concat_own", "w_str_add_rhs_own", "w_str_concat_i64", "w_i64_concat_str", "w_str_concat_int_wv", "w_int_wv_concat_str", "w_str_concat_any"]
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
        kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
        case kid
        when WIRE_KIND_CALL_DIRECT_I64
          call_name = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME)
          if !is_escape_array_read_call(call_name) && container_store_first_kept(call_name) == nil && !is_consuming_builtin(call_name) && !is_pure_builtin(call_name)
            if is_impure_call(call_name)
              has_side_effects = true
              break
        when WIRE_KIND_CALL_DIRECT_VOID
          call_name = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_NAME)
          if !is_escape_array_read_call(call_name) && container_store_first_kept(call_name) == nil && !is_consuming_builtin(call_name) && !is_pure_builtin(call_name)
            if is_impure_call(call_name)
              has_side_effects = true
              break
        when WIRE_KIND_LOAD_I64, WIRE_KIND_STORE_I64, WIRE_KIND_BR, WIRE_KIND_COND_BR, WIRE_KIND_CALL_LOC_SET_COL, WIRE_KIND_PHI_SSA
          ignored = nil
        when WIRE_KIND_CALL_METHOD_I64, WIRE_KIND_IVAR_SET, WIRE_KIND_IVAR_SET_IDX, WIRE_KIND_STORE_GLOBAL, WIRE_KIND_STORE_CVAR, WIRE_KIND_CLASS_STORE, WIRE_KIND_PUTS_I64, WIRE_KIND_PRINT_I64, WIRE_KIND_CLASS_ADD_METHOD, WIRE_KIND_CLASS_ADD_STATIC_METHOD, WIRE_KIND_CLASS_ADD_IVAR, WIRE_KIND_TYPE_CLASS_REGISTER, WIRE_KIND_NODE_KIND_CLASS_REGISTER, WIRE_KIND_CLASS_NEW
          has_side_effects = true
          break
        when WIRE_KIND_MEMO_CALL0_I64, WIRE_KIND_MEMO_CALL1_I64, WIRE_KIND_MEMO_CALL2_I64, WIRE_KIND_CALL_DIRECT_I128, WIRE_KIND_CALL_DIRECT_I64_PTR1, WIRE_KIND_CALL_DIRECT_VOID_PTR1, WIRE_KIND_CALL_DIRECT_PTR, WIRE_KIND_CALL_FUSED_OUT_REUSE
          ignored = nil
        else
          if wire_get(inst, :args) != nil || wire_get(inst, :receiver) != nil
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
      kid = ccall_nobox("w_wire_kind_extern", inst) ## i64

      case kid
      when WIRE_KIND_CALL_DIRECT_I64, WIRE_KIND_CALL_DIRECT_VOID
        if kid == WIRE_KIND_CALL_DIRECT_I64
          call_name = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME)
          args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS)
        else
          call_name = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_NAME)
          args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_ARGS)
        kept = container_store_first_kept(call_name)
        if is_escape_array_read_call(call_name)
          # an element read / reduction / bounds check: the container is neither kept nor returned
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
                    if kid == WIRE_KIND_CALL_DIRECT_I64
                      ct = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP)
                      if ct != nil
                        temp_from_param[ct] = src
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

      when WIRE_KIND_LOAD_I64, WIRE_KIND_LOAD_PTR
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_PTR), temp_from_param, param_idx)
        if src != nil
          lt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_TEMP)
          if lt != nil
            temp_from_param[lt] = src

      when WIRE_KIND_STORE_I64
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_VALUE), true, state)

      when WIRE_KIND_STORE_PTR
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_PTR_VALUE), true, state)

      when WIRE_KIND_VIEW_STORE_FIELD, WIRE_KIND_STORE_MEMO_PTR, WIRE_KIND_SLAB_NODE_SET_IDX
        escape_mark_value(wire_get(inst, :value), true, state)

      when WIRE_KIND_BR, WIRE_KIND_COND_BR, WIRE_KIND_CALL_LOC_SET_COL, WIRE_KIND_SCOPE_PUSH, WIRE_KIND_SCOPE_POP, WIRE_KIND_ALLOCA_I64, WIRE_KIND_RET_VOID, WIRE_KIND_RET_I32, WIRE_KIND_UNREACHABLE, WIRE_KIND_LOAD_GLOBAL, WIRE_KIND_LOAD_CLASS, WIRE_KIND_FREE_VALUE, WIRE_KIND_SWITCH_I64, WIRE_KIND_CLEANUP_POP, WIRE_KIND_LOAD_CVAR, WIRE_KIND_IVAR_GET, WIRE_KIND_IVAR_GET_IDX, WIRE_KIND_BIGINT_LITERAL_I64, WIRE_KIND_CONST_FLOAT, WIRE_KIND_CONST_DECIMAL, WIRE_KIND_CONST_RATIONAL, WIRE_KIND_CONST_CHAR, WIRE_KIND_FN_ADDR_I64
        ignored = nil

      when WIRE_KIND_RET_I64
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_RET_I64_VALUE), false, state)

      when WIRE_KIND_CALL_METHOD_I64
        has_side_effects = true
        escape_mark_args(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_ARGS), true, state)
        receiver = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_RECEIVER)
        mv = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_METHOD_NAME_VAL)
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

      when WIRE_KIND_STRING_I64, WIRE_KIND_SYMBOL_I64
        st = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_TEMP)
        if st != nil && strings != nil
          name_texts[st] = strings[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_STRING_ID)]

      when WIRE_KIND_TRUTHY_INLINE, WIRE_KIND_NANBOX_BOOL, WIRE_KIND_NOT_I1, WIRE_KIND_ICMP_NE_ZERO, WIRE_KIND_INTTOPTR_I64, WIRE_KIND_PTR_TO_I64, WIRE_KIND_I64_TO_PTR
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUTHY_INLINE_VALUE), temp_from_param, param_idx)
        if src != nil
          ut = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUTHY_INLINE_TEMP)
          if ut != nil
            temp_from_param[ut] = src

      when WIRE_KIND_ZEXT_I1_I64
        src = escape_param_source(wire_get(inst, :value), temp_from_param, param_idx)
        if src != nil && wire_get(inst, :temp) != nil
          temp_from_param[wire_get(inst, :temp)] = src

      when WIRE_KIND_NANBOX_INT
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_RAW), temp_from_param, param_idx)
        if src != nil
          nt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_TEMP)
          if nt != nil
            temp_from_param[nt] = src

      when WIRE_KIND_NANUNBOX_INT
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_INT_BOXED), temp_from_param, param_idx)
        if src != nil
          nt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_INT_TEMP)
          if nt != nil
            temp_from_param[nt] = src

      when WIRE_KIND_ICMP_I64
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_LHS), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_RHS), temp_from_param, param_idx)
        if src != nil
          bt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_TEMP)
          if bt != nil
            temp_from_param[bt] = src

      when WIRE_KIND_ADD_I64, WIRE_KIND_SUB_I64, WIRE_KIND_MUL_I64, WIRE_KIND_SDIV_I64, WIRE_KIND_SREM_I64, WIRE_KIND_AND_I64, WIRE_KIND_OR_I64, WIRE_KIND_XOR_I64, WIRE_KIND_SHL_I64, WIRE_KIND_ASHR_I64, WIRE_KIND_LSHR_I64, WIRE_KIND_AND_I1, WIRE_KIND_OR_I1
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_LHS), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_RHS), temp_from_param, param_idx)
        if src != nil
          bt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_TEMP)
          if bt != nil
            temp_from_param[bt] = src

      when WIRE_KIND_PHI_SSA
        incoming = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_SSA_INCOMING)
        if incoming != nil
          pt = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_SSA_TEMP)
          pi = 0
          while pi < wire_sequence_size(incoming)
            src = escape_param_source(wire_sequence_get(incoming, pi), temp_from_param, param_idx)
            if src != nil
              temp_from_param[pt] = src
            pi += 2

      when WIRE_KIND_PHI_I64
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_A_VALUE), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_B_VALUE), temp_from_param, param_idx)
        if src != nil
          temp_from_param[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_TEMP)] = src

      when WIRE_KIND_SELECT_I64
        src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_THEN_VAL), temp_from_param, param_idx)
        if src == nil
          src = escape_param_source(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_ELSE_VAL), temp_from_param, param_idx)
        if src != nil
          temp_from_param[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_TEMP)] = src

      when WIRE_KIND_IVAR_SET, WIRE_KIND_IVAR_SET_IDX, WIRE_KIND_STORE_GLOBAL, WIRE_KIND_STORE_CVAR, WIRE_KIND_CLASS_STORE
        has_side_effects = true
        escape_mark_value(wire_get(inst, :value), true, state)

      when WIRE_KIND_SMALL_ARRAY_SET_INLINE, WIRE_KIND_TYPED_ARRAY_SET_INLINE, WIRE_KIND_TYPED_ARRAY_COMPOUND_OP_INLINE
        escape_mark_value(wire_get(inst, :value), true, state)

      when WIRE_KIND_BOOL_ARRAY_SET_INLINE, WIRE_KIND_BOOL_ARRAY_SET_BYTE_INLINE
        escape_mark_value(wire_get(inst, :val), true, state)

      when WIRE_KIND_CLEANUP_PUSH_HASH, WIRE_KIND_CLEANUP_PUSH_ARRAY, WIRE_KIND_CLEANUP_PUSH_TYPED, WIRE_KIND_CLEANUP_PUSH_STRBUF, WIRE_KIND_CALL_RECYCLE_HASH, WIRE_KIND_CALL_RECYCLE_ARRAY, WIRE_KIND_CALL_RECYCLE_TYPED, WIRE_KIND_CALL_RECYCLE_STRBUF
        escape_mark_value(wire_get(inst, :value), true, state)

      when WIRE_KIND_CLOSURE_NEW
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_CAPTURES_PTR), true, state)

      when WIRE_KIND_MEMO_CALL0_I64, WIRE_KIND_MEMO_CALL1_I64, WIRE_KIND_MEMO_CALL2_I64
        escape_mark_args(wire_get(inst, :args), true, state)

      when WIRE_KIND_PUTS_I64, WIRE_KIND_PRINT_I64
        has_side_effects = true
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PUTS_I64_VALUE), true, state)

      when WIRE_KIND_CALL_DIRECT_I128, WIRE_KIND_CALL_DIRECT_I64_PTR1, WIRE_KIND_CALL_DIRECT_VOID_PTR1, WIRE_KIND_CALL_DIRECT_PTR, WIRE_KIND_CALL_FUSED_OUT_REUSE
        # The ptr1 kinds carry their single payload in :arg, not :args.
        escape_mark_args(wire_get(inst, :args), true, state)
        escape_mark_value(wire_get(inst, :arg), true, state)

      when WIRE_KIND_SLAB_ALLOC_INIT
        # Packed AST node constructor: every field value is frozen into the
        # AST arena and stored in the node (w_ast_freeze_if_array keeps the
        # array it is handed) — the node retains all of them.
        escape_mark_args(wire_get(inst, :fields), true, state)

      when WIRE_KIND_TYPED_ARRAY_STORE_U64, WIRE_KIND_VIEW_STORE_INLINE_ELEM
        # Raw stores whose slot may hold a boxed WValue (w64[] arrays,
        # `- data` inline element slots).
        escape_mark_value(wire_get(inst, :value), true, state)

      when WIRE_KIND_CLASS_ADD_METHOD, WIRE_KIND_CLASS_ADD_STATIC_METHOD, WIRE_KIND_CLASS_ADD_IVAR, WIRE_KIND_TYPE_CLASS_REGISTER, WIRE_KIND_NODE_KIND_CLASS_REGISTER
        has_side_effects = true
        escape_mark_value(wire_get(inst, :class_temp), true, state)

      when WIRE_KIND_CLASS_NEW
        has_side_effects = true
        escape_mark_value(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_NEW_SUPER_REG), true, state)

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
      kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
      if kid == WIRE_KIND_CALL_DIRECT_I64 || kid == WIRE_KIND_CALL_DIRECT_VOID
        cn = kid == WIRE_KIND_CALL_DIRECT_I64 ? ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME) : ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_NAME)
        callee_idx = fn_map[cn]
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

-> escape_tarjan_sccs_bottom_up(n, adj)
  index_of = Array.new(n)
  lowlink = Array.new(n)
  on_stack = Array.new(n)
  tarjan_stack = []
  call_v = []
  call_ei = []
  next_index = 0
  sccs = []
  root = 0
  while root < n
    if index_of[root] == nil
      index_of[root] = next_index
      lowlink[root] = next_index
      next_index += 1
      on_stack[root] = true
      tarjan_stack.push(root)
      call_v.push(root)
      call_ei.push(0)
      while call_v.size() > 0
        top = call_v.size() - 1
        v = call_v[top]
        ei = call_ei[top]
        edges = adj[v]
        n_edges = edges == nil ? 0 : edges.size()
        if ei < n_edges
          w = edges[ei]
          call_ei[top] = ei + 1
          if index_of[w] == nil
            index_of[w] = next_index
            lowlink[w] = next_index
            next_index += 1
            on_stack[w] = true
            tarjan_stack.push(w)
            call_v.push(w)
            call_ei.push(0)
          elsif on_stack[w] == true
            if index_of[w] < lowlink[v]
              lowlink[v] = index_of[w]
        else
          call_v.pop()
          call_ei.pop()
          if lowlink[v] == index_of[v]
            scc = []
            popping = true
            while popping
              w = tarjan_stack.pop()
              on_stack[w] = false
              scc.push(w)
              if w == v
                popping = false
            if scc.size() > 1
              si = 1
              while si < scc.size()
                cur = scc[si]
                sj = si
                while sj > 0 && cur < scc[sj - 1]
                  scc[sj] = scc[sj - 1]
                  sj -= 1
                scc[sj] = cur
                si += 1
            sccs.push(scc)
          if call_v.size() > 0
            parent = call_v[call_v.size() - 1]
            if lowlink[v] < lowlink[parent]
              lowlink[parent] = lowlink[v]
    root += 1
  sccs

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

  pending_slot = Array.new(n_funcs)
  pending = []
  fi = 0
  while fi < n_funcs
    pre = precomputed[fi]
    if pre != nil
      fn_escs[functions[fi][:name]] = pre
    elsif functions[fi][:blocks].size() > 0 && functions[fi][:params] != nil
      pending_slot[fi] = pending.size()
      pending.push(fi)
    fi += 1

  n_pending = pending.size()
  if n_pending > 0
    pending_adj = Array.new(n_pending)
    pi = 0
    while pi < n_pending
      fi = pending[pi]
      edges = calls_to[fi]
      sub_edges = nil
      if edges != nil
        ei = 0
        while ei < edges.size()
          ps = pending_slot[edges[ei]]
          if ps != nil
            if sub_edges == nil
              sub_edges = []
            sub_edges.push(ps)
          ei += 1
      pending_adj[pi] = sub_edges
      pi += 1
    sccs = escape_tarjan_sccs_bottom_up(n_pending, pending_adj)
    si = 0
    while si < sccs.size()
      scc = sccs[si]
      ci = 0
      while ci < scc.size()
        func = functions[pending[scc[ci]]]
        if func[:blocks].size() > 0
          escape_analyze(func, mod, fn_escs, strings)
        ci += 1
      si += 1

  mod[:fn_escs] = fn_escs
