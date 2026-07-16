# Lowering / definitions — everything that defines new named things:
# methods, functions, classes, traits, ivars, cvars, plus go and yield.
#
# Includes the method-body analysis suite (fn_body_*, has_yield_*,
# returns_only_int?, all_params_i64?, body_is_param_passthrough?,
# method_lowering_analysis, method_runtime_arity, memo-table tracking),
# the actual lowerers (lower_method_def, lower_fn_def, lower_class_def,
# lower_class_method, lower_static_method_boxed_wrapper, lower_accessors,
# lower_cvar / lower_ivar / lower_cvar_set / lower_ivar_set_expr,
# lower_on_guard), and lower_go / lower_yield.
#
# Depends on pass_registry.w, analysis.w, blocks.w, calls.w,
# control_flow.w. This file deliberately has no `use` directives —
# see pass_registry.w.


-> has_yield_node(body)
  if body == nil
    return false
  i = 0
  while i < body.size()
    if has_yield_in_node(body[i])
      return true
    i += 1
  false

-> explicit_block_param_name(params)
  if params == nil
    return nil
  i = 0
  while i < params.size()
    if params[i].block_param == true
      return param_runtime_name(params[i])
    i += 1
  nil

-> param_runtime_name(param)
  if param.block_param == true && param.name == "&"
    return "__yield_block"
  param.name

-> method_yield_block_name(params, body)
  explicit_name = explicit_block_param_name(params)
  if explicit_name != nil
    return explicit_name
  if !has_yield_node(body)
    return nil
  "__block"

-> method_lowering_analysis(node)
  cached = ast_get(node, :lowering_analysis)
  if cached != nil
    return cached

  yield_block_name = method_yield_block_name(node.params, node.body)
  needs_block_return = has_nonlocal_block_return(node.body)
  cached = {
    yield_block_name: yield_block_name,
    needs_block_return: needs_block_return
  }
  node.lowering_analysis = cached
  cached

-> method_runtime_arity(node)
  arity = node.params.size() + 1
  if method_lowering_analysis(node)[:yield_block_name] == "__block"
    arity += 1
  arity

-> mark_memo_table_used(mod, call_key)
  if mod[:used_memo_tables][call_key] == true
    return nil
  mod[:used_memo_tables][call_key] = true
  mod[:used_memo_table_order].push(call_key)
  nil

-> prepend_memo_table_initializers(main_fn, mod)
  memo_keys = mod[:used_memo_table_order]
  if memo_keys == nil || memo_keys.size() == 0
    return nil

  init_instructions = []
  mi = 0
  while mi < memo_keys.size()
    global_name = mod[:fn_memo_tables][memo_keys[mi]]
    if global_name != nil
      init_temp = next_temp(main_fn)
      init_instructions.push({op: :memo_init, temp: init_temp})
      init_instructions.push({op: :store_memo_ptr, value: init_temp, global: global_name})
    mi += 1

  if init_instructions.size() == 0
    return nil

  entry = main_fn[:blocks][0]
  old_instructions = entry[:instructions]
  new_instructions = []
  i = 0
  while i < init_instructions.size()
    new_instructions.push(init_instructions[i])
    i += 1
  i = 0
  while i < old_instructions.size()
    new_instructions.push(old_instructions[i])
    i += 1
  entry[:instructions] = new_instructions
  nil

-> has_yield_in_node(node)
  if node == nil
    return false
  t = ast_kind(node)
  case t
  when :yield
    return true
  when :if
    if has_yield_node(node.then_body)
      return true
    if node.elsif_clauses != nil
      i = 0
      while i < node.elsif_clauses.size()
        if has_yield_node(node.elsif_clauses[i][1])
          return true
        i += 1
    if has_yield_node(node.else_body)
      return true
    return false
  when :while
    return has_yield_node(node.body)
  when :with, :parallel_with
    return has_yield_node(node.body)
  when :assign, :compound_assign
    # `acc = &(acc, item)` (Enumerable#reduce) — the yield is the RHS of an
    # assignment. Without this, reduce analyzes as taking no block and drops its
    # block param while still yielding to %__block (undefined IR).
    if has_yield_in_node(node.value)
      return true
    return has_yield_in_node(node.target)
  when :passthrough
    # `$size -> &(self[i]) : self` (SmallArray/BigArray#each) parses as a
    # passthrough whose expression is `$size.each { &(self[i]) }` — the yield
    # is buried in the call's block. Without recursing here (and through :call
    # / :block below), a specialized each whose `&` param flag didn't survive
    # the clone analyzes as taking no block, so its signature drops the block
    # param while its body still yields to %__block (undefined IR). Only a real
    # :yield node returns true, so plain blocks stay false.
    if has_yield_in_node(node.expression)
      return true
    return has_yield_in_node(node.value)
  when :block
    return has_yield_node(node.body)
  when :call
    if node.block != nil && has_yield_in_node(node.block)
      return true
    if node.args != nil
      ai = 0
      while ai < node.args.size()
        if has_yield_in_node(node.args[ai])
          return true
        ai += 1
    return false
  when :case
    if node.whens != nil
      i = 0
      while i < node.whens.size()
        if has_yield_node(node.whens[i].body)
          return true
        i += 1
    return has_yield_node(node.else_body)
  when :case_value
    if node.arms != nil
      i = 0
      while i < node.arms.size()
        if has_yield_node(node.arms[i].body)
          return true
        i += 1
    return has_yield_node(node.else_body)
  when :begin
    if has_yield_node(node.body)
      return true
    return has_yield_node(node.rescue_body)
  else
    false

# Enrich a base type map (params) with int-shaped LOCAL types via a conservative
# forward scan. body_returns_only_int? only sees param types in child_var_types, so
# a fn that returns a COMPUTED local (`hi = mulhi(a,b); hi`) infers nil at the tail
# and is wrongly denied the raw ABI — boxing/truncating its u64 params. int_shaped_node?
# is conservative (clearly-int exprs only), so this only marks definitely-int locals.
-> enrich_int_locals(body, base)
  m = {}
  ks = base.keys()
  ki = 0
  while ki < ks.size()
    m[ks[ki]] = base[ks[ki]]
    ki += 1
  scan_int_local_assigns(body, m)
  m

-> scan_int_local_assigns(nodes, m)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    n = nodes[i]
    if n != nil && is_ast_node?(n)
      t = ast_kind(n)
      if t == :assign && n.target != nil && ast_kind(n.target) == :var
        if int_shaped_node?(n.value, m) && m[n.target.name] == nil
          m[n.target.name] = :i64
      if t == :if
        scan_int_local_assigns(n.then_body, m)
        scan_int_local_assigns(n.else_body, m)
        if n.elsif_clauses != nil
          j = 0
          while j < n.elsif_clauses.size()
            scan_int_local_assigns(n.elsif_clauses[j][1], m)
            j += 1
      if t == :while
        scan_int_local_assigns(n.body, m)
    i += 1

# Type-shape predicate for return values. Accepts any int-compatible
# inference; rejects :bool, :string, :nil, :float, etc. so the raw-
# callable optimization doesn't forward a tagged WValue as a raw int.
-> int_compatible_return_type?(t)
  if t == nil
    return false
  t in (:int :i64 :u64 :i32 :u32 :i16 :u16 :i8 :u8 :i4 :u4 :raw_int :raw_i64 :raw_u64)

-> body_returns_only_int?(body, var_types, fn_return_types)
  if body == nil
    return false
  i = 0
  while i < body.size()
    if !node_returns_only_int?(body[i], var_types, fn_return_types, i == body.size() - 1)
      return false
    i += 1
  true

-> node_returns_only_int?(node, var_types, fn_return_types, is_tail)
  if node == nil
    return true
  if !is_ast_node?(node)
    return true
  nt = ast_kind(node)
  if nt == :return
    if node.value == nil
      # bare `return` returns nil — not int.
      return false
    rt = infer_type(node.value, var_types, fn_return_types, lowering_infer_maps)
    return int_compatible_return_type?(rt)
  if is_tail && nt != :if && nt != :case && nt != :case_value && nt != :while
    rt = infer_type(node, var_types, fn_return_types, lowering_infer_maps)
    if rt == nil
      # nil inference is permissive for non-tail flow, but a tail
      # expression with unknown type is too risky to mark raw-callable.
      return false
    return int_compatible_return_type?(rt)
  # Recurse into branching nodes — every reachable :return inside must
  # also be int. Don't descend into nested defs / blocks (they're
  # separate fns).
  if nt in (:def :method_def :fn_def :class_def :block)
    return true
  children = ast_children(node)
  ci = 0
  while ci < children.size()
    if !node_returns_only_int?(children[ci], var_types, fn_return_types, false)
      return false
    ci += 1
  true

-> all_params_i64?(params, child_var_types)
  if params == nil || params.size() == 0
    return false
  i = 0
  while i < params.size()
    p = params[i]
    if is_ast_node?(p) && (p.block_param == true || p.default != nil)
      return false
    pname = param_runtime_name(p)
    pt = child_var_types[pname]
    # u64 shares i64's machine ABI (same 64-bit register, raw value); the
    # raw_i64_sig path forces a raw return (raw_return_type=:i64) so there is
    # no w_u64 rebox to skip. Including u64 here keeps u64 params/args/returns
    # native end-to-end instead of nanboxing them (which truncated values >2^48).
    if pt != :i64 && pt != :u64
      return false
    i += 1
  true

# Typed-array raw ABI: i64/u64 scalars pass raw, typed-array params pass their
# boxed handle unchanged (an array WValue is already the i64 the callee
# subscripts through — nothing to unbox). Eligibility mirrors
# all_params_i64? plus typed-array params and requires at least one array
# (all-scalar is the plain raw ABI). All-array signatures still benefit on the
# return boundary: an integer result remains raw instead of taking a w_int /
# w_to_i64 round trip at every statically resolved call. Profiling
# motivation (flip-graph walkers, 2026-07-02): boxed calls to
# (arrays..., scalars...) fns spent ~45% of runtime in w_int/w_to_i64
# round-trips, w_add on boxed returns, and bigint alloc/free churn for
# scalar args >2^47.
-> mixed_raw_params?(params, child_var_types)
  if params == nil || params.size() == 0
    return false
  has_scalar = false
  has_array = false
  i = 0
  while i < params.size()
    p = params[i]
    if is_ast_node?(p) && (p.block_param == true || p.default != nil)
      return false
    pname = param_runtime_name(p)
    pt = child_var_types[pname]
    if pt == :i64 || pt == :u64
      has_scalar = true
    elsif is_typed_array_type?(pt)
      has_array = true
    else
      return false
    i += 1
  has_array

-> raw_param_kinds(params, child_var_types)
  kinds = []
  i = 0
  while i < params.size()
    pname = param_runtime_name(params[i])
    pt = child_var_types[pname]
    if is_typed_array_type?(pt)
      kinds.push(:arr)
    else
      kinds.push(:scalar)
    i += 1
  kinds

# Phase: any machine-int param. Extends raw-i64 ABI to sub-i64 ints
# (i8/u8/i16/u16/i32/u32) and i64/u64/bool. The fn body for these typed
# annotations is already a passthrough (`ret %x`), so the elision is
# entirely on the caller side: pass raw without nanbox, take return as
# raw. LLVM register width is i64 either way; the difference is the
# nanbox+nanunbox pair the call-site no longer needs.
-> all_params_machine_int?(params, child_var_types)
  if params == nil || params.size() == 0
    return false
  i = 0
  while i < params.size()
    p = params[i]
    if is_ast_node?(p) && (p.block_param == true || p.default != nil)
      return false
    pname = param_runtime_name(p)
    pt = child_var_types[pname]
    # Restricted to types whose typed identity-fn body actually lowers
    # to `ret %x` at the LLVM level (passthrough). bool, u64, and the
    # floats route through unbox→rebox helpers (w_u64, nanbox_float,
    # etc.) inside the fn, so callers can't safely skip the boxing on
    # the call boundary. Their typed-overload path stays boxed and
    # remains correct via the existing chain.
    if pt != :i4 && pt != :u4 && pt != :i8 && pt != :u8 && pt != :i16 && pt != :u16 && pt != :i32 && pt != :u32 && pt != :i64
      return false
    i += 1
  true

-> param_name_in_list?(name, params)
  i = 0
  while i < params.size()
    if name == param_runtime_name(params[i])
      return true
    i += 1
  false

-> body_is_param_passthrough?(body, params)
  if body == nil || body.size() != 1
    return false
  node = body[0]
  if node == nil || !is_ast_node?(node)
    return false
  if ast_kind(node) == :var
    return param_name_in_list?(node.name, params)
  if ast_kind(node) == :return
    value = node.value
    if value != nil && is_ast_node?(value) && ast_kind(value) == :var
      return param_name_in_list?(value.name, params)
  false

# Populate the type map that controls a definition's parameter lowering and
# raw-call ABI decision.  This runs both in the module-wide ABI prepass and
# again while lowering the body; keeping one implementation is essential
# because callers and callees must agree on whether each i64 register contains
# a raw machine integer or a boxed WValue.
-> populate_definition_var_types(node, child_var_types)
  if node.type_hints != nil
    hint_names = node.type_hints.keys()
    i = 0
    while i < hint_names.size()
      ht = node.type_hints[hint_names[i]]
      hts = ht.to_s()
      htl = hts.size()
      if htl >= 3 && hts.slice(htl - 2, 2) == "\[]"
        child_var_types[hint_names[i]] = typed_array_etype_to_sym(hts.slice(0, htl - 2))
      else
        child_var_types[hint_names[i]] = normalize_type_symbol(ht)
      i += 1

  if node.param_types != nil
    pt = node.param_types
    pti = 0
    while pti < pt.size() && pti < node.params.size()
      pname = param_runtime_name(node.params[pti])
      pts = pt[pti].to_s()
      ptsl = pts.size()
      if ptsl >= 3 && pts.slice(ptsl - 2, 2) == "\[]"
        child_var_types[pname] = typed_array_etype_to_sym(pts.slice(0, ptsl - 2))
      else
        child_var_types[pname] = normalize_type_symbol(pt[pti])
      pti += 1

  fname = node.name
  if fname != nil && (fname.starts_with?("hot_") || fname.starts_with?("bench_"))
    promotions = analyze_int_promotions(node.body, node.params, child_var_types)
    promote_names = promotions.keys()
    pj = 0
    while pj < promote_names.size()
      child_var_types[promote_names[pj]] = :i64
      pj += 1
  child_var_types

# Return [raw-i64 ABI, narrow-int passthrough ABI] for one definition.  The
# module prepass and body lowerer both call this exact predicate so source order
# cannot make a forward call use the boxed ABI while its eventual callee uses
# the raw ABI.
-> definition_raw_abi_flags(node, top_level, fn_return_types, rt, child_var_types)
  rt_int_ok = (rt == nil) || int_compatible_return_type?(rt)
  body_int_ok = body_returns_only_int?(node.body, enrich_int_locals(node.body, child_var_types), fn_return_types)
  raw_i64_sig = top_level && rt_int_ok && body_int_ok && (all_params_i64?(node.params, child_var_types) || mixed_raw_params?(node.params, child_var_types))
  raw_int_sig = !raw_i64_sig && top_level && rt_int_ok && body_int_ok && all_params_machine_int?(node.params, child_var_types) && body_is_param_passthrough?(node.body, node.params)
  [raw_i64_sig, raw_int_sig]

# Decide every top-level definition's ABI before lowering any body.  Previously
# raw_callable_fns was populated only as definitions were encountered, so a
# typed forward call was emitted boxed even when the later callee was lowered
# with a raw-i64 signature.  Both ABIs are LLVM i64, making the mismatch link
# cleanly and then corrupt values at runtime.
-> preregister_top_level_raw_abis(mod, expressions)
  i = 0
  while i < expressions.size()
    node = expressions[i]
    if ast_kind(node) in (:method_def :fn_def)
      child_var_types = {}
      populate_definition_var_types(node, child_var_types)
      rt = nil
      if node.return_type != nil
        rt = normalize_type_symbol(node.return_type)
      else
        rt = infer_fn_return_type(node, lowering_infer_maps)
      flags = definition_raw_abi_flags(node, true, mod[:fn_return_types], rt, child_var_types)
      if flags[0] || flags[1]
        call_key = method_call_key_for_def(node)
        mod[:raw_callable_fns][call_key] = function_name_for_def(node)
        if flags[0]
          mod[:raw_fn_param_kinds][call_key] = raw_param_kinds(node.params, child_var_types)
    i += 1
  nil

-> lower_method_def(ctx, node)
  mod = ctx[:mod]
  name = node.name
  if ctx[:verbose]
    <- "."
  params = node.params
  body = node.body
  analysis = method_lowering_analysis(node)

  # Build param name list
  param_names = []
  i = 0
  while i < params.size()
    param_names.push(param_runtime_name(params[i]))
    i += 1

  # `yield` consumes the explicit &block parameter if present; otherwise add
  # the hidden block slot used by calls with trailing blocks.
  yield_block_name = analysis[:yield_block_name]
  if yield_block_name == "__block"
    param_names.push("__block")

  # Mangled function name. Typed overloads include their signature in the
  # symbol name so multiple definitions with the same source name can coexist.
  fn_name = function_name_for_def(node)
  call_key = method_call_key_for_def(node)

  # Register as known call with param count for nil-padding at call sites
  mod[:known_calls][call_key] = fn_name
  mod[:known_fn_param_counts][call_key] = param_names.size()
  if node.param_types != nil
    mod[:known_fn_overloads][name] = true

  # Infer return type
  rt = nil
  if node.return_type != nil
    rt = normalize_type_symbol(node.return_type)
  else
    rt = infer_fn_return_type(node, lowering_infer_maps)
  if rt != nil
    mod[:fn_return_types][call_key] = normalize_type_symbol(rt)

  # Build new function
  new_fn = build_function(fn_name, param_names, "i64", false, [])
  new_fn[:source_kind] = ast_kind(node)
  new_fn[:source_method] = name
  new_fn[:source_class] = ctx[:class_name]
  new_fn[:source_path] = ctx[:source_path]
  new_fn[:source_line] = node.line
  mod[:functions].push(new_fn)

  needs_block_return = analysis[:needs_block_return]
  if needs_block_return
    new_fn[:result_slot] = "%__block_return_result"
    new_fn[:exit_label] = next_label(new_fn, "blockret.exit")

  # Create child context
  child_var_types = {}
  child_ctx = {
    mod: mod,
    func: new_fn,
    var_types: child_var_types,
    class_name: ctx[:class_name],
    source_path: ctx[:source_path],
    method_name: name,
    bindings: {},
    unboxed_vars: {},
    verbose: ctx[:verbose],
    is_class_method: ctx[:is_class_method],
    is_block: false,
    block_return_frame: nil,
    yield_block_name: yield_block_name
  }
  block_return_buf = nil
  if needs_block_return
    block_return_buf = next_temp(new_fn)
    emit_instruction(new_fn, {op: :alloca_i64, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :call_direct_ptr, temp: block_return_buf, name: "w_block_return_push", args: []})
    block_return_bits = next_temp(new_fn)
    emit_instruction(new_fn, {op: :ptr_to_i64, temp: block_return_bits, value: block_return_buf})
    child_ctx[:block_return_frame] = block_return_bits
    sj = next_temp(new_fn)
    emit_instruction(new_fn, {op: :setjmp, temp: sj, buf: block_return_buf})
    cmp = next_temp(new_fn)
    emit_instruction(new_fn, {op: :icmp_eq_i32, temp: cmp, lhs: sj, rhs: "0"})
    body_label = next_label(new_fn, "blockret.body")
    catch_label = next_label(new_fn, "blockret.catch")
    emit_instruction(new_fn, {op: :cond_br, cond: cmp, then_label: body_label, else_label: catch_label})
    start_block(new_fn, body_label)
    block_return_slot = ensure_var_slot(new_fn, "__block_return_frame")
    emit_instruction(new_fn, {op: :store_i64, value: block_return_bits, ptr: block_return_slot})

  # Apply declared parameter/local types through the same helper used by the
  # module-wide raw-ABI prepass.
  populate_definition_var_types(node, child_var_types)

  child_ctx[:raw_int_candidates] = raw_int_candidate_map(body, child_var_types)

  # Detect raw-i64 ABI: when every param is ## i64:-annotated and there's
  # no block param or default, the fn takes raw int64_t directly. Callers
  # in lower_call see this and skip the nanbox+nanunbox round-trip on
  # both sides. The fn signature stays `i64 @name(i64, i64, ...)` at the
  # LLVM level (raw ints and WValues are both i64); the difference is
  # purely in the box/unbox elision at the call boundary. Top-level
  # functions only — class methods receive `__self` as a WValue.
  # Raw-callable opt-in requires the body's value flow to be int-shaped
  # too — predicate fns (`name?` returning true/false), string-builders,
  # nil-returners, etc. produce WValues that the raw ABI would mistakenly
  # forward as raw integers. Gate on the inferred / annotated return
  # type matching a machine int. Bodies with mixed returns (early
  # `return false if ...` plus a tail expression) likewise return
  # non-int through some paths — body_returns_only_int? walks every
  # :return node (and the final tail expression) and rejects the fn if
  # any path produces a non-int value.
  # rt comes from infer_fn_return_type which runs WITHOUT param types, so an
  # identity / param-dependent return (`f(x) = x`, `f(x) = x + 1` with a u64/i64
  # param) infers nil and would wrongly disqualify the raw ABI — boxing the param
  # and TRUNCATING values >2^48. When rt is nil, rely on body_int_ok below, which
  # is param-type-aware (walks returns via child_var_types). A non-nil rt must
  # still be machine-int.
  raw_abi_flags = definition_raw_abi_flags(node, ctx[:class_name] == nil, mod[:fn_return_types], rt, child_var_types)
  raw_i64_sig = raw_abi_flags[0]
  raw_int_sig = raw_abi_flags[1]
  if raw_i64_sig
    new_fn[:raw_i64_signature] = true
    # ensure_return_value reads raw_return_type — explicit `return X`
    # statements need to produce raw too, not just the implicit-return
    # path at function tail.
    new_fn[:raw_return_type] = :i64
    mod[:raw_callable_fns][call_key] = fn_name
    # Callers consult the per-param kinds: :scalar args pass raw machine
    # ints, :arr args pass the typed-array handle unchanged.
    mod[:raw_fn_param_kinds][call_key] = raw_param_kinds(params, child_var_types)
  if raw_int_sig
    # Sub-i64 / unsigned int variants. Fn body for these annotated
    # identity fns only. These lower to a passthrough at the LLVM level
    # (`ret %x`), so callers may skip the nanbox they would otherwise
    # emit for raw typed-array elements. Non-passthrough bodies still
    # need boxed arguments until full sub-i64 raw function bodies exist.
    new_fn[:raw_return_type] = normalize_type_symbol(rt)
    mod[:raw_callable_fns][call_key] = fn_name

  # Unbox ## i64 parameters once at function entry — skipped when this
  # fn has the raw-i64 ABI (callers pass already-raw values). The
  # binding still maps the pname to the raw register, so downstream
  # arithmetic reads it as a raw int.
  i = 0
  while i < params.size()
    pname = param_runtime_name(params[i])
    pt = child_var_types[pname]
    if is_raw_int_storage_type(pt)
      if raw_i64_sig || raw_int_sig
        child_ctx[:bindings][pname] = "%" + pname
      elsif pt in (:i64 :u64)
        # Checked unbox: a boxed caller passes values >2^47 as heap bigint
        # boxes, which the plain shl/ashr nanunbox would pass through as
        # pointer bits — comparisons inside the body then silently fail
        # (49-bit flip-graph masks: dup-scan missed, walk crippled). The
        # runtime w_to_i64/w_to_u64 handles inline and bigint boxes both.
        raw = next_temp(new_fn)
        emit_instruction(new_fn, {op: :call_direct_i64, temp: raw, name: machine_unbox_fn(pt), args: ["%" + pname], arg_types: ["i64"]})
        child_ctx[:bindings][pname] = raw
      else
        raw = nanunbox_int_emit(new_fn, "%" + pname)
        child_ctx[:bindings][pname] = raw
    i += 1

  # Emit default parameter guards: if param == nil then param = default
  # Uses select to pick between param and default value
  i = 0
  while i < params.size()
    p = params[i]
    if p.default != nil
      pname = param_runtime_name(p)
      param_reg = "%" + pname
      # Check if param is nil (W_NIL = 0)
      is_nil = next_temp(new_fn)
      emit_instruction(new_fn, {op: :icmp_i64, temp: is_nil, pred: "eq", lhs: param_reg, rhs: w_nil.to_s()})
      # Lower the default expression
      default_val = lower_expression(child_ctx, p.default)
      default_reg = ensure_i64_value(new_fn, default_val)
      # Select: if nil then default else param
      result = next_temp(new_fn)
      emit_instruction(new_fn, {op: :select_i64, temp: result, cond: is_nil, then_val: default_reg, else_val: param_reg})
      # Bind the result so future references to pname use the defaulted value
      child_ctx[:bindings][pname] = result
    i += 1

  # Pre-scan body for parameter reassignment: create var_slots and initialize
  # with parameter values so conditional reassignment doesn't leave slots uninitialized
  param_names_list = []
  pi = 0
  while pi < params.size()
    param_names_list.push(param_runtime_name(params[pi]))
    pi += 1
  reassigned = find_reassigned_params(body, param_names_list)
  pi = 0
  while pi < reassigned.size()
    pname = reassigned[pi]
    slot_type = "i64"
    if is_raw_int_storage_type(child_var_types[pname])
      slot_type = machine_slot_type(child_var_types[pname])
    ptr = ensure_var_slot(new_fn, pname, slot_type)
    # Use binding if one exists (e.g. from default-param override), otherwise use %param
    if child_ctx[:bindings][pname] != nil
      if is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:raw_i64, child_ctx[:bindings][pname]), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: child_ctx[:bindings][pname], ptr: ptr})
    else
      if is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:i64, "%" + pname), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: "%" + pname, ptr: ptr})
    pi += 1

  captured_params = find_captured_params_in_body(body, param_names_list)
  pi = 0
  while pi < captured_params.size()
    pname = captured_params[pi]
    if new_fn[:var_slots][pname] == nil
      slot_type = "i64"
      if is_raw_int_storage_type(child_var_types[pname])
        slot_type = machine_slot_type(child_var_types[pname])
      ptr = ensure_var_slot(new_fn, pname, slot_type)
      if child_ctx[:bindings][pname] != nil
        if is_raw_int_storage_type(child_var_types[pname])
          raw = ensure_raw_machine_int(new_fn, typed_value(:raw_i64, child_ctx[:bindings][pname]), child_var_types[pname], child_var_types[pname])
          emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
        else
          emit_instruction(new_fn, {op: :store_i64, value: child_ctx[:bindings][pname], ptr: ptr})
      elsif is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:i64, "%" + pname), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: "%" + pname, ptr: ptr})
    pi += 1

  # Lower body with implicit return for last expression
  if body != nil && body.size() > 0
    prev_stmts = child_ctx[:enclosing_stmts]
    prev_idx = child_ctx[:enclosing_stmt_idx]
    child_ctx[:enclosing_stmts] = body
    # Lower all statements except the last
    i = 0
    while i < body.size() - 1
      if block_terminated(new_fn)
        break
      child_ctx[:enclosing_stmt_idx] = i
      lower_statement(child_ctx, body[i])
      i += 1

    # Lower the last expression as implicit return
    if !block_terminated(new_fn)
      child_ctx[:enclosing_stmt_idx] = body.size() - 1
      last = body[body.size() - 1]
      last_t = ast_kind(last)
      # Some nodes are statements that don't produce values
      # Note: :if with else/elsif is an expression (returns a value), but a bare
      # if with no else/elsif is statement-only and yields nil.
      is_if_stmt = last_t == :if && (last.else_body == nil || last.else_body.size() == 0) && (last.elsif_clauses == nil || last.elsif_clauses.size() == 0)
      if last_t in (:puts :print :while :method_def :fn_def :begin :raise) || is_if_stmt
        lower_statement(child_ctx, last)
      elsif last_t == :return
        lower_statement(child_ctx, last)
      else
        # Expression — lower and return its value
        result = lower_expression(child_ctx, last)
        # Raw-i64 ABI: return as raw int (no nanbox). Callers receive raw
        # and use the value directly. For non-raw fns, ensure_i64_value
        # boxes when the result was raw, matches WValue ABI.
        if raw_i64_sig || raw_int_sig
          result_type = infer_type(last, child_var_types, mod[:fn_return_types], lowering_infer_maps)
          ret_raw_type = new_fn[:raw_return_type]
          if ret_raw_type == nil
            ret_raw_type = :i64
          result_reg = ensure_raw_machine_int(new_fn, result, ret_raw_type, result_type)
        else
          result_reg = ensure_i64_value(new_fn, result)
        if new_fn[:exit_label] != nil && new_fn[:result_slot] != nil
          emit_recycles_above_depth(new_fn, 0)
          emit_instruction(new_fn, {op: :store_i64, value: result_reg, ptr: new_fn[:result_slot]})
          emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})
        else
          emit_instruction(new_fn, {op: :ret_i64, value: result_reg})
    child_ctx[:enclosing_stmts] = prev_stmts
    child_ctx[:enclosing_stmt_idx] = prev_idx

  if needs_block_return
    if !block_terminated(new_fn)
      emit_recycles_above_depth(new_fn, 0)
      emit_instruction(new_fn, {op: :store_i64, value: w_nil.to_s(), ptr: new_fn[:result_slot]})
      emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})

    start_block(new_fn, catch_label)
    caught = next_temp(new_fn)
    emit_instruction(new_fn, {op: :call_direct_i64_ptr1, temp: caught, name: "w_block_return_value", arg: block_return_buf})
    emit_instruction(new_fn, {op: :store_i64, value: caught, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})

    start_block(new_fn, new_fn[:exit_label])
    emit_instruction(new_fn, {op: :call_direct_void_ptr1, name: "w_block_return_pop", arg: block_return_buf})
    final_reg = next_temp(new_fn)
    emit_instruction(new_fn, {op: :load_i64, temp: final_reg, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :ret_i64, value: final_reg, function_recycle_count: 0})

  finalize_function(new_fn)
  nil

-> lower_fn_def(ctx, node)
  mod = ctx[:mod]
  name = node.name
  call_key = method_call_key_for_def(node)
  fn_name = function_name_for_def(node)

  # Register as known call and pure call (skip pure for impure-ccall fns
  # so they don't get memoized — see Metal dispatch_n smoke).
  mod[:known_calls][call_key] = fn_name
  impure_ccall = ast_get(node, :calls_impure_ccall)
  if impure_ccall == nil
    impure_ccall = fn_body_calls_impure_ccall?(node.body)
    node.calls_impure_ccall = impure_ccall
  if !impure_ccall
    mod[:known_pure_calls][call_key] = fn_name
    if mod[:fn_memo_tables][call_key] == nil
      mod[:fn_memo_tables][call_key] = fn_name + ".memo"
      mod[:fn_memo_table_order].push(call_key)
  if node.param_types != nil
    mod[:known_fn_overloads][name] = true

  # Lower the function body (identical to method_def)
  lower_method_def(ctx, node)

# GPU kernel collector. The kernel body is NOT lowered via the WIRE
# pipeline — it's lowered by metal_emitter.w to MSL text instead.
# Here we just stash the AST on mod[:gpu_kernels] so the emitter pass
# can pick them up after lowering finishes.
-> record_gpu_kernel(ctx, node)
  mod = ctx[:mod]
  kernels = mod[:gpu_kernels]
  if kernels == nil
    kernels = []
    mod[:gpu_kernels] = kernels
  kernels.push(node)
  nil

# Schedule/layout collector. Same idea as record_gpu_kernel — stash on
# the module so a later metal_emitter pass can apply per-schedule
# transformations to the algorithm AST before MSL emission.
-> record_gpu_schedule(ctx, node)
  mod = ctx[:mod]
  schedules = mod[:gpu_schedules]
  if schedules == nil
    schedules = []
    mod[:gpu_schedules] = schedules
  schedules.push(node)
  nil

# -- Platform Guards --

-> lower_on_guard(ctx, node)
  target = detect_target()
  if !target_matches?(node.predicate, node.capabilities, target)
    return nil
  i = 0
  while i < node.body.size()
    lower_statement(ctx, node.body[i])
    i += 1
  nil

# -- Classes --

# --- Typed operator-overload dispatch -------------------------------------
#
# A class may declare several same-name / same-arity methods that differ only
# in a parameter type (`-> */1(Vec3)` vs `-> */1(Mat3)`, `-> */1(Vector)` vs
# `-> */1(Number)`). Each lowers to its own function, but they all register
# under the bare method name, so the runtime method table keeps only the last
# one and the rest mis-dispatch. This pass rewrites such a group into:
#   * one renamed type-specific worker per overload (a distinct method name,
#     e.g. `*__ovl_Vec3`), and
#   * a synthesized dispatcher under the original name that branches on
#     `@1.is_a?(ParamType)` — most-specific first — falling through to the
#     hierarchy-base overload (the param type that is an ancestor of all the
#     others, e.g. `Number`), or to `super` when the group has no such base.
# A bodyless abstract declaration that a concrete sibling satisfies is dropped
# so it cannot shadow the real implementation. Groups with a single concrete
# method are otherwise left untouched. The compiler's own classes declare no
# typed overloads, so the pass is inert there and self-host byte-identity is
# preserved.
-> overload_internal_name(base, param_types)
  out = "" + base + "__ovl"
  i = 0
  while i < param_types.size()
    out = out + "_" + param_types[i].to_s()
    i += 1
  out

-> overload_type_is_ancestor?(mod, anc, child)
  ancs = "" + anc.to_s()
  cur = "" + child.to_s()
  if cur == ancs
    return false
  guard = 0
  while guard < 64
    cls = mod[:known_classes][cur]
    if cls == nil
      # Number is the universal base of the numeric tower; treat it as the
      # ancestor of any class we cannot resolve here (load-order tolerant).
      return ancs == "Number"
    sup = cls.superclass
    if sup == nil
      return false
    sup = "" + sup.to_s()
    if sup == ancs
      return true
    cur = sup
    guard += 1
  false

-> overload_dispatch_args(arity)
  out = []
  i = 1
  while i <= arity
    out.push(Tungsten:AST:Parg.new(i))
    i += 1
  out

-> overload_is_a_cond(ovl)
  # Match by type NAME, not a ClassRef: a ClassRef to a generic template
  # (`Vector`, `Vec3`) resolves unreliably, but the runtime stores ancestry
  # under base names, so `is_a?("Vector")` is exact. The runtime is_a?
  # intercept accepts a string target and walks the ancestry by base name.
  # This compiler-only intrinsic lowers to that ancestry check directly,
  # avoiding a full dynamic send for every overload gate.
  tname = Tungsten:AST:String.new("" + ovl.param_types[0].to_s())
  call = Tungsten:AST:Call.new(nil, "__compiler_overload_is_a", [Tungsten:AST:Parg.new(1), tname])
  ast_set(call, :compiler_intrinsic, :overload_is_a)
  call

-> overload_worker_call(class_name, name, ovl, arity)
  iname = overload_internal_name("" + name, ovl.param_types)
  worker = ast_deep_clone(ovl)
  worker.name = iname
  # A body containing `yield` gains an implicit runtime block parameter that
  # the synthesized dispatcher cannot forward. Preserve the old dynamic-call
  # behavior for that unusual shape instead of emitting a mismatched direct
  # call. Ordinary operator workers have exactly self + explicit arguments.
  if method_runtime_arity(worker) != arity + 1
    return Tungsten:AST:Call.new(Tungsten:AST:Self.new, iname, overload_dispatch_args(arity))
  target = class_method_function_name(class_name, worker)
  args = [Tungsten:AST:String.new(target), Tungsten:AST:Self.new]
  dispatch_args = overload_dispatch_args(arity)
  i = 0
  while i < dispatch_args.size()
    args.push(dispatch_args[i])
    i += 1
  # The dispatcher and workers are synthesized as one unit, so the target is
  # known exactly. Lower it as a direct internal call instead of re-entering
  # the runtime method table under the worker's private name.
  call = Tungsten:AST:Call.new(nil, "__compiler_overload_worker", args)
  ast_set(call, :compiler_intrinsic, :overload_worker)
  call

-> build_overload_dispatcher(class_name, name, arity, gated, catch_all)
  first = gated[0]
  elsifs = []
  gi = 1
  while gi < gated.size()
    g = gated[gi]
    elsifs.push([overload_is_a_cond(g), [overload_worker_call(class_name, name, g, arity)]])
    gi += 1
  if catch_all != nil
    else_body = [overload_worker_call(class_name, name, catch_all, arity)]
  else
    else_body = [Tungsten:AST:Super.new(overload_dispatch_args(arity))]
  branch = Tungsten:AST:If.new(overload_is_a_cond(first), [overload_worker_call(class_name, name, first, arity)], elsifs, else_body)
  params = []
  pi = 1
  while pi <= arity
    params.push(Tungsten:AST:Param.new("__arg" + pi.to_s(), nil, false, false, false, false))
    pi += 1
  Tungsten:AST:MethodDef.new(name, params, [branch], nil, false)

-> overload_group_dispatchable?(g)
  g[:arity] == 1 && g[:overloads].size() >= 2 && g[:plain_count] == 0

-> synthesize_overload_dispatchers(mod, class_name, body)
  # Pass 1: bucket instance method defs by (name, explicit-param-count).
  groups = {}
  order = []
  i = 0
  while i < body.size()
    expr = body[i]
    if ast_kind(expr) == :method_def && expr.is_class_method != true
      arity = expr.params.size()
      key = "" + expr.name + "/" + arity.to_s()
      g = groups[key]
      if g == nil
        g = {name: ("" + expr.name), arity: arity, overloads: [], abstract_count: 0, plain_count: 0}
        groups[key] = g
        order.push(key)
      has_body = expr.body != nil && expr.body.size() > 0
      if expr.param_types != nil && has_body
        g[:overloads].push(expr)
      elsif !has_body
        g[:abstract_count] = g[:abstract_count] + 1
      else
        g[:plain_count] = g[:plain_count] + 1
    i += 1

  # Any work to do? (a dispatchable group, or a droppable abstract)
  needs_work = false
  oi = 0
  while oi < order.size()
    g = groups[order[oi]]
    concrete = g[:overloads].size() + g[:plain_count]
    if overload_group_dispatchable?(g)
      needs_work = true
    if g[:abstract_count] > 0 && concrete > 0
      needs_work = true
    oi += 1
  if !needs_work
    return body

  # Pass 2: rebuild the body — drop satisfied abstracts, rename overload
  # workers in dispatchable groups, keep everything else.
  new_body = []
  i = 0
  while i < body.size()
    expr = body[i]
    if ast_kind(expr) != :method_def || expr.is_class_method == true
      new_body.push(expr)
    else
      key = "" + expr.name + "/" + expr.params.size().to_s()
      g = groups[key]
      concrete = g[:overloads].size() + g[:plain_count]
      has_body = expr.body != nil && expr.body.size() > 0
      if !has_body && concrete > 0
        nil
      elsif overload_group_dispatchable?(g) && expr.param_types != nil && has_body
        worker = ast_deep_clone(expr)
        worker.name = overload_internal_name("" + expr.name, expr.param_types)
        new_body.push(worker)
      else
        new_body.push(expr)
    i += 1

  # Pass 3: synthesize one dispatcher per dispatchable group.
  oi = 0
  while oi < order.size()
    g = groups[order[oi]]
    if overload_group_dispatchable?(g)
      ovls = g[:overloads]
      # Catch-all: the overload whose param type is an ancestor of all others.
      catch_all_idx = 0 - 1
      ci = 0
      while ci < ovls.size()
        anc_of_all = true
        cj = 0
        while cj < ovls.size()
          if cj != ci
            if !overload_type_is_ancestor?(mod, ovls[ci].param_types[0], ovls[cj].param_types[0])
              anc_of_all = false
          cj += 1
        if anc_of_all
          catch_all_idx = ci
        ci += 1
      catch_all = nil
      if catch_all_idx >= 0
        catch_all = ovls[catch_all_idx]
      # Gated = the rest, with ancestors sorted after their descendants.
      gated = []
      gk = 0
      while gk < ovls.size()
        if gk != catch_all_idx
          gated.push(ovls[gk])
        gk += 1
      ga = 0
      while ga < gated.size()
        gb = ga + 1
        while gb < gated.size()
          if overload_type_is_ancestor?(mod, gated[ga].param_types[0], gated[gb].param_types[0])
            tmp = gated[ga]
            gated[ga] = gated[gb]
            gated[gb] = tmp
          gb += 1
        ga += 1
      new_body.push(build_overload_dispatcher(class_name, "" + g[:name], g[:arity], gated, catch_all))
    oi += 1
  new_body

-> lower_class_def(ctx, node)
  mod = ctx[:mod]
  class_name = node.name
  # Generic class template: register and skip body lowering. The
  # monomorphization pass synthesizes specialized class defs (e.g.
  # Quaternion$f32) which lower as regular non-generic classes.
  type_params = node.type_params
  if type_params != nil
    if mod[:generic_class_templates] == nil
      mod[:generic_class_templates] = {}
    mod[:generic_class_templates][class_name] = node
    return nil
  mod[:known_classes][class_name] = node
  if ctx[:verbose]
    << ""
    <- "  + " + class_name + " "

  body = node.body
  if body == nil
    return nil
  prepared_body = nil
  if mod[:prepared_class_bodies] != nil
    prepared_body = mod[:prepared_class_bodies][node]
  if prepared_body != nil
    body = prepared_body
  else
    # Fallback for callers that lower an isolated class node without running
    # lower_ast's module-wide registration prepass first.
    body = expand_class_traits(mod, body)
    body = expand_class_body_accessors(body)
    body = synthesize_overload_dispatchers(mod, class_name, body)

  # Collect view layout declarations for $data.field access
  view_fields = collect_view_fields(body)
  if view_fields != nil
    if mod[:view_layouts] == nil
      mod[:view_layouts] = {}
    mod[:view_layouts][class_name] = view_fields

  target = detect_target()
  body = expand_on_guards(body, target)
  old_raw_int_candidates = ctx[:raw_int_candidates]
  class_raw_int_candidates = raw_int_candidate_map(body, ctx[:var_types])
  if old_raw_int_candidates != nil
    merged_raw_int_candidates = {}
    old_keys = old_raw_int_candidates.keys()
    ok = 0
    while ok < old_keys.size()
      merged_raw_int_candidates[old_keys[ok]] = true
      ok += 1
    class_keys = class_raw_int_candidates.keys()
    ck = 0
    while ck < class_keys.size()
      merged_raw_int_candidates[class_keys[ck]] = true
      ck += 1
    ctx[:raw_int_candidates] = merged_raw_int_candidates
  else
    ctx[:raw_int_candidates] = class_raw_int_candidates
  i = 0
  while i < body.size()
    expr = body[i]
    if ast_kind(expr) == :method_def
      lower_class_method(ctx, class_name, desugar_trailing_accessors(ctx, class_name, expr))
    elsif ast_kind(expr) == :call && (ast_get(expr, :name) == "ro" || ast_get(expr, :name) == "rw")
      lower_accessors(ctx, class_name, expr)
    elsif ast_kind(expr) == :view_decl && ast_get(expr, :kind) == "struct"
      # Data block (`- data; T components[4]`) auto-creates an
      # `ro`-style getter per field — bare `components` inside method
      # bodies routes to the synthesized `@components` ivar load. The
      # view-layout side (offset/type for `$components` heap access)
      # is tracked separately in collect_view_fields.
      vd_layout = ast_get(expr, :count)
      if vd_layout != nil && type(vd_layout) == "Hash" && vd_layout[:fields] != nil
        df = 0
        while df < vd_layout[:fields].size()
          fname = vd_layout[:fields][df][:name]
          ivar = "@" + fname
          getter = Tungsten:AST:MethodDef.new(fname, [], [Tungsten:AST:Ivar.new(ivar)])
          lower_class_method(ctx, class_name, getter)
          df += 1
    elsif ast_kind(expr) == :assign && expr.target != nil && ast_kind(expr.target) == :cvar
      # Class variable initialization (@@all = []) — runs at class definition time
      cvar_ctx = {
        mod: mod, func: ctx[:func],
        var_types: ctx[:var_types], class_name: class_name,
        source_path: ctx[:source_path], bindings: ctx[:bindings],
        raw_int_candidates: ctx[:raw_int_candidates],
        method_name: ctx[:method_name],
        verbose: ctx[:verbose],
        is_block: false, block_return_frame: nil
      }
      lower_assign_expr(cvar_ctx, expr)
    elsif ast_kind(expr) == :assign && expr.target != nil && ast_kind(expr.target) == :var
      # Constant/variable initialization in class body — lower as top-level global
      lower_assign_expr(ctx, expr)
    i += 1
  ctx[:raw_int_candidates] = old_raw_int_candidates
  nil

# Collect all ivar names from a class body (ro/rw fields, @param assigns, @ivar in method bodies)
-> collect_class_ivars(body)
  ivars = []
  if body == nil
    return ivars
  body.each -> (expr)
    if ast_kind(expr) == :call && (ast_get(expr, :name) == "ro" || ast_get(expr, :name) == "rw")
      expr.args.each -> (arg)
        iname = "@" + arg.value
        if !ivars.include?(iname)
          ivars.push(iname)
    elsif ast_kind(expr) == :method_def
      if expr.params != nil
        expr.params.each -> (p)
          if p.ivar_assign == true
            iname = "@" + p.name
            if !ivars.include?(iname)
              ivars.push(iname)
      if expr.body != nil
        collect_ivars_from_exprs(expr.body, ivars)
  ivars

-> collect_ivars_from_exprs(exprs, ivars)
  exprs.each -> (expr)
    ek = ast_kind(expr)
    # @fastmath / @strictmath blocks are plain hash nodes; they answer only
    # subscript access, not the method-style `.body` the generic recursion
    # below uses (calling `.body` on the hash raises). Recurse into the body
    # via subscript so ivar assignments inside the block are still collected.
    if ek in (:fastmath_block :strictmath_block :overflow_block)
      collect_ivars_from_exprs(expr[:body], ivars)
    else
      if ek == :ivar
        if !ivars.include?(expr.name)
          ivars.push(expr.name)
      elsif ek == :assign && expr.target != nil && ast_kind(expr.target) == :ivar
        iname = expr.target.name
        if !ivars.include?(iname)
          ivars.push(iname)
      if expr.body != nil
        collect_ivars_from_exprs(expr.body, ivars)
      if expr.then_body != nil
        collect_ivars_from_exprs(expr.then_body, ivars)
      if expr.else_body != nil
        collect_ivars_from_exprs(expr.else_body, ivars)
      if expr.expressions != nil
        collect_ivars_from_exprs(expr.expressions, ivars)

-> register_class_method(main_fn, mod, cname, mname, arity)
  mfn_name = "__w_" + cname.gsub(":", "__") + "_" + mangle_method_name(mname) + "__a" + arity.to_s()
  mstr_id = module_string_constant(mod, mname)
  mbyte_len = utf8_byte_length(mname) + 1
  cls_reload = next_temp(main_fn)
  emit_instruction(main_fn, {op: :load_class, temp: cls_reload, class_name: cname})
  emit_instruction(main_fn, {op: :class_add_method, class_temp: cls_reload, method_str_id: mstr_id, method_byte_len: mbyte_len, fn_name: mfn_name, arity: arity})

-> method_arity_suffix(node)
  "__a" + method_runtime_arity(node).to_s()

-> class_method_function_name(cname, node)
  prefix = "__w_" + cname.gsub(":", "__") + "_"
  # Static methods (class methods) don't carry an arity suffix — the
  # raw-i64 ABI relies on the bare name + a `__boxed` wrapper variant
  # for dynamic dispatch (test #980 / #1005 / #1062). Instance methods
  # keep the arity suffix so multiple-arity overloads can coexist.
  if node.is_class_method == true
    return "__w_" + cname.gsub(":", "__") + "_S_" + mangle_method_name(node.name)
  prefix + mangle_method_name(node.name) + method_arity_suffix(node)

-> register_class_method_def(main_fn, mod, cname, node)
  mname = node.name
  arity = method_runtime_arity(node)
  mfn_name = class_method_function_name(cname, node)
  mstr_id = module_string_constant(mod, mname)
  mbyte_len = utf8_byte_length(mname) + 1
  cls_reload = next_temp(main_fn)
  emit_instruction(main_fn, {op: :load_class, temp: cls_reload, class_name: cname})
  emit_instruction(main_fn, {op: :class_add_method, class_temp: cls_reload, method_str_id: mstr_id, method_byte_len: mbyte_len, fn_name: mfn_name, arity: arity})
  # Phase 5: stash the method-def AST so specialize_method can clone+re-lower
  # it under a child context with `__self` typed to a concrete variant.
  # Also stash an arity-keyed entry so monomorphization of an OVERLOADED method
  # (e.g. Enumerable `sum`/`sum(init)`) specializes the body matching the call's
  # argument count — the bare-name key keeps only the last-registered overload,
  # which made `a.sum()` specialize `sum(init)` and leave the accumulator nil.
  mod[:class_method_asts][cname + "." + mname] = node
  pcount = 0
  if node.params != nil
    pcount = node.params.size()
  mod[:class_method_asts][cname + "." + mname + "/" + pcount.to_s()] = node

-> static_method_raw_abi?(node)
  # Both class methods (`-> .name`) and typed instance methods (`->`,
  # `fn`) qualify for the raw-i64 ABI when their type annotations make
  # it sound. Default-valued params force the boxed path so missing
  # args resolve to nil. Previously gated on is_class_method, which
  # forced every instance-method call through w_method_call_cached
  # even when the receiver type was statically known.
  params = node.params
  if params != nil
    pi = 0
    while pi < params.size()
      if params[pi].default != nil
        return false
      pi += 1
  if node.return_type != nil && is_machine_int64_type(normalize_type_symbol(node.return_type))
    return true
  pt = node.param_types
  if pt != nil
    i = 0
    while i < pt.size()
      if is_machine_int64_type(normalize_type_symbol(pt[i]))
        return true
      i += 1
  false

-> static_method_wrapper_name(cname, mname)
  "__w_" + cname.gsub(":", "__") + "_S_" + mangle_method_name(mname) + "__boxed"

-> normalized_static_param_types(node)
  if node.param_types == nil
    return []
  normalized_signature_types(node.param_types)

-> register_static_method(main_fn, mod, cname, node)
  mname = node.name
  arity = method_runtime_arity(node)
  mfn_name = class_method_function_name(cname, node)
  method_fn_name = mfn_name
  raw_abi = static_method_raw_abi?(node)
  if raw_abi
    method_fn_name = static_method_wrapper_name(cname, mname)
  return_type = nil
  if node.return_type != nil
    return_type = normalize_type_symbol(node.return_type)
  mod[:known_static_methods][cname + "." + mname] = {
    fn_name: mfn_name,
    method_fn_name: method_fn_name,
    arity: arity,
    return_type: return_type,
    param_types: normalized_static_param_types(node),
    raw_abi: raw_abi
  }
  mstr_id = module_string_constant(mod, mname)
  mbyte_len = utf8_byte_length(mname) + 1
  cls_reload = next_temp(main_fn)
  emit_instruction(main_fn, {op: :load_class, temp: cls_reload, class_name: cname})
  emit_instruction(main_fn, {op: :class_add_static_method, class_temp: cls_reload, method_str_id: mstr_id, method_byte_len: mbyte_len, fn_name: method_fn_name, arity: arity})

# `-> new(@x, @y) ro` — a bare ro/rw as a body statement of an @-binding
# method marks those params for accessor generation, mirroring a class-body
# `ro :x, :y`. Generates the getters (and setters for rw) and returns a
# MethodDef with the marker stripped; methods without the marker pass
# through untouched.
-> desugar_trailing_accessors(ctx, class_name, mdef)
  body = mdef.body
  if body == nil
    return mdef
  marker = nil
  kept = []
  i = 0
  while i < body.size()
    st = body[i]
    if marker == nil && is_ast_node?(st) && ast_kind(st) == :call && st.receiver == nil && (ast_get(st, :name) == "ro" || ast_get(st, :name) == "rw") && (st.args == nil || st.args.size() == 0)
      marker = ast_get(st, :name)
    else
      kept.push(st)
    i += 1
  if marker == nil
    return mdef
  writable = marker == "rw"
  params = mdef.params
  i = 0
  while i < params.size()
    p = params[i]
    if ast_get(p, :ivar_assign) == true
      field = ast_get(p, :name)
      ivar = "@" + field
      getter = Tungsten:AST:MethodDef.new(field, [], [Tungsten:AST:Ivar.new(ivar)])
      lower_class_method(ctx, class_name, getter)
      if writable
        setter = Tungsten:AST:MethodDef.new(field + "=", [Tungsten:AST:Param.new("value", nil, false)], [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), Tungsten:AST:Var.new("value"))])
        lower_class_method(ctx, class_name, setter)
    i += 1
  Tungsten:AST:MethodDef.new(mdef.name, params, kept)

-> lower_accessors(ctx, class_name, expr)
  writable = expr.name == "rw"
  args = expr.args
  default_expr = expr.default
  i = 0
  while i < args.size()
    arg = args[i]
    field = arg.value
    ivar = "@" + field

    getter_body = [Tungsten:AST:Ivar.new(ivar)]
    if default_expr != nil
      default_check = Tungsten:AST:If.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Ivar.new(ivar), :EQ, Tungsten:AST:Nil.new), [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), default_expr)], [], nil)
      getter_body = [default_check, Tungsten:AST:Ivar.new(ivar)]

    # Getter: -> field; @field
    getter = Tungsten:AST:MethodDef.new(field, [], getter_body)
    lower_class_method(ctx, class_name, getter)

    if writable
      # Setter: -> field=(value); @field = value
      setter = Tungsten:AST:MethodDef.new(field + "=", [Tungsten:AST:Param.new("value", nil, false)], [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), Tungsten:AST:Var.new("value"))])
      lower_class_method(ctx, class_name, setter)
    i += 1

-> class_body_accessor_methods(expr)
  writable = ast_get(expr, :name) == "rw"
  args = ast_get(expr, :args)
  default_expr = ast_get(expr, :default)
  out = []
  i = 0
  while i < args.size()
    arg = args[i]
    field = ast_get(arg, :value)
    ivar = "@" + field

    getter_body = [Tungsten:AST:Ivar.new(ivar)]
    if default_expr != nil
      default_check = Tungsten:AST:If.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Ivar.new(ivar), :EQ, Tungsten:AST:Nil.new), [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), default_expr)], [], nil)
      getter_body = [default_check, Tungsten:AST:Ivar.new(ivar)]

    out.push(Tungsten:AST:MethodDef.new(field, [], getter_body))

    if writable
      setter = Tungsten:AST:MethodDef.new(field + "=", [Tungsten:AST:Param.new("value", nil, false)], [Tungsten:AST:Assign.new(Tungsten:AST:Ivar.new(ivar), Tungsten:AST:Var.new("value"))])
      out.push(setter)
    i += 1
  out

-> expand_class_body_accessors(body)
  if body == nil
    return []
  expanded = []
  i = 0
  while i < body.size()
    expr = body[i]
    if ast_kind(expr) == :call && (ast_get(expr, :name) == "ro" || ast_get(expr, :name) == "rw")
      methods = class_body_accessor_methods(expr)
      mi = 0
      while mi < methods.size()
        expanded.push(methods[mi])
        mi += 1
    else
      expanded.push(expr)
    i += 1
  expanded

-> replace_or_append_function(mod, new_fn)
  functions = mod[:functions]

  # Class-heavy programs call this once per lowered method. Scanning the full
  # function array each time made that path quadratic. Keep a name -> array
  # index alongside it, lazily catching up with functions appended by the
  # other lowering paths before each lookup. If a direct append introduced a
  # duplicate name, the newest index wins exactly as the old full scan did.
  function_index = mod[:function_index_by_name]
  if function_index == nil
    function_index = {}
    mod[:function_index_by_name] = function_index
    mod[:function_indexed_count] = 0
  indexed_count = mod[:function_indexed_count]
  while indexed_count < functions.size()
    function_index[functions[indexed_count][:name]] = indexed_count
    indexed_count += 1
  mod[:function_indexed_count] = indexed_count

  existing_idx = function_index[new_fn[:name]]
  if existing_idx != nil
    functions[existing_idx] = new_fn
    return nil

  new_idx = functions.size()
  functions.push(new_fn)
  function_index[new_fn[:name]] = new_idx
  mod[:function_indexed_count] = new_idx + 1
  nil

-> lower_static_method_boxed_wrapper(ctx, class_name, node, raw_fn_name, wrapper_fn_name, child_var_types)
  mod = ctx[:mod]
  params = node.params
  param_names = ["__self"]
  i = 0
  while i < params.size()
    param_names.push(param_runtime_name(params[i]))
    i += 1

  wrapper_fn = build_function(wrapper_fn_name, param_names, "i64", false, [])
  wrapper_fn[:source_kind] = :static_wrapper
  wrapper_fn[:source_method] = node.name
  wrapper_fn[:source_class] = class_name
  wrapper_fn[:source_path] = ctx[:source_path]
  wrapper_fn[:source_line] = node.line
  replace_or_append_function(mod, wrapper_fn)

  call_args = ["%__self"]
  i = 0
  while i < params.size()
    pname = param_runtime_name(params[i])
    pt = child_var_types[pname]
    if is_machine_int64_type(pt)
      raw = ensure_raw_machine_int(wrapper_fn, typed_value(:i64, "%" + pname), pt, pt)
      call_args.push(raw)
    else
      call_args.push("%" + pname)
    i += 1

  temp = next_temp(wrapper_fn)
  emit_instruction(wrapper_fn, {op: :call_direct_i64, temp: temp, name: raw_fn_name, args: call_args})

  ret_type = nil
  if node.return_type != nil
    ret_type = normalize_type_symbol(node.return_type)
  if is_machine_int64_type(ret_type)
    boxed = ensure_i64_value(wrapper_fn, typed_value(raw_machine_value_type(ret_type), temp))
    emit_instruction(wrapper_fn, {op: :ret_i64, value: boxed})
  else
    emit_instruction(wrapper_fn, {op: :ret_i64, value: temp})

  finalize_function(wrapper_fn)

-> lower_class_method(ctx, class_name, node, override = nil)
  mod = ctx[:mod]
  name = node.name
  if ctx[:verbose]
    <- "."
  params = node.params
  body = node.body
  analysis = method_lowering_analysis(node)
  fn_name = class_method_function_name(class_name, node)
  # Phase 5: monomorphization override — uses a mangled fn name and pre-types
  # __self so dispatch in the body picks up the variant (e.g. typed_array_u8
  # → :typed_array_get_inline instead of method_call_dispatch).
  if override != nil && override[:fn_name] != nil
    fn_name = override[:fn_name]
  raw_abi = false
  wrapper_fn_name = nil
  if node.is_class_method == true
    static_info = mod[:known_static_methods][class_name + "." + name]
    if static_info != nil && static_info[:raw_abi] == true
      raw_abi = true
      wrapper_fn_name = static_info[:method_fn_name]

  # Build param list: __self first, then declared params
  param_names = ["__self"]
  i = 0
  while i < params.size()
    param_names.push(param_runtime_name(params[i]))
    i += 1
  yield_block_name = analysis[:yield_block_name]
  if yield_block_name == "__block"
    param_names.push("__block")

  # Build function. If a function with this name already exists (from a
  # prior class_def for the same re-opened class), remove it first — last
  # wins. Without this, mod[:functions] ends up with duplicate-named
  # entries that confuse the content-hash topo sort (keyed by name).
  new_fn = build_function(fn_name, param_names, "i64", false, [])
  if node.is_class_method == true
    new_fn[:source_kind] = :static_method
  else
    new_fn[:source_kind] = :method
  new_fn[:source_method] = name
  new_fn[:source_class] = class_name
  new_fn[:source_path] = ctx[:source_path]
  new_fn[:source_line] = node.line
  replace_or_append_function(mod, new_fn)
  if node.return_type != nil
    raw_return_type = normalize_type_symbol(node.return_type)
    # Runtime-dispatched instance methods are registered directly in the
    # method table, whose ABI always returns a boxed WValue.  Returning a raw
    # machine integer here makes values such as `1` look like the W_FALSE tag
    # to w_method_call_cached.  Static methods may use a raw worker because
    # register_static_method installs the boxed wrapper generated below.
    if raw_abi && is_raw_int_storage_type(raw_return_type)
      new_fn[:raw_return_type] = raw_return_type
    # Static methods are called `Class.name(…)` — register the dotted key
    # infer_type's static-receiver lookup uses, so a declared return type
    # (e.g. `-> .atan2(y, x) f64` in core/math.w) drives call-site
    # inference the same way top-level fn annotations do.
    if node.is_class_method == true
      mod[:fn_return_types][class_name + "." + name] = raw_return_type

  needs_block_return = analysis[:needs_block_return]
  if needs_block_return
    new_fn[:result_slot] = "%__block_return_result"
    new_fn[:exit_label] = next_label(new_fn, "blockret.exit")

  # Child context with class_name set
  child_var_types = {}
  # Phase 5: seed __self type for specialized variants. Drives downstream
  # dispatch (e.g. self[i] → :typed_array_get_inline at the variant's ebits).
  if override != nil && override[:self_type] != nil
    child_var_types["__self"] = override[:self_type]
  child_ctx = {
    mod: mod,
    func: new_fn,
    var_types: child_var_types,
    class_name: class_name,
    source_path: ctx[:source_path],
    method_name: name,
    bindings: {},
    unboxed_vars: {},
    verbose: ctx[:verbose],
    is_class_method: node.is_class_method == true,
    is_block: false,
    block_return_frame: nil,
    yield_block_name: yield_block_name
  }
  if node.param_types != nil
    pt = node.param_types
    pti = 0
    while pti < pt.size() && pti < params.size()
      pname = param_runtime_name(params[pti])
      pts = pt[pti].to_s()
      ptsl = pts.size()
      if ptsl >= 3 && pts.slice(ptsl - 2, 2) == "\[]"
        child_var_types[pname] = typed_array_etype_to_sym(pts.slice(0, ptsl - 2))
      else
        child_var_types[pname] = normalize_type_symbol(pt[pti])
      pti += 1

  child_ctx[:raw_int_candidates] = raw_int_candidate_map(body, child_var_types)

  block_return_buf = nil
  if needs_block_return
    block_return_buf = next_temp(new_fn)
    emit_instruction(new_fn, {op: :alloca_i64, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :call_direct_ptr, temp: block_return_buf, name: "w_block_return_push", args: []})
    block_return_bits = next_temp(new_fn)
    emit_instruction(new_fn, {op: :ptr_to_i64, temp: block_return_bits, value: block_return_buf})
    child_ctx[:block_return_frame] = block_return_bits
    sj = next_temp(new_fn)
    emit_instruction(new_fn, {op: :setjmp, temp: sj, buf: block_return_buf})
    cmp = next_temp(new_fn)
    emit_instruction(new_fn, {op: :icmp_eq_i32, temp: cmp, lhs: sj, rhs: "0"})
    body_label = next_label(new_fn, "blockret.body")
    catch_label = next_label(new_fn, "blockret.catch")
    emit_instruction(new_fn, {op: :cond_br, cond: cmp, then_label: body_label, else_label: catch_label})
    start_block(new_fn, body_label)
    block_return_slot = ensure_var_slot(new_fn, "__block_return_frame")
    emit_instruction(new_fn, {op: :store_i64, value: block_return_bits, ptr: block_return_slot})

  # Unbox typed machine-int class-method parameters once at function entry.
  i = 0
  while i < params.size()
    pname = param_runtime_name(params[i])
    pt = child_var_types[pname]
    if is_raw_int_storage_type(pt)
      if raw_abi && is_machine_int64_type(pt)
        child_ctx[:bindings][pname] = "%" + pname
      else
        raw = nanunbox_int_emit(new_fn, "%" + pname)
        child_ctx[:bindings][pname] = raw
    i += 1

  # Handle ivar_assign params (-> new(@name) assigns @name = name)
  i = 0
  while i < params.size()
    p = params[i]
    if p.ivar_assign == true
      lower_ivar_set_expr(child_ctx, "@" + p.name, typed_value(:i64, "%" + p.name))
    i += 1

  # Emit default parameter guards for class methods
  i = 0
  while i < params.size()
    p = params[i]
    if p.default != nil
      pname = param_runtime_name(p)
      param_reg = "%" + pname
      is_nil = next_temp(new_fn)
      emit_instruction(new_fn, {op: :icmp_i64, temp: is_nil, pred: "eq", lhs: param_reg, rhs: w_nil.to_s()})
      default_val = lower_expression(child_ctx, p.default)
      default_reg = ensure_i64_value(new_fn, default_val)
      result = next_temp(new_fn)
      emit_instruction(new_fn, {op: :select_i64, temp: result, cond: is_nil, then_val: default_reg, else_val: param_reg})
      child_ctx[:bindings][pname] = result
    i += 1

  # Pre-scan body for parameter reassignment
  reassigned = find_reassigned_params(body, param_names)
  pi = 0
  while pi < reassigned.size()
    pname = reassigned[pi]
    slot_type = "i64"
    if is_raw_int_storage_type(child_var_types[pname])
      slot_type = machine_slot_type(child_var_types[pname])
    ptr = ensure_var_slot(new_fn, pname, slot_type)
    if child_ctx[:bindings][pname] != nil
      if is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:raw_i64, child_ctx[:bindings][pname]), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: child_ctx[:bindings][pname], ptr: ptr})
    else
      if is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:i64, "%" + pname), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: "%" + pname, ptr: ptr})
    pi += 1

  captured_params = find_captured_params_in_body(body, param_names)
  pi = 0
  while pi < captured_params.size()
    pname = captured_params[pi]
    if new_fn[:var_slots][pname] == nil
      slot_type = "i64"
      if is_raw_int_storage_type(child_var_types[pname])
        slot_type = machine_slot_type(child_var_types[pname])
      ptr = ensure_var_slot(new_fn, pname, slot_type)
      if child_ctx[:bindings][pname] != nil
        if is_raw_int_storage_type(child_var_types[pname])
          raw = ensure_raw_machine_int(new_fn, typed_value(:raw_i64, child_ctx[:bindings][pname]), child_var_types[pname], child_var_types[pname])
          emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
        else
          emit_instruction(new_fn, {op: :store_i64, value: child_ctx[:bindings][pname], ptr: ptr})
      elsif is_raw_int_storage_type(child_var_types[pname])
        raw = ensure_raw_machine_int(new_fn, typed_value(:i64, "%" + pname), child_var_types[pname], child_var_types[pname])
        emit_instruction(new_fn, {op: machine_store_op(child_var_types[pname]), value: raw, ptr: ptr})
      else
        emit_instruction(new_fn, {op: :store_i64, value: "%" + pname, ptr: ptr})
    pi += 1

  # Lower body with implicit return for last expression
  if body != nil && body.size() > 0
    prev_stmts = child_ctx[:enclosing_stmts]
    prev_idx = child_ctx[:enclosing_stmt_idx]
    child_ctx[:enclosing_stmts] = body
    i = 0
    while i < body.size() - 1
      if block_terminated(new_fn)
        break
      child_ctx[:enclosing_stmt_idx] = i
      lower_statement(child_ctx, body[i])
      i += 1

    if !block_terminated(new_fn)
      child_ctx[:enclosing_stmt_idx] = body.size() - 1
      last = body[body.size() - 1]
      last_t = ast_kind(last)
      is_if_stmt = last_t == :if && (last.else_body == nil || last.else_body.size() == 0) && (last.elsif_clauses == nil || last.elsif_clauses.size() == 0)
      if last_t in (:puts :print :while :method_def :fn_def :begin :raise) || is_if_stmt
        lower_statement(child_ctx, last)
      elsif last_t == :return
        lower_statement(child_ctx, last)
      else
        result = lower_expression(child_ctx, last)
        result_reg = ensure_return_value(child_ctx, result, last)
        if new_fn[:exit_label] != nil && new_fn[:result_slot] != nil
          emit_recycles_above_depth(new_fn, 0)
          emit_instruction(new_fn, {op: :store_i64, value: result_reg, ptr: new_fn[:result_slot]})
          emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})
        else
          emit_instruction(new_fn, {op: :ret_i64, value: result_reg})
    child_ctx[:enclosing_stmts] = prev_stmts
    child_ctx[:enclosing_stmt_idx] = prev_idx

  if needs_block_return
    if !block_terminated(new_fn)
      emit_recycles_above_depth(new_fn, 0)
      emit_instruction(new_fn, {op: :store_i64, value: w_nil.to_s(), ptr: new_fn[:result_slot]})
      emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})

    start_block(new_fn, catch_label)
    caught = next_temp(new_fn)
    emit_instruction(new_fn, {op: :call_direct_i64_ptr1, temp: caught, name: "w_block_return_value", arg: block_return_buf})
    emit_instruction(new_fn, {op: :store_i64, value: caught, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :br, label: new_fn[:exit_label]})

    start_block(new_fn, new_fn[:exit_label])
    emit_instruction(new_fn, {op: :call_direct_void_ptr1, name: "w_block_return_pop", arg: block_return_buf})
    final_reg = next_temp(new_fn)
    emit_instruction(new_fn, {op: :load_i64, temp: final_reg, ptr: new_fn[:result_slot]})
    emit_instruction(new_fn, {op: :ret_i64, value: final_reg, function_recycle_count: 0})

  finalize_function(new_fn)
  if raw_abi && wrapper_fn_name != nil && wrapper_fn_name != fn_name
    lower_static_method_boxed_wrapper(ctx, class_name, node, fn_name, wrapper_fn_name, child_var_types)
  nil

# -- Class variables --

-> lower_cvar(ctx, node)
  wfn = ctx[:func]
  cvar_name = node.name
  class_name = ctx[:class_name]
  if class_name == nil
    raise compile_error_for_node(:E_LOWER_CVAR_OUTSIDE_CLASS, "class variable '" + cvar_name + "' used outside of a class", ctx[:source_path], node)
  # Strip @@ prefix for LLVM global name: @@all → all
  stripped = cvar_name.slice(2, cvar_name.size() - 2)
  cvar_key = class_name + "." + stripped
  ctx[:mod][:cvar_globals][cvar_key] = true
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :load_cvar, temp: temp, cvar_key: cvar_key})
  typed_value(:i64, temp)

-> lower_cvar_set(ctx, target, val_tv)
  wfn = ctx[:func]
  cvar_name = target.name
  val_reg = ensure_i64_value(wfn, val_tv)
  class_name = ctx[:class_name]
  if class_name == nil
    raise compile_error_for_node(:E_LOWER_CVAR_OUTSIDE_CLASS, "class variable '" + cvar_name + "' used outside of a class", ctx[:source_path], target)
  stripped = cvar_name.slice(2, cvar_name.size() - 2)
  cvar_key = class_name + "." + stripped
  ctx[:mod][:cvar_globals][cvar_key] = true
  emit_instruction(wfn, {op: :store_cvar, cvar_key: cvar_key, value: val_reg})
  typed_value(:i64, val_reg)

# -- Instance variables --

-> lower_ivar(ctx, node)
  wfn = ctx[:func]
  ivar_name = node.name
  self_val = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_val)

  # Try indexed access if class ivar offsets are known
  offset = nil
  if ctx[:class_name]
    class_node = ctx[:mod][:known_classes][ctx[:class_name]]
    if class_node && ast_get(class_node, :ivar_offsets)
      offset = ast_get(class_node, :ivar_offsets)[ivar_name]

  if offset != nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :ivar_get_idx, temp: temp, self_reg: self_reg, offset: offset})
    # Data-block typed reads: when the class declared the ivar as `int X`
    # (or any integer-like type) in its `- data` block, the polymorphic
    # ivar storage still holds a boxed Integer (w_int(...)) but we know
    # the dynamic type is always int. Unbox at the read site so callers
    # get a raw_int — letting `n <= @field` lower to a plain `icmp`
    # instead of a w_lte runtime call. The unbox is one shl/ashr pair;
    # the polymorphic compare is a function call, so this is a clear
    # win when the field is read inside a hot loop.
    field_type = ivar_data_block_type(ctx, ivar_name)
    if field_type != nil && field_type == :int
      raw = nanunbox_int_emit(wfn, temp)
      return typed_value(:raw_int, raw)
    return typed_value(:i64, temp)

  # Fallback: string-based lookup
  str_id = module_string_constant(ctx[:mod], ivar_name)
  byte_len = utf8_byte_length(ivar_name) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :ivar_get, temp: temp, temp_ptr: temp_ptr, self_reg: self_reg, str_id: str_id, byte_len: byte_len})
  typed_value(:i64, temp)

# Look up an ivar's declared type from the class's `- data` block, if any.
# Returns a normalized type symbol (:int, :i64, etc.) or nil. Used by the
# read-site to unbox at the boundary so downstream comparisons / arithmetic
# can specialize without going through w_lte / w_int / etc.
-> ivar_data_block_type(ctx, ivar_name)
  if ctx[:class_name] == nil
    return nil
  layouts = ctx[:mod][:view_layouts]
  if layouts == nil
    return nil
  class_layout = layouts[ctx[:class_name]]
  if class_layout == nil
    return nil
  # Strip the leading `@` to match the field name in the data block.
  field_name = ivar_name
  if field_name.starts_with?("@")
    field_name = field_name.slice(1, field_name.size() - 1)
  field = class_layout[field_name]
  if field == nil
    return nil
  ftype_str = field[:type]
  if ftype_str == nil
    return nil
  if ftype_str == "int"
    return :int
  nil

-> lower_ivar_set_expr(ctx, ivar_name, val_tv)
  wfn = ctx[:func]
  self_val = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_val)
  val_reg = ensure_i64_value(wfn, val_tv)

  offset = nil
  if ctx[:class_name]
    class_node = ctx[:mod][:known_classes][ctx[:class_name]]
    if class_node && ast_get(class_node, :ivar_offsets)
      offset = ast_get(class_node, :ivar_offsets)[ivar_name]

  if offset != nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :ivar_set_idx, temp: temp, self_reg: self_reg, offset: offset, value: val_reg})
    return typed_value(:i64, temp)

  # Fallback: string-based lookup
  str_id = module_string_constant(ctx[:mod], ivar_name)
  byte_len = utf8_byte_length(ivar_name) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :ivar_set, temp: temp, temp_ptr: temp_ptr, self_reg: self_reg, str_id: str_id, byte_len: byte_len, value: val_reg})
  typed_value(:i64, temp)

# -- Go (goroutine spawn) --

-> lower_go(ctx, node)
  wfn = ctx[:func]

  # Go bodies are zero-arg closures. Use an unused synthetic param to prevent
  # lower_block_closure's iterator shorthand from promoting free vars to params.
  # Must be a real Block node — lower_block_closure's is_ast_node? guard
  # silently returns nil for a plain {params:, body:} hash (slab-AST era).
  block = Tungsten:AST:Block.new(["__go_unused"], node.body)
  closure_tv = lower_block_closure(ctx, block)
  closure_reg = ensure_i64_value(wfn, closure_tv)

  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_goroutine_spawn", args: [closure_reg]})
  typed_value(:i64, temp)

# -- Yield --

-> lower_yield(ctx, node)
  wfn = ctx[:func]
  args = node.args

  # Access the block as a function parameter (not a var slot). Explicit
  # `&block` and implicit `yield` share the same call-site closure.
  block_name = ctx[:yield_block_name]
  if block_name == nil
    block_name = "__block"
  block_reg = nil

  slot = wfn[:var_slots][block_name]
  if slot != nil
    block_reg = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: block_reg, ptr: slot})

  if block_reg == nil
    binding = ctx[:bindings][block_name]
    if binding != nil
      block_reg = binding

  if block_reg == nil
    i = 0
    while i < wfn[:params].size()
      if wfn[:params][i] == block_name
        block_reg = "%" + block_name
        break
      i += 1

  if block_reg == nil
    block_reg = "%" + block_name

  # Lower yield arguments
  arg_regs = []
  i = 0
  while i < args.size()
    val = lower_expression(ctx, args[i])
    arg_regs.push(ensure_i64_value(wfn, val))
    i += 1

  temp = next_temp(wfn)
  if arg_regs.size() == 0
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_0", args: [block_reg]})
  elsif arg_regs.size() == 1
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_1", args: [block_reg, arg_regs[0]]})
  elsif arg_regs.size() == 2
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_2", args: [block_reg, arg_regs[0], arg_regs[1]]})
  else
    # Fallback: use call_1 with first arg (best effort)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_1", args: [block_reg, arg_regs[0]]})
  typed_value(:i64, temp)
