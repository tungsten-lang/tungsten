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
  if name in ("w_metal_buffer_write_from_mmap" "w_q8_split_blocks" "w_q8_dequant_row")
    return true
  return false

# Known pure builtins (read-only, no side effects, args don't escape)
-> is_pure_builtin(name)
  name in ("w_add" "w_sub" "w_mul" "w_div" "w_mod" "w_eq" "w_neq" "w_lt" "w_gt" "w_lte" "w_gte" "w_bit_and" "w_bit_or" "w_bit_xor" "w_bit_shl" "w_bit_shr" "w_negate" "w_not" "w_to_s" "w_to_i" "w_to_f" "w_string" "w_str_to_sym" "w_str_concat" "w_str_length" "__w_type" "w_hash_new" "w_array_new" "w_box_int_checked")

# Analyze one function: determine which params escape and whether it's pure.
-> escape_analyze(func, mod, fn_escs)
  params = func[:params]
  if params == nil
    return nil

  # Track which params escape: param_escaped[i] = true/false
  param_escaped = []
  pi = 0
  while pi < params.size()
    param_escaped.push(false)
    pi += 1

  # Build param name → index map
  param_idx = {}
  pi = 0
  while pi < params.size()
    param_idx[params[pi]] = pi
    pi += 1

  # Track: does this function have side effects?
  has_side_effects = false

  # Track which temps flow from which params (simple forward dataflow)
  # temp_from_param[temp] = param_index (or nil if not from a param)
  temp_from_param = {}

  # Walk all blocks
  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = inst[:op]

      # Phi: if any incoming is from a param, the phi result is from that param
      if op == :phi_ssa
        incoming = inst[:incoming]
        if incoming != nil
          pi = 0
          while pi < incoming.size()
            src_param = temp_from_param[incoming[pi]]
            if src_param != nil
              temp_from_param[inst[:temp]] = src_param
            # Also check if incoming value is a param register directly
            pname = incoming[pi]
            if pname != nil && type(pname) == "String" && pname.size() > 1
              bare = pname
              if bare.starts_with?("%")
                bare = pname.slice(1, pname.size() - 1)
              pidx = param_idx[bare]
              if pidx != nil
                temp_from_param[inst[:temp]] = pidx
            pi += 2

      # Check if instruction uses a param value
      # For call args: if an arg is a param (or derived from param), mark it escaped
      if op in (:call_direct_i64 :call_direct_void)
        call_name = inst[:name]
        # Pure builtins: args don't escape
        if !is_pure_builtin(call_name)
          # Check callee escape summary if available
          callee_escs = fn_escs[call_name]
          args = inst[:args]
          if args != nil
            ai = 0
            while ai < args.size()
              arg = args[ai]
              # Check if this arg is a param or derived from one
              src = temp_from_param[arg]
              if src == nil
                # Check if arg is directly a param register
                if arg != nil && type(arg) == "String" && arg.size() > 1
                  bare = arg
                  if bare.starts_with?("%")
                    bare = arg.slice(1, arg.size() - 1)
                  pidx = param_idx[bare]
                  if pidx != nil
                    src = pidx
              if src != nil
                # Does this callee escape this arg position?
                if callee_escs != nil && callee_escs[:escs] != nil && ai < callee_escs[:escs].size()
                  if callee_escs[:escs][ai] == true
                    param_escaped[src] = true
                else
                  # Unknown callee or no summary: conservatively escape
                  param_escaped[src] = true
              ai += 1
          # Impure calls cause side effects
          if is_impure_call(call_name)
            has_side_effects = true

      elsif op == :call_method_i64
        # Dynamic dispatch: all param-derived args escape, and it's impure
        has_side_effects = true
        args = inst[:args]
        if args != nil
          ai = 0
          while ai < args.size()
            src = temp_from_param[args[ai]]
            if src != nil
              param_escaped[src] = true
            ai += 1
        # Receiver too
        if inst[:receiver] != nil
          src = temp_from_param[inst[:receiver]]
          if src != nil
            param_escaped[src] = true

      elsif op == :ret_i64
        # Returned value: if derived from param, that param escapes
        src = temp_from_param[inst[:value]]
        if src != nil
          param_escaped[src] = true

      elsif op == :ivar_set
        has_side_effects = true
        src = temp_from_param[inst[:value]]
        if src != nil
          param_escaped[src] = true

      elsif op == :store_global
        has_side_effects = true
        src = temp_from_param[inst[:value]]
        if src != nil
          param_escaped[src] = true

      elsif op == :store_ptr
        src = temp_from_param[inst[:value]]
        if src != nil
          param_escaped[src] = true

      ii += 1
    bi += 1

  # Store summary
  fn_escs[func[:name]] = {
    escs: param_escaped,
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
        if inst[:op] in (:call_direct_i64 :call_direct_void)
          if fn_map[inst[:name]] != nil
            found = false
            ei = 0
            while ei < edges.size()
              if edges[ei] == inst[:name]
                found = true
              ei += 1
            if !found
              edges.push(inst[:name])
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
