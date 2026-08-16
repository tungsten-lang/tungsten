# Lowering / class_sets — bounded flow-sensitive source-class facts.
#
# This is deliberately an optimizer analysis, not a surface algebraic type
# system.  Before a lexical body is lowered, it interprets that body's control
# flow over a small abstract domain:
#
#   unknown | exact {C...} | compatible C
#
# Exact sets are capped at four classes.  Larger unions widen to their nearest
# common source superclass (when one exists), otherwise to unknown.  The pass
# records the receiver fact at each source call node; lowering consumes those
# facts only after LOCK_THE_DOORS has made method resolution permanent.
#
# Keeping this pass before WIRE construction matters: a closed-world call can
# be emitted without ever materializing its method-name string or IC slot.
# The transfer functions still follow CFG semantics (branch joins and loop
# fixed points); they simply operate on the AST while source-local identity is
# available instead of reconstructing it from load/store WIRE afterwards.

-> class_set_unknown
  {certainty: :unknown}

-> class_set_exact_one(class_name)
  {certainty: :exact, class_name: class_name, classes: [class_name], stable: true}

-> class_set_compatible(class_name, stable = false)
  {certainty: :compatible, class_name: class_name, stable: stable}

-> class_set_unknown?(fact)
  fact == nil || fact[:certainty] == :unknown

-> class_set_copy_env(env)
  out = {}
  if env == nil
    return out
  keys = env.keys()
  i = 0
  while i < keys.size()
    out[keys[i]] = env[keys[i]]
    i += 1
  out

-> class_set_is_descendant_or_same?(mod, child, parent)
  current = child
  guard = 0
  while current != nil && guard < 64
    if current == parent
      return true
    current = mod[:class_super_names][current]
    guard += 1
  false

-> class_set_common_ancestor(mod, classes)
  if classes == nil || classes.size() == 0
    return nil
  candidate = classes[0]
  guard = 0
  while candidate != nil && guard < 64
    all_match = true
    i = 1
    while i < classes.size()
      if !class_set_is_descendant_or_same?(mod, classes[i], candidate)
        all_match = false
        break
      i += 1
    if all_match && normal_source_instance_class?(mod, candidate)
      return candidate
    candidate = mod[:class_super_names][candidate]
    guard += 1
  nil

-> class_set_exact_many(mod, classes)
  seen = {}
  unique = []
  i = 0
  while i < classes.size()
    name = classes[i]
    if name != nil && seen[name] != true
      seen[name] = true
      unique.push(name)
    i += 1
  unique = unique.sort()
  if unique.size() == 0
    return class_set_unknown()
  if unique.size() > 4
    base = class_set_common_ancestor(mod, unique)
    if base != nil
      # Widening a closed set loses precision, not provenance: every member
      # still came from an exact constructor fact.
      return class_set_compatible(base, true)
    return class_set_unknown()
  fact = {certainty: :exact, classes: unique, stable: true}
  if unique.size() == 1
    fact[:class_name] = unique[0]
  fact

-> class_set_fact_classes(fact)
  if fact == nil || fact[:certainty] != :exact
    return []
  classes = fact[:classes]
  if classes != nil
    return classes
  if fact[:class_name] != nil
    return [fact[:class_name]]
  []

-> class_set_concat(left, right)
  out = []
  i = 0
  while i < left.size()
    out.push(left[i])
    i += 1
  i = 0
  while i < right.size()
    out.push(right[i])
    i += 1
  out

-> class_set_join(mod, left, right)
  if class_set_unknown?(left) || class_set_unknown?(right)
    return class_set_unknown()
  lc = left[:certainty]
  rc = right[:certainty]
  if lc == :exact && rc == :exact
    return class_set_exact_many(mod, class_set_concat(class_set_fact_classes(left), class_set_fact_classes(right)))

  # compatible A joined with exact descendants of A stays compatible A.
  if lc == :compatible && rc == :exact
    rclasses = class_set_fact_classes(right)
    i = 0
    while i < rclasses.size()
      if !class_set_is_descendant_or_same?(mod, rclasses[i], left[:class_name])
        names = class_set_concat(rclasses, [left[:class_name]])
        base = class_set_common_ancestor(mod, names)
        return base == nil ? class_set_unknown() : class_set_compatible(base, left[:stable] == true && right[:stable] == true)
      i += 1
    return left
  if lc == :exact && rc == :compatible
    return class_set_join(mod, right, left)
  if lc == :compatible && rc == :compatible
    if class_set_is_descendant_or_same?(mod, left[:class_name], right[:class_name])
      return class_set_compatible(right[:class_name], left[:stable] == true && right[:stable] == true)
    if class_set_is_descendant_or_same?(mod, right[:class_name], left[:class_name])
      return class_set_compatible(left[:class_name], left[:stable] == true && right[:stable] == true)
    base = class_set_common_ancestor(mod, [left[:class_name], right[:class_name]])
    return base == nil ? class_set_unknown() : class_set_compatible(base, left[:stable] == true && right[:stable] == true)
  class_set_unknown()

-> class_set_fact_equal?(left, right)
  if class_set_unknown?(left)
    return class_set_unknown?(right)
  if class_set_unknown?(right) || left[:certainty] != right[:certainty]
    return false
  if left[:certainty] == :compatible
    return left[:class_name] == right[:class_name] && left[:stable] == right[:stable]
  lc = class_set_fact_classes(left)
  rc = class_set_fact_classes(right)
  if lc.size() != rc.size()
    return false
  i = 0
  while i < lc.size()
    if lc[i] != rc[i]
      return false
    i += 1
  true

-> class_set_env_equal?(left, right)
  lkeys = left.keys().sort()
  rkeys = right.keys().sort()
  if lkeys.size() != rkeys.size()
    return false
  i = 0
  while i < lkeys.size()
    if lkeys[i] != rkeys[i] || !class_set_fact_equal?(left[lkeys[i]], right[rkeys[i]])
      return false
    i += 1
  true

# -- Return class-set summaries ------------------------------------------------
#
# Scalar return inference answers "which representation?". These summaries
# answer the orthogonal dispatch question "which source classes can this call
# return?". Keys are native worker symbols, which makes inherited and reopened
# methods line up with the exact implementation selected by the locked method
# tables. Unknown evidence poisons a summary; an unresolved edge within the
# SCC is temporarily ignored so a concrete base case can seed recursion.

-> return_class_status_known(fact)
  {kind: :known, fact: fact}

-> return_class_status_unknown
  {kind: :unknown}

-> return_class_status_cycle
  {kind: :cycle}

-> return_class_status_join(mod, left, right)
  if left[:kind] == :unknown || right[:kind] == :unknown
    return return_class_status_unknown()
  if left[:kind] == :cycle
    return right
  if right[:kind] == :cycle
    return left
  return_class_status_known(class_set_join(mod, left[:fact], right[:fact]))

-> return_class_summary_add_definition(defs, workers, worker, node, class_name)
  if worker == nil || node == nil || node.body == nil || node.body.size() == 0
    return nil
  defs[worker] = {key: worker, worker: worker, node: node, class_name: class_name}
  workers[worker] = worker
  nil

-> collect_return_class_definitions(mod, expressions, ordered_class_exprs)
  defs = {}
  workers = {}
  i = 0
  while i < expressions.size()
    node = expressions[i]
    if ast_kind(node) in (:fn_def :method_def)
      return_class_summary_add_definition(defs, workers, function_name_for_def(node), node, nil)
    i += 1

  i = 0
  while i < ordered_class_exprs.size()
    class_node = ordered_class_exprs[i]
    cname = class_node.name
    body = mod[:prepared_class_bodies][class_node]
    if body == nil
      body = class_node.body
    if body != nil
      j = 0
      while j < body.size()
        method = body[j]
        if ast_kind(method) == :method_def
          worker = class_method_function_name(cname, method)
          return_class_summary_add_definition(defs, workers, worker, method, cname)
          if method.is_class_method == true && static_method_raw_abi?(method)
            workers[static_method_wrapper_name(cname, method)] = worker
        j += 1
    i += 1
  {definitions: defs, workers: workers}

-> return_class_call_worker_keys(mod, node, class_name, receiver_fact)
  out = []
  if node == nil || ast_kind(node) != :call || node.block != nil
    return out
  argc = node.args == nil ? 0 : node.args.size()
  recv = node.receiver

  # A bare call in a method prefers implicit-self dispatch when that selector
  # exists in the hierarchy, matching lower_call. Otherwise it is a top-level
  # function and known_calls gives its deterministic worker.
  if recv == nil
    if class_name != nil && class_has_instance_method?(mod, class_name, node.name)
      targets = locked_class_set_targets(mod, class_set_compatible(class_name, true), node.name, argc)
      if targets != nil
        ti = 0
        while ti < targets.size()
          out.push(targets[ti][:fn_name])
          ti += 1
        return out
    worker = mod[:known_calls][node.name]
    if worker != nil
      out.push(worker)
    return out

  # Static source call. Constructors are handled by the expression evaluator,
  # before this resolver; a user-defined static `new` still reaches this arm.
  if is_ast_node?(recv) && ast_kind(recv) in (:class_ref :var)
    static_class = resolve_exact_source_class_name(mod, class_name, recv.name)
    if static_class != nil
      info = known_static_method_for(mod, static_class + "." + node.name, argc)
      if info != nil && info[:is_static] == true
        out.push(info[:fn_name])
        if info[:method_fn_name] != nil && info[:method_fn_name] != info[:fn_name]
          out.push(info[:method_fn_name])
        return out

  if receiver_fact == nil || class_set_unknown?(receiver_fact)
    return out
  targets = locked_class_set_targets(mod, receiver_fact, node.name, argc)
  if targets != nil
    ti = 0
    while ti < targets.size()
      out.push(targets[ti][:fn_name])
      ti += 1
  out

-> return_class_summary_for_workers(mod, workers, component)
  if workers == nil || workers.size() == 0
    return return_class_status_unknown()
  joined = nil
  i = 0
  while i < workers.size()
    summary_key = mod[:return_class_set_workers][workers[i]]
    if summary_key == nil
      return return_class_status_unknown()
    summary = mod[:return_class_sets][summary_key]
    status = nil
    if summary != nil
      status = return_class_status_known(summary)
    elsif component != nil && component[summary_key] == true
      status = return_class_status_cycle()
    else
      status = return_class_status_unknown()
    if joined == nil
      joined = status
    else
      joined = return_class_status_join(mod, joined, status)
    i += 1
  if joined == nil
    return return_class_status_unknown()
  joined

-> return_class_expr_status(mod, node, class_name, env, component)
  if node == nil || !is_ast_node?(node)
    return return_class_status_unknown()
  kind = ast_kind(node)
  if kind == :var
    fact = env[node.name]
    return fact == nil ? return_class_status_unknown() : return_class_status_known(fact)
  if kind == :self_ref && class_name != nil
    return return_class_status_known(class_set_compatible(class_name, true))
  if kind == :assign
    status = return_class_expr_status(mod, node.value, class_name, env, component)
    target = node.target
    if target != nil && ast_kind(target) == :var
      if status[:kind] == :known
        env[target.name] = status[:fact]
      else
        env.delete(target.name)
    return status
  if kind == :type_ascription
    return return_class_expr_status(mod, node.expression, class_name, env, component)
  if kind == :call
    receiver_status = return_class_status_unknown()
    if node.receiver != nil
      receiver_status = return_class_expr_status(mod, node.receiver, class_name, env, component)
    if node.args != nil
      ai = 0
      while ai < node.args.size()
        return_class_expr_status(mod, node.args[ai], class_name, env, component)
        ai += 1
    ctor_ctx = {mod: mod, class_name: class_name}
    ctor = class_set_ctor_name(ctor_ctx, node)
    if ctor != nil
      return return_class_status_known(class_set_exact_one(ctor))
    receiver_fact = receiver_status[:kind] == :known ? receiver_status[:fact] : nil
    workers = return_class_call_worker_keys(mod, node, class_name, receiver_fact)
    return return_class_summary_for_workers(mod, workers, component)
  if kind == :if
    statuses = []
    then_env = class_set_copy_env(env)
    statuses.push(return_class_body_value_status(mod, node.then_body, class_name, then_env, component))
    if node.elsif_clauses != nil
      ei = 0
      while ei < node.elsif_clauses.size()
        elsif_env = class_set_copy_env(env)
        statuses.push(return_class_body_value_status(mod, node.elsif_clauses[ei][1], class_name, elsif_env, component))
        ei += 1
    if node.else_body != nil && node.else_body.size() > 0
      else_env = class_set_copy_env(env)
      statuses.push(return_class_body_value_status(mod, node.else_body, class_name, else_env, component))
    else
      statuses.push(return_class_status_unknown())
    joined = statuses[0]
    si = 1
    while si < statuses.size()
      joined = return_class_status_join(mod, joined, statuses[si])
      si += 1
    return joined
  return_class_status_unknown()

-> return_class_body_value_status(mod, body, class_name, env, component)
  if body == nil || body.size() == 0
    return return_class_status_unknown()
  i = 0
  status = return_class_status_unknown()
  while i < body.size()
    node = body[i]
    if ast_kind(node) == :return
      return return_class_expr_status(mod, node.value, class_name, env, component)
    status = return_class_expr_status(mod, node, class_name, env, component)
    i += 1
  status

-> return_class_evidence_add(mod, evidence, status)
  if status[:kind] == :unknown
    evidence[:unknown] = true
  elsif status[:kind] == :known
    if evidence[:fact] == nil
      evidence[:fact] = status[:fact]
    else
      evidence[:fact] = class_set_join(mod, evidence[:fact], status[:fact])
  nil

-> collect_return_class_evidence(mod, node, tail, class_name, env, component, evidence)
  if node == nil || !is_ast_node?(node)
    if tail
      evidence[:unknown] = true
    return nil
  kind = ast_kind(node)
  if kind == :return
    return_class_evidence_add(mod, evidence, return_class_expr_status(mod, node.value, class_name, env, component))
    return nil
  if kind == :if
    return_class_expr_status(mod, node.condition, class_name, env, component)
    branch_envs = []
    then_env = class_set_copy_env(env)
    collect_return_class_body(mod, node.then_body, tail, class_name, then_env, component, evidence)
    branch_envs.push(then_env)
    if node.elsif_clauses != nil
      ei = 0
      while ei < node.elsif_clauses.size()
        elsif_env = class_set_copy_env(env)
        collect_return_class_body(mod, node.elsif_clauses[ei][1], tail, class_name, elsif_env, component, evidence)
        branch_envs.push(elsif_env)
        ei += 1
    if node.else_body != nil && node.else_body.size() > 0
      else_env = class_set_copy_env(env)
      collect_return_class_body(mod, node.else_body, tail, class_name, else_env, component, evidence)
      branch_envs.push(else_env)
    else
      branch_envs.push(class_set_copy_env(env))
      if tail
        evidence[:unknown] = true
    joined_env = class_set_join_envs(mod, branch_envs)
    old_keys = env.keys()
    oi = 0
    while oi < old_keys.size()
      env.delete(old_keys[oi])
      oi += 1
    keys = joined_env.keys()
    ki = 0
    while ki < keys.size()
      env[keys[ki]] = joined_env[keys[ki]]
      ki += 1
    return nil
  if kind == :begin
    collect_return_class_body(mod, node.body, tail, class_name, class_set_copy_env(env), component, evidence)
    if node.rescue_body != nil && node.rescue_body.size() > 0
      collect_return_class_body(mod, node.rescue_body, tail, class_name, class_set_copy_env(env), component, evidence)
    if node.ensure_body != nil
      collect_return_class_body(mod, node.ensure_body, false, class_name, class_set_copy_env(env), component, evidence)
    return nil
  if kind in (:while :with :parallel_with)
    collect_return_class_body(mod, node.body, false, class_name, class_set_copy_env(env), component, evidence)
    if tail
      evidence[:unknown] = true
    return nil
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :block)
    if tail
      evidence[:unknown] = true
    return nil
  status = return_class_expr_status(mod, node, class_name, env, component)
  if tail
    return_class_evidence_add(mod, evidence, status)
  nil

-> collect_return_class_body(mod, body, tail, class_name, env, component, evidence)
  if body == nil || body.size() == 0
    if tail
      evidence[:unknown] = true
    return nil
  i = 0
  while i < body.size()
    collect_return_class_evidence(mod, body[i], tail && i == body.size() - 1, class_name, env, component, evidence)
    i += 1
  nil

-> return_class_seed_env(mod, definition)
  env = {}
  node = definition[:node]
  cname = definition[:class_name]
  if cname != nil && node.is_class_method != true
    env["__self"] = class_set_compatible(cname, true)
  if node.param_types != nil && node.params != nil
    i = 0
    while i < node.param_types.size() && i < node.params.size()
      type_name = resolve_exact_source_class_name(mod, cname, "" + node.param_types[i].to_s())
      if type_name != nil && normal_source_instance_class?(mod, type_name)
        env[param_runtime_name(node.params[i])] = class_set_compatible(type_name)
      i += 1
  env

-> return_class_collect_dependency_calls(mod, node, class_name, dependencies)
  if node == nil || !is_ast_node?(node)
    return nil
  if ast_kind(node) == :call
    receiver_fact = nil
    recv = node.receiver
    if recv != nil && ast_kind(recv) == :self_ref && class_name != nil
      receiver_fact = class_set_compatible(class_name, true)
    elsif recv != nil && ast_kind(recv) == :call
      ctor_ctx = {mod: mod, class_name: class_name}
      ctor = class_set_ctor_name(ctor_ctx, recv)
      if ctor != nil
        receiver_fact = class_set_exact_one(ctor)
    workers = return_class_call_worker_keys(mod, node, class_name, receiver_fact)
    wi = 0
    while wi < workers.size()
      key = mod[:return_class_set_workers][workers[wi]]
      if key != nil
        dependencies[key] = true
      wi += 1
  children = ast_children(node)
  ci = 0
  while ci < children.size()
    return_class_collect_dependency_calls(mod, children[ci], class_name, dependencies)
    ci += 1
  nil

-> return_class_scc_plan(mod, definitions)
  graph = {}
  reverse = {}
  keys = definitions.keys()
  i = 0
  while i < keys.size()
    key = keys[i]
    deps = {}
    definition = definitions[key]
    return_class_collect_dependency_calls(mod, definition[:node], definition[:class_name], deps)
    graph[key] = deps.keys()
    reverse[key] = []
    i += 1
  i = 0
  while i < keys.size()
    from = keys[i]
    edges = graph[from]
    ei = 0
    while ei < edges.size()
      to = edges[ei]
      if reverse[to] == nil
        reverse[to] = []
      reverse[to].push(from)
      ei += 1
    i += 1
  order = []
  seen = {}
  i = 0
  while i < keys.size()
    return_inference_dfs_order(keys[i], graph, seen, order)
    i += 1
  components = []
  seen = {}
  oi = order.size() - 1
  while oi >= 0
    if seen[order[oi]] != true
      component = []
      return_inference_dfs_component(order[oi], reverse, seen, component)
      components.push(component)
    oi -= 1
  out = []
  ci = components.size() - 1
  while ci >= 0
    out.push(components[ci])
    ci -= 1
  out

-> infer_return_class_sets_fixed_point(mod, expressions, ordered_class_exprs)
  if mod[:method_tables_locked] != true
    return nil
  collected = collect_return_class_definitions(mod, expressions, ordered_class_exprs)
  definitions = collected[:definitions]
  mod[:return_class_set_workers] = collected[:workers]
  components = return_class_scc_plan(mod, definitions)
  ci = 0
  while ci < components.size()
    component = components[ci]
    component_set = {}
    i = 0
    while i < component.size()
      component_set[component[i]] = true
      i += 1
    changed = true
    iter = 0
    max_iter = component.size() + 2
    while changed && iter < max_iter
      changed = false
      i = 0
      while i < component.size()
        key = component[i]
        definition = definitions[key]
        evidence = {fact: nil, unknown: false}
        collect_return_class_body(mod, definition[:node].body, true, definition[:class_name], return_class_seed_env(mod, definition), component_set, evidence)
        next_fact = evidence[:unknown] == true ? nil : evidence[:fact]
        if class_set_unknown?(next_fact)
          next_fact = nil
        old_fact = mod[:return_class_sets][key]
        if next_fact != nil && (old_fact == nil || !class_set_fact_equal?(old_fact, next_fact))
          mod[:return_class_sets][key] = next_fact
          changed = true
        i += 1
      iter += 1
    ci += 1
  nil

-> return_class_set_call_fact(ctx, node, receiver_fact)
  workers = return_class_call_worker_keys(ctx[:mod], node, ctx[:class_name], receiver_fact)
  status = return_class_summary_for_workers(ctx[:mod], workers, nil)
  if status[:kind] == :known
    return status[:fact]
  nil

# Join reachable predecessor environments.  Absence from any predecessor is
# unknown, not bottom: a variable assigned on just one arm is not exact after
# the merge.
-> class_set_join_envs(mod, envs)
  if envs == nil || envs.size() == 0
    return {}
  out = {}
  keys = envs[0].keys()
  ki = 0
  while ki < keys.size()
    name = keys[ki]
    fact = envs[0][name]
    present = true
    ei = 1
    while ei < envs.size()
      other = envs[ei][name]
      if other == nil
        present = false
        break
      fact = class_set_join(mod, fact, other)
      if class_set_unknown?(fact)
        present = false
        break
      ei += 1
    if present
      out[name] = fact
    ki += 1
  out

-> class_set_flow(env, reachable = true)
  {env: env, reachable: reachable}

-> class_set_record_call(ctx, node, fact)
  if ctx[:class_set_call_facts] == nil
    ctx[:class_set_call_facts] = {}
  if fact == nil
    fact = class_set_unknown()
  old = ctx[:class_set_call_facts][node]
  if old == nil
    ctx[:class_set_call_facts][node] = fact
  else
    ctx[:class_set_call_facts][node] = class_set_join(ctx[:mod], old, fact)
  nil

-> class_set_ctor_name(ctx, node)
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :call || node.name != "new" || node.block != nil
    return nil
  receiver = node.receiver
  if receiver == nil || !is_ast_node?(receiver) || !(ast_kind(receiver) in (:class_ref :var))
    return nil
  name = resolve_exact_source_class_name(ctx[:mod], ctx[:class_name], receiver.name)
  if name != nil && source_constructor_returns_exact_class?(ctx[:mod], name)
    return name
  nil

-> class_set_assignment_fact(ctx, node, rhs_fact)
  if !class_set_unknown?(rhs_fact)
    return rhs_fact
  hint = ast_get(node, :type_hint)
  if hint != nil
    hinted = resolve_exact_source_class_name(ctx[:mod], ctx[:class_name], "" + hint.to_s())
    if hinted != nil && normal_source_instance_class?(ctx[:mod], hinted)
      return class_set_compatible(hinted)
  class_set_unknown()

# Evaluate an expression for side effects on local facts and return the class
# fact of its value.  Unknown expression forms still visit ordinary AST
# children so nested assignments/calls cannot leave stale facts behind.
-> class_set_eval_expr(ctx, node, env)
  if node == nil || !is_ast_node?(node)
    return class_set_unknown()
  kind = ast_kind(node)
  if kind == :var
    fact = env[node.name]
    return fact == nil ? class_set_unknown() : fact
  if kind == :self_ref && ctx[:class_name] != nil
    return class_set_compatible(ctx[:class_name], true)
  if kind == :assign
    rhs = class_set_eval_expr(ctx, node.value, env)
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      # Only a direct statement assignment has unconditional execution at this
      # point. Nested assignment expressions under short-circuit/safe-nav and
      # other expression-level control flow are conservatively forgotten.
      if ctx[:class_set_direct_assignment] != true
        env.delete(target.name)
      else
        fact = class_set_assignment_fact(ctx, node, rhs)
        if class_set_unknown?(fact)
          env.delete(target.name)
        else
          env[target.name] = fact
    return rhs
  if kind == :compound_assign
    class_set_eval_expr(ctx, node.value, env)
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      env.delete(target.name)
    return class_set_unknown()
  if kind == :multi_assign
    class_set_eval_expr(ctx, node.value, env)
    targets = node.targets
    if targets != nil
      i = 0
      while i < targets.size()
        if targets[i] != nil && is_ast_node?(targets[i]) && ast_kind(targets[i]) == :var
          env.delete(targets[i].name)
        i += 1
    return class_set_unknown()
  if kind == :call
    recv_fact = class_set_unknown()
    if node.receiver != nil
      recv_fact = class_set_eval_expr(ctx, node.receiver, env)
      class_set_record_call(ctx, node, recv_fact)
    args = node.args
    if args != nil
      i = 0
      while i < args.size()
        class_set_eval_expr(ctx, args[i], env)
        i += 1
    # Do not infer facts inside a closure here. Its execution time and capture
    # state differ from the call-expression's evaluation point; the closure's
    # own lowering context receives an independent analysis.
    ctor = class_set_ctor_name(ctx, node)
    if ctor != nil
      return class_set_exact_one(ctor)
    summary = return_class_set_call_fact(ctx, node, recv_fact)
    if summary != nil
      return summary
    return class_set_unknown()
  if kind == :if
    state = class_set_analyze_if(ctx, node, env)
    replacement = state[:env]
    old_keys = env.keys()
    oi = 0
    while oi < old_keys.size()
      env.delete(old_keys[oi])
      oi += 1
    keys = replacement.keys()
    i = 0
    while i < keys.size()
      env[keys[i]] = replacement[keys[i]]
      i += 1
    return class_set_unknown()
  if kind in (:with :parallel_with)
    state = class_set_analyze_with(ctx, node, env)
    replacement = state[:env]
    old_keys = env.keys()
    oi = 0
    while oi < old_keys.size()
      env.delete(old_keys[oi])
      oi += 1
    keys = replacement.keys()
    i = 0
    while i < keys.size()
      env[keys[i]] = replacement[keys[i]]
      i += 1
    return class_set_unknown()

  # Definitions and closures introduce fresh execution contexts.
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :gpu_kernel_def :block)
    return class_set_unknown()
  children = ast_children(node)
  i = 0
  while i < children.size()
    class_set_eval_expr(ctx, children[i], env)
    i += 1
  class_set_unknown()

-> class_set_analyze_if(ctx, node, entry_env)
  cond_env = class_set_copy_env(entry_env)
  class_set_eval_expr(ctx, node.condition, cond_env)
  reachable_envs = []

  then_state = class_set_analyze_body(ctx, node.then_body, class_set_copy_env(cond_env))
  if then_state[:reachable]
    reachable_envs.push(then_state[:env])

  fallthrough = class_set_copy_env(cond_env)
  clauses = node.elsif_clauses
  if clauses != nil
    i = 0
    while i < clauses.size()
      clause_env = class_set_copy_env(fallthrough)
      class_set_eval_expr(ctx, clauses[i][0], clause_env)
      arm_state = class_set_analyze_body(ctx, clauses[i][1], class_set_copy_env(clause_env))
      if arm_state[:reachable]
        reachable_envs.push(arm_state[:env])
      fallthrough = clause_env
      i += 1

  if node.else_body != nil && node.else_body.size() > 0
    else_state = class_set_analyze_body(ctx, node.else_body, fallthrough)
    if else_state[:reachable]
      reachable_envs.push(else_state[:env])
  else
    reachable_envs.push(fallthrough)

  if reachable_envs.size() == 0
    return class_set_flow({}, false)
  class_set_flow(class_set_join_envs(ctx[:mod], reachable_envs), true)

-> class_set_kill_assigned(env, body)
  counts = local_assignment_counts(body)
  keys = counts.keys()
  i = 0
  while i < keys.size()
    env.delete(keys[i])
    i += 1
  env

-> class_set_body_has_loop_transfer?(body)
  if body == nil
    return false
  nodes = body
  if type(nodes) != "Array"
    nodes = [nodes]
  i = 0
  while i < nodes.size()
    node = nodes[i]
    if node != nil && is_ast_node?(node)
      kind = ast_kind(node)
      if kind in (:break :next :redo)
        return true
      if kind == :if
        if class_set_body_has_loop_transfer?(node.then_body) || class_set_body_has_loop_transfer?(node.else_body)
          return true
        clauses = node.elsif_clauses
        if clauses != nil
          ci = 0
          while ci < clauses.size()
            if class_set_body_has_loop_transfer?(clauses[ci][1])
              return true
            ci += 1
      if kind in (:case :case_value)
        arms = ast_get(node, :arms)
        if arms == nil
          arms = ast_get(node, :clauses)
        if arms != nil
          ai = 0
          while ai < arms.size()
            if class_set_body_has_loop_transfer?(ast_get(arms[ai], :body))
              return true
            ai += 1
        if class_set_body_has_loop_transfer?(ast_get(node, :else_body))
          return true
      if !(kind in (:fn_def :method_def :class_def :module_def :trait_def :block))
        children = ast_children(node)
        if class_set_body_has_loop_transfer?(children)
          return true
    i += 1
  false

# A loop with break/next/redo needs edge-specific environments. Until those
# edges are represented explicitly, suppress class-set rewrites for calls in
# that loop. This is conservative and localized: ordinary loops still use the
# fixed point above, and facts outside the loop survive for untouched locals.
-> class_set_mark_calls_unknown(ctx, value)
  if value == nil
    return nil
  if type(value) == "Array"
    i = 0
    while i < value.size()
      class_set_mark_calls_unknown(ctx, value[i])
      i += 1
    return nil
  if !is_ast_node?(value)
    return nil
  kind = ast_kind(value)
  if kind == :call && value.receiver != nil
    if ctx[:class_set_call_facts] == nil
      ctx[:class_set_call_facts] = {}
    ctx[:class_set_call_facts][value] = class_set_unknown()
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :block)
    return nil
  if kind == :if
    class_set_mark_calls_unknown(ctx, value.condition)
    class_set_mark_calls_unknown(ctx, value.then_body)
    class_set_mark_calls_unknown(ctx, value.elsif_clauses)
    class_set_mark_calls_unknown(ctx, value.else_body)
    return nil
  if kind in (:case :case_value)
    class_set_mark_calls_unknown(ctx, ast_get(value, :subject))
    class_set_mark_calls_unknown(ctx, ast_get(value, :arms))
    class_set_mark_calls_unknown(ctx, ast_get(value, :clauses))
    class_set_mark_calls_unknown(ctx, ast_get(value, :else_body))
    return nil
  children = ast_children(value)
  i = 0
  while i < children.size()
    class_set_mark_calls_unknown(ctx, children[i])
    i += 1
  nil

-> class_set_analyze_while(ctx, node, entry_env)
  header = class_set_copy_env(entry_env)
  iteration = 0
  while iteration < 10
    cond_env = class_set_copy_env(header)
    class_set_eval_expr(ctx, node.condition, cond_env)
    body_state = class_set_analyze_body(ctx, node.body, class_set_copy_env(cond_env))
    incoming = [entry_env]
    if body_state[:reachable]
      incoming.push(body_state[:env])
    next_header = class_set_join_envs(ctx[:mod], incoming)
    if class_set_env_equal?(header, next_header)
      header = next_header
      break
    header = next_header
    iteration += 1

  exit_env = class_set_copy_env(header)
  class_set_eval_expr(ctx, node.condition, exit_env)
  # break/next paths require edge-specific environments. Until that detail is
  # represented, invalidate only locals written by such a loop; unchanged
  # incoming facts remain useful and sound.
  if class_set_body_has_loop_transfer?(node.body)
    class_set_mark_calls_unknown(ctx, node.body)
    class_set_kill_assigned(exit_env, node.body)
  class_set_flow(exit_env, true)

# `with` and `parallel_with` are iterative regions whose bodies may update
# captured locals on every element.  Until the analysis models their binding,
# continue, and join edges explicitly, do not retain a one-pass receiver fact
# from inside the region.  Locals untouched by the region remain precise.
-> class_set_analyze_with(ctx, node, entry_env)
  exit_env = class_set_copy_env(entry_env)
  class_set_mark_calls_unknown(ctx, node.bindings)
  class_set_mark_calls_unknown(ctx, node.body)
  class_set_kill_assigned(exit_env, node.bindings)
  class_set_kill_assigned(exit_env, node.body)
  class_set_flow(exit_env, true)

-> class_set_analyze_case(ctx, node, entry_env)
  base = class_set_copy_env(entry_env)
  subject = ast_get(node, :subject)
  if subject != nil
    class_set_eval_expr(ctx, subject, base)
  reachable_envs = []
  arms = ast_get(node, :arms)
  if arms == nil
    arms = ast_get(node, :clauses)
  if arms != nil
    i = 0
    while i < arms.size()
      arm_env = class_set_copy_env(base)
      guard = ast_get(arms[i], :guard)
      if guard != nil
        class_set_eval_expr(ctx, guard, arm_env)
      arm_state = class_set_analyze_body(ctx, ast_get(arms[i], :body), arm_env)
      if arm_state[:reachable]
        reachable_envs.push(arm_state[:env])
      i += 1
  else_body = ast_get(node, :else_body)
  if else_body != nil && else_body.size() > 0
    else_state = class_set_analyze_body(ctx, else_body, class_set_copy_env(base))
    if else_state[:reachable]
      reachable_envs.push(else_state[:env])
  else
    reachable_envs.push(base)
  class_set_flow(class_set_join_envs(ctx[:mod], reachable_envs), reachable_envs.size() > 0)

-> class_set_analyze_begin(ctx, node, entry_env)
  try_state = class_set_analyze_body(ctx, node.body, class_set_copy_env(entry_env))
  reachable_envs = []
  if try_state[:reachable]
    reachable_envs.push(try_state[:env])

  rescue_body = node.rescue_body
  if rescue_body != nil
    # An exception may arise after any prefix of the try. Locals written in
    # that region therefore have no single rescue-entry fact.
    rescue_env = class_set_copy_env(entry_env)
    class_set_kill_assigned(rescue_env, node.body)
    if node.rescue_var != nil
      rescue_env.delete(node.rescue_var)
    rescue_state = class_set_analyze_body(ctx, rescue_body, rescue_env)
    if rescue_state[:reachable]
      reachable_envs.push(rescue_state[:env])
  elsif try_state[:reachable] == false
    return class_set_flow({}, false)

  if reachable_envs.size() == 0
    return class_set_flow({}, false)
  joined = class_set_join_envs(ctx[:mod], reachable_envs)
  if node.ensure_body != nil
    return class_set_analyze_body(ctx, node.ensure_body, joined)
  class_set_flow(joined, true)

-> class_set_analyze_statement(ctx, node, env)
  if node == nil || !is_ast_node?(node)
    return class_set_flow(env, true)
  kind = ast_kind(node)
  case kind
  when :assign
    previous = ctx[:class_set_direct_assignment]
    ctx[:class_set_direct_assignment] = true
    class_set_eval_expr(ctx, node, env)
    ctx[:class_set_direct_assignment] = previous
    return class_set_flow(env, true)
  when :if
    return class_set_analyze_if(ctx, node, env)
  when :while
    return class_set_analyze_while(ctx, node, env)
  when :with, :parallel_with
    return class_set_analyze_with(ctx, node, env)
  when :case, :case_value
    return class_set_analyze_case(ctx, node, env)
  when :begin
    return class_set_analyze_begin(ctx, node, env)
  when :return
    class_set_eval_expr(ctx, node.value, env)
    return class_set_flow(env, false)
  when :raise
    class_set_eval_expr(ctx, node.value, env)
    return class_set_flow(env, false)
  when :break, :next, :redo
    value = ast_get(node, :value)
    if value != nil
      class_set_eval_expr(ctx, value, env)
    return class_set_flow(env, false)
  when :fn_def, :method_def, :class_def, :module_def, :trait_def, :gpu_kernel_def
    return class_set_flow(env, true)
  else
    class_set_eval_expr(ctx, node, env)
    return class_set_flow(env, true)

-> class_set_analyze_body(ctx, body, start_env)
  env = class_set_copy_env(start_env)
  if body == nil
    return class_set_flow(env, true)
  i = 0
  while i < body.size()
    state = class_set_analyze_statement(ctx, body[i], env)
    env = state[:env]
    if !state[:reachable]
      return state
    i += 1
  class_set_flow(env, true)

-> class_set_seed_env(ctx)
  env = {}
  types = ctx[:var_types]
  if types == nil
    return env
  keys = types.keys()
  i = 0
  while i < keys.size()
    name = keys[i]
    declared = types[name]
    if declared != nil
      cname = resolve_exact_source_class_name(ctx[:mod], ctx[:class_name], "" + declared.to_s())
      if cname != nil && normal_source_instance_class?(ctx[:mod], cname)
        env[name] = class_set_compatible(cname)
    i += 1
  env

-> prepare_class_set_analysis(ctx, body)
  if ctx[:class_set_analysis_ready] == true
    return nil
  ctx[:class_set_analysis_ready] = true
  ctx[:class_set_call_facts] = {}
  # Open-world programs cannot consume an unguarded class-set proof. Avoid
  # paying for analysis whose only possible result is the existing IC path.
  if ctx[:mod][:method_tables_locked] != true
    return nil
  class_set_analyze_body(ctx, body, class_set_seed_env(ctx))
  nil

-> receiver_flow_class_fact(ctx, call_node)
  facts = ctx[:class_set_call_facts]
  if facts == nil
    return nil
  fact = facts[call_node]
  if class_set_unknown?(fact)
    return nil
  fact
