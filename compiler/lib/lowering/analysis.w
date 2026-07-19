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

  # Phase 2 (2026-04-15): overflow_vars exclusion removed. Under the
  # silent-wrap semantics locked in by the plan, any compound +/-/* on
  # a loop-local int can stay in a raw i64 slot and run as native
  # add_i64/sub_i64/mul_i64 with no bigint-promotion fallback. Users
  # who explicitly want bigint promotion can annotate `## int` to opt
  # back into the boxed path. This change is the primary perf
  # unblocker for Phase 2's hot-loop story.
  result = []
  keys = compound_vars.keys().sort()
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
# ── Phase 0.4b: local int escape analysis ─────────────────────────────
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
    if node.receiver == nil && node.name in ("ccall_nobox" "ccall_rawargs" "wvalue_from_bits" "raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8" "mulhi" "addcarry" "subborrow")
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
    mark_subtree_escape(node.body, records)

  when :method_def, :fn_def, :gpu_kernel_def
    mark_subtree_escape(node.params, records)
    mark_subtree_escape(node.body, records)

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

# True iff the expression is structurally raw-int — a literal int or an
# arithmetic/bitwise op tree where every leaf is a known int source.
# Var references are accepted only if the referenced var is already
# declared with a machine-int type. Locals not yet promoted are rejected
# (no fixed-point iteration in this MVP — false negatives cost perf only,
# false positives would silently corrupt).
-> int_shaped_node?(node, declared_types)
  if node == nil
    return false
  if !is_ast_node?(node)
    return false
  t = ast_kind(node)
  case t
  when :int
    return true
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
    return int_shaped_node?(node.operand, declared_types)
  when :call
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
        if fname == "w_node_alloc" || fname == "w_node_field_load"
          return false
      return true
    if name in ("raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8")
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
        return int_shaped_node?(node.args[0], declared_types)
  when :binary_op
    op = node.op
    if op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
      return int_shaped_node?(node.left, declared_types) && int_shaped_node?(node.right, declared_types)
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

-> visit_promote_list(nodes, records, declared_types)
  if nodes == nil
    return nil
  i = 0
  while i < nodes.size()
    visit_promote_node(nodes[i], records, declared_types)
    i += 1

-> visit_promote_node(node, records, declared_types)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t in (:fastmath_block :strictmath_block :overflow_block)
    visit_promote_list(node[:body], records, declared_types)
    return nil


  case t
  when :assign, :compound_assign
    target = node.target
    value = node.value
    if target != nil && ast_kind(target) == :var
      vname = target.name
      rec = ensure_promote_record(records, vname)
      if int_shaped_node?(value, declared_types)
        rec[:has_int_assign] = true
      else
        rec[:has_other_assign] = true
    # Always walk the value with the contextual visitor — never bulk-escape.
    # The visitor's internal handlers (string interp, non-index calls, etc.)
    # mark only the truly escaping leaves, so a non-int-shaped RHS like
    # `sum + foo()` flags `foo()` args without dragging unrelated `sum` reads
    # along with it.
    visit_promote_node(value, records, declared_types)
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
    is_raw_load = name in ("raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8") && node.receiver == nil
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
    if node.args != nil
      i = 0
      while i < node.args.size()
        visit_promote_node(node.args[i], records, declared_types)
        i += 1
    if node.block != nil
      mark_subtree_escape(node.block, records)
    return nil

  when :return, :recase
    if node.value != nil
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
        visit_promote_node(vals[j], records, declared_types)
        j += 1
    return nil

  when :print, :raise
    if node.value != nil
      visit_promote_node(node.value, records, declared_types)
    return nil

  when :if
    visit_promote_node(node.condition, records, declared_types)
    visit_promote_list(node.then_body, records, declared_types)
    visit_promote_list(node.else_body, records, declared_types)
    if node.elsif_clauses != nil
      j = 0
      while j < node.elsif_clauses.size()
        clause = node.elsif_clauses[j]
        if clause != nil && type(clause) == "Array" && clause.size() >= 2
          visit_promote_node(clause[0], records, declared_types)
          visit_promote_list(clause[1], records, declared_types)
        j += 1
    return nil

  when :while
    visit_promote_node(node.condition, records, declared_types)
    visit_promote_list(node.body, records, declared_types)
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
              visit_promote_node(w.conditions[k], records, declared_types)
              k += 1
          visit_promote_list(w.body, records, declared_types)
        j += 1
    visit_promote_list(node.else_body, records, declared_types)
    return nil

  when :case_value
    if node.subject != nil
      visit_promote_node(node.subject, records, declared_types)
    if node.arms != nil
      j = 0
      while j < node.arms.size()
        a = node.arms[j]
        if a != nil
          visit_promote_list(a.body, records, declared_types)
        j += 1
    visit_promote_list(node.else_body, records, declared_types)
    return nil

  when :binary_op
    visit_promote_node(node.left, records, declared_types)
    visit_promote_node(node.right, records, declared_types)
    return nil

  when :unary_op
    visit_promote_node(node.operand, records, declared_types)
    return nil

  when :and, :or
    visit_promote_node(node.left, records, declared_types)
    visit_promote_node(node.right, records, declared_types)
    return nil

  when :not
    visit_promote_node(node.operand, records, declared_types)
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

-> raw_int_candidate_map(body, declared_types)
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
    visit_promote_list(body, records, known)
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
