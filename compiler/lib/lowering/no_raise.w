# Lowering / no_raise — closed-world may-raise summaries.
#
# This is a deliberately small effect analysis, not a general effect system.
# It proves only the cases needed to remove redundant rescue setup and to
# propagate `cannot raise` through direct function/method SCCs. Any dynamic or
# unclassified operation stays may-raise. `## no_raise` on a definition is an
# executable-owner promise and acts as a trusted seed, matching Tungsten's
# developer-chosen closed-world contracts.

-> definition_declares_no_raise?(node)
  hints = ast_get(node, :type_hints)
  hints != nil && hints["__function_no_raise"] == :no_raise

-> no_raise_safe_bare_builtin?(name)
  name in ("clock" "argv" "wvalue_bits" "wvalue_from_bits" "runtime_identity" "flush")

-> no_raise_seed_var_types(node)
  types = {}
  hints = ast_get(node, :type_hints)
  if hints != nil
    hint_keys = hints.keys()
    hi = 0
    while hi < hint_keys.size()
      name = hint_keys[hi]
      if name != "__function_no_raise"
        types[name] = normalize_type_symbol(hints[name])
      hi += 1
  if node.param_types != nil && node.params != nil
    i = 0
    while i < node.param_types.size() && i < node.params.size()
      types[param_runtime_name(node.params[i])] = canonical_signature_type(node.param_types[i])
      i += 1
  enrich_int_locals(node.body, types)

-> no_raise_add_worker_dependencies(mod, workers, dependencies)
  if workers == nil || workers.size() == 0
    return false
  i = 0
  while i < workers.size()
    key = mod[:return_class_set_workers][workers[i]]
    if key == nil
      return false
    dependencies[key] = true
    i += 1
  true

-> no_raise_call_safe?(mod, node, class_name, var_types, dependencies)
  if node.receiver != nil && !no_raise_node_safe?(mod, node.receiver, class_name, var_types, dependencies)
    return false
  if node.args != nil
    i = 0
    while i < node.args.size()
      if !no_raise_node_safe?(mod, node.args[i], class_name, var_types, dependencies)
        return false
      i += 1

  if node.receiver != nil && ast_kind(node.receiver) == :class_ref && node.receiver.name == "Tungsten" && node.name in ("PROTECT_THE_CORE!" "STOP_THE_PRESS!" "LOCK_THE_DOORS!")
    return true

  ctor_ctx = {mod: mod, class_name: class_name}
  ctor = class_set_ctor_name(ctor_ctx, node)
  if ctor != nil
    constructor_worker = mod[:class_constructor_fn_names][ctor + ".new/" + node.args.size().to_s()]
    if constructor_worker == nil
      return true
    return no_raise_add_worker_dependencies(mod, [constructor_worker], dependencies)

  receiver_fact = nil
  recv = node.receiver
  if recv != nil && ast_kind(recv) == :self_ref && class_name != nil
    receiver_fact = class_set_compatible(class_name, true)
  elsif recv != nil && ast_kind(recv) == :call
    recv_ctor = class_set_ctor_name(ctor_ctx, recv)
    if recv_ctor != nil
      receiver_fact = class_set_exact_one(recv_ctor)
  workers = return_class_call_worker_keys(mod, node, class_name, receiver_fact)
  if workers.size() > 0
    return no_raise_add_worker_dependencies(mod, workers, dependencies)

  if node.receiver == nil && no_raise_safe_bare_builtin?(node.name)
    return true
  false

-> no_raise_binary_safe?(mod, node, class_name, var_types, dependencies)
  if !no_raise_node_safe?(mod, node.left, class_name, var_types, dependencies) || !no_raise_node_safe?(mod, node.right, class_name, var_types, dependencies)
    return false
  lt = normalize_type_symbol(infer_type(node.left, var_types, mod[:fn_return_types], lowering_infer_maps))
  rt = normalize_type_symbol(infer_type(node.right, var_types, mod[:fn_return_types], lowering_infer_maps))
  if is_integer_like_type(lt) && is_integer_like_type(rt)
    # Integer division/remainder can raise on zero. Add/sub/mul, comparisons,
    # and bit operations are total over Tungsten integers (overflow promotes).
    return !(node.op in (:SLASH :PERCENT))
  if (lt in (:float :f64)) && (rt in (:float :f64))
    # IEEE float division produces infinities/NaN; it is not a language raise.
    return true
  false

-> no_raise_node_safe?(mod, node, class_name, var_types, dependencies)
  if node == nil
    return true
  if type(node) == "Array"
    i = 0
    while i < node.size()
      if !no_raise_node_safe?(mod, node[i], class_name, var_types, dependencies)
        return false
      i += 1
    return true
  if !is_ast_node?(node)
    return true
  kind = ast_kind(node)
  if kind == :raise
    return false
  if kind == :call
    return no_raise_call_safe?(mod, node, class_name, var_types, dependencies)
  if kind == :binary_op
    return no_raise_binary_safe?(mod, node, class_name, var_types, dependencies)
  if kind == :compound_assign
    synthetic = Tungsten:AST:BinaryOp.new(node.target, node.op, node.value)
    return no_raise_binary_safe?(mod, synthetic, class_name, var_types, dependencies)
  if kind == :assign
    safe = no_raise_node_safe?(mod, node.value, class_name, var_types, dependencies)
    if safe && node.target != nil && ast_kind(node.target) == :var
      inferred = infer_type(node.value, var_types, mod[:fn_return_types], lowering_infer_maps)
      if inferred != nil
        var_types[node.target.name] = normalize_type_symbol(inferred)
    return safe
  if kind == :begin
    # A real rescue consumes every raise from its try body. The rescue and
    # ensure bodies execute outside that protection and must prove safe.
    has_rescue = node.rescue_body != nil || node.rescue_var != nil
    if !has_rescue && !no_raise_node_safe?(mod, node.body, class_name, class_set_copy_env(var_types), dependencies)
      return false
    if !no_raise_node_safe?(mod, node.rescue_body, class_name, class_set_copy_env(var_types), dependencies)
      return false
    return no_raise_node_safe?(mod, node.ensure_body, class_name, class_set_copy_env(var_types), dependencies)
  if kind == :rescue_expr
    # The guarded expression cannot escape through raise; only the fallback's
    # effects can make the enclosing function raise.
    return no_raise_node_safe?(mod, node.fallback, class_name, class_set_copy_env(var_types), dependencies)
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :block)
    return true
  children = ast_children(node)
  i = 0
  while i < children.size()
    if !no_raise_node_safe?(mod, children[i], class_name, var_types, dependencies)
      return false
    i += 1
  true

-> infer_no_raise_fixed_point(mod, expressions, ordered_class_exprs)
  if mod[:method_tables_locked] != true
    return nil
  collected = collect_return_class_definitions(mod, expressions, ordered_class_exprs)
  definitions = collected[:definitions]
  keys = definitions.keys()
  candidates = {}
  dependencies_by_key = {}
  promised = {}
  i = 0
  while i < keys.size()
    key = keys[i]
    definition = definitions[key]
    node = definition[:node]
    if definition_declares_no_raise?(node)
      candidates[key] = true
      promised[key] = true
      dependencies_by_key[key] = {}
    else
      dependencies = {}
      candidates[key] = no_raise_node_safe?(mod, node.body, definition[:class_name], no_raise_seed_var_types(node), dependencies)
      dependencies_by_key[key] = dependencies
    i += 1

  # Greatest fixed point: a recursive SCC whose local operations are total
  # remains no-raise; one may-raise member invalidates its callers until the
  # graph converges.
  changed = true
  while changed
    changed = false
    i = 0
    while i < keys.size()
      key = keys[i]
      if candidates[key] == true && promised[key] != true
        deps = dependencies_by_key[key].keys()
        di = 0
        while di < deps.size()
          if candidates[deps[di]] != true
            candidates[key] = false
            changed = true
            break
          di += 1
      i += 1

  result = {}
  worker_names = collected[:workers].keys()
  i = 0
  while i < worker_names.size()
    worker = worker_names[i]
    canonical = collected[:workers][worker]
    if candidates[canonical] == true
      result[worker] = true
    i += 1
  mod[:no_raise_workers] = result
  nil

-> body_cannot_raise?(ctx, body)
  dependencies = {}
  types = class_set_copy_env(ctx[:var_types])
  if !no_raise_node_safe?(ctx[:mod], body, ctx[:class_name], types, dependencies)
    return false
  deps = dependencies.keys()
  i = 0
  while i < deps.size()
    if ctx[:mod][:no_raise_workers][deps[i]] != true
      return false
    i += 1
  true
