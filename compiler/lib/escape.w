# Escape analysis — per-function summaries of which parameters escape.
# Bottom-up walk: leaf functions first, callers use callee summaries.
# Stores results in mod[:fn_escs] keyed by function name.

# Known impure operations (I/O, syscalls, mutation)
-> is_impure_call(name)
  if name in ("w_puts" "w_print" "w_write_file" "w_read_file")
    return true
  if name in ("w_system" "w_exit" "w_raise" "w_env")
    return true
  if name in ("w_goroutine_spawn" "w_thread_spawn" "w_thread_spawn_slots" "w_flush" "w_read_bytes" "w_read_line_stdin")
    return true
  if name == "w_slab_freeze_safe"
    return true
  if name in ("__w_print" "__w_read_file" "__w_read_file_bytes" "__w_write_file" "__w_system")
    return true
  if name in ("__w_capture" "__w_exit" "__w_env" "__w_file_mtime_ns")
    return true
  if name in ("__w_file_exists" "__w_cache_read" "__w_cache_write")
    return true
  if name in ("__w_clock" "__w_clock_ms" "__w_sleep_ms")
    return true
  # Metal bridge — every w_metal_* call either allocates a retained
  # Obj-C object or mutates GPU-visible buffer state, so none of them
  # can be cached. Treat the whole namespace as impure.
  if name in ("w_metal_device_default" "w_metal_buffer_new" "w_metal_buffer_length")
    return true
  if name in ("w_metal_buffer_write_f32" "w_metal_buffer_write_i32" "w_metal_buffer_write_f16")
    return true
  if name in ("w_metal_buffer_read_f32" "w_metal_buffer_read_i32" "w_metal_buffer_read_f16")
    return true
  if name in ("w_metal_compile_source" "w_metal_compile_source_opts" "w_metal_library_from_file" "w_metal_pipeline_for" "w_metal_queue_new")
    return true
  if name in ("w_metal_dispatch1" "w_metal_dispatch_n" "w_metal_dispatch_groups")
    return true
  if name in ("w_metal_batch_begin" "w_metal_batch_commit" "w_metal_batch_commit_ms")
    return true
  if name in ("w_metal_batch_commit_async" "w_metal_command_buffer_wait")
    return true
  if name in ("w_metal_batch_begin_concurrent" "w_metal_batch_barrier")
    return true
  if name == "w_metal_set_threadgroup_memory"
    return true
  if name == "w_metal_pipeline_for_with_int_constants"
    return true
  if name == "w_metal_binary_archive_new"
    return true
  if name == "w_metal_batch_barrier_resources"
    return true
  if name in ("w_metal_buffer_write_from_mmap" "w_metal_fp8_e4m3_gather_rows" "w_q8_split_blocks" "w_q8_dequant_row")
    return true
  return false

# Builtins whose ARGUMENTS never escape into the result or globals. Most
# are read-only; the w_str_concat_free_* variants additionally RELEASE an
# operand (a side effect), so this list must never be used to justify
# dead-call elimination, reordering, or CSE — only escape marking.
-> is_pure_builtin(name)
  name in ("w_add" "w_sub" "w_mul" "w_div" "w_mod" "w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "w_lt" "w_gt" "w_lte" "w_gte" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "w_bit_and" "w_bit_or" "w_bit_xor" "w_bit_shl" "w_bit_shr" "w_negate" "w_not" "w_to_s" "w_int_to_s" "w_to_i" "w_to_f" "w_string" "w_str_to_sym" "w_str_concat" "w_str_concat_free_rhs" "w_str_concat_free_lhs" "w_str_length" "w_string_byte_length" "__w_type" "w_hash_new" "w_array_new" "w_box_int_checked" "w_wire_sequence_from_array")

# Param index for a WIRE value: a parameter register itself, or a temp the
# forward derivation walk below traced back to one. nil when unrelated.
-> escape_param_source(value, temp_from_param, param_idx)
  if value == nil
    return nil
  src = temp_from_param[value]
  if src != nil
    return src
  if type(value) == "String" && value.size() > 1
    bare = value
    if bare.starts_with?("%")
      bare = value.slice(1, value.size() - 1)
    return param_idx[bare]
  nil

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

# Alias-carrying operand fields of value-producing ops the main walk has no
# specific rule for: conversions (:value, :boxed, :raw), container and
# pointer bases (:arr, :base, :ptr), and arithmetic that may be pointer
# arithmetic (:lhs, :rhs). The result inherits the first param derivation
# found among them.
-> escape_derive_result_from_fields(inst, state)
  temp = wire_get(inst, :temp)
  if temp == nil
    return nil
  fields = [:value, :boxed, :raw, :arr, :base, :ptr, :lhs, :rhs]
  fi = 0
  while fi < fields.size()
    src = escape_param_source(wire_get(inst, fields[fi]), state[:temp_from_param], state[:param_idx])
    if src != nil
      state[:temp_from_param][temp] = src
      return nil
    fi += 1
  nil

# Concat variants that RELEASE or take ownership of an operand: an argument
# handed to one of these is consumed, never merely read.
-> is_consuming_builtin(name)
  name in ("w_str_concat_free_lhs" "w_str_concat_free_rhs" "w_str_concat_own")

# Analyze one function: which parameters escape (stored somewhere that
# outlives the call, or returned) and whether the function is pure.
#
# Instruction coverage mirrors ownership.w's mark_escapes op-for-op. The
# ownership pass consumes these summaries to avoid pinning a caller's
# argument (or the fresh object a guarded `Cls.new` produced) as escaped, so
# every instruction that can retain a value there must mark a param-derived
# value here. Derivation is tracked forward through phis, selects, results
# of pure builtins, and results of callees that return a parameter.
-> escape_analyze(func, mod, fn_escs)
  params = func[:params]
  if params == nil
    return nil

  param_escaped = []
  param_stored = []
  param_idx = {}
  pi = 0
  while pi < params.size()
    param_escaped.push(false)
    param_stored.push(false)
    param_idx[params[pi]] = pi
    pi += 1

  state = {param_escaped: param_escaped, param_stored: param_stored, param_idx: param_idx, temp_from_param: {}}
  temp_from_param = state[:temp_from_param]
  has_side_effects = false

  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = wire_kind(inst)

      if op == :phi_ssa
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

      elsif op in (:call_direct_i64 :call_direct_void)
        call_name = wire_get(inst, :name)
        args = wire_get(inst, :args)
        if is_consuming_builtin(call_name)
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
              ai += 1
          if is_impure_call(call_name)
            has_side_effects = true

      elsif op == :call_method_i64
        has_side_effects = true
        escape_mark_args(wire_get(inst, :args), true, state)
        escape_mark_value(wire_get(inst, :receiver), true, state)

      elsif op == :ret_i64
        escape_mark_value(wire_get(inst, :value), false, state)

      elsif op in (:ivar_set :ivar_set_idx :store_global :store_cvar :class_store)
        has_side_effects = true
        escape_mark_value(wire_get(inst, :value), true, state)

      elsif op in (:store_ptr :store_i64 :view_store_field :store_memo_ptr :slab_node_set_idx)
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
    pure: !has_side_effects,
    param_count: params.size()
  }

# Build a call graph and process functions bottom-up.
# Leaf functions (no calls to other user-defined functions) first.
-> escape_pass(mod)
  fn_escs = {}
  functions = mod[:functions]

  # Build name → function index map
  fn_map = {}
  fi = 0
  while fi < functions.size()
    fn_map[functions[fi][:name]] = fi
    fi += 1

  # Collect call edges: which functions call which
  calls_to = {}  # fn_name → [callee_name, ...]
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    edges = []
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if wire_kind(inst) in (:call_direct_i64 :call_direct_void)
          if fn_map[wire_get(inst, :name)] != nil
            found = false
            ei = 0
            while ei < edges.size()
              if edges[ei] == wire_get(inst, :name)
                found = true
              ei += 1
            if !found
              edges.push(wire_get(inst, :name))
        ii += 1
      bi += 1
    calls_to[func[:name]] = edges
    fi += 1

  # Topological sort: process functions with no unprocessed callees first
  processed = {}
  order = []
  # Simple iterative topo sort: keep scanning until all processed
  remaining = functions.size()
  while remaining > 0
    progress = false
    fi = 0
    while fi < functions.size()
      func = functions[fi]
      if processed[func[:name]] != true
        # Check if all callees are processed
        edges = calls_to[func[:name]]
        all_done = true
        ei = 0
        while ei < edges.size()
          if processed[edges[ei]] != true
            all_done = false
          ei += 1
        if all_done
          order.push(fi)
          processed[func[:name]] = true
          remaining = remaining - 1
          progress = true
      fi += 1
    if !progress
      # Cycle detected (recursion): process remaining in any order
      fi = 0
      while fi < functions.size()
        if processed[functions[fi][:name]] != true
          order.push(fi)
          processed[functions[fi][:name]] = true
          remaining = remaining - 1
        fi += 1

  # Analyze in topological order
  oi = 0
  while oi < order.size()
    func = functions[order[oi]]
    if func[:blocks].size() > 0
      escape_analyze(func, mod, fn_escs)
    oi += 1

  mod[:fn_escs] = fn_escs
