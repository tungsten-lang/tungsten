# Lowering / analysis — pre-passes that analyze AST shape before
# lowering. Depends on pass_registry.w and types.w.
#
# Includes loop-var unboxing detection, integer-promotion / escape
# classification, raw-int candidate maps, param reassignment scans, and
# scan_assigns_for_params.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).


# Find variables safe to keep unboxed through a while loop:
# must be :int in var_types, only modified via compound_assign, never full-assigned,
# and only use compound ops that cannot overflow the raw i64 slot representation.
-> find_unboxable_loop_vars(body, condition, var_types)
  # Collect all vars modified via compound assign
  compound_vars = {}
  # Collect all vars fully assigned (disqualifying)
  assigned_vars = {}
  scan_loop_vars(body, compound_vars, assigned_vars, var_types)
  scan_loop_vars([condition], compound_vars, assigned_vars, var_types)

  # As of 2026-04-15: overflow_vars exclusion removed. Under the
  # silent-wrap semantics locked in by the plan, any compound +/-/* on
  # a loop-local int can stay in a raw i64 slot and run as native
  # add_i64/sub_i64/mul_i64 with no bigint-promotion fallback. Users
  # who explicitly want bigint promotion can annotate `## int` to opt
  # back into the boxed path. This change is the primary perf
  # unblocker for the hot-loop story.
  result = []
  keys = compound_vars.keys()
  i = 0
  while i < keys.size()
    name = keys[i]
    loop_vt = var_types[name]
    if (loop_vt == :int || is_machine_int_type(loop_vt) || loop_vt == :raw_int || loop_vt == :raw_i64) && assigned_vars[name] == nil
      result.push(name)
    i += 1
  result

# Names of every var assigned (plain or compound) anywhere in a loop's body or
# condition. lower_while uses this to invalidate ONLY the bindings the loop
# actually made stale, so a var the loop never touches (e.g. an `## i64`-typed
# param used after the loop) keeps its binding and its raw-int type. Reuses
# scan_assigns_for_params (the trusted reassignment walker: recurses if / while /
# case / case_value) rather than scan_loop_vars — for a binding-clear a MISSED
# assignment is harmful (a stale binding survives), so err toward completeness.
-> find_loop_assigned_vars(body, condition)
  assigned = {}
  scan_assigns_for_params(body, assigned)
  scan_assigns_for_params([condition], assigned)
  assigned

-> scan_loop_vars(nodes, compound_vars, assigned_vars, var_types)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    node = nodes[i]
    if node == nil
      i += 1
      next
    t = ast_kind(node)
    if t == :compound_assign
      if ast_kind(node.target) == :var
        # Only keep a var unboxable if its compound-assign RHS is
        # int-shaped. A non-int RHS — e.g. an accumulator summing f64
        # (`acc += item * components[i]` in Vector#dot) — must stay a
        # boxed WValue so the runtime `w_add` promotes int+double; raw
        # unboxing would feed a double to ensure_raw_int and die with
        # "expected int, got numeric". Route those to assigned_vars so
        # the unbox filter below skips them.
        if int_shaped_node?(node.value, var_types)
          compound_vars[node.target.name] = true
        else
          assigned_vars[node.target.name] = true
    elsif t == :assign
      if ast_kind(node.target) == :var
        # Mirror the compound-assign rule: a plain reassignment whose RHS is
        # int-shaped (machine-int) can stay in a raw i64/u64 slot under the
        # silent-wrap semantics — e.g. an NTT/PRP accumulator
        # `s = (s * a + c) % p`. Only a non-int-shaped RHS (f64, bigint-
        # promoting, boxed value) disqualifies the var from unboxing.
        if int_shaped_node?(node.value, var_types)
          compound_vars[node.target.name] = true
        else
          assigned_vars[node.target.name] = true
    # Recurse into if branches but NOT into nested while loops
    # (nested loops get their own unboxing pass)
    if t == :if
      scan_loop_vars(node.then_body, compound_vars, assigned_vars, var_types)
      scan_loop_vars(node.else_body, compound_vars, assigned_vars, var_types)
      if node.elsif_clauses != nil
        j = 0
        while j < node.elsif_clauses.size()
          clause = node.elsif_clauses[j]
          scan_loop_vars(clause[1], compound_vars, assigned_vars, var_types)
          j += 1
    # For nested while: mark all modified vars as assigned (disqualify from outer unboxing)
    if t == :while
      scan_loop_vars(node.body, assigned_vars, assigned_vars, var_types)
    i += 1

# Scan function body for assignments to parameter names.
# Returns a list of parameter names that are reassigned somewhere in the body.
# ── Local int escape analysis ─────────────────────────────────────────
# Detect local vars that are exclusively used as raw machine ints (assigned
# from int literals or arithmetic, read only in arithmetic / comparisons /
# conditions / typed-array indices, never escape via string interp / method
# dispatch / fn arg / closure / return slot).
#
# Promoted vars get :i64 in child_var_types BEFORE body lowering runs, so
# the existing machine-int code paths handle them as if the user had written
# `## i64: name`.

-> ensure_promote_record(records, name)
  if records[name] == nil
    records[name] = {has_int_assign: false, has_other_assign: false, has_escape: false}
  records[name]

-> mark_subtree_escape(node, records)
  if node == nil
    return nil
  node_type = type(node)
  if node_type == "Array"
    i = 0
    while i < node.size()
      mark_subtree_escape(node[i], records)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    mark_subtree_escape(node[:body], records)
    return nil

  if t == :var
    rec = ensure_promote_record(records, node.name)
    rec[:has_escape] = true
    return nil

  case t
  when :call
    # Raw-consuming intrinsics take their arguments as machine ints with no
    # WValue boundary — mirror visit_promote_node's is_raw_ccall/is_raw_load
    # exemption here, so operands inside an escape position (e.g. `return
    # wvalue_from_bits(tag | x)`) are not force-boxed. wvalue_bits is NOT
    # exempt: its argument is a boxed WValue read.
    if node.receiver == nil && node.name in ("ccall_nobox" "ccall_rawargs" "wvalue_from_bits" "raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8" "popcount" "cttz" "array_load_u64" "array_store_u64" "prefetch" "mulhi" "addcarry" "subborrow")
      return nil
    mark_subtree_escape(node.receiver, records)
    mark_subtree_escape(node.args, records)
    mark_subtree_escape(node.block, records)

  when :program
    mark_subtree_escape(node.expressions, records)

  when :array
    mark_subtree_escape(node.elements, records)

  when :hash_literal
    mark_subtree_escape(node.entries, records)

  when :string_interp, :byte_array_interp
    mark_subtree_escape(node.parts, records)

  when :typed_array_new, :typed_array, :view_access
    mark_subtree_escape(node.size, records)
    mark_subtree_escape(node.index, records)

  when :assign, :compound_assign
    mark_subtree_escape(node.target, records)
    mark_subtree_escape(node.value, records)

  when :multi_assign
    mark_subtree_escape(node.targets, records)
    mark_subtree_escape(node.value, records)

  when :binary_op, :and, :or, :target_and, :target_or
    mark_subtree_escape(node.left, records)
    mark_subtree_escape(node.right, records)

  when :unary_op, :not
    mark_subtree_escape(node.operand, records)

  when :target_not
    mark_subtree_escape(node.expression, records)

  when :in_test
    mark_subtree_escape(node.lhs, records)
    mark_subtree_escape(node.elements, records)

  when :passthrough
    mark_subtree_escape(node.expression, records)
    mark_subtree_escape(node.value, records)

  when :type_ascription
    mark_subtree_escape(node.expression, records)

  when :range
    mark_subtree_escape(node.from, records)
    mark_subtree_escape(node.to, records)

  when :if
    mark_subtree_escape(node.condition, records)
    mark_subtree_escape(node.then_body, records)
    mark_subtree_escape(node.elsif_clauses, records)
    mark_subtree_escape(node.else_body, records)

  when :while
    mark_subtree_escape(node.condition, records)
    mark_subtree_escape(node.body, records)

  when :with, :parallel_with
    mark_subtree_escape(node.bindings, records)
    mark_subtree_escape(node.body, records)

  when :case
    mark_subtree_escape(node.whens, records)
    mark_subtree_escape(node.else_body, records)

  when :when
    mark_subtree_escape(node.conditions, records)
    mark_subtree_escape(node.body, records)

  when :case_value
    mark_subtree_escape(node.subject, records)
    mark_subtree_escape(node.arms, records)
    mark_subtree_escape(node.else_body, records)

  when :case_arm
    mark_subtree_escape(node.pattern, records)
    mark_subtree_escape(node.guard, records)
    mark_subtree_escape(node.body, records)

  when :safe_nav
    mark_subtree_escape(node.receiver, records)
    mark_subtree_escape(node.args, records)
    mark_subtree_escape(node.block, records)

  when :rescue_expr
    mark_subtree_escape(node.body, records)
    mark_subtree_escape(node.fallback, records)

  when :puts
    # node.value is a list of print-args; each escapes (consumed by print).
    vals = node.value
    i = 0
    while i < vals.size()
      mark_subtree_escape(vals[i], records)
      i += 1

  when :return, :print, :raise, :recase
    mark_subtree_escape(node.value, records)

  when :class_def, :module_def, :trait_def
    mark_subtree_escape(node.superclass, records)
    free_scan_list(node.body, {}, records)

  when :method_def, :fn_def, :gpu_kernel_def
    mark_nested_def_free_reads(node, records)

  when :param
    mark_subtree_escape(node.default, records)

  when :block
    mark_subtree_escape(node.params, records)
    mark_subtree_escape(node.body, records)

  when :begin
    mark_subtree_escape(node.body, records)
    mark_subtree_escape(node.rescue_body, records)
    mark_subtree_escape(node.ensure_body, records)

  when :yield, :super
    mark_subtree_escape(node.args, records)

  when :go
    mark_subtree_escape(node.body, records)

  when :schedule_def, :layout_def
    mark_subtree_escape(node.directives, records)

  when :on_guard
    mark_subtree_escape(node.predicate, records)
    mark_subtree_escape(node.body, records)

  when :regex_match
    mark_subtree_escape(node.regex, records)
    mark_subtree_escape(node.subject, records)

  when :cidr_match
    mark_subtree_escape(node.subject, records)
    mark_subtree_escape(node.cidr, records)
  nil

# ── Scoped escape walk for nested definitions ────────────────────────────
# A nested definition (fn/method/class body) is its own scope: assigning a
# name inside it shadows the enclosing body's var from the point of
# assignment onward (`<< gx; gx = 9` reads the enclosing global slot, then
# binds a fresh local — both engines). Only FREE reads — a :var read at a
# point no binding dominates — reach the enclosing scope's global slot and
# must pin that var boxed. Walking def bodies position-blind (every :var an
# escape) made promotion depend on which names happen to be locals in
# autoloaded core methods: `x = <big>.to_i; << x % 97` stayed boxed while
# the identical program spelled `ab` promoted and wrapped. Binds are
# tracked in statement order; a branch arm's binds dominate only the rest
# of that arm, so each arm scans a copy of the bound set. Unmodeled kinds
# fall back to the position-blind walk (conservative, never unsound).

-> free_bound_copy(bound)
  copy = {}
  ks = bound.keys()
  i = 0
  while i < ks.size()
    copy[ks[i]] = true
    i += 1
  copy

-> free_bind_name(entry, bound)
  if entry == nil
    return nil
  if is_ast_node?(entry)
    if entry.name != nil
      bound[entry.name] = true
    return nil
  if type(entry) == "String"
    bound[entry] = true
  nil

-> free_bind_params(params, bound)
  if params == nil
    return nil
  i = 0
  while i < params.size()
    free_bind_name(params[i], bound)
    i += 1
  nil

-> mark_nested_def_free_reads(def_node, records)
  bound = {}
  params = def_node.params
  if params != nil
    i = 0
    while i < params.size()
      p = params[i]
      free_bind_name(p, bound)
      # Defaults evaluate in a scope with no binds established yet —
      # keep them position-blind.
      if p != nil && is_ast_node?(p) && ast_kind(p) == :param
        mark_subtree_escape(p.default, records)
      i += 1
  free_scan_list(def_node.body, bound, records)
  nil

-> free_scan_list(list, bound, records)
  if list == nil
    return nil
  if type(list) != "Array"
    free_scan_node(list, bound, records)
    return nil
  i = 0
  while i < list.size()
    free_scan_node(list[i], bound, records)
    i += 1
  nil

-> free_scan_node(node, bound, records)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      free_scan_node(node[i], bound, records)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    free_scan_list(node[:body], free_bound_copy(bound), records)
    return nil

  if t == :var
    if bound[node.name] != true
      rec = ensure_promote_record(records, node.name)
      rec[:has_escape] = true
    return nil

  case t
  when :assign
    free_scan_node(node.value, bound, records)
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      bound[target.name] = true
    else
      free_scan_node(target, bound, records)

  when :compound_assign
    free_scan_node(node.value, bound, records)
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      # `x += v` reads x before binding it — a free read when unbound.
      free_scan_node(target, bound, records)
      bound[target.name] = true
    else
      free_scan_node(target, bound, records)

  when :multi_assign
    free_scan_node(node.value, bound, records)
    targets = node.targets
    if targets != nil
      i = 0
      while i < targets.size()
        tg = targets[i]
        if tg != nil && is_ast_node?(tg) && ast_kind(tg) == :var
          bound[tg.name] = true
        else
          free_scan_node(tg, bound, records)
        i += 1

  when :call
    free_scan_node(node.receiver, bound, records)
    free_scan_node(node.args, bound, records)
    if node.block != nil
      blk = node.block
      if is_ast_node?(blk) && ast_kind(blk) == :block
        inner = free_bound_copy(bound)
        free_bind_params(blk.params, inner)
        free_scan_list(blk.body, inner, records)
      else
        mark_subtree_escape(blk, records)

  when :block
    inner = free_bound_copy(bound)
    free_bind_params(node.params, inner)
    free_scan_list(node.body, inner, records)

  when :if
    free_scan_node(node.condition, bound, records)
    free_scan_list(node.then_body, free_bound_copy(bound), records)
    if node.elsif_clauses != nil
      j = 0
      while j < node.elsif_clauses.size()
        clause = node.elsif_clauses[j]
        if clause != nil && type(clause) == "Array" && clause.size() >= 2
          # An elsif condition only runs when earlier arms failed, so its
          # binds dominate this arm's body but never the code after the if.
          arm_bound = free_bound_copy(bound)
          free_scan_node(clause[0], arm_bound, records)
          free_scan_list(clause[1], arm_bound, records)
        j += 1
    free_scan_list(node.else_body, free_bound_copy(bound), records)

  when :while
    free_scan_node(node.condition, bound, records)
    free_scan_list(node.body, free_bound_copy(bound), records)

  when :case
    if node.whens != nil
      j = 0
      while j < node.whens.size()
        w = node.whens[j]
        if w != nil
          # A when-condition only runs when earlier arms failed — its binds
          # dominate this arm's body but never the code after the case.
          w_bound = free_bound_copy(bound)
          if w.conditions != nil
            k = 0
            while k < w.conditions.size()
              free_scan_node(w.conditions[k], w_bound, records)
              k += 1
          free_scan_list(w.body, w_bound, records)
        j += 1
    free_scan_list(node.else_body, free_bound_copy(bound), records)

  when :case_value
    if node.subject != nil
      free_scan_node(node.subject, bound, records)
    if node.arms != nil
      j = 0
      while j < node.arms.size()
        a = node.arms[j]
        if a != nil
          free_scan_list(a.body, free_bound_copy(bound), records)
        j += 1
    free_scan_list(node.else_body, free_bound_copy(bound), records)

  when :begin
    free_scan_list(node.body, free_bound_copy(bound), records)
    if node.rescue_body != nil
      inner = free_bound_copy(bound)
      free_bind_name(node.rescue_var, inner)
      free_scan_list(node.rescue_body, inner, records)
    free_scan_list(node.ensure_body, free_bound_copy(bound), records)

  when :binary_op, :and, :or, :target_and, :target_or
    free_scan_node(node.left, bound, records)
    free_scan_node(node.right, bound, records)

  when :unary_op, :not
    free_scan_node(node.operand, bound, records)

  when :target_not
    free_scan_node(node.expression, bound, records)

  when :in_test
    free_scan_node(node.lhs, bound, records)
    free_scan_node(node.elements, bound, records)

  when :range
    free_scan_node(node.from, bound, records)
    free_scan_node(node.to, bound, records)

  when :array
    free_scan_node(node.elements, bound, records)

  when :hash_literal
    free_scan_node(node.entries, bound, records)

  when :string_interp, :byte_array_interp
    free_scan_node(node.parts, bound, records)

  when :typed_array_new, :typed_array, :view_access
    free_scan_node(node.size, bound, records)
    free_scan_node(node.index, bound, records)

  when :puts
    vals = node.value
    if vals != nil
      i = 0
      while i < vals.size()
        free_scan_node(vals[i], bound, records)
        i += 1

  when :return, :print, :raise, :recase
    free_scan_node(node.value, bound, records)

  when :passthrough
    free_scan_node(node.expression, bound, records)
    free_scan_node(node.value, bound, records)

  when :type_ascription
    free_scan_node(node.expression, bound, records)

  when :yield, :super
    free_scan_node(node.args, bound, records)

  when :program
    free_scan_list(node.expressions, bound, records)

  when :method_def, :fn_def, :gpu_kernel_def
    mark_nested_def_free_reads(node, records)

  when :class_def, :module_def, :trait_def
    mark_subtree_escape(node.superclass, records)
    free_scan_list(node.body, {}, records)

  when :int, :float, :string, :symbol, :nil, :boolean
    return nil

  else
    # Unmodeled kind: fall back to the position-blind escape walk. This
    # over-marks locally-bound names in the subtree — conservative, and
    # exactly the pre-scoping behavior.
    mark_subtree_escape(node, records)
  nil

# Return the exact machine return type of a call whose lowering is already
# proven to use a raw ABI.  The return annotation alone is insufficient:
# dynamic dispatch and boxed-ABI methods can also be annotated `i64`, but
# their LLVM register still contains a WValue at this point.
-> resolved_raw_machine_call_return_type(node, mod)
  if mod == nil || node == nil || !is_ast_node?(node) || ast_kind(node) != :call
    return nil
  # Attached blocks bypass both direct-static and raw top-level call paths.
  if node.block != nil
    return nil
  # Built-in constructors are intercepted before known-static dispatch.  A
  # same-named registry entry therefore does not prove which implementation
  # lower_method_call will select.
  if node.name == "new"
    return nil

  recv = node.receiver
  if recv == nil
    # Bare calls have several resolution lanes before the raw top-level
    # fallback (intrinsics and typed overloads among them).  Proving that the
    # name exists in raw_callable_fns is therefore insufficient to prove which
    # callee lower_call will select.  Keep this analysis conservative until it
    # can mirror that complete resolver.
    return nil

  # Mirror lower_method_call's direct-static receiver shapes exactly. Parser
  # output uses both ClassRef and Var for constant-like names, and the lowering
  # route resolves either through known_static_methods before generic dispatch.
  if !(ast_kind(recv) in (:var :class_ref :call)) || recv.name == nil
    return nil
  methods = mod[:known_static_methods]
  if methods == nil
    return nil
  recv_name = recv.name
  info = known_static_method_for(mod, recv_name + "." + node.name, node.args.size())

  # Mirror lower_method_call's inherited-static lookup. Only real static
  # entries participate in the superclass walk; the same registry also holds
  # typed instance methods used for `self.foo` devirtualization.
  if info == nil && node.name != "new"
    classes = mod[:known_classes]
    supers = mod[:class_super_names]
    if classes != nil && supers != nil && classes[recv_name] != nil
      current = recv_name
      guard = 0
      while info == nil && guard < 64
        current = supers[current]
        if current == nil
          break
        candidate = known_static_method_for(mod, current + "." + node.name, node.args.size())
        if candidate != nil && candidate[:is_static] == true
          info = candidate
        guard += 1

  # The same registry also contains typed instance-method entries used only
  # for `self.foo` devirtualization.  A class-style receiver must prove this
  # is a real static method before its raw worker ABI can justify a raw local.
  if info == nil || info[:is_static] != true || info[:raw_abi] != true
    return nil
  rt = info[:return_type]
  if is_machine_int64_type(rt)
    return rt
  nil

# True iff the expression is structurally raw-int — a literal int, an exactly
# resolved raw machine-returning call, or an arithmetic/bitwise op tree where
# every leaf is a known int source. Var references are accepted only if the
# referenced var is already declared or tentatively promoted with a
# machine-int type.
-> int_shaped_node?(node, declared_types, mod = nil)
  if node == nil
    return false
  if !is_ast_node?(node)
    return false
  t = ast_kind(node)
  case t
  when :int
    # A beyond-i64 literal (classified :dec_big at parse time) cannot
    # live in a raw machine slot — admitting it makes the enclosing tree
    # a machine-int candidate and the stored value wraps. `format` is an
    # eager field; reading the sparse raw/value fields here instead would
    # materialize packed nodes and break stage identity.
    return node.format != :dec_big
  when :char
    return true
  when :var
    vt = declared_types[node.name]
    return is_machine_int_type(vt) || vt in (:i32 :u32 :i16 :u16 :i8 :u8 :i4 :u4)
  # `$value` is the receiver's raw NaN-boxed word — always a machine int in
  # compiled method bodies. Other gvars hold boxed WValues and stay non-int.
  when :gvar
    return node.name == "$value"
  when :unary_op
    return int_shaped_node?(node.operand, declared_types, mod)
  # `expr ## i64` / `## u64` names a machine-int representation for the whole
  # expression, so a chain containing it (`x ^ ((r >> s) & (255 ## u64))`) is
  # int-shaped whatever the inner literal or var would be on its own.  Without
  # this arm the ascription fell to the `else` branch, the enclosing assign
  # was classed non-int, and a u64 hash accumulator dropped to a boxed slot.
  when :type_ascription
    return assign_int_hint_type(node.type_hint) != nil
  when :call
    if resolved_raw_machine_call_return_type(node, mod) != nil
      return true
    name = node.name
    if name == "wvalue_bits" && node.receiver == nil && node.args != nil && node.args.size() == 1
      return true
    if name == "ccall_nobox"
      # Exclude w_node_alloc / w_node_field_load: their return is a
      # WValue (W_PACKED_NODE / arbitrary slab slot), not a raw int.
      # Marking them int-shaped would trigger the raw_int_candidate
      # path during assignment, which then calls w_to_i64 on the
      # WValue and dies with "expected int, got packed". calls.w tags
      # these as :i64 so the binding stays as boxed-style storage.
      args_list = node.args
      if args_list != nil && args_list.size() >= 1 && ast_kind(args_list[0]) == :string
        fname = args_list[0].value
        if ccall_nobox_returns_wvalue?(fname)
          return false
      return true
    if name in ("raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8")
      return true
    # popcount/cttz/array_load_u64/array_store_u64/prefetch return raw i64
    # (calls.w); a local bound to one stays in a raw slot.
    if name in ("popcount" "cttz" "array_load_u64" "array_store_u64" "prefetch") && node.receiver == nil
      return true
    # mulhi(a,b) returns a raw u64 (high half of a 64x64 product). Mark it
    # int-shaped so a loop-reassigned local `phi = mulhi(...)` stays unboxed and
    # composes with u64 carry chains (the SSA/multi-word pointwise multiply).
    if name == "mulhi" && node.receiver == nil && node.args != nil && node.args.size() == 2
      return true
    if name in ("addcarry" "subborrow") && node.receiver == nil && node.args != nil && node.args.size() == 2
      return true
    if name == "to_i" && node.args != nil && node.args.size() == 0
      return true
    if name in ("\[]" "[]") && node.receiver != nil && node.args != nil && node.args.size() == 1
      recv = node.receiver
      if ast_kind(recv) == :var && is_typed_array_type?(declared_types[recv.name])
        return int_shaped_node?(node.args[0], declared_types, mod)
  when :binary_op
    op = node.op
    # :LSHIFT is deliberately absent (like :POW): a shift-left overflows i64
    # with tiny operands, and raw slots have no representation for the BigInt
    # the untyped semantics then require. Its lowering routes through the
    # checked __w_shl_fast instead, so a shift-bearing chain must stay boxed.
    if op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :RSHIFT)
      return int_shaped_node?(node.left, declared_types, mod) && int_shaped_node?(node.right, declared_types, mod)
  else
    false

# `## i64`-style inline hints arrive here as raw strings on assign nodes —
# this analysis runs before lowering normalizes them. Decode the machine-int
# spellings; anything else (floats, big, typed arrays) is not an int hint.
-> assign_int_hint_type(hint)
  if hint == nil
    return nil
  if hint in ("i64" "u64" "w64" "i32" "u32" "i16" "u16" "i8" "u8" "i4" "u4" "char")
    return :i64
  nil

-> collect_raw_candidate_names_list(nodes, names, hints, declared_types)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    collect_raw_candidate_names_node(nodes[i], names, hints, declared_types)
    i += 1

-> collect_raw_candidate_names_node(node, names, hints, declared_types)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    collect_raw_candidate_names_list(node[:body], names, hints, declared_types)
    return nil


  case t
  when :assign, :compound_assign
    target = node.target
    if target != nil && ast_kind(target) == :var
      vname = target.name
      # A `x = <expr> ## i64` hint types the slot authoritatively at its
      # assignment, exactly like a declared type. Recording it here lets the
      # promotion fixed point see hinted vars as machine ints, so unhinted
      # temps assigned FROM them (`t = b` / `r = a % b`) still promote
      # instead of paying a boxed w_int/w_to_i64 round-trip per loop pass.
      if t == :assign && assign_int_hint_type(node.type_hint) != nil
        hints[vname] = true
      if declared_types[vname] == nil
        names[vname] = true
    if node.value != nil
      collect_raw_candidate_names_node(node.value, names, hints, declared_types)
    return nil

  when :if
    collect_raw_candidate_names_node(node.condition, names, hints, declared_types)
    collect_raw_candidate_names_list(node.then_body, names, hints, declared_types)
    collect_raw_candidate_names_list(node.else_body, names, hints, declared_types)
    if node.elsif_clauses != nil
      j = 0
      while j < node.elsif_clauses.size()
        clause = node.elsif_clauses[j]
        if clause != nil && type(clause) == "Array" && clause.size() >= 2
          collect_raw_candidate_names_node(clause[0], names, hints, declared_types)
          collect_raw_candidate_names_list(clause[1], names, hints, declared_types)
        j += 1
    return nil

  when :while
    collect_raw_candidate_names_node(node.condition, names, hints, declared_types)
    collect_raw_candidate_names_list(node.body, names, hints, declared_types)
    return nil

  when :case
    if node.whens != nil
      j = 0
      while j < node.whens.size()
        w = node.whens[j]
        if w != nil
          if w.conditions != nil
            k = 0
            while k < w.conditions.size()
              collect_raw_candidate_names_node(w.conditions[k], names, hints, declared_types)
              k += 1
          collect_raw_candidate_names_list(w.body, names, hints, declared_types)
        j += 1
    collect_raw_candidate_names_list(node.else_body, names, hints, declared_types)
    return nil

  when :case_value
    collect_raw_candidate_names_node(node.subject, names, hints, declared_types)
    if node.arms != nil
      j = 0
      while j < node.arms.size()
        arm = node.arms[j]
        if arm != nil
          collect_raw_candidate_names_node(arm.pattern, names, hints, declared_types)
          collect_raw_candidate_names_node(arm.guard, names, hints, declared_types)
          collect_raw_candidate_names_list(arm.body, names, hints, declared_types)
        j += 1
    collect_raw_candidate_names_list(node.else_body, names, hints, declared_types)
    return nil

  when :binary_op
    collect_raw_candidate_names_node(node.left, names, hints, declared_types)
    collect_raw_candidate_names_node(node.right, names, hints, declared_types)
    return nil

  when :unary_op, :not
    collect_raw_candidate_names_node(node.operand, names, hints, declared_types)
    return nil

  when :and, :or
    collect_raw_candidate_names_node(node.left, names, hints, declared_types)
    collect_raw_candidate_names_node(node.right, names, hints, declared_types)
    return nil

  when :call
    collect_raw_candidate_names_node(node.receiver, names, hints, declared_types)
    if node.args != nil
      i = 0
      while i < node.args.size()
        collect_raw_candidate_names_node(node.args[i], names, hints, declared_types)
        i += 1
    if node.block != nil
      collect_raw_candidate_names_node(node.block, names, hints, declared_types)
    return nil

  else
    nil

-> visit_promote_list(nodes, records, declared_types, mod = nil)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    visit_promote_node(nodes[i], records, declared_types, mod)
    i += 1

# A `recv.each { … }` (and find/detect/all?/any?/none?) whose receiver is a range,
# an int (`n.each` → `0...n`), or an array/typed-array is lowered as a frame-local
# INLINED loop — no closure allocation, the block body runs in the enclosing
# scope. So an int accumulator mutated inside is safe to raw-promote, exactly like
# a `while` body — unlike a genuine closure (a stored/passed block, or map/reduce's
# closure-arg form), whose captured slots must stay boxed. This returns the block
# param's element type (so `acc += i` is int-shaped and promotes) for those
# provably-inlined int-yielding iterators, and nil otherwise (→ the caller
# bulk-escapes the block, unchanged). Float typed-arrays return :f64 and poly
# arrays return nil-element (param left untyped), so their accumulators stay boxed
# via int_shaped_node?'s machine-int-only rule — the fix can't corrupt them. The
# receiver-type gate mirrors the lowering's inline condition (method_call.w), so
# we never recurse into a real closure.
# Returns [inlined?, elem_type_or_nil].
-> inlined_iterator_elem_type(node, declared_types)
  if node.receiver == nil
    return [false, nil]
  # Scoped to `.each` on an integer RANGE (the `(0..n).each` / `n.each` counting
  # loop) — the provably-safe, primary case. Array `.each` is deliberately
  # EXCLUDED: its inline path owns per-iteration `## recycle` lexical scopes that
  # the old bulk-escape kept intact, and recursing there segfaulted the recycle
  # validation. Range `.each` has no such scope interaction, so int accumulators
  # promote cleanly. Only `each` (not find/all?/… — those had no measured need
  # and add control-flow surface) to keep the change minimal.
  if node.name != "each"
    return [false, nil]
  rk = ast_kind(node.receiver)
  # range literal, int literal, or integer-like var (`n.each` → `(0...n).each`)
  if rk == :range || rk == :int
    return [true, :i64]
  if rk == :var && is_integer_like_type(declared_types[node.receiver.name])
    return [true, :i64]
  [false, nil]

# The block param name (explicit `-> (x)` first param), or nil.
-> iterator_block_param_name(block)
  if block == nil
    return nil
  params = block.params
  if params == nil || params.size() == 0
    return nil
  p = params[0]
  if is_ast_node?(p) && p.name != nil
    return p.name
  if type(p) == "String"
    return p
  nil

-> visit_promote_node(node, records, declared_types, mod = nil)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    visit_promote_list(node[:body], records, declared_types, mod)
    return nil


  case t
  when :assign, :compound_assign
    target = node.target
    value = node.value
    if target != nil && ast_kind(target) == :var
      vname = target.name
      rec = ensure_promote_record(records, vname)
      if int_shaped_node?(value, declared_types, mod)
        rec[:has_int_assign] = true
      else
        rec[:has_other_assign] = true
    # Always walk the value with the contextual visitor — never bulk-escape.
    # The visitor's internal handlers (string interp, non-index calls, etc.)
    # mark only the truly escaping leaves, so a non-int-shaped RHS like
    # `sum + foo()` flags `foo()` args without dragging unrelated `sum` reads
    # along with it.
    visit_promote_node(value, records, declared_types, mod)
    return nil

  when :string_interp
    parts = node.parts
    if parts != nil
      i = 0
      while i < parts.size()
        mark_subtree_escape(parts[i], records)
        i += 1
    return nil

  when :call
    name = node.name
    is_index_call = name in ("\[]" "\[]=")
    # mulhi(a,b) is a pure machine-int value intrinsic — it consumes its args as
    # raw u64 (no WValue boundary), exactly like an array index. So its args do
    # NOT escape: visit them as values so an inner index var (`mulhi(a[i],b[j])`)
    # still promotes. Without this, mulhi's args were bulk-escaped, un-promoting
    # the loop counter and collapsing the whole multi-word cascade.
    # ccall_nobox / ccall_rawargs forward their (non-string) arguments as raw
    # machine ints straight to the C function — no WValue boundary — so a
    # raw-int-candidate local passed as such an arg does NOT escape. Without
    # this, `data_ptr = ccall_nobox("w_array_data_ptr", lc)` then
    # `ccall_nobox("...", data_ptr, …)` un-promoted data_ptr/pos, boxing them
    # (w_int + corrupted nanbox of a raw pointer) and routing the packed-int
    # bit math through w_bit_or / w_bit_shl instead of native or/shl.
    is_raw_ccall = name in ("ccall_nobox" "ccall_rawargs" "wvalue_from_bits") && node.receiver == nil
    # raw_load_u8/u32/u64(ptr, idx) and raw_store_u8(ptr, idx, value) consume
    # every operand as raw machine ints
    # (inline pointer loads — no WValue boundary), so an int-candidate local
    # used as the pointer or index does NOT escape. Without this, a parser's
    # `data`/`pos` locals un-promoted to boxed, then ensure_raw_machine_int
    # ran w_to_i64 on a raw pointer and died ("expected int, got object").
    is_raw_load = name in ("raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8" "popcount" "cttz" "array_load_u64" "array_store_u64" "prefetch") && node.receiver == nil
    args_are_values = is_index_call || is_raw_ccall || is_raw_load || ((name == "mulhi" || name == "addcarry" || name == "subborrow") && node.receiver == nil && node.args != nil && node.args.size() == 2)
    # Receiver of any method call needs WValue at the dispatch boundary.
    if node.receiver != nil
      mark_subtree_escape(node.receiver, records)
    # Argument position is a VALUE use, not a storage escape: a raw-int
    # slot passed as an argument is boxed at the call site
    # (ensure_i64_value → checked w_int, which promotes >i48 to BigInt),
    # exactly like a `## i64`-hinted var passed to a call. Passing an
    # accumulator to a function therefore must not force its slot to
    # stay boxed — that conservatism kept `total = total + i; << total`
    # loops paying a per-iteration w_int box. Real storage escapes
    # remain: block/closure literals appearing in argument position hit
    # visit_promote_node's else branch and bulk-escape (closures capture
    # environment slots, which raw stack slots are invisible to), and
    # the explicit node.block below stays a hard escape.
    #
    # EXCEPTION — plain `ccall`: its lowering forwards raw-typed args RAW
    # (no box at the call site; both directions of that ABI are
    # load-bearing, see calls.w). The "boxed at the call site"
    # justification above therefore does not hold, and a promoted local
    # crossing a plain-ccall boundary would arrive as raw bits where the
    # C function expects a WValue. Restore the documented contract
    # (calls.w: "analysis.w deliberately keeps ccall out of its
    # raw-intrinsic exemption list"): plain-ccall args ESCAPE, so untyped
    # candidates stay boxed. Declared `## i64` locals are not promotion
    # candidates and keep the raw path (`ccall("w_int", n)` idiom).
    is_plain_ccall = name == "ccall" && node.receiver == nil
    if node.args != nil
      i = 0
      while i < node.args.size()
        if is_plain_ccall
          mark_subtree_escape(node.args[i], records)
        else
          visit_promote_node(node.args[i], records, declared_types, mod)
        i += 1
    if node.block != nil
      inl = inlined_iterator_elem_type(node, declared_types)
      if inl[0] == true
        # Provably-inlined loop iterator: recurse into the block body (like a
        # `while` body) instead of bulk-escaping, so int accumulators promote.
        # Type the block param to the element type only when it is provably
        # integer — a nil or float element leaves the param untyped/float, and
        # int_shaped_node?'s machine-int-only rule then keeps the accumulator
        # boxed. Real escapes INSIDE the block (return, escaping call arg, a
        # nested closure) are still caught by visit_promote_list's contextual
        # walk. Param typing is applied to `declared_types` and restored after
        # (it is a loop-local element binding, not an outer fact).
        pname = iterator_block_param_name(node.block)
        elem_t = inl[1]
        had_key = false
        old_val = nil
        if pname != nil && elem_t != nil
          had_key = declared_types.has_key?(pname)
          old_val = declared_types[pname]
          declared_types[pname] = elem_t
        visit_promote_list(node.block.body, records, declared_types, mod)
        if pname != nil && elem_t != nil
          if had_key
            declared_types[pname] = old_val
          else
            declared_types.delete(pname)
      else
        mark_subtree_escape(node.block, records)
    return nil

  when :return, :recase
    if node.value != nil && !(t == :return && mod != nil && mod[:promote_raw_return] == true)
      mark_subtree_escape(node.value, records)
    return nil

  # `<< x` / `<- x` / `<! x` are value uses: the printed/raised value is
  # boxed at the emit site, so printing an accumulator must not force
  # its slot to stay boxed. :puts carries a LIST of value nodes
  # (`<< a, b, c`); :print and :raise carry one.
  when :puts
    vals = node.value
    if vals != nil
      j = 0
      while j < vals.size()
        visit_promote_node(vals[j], records, declared_types, mod)
        j += 1
    return nil

  when :print, :raise
    if node.value != nil
      visit_promote_node(node.value, records, declared_types, mod)
    return nil

  when :if
    visit_promote_node(node.condition, records, declared_types, mod)
    visit_promote_list(node.then_body, records, declared_types, mod)
    visit_promote_list(node.else_body, records, declared_types, mod)
    if node.elsif_clauses != nil
      j = 0
      while j < node.elsif_clauses.size()
        clause = node.elsif_clauses[j]
        if clause != nil && type(clause) == "Array" && clause.size() >= 2
          visit_promote_node(clause[0], records, declared_types, mod)
          visit_promote_list(clause[1], records, declared_types, mod)
        j += 1
    return nil

  when :while
    visit_promote_node(node.condition, records, declared_types, mod)
    visit_promote_list(node.body, records, declared_types, mod)
    return nil

  when :case
    if node.whens != nil
      j = 0
      while j < node.whens.size()
        w = node.whens[j]
        if w != nil
          if w.conditions != nil
            k = 0
            while k < w.conditions.size()
              visit_promote_node(w.conditions[k], records, declared_types, mod)
              k += 1
          visit_promote_list(w.body, records, declared_types, mod)
        j += 1
    visit_promote_list(node.else_body, records, declared_types, mod)
    return nil

  when :case_value
    if node.subject != nil
      visit_promote_node(node.subject, records, declared_types, mod)
    if node.arms != nil
      j = 0
      while j < node.arms.size()
        a = node.arms[j]
        if a != nil
          visit_promote_list(a.body, records, declared_types, mod)
        j += 1
    visit_promote_list(node.else_body, records, declared_types, mod)
    return nil

  when :binary_op
    visit_promote_node(node.left, records, declared_types, mod)
    visit_promote_node(node.right, records, declared_types, mod)
    return nil

  when :unary_op
    visit_promote_node(node.operand, records, declared_types, mod)
    return nil

  when :and, :or
    visit_promote_node(node.left, records, declared_types, mod)
    visit_promote_node(node.right, records, declared_types, mod)
    return nil

  when :not
    visit_promote_node(node.operand, records, declared_types, mod)
    return nil

  # `expr ## T` is a conversion boundary, not storage.  The ascribed value
  # is consumed by the enclosing context exactly like the bare expression
  # would be (a machine-int ascription hands over raw bits), so the vars
  # under it are value uses, not escapes.  Letting this fall into the
  # else-branch bulk escape un-promoted every local whose only "escape" was
  # an argument spelled `f(x ## u64)`: once the raw-typed assign arm began
  # honoring the candidate gate (typed-target assignment commit), such a
  # local became a boxed slot, and a 63-bit word boxes into a heap BigInt,
  # so `x & (x - 1)` bit walks paid a BigInt allocation per step.
  when :type_ascription
    visit_promote_node(node.expression, records, declared_types, mod)
    return nil

  # `T[n]` typed-array constructor: the size is consumed as a raw machine
  # int (lower_typed_array_new boxes-then-unboxes it at the site), so a
  # candidate used as the size does NOT escape. Without this, `n = 1000000;
  # a = i64[n]; while i < n` pinned `n` boxed and every loop-exit test paid
  # a w_int box + tagged compare — which also kept the loop unvectorizable.
  when :typed_array
    visit_promote_node(ast_get(node, :size), records, declared_types, mod)
    return nil

  # Safe leaves — known to never carry a var that flows to a non-int sink.
  when :int, :var, :symbol, :nil, :boolean, :float, :string
    return nil

  # Unknown / not-yet-modeled context. Conservative: any var inside this
  # subtree is treated as escaping. This keeps array/hash literals, ranges,
  # closures, exception handlers, etc. on the safe side until we add
  # explicit handlers for them.
  else
    mark_subtree_escape(node, records)
    nil

-> analyze_int_promotions(body, params, declared_types)
  promoted = {}
  iter = 0
  changed = true
  # Iterative widening: each pass uses last pass's promotions as known
  # machine-int types. New candidates surface when an earlier-promoted
  # var's reference unblocks a downstream RHS. Capped at 10 iterations
  # to bound worst-case work.
  while changed && iter < 10
    changed = false
    iter += 1
    # Build the "known machine-int" view: declared types plus promotions.
    known = {}
    dkeys = declared_types.keys()
    dki = 0
    while dki < dkeys.size()
      known[dkeys[dki]] = declared_types[dkeys[dki]]
      dki += 1
    pkeys = promoted.keys()
    ppi = 0
    while ppi < pkeys.size()
      known[pkeys[ppi]] = :i64
      ppi += 1

    records = {}
    visit_promote_list(body, records, known)

    # The last value-producing statement in the body is the function's
    # implicit return. Treat it as escape (return slot expects WValue).
    if body != nil && body.size() > 0
      last = body[body.size() - 1]
      if last != nil && is_ast_node?(last)
        lt = ast_kind(last)
        if lt in (:var :binary_op :unary_op :int :call)
          mark_subtree_escape(last, records)

    names = records.keys()
    i = 0
    while i < names.size()
      name = names[i]
      rec = records[name]
      if rec[:has_int_assign] == true && rec[:has_other_assign] != true && rec[:has_escape] != true && declared_types[name] == nil && promoted[name] != true
        promoted[name] = true
        changed = true
      i += 1
  promoted

-> raw_int_candidate_map(body, declared_types, mod = nil, raw_return = false)
  candidates = {}
  hinted = {}
  collect_raw_candidate_names_list(body, candidates, hinted, declared_types)

  # Most scopes have no untyped local assignment at all.  The collection
  # walk deliberately stops at nested definitions, but visit_promote_list's
  # conservative fallback walks through them; returning here avoids a second
  # full AST traversal (and, for class/main scopes, all nested method bodies)
  # when there is nothing the promotion pass could retain.
  candidate_names = candidates.keys()
  if candidate_names.size() == 0
    return candidates

  # declared_types is immutable during this analysis.  Reuse its key list
  # across fixed-point rounds instead of materializing it every time.
  declared_names = declared_types.keys()
  hinted_names = hinted.keys()
  loop
    known = {}
    dki = 0
    while dki < declared_names.size()
      known[declared_names[dki]] = declared_types[declared_names[dki]]
      dki += 1
    # `## i64`-hinted assigns are authoritative machine-int facts, like
    # declared types — they persist across rounds rather than competing as
    # candidates.
    hki = 0
    while hki < hinted_names.size()
      known[hinted_names[hki]] = :i64
      hki += 1
    cki = 0
    while cki < candidate_names.size()
      known[candidate_names[cki]] = :i64
      cki += 1

    records = {}
    # raw_return: the enclosing fn has the raw-i64 ABI, so `return x` hands x
    # back as a machine int — no WValue boundary, no escape. Carried on mod
    # for the duration of this walk (lowering is single-threaded).
    if mod != nil && raw_return
      mod[:promote_raw_return] = true
    visit_promote_list(body, records, known, mod)
    if mod != nil && raw_return
      mod[:promote_raw_return] = nil
    next_candidates = {}
    kept = 0
    i = 0
    while i < candidate_names.size()
      name = candidate_names[i]
      rec = records[name]
      # Mirror analyze_int_promotions's filter: a var that escapes (passed to
      # a call, mutated inside a block, returned) crosses a WValue boundary,
      # so it must stay boxed — never a raw-machine-int slot. The `has_escape`
      # clause is load-bearing for float accumulators captured by a closure
      # (e.g. `dot/1 0` → `components.each_with_index -> acc += …`): without it
      # the accumulator promotes to raw :i64 and the float `+=` dies in
      # w_to_i64. (This only became effective once mark_subtree_escape was
      # fixed to walk slab nodes; see the gate there.)
      if rec != nil && rec[:has_int_assign] == true && rec[:has_other_assign] != true && rec[:has_escape] != true && declared_types[name] == nil
        next_candidates[name] = true
        kept += 1
      i += 1

    # next_candidates is constructed exclusively from candidate_names, so it
    # is always a subset.  Equal cardinality therefore proves the fixed point;
    # an empty subset is terminal too.  This replaces two key-list allocations
    # and two membership scans per round, and avoids rescanning the body after
    # the last candidate is removed.
    if kept == 0 || kept == candidate_names.size()
      return next_candidates
    candidates = next_candidates
    candidate_names = candidates.keys()

-> find_reassigned_params(body, param_names)
  if body == nil || param_names == nil || param_names.size() == 0
    return []
  assigned = {}
  scan_assigns_for_params(body, assigned)
  result = []
  i = 0
  while i < param_names.size()
    if assigned[param_names[i]] == true
      result.push(param_names[i])
    i += 1
  result

-> scan_assigns_for_params(nodes, assigned)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    node = nodes[i]
    if node == nil
      i += 1
      next
    t = ast_kind(node)
    if t in (:fastmath_block :strictmath_block :overflow_block)
      scan_assigns_for_params(node[:body], assigned)
      i += 1
      next
    case t
    when :assign
      if ast_kind(node.target) == :var
        assigned[node.target.name] = true
    when :compound_assign
      if ast_kind(node.target) == :var
        assigned[node.target.name] = true
    when :if
      scan_assigns_for_params(node.then_body, assigned)
      scan_assigns_for_params(node.else_body, assigned)
      if node.elsif_clauses != nil
        j = 0
        while j < node.elsif_clauses.size()
          scan_assigns_for_params(node.elsif_clauses[j][1], assigned)
          j += 1
    when :while
      scan_assigns_for_params(node.body, assigned)
    when :case
      if node.clauses != nil
        j = 0
        while j < node.clauses.size()
          scan_assigns_for_params(node.clauses[j].body, assigned)
          j += 1
      scan_assigns_for_params(node.else_body, assigned)
    when :case_value
      if node.arms != nil
        j = 0
        while j < node.arms.size()
          scan_assigns_for_params(node.arms[j].body, assigned)
          j += 1
      scan_assigns_for_params(node.else_body, assigned)
    i += 1

# Round-5 (2026-07-22): params whose body carries a machine-int annotated
# reassign (`p = … ## u64`) get materialized as RAW machine entry slots in
# definitions.w — the same representation a local gets from an annotated
# first assignment. That gives full-width raw reads, native 2^64 wrap on
# UNANNOTATED arithmetic reassigns in the same chain (previously those
# promoted through the boxed :bigint path while identical local chains
# wrapped), and no mid-branch retype. Returns pname → :i64/:u64, first
# hint wins. Positions this walker doesn't reach (or captured params,
# filtered by the caller) simply stay boxed — the correct-but-promoting
# round-4 behavior — so misses degrade gracefully, never miscompile.
-> find_param_machine_hints(body, param_names)
  if body == nil || param_names == nil || param_names.size() == 0
    return {}
  names = {}
  i = 0
  while i < param_names.size()
    names[param_names[i]] = true
    i += 1
  hints = {}
  scan_param_machine_hints(body, names, hints)
  hints

-> scan_param_machine_hints(nodes, names, hints)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    node = nodes[i]
    if node == nil
      i += 1
      next
    t = ast_kind(node)
    if t in (:fastmath_block :strictmath_block :overflow_block)
      scan_param_machine_hints(node[:body], names, hints)
      i += 1
      next
    case t
    when :assign
      if ast_kind(node.target) == :var && names[node.target.name] == true && node.type_hint != nil
        if node.type_hint in ("i64" "u64") && hints[node.target.name] == nil
          hints[node.target.name] = node.type_hint.to_sym()
    when :if
      scan_param_machine_hints(node.then_body, names, hints)
      scan_param_machine_hints(node.else_body, names, hints)
      if node.elsif_clauses != nil
        j = 0
        while j < node.elsif_clauses.size()
          scan_param_machine_hints(node.elsif_clauses[j][1], names, hints)
          j += 1
    when :while
      scan_param_machine_hints(node.body, names, hints)
    when :begin
      scan_param_machine_hints(node.body, names, hints)
      scan_param_machine_hints(node.rescue_body, names, hints)
      scan_param_machine_hints(node.ensure_body, names, hints)
    when :case
      if node.clauses != nil
        j = 0
        while j < node.clauses.size()
          scan_param_machine_hints(node.clauses[j].body, names, hints)
          j += 1
      scan_param_machine_hints(node.else_body, names, hints)
    when :case_value
      if node.arms != nil
        j = 0
        while j < node.arms.size()
          scan_param_machine_hints(node.arms[j].body, names, hints)
          j += 1
      scan_param_machine_hints(node.else_body, names, hints)
    i += 1

# ── Escaping-closure detection (iterator-inline gate) ─────────────────
# True when the subtree creates a closure that can OUTLIVE the enclosing
# frame: a `go` body, a bare `-> (…)` lambda in expression position
# (assignment RHS, argument, element, tail), or a Thread.new trailing
# block. Iterator-inline paths (array.each inline, range.each with-loop,
# monomorphize yield-substitution) must not inline a block whose body
# creates such a closure: inlining collapses the per-invocation block
# param into ONE enclosing-frame slot, so every escaping closure would
# alias the last iteration's value instead of its own.
#
# Ordinary trailing blocks of calls are NOT flagged (they run within the
# call and per-invocation frames keep captures fresh), but their bodies
# are still walked — a `go` nested inside an inner `.each` still poisons
# the outer inline.
-> spawns_escaping_closure?(node)
  if node == nil || !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k == :go
    return true
  if k == :block
    return true
  if k == :call
    blk = ast_get(node, :block)
    if blk != nil && is_ast_node?(blk)
      recv = ast_get(node, :receiver)
      # Thread.new's trailing block escapes to an OS thread.
      if ast_get(node, :name) == "new" && recv != nil && ast_kind(recv) in (:var :call :class_ref) && ast_get(recv, :name) == "Thread"
        return true
      if spawns_escaping_closure_in_body?(ast_get(blk, :body))
        return true
      if spawns_escaping_closure?(recv)
        return true
      args = ast_get(node, :args)
      if args != nil && type(args) == "Array"
        ai = 0
        while ai < args.size()
          if spawns_escaping_closure?(args[ai])
            return true
          ai += 1
      return false
  kids = ast_children(node)
  ki = 0
  while ki < kids.size()
    if spawns_escaping_closure?(kids[ki])
      return true
    ki += 1
  false

-> spawns_escaping_closure_in_body?(body)
  if body == nil || type(body) != "Array"
    return false
  i = 0
  while i < body.size()
    if spawns_escaping_closure?(body[i])
      return true
    i += 1
  false

# Convenience gate for a block literal: walks only its body.
-> block_spawns_escaping_closure?(blk)
  if blk == nil || !is_ast_node?(blk)
    return false
  spawns_escaping_closure_in_body?(ast_get(blk, :body))

# ── Call-site parameter type inference (Tier a, no-clone) ─────────────────
# Whole-program pre-pass: for every UNANNOTATED top-level function, collect
# the static type of each argument across ALL of its call sites. When a
# parameter is unanimously passed exactly one concrete whitelisted type
# (a typed array, or a float), populate_definition_var_types seeds
# child_var_types[param] with it — so the body's `p[i]` / float arithmetic
# lowers to raw loads / native fadd instead of boxed `[]` dispatch + w_add.
# No ABI change (a typed-array handle and a nanboxed float both pass as an
# i64 WValue either way), no body clone: the identical machinery the manual
# `(f64[] f64)` param-type-list annotation already drives.
#
# Sound by construction — it BAILS (leaves the param boxed, today's exact
# behavior) on any of:
#   * the fn is a class method / redefined / already annotated
#   * the fn NAME is used as a first-class value (closure/.call), or as a
#     symbol (send/reflection)
#   * a call site has mismatched arity or a trailing kwargs hash
#   * a param carries a default / keyword / splat / block
#   * any argument's static type is unknown at some call site
#   * the observed set is non-singleton, or the type is off-whitelist
# Gated by env TUNGSTEN_PARAM_INFER (default on) so it can be bisected.
-> param_infer_enabled?
  env("TUNGSTEN_PARAM_INFER") != "0"

# Call-site observations are a whole-program optimization input, not an ABI
# declaration. Definitions parsed from the canonical prelude therefore form a
# hard boundary: user calls may consume their ABI facts but never rewrite them.
# Parser-attached source_path is stable across autoload flattening, unlike
# expression order (which is demand-driven).
-> definition_from_core?(node)
  if node == nil
    return false
  core_source_path?(ast_get(node, :source_path))

# Count writes to lexical locals across control flow and nested blocks, while
# stopping at nested method/type definitions (fresh scopes). LOCK_THE_DOORS
# may remove a receiver-class guard only when the constructor binding has one
# write in its complete scope AND straight_line_local_assignments proves that
# write is not conditional; the old speculative exact fact deliberately
# tolerated stale closure/control-flow facts because its runtime guard caught
# them.
-> count_local_assignments(node, counts)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      count_local_assignments(node[i], counts)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  kind = ast_kind(node)
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :gpu_kernel_def)
    return nil
  if kind == :assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      old = counts[target.name]
      if old == nil
        old = 0
      counts[target.name] = old + 1
    count_local_assignments(node.value, counts)
    return nil
  if kind == :compound_assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var
      old = counts[target.name]
      if old == nil
        old = 0
      counts[target.name] = old + 1
    count_local_assignments(node.value, counts)
    return nil
  if kind == :multi_assign
    targets = node.targets
    if targets != nil
      i = 0
      while i < targets.size()
        target = targets[i]
        if target != nil && is_ast_node?(target) && ast_kind(target) == :var
          old = counts[target.name]
          if old == nil
            old = 0
          counts[target.name] = old + 1
        i += 1
    count_local_assignments(node.value, counts)
    return nil

  # These fields contain arrays-of-arrays; ast_children intentionally visits
  # only one array level, so recurse through their raw structure explicitly.
  if kind == :if
    count_local_assignments(node.condition, counts)
    count_local_assignments(node.then_body, counts)
    count_local_assignments(node.elsif_clauses, counts)
    count_local_assignments(node.else_body, counts)
    return nil
  if kind == :with || kind == :parallel_with
    count_local_assignments(node.bindings, counts)
    count_local_assignments(node.body, counts)
    return nil
  if kind == :hash_literal
    count_local_assignments(node.entries, counts)
    return nil

  kids = ast_children(node)
  i = 0
  while i < kids.size()
    count_local_assignments(kids[i], counts)
    i += 1
  nil

# A single lexical write is not necessarily a dominating write: `if cond;
# x = C.new; end; x.m()` contains one assignment but can reach the call with x
# unset. Stable exact facts therefore admit only assignments that are direct
# members of the current function/block statement list. This deliberately
# leaves branch/loop joins guarded until WIRE has a real dataflow lattice.
-> straight_line_local_assignments(body)
  result = {}
  if body == nil || type(body) != "Array"
    return result
  i = 0
  while i < body.size()
    node = body[i]
    if node != nil && is_ast_node?(node) && ast_kind(node) == :assign
      target = node.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        result[target.name] = true
    i += 1
  result

-> local_assignment_counts(body)
  counts = {}
  count_local_assignments(body, counts)
  counts

# Eligible seed type, or nil. Typed arrays pass through unchanged; floats
# normalize to :f64 to match the proven param-type-list annotation path.
-> param_infer_whitelist_type(t)
  if t == nil
    return nil
  if is_typed_array_type?(t)
    return t
  if t == :float || t == :f64
    return :f64
  nil

# Given the observed-type set (Hash type_sym→true) for one param, return the
# seed type iff the set is a whitelisted singleton, else nil.
-> param_infer_seed_type(obs_set)
  if obs_set == nil
    return nil
  ks = obs_set.keys()
  if ks.size() != 1
    return nil
  param_infer_whitelist_type(ks[0])

# Inlined twin of calls.w's call_args_has_kwargs? (that worker is `use`d
# after analysis, so it is not referenceable here): a kwargs group is a
# single trailing hash_literal marked from_kwargs.
-> pi_args_have_kwargs?(args)
  if args == nil || args.size() == 0
    return false
  last = args[args.size() - 1]
  last != nil && is_ast_node?(last) && ast_kind(last) == :hash_literal && last.from_kwargs == true

-> collect_param_type_observations(mod, expressions, core_expressions = nil, core_top_local = nil)
  if !param_infer_enabled?
    return nil
  mod[:observed_param_types] = {}
  mod[:param_infer_bailed] = {}
  if expressions == nil
    return nil

  # (1) Candidate untyped top-level functions. A name defined more than once
  # at top level is ambiguous → bail it outright.
  candidates = {}
  core_candidates = {}
  user_candidates = {}
  core_set = {}
  if core_expressions != nil
    csi = 0
    while csi < core_expressions.size()
      core_set[core_expressions[csi]] = true
      csi += 1
  seen = {}
  candidate_expressions = expressions
  if mod[:program_index] != nil
    candidate_expressions = mod[:program_index][:top_level_functions]
  i = 0
  while i < candidate_expressions.size()
    expr = candidate_expressions[i]
    if expr != nil && is_ast_node?(expr) && ast_kind(expr) in (:fn_def :method_def)
      eligible_owner = !definition_from_core?(expr) || core_expressions != nil
      if expr.is_class_method != true && expr.param_types == nil && expr.name != nil && eligible_owner
        nm = expr.name
        if seen[nm] == nil
          seen[nm] = true
          candidates[nm] = expr
          if core_set[expr] == true
            core_candidates[nm] = expr
          else
            user_candidates[nm] = expr
        else
          # Observation storage is name-keyed today. A cross-boundary
          # same-name overload therefore stays boxed rather than allowing one
          # partition's evidence to specialize the other's parameters.
          mod[:param_infer_bailed][nm] = true
    i += 1

  # (2)+(3) One complete walk of the whole program: record call-site arg
  # types and flag any candidate name used as a value/symbol.
  top_local = mod[:top_level_static_types]
  if top_local == nil
    top_local = {}
  ci = 0
  while ci < expressions.size()
    visible_candidates = candidates
    visible_local = top_local
    if core_expressions != nil
      if core_set[expressions[ci]] == true
        visible_candidates = core_candidates
        if core_top_local != nil
          visible_local = core_top_local
      else
        visible_candidates = user_candidates
    pi_walk(expressions[ci], visible_local, visible_candidates, mod)
    ci += 1
  nil

-> pi_walk_stmts(stmts, local, candidates, mod)
  if stmts == nil
    return nil
  i = 0
  while i < stmts.size()
    pi_walk(stmts[i], local, candidates, mod)
    i += 1
  nil

-> pi_walk(node, local, candidates, mod)
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  # Leaf: a candidate name appearing as a plain var is a first-class
  # reference (direct calls store the name as an attribute, not a var).
  if k == :var
    if candidates[node.name] != nil
      mod[:param_infer_bailed][node.name] = true
    return nil
  if k == :symbol
    sv = ast_get(node, :value)
    if sv != nil && candidates[sv.to_s()] != nil
      mod[:param_infer_bailed][sv.to_s()] = true
    return nil
  # Nested def: fresh scope, params unknown (they shadow any outer name).
  if k in (:fn_def :method_def)
    inner = {}
    pi_collect_local_types(node.body, inner, mod)
    pi_walk_stmts(node.body, inner, candidates, mod)
    return nil
  # Direct call to a candidate: record its arguments' inferred types.
  if k == :call && node.receiver == nil && node.name != nil && candidates[node.name] != nil
    pi_record_call(candidates[node.name], node, local, mod)
  # Recurse into every child (args, receiver, bodies, …) — completeness is
  # required so no call site or value-reference is missed.
  kids = ast_children(node)
  ki = 0
  while ki < kids.size()
    pi_walk(kids[ki], local, candidates, mod)
    ki += 1
  nil

# Flow-insensitive local static-type map for a body: record each `var =`
# assignment's inferred RHS type (last write wins). Params are left unset
# (unknown), so references to an untyped param resolve nil → conservative.
-> pi_collect_local_types(stmts, local, mod)
  if stmts == nil
    return nil
  i = 0
  while i < stmts.size()
    node = stmts[i]
    if node != nil && is_ast_node?(node)
      k = ast_kind(node)
      if k == :assign && node.target != nil && is_ast_node?(node.target) && ast_kind(node.target) == :var
        t = infer_type(node.value, local, mod[:fn_return_types], nil)
        if t != nil
          local[node.target.name] = normalize_type_symbol(t)
      if k == :if
        pi_collect_local_types(node.then_body, local, mod)
        pi_collect_local_types(node.else_body, local, mod)
        if node.elsif_clauses != nil
          j = 0
          while j < node.elsif_clauses.size()
            pi_collect_local_types(node.elsif_clauses[j][1], local, mod)
            j += 1
      if k == :while
        pi_collect_local_types(node.body, local, mod)
      if k == :case
        if node.clauses != nil
          j = 0
          while j < node.clauses.size()
            pi_collect_local_types(node.clauses[j].body, local, mod)
            j += 1
        pi_collect_local_types(node.else_body, local, mod)
      if k == :case_value
        if node.arms != nil
          j = 0
          while j < node.arms.size()
            pi_collect_local_types(node.arms[j].body, local, mod)
            j += 1
        pi_collect_local_types(node.else_body, local, mod)
    i += 1
  nil

# Record one call site's argument types into the callee's observation slots,
# bailing the whole callee on arity / kwargs mismatch.
-> pi_record_call(def_node, call_node, local, mod)
  nm = def_node.name
  if mod[:param_infer_bailed][nm] == true
    return nil
  params = def_node.params
  if params == nil
    mod[:param_infer_bailed][nm] = true
    return nil
  args = call_node.args
  if args == nil
    args = []
  if args.size() != params.size() || pi_args_have_kwargs?(args)
    mod[:param_infer_bailed][nm] = true
    return nil
  obs = mod[:observed_param_types][nm]
  if obs == nil
    obs = []
    j = 0
    while j < params.size()
      obs.push({})
      j += 1
    mod[:observed_param_types][nm] = obs
  ai = 0
  while ai < args.size()
    at = infer_type(args[ai], local, mod[:fn_return_types], nil)
    key = :unknown
    if at != nil
      key = normalize_type_symbol(at)
    obs[ai][key] = true
    ai += 1
  nil

# ── Masked-index loop detection (LLVM loop-vectorizer opt-out) ─────────
# Wraparound array indexing in a while loop — `tab[i & 1023]` (and the `%`
# equivalent) — makes LLVM's loop vectorizer mis-peel: it vectorizes only a
# fraction of one array period and runs the remaining iterations scalar
# single-accumulator, ~2.6x slower than never vectorizing at all (whose
# unroller emits a clean multi-accumulator interleave — how clang treats
# the identical C loop). No clang flag or IR attribute redirects the cost
# model for just this shape (force-interleave, no-epilogue-vec, inbounds
# GEPs: all tested, all no-ops), so lower_while stamps
# `llvm.loop.vectorize.enable=false` metadata on the latch of exactly
# these loops (the emitter's :br novec flag). Sequential-index loops are
# untouched and keep full vectorization (~15.8B ops/s headerless reads).
#
# Detection: the loop body contains an array read/write (`[]` / `[]=`)
# whose index expression masks (& / %) a value referencing a var assigned
# in this loop — i.e. the index wraps as the loop advances. A mask over
# only loop-invariant vars is a uniform load and stays vectorizable.
-> loop_masked_array_index?(nodes, assigned)
  if nodes == nil
    return false
  i = 0
  while i < nodes.size()
    if expr_masked_array_index?(nodes[i], assigned)
      return true
    i += 1
  false

-> expr_masked_array_index?(node, assigned)
  if node == nil
    return false
  case ast_kind(node)
  when :call
    nm = node.name
    args = node.args
    if nm == "[]" || nm == "[]="
      if args != nil && args.size() > 0 && index_masks_loop_var?(args[0], assigned)
        return true
    if node.receiver != nil && expr_masked_array_index?(node.receiver, assigned)
      return true
    return loop_masked_array_index?(args, assigned)
  when :assign, :compound_assign
    return expr_masked_array_index?(node.value, assigned)
  when :binary_op
    if expr_masked_array_index?(node.left, assigned)
      return true
    return expr_masked_array_index?(node.right, assigned)
  when :if
    if expr_masked_array_index?(node.condition, assigned)
      return true
    if loop_masked_array_index?(node.then_body, assigned)
      return true
    if loop_masked_array_index?(node.else_body, assigned)
      return true
    ec = node.elsif_clauses
    if ec != nil
      j = 0
      while j < ec.size()
        clause = ec[j]
        if expr_masked_array_index?(clause[0], assigned)
          return true
        if loop_masked_array_index?(clause[1], assigned)
          return true
        j += 1
    return false
  # Nested while loops run their own lower_while pass and stamp their own
  # latch; the outer loop's metadata would land on the wrong loop.
  false

-> index_masks_loop_var?(node, assigned)
  if node == nil
    return false
  if ast_kind(node) != :binary_op
    return false
  op = node.op
  if op == :AMPERSAND || op == :PERCENT
    if masked_subtree_refs?(node.left, assigned) || masked_subtree_refs?(node.right, assigned)
      return true
  if index_masks_loop_var?(node.left, assigned)
    return true
  index_masks_loop_var?(node.right, assigned)

-> masked_subtree_refs?(node, assigned)
  if node == nil
    return false
  case ast_kind(node)
  when :var
    return assigned[node.name] != nil
  when :binary_op
    if masked_subtree_refs?(node.left, assigned)
      return true
    return masked_subtree_refs?(node.right, assigned)
  false

# ── Carry-intrinsic loop detection (LLVM unroller opt-in) ──────────────
# A while loop whose body calls `addcarry`/`subborrow` is a multi-word
# carry-chain kernel (bignum add_n / sub_n / addmul_1 shapes). LLVM will
# not unroll these on its own (runtime trip count + flag-carried
# dependence), and the carry flag spills across the back-edge (llvm.org
# #74493), so lower_while stamps `llvm.loop.unroll.count N` on exactly
# these latches (the emitter's :br unroll_count field) to amortize the spill
# and loop overhead. N defaults to the measured value 8 and can be tuned with
# TUNGSTEN_CARRY_UNROLL. Measured on Apple M5: +25% on the add_n shape, +8%
# on addmul_1, neutral on sub_n / mul_1. Vectorization is deliberately
# left ENABLED — a vectorize-disable on these loops measured
# neutral-to-harmful (and badly hurts neighboring vectorizable shifts).
# Nested while loops run their own lower_while pass and stamp their own
# latch, so this walker does not descend into them (same convention as
# loop_masked_array_index?).
-> carry_chain_unroll_count(ctx, node)
  raw = env("TUNGSTEN_CARRY_UNROLL")
  if raw == nil || raw == ""
    return 8
  value_text = raw.strip()
  value = value_text.to_i()
  if value_text != value.to_s() || value < 0 || value > 64
    raise compile_error_for_node(
      :E_LOWER_CARRY_UNROLL,
      "TUNGSTEN_CARRY_UNROLL must be an integer from 0 through 64 (0 disables the hint), got '" + raw + "'",
      ctx[:source_path],
      node)
  value

-> loop_has_carry_intrinsic?(nodes)
  if nodes == nil
    return false
  i = 0
  while i < nodes.size()
    if expr_has_carry_intrinsic?(nodes[i])
      return true
    i += 1
  false

-> expr_has_carry_intrinsic?(node)
  if node == nil
    return false
  case ast_kind(node)
  when :call
    if node.receiver == nil && (node.name == "addcarry" || node.name == "subborrow")
      return true
    if node.receiver != nil && is_ast_node?(node.receiver) && expr_has_carry_intrinsic?(node.receiver)
      return true
    return loop_has_carry_intrinsic?(node.args)
  when :assign, :compound_assign
    return expr_has_carry_intrinsic?(node.value)
  when :binary_op
    if expr_has_carry_intrinsic?(node.left)
      return true
    return expr_has_carry_intrinsic?(node.right)
  when :if
    if expr_has_carry_intrinsic?(node.condition)
      return true
    if loop_has_carry_intrinsic?(node.then_body)
      return true
    if loop_has_carry_intrinsic?(node.else_body)
      return true
    ec = node.elsif_clauses
    if ec != nil
      j = 0
      while j < ec.size()
        clause = ec[j]
        if expr_has_carry_intrinsic?(clause[0])
          return true
        if loop_has_carry_intrinsic?(clause[1])
          return true
        j += 1
    return false
  false

# ── Loop versioning for untyped-array element loops ────────────────────
# `while i < a.size` / `while i < n` bodies whose array accesses go through
# the polymorphic __w_array_*_fast helpers keep a per-iteration bounds check
# whose failure edge CALLS the runtime — a may-write call inside the loop, so
# LLVM can neither hoist the header loads nor vectorize, no matter what
# metadata is attached (both annotation audits converged on this; a hoisted
# one-time guard measured 4.8x, equal to the typed path). lower_while
# versions qualifying loops: a runtime guard (receiver is a live polymorphic
# WArray, counter starts >= 0, bound <= size for var bounds) selects between
# the loop body lowered with the receiver retyped :typed_array_w64 — the
# existing UNCHECKED inline path, byte-compatible since poly slots hold
# boxed WValues — and the original checked lowering. Locals live in shared
# alloca slots, so the two copies merge with no phi plumbing.
#
# Qualification is deliberately tight (soundness first, coverage later):
#   condition   i < a.size  (a statically :array)  |  i < n (int var,
#               never assigned in the body — loop-invariant bound)
#   index       every a[...] index is EXACTLY the var i
#   counter     i int-typed; body assigns it only via i = i + <pos int lit>
#               or i += <pos int lit> (monotone non-decreasing; the guard
#               adds i >= 0 at entry, so accesses stay in [0, size))
#   body        no calls of any kind except []/[]=/size on locals (element
#               get/set never resizes; anything else — push, method calls,
#               bare calls, string interpolation — could grow/shrink/alias
#               a and invalidate the hoisted guard), no bare reference to a,
#               no blocks/closures, no nested loops (they version themselves).
# Returns {arr:, ivar:, bound_kind: :size | :var, bound_name:} or nil.
-> loop_version_spec(node, var_types)
  cond = node.condition
  if cond == nil || !is_ast_node?(cond) || ast_kind(cond) != :binary_op
    return nil
  if cond.op != :LT
    return nil
  lhs = cond.left
  if lhs == nil || !is_ast_node?(lhs) || ast_kind(lhs) != :var
    return nil
  ivar = lhs.name
  ivt = var_types[ivar]
  if !(ivt == :int || ivt == :i64 || ivt == :raw_int || ivt == :raw_i64)
    return nil
  rhs = cond.right
  if rhs == nil || !is_ast_node?(rhs)
    return nil
  arr = nil
  bound_kind = nil
  bound_name = nil
  if ast_kind(rhs) == :call && rhs.name == "size" && (rhs.args == nil || rhs.args.size() == 0)
    rrecv = rhs.receiver
    if rrecv == nil || !is_ast_node?(rrecv) || ast_kind(rrecv) != :var
      return nil
    if var_types[rrecv.name] != :array
      return nil
    arr = rrecv.name
    bound_kind = :size
  elsif ast_kind(rhs) == :var
    bvt = var_types[rhs.name]
    if !(bvt == :int || bvt == :i64 || bvt == :raw_int || bvt == :raw_i64)
      return nil
    bound_kind = :var
    bound_name = rhs.name
  else
    return nil
  st = {ok: true, arr: arr, ivar: ivar, bound_name: bound_name, i_stepped: false}
  lv_walk_body(node.body, st, var_types)
  if st[:ok] != true
    return nil
  # var-bound loops must access SOME array to be worth versioning; the walk
  # fills st[:arr] with the single a[i]-accessed :array var it finds.
  if st[:arr] == nil
    return nil
  {arr: st[:arr], ivar: st[:ivar], bound_kind: bound_kind, bound_name: bound_name}

-> lv_walk_body(nodes, st, var_types)
  if nodes == nil || st[:ok] != true
    return nil
  i = 0
  while i < nodes.size()
    lv_walk_stmt(nodes[i], st, var_types)
    i += 1
  nil

-> lv_walk_stmt(node, st, var_types)
  if node == nil || st[:ok] != true
    return nil
  if !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :assign
    tgt = node.target
    if tgt != nil && is_ast_node?(tgt) && ast_kind(tgt) == :var
      tname = tgt.name
      if tname == st[:arr] || tname == st[:bound_name]
        st[:ok] = false
        return nil
      if tname == st[:ivar]
        # counter: only i = i + <positive int literal>
        v = node.value
        if v == nil || !is_ast_node?(v) || ast_kind(v) != :binary_op || v.op != :PLUS
          st[:ok] = false
          return nil
        if !(is_ast_node?(v.left) && ast_kind(v.left) == :var && v.left.name == st[:ivar])
          st[:ok] = false
          return nil
        if !(is_ast_node?(v.right) && ast_kind(v.right) == :int && v.right.value > 0)
          st[:ok] = false
          return nil
        return nil
      lv_walk_expr(node.value, st, var_types)
      return nil
    st[:ok] = false
    return nil
  if k == :compound_assign
    tgt = node.target
    if tgt != nil && is_ast_node?(tgt) && ast_kind(tgt) == :var
      tname = tgt.name
      if tname == st[:arr] || tname == st[:bound_name]
        st[:ok] = false
        return nil
      if tname == st[:ivar]
        if node.op != :PLUS || !(is_ast_node?(node.value) && ast_kind(node.value) == :int && node.value.value > 0)
          st[:ok] = false
        return nil
      lv_walk_expr(node.value, st, var_types)
      return nil
    st[:ok] = false
    return nil
  if k == :if
    lv_walk_expr(node.condition, st, var_types)
    lv_walk_body(node.then_body, st, var_types)
    lv_walk_body(node.else_body, st, var_types)
    ec = node.elsif_clauses
    if ec != nil
      j = 0
      while j < ec.size()
        clause = ec[j]
        lv_walk_expr(clause[0], st, var_types)
        lv_walk_body(clause[1], st, var_types)
        j += 1
    return nil
  if k == :break || k == :next
    return nil
  # everything else must qualify as a pure expression
  lv_walk_expr(node, st, var_types)
  nil

-> lv_walk_expr(node, st, var_types)
  if node == nil || st[:ok] != true
    return nil
  if !is_ast_node?(node)
    if type(node) == "Array"
      i = 0
      while i < node.size()
        lv_walk_expr(node[i], st, var_types)
        i += 1
    return nil
  k = ast_kind(node)
  if k == :var
    # bare reference to the versioned array would let it escape/alias
    if node.name == st[:arr]
      st[:ok] = false
    return nil
  if k == :int || k == :float || k == :bool || k == :nil || k == :string || k == :symbol
    return nil
  if k == :binary_op
    lv_walk_expr(node.left, st, var_types)
    lv_walk_expr(node.right, st, var_types)
    return nil
  if k == :unary_op
    lv_walk_expr(node.operand, st, var_types)
    return nil
  if k == :call
    recv = node.receiver
    nm = node.name
    if recv != nil && is_ast_node?(recv) && ast_kind(recv) == :var
      rname = recv.name
      if nm == "[]" || nm == "\[]"
        if rname == st[:arr] || (st[:arr] == nil && var_types[rname] == :array)
          # candidate array access: index must be exactly the loop var
          args = node.args
          if args == nil || args.size() != 1 || !(is_ast_node?(args[0]) && ast_kind(args[0]) == :var && args[0].name == st[:ivar])
            st[:ok] = false
            return nil
          if st[:arr] == nil
            if rname == st[:bound_name] || rname == st[:ivar]
              st[:ok] = false
              return nil
            st[:arr] = rname
          return nil
        # element read on some OTHER var: safe (never resizes), args checked
        lv_walk_expr(node.args, st, var_types)
        return nil
      if nm == "[]=" || nm == "\[]="
        args = node.args
        if args == nil || args.size() != 2
          st[:ok] = false
          return nil
        if rname == st[:arr] || (st[:arr] == nil && var_types[rname] == :array)
          if !(is_ast_node?(args[0]) && ast_kind(args[0]) == :var && args[0].name == st[:ivar])
            st[:ok] = false
            return nil
          if st[:arr] == nil
            if rname == st[:bound_name] || rname == st[:ivar]
              st[:ok] = false
              return nil
            st[:arr] = rname
          lv_walk_expr(args[1], st, var_types)
          return nil
        # element write on another var: in-place, never resizes — safe
        lv_walk_expr(args[0], st, var_types)
        lv_walk_expr(args[1], st, var_types)
        return nil
      if nm == "size" && (node.args == nil || node.args.size() == 0)
        return nil
    st[:ok] = false
    return nil
  # anything unrecognized (blocks, interpolation, nested loops, case, …)
  st[:ok] = false
  nil

# ==== Automatic fused-array destination reuse ====
#
# A reassigned fused result can consume its old output buffer when that value
# is unique. This pass deliberately proves a narrow, useful shape:
#
#   y = <fresh typed-array expression>       # direct dominating seed
#   ...
#   while ...
#     y = <pure elementwise tree>            # old y dies here
#
# Every other use of y in the lexical scope must be a read-only []/size/length
# receiver use or one of those update RHS trees. A bare copy, call argument,
# capture, store, return, or unknown use rejects the candidate. The seed and
# each update are pure dot/libm trees, so they cannot retain an alias; the
# first result is fresh and uniqueness is preserved inductively. This is the
# array analogue of mutate-if-unique, kept separate because arrays have no
# shared-bit/refcount fallback if the static proof is wrong.

-> fused_reuse_tree?(node)
  if node == nil || !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:var :int :float)
    return true
  if k == :binary_op && node.op in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH :DOT_PIPE :DOT_AMP :DOT_CARET :DOT_LSHIFT :DOT_RSHIFT :PLUS :MINUS :STAR :SLASH :PERCENT :PIPE :AMPERSAND :CARET :LSHIFT :RSHIFT)
    return fused_reuse_tree?(node.left) && fused_reuse_tree?(node.right)
  if k == :call && node.receiver != nil && node.name in ("sin" "cos" "sqrt" "exp" "log" "tan")
    argc = node.args == nil ? 0 : node.args.size()
    return argc == 0 && node.block == nil && fused_reuse_tree?(node.receiver)
  false

-> fused_reuse_seed?(node)
  if node == nil || !is_ast_node?(node) || ast_get(node, :reuse_safe) == true || ast_get(node, :recycle_safe) == true
    return false
  k = ast_kind(node)
  if k in (:typed_array_new :typed_array)
    return true
  # Leaves and ordinary scalar arithmetic are valid *inside* a fused tree,
  # but are not fresh array seeds. In particular, `y = x` must never start
  # the uniqueness induction: x would retain an alias to the reused buffer.
  if k == :binary_op && node.op in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH :DOT_PIPE :DOT_AMP :DOT_CARET :DOT_LSHIFT :DOT_RSHIFT)
    return fused_reuse_tree?(node)
  if k == :call && node.receiver != nil && node.name in ("sin" "cos" "sqrt" "exp" "log" "tan")
    argc = node.args == nil ? 0 : node.args.size()
    return argc == 0 && node.block == nil && fused_reuse_tree?(node.receiver)
  false

-> fused_reuse_walk(node, var_name, st)
  if node == nil || st[:ok] != true
    return nil
  if !is_ast_node?(node)
    if type(node) == "Array"
      i = 0
      while i < node.size()
        fused_reuse_walk(node[i], var_name, st)
        i += 1
    return nil
  k = ast_kind(node)
  # Nested definitions open another lexical scope. A block does not, and the
  # generic schema walk below sees a captured bare var and rejects it.
  if k in (:method_def :fn_def :class_def :module_def :trait_def :gpu_kernel_def)
    return nil
  if k == :assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var && target.name == var_name
      st[:assigns] = st[:assigns] + 1
      if st[:assigns] == 1
        if !fused_reuse_seed?(node.value)
          st[:ok] = false
      else
        if ast_get(node.value, :reuse_safe) == true || !fused_reuse_tree?(node.value)
          st[:ok] = false
        else
          st[:updates].push(node)
      return nil
  if k == :call
    recv = node.receiver
    if recv != nil && is_ast_node?(recv) && ast_kind(recv) == :var && recv.name == var_name
      if node.block == nil && node.name in ("[]" "\[]" "size" "length")
        fused_reuse_walk(node.args, var_name, st)
        return nil
      st[:ok] = false
      return nil
  if k == :var && node.name == var_name
    st[:ok] = false
    return nil

  kid = kind_id_table[k]
  if kid == nil
    st[:ok] = false
    return nil
  keys = slab_keys_table[kid]
  if keys == nil
    st[:ok] = false
    return nil
  i = 0
  while i < keys.size()
    fused_reuse_walk(ast_get(node, keys[i]), var_name, st)
    i += 1
  nil

# Mark only reassignments; the first assignment must allocate the unique seed.
-> mark_fused_reuse_assignments(body)
  if body == nil || type(body) != "Array"
    return nil
  seeds = []
  i = 0
  while i < body.size()
    node = body[i]
    if node != nil && is_ast_node?(node) && ast_kind(node) == :assign
      target = node.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var && fused_reuse_seed?(node.value)
        seeds.push({name: target.name, node: node})
    i += 1

  si = 0
  while si < seeds.size()
    candidate = seeds[si]
    st = {ok: true, assigns: 0, updates: []}
    fused_reuse_walk(body, candidate[:name], st)
    if st[:ok] == true && st[:assigns] > 1 && st[:updates].size() > 0
      ui = 0
      while ui < st[:updates].size()
        ast_set(st[:updates][ui], :auto_reuse_safe, true)
        ast_set(st[:updates][ui].value, :auto_reuse_target, true)
        ui += 1
    si += 1
  nil

# ==== Mutate-if-unique accumulator analysis (E4 stage 1) ====
#
# A local qualifies when every value it ever holds is provably safe to
# mutate in place at its `r = r + e` / `r += e` sites: nobody else can hold
# a reference to it. Two assignment shapes are allowed, chosen because the
# runtime guards close their aliasing holes:
#   (a) literal-leaf arithmetic (`r = 1 << 4096`): mints fresh;
#   (b) one supported arithmetic op whose LEFT operand is the var itself
#       (`r = r + anything`), or its compound assignment: lowered through
#       the corresponding w_bigint_*_mut entry, whose every return is either
#       in-place (unique by induction), fresh, the dying receiver, or an
#       operand alias MARKED SHARED (w_bigint_mut_fallback) — which the
#       next mut attempt refuses and copies.
# Shapes like `r = x + r` or `r = r + i + j` are DISQUALIFIED: their outer
# ops lower through plain w_add, whose identity returns (x + 0 -> x) can
# seed the var with an unmarked alias of a live value.
#
# Uses are whitelisted positionally: binary/unary operands and branch
# conditions are plain reads. The walker is FAIL-CLOSED — any node kind it
# does not explicitly handle kills every var named inside it (calls,
# blocks/closures, returns, container/ivar/global stores, interpolation).
# A wrong "unique" proof is a silently wrong number, so unknown constructs
# must never default to safe.

-> mut_mark_all_dead(node, dead)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      mut_mark_all_dead(node[i], dead)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :var
    dead[node.name] = true
    return nil
  if k in (:int :float :string :symbol :nil :bool :char)
    return nil
  case k
  when :call
    mut_mark_all_dead(node.receiver, dead)
    mut_mark_all_dead(node.args, dead)
    mut_mark_all_dead(node.block, dead)
  when :binary_op, :and, :or, :target_and, :target_or
    mut_mark_all_dead(node.left, dead)
    mut_mark_all_dead(node.right, dead)
  when :unary_op, :not
    mut_mark_all_dead(node.operand, dead)
  when :string_interp, :byte_array_interp
    mut_mark_all_dead(node.parts, dead)
  when :array
    mut_mark_all_dead(node.elements, dead)
  when :hash_literal
    mut_mark_all_dead(node.entries, dead)
  when :range
    mut_mark_all_dead(node.from, dead)
    mut_mark_all_dead(node.to, dead)
  when :assign, :compound_assign
    mut_mark_all_dead(node.target, dead)
    mut_mark_all_dead(node.value, dead)
  when :return, :print, :puts, :raise, :recase
    mut_mark_all_dead(node.value, dead)
  when :if
    mut_mark_all_dead(node.condition, dead)
    mut_mark_all_dead(node.then_body, dead)
    mut_mark_all_dead(node.elsif_clauses, dead)
    mut_mark_all_dead(node.else_body, dead)
  when :while
    mut_mark_all_dead(node.condition, dead)
    mut_mark_all_dead(node.body, dead)
  when :block
    mut_mark_all_dead(node.params, dead)
    mut_mark_all_dead(node.body, dead)
  else
    # Unknown kind: its children cannot be enumerated here, so no candidate
    # in this scope may survive it. mark_subtree_escape's silent fall-through
    # is exactly the walker-coverage bug class this pass must not inherit —
    # a missed var here is a silently wrong number, not a leak.
    dead["__scope_poisoned__"] = true
  nil

-> mut_literal_leaves_only?(node)
  if node == nil || !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k == :int
    return true
  if k == :binary_op
    return mut_literal_leaves_only?(node.left) && mut_literal_leaves_only?(node.right)
  if k == :unary_op
    return mut_literal_leaves_only?(node.operand)
  false

-> mut_self_compound_rhs?(node, name)
  if node == nil || !is_ast_node?(node)
    return false
  if ast_kind(node) != :binary_op
    return false
  if !(node.op in (:PLUS :MINUS :STAR :SLASH :PERCENT))
    return false
  node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == name

# ==== Word-overwrite destination shape (E4 stage 3) ====
#
# `r = a + w` / `r = a - w` / `r = a * w` overwriting a candidate var: r's
# OLD value provably dies at the assignment, so lowering hands it to a
# dest-taking runtime entry (w_bigint_{add,sub,mul}_word_dest) that
# computes into the dying buffer. This predicate is purely syntactic and
# SHARED between walker admission and emission, keeping the proof and the
# transform aligned. Leaves are int literals or plain vars OTHER than the
# target: a self-reading spelling stays with the mutate-if-unique family,
# and excluding the target from operand position means the dest can only
# dynamically equal an operand through an alias — which the fresh-or-
# MARKED invariant forces to carry a shared mark (and the entries also
# pointer-compare, belt and suspenders).
-> bigint_word_dest_leaf?(n, name)
  if n == nil || !is_ast_node?(n)
    return false
  k = ast_kind(n)
  if k == :int
    return true
  k == :var && n.name != name

-> bigint_word_dest_rhs_shape(node, name)
  if env("TUNGSTEN_BIGINT_DEST_OPS") == "0"
    return nil
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :binary_op
    return nil
  if !(node.op in (:PLUS :MINUS :STAR))
    return nil
  if !(bigint_word_dest_leaf?(node.left, name) && bigint_word_dest_leaf?(node.right, name))
    return nil
  # at least one side must be a var — an all-literal RHS is a seed
  # (mut_literal_leaves_only? claims it first), never an overwrite that
  # wants the dying buffer
  if ast_kind(node.left) != :var && ast_kind(node.right) != :var
    return nil
  node

# A binary/unary arithmetic tree whose leaves are ints or plain var reads:
# exactly the shapes mut_walk_expr treats as read positions, and whose values
# only ever come from runtime arithmetic entries. Callers require the ROOT to
# be an operator: a bare `r = y` is a slot copy that mints an unmarked alias
# and must keep taking the kill arm.
# Core readers that neither retain their receiver nor hand back an
# unmarked alias of it (abs/negation aliases are shared-marked by the
# runtime). Only admitted for the LAST top-level statement of a body.
-> mut_tail_reader_call?(node)
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :call
    return false
  if node.block != nil || node.receiver == nil || !is_ast_node?(node.receiver)
    return false
  if !(node.name in ("to_s" "to_f" "bit_length" "abs" "zero?" "even?" "odd?" "negative?" "positive?" "hash" "inspect"))
    return false
  if !mut_pure_arith_rhs?(node.receiver)
    return false
  if node.args != nil
    j = 0
    while j < node.args.size()
      if !mut_pure_arith_rhs?(node.args[j])
        return false
      j += 1
  true

-> mut_tail_reader?(st)
  k = ast_kind(st)
  if k == :call
    return mut_tail_reader_call?(st)
  if k in (:print :puts :return)
    v = st.value
    if v == nil || !is_ast_node?(v)
      return false
    return mut_pure_arith_rhs?(v) || mut_tail_reader_call?(v)
  false

-> mut_pure_arith_rhs?(node)
  if node == nil || !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:var :int)
    return true
  if k == :binary_op
    return mut_pure_arith_rhs?(node.left) && mut_pure_arith_rhs?(node.right)
  if k == :unary_op
    return mut_pure_arith_rhs?(node.operand)
  false

-> mut_walk_expr(node, assigned, dead)
  # expression position: operands of arithmetic/comparisons are plain reads
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :var
    return nil
  if k == :binary_op
    mut_walk_expr(node.left, assigned, dead)
    mut_walk_expr(node.right, assigned, dead)
    return nil
  if k == :unary_op
    mut_walk_expr(node.operand, assigned, dead)
    return nil
  if k == :int
    return nil
  # anything else in operand position (calls, indexing, interpolation…)
  # retains-or-escapes as far as this analysis is concerned
  mut_mark_all_dead(node, dead)
  nil

-> mut_walk_stmts(body, assigned, dead, seeds, depth)
  if body == nil
    return nil
  i = 0
  while i < body.size()
    st = body[i]
    if st == nil || !is_ast_node?(st)
      i += 1
      next
    k = ast_kind(st)
    # The LAST top-level statement of a body handing the var itself back
    # (implicit `r` or `return r`) is the ownership transfer that ends the
    # scope: nothing follows that could mutate or release the buffer the
    # caller now holds, so it does not disqualify r. Any earlier return, or
    # one nested in control flow, still kills (fail closed).
    if depth == 0 && i == body.size() - 1
      if k == :var
        i += 1
        next
      if k == :return && st.value != nil && is_ast_node?(st.value) && ast_kind(st.value) == :var
        i += 1
        next
      # A final read-only use of the candidate — a non-retaining Core
      # reader (`acc.to_s`, `acc.bit_length`), a print, or a return of such
      # a call — is also an ownership transfer at scope end: no statement
      # follows that could release or mutate the buffer it observes.
      if mut_tail_reader?(st)
        i += 1
        next
    if k == :assign && st.target != nil && is_ast_node?(st.target) && ast_kind(st.target) == :var
      name = st.target.name
      if mut_self_compound_rhs?(st.value, name)
        # A self-update does not establish ownership. In particular, a
        # parameter may still be referenced by its caller; only a prior
        # literal-only local seed proves this scope owns the buffer it may
        # later consume.
        if assigned[name] != true
          dead[name] = true
        # the right operand is an ordinary read position
        mut_walk_expr(st.value.right, assigned, dead)
      elsif mut_literal_leaves_only?(st.value)
        assigned[name] = true
        # Word-overwrite admission (below) demands a DOMINATING seed: a
        # direct top-level statement of this body, textually earlier. That
        # proves both ownership of the dying buffer (a parameter's incoming
        # value is caller-owned and must never be consumed) and that the
        # slot is initialized on every path reaching the overwrite — the
        # dest entry READS the old value, a load the user never wrote, so
        # a conditionally-executed seed would let it read an undef slot.
        if depth == 0
          seeds[name] = true
      elsif bigint_word_dest_rhs_shape(st.value, name) != nil
        # Word-overwrite shape (E4 stage 3): `r = a op w` consumes r's OLD
        # value as the op's destination. Admitted only over a dominating
        # literal seed; the RHS operands are ordinary read positions
        # (leaves exclude the target itself).
        if seeds[name] != true
          dead[name] = true
        mut_walk_expr(st.value, assigned, dead)
      elsif seeds[name] == true && ast_kind(st.value) in (:binary_op :unary_op) && mut_pure_arith_rhs?(st.value)
        # Loop-carried overwrite (E4 stage 4): `r = <arithmetic>` where every
        # leaf is a literal or a plain var read. The dominating literal seed
        # proves this scope owns whatever r held, and a pure arithmetic RHS
        # only reaches BigInt runtime entries, which shared-mark any operand
        # alias they hand back. r's OLD value is therefore dead once the RHS
        # has been computed and lowering releases it (assign.w). Reads of r
        # inside the RHS are ordinary operand positions.
        mut_walk_expr(st.value, assigned, dead)
      else
        dead[name] = true
        # A bare-var RHS is a plain slot copy — an alias minted with NO
        # runtime entry involved, so no shared mark can guard it. The
        # SOURCE var dies too (`y = r` then `r += 1` must not move y).
        if st.value != nil && is_ast_node?(st.value) && ast_kind(st.value) == :var
          dead[st.value.name] = true
        mut_walk_expr(st.value, assigned, dead)
    elsif k == :compound_assign && st.target != nil && is_ast_node?(st.target) && ast_kind(st.target) == :var
      name = st.target.name
      if st.op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
        # Multiplication and division join once their mutating entries make
        # every identity return dying-receiver-owned or shared-marked, the
        # same invariant that admits PLUS/MINUS.
        if assigned[name] != true
          dead[name] = true
        mut_walk_expr(st.value, assigned, dead)
      else
        # any other compound op keeps failing closed
        dead[name] = true
        mut_walk_expr(st.value, assigned, dead)
    elsif k == :while
      mut_walk_expr(st.condition, assigned, dead)
      mut_walk_stmts(st.body, assigned, dead, seeds, depth + 1)
    elsif k == :if
      mut_walk_expr(st.condition, assigned, dead)
      mut_walk_stmts(st.then_body, assigned, dead, seeds, depth + 1)
      mut_walk_stmts(st.else_body, assigned, dead, seeds, depth + 1)
      if st.elsif_clauses != nil
        j = 0
        while j < st.elsif_clauses.size()
          clause = st.elsif_clauses[j]
          mut_walk_expr(clause[0], assigned, dead)
          mut_walk_stmts(clause[1], assigned, dead, seeds, depth + 1)
          j += 1
    elsif k in (:binary_op :unary_op :not :and :or)
      # A pure-arithmetic expression statement (commonly the implicit
      # return, `r % m`): its RESULT is fresh-or-caller-owned, and its
      # operands are plain reads. A BARE var in tail position does NOT
      # land here (:var is not in this list) — it falls to the kill arm
      # below, because returning the var itself hands out an alias.
      mut_walk_expr(st, assigned, dead)
    else
      # statements this walker does not model (calls, puts, returns,
      # blocks, nested defs, stores…) kill every var they mention
      mut_mark_all_dead(st, dead)
    i += 1
  nil

-> mut_accumulator_candidates(body, raw_int_candidates = nil)
  # Reproducible performance control: production/default compilation keeps
  # mutate-if-unique enabled, while the BigInt loop A/B can force ordinary
  # immutable result churn from the same source program.
  if env("TUNGSTEN_BIGINT_MUTATE_UNIQUE") == "0"
    return {}
  assigned = {}
  dead = {}
  mut_walk_stmts(body, assigned, dead, {}, 0)
  result = {}
  if dead["__scope_poisoned__"] == true
    return result
  assigned.keys().each -> (name)
    # A raw-promoted local (raw_int_candidate_map) lives in a machine-int
    # slot; the mutate-if-unique and sum-chunk seams read and write the same
    # slot as a boxed WValue. Both analyses claiming one var (`n = 0; while
    # …; n += a[z]; …; k * 8 - n`) stored a raw 0 that the chunk flush then
    # added as nil. Raw promotion wins: it is the cheaper codegen and its
    # overflow path already handles the widening the seams exist for.
    if dead[name] != true && (raw_int_candidates == nil || raw_int_candidates[name] != true)
      result[name] = true
  result

# ==== Sum-chunk detection (E4 stage 1.5) ====
#
# A while loop qualifies for chunked accumulation when a mut-candidate var
# r is touched ONLY by direct-body `r = r ± e` / `r ±= e` statements whose
# addends are int-shaped (evaluable as raw i64) and don't read r. The
# transform keeps a raw i64 partial sum in a register/slot and flushes it
# into r with ONE boxed mut-add per ~2^63 of accumulated magnitude — the
# per-iteration cost degrades to a fused add+overflow-flag check.
# Everything else about r (reads in the condition, other statements,
# unknown constructs) rejects, using the same fail-closed collector as
# the candidate walker.

-> sum_chunk_accum_stmt_var(st)
  # returns the accumulated var name if st is a qualifying accumulation
  if st == nil || !is_ast_node?(st)
    return nil
  k = ast_kind(st)
  if k == :compound_assign && st.target != nil && is_ast_node?(st.target) && ast_kind(st.target) == :var && st.op in (:PLUS :MINUS)
    return st.target.name
  if k == :assign && st.target != nil && is_ast_node?(st.target) && ast_kind(st.target) == :var
    v = st.value
    if v != nil && is_ast_node?(v) && ast_kind(v) == :binary_op && v.op in (:PLUS :MINUS) && v.left != nil && is_ast_node?(v.left) && ast_kind(v.left) == :var && v.left.name == st.target.name
      return st.target.name
  nil

-> sum_chunk_addend(st)
  if ast_kind(st) == :compound_assign
    return st.value
  st.value.right

-> sum_chunk_var(node, mut_accumulators, declared_types, mod)
  if mut_accumulators == nil || node.body == nil
    return nil
  # gather accumulation counts per var over direct body statements
  counts = {}
  i = 0
  while i < node.body.size()
    nm = sum_chunk_accum_stmt_var(node.body[i])
    if nm != nil
      if counts[nm] == nil
        counts[nm] = 0
      counts[nm] = counts[nm] + 1
    i += 1
  candidates = counts.keys()
  ci = 0
  while ci < candidates.size()
    name = candidates[ci]
    ci += 1
    if mut_accumulators[name] != true
      next
    ok = true
    refs = {}
    # the condition must not read r
    mut_mark_all_dead(node.condition, refs)
    if refs[name] == true || refs["__scope_poisoned__"] == true
      next
    j = 0
    while j < node.body.size()
      st = node.body[j]
      j += 1
      if sum_chunk_accum_stmt_var(st) == name
        addend = sum_chunk_addend(st)
        if !int_shaped_node?(addend, declared_types, mod)
          ok = false
          break
        arefs = {}
        mut_mark_all_dead(addend, arefs)
        if arefs[name] == true || arefs["__scope_poisoned__"] == true
          ok = false
          break
      else
        srefs = {}
        mut_mark_all_dead(st, srefs)
        if srefs[name] == true || srefs["__scope_poisoned__"] == true
          ok = false
          break
    if ok
      return name
  nil

# ==== Rotation-shape detection (E4 stage 2) ====
#
# The Fibonacci-style triple inside a while body:
#     t = a + b
#     a = b
#     b = t
# rotates values: old-a provably DIES at the group (nothing reads it
# after the first statement), so the sum may be computed into its buffer
# (w_bigint_add_dest) and the steady state allocates nothing.
#
# Fail-closed proof obligations, all checked here:
#   * the three statements are ADJACENT and in this exact data-flow shape
#     (t = a + b / a = b / b = t, with t, a, b three distinct plain vars);
#   * a, b, t are referenced NOWHERE else in the loop body or condition
#     (any other read of a could observe the clobbered buffer; any alias
#     store escapes it) — checked with the same mut_mark_all_dead
#     collector, so unknown constructs poison the proof;
#   * none of the three is a mut/sum-chunk candidate elsewhere (the
#     transforms must not stack on the same var).
# Returns {t:, a:, b:, index:} for the first qualifying triple, or nil.

-> rotation_triple_at(body, i)
  if i + 2 >= body.size()
    return nil
  s1 = body[i]
  s2 = body[i + 1]
  s3 = body[i + 2]
  if s1 == nil || s2 == nil || s3 == nil
    return nil
  if !(is_ast_node?(s1) && is_ast_node?(s2) && is_ast_node?(s3))
    return nil
  if !(ast_kind(s1) == :assign && ast_kind(s2) == :assign && ast_kind(s3) == :assign)
    return nil
  if !(ast_kind(s1.target) == :var && ast_kind(s2.target) == :var && ast_kind(s3.target) == :var)
    return nil
  t_name = s1.target.name
  a_name = s2.target.name
  b_name = s3.target.name
  if t_name == a_name || t_name == b_name || a_name == b_name
    return nil
  # s1: t = a + b (either operand order), or t = a - b (E4 stage 4 —
  # strict left orientation: the dying var, s2's target, must be the
  # MINUEND, because the subtract entry computes x - y into old-a's
  # buffer and only the x side may alias that dying destination)
  v1 = s1.value
  if v1 == nil || !is_ast_node?(v1) || ast_kind(v1) != :binary_op
    return nil
  if !(v1.op == :PLUS || (v1.op == :MINUS && env("TUNGSTEN_BIGINT_SUB_DEST") != "0"))
    return nil
  if v1.left == nil || v1.right == nil || !is_ast_node?(v1.left) || !is_ast_node?(v1.right)
    return nil
  if ast_kind(v1.left) != :var || ast_kind(v1.right) != :var
    return nil
  n1 = v1.left.name
  n2 = v1.right.name
  if v1.op == :PLUS
    if !((n1 == a_name && n2 == b_name) || (n1 == b_name && n2 == a_name))
      return nil
  else
    if !(n1 == a_name && n2 == b_name)
      return nil
  # s2: a = b
  if s2.value == nil || !is_ast_node?(s2.value) || ast_kind(s2.value) != :var || s2.value.name != b_name
    return nil
  # s3: b = t
  if s3.value == nil || !is_ast_node?(s3.value) || ast_kind(s3.value) != :var || s3.value.name != t_name
    return nil
  {t: t_name, a: a_name, b: b_name, index: i, op: v1.op}

-> rotation_shape_spec(node)
  if node.body == nil
    return nil
  i = 0
  while i < node.body.size()
    spec = rotation_triple_at(node.body, i)
    if spec != nil
      # isolation: t/a/b referenced nowhere else in body or condition
      refs = {}
      mut_mark_all_dead(node.condition, refs)
      j = 0
      while j < node.body.size()
        if j < spec[:index] || j > spec[:index] + 2
          mut_mark_all_dead(node.body[j], refs)
        j += 1
      if refs["__scope_poisoned__"] != true && refs[spec[:t]] != true && refs[spec[:a]] != true && refs[spec[:b]] != true
        return spec
    i += 1
  nil
