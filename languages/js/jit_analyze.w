# jsn/jit_analyze — Static + profile-guided analysis for the ARM64 JS JIT.
#
# Performs:
#   1. Eligibility checking (which functions / loops the ARM64 JIT compiles)
#   2. Intra-procedural Escape Analysis + Scalar Replacement of Aggregates (SRA)
#      for non-escaping object literals and non-escaping closure factories
#   3. Fixed-point numeric type inference (i32 vs f64 vs any) for locals & SRA fields
#   4. Self-recursive unboxed fast-entry detection (e.g. fib(n))
#   5. Loop-invariant binding discovery (for hoisting TypedArray/Array/shape/cell guards)
#   6. Inlineable function / method body inspection

in JS

# Local / expression representation kinds
JT_ANY      = 0   # boxed WValue (64-bit)
JT_I32      = 1   # unboxed signed 32-bit int in W register
JT_F64      = 2   # unboxed IEEE-754 double in D register
JT_SRA_OBJ  = 3   # scalar-replaced non-escaping object literal
JT_SRA_CLOS = 4   # scalar-replaced non-escaping closure
JT_SRA_RX   = 5   # scalar-replaced non-escaping RegExp exec match result
JT_SRA_VS   = 6   # scalar-replaced non-escaping pure-ctor value struct (e.g. Vec3)
JT_U32      = 7   # unboxed unsigned 32-bit int in W register (0..4294967295)

# Describes a scalar-replaced local object literal: { k0: ..., k1: ... }
+ JitSraObj
  rw :lidx, :keys, :field_slots, :const_i32   # keys: [String], field_slots: key -> virtual local idx
  -> new(@lidx, @keys)
    @field_slots = {}
    @const_i32 = {}

# Describes a scalar-replaced local pure-ctor value struct (e.g. `var oc = ro.sub(this.c)`)
+ JitSraVs
  rw :lidx, :ctor_info, :keys, :field_slots   # field_slots: key -> virtual JT_F64 slot idx
  -> new(@lidx, @ctor_info, @keys)
    @field_slots = {}

# Describes a scalar-replaced local closure: var f = factory(arg0, ...)
+ JitSraClos
  rw :lidx, :factory_binding, :factory_fn, :inner_jf, :cap_slots, :arg_count
  -> new(@lidx, @factory_binding, @factory_fn, @inner_jf, @cap_slots, @arg_count)
    nil

# Result of analyzing a function or OSR loop for ARM64 JIT compilation.
+ JitInfo
  rw :jf, :is_osr, :loop_node, :nlocals, :total_slots, :types, :sra_objs, :sra_clos, :sra_rxs, :sra_vs
  rw :written_in_loop, :fast_rec, :fast_rec_cell, :fast_rec_kind
  rw :reg_gpr, :reg_fpr, :spill_off, :frame_size, :uses_calls, :uses_env, :uses_this
  rw :has_loop, :hot_counts, :ta_invariants, :arr_invariants, :obj_invariants, :global_tas
  rw :param_arrs, :param_tas, :param_nums, :param_ints, :param_nonneg_ints, :param_shapes, :param_strs, :local_tas, :str_locals, :needs_entry_epoch
  rw :mono_arr_num_locals, :mono_arr_num_sh
  rw :bit32_only, :global_i32s, :global_objs, :local_ta_lens, :ta_len_locals, :nonneg_locals, :helper_owner, :local_arrs, :ro_keys_locals, :ro_keys_calls, :demote_env, :demoted_env, :inlined_fns, :nbase_slots, :proven_bounded_i32, :vs_fn_sig

  -> new(@jf, @is_osr, @loop_node)
    @nlocals = @jf.nlocals
    @nbase_slots = @nlocals
    @total_slots = @nlocals
    @types = Array.new(@nlocals, JT_ANY)
    @sra_objs = {}       # lidx -> JitSraObj
    @sra_clos = {}       # lidx -> JitSraClos
    @sra_rxs = {}        # lidx -> i64[32] caps buffer
    @sra_vs = {}         # lidx -> JitSraVs
    @written_in_loop = {}
    @fast_rec = false
    @fast_rec_cell = nil
    @fast_rec_kind = 0   # 1 = i32, 2 = f64
    @reg_gpr = {}        # slot -> ARM64 GPR (R_X22..R_X28)
    @reg_fpr = {}        # slot -> ARM64 FPR (R_D8..R_D15)
    @spill_off = {}      # slot -> positive offset from SP
    @frame_size = 0
    @uses_calls = false
    @uses_env = false
    @uses_this = @jf.uses_this
    @has_loop = false
    @hot_counts = Array.new(@nlocals, 0)
    @ta_invariants = {}   # lidx -> kind
    @arr_invariants = {}  # lidx -> true
    @obj_invariants = {}  # lidx -> shape_bits
    @global_tas = {}      # JaBinding -> [ta_kind, cell, ta_obj]
    @param_arrs = {}      # lidx -> true (read-only array param hoisted in fn prologue!)
    @param_tas = {}       # lidx -> ta_kind (read-only TypedArray param hoisted in fn prologue!)
    @param_nums = {}      # lidx -> true (read-only numeric param unboxed in fn prologue!)
    @param_ints = {}      # lidx -> true (read-only integer loop-bound param unboxed as i32 in fn prologue!)
    @param_nonneg_ints = {} # lidx -> 1 ([0, 1048576]) or 2 ([1, 1048576]) guarded in fn prologue!
    @param_shapes = {}    # lidx -> JS:Shape observed in warm_args
    @param_strs = {}      # lidx -> true (read-only String param observed in warm_args!)
    @local_tas = {}       # lidx -> ta_kind (local `var a = new Uint8Array(...)` assigned once!)
    @str_locals = {}      # lidx -> true (local assigned ONLY string literals!)
    @needs_entry_epoch = false
    @mono_arr_num_locals = {}  # lidx -> true (element local of prologue-verified all-number object array!)
    @mono_arr_num_sh = 0
    @bit32_only = {}      # slot -> true (all reads depend only on low 32 bits)
    @global_i32s = {}     # JaBinding -> [i32_val, cell, wval]
    @global_objs = {}     # JaBinding -> [cell, gv] (read-only global object/array/fn guarded once at entry!)
    @local_ta_lens = {}   # slot -> constant positive int32 length
    @ta_len_locals = {}   # slot -> ta_slot (single-write `var n = ta.length`)
    @nonneg_locals = {}   # slot -> true (proven non-negative JT_I32 local)
    @helper_owner = {}    # vslot -> helper_idx (0, 1, ...) for mutually-disjoint inlined helper locals!
    @local_arrs = {}      # slot -> true (`var a = []` assigned once, safe dense push-only array)
    @ro_keys_locals = {}  # slot -> true (`var ks = Object.keys(o)` read-only non-escaping!)
    @ro_keys_calls = {}   # call JsNode -> true (Object.keys call whose result never escapes/mutates!)
    @demote_env = false   # true when all nested fns are non-escaping & inlined (eliminates JS:Env!)
    @demoted_env = {}     # JaBinding -> flat vslot index
    @inlined_fns = {}     # fn JaBinding -> [helper_jf, param_vslots, ret_exprs]
    @proven_bounded_i32 = {} # slot -> proven strict upper bound (0 <= slot < ub) via dominating range guard!
    @vs_fn_sig = nil         # [param_specs, ret_ci] for unboxed value-struct ABI (`jit_vs_fp`)!

  -> alloc_vslot(ty = JT_ANY)
    id = @total_slots
    @total_slots += 1
    @types.push(ty)
    @hot_counts.push(10)
    id

  -> release
    ccall("w_value_free_w", @types) if @types != nil
    ccall("w_value_free_w", @hot_counts) if @hot_counts != nil
    ccall("w_value_free_w", @sra_objs) if @sra_objs != nil
    ccall("w_value_free_w", @sra_clos) if @sra_clos != nil
    ccall("w_value_free_w", @sra_rxs) if @sra_rxs != nil
    ccall("w_value_free_w", @sra_vs) if @sra_vs != nil
    ccall("w_value_free_w", @written_in_loop) if @written_in_loop != nil
    ccall("w_value_free_w", @reg_gpr) if @reg_gpr != nil
    ccall("w_value_free_w", @reg_fpr) if @reg_fpr != nil
    ccall("w_value_free_w", @spill_off) if @spill_off != nil
    ccall("w_value_free_w", @ta_invariants) if @ta_invariants != nil
    ccall("w_value_free_w", @arr_invariants) if @arr_invariants != nil
    ccall("w_value_free_w", @obj_invariants) if @obj_invariants != nil
    ccall("w_value_free_w", @global_tas) if @global_tas != nil
    ccall("w_value_free_w", @param_arrs) if @param_arrs != nil
    ccall("w_value_free_w", @param_tas) if @param_tas != nil
    ccall("w_value_free_w", @param_nums) if @param_nums != nil
    ccall("w_value_free_w", @param_ints) if @param_ints != nil
    ccall("w_value_free_w", @param_nonneg_ints) if @param_nonneg_ints != nil
    ccall("w_value_free_w", @param_shapes) if @param_shapes != nil
    ccall("w_value_free_w", @param_strs) if @param_strs != nil
    ccall("w_value_free_w", @local_tas) if @local_tas != nil
    ccall("w_value_free_w", @str_locals) if @str_locals != nil
    ccall("w_value_free_w", @mono_arr_num_locals) if @mono_arr_num_locals != nil
    ccall("w_value_free_w", @bit32_only) if @bit32_only != nil
    ccall("w_value_free_w", @global_i32s) if @global_i32s != nil
    ccall("w_value_free_w", @global_objs) if @global_objs != nil
    ccall("w_value_free_w", @local_ta_lens) if @local_ta_lens != nil
    ccall("w_value_free_w", @ta_len_locals) if @ta_len_locals != nil
    ccall("w_value_free_w", @nonneg_locals) if @nonneg_locals != nil
    ccall("w_value_free_w", @helper_owner) if @helper_owner != nil
    ccall("w_value_free_w", @local_arrs) if @local_arrs != nil
    ccall("w_value_free_w", @ro_keys_locals) if @ro_keys_locals != nil
    ccall("w_value_free_w", @ro_keys_calls) if @ro_keys_calls != nil
    ccall("w_value_free_w", @demoted_env) if @demoted_env != nil
    ccall("w_value_free_w", @inlined_fns) if @inlined_fns != nil
    ccall("w_value_free_w", @proven_bounded_i32) if @proven_bounded_i32 != nil
    ccall("w_value_free_w", self)
    nil

# Inter-procedural static escape analysis for region-scoped bump allocation (Tofte-Talpin style!).
# Returns `[allow_arr, epoch_at_compile, [[cell, fn], ...]]` if `jf` is 100% proven non-escaping:
#   - 0 parameters, no `this`, no captures, returns ONLY primitives
#   - no writes to globals or outer closure slots anywhere in its transitive call graph
#   - no closures, no eval/with/try/Proxy/WeakMap/Promise, only statically verified JS callees & pure builtins!
# When `allow_arr == true`, fixed-size 1..8 arrays never grow via push/unshift/splice, so both JS:Objects AND
# fixed-size WArrays bump-allocate safely with ZERO leaks and ZERO GC pressure!
-> jit_region_local_prim_writes?(n, li, jf, info, seen)
  return true if n == nil
  if n.is_a?(Array)
    i = 0
    while i < n.size
      return false if !jit_region_local_prim_writes?(n[i], li, jf, info, seen)
      i += 1
    return true
  return true if !n.is_a?(JsNode)
  k = n.kind
  if k == :var_decl && n.list.is_a?(Array)
    i = 0
    while i < n.list.size
      d = n.list[i]
      if d.a.kind == :ident && d.a.x != nil && d.a.x.binding != nil && !d.a.x.binding.global? && d.a.x.binding.slot < 0 && d.a.x.binding.scope.func == jf && d.a.x.binding.lidx == li
        return false if d.b != nil && !jit_region_expr_prim?(d.b, info, seen)
      i += 1
    return true
  if k == :assign && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && !n.a.x.binding.global? && n.a.x.binding.slot < 0 && n.a.x.binding.scope.func == jf && n.a.x.binding.lidx == li
    op = n.str
    if op == "="
      return false if !jit_region_expr_prim?(n.b, info, seen)
    elsif op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%=" || op == "|=" || op == "&=" || op == "^=" || op == "<<=" || op == ">>=" || op == ">>>=" || op == "**="
      nil # Always evaluates to Number or String (primitive)!
    else
      return false
  return false if !jit_region_local_prim_writes?(n.a, li, jf, info, seen)
  return false if !jit_region_local_prim_writes?(n.b, li, jf, info, seen)
  return false if !jit_region_local_prim_writes?(n.c, li, jf, info, seen)
  return false if !jit_region_local_prim_writes?(n.d, li, jf, info, seen)
  jit_region_local_prim_writes?(n.list, li, jf, info, seen)

-> jit_region_expr_prim?(e, info, seen = nil)
  return true if e == nil
  k = e.kind
  return true if k == :num || k == :string || k == :true || k == :false || k == :null || k == :unary || k == :update
  if k == :ident && e.x != nil && e.x.binding != nil
    b = e.x.binding
    if !b.global? && b.slot < 0 && b.scope.func == info.jf && b.lidx >= 0 && b.lidx < info.types.size
      t = info.types[b.lidx]
      return true if t == JT_I32 || t == JT_U32 || t == JT_F64
      seen = {} if seen == nil
      return true if seen[b.lidx] == true
      seen[b.lidx] = true
      return jit_region_local_prim_writes?(info.jf.node.b, b.lidx, info.jf, info, seen)
    return false
  if k == :binary
    op = e.str
    return true if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "!==" || op == "==" || op == "!="
  if k == :cond
    return jit_region_expr_prim?(e.b, info, seen) && jit_region_expr_prim?(e.c, info, seen)
  if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
    return true
  false

-> jit_region_guard_cell(cell, val, guards, guard_seen)
  if guard_seen[cell] == nil
    guard_seen[cell] = true
    guards.push([cell, val])
  nil

-> jit_region_scan_locals(stmts, jf, emp_arrs, obj_lits, new_arrs)
  return nil if stmts == nil
  if stmts.is_a?(Array)
    stmts.each ->(x) jit_region_scan_locals(x, jf, emp_arrs, obj_lits, new_arrs)
    return nil
  return nil if !stmts.is_a?(JsNode)
  k = stmts.kind
  if k == :var_decl
    stmts.list.each ->(d)
      if d.a.kind == :ident && d.a.x != nil && d.a.x.binding != nil
        b = d.a.x.binding
        if !b.global? && b.slot < 0 && b.scope.func == jf
          if d.b != nil && d.b.kind == :array && d.b.list.size == 0
            emp_arrs[b.lidx] = true if emp_arrs[b.lidx] == nil
            obj_lits[b.lidx] = false
            new_arrs[b.lidx] = false
          elsif d.b != nil && d.b.kind == :object
            obj_lits[b.lidx] = true if obj_lits[b.lidx] == nil
            emp_arrs[b.lidx] = false
            new_arrs[b.lidx] = false
          elsif d.b == nil || d.b.kind == :null
            emp_arrs[b.lidx] = false
            new_arrs[b.lidx] = false
          elsif d.b != nil && d.b.kind == :new && d.b.a != nil && d.b.a.kind == :ident && d.b.a.str == "Array" && d.b.list.size == 1
            new_arrs[b.lidx] = (new_arrs[b.lidx] == nil ? d.b.list[0] : false)
            emp_arrs[b.lidx] = false
            obj_lits[b.lidx] = false
          else
            emp_arrs[b.lidx] = false
            obj_lits[b.lidx] = false
            new_arrs[b.lidx] = false
  elsif k == :assign && stmts.a.kind == :ident && stmts.a.x != nil && stmts.a.x.binding != nil
    b = stmts.a.x.binding
    if !b.global? && b.slot < 0 && b.scope.func == jf
      if stmts.b != nil && stmts.b.kind == :object && obj_lits[b.lidx] == nil
        obj_lits[b.lidx] = true
      elsif !(stmts.b != nil && stmts.b.kind == :null && obj_lits[b.lidx] == true)
        obj_lits[b.lidx] = false
      emp_arrs[b.lidx] = false
      new_arrs[b.lidx] = false
  jit_region_scan_locals(stmts.a, jf, emp_arrs, obj_lits, new_arrs)
  jit_region_scan_locals(stmts.b, jf, emp_arrs, obj_lits, new_arrs)
  jit_region_scan_locals(stmts.c, jf, emp_arrs, obj_lits, new_arrs)
  jit_region_scan_locals(stmts.d, jf, emp_arrs, obj_lits, new_arrs)
  jit_region_scan_locals(stmts.list, jf, emp_arrs, obj_lits, new_arrs) if stmts.list.is_a?(Array)
  nil

-> jit_region_same_len_expr?(a, b, jf)
  return false if !a.is_a?(JsNode) || !b.is_a?(JsNode) || a.kind != b.kind
  if a.kind == :ident
    return a.x != nil && b.x != nil && a.x.binding != nil && a.x.binding == b.x.binding && a.x.binding.writes == 0
  if a.kind == :member && !a.has?(F_COMPUTED) && !b.has?(F_COMPUTED) && a.b.str == "length" && b.b.str == "length"
    return jit_region_same_len_expr?(a.a, b.a, jf)
  false

-> jit_region_check_fn?(jf, root_info, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  return false if depth > 6
  return true if visited[jf] == true
  return false if jf.dynamic || jf.mapped_args || jf.args_binding != nil || !jf.simple || jf.arrow || jf.uses_this
  return false if jf.free.size > 0 || jf.scope.has_env? || (jf.body_scope != nil && jf.body_scope.has_env?)
  return false if jf.node.has?(F_ASYNC) || jf.node.has?(F_GENERATOR) || !jf.node.b.is_a?(Array)
  visited[jf] = true
  emp_arrs = {}
  obj_lits = {}
  new_arrs = {}
  jit_region_scan_locals(jf.node.b, jf, emp_arrs, obj_lits, new_arrs)
  fn_emp_arrs[jf] = emp_arrs
  jit_region_check_node?(jf.node.b, jf, root_info, emp_arrs, obj_lits, new_arrs, nil, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)

-> jit_region_check_node?(n, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  return true if n == nil
  if n.is_a?(Array)
    i = 0
    while i < n.size
      return false if !jit_region_check_node?(n[i], jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
      i += 1
    return true
  return true if !n.is_a?(JsNode)
  k = n.kind
  return false if k == :function || k == :arrow || k == :class || k == :with || k == :try || k == :debugger || k == :yield || k == :await || k == :spread || k == :tagged_template || k == :import || k == :export || k == :this || k == :super || k == :delete
  if k == :ident && n.x != nil && n.x.binding != nil && n.x.binding.global?
    gcell = wk_cell(n.x.binding)
    gv = gcell.value
    ok_g = js_string?(gv) || js_number?(gv) || gv == true || gv == false || gv == nil || gv == JS_NULL || (gv.is_a?(JS:Special) && gv.shape == js_realm().regexp_shape)
    return false if !ok_g
    jit_region_guard_cell(gcell, gv, guards, guard_seen)
    return true
  if k == :for
    # Recognize `for (var i = 0; i < L; i++)` so `arr[i] = ...` on `var arr = new Array(L)` is proven in-bounds!
    lb = loop_bound
    if n.a != nil && n.a.kind == :var_decl && n.a.list.size == 1 && n.a.list[0].a.kind == :ident && n.a.list[0].a.x != nil && n.a.list[0].a.x.binding != nil && n.a.list[0].b != nil && n.a.list[0].b.kind == :num && n.a.list[0].b.a == ~0.0
      ib = n.a.list[0].a.x.binding
      if n.b != nil && n.b.kind == :binary && n.b.str == "<" && n.b.a.kind == :ident && n.b.a.x != nil && n.b.a.x.binding == ib
        if n.c != nil && n.c.kind == :update && n.c.str == "++" && n.c.a.kind == :ident && n.c.a.x != nil && n.c.a.x.binding == ib
          lb = [ib, n.b.b]
    return false if !jit_region_check_node?(n.a, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
    return false if !jit_region_check_node?(n.b, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
    return false if !jit_region_check_node?(n.c, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
    return jit_region_check_node?(n.d, jf, root_info, emp_arrs, obj_lits, new_arrs, lb, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  if k == :return && root_info != nil
    return false if !jit_region_expr_prim?(n.a, root_info)
  if k == :throw
    return false unless n.a != nil && n.a.kind == :new && n.a.a != nil && n.a.a.kind == :ident && n.a.a.str == "Error"
  if k == :assign || k == :update
    lhs = n.a
    if lhs.kind == :ident && lhs.x != nil && lhs.x.binding != nil
      b = lhs.x.binding
      return false if b.global? || b.slot >= 0
    elsif lhs.kind == :member
      return false if !lhs.has?(F_COMPUTED) && (lhs.b.str == "__proto__" || lhs.b.str == "prototype")
      if !lhs.has?(F_COMPUTED) && lhs.b.str == "length"
        allow_arr[0] = false
      elsif lhs.has?(F_COMPUTED)
        safe_idx_w = false
        if lhs.a.kind == :ident && lhs.a.x != nil && lhs.a.x.binding != nil
          lb_a = lhs.a.x.binding
          if !lb_a.global? && lb_a.slot < 0 && lb_a.scope.func == jf
            if obj_lits[lb_a.lidx] == true
              safe_idx_w = true
            elsif new_arrs[lb_a.lidx].is_a?(JsNode) && loop_bound != nil && lhs.b.kind == :ident && lhs.b.x != nil && lhs.b.x.binding == loop_bound[0] && jit_region_same_len_expr?(new_arrs[lb_a.lidx], loop_bound[1], jf)
              safe_idx_w = true
        allow_arr[0] = false if !safe_idx_w
      if lhs.a.kind == :ident && lhs.a.x != nil && lhs.a.x.binding != nil && lhs.a.x.binding.global?
        return false
  if k == :member && !n.has?(F_COMPUTED)
    return false if n.b.str == "__proto__" || n.b.str == "prototype" || n.b.str == "constructor"
  if k == :new
    return false if n.a == nil || n.a.kind != :ident || n.a.x == nil || n.a.x.binding == nil || !n.a.x.binding.global?
    cn = n.a.str
    return false unless cn == "Array" || cn == "Map" || cn == "Set" || cn == "Error"
    gcell = wk_cell(n.a.x.binding)
    gv = gcell.value
    r = js_realm()
    return false if gv == nil || gv != r.intrinsics[cn]
    jit_region_guard_cell(gcell, gv, guards, guard_seen)
    return jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  if k == :call
    c = n.a
    if c.kind == :ident && c.x != nil && c.x.binding != nil && c.x.binding.global?
      fn_nm = c.str
      gcell = wk_cell(c.x.binding)
      gv = gcell.value
      if fn_nm == "String" || fn_nm == "Number" || fn_nm == "Boolean" || fn_nm == "parseInt" || fn_nm == "parseFloat" || fn_nm == "isNaN" || fn_nm == "isFinite"
        return false if gv == nil || gv != js_realm().global.get_own(fn_nm)
        jit_region_guard_cell(gcell, gv, guards, guard_seen)
        return jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
      return false if !gv.is_a?(JS:Function) || gv.code == nil || !gv.code.node.is_a?(JaFunc)
      jit_region_guard_cell(gcell, gv, guards, guard_seen)
      callee_jf = gv.code.node
      call_sites.push([jf, callee_jf, n.list])
      return false if !jit_region_check_fn?(callee_jf, nil, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth + 1)
      return jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
    if c.kind == :member && !c.has?(F_COMPUTED)
      mn = c.b.str
      if c.a.kind == :ident && c.a.x != nil && c.a.x.binding != nil && c.a.x.binding.global?
        gn = c.a.str
        gcell = wk_cell(c.a.x.binding)
        gv = gcell.value
        if gn == "Math" || (gn == "JSON" && mn == "parse") || (gn == "Array" && mn == "isArray") || (gn == "Object" && mn == "keys")
          return false if gv == nil || gv != js_realm().global.get_own(gn)
          jit_region_guard_cell(gcell, gv, guards, guard_seen)
          return jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
        if mn == "test"
          if gv.is_a?(JS:Special) && gv.shape == js_realm().regexp_shape
            jit_region_guard_cell(gcell, gv, guards, guard_seen)
            return jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
        return false
      if mn == "indexOf" || mn == "slice" || mn == "charCodeAt" || mn == "pop" || mn == "get" || mn == "set" || mn == "has" || mn == "delete" || mn == "add" || mn == "join" || mn == "startsWith" || mn == "endsWith" || mn == "includes" || mn == "trim" || mn == "toLowerCase" || mn == "toUpperCase" || mn == "split"
        return jit_region_check_node?(c.a, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth) && jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
      if mn == "push"
        # Arena arrays safely grow in-arena via js_arena_push_one (zero leaks, zero malloc)!
        return jit_region_check_node?(c.a, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth) && jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
      return false
    return false
  return false if !jit_region_check_node?(n.a, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  return false if !jit_region_check_node?(n.b, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  return false if !jit_region_check_node?(n.c, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  return false if !jit_region_check_node?(n.d, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)
  jit_region_check_node?(n.list, jf, root_info, emp_arrs, obj_lits, new_arrs, loop_bound, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, depth)

-> jit_region_analyze(jf, info)
  return nil if jf.params.size != 0 || jf.script || info.is_osr
  visited = {}
  guards = []
  guard_seen = {}
  allow_arr = [true]
  push_params = {}
  call_sites = []
  fn_emp_arrs = {}
  return jit_region_analyze_oop(jf, info) if !jit_region_check_fn?(jf, info, visited, guards, guard_seen, allow_arr, push_params, call_sites, fn_emp_arrs, 0)
  return nil if guards.size == 0
  # Propagate pushed-parameter requirements backward across call sites to verify ONLY empty `[]` locals reach `.push`!
  if allow_arr[0] && push_params.size > 0
    changed = true
    passes = 0
    while changed && allow_arr[0] && passes < 8
      changed = false
      passes += 1
      ci = 0
      while ci < call_sites.size && allow_arr[0]
        cs = call_sites[ci]
        caller_jf = cs[0]
        callee_jf = cs[1]
        cargs = cs[2]
        pm = push_params[callee_jf]
        if pm != nil
          c_emp = fn_emp_arrs[caller_jf]
          pm.keys.each ->(pi)
            if pi < cargs.size
              ae = cargs[pi]
              if ae.kind == :ident && ae.x != nil && ae.x.binding != nil && !ae.x.binding.global? && ae.x.binding.slot < 0 && ae.x.binding.scope.func == caller_jf
                ab = ae.x.binding
                if c_emp != nil && c_emp[ab.lidx] == true
                  nil
                elsif ab.kind == :param
                  cpi = caller_jf.params.index(ab)
                  if cpi != nil
                    push_params[caller_jf] = {} if push_params[caller_jf] == nil
                    if !push_params[caller_jf][cpi]
                      push_params[caller_jf][cpi] = true
                      changed = true
                  else
                    allow_arr[0] = false
                else
                  allow_arr[0] = false
              else
                allow_arr[0] = false
            else
              allow_arr[0] = false
        ci += 1
    allow_arr[0] = false if changed
  # Require at least one allocating/region-benefiting callee (avoid overhead on trivial pure-math fns!)
  [allow_arr[0], JS_EPOCH[0], guards, nil, nil]

# Closed-world sound OOP Region Arena analyzer (handles OOP benchmarks/workloads with user constructors,
# prototype hierarchies, read-only global config objects, and primitive-field-only global singletons!).
# Guarantees ZERO arena pointers escape: root returns primitive, no global/proto mutation receives arena refs,
# and any primitive-only global singleton (`planner = new Planner()`) is cloned to GC heap on `js_arena_leave`.
-> jit_oop_prim_val_expr?(e)
  return true if e == nil
  k = e.kind
  return true if k == :num || k == :string || k == :true || k == :false || k == :null || k == :unary || k == :update
  if k == :binary
    op = e.str
    return true if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "!==" || op == "==" || op == "!="
  if k == :cond
    return jit_oop_prim_val_expr?(e.b) && jit_oop_prim_val_expr?(e.c)
  false

-> jit_oop_add_proto_chain(proto, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map)
  p = proto
  hops = 0
  while p.is_a?(JS:Object) && p != js_realm().object_proto && hops < 12
    return false if p.shape.dict
    if region_protos[p] == nil
      region_protos[p] = true
      is_prim_owner = prim_proto_map[p] == true
      cmks = called_methods.keys
      ci = 0
      while ci < cmks.size
        mn = cmks[ci]
        sl = p.shape.slot_of(mn)
        if sl >= 0
          return false if (p.shape.attrs_of(mn) & ATTR_ACCESSOR) != 0
          fv = p.slot_get(sl)
          return false if !fv.is_a?(JS:Function) || fv.code == nil || !fv.code.node.is_a?(JaFunc)
          if checked_fns[fv.code.node] == nil
            fn_queue.push([fv.code.node, true, is_prim_owner])
        ci += 1
    p = p.shape.proto
    hops += 1
  true

-> jit_oop_register_method(mn, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map)
  return true if called_methods[mn] == true
  called_methods[mn] = true
  rps = region_protos.keys
  ri = 0
  while ri < rps.size
    p = rps[ri]
    sl = p.shape.slot_of(mn)
    if sl >= 0
      return false if (p.shape.attrs_of(mn) & ATTR_ACCESSOR) != 0
      fv = p.slot_get(sl)
      return false if !fv.is_a?(JS:Function) || fv.code == nil || !fv.code.node.is_a?(JaFunc)
      if checked_fns[fv.code.node] == nil
        fn_queue.push([fv.code.node, true, prim_proto_map[p] == true])
    ri += 1
  true

-> jit_oop_check_node?(n, jf, root_info, allow_this, is_prim_owner, st)
  return true if n == nil
  if n.is_a?(Array)
    i = 0
    while i < n.size
      return false if !jit_oop_check_node?(n[i], jf, root_info, allow_this, is_prim_owner, st)
      i += 1
    return true
  return true if !n.is_a?(JsNode)
  k = n.kind
  return false if k == :function || k == :arrow || k == :class || k == :with || k == :try || k == :debugger || k == :yield || k == :await || k == :spread || k == :tagged_template || k == :import || k == :export || k == :super || k == :delete || k == :for_in || k == :for_of || k == :switch
  return false if k == :this && !allow_this
  if k == :return && root_info != nil
    return false if !jit_region_expr_prim?(n.a, root_info)
  if k == :throw
    return false unless n.a != nil && n.a.kind == :new && n.a.a != nil && n.a.a.kind == :ident && n.a.a.str == "Error"
  guards = st[0]; guard_seen = st[1]; gshape_guards = st[2]; gshape_seen = st[3]
  allow_arr = st[4]; prim_globals = st[5]; ro_globals = st[6]
  region_ctors = st[7]; region_protos = st[8]; called_methods = st[9]
  fn_queue = st[10]; checked_fns = st[11]; prim_proto_map = st[12]; promote_cells = st[13]
  if k == :ident && n.x != nil && n.x.binding != nil && n.x.binding.global?
    gb = n.x.binding
    return true if prim_globals[gb] != nil
    gcell = wk_cell(gb)
    gv = gcell.value
    if js_string?(gv) || js_number?(gv) || gv == true || gv == false || gv == nil || gv == JS_NULL
      jit_region_guard_cell(gcell, gv, guards, guard_seen)
      ro_globals[gb] = true
      return true
    if gv.is_a?(JS:Base) && !gv.shape.dict && !gv.exotic? && !gv.is_a?(JS:TypedArray)
      jit_region_guard_cell(gcell, gv, guards, guard_seen)
      if gshape_seen[gv] == nil
        gshape_seen[gv] = true
        gshape_guards.push([gv, gv.shape])
      ro_globals[gb] = true
      return true
    return false
  if k == :assign || k == :update
    lhs = n.a
    if lhs.kind == :ident && lhs.x != nil && lhs.x.binding != nil
      gb = lhs.x.binding
      return false if gb.slot >= 0
      if gb.global?
        # Allow assigning a primitive-field-only singleton global (`planner = new Planner()`)!
        return false if k != :assign || n.str != "=" || ro_globals[gb] == true
        rhs = n.b
        return false if rhs == nil || rhs.kind != :new || rhs.a == nil || rhs.a.kind != :ident || rhs.a.x == nil || rhs.a.x.binding == nil || !rhs.a.x.binding.global?
        ccell = wk_cell(rhs.a.x.binding)
        cfv = ccell.value
        return false if !cfv.is_a?(JS:Function) || cfv.is_a?(JS:Method) || cfv.code == nil || !cfv.code.node.is_a?(JaFunc) || cfv.shape.dict
        cproto = cfv.get("prototype", cfv)
        return false if !cproto.is_a?(JS:Object) || cproto.shape.dict
        if prim_globals[gb] != nil && prim_globals[gb] != cfv
          return false
        if prim_globals[gb] == nil
          prim_globals[gb] = cfv
          promote_cells.push(wk_cell(gb))
          prim_proto_map[cproto] = true
        jit_region_guard_cell(ccell, cfv, guards, guard_seen)
        if gshape_seen[cfv] == nil
          gshape_seen[cfv] = true
          gshape_guards.push([cfv, cfv.shape])
        if region_ctors[cfv] == nil
          region_ctors[cfv] = true
          fn_queue.push([cfv.code.node, true, true]) if checked_fns[cfv.code.node] == nil
          return false if !jit_oop_add_proto_chain(cproto, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map)
        return jit_oop_check_node?(rhs.list, jf, root_info, allow_this, is_prim_owner, st)
    elsif lhs.kind == :member
      return false if !lhs.has?(F_COMPUTED) && (lhs.b.str == "__proto__" || lhs.b.str == "prototype" || lhs.b.str == "constructor")
      return false if !lhs.has?(F_COMPUTED) && lhs.b.str == "length"
      if lhs.a.kind == :ident && lhs.a.x != nil && lhs.a.x.binding != nil && lhs.a.x.binding.global?
        gb = lhs.a.x.binding
        return false if prim_globals[gb] == nil
        return false if k == :assign && !jit_oop_prim_val_expr?(n.b)
      if is_prim_owner && lhs.a.kind == :this
        return false if k == :assign && !jit_oop_prim_val_expr?(n.b)
      if lhs.has?(F_COMPUTED)
        allow_arr[0] = false
  if k == :member && !n.has?(F_COMPUTED)
    return false if n.b.str == "__proto__" || n.b.str == "constructor"
    return false if n.b.str == "prototype"
  if k == :new
    return false if n.a == nil || n.a.kind != :ident || n.a.x == nil || n.a.x.binding == nil || !n.a.x.binding.global?
    cn = n.a.str
    ccell = wk_cell(n.a.x.binding)
    cfv = ccell.value
    r = js_realm()
    if cn == "Array" || cn == "Error"
      return false if cfv == nil || cfv != r.intrinsics[cn]
      jit_region_guard_cell(ccell, cfv, guards, guard_seen)
      return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
    return false if !cfv.is_a?(JS:Function) || cfv.is_a?(JS:Method) || cfv.code == nil || !cfv.code.node.is_a?(JaFunc) || cfv.shape.dict
    cproto = cfv.get("prototype", cfv)
    return false if !cproto.is_a?(JS:Object) || cproto.shape.dict
    jit_region_guard_cell(ccell, cfv, guards, guard_seen)
    if gshape_seen[cfv] == nil
      gshape_seen[cfv] = true
      gshape_guards.push([cfv, cfv.shape])
    if region_ctors[cfv] == nil
      region_ctors[cfv] = true
      fn_queue.push([cfv.code.node, true, prim_proto_map[cproto] == true]) if checked_fns[cfv.code.node] == nil
      return false if !jit_oop_add_proto_chain(cproto, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map)
    return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
  if k == :call
    c = n.a
    if c.kind == :ident && c.x != nil && c.x.binding != nil && c.x.binding.global?
      fn_nm = c.str
      gcell = wk_cell(c.x.binding)
      gv = gcell.value
      if fn_nm == "String" || fn_nm == "Number" || fn_nm == "Boolean" || fn_nm == "parseInt" || fn_nm == "parseFloat" || fn_nm == "isNaN" || fn_nm == "isFinite"
        return false if gv == nil || gv != js_realm().global.get_own(fn_nm)
        jit_region_guard_cell(gcell, gv, guards, guard_seen)
        return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
      return false if !gv.is_a?(JS:Function) || gv.code == nil || !gv.code.node.is_a?(JaFunc)
      jit_region_guard_cell(gcell, gv, guards, guard_seen)
      fn_queue.push([gv.code.node, false, false]) if checked_fns[gv.code.node] == nil
      return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
    if c.kind == :member && !c.has?(F_COMPUTED)
      mn = c.b.str
      # Super-call `BaseCtor.call(this, ...)` or `BaseCtor.prototype.m.call(this, ...)`!
      if mn == "call" && n.list.size >= 1 && n.list[0].kind == :this
        if c.a.kind == :ident && c.a.x != nil && c.a.x.binding != nil && c.a.x.binding.global?
          scell = wk_cell(c.a.x.binding)
          sfv = scell.value
          return false if !sfv.is_a?(JS:Function) || sfv.code == nil || !sfv.code.node.is_a?(JaFunc)
          jit_region_guard_cell(scell, sfv, guards, guard_seen)
          fn_queue.push([sfv.code.node, true, is_prim_owner]) if checked_fns[sfv.code.node] == nil
          return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
        if c.a.kind == :member && !c.a.has?(F_COMPUTED) && c.a.a.kind == :member && !c.a.a.has?(F_COMPUTED) && c.a.a.b.str == "prototype" && c.a.a.a.kind == :ident && c.a.a.a.x != nil && c.a.a.a.x.binding != nil && c.a.a.a.x.binding.global?
          scell = wk_cell(c.a.a.a.x.binding)
          sfv = scell.value
          return false if !sfv.is_a?(JS:Function) || sfv.shape.dict
          sproto = sfv.get("prototype", sfv)
          return false if !sproto.is_a?(JS:Object) || sproto.shape.dict
          sm_fn = sproto.get_own(c.a.b.str)
          return false if !sm_fn.is_a?(JS:Function) || sm_fn.code == nil || !sm_fn.code.node.is_a?(JaFunc)
          jit_region_guard_cell(scell, sfv, guards, guard_seen)
          if gshape_seen[sfv] == nil
            gshape_seen[sfv] = true
            gshape_guards.push([sfv, sfv.shape])
          fn_queue.push([sm_fn.code.node, true, is_prim_owner]) if checked_fns[sm_fn.code.node] == nil
          return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
        return false
      # Static call on read-only global object (`Math.sqrt`, `Strength.stronger`, `Strength.weaker`, `Strength.weakestOf`)!
      if c.a.kind == :ident && c.a.x != nil && c.a.x.binding != nil && c.a.x.binding.global? && prim_globals[c.a.x.binding] == nil
        gn = c.a.str
        gcell = wk_cell(c.a.x.binding)
        gv = gcell.value
        if gn == "Math"
          return false if gv == nil || gv != js_realm().global.get_own("Math")
          jit_region_guard_cell(gcell, gv, guards, guard_seen)
          return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
        if gv.is_a?(JS:Base) && !gv.shape.dict && !gv.exotic?
          sl = gv.shape.slot_of(mn)
          if sl >= 0 && (gv.shape.attrs_of(mn) & ATTR_ACCESSOR) == 0
            mfv = gv.slot_get(sl)
            if mfv.is_a?(JS:Function) && mfv.code != nil && mfv.code.node.is_a?(JaFunc)
              jit_region_guard_cell(gcell, gv, guards, guard_seen)
              if gshape_seen[gv] == nil
                gshape_seen[gv] = true
                gshape_guards.push([gv, gv.shape])
              ro_globals[c.a.x.binding] = true
              fn_queue.push([mfv.code.node, false, false]) if checked_fns[mfv.code.node] == nil
              return jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
        return false
      # Safe built-in array/string methods OR closed-world prototype methods!
      if mn != "push" && mn != "pop" && mn != "slice" && mn != "splice" && mn != "indexOf" && mn != "charCodeAt" && mn != "join"
        return false if !jit_oop_register_method(mn, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map)
      return jit_oop_check_node?(c.a, jf, root_info, allow_this, is_prim_owner, st) && jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)
    return false
  return false if !jit_oop_check_node?(n.a, jf, root_info, allow_this, is_prim_owner, st)
  return false if !jit_oop_check_node?(n.b, jf, root_info, allow_this, is_prim_owner, st)
  return false if !jit_oop_check_node?(n.c, jf, root_info, allow_this, is_prim_owner, st)
  return false if !jit_oop_check_node?(n.d, jf, root_info, allow_this, is_prim_owner, st)
  jit_oop_check_node?(n.list, jf, root_info, allow_this, is_prim_owner, st)

-> jit_region_analyze_oop(jf, info)
  return nil if jf.params.size != 0 || jf.script || info.is_osr || !jf.node.b.is_a?(Array)
  guards = []
  guard_seen = {}
  gshape_guards = []
  gshape_seen = {}
  allow_arr = [true]
  prim_globals = {}
  ro_globals = {}
  region_ctors = {}
  region_protos = {}
  called_methods = {}
  fn_queue = [[jf, false, false]]
  checked_fns = {}
  prim_proto_map = {}
  promote_cells = []
  st = [guards, guard_seen, gshape_guards, gshape_seen, allow_arr, prim_globals, ro_globals, region_ctors, region_protos, called_methods, fn_queue, checked_fns, prim_proto_map, promote_cells]
  qi = 0
  while qi < fn_queue.size
    item = fn_queue[qi]
    qi += 1
    cjf = item[0]
    allow_this = item[1]
    is_prim_owner = item[2]
    next if checked_fns[cjf] == true
    return nil if checked_fns.size >= 64
    return nil if cjf.dynamic || cjf.mapped_args || cjf.args_binding != nil || !cjf.simple || cjf.arrow
    return nil if cjf.free.size > 0 || cjf.scope.has_env? || (cjf.body_scope != nil && cjf.body_scope.has_env?)
    return nil if cjf.node.has?(F_ASYNC) || cjf.node.has?(F_GENERATOR) || !cjf.node.b.is_a?(Array)
    return nil if !allow_this && cjf.uses_this
    checked_fns[cjf] = true
    r_info = cjf == jf ? info : nil
    return nil if !jit_oop_check_node?(cjf.node.b, cjf, r_info, allow_this, is_prim_owner, st)
  return nil if region_ctors.size == 0 || guards.size == 0
  # Final check: no prim_global was also read as a ro_global before assignment? (Allowed since prim_globals only hold prim-only instances!)
  [allow_arr[0], JS_EPOCH[0], guards, promote_cells.size > 0 ? promote_cells : nil, gshape_guards.size > 0 ? gshape_guards : nil]

# ---- AST helpers ----

-> jit_int32_lit?(e)
  return false if e == nil || e.kind != :num
  v = e.a
  return false if v != v || v < ~-2147483648.0 || v > ~2147483647.0
  # Reject -0.0
  return false if v == ~0.0 && (~1.0 / v) < ~0.0
  iv = v.to_i
  iv.to_f == v

-> jit_u32_lit?(e)
  return false if e == nil || e.kind != :num
  v = e.a
  return false if v != v || v < ~0.0 || v > ~4294967295.0
  return false if v == ~0.0 && (~1.0 / v) < ~0.0
  iv = v.to_i
  iv.to_f == v

-> jit_small_int_lit?(e, max_abs)
  return false if !jit_int32_lit?(e)
  iv = e.a.to_i
  iv >= (0 - max_abs) && iv <= max_abs

# Signed int32 constant value for BOTH `:num` literals AND negative `:unary "-"` literals (`-1`, `-128`!).
# Returns Int or nil (NEVER crashes callers expecting `e.a.to_i` on `jit_int32_lit?`!).
-> jit_signed_i32_val(e)
  return nil if e == nil
  if e.kind == :num
    return jit_int32_lit?(e) ? e.a.to_i : nil
  if e.kind == :unary && e.str == "-" && e.a != nil && e.a.kind == :num
    v = e.a.a
    return nil if v != v || v < ~1.0 || v > ~2147483648.0
    iv = v.to_i
    return iv.to_f == v ? (0 - iv) : nil
  nil

# Can a plain object literal be compiled directly (0..8 simple init properties)? Returns key list or nil.
-> jit_plain_obj_keys(e)
  return nil if e == nil || e.kind != :object || e.list.size > 8
  return [] if e.list.size == 0
  ks = []
  i = 0
  while i < e.list.size
    p = e.list[i]
    return nil if p.kind != :prop || p.str != "init" || p.has?(F_COMPUTED)
    k = p.a.kind == :ident || p.a.kind == :string ? p.a.str : nil
    return nil if k == nil || k == "__proto__" || ks.include?(k)
    ks.push(k)
    i += 1
  ks

# Inspect a JS:Function constructor `function C(p0..pk) { this.f0 = e0; ... }` for pure field-init shape!
# Returns [fv, jf, keys, exprs, final_sh, proto, all_params_direct] or nil.
-> jit_pure_ctor_info(fv)
  return nil if !fv.is_a?(JS:Function) || fv.code == nil || !fv.code.node.is_a?(JaFunc)
  return nil if (fv.code.flags & CODE_CTOR) == 0 || (fv.code.flags & CODE_DERIVED) != 0
  jf = fv.code.node
  return nil if jf.dynamic || jf.mapped_args || jf.args_binding != nil || !jf.simple || jf.arrow
  return nil if jf.node.has?(F_GENERATOR) || jf.node.has?(F_ASYNC) || jf.free.size > 0 || jf.params.size > 6
  return nil if jf.scope.has_env? || (jf.body_scope != nil && jf.body_scope != jf.scope)
  stmts = jf.node.b
  return nil if !stmts.is_a?(Array) || stmts.size == 0 || stmts.size > 8
  keys = []
  exprs = []
  all_direct = true
  i = 0
  while i < stmts.size
    st = stmts[i]
    return nil if st == nil || st.kind != :expr_stmt || st.a == nil || st.a.kind != :assign || st.a.str != "="
    lhs = st.a.a
    rhs = st.a.b
    return nil if lhs == nil || lhs.kind != :member || lhs.has?(F_COMPUTED) || lhs.a == nil || lhs.a.kind != :this
    kn = lhs.b.str
    return nil if kn == "__proto__" || keys.include?(kn)
    return nil if !jit_pure_ctor_rhs_ok?(rhs, jf)
    if !(rhs.kind == :ident && rhs.x != nil && rhs.x.binding != nil && rhs.x.binding.kind == :param && rhs.x.binding.scope.func == jf)
      all_direct = false
    keys.push(kn)
    exprs.push(rhs)
    i += 1
  proto = fv.get("prototype", fv)
  return nil if !proto.is_a?(JS:Object) || proto.shape.dict
  sh = js_root_shape(proto, OBJ_INLINE, OBJ_IBASE)
  i = 0
  while i < keys.size
    sh = sh.add(keys[i], ATTR_DEFAULT)
    i += 1
  [fv, jf, keys, exprs, sh, proto, all_direct]

-> jit_pure_ctor_rhs_ok?(e, jf)
  return false if e == nil
  k = e.kind
  return true if k == :num || k == :string || k == :true || k == :false || k == :null
  if k == :ident && e.x != nil && e.x.binding != nil
    b = e.x.binding
    return b.kind == :param && b.scope.func == jf && b.writes == 0
  if k == :logical && e.str == "||"
    if e.a != nil && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.kind == :param && e.a.x.binding.scope.func == jf && e.a.x.binding.writes == 0 && e.b != nil && (e.b.kind == :num || e.b.kind == :true || e.b.kind == :false || e.b.kind == :null || e.b.kind == :string)
      return true
    return false
  if k == :binary
    op = e.str
    return (op == "+" || op == "-" || op == "*" || op == "/") && jit_pure_ctor_rhs_ok?(e.a, jf) && jit_pure_ctor_rhs_ok?(e.b, jf)
  if k == :unary
    return e.str == "-" && jit_pure_ctor_rhs_ok?(e.a, jf)
  if k == :array && e.list != nil && e.list.size == 0
    return true
  if k == :member && !e.has?(F_COMPUTED) && e.a != nil && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.global?
    return true
  false

# Check if `fv` is a pure numeric value-struct constructor (2..4 direct param fields: `this.x = x; this.y = y; this.z = z;`).
# Returns ctor_info or nil.
-> jit_vstruct_ctor_info(fv)
  ci = jit_pure_ctor_info(fv)
  return nil if ci == nil
  keys = ci[2]
  return nil if !ci[6] || keys.size < 2 || keys.size > 4 || ci[1].params.size != keys.size
  # Verify 1-to-1 param order: field[k] == param[k]
  exprs = ci[3]
  jf = ci[1]
  i = 0
  while i < keys.size
    return nil if exprs[i].x.binding != jf.params[i]
    i += 1
  ci

-> jit_vs_always_num_expr?(e)
  return false if e == nil
  k = e.kind
  return true if k == :num
  return true if k == :unary && (e.str == "-" || e.str == "+")
  if k == :binary
    op = e.str
    return true if op == "-" || op == "*" || op == "/"
    return jit_vs_always_num_expr?(e.a) && jit_vs_always_num_expr?(e.b) if op == "+"
  if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
    return e.a.b.str == "sqrt" || e.a.b.str == "abs"
  false

# Classify a method `fn` on a pure value-struct shape `sh` (2..4 fields `keys`):
#   - `[:scalar, tjf, re]`          (e.g. `dot(v)` returning f64 expression!)
#   - `[:vstruct, tjf, ctor_info, local_decl_or_nil, ret_expr]` (e.g. `add(v)`, `sub(v)`, `mul(s)`, `norm()`!)
# Returns descriptor array or nil.
-> jit_vstruct_method_info(fn, sh, depth = 0)
  return nil if depth > 3 || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
  return nil if !sh.is_a?(JS:Shape) || sh.dict || sh.count < 2 || sh.count > 4 || !sh.proto.is_a?(JS:Object)
  tjf = fn.code.node
  return nil if tjf.dynamic || tjf.mapped_args || tjf.args_binding != nil || !tjf.simple || tjf.arrow
  return nil if tjf.node.has?(F_GENERATOR) || tjf.node.has?(F_ASYNC) || tjf.free.size > 0 || tjf.params.size > 2
  return nil if tjf.scope.has_env? || (tjf.body_scope != nil && tjf.body_scope.has_env?)
  pi = 0
  while pi < tjf.params.size
    return nil if tjf.params[pi].writes > 0
    pi += 1
  stmts = tjf.node.b
  return nil if !stmts.is_a?(Array) || stmts.size == 0 || stmts.size > 2
  loc_decl = nil
  ret_st = nil
  if stmts.size == 1
    ret_st = stmts[0]
  else
    # Allow 1 local scalar decl `var d = scalar_expr; return ...;` (like `Vec.prototype.norm`!)
    st0 = stmts[0]
    return nil if st0.kind != :var_decl || st0.list.size != 1 || st0.list[0].a.kind != :ident || st0.list[0].b == nil
    lb = st0.list[0].a.x.binding
    return nil if lb == nil || lb.writes > 1
    return nil if !jit_vs_scalar_expr_ok?(st0.list[0].b, tjf, sh, nil, depth + 1)
    loc_decl = [lb, st0.list[0].b]
    ret_st = stmts[1]
  return nil if ret_st == nil || ret_st.kind != :return || ret_st.a == nil
  re = ret_st.a
  loc_b = loc_decl != nil ? loc_decl[0] : nil
  # Form 1: Guaranteed-numeric scalar return expression (e.g. `dot(v)` -> `this.x*v.x + ...`, NEVER bare `return this.obj`!)
  if loc_decl == nil && jit_vs_always_num_expr?(re) && jit_vs_scalar_expr_ok?(re, tjf, sh, nil, depth + 1)
    return [:scalar, tjf, re]
  # Form 2: `return new Ctor(e0, ..., em)` (e.g. `add(v)`, `sub(v)`, `mul(s)`)
  if re.kind == :new && re.a.kind == :ident && re.a.x != nil && re.a.x.binding != nil && re.a.x.binding.global?
    cell = wk_cell(re.a.x.binding)
    ci = jit_vstruct_ctor_info(cell.value)
    if ci != nil && ci[4] == sh && re.list.size == ci[2].size
      ok = true
      i = 0
      while i < re.list.size && ok
        ok = false if !jit_vs_scalar_expr_ok?(re.list[i], tjf, sh, loc_b, depth + 1)
        i += 1
      return [:vstruct_new, tjf, ci, loc_decl, re, cell] if ok
  # Form 3: `return this.otherMethod(arg)` (e.g. `norm()` calling `this.mul(d)`)
  if re.kind == :call && re.a.kind == :member && !re.a.has?(F_COMPUTED) && re.a.a.kind == :this && re.list.size <= 1
    sub_fn = sh.proto.get_own(re.a.b.str)
    if sub_fn.is_a?(JS:Function) && sub_fn != fn
      sub_info = jit_vstruct_method_info(sub_fn, sh, depth + 1)
      if sub_info != nil && sub_info[0] == :vstruct_new
        ok = true
        i = 0
        while i < re.list.size && ok
          ok = false if !jit_vs_scalar_expr_ok?(re.list[i], tjf, sh, loc_b, depth + 1)
          i += 1
        return [:vstruct_call, tjf, sub_info[2], loc_decl, re, sub_info] if ok
  nil

-> jit_vs_scalar_expr_ok?(e, tjf, sh, loc_b, depth)
  return false if e == nil || depth > 5
  k = e.kind
  return true if k == :num || k == :true || k == :false || k == :null
  if k == :ident && e.x != nil && e.x.binding != nil
    b = e.x.binding
    return true if loc_b != nil && b == loc_b
    return b.kind == :param && b.scope.func == tjf
  if k == :member && !e.has?(F_COMPUTED)
    if e.a.kind == :this
      sl = sh.slot_of(e.b.str)
      return sl >= 0 && (sh.attrs_of(e.b.str) & ATTR_ACCESSOR) == 0
    if e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.kind == :param && e.a.x.binding.scope.func == tjf
      sl = sh.slot_of(e.b.str)
      return sl >= 0 && (sh.attrs_of(e.b.str) & ATTR_ACCESSOR) == 0
    return false
  if k == :binary
    op = e.str
    return (op == "+" || op == "-" || op == "*" || op == "/") && jit_vs_scalar_expr_ok?(e.a, tjf, sh, loc_b, depth) && jit_vs_scalar_expr_ok?(e.b, tjf, sh, loc_b, depth)
  if k == :unary
    return e.str == "-" && jit_vs_scalar_expr_ok?(e.a, tjf, sh, loc_b, depth)
  if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED)
    if e.a.a.kind == :ident && e.a.a.str == "Math" && e.list.size == 1 && (e.a.b.str == "sqrt" || e.a.b.str == "abs")
      return jit_vs_scalar_expr_ok?(e.list[0], tjf, sh, loc_b, depth)
    # Allow `this.dot(this)` or `this.dot(v)` inside `norm()`!
    if e.a.a.kind == :this && e.list.size == 1 && (e.list[0].kind == :this || (e.list[0].kind == :ident && e.list[0].x != nil && e.list[0].x.binding != nil && e.list[0].x.binding.kind == :param && e.list[0].x.binding.scope.func == tjf))
      sub_fn = sh.proto.get_own(e.a.b.str)
      if sub_fn.is_a?(JS:Function)
        si = jit_vstruct_method_info(sub_fn, sh, depth + 1)
        return si != nil && si[0] == :scalar
  false

# Resolve pure value-struct ctor_info from an observed JS:Shape (`sh.proto.constructor`)!
# When `sample_obj` is provided, also verify every field holds a JS Number (rejects non-numeric structs like Strength(v, "name")!).
-> jit_vs_ctor_info_for_shape(sh, sample_obj = nil)
  return nil if !sh.is_a?(JS:Shape) || sh.dict || !sh.proto.is_a?(JS:Object)
  ctor = sh.proto.get_own("constructor")
  return nil if !ctor.is_a?(JS:Function)
  ci = jit_vstruct_ctor_info(ctor)
  return nil if ci == nil || ci[4] != sh
  if sample_obj.is_a?(JS:Object)
    keys = ci[2]
    i = 0
    while i < keys.size
      return nil if !js_number?(sample_obj.get_own(keys[i]))
      i += 1
  ci

# Check if `e` is a pure scalar f64 expression inside a multi-stmt vstruct-taking method (e.g. `Sphere.prototype.hit`)!
-> jit_vs_m_f64_expr_ok?(e, sh, vlocs, flocs, this_num)
  return false if e == nil
  k = e.kind
  return true if k == :num
  if k == :ident && e.x != nil && e.x.binding != nil
    return flocs[e.x.binding] == true
  if k == :unary && e.str == "-"
    return jit_vs_m_f64_expr_ok?(e.a, sh, vlocs, flocs, this_num)
  if k == :binary
    op = e.str
    return (op == "+" || op == "-" || op == "*" || op == "/") && jit_vs_m_f64_expr_ok?(e.a, sh, vlocs, flocs, this_num) && jit_vs_m_f64_expr_ok?(e.b, sh, vlocs, flocs, this_num)
  if k == :cond
    c = e.a
    return false if c == nil || c.kind != :binary || (c.str != "<" && c.str != "<=" && c.str != ">" && c.str != ">=")
    return jit_vs_m_f64_expr_ok?(c.a, sh, vlocs, flocs, this_num) && jit_vs_m_f64_expr_ok?(c.b, sh, vlocs, flocs, this_num) && jit_vs_m_f64_expr_ok?(e.b, sh, vlocs, flocs, this_num) && jit_vs_m_f64_expr_ok?(e.c, sh, vlocs, flocs, this_num)
  if k == :member && !e.has?(F_COMPUTED)
    if e.a.kind == :this
      sl = sh.slot_of(e.b.str)
      if sl >= 0 && (sh.attrs_of(e.b.str) & ATTR_ACCESSOR) == 0
        this_num[e.b.str] = true
        return true
      return false
    if e.a.kind == :ident && e.a.x != nil && vlocs[e.a.x.binding] != nil
      vci = vlocs[e.a.x.binding]
      return vci[2].include?(e.b.str)
    return false
  if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED)
    if e.a.a.kind == :ident && e.a.a.str == "Math"
      mn = e.a.b.str
      return e.list.size == 1 && jit_vs_m_f64_expr_ok?(e.list[0], sh, vlocs, flocs, this_num) if mn == "sqrt" || mn == "abs"
      return e.list.size == 2 && jit_vs_m_f64_expr_ok?(e.list[0], sh, vlocs, flocs, this_num) && jit_vs_m_f64_expr_ok?(e.list[1], sh, vlocs, flocs, this_num) if mn == "min" || mn == "max"
      return false
    if e.a.a.kind == :ident && e.a.a.x != nil && vlocs[e.a.a.x.binding] != nil
      vci = vlocs[e.a.a.x.binding]
      vsh = vci[4]
      mfn = vsh.proto.is_a?(JS:Object) ? vsh.proto.get_own(e.a.b.str) : nil
      mi = mfn.is_a?(JS:Function) ? jit_vstruct_method_info(mfn, vsh) : nil
      if mi != nil && mi[0] == :scalar && e.list.size == mi[1].params.size
        ai = 0
        while ai < e.list.size
          ae = e.list[ai]
          if ae.kind == :ident && ae.x != nil && vlocs[ae.x.binding] != nil && vlocs[ae.x.binding][4] == vsh
            nil
          elsif jit_vs_m_f64_expr_ok?(ae, sh, vlocs, flocs, this_num)
            nil
          else
            return false
          ai += 1
        return true
  false

# Classify a multi-statement pure-numeric method taking value-struct / scalar params and returning f64
# (e.g. `Sphere.prototype.hit(ro, rd)` -> inlined directly in unboxed f64 with ZERO allocations!).
# Returns `[tjf, this_vs, this_num, loc_kinds, arg_cis]` or nil.
# Infer `[elem_shape, proto_method_fn]` for a cold-branch call `global_arr[i].m(...)`
# when `global_arr` is a prologue-guarded global dense array of uniform JS:Objects!
# Still 100% runtime-guarded by `recv.@shape == sh` and `JS_EPOCH` at the call site.
-> jit_infer_global_arr_method(mem_e, global_objs)
  return nil if !mem_e.is_a?(JsNode) || mem_e.kind != :member || mem_e.has?(F_COMPUTED)
  rec = mem_e.a
  return nil if !rec.is_a?(JsNode) || rec.kind != :member || !rec.has?(F_COMPUTED)
  arr_e = rec.a
  return nil if !arr_e.is_a?(JsNode) || arr_e.kind != :ident || arr_e.x == nil || arr_e.x.binding == nil
  go = global_objs[arr_e.x.binding]
  return nil if go == nil
  gv = go[1]
  return nil if !js_array?(gv) || gv.size == 0
  el0 = gv[0]
  return nil if !el0.is_a?(JS:Object) || el0.shape.dict || !el0.shape.proto.is_a?(JS:Object)
  mname = mem_e.b.str
  return nil if el0.shape.slot_of(mname) >= 0
  fn = el0.shape.proto.get_own(mname)
  return nil if !fn.is_a?(JS:Function)
  [el0.shape, fn]

-> jit_vs_method_f64_info(fn, sh, arg_cis)
  return nil if !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
  return nil if !sh.is_a?(JS:Shape) || sh.dict || !sh.proto.is_a?(JS:Object)
  # Require at least 1 value-struct argument (never mis-match 0-arg object getters like `output()`/`isSatisfied()`!)
  has_vs_arg = false
  ai0 = 0
  while ai0 < arg_cis.size
    has_vs_arg = true if arg_cis[ai0] != nil
    ai0 += 1
  return nil if !has_vs_arg
  tjf = fn.code.node
  return nil if tjf.dynamic || tjf.mapped_args || tjf.args_binding != nil || !tjf.simple || tjf.arrow
  return nil if tjf.node.has?(F_GENERATOR) || tjf.node.has?(F_ASYNC) || tjf.free.size > 0 || tjf.params.size != arg_cis.size
  return nil if tjf.scope.has_env? || (tjf.body_scope != nil && tjf.body_scope.has_env?)
  stmts = tjf.node.b
  return nil if !stmts.is_a?(Array) || stmts.size == 0 || stmts.size > 12 || stmts[stmts.size - 1].kind != :return
  vlocs = {}
  flocs = {}
  this_vs = {}
  this_num = {}
  loc_kinds = {}
  pi = 0
  while pi < tjf.params.size
    pb = tjf.params[pi]
    return nil if pb.writes > 0
    if arg_cis[pi] != nil
      vlocs[pb] = arg_cis[pi]
    else
      flocs[pb] = true
    pi += 1
  si = 0
  while si < stmts.size
    st = stmts[si]
    if st.kind == :var_decl && st.list.size == 1 && st.list[0].a.kind == :ident && st.list[0].b != nil
      lb = st.list[0].a.x.binding
      return nil if lb == nil || lb.writes > 1
      rhs = st.list[0].b
      matched_vs = false
      if rhs.kind == :call && rhs.a.kind == :member && !rhs.a.has?(F_COMPUTED) && rhs.a.a.kind == :ident && rhs.a.a.x != nil && vlocs[rhs.a.a.x.binding] != nil
        vci = vlocs[rhs.a.a.x.binding]
        vsh = vci[4]
        mfn = vsh.proto.is_a?(JS:Object) ? vsh.proto.get_own(rhs.a.b.str) : nil
        mi = mfn.is_a?(JS:Function) ? jit_vstruct_method_info(mfn, vsh) : nil
        if mi != nil && (mi[0] == :vstruct_new || mi[0] == :vstruct_call) && rhs.list.size == mi[1].params.size
          args_ok = true
          ai = 0
          while ai < rhs.list.size && args_ok
            ae = rhs.list[ai]
            if ae.kind == :member && !ae.has?(F_COMPUTED) && ae.a.kind == :this
              sl = sh.slot_of(ae.b.str)
              if sl >= 0 && (sh.attrs_of(ae.b.str) & ATTR_ACCESSOR) == 0
                this_vs[ae.b.str] = vci
              else
                args_ok = false
            elsif ae.kind == :ident && ae.x != nil && vlocs[ae.x.binding] != nil && vlocs[ae.x.binding][4] == vsh
              nil
            elsif jit_vs_m_f64_expr_ok?(ae, sh, vlocs, flocs, this_num)
              nil
            else
              args_ok = false
            ai += 1
          if args_ok
            vlocs[lb] = mi[2]
            loc_kinds[lb] = [:vs, mi[2], mi]
            matched_vs = true
      if !matched_vs
        return nil if !jit_vs_m_f64_expr_ok?(rhs, sh, vlocs, flocs, this_num)
        flocs[lb] = true
        loc_kinds[lb] = [:f64]
    elsif st.kind == :if && st.c == nil && st.b != nil && st.b.kind == :return && st.b.a != nil
      c = st.a
      return nil if c == nil || c.kind != :binary || (c.str != "<" && c.str != "<=" && c.str != ">" && c.str != ">=")
      return nil if !jit_vs_m_f64_expr_ok?(c.a, sh, vlocs, flocs, this_num) || !jit_vs_m_f64_expr_ok?(c.b, sh, vlocs, flocs, this_num)
      return nil if !jit_vs_m_f64_expr_ok?(st.b.a, sh, vlocs, flocs, this_num)
    elsif st.kind == :return && st.a != nil
      return nil if !jit_vs_m_f64_expr_ok?(st.a, sh, vlocs, flocs, this_num)
    else
      return nil
    si += 1
  [tjf, this_vs, this_num, loc_kinds, arg_cis]

# Is a JaFunc a simple single-return expression (suitable for inlining)?
# Returns the return expression JsNode, or nil.
-> jit_inline_return_expr(jf)
  return nil if jf == nil || jf.dynamic || jf.mapped_args || jf.args_binding != nil || !jf.simple
  return nil if jf.node.has?(F_GENERATOR) || jf.node.has?(F_ASYNC)
  return nil if jf.self_binding != nil
  return nil if jf.scope.has_env? || (jf.body_scope != nil && jf.body_scope.has_env?)
  pi = 0
  while pi < jf.params.size
    return nil if jf.params[pi].writes > 0
    pi += 1
  n = jf.node
  re = nil
  if jf.arrow && n.has?(F_EXPR_BODY)
    re = n.b
  else
    stmts = n.b
    return nil if stmts == nil || stmts.size != 1
    s = stmts[0]
    re = s.a if s.kind == :return && s.a != nil
  return nil if re == nil || !jit_node_supported?(re)
  re

# Is a JaFunc a closure factory `function f(p0...) { return function(x...) { return expr; }; }`?
# Returns the inner JaFunc if so, else nil.
-> jit_closure_factory_inner(jf)
  return nil if jf == nil || jf.dynamic || jf.mapped_args || jf.args_binding != nil || !jf.simple
  return nil if jf.node.has?(F_GENERATOR) || jf.node.has?(F_ASYNC)
  return nil if jf.params.size > 4
  n = jf.node
  ret_e = nil
  if jf.arrow && n.has?(F_EXPR_BODY)
    ret_e = n.b
  elsif n.b != nil && n.b.size == 1 && n.b[0].kind == :return
    ret_e = n.b[0].a
  return nil if ret_e == nil || (ret_e.kind != :function && ret_e.kind != :arrow)
  inner = ret_e.x
  return nil if !inner.is_a?(JaFunc) || inner.uses_this
  return nil if jit_inline_return_expr(inner) == nil
  # Verify every free variable of inner is a never-reassigned parameter of jf
  fvals = inner.free.values
  i = 0
  while i < fvals.size
    fb = fvals[i]
    return nil if fb.scope.func != jf || fb.kind != :param || fb.writes > 0
    i += 1
  inner

# ---- Eligibility check ----

-> jit_node_supported?(n)
  return true if n == nil
  k = n.kind
  if k == :ident
    return false if n.x != nil && n.x.binding != nil && n.x.binding.kind == :import
    return true
  if k == :num || k == :string || k == :bigint || k == :true || k == :false || k == :null || k == :this || k == :empty || k == :debugger || k == :regex
    return true
  if k == :break || k == :continue
    return n.str == nil
  if k == :expr_stmt || k == :return || k == :throw
    return jit_node_supported?(n.a)
  if k == :unary || k == :update
    return false if k == :unary && n.str == "delete" && (n.a.kind != :member || n.a.a.kind == :super || n.a.b.kind == :private_name)
    return false if k == :update && n.a.kind == :member && (n.a.a.kind == :super || n.a.b.kind == :private_name)
    return false if k == :update && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && n.a.x.binding.decl_const
    return jit_node_supported?(n.a)
  if k == :binary || k == :logical || k == :assign
    return false if k == :assign && (n.a.kind == :object_pattern || n.a.kind == :array_pattern)
    return false if k == :assign && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && n.a.x.binding.decl_const
    return false if k == :binary && n.a.kind == :private_name
    return jit_node_supported?(n.a) && jit_node_supported?(n.b)
  if k == :cond || k == :if
    return jit_node_supported?(n.a) && jit_node_supported?(n.b) && jit_node_supported?(n.c)
  if k == :block
    sc = n.x
    return false if sc.is_a?(JaScope) && sc.has_env?
    return jit_list_supported?(n.list)
  if k == :var_decl
    i = 0
    while i < n.list.size
      d = n.list[i]
      return false if d.a.kind != :ident
      return false if d.b != nil && !jit_node_supported?(d.b)
      i += 1
    return true
  if k == :while
    return jit_node_supported?(n.a) && jit_node_supported?(n.b)
  if k == :do_while
    return jit_node_supported?(n.a) && jit_node_supported?(n.b)
  if k == :for
    sc = n.x
    return false if sc.is_a?(JaScope) && sc.has_env?
    return jit_node_supported?(n.a) && jit_node_supported?(n.b) && jit_node_supported?(n.c) && jit_node_supported?(n.d)
  if k == :for_in
    sc = n.x
    return false if sc.is_a?(JaScope) && sc.has_env?
    if n.a.kind == :var_decl
      return false if n.a.list.size != 1 || n.a.list[0].a.kind != :ident || n.a.list[0].b != nil
    elsif n.a.kind == :ident
      return false if n.a.x != nil && n.a.x.binding != nil && n.a.x.binding.decl_const
    else
      return false
    return jit_node_supported?(n.b) && jit_node_supported?(n.d)
  if k == :member
    return false if n.a.kind == :super || n.b.kind == :private_name || n.has?(F_OPTIONAL)
    return jit_node_supported?(n.a) && (!n.has?(F_COMPUTED) || jit_node_supported?(n.b))
  if k == :call || k == :new
    return false if n.a.kind == :super || n.has?(F_OPTIONAL)
    return false if n.kind == :call && n.d.is_a?(JaScope)   # direct eval
    return false if !jit_node_supported?(n.a)
    i = 0
    while i < n.list.size
      return false if n.list[i].kind == :spread || !jit_node_supported?(n.list[i])
      i += 1
    return true
  if k == :array
    i = 0
    while i < n.list.size
      e = n.list[i]
      return false if e == nil || e.kind == :spread || !jit_node_supported?(e)
      i += 1
    return true
  if k == :object
    return false if jit_plain_obj_keys(n) == nil
    i = 0
    while i < n.list.size
      return false if !jit_node_supported?(n.list[i].b)
      i += 1
    return true
  if k == :seq
    return jit_list_supported?(n.list)
  if k == :function || k == :arrow
    jf = n.x
    return jf.is_a?(JaFunc)
  if k == :template
    return jit_list_supported?(n.a)
  if k == :function_decl
    return true
  false

-> jit_list_supported?(list)
  return true if list == nil
  i = 0
  while i < list.size
    return false if !jit_node_supported?(list[i])
    i += 1
  true

-> jit_has_loop_stmt?(n)
  return false if n == nil
  k = n.kind
  return true if k == :for || k == :while || k == :do_while
  return jit_has_loop_list?(n.list) if k == :block
  return jit_has_loop_stmt?(n.b) || jit_has_loop_stmt?(n.c) if k == :if
  false

-> jit_has_loop_list?(list)
  return false if list == nil
  i = 0
  while i < list.size
    return true if jit_has_loop_stmt?(list[i])
    i += 1
  false

-> jit_has_tdz_hazard?(jf)
  i = 0
  while i < jf.scopes.size
    ord = jf.scopes[i].order
    j = 0
    while j < ord.size
      return true if ord[j].early_read
      j += 1
    i += 1
  false

-> jit_class_needs_init?(n)
  return false if n == nil
  return true if n.b != nil
  return false if !n.list.is_a?(Array)
  i = 0
  while i < n.list.size
    m = n.list[i]
    if m != nil
      return true if m.c != nil
      if !m.has?(F_STATIC)
        return true if m.kind == :field_def
        return true if m.kind == :method_def && m.a != nil && m.a.kind == :private_name
    i += 1
  false

-> jit_eligible_fn?(jf)
  return false if jf == nil || jf.script || jf.dynamic || jf.mapped_args || jf.args_binding != nil || !jf.simple
  return false if jf.unsupported0 != nil || jf.has_tail || jf.has_dispose || jit_has_tdz_hazard?(jf)
  return false if jf.node.has?(F_GENERATOR) || jf.node.has?(F_ASYNC)
  return false if jf.class_ctor && (jf.derived || jit_class_needs_init?(jf.class_node))
  return false if jf.scope.has_dyn || (jf.body_scope != nil && jf.body_scope != jf.scope)
  return false if jf.nt_binding != nil || jf.fo_binding != nil || jf.self_binding != nil
  if jf.arrow
    return false if jf.uses_this
    g_th = jf.parent
    while g_th != nil && g_th.arrow
      g_th = g_th.parent
    if g_th != nil && g_th.this_binding != nil && jf.free[g_th.this_binding.id] != nil
      return false if g_th.derived || g_th.script || g_th.mod_rec != nil
      return false if jf.single != g_th.this_binding && (g_th.this_binding.slot < 0 || g_th.this_binding.slot >= 7)
  return false if jf.nlocals > 64 || jf.params.size > 5
  n = jf.node
  return jit_node_supported?(n.b) if jf.arrow && n.has?(F_EXPR_BODY)
  jit_list_supported?(n.b)

-> jit_eligible_osr_loop?(s, act)
  jf = act.f
  return false if jf == nil || jf.dynamic || jf.has_tail || jf.has_dispose || jf.nlocals > 64 || jit_has_tdz_hazard?(jf)
  return false if act.coro != nil
  return false if JS_GC_ON[0] && jf.script && act.caller == nil
  return false if s.kind != :for && s.kind != :while
  if s.kind == :for
    sc = s.x
    return false if sc.is_a?(JaScope) && sc.has_env?
    return jit_node_supported?(s.b) && jit_node_supported?(s.c) && jit_node_supported?(s.d)
  jit_node_supported?(s.a) && jit_node_supported?(s.b)

-> jit_poly_expr_pure?(e, sh)
  return false if e == nil
  k = e.kind
  return true if k == :num || k == :true || k == :false || k == :null
  if k == :member && !e.has?(F_COMPUTED) && e.a.kind == :this
    sl = sh.slot_of(e.b.str)
    return sl >= 0 && (sh.attrs_of(e.b.str) & ATTR_ACCESSOR) == 0
  if k == :binary
    op = e.str
    return (op == "+" || op == "-" || op == "*" || op == "/") && jit_poly_expr_pure?(e.a, sh) && jit_poly_expr_pure?(e.b, sh)
  if k == :unary
    return e.str == "-" && jit_poly_expr_pure?(e.a, sh)
  false

-> jit_poly_body_no_arr_mut?(n, sh, depth = 0)
  return true if n == nil
  if n.is_a?(Array)
    i = 0
    while i < n.size
      return false if !jit_poly_body_no_arr_mut?(n[i], sh, depth)
      i += 1
    return true
  return true if !n.is_a?(JsNode)
  k = n.kind
  return true if k == :num || k == :true || k == :false || k == :null || k == :string || k == :this || k == :empty
  return false if k == :new || k == :array || k == :object || k == :function || k == :arrow || k == :class || k == :throw || k == :try || k == :with || k == :for_in || k == :for_of || k == :while || k == :for || k == :do_while
  if k == :ident
    return true if n.x == nil || n.x.binding == nil
    b = n.x.binding
    return !b.global? || b.writes <= 1
  if k == :member
    return false if n.has?(F_COMPUTED)
    return false if n.b != nil && n.b.str == "length"
    return jit_poly_body_no_arr_mut?(n.a, sh, depth)
  if k == :assign
    return false if n.a == nil || n.a.kind != :member || n.a.has?(F_COMPUTED)
    return false if n.a.b != nil && n.a.b.str == "length"
    return jit_poly_body_no_arr_mut?(n.a.a, sh, depth) && jit_poly_body_no_arr_mut?(n.b, sh, depth)
  if k == :unary
    return false if n.str == "delete"
    return jit_poly_body_no_arr_mut?(n.a, sh, depth)
  if k == :binary || k == :logical || k == :cond || k == :if || k == :expr_stmt || k == :return || k == :block
    return jit_poly_body_no_arr_mut?(n.a, sh, depth) && jit_poly_body_no_arr_mut?(n.b, sh, depth) && jit_poly_body_no_arr_mut?(n.c, sh, depth) && jit_poly_body_no_arr_mut?(n.list, sh, depth)
  if k == :call && depth < 2 && n.a != nil && n.a.kind == :member && !n.a.has?(F_COMPUTED)
    return true if n.a.a != nil && n.a.a.kind == :ident && n.a.a.str == "Math" && jit_poly_body_no_arr_mut?(n.list, sh, depth)
    if n.list.size == 0 && n.a.a != nil && n.a.a.kind == :this && sh.is_a?(JS:Shape) && !sh.dict && sh.slot_of(n.a.b.str) < 0
      p = sh.proto
      hops = 0
      while p.is_a?(JS:Base) && hops < 16
        ps = p.shape
        sl = ps.slot_of(n.a.b.str)
        if sl >= 0
          return false if ps.dict || (ps.attrs_of(n.a.b.str) & ATTR_ACCESSOR) != 0
          cfn = p.slot_get(sl)
          return false if !cfn.is_a?(JS:Function) || cfn.code == nil || !cfn.code.node.is_a?(JaFunc)
          cjf = cfn.code.node
          return false if cjf.free.size > 0 || cjf.params.size != 0 || cjf.dynamic || !cjf.simple
          return jit_poly_body_no_arr_mut?(cjf.node.b, sh, depth + 1)
        p = ps.proto
        hops += 1
      return false
  false

-> jit_poly_call_pure?(n)
  return false if n == nil || n.kind != :call || n.list.size != 0 || !n.x.is_a?(Array) || n.x.size < 2 || n.x.size > 8
  c = n.a
  return false if !c.is_a?(JsNode) || c.kind != :member || c.has?(F_COMPUTED)
  q = 0
  while q < n.x.size
    sh = n.x[q]
    fn = n.x[q + 1]
    return false if !sh.is_a?(JS:Shape) || sh.dict || sh.slot_of(c.b.str) >= 0 || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
    tjf = fn.code.node
    return false if tjf.free.size > 0 || tjf.params.size != 0 || tjf.dynamic || !tjf.simple || tjf.node.has?(F_GENERATOR) || tjf.node.has?(F_ASYNC)
    re = jit_inline_return_expr(tjf)
    if re != nil && jit_poly_expr_pure?(re, sh)
      nil
    elsif tjf.node.b.is_a?(Array) && tjf.node.b.size <= 4 && jit_poly_body_no_arr_mut?(tjf.node.b, sh, 0)
      nil
    else
      return false
    q += 2
  true

# ---- Analyzer ----

-> jit_ta_ctor_kind(name)
  return 0 if name == "Int8Array"
  return 1 if name == "Uint8Array"
  return 2 if name == "Uint8ClampedArray"
  return 3 if name == "Int16Array"
  return 4 if name == "Uint16Array"
  return 5 if name == "Int32Array"
  return 6 if name == "Uint32Array"
  return 7 if name == "Float32Array"
  return 8 if name == "Float64Array"
  return 11 if name == "Float16Array"
  -1

+ JitAnalyzer
  rw :info, :jf, :writes, :non_member_reads, :non_call_reads, :member_keys, :sra_field_writes, :depth, :cond_depth, :nonneg_slots

  -> new(@jf, is_osr, loop_node)
    @info = JS:JitInfo.new(@jf, is_osr, loop_node)
    @writes = Array.new(@jf.nlocals, nil)
    @non_member_reads = Array.new(@jf.nlocals, false)
    @non_call_reads = Array.new(@jf.nlocals, false)
    @member_keys = Array.new(@jf.nlocals, nil)
    @sra_field_writes = Array.new(@jf.nlocals, nil)
    @depth = 0
    @cond_depth = 0
    @nonneg_slots = nil
    i = 0
    while i < @jf.nlocals
      @writes[i] = []
      @member_keys[i] = {}
      @sra_field_writes[i] = {}
      i += 1

  -> release
    i = 0
    while i < @writes.size
      ccall("w_value_free_w", @writes[i]) if @writes[i] != nil
      ccall("w_value_free_w", @member_keys[i]) if @member_keys[i] != nil
      ccall("w_value_free_w", @sra_field_writes[i]) if @sra_field_writes[i] != nil
      i += 1
    ccall("w_value_free_w", @writes)
    ccall("w_value_free_w", @non_member_reads)
    ccall("w_value_free_w", @non_call_reads)
    ccall("w_value_free_w", @member_keys)
    ccall("w_value_free_w", @sra_field_writes)
    ccall("w_value_free_w", @nonneg_slots) if @nonneg_slots != nil
    ccall("w_value_free_w", self)
    nil

  -> local_idx(e)
    return -1 if e == nil || e.kind != :ident || e.x == nil
    b = e.x.binding
    return -1 if b == nil
    vs = @info.demoted_env[b]
    return vs if vs != nil
    return -1 if b.global? || b.slot >= 0 || b.scope.func != @jf
    b.lidx

  -> binding_slot(b)
    return -1 if b == nil
    vs = @info.demoted_env[b]
    return vs if vs != nil
    return -1 if b.global? || b.slot >= 0 || b.scope.func != @jf
    b.lidx

  -> grow_slot_arrays
    while @writes.size < @info.total_slots
      @writes.push([])
      @non_member_reads.push(false)
      @non_call_reads.push(false)
      @member_keys.push({})
      @sra_field_writes.push({})
    nil

  # Non-escaping nested function inlining + JS:Env demotion!
  # When ALL nested functions inside @jf are direct-called, non-escaping, non-recursive function_decls,
  # demote @jf's JS:Env bindings + helper params/locals to flat JIT vslots (ZERO JS:Env allocation!).
  -> detect_local_fn_inline
    return false if @info.is_osr || !@jf.scope.has_env? || @jf.scope.has_dyn || !@jf.node.b.is_a?(Array)
    return false if @jf.this_binding != nil && @jf.this_binding.in_env?
    fmap = {}
    f_list = []
    stmts = @jf.node.b
    i = 0
    while i < stmts.size
      st = stmts[i]
      if st.is_a?(JsNode) && st.kind == :function_decl && st.str != nil && st.x.is_a?(JaFunc)
        hjf = st.x
        fb = hjf.binding
        return false if fb == nil || !hjf.simple || hjf.dynamic || hjf.mapped_args || hjf.args_binding != nil || hjf.uses_this
        return false if hjf.node.has?(F_GENERATOR) || hjf.node.has?(F_ASYNC) || hjf.params.size > 4
        return false if hjf.scope.has_env? || hjf.scope.has_dyn || (hjf.body_scope != nil && hjf.body_scope != hjf.scope)
        return false if !hjf.node.b.is_a?(Array) || !jit_list_supported?(hjf.node.b) || jit_has_tdz_hazard?(hjf)
        fmap[fb] = hjf
        f_list.push([fb, hjf])
      i += 1
    return false if fmap.size == 0
    # Verify every free variable of every helper is global or belongs to @jf.scope (and NOT a helper itself!)
    fi = 0
    while fi < f_list.size
      hjf = f_list[fi][1]
      fvs = hjf.free.values
      j = 0
      while j < fvs.size
        fvb = fvs[j]
        return false if fmap[fvb] != nil
        return false if !fvb.global? && fvb.scope != @jf.scope
        j += 1
      fi += 1
    # Verify NO other closures exist and EVERY reference to any helper binding is a direct exact-arity call in outer body!
    return false if !lfi_check_outer_stmts?(stmts, fmap)
    fi = 0
    while fi < f_list.size
      return false if !lfi_check_helper_node?(f_list[fi][1].node.b, fmap)
      fi += 1
    # All checks passed: demote @jf.scope env bindings + helper params/locals to flat JIT vslots!
    @info.demote_env = true
    ord = @jf.scope.order
    i = 0
    while i < ord.size
      b = ord[i]
      if b.slot >= 0 && fmap[b] == nil
        vs = @info.alloc_vslot(JT_ANY)
        @info.demoted_env[b] = vs
      i += 1
    fi = 0
    while fi < f_list.size
      fb = f_list[fi][0]
      hjf = f_list[fi][1]
      pvs = []
      pi = 0
      while pi < hjf.params.size
        pb = hjf.params[pi]
        vs = @info.alloc_vslot(JT_ANY)
        @info.demoted_env[pb] = vs
        @info.helper_owner[vs] = fi if fi < 30
        pvs.push(vs)
        pi += 1
      si = 0
      while si < hjf.scopes.size
        sord = hjf.scopes[si].order
        oi = 0
        while oi < sord.size
          hb = sord[oi]
          if hb.lidx >= 0 && @info.demoted_env[hb] == nil
            vs = @info.alloc_vslot(JT_ANY)
            @info.demoted_env[hb] = vs
            @info.helper_owner[vs] = fi if fi < 30 && local_def_before_use_stmts?(hjf.node.b, vs)
          oi += 1
        si += 1
      rets = []
      lfi_collect_rets(hjf.node.b, rets)
      @info.inlined_fns[fb] = [hjf, pvs, rets]
      fi += 1
    @info.nbase_slots = @info.total_slots
    grow_slot_arrays()
    true

  -> lfi_check_outer_stmts?(stmts, fmap)
    i = 0
    while i < stmts.size
      st = stmts[i]
      if st.is_a?(JsNode) && st.kind != :function_decl
        return false if !lfi_check_node?(st, fmap, true)
      i += 1
    true

  -> lfi_check_helper_node?(n, fmap)
    lfi_check_node?(n, fmap, false)

  -> lfi_check_node?(n, fmap, allow_calls)
    return true if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return false if !lfi_check_node?(n[i], fmap, allow_calls)
        i += 1
      return true
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :function || k == :arrow || k == :function_decl
    if k == :ident
      b = n.x == nil ? nil : n.x.binding
      return false if b != nil && fmap[b] != nil
      return true
    if k == :call && n.a.is_a?(JsNode) && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && fmap[n.a.x.binding] != nil
      return false if !allow_calls
      hjf = fmap[n.a.x.binding]
      return false if n.list.size != hjf.params.size
      return lfi_check_node?(n.list, fmap, allow_calls)
    return false if !lfi_check_node?(n.a, fmap, allow_calls) || !lfi_check_node?(n.b, fmap, allow_calls) || !lfi_check_node?(n.c, fmap, allow_calls) || !lfi_check_node?(n.d, fmap, allow_calls)
    lfi_check_node?(n.list, fmap, allow_calls)

  -> lfi_collect_rets(n, out)
    return nil if n == nil
    if n.is_a?(Array)
      n.each ->(x) lfi_collect_rets(x, out)
      return nil
    return nil if !n.is_a?(JsNode)
    if n.kind == :return
      out.push(n.a)
      return nil
    lfi_collect_rets(n.a, out)
    lfi_collect_rets(n.b, out)
    lfi_collect_rets(n.c, out)
    lfi_collect_rets(n.d, out)
    lfi_collect_rets(n.list, out) if n.list.is_a?(Array)
    nil

  -> analyze(act = nil, warm_args = nil)
    if @info.is_osr
      s = @info.loop_node
      @depth = 1
      if s.kind == :for
        scan_expr(s.b, false, false)
        scan_expr(s.c, false, false)
        scan_stmt(s.d)
      else
        scan_expr(s.a, false, false)
        scan_stmt(s.b)
      @depth = 0
    else
      # Try demoting JS:Env by inlining non-escaping nested helpers!
      detect_local_fn_inline()
      if @jf.scope.has_env? && !@info.demote_env
        @info.uses_env = true
        @info.uses_calls = true
      if @jf.arrow
        g_th = @jf.parent
        while g_th != nil && g_th.arrow
          g_th = g_th.parent
        if g_th != nil && g_th.this_binding != nil && @jf.free[g_th.this_binding.id] != nil
          @info.uses_env = true
          @info.uses_this = true
      i = 0
      while i < @jf.params.size
        pb = @jf.params[i]
        pli = binding_slot(pb)
        @writes[pli].push([:param, nil]) if pli >= 0
        if warm_args.is_a?(Array) && i < warm_args.size && pli >= 0
          wv0 = warm_args[i]
          if wv0.is_a?(JS:Object) && !wv0.shape.dict
            @info.param_shapes[pli] = wv0.shape
          elsif js_string?(wv0)
            @info.param_strs[pli] = true
        i += 1
      n = @jf.node
      if @jf.arrow && n.has?(F_EXPR_BODY)
        scan_expr(n.b, false, false)
      else
        scan_stmts(n.b)
        if @info.inlined_fns.size > 0
          saved_d = @depth
          @depth = 1
          @info.inlined_fns.values.each ->(ih) scan_stmts(ih[0].node.b)
          @depth = saved_d
        prune_dead_cond_undefs()
      # Keep only read-only string params in param_strs and seed str_locals!
      @info.param_strs.keys.each ->(pli)
        if @writes[pli].size == 1 && @writes[pli][0][0] == :param
          @info.str_locals[pli] = true
        else
          @info.param_strs.delete(pli)
    # 1. Detect scalar-replaceable object literals, closure factories & pure value structs
    detect_sra(act, warm_args)
    # 2. Detect loop-invariant TypedArrays, Arrays, and Objects BEFORE type inference so TA loads infer f64/i32!
    detect_invariants(act) if act != nil
    if !@info.is_osr && @info.has_loop && warm_args.is_a?(Array)
      pi = 0
      while pi < @jf.params.size && pi < warm_args.size
        pli = binding_slot(@jf.params[pi])
        wv = warm_args[pi]
        if pli >= 0 && @writes[pli].size == 1 && @writes[pli][0][0] == :param && wv.is_a?(JS:TypedArray) && !wv.buffer.immutable
          if js_ta_length(wv) >= 0 && (wv.kind <= 8 || wv.kind == 11)
            @info.param_tas[pli] = wv.kind
            @info.ta_invariants[pli] = wv.kind
        pi += 1
    # 2b. For non-OSR functions with loops: detect read-only array & numeric params to hoist/unbox in prologue!
    detect_fn_param_hints(warm_args) if !@info.is_osr && @info.has_loop
    # 2c. Detect prologue-verifiable all-number object array elements (e.g. `step(bodies, dt)` in n-body)!
    detect_mono_arr_num_locals() if !@info.is_osr && @info.has_loop
    # 2d. Detect 32-bit-truncating-only locals (enables zero-float raw 32-bit registers for crypto/bitops!)
    detect_bit32_only()
    # 2e. Detect dominating range-guarded `var nb = ny * W + nx` locals (proves JT_I32 + BCE!)
    detect_proven_bounded_i32() if !@info.is_osr
    # 3. Fixed-point type inference (i32 / u32 / f64 / any)
    infer_types(act)
    if @nonneg_slots != nil
      ni = 0
      while ni < @nonneg_slots.size
        @info.nonneg_locals[ni] = true if @nonneg_slots[ni]
        ni += 1
    # 4. Detect self-recursive fast entry (function JIT only)
    detect_fast_rec() if !@info.is_osr
    # 5. Allocate registers for hot locals & virtual slots
    alloc_regs()
    @info

  -> scan_stmts(list)
    return nil if list == nil
    i = 0
    while i < list.size
      scan_stmt(list[i])
      i += 1
    nil

  -> scan_stmt(s)
    return nil if s == nil
    k = s.kind
    if k == :expr_stmt || k == :return || k == :throw
      scan_expr(s.a, false, false)
    elsif k == :var_decl
      is_cond_var = s.str == "var" && @cond_depth > 0
      i = 0
      while i < s.list.size
        d = s.list[i]
        li = local_idx(d.a)
        if d.b != nil
          scan_expr(d.b, false, false)
          if li >= 0
            @writes[li].push([:undef, nil]) if is_cond_var
            @writes[li].push([:init, d.b])
            @info.written_in_loop[li] = true if @depth > 0
            @info.hot_counts[li] = @info.hot_counts[li] + (@depth > 0 ? 10 : 1)
        elsif li >= 0
          @writes[li].push([:undef, nil])
          @info.written_in_loop[li] = true if @depth > 0
        i += 1
    elsif k == :block
      scan_stmts(s.list)
    elsif k == :if
      scan_expr(s.a, false, false)
      @cond_depth += 1
      scan_stmt(s.b)
      scan_stmt(s.c)
      @cond_depth -= 1
    elsif k == :for
      @info.has_loop = true
      scan_stmt(s.a) if s.a != nil && s.a.kind == :var_decl
      scan_expr(s.a, false, false) if s.a != nil && s.a.kind != :var_decl
      @depth += 1
      @cond_depth += 1
      scan_expr(s.b, false, false)
      scan_expr(s.c, false, false)
      scan_stmt(s.d)
      @cond_depth -= 1
      @depth -= 1
    elsif k == :for_in
      @info.has_loop = true
      @info.uses_calls = true
      scan_expr(s.b, false, false)
      lhs_id = s.a.kind == :var_decl ? s.a.list[0].a : s.a
      li = local_idx(lhs_id)
      if li >= 0
        @writes[li].push([:for_in, nil])
        @info.written_in_loop[li] = true
        @info.hot_counts[li] = @info.hot_counts[li] + 10
      @depth += 1
      @cond_depth += 1
      scan_stmt(s.d)
      @cond_depth -= 1
      @depth -= 1
    elsif k == :while || k == :do_while
      @info.has_loop = true
      @depth += 1
      @cond_depth += 1 if k == :while
      scan_expr(s.a, false, false) if k == :while
      scan_stmt(s.b) if k == :while
      @cond_depth -= 1 if k == :while
      scan_stmt(s.a) if k == :do_while
      scan_expr(s.b, false, false) if k == :do_while
      @depth -= 1
    elsif k == :function_decl
      if s.str != nil && s.x.is_a?(JaFunc)
        inner_jf = s.x
        fb = inner_jf.binding
        if @info.inlined_fns[fb] == nil
          @info.uses_calls = true
          if inner_jf.single != nil
            sb = inner_jf.single
            if !sb.global? && (sb.slot >= 0 || sb.scope.func != @jf)
              @info.uses_env = true
            elsif !sb.global? && sb.scope.func == @jf && sb.lidx >= 0
              @non_member_reads[sb.lidx] = true
              @non_call_reads[sb.lidx] = true
          elsif inner_jf.free.size > 0
            @info.uses_env = true
          fli = binding_slot(fb)
          @writes[fli].push([:closure, s]) if fli >= 0
    nil

  # mem_base: true if this ident is directly the receiver of a non-computed .prop access
  # call_callee: true if this ident is directly the callee of f(...)
  -> scan_expr(e, mem_base, call_callee)
    return nil if e == nil
    k = e.kind
    if k == :ident
      li = local_idx(e)
      if li >= 0
        @info.hot_counts[li] = @info.hot_counts[li] + (@depth > 0 ? 10 : 1)
        @non_member_reads[li] = true if !mem_base
        @non_call_reads[li] = true if !call_callee
      elsif e.x != nil && e.x.binding != nil
        gb = e.x.binding
        if gb.global?
          if !@info.is_osr && !call_callee && gb.writes <= 1 && @info.global_i32s[gb] == nil && @info.global_tas[gb] == nil && @info.global_objs[gb] == nil && e.str != "undefined" && e.str != "NaN" && e.str != "Infinity"
            gc = wk_cell(gb)
            gv = gc.value
            if js_number?(gv) && @info.global_i32s.size < 16
              bi = jsr_i32(wvalue_bits(gv) ## i64)
              if bi != JSR_NOI32 && bi.to_f == gv && !(gv == ~0.0 && (~1.0 / gv) < ~0.0)
                @info.global_i32s[gb] = [bi, gc, gv]
            elsif @info.global_objs.size < 8 && ((gv.is_a?(JS:Base) && !gv.shape.dict && !gv.exotic? && !gv.is_a?(JS:TypedArray)) || js_array?(gv))
              @info.global_objs[gb] = [gc, gv]
        elsif gb.slot >= 0 || gb.scope.func != @jf
          @info.uses_env = true if @info.inlined_fns[gb] == nil
    elsif k == :this
      @info.uses_this = true
      @info.uses_env = true if @jf.arrow
    elsif k == :binary || k == :logical
      scan_expr(e.a, false, false)
      scan_expr(e.b, false, false)
    elsif k == :unary
      scan_expr(e.a, false, false)
    elsif k == :update
      li = local_idx(e.a)
      if li >= 0
        @writes[li].push([:update, e])
        @info.written_in_loop[li] = true if @depth > 0
        @info.hot_counts[li] = @info.hot_counts[li] + (@depth > 0 ? 10 : 1)
        @non_member_reads[li] = true
        @non_call_reads[li] = true
      else
        scan_expr(e.a, false, false)
    elsif k == :assign
      li = local_idx(e.a)
      if li >= 0
        scan_expr(e.b, false, false)
        @writes[li].push([e.str == "=" ? :assign : :compound, e])
        @info.written_in_loop[li] = true if @depth > 0
        @info.hot_counts[li] = @info.hot_counts[li] + (@depth > 0 ? 10 : 1)
        if e.str != "="
          @non_member_reads[li] = true
          @non_call_reads[li] = true
      elsif e.a.kind == :member && !e.a.has?(F_COMPUTED)
        bli = local_idx(e.a.a)
        if bli >= 0
          @member_keys[bli][e.a.b.str] = true
          @non_call_reads[bli] = true
          @info.hot_counts[bli] = @info.hot_counts[bli] + (@depth > 0 ? 10 : 1)
          if e.str == "="
            fw = @sra_field_writes[bli][e.a.b.str]
            if fw == nil
              fw = []
              @sra_field_writes[bli][e.a.b.str] = fw
            fw.push(e.b)
          else
            @non_member_reads[bli] = true
        else
          scan_expr(e.a.a, false, false)
        scan_expr(e.b, false, false)
      else
        scan_expr(e.a, false, false)
        scan_expr(e.b, false, false)
    elsif k == :cond
      scan_expr(e.a, false, false)
      scan_expr(e.b, false, false)
      scan_expr(e.c, false, false)
    elsif k == :member
      if !e.has?(F_COMPUTED)
        bli = local_idx(e.a)
        if bli >= 0
          @member_keys[bli][e.b.str] = true
          @non_call_reads[bli] = true
          @info.hot_counts[bli] = @info.hot_counts[bli] + (@depth > 0 ? 10 : 1)
        else
          scan_expr(e.a, false, false)
      else
        # Check read-only global TypedArray access `K[i]` / `GRID[nb]`!
        if !@info.is_osr && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.global?
          gb = e.a.x.binding
          if gb.writes <= 1 && @info.global_tas[gb] == nil
            gc = wk_cell(gb)
            gv = gc.value
            if gv.is_a?(JS:TypedArray) && !gv.buffer.immutable && js_ta_length(gv) >= 0 && (gv.kind <= 8 || gv.kind == 11)
              @info.global_tas[gb] = [gv.kind, gc, gv]
        scan_expr(e.a, false, false)
        scan_expr(e.b, false, false)
    elsif k == :call
      # Check if this is an inlined nested helper call (zero call overhead, records writes to helper param vslots!)
      if e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && @info.inlined_fns[e.a.x.binding] != nil
        ih = @info.inlined_fns[e.a.x.binding]
        pvs = ih[1]
        i = 0
        while i < e.list.size
          scan_expr(e.list[i], false, false)
          if i < pvs.size
            @writes[pvs[i]].push([:init, e.list[i]])
            @info.written_in_loop[pvs[i]] = true if @depth > 0
            @info.hot_counts[pvs[i]] = @info.hot_counts[pvs[i]] + (@depth > 0 ? 10 : 1)
          i += 1
        return nil
      is_inline_math = e.a != nil && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a != nil && e.a.a.kind == :ident && e.a.a.str == "Math" && e.list.size == 1 && (e.a.b.str == "sqrt" || e.a.b.str == "abs" || e.a.b.str == "floor" || e.a.b.str == "ceil" || e.a.b.str == "trunc")
      @info.uses_calls = true if !is_inline_math
      if e.a.kind == :ident
        scan_expr(e.a, false, true)
      else
        scan_expr(e.a, false, false)
      i = 0
      while i < e.list.size
        scan_expr(e.list[i], false, false)
        i += 1
    elsif k == :new
      @info.uses_calls = true
      scan_expr(e.a, false, false)
      i = 0
      while i < e.list.size
        scan_expr(e.list[i], false, false)
        i += 1
    elsif k == :array
      i = 0
      while i < e.list.size
        scan_expr(e.list[i], false, false)
        i += 1
    elsif k == :object
      i = 0
      while i < e.list.size
        scan_expr(e.list[i].b, false, false)
        i += 1
    elsif k == :seq
      i = 0
      while i < e.list.size
        scan_expr(e.list[i], false, false)
        i += 1
    elsif k == :template
      i = 0
      while i < e.a.size
        scan_expr(e.a[i], false, false)
        i += 1
    elsif k == :function || k == :arrow
      @info.uses_calls = true
      inner_jf = e.x
      if inner_jf.is_a?(JaFunc)
        if inner_jf.single != nil
          sb = inner_jf.single
          if !sb.global? && (sb.slot >= 0 || sb.scope.func != @jf)
            @info.uses_env = true
          elsif !sb.global? && sb.scope.func == @jf && sb.lidx >= 0
            @non_member_reads[sb.lidx] = true
            @non_call_reads[sb.lidx] = true
        elsif inner_jf.free.size > 0
          @info.uses_env = true
    nil

  # ---- 1. Scalar Replacement of Aggregates (non-escaping objects & closures) ----
  -> detect_sra(act, warm_args = nil)
    i = 0
    while i < @info.nbase_slots
      ws = @writes[i]
      if ws.size > 0
        # Candidate A: Non-escaping plain object literal
        if !@non_member_reads[i]
          ok = true
          ks = nil
          j = 0
          while j < ws.size && ok
            wk = ws[j][0]
            rhs = wk == :init ? ws[j][1] : (wk == :assign ? ws[j][1].b : nil)
            if rhs == nil || rhs.kind != :object
              ok = false
            else
              rk = jit_plain_obj_keys(rhs)
              if rk == nil || rk.size == 0
                ok = false
              elsif ks == nil
                ks = rk
              elsif ks.size != rk.size
                ok = false
              else
                q = 0
                while q < ks.size
                  ok = false if ks[q] != rk[q]
                  q += 1
            j += 1
          # Also check every accessed property key is one of ks (no prototype property reads like .toString!)
          if ok && ks != nil
            @member_keys[i].keys.each ->(mk) ok = false if !ks.include?(mk)
          if ok && ks != nil && (!@info.is_osr || @info.written_in_loop[i] == true)
            sra = JS:JitSraObj.new(i, ks)
            q = 0
            while q < ks.size
              sra.field_slots[ks[q]] = @info.alloc_vslot(JT_ANY)
              q += 1
            # Detect compile-time constant i32 fields (single literal init, never written!)
            if ws.size == 1
              init_obj = ws[0][0] == :init ? ws[0][1] : ws[0][1].b
              q = 0
              while q < init_obj.list.size
                p = init_obj.list[q]
                kn = p.a.str
                if @sra_field_writes[i][kn] == nil && jit_int32_lit?(p.b)
                  sra.const_i32[kn] = p.b.a.to_i
                q += 1
            @info.sra_objs[i] = sra
            @info.types[i] = JT_SRA_OBJ
        # Candidate A2: Local TypedArray created once via `var buf = new Uint8Array(...)` (non-OSR function JIT)
        if !@info.is_osr && @info.types[i] == JT_ANY && ws.size == 1 && ws[0][0] == :init && @info.written_in_loop[i] != true
          rhs_ta = ws[0][1]
          if rhs_ta != nil && rhs_ta.kind == :new && rhs_ta.a != nil && rhs_ta.a.kind == :ident && rhs_ta.a.x != nil && rhs_ta.a.x.binding != nil && rhs_ta.a.x.binding.global?
            tk = jit_ta_ctor_kind(rhs_ta.a.str)
            if tk >= 0
              @info.local_tas[i] = tk
              @info.ta_invariants[i] = tk
              if rhs_ta.list.size == 1
                la = rhs_ta.list[0]
                if jit_int32_lit?(la) && la.a.to_i > 0
                  @info.local_ta_lens[i] = la.a.to_i
                elsif la.kind == :ident && la.x != nil && la.x.binding != nil && @info.global_i32s[la.x.binding] != nil
                  lv = @info.global_i32s[la.x.binding][0]
                  @info.local_ta_lens[i] = lv if lv > 0
                elsif la.kind == :binary && la.str == "*" && la.a.kind == :ident && la.a.x != nil && la.a.x.binding != nil && @info.global_i32s[la.a.x.binding] != nil && jit_small_int_lit?(la.b, 1024)
                  lv = @info.global_i32s[la.a.x.binding][0] * la.b.a.to_i
                  @info.local_ta_lens[i] = lv if lv > 0 && lv <= 1073741824
          elsif rhs_ta != nil && rhs_ta.kind == :string
            @info.str_locals[i] = true
          elsif rhs_ta != nil && rhs_ta.kind == :array && rhs_ta.list.size == 0 && i < @jf.nlocals && local_arr_push_safe?(@jf.node.b, i)
            @info.local_arrs[i] = true
          elsif rhs_ta != nil && rhs_ta.kind == :call && rhs_ta.a.kind == :member && !rhs_ta.a.has?(F_COMPUTED) && rhs_ta.a.a.kind == :ident && rhs_ta.a.a.str == "Object" && rhs_ta.a.b.str == "keys" && rhs_ta.list.size == 1 && i < @jf.nlocals && ro_keys_safe?(@jf.node.b, i)
            @info.ro_keys_locals[i] = true
            @info.ro_keys_calls[rhs_ta] = true
        # Candidate B: Non-escaping closure from a known closure-factory call `var f = adder(e0)`
        if @info.types[i] == JT_ANY && !@non_call_reads[i] && ws.size == 1
          wk = ws[0][0]
          rhs = wk == :init ? ws[0][1] : (wk == :assign ? ws[0][1].b : nil)
          if rhs != nil && rhs.kind == :call && rhs.a.kind == :ident && rhs.a.x != nil
            fb = rhs.a.x.binding
            if fb != nil && fb.global?
              cell = wk_cell(fb)
              fv = cell.value
              if fv.is_a?(JS:Function) && fv.code != nil && fv.code.node.is_a?(JaFunc)
                fjf = fv.code.node
                inner = jit_closure_factory_inner(fjf)
                if inner != nil && rhs.list.size == fjf.params.size
                  cslots = []
                  q = 0
                  while q < fjf.params.size
                    cslots.push(@info.alloc_vslot(JT_ANY))
                    q += 1
                  @info.sra_clos[i] = JS:JitSraClos.new(i, fb, fv, inner, cslots, rhs.list.size)
                  @info.types[i] = JT_SRA_CLOS
        # Candidate C: Non-escaping RegExp exec match variable `while ((m = re.exec(text)) !== null) n += m[2].length;`
        if @info.types[i] == JT_ANY && (!@info.is_osr || @info.written_in_loop[i] == true)
          ok_rx = true
          has_exec = false
          j = 0
          while j < ws.size && ok_rx
            wk = ws[j][0]
            rhs = wk == :init ? ws[j][1] : (wk == :assign ? ws[j][1].b : nil)
            if wk == :undef || (wk == :init && rhs == nil)
              nil
            elsif rhs != nil && rhs.kind == :null
              nil
            elsif rhs != nil && rhs.kind == :call && rhs.a.kind == :member && !rhs.a.has?(F_COMPUTED) && rhs.a.b.str == "exec" && rhs.list.size == 1
              has_exec = true
            else
              ok_rx = false
            j += 1
          if ok_rx && has_exec && sra_rx_node_ok?(@jf.node.b, i)
            caps = i64[32]
            ci = 0
            while ci < 32
              caps[ci] = -1
              ci += 1
            jit_keep(caps)
            @info.sra_rxs[i] = caps
            @info.types[i] = JT_SRA_RX
      i += 1
    # Propagate str_locals through `s.slice(...)` and string literals (enables unboxed i32 indices in parsers!)
    if !@info.is_osr
      s_nbase = @info.nbase_slots
      s_changed = true
      while s_changed
        s_changed = false
        si = 0
        while si < s_nbase
          if @info.types[si] == JT_ANY && @info.str_locals[si] == nil
            ws = @writes[si]
            if ws.size > 0
              all_s = true
              wj = 0
              while wj < ws.size && all_s
                wk = ws[wj][0]
                wn = ws[wj][1]
                rhs_s = wk == :init ? wn : (wk == :assign ? wn.b : nil)
                if rhs_s == nil
                  all_s = false
                elsif rhs_s.kind == :string
                  nil
                elsif rhs_s.kind == :call && rhs_s.a.kind == :member && !rhs_s.a.has?(F_COMPUTED) && rhs_s.a.b.str == "slice" && (rhs_s.list.size == 1 || rhs_s.list.size == 2)
                  rli = local_idx(rhs_s.a.a)
                  all_s = false if rli < 0 || @info.str_locals[rli] == nil
                else
                  all_s = false
                wj += 1
              if all_s
                @info.str_locals[si] = true
                @info.needs_entry_epoch = true
                s_changed = true
          si += 1
    # Candidate D: Unboxed value-struct function ABI (`jit_vs_fp`) & non-escaping pure value-struct locals!
    if !@info.is_osr && @jf.node.b.is_a?(Array)
      known_vs_sh = {}
      @info.param_shapes.each ->(pli, sh) known_vs_sh[pli] = sh
      # Step D0: Check if `@jf` qualifies for an unboxed value-struct entry (`trace(ro, rd, depth) -> Vec`)!
      cand_vs_sig = nil
      if !@jf.uses_this && !@info.uses_env && !@jf.arrow && @jf.params.size >= 1 && @jf.params.size <= 4 && warm_args.is_a?(Array) && warm_args.size >= @jf.params.size
        pspecs = []
        n_vs_p = 0
        n_fp_p = 0
        ok_p = true
        pi = 0
        while pi < @jf.params.size && ok_p
          pb = @jf.params[pi]
          pli = binding_slot(pb)
          wv = warm_args[pi]
          if pli < 0 || @writes[pli].size != 1 || @writes[pli][0][0] != :param
            ok_p = false
          elsif wv.is_a?(JS:Object)
            ci_p = jit_vs_ctor_info_for_shape(wv.shape, wv)
            if ci_p != nil
              pspecs.push([:vs, ci_p])
              n_vs_p += 1
              n_fp_p += ci_p[2].size
              known_vs_sh[pli] = ci_p[4]
            else
              ok_p = false
          elsif wv.is_a?(Float) && wv == wv
            if wv >= ~-2147483648.0 && wv <= ~2147483647.0 && wv.to_i.to_f == wv && !(wv == ~0.0 && (~1.0 / wv) < ~0.0)
              pspecs.push([:i32])
            else
              pspecs.push([:f64])
              n_fp_p += 1
          else
            ok_p = false
          pi += 1
        if ok_p && n_vs_p >= 1 && n_fp_p <= 8
          rets = []
          lfi_collect_rets(@jf.node.b, rets)
          if rets.size >= 1
            # First find a non-recursive return ci to seed self-recursion!
            ret_ci = nil
            ri = 0
            while ri < rets.size && ret_ci == nil
              ret_ci = expr_vs_ctor_info(rets[ri], known_vs_sh, nil) if rets[ri] != nil
              ri += 1
            if ret_ci != nil
              # Propagate shapes through locals with `self_ret_ci = ret_ci`!
              pass0 = 0
              while pass0 < 3
                i = 0
                while i < @jf.nlocals
                  if known_vs_sh[i] == nil && @info.types[i] == JT_ANY && @writes[i].size > 0
                    ws = @writes[i]
                    ci0 = nil
                    ok_sh = true
                    j = 0
                    while j < ws.size && ok_sh
                      wk = ws[j][0]
                      rhs = wk == :init ? ws[j][1] : (wk == :assign ? ws[j][1].b : nil)
                      if wk == :undef || (wk == :init && rhs == nil)
                        nil
                      else
                        ci = expr_vs_ctor_info(rhs, known_vs_sh, ret_ci)
                        if ci == nil
                          ok_sh = false
                        elsif ci0 == nil
                          ci0 = ci
                        elsif ci0[4] != ci[4]
                          ok_sh = false
                      j += 1
                    known_vs_sh[i] = ci0[4] if ok_sh && ci0 != nil
                  i += 1
                pass0 += 1
              # Verify EVERY return produces `ret_ci`!
              all_ret_ok = true
              ri = 0
              while ri < rets.size && all_ret_ok
                re = rets[ri]
                if re == nil
                  all_ret_ok = false
                else
                  rci = expr_vs_ctor_info(re, known_vs_sh, ret_ci)
                  if rci == nil && re.kind == :ident && local_idx(re) >= 0 && known_vs_sh[local_idx(re)] == ret_ci[4]
                    rci = ret_ci
                  all_ret_ok = false if rci == nil || rci[4] != ret_ci[4]
                ri += 1
              if all_ret_ok
                cand_vs_sig = [pspecs, ret_ci]
                # Verify no vstruct parameter escapes!
                pi = 0
                while pi < @jf.params.size && cand_vs_sig != nil
                  if pspecs[pi][0] == :vs
                    pli = binding_slot(@jf.params[pi])
                    cand_vs_sig = nil if !sra_vs_node_ok?(@jf.node.b, pli, pspecs[pi][1], known_vs_sh, cand_vs_sig)
                  pi += 1
      if cand_vs_sig != nil
        @info.vs_fn_sig = cand_vs_sig
        @info.needs_entry_epoch = true
        pspecs = cand_vs_sig[0]
        pi = 0
        while pi < @jf.params.size
          pli = binding_slot(@jf.params[pi])
          if pspecs[pi][0] == :vs
            ci_p = pspecs[pi][1]
            vs_obj = JS:JitSraVs.new(pli, ci_p, ci_p[2])
            q = 0
            while q < ci_p[2].size
              vs_obj.field_slots[ci_p[2][q]] = @info.alloc_vslot(JT_F64)
              q += 1
            @info.sra_vs[pli] = vs_obj
            @info.types[pli] = JT_SRA_VS
          elsif pspecs[pi][0] == :i32
            @info.param_ints[pli] = true
          elsif pspecs[pi][0] == :f64
            @info.param_nums[pli] = true
          pi += 1
      # Propagate shapes through locals in 3 passes so `p = ro.add(...)` feeds `n = p.sub(...).norm()` and `col = col.mul(...)`!
      self_rci = @info.vs_fn_sig != nil ? @info.vs_fn_sig[1] : nil
      pass = 0
      while pass < 3
        i = 0
        while i < @jf.nlocals
          if known_vs_sh[i] == nil && @info.types[i] == JT_ANY && @writes[i].size > 0
            ws = @writes[i]
            ci0 = nil
            ok_sh = true
            j = 0
            while j < ws.size && ok_sh
              wk = ws[j][0]
              rhs = wk == :init ? ws[j][1] : (wk == :assign ? ws[j][1].b : nil)
              if wk == :undef || (wk == :init && rhs == nil)
                nil
              else
                ci = expr_vs_ctor_info(rhs, known_vs_sh, self_rci)
                if ci == nil
                  ok_sh = false
                elsif ci0 == nil
                  ci0 = ci
                elsif ci0[4] != ci[4]
                  ok_sh = false
              j += 1
            known_vs_sh[i] = ci0[4] if ok_sh && ci0 != nil
          i += 1
        pass += 1
      # Now promote non-escaping single- or multi-write same-shape locals to JT_SRA_VS!
      i = 0
      while i < @jf.nlocals
        if @info.types[i] == JT_ANY && @writes[i].size >= 1
          ws = @writes[i]
          ci0 = nil
          ok_vs = true
          j = 0
          while j < ws.size && ok_vs
            wk = ws[j][0]
            rhs = wk == :init ? ws[j][1] : (wk == :assign ? ws[j][1].b : nil)
            if wk == :undef
              nil
            elsif wk == :init || wk == :assign
              ci = expr_vs_ctor_info(rhs, known_vs_sh, self_rci)
              if ci == nil
                ok_vs = false
              elsif ci0 == nil
                ci0 = ci
              elsif ci0[4] != ci[4]
                ok_vs = false
            else
              ok_vs = false
            j += 1
          if ok_vs && ci0 != nil && sra_vs_node_ok?(@jf.node.b, i, ci0, known_vs_sh, @info.vs_fn_sig)
            vs_obj = JS:JitSraVs.new(i, ci0, ci0[2])
            q = 0
            while q < ci0[2].size
              vs_obj.field_slots[ci0[2][q]] = @info.alloc_vslot(JT_F64)
              q += 1
            @info.sra_vs[i] = vs_obj
            @info.types[i] = JT_SRA_VS
            @info.needs_entry_epoch = true
            known_vs_sh[i] = ci0[4]
        i += 1
    nil

  # Resolve the pure value-struct ctor_info produced by expression `e` (or nil).
  -> expr_vs_ctor_info(e, known_vs_sh, self_ret_ci = nil)
    return nil if !e.is_a?(JsNode)
    k = e.kind
    if k == :ident
      li = local_idx(e)
      return @info.sra_vs[li].ctor_info if li >= 0 && @info.sra_vs[li] != nil
      if li >= 0 && known_vs_sh[li] != nil
        return jit_vs_ctor_info_for_shape(known_vs_sh[li])
      if e.x != nil && e.x.binding != nil && @info.global_objs[e.x.binding] != nil
        gv = @info.global_objs[e.x.binding][1]
        return jit_vs_ctor_info_for_shape(gv.shape) if gv.is_a?(JS:Object)
      return nil
    if k == :new && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.global?
      cell = wk_cell(e.a.x.binding)
      ci = jit_vstruct_ctor_info(cell.value)
      return ci if ci != nil && e.list.size == ci[2].size
      return nil
    if k == :call && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil
      if self_ret_ci != nil && e.a.x.binding == @jf.binding && e.list.size == @jf.params.size
        return self_ret_ci
      if e.a.x.binding.global?
        fv = wk_cell(e.a.x.binding).value
        if fv.is_a?(JS:Function) && fv.code != nil && fv.code.jit_vs_sig != nil && e.list.size == fv.code.jit_vs_sig[0].size
          return fv.code.jit_vs_sig[1]
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED)
      mname = e.a.b.str
      rsh = nil
      fn = nil
      if e.x.is_a?(Array) && e.x.size == 2 && e.x[0].is_a?(JS:Shape) && e.x[1].is_a?(JS:Function)
        rsh = e.x[0]
        fn = e.x[1]
      else
        rci = expr_vs_ctor_info(e.a.a, known_vs_sh, self_ret_ci)
        if rci != nil
          rsh = rci[4]
        elsif e.a.a.kind == :ident
          rli = local_idx(e.a.a)
          rsh = known_vs_sh[rli] if rli >= 0
        if rsh != nil && rsh.proto.is_a?(JS:Object)
          cand = rsh.proto.get_own(mname)
          fn = cand if cand.is_a?(JS:Function)
        elsif known_vs_sh.size > 0
          known_vs_sh.values.each ->(csh)
            if fn == nil && csh.is_a?(JS:Shape) && csh.proto.is_a?(JS:Object)
              cand = csh.proto.get_own(mname)
              if cand.is_a?(JS:Function)
                cmi = jit_vstruct_method_info(cand, csh)
                if cmi != nil && e.list.size == cmi[1].params.size
                  rsh = csh
                  fn = cand
      if rsh != nil && fn != nil
        mi = jit_vstruct_method_info(fn, rsh)
        return mi[2] if mi != nil && (mi[0] == :vstruct_new || mi[0] == :vstruct_call)
    nil

  # Check if local `li` (holding a value struct of `ci`) NEVER escapes in `n`!
  # Allowed uses:
  #   - LHS of its own var_decl / assign
  #   - `li.field` (known own field in `ci[2]`)
  #   - `return li` (when enclosing function has matching `vs_fn_sig`)
  #   - receiver or arg of a pure vstruct/scalar method on `ci[4]`, or arg of a `jit_vs_method_f64_info` method,
  #     or arg of a direct `jit_vs_fp` call (self or global)!
  -> sra_vs_node_ok?(n, li, ci, known_vs_sh, cur_vs_sig = nil)
    return true if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return false if !sra_vs_node_ok?(n[i], li, ci, known_vs_sh, cur_vs_sig)
        i += 1
      return true
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :ident && local_idx(n) == li
    if k == :return
      return true if n.a != nil && n.a.kind == :ident && local_idx(n.a) == li && cur_vs_sig != nil && cur_vs_sig[1][4] == ci[4]
      return sra_vs_node_ok?(n.a, li, ci, known_vs_sh, cur_vs_sig)
    if k == :var_decl
      i = 0
      while i < n.list.size
        d = n.list[i]
        if d.a.kind == :ident && local_idx(d.a) == li
          return false if d.b != nil && !sra_vs_node_ok?(d.b, li, ci, known_vs_sh, cur_vs_sig)
        else
          return false if !sra_vs_node_ok?(d.a, li, ci, known_vs_sh, cur_vs_sig) || !sra_vs_node_ok?(d.b, li, ci, known_vs_sh, cur_vs_sig)
        i += 1
      return true
    if k == :assign && n.str == "=" && n.a.kind == :ident && local_idx(n.a) == li
      return sra_vs_node_ok?(n.b, li, ci, known_vs_sh, cur_vs_sig)
    if k == :member && !n.has?(F_COMPUTED) && n.a.kind == :ident && local_idx(n.a) == li
      return ci[2].include?(n.b.str)
    if k == :call && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil
      # Direct call to self (`cur_vs_sig`) or compiled global `jit_vs_fp` function!
      csig = nil
      if cur_vs_sig != nil && n.a.x.binding == @jf.binding
        csig = cur_vs_sig
      elsif n.a.x.binding.global?
        fv = wk_cell(n.a.x.binding).value
        csig = fv.code.jit_vs_sig if fv.is_a?(JS:Function) && fv.code != nil && fv.code.jit_vs_fp != 0
      if csig != nil && n.list.size == csig[0].size
        ai = 0
        while ai < n.list.size
          ae = n.list[ai]
          if ae.kind == :ident && local_idx(ae) == li
            ps = csig[0][ai]
            return false if ps[0] != :vs || ps[1][4] != ci[4]
          else
            return false if !sra_vs_node_ok?(ae, li, ci, known_vs_sh, cur_vs_sig)
          ai += 1
        return true
    if k == :call && n.a.kind == :member && !n.a.has?(F_COMPUTED)
      mname = n.a.b.str
      rec_is_li = n.a.a.kind == :ident && local_idx(n.a.a) == li
      arg_has_li = false
      ai = 0
      while ai < n.list.size
        arg_has_li = true if n.list[ai].kind == :ident && local_idx(n.list[ai]) == li
        ai += 1
      if rec_is_li || arg_has_li
        sh = ci[4]
        fn = sh.proto.is_a?(JS:Object) ? sh.proto.get_own(mname) : nil
        mi = fn.is_a?(JS:Function) ? jit_vstruct_method_info(fn, sh) : nil
        if mi != nil
          return false if !rec_is_li && !sra_vs_node_ok?(n.a.a, li, ci, known_vs_sh, cur_vs_sig)
          ai = 0
          while ai < n.list.size
            ae = n.list[ai]
            if !(ae.kind == :ident && local_idx(ae) == li)
              return false if !sra_vs_node_ok?(ae, li, ci, known_vs_sh, cur_vs_sig)
            ai += 1
          return true
        # Also allow passing `li` as an arg to an inlineable multi-stmt pure-numeric method (e.g. `spheres[i].hit(p, light)`)!
        if !rec_is_li
          m_prof = (n.x.is_a?(Array) && n.x.size == 2 && n.x[0].is_a?(JS:Shape) && n.x[1].is_a?(JS:Function)) ? n.x : jit_infer_global_arr_method(n.a, @info.global_objs)
          if m_prof != nil
            arg_cis = []
            ai = 0
            while ai < n.list.size
              ae = n.list[ai]
              aci = (ae.kind == :ident && local_idx(ae) == li) ? ci : expr_vs_ctor_info(ae, known_vs_sh, cur_vs_sig != nil ? cur_vs_sig[1] : nil)
              arg_cis.push(aci)
              ai += 1
            if jit_vs_method_f64_info(m_prof[1], m_prof[0], arg_cis) != nil
              return false if !sra_vs_node_ok?(n.a.a, li, ci, known_vs_sh, cur_vs_sig)
              ai = 0
              while ai < n.list.size
                ae = n.list[ai]
                if !(ae.kind == :ident && local_idx(ae) == li)
                  return false if !sra_vs_node_ok?(ae, li, ci, known_vs_sh, cur_vs_sig)
                ai += 1
              return true
        return false
    return false if !sra_vs_node_ok?(n.a, li, ci, known_vs_sh, cur_vs_sig) || !sra_vs_node_ok?(n.b, li, ci, known_vs_sh, cur_vs_sig) || !sra_vs_node_ok?(n.c, li, ci, known_vs_sh, cur_vs_sig) || !sra_vs_node_ok?(n.d, li, ci, known_vs_sh, cur_vs_sig)
    sra_vs_node_ok?(n.list, li, ci, known_vs_sh, cur_vs_sig)

  # Verify every occurrence of local `li` in the entire function body is a non-escaping SRA_RX use!
  -> sra_rx_node_ok?(n, li)
    return true if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return false if !sra_rx_node_ok?(n[i], li)
        i += 1
      return true
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :ident && local_idx(n) == li
    # Allow `m = re.exec(s)` / `m = null` inside `(m = ...) !== null` or standalone expr_stmt
    if k == :binary && (n.str == "!==" || n.str == "===") && n.b.kind == :null
      if n.a.kind == :ident && local_idx(n.a) == li
        return true
      if n.a.kind == :assign && n.a.str == "=" && n.a.a.kind == :ident && local_idx(n.a.a) == li
        return sra_rx_node_ok?(n.a.b, li)
    if k == :assign && n.str == "=" && n.a.kind == :ident && local_idx(n.a) == li
      return sra_rx_node_ok?(n.b, li)
    if k == :var_decl
      i = 0
      while i < n.list.size
        d = n.list[i]
        if d.a.kind == :ident && local_idx(d.a) == li
          return false if d.b != nil && !sra_rx_node_ok?(d.b, li)
        else
          return false if !sra_rx_node_ok?(d.a, li) || !sra_rx_node_ok?(d.b, li)
        i += 1
      return true
    # Allow `m[k].length` (0 <= k < 15) and `m.index`
    if k == :member && !n.has?(F_COMPUTED)
      if n.b.str == "index" && n.a.kind == :ident && local_idx(n.a) == li
        return true
      if n.b.str == "length" && n.a.kind == :member && n.a.has?(F_COMPUTED) && n.a.a.kind == :ident && local_idx(n.a.a) == li && jit_int32_lit?(n.a.b) && n.a.b.a.to_i >= 0 && n.a.b.a.to_i < 15
        return true
    return false if !sra_rx_node_ok?(n.a, li) || !sra_rx_node_ok?(n.b, li) || !sra_rx_node_ok?(n.c, li) || !sra_rx_node_ok?(n.d, li)
    sra_rx_node_ok?(n.list, li)

  # Verify local `li` (initialized via `Object.keys(o)`) is ONLY read via `.length` and `[idx]` (zero escape/mutation!).
  -> ro_keys_safe?(n, li)
    return true if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return false if !ro_keys_safe?(n[i], li)
        i += 1
      return true
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :ident && local_idx(n) == li
    if k == :var_decl
      i = 0
      while i < n.list.size
        d = n.list[i]
        if d.a.kind == :ident && local_idx(d.a) == li
          return false if !ro_keys_safe?(d.b, li)
        else
          return false if !ro_keys_safe?(d.a, li) || !ro_keys_safe?(d.b, li)
        i += 1
      return true
    if k == :assign && n.a.kind == :member && n.a.a.kind == :ident && local_idx(n.a.a) == li
      return false
    if k == :member && !n.has?(F_COMPUTED) && n.b.str == "length" && n.a.kind == :ident && local_idx(n.a) == li
      return true
    if k == :member && n.has?(F_COMPUTED) && n.a.kind == :ident && local_idx(n.a) == li
      return ro_keys_safe?(n.b, li)
    return false if !ro_keys_safe?(n.a, li) || !ro_keys_safe?(n.b, li) || !ro_keys_safe?(n.c, li) || !ro_keys_safe?(n.d, li)
    ro_keys_safe?(n.list, li)

  # Verify local `li` (initialized as `[]`) is ONLY used in safe dense push/length/return contexts!
  -> local_arr_push_safe?(n, li)
    return true if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return false if !local_arr_push_safe?(n[i], li)
        i += 1
      return true
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :ident && local_idx(n) == li
    if k == :var_decl
      i = 0
      while i < n.list.size
        d = n.list[i]
        if d.a.kind == :ident && local_idx(d.a) == li
          return false if d.b != nil && !local_arr_push_safe?(d.b, li)
        else
          return false if !local_arr_push_safe?(d.a, li) || !local_arr_push_safe?(d.b, li)
        i += 1
      return true
    if k == :return && n.a.is_a?(JsNode) && n.a.kind == :ident && local_idx(n.a) == li
      return true
    if k == :call && n.a.is_a?(JsNode) && n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.a.a.is_a?(JsNode) && n.a.a.kind == :ident && local_idx(n.a.a) == li && n.a.b.str == "push" && n.list.size == 1
      return local_arr_push_safe?(n.list[0], li)
    if k == :member && !n.has?(F_COMPUTED) && n.a.is_a?(JsNode) && n.a.kind == :ident && local_idx(n.a) == li && n.b.str == "length"
      return true
    return false if !local_arr_push_safe?(n.a, li) || !local_arr_push_safe?(n.b, li) || !local_arr_push_safe?(n.c, li) || !local_arr_push_safe?(n.d, li)
    local_arr_push_safe?(n.list, li)

  # ---- 2d. Detect 32-bit-truncating-only locals (all reads depend ONLY on low 32 bits!) ----
  -> detect_bit32_only
    nbase = @info.nbase_slots
    cand = Array.new(nbase, false)
    copy_dsts = Array.new(nbase, nil)
    i = 0
    while i < nbase
      if @writes[i].size > 0 && @info.types[i] == JT_ANY && @info.ta_invariants[i] == nil && @info.arr_invariants[i] == nil && @info.param_arrs[i] == nil && @info.str_locals[i] == nil && @info.local_arrs[i] == nil && @info.ro_keys_locals[i] == nil
        has_bad = false
        @writes[i].each ->(w) has_bad = true if w[0] == :param || w[0] == :undef || w[0] == :for_in
        if !has_bad
          cand[i] = true
          copy_dsts[i] = []
      i += 1
    if @info.is_osr
      b32_scan_node(@info.loop_node, false, 0, cand, copy_dsts)
    else
      b32_scan_node(@jf.node.b, false, 0, cand, copy_dsts)
      @info.inlined_fns.values.each ->(ih) b32_scan_node(ih[0].node.b, false, 0, cand, copy_dsts)
    # Propagate disqualification backwards along copy edges (`dst = src`)!
    chg = true
    while chg
      chg = false
      i = 0
      while i < nbase
        if cand[i]
          ds = copy_dsts[i]
          j = 0
          while j < ds.size
            if !cand[ds[j]]
              cand[i] = false
              chg = true
              break
            j += 1
        i += 1
    i = 0
    while i < nbase
      @info.bit32_only[i] = true if cand[i]
      ccall("w_value_free_w", copy_dsts[i]) if copy_dsts[i] != nil
      i += 1
    ccall("w_value_free_w", cand)
    ccall("w_value_free_w", copy_dsts)
    nil

  -> b32_sum_leaf_ok?(e, cand)
    return false if e == nil
    k = e.kind
    return jit_int32_lit?(e) || jit_u32_lit?(e) if k == :num
    if k == :ident
      li = local_idx(e)
      return true if li >= 0 && (cand[li] || @info.types[li] == JT_I32 || @info.types[li] == JT_U32)
      return true if e.x != nil && e.x.binding != nil && @info.global_i32s[e.x.binding] != nil
      return false
    if k == :binary
      op = e.str
      return true if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
      return b32_sum_leaf_ok?(e.a, cand) && b32_sum_leaf_ok?(e.b, cand) if op == "+" || op == "-"
      return false
    return true if k == :unary && e.str == "~"
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      return true if bli >= 0 && @info.ta_invariants[bli] != nil && @info.ta_invariants[bli] <= 6
      return true if e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && @info.global_tas[e.a.x.binding] != nil && @info.global_tas[e.a.x.binding][0] <= 6
    false

  -> b32_scan_node(n, in_bit32, sum_depth, cand, copy_dsts)
    return nil if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        b32_scan_node(n[i], false, 0, cand, copy_dsts)
        i += 1
      return nil
    return nil if !n.is_a?(JsNode)
    k = n.kind
    if k == :ident
      li = local_idx(n)
      cand[li] = false if li >= 0 && li < cand.size && !in_bit32
      return nil
    if k == :var_decl
      i = 0
      while i < n.list.size
        d = n.list[i]
        dli = local_idx(d.a)
        if d.b != nil
          if dli >= 0 && dli < cand.size && cand[dli] && d.b.kind == :ident && local_idx(d.b) >= 0 && local_idx(d.b) < cand.size
            sli = local_idx(d.b)
            copy_dsts[sli].push(dli) if cand[sli]
          else
            b32_scan_node(d.b, false, 0, cand, copy_dsts)
        i += 1
      return nil
    if k == :assign
      if n.str == "=" && n.a.kind == :ident
        dli = local_idx(n.a)
        if dli >= 0 && dli < cand.size && cand[dli] && n.b.kind == :ident && local_idx(n.b) >= 0 && local_idx(n.b) < cand.size
          sli = local_idx(n.b)
          copy_dsts[sli].push(dli) if cand[sli]
          return nil
        b32_scan_node(n.b, false, 0, cand, copy_dsts)
        return nil
      if n.str == "=" && n.a.kind == :member && n.a.has?(F_COMPUTED)
        bli = local_idx(n.a.a)
        b32_scan_node(n.a.b, false, 0, cand, copy_dsts)
        is_int_ta = bli >= 0 && @info.ta_invariants[bli] != nil && @info.ta_invariants[bli] <= 6
        b32_scan_node(n.b, is_int_ta, is_int_ta ? 1 : 0, cand, copy_dsts)
        return nil
      b32_scan_node(n.a, false, 0, cand, copy_dsts)
      b32_scan_node(n.b, false, 0, cand, copy_dsts)
      return nil
    if k == :binary
      op = n.str
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
        b32_scan_node(n.a, true, 1, cand, copy_dsts)
        b32_scan_node(n.b, true, 1, cand, copy_dsts)
        return nil
      if (op == "+" || op == "-") && in_bit32 && sum_depth > 0 && sum_depth < 8 && b32_sum_leaf_ok?(n.a, cand) && b32_sum_leaf_ok?(n.b, cand)
        b32_scan_node(n.a, true, sum_depth + 1, cand, copy_dsts)
        b32_scan_node(n.b, true, sum_depth + 1, cand, copy_dsts)
        return nil
      b32_scan_node(n.a, false, 0, cand, copy_dsts)
      b32_scan_node(n.b, false, 0, cand, copy_dsts)
      return nil
    if k == :unary && n.str == "~"
      b32_scan_node(n.a, true, 1, cand, copy_dsts)
      return nil
    b32_scan_node(n.a, false, 0, cand, copy_dsts)
    b32_scan_node(n.b, false, 0, cand, copy_dsts)
    b32_scan_node(n.c, false, 0, cand, copy_dsts)
    b32_scan_node(n.d, false, 0, cand, copy_dsts)
    b32_scan_node(n.list, false, 0, cand, copy_dsts) if n.list.is_a?(Array)
    nil

  # ---- 2e. Detect dominating range-guarded locals (`if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue; var nb = ny * W + nx;`) ----
  -> an_small_pos_const(e)
    return nil if e == nil
    if e.kind == :num && jit_int32_lit?(e)
      v = e.a.to_i
      return (v > 0 && v <= 1048576) ? v : nil
    if e.kind == :ident && e.x != nil && e.x.binding != nil && @info.global_i32s[e.x.binding] != nil
      v = @info.global_i32s[e.x.binding][0]
      return (v > 0 && v <= 1048576) ? v : nil
    nil

  -> an_collect_or_range_guards(e, lt0, ge_ub)
    return nil if e == nil
    if e.kind == :logical && e.str == "||"
      an_collect_or_range_guards(e.a, lt0, ge_ub)
      an_collect_or_range_guards(e.b, lt0, ge_ub)
      return nil
    if e.kind == :binary && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0
        if e.str == "<" && e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i == 0
          lt0[li] = true
        elsif e.str == ">="
          uv = an_small_pos_const(e.b)
          ge_ub[li] = uv if uv != nil
    nil

  -> an_scan_range_guards_stmts(stmts, cand_ub)
    return nil if !stmts.is_a?(Array)
    lt0 = {}
    ge_ub = {}
    i = 0
    while i < stmts.size
      st = stmts[i]
      if st.is_a?(JsNode)
        k = st.kind
        if k == :if && st.c == nil && st.b.is_a?(JsNode) && (st.b.kind == :continue || st.b.kind == :break || st.b.kind == :return)
          an_collect_or_range_guards(st.a, lt0, ge_ub)
        elsif k == :var_decl && st.list.is_a?(Array)
          q = 0
          while q < st.list.size
            d = st.list[q]
            dli = local_idx(d.a)
            if dli >= 0
              lt0.delete(dli)
              ge_ub.delete(dli)
              if d.b != nil && d.b.kind == :binary && d.b.str == "+" && d.b.a.kind == :binary && d.b.a.str == "*"
                ali = local_idx(d.b.a.a)
                bli = local_idx(d.b.b)
                wv = an_small_pos_const(d.b.a.b)
                if ali >= 0 && bli >= 0 && wv != nil && lt0[ali] && ge_ub[ali] != nil && lt0[bli] && ge_ub[bli] != nil && ge_ub[bli] <= wv
                  ub = ge_ub[ali] * wv
                  cand_ub[dli] = ub if ub > 0 && ub <= 1073741824
              elsif d.b != nil && d.b.kind == :binary && d.b.str == "&" && jit_int32_lit?(d.b.b)
                mv = d.b.b.a.to_i
                cand_ub[dli] = mv + 1 if mv >= 0 && mv < 1073741824
            q += 1
        elsif k == :block
          an_scan_range_guards_stmts(st.list, cand_ub)
        elsif k == :for
          an_scan_range_guards_stmts(st.d.kind == :block ? st.d.list : [st.d], cand_ub) if st.d.is_a?(JsNode)
        elsif k == :while
          an_scan_range_guards_stmts(st.b.kind == :block ? st.b.list : [st.b], cand_ub) if st.b.is_a?(JsNode)
        elsif k == :if
          an_scan_range_guards_stmts(st.b.kind == :block ? st.b.list : [st.b], cand_ub) if st.b.is_a?(JsNode)
          an_scan_range_guards_stmts(st.c.kind == :block ? st.c.list : [st.c], cand_ub) if st.c.is_a?(JsNode)
      i += 1
    nil

  -> detect_proven_bounded_i32
    return nil if !@jf.node.b.is_a?(Array)
    cand_ub = {}
    an_scan_range_guards_stmts(@jf.node.b, cand_ub)
    cand_ub.each ->(li, ub)
      ws = @writes[li]
      ok_w = (ws.size == 1 && ws[0][0] == :init) || (ws.size == 2 && ws[0][0] == :undef && ws[1][0] == :init && local_def_before_use_stmts?(@jf.node.b, li))
      if ok_w && @info.types[li] == JT_ANY
        @info.proven_bounded_i32[li] = ub
    # Also detect single-write `var n = ta.length` locals for branch-guarded TA BCE (`if (i + K < n)`).
    i = 0
    while i < @jf.nlocals
      if @writes[i].size == 1 && @writes[i][0][0] == :init
        rhs_l = @writes[i][0][1]
        if rhs_l != nil && rhs_l.kind == :member && !rhs_l.has?(F_COMPUTED) && rhs_l.b.str == "length"
          tli = local_idx(rhs_l.a)
          if tli >= 0 && @info.ta_invariants[tli] != nil
            @info.ta_len_locals[i] = tli
      i += 1
    nil

  # ---- 2. Fixed-point Numeric Type Inference ----
  -> expr_nonneg_i32?(e)
    return false if e == nil
    k = e.kind
    return jit_int32_lit?(e) && e.a.to_i >= 0 && e.a.to_i <= 1073741824 if k == :num
    if k == :ident
      if e.x != nil && e.x.binding != nil && @info.global_i32s[e.x.binding] != nil
        gv = @info.global_i32s[e.x.binding][0]
        return gv >= 0 && gv <= 1073741824
      li = local_idx(e)
      return li >= 0 && @nonneg_slots != nil && @nonneg_slots[li] == true
    if k == :member && !e.has?(F_COMPUTED) && e.b.str == "length"
      bli = local_idx(e.a)
      return bli >= 0 && (@info.ta_invariants[bli] != nil || @info.param_arrs[bli] != nil || @info.arr_invariants[bli] != nil || @info.local_arrs[bli] != nil || @info.ro_keys_locals[bli] != nil)
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.ta_invariants[bli] != nil
        tk = @info.ta_invariants[bli]
        return tk == 1 || tk == 2 || tk == 4
      if e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && @info.global_tas[e.a.x.binding] != nil
        tk = @info.global_tas[e.a.x.binding][0]
        return tk == 1 || tk == 2 || tk == 4
    if k == :binary && e.str == "&" && jit_int32_lit?(e.b) && e.b.a.to_i >= 0 && e.b.a.to_i <= 1073741824
      return true
    if k == :binary && e.str == ">>>" && jit_int32_lit?(e.b) && (e.b.a.to_i & 31) >= 1
      return true
    if k == :binary && e.str == "*"
      if jit_small_int_lit?(e.b, 1024) && e.b.a.to_i >= 0 && expr_nonneg_i32?(e.a)
        return true
      if jit_small_int_lit?(e.a, 1024) && e.a.a.to_i >= 0 && expr_nonneg_i32?(e.b)
        return true
      if e.b.kind == :ident && e.b.x != nil && e.b.x.binding != nil && @info.global_i32s[e.b.x.binding] != nil && @info.global_i32s[e.b.x.binding][0] >= 0 && @info.global_i32s[e.b.x.binding][0] <= 1024 && expr_nonneg_i32?(e.a)
        return true
    if k == :binary && e.str == "+" && expr_nonneg_i32?(e.a)
      return true if jit_small_int_lit?(e.b, 4095) && e.b.a.to_i >= 0
      return true if e.b.kind == :binary && e.b.str == "*" && jit_small_int_lit?(e.b.b, 16) && e.b.b.a.to_i >= 0 && expr_nonneg_i32?(e.b.a)
      return true if expr_nonneg_i32?(e.b) && expr_small_i32?(e.b)
    if k == :binary && e.str == "%" && expr_nonneg_i32?(e.a)
      return true if e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i > 0
      return true if e.b.kind == :ident && local_idx(e.b) >= 0 && @info.param_nonneg_ints[local_idx(e.b)] == 2
    false

  -> expr_small_mod_rhs?(b)
    return false if b == nil
    return true if b.kind == :num && jit_int32_lit?(b) && b.a.to_i > 0 && b.a.to_i <= 1048576
    b.kind == :ident && local_idx(b) >= 0 && @info.param_nonneg_ints[local_idx(b)] == 2

  -> expr_small_i32?(e)
    return false if e == nil
    sv = jit_signed_i32_val(e)
    return sv >= -1048576 && sv <= 1048576 if sv != nil
    k = e.kind
    if k == :ident
      if e.x != nil && e.x.binding != nil && @info.global_i32s[e.x.binding] != nil
        gv = @info.global_i32s[e.x.binding][0]
        return gv >= -1048576 && gv <= 1048576
      li = local_idx(e)
      if li >= 0
        return true if @info.param_nonneg_ints[li] != nil
        if @writes[li].size == 1 && @writes[li][0][0] == :init
          w0 = @writes[li][0][1]
          return true if w0 != nil && w0.kind == :binary && w0.str == "%" && expr_small_mod_rhs?(w0.b)
      return false
    if k == :binary && e.str == "&" && jit_int32_lit?(e.b) && e.b.a.to_i >= 0 && e.b.a.to_i <= 1048575
      return true
    if k == :binary && e.str == "%" && expr_small_mod_rhs?(e.b)
      return true
    if k == :cond
      return expr_small_i32?(e.b) && expr_small_i32?(e.c)
    false

  -> expr_u32_compat?(e)
    return false if e == nil
    t = expr_type(e)
    return true if t == JT_U32
    return true if e.kind == :num && jit_u32_lit?(e)
    return true if expr_nonneg_i32?(e)
    false

  -> expr_type(e)
    return JT_ANY if e == nil
    k = e.kind
    return jit_int32_lit?(e) ? JT_I32 : (jit_u32_lit?(e) ? JT_U32 : JT_F64) if k == :num
    if k == :ident
      li = local_idx(e)
      return @info.types[li] if li >= 0
      return JT_I32 if e.x != nil && e.x.binding != nil && @info.global_i32s[e.x.binding] != nil
      return JT_ANY
    if k == :cond
      return type_join(expr_type(e.b), expr_type(e.c))
    if k == :binary
      op = e.str
      ta = expr_type(e.a)
      tb = expr_type(e.b)
      both_num = (ta == JT_I32 || ta == JT_U32 || ta == JT_F64) && (tb == JT_I32 || tb == JT_U32 || tb == JT_F64)
      any_lit_num = e.a.kind == :num || e.b.kind == :num
      if op == ">>>"
        return (both_num || any_lit_num) ? JT_U32 : JT_ANY
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>"
        return (both_num || any_lit_num) ? JT_I32 : JT_ANY
      if op == "-"
        if ta == JT_I32 && (jit_small_int_lit?(e.b, 4095) || (tb == JT_I32 && expr_nonneg_i32?(e.a) && expr_nonneg_i32?(e.b)))
          return JT_I32
        return (both_num || any_lit_num) ? JT_F64 : JT_ANY
      if op == "*"
        if ta == JT_I32 && tb == JT_I32 && ((expr_small_i32?(e.a) && jit_small_int_lit?(e.b, 1024)) || (jit_small_int_lit?(e.a, 1024) && expr_small_i32?(e.b)))
          return JT_I32
        if ta == JT_I32 && e.b.kind == :num && jit_small_int_lit?(e.b, 16) && e.b.a.to_i >= 0 && expr_nonneg_i32?(e.a)
          return JT_I32
        if ta == JT_I32 && e.b.kind == :ident && e.b.x != nil && e.b.x.binding != nil && @info.global_i32s[e.b.x.binding] != nil && @info.global_i32s[e.b.x.binding][0] >= 0 && @info.global_i32s[e.b.x.binding][0] <= 1024 && expr_nonneg_i32?(e.a)
          return JT_I32
        return (both_num || any_lit_num) ? JT_F64 : JT_ANY
      if op == "/"
        return (both_num || any_lit_num) ? JT_F64 : JT_ANY
      if op == "+" || op == "%"
        if op == "%" && ta == JT_I32 && expr_nonneg_i32?(e.a)
          if e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i > 0
            return JT_I32
          if e.b.kind == :ident && local_idx(e.b) >= 0 && @info.param_nonneg_ints[local_idx(e.b)] == 2
            return JT_I32
        if op == "+" && ta == JT_I32 && (jit_small_int_lit?(e.b, 4095) || expr_small_i32?(e.b))
          return JT_I32
        if op == "+" && ta == JT_I32 && tb == JT_I32 && (expr_nonneg_i32?(e.a) && expr_nonneg_i32?(e.b)) && (e.b.kind == :binary && e.b.str == "*" && jit_small_int_lit?(e.b.b, 16))
          return JT_I32
        if op == "+" && ta == JT_I32 && tb == JT_I32 && expr_nonneg_i32?(e.a) && expr_nonneg_i32?(e.b) && e.a.kind == :binary && e.a.str == "*"
          return JT_I32
        return JT_F64 if both_num
      return JT_ANY
    if k == :unary
      if e.str == "~"
        t = expr_type(e.a)
        return (t == JT_I32 || t == JT_U32 || t == JT_F64) ? JT_I32 : JT_ANY
      if e.str == "+"
        return JT_F64
      if e.str == "-"
        return JT_I32 if jit_signed_i32_val(e) != nil
        t = expr_type(e.a)
        return JT_F64 if t == JT_I32 || t == JT_U32 || t == JT_F64
      return JT_ANY
    if k == :update
      li = local_idx(e.a)
      return li >= 0 ? @info.types[li] : JT_ANY
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if e.b.str == "length" && bli >= 0 && (@info.ta_invariants[bli] != nil || @info.param_arrs[bli] != nil || @info.arr_invariants[bli] != nil || @info.local_arrs[bli] != nil || @info.ro_keys_locals[bli] != nil || (!@info.is_osr && @info.str_locals[bli]))
        @info.needs_entry_epoch = true if @info.str_locals[bli]
        return JT_I32
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return vs != nil ? @info.types[vs] : JT_ANY
      if bli >= 0 && @info.sra_vs[bli] != nil
        vs = @info.sra_vs[bli].field_slots[e.b.str]
        return vs != nil ? JT_F64 : JT_ANY
      if bli >= 0 && @info.mono_arr_num_locals[bli]
        return JT_F64
      if bli >= 0 && @info.sra_rxs[bli] != nil && e.b.str == "index"
        return JT_I32
      if e.b.str == "length" && e.a.kind == :member && e.a.has?(F_COMPUTED) && local_idx(e.a.a) >= 0 && @info.sra_rxs[local_idx(e.a.a)] != nil && jit_int32_lit?(e.a.b) && e.a.b.a.to_i >= 0 && e.a.b.a.to_i < 15
        return JT_I32
      return JT_ANY
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.ta_invariants[bli] != nil
        tk = @info.ta_invariants[bli]
        return tk <= 5 ? JT_I32 : (tk == 6 ? JT_U32 : JT_F64)
      if e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && @info.global_tas[e.a.x.binding] != nil
        tk = @info.global_tas[e.a.x.binding][0]
        return tk <= 5 ? JT_I32 : (tk == 6 ? JT_U32 : JT_F64)
      return JT_ANY
    if k == :call && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && @info.inlined_fns[e.a.x.binding] != nil
      rets = @info.inlined_fns[e.a.x.binding][2]
      return JT_ANY if rets.size == 0
      rt0 = nil
      ri = 0
      while ri < rets.size
        rt = rets[ri] == nil ? JT_ANY : expr_type(rets[ri])
        rt0 = rt0 == nil ? rt : type_join(rt0, rt)
        ri += 1
      return rt0 == nil ? JT_ANY : rt0
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
      mn = e.a.b.str
      return JT_I32 if mn == "imul" || mn == "clz32"
      if mn == "abs" && e.list.size == 1
        a0 = e.list[0]
        return JT_U32 if expr_type(a0) == JT_I32
        return JT_U32 if a0.kind == :binary && a0.str == "-" && expr_type(a0.a) == JT_I32 && expr_type(a0.b) == JT_I32
      return JT_F64 if mn == "sqrt" || mn == "abs" || mn == "floor" || mn == "ceil" || mn == "round" || mn == "trunc" || mn == "min" || mn == "max"
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && !@info.is_osr
      # Scalar method on an SRA_VS or known-shape value struct (e.g. `oc.dot(rd)`, `n.dot(light)`, `rd.dot(n)`)!
      rli = local_idx(e.a.a)
      rsh = nil
      if rli >= 0 && @info.sra_vs[rli] != nil
        rsh = @info.sra_vs[rli].ctor_info[4]
      elsif rli >= 0 && @info.param_shapes[rli] != nil
        rsh = @info.param_shapes[rli]
      elsif e.x.is_a?(Array) && e.x.size == 2 && e.x[0].is_a?(JS:Shape)
        rsh = e.x[0]
      if rsh != nil && rsh.proto.is_a?(JS:Object)
        cand = rsh.proto.get_own(e.a.b.str)
        if cand.is_a?(JS:Function)
          mi = jit_vstruct_method_info(cand, rsh)
          return JT_F64 if mi != nil && mi[0] == :scalar
      m_prof_t = (e.x.is_a?(Array) && e.x.size == 2 && e.x[0].is_a?(JS:Shape) && e.x[1].is_a?(JS:Function)) ? e.x : jit_infer_global_arr_method(e.a, @info.global_objs)
      if m_prof_t != nil
        arg_cis = []
        ai_m = 0
        while ai_m < e.list.size
          ae_m = e.list[ai_m]
          aci_m = nil
          if ae_m.kind == :ident
            ali_m = local_idx(ae_m)
            if ali_m >= 0 && @info.sra_vs[ali_m] != nil
              aci_m = @info.sra_vs[ali_m].ctor_info
            elsif ali_m >= 0 && @info.param_shapes[ali_m] != nil
              aci_m = jit_vs_ctor_info_for_shape(@info.param_shapes[ali_m])
            elsif ae_m.x != nil && ae_m.x.binding != nil && @info.global_objs[ae_m.x.binding] != nil
              gv_m = @info.global_objs[ae_m.x.binding][1]
              aci_m = jit_vs_ctor_info_for_shape(gv_m.shape) if gv_m.is_a?(JS:Object)
          arg_cis.push(aci_m)
          ai_m += 1
        return JT_F64 if jit_vs_method_f64_info(m_prof_t[1], m_prof_t[0], arg_cis) != nil
      if e.list.size == 1 || e.list.size == 2
        sli = local_idx(e.a.a)
        if sli >= 0 && @info.str_locals[sli]
          mn = e.a.b.str
          if mn == "indexOf"
            @info.needs_entry_epoch = true
            return JT_I32
          if mn == "charCodeAt" && e.list.size == 1
            @info.needs_entry_epoch = true
            return JT_F64
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        if re != nil && re.kind == :binary && (re.str == "+" || re.str == "-" || re.str == "*")
          all_num = true
          sc.cap_slots.each ->(cs) all_num = false if @info.types[cs] != JT_I32 && @info.types[cs] != JT_F64
          e.list.each ->(ae)
            at = expr_type(ae)
            all_num = false if at != JT_I32 && at != JT_F64
          return JT_F64 if all_num
    JT_ANY

  -> type_join(a, b)
    return JT_ANY if a == JT_ANY || b == JT_ANY
    return a if a == b
    return JT_F64 if a == JT_F64 || b == JT_F64
    JT_F64

  -> all_writes_u32_compat?(ws)
    j = 0
    while j < ws.size
      wk = ws[j][0]
      wn = ws[j][1]
      return false if wk == :param || wk == :undef || wk == :for_in || wk == :update || wk == :compound
      rhs = wk == :init ? wn : wn.b
      return false if !expr_u32_compat?(rhs)
      j += 1
    true

  -> infer_types(act)
    nbase = @info.nbase_slots
    @nonneg_slots = Array.new(nbase, false)
    # Seed initial types from OSR runtime values (for variables live on entry to the loop!)
    if @info.is_osr && act != nil
      i = 0
      while i < @jf.nlocals
        if @info.types[i] == JT_ANY
          v = act.locals[i]
          if js_number?(v)
            b = jsr_i32(wvalue_bits(v) ## i64)
            if b != JSR_NOI32 && b.to_f == v && !(v == ~0.0 && (~1.0 / v) < ~0.0)
              @info.types[i] = JT_I32
              @nonneg_slots[i] = true if b >= 0 && b <= 1073741824
            else
              @info.types[i] = JT_F64
        i += 1
    else
      # Non-OSR function: start non-param locals as optimistic JT_I32, then widen to U32/F64/ANY
      i = 0
      while i < nbase
        if @info.types[i] == JT_ANY && @writes[i].size > 0
          has_param = false
          @writes[i].each ->(w) has_param = true if w[0] == :param || w[0] == :undef || w[0] == :for_in
          if !has_param
            @info.types[i] = JT_I32
            @nonneg_slots[i] = true
        elsif @info.param_ints[i]
          @nonneg_slots[i] = @info.param_nonneg_ints[i] != nil
        i += 1
    # Also seed SRA object field slots optimistically
    @info.sra_objs.values.each ->(sra)
      sra.field_slots.values.each ->(vs) @info.types[vs] = JT_I32
    @info.sra_clos.values.each ->(sc)
      sc.cap_slots.each ->(vs) @info.types[vs] = JT_I32

    # Fixed-point widening: JT_I32 -> JT_U32 -> JT_F64 -> JT_ANY (strictly monotonic)
    changed = true
    iter = 0
    while changed && iter < 10
      changed = false
      iter += 1
      # Update @nonneg_slots monotonically (true -> false)
      i = 0
      while i < nbase
        if @nonneg_slots[i]
          if @info.types[i] != JT_I32
            @nonneg_slots[i] = false
            changed = true
          else
            ws = @writes[i]
            j = 0
            while j < ws.size && @nonneg_slots[i]
              wk = ws[j][0]
              wn = ws[j][1]
              if wk == :update
                @nonneg_slots[i] = false if wn.str != "++"
              elsif wk == :compound
                if wn.str == "+=" && expr_nonneg_i32?(wn.b)
                  nil
                else
                  @nonneg_slots[i] = false
              elsif wk == :init || wk == :assign
                rhs = wk == :init ? wn : wn.b
                @nonneg_slots[i] = false if @info.proven_bounded_i32[i] == nil && !expr_nonneg_i32?(rhs)
              else
                @nonneg_slots[i] = false
              j += 1
            changed = true if !@nonneg_slots[i]
        i += 1
      i = 0
      while i < nbase
        ty = @info.types[i]
        if ty == JT_I32 || ty == JT_U32 || ty == JT_F64
          ws = @writes[i]
          is_b32 = @info.bit32_only[i] == true
          j = 0
          while j < ws.size && ty != JT_ANY
            wk = ws[j][0]
            wn = ws[j][1]
            wt = JT_ANY
            if wk == :param || wk == :undef
              wt = @info.param_ints[i] ? JT_I32 : (@info.param_nums[i] ? JT_F64 : JT_ANY)
            elsif wk == :for_in || wk == :closure
              wt = JT_ANY
            elsif wk == :update
              wt = ty == JT_U32 ? JT_F64 : ty
            elsif wk == :compound
              op = wn.str
              if op == "|=" || op == "&=" || op == "^=" || op == "<<=" || op == ">>="
                rt = expr_type(wn.b)
                wt = (rt == JT_I32 || rt == JT_U32 || rt == JT_F64) ? (ty == JT_I32 ? JT_I32 : JT_F64) : JT_ANY
              elsif op == "+=" && ty == JT_I32 && (jit_small_int_lit?(wn.b, 4095) || expr_nonneg_i32?(wn.b))
                wt = JT_I32
              elsif op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%="
                rt = expr_type(wn.b)
                wt = (rt == JT_I32 || rt == JT_U32 || rt == JT_F64) ? JT_F64 : JT_ANY
              else
                wt = JT_ANY
            else
              rhs = wk == :init ? wn : wn.b
              wt = @info.proven_bounded_i32[i] != nil ? JT_I32 : expr_type(rhs)
            nt = ty
            if ty == wt
              nt = ty
            elsif ty == JT_ANY || wt == JT_ANY
              nt = JT_ANY
            elsif ty == JT_F64 || wt == JT_F64
              if is_b32 && (ty == JT_I32 || ty == JT_U32) && (wk == :init || wk == :assign)
                rhs_b = wk == :init ? wn : wn.b
                if rhs_b != nil && rhs_b.kind == :binary && (rhs_b.str == "+" || rhs_b.str == "-")
                  ta_b = expr_type(rhs_b.a)
                  tb_b = expr_type(rhs_b.b)
                  if (ta_b == JT_I32 || ta_b == JT_U32) && (tb_b == JT_I32 || tb_b == JT_U32)
                    nt = JT_I32
                  else
                    nt = JT_F64
                else
                  nt = JT_F64
              else
                nt = JT_F64
            elsif (ty == JT_I32 && wt == JT_U32) || (ty == JT_U32 && wt == JT_I32)
              if is_b32
                nt = JT_I32
              elsif all_writes_u32_compat?(ws)
                nt = JT_U32
              else
                nt = JT_F64
            else
              nt = JT_F64
            if nt != ty
              @info.types[i] = nt
              ty = nt
              changed = true
            j += 1
        elsif ty == JT_SRA_OBJ
          # Infer virtual field types from object literal writes
          sra = @info.sra_objs[i]
          ws = @writes[i]
          j = 0
          while j < ws.size
            rhs = ws[j][0] == :init ? ws[j][1] : ws[j][1].b
            q = 0
            while q < rhs.list.size
              p = rhs.list[q]
              vs = sra.field_slots[p.a.str]
              cur_t = @info.types[vs]
              rt = expr_type(p.b)
              # `i + 1` where i is i32: keep as i32 when small constant offset!
              if rt == JT_F64 && p.b.kind == :binary && (p.b.str == "+" || p.b.str == "-") && expr_type(p.b.a) == JT_I32 && jit_small_int_lit?(p.b.b, 65536)
                rt = JT_I32
              nt = cur_t == JT_ANY || rt == JT_ANY ? JT_ANY : (cur_t == JT_F64 || rt == JT_F64 ? JT_F64 : JT_I32)
              if nt != cur_t
                @info.types[vs] = nt
                changed = true
              q += 1
            j += 1
          # Also propagate types from explicit field writes `o.prop = rhs`!
          @sra_field_writes[i].each ->(fk, fws)
            vs = sra.field_slots[fk]
            if vs != nil
              fi = 0
              while fi < fws.size
                cur_t = @info.types[vs]
                rt = expr_type(fws[fi])
                nt = cur_t == JT_ANY || rt == JT_ANY ? JT_ANY : (cur_t == JT_F64 || rt == JT_F64 ? JT_F64 : JT_I32)
                if nt != cur_t
                  @info.types[vs] = nt
                  changed = true
                fi += 1
        elsif ty == JT_SRA_CLOS
          sc = @info.sra_clos[i]
          rhs = @writes[i][0][0] == :init ? @writes[i][0][1] : @writes[i][0][1].b
          q = 0
          while q < sc.cap_slots.size
            vs = sc.cap_slots[q]
            cur_t = @info.types[vs]
            rt = expr_type(rhs.list[q])
            nt = cur_t == JT_ANY || rt == JT_ANY ? JT_ANY : (cur_t == JT_F64 || rt == JT_F64 ? JT_F64 : JT_I32)
            if nt != cur_t
              @info.types[vs] = nt
              changed = true
            q += 1
        elsif ty == JT_SRA_VS
          nil
        i += 1
    nil

  # Strip synthetic `:undef` from hoisted `var x = init` inside loops/blocks when `x` is NEVER
  # observed before its own unconditional `var x = init` in the same block (100% sound definite-assignment!).
  -> prune_dead_cond_undefs
    return nil if !@jf.node.b.is_a?(Array)
    i = 0
    while i < @info.nbase_slots
      ws = @writes[i]
      has_undef = false
      has_param = false
      has_real = false
      j = 0
      while j < ws.size
        wk = ws[j][0]
        has_undef = true if wk == :undef
        has_param = true if wk == :param
        has_real = true if wk != :undef && wk != :param
        j += 1
      if has_undef && !has_param && has_real
        ok_def = local_def_before_use_stmts?(@jf.node.b, i)
        if ok_def && @info.inlined_fns.size > 0
          @info.inlined_fns.values.each ->(ih) ok_def = false if !local_def_before_use_stmts?(ih[0].node.b, i)
        if ok_def
          nw = []
          ws.each ->(w) nw.push(w) if w[0] != :undef
          @writes[i] = nw
      i += 1
    nil

  -> an_node_refs_local?(n, li)
    return false if !n.is_a?(JsNode)
    return local_idx(n) == li if n.kind == :ident
    return true if an_node_refs_local?(n.a, li) || an_node_refs_local?(n.b, li) || an_node_refs_local?(n.c, li) || an_node_refs_local?(n.d, li)
    if n.list.is_a?(Array)
      k = 0
      while k < n.list.size
        return true if an_node_refs_local?(n.list[k], li)
        k += 1
    false

  -> local_def_before_use_stmt?(st, li)
    return true if !st.is_a?(JsNode)
    return local_def_before_use_stmts?(st.list, li) if st.kind == :block
    local_def_before_use_stmts?([st], li)

  -> local_def_before_use_stmts?(stmts, li)
    return true if stmts == nil
    defined = false
    i = 0
    while i < stmts.size
      st = stmts[i]
      if !defined && st.is_a?(JsNode)
        k = st.kind
        if k == :var_decl && st.list.is_a?(Array)
          q = 0
          while q < st.list.size
            d = st.list[q]
            if !defined
              return false if d.b != nil && an_node_refs_local?(d.b, li)
              defined = true if local_idx(d.a) == li && d.b != nil
            q += 1
        elsif k == :block
          return false if !local_def_before_use_stmts?(st.list, li)
        elsif k == :for
          if st.a != nil && st.a.kind == :var_decl && st.a.list.is_a?(Array)
            fdef = false
            q = 0
            while q < st.a.list.size
              d = st.a.list[q]
              if !fdef
                return false if d.b != nil && an_node_refs_local?(d.b, li)
                fdef = true if local_idx(d.a) == li && d.b != nil
              q += 1
            if fdef
              defined = true
            else
              return false if an_node_refs_local?(st.b, li) || an_node_refs_local?(st.c, li)
              return false if !local_def_before_use_stmt?(st.d, li)
          else
            return false if an_node_refs_local?(st.a, li) || an_node_refs_local?(st.b, li) || an_node_refs_local?(st.c, li)
            return false if !local_def_before_use_stmt?(st.d, li)
        elsif k == :while
          return false if an_node_refs_local?(st.a, li)
          return false if !local_def_before_use_stmt?(st.b, li)
        elsif k == :do_while
          return false if an_node_refs_local?(st.b, li)
          return false if !local_def_before_use_stmt?(st.a, li)
        elsif k == :if
          return false if an_node_refs_local?(st.a, li)
          return false if !local_def_before_use_stmt?(st.b, li) || !local_def_before_use_stmt?(st.c, li)
        else
          return false if an_node_refs_local?(st, li)
      i += 1
    true

  # Detect functions operating purely on a single read-only dense Array param of homogeneous numeric objects
  # (e.g. `step(bodies, dt)` in n-body): allows prologue-verified `JT_F64` inference for `a.x - b.x`, etc.!
  -> detect_mono_arr_num_locals
    return nil if @info.uses_calls || @info.uses_env || @jf.uses_this || @info.param_arrs.size != 1 || !@jf.node.b.is_a?(Array)
    arr_li = @info.param_arrs.keys[0]
    pi = 0
    while pi < @jf.params.size
      pli = @jf.params[pi].lidx
      if pli >= 0 && pli != arr_li
        return nil if !@info.param_nums[pli] && !@info.param_ints[pli]
      pi += 1
    elem_lis = {}
    i = 0
    while i < @jf.nlocals
      if i != arr_li && @writes[i].size >= 1
        all_from_arr = true
        j = 0
        while j < @writes[i].size && all_from_arr
          wk = @writes[i][j][0]
          wn = @writes[i][j][1]
          rhs = wk == :init ? wn : (wk == :assign ? wn.b : nil)
          if rhs == nil || rhs.kind != :member || !rhs.has?(F_COMPUTED) || local_idx(rhs.a) != arr_li
            all_from_arr = false
          j += 1
        elem_lis[i] = true if all_from_arr
      i += 1
    return nil if elem_lis.size == 0
    # Verify AST purity and collect one unique warm non-dict JS:Shape across all member accesses on elem_lis!
    st_res = [0, true]   # [mono_sh, ok]
    an_scan_mono_arr(@jf.node.b, elem_lis, st_res)
    return nil if !st_res[1] || st_res[0] == 0
    sh_obj = wvalue_from_bits(st_res[0])
    return nil if !sh_obj.is_a?(JS:Shape) || sh_obj.dict || sh_obj.count <= 0 || sh_obj.count > sh_obj.inline + 4
    @info.mono_arr_num_sh = st_res[0]
    elem_lis.keys.each ->(eli) @info.mono_arr_num_locals[eli] = true
    nil

  -> an_scan_mono_arr(n, elem_lis, st)
    return nil if n == nil || !st[1]
    if n.is_a?(Array)
      n.each ->(x) an_scan_mono_arr(x, elem_lis, st)
      return nil
    return nil if !n.is_a?(JsNode)
    k = n.kind
    if k == :object || k == :array || k == :new || k == :fn_decl || k == :fn_expr || k == :arrow || k == :bigint || k == :string || k == :template
      st[1] = false
      return nil
    if k == :ident && n.x != nil && n.x.binding != nil && n.x.binding.global? && n.str != "Math"
      st[1] = false
      return nil
    if k == :assign && n.a.is_a?(JsNode) && n.a.kind == :member
      if n.a.has?(F_COMPUTED) || !(n.str == "=" || n.str == "+=" || n.str == "-=" || n.str == "*=" || n.str == "/=")
        st[1] = false
        return nil
      eli = local_idx(n.a.a)
      if eli < 0 || !elem_lis[eli]
        st[1] = false
        return nil
      ic = n.a.x
      if ic == nil || ic[0] == 0 || ic[2] != 0 || ic[1] == 0
        st[1] = false
        return nil
      if st[0] == 0
        st[0] = ic[0]
      elsif st[0] != ic[0]
        st[1] = false
        return nil
    elsif k == :member && !n.has?(F_COMPUTED)
      eli = local_idx(n.a)
      if eli >= 0 && elem_lis[eli]
        ic = n.x
        if ic == nil || ic[0] == 0 || ic[2] != 0 || ic[1] == 0
          st[1] = false
          return nil
        if st[0] == 0
          st[0] = ic[0]
        elsif st[0] != ic[0]
          st[1] = false
          return nil
    an_scan_mono_arr(n.a, elem_lis, st)
    an_scan_mono_arr(n.b, elem_lis, st)
    an_scan_mono_arr(n.c, elem_lis, st)
    an_scan_mono_arr(n.d, elem_lis, st)
    an_scan_mono_arr(n.list, elem_lis, st) if n.list.is_a?(Array)
    nil

  # ---- 2b. Detect read-only array/numeric/int parameters in functions with loops (e.g. step(bodies, dt), run(n)) ----
  -> detect_fn_param_hints(warm_args = nil)
    arr_uses = {}
    num_uses = {}
    int_uses = {}
    bad_num = {}
    bad_arr = {}
    bad_int = {}
    mod_rhs = {}
    small_arith = {}
    scan_param_hints(@jf.node.b, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    i = 0
    while i < @jf.params.size
      pb = @jf.params[i]
      li = binding_slot(pb)
      if li >= 0 && @writes[li].size == 1 && @writes[li][0][0] == :param && @info.param_tas[li] == nil
        warm_is_i32 = false
        warm_bi = -1
        if warm_args.is_a?(Array) && i < warm_args.size
          wv = warm_args[i]
          if js_number?(wv)
            bi = jsr_i32(wvalue_bits(wv) ## i64)
            if bi != JSR_NOI32 && bi.to_f == wv && !(wv == ~0.0 && (~1.0 / wv) < ~0.0)
              warm_is_i32 = true
              warm_bi = bi
        if arr_uses[li] && !bad_arr[li] && !node_mutates_arr?(@jf.node.b, li)
          @info.param_arrs[li] = true
        elsif (int_uses[li] || (warm_is_i32 && num_uses[li])) && !bad_int[li] && !arr_uses[li]
          @info.param_ints[li] = true
          @info.types[li] = JT_I32
          if warm_is_i32 && warm_bi >= 0 && warm_bi <= 1048576
            if mod_rhs[li] && warm_bi > 0
              @info.param_nonneg_ints[li] = 2
            elsif small_arith[li]
              @info.param_nonneg_ints[li] = 1
        elsif num_uses[li] && !bad_num[li] && !arr_uses[li]
          @info.param_nums[li] = true
          @info.types[li] = JT_F64
      i += 1
    nil

  -> scan_param_hints(n, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    return nil if n == nil
    if n.is_a?(Array)
      n.each ->(x) scan_param_hints(x, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
      return nil
    return nil if !n.is_a?(JsNode)
    k = n.kind
    if k == :member
      li = local_idx(n.a)
      if li >= 0
        if n.has?(F_COMPUTED) || n.b.str == "length"
          arr_uses[li] = true
          bad_num[li] = true
          bad_int[li] = true
        else
          bad_arr[li] = true
          bad_num[li] = true
          bad_int[li] = true
    elsif k == :assign && n.a.is_a?(JsNode) && n.a.kind == :member
      # Mutating array elements via `arr[i] = ...` or `.length = ...` disqualifies read-only hoist
      li = local_idx(n.a.a)
      bad_arr[li] = true if li >= 0
    elsif k == :call && n.a.is_a?(JsNode) && n.a.kind == :member
      # Method call on param (`arr.push(...)` etc.) disqualifies read-only hoist!
      li = local_idx(n.a.a)
      bad_arr[li] = true if li >= 0
      bad_num[li] = true if li >= 0
      bad_int[li] = true if li >= 0
    elsif k == :binary && (n.str == "<" || n.str == "<=" || n.str == ">" || n.str == ">=")
      la = local_idx(n.a)
      lb = local_idx(n.b)
      int_uses[la] = true if la >= 0
      int_uses[lb] = true if lb >= 0
    elsif k == :binary && n.str == "%"
      lb = local_idx(n.b)
      mod_rhs[lb] = true if lb >= 0
    elsif k == :binary && n.str == "+"
      la = local_idx(n.a)
      lb = local_idx(n.b)
      small_arith[la] = true if la >= 0
      small_arith[lb] = true if lb >= 0
    elsif k == :binary && (n.str == "*" || n.str == "/" || n.str == "-")
      la = local_idx(n.a)
      lb = local_idx(n.b)
      num_uses[la] = true if la >= 0
      num_uses[lb] = true if lb >= 0
      if n.str == "/"
        bad_int[la] = true if la >= 0
        bad_int[lb] = true if lb >= 0
      elsif n.str == "*"
        # Float literal multiply disqualifies int32 hint (e.g. `dt * 0.5`)
        if (n.a.kind == :num && !jit_int32_lit?(n.a)) || (n.b.kind == :num && !jit_int32_lit?(n.b))
          bad_int[la] = true if la >= 0
          bad_int[lb] = true if lb >= 0
        elsif jit_small_int_lit?(n.a, 32) || jit_small_int_lit?(n.b, 32)
          small_arith[la] = true if la >= 0
          small_arith[lb] = true if lb >= 0
    scan_param_hints(n.a, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    scan_param_hints(n.b, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    scan_param_hints(n.c, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    scan_param_hints(n.d, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith)
    scan_param_hints(n.list, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int, mod_rhs, small_arith) if n.list.is_a?(Array)
    nil

  # Check if `n` mutates `arr_li` directly (`arr[i] = ...`, `arr.prop = ...`, `arr = ...`) or makes any non-pure call
  # that could alias & mutate/reallocate `arr_li`.
  -> node_mutates_arr?(n, arr_li)
    return false if n == nil
    if n.is_a?(Array)
      i = 0
      while i < n.size
        return true if node_mutates_arr?(n[i], arr_li)
        i += 1
      return false
    return false if !n.is_a?(JsNode)
    k = n.kind
    if k == :assign
      return true if local_idx(n.a) == arr_li
      if n.a.is_a?(JsNode) && n.a.kind == :member && local_idx(n.a.a) == arr_li
        return true
    elsif k == :update
      if n.a.is_a?(JsNode) && n.a.kind == :member && local_idx(n.a.a) == arr_li
        return true
    elsif k == :new
      return true
    elsif k == :call
      c = n.a
      is_pure = false
      if c.is_a?(JsNode) && c.kind == :member && !c.has?(F_COMPUTED)
        is_pure = true if c.a.is_a?(JsNode) && c.a.kind == :ident && c.a.str == "Math"
        if (c.b.str == "indexOf" || c.b.str == "charCodeAt") && n.list.size == 1
          sli = local_idx(c.a)
          is_pure = true if sli >= 0 && @info.str_locals[sli]
        is_pure = true if !is_pure && jit_poly_call_pure?(n)
      return true if !is_pure
    return true if node_mutates_arr?(n.a, arr_li) || node_mutates_arr?(n.b, arr_li) || node_mutates_arr?(n.c, arr_li) || node_mutates_arr?(n.d, arr_li)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if node_mutates_arr?(n.list[i], arr_li)
        i += 1
    false

  # ---- 3. Detect loop-invariant TypedArrays, Arrays, and Objects ----
  -> detect_invariants(act)
    i = 0
    while i < @jf.nlocals
      if @info.written_in_loop[i] != true && @info.types[i] == JT_ANY
        v = act.locals[i]
        if v.is_a?(JS:TypedArray)
          n = js_ta_length(v)
          if n >= 0 && (v.kind <= 8 || v.kind == 11)
            @info.ta_invariants[i] = v.kind
        elsif js_array?(v) && (js_array_flags(v) & 15) == JS_AF_ARRAY && !node_mutates_arr?(@info.loop_node, i)
          @info.arr_invariants[i] = true
        elsif v.is_a?(JS:Object) && !v.shape.dict
          @info.obj_invariants[i] = wvalue_bits(v.shape) ## i64
      i += 1
    nil

  # ---- 4. Self-Recursive Fast Entry Detection (e.g. fib(n)) ----
  -> detect_fast_rec
    return nil if @jf.params.size != 1 || @jf.nlocals != 1
    b = @jf.binding
    return nil if b == nil || b.writes > 1
    ret_e = jit_inline_return_expr(@jf)
    return nil if ret_e == nil
    # Verify body only uses param, num literals, < <= > >= == === + -, cond, and self-calls
    return nil if !fast_rec_expr?(ret_e, b)
    @info.fast_rec = true
    @info.fast_rec_kind = 1   # i32 fast entry (with overflow fallback to generic/f64!)
    @info.fast_rec_cell = wk_cell(b) if b.global?
    nil

  -> fast_rec_expr?(e, self_b)
    return false if e == nil
    k = e.kind
    return jit_int32_lit?(e) if k == :num
    return local_idx(e) == 0 if k == :ident
    if k == :binary
      op = e.str
      return (op == "+" || op == "-" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "==") && fast_rec_expr?(e.a, self_b) && fast_rec_expr?(e.b, self_b)
    if k == :cond
      return fast_rec_expr?(e.a, self_b) && fast_rec_expr?(e.b, self_b) && fast_rec_expr?(e.c, self_b)
    if k == :call
      return e.a.kind == :ident && e.a.x != nil && e.a.x.binding == self_b && e.list.size == 1 && fast_rec_expr?(e.list[0], self_b)
    false

  # ---- 5. Linear-Scan / Priority Register Allocation (with Disjoint-Loop Coalescing!) ----
  # Assign top 7 hot GPR slots (JT_I32 / JT_ANY) -> R_X22..R_X28
  # Assign top 8 hot FPR slots (JT_F64) -> R_D8..R_D15
  # Remaining slots live on stack frame at [sp + spill_off].
  -> scan_stmt_use_mask(n, bit, masks)
    return nil if !n.is_a?(JsNode)
    if n.kind == :ident
      li = local_idx(n)
      masks[li] = masks[li] | bit if li >= 0
      return nil
    if n.kind == :var_decl && n.list.is_a?(Array)
      n.list.each ->(d)
        if d.is_a?(JsNode)
          li = local_idx(d.a)
          masks[li] = masks[li] | bit if li >= 0
          scan_stmt_use_mask(d.b, bit, masks)
      return nil
    scan_stmt_use_mask(n.a, bit, masks)
    scan_stmt_use_mask(n.b, bit, masks)
    scan_stmt_use_mask(n.c, bit, masks)
    scan_stmt_use_mask(n.d, bit, masks)
    if n.list.is_a?(Array)
      n.list.each ->(x) scan_stmt_use_mask(x, bit, masks)
    nil

  -> stmt_def_before_use?(s, target_li)
    return false if !s.is_a?(JsNode)
    if s.kind == :for
      # `for (var k = init; ...)` defines k before any use if init doesn't read k
      if s.a != nil && s.a.kind == :var_decl && s.a.list.size >= 1 && local_idx(s.a.list[0].a) == target_li && s.a.list[0].b != nil
        m = Array.new(@jf.nlocals, 0)
        scan_stmt_use_mask(s.a.list[0].b, 1, m)
        return m[target_li] == 0
      # `for (...) { var c = expr; ... }` defines c before any use in body
      if s.d != nil && s.d.kind == :block && s.d.list != nil && s.d.list.size >= 1
        st0 = s.d.list[0]
        if st0.kind == :var_decl && st0.list.size >= 1 && local_idx(st0.list[0].a) == target_li && st0.list[0].b != nil
          m = Array.new(@jf.nlocals, 0)
          scan_stmt_use_mask(s.a, 1, m)
          scan_stmt_use_mask(s.b, 1, m)
          scan_stmt_use_mask(s.c, 1, m)
          scan_stmt_use_mask(st0.list[0].b, 1, m)
          return m[target_li] == 0
    false

  -> alloc_regs
    # Compile-time constant i32 fields of scalar-replaced object literals are folded directly into immediates;
    # keep their backing slots on stack so they never waste callee-saved GPRs needed by loops!
    @info.sra_objs.values.each ->(sra)
      sra.const_i32.keys.each ->(ck)
        cvs = sra.field_slots[ck]
        @info.hot_counts[cvs] = -1 if cvs != nil
    gpr_cands = []
    fpr_cands = []
    i = 0
    while i < @info.total_slots
      ty = @info.types[i]
      if ty == JT_F64
        fpr_cands.push(i)
      elsif ty == JT_I32 || ty == JT_U32 || ty == JT_ANY
        # Hoisted TypedArrays / read-only hoisted Arrays live in their hoisted (ptr, len) regs,
        # so don't waste a precious callee-saved GPR on their boxed WValue!
        if @info.ta_invariants[i] != nil || @info.arr_invariants[i] != nil || @info.param_arrs[i] != nil
          @info.hot_counts[i] = -1
        gpr_cands.push(i)
      i += 1
    # Compute disjoint top-level statement live masks for non-OSR functions with >= 2 statements!
    stmt_masks = nil
    def_first = nil
    if !@info.is_osr && @jf.node.b.is_a?(Array) && @jf.node.b.size >= 2 && @jf.node.b.size <= 30
      stmts = @jf.node.b
      stmt_masks = Array.new(@info.total_slots, 0)
      def_first = Array.new(@info.total_slots, false)
      si = 0
      while si < stmts.size
        scan_stmt_use_mask(stmts[si], 1 << si, stmt_masks)
        si += 1
      # Parameters are live across the whole function
      pi = 0
      while pi < @jf.params.size
        pb = @jf.params[pi]
        stmt_masks[pb.lidx] = -1 if pb.lidx >= 0
        pi += 1
      li = 0
      while li < @jf.nlocals
        m = stmt_masks[li]
        if m > 0 && (m & (m - 1)) == 0
          # Used in exactly 1 top-level statement — find which one and check def-before-use!
          si = 0
          while si < stmts.size
            if m == (1 << si)
              def_first[li] = stmt_def_before_use?(stmts[si], li)
              break
            si += 1
        li += 1
    # Sort descending by hotness
    gpr_cands = gpr_cands.sort_by(->(s) 0 - @info.hot_counts[s])
    fpr_cands = fpr_cands.sort_by(->(s) 0 - @info.hot_counts[s])
    off = 192   # space below sp+192 reserved for saved x29..x30, x19..x28, d8..d15 (160 bytes) + 32 bytes scratch/temp
    # Reserve up to 2 callee-saved GPRs for hot hoisted TypedArray/Array base pointers so
    # byte/element loops (`compress`, `decompress`, `astar`) never reload base pointers from stack!
    n_hoist_ptrs = @info.ta_invariants.size + @info.arr_invariants.size + @info.param_arrs.size + @info.global_tas.size
    max_loc_gprs = 7
    if @info.has_loop && n_hoist_ptrs >= 3 && gpr_cands.size > 6
      max_loc_gprs = 6
    reg_masks = Array.new(7, 0)   # combined top-level stmt bitmask per physical GPR R_X22..R_X28
    next_gpr = 0
    g = 0
    while g < gpr_cands.size
      sl = gpr_cands[g]
      assigned = -1
      if @info.hot_counts[sl] > 0
        # Try coalescing with an existing physical GPR whose top-level statements are 100% disjoint!
        if stmt_masks != nil && sl < @jf.nlocals && def_first[sl] && stmt_masks[sl] > 0
          m = stmt_masks[sl]
          rg = 0
          while rg < next_gpr
            if reg_masks[rg] > 0 && (reg_masks[rg] & m) == 0
              assigned = rg
              reg_masks[rg] = reg_masks[rg] | m
              break
            rg += 1
        # In functions with loops AND calls, reserve >= 2 GPRs after top 4 JT_ANY locals for loop-hoisted arrays/shapes/inlined frames!
        eff_max_gprs = (@info.has_loop && @info.uses_calls && @info.types[sl] == JT_ANY && max_loc_gprs > 4) ? 4 : max_loc_gprs
        if assigned < 0 && next_gpr < eff_max_gprs
          assigned = next_gpr
          next_gpr += 1
          if stmt_masks != nil && sl < @jf.nlocals && def_first[sl] && stmt_masks[sl] > 0
            reg_masks[assigned] = stmt_masks[sl]
          else
            reg_masks[assigned] = -1   # conservative: interferes with everything
      if assigned >= 0
        @info.reg_gpr[sl] = R_X22 + assigned
      else
        @info.spill_off[sl] = off
        off += 8
      g += 1
    f = 0
    while f < fpr_cands.size
      sl = fpr_cands[f]
      if f < 8 && @info.hot_counts[sl] > 0
        @info.reg_fpr[sl] = R_D8 + f
      else
        @info.spill_off[sl] = off
        off += 8
      f += 1
    # Reserve 64 bytes for expression temp spills + OSR/arg save slots
    off += 128
    # Align frame size to 16 bytes
    @info.frame_size = ((off + 15) / 16) * 16
    nil
