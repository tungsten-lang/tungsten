# Lowering / elision — escape analyses that let assignment lowering
# skip materializing single-use closure and range bindings (consumed
# by lower_assign_expr / lower_multi_assign in assign.w).
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

-> closure_binding_assignment_count(node, name)
  if node == nil
    return 0
  if type(node) == "Array"
    total = 0
    i = 0
    while i < node.size()
      total += closure_binding_assignment_count(node[i], name)
      i += 1
    return total
  if !is_ast_node?(node)
    return 0
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return 0
  total = 0
  if ast_kind(node) == :assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var && target.name == name
      total += 1
  # The :assign-target-skip case is specific: we don't count the LHS
  # of an assignment as a binding use. Schema for :assign is
  # {:target=>0, :value=>1, :type_hint=>2}; :type_hint is a sym, not
  # AST, so only :value matters.
  if ast_kind(node) == :assign
    total += closure_binding_assignment_count(node.value, name)
  else
    ast_children(node).each -> (c)
      total += closure_binding_assignment_count(c, name)
  total

-> closure_binding_safe_use?(node, name)
  if node == nil
    return true
  if type(node) == "Array"
    i = 0
    while i < node.size()
      if !closure_binding_safe_use?(node[i], name)
        return false
      i += 1
    return true
  if !is_ast_node?(node)
    return true
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return true
  if ast_kind(node) == :var && node.name == name
    return false
  if ast_kind(node) == :assign
    return closure_binding_safe_use?(node.value, name)
  if ast_kind(node) == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return true
        pi += 1
  if ast_kind(node) == :call
    # A bare call `name(...)` directly invokes the closure-bound variable. The
    # callee is encoded in Call.name (a string), not as a :var child, so the
    # generic child traversal below never sees it as a use — and the closure
    # would be wrongly elided, leaving the call to load nil ("expected
    # closure"). A direct invocation needs a materialized closure WValue, so it
    # is an escaping use. (`name.call(...)` is already caught: its receiver is a
    # real :var child handled above.)
    if node.receiver == nil && node.name == name
      return false
    args = node.args
    if node.receiver != nil && node.block == nil && args != nil && args.size() >= 1 && inline_closure_arg_iterator_method?(node.name)
      last = args[args.size() - 1]
      if last != nil && is_ast_node?(last) && ast_kind(last) == :var && last.name == name
        if !closure_binding_safe_use?(node.receiver, name)
          return false
        ai = 0
        while ai < args.size() - 1
          if !closure_binding_safe_use?(args[ai], name)
            return false
          ai += 1
        return true
  children = ast_children(node)
  i = 0
  while i < children.size()
    if !closure_binding_safe_use?(children[i], name)
      return false
    i += 1
  true

-> closure_binding_var_use_count(node, name)
  if node == nil
    return 0
  if type(node) == "Array"
    total = 0
    i = 0
    while i < node.size()
      total += closure_binding_var_use_count(node[i], name)
      i += 1
    return total
  if !is_ast_node?(node)
    return 0
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return 0
  if ast_kind(node) == :var && node.name == name
    return 1
  if ast_kind(node) == :assign
    return closure_binding_var_use_count(node.value, name)
  if ast_kind(node) == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return 0
        pi += 1
  total = 0
  ast_children(node).each -> (c)
    total += closure_binding_var_use_count(c, name)
  total

-> closure_binding_consumed_as_iter_arg?(node, name)
  if node == nil || !is_ast_node?(node)
    return false
  if ast_kind(node) == :call
    args = node.args
    if node.receiver != nil && node.block == nil && args != nil && args.size() >= 1 && inline_closure_arg_iterator_method?(node.name)
      last = args[args.size() - 1]
      return last != nil && is_ast_node?(last) && ast_kind(last) == :var && last.name == name
  if ast_kind(node) in (:assign :return :puts :print)
    return closure_binding_consumed_as_iter_arg?(node.value, name)
  if ast_kind(node) == :passthrough
    return closure_binding_consumed_as_iter_arg?(node.expression, name) || closure_binding_consumed_as_iter_arg?(node.value, name)
  if ast_kind(node) == :type_ascription
    return closure_binding_consumed_as_iter_arg?(node.expression, name)
  false

-> closure_binding_consumed_by_next_stmt?(ctx, name)
  stmts = ctx[:enclosing_stmts]
  idx = ctx[:enclosing_stmt_idx]
  if stmts == nil || idx == nil || idx + 1 >= stmts.size()
    return false
  if closure_binding_assignment_count(stmts, name) != 1
    return false
  if closure_binding_var_use_count(stmts, name) != 1
    return false
  closure_binding_consumed_as_iter_arg?(stmts[idx + 1], name)

-> closure_binding_no_escape?(ctx, name)
  stmts = ctx[:enclosing_stmts]
  if stmts == nil
    return false
  if closure_binding_assignment_count(stmts, name) != 1
    return false
  closure_binding_safe_use?(stmts, name)

# --- Range-materialization elision (#49 completion) -------------------------
#
# `r = (lo..hi)` lowers through lower_range, which MATERIALIZES the range:
# an empty array plus a push loop over every element — O(N) time and memory.
# The range-elision substitution (ctx[:range_bindings], consumed by the
# `.each` handler in method_call.w and lower_pipeline in pipeline_fusion.w)
# already rewrites every elidable USE to the range literal, so when every
# use is elidable the materialization is dead weight: a (1..10^9) binding
# feeding a folded `range/Σ(…)` costs seconds and gigabytes for a value
# nothing reads. These walkers prove that, letting lower_assign_expr skip
# the materialization entirely.
#
# Elidable uses — exactly the shapes the substitution sites rewrite:
#   - `r.each -> (…) …`         (method_call.w range-elision)
#   - pipeline base: `r/…`, `r/…:sum`, `r/….take(n)`   (lower_pipeline)
# Everything else (bare `r`, `r.size`, `r.map(:sym)`, passing `r` along) is
# a real use and keeps the materialization.
#
# Soundness gates (range_assign_elidable?):
#   - not main's top level: a top-level single-assign var promotes to
#     @global.<name>, readable from functions this walk can't see.
#   - fresh name: no existing slot/binding/type and not a param — a capture
#     or reassignment writes storage other scopes may read.
#   - single binding in the enclosing statement list (counting :assign,
#     :compound_assign AND :multi_assign targets), no use before or inside
#     the assign statement, every later use elidable.
#   - uses inside nested :block subtrees are rejected wholesale: a block
#     lowered as a real closure gets a fresh child ctx WITHOUT
#     range_bindings, so the substitution could not fire there.
#   - bounds are :int literals or plain :var reads, and no bound var is
#     rebound after the assign — substitution re-evaluates bounds at the
#     use site, which must observe the same values.

-> range_elision_assign_count(node, name)
  if node == nil
    return 0
  if type(node) == "Array"
    total = 0
    i = 0
    while i < node.size()
      total += range_elision_assign_count(node[i], name)
      i += 1
    return total
  if !is_ast_node?(node)
    return 0
  k = ast_kind(node)
  if k in (:method_def :fn_def :class_def :module_def :trait_def)
    return 0
  if k == :assign || k == :compound_assign
    total = 0
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var && target.name == name
      total += 1
    else
      total += range_elision_assign_count(target, name)
    total += range_elision_assign_count(node.value, name)
    return total
  if k == :multi_assign
    total = 0
    targets = ast_get(node, :targets)
    if targets != nil
      ti = 0
      while ti < targets.size()
        t = targets[ti]
        if t != nil && is_ast_node?(t) && ast_kind(t) == :var && t.name == name
          total += 1
        ti += 1
    total += range_elision_assign_count(node.value, name)
    return total
  if k == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return 0
        pi += 1
  total = 0
  ast_children(node).each -> (c)
    total += range_elision_assign_count(c, name)
  total

# The pipeline chain `base /stage… [:terminal]` is nested Map/Calc nodes.
# Walk the chain: every non-source child (stage funcs, args) must be a safe
# use; the final base being our var is the one position the substitution
# rewrites. Mirrors fuse_pipeline's flattening (including the `.lazy` unwrap).
-> range_elision_pipeline_safe?(node, name)
  cur = node
  while is_ast_node?(cur) && ast_kind(cur) in (:map :calc)
    src = ast_get(cur, :source)
    kids = ast_children(cur)
    i = 0
    while i < kids.size()
      if kids[i] != src
        if !range_elision_safe_use?(kids[i], name)
          return false
      i += 1
    cur = src
  if is_ast_node?(cur) && ast_kind(cur) == :call && ast_get(cur, :name) == "lazy" && cur.receiver != nil
    a = ast_get(cur, :args)
    if a == nil || a.size() == 0
      cur = cur.receiver
  if is_ast_node?(cur) && ast_kind(cur) == :var && cur.name == name
    return true
  range_elision_safe_use?(cur, name)

-> range_elision_safe_use?(node, name)
  if node == nil
    return true
  if type(node) == "Array"
    i = 0
    while i < node.size()
      if !range_elision_safe_use?(node[i], name)
        return false
      i += 1
    return true
  if !is_ast_node?(node)
    return true
  k = ast_kind(node)
  if k in (:method_def :fn_def :class_def :module_def :trait_def)
    return true
  if k == :var
    return node.name != name
  if k == :block
    # A block param shadows the name — inner uses are the param's.
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return true
        pi += 1
    # A block lowered as a closure gets a fresh ctx without range_bindings,
    # so no use of the name inside any block subtree can substitute.
    return closure_binding_var_use_count(node, name) == 0
  if k in (:map :calc)
    return range_elision_pipeline_safe?(node, name)
  if k == :call
    # A bare call `name(…)` is a direct use (callee lives in Call.name, not
    # a :var child, so the generic traversal below would miss it).
    if node.receiver == nil && node.name == name
      return false
    recv = node.receiver
    if recv != nil && is_ast_node?(recv) && ast_kind(recv) == :var && recv.name == name
      # Only `.each` with a trailing block elides at the use site.
      if node.name == "each" && node.block != nil
        if !range_elision_safe_use?(ast_get(node, :args), name)
          return false
        return range_elision_safe_use?(node.block, name)
      return false
  if k == :assign || k == :compound_assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var && target.name == name
      return range_elision_safe_use?(node.value, name)
    if !range_elision_safe_use?(target, name)
      return false
    return range_elision_safe_use?(node.value, name)
  children = ast_children(node)
  i = 0
  while i < children.size()
    if !range_elision_safe_use?(children[i], name)
      return false
    i += 1
  true

# A bound expression the substitution may legally re-evaluate at the use
# site: pure arithmetic over literals and plain variable reads. Calls (side
# effects would replay per use) and ivars (mutable behind method calls the
# walkers can't see) disqualify the whole range from ctx[:range_bindings].
-> range_binding_pure_bound?(bound)
  if bound == nil || !is_ast_node?(bound)
    return false
  k = ast_kind(bound)
  if k in (:int :float :var)
    return true
  if k in (:binary_op :unary_op)
    kids = ast_children(bound)
    i = 0
    while i < kids.size()
      if !range_binding_pure_bound?(kids[i])
        return false
      i += 1
    return true
  false

# Rebinding `name` invalidates its own recorded range AND any recorded range
# whose bounds read `name` — the substitution re-evaluates bounds at the use
# site, which must observe the values the bounds had at the assignment.
-> range_binding_invalidate(ctx, name)
  if ctx[:range_bindings] == nil
    return nil
  ctx[:range_bindings][name] = nil
  ctx[:range_bindings].keys().each -> (rk)
    rn = ctx[:range_bindings][rk]
    if rn != nil
      if closure_binding_var_use_count(ast_get(rn, :from), name) > 0 || closure_binding_var_use_count(ast_get(rn, :to), name) > 0
        ctx[:range_bindings][rk] = nil

-> range_elision_bound_stable?(stmt, bound)
  if !is_ast_node?(bound)
    return true
  if ast_kind(bound) == :var
    return range_elision_assign_count(stmt, bound.name) == 0
  kids = ast_children(bound)
  i = 0
  while i < kids.size()
    if !range_elision_bound_stable?(stmt, kids[i])
      return false
    i += 1
  true

-> range_assign_elidable?(ctx, name, value)
  wfn = ctx[:func]
  if wfn[:name] == "main"
    return false
  stmts = ctx[:enclosing_stmts]
  idx = ctx[:enclosing_stmt_idx]
  if stmts == nil || idx == nil
    return false
  if wfn[:var_slots][name] != nil || ctx[:bindings][name] != nil || ctx[:var_types][name] != nil
    return false
  if wfn[:params].include?(name)
    return false
  from = ast_get(value, :from)
  to = ast_get(value, :to)
  if !range_binding_pure_bound?(from) || !range_binding_pure_bound?(to)
    return false
  if range_elision_assign_count(stmts, name) != 1
    return false
  i = 0
  while i <= idx
    if closure_binding_var_use_count(stmts[i], name) != 0
      return false
    i += 1
  j = idx + 1
  while j < stmts.size()
    if !range_elision_safe_use?(stmts[j], name)
      return false
    if !range_elision_bound_stable?(stmts[j], from) || !range_elision_bound_stable?(stmts[j], to)
      return false
    j += 1
  true
