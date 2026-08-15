# Return type inference.
#
# When a method or fn is defined without an explicit return type annotation
# (the `-> add(a, b) i64 : a + b` form), infer one from the body so downstream
# code can use type-directed optimizations and gradual-typing diagnostics.
#
# One inference rule is implemented: accumulator-seed inference.
# When a method uses the accumulator form — where a trailing expression after
# the param list becomes the seed for an indented body that mutates it — the
# seed's static type IS the return type. The parser desugars this form at
# parser.w:1360-1368: the trailing expression becomes `acc_name = trailing_expr`
# at the head of the body, and the final body statement is `Tungsten:AST:Var.new(acc_name)`.
# By the time this inference runs on the AST, that desugaring has happened.
#
# The accumulator-seed rule itself is local and always-terminating. Module
# lowering builds the call graph around it, condenses that graph into strongly
# connected components, and evaluates callees before callers. Recursive
# components use explicit/base-case return evidence as a seed and iterate to
# convergence.

use ast
use runtime_types

# Try to infer a return type from an accumulator-form method body.
#
# Returns a type symbol (e.g. :int, :float, :string) if the body matches
# the accumulator shape and the seed has an inferrable type. Returns nil
# if the body doesn't match the shape or the seed's type can't be determined.
#
# Shape recognition: the parser desugars `-> sum(items) 0 \n items -> out += i`
# into a body that starts with `acc = 0` and ends with `Tungsten:AST:Var.new(acc)`. We
# detect this by checking that the first statement is an assign of a literal
# or an inferrable expression, and the last statement is a var reference
# to the assignment's target.
-> infer_accumulator_return_type(body, var_types, fn_return_types, infer_maps)
  if body == nil || body.size() < 2
    return nil
  first = body[0]
  last = body[body.size() - 1]
  if first == nil || last == nil
    return nil
  if ast_kind(first) != :assign
    return nil
  if ast_kind(last) != :var
    return nil
  target = first.target
  if target == nil || ast_kind(target) != :var
    return nil
  if target.name != last.name
    return nil
  # Found the accumulator shape — infer from the seed value.
  infer_type(first.value, var_types, fn_return_types, infer_maps)

# Top-level entry: given a method/fn AST node, return its inferred return
# type or nil if no inference rule matches. Called from lower_method_def /
# lower_fn_def when the node has no explicit :return_type annotation.
-> infer_return_type(node, var_types, fn_return_types, infer_maps)
  # Explicit annotation wins — caller should check this first but we
  # defensively honor it here too.
  if node.return_type != nil
    return node.return_type
  # Accumulator-seed rule
  acc_type = infer_accumulator_return_type(node.body, var_types, fn_return_types, infer_maps)
  if acc_type != nil
    return acc_type
  # Fall through to the existing last-expression inference (this pass does
  # not add new machinery here — just uses whatever infer_fn_return_type
  # already does).
  infer_fn_return_type(node, infer_maps)

# Return inference needs more than the final expression for recursion: a base
# case commonly returns explicitly while the tail calls a sibling in the same
# SCC. Collect every explicit return plus the tail position, ignoring unknown
# recursive edges until another member supplies a seed. A singleton evidence
# set is safe to publish; mixed evidence remains unknown.
-> collect_return_type_evidence(node, tail_position, var_types, fn_return_types, infer_maps, evidence)
  if node == nil || !is_ast_node?(node)
    return nil
  kind = ast_kind(node)
  if kind == :return
    if node.value != nil
      rt = infer_type(node.value, var_types, fn_return_types, infer_maps)
      if rt != nil
        evidence[normalize_type_symbol(rt)] = true
    return nil
  if tail_position && kind == :if
    collect_body_return_evidence(node.then_body, var_types, fn_return_types, infer_maps, evidence)
    if node.elsif_clauses != nil
      ei = 0
      while ei < node.elsif_clauses.size()
        collect_body_return_evidence(node.elsif_clauses[ei][1], var_types, fn_return_types, infer_maps, evidence)
        ei += 1
    collect_body_return_evidence(node.else_body, var_types, fn_return_types, infer_maps, evidence)
  elsif tail_position && kind == :begin
    collect_body_return_evidence(node.body, var_types, fn_return_types, infer_maps, evidence)
    collect_body_return_evidence(node.rescue_body, var_types, fn_return_types, infer_maps, evidence)
    collect_body_return_evidence(node.ensure_body, var_types, fn_return_types, infer_maps, evidence)
  else
    if tail_position
      rt = infer_type(node, var_types, fn_return_types, infer_maps)
      if rt != nil
        evidence[normalize_type_symbol(rt)] = true
    children = ast_children(node)
    ci = 0
    while ci < children.size()
      collect_return_type_evidence(children[ci], false, var_types, fn_return_types, infer_maps, evidence)
      ci += 1
  nil

-> collect_body_return_evidence(body, var_types, fn_return_types, infer_maps, evidence)
  if body == nil || body.size() == 0
    return nil
  i = 0
  while i < body.size()
    collect_return_type_evidence(body[i], i == body.size() - 1, var_types, fn_return_types, infer_maps, evidence)
    i += 1
  nil

-> infer_return_type_evidence(node, var_types, fn_return_types, infer_maps)
  evidence = {}
  collect_body_return_evidence(node.body, var_types, fn_return_types, infer_maps, evidence)
  types = evidence.keys()
  if types.size() == 1
    return types[0]
  nil

-> return_inference_collect_calls(node, unique_names, dependencies)
  if node == nil || !is_ast_node?(node)
    return nil
  if ast_kind(node) == :call && node.receiver == nil && node.name != nil
    dep = unique_names[node.name]
    if dep != nil
      dependencies[dep] = true
  children = ast_children(node)
  i = 0
  while i < children.size()
    return_inference_collect_calls(children[i], unique_names, dependencies)
    i += 1
  nil

-> return_inference_dfs_order(key, graph, seen, order)
  if seen[key] == true
    return nil
  seen[key] = true
  edges = graph[key]
  if edges != nil
    i = 0
    while i < edges.size()
      return_inference_dfs_order(edges[i], graph, seen, order)
      i += 1
  order.push(key)
  nil

-> return_inference_dfs_component(key, reverse_graph, seen, component)
  if seen[key] == true
    return nil
  seen[key] = true
  component.push(key)
  edges = reverse_graph[key]
  if edges != nil
    i = 0
    while i < edges.size()
      return_inference_dfs_component(edges[i], reverse_graph, seen, component)
      i += 1
  nil

# Return SCCs in callee-before-caller order. The first Kosaraju pass records
# dependency finish order; the second pass over the transpose yields callers
# first, so reverse the component list for inference.
-> return_inference_sccs(inferable_methods)
  defs = {}
  unique_names = {}
  duplicate_names = {}
  i = 0
  while i < inferable_methods.size()
    node = inferable_methods[i]
    key = method_call_key_for_def(node)
    defs[key] = node
    if duplicate_names[node.name] != true
      if unique_names[node.name] == nil
        unique_names[node.name] = key
      else
        unique_names[node.name] = nil
        duplicate_names[node.name] = true
    i += 1

  graph = {}
  reverse_graph = {}
  keys = defs.keys()
  i = 0
  while i < keys.size()
    key = keys[i]
    deps_set = {}
    return_inference_collect_calls(defs[key], unique_names, deps_set)
    deps = deps_set.keys()
    graph[key] = deps
    if reverse_graph[key] == nil
      reverse_graph[key] = []
    di = 0
    while di < deps.size()
      dep = deps[di]
      if reverse_graph[dep] == nil
        reverse_graph[dep] = []
      reverse_graph[dep].push(key)
      di += 1
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
    key = order[oi]
    if seen[key] != true
      component = []
      return_inference_dfs_component(key, reverse_graph, seen, component)
      components.push(component)
    oi -= 1
  out = []
  ci = components.size() - 1
  while ci >= 0
    out.push(components[ci])
    ci -= 1
  {components: out, definitions: defs}
