# perf_inspect.w — AST Performance Inspection & Loop/Fetch Instrumentation
#
# Annotates the Tungsten AST and inspects loops (`while`, `.each`, `.times`,
# `.map`, `.select`, `.reject`) and load/fetch expressions (`arr[i]`,
# `obj.field()`, `view[i]`, `var$field`, `@ivar`, `$gvar`) to bubble up:
#   1. Repeated fetches per iteration (`repeated_fetch`): the same object/
#      element/property is fetched 2+ times on a single path through a loop
#      iteration without an intervening mutation to its receiver or index.
#   2. Loop-invariant fetches (`loop_invariant_fetch`): a fetch inside a loop
#      (or loop condition, e.g. `while i < arr.size()`) whose receiver and
#      index variables are never mutated in the loop and can be hoisted.
#
# Also supports AST instrumentation (`perf_inspect_instrument_ast`) using
# `Tungsten:AST:Passthrough` nodes and global counters so `tungsten flame`
# (or `tungsten compile --perf-inspect`) can measure exact runtime loop
# iterations and dynamic fetch executions per cycle.

use core/json
use lexer
use parser

-> perf_op_to_s(op)
  if op == :PLUS
    return "+"
  if op == :MINUS
    return "-"
  if op == :STAR
    return "*"
  if op == :SLASH
    return "/"
  if op == :PERCENT
    return "%"
  if op == :EQ
    return "=="
  if op == :NEQ
    return "!="
  if op == :LT
    return "<"
  if op == :GT
    return ">"
  if op == :LTE
    return "<="
  if op == :GTE
    return ">="
  if op == :AMP
    return "&"
  if op == :PIPE
    return "|"
  if op == :CARET
    return "^"
  if op == :LSHIFT
    return "<<"
  if op == :RSHIFT
    return ">>"
  op.to_s()

-> perf_args_to_s(args)
  if args == nil || args.size() == 0
    return ""
  parts = []
  i = 0
  while i < args.size()
    parts.push(perf_expr_to_s(args[i]))
    i += 1
  parts.join(", ")

-> perf_expr_to_s(node)
  if node == nil
    return "nil"
  if !is_ast_node?(node)
    return node.to_s()
  k = ast_kind(node)
  case k
  when :var, :class_ref, :ivar, :cvar, :gvar
    return node.name.to_s()
  when :int, :float, :decimal
    return node.value.to_s()
  when :string
    return "\"" + node.value.to_s() + "\""
  when :symbol
    return ":" + node.value.to_s()
  when :bool
    return node.value ? "true" : "false"
  when :nil_lit
    return "nil"
  when :self_ref
    return "self"
  when :binary_op
    return perf_expr_to_s(node.left) + " " + perf_op_to_s(node.op) + " " + perf_expr_to_s(node.right)
  when :and
    return perf_expr_to_s(node.left) + " && " + perf_expr_to_s(node.right)
  when :or
    return perf_expr_to_s(node.left) + " || " + perf_expr_to_s(node.right)
  when :unary_op
    return perf_op_to_s(node.op) + perf_expr_to_s(node.operand)
  when :not
    return "!" + perf_expr_to_s(node.operand)
  when :view_access
    return perf_expr_to_s(node.view_name) + "\[" + perf_expr_to_s(node.index) + "]"
  when :view_field_var
    return perf_expr_to_s(node.receiver) + "$" + node.field.to_s()
  when :view_field
    return "$" + node.field.to_s()
  when :type_ascription
    return perf_expr_to_s(node.expression)
  when :passthrough
    return perf_expr_to_s(node.value)
  when :call
    name = node.name.to_s()
    if name == "[]" && node.receiver != nil
      return perf_expr_to_s(node.receiver) + "\[" + perf_args_to_s(node.args) + "]"
    if node.receiver != nil
      if node.args == nil || node.args.size() == 0
        return perf_expr_to_s(node.receiver) + "." + name + "()"
      return perf_expr_to_s(node.receiver) + "." + name + "(" + perf_args_to_s(node.args) + ")"
    return name + "(" + perf_args_to_s(node.args) + ")"
  else
    return k.to_s()

# Extract the first available 1-indexed line number from `node` or its subtree.
-> perf_node_line(node, fallback = nil)
  if node == nil
    return fallback
  if type(node) == "Array"
    i = 0
    while i < node.size()
      ln = perf_node_line(node[i], nil)
      if ln != nil && ln > 0
        return ln
      i += 1
    return fallback
  if !is_ast_node?(node)
    return fallback
  ln = node.line
  if ln != nil && ln > 0
    return ln
  kids = ast_children(node)
  i = 0
  while i < kids.size()
    kln = perf_node_line(kids[i], nil)
    if kln != nil && kln > 0
      return kln
    i += 1
  fallback

# True when `node` is a side-effect-free expression suitable for fetch keys.
-> perf_expr_pure?(node)
  if node == nil
    return true
  if !is_ast_node?(node)
    return true
  k = ast_kind(node)
  case k
  when :var, :class_ref, :ivar, :cvar, :gvar, :int, :float, :decimal, :string, :symbol, :bool, :nil_lit, :self_ref, :view_field
    return true
  when :binary_op, :and, :or
    return perf_expr_pure?(node.left) && perf_expr_pure?(node.right)
  when :unary_op, :not
    return perf_expr_pure?(node.operand)
  when :type_ascription
    return perf_expr_pure?(node.expression)
  when :passthrough
    return perf_expr_pure?(node.value)
  when :view_access
    return perf_expr_pure?(node.view_name) && perf_expr_pure?(node.index)
  when :view_field_var
    return perf_expr_pure?(node.receiver)
  when :call
    if node.block != nil || node.receiver == nil
      return false
    if !perf_expr_pure?(node.receiver)
      return false
    name = node.name.to_s()
    if name == "[]" && node.args != nil && node.args.size() >= 1
      i = 0
      while i < node.args.size()
        if !perf_expr_pure?(node.args[i])
          return false
        i += 1
      return true
    if (node.args == nil || node.args.size() == 0) && perf_getter_name?(name)
      return true
    return false
  else
    return false

-> perf_getter_name?(name)
  if name in ("size" "length" "keys" "values" "first" "last" "empty?" "strip" "chars" "lines" "to_i" "to_s" "to_f")
    return true
  if name in ("receiver" "name" "args" "block" "body" "left" "right" "value" "target" "condition" "expressions" "params" "line" "col" "loc" "kind" "op" "operand" "elements" "entries")
    return true
  false

# Base receiver variable/identifier name for an expression (`a[i][j]` -> `"a"`).
-> perf_base_receiver_name(node)
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  case k
  when :var, :class_ref, :ivar, :cvar, :gvar
    return node.name.to_s()
  when :self_ref
    return "self"
  when :view_access
    return perf_base_receiver_name(node.view_name)
  when :view_field_var
    return perf_base_receiver_name(node.receiver)
  when :view_field
    return "self"
  when :type_ascription
    return perf_base_receiver_name(node.expression)
  when :passthrough
    return perf_base_receiver_name(node.value)
  when :call
    if node.receiver != nil
      return perf_base_receiver_name(node.receiver)
    return nil
  else
    return nil

# Collect all variable/receiver names that `node` depends on.
-> perf_collect_deps(node, out_hash)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      perf_collect_deps(node[i], out_hash)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k in (:var :class_ref :ivar :cvar :gvar)
    out_hash[node.name.to_s()] = true
    return nil
  if k == :self_ref || k == :view_field
    out_hash["self"] = true
    return nil
  kids = ast_children(node)
  i = 0
  while i < kids.size()
    perf_collect_deps(kids[i], out_hash)
    i += 1
  nil

# Is `node` a load/fetch AST node that we should inspect inside loops?
-> perf_is_fetch_node?(node)
  if node == nil || !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:ivar :gvar :view_field)
    return true
  if k == :view_access
    return perf_expr_pure?(node.view_name) && perf_expr_pure?(node.index)
  if k == :view_field_var
    return perf_expr_pure?(node.receiver)
  if k == :call
    if node.block != nil || node.receiver == nil
      return false
    if !perf_expr_pure?(node.receiver)
      return false
    name = node.name.to_s()
    if name == "[]" && node.args != nil && node.args.size() >= 1
      i = 0
      while i < node.args.size()
        if !perf_expr_pure?(node.args[i])
          return false
        i += 1
      return true
    if (node.args == nil || node.args.size() == 0) && perf_getter_name?(name)
      return true
  false

-> perf_iterator_call?(node)
  if node == nil || !is_ast_node?(node)
    return false
  if ast_kind(node) != :call || node.block == nil
    return false
  name = node.name.to_s()
  name in ("each" "times" "map" "select" "reject" "each_with_index" "upto" "downto")

-> perf_mutating_method?(name)
  if name.ends_with?("=") || name.ends_with?("!")
    return true
  name in ("[]=" "push" "pop" "clear" "delete" "shift" "unshift" "replace" "concat" "append" "<<")

# Collect all mutated variables and mutated receiver objects across a subtree
# (including nested loops and branches).
-> perf_collect_mutations(node, mutated_vars, mutated_recvs)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      perf_collect_mutations(node[i], mutated_vars, mutated_recvs)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :assign || k == :compound_assign
    target = node.target
    if target != nil && is_ast_node?(target)
      tk = ast_kind(target)
      if tk in (:var :ivar :cvar :gvar)
        mutated_vars[target.name.to_s()] = true
      else
        rname = perf_base_receiver_name(target)
        if rname != nil
          mutated_recvs[rname] = true
  elsif k == :multi_assign
    targets = node.targets
    if targets != nil
      ti = 0
      while ti < targets.size()
        t = targets[ti]
        if t != nil && is_ast_node?(t) && ast_kind(t) in (:var :ivar :cvar :gvar)
          mutated_vars[t.name.to_s()] = true
        ti += 1
  elsif k == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        p = params[pi]
        if type(p) == "String"
          mutated_vars[p] = true
        elsif is_ast_node?(p) && ast_kind(p) == :param
          mutated_vars[p.name.to_s()] = true
        pi += 1
  elsif k == :call
    name = node.name.to_s()
    if node.receiver != nil && perf_mutating_method?(name)
      rname = perf_base_receiver_name(node.receiver)
      if rname != nil
        mutated_recvs[rname] = true
    # Known buffer/array-mutating helpers in Tungsten/Metal code
    if node.receiver == nil && (name.starts_with?("metal_buffer_write") || name.starts_with?("lrc_v4_copy"))
      if node.args != nil && node.args.size() >= 1
        rname = perf_base_receiver_name(node.args[0])
        if rname != nil
          mutated_recvs[rname] = true
  kids = ast_children(node)
  i = 0
  while i < kids.size()
    perf_collect_mutations(kids[i], mutated_vars, mutated_recvs)
    i += 1
  nil

-> perf_epoch_sig(expr_str, deps_hash, epochs)
  keys = deps_hash.keys().sort()
  out = StringBuffer(expr_str.size() + 16)
  out << expr_str
  out << "@"
  i = 0
  while i < keys.size()
    v = keys[i]
    ep = epochs[v]
    if ep == nil
      ep = 0
    out << v << "=" << ep.to_s() << ";"
    i += 1
  out.to_s()

-> perf_bump_epochs_for_subtree(node, epochs)
  mv = {}
  mr = {}
  perf_collect_mutations(node, mv, mr)
  mv.keys().each -> (v)
    cur = epochs[v]
    epochs[v] = (cur == nil ? 1 : cur + 1)
  mr.keys().each -> (r)
    cur = epochs[r]
    epochs[r] = (cur == nil ? 1 : cur + 1)
  nil

-> perf_record_fetch(node, in_cond, cur_line, epochs, bucket)
  expr_str = perf_expr_to_s(node)
  ast_set(node, :perf_fetch_key, expr_str)
  deps = {}
  perf_collect_deps(node, deps)
  rname = perf_base_receiver_name(node)
  if rname != nil
    deps[rname] = true
  sig = perf_epoch_sig(expr_str, deps, epochs)
  ln = perf_node_line(node, cur_line)
  entry = bucket[sig]
  if entry == nil
    entry = {
      sig: sig,
      expr: expr_str,
      receiver: rname,
      deps: deps,
      count: 0,
      in_cond: false,
      lines: [],
      nodes: []
    }
    bucket[sig] = entry
  entry[:count] = entry[:count] + 1
  if in_cond
    entry[:in_cond] = true
  if ln != nil
    entry[:lines].push(ln)
  entry[:nodes].push(node)
  nil

# Merge branch buckets using the Path-Max rule: across mutually exclusive
# branches (then / elsif / else), a single execution path hits a fetch at most
# `max(branch_1, branch_2, ...)` times.
-> perf_merge_branch_buckets(target_bucket, branch_buckets)
  seen_sigs = {}
  bi = 0
  while bi < branch_buckets.size()
    b = branch_buckets[bi]
    b.keys().each -> (sig)
      seen_sigs[sig] = true
    bi += 1

  seen_sigs.keys().each -> (sig)
    max_count = 0
    chosen = nil
    all_lines = []
    all_nodes = []
    in_cond = false
    bi = 0
    while bi < branch_buckets.size()
      b = branch_buckets[bi]
      e = b[sig]
      if e != nil
        if e[:count] > max_count
          max_count = e[:count]
          chosen = e
        if e[:in_cond]
          in_cond = true
        li = 0
        while li < e[:lines].size()
          all_lines.push(e[:lines][li])
          li += 1
        ni = 0
        while ni < e[:nodes].size()
          all_nodes.push(e[:nodes][ni])
          ni += 1
      bi += 1
    if chosen != nil && max_count > 0
      existing = target_bucket[sig]
      if existing == nil
        target_bucket[sig] = {
          sig: sig,
          expr: chosen[:expr],
          receiver: chosen[:receiver],
          deps: chosen[:deps],
          count: max_count,
          in_cond: in_cond,
          lines: all_lines,
          nodes: all_nodes
        }
      else
        existing[:count] = existing[:count] + max_count
        if in_cond
          existing[:in_cond] = true
        li = 0
        while li < all_lines.size()
          existing[:lines].push(all_lines[li])
          li += 1
        ni = 0
        while ni < all_nodes.size()
          existing[:nodes].push(all_nodes[ni])
          ni += 1
  nil

-> perf_clone_epochs(epochs)
  out = {}
  epochs.keys().each -> (k)
    out[k] = epochs[k]
  out

# Walk an expression or statement in the current loop's direct iteration scope
# (stops at nested child loops so child loops are analyzed in their own scope).
-> perf_walk_loop_scope(node, in_cond, cur_line, epochs, bucket)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      perf_walk_loop_scope(node[i], in_cond, cur_line, epochs, bucket)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil

  ln = perf_node_line(node, cur_line)
  k = ast_kind(node)

  # Do not merge a nested loop's body into the parent loop's single-iteration
  # count; nested loops are analyzed as their own loop entries (though any
  # mutations inside the nested loop still advance the parent's epochs!).
  if k == :while
    perf_bump_epochs_for_subtree(node, epochs)
    return nil
  if perf_iterator_call?(node)
    perf_walk_loop_scope(node.receiver, in_cond, ln, epochs, bucket)
    perf_bump_epochs_for_subtree(node.block, epochs)
    return nil

  if k == :assign
    # RHS is evaluated first; LHS target is written (if LHS is `a[i] = v`,
    # the index expressions inside `a[i]` are read, not `a[i]` itself).
    perf_walk_loop_scope(node.value, in_cond, ln, epochs, bucket)
    target = node.target
    if target != nil && is_ast_node?(target)
      tk = ast_kind(target)
      if tk == :call && target.receiver != nil
        perf_walk_loop_scope(target.receiver, in_cond, ln, epochs, bucket)
        perf_walk_loop_scope(target.args, in_cond, ln, epochs, bucket)
      elsif tk == :view_access
        perf_walk_loop_scope(target.index, in_cond, ln, epochs, bucket)
      elsif tk == :view_field_var
        perf_walk_loop_scope(target.receiver, in_cond, ln, epochs, bucket)
    perf_bump_epochs_for_subtree(node, epochs)
    return nil

  if k == :compound_assign
    # `target += value` reads `target`, evaluates `value`, then mutates `target`.
    perf_walk_loop_scope(node.target, in_cond, ln, epochs, bucket)
    perf_walk_loop_scope(node.value, in_cond, ln, epochs, bucket)
    perf_bump_epochs_for_subtree(node, epochs)
    return nil

  if k == :multi_assign
    perf_walk_loop_scope(node.value, in_cond, ln, epochs, bucket)
    perf_bump_epochs_for_subtree(node, epochs)
    return nil

  if k == :if
    perf_walk_loop_scope(node.condition, in_cond, ln, epochs, bucket)
    branches = []
    b_then = {}
    perf_walk_loop_scope(node.then_body, in_cond, ln, perf_clone_epochs(epochs), b_then)
    branches.push(b_then)
    elsifs = node.elsif_clauses
    if elsifs != nil
      ei = 0
      while ei < elsifs.size()
        clause = elsifs[ei]
        b_el = {}
        ep_el = perf_clone_epochs(epochs)
        if type(clause) == "Array" && clause.size() >= 2
          perf_walk_loop_scope(clause[0], in_cond, ln, ep_el, b_el)
          perf_walk_loop_scope(clause[1], in_cond, ln, ep_el, b_el)
        elsif is_ast_node?(clause)
          perf_walk_loop_scope(clause.condition, in_cond, ln, ep_el, b_el)
          perf_walk_loop_scope(clause.body, in_cond, ln, ep_el, b_el)
        branches.push(b_el)
        ei += 1
    if node.else_body != nil
      b_else = {}
      perf_walk_loop_scope(node.else_body, in_cond, ln, perf_clone_epochs(epochs), b_else)
      branches.push(b_else)
    perf_merge_branch_buckets(bucket, branches)
    perf_bump_epochs_for_subtree(node, epochs)
    return nil

  if k == :case || k == :case_value
    if k == :case_value
      perf_walk_loop_scope(node.subject, in_cond, ln, epochs, bucket)
    branches = []
    arms = (k == :case) ? node.whens : node.arms
    if arms != nil
      ai = 0
      while ai < arms.size()
        arm = arms[ai]
        b_arm = {}
        ep_arm = perf_clone_epochs(epochs)
        if is_ast_node?(arm)
          if ast_kind(arm) == :when
            perf_walk_loop_scope(arm.conditions, in_cond, ln, ep_arm, b_arm)
            perf_walk_loop_scope(arm.body, in_cond, ln, ep_arm, b_arm)
          elsif ast_kind(arm) == :case_arm
            perf_walk_loop_scope(arm.guard, in_cond, ln, ep_arm, b_arm)
            perf_walk_loop_scope(arm.body, in_cond, ln, ep_arm, b_arm)
        branches.push(b_arm)
        ai += 1
    if node.else_body != nil
      b_else = {}
      perf_walk_loop_scope(node.else_body, in_cond, ln, perf_clone_epochs(epochs), b_else)
      branches.push(b_else)
    perf_merge_branch_buckets(bucket, branches)
    perf_bump_epochs_for_subtree(node, epochs)
    return nil

  if perf_is_fetch_node?(node)
    perf_record_fetch(node, in_cond, ln, epochs, bucket)
    # Also walk sub-expressions (e.g. `a[b[i]]` records both `a[b[i]]` and `b[i]`,
    # but don't double-record `node.receiver` if `node.receiver` is a bare `:ivar`/`:gvar`
    # when `node` is `@arr[i]`).
    if k == :call
      if !(is_ast_node?(node.receiver) && ast_kind(node.receiver) in (:ivar :gvar))
        perf_walk_loop_scope(node.receiver, in_cond, ln, epochs, bucket)
      perf_walk_loop_scope(node.args, in_cond, ln, epochs, bucket)
    elsif k == :view_access
      perf_walk_loop_scope(node.index, in_cond, ln, epochs, bucket)
    elsif k == :view_field_var
      if !(is_ast_node?(node.receiver) && ast_kind(node.receiver) in (:ivar :gvar))
        perf_walk_loop_scope(node.receiver, in_cond, ln, epochs, bucket)
    return nil

  kids = ast_children(node)
  i = 0
  while i < kids.size()
    perf_walk_loop_scope(kids[i], in_cond, ln, epochs, bucket)
    i += 1
  if k == :call && node.receiver != nil && perf_mutating_method?(node.name.to_s())
    perf_bump_epochs_for_subtree(node, epochs)
  nil

-> perf_dedup_ints(arr)
  out = []
  seen = {}
  i = 0
  while i < arr.size()
    v = arr[i]
    if v != nil && seen[v] == nil
      seen[v] = true
      out.push(v)
    i += 1
  out

-> perf_analyze_single_loop(loop_node, loop_id, fn_name, file_path, loop_depth, loops_out, findings_out)
  k = ast_kind(loop_node)
  ln = perf_node_line(loop_node, 0)
  cond_node = nil
  body_node = nil
  loop_desc = "while"
  if k == :while
    cond_node = loop_node.condition
    body_node = loop_node.body
    loop_desc = "while " + perf_expr_to_s(cond_node)
  else
    # Iterator call (`recv.each -> (x) ...`)
    cond_node = loop_node.receiver
    body_node = loop_node.block
    loop_desc = perf_expr_to_s(loop_node.receiver) + "." + loop_node.name.to_s()

  mutated_vars = {}
  mutated_recvs = {}
  perf_collect_mutations(body_node, mutated_vars, mutated_recvs)

  epochs = {}
  bucket = {}
  if k == :while
    perf_walk_loop_scope(cond_node, true, ln, epochs, bucket)
    perf_walk_loop_scope(body_node, false, ln, epochs, bucket)
  else
    if loop_node.block != nil && is_ast_node?(loop_node.block)
      perf_walk_loop_scope(loop_node.block.body, false, ln, epochs, bucket)

  loop_findings = []
  sigs = bucket.keys()
  si = 0
  while si < sigs.size()
    entry = bucket[sigs[si]]
    expr_str = entry[:expr]
    count = entry[:count]
    deps = entry[:deps]
    rname = entry[:receiver]
    lines = perf_dedup_ints(entry[:lines])

    # Check if this fetch is loop-invariant (none of its deps are in mutated_vars,
    # and its base receiver is not in mutated_recvs).
    invariant = true
    if rname != nil && (mutated_vars[rname] == true || mutated_recvs[rname] == true)
      invariant = false
    if invariant
      dep_keys = deps.keys()
      di = 0
      while di < dep_keys.size()
        dv = dep_keys[di]
        if mutated_vars[dv] == true || mutated_recvs[dv] == true
          invariant = false
        di += 1

    if count >= 2
      site_id = findings_out.size()
      kind_tag = invariant ? "repeated_loop_invariant_fetch" : "repeated_fetch"
      advice = invariant ? "Hoist `" + expr_str + "` before the loop (fetched " + count.to_s() + "x per iteration and loop-invariant)." : "Cache `" + expr_str + "` in a local variable at the start of the iteration (fetched " + count.to_s() + "x per iteration without mutation)."
      f = {
        site_id: site_id,
        loop_id: loop_id,
        category: kind_tag,
        function: fn_name,
        file: file_path,
        line: lines.size() > 0 ? lines[0] : ln,
        lines: lines,
        loop_line: ln,
        loop_depth: loop_depth,
        loop_desc: loop_desc,
        expr: expr_str,
        count_per_iter: count,
        loop_invariant: invariant,
        explanation: "`" + expr_str + "` is fetched " + count.to_s() + "x per iteration in `" + loop_desc + "` (depth " + loop_depth.to_s() + ").",
        suggestion: advice,
        nodes: entry[:nodes]
      }
      findings_out.push(f)
      loop_findings.push(f)
    elsif invariant && (entry[:in_cond] || loop_depth >= 2)
      # Single-occurrence loop-invariant fetch in a `while` condition (e.g.
      # `while i < arr.size()`) or inside a nested inner loop (`depth >= 2`).
      site_id = findings_out.size()
      where_str = entry[:in_cond] ? "in loop condition" : ("inside depth-" + loop_depth.to_s() + " inner loop")
      f = {
        site_id: site_id,
        loop_id: loop_id,
        category: "loop_invariant_fetch",
        function: fn_name,
        file: file_path,
        line: lines.size() > 0 ? lines[0] : ln,
        lines: lines,
        loop_line: ln,
        loop_depth: loop_depth,
        loop_desc: loop_desc,
        expr: expr_str,
        count_per_iter: 1,
        loop_invariant: true,
        explanation: "Loop-invariant `" + expr_str + "` is re-evaluated every cycle " + where_str + " (`" + loop_desc + "`).",
        suggestion: "Hoist `" + expr_str + "` into a local variable outside the loop.",
        nodes: entry[:nodes]
      }
      findings_out.push(f)
      loop_findings.push(f)
    si += 1

  ast_set(loop_node, :perf_loop_id, loop_id)
  loop_info = {
    loop_id: loop_id,
    function: fn_name,
    file: file_path,
    line: ln,
    depth: loop_depth,
    desc: loop_desc,
    findings_count: loop_findings.size(),
    node: loop_node
  }
  loops_out.push(loop_info)
  nil

-> perf_walk_ast(node, fn_name, class_name, file_path, loop_depth, loops_out, findings_out)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      perf_walk_ast(node[i], fn_name, class_name, file_path, loop_depth, loops_out, findings_out)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil

  sp = ast_get(node, :source_path)
  cur_file = (sp != nil && sp != "") ? sp : file_path
  k = ast_kind(node)

  if k == :file
    f_path = node.path != nil ? node.path.to_s() : cur_file
    return perf_walk_ast(node.body, fn_name, class_name, f_path, loop_depth, loops_out, findings_out)

  if k == :class_def || k == :module_def
    cname = node.name.to_s()
    if class_name != nil && class_name != ""
      cname = class_name + ":" + cname
    return perf_walk_ast(node.body, fn_name, cname, cur_file, loop_depth, loops_out, findings_out)

  if k == :fn_def || k == :gpu_kernel_def
    fname = node.name.to_s()
    if class_name != nil && class_name != ""
      fname = class_name + "." + fname
    return perf_walk_ast(node.body, fname, class_name, cur_file, 0, loops_out, findings_out)

  if k == :method_def
    mname = node.name.to_s()
    sep = node.is_class_method ? "." : "#"
    full = (class_name != nil && class_name != "") ? (class_name + sep + mname) : mname
    return perf_walk_ast(node.body, full, class_name, cur_file, 0, loops_out, findings_out)

  if k == :while || perf_iterator_call?(node)
    lid = loops_out.size()
    next_depth = loop_depth + 1
    perf_analyze_single_loop(node, lid, fn_name, cur_file, next_depth, loops_out, findings_out)
    kids = ast_children(node)
    i = 0
    while i < kids.size()
      perf_walk_ast(kids[i], fn_name, class_name, cur_file, next_depth, loops_out, findings_out)
      i += 1
    return nil

  kids = ast_children(node)
  i = 0
  while i < kids.size()
    perf_walk_ast(kids[i], fn_name, class_name, cur_file, loop_depth, loops_out, findings_out)
    i += 1
  nil

# Filter to the entry source file when inspecting a multi-file Loader AST.
-> perf_same_source?(path, entry_path)
  if entry_path == nil || entry_path == "" || path == nil || path == ""
    return true
  if path == entry_path
    return true
  file_expand_path(path) == file_expand_path(entry_path)

-> perf_inspect_ast(ast, source_path = "(source)", entry_only = true)
  all_loops = []
  all_findings = []
  perf_walk_ast(ast, "<top>", nil, source_path, 0, all_loops, all_findings)

  loops = []
  findings = []
  entry_raw_loops = []
  entry_raw_findings = []
  old_to_new_loop = {}
  li = 0
  while li < all_loops.size()
    lp = all_loops[li]
    if !entry_only || perf_same_source?(lp[:file], source_path)
      new_lid = loops.size()
      old_to_new_loop[lp[:loop_id]] = new_lid
      lp[:loop_id] = new_lid
      if lp[:node] != nil && is_ast_node?(lp[:node])
        ast_set(lp[:node], :perf_loop_id, new_lid)
      entry_raw_loops.push(lp)
      loops.push({
        loop_id: new_lid,
        function: lp[:function],
        file: lp[:file],
        line: lp[:line],
        depth: lp[:depth],
        desc: lp[:desc],
        findings_count: lp[:findings_count]
      })
    li += 1

  fi = 0
  while fi < all_findings.size()
    fd = all_findings[fi]
    if !entry_only || perf_same_source?(fd[:file], source_path)
      new_sid = findings.size()
      new_lid = old_to_new_loop[fd[:loop_id]]
      if new_lid == nil
        new_lid = fd[:loop_id]
      fd[:site_id] = new_sid
      fd[:loop_id] = new_lid
      entry_raw_findings.push(fd)
      findings.push({
        site_id: new_sid,
        loop_id: new_lid,
        category: fd[:category],
        function: fd[:function],
        file: fd[:file],
        line: fd[:line],
        lines: fd[:lines],
        loop_line: fd[:loop_line],
        loop_depth: fd[:loop_depth],
        loop_desc: fd[:loop_desc],
        expr: fd[:expr],
        count_per_iter: fd[:count_per_iter],
        loop_invariant: fd[:loop_invariant],
        explanation: fd[:explanation],
        suggestion: fd[:suggestion]
      })
    fi += 1

  {
    schema_version: 1,
    phase: "ast_perf_inspect",
    source: source_path,
    loop_count: loops.size(),
    finding_count: findings.size(),
    loops: loops,
    findings: findings,
    raw_loops: entry_raw_loops,
    raw_findings: entry_raw_findings
  }

-> perf_inspect_source(source, source_path = "(source)")
  source = ccall("w_algebra_rewrite_source", source)
  lexer = Lexer.new(source, source_path)
  token_count = lexer.tokenize()
  parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
  ast = parser.parse()
  perf_inspect_ast(ast, source_path, false)

-> perf_inspect_file(file_path)
  source = read_file(file_path)
  if source == nil
    return nil
  perf_inspect_source(source, file_path)

# Format the AST Performance Inspection report as human-readable text.
# Optional `hot_fns` (Hash of func_name => sample_pct_x10 or true) and
# `dyn_loops` / `dyn_sites` (Hashes of loop_id/site_id => dynamic_count)
# enrich the report when called from `tungsten flame`.
-> perf_inspect_report_text(report, use_color = false, top_n = 20, hot_fns = nil, dyn_loops = nil, dyn_sites = nil)
  bold   = use_color ? "\e\[1m" : ""
  dim    = use_color ? "\e\[2m" : ""
  yellow = use_color ? "\e\[33m" : ""
  cyan   = use_color ? "\e\[36m" : ""
  green  = use_color ? "\e\[32m" : ""
  reset  = use_color ? "\e\[0m" : ""

  out = StringBuffer(1024)
  out << "\n  " << bold << "AST Performance Inspection (Loops & Redundant Fetches)" << reset << "\n"
  out << "  " << dim << "Source: " << report[:source].to_s() << " (" << report[:loop_count].to_s() << " loops analyzed, " << report[:finding_count].to_s() << " fetch optimization sites)" << reset << "\n"

  findings = report[:findings]
  if findings == nil || findings.size() == 0
    out << "  " << green << "No redundant per-iteration or loop-invariant fetches detected." << reset << "\n"
    return out.to_s()

  # Rank findings: prioritize findings in hot functions, then dynamic hits (if
  # available), then (count_per_iter * loop_depth).
  ranked = []
  i = 0
  while i < findings.size()
    f = findings[i]
    score = f[:count_per_iter] * 100 + f[:loop_depth] * 25
    if f[:category] == "repeated_loop_invariant_fetch"
      score += 50
    is_hot = false
    if hot_fns != nil && hot_fns.has_key?(f[:function])
      is_hot = true
      score += 10000
    dyn_iter = nil
    dyn_hit = nil
    if dyn_loops != nil && dyn_loops.has_key?(f[:loop_id])
      dyn_iter = dyn_loops[f[:loop_id]]
    if dyn_sites != nil && dyn_sites.has_key?(f[:site_id])
      dyn_hit = dyn_sites[f[:site_id]]
      score += dyn_hit
    elsif dyn_iter != nil
      dyn_hit = dyn_iter * f[:count_per_iter]
      score += dyn_hit
    ranked.push({finding: f, score: score, hot: is_hot, dyn_iter: dyn_iter, dyn_hit: dyn_hit})
    i += 1

  # Insertion sort descending by score
  j = 1
  while j < ranked.size()
    item = ranked[j]
    k = j - 1
    while k >= 0 && ranked[k][:score] < item[:score]
      ranked[k + 1] = ranked[k]
      k -= 1
    ranked[k + 1] = item
    j += 1

  limit = ranked.size()
  if top_n > 0 && limit > top_n
    limit = top_n

  i = 0
  while i < limit
    r = ranked[i]
    f = r[:finding]
    lines_s = ""
    if f[:lines] != nil && f[:lines].size() > 0
      lparts = []
      li = 0
      while li < f[:lines].size()
        lparts.push("L" + f[:lines][li].to_s())
        li += 1
      lines_s = lparts.join(", ")
    else
      lines_s = "L" + f[:line].to_s()

    badge = f[:category] == "loop_invariant_fetch" ? "\[loop-invariant]" : ("\[fetched " + f[:count_per_iter].to_s() + "x/iter]")
    hot_tag = r[:hot] ? (" " + yellow + "★ HOT FN" + reset) : ""
    out << "\n    " << cyan << badge << reset << " " << bold << "`" << f[:expr] << "`" << reset << " in " << bold << f[:function] << reset << " (" << f[:file].to_s() << ":" << f[:loop_line].to_s() << ", " << lines_s << ", depth " << f[:loop_depth].to_s() << ")" << hot_tag << "\n"
    if r[:dyn_iter] != nil
      wasted = 0
      if f[:loop_invariant]
        wasted = r[:dyn_hit] > 1 ? (r[:dyn_hit] - 1) : 0
      elsif r[:dyn_hit] > r[:dyn_iter]
        wasted = r[:dyn_hit] - r[:dyn_iter]
      out << "      " << yellow << "Dynamic:" << reset << " loop ran " << r[:dyn_iter].to_s() << " iters, fetched " << r[:dyn_hit].to_s() << " times (" << wasted.to_s() << " redundant fetches)\n"
    out << "      " << dim << "Loop: " << f[:loop_desc] << reset << "\n"
    out << "      " << green << "Fix:  " << reset << f[:suggestion] << "\n"
    i += 1

  if ranked.size() > limit
    out << "\n    " << dim << "(+" << (ranked.size() - limit).to_s() << " more sites; pass --top N to view more)" << reset << "\n"
  out.to_s()

# Strip non-JSON-serializable raw AST node handles before JSON.encode.
-> perf_inspect_json_safe(report)
  {
    schema_version: report[:schema_version],
    phase: report[:phase],
    source: report[:source],
    loop_count: report[:loop_count],
    finding_count: report[:finding_count],
    loops: report[:loops],
    findings: findings_without_nodes(report[:findings])
  }

-> findings_without_nodes(findings)
  out = []
  if findings == nil
    return out
  i = 0
  while i < findings.size()
    fd = findings[i]
    out.push({
      site_id: fd[:site_id],
      loop_id: fd[:loop_id],
      category: fd[:category],
      function: fd[:function],
      file: fd[:file],
      line: fd[:line],
      lines: fd[:lines],
      loop_line: fd[:loop_line],
      loop_depth: fd[:loop_depth],
      loop_desc: fd[:loop_desc],
      expr: fd[:expr],
      count_per_iter: fd[:count_per_iter],
      loop_invariant: fd[:loop_invariant],
      explanation: fd[:explanation],
      suggestion: fd[:suggestion]
    })
    i += 1
  out

# Build `$gvar = $gvar + 1` AST statement.
-> perf_make_gvar_inc(gvar_name)
  gv = Tungsten:AST:GVar.new(gvar_name)
  Tungsten:AST:Assign.new(gv, Tungsten:AST:BinaryOp.new(gv, :PLUS, Tungsten:AST:Int.new(1)))

# Recursively wrap flagged fetch AST nodes in Passthrough counter increments
# and hook bare `exit(...)` calls to flush dynamic counters before exiting.
-> perf_rewrite_ast_nodes(node, site_map)
  if node == nil
    return nil
  if type(node) == "Array"
    out = []
    changed = false
    i = 0
    while i < node.size()
      orig = node[i]
      rew = perf_rewrite_ast_nodes(orig, site_map)
      if wvalue_bits(rew) != wvalue_bits(orig)
        changed = true
      out.push(rew)
      i += 1
    return changed ? out : node
  if !is_ast_node?(node)
    return node

  k = ast_kind(node)
  # Never instrument inside @gpu kernels (compiled to MSL/CUDA).
  if k == :gpu_kernel_def || k == :schedule_def || k == :layout_def
    return node

  packed = ccall_nobox("w_is_node_extern", node) == 1
  if packed
    kid = ccall_nobox("w_node_kind_extern", node)
    offsets = slab_child_offsets_table[kid]
    keys = slab_child_keys_table[kid]
    if offsets != nil
      i = 0
      while i < offsets.size()
        slot_key = keys != nil ? keys[i] : nil
        # Do not wrap the LHS target slot of an assignment.
        if !((k == :assign || k == :compound_assign) && slot_key == :target) && !(k == :multi_assign && slot_key == :targets)
          child = ccall_nobox("w_node_field_load", node, offsets[i])
          if child != nil
            if is_ast_node?(child) || type(child) == "Array"
              rewritten = perf_rewrite_ast_nodes(child, site_map)
              if wvalue_bits(rewritten) != wvalue_bits(child)
                ccall_nobox("w_node_field_store", node, offsets[i], rewritten)
        i += 1

  if k == :call && node.receiver == nil && node.name.to_s() == "exit"
    dump_call = Tungsten:AST:Call.new(nil, "__w_perf_inspect_dump", [])
    return Tungsten:AST:Passthrough.new(dump_call, node)

  if k in (:call :view_access :view_field_var)
    bits = wvalue_bits(node)
    sid = site_map[bits]
    if sid != nil
      inc_stmt = perf_make_gvar_inc("$__w_pi_s_" + sid.to_s())
      return Tungsten:AST:Passthrough.new(inc_stmt, node)

  node

# Instrument `ast` in-place using the loops and findings from `report`.
# Emits `TPERF_LOOP <loop_id> <iters>` and `TPERF_SITE <site_id> <hits>` to
# stderr on program completion or `exit(...)`.
-> perf_inspect_instrument_ast(ast, report)
  if ast == nil || report == nil
    return ast
  raw_loops = report[:raw_loops]
  raw_findings = report[:raw_findings]
  if raw_loops == nil || raw_loops.size() == 0
    return ast

  site_map = {}
  if raw_findings != nil
    fi = 0
    while fi < raw_findings.size()
      fd = raw_findings[fi]
      sid = fd[:site_id]
      fnodes = fd[:nodes]
      if fnodes != nil
        ni = 0
        while ni < fnodes.size()
          fnode = fnodes[ni]
          if fnode != nil && is_ast_node?(fnode) && ast_kind(fnode) in (:call :view_access :view_field_var)
            site_map[wvalue_bits(fnode)] = sid
          ni += 1
      fi += 1

  perf_rewrite_ast_nodes(ast, site_map)

  # Prepend per-iteration counter increments to each loop body.
  li = 0
  while li < raw_loops.size()
    lp = raw_loops[li]
    lid = lp[:loop_id]
    lnode = lp[:node]
    if lnode != nil && is_ast_node?(lnode)
      inc_stmt = perf_make_gvar_inc("$__w_pi_l_" + lid.to_s())
      if ast_kind(lnode) == :while
        new_body = [inc_stmt]
        old_body = lnode.body
        if old_body != nil
          bi = 0
          while bi < old_body.size()
            new_body.push(old_body[bi])
            bi += 1
        lnode.body = new_body
      elsif perf_iterator_call?(lnode) && lnode.block != nil && is_ast_node?(lnode.block)
        new_body = [inc_stmt]
        old_body = lnode.block.body
        if old_body != nil
          bi = 0
          while bi < old_body.size()
            new_body.push(old_body[bi])
            bi += 1
        lnode.block.body = new_body
    li += 1

  # Build top-level counter initializers and `__w_perf_inspect_dump` fn.
  init_stmts = []
  dump_body = []
  guard_gv = Tungsten:AST:GVar.new("$__w_pi_dumped")
  init_stmts.push(Tungsten:AST:Assign.new(guard_gv, Tungsten:AST:Int.new(0)))
  dump_body.push(Tungsten:AST:If.new(
    Tungsten:AST:BinaryOp.new(guard_gv, :EQ, Tungsten:AST:Int.new(1)),
    [Tungsten:AST:Return.new(Tungsten:AST:Int.new(0))]
  ))
  dump_body.push(Tungsten:AST:Assign.new(guard_gv, Tungsten:AST:Int.new(1)))

  li = 0
  while li < raw_loops.size()
    lid = raw_loops[li][:loop_id]
    gname = "$__w_pi_l_" + lid.to_s()
    gv = Tungsten:AST:GVar.new(gname)
    init_stmts.push(Tungsten:AST:Assign.new(gv, Tungsten:AST:Int.new(0)))
    to_s_call = Tungsten:AST:Call.new(gv, "to_s", [])
    msg = Tungsten:AST:BinaryOp.new(Tungsten:AST:String.new("TPERF_LOOP " + lid.to_s() + " "), :PLUS, to_s_call)
    eputs_call = Tungsten:AST:Call.new(nil, "ccall", [Tungsten:AST:String.new("w_eputs"), msg])
    dump_body.push(Tungsten:AST:If.new(
      Tungsten:AST:BinaryOp.new(gv, :GT, Tungsten:AST:Int.new(0)),
      [eputs_call]
    ))
    li += 1

  if raw_findings != nil
    fi = 0
    while fi < raw_findings.size()
      sid = raw_findings[fi][:site_id]
      gname = "$__w_pi_s_" + sid.to_s()
      gv = Tungsten:AST:GVar.new(gname)
      init_stmts.push(Tungsten:AST:Assign.new(gv, Tungsten:AST:Int.new(0)))
      to_s_call = Tungsten:AST:Call.new(gv, "to_s", [])
      msg = Tungsten:AST:BinaryOp.new(Tungsten:AST:String.new("TPERF_SITE " + sid.to_s() + " "), :PLUS, to_s_call)
      eputs_call = Tungsten:AST:Call.new(nil, "ccall", [Tungsten:AST:String.new("w_eputs"), msg])
      dump_body.push(Tungsten:AST:If.new(
        Tungsten:AST:BinaryOp.new(gv, :GT, Tungsten:AST:Int.new(0)),
        [eputs_call]
      ))
      fi += 1

  dump_body.push(Tungsten:AST:Int.new(0))
  dump_fn = Tungsten:AST:FnDef.new("__w_perf_inspect_dump", [], dump_body)
  init_stmts.push(dump_fn)

  prog = ast
  if ast_kind(prog) == :file
    prog = prog.body
  if prog != nil && is_ast_node?(prog) && ast_kind(prog) == :program
    old_exprs = prog.expressions
    new_exprs = []
    # Keep `use` and `in` directives at the very top of the program.
    idx = 0
    while idx < old_exprs.size()
      st = old_exprs[idx]
      if st != nil && is_ast_node?(st) && ast_kind(st) in (:use :namespace_decl)
        new_exprs.push(st)
        idx += 1
      else
        break
    ii = 0
    while ii < init_stmts.size()
      new_exprs.push(init_stmts[ii])
      ii += 1
    while idx < old_exprs.size()
      new_exprs.push(old_exprs[idx])
      idx += 1
    new_exprs.push(Tungsten:AST:Call.new(nil, "__w_perf_inspect_dump", []))
    prog.expressions = new_exprs
  ast

# Parse `TPERF_LOOP <id> <count>` and `TPERF_SITE <id> <count>` lines from output.
-> perf_parse_dynamic_output(text)
  dyn_loops = {}
  dyn_sites = {}
  if text == nil || text == ""
    return [dyn_loops, dyn_sites]
  lines = text.split("\n")
  i = 0
  while i < lines.size()
    ln = lines[i].strip()
    if ln.starts_with?("TPERF_LOOP ")
      parts = ln.split(" ")
      if parts.size() >= 3
        dyn_loops[parts[1].to_i()] = parts[2].to_i()
    elsif ln.starts_with?("TPERF_SITE ")
      parts = ln.split(" ")
      if parts.size() >= 3
        dyn_sites[parts[1].to_i()] = parts[2].to_i()
    i += 1
  [dyn_loops, dyn_sites]

