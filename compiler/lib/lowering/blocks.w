# Lowering / blocks — block and closure lowering. Captures discovery,
# free-var analysis, parg sniffing, and lower_block_closure live here.
#
# Depends on pass_registry.w, types.w, ops.w. Sits before
# control_flow.w and calls.w in the dep chain — both call lower_block_closure
# (case-arm bodies, inline iter calls).
#
# This file deliberately has no `use` directives — see pass_registry.w.


# -- Blocks / Closures --

-> find_captures(block, ctx)
  captures = []
  block_param_set = {}
  bp = ast_get(block, :params)
  if bp in (nil false)
    bp = []
  i = 0
  while i < bp.size()
    block_param_set[bp[i]] = true
    i += 1
  outer_vars = ctx[:func][:var_slots]
  fn_params = ctx[:func][:params]
  find_vars_in_body(ast_get(block, :body), captures, block_param_set, outer_vars, fn_params)
  captures

-> merge_capture_names(into, names)
  if names == nil
    return nil
  i = 0
  while i < names.size()
    name = names[i]
    if !into.include?(name)
      into.push(name)
    i += 1

-> find_captured_params_in_body(body, fn_params)
  captures = []
  if body == nil
    return captures
  i = 0
  while i < body.size()
    find_captured_params_in_node(body[i], captures, fn_params)
    i += 1
  captures

-> find_captured_params_in_node(node, captures, fn_params)
  if node == nil
    return nil

  if ast_get(node, :block) != nil
    block_ctx = {func: {var_slots: {}, params: fn_params}}
    merge_capture_names(captures, find_captures(ast_get(node, :block), block_ctx))
    if fn_params.include?("__self") && !captures.include?("__self")
      captures.push("__self")
    merge_capture_names(captures, find_captured_params_in_body(ast_get(ast_get(node, :block), :body), fn_params))

  t = ast_kind(node)
  case t
  when :call
    if ast_get(node, :receiver) == nil
      # A bare call whose name is an enclosing function parameter is a
      # closure invocation, not an implicit-self method. Record it before
      # lowering any branch so the captured parameter slot is initialized at
      # function entry rather than on whichever closure literal appears first.
      name = ast_get(node, :name)
      if fn_params.include?(name) && !captures.include?(name)
        captures.push(name)
    else
      find_captured_params_in_node(ast_get(node, :receiver), captures, fn_params)
    if ast_get(node, :args) != nil
      i = 0
      while i < ast_get(node, :args).size()
        find_captured_params_in_node(ast_get(node, :args)[i], captures, fn_params)
        i += 1
    return nil
  when :assign, :compound_assign
    if ast_get(node, :target) != nil
      find_captured_params_in_node(ast_get(node, :target), captures, fn_params)
    if ast_get(node, :value) != nil
      find_captured_params_in_node(ast_get(node, :value), captures, fn_params)
    return nil
  when :binary_op, :and, :or
    find_captured_params_in_node(ast_get(node, :left), captures, fn_params)
    find_captured_params_in_node(ast_get(node, :right), captures, fn_params)
    return nil
  when :puts
    # node.value is a list of print-args — walk each (cf. the :call case).
    vals = ast_get(node, :value)
    if vals != nil
      i = 0
      while i < vals.size()
        find_captured_params_in_node(vals[i], captures, fn_params)
        i += 1
    return nil
  when :unary_op, :not, :print, :return
    if ast_get(node, :operand) != nil
      find_captured_params_in_node(ast_get(node, :operand), captures, fn_params)
    if ast_get(node, :value) != nil
      find_captured_params_in_node(ast_get(node, :value), captures, fn_params)
    return nil
  when :if
    find_captured_params_in_node(ast_get(node, :condition), captures, fn_params)
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :then_body), fn_params))
    if ast_get(node, :elsif_clauses) != nil
      i = 0
      while i < ast_get(node, :elsif_clauses).size()
        clause = ast_get(node, :elsif_clauses)[i]
        find_captured_params_in_node(clause[0], captures, fn_params)
        merge_capture_names(captures, find_captured_params_in_body(clause[1], fn_params))
        i += 1
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :else_body), fn_params))
    return nil
  when :while
    find_captured_params_in_node(ast_get(node, :condition), captures, fn_params)
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :body), fn_params))
    return nil
  when :case
    if ast_get(node, :whens) != nil
      i = 0
      while i < ast_get(node, :whens).size()
        w = ast_get(node, :whens)[i]
        ci = 0
        while ci < ast_get(w, :conditions).size()
          find_captured_params_in_node(ast_get(w, :conditions)[ci], captures, fn_params)
          ci += 1
        merge_capture_names(captures, find_captured_params_in_body(ast_get(w, :body), fn_params))
        i += 1
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :else_body), fn_params))
    return nil
  when :case_value
    find_captured_params_in_node(ast_get(node, :subject), captures, fn_params)
    if ast_get(node, :arms) != nil
      i = 0
      while i < ast_get(node, :arms).size()
        arm = ast_get(node, :arms)[i]
        find_captured_params_in_node(ast_get(arm, :pattern), captures, fn_params)
        if ast_get(arm, :guard) != nil
          find_captured_params_in_node(ast_get(arm, :guard), captures, fn_params)
        merge_capture_names(captures, find_captured_params_in_body(ast_get(arm, :body), fn_params))
        i += 1
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :else_body), fn_params))
    return nil
  when :begin
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :body), fn_params))
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :rescue_body), fn_params))
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :ensure_body), fn_params))
    return nil
  when :array
    if ast_get(node, :elements) != nil
      i = 0
      while i < ast_get(node, :elements).size()
        find_captured_params_in_node(ast_get(node, :elements)[i], captures, fn_params)
        i += 1
    return nil
  when :hash_literal
    if ast_get(node, :entries) != nil
      i = 0
      while i < ast_get(node, :entries).size()
        entry = ast_get(node, :entries)[i]
        find_captured_params_in_node(entry[0], captures, fn_params)
        find_captured_params_in_node(entry[1], captures, fn_params)
        i += 1
    return nil
  when :string_interp
    i = 0
    while i < ast_get(node, :parts).size()
      part = ast_get(node, :parts)[i]
      if part[0] != :str
        find_captured_params_in_node(part[1], captures, fn_params)
      i += 1
    return nil
  when :go
    block_ctx = {func: {var_slots: {}, params: fn_params}}
    merge_capture_names(captures, find_captures({params: [], body: ast_get(node, :body)}, block_ctx))
    if fn_params.include?("__self") && !captures.include?("__self")
      captures.push("__self")
    merge_capture_names(captures, find_captured_params_in_body(ast_get(node, :body), fn_params))
    return nil
  else
    nil

-> find_vars_in_body(body, captures, block_params, outer_vars, fn_params)
  if body == nil
    return nil
  i = 0
  while i < body.size()
    find_vars_in_node(body[i], captures, block_params, outer_vars, fn_params)
    i += 1

-> is_outer_var(name, outer_vars, fn_params)
  if outer_vars[name] != nil
    return true
  i = 0
  while i < fn_params.size()
    if fn_params[i] == name
      return true
    i += 1
  false

-> find_vars_in_node(node, captures, block_params, outer_vars, fn_params)
  if node == nil
    return nil
  t = ast_kind(node)
  case t
  when :var
    name = ast_get(node, :name)
    if is_outer_var(name, outer_vars, fn_params) && block_params[name] == nil && !captures.include?(name)
      captures.push(name)
    return nil
  when :parg
    # `@N` denotes the enclosing method's Nth argument (the param named
    # `__argN`) — never a block parameter. Capture it into the closure so the
    # reference resolves to the method's arg from inside the block body.
    name = "__arg" + ast_get(node, :index).to_s()
    if is_outer_var(name, outer_vars, fn_params) && block_params[name] == nil && !captures.include?(name)
      captures.push(name)
    return nil
  when :assign
    find_vars_in_node(ast_get(node, :value), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :target) != nil
      find_vars_in_node(ast_get(node, :target), captures, block_params, outer_vars, fn_params)
    return nil
  when :compound_assign
    find_vars_in_node(ast_get(node, :value), captures, block_params, outer_vars, fn_params)
    # Also check the target variable
    if ast_get(node, :target) != nil
      find_vars_in_node(ast_get(node, :target), captures, block_params, outer_vars, fn_params)
    return nil
  when :binary_op
    find_vars_in_node(ast_get(node, :left), captures, block_params, outer_vars, fn_params)
    find_vars_in_node(ast_get(node, :right), captures, block_params, outer_vars, fn_params)
    return nil
  when :call
    if ast_get(node, :receiver) == nil
      # Local closures use ordinary call syntax (`callback(item)`). Capture
      # the callee itself as well as the call arguments.
      name = ast_get(node, :name)
      if is_outer_var(name, outer_vars, fn_params) && block_params[name] == nil && !captures.include?(name)
        captures.push(name)
    else
      find_vars_in_node(ast_get(node, :receiver), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :args) != nil
      i = 0
      while i < ast_get(node, :args).size()
        find_vars_in_node(ast_get(node, :args)[i], captures, block_params, outer_vars, fn_params)
        i += 1
    if ast_get(node, :block) != nil
      find_vars_in_body(ast_get(ast_get(node, :block), :body), captures, block_params, outer_vars, fn_params)
    return nil
  when :puts
    vals = ast_get(node, :value)
    if vals != nil
      i = 0
      while i < vals.size()
        find_vars_in_node(vals[i], captures, block_params, outer_vars, fn_params)
        i += 1
    return nil
  when :print
    find_vars_in_node(ast_get(node, :value), captures, block_params, outer_vars, fn_params)
    return nil
  when :if
    find_vars_in_node(ast_get(node, :condition), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :then_body) != nil
      find_vars_in_body(ast_get(node, :then_body), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :elsif_clauses) != nil
      i = 0
      while i < ast_get(node, :elsif_clauses).size()
        clause = ast_get(node, :elsif_clauses)[i]
        find_vars_in_node(clause[0], captures, block_params, outer_vars, fn_params)
        find_vars_in_body(clause[1], captures, block_params, outer_vars, fn_params)
        i += 1
    if ast_get(node, :else_body) != nil
      find_vars_in_body(ast_get(node, :else_body), captures, block_params, outer_vars, fn_params)
    return nil
  when :return
    find_vars_in_node(ast_get(node, :value), captures, block_params, outer_vars, fn_params)
    return nil
  when :unary_op
    find_vars_in_node(ast_get(node, :operand), captures, block_params, outer_vars, fn_params)
    return nil
  when :and, :or
    find_vars_in_node(ast_get(node, :left), captures, block_params, outer_vars, fn_params)
    find_vars_in_node(ast_get(node, :right), captures, block_params, outer_vars, fn_params)
    return nil
  when :not
    find_vars_in_node(ast_get(node, :operand), captures, block_params, outer_vars, fn_params)
    return nil
  when :string_interp
    i = 0
    while i < ast_get(node, :parts).size()
      part = ast_get(node, :parts)[i]
      if part[0] != :str
        find_vars_in_node(part[1], captures, block_params, outer_vars, fn_params)
      i += 1
    return nil
  when :while
    find_vars_in_node(ast_get(node, :condition), captures, block_params, outer_vars, fn_params)
    find_vars_in_body(ast_get(node, :body), captures, block_params, outer_vars, fn_params)
    return nil
  when :go
    find_vars_in_body(ast_get(node, :body), captures, block_params, outer_vars, fn_params)
    return nil
  when :case
    if ast_get(node, :whens) != nil
      i = 0
      while i < ast_get(node, :whens).size()
        w = ast_get(node, :whens)[i]
        ci = 0
        while ci < ast_get(w, :conditions).size()
          find_vars_in_node(ast_get(w, :conditions)[ci], captures, block_params, outer_vars, fn_params)
          ci += 1
        find_vars_in_body(ast_get(w, :body), captures, block_params, outer_vars, fn_params)
        i += 1
    if ast_get(node, :else_body) != nil
      find_vars_in_body(ast_get(node, :else_body), captures, block_params, outer_vars, fn_params)
    return nil
  when :case_value
    find_vars_in_node(ast_get(node, :subject), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :arms) != nil
      i = 0
      while i < ast_get(node, :arms).size()
        arm = ast_get(node, :arms)[i]
        find_vars_in_node(ast_get(arm, :pattern), captures, block_params, outer_vars, fn_params)
        if ast_get(arm, :guard) != nil
          find_vars_in_node(ast_get(arm, :guard), captures, block_params, outer_vars, fn_params)
        find_vars_in_body(ast_get(arm, :body), captures, block_params, outer_vars, fn_params)
        i += 1
    if ast_get(node, :else_body) != nil
      find_vars_in_body(ast_get(node, :else_body), captures, block_params, outer_vars, fn_params)
    return nil
  when :begin
    find_vars_in_body(ast_get(node, :body), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :rescue_body) != nil
      find_vars_in_body(ast_get(node, :rescue_body), captures, block_params, outer_vars, fn_params)
    if ast_get(node, :ensure_body) != nil
      find_vars_in_body(ast_get(node, :ensure_body), captures, block_params, outer_vars, fn_params)
    return nil
  when :array
    if ast_get(node, :elements) != nil
      i = 0
      while i < ast_get(node, :elements).size()
        find_vars_in_node(ast_get(node, :elements)[i], captures, block_params, outer_vars, fn_params)
        i += 1
    return nil
  when :hash_literal
    if ast_get(node, :entries) != nil
      i = 0
      while i < ast_get(node, :entries).size()
        entry = ast_get(node, :entries)[i]
        find_vars_in_node(entry[0], captures, block_params, outer_vars, fn_params)
        find_vars_in_node(entry[1], captures, block_params, outer_vars, fn_params)
        i += 1
    return nil
  when :ivar
    return nil
  else
    nil

-> lower_block_free_vars(block, ctx)
  # Collect variables referenced in block body that are NOT in any outer scope.
  # These become implicit block params (ordered by first appearance).
  vars = []
  seen = {}
  outer_vars = ctx[:func][:var_slots]
  params = ctx[:func][:params]
  known_calls = ctx[:mod][:known_calls]
  collect_free_vars_in_body(ast_get(block, :body), vars, seen, outer_vars, params, known_calls, ctx[:bindings])
  vars

-> collect_free_vars_in_body(body, vars, seen, outer_vars, params, known_calls, bindings)
  if body == nil
    return nil
  i = 0
  while i < body.size()
    collect_free_vars_in_node(body[i], vars, seen, outer_vars, params, known_calls, bindings)
    i += 1

-> collect_free_vars_in_node(node, vars, seen, outer_vars, params, known_calls, bindings)
  if node == nil
    return nil
  t = ast_kind(node)
  case t
  when :var
    name = ast_get(node, :name)
    # Free if not seen, not in outer scope, not a param, not a known function,
    # not a binding. `item` is special: in a zero-param block it is ALWAYS the
    # implicit element param, even when an outer `item` slot exists (an earlier
    # inlined iterator leaks its loop var into var_slots — without this, the
    # block silently captures the stale value: [60,60,60] instead of [20,40,60]).
    if seen[name] == nil && (name == "item" || outer_vars[name] == nil) && !params.include?(name) && known_calls[name] == nil && bindings[name] == nil
      # Skip constants (uppercase first letter) and class names
      ch = name.slice(0, 1)
      if ch != nil && ch >= "a" && ch <= "z"
        seen[name] = true
        vars.push(name)
    return nil
  when :assign
    # Mark LHS as seen (defined in block scope, not a free var)
    if ast_get(node, :target) != nil && ast_kind(ast_get(node, :target)) == :var
      seen[ast_get(ast_get(node, :target), :name)] = true
    collect_free_vars_in_node(ast_get(node, :value), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :compound_assign
    # Compound assignment updates an existing binding; the target is never an
    # implicit block parameter, but the RHS may still reference one.
    if ast_get(node, :target) != nil && ast_kind(ast_get(node, :target)) == :var
      seen[ast_get(ast_get(node, :target), :name)] = true
    elsif ast_get(node, :target) != nil
      collect_free_vars_in_node(ast_get(node, :target), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_node(ast_get(node, :value), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :binary_op
    collect_free_vars_in_node(ast_get(node, :left), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_node(ast_get(node, :right), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :range
    collect_free_vars_in_node(ast_get(node, :from), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_node(ast_get(node, :to), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :call
    if ast_get(node, :receiver) != nil
      collect_free_vars_in_node(ast_get(node, :receiver), vars, seen, outer_vars, params, known_calls, bindings)
    if ast_get(node, :args) != nil
      i = 0
      while i < ast_get(node, :args).size()
        collect_free_vars_in_node(ast_get(node, :args)[i], vars, seen, outer_vars, params, known_calls, bindings)
        i += 1
    return nil
  when :puts
    vals = ast_get(node, :value)
    if vals != nil
      i = 0
      while i < vals.size()
        collect_free_vars_in_node(vals[i], vars, seen, outer_vars, params, known_calls, bindings)
        i += 1
    return nil
  when :print
    collect_free_vars_in_node(ast_get(node, :value), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :yield
    if ast_get(node, :args) != nil
      i = 0
      while i < ast_get(node, :args).size()
        collect_free_vars_in_node(ast_get(node, :args)[i], vars, seen, outer_vars, params, known_calls, bindings)
        i += 1
    return nil
  when :return
    collect_free_vars_in_node(ast_get(node, :value), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :passthrough
    collect_free_vars_in_node(ast_get(node, :expression), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_node(ast_get(node, :value), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :view_field
    return nil
  when :if
    collect_free_vars_in_node(ast_get(node, :condition), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_body(ast_get(node, :then_body), vars, seen, outer_vars, params, known_calls, bindings)
    if ast_get(node, :else_body) != nil
      collect_free_vars_in_body(ast_get(node, :else_body), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :unary_op
    collect_free_vars_in_node(ast_get(node, :operand), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :not
    collect_free_vars_in_node(ast_get(node, :operand), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :and, :or
    collect_free_vars_in_node(ast_get(node, :left), vars, seen, outer_vars, params, known_calls, bindings)
    collect_free_vars_in_node(ast_get(node, :right), vars, seen, outer_vars, params, known_calls, bindings)
    return nil
  when :string_interp
    i = 0
    while i < ast_get(node, :parts).size()
      part = ast_get(node, :parts)[i]
      if part[0] != :str
        collect_free_vars_in_node(part[1], vars, seen, outer_vars, params, known_calls, bindings)
      i += 1
    return nil
  else
    nil

-> lower_block_closure(ctx, block, expected_param_types = nil)
  mod = ctx[:mod]
  wfn = ctx[:func]

  # Guard: block must be a hash (not a WObject, bool, or nil)
  if !is_ast_node?(block)
    return typed_value(:i64, w_nil.to_s())

  # Find captured variables from outer scope
  captures = find_captures(block, ctx)
  inherited_yield_block_name = ctx[:yield_block_name]
  if inherited_yield_block_name != nil && !captures.include?(inherited_yield_block_name)
    captures.push(inherited_yield_block_name)
  uses_block_return = has_nonlocal_block_return_in_node(block.body, true)
  if uses_block_return && ctx[:block_return_frame] != nil && !captures.include?("__block_return_frame")
    captures.push("__block_return_frame")
  if ctx[:class_name] != nil && !captures.include?("__self")
    has_self = wfn[:var_slots]["__self"] != nil || wfn[:params].include?("__self")
    if has_self
      captures.push("__self")

  # Generate block function name
  block_id = mod[:next_block]
  mod[:next_block] = block_id + 1
  fn_name = "__block_" + block_id.to_s()

  # Block params — if none declared, auto-bind free variables by order of appearance.
  # `@N` positional refs are NOT block params: they always denote the enclosing
  # method's Nth argument (`__argN`), captured by find_captures above.
  block_params = []
  if block.params.size() == 0
    block_params = lower_block_free_vars(block, ctx)
  else
    i = 0
    while i < block.params.size()
      block_params.push(block.params[i])
      i += 1

  # Params shadow captures. find_captures sees an outer slot named like a
  # block param (an earlier inlined iterator leaks its loop var, e.g. `item`)
  # and lists it as a capture — and the capture load would then CLOBBER the
  # param's slot binding, so the block body read the stale outer value
  # instead of its own argument. A name that is a param is never a capture.
  if captures.size() > 0 && block_params.size() > 0
    kept = []
    ci = 0
    while ci < captures.size()
      if !block_params.include?(captures[ci])
        kept.push(captures[ci])
      ci += 1
    captures = kept

  # Build block function: ptr %__captures first, then i64 params
  captures_extra = [{type: "ptr", name: "%__captures"}]
  new_fn = build_function(fn_name, block_params, "i64", false, captures_extra)
  new_fn[:source_kind] = :block
  new_fn[:source_method] = ctx[:method_name]
  new_fn[:source_class] = ctx[:class_name]
  new_fn[:source_path] = ctx[:source_path]
  new_fn[:source_line] = block.line
  mod[:functions].push(new_fn)

  # In block function: load captured variables from captures array
  ci = 0
  while ci < captures.size()
    cap_name = captures[ci]
    gep_temp = next_temp(new_fn)
    emit_instruction(new_fn, {op: :gep_array, temp: gep_temp, base: "%__captures", count: captures.size(), index: ci})
    load_temp = next_temp(new_fn)
    emit_instruction(new_fn, {op: :load_ptr, temp: load_temp, ptr: gep_temp})
    cap_ptr = next_temp(new_fn)
    emit_instruction(new_fn, {op: :i64_to_ptr, temp: cap_ptr, value: load_temp})
    new_fn[:var_slots][cap_name] = cap_ptr
    ci += 1

  # Child context for block body
  child_var_types = {}
  # Inherit type info for captured variables
  ci = 0
  while ci < captures.size()
    cap_name = captures[ci]
    if ctx[:var_types][cap_name] != nil
      child_var_types[cap_name] = ctx[:var_types][cap_name]
    ci += 1
  if expected_param_types != nil
    pi = 0
    while pi < block_params.size() && pi < expected_param_types.size()
      expected_t = expected_param_types[pi]
      if expected_t != nil
        pname = block_params[pi]
        if is_ast_node?(pname)
          pname = param_runtime_name(pname)
        child_var_types[pname] = normalize_type_symbol(expected_t)
      pi += 1

  child_ctx = {
    mod: mod,
    func: new_fn,
    var_types: child_var_types,
    class_name: ctx[:class_name],
    source_path: ctx[:source_path],
    method_name: ctx[:method_name],
    bindings: {},
    unboxed_vars: {},
    verbose: ctx[:verbose],
    is_class_method: ctx[:is_class_method],
    is_block: true,
    block_return_frame: nil,
    yield_block_name: inherited_yield_block_name
  }

  if uses_block_return && captures.include?("__block_return_frame")
    child_ctx[:block_return_frame] = "__block_return_frame"

  # Pre-scan body for parameter reassignment
  body = block.body
  child_ctx[:raw_int_candidates] = raw_int_candidate_map(body, child_var_types)
  reassigned = find_reassigned_params(body, block_params)
  pi = 0
  while pi < reassigned.size()
    pname = reassigned[pi]
    ptr = ensure_var_slot(new_fn, pname)
    emit_instruction(new_fn, {op: :store_i64, value: "%" + pname, ptr: ptr})
    pi += 1

  # Lower block body with implicit return for last expression
  if body != nil && body.size() > 0
    i = 0
    while i < body.size() - 1
      if block_terminated(new_fn)
        break
      lower_statement(child_ctx, body[i])
      i += 1

    if !block_terminated(new_fn)
      last = body[body.size() - 1]
      last_t = ast_kind(last)
      is_if_stmt = last_t == :if && (last.else_body == nil || last.else_body.size() == 0) && (last.elsif_clauses == nil || last.elsif_clauses.size() == 0)
      if last_t in (:puts :print :while :method_def :fn_def :begin :raise) || is_if_stmt
        lower_statement(child_ctx, last)
      elsif last_t == :return
        lower_statement(child_ctx, last)
      else
        result = lower_expression(child_ctx, last)
        result_reg = ensure_i64_value(new_fn, result)
        emit_instruction(new_fn, {op: :ret_i64, value: result_reg})

  finalize_function(new_fn)

  # Back in caller context: create closure with captures
  if captures.size() > 0
    # Allocate capture array on stack
    arr_ptr = next_temp(wfn)
    emit_instruction(wfn, {op: :alloca_array, ptr: arr_ptr, count: captures.size()})
    # Store each captured variable's value into the array
    ci = 0
    while ci < captures.size()
      cap_name = captures[ci]
      cap_slot = wfn[:var_slots][cap_name]
      if cap_slot == nil
        raw_type = ctx[:var_types][cap_name]
        cap_store = nil
        if cap_name == "__block_return_frame" && ctx[:block_return_frame] != nil
          cap_store = ctx[:block_return_frame]
        elsif ctx[:bindings][cap_name] != nil
          if is_raw_int_storage_type(raw_type)
            cap_store = ensure_raw_machine_int(wfn, typed_value(:i64, ctx[:bindings][cap_name]), raw_type, raw_type)
          elsif is_machine_float_type(raw_type)
            if raw_type in (:f32 :raw_f32)
              cap_store = ensure_raw_f32(wfn, typed_value(raw_float_value_type(raw_type), ctx[:bindings][cap_name]))
            else
              cap_store = ensure_raw_f64(wfn, typed_value(raw_float_value_type(raw_type), ctx[:bindings][cap_name]))
          else
            cap_store = ctx[:bindings][cap_name]
        else
          cap_val = lower_var(ctx, Tungsten:AST:Var.new(cap_name))
          if is_raw_int_storage_type(raw_type)
            cap_store = ensure_raw_machine_int(wfn, cap_val, raw_type, raw_type)
          elsif is_machine_float_type(raw_type)
            if raw_type in (:f32 :raw_f32)
              cap_store = ensure_raw_f32(wfn, cap_val)
            else
              cap_store = ensure_raw_f64(wfn, cap_val)
          else
            cap_store = ensure_i64_value(wfn, cap_val)
        slot_type = "i64"
        if is_raw_int_storage_type(raw_type)
          slot_type = machine_slot_type(raw_type)
        elsif is_machine_float_type(raw_type)
          slot_type = float_slot_type(raw_type)
        cap_slot = ensure_var_slot(wfn, cap_name, slot_type)
        store_op = :store_i64
        if is_raw_int_storage_type(raw_type)
          store_op = machine_store_op(raw_type)
        elsif is_machine_float_type(raw_type)
          store_op = float_store_op(raw_type)
        emit_instruction(wfn, {op: store_op, value: cap_store, ptr: cap_slot})
      cap_bits = next_temp(wfn)
      emit_instruction(wfn, {op: :ptr_to_i64, temp: cap_bits, value: cap_slot})
      gep_reg = next_temp(wfn)
      emit_instruction(wfn, {op: :gep_array, temp: gep_reg, base: arr_ptr, count: captures.size(), index: ci})
      emit_instruction(wfn, {op: :store_ptr, value: cap_bits, dest: gep_reg})
      ci += 1
    cap_ptr = arr_ptr
  else
    cap_ptr = next_temp(wfn)
    emit_instruction(wfn, {op: :null_ptr, temp: cap_ptr})

  closure = next_temp(wfn)
  emit_instruction(wfn, {op: :closure_new, temp: closure, fn_name: fn_name, captures_ptr: cap_ptr, capture_count: captures.size()})
  typed_value(:i64, closure)
