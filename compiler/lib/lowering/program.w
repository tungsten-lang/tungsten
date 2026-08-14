# Lowering / program — whole-program pre-passes over the top level:
# extern-var collection, top-level static types and const-eval, the
# --tags report, trait expansion into class bodies, and AST-constructor
# return-type registration.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

-> receiver_static_type(ctx, recv_node)
  recv_type = infer_type(recv_node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if recv_type == nil && recv_node != nil && ast_kind(recv_node) == :var
    if ctx[:mod][:top_level_static_types] != nil
      recv_type = ctx[:mod][:top_level_static_types][recv_node.name]
    if recv_type == nil && ctx[:mod][:top_level_var_types] != nil
      recv_type = ctx[:mod][:top_level_var_types][recv_node.name]
  recv_type

-> top_level_assignment_static_type(expr, mod)
  if expr.type_hint != nil
    if expr.type_hint == "w64"
      return :i64
    # Opt-in auto-promoting BigInt accumulator (top-level seed).
    if expr.type_hint == "big" || expr.type_hint == "bigint" || expr.type_hint == "bignum"
      return :bigint
    ht = expr.type_hint
    hint_etype = array_hint_element_type(ht)
    # `## f32[]` / `## i32[N]` / etc. — normalize to :typed_array_<etype>
    # so receiver_static_type → typed_array_get_inline fast path fires.
    # EXCEPT when the hint matches a typed-array literal RHS that stack-
    # promotes (`a = bf16[4] ## bf16[]`): resolve to the :small_array_*
    # symbol exactly as inference would, because forcing :typed_array_*
    # sends every reader down heap-WArray offsets against a SmallArray
    # handle — a segfault, not a type error.
    if hint_etype != nil
      v = expr.value
      if v != nil && is_ast_node?(v) && ast_kind(v) in (:typed_array_new :typed_array) && v.element_type == hint_etype && typed_array_new_stack_promoted?(v)
        return small_array_etype_to_sym(hint_etype)
      return typed_array_etype_to_sym(hint_etype)
    return normalize_type_symbol(expr.type_hint)
  # Infer the RHS against the static types collected so far, not an empty
  # map — otherwise a reassignment like `x = x * y` (no `##` hint) can't see
  # that x/y are machine-ints, infers :int, and downgrades x's recorded type.
  st = mod[:top_level_static_types]
  if st == nil
    st = {}
  infer_type(expr.value, st, mod[:fn_return_types], lowering_infer_maps)

# ── Top-level global demotion prepass ─────────────────────────────────────
# A top-level var lowers to a main-fn slot/binding PLUS a mirror store to
# @global.NAME on every assignment. The mirror exists for other scopes
# (fn/method/class bodies and closures resolve module vars via load_global),
# but ownership analysis treats :store_global as an escape, so EVERY
# top-level heap value was pinned (zero frees in whole-script programs;
# RSS grew without bound on top-level loops). Collect the set of var names
# actually referenced inside a nested executable scope — fn_def /
# method_def / class_def / module_def bodies and :block (closure/lambda)
# literals; emit_store_global_unless_const skips the mirror for everything
# else. main itself always resolves through slots/bindings first
# (lower_var checks them before the top_level_vars fallback), so a skipped
# mirror is unobservable from straight-line main code. @global emission is
# untouched (a never-stored global is dead weight, not a hazard).
# Gated by TUNGSTEN_DEMOTE_TOP_LEVEL (default on) for bisection.
-> collect_extern_var_refs(mod, expressions)
  mod[:extern_var_refs] = {}
  if env("TUNGSTEN_DEMOTE_TOP_LEVEL") == "0"
    mod[:extern_var_refs] = nil
    return nil
  i = 0
  while i < expressions.size()
    evr_walk(expressions[i], mod[:extern_var_refs], false)
    i += 1
  nil

-> evr_walk(node, refs, in_nested)
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  nested = in_nested
  if k in (:fn_def :method_def :class_def :module_def :trait_def :block)
    nested = true
  if nested && k == :var && node.name != nil
    refs[node.name] = true
  # Interpolation parts are [tag, payload] packed-body pairs (W_PACKED_BODY,
  # subtype 6) — not AST nodes — so ast_children skips them. Walk the expr
  # payloads explicitly, or a var read only from inside "[x]" in a nested
  # scope loses its @global mirror and the fn reads an unset global.
  if k in (:string_interp :byte_array_interp)
    ps = node.parts
    pi = 0
    while pi < ps.size()
      p = ps[pi]
      if p[0] != :str
        evr_walk(p[1], refs, nested)
      pi += 1
  # elsif_clauses are [condition, body] packed pairs — the same
  # ast_children blindness. A var read ONLY inside an elsif arm was
  # demoted (wassat's WASSAT_COVER_MAX_EDGES read nil in covering).
  # mark_subtree_escape walks them explicitly for the same reason.
  if k == :if
    ecs = node.elsif_clauses
    if ecs != nil
      ei = 0
      while ei < ecs.size()
        ec = ecs[ei]
        evr_walk(ec[0], refs, nested)
        ebody = ec[1]
        if ebody != nil
          bi = 0
          while bi < ebody.size()
            evr_walk(ebody[bi], refs, nested)
            bi += 1
        ei += 1
  kids = ast_children(node)
  ki = 0
  while ki < kids.size()
    evr_walk(kids[ki], refs, nested)
    ki += 1
  nil

# Recursive nested-assignment scan for constant eligibility: any
# :assign / :compound_assign targeting a var below statement level marks
# it multiply-assigned (true) in assign_count — a block or loop body can
# mutate a top-level var, and folding such a var to an LLVM `constant`
# makes its loads fold to the stale literal. fn/method/class bodies are
# SKIPPED: an assignment there shadows the module-scope var and never
# writes the global. Field probes mirror loader.w's
# collect_autoload_refs — the proven stage-0-safe generic walk (no
# block-passing calls: the C VM cannot dispatch them during bootstrap).
-> const_disqualify_nested(node, assign_count)
  if !is_ast_node?(node) || ast_kind(node) == nil
    return nil
  t = ast_kind(node)
  if t in (:fn_def :method_def :class_def)
    return nil
  if t in (:assign :compound_assign)
    tgt = node.target
    if tgt != nil && is_ast_node?(tgt) && ast_kind(tgt) == :var
      assign_count[tgt.name] = true
  if t in (:fastmath_block :strictmath_block :overflow_block)
    mb = node[:body]
    if mb != nil
      mbi = 0
      while mbi < mb.size()
        const_disqualify_nested(mb[mbi], assign_count)
        mbi += 1
    return nil
  if t == :puts && node.value != nil
    vals = node.value
    vi = 0
    while vi < vals.size()
      const_disqualify_nested(vals[vi], assign_count)
      vi += 1
  elsif node.value != nil && is_ast_node?(node.value)
    const_disqualify_nested(node.value, assign_count)
  if t == :array && node.elements != nil
    els = node.elements
    ei = 0
    while ei < els.size()
      const_disqualify_nested(els[ei], assign_count)
      ei += 1
  if node.left != nil && is_ast_node?(node.left)
    const_disqualify_nested(node.left, assign_count)
  if node.right != nil && is_ast_node?(node.right)
    const_disqualify_nested(node.right, assign_count)
  if node.condition != nil && is_ast_node?(node.condition)
    const_disqualify_nested(node.condition, assign_count)
  if node.receiver != nil && is_ast_node?(node.receiver)
    const_disqualify_nested(node.receiver, assign_count)
  if t != :assign && t != :compound_assign && node.target != nil && is_ast_node?(node.target)
    const_disqualify_nested(node.target, assign_count)
  if node.source != nil && is_ast_node?(node.source)
    const_disqualify_nested(node.source, assign_count)
  if node.func != nil && is_ast_node?(node.func)
    const_disqualify_nested(node.func, assign_count)
  if node.block != nil && is_ast_node?(node.block)
    const_disqualify_nested(node.block, assign_count)
  if node.args != nil
    ai = 0
    while ai < node.args.size()
      const_disqualify_nested(node.args[ai], assign_count)
      ai += 1
  if node.body != nil
    const_disqualify_nested_seq(node.body, assign_count)
  if node.then_body != nil
    const_disqualify_nested_seq(node.then_body, assign_count)
  if node.else_body != nil
    const_disqualify_nested_seq(node.else_body, assign_count)
  if node.rescue_body != nil
    const_disqualify_nested_seq(node.rescue_body, assign_count)
  if node.ensure_body != nil
    const_disqualify_nested_seq(node.ensure_body, assign_count)
  if node.fallback != nil
    const_disqualify_nested_seq(node.fallback, assign_count)
  if node.expressions != nil
    const_disqualify_nested_seq(node.expressions, assign_count)
  nil

-> const_disqualify_nested_seq(seq, assign_count)
  i = 0
  while i < seq.size()
    const_disqualify_nested(seq[i], assign_count)
    i += 1
  nil

-> collect_top_level_static_types(mod, expressions)
  if mod[:top_level_static_types] == nil
    mod[:top_level_static_types] = {}
  if mod[:top_level_const_values] == nil
    mod[:top_level_const_values] = {}

  # First pass: count top-level :assign targets per name. A var assigned
  # exactly once at module scope is eligible for `constant` emission.
  # `assign_count[nm]` is nil → 1, true → "already saw more than one".
  #
  # NESTED assignments disqualify too: `acc ## i64 = 0` followed by
  # `(1..n).each -> (k) acc = acc + k` mutates acc from inside a block —
  # folding acc to an LLVM `constant` would make its loads fold to the
  # literal and the loop's writes skip the (illegal) global store. Any
  # :assign / :compound_assign to the name anywhere below statement level
  # marks it multiply-assigned outright.
  assign_count = {}
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if expr != nil && is_ast_node?(expr) && ast_kind(expr) == :assign
      target = expr.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        nm = target.name
        prev = assign_count[nm]
        if prev == nil
          assign_count[nm] = 1
        else
          assign_count[nm] = true
      const_disqualify_nested(ast_get(expr, :value), assign_count)
    elsif expr != nil && is_ast_node?(expr)
      const_disqualify_nested(expr, assign_count)
    i += 1

  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if expr != nil && is_ast_node?(expr) && ast_kind(expr) == :assign
      target = expr.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        name = target.name
        static_type = top_level_assignment_static_type(expr, mod)
        if static_type != nil
          # Don't let a later, weaker inference (e.g. a hintless reassignment
          # inferred as :int) clobber a machine-int type already established by
          # an explicit `## u64`/`## i64` annotation on an earlier assignment.
          prev = mod[:top_level_static_types][name]
          if is_bigint_type(prev) && !is_bigint_type(static_type)
            # Sticky BigInt seed: don't let a later weaker inference downgrade
            # a `## big` top-level accumulator back to :int (which would
            # re-enable native-wrap unboxing in the loop).
            nil
          elsif prev == nil || !is_machine_int_type(prev) || is_machine_int_type(static_type)
            mod[:top_level_static_types][name] = static_type
        # Predeclare the global so function bodies lowered before the
        # assignment still resolve the name as a module-scope value.
        mod[:top_level_vars][name] = true
        # Constant detection: a single-assignment `## i64` top-level var
        # with an integer-literal RHS is folded to an LLVM `constant`.
        # The store at module-init time is skipped; every load of the
        # global folds to the literal.
        if assign_count[name] == 1 && expr.type_hint == "i64"
          cv_val = top_level_const_eval(expr.value)
          if cv_val != nil
            mod[:top_level_const_values][name] = cv_val
    i += 1

# Constant-expression evaluator for `constant`-eligible top-level `## i64`
# bindings. Beyond the original bare :int / :wvalue literals (KIND_PROGRAM
# = 60, AST_NIL = u0xFFFE...), it folds unary minus and the closed integer
# ops over constant operands, so a named tag constant can be CONSTRUCTED
# readably — `W_BI_TAG = ((0xFFF8 - 0x10000) << 48) ## i64` — and still
# emit as an LLVM `constant` whose loads fold to the immediate.
#
# Every intermediate is range-guarded to |v| < 2^62: this pre-pass runs on
# whatever host is bootstrapping (the stage-0 C VM has no bigint tower),
# so an expression whose folding would need arbitrary-precision arithmetic
# must fall back to a runtime global on EVERY host identically, or stage
# identity breaks. Shift counts are bounded to 0..62 for the same reason.
-> top_level_const_eval(node)
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :int || k == :wvalue
    v = node.value
    # Raw :wvalue payloads exceed i48 and read back as BigInt under the
    # compiled engine's exact type() split; both are integers here.
    if type(v) in ("Int" "BigInt")
      return v
    return nil
  if k == :unary_op && node.op == :MINUS
    uv = top_level_const_eval(node.operand)
    if uv == nil
      return nil
    return 0 - uv
  if k == :binary_op
    lv = top_level_const_eval(node.left)
    if lv == nil
      return nil
    rv = top_level_const_eval(node.right)
    if rv == nil
      return nil
    bound = 4611686018427387904
    if lv >= bound || lv <= 0 - bound || rv >= bound || rv <= 0 - bound
      return nil
    bop = node.op
    out = nil
    if bop == :PLUS
      out = lv + rv
    elsif bop == :MINUS
      out = lv - rv
    elsif bop == :STAR
      # Division precheck so the product never overflows on a host with no
      # bigint tower (the post-check alone would be too late there).
      sla = lv < 0 ? 0 - lv : lv
      sra = rv < 0 ? 0 - rv : rv
      if sla != 0 && sra > (bound - 1) / sla
        return nil
      out = lv * rv
    elsif bop == :LSHIFT
      if rv < 0 || rv > 62
        return nil
      factor = 1 << rv
      sla = lv < 0 ? 0 - lv : lv
      if sla != 0 && sla > (bound - 1) / factor
        return nil
      out = lv * factor
    elsif bop == :AMPERSAND
      out = lv & rv
    elsif bop == :PIPE
      out = lv | rv
    elsif bop == :CARET
      out = lv ^ rv
    if out == nil
      return nil
    if out >= bound || out <= 0 - bound
      return nil
    return out
  nil

# `tungsten --tags <file.w>`: the dispatch report. Rows are collected
# during lowering (calls.w's overload-gate arm, ops.w's infix classifier)
# into mod[:tag_report_gates] / mod[:tag_report_infix] — side data no
# hashing or emission pass reads. Output is sorted, so the report is
# deterministic for a given program.
-> tag_report_text(mod, file_path)
  out = StringBuffer(512)
  out << "dispatch report: " << file_path << "\n\n"

  gates = mod[:tag_report_gates]
  if gates == nil
    gates = []
  out << "typed-overload gates (" << gates.size().to_s() << ")\n"
  gate_counts = {}
  gi = 0
  while gi < gates.size()
    g = gates[gi]
    reason = ""
    if g[:route] == :ancestry
      reason = g[:reason] == :subclassed ? " (in table, reverted: subclass registered)" : ""
    key = "  " + (g[:route] == :exact_tag ? "exact-tag" : "ancestry ") + "  (" + g[:type_name] + ")" + reason + "  in " + (g[:class_name] == nil ? "<top>" : g[:class_name])
    cur = gate_counts[key]
    gate_counts[key] = cur == nil ? 1 : cur + 1
    gi += 1
  gate_keys = gate_counts.keys().sort()
  gk = 0
  while gk < gate_keys.size()
    out << gate_keys[gk] << "  x" << gate_counts[gate_keys[gk]].to_s() << "\n"
    gk += 1

  infix = mod[:tag_report_infix]
  if infix == nil
    infix = []
  out << "\ninfix +/-/* runtime-fallback sites (" << infix.size().to_s() << ")\n"
  route_counts = {}
  miss_sites = {}
  ii = 0
  while ii < infix.size()
    r = infix[ii]
    op_name = r[:op] == :PLUS ? "+" : (r[:op] == :MINUS ? "-" : "*")
    rkey = "  " + (r[:route] == :static_direct ? "static-direct" : (r[:route] == :near_miss ? "near-miss    " : "polymorphic  ")) + "  " + op_name
    cur = route_counts[rkey]
    route_counts[rkey] = cur == nil ? 1 : cur + 1
    if r[:route] == :near_miss
      where = r[:class_name] == nil ? "" : r[:class_name] + "#"
      mkey = "    " + op_name + "  in " + where + (r[:fname] == nil ? "<top>" : r[:fname])
      mcur = miss_sites[mkey]
      miss_sites[mkey] = mcur == nil ? 1 : mcur + 1
    ii += 1
  route_keys = route_counts.keys().sort()
  rk = 0
  while rk < route_keys.size()
    out << route_keys[rk] << "  x" << route_counts[route_keys[rk]].to_s() << "\n"
    rk += 1
  if miss_sites.keys().size() > 0
    out << "\n  near-miss detail (one operand inferred bigint — typing the other\n"
    out << "  upgrades the site to a static direct call):\n"
    miss_keys = miss_sites.keys().sort()
    mk = 0
    while mk < miss_keys.size()
      out << miss_keys[mk] << "  x" << miss_sites[miss_keys[mk]].to_s() << "\n"
      mk += 1
  out.to_s()

-> trait_include_name(mod, node)
  if ast_kind(node) == :trait_include
    return node.name
  if ast_kind(node) == :use && mod[:known_traits][node.path] != nil
    return node.path
  nil

-> expand_class_traits(mod, body)
  if body == nil
    return []
  expanded = []
  i = 0
  while i < body.size()
    expr = body[i]
    trait_name = trait_include_name(mod, expr)
    if trait_name != nil
      trait_def = mod[:known_traits][trait_name]
      if trait_def == nil && ast_kind(expr) == :trait_include
        raise compile_error_for_node(:E_LOWER_UNKNOWN_TRAIT, "Unknown trait '" + trait_name + "'", nil, expr)
      if trait_def != nil && trait_def.body != nil
        j = 0
        while j < trait_def.body.size()
          expanded.push(trait_def.body[j])
          j += 1
    i += 1
  i = 0
  while i < body.size()
    expr = body[i]
    trait_name = trait_include_name(mod, expr)
    if trait_name == nil || mod[:known_traits][trait_name] == nil
      expanded.push(expr)
    i += 1
  expanded

# Register AST class constructor return types so infer_type can
# recognize `Tungsten:AST:X.new(...)` as producing a specific AST
# kind. This unlocks the strict-gated node.field recognizer in
# lower_call: with these entries in place, the type of a freshly-
# constructed AST node is statically pinned and downstream field
# accesses can bypass method_missing dispatch via direct ast_get.
# Two special cases override the snake_case derivation:
#   Nil  → :nil_lit (the kind in ast_schema, not :nil)
#   Self → :self_ref
# All other class names convert PascalCase → snake_case directly.
-> register_ast_constructor_return_types(mod)
  mod[:fn_return_types]["Tungsten:AST:File.new"] = :file
  mod[:fn_return_types]["Tungsten:AST:Program.new"] = :program
  mod[:fn_return_types]["Tungsten:AST:Int.new"] = :int
  mod[:fn_return_types]["Tungsten:AST:Wvalue.new"] = :wvalue
  mod[:fn_return_types]["Tungsten:AST:Float.new"] = :float
  mod[:fn_return_types]["Tungsten:AST:Decimal.new"] = :decimal
  mod[:fn_return_types]["Tungsten:AST:TypedArrayNew.new"] = :typed_array_new
  mod[:fn_return_types]["Tungsten:AST:String.new"] = :string
  mod[:fn_return_types]["Tungsten:AST:StringInterp.new"] = :string_interp
  mod[:fn_return_types]["Tungsten:AST:Regex.new"] = :regex
  mod[:fn_return_types]["Tungsten:AST:RegexCapture.new"] = :regex_capture
  mod[:fn_return_types]["Tungsten:AST:Bool.new"] = :bool
  mod[:fn_return_types]["Tungsten:AST:Nil.new"] = :nil_lit
  mod[:fn_return_types]["Tungsten:AST:Symbol.new"] = :symbol
  mod[:fn_return_types]["Tungsten:AST:MagicConstant.new"] = :magic_constant
  mod[:fn_return_types]["Tungsten:AST:Array.new"] = :array
  mod[:fn_return_types]["Tungsten:AST:ScheduleDef.new"] = :schedule_def
  mod[:fn_return_types]["Tungsten:AST:LayoutDef.new"] = :layout_def
  mod[:fn_return_types]["Tungsten:AST:HashLiteral.new"] = :hash_literal
  mod[:fn_return_types]["Tungsten:AST:ByteArray.new"] = :byte_array
  mod[:fn_return_types]["Tungsten:AST:ByteArrayInterp.new"] = :byte_array_interp
  mod[:fn_return_types]["Tungsten:AST:Currency.new"] = :currency
  mod[:fn_return_types]["Tungsten:AST:Quantity.new"] = :quantity
  mod[:fn_return_types]["Tungsten:AST:Duration.new"] = :duration
  mod[:fn_return_types]["Tungsten:AST:Uuid.new"] = :uuid
  mod[:fn_return_types]["Tungsten:AST:Date.new"] = :date
  mod[:fn_return_types]["Tungsten:AST:Datetime.new"] = :datetime
  mod[:fn_return_types]["Tungsten:AST:Time.new"] = :time
  mod[:fn_return_types]["Tungsten:AST:Month.new"] = :month
  mod[:fn_return_types]["Tungsten:AST:Ip4.new"] = :ip4
  mod[:fn_return_types]["Tungsten:AST:Cidr4.new"] = :cidr4
  mod[:fn_return_types]["Tungsten:AST:Ip6.new"] = :ip6
  mod[:fn_return_types]["Tungsten:AST:Cidr6.new"] = :cidr6
  mod[:fn_return_types]["Tungsten:AST:Rational.new"] = :rational
  mod[:fn_return_types]["Tungsten:AST:Char.new"] = :char
  mod[:fn_return_types]["Tungsten:AST:Codepoint.new"] = :codepoint
  mod[:fn_return_types]["Tungsten:AST:Key.new"] = :key
  mod[:fn_return_types]["Tungsten:AST:WordArray.new"] = :word_array
  mod[:fn_return_types]["Tungsten:AST:SymbolArray.new"] = :symbol_array
  mod[:fn_return_types]["Tungsten:AST:MapOp.new"] = :map_op
  mod[:fn_return_types]["Tungsten:AST:Map.new"] = :map
  mod[:fn_return_types]["Tungsten:AST:Calc.new"] = :calc
  mod[:fn_return_types]["Tungsten:AST:Parg.new"] = :parg
  mod[:fn_return_types]["Tungsten:AST:LambdaArity.new"] = :lambda_arity
  mod[:fn_return_types]["Tungsten:AST:Superscript.new"] = :superscript
  mod[:fn_return_types]["Tungsten:AST:Encoded.new"] = :encoded
  mod[:fn_return_types]["Tungsten:AST:Color.new"] = :color
  mod[:fn_return_types]["Tungsten:AST:ViewDecl.new"] = :view_decl
  mod[:fn_return_types]["Tungsten:AST:FieldDecl.new"] = :field_decl
  mod[:fn_return_types]["Tungsten:AST:ViewAccess.new"] = :view_access
  mod[:fn_return_types]["Tungsten:AST:ViewField.new"] = :view_field
  mod[:fn_return_types]["Tungsten:AST:ViewFieldVar.new"] = :view_field_var
  mod[:fn_return_types]["Tungsten:AST:ViewBase.new"] = :view_base
  mod[:fn_return_types]["Tungsten:AST:ViewValue.new"] = :view_value
  mod[:fn_return_types]["Tungsten:AST:Var.new"] = :var
  mod[:fn_return_types]["Tungsten:AST:ClassRef.new"] = :class_ref
  mod[:fn_return_types]["Tungsten:AST:Ivar.new"] = :ivar
  mod[:fn_return_types]["Tungsten:AST:Cvar.new"] = :cvar
  mod[:fn_return_types]["Tungsten:AST:GVar.new"] = :gvar
  mod[:fn_return_types]["Tungsten:AST:Self.new"] = :self_ref
  mod[:fn_return_types]["Tungsten:AST:Assign.new"] = :assign
  mod[:fn_return_types]["Tungsten:AST:CompoundAssign.new"] = :compound_assign
  mod[:fn_return_types]["Tungsten:AST:MultiAssign.new"] = :multi_assign
  mod[:fn_return_types]["Tungsten:AST:BinaryOp.new"] = :binary_op
  mod[:fn_return_types]["Tungsten:AST:UnaryOp.new"] = :unary_op
  mod[:fn_return_types]["Tungsten:AST:And.new"] = :and
  mod[:fn_return_types]["Tungsten:AST:Or.new"] = :or
  mod[:fn_return_types]["Tungsten:AST:Not.new"] = :not
  mod[:fn_return_types]["Tungsten:AST:InTest.new"] = :in_test
  mod[:fn_return_types]["Tungsten:AST:Passthrough.new"] = :passthrough
  mod[:fn_return_types]["Tungsten:AST:TypeAscription.new"] = :type_ascription
  mod[:fn_return_types]["Tungsten:AST:Range.new"] = :range
  mod[:fn_return_types]["Tungsten:AST:If.new"] = :if
  mod[:fn_return_types]["Tungsten:AST:While.new"] = :while
  mod[:fn_return_types]["Tungsten:AST:With.new"] = :with
  mod[:fn_return_types]["Tungsten:AST:ParallelWith.new"] = :parallel_with
  mod[:fn_return_types]["Tungsten:AST:Case.new"] = :case
  mod[:fn_return_types]["Tungsten:AST:When.new"] = :when
  mod[:fn_return_types]["Tungsten:AST:CaseValue.new"] = :case_value
  mod[:fn_return_types]["Tungsten:AST:CaseArm.new"] = :case_arm
  mod[:fn_return_types]["Tungsten:AST:SafeNav.new"] = :safe_nav
  mod[:fn_return_types]["Tungsten:AST:RescueExpr.new"] = :rescue_expr
  mod[:fn_return_types]["Tungsten:AST:Break.new"] = :break
  mod[:fn_return_types]["Tungsten:AST:Next.new"] = :next
  mod[:fn_return_types]["Tungsten:AST:Return.new"] = :return
  mod[:fn_return_types]["Tungsten:AST:Recase.new"] = :recase
  mod[:fn_return_types]["Tungsten:AST:ReturnNil.new"] = :return_nil
  mod[:fn_return_types]["Tungsten:AST:TypedArray.new"] = :typed_array
  mod[:fn_return_types]["Tungsten:AST:ClassDef.new"] = :class_def
  mod[:fn_return_types]["Tungsten:AST:ModuleDef.new"] = :module_def
  mod[:fn_return_types]["Tungsten:AST:TraitDef.new"] = :trait_def
  mod[:fn_return_types]["Tungsten:AST:TraitInclude.new"] = :trait_include
  mod[:fn_return_types]["Tungsten:AST:NamespaceDecl.new"] = :namespace_decl
  mod[:fn_return_types]["Tungsten:AST:IvarsDecl.new"] = :ivars_decl
  mod[:fn_return_types]["Tungsten:AST:MethodDef.new"] = :method_def
  mod[:fn_return_types]["Tungsten:AST:FnDef.new"] = :fn_def
  mod[:fn_return_types]["Tungsten:AST:GpuKernelDef.new"] = :gpu_kernel_def
  mod[:fn_return_types]["Tungsten:AST:Param.new"] = :param
  mod[:fn_return_types]["Tungsten:AST:Call.new"] = :call
  mod[:fn_return_types]["Tungsten:AST:Block.new"] = :block
  mod[:fn_return_types]["Tungsten:AST:Puts.new"] = :puts
  mod[:fn_return_types]["Tungsten:AST:Print.new"] = :print
  mod[:fn_return_types]["Tungsten:AST:Raise.new"] = :raise
  mod[:fn_return_types]["Tungsten:AST:Begin.new"] = :begin
  mod[:fn_return_types]["Tungsten:AST:Use.new"] = :use
  mod[:fn_return_types]["Tungsten:AST:Yield.new"] = :yield
  mod[:fn_return_types]["Tungsten:AST:Super.new"] = :super
  mod[:fn_return_types]["Tungsten:AST:ExternLib.new"] = :extern_lib
  mod[:fn_return_types]["Tungsten:AST:ExternFn.new"] = :extern_fn
  mod[:fn_return_types]["Tungsten:AST:Go.new"] = :go
  mod[:fn_return_types]["Tungsten:AST:TargetDesignator.new"] = :target_designator
  mod[:fn_return_types]["Tungsten:AST:TargetAnd.new"] = :target_and
  mod[:fn_return_types]["Tungsten:AST:TargetOr.new"] = :target_or
  mod[:fn_return_types]["Tungsten:AST:TargetNot.new"] = :target_not
  mod[:fn_return_types]["Tungsten:AST:OnGuard.new"] = :on_guard
  mod[:fn_return_types]["Tungsten:AST:RegexMatch.new"] = :regex_match
  mod[:fn_return_types]["Tungsten:AST:CidrMatch.new"] = :cidr_match
