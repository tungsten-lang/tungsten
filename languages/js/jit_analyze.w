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

# Describes a scalar-replaced local object literal: { k0: ..., k1: ... }
+ JitSraObj
  rw :lidx, :keys, :field_slots, :const_i32   # keys: [String], field_slots: key -> virtual local idx
  -> new(@lidx, @keys)
    @field_slots = {}
    @const_i32 = {}

# Describes a scalar-replaced local closure: var f = factory(arg0, ...)
+ JitSraClos
  rw :lidx, :factory_binding, :factory_fn, :inner_jf, :cap_slots, :arg_count
  -> new(@lidx, @factory_binding, @factory_fn, @inner_jf, @cap_slots, @arg_count)
    nil

# Result of analyzing a function or OSR loop for ARM64 JIT compilation.
+ JitInfo
  rw :jf, :is_osr, :loop_node, :nlocals, :total_slots, :types, :sra_objs, :sra_clos, :sra_rxs
  rw :written_in_loop, :fast_rec, :fast_rec_cell, :fast_rec_kind
  rw :reg_gpr, :reg_fpr, :spill_off, :frame_size, :uses_calls, :uses_env, :uses_this
  rw :has_loop, :hot_counts, :ta_invariants, :arr_invariants, :obj_invariants
  rw :param_arrs, :param_nums, :param_ints, :local_tas, :str_locals, :needs_entry_epoch

  -> new(@jf, @is_osr, @loop_node)
    @nlocals = @jf.nlocals
    @total_slots = @nlocals
    @types = Array.new(@nlocals, JT_ANY)
    @sra_objs = {}       # lidx -> JitSraObj
    @sra_clos = {}       # lidx -> JitSraClos
    @sra_rxs = {}        # lidx -> i64[32] caps buffer
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
    @param_arrs = {}      # lidx -> true (read-only array param hoisted in fn prologue!)
    @param_nums = {}      # lidx -> true (read-only numeric param unboxed in fn prologue!)
    @param_ints = {}      # lidx -> true (read-only integer loop-bound param unboxed as i32 in fn prologue!)
    @local_tas = {}       # lidx -> ta_kind (local `var a = new Uint8Array(...)` assigned once!)
    @str_locals = {}      # lidx -> true (local assigned ONLY string literals!)
    @needs_entry_epoch = false

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
    ccall("w_value_free_w", @written_in_loop) if @written_in_loop != nil
    ccall("w_value_free_w", @reg_gpr) if @reg_gpr != nil
    ccall("w_value_free_w", @reg_fpr) if @reg_fpr != nil
    ccall("w_value_free_w", @spill_off) if @spill_off != nil
    ccall("w_value_free_w", @ta_invariants) if @ta_invariants != nil
    ccall("w_value_free_w", @arr_invariants) if @arr_invariants != nil
    ccall("w_value_free_w", @obj_invariants) if @obj_invariants != nil
    ccall("w_value_free_w", @param_arrs) if @param_arrs != nil
    ccall("w_value_free_w", @param_nums) if @param_nums != nil
    ccall("w_value_free_w", @param_ints) if @param_ints != nil
    ccall("w_value_free_w", @local_tas) if @local_tas != nil
    ccall("w_value_free_w", @str_locals) if @str_locals != nil
    ccall("w_value_free_w", self)
    nil

# ---- AST helpers ----

-> jit_int32_lit?(e)
  return false if e == nil || e.kind != :num
  v = e.a
  return false if v != v || v < ~-2147483648.0 || v > ~2147483647.0
  # Reject -0.0
  return false if v == ~0.0 && (~1.0 / v) < ~0.0
  iv = v.to_i
  iv.to_f == v

-> jit_small_int_lit?(e, max_abs)
  return false if !jit_int32_lit?(e)
  iv = e.a.to_i
  iv >= (0 - max_abs) && iv <= max_abs

# Can a plain object literal be scalar-replaced? Returns key list or nil.
-> jit_plain_obj_keys(e)
  return nil if e == nil || e.kind != :object || e.list.size == 0 || e.list.size > 8
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
  if k == :num || k == :string || k == :true || k == :false || k == :null || k == :this || k == :empty || k == :debugger || k == :regex
    return true
  if k == :break || k == :continue
    return n.str == nil
  if k == :expr_stmt || k == :return || k == :throw
    return jit_node_supported?(n.a)
  if k == :unary || k == :update
    return false if k == :unary && n.str == "delete"
    return false if k == :update && n.a.kind == :member
    return false if k == :update && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && n.a.x.binding.decl_const
    return jit_node_supported?(n.a)
  if k == :binary || k == :logical || k == :assign
    return false if k == :assign && (n.a.kind == :object_pattern || n.a.kind == :array_pattern || n.str == "&&=" || n.str == "||=" || n.str == "??=" || n.str == "**=")
    return false if k == :assign && n.a.kind == :ident && n.a.x != nil && n.a.x.binding != nil && n.a.x.binding.decl_const
    return false if k == :binary && (n.a.kind == :private_name || n.str == "**")
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
  return false if jf.scope.has_env? || (jf.body_scope != nil && jf.body_scope != jf.scope)
  return false if jf.nt_binding != nil || jf.fo_binding != nil || jf.self_binding != nil
  return false if jf.arrow && jf.uses_this
  return false if jf.nlocals > 64 || jf.params.size > 4
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
  -1

+ JitAnalyzer
  rw :info, :jf, :writes, :non_member_reads, :non_call_reads, :member_keys, :sra_field_writes, :depth, :cond_depth

  -> new(@jf, is_osr, loop_node)
    @info = JS:JitInfo.new(@jf, is_osr, loop_node)
    @writes = Array.new(@jf.nlocals, nil)
    @non_member_reads = Array.new(@jf.nlocals, false)
    @non_call_reads = Array.new(@jf.nlocals, false)
    @member_keys = Array.new(@jf.nlocals, nil)
    @sra_field_writes = Array.new(@jf.nlocals, nil)
    @depth = 0
    @cond_depth = 0
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
    ccall("w_value_free_w", self)
    nil

  -> local_idx(e)
    return -1 if e == nil || e.kind != :ident || e.x == nil
    b = e.x.binding
    return -1 if b == nil || b.global? || b.slot >= 0 || b.scope.func != @jf
    b.lidx

  -> analyze(act = nil)
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
      # Mark parameter slots as written by :param
      i = 0
      while i < @jf.params.size
        pb = @jf.params[i]
        @writes[pb.lidx].push([:param, nil]) if pb.lidx >= 0
        i += 1
      n = @jf.node
      if @jf.arrow && n.has?(F_EXPR_BODY)
        scan_expr(n.b, false, false)
      else
        scan_stmts(n.b)
    # 1. Detect scalar-replaceable object literals & closure factories
    detect_sra(act)
    # 2. Detect loop-invariant TypedArrays, Arrays, and Objects BEFORE type inference so TA loads infer f64/i32!
    detect_invariants(act) if act != nil
    # 2b. For non-OSR functions with loops: detect read-only array & numeric params to hoist/unbox in prologue!
    detect_fn_param_hints() if !@info.is_osr && @info.has_loop
    # 3. Fixed-point type inference (i32 / f64 / any)
    infer_types(act)
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
      elsif e.x != nil && e.x.binding != nil && !e.x.binding.global? && (e.x.binding.slot >= 0 || e.x.binding.scope.func != @jf)
        @info.uses_env = true
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
        scan_expr(e.a, false, false)
        scan_expr(e.b, false, false)
    elsif k == :call
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
      inner_jf = e.x
      if inner_jf.is_a?(JaFunc)
        if inner_jf.single != nil
          sb = inner_jf.single
          if !sb.global? && (sb.slot >= 0 || sb.scope.func != @jf)
            @info.uses_env = true
        elsif inner_jf.free.size > 0
          @info.uses_env = true
    nil

  # ---- 1. Scalar Replacement of Aggregates (non-escaping objects & closures) ----
  -> detect_sra(act)
    i = 0
    while i < @jf.nlocals
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
              if rk == nil
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
          elsif rhs_ta != nil && rhs_ta.kind == :string
            @info.str_locals[i] = true
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
    nil

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

  # ---- 2. Fixed-point Numeric Type Inference ----
  -> expr_type(e)
    return JT_ANY if e == nil
    k = e.kind
    return jit_int32_lit?(e) ? JT_I32 : JT_F64 if k == :num
    if k == :ident
      li = local_idx(e)
      return li >= 0 ? @info.types[li] : JT_ANY
    if k == :binary
      op = e.str
      return JT_F64 if op == ">>>"
      ta = expr_type(e.a)
      tb = expr_type(e.b)
      both_num = (ta == JT_I32 || ta == JT_F64) && (tb == JT_I32 || tb == JT_F64)
      any_lit_num = e.a.kind == :num || e.b.kind == :num
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>"
        return (both_num || any_lit_num) ? JT_I32 : JT_ANY
      if op == "-" || op == "*" || op == "/"
        return (both_num || any_lit_num) ? JT_F64 : JT_ANY
      if op == "+" || op == "%"
        if op == "+" && ta == JT_I32 && jit_small_int_lit?(e.b, 4095) && e.b.a.to_i >= 0
          return JT_I32
        return JT_F64 if both_num
      return JT_ANY
    if k == :unary
      if e.str == "~"
        t = expr_type(e.a)
        return (t == JT_I32 || t == JT_F64) ? JT_I32 : JT_ANY
      if e.str == "+"
        return JT_F64
      if e.str == "-"
        t = expr_type(e.a)
        return JT_F64 if t == JT_I32 || t == JT_F64
      return JT_ANY
    if k == :update
      li = local_idx(e.a)
      return li >= 0 ? @info.types[li] : JT_ANY
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return vs != nil ? @info.types[vs] : JT_ANY
      if bli >= 0 && @info.sra_rxs[bli] != nil && e.b.str == "index"
        return JT_I32
      if e.b.str == "length" && e.a.kind == :member && e.a.has?(F_COMPUTED) && local_idx(e.a.a) >= 0 && @info.sra_rxs[local_idx(e.a.a)] != nil && jit_int32_lit?(e.a.b) && e.a.b.a.to_i >= 0 && e.a.b.a.to_i < 15
        return JT_I32
      return JT_ANY
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.ta_invariants[bli] != nil
        tk = @info.ta_invariants[bli]
        return tk <= 5 ? JT_I32 : JT_F64
      return JT_ANY
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
      mn = e.a.b.str
      return JT_I32 if mn == "imul" || mn == "clz32"
      return JT_F64 if mn == "sqrt" || mn == "abs" || mn == "floor" || mn == "ceil" || mn == "round" || mn == "trunc" || mn == "min" || mn == "max"
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.list.size == 1 && !@info.is_osr
      sli = local_idx(e.a.a)
      if sli >= 0 && @info.str_locals[sli]
        mn = e.a.b.str
        if mn == "indexOf"
          @info.needs_entry_epoch = true
          return JT_I32
        if mn == "charCodeAt"
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
    return JT_F64 if a == JT_F64 || b == JT_F64
    JT_I32

  -> infer_types(act)
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
            else
              @info.types[i] = JT_F64
        i += 1
    else
      # Non-OSR function: start non-param locals as optimistic JT_I32, then widen to F64/ANY
      i = 0
      while i < @jf.nlocals
        if @info.types[i] == JT_ANY && @writes[i].size > 0
          has_param = false
          @writes[i].each ->(w) has_param = true if w[0] == :param || w[0] == :undef
          @info.types[i] = JT_I32 if !has_param
        i += 1
    # Also seed SRA object field slots optimistically
    @info.sra_objs.values.each ->(sra)
      sra.field_slots.values.each ->(vs) @info.types[vs] = JT_I32
    @info.sra_clos.values.each ->(sc)
      sc.cap_slots.each ->(vs) @info.types[vs] = JT_I32

    # Fixed-point widening: JT_I32 -> JT_F64 -> JT_ANY (strictly monotonic via type_join)
    changed = true
    iter = 0
    while changed && iter < 8
      changed = false
      iter += 1
      i = 0
      while i < @jf.nlocals
        ty = @info.types[i]
        if ty == JT_I32 || ty == JT_F64
          ws = @writes[i]
          j = 0
          while j < ws.size && ty != JT_ANY
            wk = ws[j][0]
            wn = ws[j][1]
            wt = JT_ANY
            if wk == :param || wk == :undef
              wt = @info.param_ints[i] ? JT_I32 : (@info.param_nums[i] ? JT_F64 : JT_ANY)
            elsif wk == :update
              # x++ / x-- stays i32 if currently i32 (runtime guard / overflow check handles huge loops)
              wt = ty
            elsif wk == :compound
              op = wn.str
              if op == "|=" || op == "&=" || op == "^=" || op == "<<=" || op == ">>="
                rt = expr_type(wn.b)
                wt = (rt == JT_I32 || rt == JT_F64) ? (ty == JT_I32 ? JT_I32 : JT_F64) : JT_ANY
              elsif op == "+=" || op == "-=" || op == "*=" || op == "/=" || op == "%="
                rt = expr_type(wn.b)
                wt = (rt == JT_I32 || rt == JT_F64) ? JT_F64 : JT_ANY
              else
                wt = JT_ANY
            else
              rhs = wk == :init ? wn : wn.b
              wt = expr_type(rhs)
            nt = type_join(ty, wt)
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
        i += 1
    nil

  # ---- 2b. Detect read-only array/numeric/int parameters in functions with loops (e.g. step(bodies, dt), run(n)) ----
  -> detect_fn_param_hints
    arr_uses = {}
    num_uses = {}
    int_uses = {}
    bad_num = {}
    bad_arr = {}
    bad_int = {}
    scan_param_hints(@jf.node.b, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    i = 0
    while i < @jf.params.size
      pb = @jf.params[i]
      li = pb.lidx
      if li >= 0 && @writes[li].size == 1 && @writes[li][0][0] == :param
        if arr_uses[li] && !bad_arr[li] && !node_mutates_arr?(@jf.node.b, li)
          @info.param_arrs[li] = true
        elsif int_uses[li] && !bad_int[li] && !arr_uses[li]
          @info.param_ints[li] = true
          @info.types[li] = JT_I32
        elsif num_uses[li] && !bad_num[li] && !arr_uses[li]
          @info.param_nums[li] = true
          @info.types[li] = JT_F64
      i += 1
    nil

  -> scan_param_hints(n, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    return nil if n == nil
    if n.is_a?(Array)
      n.each ->(x) scan_param_hints(x, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
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
    scan_param_hints(n.a, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    scan_param_hints(n.b, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    scan_param_hints(n.c, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    scan_param_hints(n.d, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int)
    scan_param_hints(n.list, arr_uses, num_uses, int_uses, bad_num, bad_arr, bad_int) if n.list.is_a?(Array)
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
          if n >= 0 && v.kind <= 8
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
    gpr_cands = []
    fpr_cands = []
    i = 0
    while i < @info.total_slots
      ty = @info.types[i]
      if ty == JT_F64
        fpr_cands.push(i)
      elsif ty == JT_I32 || ty == JT_ANY
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
        if assigned < 0 && next_gpr < 7
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
