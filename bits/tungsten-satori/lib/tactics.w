# Satori tactic engine. Untrusted: tactics refine goals and record
# justifications that rebuild the goal's theorem from its subgoals' theorems
# using kernel rules only.

+ Goal
  ro :fixes, :hyps, :concl
  # fixes: array of [name, var]; hyps: array of [name, prop]
  -> new(@fixes, @hyps, @concl)

  -> hyp(name)
    i = @hyps.size - 1
    while i >= 0
      if @hyps[i][0] == name
        return @hyps[i][1]
      i -= 1
    nil

  -> locals
    @fixes

  -> all_terms
    out = [@concl]
    @hyps.each -> (h)
      out.push(h[1])
    @fixes.each -> (f)
      out.push(f[1])
    out

  -> with_concl(c)
    Goal.new(@fixes, @hyps, c)

  -> add_hyp(name, p)
    Goal.new(@fixes, @hyps + [[name, p]], @concl)

  -> add_fix(name, v)
    Goal.new(@fixes + [[name, v]], @hyps, @concl)

  -> without_hyp(name)
    hs = []
    @hyps.each -> (h)
      if h[0] != name
        hs.push(h)
    Goal.new(@fixes, hs, @concl)

  -> show(k)
    lines = []
    @fixes.each -> (f)
      lines.push("  " + f[0] + " : " + ty_show(f[1].ty))
    @hyps.each -> (h)
      lines.push("  " + h[0] + " : " + tm_show(h[1]))
    lines.push("  ⊢ " + tm_show(@concl))
    lines.join("\n")

+ GoalRef
  rw :goal, :thm, :node, :index
  -> new(@goal, @node, @index)
    @thm = nil

  -> solve(th)
    @thm = th
    if @node != nil
      @node.child_done
    th

+ JustNode
  ro :children
  -> new(@parent, @just)
    @children = []
    @done = 0

  -> set_children(cs)
    @children = cs

  -> child_done
    @done += 1
    if @done == @children.size
      thms = []
      @children.each -> (c)
        thms.push(c.thm)
      @parent.solve(@just.call(thms))

-> partial_proof_note(proved, missing, witness = nil)
  note = "  proved " + proved
  if missing != nil
    note += "\n  need " + missing
  witness == nil ? note : "  witness " + witness + "\n" + note

# These conversions depend only on the terms and the fixed session definitions.
# Nested rule applications and diagnostic probes can reuse their kernel proofs.
+ ApplicationConversions
  ro :definitions, :aliases, :rules

  -> new
    @definitions = Array.new(64)
    @aliases = Array.new(64)
    @rules = {}

+ Prover
  ro :k, :d, :session
  rw :goals, :sum_aliases_allowed, :registered_search, :auto_rule_path

  -> new(@session, @conversions = nil)
    @k = @session.k
    @d = @session.d
    @goals = []
    @auto_rule_path = []
    @open_interval_case = nil
    @registered_search = false
    @sum_aliases_allowed = true
    @sum_alias_rules = {}
    @fold_alias_rules = {}
    @application_squares = {}
    @application_square_cache = {}
    @hcount = 0
    @split_ne = []
    @nl_mode = false
    @omega_mode = false
    @split_sub = []

  -> application_conversions
    if @conversions == nil
      @conversions = ApplicationConversions.new
    @conversions

  -> goal_has_name?(goal, nm)
    if goal == nil
      return false
    if goal.hyp(nm) != nil
      return true
    goal.fixes.each -> (f)
      if f[0] == nm
        return true
    false

  -> fresh_hyp_name(goal = nil)
    @hcount += 1
    nm = "h" + @hcount.to_s
    while goal_has_name?(goal, nm)
      @hcount += 1
      nm = "h" + @hcount.to_s
    nm

  -> fail(msg)
    raise msg

  # Replace goal reference g by subgoals; just maps their theorems to g's theorem.
  -> refine(g, subgoals, just)
    node = JustNode.new(g, just)
    refs = []
    i = 0
    subgoals.each -> (sg)
      refs.push(GoalRef.new(sg, node, i))
      i += 1
    node.set_children(refs)
    idx = 0
    while idx < @goals.size && !(@goals[idx] == g)
      idx += 1
    rest_before = arr_sub(@goals, 0, idx)
    rest_after = arr_sub(@goals, idx + 1, @goals.size - idx - 1)
    @goals = rest_before + refs + rest_after
    if refs.size == 0
      g.solve(just.call([]))
    refs

  -> close(g, th)
    refine(g, [], ->(ts) th)

  -> first_goal
    if @goals.size == 0
      fail("no goals remain")
    @goals[0]

  # Checks that th proves g (conclusion up to beta, hypotheses within g's).
  -> fit(g, th)
    goal = g.goal
    c = th.concl
    if !tm_eq(c, goal.concl)
      th2 = @d.beta_norm_thm(th)
      gc = @d.beta_norm_term(goal.concl)
      if tm_eq(th2.concl, gc)
        th = @k.eq_mp(@k.sym(@d.beta_norm_conv(goal.concl)), th2)
      else
        th3 = try_eta_fit(th, goal.concl)
        if th3 == nil
          th3 = try_defeq(th, goal.concl)
        if th3 == nil
          fail("type mismatch: proof shows\n  " + tm_show(th.concl) + "\nbut the goal is\n  " + tm_show(goal.concl))
        th = th3
    th.hyps.each -> (h)
      ok = false
      goal.hyps.each -> (gh)
        if !ok && tm_eq(gh[1], h)
          ok = true
      if !ok
        fail("proof depends on an assumption not in context: " + tm_show(h))
    th

  # Candidates for the same goal repeatedly request the same conversion.
  # Cache checked equations locally, including the original term for collisions.
  -> application_defeq_conv(t, deep)
    cache = application_conversions.definitions
    slot = (t.h % 32)*2 + (deep ? 1 : 0)
    entry = cache[slot]
    if entry != nil && tm_eq(entry.concl.a.b, t)
      return entry
    conv = nil
    if deep
      conv = @d.compute_conv(t)
    else
      conv = @d.beta_eta_conv(t)
      conv = @k.trans(conv, @k.compute(conv.concl.b))
    conv = @k.trans(conv, @d.beta_eta_conv(conv.concl.b))
    cache[slot] = conv
    conv

  # Checked conversion through definitions and repeated-product notation.
  -> try_defeq(th, target)
    begin
      a = application_defeq_conv(th.concl, false)
      b = application_defeq_conv(target, false)
      va = dest_binop(a.concl, "=")[1]
      vb = dest_binop(b.concl, "=")[1]
      if !tm_eq(va, vb)
        # Aliases can occur inside quantified goals as well as at the head.
        b = @k.trans(b, application_defeq_conv(vb, true))
        # A closed theorem cannot convert to a normal form containing free
        # variables. In particular, avoid unfolding an entire quantified rule
        # when trying its unused prefixes against a local goal.
        if th.concl.cl && !b.concl.b.cl
          return nil
        a = @k.trans(a, application_defeq_conv(va, true))
        va = dest_binop(a.concl, "=")[1]
        vb = dest_binop(b.concl, "=")[1]
      if !tm_eq(va, vb)
        sa = application_square_normalization(va)
        sb = application_square_normalization(vb)
        if sa != nil
          a = @k.trans(a, sa)
        if sb != nil
          b = @k.trans(b, sb)
        va = dest_binop(a.concl, "=")[1]
        vb = dest_binop(b.concl, "=")[1]
      if tm_eq(va, vb)
        return @k.eq_mp(@k.sym(b), @k.eq_mp(a, th))
    rescue e
      0
    try_square_fit(th, target)

  # ---------------------------------------------------------------------------
  # Running tactic blocks

  -> run_block(nodes)
    nodes.each -> (n)
      run_node(n)

  -> run_node(n)
    toks = n.toks
    if toks.size == 0
      return
    if toks[0].text == "·" || toks[0].text == "."
      g = first_goal
      sub = Prover.new(@session)
      sub.goals = [g]
      rest = arr_sub(toks, 1, toks.size - 1)
      nodes = []
      parts = semi_parts(rest)
      # block lines indented deeper than the last inline tactic belong to it (`· have h : P` + its proof block)
      owned = []
      siblings = []
      owning = parts.size > 0
      col = 0
      if parts.size > 0
        col = parts[parts.size - 1][0].col
      if parts.size > 0 && !block_tactic?(parts[parts.size - 1])
        owning = false
      n.block.each -> (b)
        if owning && b.toks.size > 0 && b.toks[0].col > col
          owned.push(b)
        else
          owning = false
          siblings.push(b)
      pi = 0
      while pi < parts.size
        if pi == parts.size - 1
          nodes.push(TacNode.new(parts[pi], owned, n.line))
        else
          nodes.push(TacNode.new(parts[pi], [], n.line))
        pi += 1
      siblings.each -> (b)
        nodes.push(b)
      sub.run_block(nodes)
      if sub.goals.size > 0
        fail("line " + n.line.to_s + ": focused goal not closed:\n" + sub.goals[0].goal.show(@k))
      @goals = arr_sub(@goals, 1, @goals.size - 1)
      return
    # a line ending in `<;>` continues on its first indented line: `t1 <;>` / `    t2`
    if toks[toks.size - 1].text == "<;>" && n.block.size > 0
      first = n.block[0]
      return run_node(TacNode.new(toks + first.toks, first.block + arr_sub(n.block, 1, n.block.size - 1), n.line))
    # (t): a parenthesized tactic sequence
    if toks[0].text == "(" && find_top(toks, ")", 0) == toks.size - 1
      return run_node(TacNode.new(arr_sub(toks, 1, toks.size - 2), n.block, n.line))
    # all_goals t : t (which may itself contain <;>) on every open goal
    if toks[0].text == "all_goals" || toks[0].text == "any_goals"
      run_all_goals(arr_sub(toks, 1, toks.size - 1), n.line)
      run_block(n.block)
      return
    # t1 <;> t2 : run t2 on every goal t1 produces (left-associative),
    # except that `<;>` after a top-level `by` belongs to that `by` subproof.
    by_idx = find_top(toks, "by", 0)
    search_toks = by_idx >= 0 ? arr_sub(toks, 0, by_idx) : toks
    k = find_top_last(search_toks, "<;>")
    if k >= 0
      run_then_all(arr_sub(toks, 0, k), arr_sub(toks, k + 1, toks.size - k - 1), n.line)
      run_block(n.block)
      return
    parts = semi_parts(toks)
    if n.block.size > 0 && parts.size > 0 && !block_tactic?(parts[parts.size - 1])
      # An indented continuation owns only this goal and its descendants.
      # Dedenting cannot abandon its goals or consume a surrounding sibling.
      sub = Prover.new(@session)
      sub.goals = [first_goal]
      sub.run_node(TacNode.new(toks, [], n.line))
      sub.run_block(n.block)
      if sub.goals.size > 0
        fail("line " + n.line.to_s + ": indented proof not closed:\n" + sub.goals[0].goal.show(@k))
      @goals = arr_sub(@goals, 1, @goals.size - 1)
      return
    if parts.size > 1
      pi = 0
      while pi < parts.size
        if pi == parts.size - 1 && block_tactic?(parts[pi])
          run_node(TacNode.new(parts[pi], n.block, n.line))
        else
          run_node(TacNode.new(parts[pi], [], n.line))
        pi += 1
      if !block_tactic?(parts[parts.size - 1])
        run_block(n.block)
      return
    begin
      run_tactic(toks, n.block, n.line)
    rescue e
      msg = e.to_s
      if !msg.starts_with?("line ")
        state = ""
        if @goals.size > 0
          state = "\n" + @goals[0].goal.show(@k)
        msg = "line " + n.line.to_s + ": " + msg + state
      raise msg

  -> find_top_last(toks, sym)
    last = -1
    k = find_top(toks, sym, 0)
    while k >= 0
      last = k
      k = find_top(toks, sym, k + 1)
    last

  # runs t1 on the first goal, then t2 on each goal t1 left in its place
  -> run_then_all(t1, t2, line)
    before = @goals.size
    run_node(TacNode.new(t1, [], line))
    made = @goals.size - before + 1
    if made < 0
      made = 0
    produced = arr_sub(@goals, 0, made)
    rest = arr_sub(@goals, made, @goals.size - made)
    out = []
    produced.each -> (sg)
      @goals = [sg]
      run_node(TacNode.new(t2, [], line))
      out = out + @goals
    @goals = out + rest

  # all_goals t : run t on every open goal
  -> run_all_goals(t, line)
    gs = @goals
    out = []
    gs.each -> (sg)
      @goals = [sg]
      run_node(TacNode.new(t, [], line))
      out = out + @goals
    @goals = out

  # tactics that take an indented block as their own proof (`have h : P` + block, `calc` + steps)
  -> block_tactic?(part)
    if part.size == 0
      return false
    if part[0].text == "calc"
      return true
    if part[0].text != "have"
      return false
    find_top(part, ":=", 0) < 0 || part[part.size - 1].text == "by"

  # Splits `t1; t2; …` at top-level semicolons, except that everything after a top-level `by` belongs to that `by`
  # (`have h : P := by t1; t2` runs t1 and t2 on the subgoal, as `by_nodes` does).
  -> semi_parts(toks)
    k = find_top(toks, "by", 0)
    if k < 0
      out = []
      split_top(toks, ";").each -> (p)
        if p.size > 0
          out.push(p)
      return out
    out = []
    pre = split_top(arr_sub(toks, 0, k), ";")
    i = 0
    while i < pre.size - 1
      if pre[i].size > 0
        out.push(pre[i])
      i += 1
    last = []
    if pre.size > 0
      last = pre[pre.size - 1]
    out.push(last + arr_sub(toks, k, toks.size - k))
    out

  -> run_tactic(toks, block, line)
    name = toks[0].text
    args = arr_sub(toks, 1, toks.size - 1)
    if name == "all_goals" || name == "any_goals"
      return run_all_goals(args, line)
    g = first_goal
    conv = @d.beta_norm_opt(g.goal.concl)
    if conv != nil
      normalized = dest_binop(conv.concl, "=")[1]
      refs = refine(g, [g.goal.with_concl(normalized)], ->(ts) @k.eq_mp(@k.sym(conv), ts[0]))
      g = refs[0]
    case name
    when "intro", "intros"
      tac_intro(g, args, name == "intros")
    when "exact"
      th = proof_expr(g.goal, args, g.goal.concl)
      close(g, fit(g, th))
    when "apply"
      tac_apply(g, args)
    when "refine"
      tac_apply(g, args)
    when "assumption"
      tac_assumption(g)
    when "rfl"
      tac_rfl(g)
    when "trivial"
      tac_trivial(g)
    when "constructor", "split"
      tac_constructor(g)
    when "left"
      tac_left_right(g, true)
    when "right"
      tac_left_right(g, false)
    when "use", "exists"
      tac_use(g, args)
    when "exfalso"
      tac_exfalso(g)
    when "by_contra", "by_contradiction"
      tac_by_contra(g, args)
    when "by_cases"
      tac_by_cases(g, args)
    when "contradiction"
      tac_contradiction(g)
    when "have"
      tac_have(g, args, block, line)
    when "set"
      tac_set(g, args)
    when "show"
      tac_show(g, args)
    when "obtain", "rcases"
      tac_obtain(g, args)
    when "cases"
      tac_cases(g, args)
    when "interval_cases"
      tac_interval_cases(g, args)
    when "induction"
      tac_induction(g, args)
    when "rw", "rewrite"
      tac_rw(g, args)
    when "simp", "simp_all"
      tac_simp(g, args, name == "simp_all")
    when "simpa"
      tac_simpa(g, args)
    when "unfold"
      tac_unfold(g, args)
    when "decide"
      tac_decide(g)
    when "norm_num"
      tac_norm_num(g, args)
    when "ring"
      tac_ring(g)
    when "field_simp"
      tac_field_simp(g, args)
    when "linear_combination"
      tac_linear_combination(g, args)
    when "linarith", "arith"
      tac_linarith(g, args)
    when "omega"
      @omega_mode = true
      begin
        tac_linarith(g, args)
      rescue e
        @omega_mode = false
        raise e
      @omega_mode = false
    when "positivity"
      tac_positivity(g, args)
    when "continuity"
      tac_continuity(g, args)
    when "canalytic", "analytic"
      tac_canalytic(g, args)
    when "push_cast"
      tac_push_cast(g, args)
    when "nlinarith"
      @nl_mode = true
      begin
        tac_linarith(g, args)
      rescue e
        @nl_mode = false
        raise e
      @nl_mode = false
    when "sat"
      tac_sat(g)
    when "auto", "tauto", "aesop"
      hints = []
      if args.size > 0
        if args.size < 2 || args[0].text != "\[" || args[args.size - 1].text != "]"
          fail("auto: expected a bracketed list of lemmas")
        inner = arr_sub(args, 1, args.size - 2)
        if inner.size > 0
          split_top(inner, ",").each -> (hint)
            hints = hints + auto_hint_rules(g.goal, proof_expr(g.goal, hint, nil))
      @open_interval_case = nil
      begin
        tac_auto(g, 3, hints, [24, 4], [])
      rescue e
        if e.to_s == "auto failed" && @goals.size > 0
          goal = first_goal.goal
          note = strict_bound_feedback(goal, hints)
          if note == nil
            begin
              sides = @k.dest_eq(goal.concl)
              layout = sides == nil ? nil : @session.elab.record_layout(type_of(sides[0]))
              if layout != nil
                note = record_evidence(goal, sides, layout, hints, true)
              if note == nil && dest_binop(goal.concl, "all") != nil
                note = auto_list_evidence(goal, hints, true)
              if note == nil
                note = witness_feedback(goal, hints)
              if note == nil
                note = hint_feedback(goal, hints)
            rescue diagnostic_error
              note = nil
          if note == nil && @open_interval_case != nil && @open_interval_case[0] == goal
            note = @open_interval_case[1]
          if note != false
            refutation = polynomial_counterexample(g.goal, hints)
            if refutation != nil
              note = note == nil ? refutation : note + "\n" + refutation
          if note
            fail("auto failed\n" + note)
        raise e
    when "specialize"
      tac_specialize(g, args)
    when "symm"
      tac_symm(g)
    when "calc"
      tac_calc(g, args, block)
    when "ext"
      sides = @k.dest_eq(g.goal.concl)
      if sides != nil && type_of(sides[0]).fun?
        return tac_funext(g, args)
      record = sides == nil ? nil : @session.elab.record_layout(type_of(sides[0]))
      if record == nil
        fail("ext: expected an equality of structures, pairs or functions")
      if args.size > 0
        fail("ext: a structure equality takes no binder")
      parts = record_equation(sides, record)
      if parts[0].empty?()
        return close(g, parts[1].call([]))
      refine(g, parts[0].map(-> (eq) g.goal.with_concl(eq)), parts[1])
    when "funext"
      tac_funext(g, args)
    when "subst"
      tac_subst(g, args)
    when "sorry", "admit"
      close(g, @k.sorry_thm(g.goal.concl))
    when "revert"
      tac_revert(g, args)
    when "clear"
      @goals[0] = GoalRef.new(g.goal, g.node, g.index)
    else
      expression = parse_expr_toks(toks)
      if proof_line?(g.goal, expression)
        return close(g, fit(g, proof_ast(g.goal, expression, g.goal.concl)))
      fail("unknown tactic '" + name + "'")

  # A known proof expression can stand alone as a proof step. Tactic names
  # are dispatched first; term variables and unknown names are not guessed.
  -> proof_line?(goal, expression)
    if expression.kind == :id
      if goal.fixes.any?(->(fixed) fixed[0] == expression.s)
        return false
      return !term_def?(goal, expression.s) && lookup_proof(goal, expression.s) != nil
    if expression.kind == :app || expression.kind == :proj || expression.kind == :paren
      return proof_line?(goal, expression.kids[0])
    expression.kind == :anon

  # ---------------------------------------------------------------------------
  # Proof expressions: hypothesis/theorem names applied to terms and proofs.

  -> elab_term(goal, toks, expected = nil)
    e = parse_expr_toks(toks)
    elab_term_ast(goal, e, expected)

  -> elab_term_ast(goal, e, expected = nil)
    @session.elab.elab_in(e, goal.fixes, expected)

  -> proof_expr(goal, toks, expected = nil)
    e = parse_expr_toks(toks)
    proof_ast(goal, e, expected)

  -> lookup_proof(goal, name)
    p = goal.hyp(name)
    if p != nil
      return @k.assume(p)
    th = @session.theorem(name)
    if th != nil
      return th
    # projections h.1 h.2 h.mp h.mpr h.symm, or bundled structure/class law x.<law>
    if name.include?(".")
      parts = name.split(".")
      prefix_name = arr_sub(parts, 0, parts.size - 1).join(".")
      field = parts[parts.size - 1]
      if ["1", "2", "left", "right", "mp", "mpr", "symm"].include?(field)
        base = lookup_proof(goal, prefix_name)
        if base != nil
          return project_proof(base, field)
      law_th = lookup_term_law_by_name(goal, prefix_name, field)
      if law_th != nil
        return law_th
    nil

  -> lookup_term_law_by_name(goal, prefix_name, field)
    tm = nil
    goal.fixes.each -> (f)
      if f[0] == prefix_name
        tm = f[1]
    if tm == nil
      begin
        tm = elab_term(goal, [Tok.new(:id, prefix_name, 0, 0)], nil)
      rescue _e
        tm = nil
    if tm == nil
      return nil
    project_term_law(goal, tm, field)

  -> project_term_law(goal, base_tm, field)
    ty = type_of(base_tm)
    if ty.tag != :c || !@session.elab.laws_of(ty.name).include?(field)
      return nil
    law_th = @session.theorem(ty.name + "." + field)
    if law_th == nil
      return nil
    val_th = synth_valid(goal, base_tm, 0)
    if val_th == nil
      return nil
    q = dest_unop(law_th.concl, "∀")
    if q == nil
      return nil
    m = {}
    if !ty_match(q.ty, ty, m)
      return nil
    th_i = m.size > 0 ? @k.inst_type(law_th, m) : law_th
    @d.beta_norm_thm(@k.mp(@k.spec(base_tm, th_i), val_th))

  -> synth_goal_instance(goal, cty, depth = 0)
    if depth > 8 || cty.tag != :c || !@session.elab.is_class_ty?(cty)
      return nil
    i = goal.fixes.size - 1
    while i >= 0
      fv = goal.fixes[i][1]
      if ty_eq(fv.ty, cty)
        return fv
      i -= 1
    list = @session.elab.instances[cty.name]
    if list == nil
      return nil
    j = list.size - 1
    while j >= 0
      entry = list[j]
      m = {}
      if ty_match(entry[1], cty, m)
        ok = true
        dep_tms = []
        entry[2].each -> (dt)
          sub = synth_goal_instance(goal, ty_subst(dt, m), depth + 1)
          if sub == nil
            ok = false
          else
            dep_tms.push(sub)
        if ok
          g_ty = @k.const_type(entry[0])
          res = mk_const_raw(entry[0], ty_subst(g_ty, m))
          dep_tms.each -> (dtm)
            res = mk_app(res, dtm)
          return res
      j -= 1
    nil

  -> synth_valid(goal, tm, depth = 0)
    if depth > 6
      return nil
    ty = type_of(tm)
    if ty.tag != :c || !@session.elab.has_laws?(ty.name)
      return nil
    want = mk_app(mk_const_raw(ty.name + ".Valid", ty_fun(ty, ty_bool)), tm)
    i = goal.hyps.size - 1
    while i >= 0
      if tm_eq(goal.hyps[i][1], want)
        return @k.assume(want)
      i -= 1
    sp = strip_app(tm)
    hd = sp[0]
    args = sp[1]
    if hd.tag == :const
      vth = @session.theorem(hd.name + ".valid")
      if vth != nil
        m = {}
        if ty_match(@k.const_type(hd.name), hd.ty, m)
          cur = m.size > 0 ? @k.inst_type(vth, m) : vth
          args.each -> (arg)
            if dest_unop(cur.concl, "∀") != nil
              cur = @k.spec(arg, cur)
          ok = true
          while ok && dest_binop(cur.concl, "⇒") != nil
            prem = dest_binop(cur.concl, "⇒")[0]
            if prem.tag == :app && prem.a.tag == :const && prem.a.name.ends_with?(".Valid")
              sv = synth_valid(goal, prem.b, depth + 1)
              if sv == nil
                ok = false
              else
                cur = @k.mp(cur, sv)
            else
              ok = false
          if ok && tm_eq(cur.concl, want)
            return cur
      if hd.name == ty.name + ".mk" && depth <= 2
        begin
          sub = Prover.new(@session)
          root = GoalRef.new(Goal.new(goal.fixes, goal.hyps, want), nil, 0)
          sub.goals = [root]
          sub.auto_prove_valid_state(nil, ty.name)
          if sub.goals.size == 0
            return root.thm
        rescue _e
          0
    nil

  -> auto_prove_valid_state(const_name, sname)
    uf_toks = []
    if const_name != nil
      uf_toks.push(Tok.new(:id, const_name, 0, 0))
    uf_toks.push(Tok.new(:id, sname + ".Valid", 0, 0))
    begin
      tac_unfold(first_goal, uf_toks)
    rescue _e
      0
    begin
      tac_simp(first_goal, [], false)
    rescue _e
      0
    guard = 0
    while @goals.size > 0 && guard < 256
      guard += 1
      g = first_goal
      if dest_binop(g.goal.concl, "∧") != nil
        tac_constructor(g)
        next
      if dest_unop(g.goal.concl, "∀") != nil || dest_binop(g.goal.concl, "⇒") != nil
        intro1(g, "_")
        next
      solved = false
      ["simp", "ring", "omega", "decide", "nlinarith", "auto"].each -> (tname)
        if !solved && @goals.size > 0 && @goals[0] == g
          saved = @goals + []
          begin
            run_tactic([Tok.new(:id, tname, 0, 0)], [], 0)
            if @goals.size == 0 || @goals[0] != g
              solved = true
          rescue _e
            @goals = saved
      if !solved
        break

  # Expose a connective hidden behind a defined predicate. Only reduce the
  # applied head so evidence for its arguments keeps its original spelling.
  -> proof_head_conv(t, connectives, remaining = nil)
    cur = t
    result = nil
    while true
      spine = strip_app(cur)
      head = spine[0]
      if head.tag == :lam && !spine[1].empty?()
        step = @k.refl(head)
      else
        if head.tag != :const
          return nil
        if connectives.include?(head.name)
          return result
        if remaining != nil
          if remaining <= 0 || !auto_small_term?(cur, [256])
            return nil
          remaining -= 1
        definition = @k.defs[head.name]
        if definition == nil
          return nil
        step = Simp.new(@d, [make_rule(@d, definition, head.name)]).rewrite_top(head, 0)
        if step == nil
          return nil
      spine[1].each -> (arg)
        step = @d.ap_thm(step, arg)
        if step.concl.b.a.tag == :lam
          step = @k.trans(step, @k.beta(step.concl.b))
      result = result == nil ? step : @k.trans(result, step)
      cur = step.concl.b

  -> project_proof(th, field)
    th = @d.beta_norm_thm(th)
    connective = ["1", "left", "2", "right"].include?(field) ? "∧" : "="
    if dest_binop(th.concl, connective) == nil
      conv = proof_head_conv(th.concl, [connective])
      if conv != nil
        th = @k.eq_mp(conv, th)
    case field
    when "1", "left"
      @k.conj1(th)
    when "2", "right"
      @k.conj2(th)
    when "mp"
      e = dest_binop(th.concl, "=")
      if e == nil || !ty_eq(type_of(e[0]), ty_bool)
        fail(".mp needs an equivalence")
      @k.disch(e[0], @k.eq_mp(th, @k.assume(e[0])))
    when "mpr"
      e = dest_binop(th.concl, "=")
      if e == nil || !ty_eq(type_of(e[0]), ty_bool)
        fail(".mpr needs an equivalence")
      @k.disch(e[1], @k.eq_mp(@k.sym(th), @k.assume(e[1])))
    when "symm"
      @k.sym(th)
    else
      fail("unknown projection ." + field)

  -> project_rule_thm(th, field)
    if !["1", "2", "left", "right", "mp", "mpr", "symm"].include?(field)
      return nil
    begin
      used = {}
      tm_free_names_into(th.concl, used)
      th.hyps.each -> (h)
        tm_free_names_into(h, used)
      vars = []
      t = @d.beta_norm_thm(th)
      while true
        q = dest_unop(t.concl, "∀")
        if q == nil || q.tag != :lam
          break
        nm = q.name
        if nm == nil || nm == ""
          nm = "x"
        v = mk_var(fresh_name_from_set(nm, used), q.ty)
        vars.push(v)
        t = @k.spec(v, t)
      c = t.concl
      conds = []
      while dest_binop(c, "⇒") != nil
        pq = dest_binop(c, "⇒")
        conds.push(pq[0])
        c = pq[1]
      u = t
      conds.each -> (p)
        u = @k.mp(u, @k.assume(p))
      u = project_proof(u, field)
      i = conds.size - 1
      while i >= 0
        u = @k.disch(conds[i], u)
        i -= 1
      return @d.gen_all(vars, u)
    rescue _e
      return nil

  -> extract_projected_thm(goal, node)
    while node.kind == :paren
      node = node.kids[0]
    if node.kind == :id
      if node.s == "rfl" || node.s == "trivial"
        return nil
      if (goal.hyp(node.s) == nil && goal.fixes.any?(->(f) f[0] == node.s)) || term_def?(goal, node.s)
        return nil
      th = lookup_proof(goal, node.s)
      return th == nil ? nil : [th, [], false]
    if node.kind == :app
      sp = @session.elab.ast_spine(node)
      base = extract_projected_thm(goal, sp[0])
      return base == nil ? nil : [base[0], base[1] + sp[1], base[2]]
    if node.kind == :proj && ["1", "2", "left", "right", "mp", "mpr", "symm"].include?(node.s)
      base = extract_projected_thm(goal, node.kids[0])
      if base == nil
        return nil
      pth = project_rule_thm(base[0], node.s)
      return pth == nil ? nil : [pth, base[1], true]
    nil

  -> proof_name?(goal, e)
    if e.kind == :proj || e.kind == :anon || e.kind == :by
      return true
    if e.kind == :id
      if e.s == "rfl" || e.s == "trivial"
        return true
      if goal.hyp(e.s) == nil && goal.fixes.any?(->(f) f[0] == e.s)
        return false
      return !term_def?(goal, e.s) && lookup_proof(goal, e.s) != nil
    if e.kind == :app
      h = @session.elab.ast_spine(e)[0]
      return h.kind == :id && goal.fixes.select(->(f) f[0] == h.s).size == 0 && !term_def?(goal, h.s) && lookup_proof(goal, h.s) != nil
    false

  # a defined function or constant (not a theorem or hypothesis): an argument
  # `(f x)` built from it is a term, not a proof
  -> term_def?(goal, name)
    if goal.hyp(name) != nil || @session.theorems.has_key?(name)
      return false
    @k.defs.has_key?(name)

  -> proof_ast(goal, e, expected = nil)
    if expected != nil
      conv = @d.beta_norm_opt(expected)
      if conv != nil
        normalized = dest_binop(conv.concl, "=")[1]
        th = fit_concl(proof_ast(goal, e, normalized), normalized)
        return @k.eq_mp(@k.sym(conv), th)
    if e.kind == :by
      if expected == nil
        fail("(by …) needs a known statement here")
      return run_subproof(goal, expected, by_nodes(e.binders, [], 0))
    if e.kind == :proj
      if !["1", "2", "left", "right", "mp", "mpr", "symm"].include?(e.s)
        begin
          btm = elab_term_ast(goal, e.kids[0], nil)
          lth = project_term_law(goal, btm, e.s)
          if lth != nil
            if expected != nil && !tm_eq(lth.concl, expected)
              return instantiate_to(goal, lth, [], expected, false)[0]
            return lth
        rescue _e
          0
      proj_sp = extract_projected_thm(goal, e)
      if proj_sp != nil && proj_sp[2]
        return instantiate_to(goal, proj_sp[0], proj_sp[1], expected, false)[0]
      return project_proof(proof_ast(goal, e.kids[0], nil), e.s)
    if e.kind == :id && e.s == "rfl" && expected != nil
      eq = dest_binop(expected, "=")
      if eq != nil
        if tm_eq(eq[0], eq[1])
          return @k.refl(eq[0])
        a = @k.compute(eq[0])
        b = @k.compute(eq[1])
        return @k.trans(a, @k.sym(b))
    if e.kind == :id && e.s == "trivial" && expected != nil && is_const?(expected, "⊤")
      return @k.truth
    if e.kind == :id
      th = lookup_proof(goal, e.s)
      if th == nil
        fail("unknown hypothesis or theorem '" + e.s + "'")
      if expected != nil
        if tm_eq(th.concl, expected)
          return th
        if tm_eq(@d.beta_norm_term(th.concl), @d.beta_norm_term(expected))
          return th
        return instantiate_to(goal, th, [], expected, false)[0]
      return th
    if e.kind == :app
      sp = @session.elab.ast_spine(e)
      head = sp[0]
      if head.kind == :id
        th = lookup_proof(goal, head.s)
        if th == nil
          fail("unknown hypothesis or theorem '" + head.s + "'")
        r = instantiate_to(goal, th, sp[1], expected, false)
        return r[0]
      proj_sp = extract_projected_thm(goal, e)
      if proj_sp != nil && proj_sp[2]
        return instantiate_to(goal, proj_sp[0], proj_sp[1], expected, false)[0]
      # `(thm a b).mpr h`: any other head is itself a proof expression
      if head.kind == :proj || head.kind == :paren || head.kind == :app
        r = instantiate_to(goal, proof_ast(goal, head, nil), sp[1], expected, false)
        return r[0]
    if e.kind == :anon
      if expected == nil
        return anon_conj_proof(goal, e.kids)
      return anon_proof(goal, e.kids, expected)
    if e.kind == :app && e.kids[0].kind == :id && e.kids[0].s == "by"
      fail("nested by")
    fail("cannot read proof expression")

  -> anon_conj_proof(goal, items)
    if items.size < 2
      fail("⟨...⟩ needs a known goal")
    a = proof_ast(goal, items[0], nil)
    b = items.size == 2 ? proof_ast(goal, items[1], nil) : anon_conj_proof(goal, arr_sub(items, 1, items.size - 1))
    @k.conj(a, b)

  -> anon_proof(goal, items, expected)
    c = expected
    ex = dest_unop(c, "∃")
    if ex != nil && ex.tag == :lam
      w = elab_term_ast(goal, items[0], ex.ty)
      body = tm_instantiate(ex.b, w, 0)
      rest = nil
      if items.size == 2
        rest = proof_ast(goal, items[1], body)
      else
        rest = anon_proof(goal, arr_sub(items, 1, items.size - 1), body)
      rest = fit_concl(rest, body)
      return @k.exists_intro(c, w, rest)
    pq = dest_binop(c, "∧")
    if pq != nil
      a = fit_concl(proof_ast(goal, items[0], pq[0]), pq[0])
      b = nil
      if items.size == 2
        b = proof_ast(goal, items[1], pq[1])
      else
        b = anon_proof(goal, arr_sub(items, 1, items.size - 1), pq[1])
      return @k.conj(a, fit_concl(b, pq[1]))
    e = dest_binop(c, "=")
    if e != nil && type_of(e[0]).name == "bool" && items.size == 2
      a = fit_concl(proof_ast(goal, items[0], @k.bin("⇒", e[0], e[1])), @k.bin("⇒", e[0], e[1]))
      b = fit_concl(proof_ast(goal, items[1], @k.bin("⇒", e[1], e[0])), @k.bin("⇒", e[1], e[0]))
      return @k.deduct_antisym(@d.undisch(b), @d.undisch(a))
    conv = proof_head_conv(c, ["∃", "∧", "="])
    if conv != nil
      return @k.eq_mp(@k.sym(conv), anon_proof(goal, items, conv.concl.b))
    fail("⟨...⟩: goal is not ∃, ∧ or ↔: " + tm_show(c))

  -> fit_concl(th, target)
    if tm_eq(th.concl, target)
      return th
    th2 = @d.beta_norm_thm(th)
    t2 = @d.beta_norm_term(target)
    if tm_eq(th2.concl, t2)
      return @k.eq_mp(@k.sym(@d.beta_norm_conv(target)), th2)
    th3 = try_eta_fit(th, target)
    if th3 != nil
      return th3
    th3 = try_defeq(th, target)
    if th3 != nil
      return th3
    fail("mismatch: have " + tm_show(th.concl) + " but need " + tm_show(target))

  -> try_eta_fit(th, target)
    from = @d.beta_eta_conv(th.concl)
    to = @d.beta_eta_conv(target)
    if !tm_eq(dest_binop(from.concl, "=")[1], dest_binop(to.concl, "=")[1])
      return nil
    @k.eq_mp(@k.sym(to), @k.eq_mp(from, th))

  # A complete match takes precedence. If the witnesses are spread across
  # relational premises, combine unique partial matches without backtracking.
  -> infer_from_premises(goal, steps, mt, hints)
    missing = steps.select(-> (step) step[0] == :all && !mt.tm.has_key?(step[1].vkey)).map -> (step) step[1]
    if missing.empty?()
      return mt
    facts = (goal.hyps.map -> (h) h[1]) + (hints.map -> (th) th.concl)
    premises = steps.select(-> (step) step[0] != :all).map -> (step) step[1]
    agreed = nil
    premises.each -> (prem)
      if !missing.all?(-> (v) tm_free_in?(v, prem))
        next
      matches = premise_bindings(mt, prem, facts, missing, false)
      if matches[1]
        return mt
      trial = matches[0]
      if trial != nil
        if agreed != nil && !agreed.same_bindings?(trial)
          return mt
        agreed = trial
    if agreed != nil || missing.size < 2
      return agreed == nil ? mt : agreed
    current = mt
    while !missing.empty?()
      before = current.tm.size
      premises.each -> (prem)
        needed = missing.select -> (v) tm_free_in?(v, prem)
        if !needed.empty?()
          matches = premise_bindings(current, prem, facts, needed, true)
          if matches[0] != nil && !matches[1]
            current = matches[0]
            missing = missing.select -> (v) !current.tm.has_key?(v.vkey)
      if current.tm.size == before
        # Rigid premises may have fixed the structure and its maps. With one
        # witness left, an equation can now determine it without guessing.
        if missing.size == 1 && current.tm.size > mt.tm.size
          return infer_from_premises(goal, steps, current, hints)
        return mt
    current

  # Return the common substitution and whether different witnesses matched.
  -> premise_bindings(mt, prem, facts, needed, partial)
    head = strip_app(prem)[0]
    if head.tag == :var && mt.tm.has_key?(head.vkey)
      head = mt.tm[head.vkey]
    if head.tag != :const && head.tag != :var
      return [nil, false]
    # Bounds and logical connectives are too broad to select partial witnesses.
    if partial && ["∀", "∃", "⇒", "∧", "∨", "¬", "=", "<", "≤"].include?(head.name)
      return [nil, false]
    agreed = nil
    facts.each -> (fact)
      hyp_head = strip_app(fact)[0]
      if hyp_head.tag != head.tag || hyp_head.name != head.name
        next
      trial = partial ? match_application_folded(mt, prem, fact) : match_application(mt, prem, fact)
      if trial == nil || !needed.all?(-> (v) trial.tm.has_key?(v.vkey))
        next
      if agreed != nil && !agreed.same_bindings?(trial)
        return [nil, true]
      agreed = trial
    [agreed, false]

  # Instantiate theorem th with explicit args; match its conclusion against
  # `target` (if given). Returns [thm, remaining premise props].
  # With allow_open, unproved premises are returned instead of failing.
  -> instantiate_to(goal, th, args, target, allow_open, hints = [], match_result = false, deferred_rw_by = nil)
    k = @k
    # rename type variables to fresh pattern type vars
    tyvars = tm_tyvars(th.concl)
    hv = []
    th.hyps.each -> (h)
      tm_tyvars_into(h, hv)
    # A projection or partially applied theorem can contain fixed local terms
    # even with no hypotheses. Their types were already chosen by the caller.
    tm_frees(th.concl).each -> (v)
      tm_tyvars_into(v, hv)
    ren = {}
    tvs = {}
    tyvars.each -> (x)
      if !hv.include?(x)
        nn = "§" + x
        ren[x] = ty_var(nn)
        tvs[nn] = true
    t = th
    if ren.size > 0
      t = k.inst_type(th, ren)
    # A local `have` can retain an applied predicate at its head. Expose its
    # checked logical form before discovering any arguments to consume.
    t = @d.beta_norm_thm(t)
    # telescope: walk ∀ and ⇒, creating pattern vars
    steps = []
    pvars = {}
    used_names = {}
    goal.all_terms.each -> (gt)
      tm_free_names_into(gt, used_names)
    tm_free_names_into(t.concl, used_names)
    cur = t.concl
    th_cur = t
    curs = [cur]
    while true
      q = dest_unop(cur, "∀")
      if q != nil && q.tag == :lam
        nm = q.name
        if nm == nil || nm == ""
          nm = "x"
        v = mk_var(fresh_name_from_set("?" + nm, used_names), q.ty)
        pvars[v.vkey] = true
        steps.push([:all, v])
        cur = tm_instantiate(q.b, v, 0)
        curs.push(cur)
      else
        pq = dest_binop(cur, "⇒")
        nq = dest_unop(cur, "¬")
        if pq != nil
          steps.push([:imp, pq[0]])
          cur = pq[1]
          curs.push(cur)
        elsif nq != nil && ((target != nil && is_const?(target, "⊥")) || (target == nil && steps.size == 0 && args.size > 0))
          steps.push([:not, nq])
          cur = @k.false_tm
          curs.push(cur)
        else
          break
    mt = Matcher.new(pvars, tvs)
    proofs = {}
    deferred_by = {}
    ai = 0
    si = 0
    # ∀-steps filled out of order: Satori hoists every ∀ binder to the front of a statement, so in
    # `thm L a ha u hu` (declared (L a) (ha) (u) (hu)) the term u arrives while the next step is the premise of ha's kind
    filled = {}
    has_hole = false
    maxused = -1
    while ai < args.size
      a = args[ai]
      a_is_hole = a.kind == :hole || (a.kind == :id && a.s == "_")
      isproof = a_is_hole ? false : proof_name?(goal, a)
      if isproof
        # Synthesize any now-determined leading typeclass dictionaries so `.Valid` guards can be auto-discharged
        steps.each -> (st)
          if st[0] == :all && !mt.tm.has_key?(var_key(st[1]))
            cty = ty_subst(st[1].ty, mt.ty)
            if @session.elab.is_class_ty?(cty) && !ty_vars(cty).any?(-> (tv) tvs.has_key?(tv))
              dict = synth_goal_instance(goal, cty, 0)
              if dict != nil
                mt.m(st[1], dict, 0)
      while si < steps.size
        if filled.has_key?(si) || (steps[si][0] == :all && isproof)
          si += 1
        elsif isproof && steps[si][0] == :imp && !proofs.has_key?(si) && !deferred_by.has_key?(si)
          prem_auto = closed_or_nil(tm_subst(steps[si][1], mt.tm), pvars)
          if prem_auto != nil
            prem_auto = tm_inst_types(prem_auto, mt.ty)
          if prem_auto != nil && prem_auto.tag == :app && prem_auto.a.tag == :const && prem_auto.a.name.ends_with?(".Valid")
            vth_auto = synth_valid(goal, prem_auto.b, 0)
            if vth_auto != nil
              proofs[si] = vth_auto
              if si > maxused
                maxused = si
              si += 1
            else
              break
          else
            break
        else
          break
      tstep = si
      if !isproof
        # Check if `a` explicitly supplies a dictionary of a class type
        arg_class_name = nil
        if !a_is_hole
          begin
            probe = elab_term_ast(goal, a, nil)
            pty = type_of(probe)
            if pty.tag == :c && @session.elab.is_class_ty?(pty)
              arg_class_name = pty.name
          rescue _e
            arg_class_name = nil
        # the earliest ∀ binder still unbound (skipping leading typeclass dictionaries unless explicitly passed)
        j = 0
        while j < steps.size
          if steps[j][0] == :all && !filled.has_key?(j) && !mt.tm.has_key?(var_key(steps[j][1]))
            sty = steps[j][1].ty
            if !@session.elab.is_class_ty?(sty) || (arg_class_name != nil && sty.tag == :c && sty.name == arg_class_name)
              break
          j += 1
        if j >= steps.size
          j = 0
          while j < steps.size && !(steps[j][0] == :all && !filled.has_key?(j) && !mt.tm.has_key?(var_key(steps[j][1])))
            j += 1
        if j < steps.size
          tstep = j
      if tstep >= steps.size
        if ai > 0
          # Instantiating a predicate may expose more logical arguments.
          # Replay the supplied prefix, then continue from its checked beta
          # conversion. Each retry consumes at least one source argument.
          prefix = instantiate_to(goal, th, arr_sub(args, 0, ai), nil, false)
          resumed = @d.beta_norm_thm(prefix[0])
          return instantiate_to(goal, resumed, arr_sub(args, ai, args.size - ai), target, allow_open, hints, match_result, deferred_rw_by)
        fail("too many arguments")
      if steps[tstep][0] == :all
        if a_is_hole
          has_hole = true
          if tstep > maxused
            maxused = tstep
          if tstep == si
            si += 1
          filled[tstep] = true
        else
          v = steps[tstep][1]
          vt = ty_subst(v.ty, mt.ty)
          term = nil
          inferred_types = {}
          ty_vars(vt).each -> (name)
            if tvs.has_key?(name)
              inferred_types[name] = @session.elab.fresh_meta
          # Keep known parts of the expected type (e.g. a projection's domain)
          # while allowing its remaining type parameters to be inferred.
          term = elab_term_ast(goal, a, ty_subst(vt, inferred_types))
          if !mt.m(v, term, 0)
            fail("argument has the wrong type")
          if tstep > maxused
            maxused = tstep
          if tstep == si
            si += 1
          else
            filled[tstep] = true
      else
        if a_is_hole && allow_open
          if si > maxused
            maxused = si
          si += 1
        else
          prem = steps[si][1]
          prem_i = closed_or_nil(tm_subst(prem, mt.tm), pvars)
          if prem_i != nil
            prem_i = tm_inst_types(prem_i, mt.ty)
          if a.kind == :by && prem_i == nil && (target != nil || deferred_rw_by != nil)
            deferred_by[si] = a
            if si > maxused
              maxused = si
            si += 1
          else
            if si > maxused
              maxused = si
            pth = proof_ast(goal, a, prem_i)
            matched = match_application(mt, prem, pth.concl)
            if matched == nil && prem_i != nil
              # A hypothesis or projection can prove a definitionally equal alias.
              # Convert the supplied proof before matching the known premise; the
              # conversion preserves its assumptions and is replayed by the kernel.
              converted = try_defeq(pth, prem_i)
              if converted != nil
                matched = match_application(mt, prem, converted.concl)
                if matched != nil
                  pth = converted
            if matched == nil
              fail("argument proves " + tm_show(pth.concl) + " but the premise is " + tm_show(prem))
            mt = matched
            proofs[si] = pth
            si += 1
      ai += 1
    if target != nil
      # Match the visible conclusions before expanding aliases in the target.
      # A large defined argument can occur under a rigid relation even when a
      # shorter prefix still has an implication at its head.
      # In backwards search an arithmetic rule concludes a comparison. Its
      # quantified and conditional prefixes are premises to open, and fully
      # expanding them can duplicate every definition in a large theorem.
      cmp = match_result ? dest_cmp_rel(target) : nil
      start = cmp != nil && numeric_type?(type_of(cmp[1])) ? steps.size : si
      found = -1
      [false, true].each -> (aliases)
        j = start
        while j <= steps.size && found < 0
          trial = aliases ? match_application_aliases(mt, curs[j], target) : match_application_folded(mt, curs[j], target)
          if trial != nil
            found = j
            mt = trial
          j += 1
      if found < 0 && args.size > 0 && deferred_by.size == 0
        # Expose a supplied predicate's telescope before definitional fitting
        # can erase a premise such as True. `apply` still opens that premise.
        prefix = instantiate_to(goal, th, args, nil, false)
        resumed = @d.beta_norm_thm(prefix[0])
        if !tm_eq(resumed.concl, th.concl)
          return instantiate_to(goal, resumed, [], target, allow_open, hints)
      if found < 0
        # Preserve ordinary premise matching before trying aliases: computing
        # a whole implication can otherwise erase a trivially true premise.
        j = start
        while j <= steps.size && found < 0
          instantiated = closed_or_nil(tm_subst(curs[j], mt.tm), pvars)
          if instantiated != nil
            instantiated = tm_inst_types(instantiated, mt.ty)
            if try_defeq(k.assume(instantiated), target) != nil
              found = j
          j += 1
      if found < 0
        fail("cannot match " + tm_show(cur) + " with goal " + tm_show(target))
      steps = arr_sub(steps, 0, found)
      if (allow_open || has_hole || deferred_by.size > 0) && mt.tm.size < pvars.size && (goal.hyps.size > 0 || hints.size > 0)
        mt = infer_from_premises(goal, steps, mt, hints)
    elsif (has_hole || deferred_by.size > 0) && mt.tm.size < pvars.size && (goal.hyps.size > 0 || hints.size > 0)
      mt = infer_from_premises(goal, steps, mt, hints)
    # Auto-synthesize leading typeclass dictionaries and bundled .Valid guards
    steps.each -> (st)
      if st[0] == :all && !mt.tm.has_key?(var_key(st[1]))
        cty = ty_subst(st[1].ty, mt.ty)
        if @session.elab.is_class_ty?(cty) && !ty_vars(cty).any?(-> (tv) tvs.has_key?(tv))
          dict = synth_goal_instance(goal, cty, 0)
          if dict != nil
            mt.m(st[1], dict, 0)
    vsi = 0
    while vsi < steps.size
      if steps[vsi][0] == :imp && !proofs.has_key?(vsi) && !deferred_by.has_key?(vsi)
        prem_v = closed_or_nil(tm_subst(steps[vsi][1], mt.tm), pvars)
        if prem_v != nil
          prem_v = tm_inst_types(prem_v, mt.ty)
          if prem_v.tag == :app && prem_v.a.tag == :const && prem_v.a.name.ends_with?(".Valid")
            vth = synth_valid(goal, prem_v.b, 0)
            if vth != nil
              proofs[vsi] = vth
              if vsi > maxused
                maxused = vsi
      vsi += 1
    if deferred_by.size > 0 && (target != nil || deferred_rw_by == nil)
      dsi = 0
      while dsi < steps.size
        if deferred_by.has_key?(dsi) && !proofs.has_key?(dsi)
          dprem = closed_or_nil(tm_subst(steps[dsi][1], mt.tm), pvars)
          if dprem == nil
            fail("(by …) needs a known statement here")
          dprem = tm_inst_types(dprem, mt.ty)
          proofs[dsi] = proof_ast(goal, deferred_by[dsi], dprem)
        dsi += 1
    # build the theorem
    thx = t
    if mt.ty.size > 0
      thx = k.inst_type(thx, mt.ty)
    if target == nil && deferred_rw_by != nil && deferred_by.size > 0
      gens_rw = []
      rem_conds = []
      si = 0
      while si < steps.size
        st = steps[si]
        if st[0] == :all
          v = st[1]
          kk = var_key(v)
          if mt.tm.has_key?(kk)
            thx = k.spec(mt.tm[kk], thx)
          else
            fv = mk_var(fresh_name_from_set(v.name.slice(1, v.name.size - 1), used_names), ty_subst(v.ty, mt.ty))
            gens_rw.push(fv)
            thx = k.spec(fv, thx)
        elsif st[0] == :imp
          prem = dest_binop(thx.concl, "⇒")[0]
          if proofs.has_key?(si)
            thx = k.mp(thx, fit_concl(proofs[si], prem))
          else
            rem_conds.push(prem)
            deferred_rw_by.push(deferred_by[si])
            thx = @d.undisch(thx)
        si += 1
      ri = rem_conds.size - 1
      while ri >= 0
        thx = k.disch(rem_conds[ri], thx)
        ri -= 1
      return [regen(thx, gens_rw), []]
    open = []
    gens = []
    si = 0
    while si < steps.size
      st = steps[si]
      if st[0] == :all
        v = st[1]
        kk = var_key(v)
        if !mt.tm.has_key?(kk)
          # partial application (`have k := thm a b`): nothing after this binder was supplied, so keep it quantified
          if target == nil && si > maxused
            return [regen(thx, gens), open]
          if target == nil
            # a later premise was supplied: instantiate with a fresh variable and generalize back at the end
            fv = mk_var(fresh_name_from_set(v.name.slice(1, v.name.size - 1), used_names), ty_subst(v.ty, mt.ty))
            gens.push(fv)
            thx = k.spec(fv, thx)
            si += 1
            next
          if target != nil || !allow_open
            fail("cannot infer argument " + v.name.slice(1, v.name.size - 1) + " of the theorem")
          # leave universally quantified: stop here
          return [thx, open]
        val = mt.tm[kk]
        thx = k.spec(val, thx)
      elsif st[0] == :not
        prem = dest_unop(thx.concl, "¬")
        if proofs.has_key?(si)
          thx = k.not_elim(thx, fit_concl(proofs[si], prem))
        else
          if !allow_open
            fail("missing proof of premise " + tm_show(prem))
          open.push(prem)
          thx = k.not_elim(thx, k.assume(prem))
      else
        prem = dest_binop(thx.concl, "⇒")[0]
        if proofs.has_key?(si)
          pth = proofs[si]
          thx = k.mp(thx, fit_concl(pth, prem))
        else
          if !allow_open
            if target == nil
              return [regen(thx, gens), open]
            fail("missing proof of premise " + tm_show(prem))
          open.push(prem)
          thx = @d.undisch(thx)
      si += 1
    [regen(thx, gens), open]

  # Compress repeated numeric factors without expanding their contents.
  # Prove v*v = v^2 once per type, then instantiate at the actual operand.
  -> application_square?(t)
    pair = dest_binop(t, "*")
    pair != nil && tm_eq(pair[0], pair[1]) && ["nat", "int", "rat", "real"].include?(type_of(pair[0]).name)

  -> application_square_conv(t, budget)
    budget[0] -= 1
    if budget[0] < 0
      fail("application: square normalization limit")
    th = nil
    if t.tag == :app
      f = application_square_conv(t.a, budget)
      x = application_square_conv(t.b, budget)
      if f != nil || x != nil
        th = @k.mk_comb(f == nil ? @k.refl(t.a) : f, x == nil ? @k.refl(t.b) : x)
    elsif t.tag == :lam
      opened = dest_lam_fresh(t, [t])
      body = application_square_conv(opened[1], budget)
      if body != nil
        th = @k.abs_rule(opened[0], body)
    cur = th == nil ? t : dest_binop(th.concl, "=")[1]
    if application_square?(cur)
      base = dest_binop(cur, "*")[0]
      ty = type_of(base)
      rule = @application_squares[ty.name]
      if rule == nil
        v = mk_var("square", ty)
        product = mk_apps(@k.mk_const("*", ty_funs([ty, ty], ty)), [v, v])
        power = mk_apps(@k.mk_const("^", ty_funs([ty, ty_nat], ty)), [v, mk_lit(2, ty_nat)])
        rule = @k.gen(v, @k.ring_eq(product, power))
        @application_squares[ty.name] = rule
      step = @k.spec(base, rule)
      th = th == nil ? step : @k.trans(th, step)
    th

  -> application_square_normalization(t)
    if (t.search_ops & TERM_SQUARE_PRODUCT) == 0
      return nil
    bucket = @application_square_cache[t.h]
    if bucket != nil
      bucket.each -> (entry)
        if tm_eq(entry[0], t)
          return entry[1]
    conv = nil
    begin
      conv = application_square_conv(t, [128])
    rescue e
      0
    if @application_square_cache.size < 256
      if bucket == nil
        bucket = []
        @application_square_cache[t.h] = bucket
      bucket.push([t, conv])
    conv

  -> try_square_fit(th, target)
    if ((th.concl.search_ops | target.search_ops) & TERM_SQUARE_PRODUCT) == 0
      return nil
    left_head = strip_app(th.concl)[0]
    right_head = strip_app(target)[0]
    if [:const, :var].include?(left_head.tag) && [:const, :var].include?(right_head.tag) && !tm_eq(left_head, right_head)
      return nil
    a = application_square_normalization(th.concl)
    b = application_square_normalization(target)
    if a == nil && b == nil
      return nil
    left = a == nil ? th.concl : dest_binop(a.concl, "=")[1]
    right = b == nil ? target : dest_binop(b.concl, "=")[1]
    if !tm_eq(left, right)
      return nil
    result = a == nil ? th : @k.eq_mp(a, th)
    b == nil ? result : @k.eq_mp(@k.sym(b), result)

  -> match_application_squares(mt, pattern, target)
    a = application_square_normalization(pattern)
    b = application_square_normalization(target)
    if a == nil && b == nil
      return nil
    mt.match_instantiated(@d, a == nil ? pattern : dest_binop(a.concl, "=")[1], b == nil ? target : dest_binop(b.concl, "=")[1])

  -> match_application(mt, pattern, target)
    matched = match_application_folded(mt, pattern, target)
    matched == nil ? match_application_aliases(mt, pattern, target) : matched

  -> match_application_folded(mt, pattern, target)
    if distinct_proposition_heads?(pattern, target)
      return nil
    trial = mt.clone
    if trial.m(pattern, target, 0)
      return trial
    trial = mt.clone
    if trial.m(pattern, @d.beta_norm_term(target), 0)
      return trial
    trial = mt.clone
    if trial.m(@d.beta_eta_term(pattern), @d.beta_eta_term(target), 0)
      return trial
    matched = mt.match_instantiated(@d, pattern, target)
    if matched != nil
      return matched
    begin
      matched = mt.match_instantiated(@d, pattern, target, true)
      if matched != nil
        return matched
    rescue e
      0
    match_application_squares(mt, pattern, target)

  -> match_application_aliases(mt, pattern, target)
    # Expose target-side definitions absent from the theorem's vocabulary.
    # Keep shared operations (such as sum_below) folded while inferring args.
    protected = {}
    application_constants(pattern, protected)
    rules = []
    application_aliases(target, protected, {}, rules, [8])
    if rules.empty?()
      return nil
    begin
      # Infer arguments before a reflexive equality or other outer proposition
      # simplifies to True and loses the structure needed by the theorem.
      forms = application_alias_forms(target, rules)
      inner = forms[2]
      if inner != nil
        expanded = dest_binop(inner.concl, "=")[1]
        matched = mt.match_instantiated(@d, pattern, expanded)
        if matched == nil
          matched = match_application_squares(mt, pattern, expanded)
        if matched != nil
          return matched
      conv = forms[3]
      if conv == nil
        conv = Simp.new(@d, rules).finish_simp_opt(target, 0, inner)
        if conv == nil
          conv = @k.refl(target)
        forms[3] = conv
      expanded = dest_binop(conv.concl, "=")[1]
      matched = mt.match_instantiated(@d, pattern, expanded)
      return matched == nil ? match_application_squares(mt, pattern, expanded) : matched
    rescue err
      # This expansion was speculative. A later premise or conclusion can match.
      return nil

  # The same target is matched against many theorem prefixes. Only the
  # ordered rewrite rules determine its two conversions, not the matcher.
  -> application_alias_forms(target, rules)
    cache = application_conversions.aliases
    slot = target.h
    rules.each -> (rule) slot = (slot * 31 + rule.th.concl.h) % 64
    forms = cache[slot]
    if forms != nil && tm_eq(forms[0], target) && forms[1] == rules
      return forms
    forms = [target, rules, Simp.new(@d, rules).simp_definition_conv(target, true), nil]
    cache[slot] = forms
    forms

  -> application_constants(t, names)
    if t.tag == :const
      names[t.name] = true
    elsif t.tag == :app
      application_constants(t.a, names)
      application_constants(t.b, names)
    elsif t.tag == :lam
      application_constants(t.b, names)

  # Retain a record field as a projection rather than unfolding its recursor.
  # Use only closed, unconditional, kernel-only constructor equations.
  -> application_projection_rules(t)
    if !t.ty.fun?
      return []
    info = @k.inductives[t.ty.dom.name]
    candidates = @session.simp_by_head[t.name]
    if info == nil || info.ctors.size != 1 || candidates == nil
      return []
    out = []
    candidates.each -> (r)
      if r.is_eq && r.conds.size == 0 && r.th.hyps.size == 0 && r.th.tags.size == 0 && r.rhs.tag == :var
        lhs = strip_app(r.lhs)
        if lhs[0].tag == :const && lhs[0].name == t.name && lhs[1].size == 1
          ctor = strip_app(lhs[1][0])
          if ctor[0].tag == :const && ctor[0].name == info.ctors[0][0] && ctor[1].size == info.ctors[0][1].size
            fields = true
            selected = false
            ctor[1].each -> (arg)
              if arg.tag != :var
                fields = false
              if tm_eq(arg, r.rhs)
                selected = true
            if fields && selected
              out.push(r)
    out

  -> application_aliases(t, protected, seen, rules, budget)
    if budget[0] <= 0
      return 0
    if t.tag == :const
      if !protected.has_key?(t.name) && !seen.has_key?(t.name)
        seen[t.name] = true
        projections = application_projection_rules(t)
        if projections.size > 0
          budget[0] -= 1
          projections.each -> (rule) rules.push(rule)
          return 0
        definition = @k.defs[t.name]
        if definition != nil
          budget[0] -= 1
          rule_cache = application_conversions.rules
          rule = rule_cache[t.name]
          if rule == nil
            rule = make_rule(@d, definition, t.name)
            rule_cache[t.name] = rule
          rules.push(rule)
          application_aliases(dest_binop(definition.concl, "=")[1], protected, seen, rules, budget)
    elsif t.tag == :app
      application_aliases(t.a, protected, seen, rules, budget)
      application_aliases(t.b, protected, seen, rules, budget)
    elsif t.tag == :lam
      application_aliases(t.b, protected, seen, rules, budget)
    0

  -> regen(thx, gens)
    i = gens.size - 1
    while i >= 0
      thx = @k.gen(gens[i], thx)
      i -= 1
    thx

  # ---------------------------------------------------------------------------
  # Tactics

  -> tac_intro(g, args, all)
    if all
      count = 0
      while intro_able?(g.goal.concl) && count <= 64
        g = intro1(g, "_")
        count += 1
      return g
    if args.size == 0
      return intro1(g, "_")
    pats = []
    idx = 0
    while idx < args.size
      tk = args[idx].text
      if tk == "⟨" || tk == "("
        close_tk = tk == "⟨" ? "⟩" : ")"
        depth = 1
        j = idx + 1
        while j < args.size && depth > 0
          if args[j].text == tk
            depth += 1
          elsif args[j].text == close_tk
            depth -= 1
          j += 1
        pats.push(arr_sub(args, idx, j - idx))
        idx = j
      else
        pats.push([args[idx]])
        idx += 1
    leaves = [g]
    pats.each -> (pat)
      next_leaves = []
      leaves.each -> (lg)
        if pat.size == 1 && pat[0].text != "rfl"
          next_leaves.push(intro1(lg, pat[0].text))
        else
          tmp = fresh_hyp_name(lg.goal)
          lg1 = intro1(lg, tmp)
          th = @k.assume(lg1.goal.hyp(tmp))
          next_leaves = next_leaves + destruct(lg1, th, pat)
      leaves = next_leaves
    leaves.size > 0 ? leaves[0] : g

  -> intro_able?(c)
    q = dest_unop(c, "∀")
    (q != nil && q.tag == :lam) || dest_binop(c, "⇒") != nil || dest_unop(c, "¬") != nil

  -> intro1(g, nm)
    goal = g.goal
    c = goal.concl
    q = dest_unop(c, "∀")
    if q != nil && q.tag == :lam
      base = nm
      if nm == "_"
        base = q.name
        if base == nil || base == ""
          base = "x"
      vname = fresh_name(base, goal.all_terms)
      v = mk_var(vname, q.ty)
      ng = Goal.new(goal.fixes + [[base, v]], goal.hyps, tm_instantiate(q.b, v, 0))
      refs = refine(g, [ng], ->(ts) @k.gen(v, ts[0]))
      return refs[0]
    pq = dest_binop(c, "⇒")
    if pq != nil
      hn = nm
      if nm == "_"
        hn = fresh_hyp_name(goal)
      p = pq[0]
      ng = Goal.new(goal.fixes, goal.hyps + [[hn, p]], pq[1])
      refs = refine(g, [ng], ->(ts) @k.disch(p, ts[0]))
      return refs[0]
    np = dest_unop(c, "¬")
    if np != nil
      hn = nm
      if nm == "_"
        hn = fresh_hyp_name(goal)
      ng = Goal.new(goal.fixes, goal.hyps + [[hn, np]], @k.false_tm)
      refs = refine(g, [ng], ->(ts) @k.not_intro(np, ts[0]))
      return refs[0]
    conv = proof_head_conv(c, ["∀", "⇒", "¬"], 8)
    if conv != nil
      unfolded = dest_binop(conv.concl, "=")[1]
      refs = refine(g, [goal.with_concl(unfolded)], ->(ts) @k.eq_mp(@k.sym(conv), ts[0]))
      return intro1(refs[0], nm)
    fail("intro: goal is not ∀, → or ¬: " + tm_show(c))

  -> tac_apply(g, args)
    if args.size == 0
      fail("apply needs a theorem")
    e = parse_expr_toks(args)
    proj_sp = extract_projected_thm(g.goal, e)
    r = nil
    if proj_sp != nil && proj_sp[2]
      r = instantiate_to(g.goal, proj_sp[0], proj_sp[1], g.goal.concl, true)
    else
      sp = @session.elab.ast_spine(e)
      head = sp[0]
      if head.kind != :id
        fail("apply: expected a theorem name")
      th = lookup_proof(g.goal, head.s)
      if th == nil
        fail("unknown theorem '" + head.s + "'")
      r = instantiate_to(g.goal, th, sp[1], g.goal.concl, true)
    thx = r[0]
    prems = r[1]
    subs = []
    prems.each -> (p)
      subs.push(g.goal.with_concl(@d.beta_norm_term(p)))
    goalc = g.goal.concl
    just = ->(ts)
      res = thx
      i = 0
      while i < prems.size
        pt = fit_concl(ts[i], prems[i])
        res = @d.prove_hyp(pt, res)
        i += 1
      fit_concl(res, goalc)
    refine(g, subs, just)

  -> tac_assumption(g)
    th = find_assumption(g.goal)
    if th == nil
      fail("assumption: no hypothesis matches the goal")
    close(g, th)

  -> find_assumption(goal)
    c = goal.concl
    goal.hyps.each -> (h)
      if tm_eq(h[1], c)
        return @k.assume(h[1])
    if is_const?(c, "⊤")
      return @k.truth
    goal.hyps.each -> (h)
      if is_const?(h[1], "⊥")
        return @k.false_elim(@k.assume(h[1]), c)
    goal.hyps.each -> (h)
      fitted = try_square_fit(@k.assume(h[1]), c)
      if fitted != nil
        return fitted
    nil

  -> tac_rfl(g)
    c = g.goal.concl
    e = dest_binop(c, "=")
    if e == nil
      fail("rfl: goal is not an equation")
    if tm_eq(e[0], e[1])
      return close(g, @k.refl(e[0]))
    a = @k.compute(e[0])
    b = @k.compute(e[1])
    if tm_eq(dest_binop(a.concl, "=")[1], dest_binop(b.concl, "=")[1])
      return close(g, @k.trans(a, @k.sym(b)))
    fail("rfl: sides are not definitionally equal")

  -> tac_trivial(g)
    th = find_assumption(g.goal)
    if th != nil
      return close(g, th)
    begin
      return tac_rfl(g)
    rescue e
      0
    tac_decide(g)

  -> tac_constructor(g)
    goal = g.goal
    c = goal.concl
    pq = dest_binop(c, "∧")
    if pq != nil
      return refine(g, [goal.with_concl(pq[0]), goal.with_concl(pq[1])], ->(ts) @k.conj(ts[0], ts[1]))
    e = dest_binop(c, "=")
    if e != nil && type_of(e[0]).name == "bool"
      l = e[0]
      r = e[1]
      return refine(g, [goal.with_concl(@k.bin("⇒", l, r)), goal.with_concl(@k.bin("⇒", r, l))], ->(ts) @k.deduct_antisym(@d.undisch(ts[1]), @d.undisch(ts[0])))
    if is_const?(c, "⊤")
      return close(g, @k.truth)
    conv = proof_head_conv(c, ["∧", "=", "⊤"])
    if conv != nil
      sides = dest_binop(conv.concl.b, "=")
      if sides == nil || type_of(sides[0]).name == "bool"
        refs = refine(g, [goal.with_concl(conv.concl.b)], ->(ts) @k.eq_mp(@k.sym(conv), ts[0]))
        return tac_constructor(refs[0])
    fail("constructor: goal is not ∧, ↔ or True")

  -> tac_left_right(g, left)
    goal = g.goal
    pq = dest_binop(goal.concl, "∨")
    if pq == nil
      fail("left/right: goal is not a disjunction")
    if left
      refine(g, [goal.with_concl(pq[0])], ->(ts) @k.disj1(ts[0], pq[1]))
    else
      refine(g, [goal.with_concl(pq[1])], ->(ts) @k.disj2(pq[0], ts[0]))

  -> tac_use(g, args)
    goal = g.goal
    parts = split_top(args, ",")
    cur = g
    parts.each -> (p)
      gg = cur.goal
      c = gg.concl
      ex = dest_unop(c, "∃")
      if ex == nil || ex.tag != :lam
        conv = proof_head_conv(c, ["∃"])
        if conv != nil
          refs0 = refine(cur, [gg.with_concl(conv.concl.b)], ->(ts) @k.eq_mp(@k.sym(conv), ts[0]))
          cur = refs0[0]
          gg = cur.goal
          c = gg.concl
          ex = dest_unop(c, "∃")
      if ex == nil || ex.tag != :lam
        fail("use: goal is not an existential")
      w = elab_term(gg, p, ex.ty)
      body = tm_instantiate(ex.b, w, 0)
      refs = refine(cur, [gg.with_concl(body)], ->(ts) @k.exists_intro(c, w, ts[0]))
      cur = refs[0]
    # try to close trivially (skip decide on open compound/quantified goals so
    # analytic proofs do not wastefully unfold huge definitions in KEval)
    begin
      th = find_assumption(cur.goal)
      if th != nil
        close(cur, th)
      else
        closed_rfl = false
        begin
          tac_rfl(cur)
          closed_rfl = true
        rescue e_rfl
          0
        if !closed_rfl
          cc = cur.goal.concl
          if tm_frees(cc).empty? || (dest_binop(cc, "∧") == nil && dest_binop(cc, "⇒") == nil && dest_unop(cc, "∀") == nil && dest_unop(cc, "∃") == nil)
            tac_decide(cur)
    rescue e
      0
    cur

  -> tac_exfalso(g)
    c = g.goal.concl
    refine(g, [g.goal.with_concl(@k.false_tm)], ->(ts) @k.false_elim(ts[0], c))

  -> tac_by_contra(g, args)
    goal = g.goal
    c = goal.concl
    hn = "h"
    if args.size > 0
      hn = args[0].text
    nc = @k.neg_tm(c)
    # if goal is ¬p, assume p instead
    p = dest_unop(c, "¬")
    if p != nil
      ng = Goal.new(goal.fixes, goal.hyps + [[hn, p]], @k.false_tm)
      return refine(g, [ng], ->(ts) @k.not_intro(p, ts[0]))
    ng = Goal.new(goal.fixes, goal.hyps + [[hn, nc]], @k.false_tm)
    refine(g, [ng], ->(ts) classical_by_contra(c, ts[0]))

  # by_cases h : P  — two goals, with h : P and with h : ¬P (excluded middle)
  -> tac_by_cases(g, args)
    goal = g.goal
    name = "h"
    rest = args
    if args.size > 1 && args[0].kind == :id && args[1].text == ":"
      name = args[0].text
      rest = arr_sub(args, 2, args.size - 2)
    p = elab_term(goal, rest, ty_bool)
    g1 = goal.add_hyp(name, p)
    g2 = goal.add_hyp(name, @k.neg_tm(p))
    refine(g, [g1, g2], ->(ts) @k.disj_cases(@k.excluded_middle(p), ts[0], ts[1]))

  # from ¬c ⊢ ⊥ derive ⊢ c
  -> classical_by_contra(c, th)
    k = @k
    em = k.excluded_middle(c)
    yes = k.assume(c)
    no = k.false_elim(th, c)
    k.disj_cases(em, yes, no)

  -> tac_contradiction(g)
    goal = g.goal
    c = goal.concl
    goal.hyps.each -> (h)
      p = h[1]
      if is_const?(p, "⊥")
        return close(g, @k.false_elim(@k.assume(p), c))
      np = dest_unop(p, "¬")
      if np != nil
        goal.hyps.each -> (h2)
          if tm_eq(h2[1], np)
            f = @k.not_elim(@k.assume(p), @k.assume(np))
            return close(g, @k.false_elim(f, c))
        e = dest_binop(np, "=")
        if e != nil && tm_eq(e[0], e[1])
          f = @k.not_elim(@k.assume(p), @k.refl(e[0]))
          return close(g, @k.false_elim(f, c))
      # decidable false hypothesis
      begin
        r = @k.compute(p)
        if is_const?(dest_binop(r.concl, "=")[1], "⊥")
          f = @k.eq_mp(r, @k.assume(p))
          return close(g, @k.false_elim(f, c))
      rescue e
        0
    fail("contradiction: none found")

  # set x [: T] := value [with hx]. Fold exact occurrences in this branch;
  # instantiating x in its finished proof restores the original context.
  -> tac_set(g, args)
    goal = g.goal
    assign = find_top(args, ":=", 0)
    if assign < 1 || args[0].kind != :id || (assign != 1 && (assign < 3 || args[1].text != ":"))
      fail("set: expected 'name := value' or 'name : type := value'")
    name = args[0].text
    eqname = name + "_def"
    stop = find_top(args, "with", assign + 1)
    if stop < 0
      stop = args.size
    elsif stop + 2 == args.size && args[stop + 1].kind == :id
      eqname = args[stop + 1].text
    else
      fail("set: expected an equation name after 'with'")
    if stop == assign + 1
      fail("set: expected a value after ':='")
    expected = nil
    if assign > 1
      expected = @session.elab.elab_type(parse_type_toks(arr_sub(args, 2, assign - 2)))
    value = elab_term(goal, arr_sub(args, assign + 1, stop - assign - 1), expected)
    variable = mk_var(fresh_name(name, goal.all_terms + [value]), type_of(value))
    equation = @k.eq_tm(variable, value)
    hyps = goal.hyps.map -> (h) [h[0], set_occurrences(h[1], value, variable)]
    body = set_occurrences(goal.concl, value, variable)
    subgoal = Goal.new(goal.fixes + [[name, variable]], hyps + [[eqname, equation]], body)
    refine(g, [subgoal], ->(ts) @d.prove_hyp(@k.refl(value), @k.inst(ts[0], [[variable, value]])))

  # Both needle and replacement are locally closed. Bound indices in a body
  # cannot equal their free variables, including under a shadowing binder.
  -> set_occurrences(t, needle, variable)
    if tm_eq(t, needle)
      return variable
    if t.tag == :app
      a = set_occurrences(t.a, needle, variable)
      b = set_occurrences(t.b, needle, variable)
      if a != t.a || b != t.b
        return mk_app_raw(a, b)
    elsif t.tag == :lam
      b = set_occurrences(t.b, needle, variable)
      if b != t.b
        return mk_lam_raw(t.name, t.ty, b)
    t

  -> tac_have(g, args, block, line)
    goal = g.goal
    # have name : P := proof | have name : P (block) | have name := proof-expr | have : P
    name = "this"
    i = 0
    if args.size > 0 && args[0].kind == :id && args.size > 1 && (args[1].text == ":" || args[1].text == ":=")
      name = args[0].text
      i = 1
    rest = arr_sub(args, i, args.size - i)
    k = find_top(rest, ":=", 0)
    prop = nil
    proof_toks = nil
    if rest.size > 0 && rest[0].text == ":"
      if k < 0
        prop = elab_term(goal, arr_sub(rest, 1, rest.size - 1), ty_bool)
      else
        prop = elab_term(goal, arr_sub(rest, 1, k - 1), ty_bool)
        proof_toks = arr_sub(rest, k + 1, rest.size - k - 1)
    elsif rest.size > 0 && rest[0].text == ":="
      proof_toks = arr_sub(rest, 1, rest.size - 1)
    else
      fail("have: expected ':' or ':='")
    th = nil
    trailing_toks = nil
    if proof_toks != nil && proof_toks.size > 0 && proof_toks[0].text == "by"
      inline_toks = arr_sub(proof_toks, 1, proof_toks.size - 1)
      if block.size == 0
        if prop == nil
          fail("have: ':= by ...' requires a type annotation ': P'")
        parts = []
        split_top(inline_toks, ";").each -> (p)
          if p.size > 0
            parts.push(p)
        sub = Prover.new(@session)
        root = GoalRef.new(goal.with_concl(prop), nil, 0)
        sub.goals = [root]
        pi = 0
        while pi < parts.size
          sub.run_node(TacNode.new(parts[pi], [], line))
          pi += 1
          if sub.goals.size == 0
            break
        if sub.goals.size > 0
          fail("unsolved goals in subproof:\n" + sub.goals[0].goal.show(@k))
        th = root.thm
        if pi < parts.size
          trailing_toks = []
          while pi < parts.size
            if trailing_toks.size > 0
              trailing_toks.push(Tok.new(:sym, ";", line, 0))
            parts[pi].each -> (tk)
              trailing_toks.push(tk)
            pi += 1
      else
        th = run_subproof(goal, prop, by_nodes(inline_toks, block, line))
    elsif proof_toks != nil
      th = proof_expr(goal, proof_toks, prop)
      if prop != nil
        th = fit_concl(th, prop)
      else
        prop = th.concl
    else
      th = run_subproof(goal, prop, block)
    hp = th.concl
    if prop != nil
      hp = prop
    ng = goal.add_hyp(name, hp)
    refine(g, [ng], ->(ts) @d.prove_hyp(th, ts[0]))
    if trailing_toks != nil && trailing_toks.size > 0
      run_node(TacNode.new(trailing_toks, [], line))

  -> by_nodes(toks, block, line)
    nodes = []
    split_top(toks, ";").each -> (p)
      if p.size > 0
        nodes.push(TacNode.new(p, [], line))
    block.each -> (b)
      nodes.push(b)
    nodes

  -> run_subproof(goal, prop, nodes)
    sub = Prover.new(@session)
    root = GoalRef.new(goal.with_concl(prop), nil, 0)
    sub.goals = [root]
    sub.run_block(nodes)
    if sub.goals.size > 0
      fail("unsolved goals in subproof:\n" + sub.goals[0].goal.show(@k))
    root.thm

  -> tac_show(g, args)
    goal = g.goal
    p = elab_term(goal, args, ty_bool)
    c = goal.concl
    refine(g, [goal.with_concl(p)], ->(ts) fit_concl(ts[0], c))

  # obtain ⟨x, hx⟩ := proof   |  obtain h1 | h2 := proof
  -> tac_obtain(g, args)
    k = find_top(args, ":=", 0)
    if k < 0
      fail("obtain: expected 'pattern := proof'")
    pat = arr_sub(args, 0, k)
    pth = proof_expr(g.goal, arr_sub(args, k + 1, args.size - k - 1))
    destruct(g, pth, pat)

  # Destructs theorem th (whose hyps are in g's context) according to a pattern.
  -> destruct(g, th, pat)
    goal = g.goal
    if pat.size == 0
      fail("empty pattern")
    alts = split_top(pat, "|")
    if alts.size > 1 || (pat[0].text == "(" && split_top(arr_sub(pat, 1, pat.size - 2), "|").size > 1)
      inner = pat
      if pat[0].text == "("
        inner = arr_sub(pat, 1, pat.size - 2)
        alts = split_top(inner, "|")
      return destruct_or(g, th, alts)
    if pat[0].text == "⟨"
      items = split_top(arr_sub(pat, 1, pat.size - 2), ",")
      return destruct_tuple(g, th, items)
    if pat[0].text == "("
      return destruct(g, th, arr_sub(pat, 1, pat.size - 2))
    name = pat[0].text
    p = th.concl
    if name == "rfl"
      return subst_eq_thm(g, th)
    ng = goal.add_hyp(name, p)
    refine(g, [ng], ->(ts) @d.prove_hyp(th, ts[0]))

  -> destruct_or(g, th, alts)
    th = @d.beta_norm_thm(th)
    goal = g.goal
    pq = dest_binop(th.concl, "∨")
    if pq == nil
      conv = proof_head_conv(th.concl, ["∨"])
      if conv != nil
        th = @k.eq_mp(conv, th)
        pq = dest_binop(th.concl, "∨")
    if pq == nil
      fail("pattern '|' needs a disjunction, got " + tm_show(th.concl))
    first = alts[0]
    rest = nil
    if alts.size == 2
      rest = alts[1]
    else
      rest = []
      i = 1
      while i < alts.size
        if i > 1
          rest.push(Tok.new(:sym, "|", 0, 0))
        alts[i].each -> (t)
          rest.push(t)
        i += 1
    n1 = fresh_hyp_name(goal)
    n2 = fresh_hyp_name(goal)
    g1 = goal.add_hyp(n1, pq[0])
    g2 = goal.add_hyp(n2, pq[1])
    c = goal.concl
    refs = refine(g, [g1, g2], ->(ts) @k.disj_cases(th, ts[0], ts[1]))
    r1 = refs[0]
    r2 = refs[1]
    l1 = destruct(r1, @k.assume(pq[0]), first)
    l2 = destruct(r2, @k.assume(pq[1]), rest)
    l1 + l2

  # destruct returns the goals it leaves open; the rest of a ⟨…⟩ pattern continues on exactly those
  # (never on the globally first goal, which inside `a | ⟨b, c⟩` is the other branch's goal).
  -> destruct_rest(leaves, th, items)
    out = []
    i = 0
    while i < leaves.size
      out = out + destruct_tuple(leaves[i], th, items)
      i += 1
    out

  -> destruct_tuple(g, th, items)
    th = @d.beta_norm_thm(th)
    goal = g.goal
    if items.size == 1
      return destruct(g, th, items[0])
    c = th.concl
    ex = dest_unop(c, "∃")
    if ex != nil && ex.tag == :lam
      nm = items[0][0].text
      vname = fresh_name(nm, goal.all_terms + [c])
      v = mk_var(vname, ex.ty)
      body = tm_instantiate(ex.b, v, 0)
      ng = Goal.new(goal.fixes + [[nm, v]], goal.hyps, goal.concl)
      refs = refine(g, [ng], ->(ts) @k.choose(v, th, ts[0]))
      return destruct_tuple(refs[0], @k.assume(body), arr_sub(items, 1, items.size - 1))
    pq = dest_binop(c, "∧")
    if pq != nil
      a = @k.conj1(th)
      b = @k.conj2(th)
      return destruct_rest(destruct(g, a, items[0]), b, arr_sub(items, 1, items.size - 1))
    e = dest_binop(c, "=")
    if e != nil && type_of(e[0]).name == "bool"
      mp = project_proof(th, "mp")
      mpr = project_proof(th, "mpr")
      return destruct_rest(destruct(g, mp, items[0]), mpr, arr_sub(items, 1, items.size - 1))
    conv = proof_head_conv(c, ["∃", "∧", "="])
    if conv != nil
      sides = dest_binop(conv.concl.b, "=")
      if sides == nil || type_of(sides[0]).name == "bool"
        return destruct_tuple(g, @k.eq_mp(conv, th), items)
    fail("⟨...⟩ pattern needs ∃, ∧ or ↔, got " + tm_show(c))

  # h : x = t (x a fixed variable) — replace x by t everywhere.
  -> subst_eq_thm(g, th)
    th = @d.beta_norm_thm(th)
    goal = g.goal
    e = dest_binop(th.concl, "=")
    if e == nil
      fail("rfl pattern needs an equation")
    v = e[0]
    t = e[1]
    eqth = th
    if v.tag != :var
      if t.tag == :var
        v = e[1]
        t = e[0]
        eqth = @k.sym(th)
      else
        fail("rfl pattern: neither side is a variable")
    rewrite_everywhere(g, g.goal, eqth, v, t)

  -> rewrite_everywhere(g, goal, eqth, v, t)
    m = {}
    m[var_key(v)] = t
    nh = []
    goal.hyps.each -> (h)
      nh.push([h[0], tm_subst(h[1], m)])
    nf = []
    goal.fixes.each -> (f)
      if !(f[1].name == v.name && ty_eq(f[1].ty, v.ty))
        nf.push(f)
    nc = tm_subst(goal.concl, m)
    ng = Goal.new(nf, nh, nc)
    oldc = goal.concl
    oldh = goal.hyps
    just = ->(ts)
      # Transport only the substituted premises used by this proof. A fact
      # already available unchanged needs no transport, even if two original
      # hypotheses became identical after the substitution.
      res = ts[0]
      ts[0].hyps.each -> (used)
        if !oldh.any?(-> (h) tm_eq(h[1], used))
          i = 0
          while i < nh.size && !tm_eq(nh[i][1], used)
            i += 1
          if i == nh.size
            fail("substitution: unexpected branch assumption")
          h = oldh[i][1]
          transport = replace_conv(h, v, eqth)
          res = @d.prove_hyp(@k.eq_mp(transport, @k.assume(h)), res)
      conv = replace_conv_opt(oldc, v, eqth)
      conv == nil ? res : @k.eq_mp(@k.sym(conv), res)
    refine(g, [ng], just)

  -> tac_subst(g, args)
    th = proof_expr(g.goal, args)
    subst_eq_thm(g, th)

  # cases h — destruct a hypothesis; cases x — case split on an inductive variable.
  -> tac_cases(g, args)
    goal = g.goal
    wi = find_top(args, "with", 0)
    names = []
    target = args
    if wi >= 0
      target = arr_sub(args, 0, wi)
      arr_sub(args, wi + 1, args.size - wi - 1).each -> (t)
        names.push(t.text)
    if target.size == 1 && goal.hyp(target[0].text) != nil
      th = @k.assume(goal.hyp(target[0].text))
      c = th.concl
      g2 = Goal.new(goal.fixes, goal.hyps, goal.concl)
      if dest_binop(c, "∨") != nil
        n1 = "h"
        n2 = "h"
        if names.size > 0
          n1 = names[0]
        if names.size > 1
          n2 = names[1]
        return destruct_or(g, th, [[Tok.new(:id, n1, 0, 0)], [Tok.new(:id, n2, 0, 0)]])
      items = []
      if names.size == 0
        names = ["x", "h"]
      names.each -> (nm)
        items.push([Tok.new(:id, nm, 0, 0)])
      return destruct_tuple(g, th, items)
    # case split on a variable of inductive type (induction without hypotheses)
    tac_induction_impl(g, target, names, false)

  # Endpoints may be literals or small closed offsets such as 2+1. Avoid
  # evaluating arbitrary definitions just to discover whether a range is finite.
  -> interval_literal(term, fuel)
    if term.tag == :lit
      return term.val
    if fuel <= 0 || term.tag != :app
      return nil
    if term.a.op == OP_NEG
      x = interval_literal(term.b, fuel - 1)
      return x == nil ? nil : zsub(0, x)
    if term.a.tag != :app || ![OP_ADD, OP_SUB].include?(term.a.a.op)
      return nil
    a = interval_literal(term.a.b, fuel - 1)
    b = interval_literal(term.b, fuel - 1)
    if a == nil || b == nil
      return nil
    if term.a.a.op == OP_ADD
      return zadd(a, b)
    type_of(term) == TY_NAT_SINGLETON && a < b ? 0 : zsub(a, b)

  # Keep the strongest bound on each side and its original proof. Naturals
  # have an implicit lower bound of zero, which arithmetic proves at the leaf.
  -> interval_bounds(v, facts)
    low = v.ty == TY_NAT_SINGLETON ? 0 : nil
    high = nil
    lower = nil
    upper = nil
    facts.each -> (th)
      cmp = dest_cmp_rel(th.concl)
      if cmp == nil
        next
      on_left = tm_eq(cmp[1], v)
      if !on_left && !tm_eq(cmp[2], v)
        next
      n = interval_literal(on_left ? cmp[2] : cmp[1], 5)
      if n == nil
        next
      strict = cmp[0] == "<" ? 1 : 0
      if !on_left || cmp[0] == "="
        candidate = zadd(n, strict)
        if low == nil || candidate > low
          low = candidate
          lower = th
      if on_left || cmp[0] == "="
        candidate = zsub(n, strict)
        if high == nil || candidate < high
          high = candidate
          upper = th
    [low, high, lower, upper]

  # Each bisection uses excluded middle, and each singleton substitution
  # replays an equality from its two bounds. Only the mathematical integers
  # support the unit gap used to move past the midpoint.
  -> interval_branches(g, context, v, low, high, lower, upper)
    if low >= high
      facts = [lower, upper].compact()
      if low > high
        bottom = arith_prove_core(Goal.new([], [], @k.false_tm), facts)
        return close(g, @k.false_elim(bottom, g.goal.concl))
      equation = @k.eq_tm(v, mk_lit(low, v.ty))
      eq = linarith_proof(Goal.new([], [], equation), facts)
      return rewrite_everywhere(g, context, eq, v, equation.b)
    mid = zadd(low, zsub(high, low) >> 1)
    le = @k.mk_const("≤", ty_funs([v.ty, v.ty], ty_bool))
    cut = mk_apps(le, [v, mk_lit(mid, v.ty)])
    other = @k.neg_tm(cut)
    refs = refine(g, [g.goal.add_hyp("§interval", cut), g.goal.add_hyp("§interval", other)],
      ->(ts) @k.disj_cases(@k.excluded_middle(cut), ts[0], ts[1]))
    interval_branches(refs[0], context, v, low, mid, lower, @k.assume(cut))
    interval_branches(refs[1], context, v, zadd(mid, 1), high, @k.assume(other), upper)

  -> tac_interval_cases(g, args)
    v = elab_term(g.goal, args)
    if v.tag != :var || (v.ty != TY_NAT_SINGLETON && v.ty != TY_INT_SINGLETON)
      fail("interval_cases expects a natural or integer variable")
    facts = []
    g.goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), facts)
    bounds = interval_bounds(v, facts)
    if bounds[0] == nil || bounds[1] == nil
      fail("interval_cases needs finite bounds on " + v.name)
    if zsub(bounds[1], bounds[0]) >= 64
      fail("interval_cases exceeds 64 values")
    interval_branches(g, g.goal, v, bounds[0], bounds[1], bounds[2], bounds[3])

  # Try the shortest small interval late in auto. Only concrete evaluation,
  # direct facts and contradictions are tried in the branches; no recursive
  # call to auto can enumerate another variable behind the user's back.
  -> auto_interval_cases(goal, hints)
    if goal.hyps.size + hints.size > 16 || !auto_small_term?(goal.concl, [128])
      return nil
    vars = goal.fixes.select -> (fix)
      (fix[1].ty == TY_NAT_SINGLETON || fix[1].ty == TY_INT_SINGLETON) && tm_free_in?(fix[1], goal.concl)
    if vars.empty?()
      return nil
    facts = []
    goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), facts)
    hints.each -> (th) normalize_comparisons(th, facts)
    width = 8
    best = nil
    variable = nil
    vars.each -> (fix)
      bounds = interval_bounds(fix[1], facts)
      if bounds[0] != nil && bounds[1] != nil
        span = zsub(bounds[1], bounds[0])
        if span < width && bounds[0] >= -256 && bounds[1] <= 256
          best = bounds
          width = span
          variable = fix[1]
    if best == nil
      return nil
    begin
      worker = Prover.new(@session)
      context = goal
      hints.each -> (th) context = context.add_hyp("§hint", th.concl)
      root = GoalRef.new(context, nil, 0)
      worker.goals = [root]
      worker.interval_branches(root, context, variable, best[0], best[1], best[2], best[3])
      leaves = worker.goals + []
      value = best[0]
      leaves.each -> (leaf)
        begin
          worker.tac_trivial(leaf)
        rescue e
          begin
            worker.tac_contradiction(leaf)
          rescue e
            facts = worker.hyp_thms(leaf.goal)
            proof = worker.auto_arithmetic_proof(leaf.goal, facts, [1])
            if proof == nil
              proof = worker.auto_predicate_ring(leaf.goal.concl, facts)
            if proof == nil
              @open_interval_case = [goal, "  open case " + variable.name + " = " + value.to_s]
              return nil
            worker.close(leaf, proof)
        value = zadd(value, 1)
      result = worker.fit(root, root.thm)
      hints.each -> (th) result = @d.prove_hyp(th, result)
      result
    rescue e
      nil

  -> tac_induction(g, args)
    wi = find_top(args, "with", 0)
    names = []
    target = args
    if wi >= 0
      target = arr_sub(args, 0, wi)
      arr_sub(args, wi + 1, args.size - wi - 1).each -> (t)
        if t.text != "|" && t.text != "=>"
          names.push(t.text)
    tac_induction_impl(g, target, names, true)

  # Find a named binder in the leading ∀/→ telescope without changing scope.
  -> induction_intro_count(c, name)
    count = 0
    while true
      quant = dest_unop(c, "∀")
      if quant != nil && quant.tag == :lam
        count += 1
        if quant.name == name
          return count
        c = quant.b
      else
        implication = dest_binop(c, "⇒")
        if implication == nil
          return -1
        count += 1
        c = implication[1]

  -> tac_induction_impl(g, target, names, use_ih)
    if target.size != 1 || target[0].kind != :id
      fail("induction/cases expects a single variable")
    goal = g.goal
    vname = target[0].text
    v = nil
    goal.fixes.each -> (f)
      if f[0] == vname || f[1].name == vname
        v = f[1]
    if v == nil && use_ih
      count = induction_intro_count(goal.concl, vname)
      if count > 0
        while count > 0
          g = intro1(g, "_")
          count -= 1
        goal = g.goal
        v = goal.fixes[goal.fixes.size - 1][1]
    if v == nil
      fail("induction: unknown variable " + vname)
    # revert hypotheses mentioning v
    rev = []
    keep = []
    goal.hyps.each -> (h)
      if tm_free_in?(v, h[1])
        rev.push(h)
      else
        keep.push(h)
    body = goal.concl
    i = rev.size - 1
    while i >= 0
      body = @k.bin("⇒", rev[i][1], body)
      i -= 1
    pred = mk_lam(v, body)
    ind = @session.induction_thm(v.ty)
    if ind == nil
      fail("induction: no induction principle for " + ty_show(v.ty))
    # ind : ∀P. prem_1 ⇒ ... ⇒ prem_k ⇒ ∀t. P t
    th = ind
    m = {}
    q0 = dest_unop(th.concl, "∀")
    # Count constructor + IH binders per branch from the raw induction principle before instantiating P.
    ctor_ih_counts = []
    total_ctor_ih = 0
    if q0 != nil && q0.tag == :lam
      p_var = mk_var("__ind_P", q0.ty)
      raw_c = tm_instantiate(q0.b, p_var, 0)
      while dest_binop(raw_c, "⇒") != nil
        rpq = dest_binop(raw_c, "⇒")
        rc = rpq[0]
        cnt = 0
        used_tmp = {}
        tm_free_names_into(rc, used_tmp)
        while true
          rq = dest_unop(rc, "∀")
          if rq != nil && rq.tag == :lam
            fv = mk_var(fresh_name_from_set("v", used_tmp), rq.ty)
            rc = tm_instantiate(rq.b, fv, 0)
            cnt += 1
          elsif dest_binop(rc, "⇒") != nil
            rc = dest_binop(rc, "⇒")[1]
            cnt += 1
          else
            break
        ctor_ih_counts.push(cnt)
        total_ctor_ih += cnt
        raw_c = rpq[1]
    ty_match(q0.ty.dom, v.ty, m)
    if m.size > 0
      th = @k.inst_type(th, m)
    th = @k.spec(pred, th)
    th = @d.beta_norm_thm(th)
    prems = []
    c = th.concl
    while dest_binop(c, "⇒") != nil
      pq = dest_binop(c, "⇒")
      prems.push(pq[0])
      c = pq[1]
    fixes2 = []
    goal.fixes.each -> (f)
      if !(f[1].name == v.name && ty_eq(f[1].ty, v.ty))
        fixes2.push(f)
    base_goal = Goal.new(fixes2, keep, @k.truth_tm)
    subs = []
    prems.each -> (p)
      subs.push(base_goal.with_concl(p))
    vv = v
    revp = rev
    just = ->(ts)
      r = th
      ts.each -> (t)
        r = @k.mp(r, t)
      r = @k.spec(vv, r)
      r = @d.beta_norm_thm(r)
      revp.each -> (h)
        r = @k.mp(r, @k.assume(h[1]))
      r
    refs = refine(g, subs, just)
    # introduce constructor arguments and induction hypotheses with the given names
    preserve_rev_names = revp.size > 0 && ctor_ih_counts.size == refs.size && names.size <= total_ctor_ih
    ni = 0
    bi = 0
    refs.each -> (rf)
      cur = rf
      if preserve_rev_names
        limit = ctor_ih_counts[bi]
        step_i = 0
        while step_i < limit && intro_able?(cur.goal.concl)
          nm = "_"
          if ni < names.size
            nm = names[ni]
            ni += 1
          cur = intro1(cur, nm)
          step_i += 1
        revp.each -> (h)
          if dest_binop(cur.goal.concl, "⇒") != nil
            cur = intro1(cur, h[0])
      else
        while intro_able?(cur.goal.concl)
          nm = "_"
          if ni < names.size
            nm = names[ni]
            ni += 1
          cur = intro1(cur, nm)
        revp.each -> (h)
          if dest_binop(cur.goal.concl, "⇒") != nil
            cur = intro1(cur, h[0])
      bi += 1
    0

  # rw [h1, ← h2, foo a] (at h | at *)?
  -> tac_rw(g, args)
    at = find_top(args, "at", 0)
    targets = [nil]
    everywhere = false
    rs = args
    if at >= 0
      # `rw [...] at h1 h2 ⊢` rewrites every listed hypothesis (and the goal for ⊢); `at *` rewrites all
      targets = []
      if at + 2 == args.size && args[at + 1].text == "*"
        everywhere = true
      else
        k = at + 1
        while k < args.size
          if args[k].text == "⊢"
            targets.push(nil)
          else
            targets.push(args[k].text)
          k += 1
      rs = arr_sub(args, 0, at)
    if rs.size > 0 && rs[0].text == "\["
      rs = arr_sub(rs, 1, rs.size - 2)
    cur = g
    if everywhere
      split_top(rs, ",").each -> (r)
        rtoks = r
        rev = false
        if rtoks.size > 0 && (rtoks[0].text == "←" || rtoks[0].text == "<-")
          rev = true
          rtoks = arr_sub(rtoks, 1, rtoks.size - 1)
        self_hyp = (rtoks.size == 1 && cur.goal.hyp(rtoks[0].text) != nil) ? rtoks[0].text : nil
        by_asts = []
        base_goal = cur.goal
        th = rule_theorem(base_goal, rtoks, by_asts)
        if rev
          th = sym_rule(th)
        rule = make_rule(@d, th, "rw")
        any_hit = false
        hs = []
        cur.goal.hyps.each -> (h)
          if h[0] != self_hyp
            hs.push(h[0])
        hs.push(nil)
        hs.each -> (th_name)
          term = th_name == nil ? cur.goal.concl : hyp_or_fail(cur.goal, th_name)
          eqth = rewrite_once(rule, term, cur.goal, by_asts)
          if eqth != nil
            any_hit = true
            rhs = dest_binop(eqth.concl, "=")[1]
            if th_name == nil
              cur = refine(cur, [cur.goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))[0]
            else
              old = hyp_or_fail(cur.goal, th_name)
              ng = cur.goal.without_hyp(th_name).add_hyp(th_name, rhs)
              cur = refine(cur, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))[0]
        if !any_hit
          fail("rw: pattern " + tm_show(rule.lhs) + " not found")
    else
      targets.each -> (target_h)
        split_top(rs, ",").each -> (r)
          cur = rw_one(cur, r, target_h)
    # close goals of the form a = a or True
    begin
      c = cur.goal.concl
      e = dest_binop(c, "=")
      if (e != nil && tm_eq(e[0], e[1])) || is_const?(c, "⊤")
        tac_trivial(cur)
      elsif e != nil
        th = try_eta_fit(@k.refl(e[0]), c)
        if th != nil
          close(cur, th)
    rescue e
      0
    cur

  -> rw_one(g, rtoks, target_h)
    goal = g.goal
    rev = false
    if rtoks[0].text == "←" || rtoks[0].text == "<-"
      rev = true
      rtoks = arr_sub(rtoks, 1, rtoks.size - 1)
    by_asts = []
    th = rule_theorem(goal, rtoks, by_asts)
    if rev
      th = sym_rule(th)
    rule = make_rule(@d, th, "rw")
    term = goal.concl
    if target_h != nil
      term = hyp_or_fail(goal, target_h)
    eqth = rewrite_once(rule, term, goal, by_asts)
    if eqth == nil
      fail("rw: pattern " + tm_show(rule.lhs) + " not found")
    rhs = dest_binop(eqth.concl, "=")[1]
    if target_h == nil
      refine(g, [goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))[0]
    else
      old = hyp_or_fail(goal, target_h)
      ng = goal.without_hyp(target_h).add_hyp(target_h, rhs)
      refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))[0]

  -> rule_theorem(goal, toks, deferred_rw_by = nil)
    e = parse_expr_toks(toks)
    if e.kind == :id
      th = lookup_proof(goal, e.s)
      if th == nil
        fail("unknown rule '" + e.s + "'")
      return th
    proj_sp = extract_projected_thm(goal, e)
    if proj_sp != nil && proj_sp[2]
      return instantiate_to(goal, proj_sp[0], proj_sp[1], nil, true, [], false, deferred_rw_by)[0]
    hd = @session.elab.ast_spine(e)[0]
    if hd.kind != :id
      return proof_ast(goal, e, nil)
    base = lookup_proof(goal, hd.s)
    if base == nil
      fail("unknown rule '" + hd.s + "'")
    r = instantiate_to(goal, base, @session.elab.ast_spine(e)[1], nil, true, [], false, deferred_rw_by)
    r[0]

  -> sym_rule(th)
    # ∀xs. c → l = r  ~>  ∀xs. c → r = l
    t = @d.spec_all(th)
    vars = tm_frees(t.concl)
    c = t.concl
    conds = []
    while dest_binop(c, "⇒") != nil
      pq = dest_binop(c, "⇒")
      conds.push(pq[0])
      c = pq[1]
    u = t
    conds.each -> (p)
      u = @k.mp(u, @k.assume(p))
    if dest_binop(u.concl, "=") == nil
      fail("← needs an equation")
    u = @k.sym(u)
    i = conds.size - 1
    while i >= 0
      u = @k.disch(conds[i], u)
      i -= 1
    gen_free(u, t, th)

  -> gen_free(u, t, th)
    out = u
    fv = []
    # variables already free in the original rule (an instantiation such as `← sqa b`) stay fixed
    pre = {}
    tm_frees(th.concl).each -> (v)
      pre[var_key(v)] = true
    tm_frees(u.concl).each -> (v)
      inhyp = false
      u.hyps.each -> (h)
        if tm_free_in?(v, h)
          inhyp = true
      if !inhyp && !pre.has_key?(var_key(v))
        fv.push(v)
    i = fv.size - 1
    while i >= 0
      out = @k.gen(fv[i], out)
      i -= 1
    out

  -> attach_rw_by_tactics(rule, goal, by_asts)
    if by_asts == nil || by_asts.size == 0
      rule.cond_tactics = nil
      return
    prover = self
    tacs = Array.new(by_asts.size)
    i = 0
    while i < by_asts.size
      ba = by_asts[i]
      if ba != nil
        tacs[i] = ->(cond_tm)
          res_th = nil
          begin
            res_th = prover.proof_ast(goal, ba, cond_tm)
          rescue _e
            res_th = nil
          res_th
      i += 1
    rule.cond_tactics = tacs

  # Rewrites all occurrences of the first instance of the rule found in term
  # (including beneath λ/∀/∃/∑ binders using @k.abs_rule).
  -> rewrite_once(rule, term, goal, by_asts = nil)
    s = Simp.new(@d, [rule])
    s.hyp_rules = hyp_thms(goal)
    s.infer_conditions = true
    attach_rw_by_tactics(rule, goal, by_asts)
    inst = find_instance_with_simp(s, rule, term)
    if inst != nil
      lhs = dest_binop(inst.concl, "=")[0]
      conv = replace_conv_opt(term, lhs, inst)
      if conv == nil
        return @k.refl(term)
      return conv
    if (term.search_ops & TERM_LAMBDA) != 0
      avoid = [term, rule.th.concl] + rule.th.hyps + goal.all_terms
      return rewrite_under_binders_opt(rule, term, goal, by_asts, avoid)
    nil

  -> rewrite_under_binders_opt(rule, t, goal, by_asts, avoid)
    case t.tag
    when :app
      if (t.a.search_ops & TERM_LAMBDA) != 0
        a = rewrite_under_binders_opt(rule, t.a, goal, by_asts, avoid)
        if a != nil
          return @k.mk_comb(a, @k.refl(t.b))
      if (t.b.search_ops & TERM_LAMBDA) != 0
        b = rewrite_under_binders_opt(rule, t.b, goal, by_asts, avoid)
        if b != nil
          return @k.mk_comb(@k.refl(t.a), b)
      nil
    when :lam
      p = dest_lam_fresh(t, avoid)
      v = p[0]
      body = p[1]
      sub_goal = goal.add_fix(v.name, v)
      inner = rewrite_once(rule, body, sub_goal, by_asts)
      if inner == nil
        return nil
      bad = false
      inner.hyps.each -> (h)
        if tm_free_in?(v, h)
          bad = true
      if bad
        return nil
      return @k.abs_rule(v, inner)
    nil

  -> find_instance_with_simp(s, rule, t)
    # Search beneath binders too, but never instantiate a rule with a loose
    # de Bruijn index. Closed subterms there (such as a free variable) are safe.
    if tm_closed_bound?(t)
      th = s.apply_rule(rule, t, 0)
      if th != nil
        return th
    case t.tag
    when :app
      r = find_instance_with_simp(s, rule, t.a)
      if r != nil
        return r
      return find_instance_with_simp(s, rule, t.b)
    when :lam
      return find_instance_with_simp(s, rule, t.b)
    nil

  # Returns nil when lhs does not occur in t, else ⊢ t = t[rhs/lhs].
  -> replace_conv_opt(t, lhs, eqth)
    if tm_eq(t, lhs)
      return eqth
    case t.tag
    when :app
      a = replace_conv_opt(t.a, lhs, eqth)
      b = replace_conv_opt(t.b, lhs, eqth)
      if a == nil && b == nil
        return nil
      ath = a == nil ? @k.refl(t.a) : a
      bth = b == nil ? @k.refl(t.b) : b
      return @k.mk_comb(ath, bth)
    when :lam
      p = dest_lam_fresh(t, [t, eqth.concl] + eqth.hyps)
      inner = replace_conv_opt(p[1], lhs, eqth)
      if inner == nil
        return nil
      bad = false
      inner.hyps.each -> (h)
        if tm_free_in?(p[0], h)
          bad = true
      if bad
        return nil
      return @k.abs_rule(p[0], inner)
    nil

  -> replace_conv(t, lhs, eqth)
    conv = replace_conv_opt(t, lhs, eqth)
    if conv == nil
      return @k.refl(t)
    conv

  -> hyp_thms(goal)
    out = Array.new(goal.hyps.size)
    i = 0
    while i < goal.hyps.size
      out[i] = @k.assume(goal.hyps[i][1])
      i += 1
    out

  -> named_equation(eqth, name)
    rule = make_rule(@d, eqth, name)
    rule.literal_patterns = true
    rule

  -> simp_extra_rules_from(goal, toks)
    rules = []
    if toks.size > 0
      inner = toks
      if inner[0].text == "\["
        inner = arr_sub(inner, 1, inner.size - 2)
      split_top(inner, ",").each -> (r)
        if r.size > 0
          if r[0].text == "*"
            goal.hyps.each -> (h)
              rules.push(make_rule(@d, @k.assume(h[1]), h[0]))
          else
            rev = false
            if r[0].text == "←"
              rev = true
              r = arr_sub(r, 1, r.size - 1)
            nm = r[0].text
            if r.size == 1 && @session.k.defs.has_key?(nm)
              rules.push(make_rule(@d, @session.k.defs[nm], nm, false))
              @session.eqns_of(nm).each -> (eqth)
                rules.push(named_equation(eqth, nm))
            else
              by_asts = []
              th = rule_theorem(goal, r, by_asts)
              if rev
                th = sym_rule(th)
              rl = make_rule(@d, th, nm)
              attach_rw_by_tactics(rl, goal, by_asts)
              rules.push(rl)
    rules

  -> goal_simplifier(goal, rs, all = false)
    only = false
    if rs.size > 0 && rs[0].text == "only"
      only = true
      rs = arr_sub(rs, 1, rs.size - 1)
    rules = simp_extra_rules_from(goal, rs)
    if all
      goal.hyps.each -> (h)
        rules.push(make_rule(@d, @k.assume(h[1]), h[0]))
    s = only ? Simp.new(@d, rules) : Simp.new(@d, rules, @session.simp_by_head, @session.simp_general)
    s.hyp_rules = hyp_thms(goal)
    prover = self
    s.discharger = ->(c) prover.try_arith_discharge(goal, c)
    s

  -> tac_simpa(g, args)
    goal = g.goal
    using = find_top(args, "using", 0)
    rs = using < 0 ? args : arr_sub(args, 0, using)
    if find_top(rs, "at", 0) >= 0
      fail("simpa closes the goal; use simp for hypothesis locations")
    th = nil
    if using >= 0
      if using + 1 == args.size
        fail("simpa: expected a proof after 'using'")
      # Check the supplied proof even when simplification could close the goal alone.
      th = proof_expr(goal, arr_sub(args, using + 1, args.size - using - 1))
    s = goal_simplifier(goal, rs)
    goal_eq = s.simp_conv(goal.concl, 0)
    target = dest_binop(goal_eq.concl, "=")[1]
    if th != nil
      source_eq = goal_simplifier(goal, rs).simp_conv(th.concl, 0)
      th = @k.eq_mp(source_eq, th)
      th = instantiate_to(goal, th, [], target, false)[0]
      th = fit_concl(th, target)
    elsif target.op == OP_TRUE
      th = @k.truth
    else
      th = find_assumption(goal.with_concl(target))
      if th == nil
        fail("simpa did not close the goal: " + tm_show(target))
    close(g, fit(g, @k.eq_mp(@k.sym(goal_eq), th)))

  -> tac_simp(g, args, all)
    goal = g.goal
    at = find_top(args, "at", 0)
    rs = args
    targets = [nil]
    everywhere = false
    if at >= 0
      rs = arr_sub(args, 0, at)
      locations = arr_sub(args, at + 1, args.size - at - 1)
      if locations.size == 0
        fail("simp: expected a location after 'at'")
      targets = []
      if locations.any?(-> (t) t.text == "*")
        if locations.size != 1
          fail("simp: '*' already selects every hypothesis and the goal")
        everywhere = true
        goal.hyps.each -> (h) targets.push(h[0])
        targets.push(nil)
      else
        locations.each -> (t)
          if t.text == "⊢"
            targets.push(nil)
          else
            hyp_or_fail(goal, t.text)
            targets.push(t.text)
    # Resolve rules before rewriting hypotheses that may supply those rules.
    s = goal_simplifier(goal, rs, all)
    cur = g
    targets.each -> (target)
      r = simp_at_goal(cur, s, target, everywhere)
      if r.size == 0 || r[0].thm != nil
        return []
      cur = r[0]
    [cur]

  -> simp_at_goal(g, s, target_h = nil, allow_unchanged = false)
    goal = g.goal
    if target_h != nil
      old = hyp_or_fail(goal, target_h)
      if is_const?(old, "⊥")
        return close(g, @k.false_elim(@k.assume(old), goal.concl))
      eqth = s.simp_conv_opt(old, 0)
      if eqth == nil
        return [g]
      newp = dest_binop(eqth.concl, "=")[1]
      if newp.op == OP_FALSE
        f = @k.eq_mp(eqth, @k.assume(old))
        return close(g, @k.false_elim(f, goal.concl))
      ng = goal.without_hyp(target_h).add_hyp(target_h, newp)
      return refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))
    eqth = s.simp_conv_opt(goal.concl, 0)
    if eqth == nil
      th = find_assumption(goal)
      if th != nil
        return close(g, th)
      if allow_unchanged
        return [g]
      fail("simp made no progress")
    rhs = dest_binop(eqth.concl, "=")[1]
    if rhs.op == OP_TRUE
      return close(g, @d.eqt_elim(eqth))
    if tm_eq(rhs, goal.concl)
      th = find_assumption(goal)
      if th != nil
        return close(g, th)
      if allow_unchanged
        return [g]
      fail("simp made no progress")
    ng = goal.with_concl(rhs)
    refs = refine(g, [ng], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))
    th = find_assumption(ng)
    if th != nil
      close(refs[0], th)
    refs

  -> hyp_or_fail(goal, name)
    h = goal.hyp(name)
    if h == nil
      fail("unknown hypothesis " + name)
    h

  -> try_arith_discharge(goal, c)
    begin
      sub = Prover.new(@session)
      root = GoalRef.new(goal.with_concl(c), nil, 0)
      sub.goals = [root]
      sub.tac_linarith(root, [], false)
      return root.thm
    rescue e
      return nil

  -> tac_unfold(g, args)
    at = find_top(args, "at", 0)
    if at >= 0 && args.size - at - 1 == 1 && args[at + 1].text == "⊢"
      return tac_unfold(g, arr_sub(args, 0, at))
    target_h = nil
    everywhere = false
    names = args
    if at >= 0
      if args.size - at - 1 == 1 && args[at + 1].text == "*"
        everywhere = true
        names = arr_sub(args, 0, at)
      elsif args.size - at - 1 > 1
        # `unfold f at h1 h2` unfolds in each listed hypothesis
        cur = g
        k = at + 1
        while k < args.size
          if args[k].text == "⊢"
            cur = tac_unfold(cur, arr_sub(args, 0, at))[0]
          else
            cur = tac_unfold(cur, arr_sub(args, 0, at + 1) + [args[k]])[0]
          k += 1
        return [cur]
      else
        target_h = args[at + 1].text
        names = arr_sub(args, 0, at)
    rules = []
    names.each -> (t)
      nm = t.text
      eqs = @session.eqns_of(nm)
      if eqs.size > 0
        eqs.each -> (e)
          rules.push(named_equation(e, nm))
      # Applied equations do not match a bare function passed as an argument.
      # Its defining equality also unfolds that higher-order occurrence.
      if @k.defs.has_key?(nm)
        rules.push(make_rule(@d, @k.defs[nm], nm, false))
      elsif eqs.size == 0
        fail("unfold: " + nm + " is not a definition")
    s = Simp.new(@d, rules)
    if everywhere
      cur = g
      hs = []
      cur.goal.hyps.each -> (h) hs.push(h[0])
      hs.each -> (hn)
        old = hyp_or_fail(cur.goal, hn)
        eqth = s.simp_conv_opt(old, 0)
        if eqth != nil
          newp = dest_binop(eqth.concl, "=")[1]
          ng = cur.goal.without_hyp(hn).add_hyp(hn, newp)
          cur = refine(cur, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))[0]
      eqth = s.simp_conv_opt(cur.goal.concl, 0)
      if eqth != nil
        rhs = dest_binop(eqth.concl, "=")[1]
        cur = refine(cur, [cur.goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))[0]
      return [cur]
    goal = g.goal
    if target_h != nil
      old = hyp_or_fail(goal, target_h)
      eqth = s.simp_conv(old, 0)
      newp = dest_binop(eqth.concl, "=")[1]
      ng = goal.without_hyp(target_h).add_hyp(target_h, newp)
      return refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))
    eqth = s.simp_conv(goal.concl, 0)
    rhs = dest_binop(eqth.concl, "=")[1]
    refine(g, [goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))

  -> tac_decide(g)
    c = g.goal.concl
    th = @k.compute(c)
    r = dest_binop(th.concl, "=")[1]
    if !is_const?(r, "⊤")
      fail("decide: proposition evaluates to " + tm_show(r))
    close(g, @d.eqt_elim(th))

  # norm_num: closed numerals by evaluation; otherwise a ring identity, then linear
  # arithmetic, and finally simp (which may leave a simplified goal)
  -> tac_norm_num(g, args)
    begin
      return tac_decide(g)
    rescue e
      0
    if dest_binop(g.goal.concl, "=") != nil || dest_binop(g.goal.concl, "∧") != nil
      begin
        return tac_ring(g)
      rescue e2
        0
    begin
      return tac_linarith(g, [])
    rescue e3
      0
    tac_simp(g, args, false)

  -> tac_ring(g)
    c = @d.beta_eta_term(g.goal.concl)
    proof = prove_conjuncts(c, -> (leaf) ring_equality_proof(leaf))
    close(g, fit_concl(proof, g.goal.concl))

  # Each leaf gets the same context. Build the original conjunction only
  # after both proofs return, so a failure cannot partly close the goal.
  -> prove_conjuncts(c, prove, conjunct = false)
    parts = dest_binop(c, "∧")
    if parts != nil
      return @k.conj(prove_conjuncts(parts[0], prove, true), prove_conjuncts(parts[1], prove, true))
    begin
      return prove.call(c)
    rescue e
      if conjunct
        fail(e.to_s + "\n  failed conjunct " + tm_show(c))
      raise e

  -> ring_equality_proof(c)
    e = dest_binop(c, "=")
    if e == nil
      fail("ring: goal is not an equation")
    if type_of(e[0]).fun?
      if tm_eq(e[0], e[1])
        return @k.refl(e[0])
      v = mk_var(fresh_name("x", e), type_of(e[0]).dom)
      at_v = @d.beta_eta_term(@k.eq_tm(mk_app(e[0], v), mk_app(e[1], v)))
      return funext_proof(e[0], e[1], v, ring_equality_proof(at_v))
    lhs_ty = type_of(e[0])
    if lhs_ty.tag == :c && lhs_ty.name == "complex"
      if tm_eq(e[0], e[1])
        return @k.refl(e[0])
      ext_th = @session.theorem("complex.ext")
      if ext_th != nil
        return complex_ring_equality_proof(e[0], e[1], lhs_ty, ext_th)
    begin
      return @k.ring_eq(e[0], e[1])
    rescue original
      congruent = ring_congruence(e[0], e[1], [192], false)
      if congruent != nil
        return congruent
      # Try checked defining equations only after ordinary ring normalization.
      # Normalize the two sides separately so the final polynomial check and
      # its trust tag remain the same as an explicit unfold followed by ring.
      begin
        rules = auto_relation_definitions([c])
        simplifier = Simp.new(@d, rules)
        simplifier.step_limit = 4096
        left = simplifier.simp_definition_conv(e[0])
        right = simplifier.simp_definition_conv(e[1])
        lhs = dest_binop(left.concl, "=")[1]
        rhs = dest_binop(right.concl, "=")[1]
        if (!tm_eq(lhs, e[0]) || !tm_eq(rhs, e[1])) && auto_small_term?(lhs, [8192]) && auto_small_term?(rhs, [8192])
          begin
            middle = @k.ring_eq(lhs, rhs)
          rescue not_polynomial
            middle = ring_congruence(lhs, rhs, [192], false)
          if middle != nil
            return @k.trans(left, @k.trans(middle, @k.sym(right)))
      rescue e2
        0
      fail(original.to_s)

  -> complex_ring_proj_proof(proj_fn, lhs, rhs)
    pl = mk_app(proj_fn, lhs)
    pr = mk_app(proj_fn, rhs)
    s = Simp.new(@d, [], @session.simp_by_head, @session.simp_general)
    s.step_limit = 4096
    leq = s.simp_conv(pl, 0)
    req = s.simp_conv(pr, 0)
    l1 = dest_binop(leq.concl, "=")[1]
    r1 = dest_binop(req.concl, "=")[1]
    mid = nil
    begin
      mid = @k.ring_eq(l1, r1)
    rescue err1
      mid = ring_congruence(l1, r1, [192], false)
    if mid == nil
      defs = auto_relation_definitions([lhs, rhs, l1, r1])
      s2 = Simp.new(@d, defs, @session.simp_by_head, @session.simp_general)
      s2.step_limit = 4096
      leq2 = s2.simp_conv(l1, 0)
      req2 = s2.simp_conv(r1, 0)
      l2 = dest_binop(leq2.concl, "=")[1]
      r2 = dest_binop(req2.concl, "=")[1]
      leq = @k.trans(leq, leq2)
      req = @k.trans(req, req2)
      mid = ring_equality_proof(@k.eq_tm(l2, r2))
    @k.trans(leq, @k.trans(mid, @k.sym(req)))

  -> complex_ring_equality_proof(lhs, rhs, cx_ty, ext_th)
    re_fn = @k.mk_const("complex.re", ty_fun(cx_ty, ty_real))
    im_fn = @k.mk_const("complex.im", ty_fun(cx_ty, ty_real))
    re_prf = complex_ring_proj_proof(re_fn, lhs, rhs)
    im_prf = complex_ring_proj_proof(im_fn, lhs, rhs)
    @k.mp(@k.mp(@k.spec(rhs, @k.spec(lhs, ext_th)), re_prf), im_prf)

  -> field_has_div?(tm, ty)
    if tm.tag != :app
      return false
    if !ty_eq(type_of(tm), ty)
      return false
    if tm.a.tag == :const && tm.a.op == OP_NEG
      return field_has_div?(tm.b, ty)
    if tm.a.tag == :app && tm.a.a.tag == :const
      op = tm.a.a.op
      if op == OP_DIV
        return true
      if op == OP_ADD || op == OP_SUB || op == OP_MUL
        return field_has_div?(tm.a.b, ty) || field_has_div?(tm.b, ty)
    false

  -> field_extract_nat_cast(tm)
    t = tm
    if t.tag == :app && t.a.tag == :const && t.a.name == "real_of_rat"
      t = t.b
    if t.tag == :app && t.a.tag == :const && t.a.name == "rat_of_int"
      t = t.b
    if t.tag == :app && t.a.tag == :const && t.a.name == "int_of_nat"
      return t.b
    nil

  -> field_prove_pos(goal, hints, tm, ty, sfx, depth = 0)
    if depth > 8
      return nil
    zero = mk_lit(Q_ZERO, ty)
    lt_c = @k.mk_const("<", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    want = mk_apps(lt_c, [zero, tm])
    if tm.tag == :app && tm.a.tag == :app && tm.a.a.tag == :const
      op = tm.a.a.op
      if op == OP_MUL
        pa = field_prove_pos(goal, hints, tm.a.b, ty, sfx, depth + 1)
        if pa != nil
          pb = field_prove_pos(goal, hints, tm.b, ty, sfx, depth + 1)
          if pb != nil
            mp_lem = @session.theorem("mul_pos" + sfx)
            if mp_lem != nil
              return @k.mp(@k.mp(@k.spec(tm.b, @k.spec(tm.a.b, mp_lem)), pa), pb)
      elsif op == OP_DIV
        pa = field_prove_pos(goal, hints, tm.a.b, ty, sfx, depth + 1)
        if pa != nil
          pb = field_prove_pos(goal, hints, tm.b, ty, sfx, depth + 1)
          if pb != nil
            dp_lem = @session.theorem("div_pos" + sfx)
            if dp_lem != nil
              return @k.mp(@k.mp(@k.spec(tm.b, @k.spec(tm.a.b, dp_lem)), pa), pb)
      elsif op == OP_POW && ty_eq(type_of(tm.b), TY_NAT_SINGLETON)
        pa = field_prove_pos(goal, hints, tm.a.b, ty, sfx, depth + 1)
        if pa != nil
          pp_lem = @session.theorem("pow_pos" + sfx)
          if pp_lem != nil
            return @k.mp(@k.spec(tm.b, @k.spec(tm.a.b, pp_lem)), pa)
    if ty_eq(ty, ty_real)
      sp = strip_app(tm)
      if sp[0].tag == :const
        if sp[0].name == "exp" && sp[1].size == 1 && @session.theorem("exp_pos") != nil
          return @k.spec(sp[1][0], @session.theorem("exp_pos"))
        if sp[0].name == "rpow" && sp[1].size == 2 && @session.theorem("rpow.pos") != nil
          return @k.spec(sp[1][1], @k.spec(sp[1][0], @session.theorem("rpow.pos")))
    nat_arg = field_extract_nat_cast(tm)
    if nat_arg != nil
      nsp = strip_app(nat_arg)
      if ty_eq(ty, ty_real) && nsp[0].tag == :const && nsp[0].name == "fact" && nsp[1].size == 1 && @session.theorem("fact_cast_pos") != nil
        return @k.spec(nsp[1][0], @session.theorem("fact_cast_pos"))
      cp_lem = @session.theorem("cast_pos" + sfx)
      if cp_lem != nil
        lt_nat = @k.mk_const("<", ty_funs([TY_NAT_SINGLETON, TY_NAT_SINGLETON], TY_BOOL_SINGLETON))
        saved_om = @omega_mode
        @omega_mode = true
        pnat = nil
        begin
          pnat = arith_prove(goal.with_concl(mk_apps(lt_nat, [mk_lit(0, TY_NAT_SINGLETON), nat_arg])), hints)
        rescue err_om
          pnat = nil
        @omega_mode = saved_om
        if pnat != nil
          return @k.eq_mp(@k.sym(@k.spec(nat_arg, cp_lem)), pnat)
    extra = [] + hints
    pos_facts(tm, extra, {})
    saved_nl = @nl_mode
    @nl_mode = true
    res = nil
    begin
      res = arith_prove(goal.with_concl(want), extra)
    rescue err_pos
      res = nil
    @nl_mode = saved_nl
    res

  -> field_prove_nonzero(goal, hints, tm, ty, sfx, depth = 0)
    if depth > 8
      fail("field_simp: could not prove denominator nonzero: " + tm_show(tm))
    zero = mk_lit(Q_ZERO, ty)
    if tm.tag == :app && tm.a.tag == :app && tm.a.a.tag == :const
      op = tm.a.a.op
      if op == OP_MUL
        mnz = @session.theorem("mul_ne_zero" + sfx)
        if mnz != nil
          begin
            na = field_prove_nonzero(goal, hints, tm.a.b, ty, sfx, depth + 1)
            nb = field_prove_nonzero(goal, hints, tm.b, ty, sfx, depth + 1)
            return @k.mp(@k.mp(@k.spec(tm.b, @k.spec(tm.a.b, mnz)), na), nb)
          rescue err_m
            0
      elsif op == OP_DIV
        dei = @session.theorem("div_eq_iff" + sfx)
        if dei != nil
          begin
            na = field_prove_nonzero(goal, hints, tm.a.b, ty, sfx, depth + 1)
            nb = field_prove_nonzero(goal, hints, tm.b, ty, sfx, depth + 1)
            mul_c = @k.mk_const("*", ty_funs([ty, ty], ty))
            h0 = @k.eq_tm(tm, zero)
            iff0 = @k.mp(@k.spec(tm.b, @k.spec(zero, @k.spec(tm.a.b, dei))), nb)
            a_eq = @k.trans(@k.eq_mp(iff0, @k.assume(h0)), @k.ring_eq(mk_apps(mul_c, [zero, tm.b]), zero))
            return @k.not_intro(h0, @k.not_elim(na, a_eq))
          rescue err_d
            0
      elsif op == OP_POW && ty_eq(type_of(tm.b), TY_NAT_SINGLETON)
        pez = @session.theorem("pow_eq_zero" + sfx)
        if pez != nil
          begin
            na = field_prove_nonzero(goal, hints, tm.a.b, ty, sfx, depth + 1)
            h0 = @k.eq_tm(tm, zero)
            a0 = @k.mp(@k.spec(tm.b, @k.spec(tm.a.b, pez)), @k.assume(h0))
            return @k.not_intro(h0, @k.not_elim(na, a0))
          rescue err_p
            0
    p = field_prove_pos(goal, hints, tm, ty, sfx, depth)
    if p != nil
      return arith_prove(Goal.new([], [], @k.neg_tm(@k.eq_tm(tm, zero))), [p])
    extra = [] + hints
    pos_facts(tm, extra, {})
    saved_nl = @nl_mode
    @nl_mode = true
    res = nil
    begin
      res = arith_prove(goal.with_concl(@k.neg_tm(@k.eq_tm(tm, zero))), extra)
    rescue err_nz
      @nl_mode = saved_nl
      fail("field_simp: could not prove denominator nonzero: " + tm_show(tm))
    @nl_mode = saved_nl
    res

  # Prove (a / b) * c = (a * c) / b using div_def and ring_eq.
  -> field_shift_div_mul(a, b, c, ty, div_def)
    mul_c = @k.mk_const("*", ty_funs([ty, ty], ty))
    ac = mk_apps(mul_c, [a, c])
    e1 = @k.spec(b, @k.spec(a, div_def))
    e2 = @k.spec(b, @k.spec(ac, div_def))
    lhs_step = combination_binop("*", ty, e1, @k.refl(c))
    mid = @k.ring_eq(dest_binop(lhs_step.concl, "=")[1], dest_binop(e2.concl, "=")[1])
    @k.trans(lhs_step, @k.trans(mid, @k.sym(e2)))

  # Build prop equality: ⊢ (n_l / d_l = n_r / d_r) = (n_l * d_r = n_r * d_l)
  -> field_frac_eq_iff(n_l, d_l, ne_l, n_r, d_r, ne_r, ty, div_def, div_eq_iff, eq_div_iff)
    div_c = @k.mk_const("/", ty_funs([ty, ty], ty))
    mul_c = @k.mk_const("*", ty_funs([ty, ty], ty))
    eq_c = @k.mk_const("=", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    rhs_frac = mk_apps(div_c, [n_r, d_r])
    iff1 = @k.mp(@k.spec(d_l, @k.spec(rhs_frac, @k.spec(n_l, div_eq_iff))), ne_l)
    sh = field_shift_div_mul(n_r, d_r, d_l, ty, div_def)
    iff2 = @d.ap_term(mk_app(eq_c, n_l), sh)
    iff3 = @k.mp(@k.spec(d_r, @k.spec(mk_apps(mul_c, [n_r, d_l]), @k.spec(n_l, eq_div_iff))), ne_r)
    @k.trans(iff1, @k.trans(iff2, iff3))

  # Normalize tm into [num, den, eq_thm (⊢ tm = num / den), ne_thm (⊢ den ≠ 0)].
  -> field_norm(goal, hints, tm, ty, sfx)
    one = mk_lit(Q_ONE, ty)
    zero = mk_lit(Q_ZERO, ty)
    add_c = @k.mk_const("+", ty_funs([ty, ty], ty))
    sub_c = @k.mk_const("-", ty_funs([ty, ty], ty))
    mul_c = @k.mk_const("*", ty_funs([ty, ty], ty))
    div_c = @k.mk_const("/", ty_funs([ty, ty], ty))
    neg_c = @k.mk_const("neg", ty_fun(ty, ty))
    eq_div_iff = @session.theorem("eq_div_iff" + sfx)
    div_eq_iff = @session.theorem("div_eq_iff" + sfx)
    div_def = @session.theorem("div_def" + sfx)
    mul_ne_zero = @session.theorem("mul_ne_zero" + sfx)
    ne1 = arith_prove(Goal.new([], [], @k.neg_tm(@k.eq_tm(one, zero))), [])
    if !field_has_div?(tm, ty)
      iff = @k.mp(@k.spec(one, @k.spec(tm, @k.spec(tm, eq_div_iff))), ne1)
      eq_th = @k.eq_mp(@k.sym(iff), @k.ring_eq(mk_apps(mul_c, [tm, one]), tm))
      return [tm, one, eq_th, ne1]
    if tm.a.tag == :const && tm.a.op == OP_NEG
      r1 = field_norm(goal, hints, tm.b, ty, sfx)
      n1 = r1[0]
      d1 = r1[1]
      nn1 = mk_app(neg_c, n1)
      step1 = @d.ap_term(neg_c, r1[2])
      e_in = @d.ap_term(neg_c, @k.spec(d1, @k.spec(n1, div_def)))
      e_out = @k.spec(d1, @k.spec(nn1, div_def))
      mid = @k.ring_eq(dest_binop(e_in.concl, "=")[1], dest_binop(e_out.concl, "=")[1])
      return [nn1, d1, @k.trans(step1, @k.trans(e_in, @k.trans(mid, @k.sym(e_out)))), r1[3]]
    op = tm.a.a.op
    a = tm.a.b
    b = tm.b
    if op == OP_ADD || op == OP_SUB
      r1 = field_norm(goal, hints, a, ty, sfx)
      r2 = field_norm(goal, hints, b, ty, sfx)
      n1 = r1[0]
      d1 = r1[1]
      n2 = r2[0]
      d2 = r2[1]
      op_str = op == OP_ADD ? "+" : "-"
      comb = combination_binop(op_str, ty, r1[2], r2[2])
      if tm_eq(d1, d2)
        num = mk_apps(op == OP_ADD ? add_c : sub_c, [n1, n2])
        lem = @session.theorem((op == OP_ADD ? "add_div" : "sub_div") + sfx)
        return [num, d1, @k.trans(comb, @k.sym(@k.spec(d1, @k.spec(n2, @k.spec(n1, lem))))), r1[3]]
      num = mk_apps(op == OP_ADD ? add_c : sub_c, [mk_apps(mul_c, [n1, d2]), mk_apps(mul_c, [d1, n2])])
      den = mk_apps(mul_c, [d1, d2])
      ne12 = @k.mp(@k.mp(@k.spec(d2, @k.spec(d1, mul_ne_zero)), r1[3]), r2[3])
      if op == OP_ADD
        dad = @session.theorem("div_add_div" + sfx)
        step = @k.mp(@k.mp(@k.spec(d2, @k.spec(n2, @k.spec(d1, @k.spec(n1, dad)))), r1[3]), r2[3])
        return [num, den, @k.trans(comb, step), ne12]
      # For subtraction: prove n1 / d1 - n2 / d2 = (n1 * d2 - d1 * n2) / (d1 * d2) via eq_div_iff + div_add_div on -n2
      nn2 = mk_app(neg_c, n2)
      dad = @session.theorem("div_add_div" + sfx)
      e_sub = combination_binop("-", ty, @k.spec(d1, @k.spec(n1, div_def)), @k.spec(d2, @k.spec(n2, div_def)))
      e_add = combination_binop("+", ty, @k.spec(d1, @k.spec(n1, div_def)), @k.spec(d2, @k.spec(nn2, div_def)))
      to_add = @k.trans(e_sub, @k.trans(@k.ring_eq(dest_binop(e_sub.concl, "=")[1], dest_binop(e_add.concl, "=")[1]), @k.sym(e_add)))
      dad_th = @k.mp(@k.mp(@k.spec(d2, @k.spec(nn2, @k.spec(d1, @k.spec(n1, dad)))), r1[3]), r2[3])
      num_eq = @k.ring_eq(mk_apps(add_c, [mk_apps(mul_c, [n1, d2]), mk_apps(mul_c, [d1, nn2])]), num)
      tail = @k.trans(to_add, @k.trans(dad_th, @d.ap_thm(@d.ap_term(div_c, num_eq), den)))
      return [num, den, @k.trans(comb, tail), ne12]
    if op == OP_MUL
      if !field_has_div?(a, ty)
        r2 = field_norm(goal, hints, b, ty, sfx)
        mda = @session.theorem("mul_div_assoc" + sfx)
        step1 = combination_binop("*", ty, @k.refl(a), r2[2])
        return [mk_apps(mul_c, [a, r2[0]]), r2[1], @k.trans(step1, @k.sym(@k.spec(r2[1], @k.spec(r2[0], @k.spec(a, mda))))), r2[3]]
      if !field_has_div?(b, ty)
        r1 = field_norm(goal, hints, a, ty, sfx)
        step1 = combination_binop("*", ty, r1[2], @k.refl(b))
        sh = field_shift_div_mul(r1[0], r1[1], b, ty, div_def)
        return [mk_apps(mul_c, [r1[0], b]), r1[1], @k.trans(step1, sh), r1[3]]
      r1 = field_norm(goal, hints, a, ty, sfx)
      r2 = field_norm(goal, hints, b, ty, sfx)
      dmd = @session.theorem("div_mul_div" + sfx)
      comb = combination_binop("*", ty, r1[2], r2[2])
      ne12 = @k.mp(@k.mp(@k.spec(r2[1], @k.spec(r1[1], mul_ne_zero)), r1[3]), r2[3])
      return [mk_apps(mul_c, [r1[0], r2[0]]), mk_apps(mul_c, [r1[1], r2[1]]), @k.trans(comb, @k.spec(r2[1], @k.spec(r2[0], @k.spec(r1[1], @k.spec(r1[0], dmd))))), ne12]
    # op == OP_DIV
    hb_ne = field_prove_nonzero(goal, hints, b, ty, sfx)
    if !field_has_div?(a, ty) && !field_has_div?(b, ty)
      return [a, b, @k.refl(tm), hb_ne]
    if !field_has_div?(b, ty)
      r1 = field_norm(goal, hints, a, ty, sfx)
      dd = @session.theorem("div_div" + sfx)
      step1 = @d.ap_thm(@d.ap_term(div_c, r1[2]), b)
      ne_db = @k.mp(@k.mp(@k.spec(b, @k.spec(r1[1], mul_ne_zero)), r1[3]), hb_ne)
      return [r1[0], mk_apps(mul_c, [r1[1], b]), @k.trans(step1, @k.spec(b, @k.spec(r1[1], @k.spec(r1[0], dd)))), ne_db]
    r1 = field_norm(goal, hints, a, ty, sfx)
    r2 = field_norm(goal, hints, b, ty, sfx)
    n1 = r1[0]
    d1 = r1[1]
    n2 = r2[0]
    d2 = r2[1]
    eq_c = @k.mk_const("=", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    frac2 = mk_apps(div_c, [n2, d2])
    f2_zero = @k.eq_tm(frac2, zero)
    f2_to_b = @d.ap_thm(@d.ap_term(eq_c, @k.sym(r2[2])), zero)
    h_f2_ne = @k.not_intro(f2_zero, @k.not_elim(hb_ne, @k.eq_mp(f2_to_b, @k.assume(f2_zero))))
    n2_zero = @k.eq_tm(n2, zero)
    z_div = @k.trans(@d.ap_thm(@d.ap_term(div_c, @k.assume(n2_zero)), d2), @k.trans(@k.spec(d2, @k.spec(zero, div_def)), @k.ring_eq(mk_apps(mul_c, [zero, mk_apps(div_c, [one, d2])]), zero)))
    hn2_ne = @k.not_intro(n2_zero, @k.not_elim(h_f2_ne, z_div))
    den = mk_apps(mul_c, [d1, n2])
    num = mk_apps(mul_c, [n1, d2])
    ne_den = @k.mp(@k.mp(@k.spec(n2, @k.spec(d1, mul_ne_zero)), r1[3]), hn2_ne)
    comb = @k.mk_comb(@d.ap_term(div_c, r1[2]), r2[2])
    iff_outer = @k.mp(@k.spec(frac2, @k.spec(mk_apps(div_c, [num, den]), @k.spec(mk_apps(div_c, [n1, d1]), div_eq_iff))), h_f2_ne)
    dmd = @session.theorem("div_mul_div" + sfx)
    mul_rhs = @k.spec(d2, @k.spec(n2, @k.spec(den, @k.spec(num, dmd))))
    ne_big = @k.mp(@k.mp(@k.spec(d2, @k.spec(den, mul_ne_zero)), ne_den), r2[3])
    iff_inner = field_frac_eq_iff(n1, d1, r1[3], mk_apps(mul_c, [num, n2]), mk_apps(mul_c, [den, d2]), ne_big, ty, div_def, div_eq_iff, eq_div_iff)
    ring_ok = @k.ring_eq(mk_apps(mul_c, [n1, mk_apps(mul_c, [den, d2])]), mk_apps(mul_c, [mk_apps(mul_c, [num, n2]), d1]))
    inner_eq = @k.eq_mp(@k.sym(iff_inner), ring_ok)
    outer_eq = @k.eq_mp(@k.sym(iff_outer), @k.trans(inner_eq, @k.sym(mul_rhs)))
    [num, den, @k.trans(comb, outer_eq), ne_den]

  -> tac_field_simp(g, args)
    hints = []
    if args.size > 0
      if args.size < 2 || args[0].text != "\[" || args[args.size - 1].text != "]"
        fail("field_simp: expected optional [h1, h2, ...] hints")
      inner = arr_sub(args, 1, args.size - 2)
      if inner.size > 0
        split_top(inner, ",").each -> (item)
          hints.push(proof_expr(g.goal, item))
    c = @d.beta_eta_term(g.goal.concl)
    rel = nil
    sides = dest_binop(c, "=")
    if sides != nil
      rel = "="
    else
      sides = dest_binop(c, "≤")
      if sides != nil
        rel = "≤"
      else
        sides = dest_binop(c, "<")
        if sides != nil
          rel = "<"
    if rel == nil
      fail("field_simp: goal must be =, ≤, or < over ℝ or ℚ")
    ty = type_of(sides[0])
    if !ty_eq(ty, ty_real) && !ty_eq(ty, ty_rat)
      fail("field_simp: expected ℝ or ℚ terms, got " + ty_show(ty))
    sfx = ty_eq(ty, ty_real) ? ".real" : ".rat"
    if @session.theorem("eq_div_iff" + sfx) == nil
      fail("field_simp: requires 'import arith'")
    one = mk_lit(Q_ONE, ty)
    mul_c = @k.mk_const("*", ty_funs([ty, ty], ty))
    div_c = @k.mk_const("/", ty_funs([ty, ty], ty))
    rel_c = @k.mk_const(rel, ty_funs([ty, ty], TY_BOOL_SINGLETON))
    div_def = @session.theorem("div_def" + sfx)
    r_l = field_norm(g.goal, hints, sides[0], ty, sfx)
    r_r = field_norm(g.goal, hints, sides[1], ty, sfx)
    n_l = r_l[0]
    d_l = r_l[1]
    n_r = r_r[0]
    d_r = r_r[1]
    lhs_has = field_has_div?(sides[0], ty)
    rhs_has = field_has_div?(sides[1], ty)
    if !lhs_has && !rhs_has
      if rel == "="
        return tac_ring(g)
      fail("field_simp: no field divisions found in goal")
    if rel == "="
      div_eq_iff = @session.theorem("div_eq_iff" + sfx)
      eq_div_iff = @session.theorem("eq_div_iff" + sfx)
      prop_step = nil
      new_lhs = nil
      new_rhs = nil
      if lhs_has && !rhs_has
        to_frac = @d.ap_thm(@d.ap_term(rel_c, r_l[2]), sides[1])
        iff1 = @k.mp(@k.spec(d_l, @k.spec(sides[1], @k.spec(n_l, div_eq_iff))), r_l[3])
        prop_step = @k.trans(to_frac, iff1)
        new_lhs = n_l
        new_rhs = mk_apps(mul_c, [sides[1], d_l])
      elsif !lhs_has && rhs_has
        to_frac = @k.mk_comb(@d.ap_term(rel_c, @k.refl(sides[0])), r_r[2])
        iff1 = @k.mp(@k.spec(d_r, @k.spec(n_r, @k.spec(sides[0], eq_div_iff))), r_r[3])
        prop_step = @k.trans(to_frac, iff1)
        new_lhs = mk_apps(mul_c, [sides[0], d_r])
        new_rhs = n_r
      else
        to_frac = @k.mk_comb(@d.ap_term(rel_c, r_l[2]), r_r[2])
        iff_both = field_frac_eq_iff(n_l, d_l, r_l[3], n_r, d_r, r_r[3], ty, div_def, div_eq_iff, eq_div_iff)
        prop_step = @k.trans(to_frac, iff_both)
        new_lhs = mk_apps(mul_c, [n_l, d_r])
        new_rhs = mk_apps(mul_c, [n_r, d_l])
      new_concl = @k.eq_tm(new_lhs, new_rhs)
      ring_prf = nil
      begin
        ring_prf = ring_equality_proof(new_concl)
      rescue err_r
        ring_prf = nil
      if ring_prf == nil && new_concl.has_widening_cast?
        cast_rules = []
        ["int_of_nat", "rat_of_int", "real_of_rat"].each -> (cast)
          bucket = @session.simp_by_head[cast]
          if bucket != nil
            bucket.each -> (rule)
              if (rule.name == cast + "_add" || rule.name == cast + "_mul") && rule.th.tags.size == 0
                cast_rules.push(rule)
        if cast_rules.size > 0
          cfold = Simp.new(@d, cast_rules)
          cl_eq = cfold.simp_conv(new_lhs, 0)
          cr_eq = cfold.simp_conv(new_rhs, 0)
          cl_rhs = dest_binop(cl_eq.concl, "=")[1]
          cr_rhs = dest_binop(cr_eq.concl, "=")[1]
          begin
            cmid = ring_equality_proof(@k.eq_tm(cl_rhs, cr_rhs))
            ring_prf = @k.trans(cl_eq, @k.trans(cmid, @k.sym(cr_eq)))
          rescue err_cr
            ring_prf = nil
      if ring_prf != nil
        return close(g, fit_concl(@k.eq_mp(@k.sym(prop_step), ring_prf), g.goal.concl))
      return refine(g, [g.goal.with_concl(new_concl)], ->(ts) fit_concl(@k.eq_mp(@k.sym(prop_step), ts[0]), g.goal.concl))
    # Inequality clearing (≤ or <): requires strictly positive denominators
    div_rel_iff = @session.theorem((rel == "≤" ? "div_le_iff" : "div_lt_iff") + sfx)
    rel_div_iff = @session.theorem((rel == "≤" ? "le_div_iff" : "lt_div_iff") + sfx)
    if lhs_has && !rhs_has
      pos_l = field_prove_pos(g.goal, hints, d_l, ty, sfx)
      if pos_l == nil
        fail("field_simp: could not prove denominator > 0 for inequality: " + tm_show(d_l))
      to_frac = @d.ap_thm(@d.ap_term(rel_c, r_l[2]), sides[1])
      iff1 = @k.mp(@k.spec(d_l, @k.spec(sides[1], @k.spec(n_l, div_rel_iff))), pos_l)
      prop_step = @k.trans(to_frac, iff1)
      new_concl = mk_apps(rel_c, [n_l, mk_apps(mul_c, [sides[1], d_l])])
      return refine(g, [g.goal.with_concl(new_concl)], ->(ts) fit_concl(@k.eq_mp(@k.sym(prop_step), ts[0]), g.goal.concl))
    if !lhs_has && rhs_has
      pos_r = field_prove_pos(g.goal, hints, d_r, ty, sfx)
      if pos_r == nil
        fail("field_simp: could not prove denominator > 0 for inequality: " + tm_show(d_r))
      to_frac = @k.mk_comb(@d.ap_term(rel_c, @k.refl(sides[0])), r_r[2])
      iff1 = @k.mp(@k.spec(d_r, @k.spec(n_r, @k.spec(sides[0], rel_div_iff))), pos_r)
      prop_step = @k.trans(to_frac, iff1)
      new_concl = mk_apps(rel_c, [mk_apps(mul_c, [sides[0], d_r]), n_r])
      return refine(g, [g.goal.with_concl(new_concl)], ->(ts) fit_concl(@k.eq_mp(@k.sym(prop_step), ts[0]), g.goal.concl))
    pos_l = field_prove_pos(g.goal, hints, d_l, ty, sfx)
    if pos_l == nil
      fail("field_simp: could not prove denominator > 0 for inequality: " + tm_show(d_l))
    pos_r = field_prove_pos(g.goal, hints, d_r, ty, sfx)
    if pos_r == nil
      fail("field_simp: could not prove denominator > 0 for inequality: " + tm_show(d_r))
    to_frac = @k.mk_comb(@d.ap_term(rel_c, r_l[2]), r_r[2])
    rhs_frac = mk_apps(div_c, [n_r, d_r])
    iff1 = @k.mp(@k.spec(d_l, @k.spec(rhs_frac, @k.spec(n_l, div_rel_iff))), pos_l)
    sh = field_shift_div_mul(n_r, d_r, d_l, ty, div_def)
    iff2 = @d.ap_term(mk_app(rel_c, n_l), sh)
    iff3 = @k.mp(@k.spec(d_r, @k.spec(mk_apps(mul_c, [n_r, d_l]), @k.spec(n_l, rel_div_iff))), pos_r)
    prop_step = @k.trans(to_frac, @k.trans(iff1, @k.trans(iff2, iff3)))
    new_concl = mk_apps(rel_c, [mk_apps(mul_c, [n_l, d_r]), mk_apps(mul_c, [n_r, d_l])])
    refine(g, [g.goal.with_concl(new_concl)], ->(ts) fit_concl(@k.eq_mp(@k.sym(prop_step), ts[0]), g.goal.concl))

  # ---- continuity tactic ----------------------------------------------------

  -> cont_congr(f_tm, g_tm, x, hf, y_var, eq_mid)
    congr_th = @session.theorem("continuous_at.congr")
    if congr_th == nil
      return nil
    bg = @d.beta_norm_conv(mk_app(g_tm, y_var))
    bf = @d.beta_norm_conv(mk_app(f_tm, y_var))
    eq_app = @k.trans(bg, @k.trans(eq_mid, @k.sym(bf)))
    agree = @k.gen(y_var, eq_app)
    @k.mp(@k.mp(@k.spec(x, @k.spec(g_tm, @k.spec(f_tm, congr_th))), hf), agree)

  -> cont_discharge_cond(goal, hints, extra_rules, cond, depth)
    if depth > 6
      return nil
    goal.hyps.each -> (h)
      if tm_eq(h[1], cond)
        return @k.assume(h[1])
    hints.each -> (th)
      if tm_eq(th.concl, cond)
        return th
    sp = strip_app(cond)
    if (sp[0].tag == :const && (sp[0].name == "continuous_at" || sp[0].name == "continuous_within_at")) || dest_binop(cond, "∧") != nil
      csub = cont_solve_goal(goal.with_concl(cond), hints, extra_rules, depth + 1)
      if csub != nil
        return csub
    extra = [] + hints
    pos_facts(cond, extra, {})
    saved_nl = @nl_mode
    @nl_mode = true
    res = nil
    begin
      res = arith_prove(goal.with_concl(cond), extra)
    rescue err_cd
      res = nil
    @nl_mode = saved_nl
    res

  -> cont_try_thm(goal, hints, extra_rules, th, v, body, x, depth)
    if th.concl.tv
      return nil
    avoid = goal.all_terms + [v, body, x, th.concl]
    steps = []
    qvars = []
    pvars = {}
    cur = th.concl
    while true
      q = dest_unop(cur, "∀")
      if q != nil && q.tag == :lam
        vp = dest_lam_fresh(q, avoid)
        avoid.push(vp[0])
        qvars.push(vp[0])
        pvars[vp[0].vkey] = true
        steps.push([:all, vp[0]])
        cur = vp[1]
      else
        imp = dest_binop(cur, "⇒")
        if imp != nil
          steps.push([:imp])
          cur = imp[1]
        else
          break
    leaves = []
    stk = [[[], cur]]
    while stk.size > 0
      it = stk.pop
      cj = dest_binop(it[1], "∧")
      if cj != nil
        stk.push([it[0] + [false], cj[1]])
        stk.push([it[0] + [true], cj[0]])
      else
        leaves.push(it)
    li = 0
    while li < leaves.size
      path = leaves[li][0]
      ltm = leaves[li][1]
      lsp = strip_app(ltm)
      if lsp[0].tag == :const && lsp[0].name == "continuous_at" && lsp[1].size == 2 && ty_eq(type_of(lsp[1][1]), ty_real)
        g_pat = lsp[1][0]
        pt_pat = lsp[1][1]
        app_pat = @d.beta_norm_term(mk_app(g_pat, v))
        mat = Matcher.new(pvars, {})
        if mat.m(pt_pat, x, 0, true) && mat.m(app_pat, body, 0, true)
          ok = true
          qi = 0
          while qi < qvars.size
            bval = mat.tm[qvars[qi].vkey]
            if bval == nil || tm_free_in?(v, bval)
              ok = false
              break
            qi += 1
          if ok
            inst_th = th
            si = 0
            while si < steps.size
              st = steps[si]
              if st[0] == :all
                inst_th = @k.spec(mat.tm[st[1].vkey], inst_th)
              else
                imp_now = dest_binop(@d.beta_norm_term(inst_th.concl), "⇒")
                if imp_now == nil
                  ok = false
                  break
                inst_th = @d.beta_norm_thm(inst_th)
                cprf = cont_discharge_cond(goal, hints, extra_rules, imp_now[0], depth + 1)
                if cprf == nil
                  ok = false
                  break
                inst_th = @k.mp(inst_th, cprf)
              si += 1
            if ok
              inst_th = @d.beta_norm_thm(inst_th)
              pi = 0
              while pi < path.size
                inst_th = path[pi] ? @k.conj1(inst_th) : @k.conj2(inst_th)
                pi += 1
              f_lam = mk_lam(v, body)
              g_inst = strip_app(inst_th.concl)[1][0]
              if tm_eq(g_inst, f_lam)
                return inst_th
              return cont_congr(g_inst, f_lam, x, inst_th, v, @k.refl(body))
      li += 1
    nil

  -> cont_from_hyps(goal, hints, extra_rules, v, body, x, depth)
    hi = 0
    while hi < hints.size
      r = cont_try_thm(goal, hints, extra_rules, hints[hi], v, body, x, depth)
      if r != nil
        return r
      hi += 1
    gi = goal.hyps.size - 1
    while gi >= 0
      hth = @k.assume(goal.hyps[gi][1])
      r = cont_try_thm(goal, hints, extra_rules, hth, v, body, x, depth)
      if r != nil
        return r
      gi -= 1
    nil

  -> cont_prove_fn(goal, hints, extra_rules, f_fn, pt, depth)
    v = mk_var(fresh_name("y", goal.all_terms + [f_fn, pt]), ty_real)
    body = @d.beta_norm_term(mk_app(f_fn, v))
    res_lam = cont_prove(goal, hints, extra_rules, v, body, pt, depth)
    if res_lam == nil
      return nil
    lam_v = mk_lam(v, body)
    if tm_eq(lam_v, f_fn)
      return res_lam
    if f_fn.tag != :lam
      eta_eq = @k.eta(mk_lam(v, mk_app(f_fn, v)))
      ca_c = @k.mk_const("continuous_at", ty_funs([ty_fun(ty_real, ty_real), ty_real], TY_BOOL_SINGLETON))
      if tm_eq(body, mk_app(f_fn, v))
        return @k.eq_mp(@d.ap_thm(@d.ap_term(ca_c, eta_eq), pt), res_lam)
    cont_congr(lam_v, f_fn, pt, res_lam, v, @k.refl(body))

  -> cont_prove(goal, hints, extra_rules, v, raw_body, x, depth)
    if depth > 24
      return nil
    bb = @d.beta_norm_conv(raw_body)
    body = dest_binop(bb.concl, "=")[1]
    res = cont_prove_norm(goal, hints, extra_rules, v, body, x, depth)
    if res == nil
      return nil
    if tm_eq(raw_body, body)
      return res
    cont_congr(mk_lam(v, body), mk_lam(v, raw_body), x, res, v, @k.refl(body))

  -> cont_prove_norm(goal, hints, extra_rules, v, body, x, depth)
    if !tm_free_in?(v, body)
      cth = @session.theorem("continuous_at.const")
      return cth == nil ? nil : @k.spec(x, @k.spec(body, cth))
    if tm_eq(body, v)
      ith = @session.theorem("continuous_at.id")
      return ith == nil ? nil : @k.spec(x, ith)
    from_h = cont_from_hyps(goal, hints, extra_rules, v, body, x, depth)
    if from_h != nil
      return from_h
    zero_r = mk_lit(Q_ZERO, ty_real)
    one_r = mk_lit(Q_ONE, ty_real)
    sub_c = @k.mk_const("-", ty_funs([ty_real, ty_real], ty_real))
    mul_c = @k.mk_const("*", ty_funs([ty_real, ty_real], ty_real))
    div_c = @k.mk_const("/", ty_funs([ty_real, ty_real], ty_real))
    if body.tag == :app && body.a.tag == :const && body.a.op == OP_NEG && ty_eq(type_of(body), ty_real)
      alt = mk_apps(sub_c, [zero_r, body.b])
      p_alt = cont_prove_norm(goal, hints, extra_rules, v, alt, x, depth + 1)
      if p_alt != nil
        return cont_congr(mk_lam(v, alt), mk_lam(v, body), x, p_alt, v, @k.ring_eq(body, alt))
    if body.tag == :app && body.a.tag == :app && body.a.a.tag == :const && ty_eq(type_of(body), ty_real)
      op = body.a.a.op
      a = body.a.b
      b = body.b
      if op == OP_ADD || op == OP_SUB || op == OP_MUL
        lem_nm = op == OP_ADD ? "continuous_at.add" : (op == OP_SUB ? "continuous_at.sub" : "continuous_at.mul")
        lem = @session.theorem(lem_nm)
        if lem != nil
          pa = cont_prove(goal, hints, extra_rules, v, a, x, depth + 1)
          if pa != nil
            pb = cont_prove(goal, hints, extra_rules, v, b, x, depth + 1)
            if pb != nil
              return @d.beta_norm_thm(@k.mp(@k.mp(@k.spec(x, @k.spec(mk_lam(v, b), @k.spec(mk_lam(v, a), lem))), pa), pb))
      elsif op == OP_DIV
        div_def = @session.theorem("div_def.real")
        if div_def != nil
          if !tm_free_in?(v, b)
            alt = mk_apps(mul_c, [a, mk_apps(div_c, [one_r, b])])
            p_alt = cont_prove(goal, hints, extra_rules, v, alt, x, depth + 1)
            if p_alt != nil
              return cont_congr(mk_lam(v, alt), mk_lam(v, body), x, p_alt, v, @k.spec(b, @k.spec(a, div_def)))
          else
            inv_pos_th = @session.theorem("continuous_at.inv_of_pos")
            if inv_pos_th != nil
              bx = tm_subst(b, {v.vkey => x})
              pos_b = field_prove_pos(goal, hints, bx, ty_real, ".real")
              if pos_b != nil
                pb = cont_prove(goal, hints, extra_rules, v, b, x, depth + 1)
                if pb != nil
                  inv_inst = @d.beta_norm_thm(@k.spec(x, @k.spec(mk_lam(v, b), inv_pos_th)))
                  inv_prf = @d.beta_norm_thm(@k.mp(@k.mp(inv_inst, pb), pos_b))
                  if tm_eq(a, one_r)
                    return inv_prf
                  mul_th = @session.theorem("continuous_at.mul")
                  pa = cont_prove(goal, hints, extra_rules, v, a, x, depth + 1)
                  if mul_th != nil && pa != nil
                    inv_b = mk_apps(div_c, [one_r, b])
                    alt = mk_apps(mul_c, [a, inv_b])
                    p_alt = @d.beta_norm_thm(@k.mp(@k.mp(@k.spec(x, @k.spec(mk_lam(v, inv_b), @k.spec(mk_lam(v, a), mul_th))), pa), inv_prf))
                    return cont_congr(mk_lam(v, alt), mk_lam(v, body), x, p_alt, v, @k.spec(b, @k.spec(a, div_def)))
      elsif op == OP_POW && !tm_free_in?(v, b) && ty_eq(type_of(b), TY_NAT_SINGLETON)
        pow_th = @session.theorem("continuous_at.pow")
        if pow_th != nil
          pa = cont_prove(goal, hints, extra_rules, v, a, x, depth + 1)
          if pa != nil
            return @d.beta_norm_thm(@k.mp(@k.spec(x, @k.spec(b, @k.spec(mk_lam(v, a), pow_th))), pa))
    sp = strip_app(body)
    if sp[0].tag == :const
      if sp[0].op == OP_ABS && sp[1].size == 1 && ty_eq(type_of(sp[1][0]), ty_real)
        abs_th = @session.theorem("continuous_at.abs")
        if abs_th != nil
          pa = cont_prove(goal, hints, extra_rules, v, sp[1][0], x, depth + 1)
          if pa != nil
            return @d.beta_norm_thm(@k.mp(@k.spec(x, @k.spec(mk_lam(v, sp[1][0]), abs_th)), pa))
      elsif (sp[0].name == "min" || sp[0].name == "max") && sp[1].size == 2 && ty_eq(type_of(body), ty_real)
        mm_th = @session.theorem("continuous_at." + sp[0].name)
        if mm_th != nil
          pa = cont_prove(goal, hints, extra_rules, v, sp[1][0], x, depth + 1)
          if pa != nil
            pb = cont_prove(goal, hints, extra_rules, v, sp[1][1], x, depth + 1)
            if pb != nil
              return @d.beta_norm_thm(@k.mp(@k.mp(@k.spec(x, @k.spec(mk_lam(v, sp[1][1]), @k.spec(mk_lam(v, sp[1][0]), mm_th))), pa), pb))
      elsif sp[0].name == "sum_below" && sp[1].size == 2 && !tm_free_in?(v, sp[1][0]) && sp[1][1].tag == :lam && ty_eq(type_of(body), ty_real)
        sb_th = @session.theorem("continuous_at.sum_below")
        if sb_th != nil
          n_tm = sp[1][0]
          i_lp = dest_lam_fresh(sp[1][1], goal.all_terms + [v, body, x, n_tm])
          i_var = i_lp[0]
          body_i = i_lp[1]
          lt_nat = @k.mk_const("<", ty_funs([TY_NAT_SINGLETON, TY_NAT_SINGLETON], TY_BOOL_SINGLETON))
          i_lt_n = mk_apps(lt_nat, [i_var, n_tm])
          sub_goal = goal.add_fix(i_var.name, i_var).add_hyp(fresh_hyp_name(goal), i_lt_n)
          pi_prf = cont_prove(sub_goal, hints, extra_rules, v, body_i, x, depth + 1)
          if pi_prf != nil
            f_2 = mk_lam(i_var, mk_lam(v, body_i))
            b_conv = @d.beta_norm_conv(mk_app(f_2, i_var))
            ca_c = @k.mk_const("continuous_at", ty_funs([ty_fun(ty_real, ty_real), ty_real], TY_BOOL_SINGLETON))
            pi_adj = @k.eq_mp(@k.sym(@d.ap_thm(@d.ap_term(ca_c, b_conv), x)), pi_prf)
            all_i = @k.gen(i_var, @k.disch(i_lt_n, pi_adj))
            raw_sb = @d.beta_norm_thm(@k.mp(@k.spec(x, @k.spec(n_tm, @k.spec(f_2, sb_th))), all_i))
            sb_fn = strip_app(raw_sb.concl)[1][0]
            if tm_eq(sb_fn, mk_lam(v, body))
              return raw_sb
            return cont_congr(sb_fn, mk_lam(v, body), x, raw_sb, v, @k.refl(body))
      elsif sp[0].name == "exp" && sp[1].size == 1
        exp_comp_th = @session.theorem("continuous_at.exp_comp")
        if exp_comp_th != nil
          pa = cont_prove(goal, hints, extra_rules, v, sp[1][0], x, depth + 1)
          if pa != nil
            return @d.beta_norm_thm(@k.mp(@k.spec(x, @k.spec(mk_lam(v, sp[1][0]), exp_comp_th)), pa))
      elsif (sp[0].name == "sin" || sp[0].name == "cos") && sp[1].size == 1
        comp_th = @session.theorem("continuous_at.comp")
        sc_th = @session.theorem("continuous_at." + sp[0].name)
        if comp_th != nil && sc_th != nil
          arg_x = tm_subst(sp[1][0], {v.vkey => x})
          pa = cont_prove(goal, hints, extra_rules, v, sp[1][0], x, depth + 1)
          if pa != nil
            comp_inst = @d.beta_norm_thm(@k.spec(x, @k.spec(mk_lam(v, sp[1][0]), @k.spec(sp[0], comp_th))))
            return @d.beta_norm_thm(@k.mp(@k.mp(comp_inst, @k.spec(arg_x, sc_th)), pa))
      elsif sp[0].name == "log" && sp[1].size == 1
        comp_th = @session.theorem("continuous_at.comp")
        log_th = @session.theorem("continuous_at.log")
        if comp_th != nil && log_th != nil
          arg_x = tm_subst(sp[1][0], {v.vkey => x})
          pos_arg = field_prove_pos(goal, hints, arg_x, ty_real, ".real")
          if pos_arg != nil
            pa = cont_prove(goal, hints, extra_rules, v, sp[1][0], x, depth + 1)
            if pa != nil
              comp_inst = @d.beta_norm_thm(@k.spec(x, @k.spec(mk_lam(v, sp[1][0]), @k.spec(sp[0], comp_th))))
              return @d.beta_norm_thm(@k.mp(@k.mp(comp_inst, @k.mp(@k.spec(arg_x, log_th), pos_arg)), pa))
    if body.tag == :app && ty_eq(type_of(body.b), ty_real) && !tm_free_in?(v, body.a) && tm_free_in?(v, body.b)
      comp_th = @session.theorem("continuous_at.comp")
      if comp_th != nil
        arg_x = tm_subst(body.b, {v.vkey => x})
        prf_f = cont_prove_fn(goal, hints, extra_rules, body.a, arg_x, depth + 1)
        if prf_f != nil
          prf_arg = cont_prove(goal, hints, extra_rules, v, body.b, x, depth + 1)
          if prf_arg != nil
            comp_inst = @d.beta_norm_thm(@k.spec(x, @k.spec(mk_lam(v, body.b), @k.spec(body.a, comp_th))))
            return @d.beta_norm_thm(@k.mp(@k.mp(comp_inst, prf_f), prf_arg))
    # Fallback 1: simplify body with @session [simp] + explicit extra_rules
    s1 = Simp.new(@d, extra_rules, @session.simp_by_head, @session.simp_general)
    s1.hyp_rules = hyp_thms(goal)
    prover = self
    s1.discharger = ->(c) prover.try_arith_discharge(goal, c)
    s1_eq = s1.simp_conv(body, 0)
    s1_rhs = @d.beta_norm_term(dest_binop(s1_eq.concl, "=")[1])
    if !tm_eq(body, s1_rhs)
      ba = @d.beta_norm_conv(dest_binop(s1_eq.concl, "=")[1])
      p_s1 = cont_prove_norm(goal, hints, extra_rules, v, s1_rhs, x, depth + 1)
      if p_s1 != nil
        return cont_congr(mk_lam(v, s1_rhs), mk_lam(v, body), x, p_s1, v, @k.trans(s1_eq, ba))
    # Fallback 2: unfold local `set` bindings (variables not protected by a continuous_at hypothesis)
    protected_vars = {}
    goal.hyps.each -> (h)
      if tm_contains_const_name?(h[1], "continuous_at") || tm_contains_const_name?(h[1], "continuous_within_at")
        tm_frees(h[1]).each -> (fv)
          protected_vars[fv.vkey] = true
    set_rules = [] + extra_rules
    goal.hyps.each -> (h)
      eq_sides = dest_binop(h[1], "=")
      if eq_sides != nil && eq_sides[0].tag == :var && !protected_vars.has_key?(eq_sides[0].vkey) && !tm_free_in?(eq_sides[0], eq_sides[1])
        set_rules.push(make_rule(@d, @k.assume(h[1]), h[0]))
    if set_rules.size > extra_rules.size
      s2 = Simp.new(@d, set_rules, @session.simp_by_head, @session.simp_general)
      s2.hyp_rules = hyp_thms(goal)
      s2.discharger = ->(c) prover.try_arith_discharge(goal, c)
      s2_eq = s2.simp_conv(body, 0)
      s2_rhs = @d.beta_norm_term(dest_binop(s2_eq.concl, "=")[1])
      if !tm_eq(body, s2_rhs)
        ba2 = @d.beta_norm_conv(dest_binop(s2_eq.concl, "=")[1])
        p_s2 = cont_prove_norm(goal, hints, extra_rules, v, s2_rhs, x, depth + 1)
        if p_s2 != nil
          return cont_congr(mk_lam(v, s2_rhs), mk_lam(v, body), x, p_s2, v, @k.trans(s2_eq, ba2))
    # Fallback 3: unfold head non-primitive definition once (e.g. rpow, or inner complex def under complex.re/im)
    cand_hd = sp[0]
    if sp[0].tag == :const && (sp[0].name == "complex.re" || sp[0].name == "complex.im") && sp[1].size == 1
      isp = strip_app(sp[1][0])
      if isp[0].tag == :const && @session.k.defs.has_key?(isp[0].name)
        cand_hd = isp[0]
    if cand_hd.tag == :const && @session.k.defs.has_key?(cand_hd.name)
      hd_nm = cand_hd.name
      def_rules = [make_rule(@d, @session.k.defs[hd_nm], hd_nm, false)] + extra_rules
      @session.eqns_of(hd_nm).each -> (eqth)
        def_rules.push(named_equation(eqth, hd_nm))
      s3 = Simp.new(@d, def_rules, @session.simp_by_head, @session.simp_general)
      s3.hyp_rules = hyp_thms(goal)
      s3.discharger = ->(c) prover.try_arith_discharge(goal, c)
      s3_eq = s3.simp_conv(body, 0)
      s3_rhs = @d.beta_norm_term(dest_binop(s3_eq.concl, "=")[1])
      if !tm_eq(body, s3_rhs)
        ba3 = @d.beta_norm_conv(dest_binop(s3_eq.concl, "=")[1])
        p_s3 = cont_prove_norm(goal, hints, extra_rules, v, s3_rhs, x, depth + 1)
        if p_s3 != nil
          return cont_congr(mk_lam(v, s3_rhs), mk_lam(v, body), x, p_s3, v, @k.trans(s3_eq, ba3))
    nil

  -> tm_contains_const_name?(t, nm)
    if t.tag == :const
      return t.name == nm
    if t.tag == :app
      return tm_contains_const_name?(t.a, nm) || tm_contains_const_name?(t.b, nm)
    t.tag == :lam && tm_contains_const_name?(t.b, nm)

  -> cont_solve_goal(goal, hints, extra_rules, depth)
    if depth > 16
      return nil
    bc = @d.beta_norm_conv(goal.concl)
    ct = dest_binop(bc.concl, "=")[1]
    q = dest_unop(ct, "∀")
    if q != nil && q.tag == :lam
      vp = dest_lam_fresh(q, goal.all_terms + [ct])
      sub = cont_solve_goal(goal.add_fix(vp[0].name, vp[0]).with_concl(vp[1]), hints, extra_rules, depth + 1)
      return sub == nil ? nil : @k.eq_mp(@k.sym(bc), @k.gen(vp[0], sub))
    imp = dest_binop(ct, "⇒")
    if imp != nil
      sub = cont_solve_goal(goal.add_hyp(fresh_hyp_name(goal), imp[0]).with_concl(imp[1]), hints, extra_rules, depth + 1)
      return sub == nil ? nil : @k.eq_mp(@k.sym(bc), @k.disch(imp[0], sub))
    cj = dest_binop(ct, "∧")
    if cj != nil
      p1 = cont_solve_goal(goal.with_concl(cj[0]), hints, extra_rules, depth + 1)
      if p1 == nil
        return nil
      p2 = cont_solve_goal(goal.with_concl(cj[1]), hints, extra_rules, depth + 1)
      if p2 == nil
        return nil
      return @k.eq_mp(@k.sym(bc), @k.conj(p1, p2))
    sp = strip_app(ct)
    if sp[0].tag == :const && sp[0].name == "continuous_within_at" && sp[1].size == 3
      within_th = @session.theorem("continuous_at.within")
      if within_th == nil
        return nil
      ca_c = @k.mk_const("continuous_at", ty_funs([ty_fun(ty_real, ty_real), ty_real], TY_BOOL_SINGLETON))
      ca_prf = cont_solve_goal(goal.with_concl(mk_apps(ca_c, [sp[1][0], sp[1][2]])), hints, extra_rules, depth + 1)
      if ca_prf == nil
        return nil
      return @k.eq_mp(@k.sym(bc), @k.mp(@k.spec(sp[1][2], @k.spec(sp[1][1], @k.spec(sp[1][0], within_th))), ca_prf))
    if sp[0].tag == :const && sp[0].name == "continuous_at" && sp[1].size == 2 && ty_eq(type_of(sp[1][1]), ty_real)
      res = cont_prove_fn(goal, hints, extra_rules, sp[1][0], sp[1][1], 0)
      return res == nil ? nil : @k.eq_mp(@k.sym(bc), res)
    nil

  -> tac_continuity(g, args)
    hints = []
    extra_rules = []
    if args.size > 0
      if args.size < 2 || args[0].text != "\[" || args[args.size - 1].text != "]"
        fail("continuity: expected optional [h1, h2, ...] hints")
      inner = arr_sub(args, 1, args.size - 2)
      if inner.size > 0
        split_top(inner, ",").each -> (item)
          if item.size == 1 && @session.k.defs.has_key?(item[0].text)
            nm = item[0].text
            extra_rules.push(make_rule(@d, @session.k.defs[nm], nm))
            @session.eqns_of(nm).each -> (eqth)
              extra_rules.push(named_equation(eqth, nm))
            if @session.theorem(nm) != nil
              hints.push(@session.theorem(nm))
          else
            th = proof_expr(g.goal, item)
            hints.push(th)
            if dest_binop(th.concl, "=") != nil
              extra_rules.push(make_rule(@d, th, "hint"))
    prf = cont_solve_goal(g.goal, hints, extra_rules, 0)
    if prf == nil
      fail("continuity failed")
    close(g, fit_concl(prf, g.goal.concl))

  # ---- push_cast tactic -----------------------------------------------------

  -> push_cast_rules
    names = [
      "cast_zero.int", "cast_one.int", "cast_add.int", "cast_mul.int", "cast_succ.int", "cast_pow.int", "cast_sum.int", "cast_mod.int", "cast_div.int",
      "cast_zero.rat", "cast_one.rat", "cast_add.rat", "cast_mul.rat", "cast_succ.rat", "cast_pow.rat", "cast_sum.rat",
      "cast_zero.real", "cast_one.real", "cast_add.real", "cast_mul.real", "cast_succ.real", "cast_pow.real", "cast_sum.real",
      "int_of_nat_add", "int_of_nat_mul", "rat_of_int_add", "rat_of_int_mul", "real_of_rat_add", "real_of_rat_mul"
    ]
    rules = []
    names.each -> (nm)
      th = @session.theorem(nm)
      if th != nil
        rules.push(make_rule(@d, th, nm))
    rules

  -> tac_push_cast(g, args)
    at = find_top(args, "at", 0)
    if at >= 0 && args.size - at - 1 == 1 && args[at + 1].text == "⊢"
      return tac_push_cast(g, arr_sub(args, 0, at))
    target_h = nil
    pre_args = args
    if at >= 0
      if args.size - at - 1 > 1
        cur = g
        k = at + 1
        while k < args.size
          if args[k].text == "⊢"
            cur = tac_push_cast(cur, arr_sub(args, 0, at))[0]
          else
            cur = tac_push_cast(cur, arr_sub(args, 0, at + 1) + [args[k]])[0]
          k += 1
        return [cur]
      target_h = args[at + 1].text
      pre_args = arr_sub(args, 0, at)
    rules = push_cast_rules
    if pre_args.size > 0
      if pre_args.size < 2 || pre_args[0].text != "\[" || pre_args[pre_args.size - 1].text != "]"
        fail("push_cast: expected optional [r1, ...] rules")
      inner = arr_sub(pre_args, 1, pre_args.size - 2)
      if inner.size > 0
        split_top(inner, ",").each -> (item)
          th = proof_expr(g.goal, item)
          rules.push(make_rule(@d, th, "hint"))
    s = Simp.new(@d, rules, {}, [])
    prover = self
    goal = g.goal
    s.discharger = ->(c) prover.try_arith_discharge(goal, c)
    if target_h != nil
      old = hyp_or_fail(goal, target_h)
      eqth = s.simp_conv(old, 0)
      newp = dest_binop(eqth.concl, "=")[1]
      ng = goal.without_hyp(target_h).add_hyp(target_h, newp)
      return refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))
    eqth = s.simp_conv(goal.concl, 0)
    rhs = dest_binop(eqth.concl, "=")[1]
    if is_const?(rhs, "⊤")
      return close(g, @d.eqt_elim(eqth))
    refine(g, [goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))

  # ---- canalytic tactic -----------------------------------------------------

  -> cana_ring_eq(goal, lhs, rhs)
    if tm_eq(lhs, rhs)
      return @k.refl(lhs)
    ty = type_of(lhs)
    if !ty_eq(ty, type_of(rhs))
      return nil
    eq_tm = mk_apps(@k.mk_const("=", ty_funs([ty, ty], TY_BOOL_SINGLETON)), [lhs, rhs])
    begin
      sub = Prover.new(@session, application_conversions)
      root = GoalRef.new(goal.with_concl(eq_tm), nil, 0)
      sub.goals = [root]
      sub.tac_ring(root)
      return root.thm
    rescue err_cr
      return nil

  -> cana_congr(f_tm, g_tm, z0, hf, v, eq_body_to_alt)
    # hf : is_canalytic_at f_tm z0, eq_body_to_alt : g_body = f_body (where g_tm = fun v => g_body, f_tm = fun v => f_body)
    congr_th = @session.theorem("is_canalytic_at.congr")
    if congr_th == nil
      return nil
    ty_c = ty_con("complex", [])
    one_r = mk_lit(Q_ONE, ty_real)
    zero_r = mk_lit(Q_ZERO, ty_real)
    lt_r = @k.mk_const("<", ty_funs([ty_real, ty_real], TY_BOOL_SINGLETON))
    hr = @d.eqt_elim(@k.compute(mk_apps(lt_r, [zero_r, one_r])))
    bf = @d.beta_norm_conv(mk_app(f_tm, v))
    bg = @d.beta_norm_conv(mk_app(g_tm, v))
    eq_fg = @k.trans(bf, @k.trans(@k.sym(eq_body_to_alt), @k.sym(bg)))
    cabs_c = @k.mk_const("complex.abs", ty_fun(ty_c, ty_real))
    csub_c = @k.mk_const("complex.sub", ty_funs([ty_c, ty_c], ty_c))
    cond_lt = mk_apps(lt_r, [mk_app(cabs_c, mk_apps(csub_c, [v, z0])), one_r])
    heq = @k.gen(v, @k.disch(cond_lt, eq_fg))
    inst = @k.spec(one_r, @k.spec(z0, @k.spec(g_tm, @k.spec(f_tm, congr_th))))
    @k.mp(@k.mp(@k.mp(inst, hr), hf), heq)

  -> cana_simp_real_cond(goal, tm)
    rules = []
    if @session.k.defs.has_key?("complex.of_real")
      rules.push(make_rule(@d, @session.k.defs["complex.of_real"], "complex.of_real"))
    prover = self
    s = Simp.new(@d, rules, @session.simp_by_head, @session.simp_general)
    s.hyp_rules = hyp_thms(goal)
    s.discharger = ->(c) prover.try_arith_discharge(goal, c)
    s.simp_conv(tm, 0)

  -> cana_prove_ne_zero(goal, hints, extra_rules, z, depth)
    if depth > 32
      return nil
    ty_c = ty_con("complex", [])
    not_c = @k.mk_const("¬", ty_fun(TY_BOOL_SINGLETON, TY_BOOL_SINGLETON))
    czero = @k.mk_const("complex.zero", ty_c)
    eq_c = @k.mk_const("=", ty_funs([ty_c, ty_c], TY_BOOL_SINGLETON))
    z_eq_0 = mk_apps(eq_c, [z, czero])
    ne_tm = mk_app(not_c, z_eq_0)
    goal.hyps.each -> (h)
      if tm_eq(h[1], ne_tm)
        return @k.assume(h[1])
    hints.each -> (th)
      if tm_eq(th.concl, ne_tm)
        return th
    zsp = strip_app(z)
    if zsp[0].tag == :const && zsp[0].name == "complex.sub" && zsp[1].size == 2
      u = zsp[1][0]
      w = zsp[1][1]
      ne_uw = mk_app(not_c, mk_apps(eq_c, [u, w]))
      ne_wu = mk_app(not_c, mk_apps(eq_c, [w, u]))
      huw = nil
      goal.hyps.each -> (h)
        if tm_eq(h[1], ne_uw)
          huw = [@k.assume(h[1]), false]
        elsif tm_eq(h[1], ne_wu)
          huw = [@k.assume(h[1]), true]
      if huw != nil
        cadd_c = @k.mk_const("complex.add", ty_funs([ty_c, ty_c], ty_c))
        r1 = cana_ring_eq(goal, u, mk_apps(cadd_c, [z, w]))
        r2 = cana_ring_eq(goal, mk_apps(cadd_c, [czero, w]), w)
        if r1 != nil && r2 != nil
          ass = @k.assume(z_eq_0)
          step_mid = @d.ap_thm(@d.ap_term(cadd_c, ass), w)
          u_eq_w = @k.trans(r1, @k.trans(step_mid, r2))
          eq_oriented = huw[1] ? @k.sym(u_eq_w) : u_eq_w
          return @k.not_intro(z_eq_0, @k.not_elim(huw[0], eq_oriented))
    if zsp[0].tag == :const && zsp[0].name == "complex.mul" && zsp[1].size == 2
      mul_nz = @session.theorem("complex.mul_ne_zero")
      if mul_nz != nil
        p1 = cana_prove_ne_zero(goal, hints, extra_rules, zsp[1][0], depth + 1)
        if p1 != nil
          p2 = cana_prove_ne_zero(goal, hints, extra_rules, zsp[1][1], depth + 1)
          if p2 != nil
            return @k.mp(@k.mp(@k.spec(zsp[1][1], @k.spec(zsp[1][0], mul_nz)), p1), p2)
    if zsp[0].tag == :const && zsp[0].name == "classical_gamma" && zsp[1].size == 2
      cg_nz = @session.theorem("classical_gamma.ne_zero_re_pos")
      if cg_nz != nil
        re_c = @k.mk_const("complex.re", ty_fun(ty_c, ty_real))
        lt_r = @k.mk_const("<", ty_funs([ty_real, ty_real], ty_bool))
        zero_r = mk_lit(Q_ZERO, ty_real)
        pre = cana_discharge_cond(goal, hints, extra_rules, mk_apps(lt_r, [zero_r, mk_app(re_c, zsp[1][1])]), depth + 1)
        if pre != nil
          return @k.mp(@k.spec(zsp[1][1], @k.spec(zsp[1][0], cg_nz)), pre)
    if zsp[0].tag == :const && zsp[0].name == "gamma" && zsp[1].size == 1
      g_nz = @session.theorem("gamma.ne_zero_of_re_pos")
      if g_nz != nil
        re_c = @k.mk_const("complex.re", ty_fun(ty_c, ty_real))
        lt_r = @k.mk_const("<", ty_funs([ty_real, ty_real], ty_bool))
        zero_r = mk_lit(Q_ZERO, ty_real)
        pre = cana_discharge_cond(goal, hints, extra_rules, mk_apps(lt_r, [zero_r, mk_app(re_c, zsp[1][0])]), depth + 1)
        if pre != nil
          return @k.mp(@k.spec(zsp[1][0], g_nz), pre)
    # Try projecting complex.re z = complex.re complex.zero and complex.im z = complex.im complex.zero -> contradiction by linarith
    re_c = @k.mk_const("complex.re", ty_fun(ty_c, ty_real))
    im_c = @k.mk_const("complex.im", ty_fun(ty_c, ty_real))
    ass0 = @k.assume(z_eq_0)
    re_raw = @d.ap_term(re_c, ass0)
    im_raw = @d.ap_term(im_c, ass0)
    re_s = cana_simp_real_cond(goal, re_raw.concl)
    im_s = cana_simp_real_cond(goal, im_raw.concl)
    re_th = @k.eq_mp(re_s, re_raw)
    im_th = @k.eq_mp(im_s, im_raw)
    extra = [re_th, im_th] + hints
    goal.hyps.each -> (h)
      hs_eq = cana_simp_real_cond(goal, h[1])
      if !tm_eq(h[1], dest_binop(hs_eq.concl, "=")[1])
        extra.push(@k.eq_mp(hs_eq, @k.assume(h[1])))
    saved_nl = @nl_mode
    @nl_mode = true
    bot_prf = nil
    begin
      bot_prf = arith_prove(goal.with_concl(@k.false_tm), extra)
    rescue err_nz
      bot_prf = nil
    @nl_mode = saved_nl
    bot_prf == nil ? nil : @k.not_intro(z_eq_0, bot_prf)

  -> cana_discharge_cond(goal, hints, extra_rules, cond, depth)
    if depth > 32
      return nil
    goal.hyps.each -> (h)
      if tm_eq(h[1], cond)
        return @k.assume(h[1])
    hints.each -> (th)
      if tm_eq(th.concl, cond)
        return th
    sp = strip_app(cond)
    if sp[0].tag == :const && sp[0].name == "is_canalytic_at" && sp[1].size == 2
      return cana_solve_goal(goal.with_concl(cond), hints, extra_rules, depth + 1)
    if sp[0].tag == :const && sp[0].name == "dchar.valid" && sp[1].size == 1
      arg = sp[1][0]
      if arg.tag == :const && arg.name == "dchar.trivial_one"
        t1 = @session.theorem("dchar.trivial_one_valid")
        if t1 != nil
          return t1
      asp = strip_app(arg)
      if asp[0].tag == :const && asp[0].name == "dchar.inv" && asp[1].size == 1
        iv_th = @session.theorem("dchar.inv_valid")
        if iv_th != nil
          sub_v = cana_discharge_cond(goal, hints, extra_rules, mk_app(sp[0], asp[1][0]), depth + 1)
          if sub_v != nil
            return @k.mp(@k.spec(asp[1][0], iv_th), sub_v)
      if asp[0].tag == :const && asp[0].name == "dchar.prim" && asp[1].size == 1
        ps_th = @session.theorem("dchar.prim_spec")
        if ps_th != nil && @session.k.defs.has_key?("dchar.is_primitive")
          sub_v = cana_discharge_cond(goal, hints, extra_rules, mk_app(sp[0], asp[1][0]), depth + 1)
          if sub_v != nil
            prim_th = @k.conj1(@k.mp(@k.spec(asp[1][0], ps_th), sub_v))
            u_eq = Simp.new(@d, [make_rule(@d, @session.k.defs["dchar.is_primitive"], "dchar.is_primitive")]).simp_conv(prim_th.concl, 0)
            u_rhs = dest_binop(u_eq.concl, "=")[1]
            if dest_binop(u_rhs, "∧") != nil
              return @k.conj1(@k.eq_mp(u_eq, prim_th))
    neg_inner = dest_unop(cond, "¬")
    if neg_inner != nil
      eqp = dest_binop(neg_inner, "=")
      if eqp != nil && ty_eq(type_of(eqp[0]), ty_con("complex", [])) && is_const?(eqp[1], "complex.zero")
        nz = cana_prove_ne_zero(goal, hints, extra_rules, eqp[0], depth + 1)
        if nz != nil
          return nz
    cond_s = cana_simp_real_cond(goal, cond)
    cond_rhs = dest_binop(cond_s.concl, "=")[1]
    extra = [] + hints
    pos_facts(cond_rhs, extra, {})
    goal.hyps.each -> (h)
      hs_eq = cana_simp_real_cond(goal, h[1])
      if !tm_eq(h[1], dest_binop(hs_eq.concl, "=")[1])
        extra.push(@k.eq_mp(hs_eq, @k.assume(h[1])))
    saved_nl = @nl_mode
    @nl_mode = true
    res = nil
    begin
      res = arith_prove(goal.with_concl(cond_rhs), extra)
    rescue err_ca
      res = nil
    @nl_mode = saved_nl
    res == nil ? nil : @k.eq_mp(@k.sym(cond_s), res)

  -> cana_try_thm(goal, hints, extra_rules, th, v, body, z0, depth)
    if th == nil || th.concl.tv
      return nil
    ty_c = ty_con("complex", [])
    avoid = goal.all_terms + [v, body, z0, th.concl]
    steps = []
    qvars = []
    pvars = {}
    cur = th.concl
    while true
      q = dest_unop(cur, "∀")
      if q != nil && q.tag == :lam
        vp = dest_lam_fresh(q, avoid)
        avoid.push(vp[0])
        qvars.push(vp[0])
        pvars[vp[0].vkey] = true
        steps.push([:all, vp[0]])
        cur = vp[1]
      else
        imp = dest_binop(cur, "⇒")
        if imp != nil
          steps.push([:imp])
          cur = imp[1]
        else
          break
    leaves = []
    stk = [[[], cur]]
    while stk.size > 0
      it = stk.pop
      cj = dest_binop(it[1], "∧")
      if cj != nil
        stk.push([it[0] + [false], cj[1]])
        stk.push([it[0] + [true], cj[0]])
      else
        leaves.push(it)
    li = 0
    while li < leaves.size
      path = leaves[li][0]
      ltm = leaves[li][1]
      lsp = strip_app(ltm)
      if lsp[0].tag == :const && lsp[0].name == "is_canalytic_at" && lsp[1].size == 2 && ty_eq(type_of(lsp[1][1]), ty_c)
        g_pat = lsp[1][0]
        pt_pat = lsp[1][1]
        app_pat = @d.beta_norm_term(mk_app(g_pat, v))
        mat = Matcher.new(pvars, {})
        if mat.m(pt_pat, z0, 0, true) && mat.m(app_pat, body, 0, true)
          ok = true
          qi = 0
          while qi < qvars.size
            bval = mat.tm[qvars[qi].vkey]
            if bval == nil || tm_free_in?(v, bval)
              ok = false
              break
            qi += 1
          if ok
            inst_th = th
            si = 0
            while si < steps.size
              st = steps[si]
              if st[0] == :all
                inst_th = @k.spec(mat.tm[st[1].vkey], inst_th)
              else
                imp_now = dest_binop(@d.beta_norm_term(inst_th.concl), "⇒")
                if imp_now == nil
                  ok = false
                  break
                inst_th = @d.beta_norm_thm(inst_th)
                cprf = cana_discharge_cond(goal, hints, extra_rules, imp_now[0], depth + 1)
                if cprf == nil
                  ok = false
                  break
                inst_th = @k.mp(inst_th, cprf)
              si += 1
            if ok
              inst_th = @d.beta_norm_thm(inst_th)
              pi = 0
              while pi < path.size
                inst_th = path[pi] ? @k.conj1(inst_th) : @k.conj2(inst_th)
                pi += 1
              f_lam = mk_lam(v, body)
              g_inst = strip_app(inst_th.concl)[1][0]
              if tm_eq(g_inst, f_lam)
                return inst_th
              return cana_congr(g_inst, f_lam, z0, inst_th, v, @k.refl(body))
      li += 1
    nil

  -> cana_from_hyps_and_lib(goal, hints, extra_rules, v, body, z0, depth)
    hi = 0
    while hi < hints.size
      r = cana_try_thm(goal, hints, extra_rules, hints[hi], v, body, z0, depth)
      if r != nil
        return r
      hi += 1
    gi = goal.hyps.size - 1
    while gi >= 0
      hth = @k.assume(goal.hyps[gi][1])
      r = cana_try_thm(goal, hints, extra_rules, hth, v, body, z0, depth)
      if r != nil
        return r
      gi -= 1
    lib_names = [
      "Z_reg.is_canalytic_at_re_pos",
      "classical_L_reg.is_canalytic_at_re_pos",
      "classical_gamma.is_canalytic_at_re_pos",
      "gamma.is_canalytic_at_re_pos",
      "riemann_theta_tail_int.is_canalytic_at",
      "classical_Lambda_triv_reg.is_canalytic_at_re_pos",
      "nt_mellin_int.is_canalytic_at",
      "classical_Lambda_nt.is_canalytic_at",
      "induced_euler_ratio.is_canalytic_at",
      "D_chi.is_canalytic_at_re_pos",
      "N_base.is_canalytic_at_re_pos",
      "finite_G_mellin.is_canalytic_at",
      "cpow_real.is_canalytic_at_linear"
    ]
    li = 0
    while li < lib_names.size
      lth = @session.theorem(lib_names[li])
      if lth != nil
        r = cana_try_thm(goal, hints, extra_rules, lth, v, body, z0, depth)
        if r != nil
          return r
      li += 1
    nil

  -> cana_prove_fn(goal, hints, extra_rules, f_tm, z0, depth)
    ty_c = ty_con("complex", [])
    if f_tm.tag == :lam
      vp = dest_lam_fresh(f_tm, goal.all_terms + [f_tm, z0])
      return cana_prove(goal, hints, extra_rules, vp[0], vp[1], z0, depth)
    v = mk_var(fresh_name("s", goal.all_terms + [f_tm, z0]), ty_c)
    body = mk_app(f_tm, v)
    pf = cana_prove(goal, hints, extra_rules, v, body, z0, depth)
    if pf == nil
      return nil
    cana_congr(mk_lam(v, body), f_tm, z0, pf, v, @k.refl(body))

  -> cana_prove(goal, hints, extra_rules, v, body, z0, depth)
    if depth > 24
      return nil
    bc = @d.beta_norm_conv(body)
    rhs = dest_binop(bc.concl, "=")[1]
    pf = cana_prove_norm(goal, hints, extra_rules, v, rhs, z0, depth)
    if pf == nil
      return nil
    if tm_eq(body, rhs)
      return pf
    cana_congr(mk_lam(v, rhs), mk_lam(v, body), z0, pf, v, bc)

  -> cana_prove_norm(goal, hints, extra_rules, v, body, z0, depth)
    if depth > 24
      return nil
    ty_c = ty_con("complex", [])
    if !tm_free_in?(v, body)
      cth = @session.theorem("is_canalytic_at.const")
      return cth == nil ? nil : @k.spec(z0, @k.spec(body, cth))
    if tm_eq(body, v)
      ith = @session.theorem("is_canalytic_at.id")
      return ith == nil ? nil : @k.spec(z0, ith)
    from_h = cana_from_hyps_and_lib(goal, hints, extra_rules, v, body, z0, depth)
    if from_h != nil
      return from_h
    sp = strip_app(body)
    if sp[0].tag == :const
      nm = sp[0].name
      if nm == "complex.neg" && sp[1].size == 1
        nth = @session.theorem("is_canalytic_at.neg")
        if nth != nil
          pa = cana_prove(goal, hints, extra_rules, v, sp[1][0], z0, depth + 1)
          if pa != nil
            return @d.beta_norm_thm(@k.mp(@k.spec(z0, @k.spec(mk_lam(v, sp[1][0]), nth)), pa))
      elsif (nm == "complex.add" || nm == "complex.sub" || nm == "complex.mul") && sp[1].size == 2
        a = sp[1][0]
        b = sp[1][1]
        if nm == "complex.mul" && !tm_free_in?(v, a) && @session.theorem("is_canalytic_at.const_mul") != nil
          cmth = @session.theorem("is_canalytic_at.const_mul")
          pb = cana_prove(goal, hints, extra_rules, v, b, z0, depth + 1)
          if pb != nil
            return @d.beta_norm_thm(@k.mp(@k.spec(z0, @k.spec(mk_lam(v, b), @k.spec(a, cmth))), pb))
        lem_nm = nm == "complex.add" ? "is_canalytic_at.add" : (nm == "complex.sub" ? "is_canalytic_at.sub" : "is_canalytic_at.mul")
        lem = @session.theorem(lem_nm)
        if lem != nil
          pa = cana_prove(goal, hints, extra_rules, v, a, z0, depth + 1)
          if pa != nil
            pb = cana_prove(goal, hints, extra_rules, v, b, z0, depth + 1)
            if pb != nil
              return @d.beta_norm_thm(@k.mp(@k.mp(@k.spec(z0, @k.spec(mk_lam(v, b), @k.spec(mk_lam(v, a), lem))), pa), pb))
      elsif nm == "complex.smul" && sp[1].size == 2 && !tm_free_in?(v, sp[1][0])
        of_r = @k.mk_const("complex.of_real", ty_fun(ty_real, ty_c))
        cmul_c = @k.mk_const("complex.mul", ty_funs([ty_c, ty_c], ty_c))
        alt = mk_apps(cmul_c, [mk_app(of_r, sp[1][0]), sp[1][1]])
        req = cana_ring_eq(goal, body, alt)
        if req != nil
          p_alt = cana_prove_norm(goal, hints, extra_rules, v, alt, z0, depth + 1)
          if p_alt != nil
            return cana_congr(mk_lam(v, alt), mk_lam(v, body), z0, p_alt, v, req)
      elsif nm == "complex.inv" && sp[1].size == 1
        inv_th = @session.theorem("is_canalytic_at.inv")
        if inv_th != nil
          a = sp[1][0]
          az0 = @d.beta_norm_term(tm_subst(a, {v.vkey => z0}))
          hne = cana_prove_ne_zero(goal, hints, extra_rules, az0, 0)
          if hne != nil
            pa = cana_prove(goal, hints, extra_rules, v, a, z0, depth + 1)
            if pa != nil
              inst_inv = @d.beta_norm_thm(@k.spec(z0, @k.spec(mk_lam(v, a), inv_th)))
              return @k.mp(@k.mp(inst_inv, pa), hne)
      elsif nm == "cderiv_at" && sp[1].size == 2 && tm_eq(sp[1][1], v) && !tm_free_in?(v, sp[1][0])
        cd_th = @session.theorem("is_canalytic_at.cderiv_at")
        if cd_th != nil
          pf_inner = cana_prove_fn(goal, hints, extra_rules, sp[1][0], z0, depth + 1)
          if pf_inner != nil
            cd_res = @k.conj2(@k.mp(@k.spec(z0, @k.spec(sp[1][0], cd_th)), pf_inner))
            return cana_congr(mk_app(@k.mk_const("cderiv_at", ty_funs([ty_fun(ty_c, ty_c), ty_c], ty_c)), sp[1][0]), mk_lam(v, body), z0, cd_res, v, @k.refl(body))
      elsif nm == "cpow_real" && sp[1].size == 2 && !tm_free_in?(v, sp[1][0])
        cp_th = @session.theorem("cpow_real.is_canalytic_at_linear")
        if cp_th != nil
          c_base = sp[1][0]
          w_exp = sp[1][1]
          csmul_c = @k.mk_const("complex.smul", ty_funs([ty_real, ty_c], ty_c))
          cadd_c = @k.mk_const("complex.add", ty_funs([ty_c, ty_c], ty_c))
          czero = @k.mk_const("complex.zero", ty_c)
          a_sc = nil
          b_off = nil
          wsp = strip_app(w_exp)
          if tm_eq(w_exp, v)
            a_sc = mk_lit(Q_ONE, ty_real)
            b_off = czero
          elsif wsp[0].tag == :const && wsp[0].name == "complex.neg" && wsp[1].size == 1 && tm_eq(wsp[1][0], v)
            a_sc = mk_app(@k.mk_const("neg", ty_fun(ty_real, ty_real)), mk_lit(Q_ONE, ty_real))
            b_off = czero
          elsif wsp[0].tag == :const && wsp[0].name == "complex.sub" && wsp[1].size == 2 && !tm_free_in?(v, wsp[1][0]) && tm_eq(wsp[1][1], v)
            a_sc = mk_app(@k.mk_const("neg", ty_fun(ty_real, ty_real)), mk_lit(Q_ONE, ty_real))
            b_off = wsp[1][0]
          elsif wsp[0].tag == :const && wsp[0].name == "complex.smul" && wsp[1].size == 2 && !tm_free_in?(v, wsp[1][0]) && tm_eq(wsp[1][1], v)
            a_sc = wsp[1][0]
            b_off = czero
          if a_sc != nil
            aff = mk_apps(cadd_c, [mk_apps(csmul_c, [a_sc, v]), b_off])
            weq = cana_ring_eq(goal, w_exp, aff)
            if weq != nil
              alt = mk_apps(sp[0], [c_base, aff])
              beq = @d.ap_term(mk_app(sp[0], c_base), weq)
              p_alt = cana_from_hyps_and_lib(goal, hints, extra_rules, v, alt, z0, depth + 1)
              if p_alt != nil
                return cana_congr(mk_lam(v, alt), mk_lam(v, body), z0, p_alt, v, beq)
    # Positive affine pullback: f(a_sc • v + b_off)
    if body.tag == :app && !tm_free_in?(v, body.a) && tm_free_in?(v, body.b)
      asp = strip_app(body.b)
      if asp[0].tag == :const && asp[0].name == "complex.add" && asp[1].size == 2 && !tm_free_in?(v, asp[1][1])
        smsp = strip_app(asp[1][0])
        if smsp[0].tag == :const && smsp[0].name == "complex.smul" && smsp[1].size == 2 && !tm_free_in?(v, smsp[1][0]) && tm_eq(smsp[1][1], v)
          aff_th = @session.theorem("is_canalytic_at.comp_pos_affine")
          if aff_th != nil
            a_sc = smsp[1][0]
            b_off = asp[1][1]
            lt_r = @k.mk_const("<", ty_funs([ty_real, ty_real], ty_bool))
            pa_pos = cana_discharge_cond(goal, hints, extra_rules, mk_apps(lt_r, [mk_lit(Q_ZERO, ty_real), a_sc]), depth + 1)
            if pa_pos != nil
              pt_img = @d.beta_norm_term(tm_subst(body.b, {v.vkey => z0}))
              pf_out = cana_prove_fn(goal, hints, extra_rules, body.a, pt_img, depth + 1)
              if pf_out != nil
                inst_aff = @d.beta_norm_thm(@k.spec(z0, @k.spec(b_off, @k.spec(a_sc, @k.spec(body.a, aff_th)))))
                return @k.mp(@k.mp(inst_aff, pa_pos), pf_out)
    # Fallback: simplify via extra_rules + local set equations + if_pos/if_neg
    set_rules = [] + extra_rules
    if @session.theorem("if_pos") != nil
      set_rules.push(make_rule(@d, @session.theorem("if_pos"), "if_pos"))
    if @session.theorem("if_neg") != nil
      set_rules.push(make_rule(@d, @session.theorem("if_neg"), "if_neg"))
    goal.hyps.each -> (h)
      eq = dest_binop(h[1], "=")
      if eq != nil && (eq[0].tag == :var || (eq[0].tag == :const && @session.k.defs.has_key?(eq[0].name))) && !tm_free_in?(v, eq[0])
        set_rules.push(make_rule(@d, @k.assume(h[1]), "local_eq", false))
    prover = self
    s_fb = Simp.new(@d, set_rules, @session.simp_by_head, @session.simp_general)
    s_fb.hyp_rules = hyp_thms(goal)
    s_fb.discharger = ->(c) prover.try_arith_discharge(goal, c)
    fb_eq = s_fb.simp_conv(body, 0)
    fb_rhs = @d.beta_norm_term(dest_binop(fb_eq.concl, "=")[1])
    if !tm_eq(body, fb_rhs)
      ba_fb = @d.beta_norm_conv(dest_binop(fb_eq.concl, "=")[1])
      p_fb = cana_prove_norm(goal, hints, extra_rules, v, fb_rhs, z0, depth + 1)
      if p_fb != nil
        return cana_congr(mk_lam(v, fb_rhs), mk_lam(v, body), z0, p_fb, v, @k.trans(fb_eq, ba_fb))
    nil

  -> cana_solve_goal(goal, hints, extra_rules, depth)
    if depth > 16
      return nil
    bc = @d.beta_norm_conv(goal.concl)
    ct = dest_binop(bc.concl, "=")[1]
    q = dest_unop(ct, "∀")
    if q != nil && q.tag == :lam
      vp = dest_lam_fresh(q, goal.all_terms + [ct])
      sub = cana_solve_goal(goal.add_fix(vp[0].name, vp[0]).with_concl(vp[1]), hints, extra_rules, depth + 1)
      return sub == nil ? nil : @k.eq_mp(@k.sym(bc), @k.gen(vp[0], sub))
    imp = dest_binop(ct, "⇒")
    if imp != nil
      sub = cana_solve_goal(goal.add_hyp(fresh_hyp_name(goal), imp[0]).with_concl(imp[1]), hints, extra_rules, depth + 1)
      return sub == nil ? nil : @k.eq_mp(@k.sym(bc), @k.disch(imp[0], sub))
    cj = dest_binop(ct, "∧")
    if cj != nil
      p1 = cana_solve_goal(goal.with_concl(cj[0]), hints, extra_rules, depth + 1)
      if p1 == nil
        return nil
      p2 = cana_solve_goal(goal.with_concl(cj[1]), hints, extra_rules, depth + 1)
      if p2 == nil
        return nil
      return @k.eq_mp(@k.sym(bc), @k.conj(p1, p2))
    sp = strip_app(ct)
    if sp[0].tag == :const && sp[0].name == "is_canalytic_at" && sp[1].size == 2 && ty_eq(type_of(sp[1][1]), ty_con("complex", []))
      res = cana_prove_fn(goal, hints, extra_rules, sp[1][0], sp[1][1], 0)
      return res == nil ? nil : @k.eq_mp(@k.sym(bc), res)
    nil

  -> tac_canalytic(g, args)
    hints = []
    extra_rules = []
    if args.size > 0
      if args.size < 2 || args[0].text != "\[" || args[args.size - 1].text != "]"
        fail("canalytic: expected optional [h1, h2, ...] hints")
      inner = arr_sub(args, 1, args.size - 2)
      if inner.size > 0
        split_top(inner, ",").each -> (item)
          if item.size == 1 && @session.k.defs.has_key?(item[0].text)
            nm = item[0].text
            extra_rules.push(make_rule(@d, @session.k.defs[nm], nm))
            @session.eqns_of(nm).each -> (eqth)
              extra_rules.push(named_equation(eqth, nm))
            if @session.theorem(nm) != nil
              hints.push(@session.theorem(nm))
          else
            th = proof_expr(g.goal, item)
            hints.push(th)
            if dest_binop(th.concl, "=") != nil
              extra_rules.push(make_rule(@d, th, "hint"))
    prf = cana_solve_goal(g.goal, hints, extra_rules, 0)
    if prf == nil
      fail("canalytic failed")
    close(g, fit_concl(prf, g.goal.concl))

  # Lift a polynomial identity through matching applications and binders.
  # A fresh variable opens both functions; eta also admits an unapplied side.
  -> ring_congruence(left, right, fuel, try_ring = true)
    if tm_eq(left, right)
      return @k.refl(left)
    fuel[0] -= 1
    if fuel[0] <= 0 || !ty_eq(type_of(left), type_of(right))
      return nil
    if left.tag == :lam || right.tag == :lam
      v = mk_var(fresh_name("x", [left, right]), type_of(left).dom)
      a = left.tag == :lam ? tm_instantiate(left.b, v, 0) : mk_app(left, v)
      b = right.tag == :lam ? tm_instantiate(right.b, v, 0) : mk_app(right, v)
      body = ring_congruence(a, b, fuel)
      if body == nil
        return nil
      return funext_proof(left, right, v, body)
    if left.tag == :app && right.tag == :app && tm_eq(strip_app(left)[0], strip_app(right)[0])
      head_eq = ring_congruence(left.a, right.a, fuel)
      if head_eq != nil
        arg = ring_congruence(left.b, right.b, fuel)
        if arg != nil
          return @k.mk_comb(head_eq, arg)
    if try_ring && fuel[0] > 0 && numeric_type?(type_of(left))
      begin
        recurrence_ring_cost(left, type_of(left).name, fuel)
        recurrence_ring_cost(right, type_of(right).name, fuel)
        return @k.ring_eq(left, right)
      rescue err
        return nil
    nil

  # A polynomial certificate written as a sum of scaled equality proofs.
  # Subtraction reverses an equality, so it also works over ℕ without using
  # truncated subtraction. Every leaf and coefficient is checked before use.
  -> combination_binop(op, ty, a, b)
    operator = @k.mk_const(op, ty_funs([ty, ty], ty))
    @k.mk_comb(@k.mk_comb(@k.refl(operator), a), b)

  -> combination_proof(goal, e, ty)
    if e.kind == :unop && e.s == "neg"
      return @k.sym(combination_proof(goal, e.kids[0], ty))
    if e.kind == :binop && (e.s == "+" || e.s == "-")
      a = combination_proof(goal, e.kids[0], ty)
      b = combination_proof(goal, e.kids[1], ty)
      if e.s == "-"
        b = @k.sym(b)
      return combination_binop("+", ty, a, b)
    if e.kind == :binop && e.s == "*"
      coefficient = nil
      begin
        coefficient = elab_term_ast(goal, e.kids[0], ty)
      rescue err
        0
      if coefficient != nil
        return combination_binop("*", ty, @k.refl(coefficient), combination_proof(goal, e.kids[1], ty))
      coefficient = elab_term_ast(goal, e.kids[1], ty)
      return combination_binop("*", ty, combination_proof(goal, e.kids[0], ty), @k.refl(coefficient))
    th = proof_ast(goal, e)
    th = fit_concl(th, @d.beta_eta_term(th.concl))
    eq = dest_binop(th.concl, "=")
    if eq == nil || !ty_eq(type_of(eq[0]), ty)
      fail("linear_combination: expected an equality at " + ty_show(ty))
    th

  -> tac_linear_combination(g, args)
    if args.size == 0
      return tac_ring(g)
    target = dest_binop(@d.beta_eta_term(g.goal.concl), "=")
    if target == nil || !numeric_type?(type_of(target[0]))
      fail("linear_combination: goal must be an equality over ℕ, ℤ, ℚ or ℝ")
    ty = type_of(target[0])
    th = combination_proof(g.goal, parse_expr_toks(args), ty)
    th = fit_concl(th, @d.beta_eta_term(th.concl))
    close(g, fit(g, finish_combination(target, ty, th)))

  -> finish_combination(target, ty, th)
    eq = dest_binop(th.concl, "=")
    add = @k.mk_const("+", ty_funs([ty, ty], ty))
    if ty_eq(ty, ty_nat)
      # Ring checks the proposed combination; arithmetic only cancels the
      # common additive term. It sees this certificate, not unrelated hypotheses.
      left = mk_apps(add, [target[0], eq[1]])
      right = mk_apps(add, [target[1], eq[0]])
      balanced = @k.trans(@k.ring_eq(left, right), @k.mk_comb(@k.refl(mk_app(add, target[1])), th))
      le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
      forward = mk_apps(le, [target[0], target[1]])
      backward = mk_apps(le, [target[1], target[0]])
      a = arith_prove_core(Goal.new([], [], forward), [balanced])
      b = arith_prove_core(Goal.new([], [], backward), [balanced])
      anti = @session.lemma_at("le_antisymm", ty)
      result = @k.mp(@k.mp(@k.spec(target[1], @k.spec(target[0], anti)), a), b)
    else
      # A - B = L - R gives A = L + (B - R) = R + (B - R) = B.
      sub = @k.mk_const("-", ty_funs([ty, ty], ty))
      pad = mk_apps(sub, [target[1], eq[1]])
      shifted = combination_binop("+", ty, th, @k.refl(pad))
      ends = dest_binop(shifted.concl, "=")
      result = @k.trans(@k.trans(@k.ring_eq(target[0], ends[0]), shifted), @k.ring_eq(ends[1], target[1]))
    result

  -> auto_polynomial_equation(goal, target, hints)
    if !numeric_type?(type_of(target[0])) || goal.hyps.size + hints.size > 16
      return nil
    ty = type_of(target[0])
    facts = []
    hints.each -> (hint)
      eq = @k.dest_eq(hint.concl)
      if eq != nil && ty_eq(type_of(eq[0]), ty)
        facts.push(hint)
    goal.hyps.each -> (h)
      eq = @k.dest_eq(h[1])
      if eq != nil && ty_eq(type_of(eq[0]), ty)
        facts.push(@k.assume(h[1]))
    if facts.empty?() || facts.size > 8
      return nil
    begin
      PolynomialReduction.new(ty).prove(self, target, facts)
    rescue unsupported
      nil

  # Select an equality from each arm. The checked cross-sum lemma is the
  # zero-product law written without subtraction, including on ℕ.
  -> polynomial_case_guards(term, out)
    if out.size == 2
      return out
    pair = dest_binop(term, "∧")
    if pair != nil
      polynomial_case_guards(pair[0], out)
      polynomial_case_guards(pair[1], out)
    else
      eq = @k.dest_eq(term)
      if eq != nil && numeric_type?(type_of(eq[0])) && !hyps_has?(out, term)
        out.push(term)
    out

  -> polynomial_case_leaf(goal, leaf, guard, hints)
    if tm_eq(leaf, guard.concl)
      return guard
    local = goal.with_concl(leaf)
    fact = find_assumption(local)
    if fact == nil
      fact = hints.find -> (th) tm_eq(th.concl, leaf)
    if fact != nil
      return fact
    if !comparison?(leaf)
      fail("polynomial cases: unresolved branch")
    facts = [guard] + hints
    begin
      return linarith_proof(local, facts)
    rescue missed
      eq = @k.dest_eq(leaf)
      if eq != nil
        proof = auto_polynomial_equation(local, eq, facts)
        if proof != nil
          return proof
      raise missed

  -> auto_polynomial_cases(goal, arms, hints)
    if goal.hyps.size + hints.size > 16 || !auto_small_term?(goal.concl, [192])
      return nil
    lefts = polynomial_case_guards(arms[0], [])
    rights = polynomial_case_guards(arms[1], [])
    lefts.each -> (left)
      a = @k.dest_eq(left)
      ty = type_of(a[0])
      rule = auto_loaded_rule("eq_or_eq_of_cross_sum." + ty.name)
      if rule == nil
        next
      rights.each -> (right)
        b = @k.dest_eq(right)
        if !ty_eq(ty, type_of(b[0]))
          next
        begin
          law = @k.spec(b[1], @k.spec(b[0], @k.spec(a[1], @k.spec(a[0], rule))))
          cross = dest_binop(law.concl, "⇒")[0]
          local = goal.with_concl(cross)
          proof = find_assumption(local)
          if proof == nil
            proof = auto_polynomial_equation(local, @k.dest_eq(cross), hints)
          if proof != nil
            split = @k.mp(law, proof)
            if !tm_eq(split.concl, @k.bin("∨", left, right))
              next
            if tm_eq(split.concl, goal.concl)
              return split
            lhs = @k.assume(left)
            rhs = @k.assume(right)
            yes = prove_conjuncts(arms[0], -> (leaf) polynomial_case_leaf(goal, leaf, lhs, hints))
            no = prove_conjuncts(arms[1], -> (leaf) polynomial_case_leaf(goal, leaf, rhs, hints))
            return @k.disj_cases(split, @k.disj1(yes, arms[1]), @k.disj2(arms[0], no))
        rescue missed
          0
    nil

  # Linear arithmetic over hypotheses and the negated goal.
  -> tac_linarith(g, args, with_casts = true)
    goal = g.goal
    extra = []
    if args.size > 0
      inner = args
      if inner[0].text == "\["
        inner = arr_sub(inner, 1, inner.size - 2)
      split_top(inner, ",").each -> (p)
        if p.size > 0
          extra.push(proof_expr(goal, p))
    solve = -> (c) linarith_leaf(goal.with_concl(c), extra, with_casts)
    close(g, prove_conjuncts(goal.concl, solve))

  -> linarith_leaf(goal, extra, with_casts)
    begin
      return linarith_proof(goal, extra)
    rescue e
      if !with_casts
        raise e
      proof = cast_arithmetic_proof(goal, extra)
      if proof == nil
        raise e
      return proof

  # Put comparisons in a common domain already present in the problem.
  # Every transport is a checked equivalence. In particular a natural
  # subtraction remains inside its cast and a rational need never be rounded.
  -> cast_arithmetic_proof(goal, extra)
    if !goal.concl.has_widening_cast? && !goal.hyps.any?(-> (h) h[1].has_widening_cast?)
      if !extra.any?(-> (th) th.concl.has_widening_cast?)
        return nil
    negated = dest_unop(goal.concl, "¬")
    if negated != nil
      refutation = cast_arithmetic_proof(goal.with_concl(@k.false_tm), extra + [@k.assume(negated)])
      return refutation == nil ? nil : @k.not_intro(negated, refutation)
    target = dest_cmp_rel(goal.concl)
    if goal.concl.op != OP_FALSE && (target == nil || !numeric_type?(type_of(target[1])))
      return nil
    facts = []
    goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), facts, true)
    extra.each -> (th) normalize_comparisons(th, facts, true)
    domain = target == nil ? TY_NAT_SINGLETON : type_of(target[1])
    facts.each -> (th)
      cmp = th.concl.a.op == OP_NOT ? th.concl.b : th.concl
      ty = type_of(cmp.a.b)
      if th.concl.has_widening_cast? && @session.elab.coercion(domain, ty) != nil
        domain = ty
    # Reuse just the cast homomorphisms. Simplifying the comparison itself
    # with the full simp set would immediately strip both casts again.
    rules = []
    ["int_of_nat", "rat_of_int", "real_of_rat"].each -> (cast)
      bucket = @session.simp_by_head[cast]
      if bucket != nil
        bucket.each -> (rule)
          if (rule.name == cast + "_add" || rule.name == cast + "_mul") && rule.th.tags.size == 0
            rules.push(rule)
    folder = Simp.new(@d, rules)
    begin
      eq = target == nil ? @k.refl(goal.concl) : comparison_at_type(goal.concl, domain, folder)
      if eq == nil
        return nil
      conclusion = eq.concl.b
      changed = !tm_eq(goal.concl, conclusion)
      if conclusion.op == OP_TRUE
        return @k.eq_mp(@k.sym(eq), @k.truth)
      # Preserve the unit gap of strict natural and integer bounds on widening.
      gaps = []
      facts.each -> (th)
        if th.concl.a.tag == :app && th.concl.a.a.op == OP_LT
          ty = type_of(th.concl.a.b)
          if ty == domain || (ty != TY_NAT_SINGLETON && ty != TY_INT_SINGLETON)
            next
          bound = integer_strengthen([th], ty)[0]
          if bound != th
            gaps.push(bound)
      lifted = []
      (facts + gaps).each -> (th)
        conv = comparison_at_type(th.concl, domain, folder)
        if conv != nil
          fact = @k.eq_mp(conv, th)
          changed = changed || !tm_eq(fact.concl, th.concl)
          if tm_eq(fact.concl, conclusion)
            return @k.eq_mp(@k.sym(eq), fact)
          lifted.push(fact)
      if !changed
        return nil
      th = Prover.new(@session).linarith_proof(Goal.new(goal.fixes, [], conclusion), lifted)
      return @k.eq_mp(@k.sym(eq), th)
    rescue e
      nil

  -> comparison_at_type(term, domain, folder)
    body = dest_unop(term, "¬")
    if body != nil
      eq = comparison_at_type(body, domain, folder)
      return eq == nil ? nil : @k.mk_comb(@k.refl(term.a), eq)
    cmp = dest_cmp_rel(term)
    ty = type_of(cmp[1])
    if ty == domain
      return folder.simp_conv(term)
    if @session.elab.coercion(ty, domain) == nil
      return nil
    prefix = ty == TY_NAT_SINGLETON ? "cast_" : ty.name + "_cast_"
    suffix = {"≤" => "le", "<" => "lt", "=" => "inj"}[cmp[0]]
    lem = @session.theorems[prefix + suffix + "." + domain.name]
    if lem == nil || lem.tags.size != 0
      return nil
    eq = @k.sym(@k.spec(cmp[2], @k.spec(cmp[1], lem)))
    @k.trans(eq, folder.simp_conv(eq.concl.b))

  -> linarith_proof(goal, extra)
    c = goal.concl
    if @omega_mode
      pq = dest_binop(c, "∨")
      if pq != nil
        begin
          neg_l = @k.neg_tm(pq[0])
          rhs_th = linarith_proof(Goal.new(goal.fixes, goal.hyps + [["_not_or_l", neg_l]], pq[1]), extra)
          em = @k.excluded_middle(pq[0])
          return @k.disj_cases(em, @k.disj1(@k.assume(pq[0]), pq[1]), @k.disj2(pq[0], rhs_th))
        rescue _e
          0
    e = dest_binop(c, "=")
    if e != nil && numeric_type?(type_of(e[0]))
      # prove ≤ both ways then antisymmetry
      begin
        ty = type_of(e[0])
        le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
        a = mk_apps(le, [e[0], e[1]])
        b = mk_apps(le, [e[1], e[0]])
        t1 = arith_prove(goal.with_concl(a), extra)
        t2 = arith_prove(goal.with_concl(b), extra)
        anti = @session.lemma_at("le_antisymm", ty)
        return @k.mp(@k.mp(@k.spec(e[1], @k.spec(e[0], anti)), t1), t2)
      rescue eq_err
        if @omega_mode
          res_th = omega_residue_fallback(goal, extra)
          if res_th != nil
            return res_th
        raise eq_err
    begin
      arith_prove(goal, extra)
    rescue ord_err
      if @omega_mode
        res_th = omega_residue_fallback(goal, extra)
        if res_th != nil
          return res_th
      raise ord_err

  -> omega_residue_fallback(goal, extra)
    begin
      facts = []
      goal.hyps.each -> (h)
        facts.push(@k.assume(h[1]))
      extra.each -> (th)
        facts.push(th)
      target = literal_residue(goal.concl)
      r = auto_residue_facts(goal.concl, target, facts)
      if r != nil
        return r
      if goal.concl.op != OP_FALSE
        neg_g = @k.neg_tm(goal.concl)
        bot = auto_residue_facts(@k.false_tm, nil, facts + [@k.assume(neg_g)])
        if bot != nil
          return classical_by_contra(goal.concl, bot)
    rescue _e
      0
    nil

  -> numeric_type?(ty)
    ty.tag == :c && ["nat", "int", "rat", "real"].include?(ty.name)

  -> comparison?(p)
    ["<", "≤", "="].each -> (r)
      d = dest_binop(p, r)
      if d != nil && numeric_type?(type_of(d[0]))
        return true
    false

  -> arith_prove(goal, extra)
    c = goal.concl
    # ¬P: assume P and refute
    np = dest_unop(c, "¬")
    if np != nil
      inner = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_neg", np]], @k.false_tm), extra)
      return @k.not_intro(np, inner)
    # Try the linear certificate first. Only split a disequality when the
    # unsplit facts do not suffice, retaining the proof that supplied it.
    begin
      return arith_prove_order(goal, extra)
    rescue failure
      if @split_ne.size >= 4 || extra.size >= 100
        raise failure
      facts = []
      goal.hyps.each -> (h)
        if numeric_disequality?(h[1]) || dest_binop(h[1], "∧") != nil
          collect_disequalities(@k.assume(h[1]), facts)
      extra.each -> (th) collect_disequalities(th, facts)
      goal_vars = {}
      tm_frees(goal.concl).each -> (v)
        goal_vars[var_key(v)] = true
      rel_facts = []
      other_facts = []
      facts.each -> (th)
        if tm_frees(th.concl).any?(-> (v) goal_vars.has_key?(var_key(v)))
          rel_facts.push(th)
        else
          other_facts.push(th)
      (rel_facts + other_facts).each -> (th)
        key = tm_key(th.concl)
        if !@split_ne.include?(key)
          sides = @k.dest_eq(th.concl.b)
          lem = @session.lemma_at("lt_or_gt_of_ne", type_of(sides[0]))
          if lem != nil
            disj = @k.mp(@k.spec(sides[1], @k.spec(sides[0], lem)), th)
            pq = dest_binop(disj.concl, "∨")
            @split_ne.push(key)
            ok_ne = false
            left = nil
            right = nil
            begin
              left = arith_prove(goal.add_hyp("_lt", pq[0]), extra)
              right = arith_prove(goal.add_hyp("_gt", pq[1]), extra)
              ok_ne = true
            rescue _ne_err
              ok_ne = false
            ensure
              @split_ne.pop
            if ok_ne
              if !hyps_has?(left.hyps, pq[0])
                return left
              if !hyps_has?(right.hyps, pq[1])
                return right
              return @k.disj_cases(disj, left, right)
      if @omega_mode
        or_facts = []
        goal.hyps.each -> (h)
          collect_disjunctions(@k.assume(h[1]), or_facts)
        extra.each -> (th)
          collect_disjunctions(th, or_facts)
        or_facts.each -> (dth)
          key = "or:" + tm_key(dth.concl)
          if !@split_ne.include?(key)
            pq = dest_binop(dth.concl, "∨")
            @split_ne.push(key)
            ok_or = false
            left = nil
            right = nil
            begin
              left = linarith_proof(goal.add_hyp("_or_l", pq[0]), extra)
              right = linarith_proof(goal.add_hyp("_or_r", pq[1]), extra)
              ok_or = true
            rescue _or_err
              ok_or = false
            ensure
              @split_ne.pop
            if ok_or
              return @k.disj_cases(dth, left, right)
      raise failure

  -> collect_disjunctions(th, out)
    if dest_binop(th.concl, "∨") != nil
      out.push(th)
    elsif dest_binop(th.concl, "∧") != nil
      collect_disjunctions(@k.conj1(th), out)
      collect_disjunctions(@k.conj2(th), out)
    0

  -> collect_disequalities(th, out)
    if numeric_disequality?(th.concl)
      out.push(th)
    elsif dest_binop(th.concl, "∧") != nil
      collect_disequalities(@k.conj1(th), out)
      collect_disequalities(@k.conj2(th), out)
    0

  -> numeric_disequality?(term)
    if term.tag != :app || term.a.op != OP_NOT
      return false
    sides = @k.dest_eq(term.b)
    sides != nil && numeric_type?(type_of(sides[0]))

  -> arith_prove_order(goal, extra)
    c = goal.concl
    # omega: split nonlinearities (ℕ sub, ℤ abs, ite/min/max), prioritizing goal.concl before hypotheses, at most 5 deep
    if @omega_mode && @split_sub.size < 5
      s = nat_sub_in(c)
      ab = s == nil ? int_abs_in(c) : nil
      it = (s == nil && ab == nil) ? omega_ite_in(c) : nil
      if s == nil && ab == nil && it == nil
        s = find_nat_sub(goal, extra)
        ab = s == nil ? find_int_abs(goal, extra) : nil
        it = (s == nil && ab == nil) ? find_omega_ite(goal, extra) : nil
      if s != nil
        d = dest_binop(s, "-")
        tot = @session.lemma_at("le_total", ty_nat)
        sac = @session.lemma_at("sub_add_cancel", ty_nat)
        sez = @session.lemma_at("sub_eq_zero", ty_nat)
        if tot != nil && sac != nil && sez != nil
          @split_sub.push(tm_key(s))
          disj = @k.spec(d[0], @k.spec(d[1], tot))
          pq = dest_binop(disj.concl, "∨")
          f1 = @k.mp(@k.spec(d[1], @k.spec(d[0], sac)), @k.assume(pq[0]))
          f2 = @k.mp(@k.spec(d[1], @k.spec(d[0], sez)), @k.assume(pq[1]))
          begin
            t1 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_ge", pq[0]]], c), extra + [f1])
            t2 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_le", pq[1]]], c), extra + [f2])
          rescue e
            @split_sub.pop
            raise e
          @split_sub.pop
          return @k.disj_cases(disj, t1, t2)
      if ab != nil
        x = ab.b
        aon = @session.lemma_at("abs_of_nonneg", ty_int)
        aog = @session.lemma_at("abs_of_neg", ty_int)
        nle = @session.lemma_at("not_le", ty_int)
        if aon != nil && aog != nil && nle != nil
          @split_sub.push(tm_key(ab))
          le_tm = mk_apps(@k.mk_const("≤", ty_funs([ty_int, ty_int], ty_bool)), [mk_lit(0, ty_int), x])
          nle_tm = @k.neg_tm(le_tm)
          f1 = @k.mp(@k.spec(x, aon), @k.assume(le_tm))
          hlt = @k.mp(@k.spec(x, @k.spec(mk_lit(0, ty_int), nle)), @k.assume(nle_tm))
          f2 = @k.mp(@k.spec(x, aog), hlt)
          begin
            t1 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_abs_nn", le_tm]], c), extra + [f1])
            t2 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_abs_neg", nle_tm]], c), extra + [f2])
          ensure
            @split_sub.pop
          return @k.disj_cases(@k.excluded_middle(le_tm), t1, t2)
      if it != nil
        ip = @session.theorem("if_pos")
        ineg = @session.theorem("if_neg")
        if ip != nil && ineg != nil
          @split_sub.push(tm_key(it[0]))
          cond_tm = it[1]
          ncond_tm = @k.neg_tm(cond_tm)
          ty_i = type_of(it[0])
          ip_i = @k.inst_type(ip, {tm_tyvars(ip.concl)[0] => ty_i})
          in_i = @k.inst_type(ineg, {tm_tyvars(ineg.concl)[0] => ty_i})
          f1 = @k.mp(@k.spec(it[3], @k.spec(it[2], @k.spec(cond_tm, ip_i))), @k.assume(cond_tm))
          f2 = @k.mp(@k.spec(it[3], @k.spec(it[2], @k.spec(cond_tm, in_i))), @k.assume(ncond_tm))
          if it[4] != nil
            f1 = @k.trans(it[4], f1)
            f2 = @k.trans(it[4], f2)
          begin
            t1 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_ite_t", cond_tm]], c), extra + [f1])
            t2 = arith_prove(Goal.new(goal.fixes, goal.hyps + [["_ite_f", ncond_tm]], c), extra + [f2])
          ensure
            @split_sub.pop
          return @k.disj_cases(@k.excluded_middle(cond_tm), t1, t2)
    arith_prove_core(goal, extra + divmod_facts(goal, extra))

  -> prioritize_goal_terms(goal, extra)
    gvars = {}
    tm_frees(goal.concl).each -> (v)
      gvars[var_key(v)] = true
    if gvars.size == 0
      ts = [goal.concl]
      goal.hyps.each -> (h) ts.push(h[1])
      extra.each -> (t) ts.push(t.concl)
      return ts
    rel = [goal.concl]
    other = []
    hi = goal.hyps.size - 1
    while hi >= 0
      h = goal.hyps[hi]
      if tm_frees(h[1]).any?(-> (v) gvars.has_key?(var_key(v)))
        rel.push(h[1])
      else
        other.push(h[1])
      hi -= 1
    ei = extra.size - 1
    while ei >= 0
      t = extra[ei]
      if tm_frees(t.concl).any?(-> (v) gvars.has_key?(var_key(v)))
        rel.push(t.concl)
      else
        other.push(t.concl)
      ei -= 1
    rel + other

  -> find_int_abs(goal, extra)
    ts = prioritize_goal_terms(goal, extra)
    found = nil
    ts.each -> (t)
      if found == nil
        found = int_abs_in(t)
    found

  -> int_abs_in(t)
    if t.tag != :app
      return nil
    if t.a.tag == :const && t.a.op == OP_ABS && ty_eq(type_of(t), ty_int) && !@split_sub.include?(tm_key(t))
      return t
    r = int_abs_in(t.a)
    r != nil ? r : int_abs_in(t.b)

  -> find_omega_ite(goal, extra)
    ts = prioritize_goal_terms(goal, extra)
    found = nil
    ts.each -> (t)
      if found == nil
        found = omega_ite_in(t)
    found

  -> omega_ite_in(t)
    if t.tag != :app
      return nil
    sp = strip_app(t)
    h = sp[0]
    ty = type_of(t)
    if h.tag == :const && numeric_type?(ty) && !@split_sub.include?(tm_key(t))
      if h.name == "ite" && sp[1].size == 3
        return [t, sp[1][0], sp[1][1], sp[1][2], nil]
      if (h.name == "min" || h.name == "max") && sp[1].size == 2 && @k.defs.has_key?(h.name)
        conv = nil
        u0 = Simp.new(@d, [make_rule(@d, @k.defs[h.name], h.name)]).rewrite_top(h, 0)
        if u0 != nil
          u1 = @d.ap_thm(u0, sp[1][0])
          r1 = dest_binop(u1.concl, "=")[1]
          if r1.tag == :app && r1.a.tag == :lam
            u1 = @k.trans(u1, @k.beta(r1))
          u2 = @d.ap_thm(u1, sp[1][1])
          r2 = dest_binop(u2.concl, "=")[1]
          if r2.tag == :app && r2.a.tag == :lam
            conv = @k.trans(u2, @k.beta(r2))
        if conv == nil
          conv = @d.compute_conv(t)
        rhs = dest_binop(conv.concl, "=")[1]
        rsp = strip_app(rhs)
        if rsp[0].tag == :const && rsp[0].name == "ite" && rsp[1].size == 3
          return [t, rsp[1][0], rsp[1][1], rsp[1][2], conv]
    r = nil
    sp[1].each -> (a)
      if r == nil
        r = omega_ite_in(a)
    r

  # the first ℕ subtraction a - b in the goal, hypotheses or extra facts that is not already being split
  -> find_nat_sub(goal, extra)
    ts = prioritize_goal_terms(goal, extra)
    found = nil
    ts.each -> (t)
      if found == nil
        found = nat_sub_in(t)
    found

  -> nat_sub_in(t)
    if t.tag != :app
      return nil
    sp = strip_app(t)
    h = sp[0]
    if h.tag == :const && h.name == "-" && sp[1].size == 2 && ty_eq(type_of(t), ty_nat) && !@split_sub.include?(tm_key(t))
      return t
    r = nil
    sp[1].each -> (a)
      if r == nil
        r = nat_sub_in(a)
    r

  # x / k and x % k with a literal k > 0 (ℕ, ℤ): k * (x / k) + x % k = x, 0 ≤ x % k < k
  -> divmod_facts(goal, extra)
    seen = {}
    out = []
    collect_divmod(goal.concl, seen, out)
    nh = goal.hyps.size
    i = 0
    while i < nh
      collect_divmod(goal.hyps[i][1], seen, out)
      i += 1
    ne = extra.size
    i = 0
    while i < ne
      collect_divmod(extra[i].concl, seen, out)
      i += 1
    out

  # Orient a literal remainder equation. For odd/even, unfold only the head
  # so the dividend keeps exactly the spelling it has in the branch fact.
  -> literal_residue(prop)
    conversion = nil
    if prop.tag == :app && (is_const?(prop.a, "odd") || is_const?(prop.a, "even"))
      head = @k.compute(prop.a)
      if head.concl.b.tag != :lam
        return nil
      applied = @d.ap_thm(head, prop.b)
      conversion = @k.trans(applied, @k.beta(applied.concl.b))
      prop = conversion.concl.b
    if (prop.search_ops & TERM_DIVMOD) == 0
      return nil
    sides = dest_binop(prop, "=")
    if sides == nil
      return nil
    reversed = sides[0].tag == :lit
    rem = reversed ? sides[1] : sides[0]
    value = reversed ? sides[0] : sides[1]
    if value.tag != :lit || rem.tag != :app || rem.a.tag != :app || rem.a.a.op != OP_MOD || rem.b.tag != :lit
      return nil
    ty = type_of(rem)
    if (ty != TY_NAT_SINGLETON && ty != TY_INT_SINGLETON) || rem.b.val <= 0
      return nil
    [rem, value, reversed, conversion]

  -> residue_from_fact(rem, source, fact, expected = nil)
    if source == nil
      return nil
    dividend = source[0].a.b
    if !tm_eq(dividend, rem.a.b)
      return nil
    modulus = source[0].b
    divisor = rem.b
    if modulus.val % divisor.val != 0 || (expected != nil && int_fmod(source[1].val, divisor.val) != expected.val)
      return nil
    begin
      equation = source[3] == nil ? fact : @k.eq_mp(source[3], fact)
      proof = source[2] ? @k.sym(equation) : equation
      if !tm_eq(modulus, divisor)
        ty = type_of(divisor)
        rule = auto_loaded_rule("mod_of_factor." + ty.name)
        if rule == nil
          return nil
        factor = mk_lit(modulus.val / divisor.val, ty)
        [dividend, modulus, divisor, factor, source[1]].each -> (arg) rule = @k.spec(arg, rule)
        # Compute the factorization and positivity guards inside the kernel.
        rule = @k.mp(rule, @d.eqt_elim(@k.compute(rule.concl.a.b)))
        if ty == TY_INT_SINGLETON
          rule = @k.mp(rule, @d.eqt_elim(@k.compute(rule.concl.a.b)))
        proof = @k.mp(rule, proof)
        proof = @k.trans(proof, @k.compute(proof.concl.b))
      sides = @k.dest_eq(proof.concl)
      if sides != nil && tm_eq(sides[0], rem) && sides[1].tag == :lit
        return proof
      nil
    rescue e
      nil

  -> finish_residue(target, proof)
    if proof == nil || !tm_eq(proof.concl, @k.eq_tm(target[0], target[1]))
      return nil
    oriented = target[2] ? @k.sym(proof) : proof
    target[3] == nil ? oriented : @k.eq_mp(@k.sym(target[3]), oriented)

  -> residue_operation(t)
    if t.tag == :app && t.a.tag == :app
      op = t.a.a.op
      if op == OP_ADD || op == OP_MUL || op == OP_POW
        return op
    OP_NONE

  # An idempotent residue survives positive powers. If the exponent might
  # vanish, the lemma also requires the residue of the zeroth power.
  -> residue_power(power, modulus, base, facts)
    if base == nil
      return nil
    ty = type_of(modulus)
    rule = auto_loaded_rule("pow_mod_idempotent." + ty.name)
    if rule == nil
      return nil
    residue = base.concl.b
    [power.a.b, modulus, residue, power.b].each -> (arg) rule = @k.spec(arg, rule)
    if ty == TY_INT_SINGLETON
      rule = @k.mp(rule, @d.eqt_elim(@k.compute(rule.concl.a.b)))
    rule = @k.mp(rule, base)
    square = @k.compute(rule.concl.a.b)
    if square.concl.b.op != OP_TRUE
      return nil
    rule = @k.mp(rule, @d.eqt_elim(square))
    initial = dest_binop(rule.concl.a.b, "⇒")
    unit = @k.compute(initial[1])
    if unit.concl.b.op == OP_TRUE
      zero_case = @d.eqt_elim(unit)
    else
      impossible = auto_arithmetic_proof(Goal.new([], [], @k.false_tm), facts + [@k.assume(initial[0])], [1])
      if impossible == nil
        return nil
      zero_case = @k.false_elim(impossible, initial[1])
    @k.mp(rule, @k.disch(initial[0], zero_case))

  # Each visited subterm yields a theorem t % k = r at the goal's modulus.
  # The fact index and node budget belong to this branch alone.
  -> residue_expression(rem, known, facts, fuel)
    if fuel[0] <= 0
      return nil
    fuel[0] -= 1
    t = rem.a.b
    if t.tag == :lit || (t.tag == :app && t.a.op == OP_NEG && t.b.tag == :lit)
      return @k.compute(rem)
    bucket = known[t.h]
    if bucket != nil
      bucket.each -> (entry)
        proof = residue_from_fact(rem, entry[0], entry[1])
        if proof != nil
          return proof
    op = residue_operation(t)
    if op == OP_POW
      base = mk_apps(rem.a.a, [t.a.b, rem.b])
      return residue_power(t, rem.b, residue_expression(base, known, facts, fuel), facts)
    if op == OP_NONE
      return nil
    modulus = rem.b
    mod_op = rem.a.a
    lhs = mk_apps(mod_op, [t.a.b, modulus])
    rhs = mk_apps(mod_op, [t.b, modulus])
    left = residue_expression(lhs, known, facts, fuel)
    if left == nil && op == OP_ADD
      return nil
    right = tm_eq(lhs, rhs) ? left : residue_expression(rhs, known, facts, fuel)
    ty = type_of(modulus)
    if left != nil && right != nil
      reduced = @k.mk_comb(@d.ap_term(t.a.a, left), right)
    else
      # One zero residue determines a product even with an unknown cofactor.
      zero = left == nil ? right : left
      if op != OP_MUL || zero == nil || zero.concl.b.val != 0
        return nil
      other = left == nil ? lhs : rhs
      law = auto_loaded_rule((left == nil ? "mul_zero." : "zero_mul.") + ty.name)
      if law == nil
        return nil
      change = left == nil ? @d.ap_term(mk_app_raw(t.a.a, lhs), right) : @d.ap_thm(@d.ap_term(t.a.a, left), rhs)
      reduced = @k.trans(change, @k.spec(other, law))
    rule = auto_loaded_rule((op == OP_ADD ? "add_mod." : "mul_mod.") + ty.name)
    if rule == nil
      return nil
    rule = @k.spec(modulus, @k.spec(t.b, @k.spec(t.a.b, rule)))
    if ty == TY_INT_SINGLETON
      rule = @k.mp(rule, @d.eqt_elim(@k.compute(rule.concl.a.b)))
    step = @d.ap_thm(@d.ap_term(mod_op, reduced), modulus)
    @k.trans(@k.trans(rule, step), @k.compute(step.concl.b))

  -> residue_expression_head?(t)
    if t.tag != :app
      return false
    residue_operation(t) != OP_NONE || (t.a.tag == :app && t.a.a.op == OP_SUB && type_of(t) == TY_INT_SINGLETON)

  # Write the dividend as c + d*q, where d divides the modulus and every
  # nonconstant coefficient. The kernel checks the reconstructed polynomial
  # and add_mul_mod before the residue can close a goal or refute a fact.
  -> polynomial_residue(source, refuting)
    rem = source[0]
    t = rem.a.b
    if !residue_expression_head?(t) || (t.search_ops & TERM_POWER) != 0
      return nil
    ty = type_of(t)
    begin
      recurrence_ring_cost(t, ty.name, [64])
      ctx = RingCtx.new(ty.name)
      poly = ring_norm(t, ty.name, ctx)
      d = rem.b.val
      poly.each -> (mid, coeff)
        if mid != 0
          d = int_gcd(d, coeff[0])
      constant = poly[0] == nil ? 0 : poly[0][0]
      r = int_fmod(constant, d)
      if refuting
        if d == 1 || r == int_fmod(source[1].val, d)
          return nil
      elsif d != rem.b.val || r != source[1].val
        return nil
      atoms = {}
      ctx.atoms.each -> (_key, entries)
        entries.each -> (entry) atoms[entry[1]] = entry[0]
      plus = @k.mk_const("+", ty_funs([ty, ty], ty))
      times = @k.mk_const("*", ty_funs([ty, ty], ty))
      quotient = mk_lit(0, ty)
      poly.each -> (mid, coeff)
        if mid != 0
          term = mk_lit(coeff[0] / d, ty)
          mono = ctx.monos[mid]
          i = 0
          while i < mono.size
            mono[i + 1].times -> term = mk_apps(times, [term, atoms[mono[i]]])
            i += 2
          quotient = mk_apps(plus, [quotient, term])
      divisor = mk_lit(d, ty)
      offset = mk_lit(constant, ty)
      law = auto_loaded_rule("add_mul_mod." + ty.name)
      if law == nil
        return nil
      law = @k.spec(divisor, @k.spec(quotient, @k.spec(offset, law)))
      if ty == TY_INT_SINGLETON
        law = @k.mp(law, @d.eqt_elim(@k.compute(law.concl.a.b)))
      rewrite = @k.ring_eq(t, mk_apps(plus, [offset, mk_apps(times, [divisor, quotient])]))
      lifted = @d.ap_thm(@d.ap_term(rem.a.a, rewrite), divisor)
      @k.trans(@k.trans(lifted, law), @k.compute(law.concl.b))
    rescue e
      nil

  # The host gcd proposes a common divisor. Each projection checks its
  # factorization, and kernel evaluation refutes the resulting literal equality.
  -> residue_conflict(source, fact, previous)
    other = previous[0]
    rem = source[0]
    if !tm_eq(rem.a.b, other[0].a.b)
      return nil
    d = int_gcd(rem.b.val, other[0].b.val)
    if d == 1 || int_fmod(source[1].val, d) == int_fmod(other[1].val, d)
      return nil
    common = mk_app_raw(rem.a, mk_lit(d, type_of(rem)))
    left = residue_from_fact(common, source, fact)
    right = residue_from_fact(common, other, previous[1])
    residue_disagreement(left, right)

  -> residue_disagreement(left, right)
    if left == nil || right == nil || tm_eq(left.concl.b, right.concl.b)
      return nil
    equality = @k.trans(@k.sym(left), right)
    @k.eq_mp(@k.compute(equality.concl), equality)

  -> auto_residue_facts(goal, target, facts)
    expression = target != nil && residue_expression_head?(target[0].a.b)
    if facts.size == 0 && !expression
      return nil
    known = {}
    facts.each -> (fact)
      source = literal_residue(fact.concl)
      if source == nil
        next
      intrinsic = polynomial_residue(source, true)
      if intrinsic != nil
        claimed = residue_from_fact(intrinsic.concl.a.b, source, fact)
        absurd = residue_disagreement(intrinsic, claimed)
        if absurd != nil
          return @k.false_elim(absurd, goal)
      key = source[0].a.b.h
      bucket = known[key]
      if bucket == nil
        bucket = []
        known[key] = bucket
      else
        bucket.each -> (previous)
          absurd = residue_conflict(source, fact, previous)
          if absurd != nil
            return @k.false_elim(absurd, goal)
      bucket.push([source, fact])
    if expression
      begin
        proof = residue_expression(target[0], known, facts, [64])
        if proof == nil
          proof = polynomial_residue(target, false)
        return finish_residue(target, proof)
      rescue e
        return nil
    nil

  -> collect_divmod(t, seen, out)
    if (t.search_ops & TERM_DIVMOD) == 0 || t.tag != :app
      return 0
    collect_divmod(t.a, seen, out)
    collect_divmod(t.b, seen, out)
    if t.a.tag == :app && t.a.a.tag == :const
      op = t.a.a.op
      if op == OP_DIV || op == OP_MOD
        ty = type_of(t)
        k = t.b
        x = t.a.b
        if (ty == TY_NAT_SINGLETON || ty == TY_INT_SINGLETON) && k.tag == :lit && k.val > 0
          canon = mk_app_raw(mk_app_raw(mk_const_raw("/", ty_fun(ty, ty_fun(ty, ty))), x), k)
          if tm_set_add?(seen, canon)
            begin
              dam = @session.lemma_at("div_add_mod", ty)
              mnn = @session.lemma_at("mod_nonneg", ty)
              mlt = @session.lemma_at("mod_lt", ty)
              lt = mk_const_raw("<", ty_fun(ty, ty_fun(ty, TY_BOOL_SINGLETON)))
              kpos = arith_prove_core(Goal.new([], [], mk_apps(lt, [mk_lit(0, ty), k])), [])
              out.push(@k.spec(k, @k.spec(x, dam)))
              out.push(@k.mp(@k.spec(k, @k.spec(x, mnn)), kpos))
              out.push(@k.mp(@k.spec(k, @k.spec(x, mlt)), kpos))
            rescue e
              0
    0

  -> arith_prove_core(goal, extra, with_squares = true)
    c = goal.concl
    # negate goal into a comparison hypothesis
    hyps = []
    goal.hyps.each -> (h)
      hyps.push(@k.assume(h[1]))
    extra.each -> (t)
      hyps.push(t)
    neg = nil
    if c.op == OP_FALSE
      neg = nil
    else
      neg = @k.neg_tm(c)
      hyps.push(@k.assume(neg))
    # Normalize the induction constructor even inside opaque function atoms;
    # the resulting equality conversions carry the successor lemma's proof.
    rules = []
    successor = @session.lemma_at("succ_eq_add_one", ty_nat)
    if successor != nil
      rules.push(make_rule(@d, successor, "succ_eq_add_one.nat"))
    if @omega_mode
      [ty_nat, ty_int, ty_rat, ty_real].each -> (nty)
        ["mul_one", "one_mul", "mul_zero", "zero_mul", "add_zero", "zero_add"].each -> ( stem )
          lem_u = @session.lemma_at(stem, nty)
          if lem_u != nil && lem_u.tags.size == 0
            rules.push(make_rule(@d, lem_u, stem + "." + nty.name))
    # Fold closed numeric subterms (1 / 2 ^ 4 ↦ 1/16) on the same traversal.
    folder = Simp.new(@d, rules)
    folded = []
    bottom = nil
    hyps.each -> (h)
      begin
        if (h.concl.search_ops & TERM_LAMBDA) != 0
          h = @k.eq_mp(@d.beta_eta_conv(h.concl), h)
        eqth = folder.simp_conv_opt(h.concl, 0)
        if eqth == nil
          folded.push(h)
        else
          rhs = dest_binop(eqth.concl, "=")[1]
          if tm_eq(rhs, h.concl)
            folded.push(h)
          elsif rhs.op == OP_FALSE
            bottom = @k.eq_mp(eqth, h)
          elsif rhs.op != OP_TRUE
            folded.push(@k.eq_mp(eqth, h))
      rescue e
        folded.push(h)
    if bottom != nil
      if neg == nil
        return bottom
      return classical_by_contra(c, bottom)
    hyps = folded
    comps = []
    hyps.each -> (h)
      normalize_comparisons(h, comps)
    # group by type
    by_type = {}
    comps.each -> (t)
      cmp = dest_cmp_rel(t.concl)
      ty = type_of(cmp[1])
      arr = by_type[ty.id]
      if arr == nil
        arr = []
        by_type[ty.id] = arr
      arr.push(t)
    by_type.each -> (_tid, ts)
      ty = type_of(first_side(ts[0]))
      ts2 = ts
      if ty == TY_NAT_SINGLETON
        ts2 = ts + nat_nonneg(ts)
      if @nl_mode && ty != TY_NAT_SINGLETON
        ts2 = ts2 + nl_products(ts, ty)
      if @nl_mode && ty == TY_NAT_SINGLETON
        # Products need the derived 0 ≤ n facts too, including factors that
        # occur only in the goal. Otherwise a ≤ b cannot be scaled by n.
        ts2 = ts2 + nl_products_nat(integer_strengthen(ts2, ty))
      if ty == TY_NAT_SINGLETON || ty == TY_INT_SINGLETON
        ts2 = integer_strengthen(ts2, ty)
      coeffs = fm_certificate(ts2, ty.name)
      if coeffs == nil && @nl_mode && ty != TY_NAT_SINGLETON
        unified = nl_unify_variables(ts)
        cross_input = unified
        if with_squares
          unified = unified + nl_square_facts(unified, ty)
        ts3 = unified + nl_products(unified, ty) + nl_products(unified, ty, true)
        coeffs = fm_certificate(ts3, ty.name)
        if coeffs == nil && with_squares
          # Try completed squares last, without multiplying them pairwise.
          ts3 = ts3 + nl_square_facts(cross_input, ty, true)
          coeffs = fm_certificate(ts3, ty.name)
        ts2 = ts3
      if coeffs != nil
        f = @k.farkas(ts2, coeffs)
        if neg == nil
          return f
        return classical_by_contra(c, f)
    fail("linarith failed")

  # Check the goal given to the tactic. A failed speculative refinement may
  # be false even when its parent is true.
  -> polynomial_counterexample(goal, hints)
    c = goal.concl
    if goal.hyps.size + hints.size > 16 || !auto_small_term?(c, [384])
      return nil
    premises = goal.hyps.map(-> (h) h[1]) + hints.map(-> (th) th.concl)
    avoid = goal.all_terms
    while true
      binder = dest_unop(c, "∀")
      if binder != nil && binder.tag == :lam
        opened = dest_lam_fresh(binder, avoid)
        avoid = avoid + [opened[0]]
        c = opened[1]
        next
      implication = dest_binop(c, "⇒")
      if implication == nil
        break
      premises.push(implication[0])
      c = implication[1]
    if c.tag != :app || c.a.tag != :app || (c.a.a.op != OP_LT && c.a.a.op != OP_LE)
      return nil
    nodes = [384]
    if premises.size > 16 || !premises.all?(-> (p) auto_small_term?(p, nodes))
      return nil
    begin
      facts = []
      premises.each -> (p) normalize_comparisons(@k.assume(p), facts)
      PolynomialSign.new(self).counterexample(c, facts, premises)
    rescue diagnostic_error
      nil

  -> auto_polynomial_sign(goal, hints)
    c = goal.concl
    if c.tag != :app || c.a.tag != :app || (c.a.a.op != OP_LT && c.a.a.op != OP_LE)
      return nil
    if goal.hyps.size + hints.size > 24 || !auto_small_term?(c, [384])
      return nil
    facts = []
    goal.hyps.each -> (h)
      if auto_small_term?(h[1], [64])
        normalize_comparisons(@k.assume(h[1]), facts)
    hints.each -> (th)
      if auto_small_term?(th.concl, [64])
        normalize_comparisons(th, facts)
    begin
      PolynomialSign.new(self).prove(c, facts)
    rescue e
      nil

  # positivity: sign facts of the goal's subterms (|x| ≥ 0, exp x > 0, √x ≥ 0, x^(2k) ≥ 0), then nlinarith
  -> tac_positivity(g, args)
    facts = []
    pos_facts(g.goal.concl, facts, {})
    solve = -> (c) arith_prove(g.goal.with_concl(c), facts)
    @nl_mode = true
    begin
      close(g, prove_conjuncts(g.goal.concl, solve))
    ensure
      @nl_mode = false

  -> pos_facts(t, out, seen)
    if t.tag != :app
      return 0
    sp = strip_app(t)
    h = sp[0]
    sp[1].each -> (a)
      pos_facts(a, out, seen)
    if h.tag != :const || !tm_set_add?(seen, t)
      return 0
    ty = type_of(t)
    args = sp[1]
    begin
      if h.op == OP_ABS && args.size == 1
        l = @session.lemma_at("abs_nonneg", ty)
        if l != nil
          out.push(@k.spec(args[0], l))
      elsif h.name == "exp" && args.size == 1
        l = @session.theorem("exp_pos")
        if l != nil
          out.push(@k.spec(args[0], l))
      elsif h.name == "sqrt" && args.size == 1
        l = @session.theorem("sqrt_nonneg")
        if l != nil
          out.push(@k.spec(args[0], l))
      elsif h.name == "rpow" && args.size == 2
        l = @session.theorem("rpow.pos")
        if l != nil
          out.push(@k.spec(args[1], @k.spec(args[0], l)))
      elsif h.name == "complex.norm_sq" && args.size == 1
        l = @session.theorem("complex.norm_sq_nonneg")
        if l != nil
          out.push(@k.spec(args[0], l))
      elsif h.name == "complex.abs" && args.size == 1
        l = @session.theorem("complex.abs_nonneg")
        if l != nil
          out.push(@k.spec(args[0], l))
      elsif h.op == OP_POW && args.size == 2 && args[1].tag == :lit
        n = args[1].val
        l = @session.lemma_at("sq_nonneg", ty)
        if l != nil && n.is_a?(Integer) && n >= 2 && n % 2 == 0
          base = args[0]
          if n > 2
            base = mk_apps(@k.mk_const("^", ty_funs([ty, TY_NAT_SINGLETON], ty)), [args[0], mk_lit(n / 2, TY_NAT_SINGLETON)])
          out.push(@k.spec(base, l))
    rescue e
      0
    0

  # Direct 2-premise Farkas helper: proves `0 ≤ dt` (or `0 < dt` when want_strict) from `t : a ≤ b` / `a < b`.
  -> prove_diff_sign(t, dt, zero, le_c, lt_c, not_le, not_lt, want_strict)
    goal_tm = mk_app_raw(mk_app_raw(want_strict ? lt_c : le_c, zero), dt)
    lem = want_strict ? not_lt : not_le
    if lem != nil
      neg_g = @k.neg_tm(goal_tm)
      flipped = @k.mp(@k.spec(dt, @k.spec(zero, lem)), @k.assume(neg_g))
      bot = @k.farkas([flipped, t], [Q_ONE, Q_ONE])
      return classical_by_contra(goal_tm, bot)
    arith_prove_core(Goal.new([], [], goal_tm), [t])

  # nlinarith: for each hypothesis a ≤ b (a < b) the fact 0 ≤ b - a (0 < b - a), then every pairwise product of those
  # differences, proved with mul_nonneg / mul_pos. Linear arithmetic then treats the expanded monomials as atoms.
  -> nl_products(ts, ty, cubic = false)
    zero = ty == TY_INT_SINGLETON ? mk_lit(0, ty) : mk_lit(Q_ZERO, ty)
    minus = @k.mk_const("-", ty_funs([ty, ty], ty))
    le = @k.mk_const("≤", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    lt = @k.mk_const("<", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    mn = @session.lemma_at("mul_nonneg", ty)
    mp = @session.lemma_at("mul_pos", ty)
    if mn == nil || mp == nil
      return []
    not_le = @session.lemma_at("not_le", ty)
    not_lt = @session.lemma_at("not_lt", ty)
    terms = []
    nns = []
    poss = []
    saved = @nl_mode
    @nl_mode = false
    ts.each -> (t)
      if terms.size < 24
        d = dest_binop(t.concl, "≤")
        strict = false
        if d == nil
          d = dest_binop(t.concl, "<")
          strict = true
        if d != nil
          begin
            if tm_eq(d[0], zero)
              dt = d[1]
              if !strict
                terms.push(dt)
                nns.push(t)
                poss.push(nil)
              else
                nn = prove_diff_sign(t, dt, zero, le, lt, not_le, not_lt, false)
                terms.push(dt)
                nns.push(nn)
                poss.push(t)
            else
              dt = mk_app_raw(mk_app_raw(minus, d[1]), d[0])
              nn = prove_diff_sign(t, dt, zero, le, lt, not_le, not_lt, false)
              ps = nil
              if strict
                ps = prove_diff_sign(t, dt, zero, le, lt, not_le, not_lt, true)
              terms.push(dt)
              nns.push(nn)
              poss.push(ps)
          rescue e
            0
    @nl_mode = saved
    out = []
    if cubic
      # Bound the fallback to eight affine factors (at most 120 triples).
      # Every generated fact is an application of existing multiplication rules.
      eligible = []
      terms.each_with_index -> (term, index)
        if eligible.size < 8 && nl_affine_degree(term) <= 1
          eligible.push(index)
      i = 0
      while i < eligible.size
        j = i
        while j < eligible.size
          a = eligible[i]
          b = eligible[j]
          pair = @k.mp(@k.mp(@k.spec(terms[b], @k.spec(terms[a], mn)), nns[a]), nns[b])
          pair_pos = nil
          if poss[a] != nil && poss[b] != nil
            pair_pos = @k.mp(@k.mp(@k.spec(terms[b], @k.spec(terms[a], mp)), poss[a]), poss[b])
          product = dest_binop(pair.concl, "≤")[1]
          k = j
          while k < eligible.size
            c = eligible[k]
            if pair_pos != nil && poss[c] != nil
              out.push(@k.mp(@k.mp(@k.spec(terms[c], @k.spec(product, mp)), pair_pos), poss[c]))
            else
              out.push(@k.mp(@k.mp(@k.spec(terms[c], @k.spec(product, mn)), pair), nns[c]))
            k += 1
          j += 1
        i += 1
      return out
    i = 0
    while i < terms.size
      j = i
      while j < terms.size
        if poss[i] != nil && poss[j] != nil
          out.push(@k.mp(@k.mp(@k.spec(terms[j], @k.spec(terms[i], mp)), poss[i]), poss[j]))
        else
          out.push(@k.mp(@k.mp(@k.spec(terms[j], @k.spec(terms[i], mn)), nns[i]), nns[j]))
        j += 1
      i += 1
    out

  # Squares need no sign premise. Prove each detected square by a checked
  # sign split, without recursively collecting square facts in either branch.
  -> nl_square_facts(ts, ty, cross = false)
    bases = []
    seen = {}
    if cross
      nl_cross_square_bases(ts, ty, bases, seen)
    else
      ts.each -> (th)
        nl_square_bases(th.concl, ty, bases, seen)
    zero = ty == TY_INT_SINGLETON ? mk_lit(0, ty) : mk_lit(Q_ZERO, ty)
    le = @k.mk_const("≤", ty_funs([ty, ty], TY_BOOL_SINGLETON))
    mul = @k.mk_const("*", ty_funs([ty, ty], ty))
    out = []
    bases.each -> (base)
      sign = mk_apps(le, [zero, base])
      square = mk_apps(le, [zero, mk_apps(mul, [base, base])])
      yes = arith_prove_core(Goal.new([], [["square_sign", sign]], square), [], false)
      no = arith_prove_core(Goal.new([], [["square_sign", @k.neg_tm(sign)]], square), [], false)
      out.push(@k.disj_cases(@k.excluded_middle(sign), yes, no))
    out

  # A quadratic's x*y or linear x term suggests checked completed squares.
  # Treat linear terms as x*1; inspect normalized monomials, not notation.
  -> nl_cross_square_bases(ts, ty, bases, seen)
    ctx = RingCtx.new("rat")
    pairs = []
    diagonals = []
    ts.each -> (th)
      cmp = dest_cmp_rel(th.concl)
      poly = poly_add(ring_norm(cmp[2], ty.name, ctx), poly_scale(ring_norm(cmp[1], ty.name, ctx), Q_NEG_ONE))
      poly.each -> (mid, coefficient)
        factors = ctx.monos[mid]
        pair = nil
        # A coefficient can hide the syntactic square: c*x*x is still x².
        if factors.size == 2 && factors[1] == 2 && diagonals.size < 12 && !diagonals.include?(factors[0])
          diagonals.push(factors[0])
        if factors.size == 4 && factors[1] == 1 && factors[3] == 1
          diagonal = poly[ctx.intern_mono([factors[0], 2])]
          pair = [factors[0], factors[2], diagonal, coefficient]
        elsif factors.size == 2 && factors[1] == 1
          diagonal = poly[ctx.intern_mono([factors[0], 2])]
          if diagonal != nil
            pair = [factors[0], 0, diagonal, coefficient]
        if pair != nil && pairs.size < 6 && !pairs.include?(pair)
          pairs.push(pair)
    atoms = {}
    atoms[0] = ty == TY_INT_SINGLETON ? mk_lit(1, ty) : mk_lit(Q_ONE, ty)
    ctx.atoms.each -> (_hash, bucket)
      bucket.each -> (entry) atoms[entry[1]] = entry[0]
    diagonals.each -> (id)
      base = atoms[id]
      if tm_closed_bound?(base) && tm_set_add?(seen, base)
        bases.push(base)
    minus = @k.mk_const("-", ty_funs([ty, ty], ty))
    plus = @k.mk_const("+", ty_funs([ty, ty], ty))
    mul = @k.mk_const("*", ty_funs([ty, ty], ty))
    pairs.each -> (pair)
      a = atoms[pair[0]]
      b = atoms[pair[1]]
      [minus, plus].each -> (operator)
        base = mk_apps(operator, [a, b])
        if tm_closed_bound?(base) && tm_set_add?(seen, base)
          bases.push(base)
      # For A*x^2+B*x*y, complete the square with (2*A*x+B*y)^2.
      # Clear rational denominators so the same construction works over ℤ.
      if pair[2] != nil
        diagonal = pair[2]
        cross = pair[3]
        left = 2 * diagonal[0] * cross[1]
        right = cross[0] * diagonal[1]
        lc = ty == TY_INT_SINGLETON ? mk_lit(left, ty) : mk_lit([left, 1], ty)
        rc = ty == TY_INT_SINGLETON ? mk_lit(right, ty) : mk_lit([right, 1], ty)
        base = mk_apps(plus, [mk_apps(mul, [lc, a]), mk_apps(mul, [rc, b])])
        if tm_closed_bound?(base) && tm_set_add?(seen, base)
          bases.push(base)
    0

  -> nl_square_bases(t, ty, bases, seen)
    if bases.size >= 12 || t.tag != :app
      return 0
    product = dest_binop(t, "*")
    power = dest_binop(t, "^")
    base = nil
    if product != nil && tm_eq(product[0], product[1])
      base = product[0]
    elsif power != nil && power[1].tag == :lit && power[1].val == 2
      base = power[0]
    if base != nil && base.tag != :lit && ty_eq(type_of(base), ty) && tm_closed_bound?(base) && tm_set_add?(seen, base)
      bases.push(base)
    nl_square_bases(t.a, ty, bases, seen)
    nl_square_bases(t.b, ty, bases, seen)
    0

  # Substitute equal local variables using checked congruence before the
  # cubic search: x = y must identify x*p*q and y*p*q as well as x and y.
  -> nl_unify_variables(ts)
    out = ts
    count = 0
    ts.each -> (equation)
      eq = dest_binop(equation.concl, "=")
      if count < 8 && eq != nil && eq[0].tag == :var && eq[1].tag == :var && !tm_eq(eq[0], eq[1])
        changed = []
        out.each -> (th)
          conv = replace_conv_opt(th.concl, eq[0], equation)
          changed.push(conv == nil ? th : @k.eq_mp(conv, th))
        out = changed
        count += 1
    out

  # Conservative syntactic degree; opaque function applications are atoms.
  -> nl_affine_degree(t)
    if t.tag == :lit
      return 0
    if t.tag == :app && t.a.tag == :const && t.a.op == OP_NEG
      return nl_affine_degree(t.b)
    d = dest_binop(t, "/")
    if d != nil && d[1].tag == :lit
      return nl_affine_degree(d[0])
    d = dest_binop(t, "+")
    if d == nil
      d = dest_binop(t, "-")
    if d != nil
      a = nl_affine_degree(d[0])
      b = nl_affine_degree(d[1])
      return a > b ? a : b
    d = dest_binop(t, "*")
    if d != nil
      return nl_affine_degree(d[0]) + nl_affine_degree(d[1])
    d = dest_binop(t, "^")
    if d != nil
      return 2
    return 1

  # nlinarith over ℕ: for hypotheses a ≤ b, c ≤ d the product fact a*d + b*c ≤ a*c + b*d (nl_cross.nat), i.e.
  # (b - a)(d - c) ≥ 0 without truncated subtraction
  -> nl_products_nat(ts)
    lem = @session.theorem("nl_cross.nat")
    if lem == nil
      return []
    les = []
    ts.each -> (t)
      if les.size < 24 && dest_binop(t.concl, "≤") != nil
        les.push(t)
    out = []
    i = 0
    while i < les.size
      j = i
      while j < les.size
        p = dest_binop(les[i].concl, "≤")
        q = dest_binop(les[j].concl, "≤")
        inst = @k.spec(q[1], @k.spec(q[0], @k.spec(p[1], @k.spec(p[0], lem))))
        out.push(@k.mp(@k.mp(inst, les[i]), les[j]))
        j += 1
      i += 1
    out

  -> first_side(th)
    ["<", "≤", "="].each -> (r)
      d = dest_binop(th.concl, r)
      if d != nil
        return d[0]
    nil

  # Turns hypothesis theorems into comparison theorems (a < b, a ≤ b, a = b).
  -> normalize_comparisons(th, out, include_ne = false)
    p = th.concl
    if comparison?(p) || (include_ne && numeric_disequality?(p))
      out.push(th)
      return
    pq = dest_binop(p, "∧")
    if pq != nil
      normalize_comparisons(@k.conj1(th), out, include_ne)
      normalize_comparisons(@k.conj2(th), out, include_ne)
      return
    np = dest_unop(p, "¬")
    if np != nil
      d = dest_binop(np, "≤")
      if d != nil && numeric_type?(type_of(d[0]))
        l = @session.lemma_at("not_le", type_of(d[0]))
        if l != nil
          out.push(@k.mp(@k.spec(d[1], @k.spec(d[0], l)), th))
        return
      d = dest_binop(np, "<")
      if d != nil && numeric_type?(type_of(d[0]))
        l = @session.lemma_at("not_lt", type_of(d[0]))
        if l != nil
          out.push(@k.mp(@k.spec(d[1], @k.spec(d[0], l)), th))
        return
    0

  -> nat_nonneg(ts)
    l = @session.lemma_at("zero_le", ty_nat)
    if l == nil
      return []
    seen = {}
    out = []
    ts.each -> (t)
      collect_nat_atoms(t.concl, seen, out, l)
    out

  -> collect_nat_atoms(p, seen, out, l)
    case p.tag
    when :app
      sp = strip_app(p)
      h = sp[0]
      if h.tag == :const && ["+", "*", "<", "≤", "="].include?(h.name)
        sp[1].each -> (a)
          collect_nat_atoms(a, seen, out, l)
        # a product of naturals is a natural too: 0 ≤ x * y (linarith sees it as one monomial)
        if h.name == "*" && ty_eq(type_of(p), ty_nat) && sp[1][0].tag != :lit && sp[1][1].tag != :lit
          add_nat_atom(p, seen, out, l)
        return
      if h.tag == :const && h.name == "^"
        collect_nat_atoms(sp[1][0], seen, out, l)
        # (x + y + c)^n expands into monomials x^j and x*y: each is a natural, so ≥ 0
        if ty_eq(type_of(p), ty_nat) && sp[1][1].tag == :lit && sp[1][1].val >= 2 && sp[1][0].tag == :app
          atoms = []
          nat_base_atoms(sp[1][0], atoms)
          pw = @k.mk_const("^", ty_funs([ty_nat, ty_nat], ty_nat))
          ml = @k.mk_const("*", ty_funs([ty_nat, ty_nat], ty_nat))
          top = sp[1][1].val
          if top > 8
            top = 8
          ai = 0
          while ai < atoms.size && ai < 4
            j = 2
            while j <= top
              add_nat_atom(mk_apps(pw, [atoms[ai], mk_lit(j, ty_nat)]), seen, out, l)
              j += 1
            bj = ai + 1
            while bj < atoms.size && bj < 4
              add_nat_atom(mk_apps(ml, [atoms[ai], atoms[bj]]), seen, out, l)
              bj += 1
            ai += 1
      if ty_eq(type_of(p), ty_nat)
        add_nat_atom(p, seen, out, l)
    when :var
      if ty_eq(p.ty, ty_nat)
        add_nat_atom(p, seen, out, l)
    when :const
      if ty_eq(p.ty, ty_nat)
        add_nat_atom(p, seen, out, l)
    0

  # the non-arithmetic ℕ subterms (variables, applications) of a sum or product
  -> nat_base_atoms(t, acc)
    if t.tag == :app
      sp = strip_app(t)
      h = sp[0]
      if h.tag == :const && (h.name == "+" || h.name == "*")
        sp[1].each -> (a)
          nat_base_atoms(a, acc)
        return 0
    if t.tag == :lit
      return 0
    if ty_eq(type_of(t), ty_nat)
      dup = false
      acc.each -> (x)
        if tm_eq(x, t)
          dup = true
      if !dup
        acc.push(t)
    0

  -> add_nat_atom(t, seen, out, l)
    if tm_set_add?(seen, t)
      out.push(@k.spec(t, l))

  # integers: a < b  ~>  a + 1 ≤ b
  -> integer_strengthen(ts, ty)
    l = @session.lemma_at("lt_iff_add_one_le", ty)
    if l == nil
      return ts
    out = []
    ts.each -> (t)
      d = dest_binop(t.concl, "<")
      if d != nil
        inst = @k.spec(d[1], @k.spec(d[0], l))
        out.push(@k.eq_mp(inst, t))
      else
        out.push(t)
    out

  -> tac_sat(g)
    c = g.goal.concl
    u = dest_unop(c, "cnf_unsat")
    if u == nil
      return tac_sat_prop(g)
    ev = @k.compute(u)
    f = dest_binop(ev.concl, "=")[1]
    clauses = cnf_literal_value(f)
    if clauses == nil
      fail("sat: the CNF did not evaluate to a literal list")
    lrat = sat_solve_lrat(@session, clauses)
    th = @k.sat_unsat(f, lrat)
    unsat_c = strip_app(c)[0]
    back = @d.ap_term(unsat_c, ev)
    close(g, @k.eq_mp(@k.sym(back), th))

  # Saturate the local context with kernel-checked consequences. Caps on facts
  # and candidate terms keep quantified instantiation predictable.
  -> auto_add_fact(facts, th)
    if facts.size >= 128
      return false
    c = th.concl
    i = 0
    while i < facts.size
      if tm_eq(facts[i].concl, c)
        return false
      i += 1
    facts.push(th)
    true

  -> auto_collect_terms(t, terms)
    if terms.size >= 64
      return
    if tm_closed_bound?(t)
      i = 0
      while i < terms.size && !tm_eq(terms[i], t)
        i += 1
      if i == terms.size
        terms.push(t)
    if t.tag == :app
      auto_collect_terms(t.b, terms)
      auto_collect_terms(t.a, terms)
    elsif t.tag == :lam
      auto_collect_terms(t.b, terms)

  # Index a fixed fact set once. Hash collisions still require full term
  # equality, and every edge retains the theorem that justifies it.
  -> auto_equality_graph(facts)
    graph = {}
    facts.each -> (th)
      eq = @k.dest_eq(th.concl)
      if eq != nil
        [false, true].each -> (reverse)
          source = eq[reverse ? 1 : 0]
          target = eq[reverse ? 0 : 1]
          bucket = graph[source.h]
          if bucket == nil
            bucket = []
            graph[source.h] = bucket
          bucket.push([source, target, th, reverse])
    graph

  -> auto_equality_path(left, right, graph)
    nodes = [left]
    paths = [nil]
    visited = {}
    tm_set_add?(visited, left)
    i = 0
    while i < nodes.size && nodes.size < 128
      node = nodes[i]
      edges = graph[node.h]
      if edges != nil
        edges.each -> (edge)
          if tm_eq(edge[0], node)
            next_term = edge[1]
            found = tm_eq(next_term, right)
            if found || (!tm_set_has?(visited, next_term) && nodes.size < 128)
              step = edge[3] ? @k.sym(edge[2]) : edge[2]
              path = i == 0 ? step : @k.trans(paths[i], step)
              if found
                return path
              tm_set_add?(visited, next_term)
              nodes.push(next_term)
              paths.push(path)
      i += 1
    nil

  # Search the known equality graph, then compare applications structurally.
  # Reuse the index through congruence; allocate proofs only for new paths.
  -> auto_equal(left, right, facts, depth, graph = nil)
    if tm_eq(left, right)
      return @k.refl(left)
    if depth <= 0 || !ty_eq(type_of(left), type_of(right))
      return nil
    if graph == nil
      graph = auto_equality_graph(facts)
    if graph.size == 0
      return nil
    # Every equality contributes both endpoints. A path needs an edge at each.
    if graph[left.h] != nil && graph[right.h] != nil
      path = auto_equality_path(left, right, graph)
      if path != nil
        return path
    if left.tag == :app && right.tag == :app
      if tm_eq(left.a, right.a)
        arg_eq = auto_equal(left.b, right.b, facts, depth - 1, graph)
        return arg_eq == nil ? nil : @k.mk_comb(@k.refl(left.a), arg_eq)
      fn_eq = auto_equal(left.a, right.a, facts, depth - 1, graph)
      if fn_eq != nil
        arg_eq = auto_equal(left.b, right.b, facts, depth - 1, graph)
        if arg_eq != nil
          return @k.mk_comb(fn_eq, arg_eq)
    nil

  # Arithmetic equalities between existing arguments can be lifted through
  # applications. No new terms or backwards rules are searched here.
  -> auto_argument_equal(left, right, facts, depth, budget)
    known = auto_equal(left, right, facts, depth)
    if known != nil
      return known
    if depth <= 0 || !ty_eq(type_of(left), type_of(right))
      return nil
    if left.tag == :app && right.tag == :app && tm_eq(strip_app(left)[0], strip_app(right)[0])
      head = auto_argument_equal(left.a, right.a, facts, depth - 1, budget)
      if head != nil
        arg = auto_argument_equal(left.b, right.b, facts, depth - 1, budget)
        if arg != nil
          return @k.mk_comb(head, arg)
    if numeric_type?(type_of(left)) && budget[0] > 0
      nodes = [64]
      a = auto_quadratic_degree(left, nodes)
      b = auto_quadratic_degree(right, nodes)
      if nodes[0] >= 0 && a >= 0 && a <= 1 && b >= 0 && b <= 1
        budget[0] -= 1
        comparisons = []
        facts.each -> (th) normalize_comparisons(th, comparisons)
        begin
          prover = Prover.new(@session)
          return prover.linarith_proof(Goal.new([], [], @k.eq_tm(left, right)), comparisons)
        rescue e
          0
    nil

  # Congruence preserves the head unless an equality can rewrite the
  # term or a function on its spine. Hash collisions only admit extra matches.
  -> auto_fixed_head(term, graph)
    while graph[term.h] == nil
      if term.tag != :app
        return term.h
      term = term.a
    nil

  # Derive one new consequence using an equality to match a premise. Processing
  # the new fact before searching again also handles chained implications.
  -> auto_equal_mp(facts)
    if facts.size >= 128
      return false
    graph = auto_equality_graph(facts)
    if graph.size == 0
      return false
    heads = facts.map(-> (th) auto_fixed_head(th.concl, graph))
    facts.each -> (rule)
      imp = dest_binop(rule.concl, "⇒")
      guard = imp == nil ? dest_unop(rule.concl, "¬") : imp[0]
      if guard != nil && (imp == nil || !facts.any?(-> (th) tm_eq(th.concl, imp[1])))
        head = auto_fixed_head(guard, graph)
        j = 0
        while j < facts.size
          premise = facts[j]
          if (head == nil || heads[j] == nil || head == heads[j]) && !tm_eq(premise.concl, guard)
            eq = auto_equal(premise.concl, guard, facts, 16, graph)
            if eq != nil
              matched = @k.eq_mp(eq, premise)
              result = imp == nil ? @k.not_elim(rule, matched) : @k.mp(rule, matched)
              if auto_add_fact(facts, result)
                return true
          j += 1
    false

  -> auto_fresh(goal, facts, terms, ty)
    avoid = goal.all_terms + terms
    facts.each -> (fact)
      avoid.push(fact.concl)
      fact.hyps.each -> (hyp)
        avoid.push(hyp)
    mk_var(fresh_name("w", avoid), ty)

  -> auto_forward(goal, hints = [])
    facts = []
    terms = []
    goal.fixes.each -> (f)
      auto_collect_terms(f[1], terms)
    auto_collect_terms(goal.concl, terms)
    goal.hyps.each -> (h)
      auto_add_fact(facts, @k.assume(h[1]))
      auto_collect_terms(h[1], terms)
    hints.each -> (hint) auto_add_fact(facts, hint)
    proof = auto_search_root(goal, facts + [], terms)
    if proof != nil
      return proof
    proof = auto_classical(goal, facts, terms, [], 3, [12], false)
    if proof != nil
      return proof
    auto_predicate_ring(goal.concl, facts)

  # Transport a known predicate across checked polynomial identities in its
  # numeric arguments. Other arguments, including functions and sets, must agree.
  -> auto_predicate_ring(target, facts)
    if target.tag != :app || facts.empty?()
      return nil
    spine = strip_app(target)
    head = spine[0]
    if head.tag != :var && !(head.tag == :const && head.op == OP_NONE)
      return nil
    args = spine[1]
    nodes = [96]
    attempts = 4
    facts.each -> (fact)
      if attempts <= 0
        return nil
      candidate = strip_app(fact.concl)
      src = candidate[1]
      if !tm_eq(head, candidate[0]) || args.size != src.size
        next
      if !(0...args.size).all?(-> (i) tm_eq(src[i], args[i]) || numeric_type?(type_of(args[i])))
        next
      attempts -= 1
      begin
        eq = @k.refl(head)
        i = 0
        while i < args.size
          a = src[i]
          b = args[i]
          if tm_eq(a, b)
            eq = @d.ap_thm(eq, a)
          else
            recurrence_ring_cost(a, type_of(a).name, nodes)
            recurrence_ring_cost(b, type_of(b).name, nodes)
            eq = @k.mk_comb(eq, @k.ring_eq(a, b))
          i += 1
        return @k.eq_mp(eq, fact)
      rescue e
        0
    nil

  -> auto_arithmetic_proof(goal, facts, budget)
    if budget[0] <= 0 || (!comparison?(goal.concl) && !numeric_disequality?(goal.concl) && !is_const?(goal.concl, "⊥"))
      return nil
    comparisons = []
    facts.each -> (th)
      normalize_comparisons(th, comparisons, true)
    if comparisons.size == 0
      return nil
    budget[0] -= 1
    # The theorem objects retain the assumptions used by both attempts.
    prover = Prover.new(@session)
    target = Goal.new(goal.fixes, [], goal.concl)
    begin
      return prover.linarith_proof(target, comparisons)
    rescue e
      if comparisons.any?(-> (th) numeric_disequality?(th.concl))
        return prover.cast_arithmetic_proof(target, comparisons)
      nil

  -> auto_has_arithmetic(t)
    if comparison?(t)
      return true
    if t.tag == :app
      return auto_has_arithmetic(t.a) || auto_has_arithmetic(t.b)
    if t.tag == :lam
      return auto_has_arithmetic(t.b)
    false

  # Arithmetic treats applications as atoms. Connect existing numeric atoms
  # whose arguments are equal, using ordinary checked congruence.
  -> auto_arithmetic_congruence(terms, facts, budget)
    if budget.size == 1
      budget.push(32)
      budget.push(8)
    added = 0
    i = 0
    while i < terms.size && budget[1] > 0 && budget[2] > 0
      left = terms[i]
      if left.tag == :app && numeric_type?(type_of(left))
        head = strip_app(left)[0]
        j = i + 1
        while j < terms.size && budget[1] > 0 && budget[2] > 0
          right = terms[j]
          if right.tag == :app && ty_eq(type_of(left), type_of(right)) && tm_eq(head, strip_app(right)[0])
            budget[1] -= 1
            eq = auto_argument_equal(left, right, facts, 16, budget)
            if eq != nil && auto_add_fact(facts, eq)
              added += 1
              budget[2] -= 1
          j += 1
      i += 1
    added > 0

  -> auto_arithmetic_forward(goal, hints = [], nonlinear = nil, squares = false)
    facts = []
    terms = []
    useful = false
    goal.hyps.each -> (h)
      known = @k.assume(h[1])
      auto_add_fact(facts, known)
      bounds = auto_abs_bounds(known)
      if bounds != nil
        auto_add_fact(facts, bounds)
        useful = true
      if auto_minmax_facts(h[1], facts)
        useful = true
      if comparison?(h[1]) || @k.dest_eq(h[1]) != nil || dest_unop(h[1], "∀") != nil || dest_binop(h[1], "⇒") != nil || dest_binop(h[1], "∨") != nil || dest_binop(h[1], "∧") != nil
        useful = true
    useful = useful || hints.size > 0
    if auto_minmax_facts(goal.concl, facts)
      useful = true
    if !(goal.all_terms + hints.map -> (hint) hint.concl).any?(->(term) auto_has_arithmetic(term))
      return nonlinear == nil ? nil : auto_nonlinear_premise(goal, nonlinear)
    auto_collect_terms(goal.concl, terms)
    goal.fixes.each -> (f)
      auto_collect_terms(f[1], terms)
    goal.hyps.each -> (h)
      auto_collect_terms(h[1], terms)
    hints.each -> (hint) auto_collect_terms(hint.concl, terms)
    if !useful
      return nonlinear == nil ? nil : auto_nonlinear_premise(goal, nonlinear)
    instances = auto_hint_instances(goal, hints, terms, false, squares)
    if instances.size > 0
      selected = []
      (facts + hints).each -> (known)
        if !hints.any?(-> (hint) dest_unop(hint.concl, "∀") != nil && tm_eq(hint.concl, known.concl))
          auto_add_fact(selected, known)
      instances.each -> (hint) auto_add_fact(selected, hint)
      proof = auto_search_root(goal, selected, terms, true)
      if proof != nil
        return proof
      if nonlinear != nil && squares
        proof = auto_square_arithmetic(goal, nonlinear, selected)
        if proof != nil
          return proof
    # Preserve the general search when matching existing operands is insufficient.
    hints.each -> (hint) auto_add_fact(facts, hint)
    proof = auto_search_root(goal, facts, terms, true)
    if proof != nil || nonlinear == nil
      return proof
    if squares
      return auto_square_arithmetic(goal, nonlinear, facts)
    # The hint fallback follows the ordinary local-context attempt.
    if hints.size == 0
      proof = auto_nonlinear_premise(goal, nonlinear)
      if proof != nil
        return proof
    # Only root saturation facts survive here. Branch-local assumptions stayed
    # in copied fact arrays and cannot enter a later arithmetic certificate.
    auto_nonlinear_premise(goal, nonlinear, facts)

  # Prioritize quantified hints whose arithmetic operands already occur here.
  # Match whole applications to infer correlated arguments, retaining guards.
  -> auto_hint_instances(goal, hints, terms, left_only = false, match_guards = false)
    out = []
    budget = 32
    joined_out = []
    join_budget = 16
    hints.each -> (hint)
      if dest_unop(hint.concl, "∀") != nil && out.size < 8 && budget > 0
        fixed = []
        hint.hyps.each -> (h) tm_tyvars_into(h, fixed)
        tm_frees(hint.concl).each -> (v) tm_tyvars_into(v, fixed)
        used_types = {}
        (goal.all_terms + [hint.concl]).each -> (t)
          tm_tyvars(t).each -> (name) used_types[name] = true
        ren = {}
        tvs = {}
        tm_tyvars(hint.concl).each -> (name)
          if !fixed.include?(name)
            fresh = fresh_name_from_set("§hint_" + name, used_types)
            ren[name] = ty_var(fresh)
            tvs[fresh] = true
        th = @k.inst_type(hint, ren)
        names = {}
        (goal.all_terms + [th.concl] + th.hyps).each -> (t) tm_free_names_into(t, names)
        vars = []
        pvars = {}
        quant = dest_unop(th.concl, "∀")
        while quant != nil && quant.tag == :lam && vars.size < 8
          v = mk_var(fresh_name_from_set("?hint", names), quant.ty)
          vars.push(v)
          pvars[v.vkey] = true
          th = @k.spec(v, th)
          quant = dest_unop(th.concl, "∀")
        conclusion = th.concl
        guards = []
        implication = dest_binop(conclusion, "⇒")
        while implication != nil
          guards.push(implication[0])
          conclusion = implication[1]
          implication = dest_binop(conclusion, "⇒")
        patterns = []
        if !left_only && numeric_disequality?(conclusion)
          conclusion = conclusion.b
        if quant == nil && comparison?(conclusion)
          equality = @k.dest_eq(conclusion)
          if left_only
            if equality != nil && vars.all?(-> (v) tm_free_in?(v, equality[0]))
              patterns.push(equality[0])
          else
            auto_collect_terms(conclusion, patterns)
        patterns.each -> (pattern)
          if pattern.tag == :app && numeric_type?(type_of(pattern))
            head = strip_app(pattern)[0]
            terms.each -> (term)
              target_head = strip_app(term)[0]
              if term.tag == :app && (!left_only || ty_eq(type_of(pattern), type_of(term))) && (head.tag == :var || (target_head.tag == :const && head.name == target_head.name)) && out.size < 8 && budget > 0
                budget -= 1
                mt = Matcher.new(pvars, tvs)
                if mt.m(pattern, term, 0)
                  if vars.all?(-> (v) mt.tm.has_key?(v.vkey))
                    instance = @k.inst(@k.inst_type(th, mt.ty), mt.pairs)
                    auto_add_fact(out, instance)
                  elsif !left_only && join_budget > 0
                    # Independent operands can determine different binders,
                    # as in 1/a ≤ 1/b. Join two matches within the same fuel.
                    endpoints = dest_cmp_rel(conclusion)
                    [endpoints[1], endpoints[2]].each -> (other)
                      if other.tag == :app && vars.any?(-> (v) !mt.tm.has_key?(v.vkey) && tm_free_in?(v, other))
                        other_head = strip_app(other)[0]
                        terms.each -> (candidate)
                          candidate_head = strip_app(candidate)[0]
                          if candidate.tag == :app && candidate_head.tag == :const && other_head.tag == :const && candidate_head.name == other_head.name && joined_out.size < 8 && join_budget > 0
                            join_budget -= 1
                            joined = mt.clone
                            if joined.m(other, candidate, 0) && vars.all?(-> (v) joined.tm.has_key?(v.vkey))
                              instance = @k.inst(@k.inst_type(th, joined.ty), joined.pairs)
                              auto_add_fact(joined_out, instance)
        # A known guard can determine correlated arguments even when the
        # bound's endpoint occurs only after arithmetic normalization.
        # Keep the implication intact: matching a guard does not prove it.
        if match_guards && !left_only && quant == nil
          guards.each -> (guard)
            if guard.tag == :app
              goal.hyps.each -> (hyp)
                if out.size < 8 && budget > 0
                  budget -= 1
                  mt = Matcher.new(pvars, tvs)
                  if mt.m(guard, hyp[1], 0) && vars.all?(-> (v) mt.tm.has_key?(v.vkey))
                    auto_add_fact(out, @k.inst(@k.inst_type(th, mt.ty), mt.pairs))
    # Keep the original complete matches first; joined operands fill spare slots.
    joined_out.each -> (instance)
      if out.size < 8
        auto_add_fact(out, instance)
    out

  # Split only on existing atomic propositions, with a shared case budget.
  # Each branch is an ordinary kernel proof and excluded_middle supplies the split.
  -> auto_classical(goal, facts, terms, used, depth, budget, try_direct)
    if try_direct
      proof = auto_search(goal, facts + [], terms, [], 3, [24])
      if proof != nil
        return proof
    if depth <= 0 || budget[0] <= 0
      return nil
    i = 0
    while i < terms.size && budget[0] > 0
      atom = terms[i]
      if ty_eq(type_of(atom), ty_bool) && !is_const?(atom, "⊤") && !is_const?(atom, "⊥") && dest_unop(atom, "¬") == nil && dest_unop(atom, "∀") == nil && dest_unop(atom, "∃") == nil && dest_binop(atom, "∧") == nil && dest_binop(atom, "∨") == nil && dest_binop(atom, "⇒") == nil
        # Splitting a fact already known true or false repeats the same
        # quantified search in its live branch and adds no information.
        seen = facts.any? -> (th) tm_eq(th.concl, atom) || (dest_unop(th.concl, "¬") != nil && tm_eq(dest_unop(th.concl, "¬"), atom))
        used.each -> (old)
          if tm_eq(old, atom)
            seen = true
        if !seen
          budget[0] -= 1
          next_used = used + [atom]
          yes = auto_classical(goal, facts + [@k.assume(atom)], terms, next_used, depth - 1, budget, true)
          if yes != nil
            no = auto_classical(goal, facts + [@k.assume(@k.neg_tm(atom))], terms, next_used, depth - 1, budget, true)
            if no != nil
              return @k.disj_cases(@k.excluded_middle(atom), yes, no)
      i += 1
    nil

  -> auto_type_patterns(t, flexible, out)
    if out.size >= 16
      return 0
    if t.tag == :const
      if t.name != "∀" && t.name != "∃" && tm_tyvars(t).any?(-> (name) flexible.has_key?(name)) && !out.any?(-> (old) tm_eq(old, t))
        out.push(t)
    elsif t.tag == :app
      auto_type_patterns(t.a, flexible, out)
      auto_type_patterns(t.b, flexible, out)
    elsif t.tag == :lam
      auto_type_patterns(t.b, flexible, out)
    0

  # A first-order recurrence should specialize at indices of its sequence
  # already in scope, plus literal cases. Unrelated natural coefficients are
  # not useful indices. Other quantified facts retain the general search.
  -> auto_recurrence_witnesses(quant, terms)
    if !ty_eq(quant.ty, ty_nat)
      return nil
    index = mk_var(fresh_name("recurrence_index", [quant] + terms), ty_nat)
    body = tm_instantiate(quant.b, index, 0)
    equation = @k.dest_eq(body)
    if equation == nil || !numeric_type?(type_of(equation[0]))
      return nil
    [false, true].each -> (reverse)
      side = equation[reverse ? 1 : 0]
      other = equation[reverse ? 0 : 1]
      spine = strip_app(side)
      head = spine[0]
      args = spine[1]
      if head.tag == :var || (head.tag == :const && head.op == OP_NONE)
        position = -1
        valid = true
        current = []
        args.each_with_index -> (arg, i)
          successor = dest_unop(arg, "succ")
          addition = dest_binop(arg, "+")
          shifted = (successor != nil && tm_eq(successor, index)) || (addition != nil && tm_eq(addition[0], index) && addition[1].tag == :lit && addition[1].val == 1)
          if shifted && position == -1
            position = i
            current.push(index)
          else
            if tm_free_in?(index, arg)
              valid = false
            current.push(arg)
        if valid && position >= 0
          previous = mk_apps(head, current)
          parts = []
          auto_collect_terms(other, parts)
          if parts.any?(-> (term) tm_eq(term, previous))
            selected = []
            matched = false
            terms.each -> (term)
              if term.tag == :lit && ty_eq(type_of(term), ty_nat) && !selected.any?(-> (old) tm_eq(old, term))
                selected.push(term)
              target = strip_app(term)
              if target[1].size == args.size && tm_eq(target[0], head)
                same = true
                args.each_with_index -> (arg, i)
                  if i != position && !tm_eq(arg, target[1][i])
                    same = false
                if same
                  witness = target[1][position]
                  if ty_eq(type_of(witness), ty_nat)
                    matched = true
                    if !selected.any?(-> (old) tm_eq(old, witness))
                      selected.push(witness)
            if matched
              return selected
    nil

  # Infer reusable type parameters from typed symbols already in scope.
  # Hypotheses and supplied free terms fix their types, as in theorem application.
  -> auto_specialize_fact(th, quant, terms, facts)
    if facts.size >= 128
      return
    witnesses = auto_recurrence_witnesses(quant, terms)
    if witnesses == nil
      witnesses = terms
    witnesses.each -> (term)
      if facts.size < 128 && ty_eq(quant.ty, type_of(term))
        auto_add_fact(facts, @k.spec(term, th))
    fixed = []
    th.hyps.each -> (hyp) tm_tyvars_into(hyp, fixed)
    tm_frees(th.concl).each -> (term) tm_tyvars_into(term, fixed)
    flexible = {}
    tm_tyvars(th.concl).each -> (name)
      if !fixed.include?(name)
        flexible[name] = true
    if flexible.size == 0
      return 0
    patterns = []
    auto_type_patterns(th.concl, flexible, patterns)
    instances = []
    terms.each -> (term)
      if term.tag == :const
        patterns.each -> (pattern)
          if instances.size < 8 && pattern.name == term.name
            matcher = Matcher.new({}, flexible)
            if matcher.match_ty(pattern.ty, term.ty)
              instance = @k.inst_type(th, matcher.ty)
              if !tm_eq(instance.concl, th.concl) && !instances.any?(-> (old) tm_eq(old.concl, instance.concl))
                instances.push(instance)
    # A purely logical rule may have no matching typed symbol in the goal.
    if instances.size == 0
      terms.each -> (term)
        if instances.size < 8
          matcher = Matcher.new({}, flexible)
          if matcher.match_ty(quant.ty, type_of(term))
            instance = @k.inst_type(th, matcher.ty)
            if !tm_eq(instance.concl, th.concl) && !instances.any?(-> (old) tm_eq(old.concl, instance.concl))
              instances.push(instance)
    instances.each -> (instance)
      binder = dest_unop(instance.concl, "∀")
      terms.each -> (term)
        if ty_eq(binder.ty, type_of(term))
          auto_add_fact(facts, @k.spec(term, instance))
    0

  # Only already loaded, closed rules with the standard checked oracles may
  # enter implicit search. Named assumptions remain explicit hints.
  -> auto_loaded_rule(name)
    th = @session.theorems[name]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0
      return nil
    th.tags.each -> (tag)
      if tag != "oracle:arith" && tag != "oracle:ring"
        return nil
    th

  -> auto_abs_bounds(th)
    cmp = dest_cmp_rel(th.concl)
    if cmp == nil || (cmp[0] != "≤" && cmp[0] != "<")
      return nil
    value = dest_unop(cmp[1], "abs")
    if value == nil || !["int", "rat", "real"].include?(type_of(value).name)
      return nil
    name = cmp[0] == "≤" ? "abs_le." : "abs_lt."
    rule = auto_loaded_rule(name + type_of(value).name)
    if rule == nil
      return nil
    begin
      return @k.eq_mp(@k.spec(cmp[2], @k.spec(value, rule)), th)
    rescue e
      nil

  # Supply checked endpoint bounds only for min/max terms already present in
  # a comparison. Closed-term collection and the existing fact cap bound this
  # enrichment; no new min/max applications or branch assumptions are invented.
  -> auto_minmax_facts(conclusion, facts)
    if (conclusion.search_ops & TERM_MINMAX) == 0
      return false
    cmp = dest_cmp_rel(conclusion)
    if cmp == nil
      return false
    terms = []
    auto_collect_terms(cmp[1], terms)
    auto_collect_terms(cmp[2], terms)
    added = false
    terms.each -> (term)
      spine = strip_app(term)
      if spine[0].tag == :const && ["min", "max"].include?(spine[0].name) && spine[1].size == 2
        suffix = type_of(term).name
        if ["nat", "int", "rat", "real"].include?(suffix)
          prefix = spine[0].name == "min" ? "min_le_" : "le_max_"
          ["left", "right"].each -> (side)
            rule = auto_loaded_rule(prefix + side + "." + suffix)
            if rule != nil
              begin
                th = @k.spec(spine[1][1], @k.spec(spine[1][0], rule))
                if auto_add_fact(facts, th)
                  added = true
              rescue e
                0
    added

  -> auto_introduce_search(goal, facts, terms, used, depth, budget, arithmetic)
    if depth <= 0 || budget[0] <= 0
      return nil
    if dest_unop(goal.concl, "∀") != nil || dest_binop(goal.concl, "⇒") != nil
      facts.each -> (known)
        if tm_eq(known.concl, goal.concl)
          return known
    universal = dest_unop(goal.concl, "∀")
    if universal != nil && universal.tag == :lam && budget[0] > 0
      budget[0] -= 1
      v = auto_fresh(goal, facts, terms, universal.ty)
      body = tm_instantiate(universal.b, v, 0)
      proof = auto_search(goal.with_concl(body), facts + [], terms + [v], used, depth - 1, budget, arithmetic)
      if proof != nil
        return @k.gen(v, proof)
    implication_goal = dest_binop(goal.concl, "⇒")
    if implication_goal != nil && budget[0] > 0
      budget[0] -= 1
      proof = auto_search(goal.with_concl(implication_goal[1]), facts + [@k.assume(implication_goal[0])], terms, used, depth - 1, budget, arithmetic)
      if proof != nil
        return @k.disch(implication_goal[0], proof)
    nil

  # Quantified bounds can generate a Cartesian product of instances. Before
  # saturating, try the origin and signed coordinate unit vectors. An assignment
  # prunes this forward search only when it satisfies every supplied fact and
  # falsifies the goal. Universal premises need symbolic justification.
  -> auto_arithmetic_counterexample(goal, facts)
    if facts.size == 0 || facts.size > 12 || goal.fixes.size > 8 || !comparison?(goal.concl)
      return false
    if !facts.any?(-> (th) dest_unop(th.concl, "∀") != nil)
      return false
    nodes = [1024]
    if !auto_small_term?(goal.concl, nodes) || !facts.all?(-> (th) auto_small_term?(th.concl, nodes))
      return false
    vars = goal.fixes.map(-> (entry) entry[1]).select(-> (v) numeric_type?(v.ty))
    assignment = {}
    vars.each -> (v) assignment[v.vkey] = model_integer(v.ty, 0)
    begin
      if model_witness?(goal, facts, assignment)
        return true
      vars.each -> (v)
        values = v.ty.name == "nat" ? [1] : [1, -1]
        values.each -> (n)
          assignment[v.vkey] = model_integer(v.ty, n)
          if model_witness?(goal, facts, assignment)
            return true
        assignment[v.vkey] = model_integer(v.ty, 0)
    rescue e
      return false
    false

  -> model_witness?(goal, facts, assignment)
    fuel = [96]
    model_truth(goal.concl, assignment, fuel) == false && facts.all?(-> (th) model_truth(th.concl, assignment, fuel) == true)

  -> model_integer(ty, n)
    mk_lit(ty.name == "nat" || ty.name == "int" ? n : [n, 1], ty)

  -> model_truth(term, assignment, fuel)
    fuel[0] -= 1
    if fuel[0] < 0
      return nil
    guard = dest_binop(term, "⇒")
    if guard != nil
      conclusion = model_truth(guard[1], assignment, fuel)
      if conclusion == true
        return true
      premise = model_truth(guard[0], assignment, fuel)
      if premise == false
        return true
      return premise == true ? conclusion : nil
    body = term
    types = []
    binder = dest_unop(body, "∀")
    while binder != nil && binder.tag == :lam && numeric_type?(binder.ty)
      types.push(binder.ty)
      body = binder.b
      binder = dest_unop(body, "∀")
    result = model_comparison(body, assignment)
    if result != nil || types.size == 0 || types.size > 4
      return result
    # One exact false instance refutes a universal. Finite successes leave it
    # unknown. Symbolic normalization above is what can establish it for all.
    unit = -1
    while unit < types.size
      instance = body
      i = types.size - 1
      while i >= 0
        instance = tm_instantiate(instance, model_integer(types[i], i == unit ? 1 : 0), types.size - 1 - i)
        i -= 1
      if model_comparison(instance, assignment) == false
        return false
      unit += 1
    nil

  -> model_comparison(term, assignment)
    cmp = dest_cmp_rel(term)
    if cmp == nil || !numeric_type?(type_of(cmp[1]))
      return nil
    kind = type_of(cmp[1]).name
    nodes = [128]
    recurrence_ring_cost(cmp[1], kind, nodes)
    recurrence_ring_cost(cmp[2], kind, nodes)
    ctx = RingCtx.new("rat")
    left = ring_norm(tm_subst(cmp[1], assignment), kind, ctx)
    right = ring_norm(tm_subst(cmp[2], assignment), kind, ctx)
    diff = poly_add(right, poly_scale(left, Q_NEG_ONE))
    if diff.size > 0 && (diff.size != 1 || diff[0] == nil)
      return nil
    sign = diff.size == 0 ? 0 : diff[0][0]
    case cmp[0]
    when "<"
      sign > 0
    when "≤"
      sign >= 0
    else
      sign == 0

  # Read n = m*q + r under an existential. Only q may refer to the binder.
  -> quotient_pattern(ex)
    if ex.ty != TY_NAT_SINGLETON && ex.ty != TY_INT_SINGLETON
      return nil
    sides = dest_binop(ex.b, "=")
    if sides == nil
      return nil
    reversed = !tm_closed_bound?(sides[0])
    n = reversed ? sides[1] : sides[0]
    body = reversed ? sides[0] : sides[1]
    remainder = mk_lit(0, ex.ty)
    sum = dest_binop(body, "+")
    if sum != nil
      offset_first = tm_closed_bound?(sum[0])
      remainder = offset_first ? sum[0] : sum[1]
      body = offset_first ? sum[1] : sum[0]
    product = dest_binop(body, "*")
    if product == nil
      return nil
    witness_first = product[0].tag == :bnd
    witness = witness_first ? product[0] : product[1]
    modulus = witness_first ? product[1] : product[0]
    if witness.tag != :bnd || witness.idx != 0 || !tm_closed_bound?(n) || !tm_closed_bound?(modulus) || !tm_closed_bound?(remainder)
      return nil
    [n, modulus, remainder]

  -> auto_quotient_witness(goal, ex, facts, terms, budget)
    pattern = quotient_pattern(ex)
    if pattern == nil || budget[0] <= 0
      return nil
    division = auto_loaded_rule("div_add_mod." + ex.ty.name)
    if division == nil
      return nil
    begin
      operators = ty_funs([ex.ty, ex.ty], ex.ty)
      n = pattern[0]
      modulus = pattern[1]
      rem = mk_apps(@k.mk_const("%", operators), [n, modulus])
      required = @k.eq_tm(rem, pattern[2])
      budget[0] -= 1
      # The enclosing search already saturated the facts. A shallow residue
      # check leaves other witnesses available if n/m does not fit.
      residue = auto_search(goal.with_concl(required), facts + [], terms, [], 0, [1])
      if residue == nil
        return nil
      quotient = mk_apps(@k.mk_const("/", operators), [n, modulus])
      body = tm_instantiate(ex.b, quotient, 0)
      division = @k.spec(modulus, @k.spec(n, division))
      proof = auto_arithmetic_proof(goal.with_concl(body), [division, residue], [1])
      proof == nil ? nil : @k.exists_intro(goal.concl, quotient, proof)
    rescue e
      nil

  -> auto_search_root(goal, facts, terms, arithmetic = false)
    proof = auto_search(goal, facts, terms, [], 3, [24], arithmetic ? [24] : nil)
    target = dest_unop(goal.concl, "∃")
    if proof != nil || target == nil || target.tag != :lam
      return proof
    # After ordinary witness search, the root facts include proved instances
    # of hints. Open one existential and try its witness directly in the goal.
    budget = [12]
    solver = arithmetic ? [12] : nil
    facts.each -> (th)
      source = dest_unop(th.concl, "∃")
      if source != nil && source.tag == :lam && ty_eq(source.ty, target.ty) && budget[0] > 0
        budget[0] -= 1
        witness = auto_fresh(goal, facts, terms, source.ty)
        given = tm_instantiate(source.b, witness, 0)
        required = tm_instantiate(target.b, witness, 0)
        body = auto_search(goal.with_concl(required), facts + [@k.assume(given)], [witness] + terms, [th.concl], 2, budget, solver)
        if body != nil
          return @k.choose(witness, th, @k.exists_intro(goal.concl, witness, body))
    auto_interval_witness(goal, target, facts)

  -> auto_search(goal, facts, terms, used, depth, budget, arithmetic = nil)
    if auto_arithmetic_counterexample(goal, facts)
      return nil
    # Guard goals introduce their binders before spending arithmetic fuel on
    # unrelated instances of the surrounding range hypotheses.
    if arithmetic != nil
      proof = auto_introduce_search(goal, facts, terms, used, depth, budget, arithmetic)
      if proof != nil
        return proof
    residue = literal_residue(goal.concl)
    implications = []
    negations = []
    exclusions = []
    i = 0
    while true
      while i < facts.size
        th = facts[i]
        if tm_eq(th.concl, goal.concl)
          return th
        if residue != nil
          equation = residue_from_fact(residue[0], literal_residue(th.concl), th, residue[1])
          proof = finish_residue(residue, equation)
          if proof != nil
            return proof
        fitted = try_square_fit(th, goal.concl)
        if fitted != nil
          return fitted
        if is_const?(th.concl, "⊥")
          return @k.false_elim(th, goal.concl)
        if dest_binop(th.concl, "∧") != nil
          auto_add_fact(facts, @k.conj1(th))
          auto_add_fact(facts, @k.conj2(th))
        bounds = auto_abs_bounds(th)
        if bounds != nil
          auto_add_fact(facts, bounds)
        if arithmetic != nil
          auto_minmax_facts(th.concl, facts)
        quant = dest_unop(th.concl, "∀")
        if quant != nil && quant.tag == :lam
          auto_specialize_fact(th, quant, terms, facts)
        imp = dest_binop(th.concl, "⇒")
        neg = dest_unop(th.concl, "¬")
        implications.push(imp)
        negations.push(neg)
        if neg != nil && dest_unop(neg, "∃") != nil
          exclusions.push(th)
        # Check both directions because either premise may have arrived last.
        j = 0
        while j <= i
          other = facts[j]
          if imp != nil && tm_eq(imp[0], other.concl)
            auto_add_fact(facts, @k.mp(th, other))
          imp2 = implications[j]
          if imp2 != nil && tm_eq(imp2[0], th.concl)
            auto_add_fact(facts, @k.mp(other, th))
          if neg != nil && tm_eq(neg, other.concl)
            return @k.false_elim(@k.not_elim(th, other), goal.concl)
          neg2 = negations[j]
          if neg2 != nil && tm_eq(neg2, th.concl)
            return @k.false_elim(@k.not_elim(other, th), goal.concl)
          j += 1
        i += 1
      changed = auto_equal_mp(facts)
      if arithmetic != nil
        if auto_arithmetic_congruence(terms, facts, arithmetic)
          changed = true
        proof = auto_arithmetic_proof(goal, facts, arithmetic)
        if proof != nil
          return proof
        # Discharge instantiated guards using only already checked facts.
        # Retry after new consequences arrive, within the shared solver budget.
        attempted = []
        facts.each -> (rule)
          implication = dest_binop(rule.concl, "⇒")
          if implication != nil && !facts.any?(->(th) tm_eq(th.concl, implication[1]))
            guard = nil
            facts.each -> (known)
              if tm_eq(known.concl, implication[0])
                guard = known
            if guard == nil && !attempted.any?(->(term) tm_eq(term, implication[0]))
              attempted.push(implication[0])
              guard = auto_arithmetic_proof(goal.with_concl(implication[0]), facts, arithmetic)
              # Induction hypotheses often require a bounded universal premise.
              # Prove it in a detached search, sharing fuel and cycle detection.
              structured = dest_unop(implication[0], "∀") != nil || dest_binop(implication[0], "⇒") != nil || dest_binop(implication[0], "∧") != nil
              if guard == nil && structured && depth > 0 && budget[0] > 0 && !used.any?(-> (old) tm_eq(old, rule.concl))
                budget[0] -= 1
                guard = auto_search(goal.with_concl(implication[0]), facts + [], terms, used + [rule.concl], depth - 1, budget, arithmetic)
            if guard != nil
              auto_add_fact(facts, guard)
              if auto_add_fact(facts, @k.mp(rule, guard))
                changed = true
      if !changed
        break
    proof = auto_residue_facts(goal.concl, residue, facts)
    if proof != nil
      return proof
    graph = auto_equality_graph(facts)
    # A negated conjunction contradicts its two known components.
    ni = 0
    while ni < facts.size
      neg_th = facts[ni]
      neg = dest_unop(neg_th.concl, "¬")
      pair = nil
      if neg != nil
        pair = dest_binop(neg, "∧")
      if pair != nil
        left = nil
        right = nil
        facts.each -> (candidate)
          if left == nil
            eq = auto_equal(candidate.concl, pair[0], facts, 16, graph)
            if eq != nil
              left = @k.eq_mp(eq, candidate)
          if right == nil
            eq = auto_equal(candidate.concl, pair[1], facts, 16, graph)
            if eq != nil
              right = @k.eq_mp(eq, candidate)
        if left != nil && right != nil
          return @k.false_elim(@k.not_elim(neg_th, @k.conj(left, right)), goal.concl)
      ni += 1
    target_eq = @k.dest_eq(goal.concl)
    if target_eq != nil
      proof = auto_equal(target_eq[0], target_eq[1], facts, 16, graph)
      if proof != nil
        return proof
    facts.each -> (th)
      proof = auto_equal(th.concl, goal.concl, facts, 16, graph)
      if proof != nil
        return @k.eq_mp(proof, th)
    alternatives = dest_binop(goal.concl, "∨")
    if alternatives != nil
      facts.each -> (th)
        left_eq = auto_equal(th.concl, alternatives[0], facts, 16, graph)
        if left_eq != nil
          return @k.disj1(@k.eq_mp(left_eq, th), alternatives[1])
        right_eq = auto_equal(th.concl, alternatives[1], facts, 16, graph)
        if right_eq != nil
          return @k.disj2(alternatives[0], @k.eq_mp(right_eq, th))
    if depth > 0
      if arithmetic == nil
        proof = auto_introduce_search(goal, facts, terms, used, depth, budget, arithmetic)
        if proof != nil
          return proof
      negation_goal = dest_unop(goal.concl, "¬")
      if negation_goal != nil && budget[0] > 0
        budget[0] -= 1
        proof = auto_search(goal.with_concl(@k.false_tm), facts + [@k.assume(negation_goal)], terms, used, depth - 1, budget, arithmetic)
        if proof != nil
          return @k.not_intro(negation_goal, proof)
      conjunction = dest_binop(goal.concl, "∧")
      if conjunction != nil && budget[0] > 0
        budget[0] -= 1
        left = auto_search(goal.with_concl(conjunction[0]), facts + [], terms, used, depth - 1, budget, arithmetic)
        if left != nil
          right = auto_search(goal.with_concl(conjunction[1]), facts + [], terms, used, depth - 1, budget, arithmetic)
          if right != nil
            return @k.conj(left, right)
      existential = dest_unop(goal.concl, "∃")
      if existential != nil && existential.tag == :lam
        proof = auto_quotient_witness(goal, existential, facts, terms, budget)
        if proof != nil
          return proof
        ti = 0
        while ti < terms.size && budget[0] > 0
          witness = terms[ti]
          if ty_eq(existential.ty, type_of(witness))
            budget[0] -= 1
            body = tm_instantiate(existential.b, witness, 0)
            proof = auto_search(goal.with_concl(body), facts + [], terms, used, depth - 1, budget, arithmetic)
            if proof != nil
              return @k.exists_intro(goal.concl, witness, proof)
          ti += 1
      # Work backwards from a relevant implication, then prove its premise.
      # Remember attempted implications to stop cycles such as p → q → p.
      ii = 0
      while ii < facts.size && budget[0] > 0
        implication = facts[ii]
        imp = dest_binop(implication.concl, "⇒")
        if imp != nil
          seen = false
          used.each -> (old)
            if tm_eq(old, implication.concl)
              seen = true
          if !seen
            consequent_eq = auto_equal(imp[1], goal.concl, facts, 16, graph)
            if consequent_eq != nil
              budget[0] -= 1
              premise = auto_search(goal.with_concl(imp[0]), facts + [], terms, used + [implication.concl], depth - 1, budget, arithmetic)
              if premise != nil
                return @k.eq_mp(consequent_eq, @k.mp(implication, premise))
        ii += 1
      fi = 0
      while fi < facts.size && budget[0] > 0
        th = facts[fi]
        ex = dest_unop(th.concl, "∃")
        if ex != nil && ex.tag == :lam
          seen = false
          used.each -> (old)
            if tm_eq(old, th.concl)
              seen = true
          if !seen
            budget[0] -= 1
            witness = auto_fresh(goal, facts, terms, ex.ty)
            body = tm_instantiate(ex.b, witness, 0)
            proof = auto_search(goal, facts + [@k.assume(body)], terms + [witness], used + [th.concl], depth - 1, budget, arithmetic)
            if proof != nil
              return @k.choose(witness, th, proof)
        fi += 1
      facts.each -> (th)
        disj = dest_binop(th.concl, "∨")
        if disj != nil && budget[0] > 0
          seen = false
          used.each -> (old)
            if tm_eq(old, th.concl)
              seen = true
          if !seen
            budget[0] -= 1
            next_used = used + [th.concl]
            left_facts = facts + [@k.assume(disj[0])]
            left = auto_search(goal, left_facts, terms, next_used, depth - 1, budget, arithmetic)
            if left != nil
              right_facts = facts + [@k.assume(disj[1])]
              right = auto_search(goal, right_facts, terms, next_used, depth - 1, budget, arithmetic)
              if right != nil
                return @k.disj_cases(th, left, right)
      # A checked witness contradicts its exclusion for any conclusion.
      exclusions.each -> (th)
        if budget[0] > 0 && !used.any?(-> (old) tm_eq(old, th.concl))
          budget[0] -= 1
          exists = auto_search(goal.with_concl(th.concl.b), facts + [], terms, used + [th.concl], depth - 1, budget, arithmetic)
          if exists != nil
            return @k.false_elim(@k.not_elim(th, exists), goal.concl)
    nil

  # Expose both directions of a quantified/conditional iff, retaining every
  # binder and guard. These are derived implications, not a rewrite oracle.
  -> auto_hint_rules(goal, hint)
    th = @d.beta_norm_thm(hint)
    steps = []
    while true
      quant = dest_unop(th.concl, "∀")
      if quant != nil && quant.tag == :lam
        avoid = goal.all_terms + [th.concl] + th.hyps
        v = mk_var(fresh_name("hint", avoid), quant.ty)
        steps.push([:all, v])
        th = @k.spec(v, th)
      else
        implication = dest_binop(th.concl, "⇒")
        if implication == nil
          break
        steps.push([:imp, implication[0]])
        th = @d.undisch(th)
    equality = @k.dest_eq(th.concl)
    if equality == nil || !ty_eq(type_of(equality[0]), ty_bool)
      return [hint]
    forward = @k.disch(equality[0], @k.eq_mp(th, @k.assume(equality[0])))
    backward = @k.disch(equality[1], @k.eq_mp(@k.sym(th), @k.assume(equality[1])))
    i = steps.size - 1
    while i >= 0
      step = steps[i]
      if step[0] == :all
        forward = @k.gen(step[1], forward)
        backward = @k.gen(step[1], backward)
      else
        forward = @k.disch(step[1], forward)
        backward = @k.disch(step[1], backward)
      i -= 1
    [hint, forward, backward]

  # Index a small set of loaded arithmetic/analysis rules by the relation and
  # outer operand constructors. Bound variables are wildcard operand heads.
  -> auto_operand_head(t)
    head = strip_app(t)[0]
    if head.tag == :const
      return "c:" + head.name
    if head.tag == :lit
      return "literal"
    "*"

  # Follow only the applied head, retaining each spelling for indexed lookup.
  # This selects candidates; their application still reconstructs a checked proof.
  -> auto_operand_heads(t)
    out = []
    steps = 0
    while steps <= 8
      name = auto_operand_head(t)
      if !out.include?(name)
        out.push(name)
      if application_square?(t) && !out.include?("c:^")
        out.push("c:^")
      square = dest_binop(t, "^")
      if square != nil && square[1].tag == :lit && square[1].val == 2 && ["nat", "int", "rat", "real"].include?(type_of(square[0]).name) && !out.include?("c:*")
        out.push("c:*")
      spine = strip_app(t)
      head = spine[0]
      if steps == 8 || head.tag != :const || @k.defs[head.name] == nil
        break
      rule = make_rule(@d, @k.defs[head.name], head.name)
      conv = Simp.new(@d, [rule]).rewrite_top(head, 0)
      if conv == nil
        break
      rhs = dest_binop(conv.concl, "=")[1]
      t = @d.beta_norm_term(mk_apps(rhs, spine[1]))
      steps += 1
    out

  -> auto_rule_conclusion(t)
    while true
      quant = dest_unop(t, "∀")
      if quant != nil && quant.tag == :lam
        t = quant.b
      else
        implication = dest_binop(t, "⇒")
        if implication == nil
          break
        t = implication[1]
    t

  -> auto_rule_spine(t)
    spine = strip_app(auto_rule_conclusion(t))
    if spine[0].tag != :const || !["=", "≤", "<"].include?(spine[0].name) || spine[1].size != 2
      return nil
    spine

  -> auto_rule_shape(t)
    spine = auto_rule_spine(t)
    if spine == nil
      return nil
    [spine[0].name, auto_operand_head(spine[1][0]), auto_operand_head(spine[1][1]), ty_show(type_of(spine[1][0]))]

  -> auto_logic_key(conclusion)
    head = strip_app(conclusion)[0]
    head.tag == :const ? "logic|" + head.name : "*"

  # Prefer reflexivity or a matching pair of operand constructors for a
  # user-defined relation. The ordinary bucket still supplies every fallback.
  -> auto_relation_operand_key(term)
    if term.tag != :app
      return nil
    # Existential rules with different witness predicates share the ∃ head.
    # Prefer a rule with the same binder count and visible predicate.
    binder = dest_unop(term, "∃")
    if binder != nil
      count = 0
      while binder != nil && binder.tag == :lam
        count += 1
        term = binder.b
        binder = dest_unop(term, "∃")
      head = strip_app(term)[0]
      if count > 0 && head.tag == :const
        key = "exists|" + count.to_s + "|" + head.name
        pair = dest_binop(term, "∧")
        if pair != nil
          property = strip_app(auto_rule_conclusion(pair[0]))[0]
          if property.tag == :const
            return key + "|" + property.name
        return key
      return nil
    spine = strip_app(term)
    head = spine[0]
    if head.tag != :const || head.op != OP_NONE
      return nil
    # Rules such as continuity under addition and multiplication have the
    # same predicate head. Prefer the rule for the body's outer operation.
    first = spine[1][0]
    if first.tag == :lam
      body = first.b
      key = "lambda|" + head.name + "|"
      if body.tag == :bnd
        return key + (body.idx == 0 ? "id" : "const")
      if body.mx == 0
        return key + "const"
      op = strip_app(body)[0]
      if op.tag == :const
        return key + "op:" + op.name
    elsif first.tag == :app && type_of(first).fun?
      op = strip_app(first)[0]
      if op.tag == :const
        return "lambda|" + head.name + "|op:" + op.name
    if term.a.tag != :app
      return nil
    a = term.a.b
    b = term.b
    if tm_eq(a, b)
      return "refl|" + head.name
    if a.tag != :app || b.tag != :app
      return nil
    left = strip_app(a)[0]
    right = strip_app(b)[0]
    if left.tag != :const || right.tag != :const
      return nil
    "relation|" + head.name + "|" + left.name + "|" + right.name

  # All registered rules are closed. Their projections and index keys depend
  # only on the library, so detached searches can share one session index.
  -> build_registered_index
    index = {}
    context = Goal.new([], [], @k.false_tm)
    @session.auto_rules.each -> (name, th)
      begin
        auto_relation_parts(th, [32]).each -> (part)
          auto_hint_rules(context, part).each -> (rule)
            conclusion = auto_rule_conclusion(rule.concl)
            shape = auto_rule_shape(conclusion)
            if shape == nil
              keys = [auto_logic_key(conclusion)]
              specific = auto_relation_operand_key(conclusion)
              if specific != nil
                keys.push(specific)
            else
              if ty_vars(type_of(conclusion.a.b)).size > 0
                shape[3] = "*"
              keys = ["math|" + shape.join("|")]
              [[shape[0], shape[1], "?rhs", shape[3]], [shape[0], "?lhs", shape[2], shape[3]]].each -> (parts)
                keys.push("math|" + parts.join("|"))
            entry = [name, th, rule]
            keys.each -> (key)
              if index[key] == nil
                index[key] = []
              index[key].push(entry)
      rescue e
        0
    index

  -> auto_registered_hints(goal, side = nil)
    index = @session.auto_rule_index
    if index == nil
      index = build_registered_index
      @session.auto_rule_index = index
    keys = side == nil ? ["*"] : []
    shape = auto_rule_shape(goal.concl)
    if shape != nil
      spine = auto_rule_spine(goal.concl)
      lefts = side == :right ? ["?lhs"] : auto_operand_heads(spine[1][0]) + ["*"]
      rights = side == :left ? ["?rhs"] : auto_operand_heads(spine[1][1]) + ["*"]
      [shape[3], "*"].each -> (ty)
        lefts.each -> (left)
          rights.each -> (right)
            key = "math|" + [shape[0], left, right, ty].join("|")
            if !keys.include?(key)
              keys.push(key)
    else
      conclusion = auto_rule_conclusion(goal.concl)
      specific = auto_relation_operand_key(conclusion)
      if specific != nil
        keys = [specific] + keys
      keys.push(auto_logic_key(conclusion))
    out = []
    keys.each -> (key)
      bucket = index[key]
      if bucket != nil
        bucket.each -> (entry)
          # Shadowing a name does not transfer its old registration.
          if @session.theorems[entry[0]] == entry[1]
            auto_add_fact(out, entry[2])
    out

  # Compare open terms before specializing any theorem. The same binders and
  # guards must surround the requested conjunct on both sides.
  -> pointwise_conjunct_path(source, target, fuel)
    if fuel[0] <= 0
      return nil
    fuel[0] -= 1
    if tm_eq(source, target)
      return []
    pair = dest_binop(source, "∧")
    if pair != nil
      left = pointwise_conjunct_path(pair[0], target, fuel)
      if left != nil
        return [:left] + left
      right = pointwise_conjunct_path(pair[1], target, fuel)
      return right == nil ? nil : [:right] + right
    quant = dest_unop(source, "∀")
    if quant != nil && quant.tag == :lam
      want = dest_unop(target, "∀")
      if want != nil && want.tag == :lam && ty_eq(quant.ty, want.ty)
        tail = pointwise_conjunct_path(quant.b, want.b, fuel)
        return tail == nil ? nil : [:all] + tail
    guard = dest_binop(source, "⇒")
    if guard != nil
      want = dest_binop(target, "⇒")
      if want != nil && tm_eq(guard[0], want[0])
        tail = pointwise_conjunct_path(guard[1], want[1], fuel)
        return tail == nil ? nil : [:guard] + tail
    nil

  -> prove_pointwise_conjunct(th, path, i)
    if i == path.size
      return th
    case path[i]
    when :left
      return prove_pointwise_conjunct(@k.conj1(th), path, i + 1)
    when :right
      return prove_pointwise_conjunct(@k.conj2(th), path, i + 1)
    when :all
      v = dest_lam_fresh(dest_unop(th.concl, "∀"), [th.concl] + th.hyps)[0]
      return @k.gen(v, prove_pointwise_conjunct(@k.spec(v, th), path, i + 1))
    else
      p = dest_binop(th.concl, "⇒")[0]
      @k.disch(p, prove_pointwise_conjunct(@k.mp(th, @k.assume(p)), path, i + 1))

  # Use the same fresh coordinates on both sides of a quantified bound.
  # A one-premise linear certificate allows rearranged polynomial terms.
  -> auto_pointwise_comparison(goal, facts)
    if !auto_small_term?(goal.concl, [160])
      return nil
    target = goal.concl
    variables = []
    binder = dest_unop(target, "∀")
    while binder != nil && binder.tag == :lam && variables.size < 3
      v = auto_fresh(goal, facts, variables, binder.ty)
      variables.push(v)
      target = tm_instantiate(binder.b, v, 0)
      binder = dest_unop(target, "∀")
    if variables.empty?() || !comparison?(target)
      return nil
    attempts = 0
    facts.each -> (fact)
      if attempts >= 6
        return nil
      if !auto_small_term?(fact.concl, [160])
        next
      source = fact
      i = 0
      while i < variables.size
        quant = dest_unop(source.concl, "∀")
        if quant == nil || quant.tag != :lam || !ty_eq(quant.ty, variables[i].ty)
          break
        source = @k.spec(variables[i], source)
        i += 1
      if !comparison?(source.concl) || !ty_eq(type_of(source.concl.a.b), type_of(target.a.b))
        next
      attempts += 1
      begin
        if auto_binary_cost_ok?([target, source.concl])
          proof = linarith_proof(Goal.new([], [], target), [source])
          return regen(proof, variables)
      rescue e
        0
    nil

  # Registered bounds can be intermediate facts rather than the entire goal.
  # Select by existing endpoints; matching still retains every rule guard.
  -> auto_registered_arithmetic(goal, hints, budget, seen = [], known_only = false)
    if budget[0] <= 0 || !comparison?(goal.concl) || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256])
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    goal.hyps.each -> (h) auto_collect_terms(h[1], terms)
    candidates = []
    terms.each -> (term)
      if term.tag == :app && numeric_type?(type_of(term)) && candidates.size < 32
        ["=", "≤", "<"].each -> (relation)
          rel = @k.mk_const(relation, ty_funs([type_of(term), type_of(term)], ty_bool))
          probe = goal.with_concl(mk_apps(rel, [term, term]))
          [:left, :right].each -> (side)
            auto_registered_hints(probe, side).each -> (rule)
              if candidates.size < 32
                auto_add_fact(candidates, rule)
    if candidates.size == 0
      return nil
    budget[0] -= 1
    instances = auto_hint_instances(goal, candidates, terms, false, true)
    if instances.size == 0
      return nil
    supplied = hints + auto_hint_instances(goal, hints, terms, false, true)
    context = (goal.hyps.map -> (h) @k.assume(h[1])) + supplied
    if known_only
      bounds = []
      instances.each -> (instance)
        bound = instance
        imp = dest_binop(bound.concl, "⇒")
        while imp != nil
          premise = context.find(-> (th) tm_eq(th.concl, imp[0]))
          if premise == nil
            break
          bound = @k.mp(bound, premise)
          imp = dest_binop(bound.concl, "⇒")
        if imp == nil && comparison?(bound.concl)
          bounds.push(bound)
      return bounds.size == 0 ? nil : auto_arithmetic_proof(goal, context + bounds, budget)
    if !auto_arithmetic_counterexample(goal, context + instances)
      proof = auto_arithmetic_forward(goal, supplied + instances, budget)
      if proof != nil
        return proof
    # First check which suggested bound would actually close the arithmetic
    # goal. Only then spend premise-search fuel on its quantified guards.
    # The provisional assumption must be discharged by the proved bound.
    instances.each -> (instance)
      spine = auto_rule_spine(instance.concl)
      if spine != nil && budget[0] > 0
        conclusion = mk_apps(spine[0], spine[1])
        # The index looks under binders. Only a specialized comparison can
        # serve as a provisional arithmetic fact in this goal.
        if !tm_closed_bound?(conclusion)
          next
        bridge = auto_arithmetic_proof(goal, context + [@k.assume(conclusion)], budget)
        if bridge != nil
          bound = auto_hint_proof(goal.with_concl(conclusion), [instance], supplied, budget, seen + [goal.concl])
          if bound != nil
            return @d.prove_hyp(bound, bridge)
    nil

  # A quantified premise can determine a whole function whose value at the
  # goal differs syntactically, e.g. a bound on f(y) for all y > x at x.
  -> auto_quantified_bound(goal, hints, feedback = false)
    if !comparison?(goal.concl) || goal.hyps.size + hints.size > 12 || !auto_small_term?(goal.concl, [160])
      return nil
    rows = goal.hyps.select -> (h) dest_unop(h[1], "∀") != nil
    hints.each -> (th)
      if dest_unop(th.concl, "∀") != nil
        rows.push(["", th.concl])
    nodes = [384]
    if rows.empty?() || @session.auto_rules.empty?() || !rows.all?(-> (row) auto_small_term?(row[1], nodes))
      return nil
    candidates = auto_registered_hints(goal)
    # Use the quantified facts as matching patterns before spending any fuel
    # on subexpressions. The instantiated theorem still has every premise.
    instances = auto_hint_instances(Goal.new(goal.fixes, rows, goal.concl), candidates, [], false, true)
    worker = Prover.new(@session, application_conversions)
    worker.registered_search = true
    budget = [32, 4]
    attempts = 0
    instances.each -> (instance)
      if attempts >= 4 || budget[0] <= 0
        return nil
      if !auto_small_term?(instance.concl, [512])
        next
      attempts += 1
      begin
        instance = @d.beta_norm_thm(instance)
        bound = auto_rule_conclusion(instance.concl)
        if !comparison?(bound) || !tm_closed_bound?(bound) || !auto_small_term?(bound, [160])
          next
        bridge = @k.assume(bound)
        if !tm_eq(bound, goal.concl)
          if !auto_binary_cost_ok?([bound, goal.concl])
            next
          bridge = auto_arithmetic_proof(goal, [bridge], [1])
          if bridge == nil || !hyps_has?(bridge.hyps, bound)
            next
        sub = goal.with_concl(bound)
        if feedback
          applied = match_feedback_rule(sub, instance, hints, 256)
          if applied != nil
            conditional = @d.prove_hyp(applied[0], bridge)
            note = hint_premise_note(goal, [conditional, applied[1]], hints, [5], nil, 128, 4)
            if note != nil
              return note
        else
          proof = worker.auto_hint_proof(sub, [instance], hints, budget, [])
          if proof != nil
            return @d.prove_hyp(proof, bridge)
      rescue unsupported
        0
    nil

  -> auto_default_hints(goal, left_only = false)
    shape = auto_rule_shape(goal.concl)
    if shape == nil
      return []
    index = @session.auto_default_index
    if index == nil
      index = {}
      context = Goal.new([], [], @k.false_tm)
      analytic_order = ["exp_le_exp", "exp_lt_exp", "log_le_log", "log_lt_log",
        "exp_le_one_iff", "exp_lt_one", "one_le_exp_iff"]
      names = ["sum_below.congr", "sum_below.eq_of_recurrence", "sqrt_nonneg", "sqrt_pos", "sqrt_le_sqrt", "sqrt_lt_sqrt",
        "sequence.descent_on.nat", "sequence.descent_length.nat",
        "recurrence.geometric_sum.nat", "recurrence.geometric_sum_of_pos.nat",
        "sq_sqrt", "sqrt_sq", "sqrt_sq_eq_abs", "sqrt_eq_of_mul_self", "sqrt_mul",
        "sqrt_lt_iff", "lt_sqrt_iff", "exp_pos", "exp_nonneg", "one_lt_exp", "exp_ge_one_add",
        "log_nonneg", "log_pos", "log_neg", "log_le_sub_one",
        "sq_nonneg.int", "sq_nonneg.rat", "sq_nonneg.real", "two_mul_le_add_sq.nat",
        "square_gap.le_abs.int", "square_gap.le_abs.rat", "square_gap.le_abs.real",
        "one_add_lt_exp", "exp_tangent_le", "exp_tangent_lt", "exp_midpoint_le", "exp_midpoint_lt",
        "exp_weighted_jensen", "exp_weighted_jensen_lt", "sqrt_le_iff", "le_sqrt_iff",
        "one_div_sqrt_le_div_iff", "one_div_sqrt_lt_div_iff", "div_le_one_div_sqrt_iff", "div_lt_one_div_sqrt_iff",
        "sqrt_sub_sq_le_abs", "sqrt_sub_abs_le", "log_midpoint_le", "log_midpoint_lt",
        "log_weighted_jensen", "log_weighted_jensen_lt", "sub_one_le_mul_log", "neg_mul_log_le_scale",
        "sum_below.entropy_le_log.real",
        "list_sum.weighted_sqrt_mul_le.real", "list_sum.sqrt_mul_le.real",
        "sum_below.weighted_sqrt_mul_le.real", "sum_below.sqrt_mul_le.real",
        "sqrt_mul.weighted_add_le", "sqrt_mul.add_le", "abs_le_sqrt_mul", "norm2.add_le", "norm2.sub_le"] + analytic_order
      ["nat", "int", "rat", "real"].each -> (suffix)
        ["sequence.monotone_on", "sequence.antitone_on",
          "sum_nonneg", "sum_le", "sum_add", "sum_sub", "sum_const_mul", "sum_mul_const",
          "sum_below.split", "sum_below.const_le", "sum_below.le_const", "sum_below.mono",
          "sum_below.zero", "sum_below.eq_zero", "sum_below.swap", "sum_below.exchange",
          "sum_below.scale", "sum_below.add", "sum_below.sub", "sum_below.succ_front",
          "sum_below.single", "sum_below.single_out", "sum_below.single_eq",
          "sum_const", "sum_below.eq_const", "sum_below.eq_one", "sum_telescope"].each -> (prefix)
          names.push(prefix + "." + suffix)
      ["list_sum", "sum_below"].each -> (prefix)
        ["int", "rat", "real"].each -> (suffix)
          ["weighted_cauchy", "cauchy"].each -> (rule)
            names.push(prefix + "." + rule + "." + suffix)
        ["weighted_cauchy_sqrt", "cauchy_sqrt", "weighted_minkowski", "minkowski"].each -> (rule)
          names.push(prefix + "." + rule + ".real")
      ["int", "rat", "real"].each -> (suffix)
        ["recurrence.geometric_sum", "recurrence.geometric_forcing",
          "abs_nonneg", "abs_pos", "abs_of_nonneg", "abs_of_nonpos", "le_abs_self",
          "neg_le_abs", "neg_abs_le", "abs_le_of", "abs_lt_of", "abs_add", "abs_sub",
          "abs_sub_le", "abs_sub_abs_le_abs_sub", "abs_abs_sub_abs_le", "abs_mul",
          "abs_neg", "abs_sub_comm", "abs_abs", "abs_sq", "sq_abs", "sq_le_sq",
          "sq_lt_sq", "abs_le_of_sq_le_sq"].each -> (prefix)
          names.push(prefix + "." + suffix)
      ["nat", "int", "rat", "real"].each -> (suffix)
        ["div_eq_zero_of_den_eq_zero", "min_le_left", "min_le_right", "le_min", "lt_min", "min_eq_left",
          "min_eq_right", "min_comm", "min_self", "le_max_left", "le_max_right",
          "max_le", "max_lt", "max_eq_left", "max_eq_right", "max_comm", "max_self",
          "min_le_max", "min_add_max", "min_le_min", "max_le_max",
          "max_le_mul_max", "mul_min_le_min"].each -> (prefix)
          names.push(prefix + "." + suffix)
      power_identities = []
      ["nat", "int", "rat", "real"].each -> (suffix)
        ["pow_add", "pow_mul", "mul_pow"].each -> (prefix)
          name = prefix + "." + suffix
          power_identities.push(name)
          names.push(name)
        ["pow_nonneg", "pow_pos", "one_le_pow", "pow_le_one", "pow_le_pow_left",
          "pow_le_pow_right", "pow_le_pow_of_le_one", "pow_lt_pow_left",
          "pow_lt_pow_right"].each -> (prefix)
          names.push(prefix + "." + suffix)
      division_order = []
      ["rat", "real"].each -> (suffix)
        ["one_div_pos", "one_div_nonneg", "one_div_neg", "div_pos", "div_nonneg",
          "div_le_div_of_nonneg_right", "div_lt_div_of_pos_right",
          "div_le_div_of_nonneg_left", "one_div_le_one_div_of_le",
          "one_div_lt_one_div_of_lt", "div_self", "mul_div_cancel",
          "mul_div_cancel_right", "mul_div_cancel_left", "one_div_one_div"].each -> (prefix)
          names.push(prefix + "." + suffix)
        ["div_le_iff", "le_div_iff", "div_lt_iff", "lt_div_iff", "div_le_one",
          "div_le_div_iff", "div_lt_div_iff", "eq_div_iff", "div_eq_iff"].each -> (prefix)
          name = prefix + "." + suffix
          division_order.push(name)
          names.push(name)
      names.each -> (name)
        # Also watch absent names, so a later import can add a default.
        @session.auto_default_names[name] = true
        th = auto_loaded_rule(name)
        if th != nil
          rules = auto_hint_rules(context, th)
          # These unconditional identities are equally useful in either
          # direction. Kernel symmetry avoids an arithmetic detour.
          if power_identities.include?(name)
            rules.push(sym_rule(th))
          rules.each -> (rule)
            pattern = auto_rule_shape(rule.concl)
            # Order equivalences reduce an exp/log comparison to its inputs.
            # Their reverse directions would introduce exp/log into arbitrary
            # arithmetic goals; those remain available as explicit hints.
            oriented = !analytic_order.include?(name) || (pattern != nil && (["c:exp", "c:log"].include?(pattern[1]) || ["c:exp", "c:log"].include?(pattern[2])))
            # Clear a quotient goal only after proving its denominator guard.
            # Reverse directions remain explicit, avoiding division in ordinary
            # product comparisons and unconstrained denominator searches.
            if division_order.include?(name)
              oriented = pattern != nil && (pattern[1] == "c:/" || pattern[2] == "c:/")
            if pattern != nil && oriented
              # Generic defaults share a lookup bucket, but instantiate_to
              # still checks the full types and every premise before use.
              operand = auto_rule_spine(rule.concl)[1][0]
              if ty_vars(type_of(operand)).size > 0
                pattern[3] = "*"
              key = pattern.join("|")
              bucket = index[key]
              if bucket == nil
                bucket = []
                index[key] = bucket
              bucket.push(rule)
              if pattern[0] == "="
                key = ["=", pattern[1], "?rhs", pattern[3]].join("|")
                bucket = index[key]
                if bucket == nil
                  bucket = []
                  index[key] = bucket
                bucket.push(rule)
      @session.auto_default_index = index
    out = []
    keys = []
    spine = auto_rule_spine(goal.concl)
    lefts = auto_operand_heads(spine[1][0]) + ["*"]
    rights = left_only ? ["?rhs"] : auto_operand_heads(spine[1][1]) + ["*"]
    [shape[3], "*"].each -> (ty)
      lefts.each -> (left)
        rights.each -> (right)
          key = [shape[0], left, right, ty].join("|")
          if !keys.include?(key)
            keys.push(key)
            bucket = index[key]
            if bucket != nil
              out = out + bucket
    out

  # Instantiate equalities at existing numeric subexpressions, then let the
  # arithmetic search discharge their guards and combine their conclusions.
  # This final root fallback neither invents endpoints nor recursively expands
  # newly derived terms: at most64 terms,32 rules/matches and8 instances.
  -> auto_subterm_arithmetic(goal, hints)
    if !comparison?(goal.concl)
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    goal.hyps.each -> (h) auto_collect_terms(h[1], terms)
    candidates = []
    hints.each -> (hint)
      if candidates.size < 32
        auto_add_fact(candidates, hint)
    terms.each -> (term)
      if term.tag == :app && numeric_type?(type_of(term)) && candidates.size < 32
        probe = goal.with_concl(@k.eq_tm(term, term))
        auto_default_hints(probe, true).each -> (rule)
          if candidates.size < 32
            auto_add_fact(candidates, rule)
    instances = auto_hint_instances(goal, candidates, terms, true)
    if instances.size > 0
      proof = auto_arithmetic_forward(goal, hints + instances)
      if proof != nil
        return proof
    # A default bound can also contribute to arithmetic without matching the
    # whole goal, e.g. a square bound followed by an added positive margin.
    # Instantiate only at existing terms; the ordinary checker proves the
    # final comparison, including strictness and every rule premise.
    cmp = dest_cmp_rel(goal.concl)
    if !["≤", "<"].include?(cmp[0]) || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256])
      return nil
    probe = goal
    if cmp[0] == "<"
      rel = @k.mk_const("≤", ty_funs([type_of(cmp[1]), type_of(cmp[1])], ty_bool))
      probe = goal.with_concl(mk_apps(rel, [cmp[1], cmp[2]]))
    rules = auto_default_hints(probe)
    instances = auto_hint_instances(goal, rules, terms)
    if instances.size == 0
      return nil
    auto_arithmetic_forward(goal, hints + instances)

  -> auto_arithmetic_shape?(term, leaves)
    conjunction = dest_binop(term, "∧")
    if conjunction != nil
      return auto_arithmetic_shape?(conjunction[0], leaves) && auto_arithmetic_shape?(conjunction[1], leaves)
    leaves[0] -= 1
    comparison = dest_cmp_rel(term)
    leaves[0] >= 0 && comparison != nil && numeric_type?(type_of(comparison[1]))

  # Expose small defined arithmetic expressions once, keeping recursive tails
  # folded. Every new hypothesis is derived from its original checked equation.
  -> auto_defined_arithmetic(goal, hints, budget, rewrite_hints = false)
    comparison = dest_cmp_rel(goal.concl)
    shape = rewrite_hints ? auto_arithmetic_shape?(goal.concl, [4]) : (comparison != nil && numeric_type?(type_of(comparison[1])))
    if budget[0] <= 0 || !shape || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256])
      return nil
    begin
      definitions = auto_relation_definitions(goal.all_terms + (hints.map -> (hint) hint.concl))
      facts = []
      if rewrite_hints
        rules = []
        protected = []
        nodes = [4096]
        hints.each -> (hint)
          if auto_small_term?(hint.concl, [512])
            auto_relation_parts(hint, [8]).each -> (part)
              if rules.size >= 32
                fail("arithmetic rewrites: rule limit")
              rule = make_rule(@d, part, "arithmetic hint")
              rules.push(rule)
              auto_relation_heads(rule.lhs, protected, nodes)
        if rules.size == 0
          return nil
        # Keep the supplied formula's head intact until its rewrite can apply.
        definitions = rules + (definitions.select -> (rule) !protected.include?(rule.head_name))
        facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
      if definitions.size == 0
        return nil
      conversion = auto_relation_normalize(goal.concl, definitions, facts)
      conclusion = dest_binop(conversion.concl, "=")[1]
      if !auto_small_term?(conclusion, [1024])
        return nil
      changed = !tm_eq(conclusion, goal.concl)
      nodes = [4096]
      hyps = goal.hyps + []
      converted = []
      goal.hyps.each -> (h)
        step = auto_relation_normalize(h[1], definitions, facts)
        term = dest_binop(step.concl, "=")[1]
        if !auto_small_term?(term, nodes)
          fail("defined arithmetic: hypothesis limit")
        if !tm_eq(term, h[1])
          name = "defined_fact" + converted.size.to_s
          while hyps.any?(-> (old) old[0] == name)
            name += "_"
          hyps.push([name, term])
          converted.push(@k.eq_mp(step, @k.assume(h[1])))
          changed = true
      normalized_hints = hints.map -> (hint)
        step = auto_relation_normalize(hint.concl, definitions, facts)
        proof = @k.eq_mp(step, hint)
        if !auto_small_term?(proof.concl, nodes)
          fail("defined arithmetic: hint limit")
        if !tm_eq(proof.concl, hint.concl)
          changed = true
        proof
      if !changed
        return nil
      # A formula may simplify its own statement to True. Retain the supplied
      # facts as well: another arithmetic step can still need that statement.
      if rewrite_hints
        normalized_hints = hints + normalized_hints
      budget[0] -= 1
      worker = Prover.new(@session)
      worker.registered_search = @registered_search
      ref = GoalRef.new(Goal.new(goal.fixes, hyps, conclusion), nil, 0)
      worker.goals = [ref]
      worker.tac_auto(ref, 3, normalized_hints, budget, [goal.concl])
      if ref.thm == nil || worker.goals.size != 0
        return nil
      proof = @k.eq_mp(@k.sym(conversion), worker.fit(ref, ref.thm))
      converted.each -> (fact) proof = @d.prove_hyp(fact, proof)
      proof
    rescue e
      nil

  # Fold exactly the loaded definition of sum_below, using a checked equation.
  # Matching the complete recursion body distinguishes sums from other recursors.
  -> auto_sum_fold_rule(ty)
    key = ty_show(ty)
    cached = @sum_alias_rules[key]
    if cached != nil
      return cached
    definition = @k.defs["sum_below"]
    if definition == nil
      return nil
    n = mk_var("sum_index", ty_nat)
    f = mk_var("sum_function", ty_fun(ty_nat, ty))
    head = @k.mk_const("sum_below", ty_funs([ty_nat, type_of(f)], ty))
    unfolded = Simp.new(@d, [make_rule(@d, definition, "sum_below")]).rewrite_top(head, 0)
    if unfolded == nil
      return nil
    unfolded = @d.beta_norm_thm(@d.ap_thm(@d.ap_thm(unfolded, n), f))
    equation = @k.gen(n, @k.gen(f, @k.sym(unfolded)))
    rule = make_rule(@d, equation, "sum_below.fold")
    @sum_alias_rules[key] = rule
    rule

  -> auto_sum_alias_top(t, limits)
    spine = strip_app(t)
    head = spine[0]
    if limits[1] <= 0 || limits[2] <= 0 || t.tag != :app || type_of(t).fun? || head.tag != :const || head.name == "sum_below" || @k.defs[head.name] == nil || !auto_small_term?(t, [128])
      return nil
    limits[1] -= 1
    th = nil
    cur = t
    steps = 0
    while steps < 8
      spine = strip_app(cur)
      head = spine[0]
      if head.tag != :const || @k.defs[head.name] == nil
        break
      step = Simp.new(@d, [make_rule(@d, @k.defs[head.name], head.name)]).rewrite_top(head, 0)
      if step == nil
        break
      spine[1].each -> (arg) step = @d.ap_thm(step, arg)
      step = @d.beta_norm_thm(step)
      th = th == nil ? step : @k.trans(th, step)
      cur = dest_binop(th.concl, "=")[1]
      if !auto_small_term?(cur, [128])
        return nil
      if is_const?(strip_app(cur)[0], "sum_below")
        limits[2] -= 1
        return th
      steps += 1
    if th == nil
      return nil
    rule = auto_sum_fold_rule(type_of(t))
    if rule == nil
      return nil
    folded = Simp.new(@d, [rule]).apply_rule(rule, cur, 0)
    if folded == nil
      return nil
    limits[2] -= 1
    @k.trans(th, folded)

  -> auto_sum_alias_conv(t, limits)
    if limits[0] <= 0 || limits[2] <= 0
      return nil
    limits[0] -= 1
    th = nil
    if t.tag == :app
      a = auto_sum_alias_conv(t.a, limits)
      b = auto_sum_alias_conv(t.b, limits)
      if a != nil || b != nil
        th = @k.mk_comb(a == nil ? @k.refl(t.a) : a, b == nil ? @k.refl(t.b) : b)
    elsif t.tag == :lam
      opened = dest_lam_fresh(t, [t])
      body = auto_sum_alias_conv(opened[1], limits)
      if body != nil
        th = @k.abs_rule(opened[0], body)
    cur = th == nil ? t : dest_binop(th.concl, "=")[1]
    step = auto_sum_alias_top(cur, limits)
    if step != nil
      th = th == nil ? step : @k.trans(th, step)
    th

  # One final retry on checked sum notation. Scan at most512 nodes, try16
  # defined heads and convert four sums, unfolding at most eight heads each.
  -> auto_sum_alias_proof(goal, hints, budget)
    if !@sum_aliases_allowed || budget[0] <= 0 || (!comparison?(goal.concl) && @k.dest_eq(goal.concl) == nil)
      return nil
    begin
      limits = [512, 16, 4]
      conversion = auto_sum_alias_conv(goal.concl, limits)
      conclusion = conversion == nil ? goal.concl : dest_binop(conversion.concl, "=")[1]
      # Supplied proofs may still depend on the original hypotheses.
      hyps = goal.hyps + []
      converted = []
      goal.hyps.each -> (h)
        step = auto_sum_alias_conv(h[1], limits)
        if step != nil
          name = "sum_alias" + converted.size.to_s
          while hyps.any?(-> (old) old[0] == name)
            name += "_"
          hyps.push([name, dest_binop(step.concl, "=")[1]])
          converted.push(@k.eq_mp(step, @k.assume(h[1])))
      normalized_hints = hints.map -> (hint)
        step = auto_sum_alias_conv(hint.concl, limits)
        step == nil ? hint : @k.eq_mp(step, hint)
      if conversion == nil && converted.size == 0 && limits[2] == 4
        return nil
      worker = Prover.new(@session)
      worker.registered_search = @registered_search
      worker.sum_aliases_allowed = false
      ref = GoalRef.new(Goal.new(goal.fixes, hyps, conclusion), nil, 0)
      worker.goals = [ref]
      worker.tac_auto(ref, 3, normalized_hints, budget, [])
      if ref.thm == nil || worker.goals.size != 0
        return nil
      result = worker.fit(ref, ref.thm)
      if conversion != nil
        result = @k.eq_mp(@k.sym(conversion), result)
      converted.each -> (proof) result = @d.prove_hyp(proof, result)
      result
    rescue e
      nil

  # One checked bottom-up pass, without repeatedly simplifying a successor
  # chain's expanded children. The same node budget covers premises and facts.
  -> auto_recurrence_successors(t, rule, nodes)
    nodes[0] -= 1
    if nodes[0] < 0
      fail("recurrence: successor conversion limit")
    if t.tag == :lam
      opened = dest_lam_fresh(t, [t])
      return @k.abs_rule(opened[0], auto_recurrence_successors(opened[1], rule, nodes))
    if t.tag != :app
      return @k.refl(t)
    result = @k.mk_comb(auto_recurrence_successors(t.a, rule, nodes), auto_recurrence_successors(t.b, rule, nodes))
    value = dest_binop(result.concl, "=")[1]
    if value.a.tag == :const && value.a.op == OP_SUCC
      result = @k.trans(result, @k.spec(value.b, rule))
    result

  # Check a recurrence premise after opening its binders. Definitions and
  # supplied equalities may expose a ring identity; every conversion is checked.
  -> auto_recurrence_premise(goal, hints, induction = false, paired = false)
    worker = Prover.new(@session)
    root = GoalRef.new(goal, nil, 0)
    worker.goals = [root]
    ref = worker.tac_intro(root, [], true)
    definitions = paired ? auto_relation_definitions(ref.goal.all_terms + (hints.map -> (hint) hint.concl)) : nil
    conversion = paired ? auto_relation_normalize(ref.goal.concl, definitions) : @d.compute_conv(ref.goal.concl)
    conclusion = dest_binop(conversion.concl, "=")[1]
    if !auto_small_term?(conclusion, [paired ? 2048 : 512])
      fail("recurrence: expanded premise limit")
    successor = auto_loaded_rule("succ_eq_add_one.nat")
    successor_nodes = [paired ? 8192 : 1024]
    if successor != nil
      normalized = auto_recurrence_successors(conclusion, successor, successor_nodes)
      conversion = @k.trans(conversion, normalized)
      conclusion = dest_binop(conversion.concl, "=")[1]
    expansion = nil
    if induction
      names = ["nat", "int", "rat", "real"].map -> (suffix) "pow_succ." + suffix
      equation = @k.dest_eq(ref.goal.concl)
      if equation != nil
        names.push("cast_succ." + type_of(equation[0]).name)
      expansions = []
      names.each -> (name)
        rule = auto_loaded_rule(name)
        if rule != nil
          expansions.push(make_rule(@d, rule, name))
      if expansions.size > 0
        expansion = Simp.new(@d, expansions)
        expansion.step_limit = 512
        normalized = expansion.simp_conv_opt(conclusion, 0)
        if normalized != nil
          conversion = @k.trans(conversion, normalized)
          conclusion = dest_binop(conversion.concl, "=")[1]
    facts = (ref.goal.hyps.map -> (h) @k.assume(h[1])) + hints
    rules = []
    converted_facts = []
    induction_rules = []
    facts.each_with_index -> (fact, i)
      if rules.size < 32 && auto_small_term?(fact.concl, [paired ? 512 : 128])
        begin
          converted = @k.eq_mp(paired ? auto_relation_normalize(fact.concl, definitions) : @d.compute_conv(fact.concl), fact)
          if auto_small_term?(converted.concl, [paired ? 2048 : 512])
            if successor != nil
              converted = @k.eq_mp(auto_recurrence_successors(converted.concl, successor, successor_nodes), converted)
            if expansion != nil
              # Each already size-bounded fact gets its own normalization fuel.
              fact_expansion = Simp.new(@d, expansions)
              fact_expansion.step_limit = 512
              normalized = fact_expansion.simp_conv_opt(converted.concl, 0)
              if normalized != nil
                converted = @k.eq_mp(normalized, converted)
            parts = paired ? auto_relation_parts(converted, [8]) : [converted]
            parts.each -> (part)
              if rules.size < 32
                rule = make_rule(@d, part, "recurrence premise")
                rules.push(rule)
                if i >= goal.hyps.size && i < ref.goal.hyps.size
                  induction_rules.push(rule)
            converted_facts.push(converted)
        rescue e
          0
    # Use the newly introduced induction hypothesis before supplied rules can
    # rewrite inside an unfolded recursive body and change its matching shape.
    if induction_rules.size > 0
      induction_simp = Simp.new(@d, induction_rules)
      induction_simp.step_limit = 512
      simplified = induction_simp.simp_conv_opt(conclusion, 0)
      if simplified != nil
        conversion = @k.trans(conversion, simplified)
        conclusion = dest_binop(conversion.concl, "=")[1]
    simplifier = Simp.new(@d, paired ? rules + definitions : rules)
    simplifier.step_limit = 512
    simplified = simplifier.simp_conv_opt(conclusion, 0)
    if simplified != nil
      conversion = @k.trans(conversion, simplified)
      conclusion = dest_binop(conversion.concl, "=")[1]
    # Checked rewrites may duplicate a bounded input; ring expansion stays capped.
    equality = @k.dest_eq(conclusion)
    proof = is_const?(conclusion, "⊤") ? @k.truth : nil
    if paired
      proof = auto_relation_result(conclusion, [4])
    if equality != nil && auto_small_term?(conclusion, [1024])
      begin
        equality.each -> (side) recurrence_ring_cost(side, type_of(side).name, [128])
        proof = tm_eq(equality[0], equality[1]) ? @k.refl(equality[0]) : @k.ring_eq(equality[0], equality[1])
      rescue e
        0
    if proof == nil && induction && equality != nil && auto_small_term?(conclusion, [1024])
      proof = auto_arithmetic_proof(ref.goal.with_concl(conclusion), converted_facts, [1])
    if proof == nil
      fail("recurrence: initial value or step is not established")
    worker.goals = [ref]
    worker.close(ref, worker.fit(ref, @k.eq_mp(@k.sym(conversion), proof)))
    worker.fit(root, root.thm)

  -> auto_recurrence_indices(term, kind = "nat")
    terms = []
    auto_collect_terms(term, terms)
    indices = []
    # Preserve numeric sequence candidates first. A list may also feed a
    # structured result whose numeric observation appears in the outer formula.
    passes = kind == "list" ? [true, false] : [true]
    passes.each -> (numeric)
      terms.each -> (term)
        spine = strip_app(term)
        head = spine[0]
        args = spine[1]
        if indices.size < 2 && args.size > 0 && numeric_type?(type_of(term)) == numeric && (head.tag == :var || (head.tag == :const && head.op == OP_NONE))
          args.reverse.each -> (index)
            if indices.size < 2 && index.tag == :var && type_of(index).tag == :c && type_of(index).name == kind && !indices.any?(-> (old) tm_eq(old, index))
              indices.push(index)
    indices

  # Infer degree <=3 coefficients from the requested answer, then replay an
  # existing induction lemma. At most two sequence indices per orientation;
  # never recursively guess another polynomial while checking its premises.
  -> auto_polynomial_recurrence(goal, hints, budget)
    equality = @k.dest_eq(goal.concl)
    if equality == nil || !numeric_type?(type_of(equality[0])) || !auto_small_term?(goal.concl, [256])
      return nil
    [false, true].each -> (reverse)
      left = equality[reverse ? 1 : 0]
      right = equality[reverse ? 0 : 1]
      indices = auto_recurrence_indices(left)
      indices.each -> (index)
        if budget[0] > 0
          begin
            recognized = recurrence_coefficients(@k, right, index)
            degree = recognized[0]
            cs = recognized[1]
            name = degree <= 1 ? "linear_eq" : (degree == 2 ? "quadratic" : "cubic")
            counter = ty_eq(type_of(left), ty_nat) && tm_eq(right, index)
            rule = auto_loaded_rule(counter ? "recurrence.count" : "recurrence." + name + "." + type_of(left).name)
            if rule != nil
              budget[0] -= 1
              values = degree <= 1 ? [cs[0], cs[1]] : (degree == 2 ? [cs[2], cs[1], cs[0]] : [cs[3], cs[2], cs[1], cs[0]])
              if counter
                values = []
              result = rule
              ([mk_lam(index, left)] + values + [index]).each -> (value) result = @k.spec(value, result)
              result = @d.beta_norm_thm(result)
              while dest_binop(result.concl, "⇒") != nil
                premise = dest_binop(result.concl, "⇒")[0]
                result = @k.mp(result, auto_recurrence_premise(goal.with_concl(premise), hints))
              sides = @k.dest_eq(result.concl)
              sides.each -> (side) recurrence_ring_cost(side, type_of(side).name, [128])
              if !tm_eq(sides[1], right)
                result = @k.trans(result, @k.ring_eq(sides[1], right))
              return reverse ? @k.sym(result) : result
          rescue e
            0
    nil

  # Recognize A*r^n+B from the requested answer. The shifted sequence must
  # satisfy the loaded geometric rule; no rate, base or step is assumed.
  # Natural goals require B=0, since subtraction there is truncated.
  -> auto_geometric_equality(goal, hints, budget)
    equality = @k.dest_eq(goal.concl)
    if equality == nil || !numeric_type?(type_of(equality[0])) || !auto_small_term?(goal.concl, [256])
      return nil
    ty = type_of(equality[0])
    rule = auto_loaded_rule("recurrence.geometric_eq." + ty.name)
    if rule == nil
      return nil
    zero = mk_lit(ty.name == "nat" || ty.name == "int" ? 0 : Q_ZERO, ty)
    [false, true].each -> (reverse)
      left = equality[reverse ? 1 : 0]
      right = equality[reverse ? 0 : 1]
      indices = auto_recurrence_indices(left)
      terms = []
      auto_collect_terms(right, terms)
      attempts = 0
      terms.each -> (power)
        parts = dest_binop(power, "^")
        if parts != nil && parts[1].tag == :var && indices.any?(-> (index) tm_eq(index, parts[1])) && !tm_free_in?(parts[1], parts[0]) && attempts < 2 && budget[0] > 0
          attempts += 1
          budget[0] -= 1
          begin
            index = parts[1]
            recognized = recurrence_atom_coefficients(@k, right, index, power)
            if recognized[0] > 1
              fail("recurrence: not affine in a single power")
            constant = recognized[1][0]
            coefficient = recognized[1][1]
            shifted = !tm_eq(constant, zero)
            if shifted && ty.name == "nat"
              fail("recurrence: natural offset must be on the sequence side")
            value = left
            if shifted
              value = mk_apps(@k.mk_const("-", ty_funs([ty, ty], ty)), [left, constant])
            sequence = mk_lam(index, value)
            result = @d.beta_norm_thm(@k.spec(index, @k.spec(parts[0], @k.spec(sequence, rule))))
            premise = dest_binop(result.concl, "⇒")[0]
            result = @k.mp(result, auto_recurrence_premise(goal.with_concl(premise), hints))
            initial = @d.beta_norm_term(mk_app(sequence, mk_lit(0, ty_nat)))
            base = auto_recurrence_premise(goal.with_concl(@k.eq_tm(initial, coefficient)), hints)
            times = @k.mk_const("*", ty_funs([ty, ty], ty))
            result = @k.trans(result, @k.mk_comb(@k.mk_comb(@k.refl(times), base), @k.refl(power)))
            if shifted
              plus = @k.mk_const("+", ty_funs([ty, ty], ty))
              result = @k.mk_comb(@k.mk_comb(@k.refl(plus), result), @k.refl(constant))
            sides = @k.dest_eq(result.concl)
            sides.each -> (side) recurrence_ring_cost(side, ty.name, [128])
            result = @k.trans(@k.ring_eq(left, sides[0]), @k.trans(result, @k.ring_eq(sides[1], right)))
            return reverse ? @k.sym(result) : result
          rescue e
            0
    nil

  # One library induction for a small numeric closed form. Its step receives
  # exactly the current-index equality, never the goal at the next index.
  # The premise checker performs bounded algebra, with no recursive auto.
  -> auto_recurrence_identity(goal, hints, budget, kind = "nat")
    equality = @k.dest_eq(goal.concl)
    if equality == nil || !numeric_type?(type_of(equality[0])) || !auto_small_term?(goal.concl, [256]) || budget[0] <= 0
      return nil
    rule = auto_loaded_rule(kind == "list" ? "list.recursive_identity" : "recurrence.identity")
    if rule == nil
      return nil
    [false, true].each -> (reverse)
      left = equality[reverse ? 1 : 0]
      right = equality[reverse ? 0 : 1]
      auto_recurrence_indices(left, kind).each -> (index)
        if budget[0] > 0
          begin
            if !recurrence_formula?(@k, right, index, [64], [4, []])
              fail("recurrence: unsupported closed form")
            recurrence_ring_cost(right, type_of(right).name, [128])
            budget[0] -= 1
            sequence = mk_lam(index, left)
            formula = mk_lam(index, right)
            types = {}
            ty_match(dest_unop(rule.concl, "∀").ty, type_of(sequence), types)
            result = @k.inst_type(rule, types)
            [sequence, formula, index].each -> (value) result = @k.spec(value, result)
            result = @d.beta_norm_thm(result)
            while dest_binop(result.concl, "⇒") != nil
              premise = dest_binop(result.concl, "⇒")[0]
              proof = nil
              begin
                proof = auto_recurrence_premise(goal.with_concl(premise), hints, true)
              rescue e
                if kind == "list"
                  proof = auto_list_identity_premise(goal.with_concl(premise), hints, budget)
                else
                  fail("recurrence: unproved premise")
              result = @k.mp(result, proof)
            return reverse ? @k.sym(result) : result
          rescue e
            0
    nil

  # Try one universally quantified parameter, retaining it in the induction
  # hypothesis so a recursive call may pass a different value. At most two
  # argument variables per index; every generalized base and step is checked.
  -> auto_recurrence_family(goal, hints, budget)
    equality = @k.dest_eq(goal.concl)
    if equality == nil || !numeric_type?(type_of(equality[0])) || !auto_small_term?(goal.concl, [256]) || budget[0] <= 0
      return nil
    rule = auto_loaded_rule("recurrence.family")
    if rule == nil
      return nil
    [false, true].each -> (reverse)
      left = equality[reverse ? 1 : 0]
      right = equality[reverse ? 0 : 1]
      auto_recurrence_indices(left).each -> (index)
        terms = []
        auto_collect_terms(left, terms)
        parameters = []
        terms.each -> (term)
          spine = strip_app(term)
          if numeric_type?(type_of(term)) && spine[1].any?(-> (arg) tm_eq(arg, index)) && (spine[0].tag == :var || (spine[0].tag == :const && spine[0].op == OP_NONE))
            spine[1].reverse.each -> (arg)
              if parameters.size < 2 && arg.tag == :var && !tm_eq(arg, index) && !parameters.any?(-> (old) tm_eq(old, arg))
                parameters.push(arg)
        parameters.each -> (parameter)
          if budget[0] > 0
            begin
              if !recurrence_formula?(@k, right, index, [64], [4, []])
                fail("recurrence: unsupported family formula")
              recurrence_ring_cost(right, type_of(right).name, [128])
              budget[0] -= 1
              sequence = mk_lam(index, mk_lam(parameter, left))
              formula = mk_lam(index, mk_lam(parameter, right))
              types = {}
              ty_match(dest_unop(rule.concl, "∀").ty, type_of(sequence), types)
              result = @k.inst_type(rule, types)
              [sequence, formula, index].each -> (value) result = @k.spec(value, result)
              result = @d.beta_norm_thm(result)
              while dest_binop(result.concl, "⇒") != nil
                premise = dest_binop(result.concl, "⇒")[0]
                result = @k.mp(result, auto_recurrence_premise(goal.with_concl(premise), hints, true))
              result = @k.spec(parameter, result)
              return reverse ? @k.sym(result) : result
            rescue e
              0
    nil

  -> auto_relation_heads(t, names, nodes)
    nodes[0] -= 1
    if nodes[0] < 0
      fail("list relation: definition scan limit")
    if t.tag == :const && @k.defs[t.name] != nil && !names.include?(t.name)
      if names.size >= 32
        fail("list relation: definition limit")
      names.push(t.name)
    if t.tag == :app
      auto_relation_heads(t.a, names, nodes)
      auto_relation_heads(t.b, names, nodes)
    elsif t.tag == :lam
      auto_relation_heads(t.b, names, nodes)
    0

  # Use checked constructor equations instead of expanding opaque recursive
  # tails into recursors. Include only definitions reached from this premise.
  -> auto_relation_definitions(terms)
    names = []
    nodes = [8192]
    terms.each -> (term) auto_relation_heads(term, names, nodes)
    rules = []
    i = 0
    while i < names.size
      name = names[i]
      equations = @session.eqns_of(name)
      if equations.size == 0
        projection = auto_loaded_rule(name + ".mk")
        if projection != nil && projection.tags.size == 0
          equations = [projection]
      equations.each -> (equation)
        if equation.hyps.size == 0 && equation.tags.size == 0
          if rules.size >= 64
            fail("list relation: defining equation limit")
          rules.push(make_rule(@d, equation, name))
          auto_relation_heads(equation.concl, names, nodes)
      i += 1
    rules

  -> auto_relation_normalize(t, rules, facts = [])
    simplifier = Simp.new(@d, rules)
    simplifier.hyp_rules = facts
    simplifier.step_limit = 1024
    simplifier.simp_conv(t, 0)

  # Project conjunctions through binders and guards without dropping either.
  # Every resulting rewrite theorem retains the original hypotheses and tags.
  -> auto_relation_parts(th, leaves, variables = [], guards = [])
    quant = dest_unop(th.concl, "∀")
    if quant != nil
      opened = dest_lam_fresh(quant, [th.concl] + th.hyps)
      return auto_relation_parts(@k.spec(opened[0], th), leaves, variables + [opened[0]], guards)
    implication = dest_binop(th.concl, "⇒")
    if implication != nil
      return auto_relation_parts(@k.mp(th, @k.assume(implication[0])), leaves, variables, guards + [implication[0]])
    conjunction = dest_binop(th.concl, "∧")
    if conjunction != nil
      return auto_relation_parts(@k.conj1(th), leaves, variables, guards) + auto_relation_parts(@k.conj2(th), leaves, variables, guards)
    leaves[0] -= 1
    if leaves[0] < 0
      fail("list relation: fact projection limit")
    result = th
    guards.reverse.each -> (guard) result = @k.disch(guard, result)
    variables.reverse.each -> (variable) result = @k.gen(variable, result)
    [result]

  -> auto_relation_result(t, leaves)
    if is_const?(t, "⊤")
      return @k.truth
    conjunction = dest_binop(t, "∧")
    if conjunction != nil
      return @k.conj(auto_relation_result(conjunction[0], leaves), auto_relation_result(conjunction[1], leaves))
    leaves[0] -= 1
    equation = @k.dest_eq(t)
    if leaves[0] < 0 || equation == nil || !auto_small_term?(t, [1024])
      fail("list relation: equation limit")
    if tm_eq(equation[0], equation[1])
      return @k.refl(equation[0])
    equation.each -> (side) recurrence_ring_cost(side, type_of(side).name, [128])
    @k.ring_eq(equation[0], equation[1])

  -> auto_relation_shape?(t, leaves)
    conjunction = dest_binop(t, "∧")
    if conjunction != nil
      return auto_relation_shape?(conjunction[0], leaves) && auto_relation_shape?(conjunction[1], leaves)
    leaves[0] -= 1
    equation = @k.dest_eq(t)
    leaves[0] >= 0 && equation != nil && type_of(equation[0]).name != "bool"

  -> auto_relation_state_call?(t, index, state)
    terms = []
    auto_collect_terms(t, terms)
    terms.any? -> (term)
      args = strip_app(term)[1]
      args.any?(-> (arg) tm_eq(arg, index)) && args.any?(-> (arg) tm_eq(arg, state))

  # Prefer rewriting the stateful call to its formula, independently in each
  # coordinate. The checked symmetry is reversed when rebuilding the result.
  -> auto_relation_orient(th, index, state)
    conjunction = dest_binop(th.concl, "∧")
    if conjunction != nil
      return @k.conj(auto_relation_orient(@k.conj1(th), index, state), auto_relation_orient(@k.conj2(th), index, state))
    equation = @k.dest_eq(th.concl)
    if !auto_relation_state_call?(equation[0], index, state) && auto_relation_state_call?(equation[1], index, state)
      return @k.sym(th)
    th

  -> auto_relation_restore(th, target)
    conjunction = dest_binop(target, "∧")
    if conjunction != nil
      return @k.conj(auto_relation_restore(@k.conj1(th), conjunction[0]), auto_relation_restore(@k.conj2(th), conjunction[1]))
    tm_eq(th.concl, target) ? th : @k.sym(th)

  # Assemble a list certificate from proofs of individual propositions. Only
  # beta-reduce the predicate application; the item itself may be expensive.
  -> auto_list_evidence(goal, hints, report = false)
    predicate = goal.concl.a.b
    xs = goal.concl.b
    step = auto_loaded_rule("list.all_cons")
    base = auto_loaded_rule("list.all_nil")
    if step == nil || base == nil
      return nil
    begin
      types = {}
      ty_match(dest_unop(step.concl, "∀").ty, type_of(predicate), types)
      step = @k.spec(predicate, @k.inst_type(step, types))
      facts = hints + (goal.hyps.map -> (h) @k.assume(h[1]))
      cells = []
      gap = report ? [nil, nil] : nil
      while true
        rest = mk_app(goal.concl.a, xs)
        tail = list_item_evidence(rest, facts, nil)
        if tail != nil
          if report && gap[0] == nil
            gap[0] = tail
          break
        if is_const?(xs, "nil")
          tail = @k.spec(predicate, @k.inst_type(base, types))
          break
        if dest_binop(xs, "cons") == nil
          if !report || gap[1] != nil
            return nil
          gap[1] = rest
          tail = @k.assume(rest)
          break
        term = mk_app(predicate, xs.a.b)
        beta = predicate.tag == :lam ? @k.beta(term) : nil
        head = list_item_evidence(beta == nil ? term : beta.concl.b, facts, gap)
        if head == nil
          return nil
        cells.push([xs, beta == nil ? head : @k.eq_mp(@k.sym(beta), head)])
        xs = xs.b
      if report && (gap[0] == nil || gap[1] == nil)
        return nil
      cells.reverse.each -> (cell)
        values = cell[0]
        instance = @k.spec(values.b, @k.spec(values.a.b, step))
        tail = @k.mp(@k.mp(instance, cell[1]), tail)
      if report
        return checked_progress_note(gap[0], gap[1], nil, [@k.disch(gap[1], tail)])
      return tail
    rescue unsupported_rule
      return nil

  -> list_item_evidence(term, facts, gap)
    proof = facts.find(-> (fact) tm_eq(fact.concl, term))
    if proof == nil
      proof = @session.exact_premise(term)
    if gap != nil
      if proof == nil && (gap[1] == nil || tm_eq(gap[1], term))
        gap[1] = term
        return @k.assume(term)
      if proof != nil && gap[0] == nil
        gap[0] = proof
    proof

  # One list induction with one generalized state, keeping up to four
  # coordinate equations together. At most two existing argument pairs are
  # tried; the premise checker performs bounded rewriting and ring arithmetic.
  -> auto_list_relation(goal, hints, budget)
    if budget[0] <= 0 || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256]) || !auto_relation_shape?(goal.concl, [4])
      return nil
    rule = auto_loaded_rule("list.recursive_relation")
    if rule == nil
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    pairs = []
    terms.each -> (term)
      spine = strip_app(term)
      if spine[0].tag == :var || (spine[0].tag == :const && spine[0].op == OP_NONE)
        spine[1].each -> (index)
          if index.tag == :var && index.ty.tag == :c && index.ty.name == "list"
            spine[1].reverse.each -> (state)
              if pairs.size < 2 && state.tag == :var && !state.ty.fun? && !tm_eq(state, index) && !pairs.any?(-> (pair) tm_eq(pair[0], index) && tm_eq(pair[1], state))
                pairs.push([index, state])
    pairs.each -> (pair)
      if budget[0] > 0
        budget[0] -= 1
        begin
          conclusion = auto_relation_orient(@k.assume(goal.concl), pair[0], pair[1]).concl
          predicate = mk_lam(pair[0], mk_lam(pair[1], conclusion))
          types = {}
          ty_match(dest_unop(rule.concl, "∀").ty, type_of(predicate), types)
          result = @k.inst_type(rule, types)
          [predicate, pair[0]].each -> (value) result = @k.spec(value, result)
          result = @d.beta_norm_thm(result)
          while dest_binop(result.concl, "⇒") != nil
            premise = dest_binop(result.concl, "⇒")[0]
            result = @k.mp(result, auto_recurrence_premise(goal.with_concl(premise), hints, true, true))
          return fit_concl(auto_relation_restore(@k.spec(pair[1], result), goal.concl), goal.concl)
        rescue e
          0
    nil

  # Reverse the complete loaded fold definition. Matching its entire recursion
  # body checks the direction, initial state and step, not just the head name.
  -> auto_fold_rule(name, list_ty, state_ty)
    key = name + ":" + ty_show(list_ty) + ":" + ty_show(state_ty)
    if @fold_alias_rules[key] != nil
      return @fold_alias_rules[key]
    definition = @k.defs[name]
    if definition == nil
      return nil
    step = mk_var("fold_step", ty_funs([list_ty.args[0], state_ty], state_ty))
    xs = mk_var("fold_list", list_ty)
    state = mk_var("fold_state", state_ty)
    head = @k.mk_const(name, ty_funs([type_of(step), list_ty, state_ty], state_ty))
    unfolded = Simp.new(@d, [make_rule(@d, definition, name)]).rewrite_top(head, 0)
    if unfolded == nil
      return nil
    [step, xs, state].each -> (value) unfolded = @d.ap_thm(unfolded, value)
    equation = @k.sym(@d.beta_norm_thm(unfolded))
    [state, xs, step].each -> (value) equation = @k.gen(value, equation)
    rule = make_rule(@d, equation, name + ".fold")
    @fold_alias_rules[key] = rule
    rule

  -> auto_fold_call(t, list_ty)
    names = ["list.foldl", "list.foldr"]
    if names.include?(strip_app(t)[0].name)
      return @k.refl(t)
    cur = t
    result = nil
    steps = 0
    while steps < 8
      spine = strip_app(cur)
      head = spine[0]
      if head.tag != :const || @k.defs[head.name] == nil
        break
      conv = Simp.new(@d, [make_rule(@d, @k.defs[head.name], head.name)]).rewrite_top(head, 0)
      if conv == nil
        break
      spine[1].each -> (arg) conv = @d.ap_thm(conv, arg)
      conv = @d.beta_norm_thm(conv)
      result = result == nil ? conv : @k.trans(result, conv)
      cur = dest_binop(result.concl, "=")[1]
      if !auto_small_term?(cur, [256])
        return nil
      if names.include?(strip_app(cur)[0].name)
        return result
      steps += 1
    if result == nil
      return nil
    names.each -> (name)
      rule = auto_fold_rule(name, list_ty, type_of(t))
      if rule != nil
        folded = Simp.new(@d, [rule]).apply_rule(rule, cur, 0)
        if folded != nil
          return @k.trans(result, folded)
    nil

  # Abstract only the selected, locally closed traversal call. Keeping the
  # whole conclusion preserves mutually dependent components of an invariant.
  -> auto_fold_body(t, call, state)
    if tm_eq(t, call)
      return state
    if t.tag == :app
      return mk_app(auto_fold_body(t.a, call, state), auto_fold_body(t.b, call, state))
    if t.tag == :lam
      return mk_lam_raw(t.name, t.ty, auto_fold_body(t.b, call, state))
    t

  # One loaded invariant theorem, with its base and preservation premises
  # proved independently. At most two calls from a 256-node conclusion, eight
  # alias unfoldings each, sharing auto's fuel. Premises cannot start induction.
  -> auto_fold_invariant(goal, hints, budget)
    if budget[0] <= 0 || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256])
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    attempts = 0
    terms.each -> (call)
      spine = strip_app(call)
      if attempts < 2 && budget[0] > 0 && call.tag == :app && !type_of(call).fun? && spine[0].tag == :const && @k.defs[spine[0].name] != nil && spine[1].size >= 2
        args = spine[1]
        initial = args[args.size - 1]
        index = -1
        args.each_with_index -> (arg, i)
          if i < args.size - 1 && type_of(arg).tag == :c && type_of(arg).name == "list"
            index = i
        if index >= 0 && ty_eq(type_of(initial), type_of(call))
          attempts += 1
          budget[0] -= 1
          begin
            state = mk_var(fresh_name("fold_state", goal.all_terms), type_of(call))
            xs = mk_var(fresh_name("fold_list", goal.all_terms + [state]), type_of(args[index]))
            predicate = mk_lam(state, auto_fold_body(goal.concl, call, state))
            conversion = auto_fold_call(call, type_of(args[index]))
            if conversion != nil
              folded = strip_app(dest_binop(conversion.concl, "=")[1])
              rule = auto_loaded_rule(folded[0].name + "_invariant_on")
              if rule == nil || folded[1].size != 3
                fail("fold: invariant rule not loaded")
              types = {}
              ty_match(dest_unop(rule.concl, "∀").ty, type_of(folded[1][0]), types)
              result = @k.inst_type(rule, types)
              [folded[1][0], predicate, folded[1][1]].each -> (value) result = @k.spec(value, result)
              initial = folded[1][2]
            else
              rule = auto_loaded_rule("list.recursive_invariant")
              if rule == nil
                fail("fold: recursive invariant rule not loaded")
              generalized = args + []
              generalized[index] = xs
              generalized[args.size - 1] = state
              sequence = mk_lam(xs, mk_lam(state, mk_apps(spine[0], generalized)))
              types = {}
              ty_match(dest_unop(rule.concl, "∀").ty, type_of(sequence), types)
              result = @k.inst_type(rule, types)
              [sequence, predicate, args[index]].each -> (value) result = @k.spec(value, result)
            result = @d.beta_norm_thm(result)
            while dest_binop(result.concl, "⇒") != nil || dest_unop(result.concl, "∀") != nil
              if dest_unop(result.concl, "∀") != nil
                result = @d.beta_norm_thm(@k.spec(initial, result))
              else
                premise = dest_binop(result.concl, "⇒")[0]
                worker = Prover.new(@session)
                ref = GoalRef.new(goal.with_concl(premise), nil, 0)
                worker.goals = [ref]
                opened = worker.tac_intro(ref, [], true)
                proof = worker.auto_list_bound_premise(opened.goal, hints, budget)
                worker.close(opened, proof)
                result = @k.mp(result, worker.fit(ref, ref.thm))
            if conversion != nil
              conversion = replace_conv(goal.concl, call, conversion)
              result = fit_concl(result, dest_binop(conversion.concl, "=")[1])
              result = @k.eq_mp(@k.sym(conversion), result)
            return fit_concl(result, goal.concl)
          rescue e
            0
    nil

  # Normalize one list-induction branch, then use bounded non-inductive auto.
  # Conversion proofs retain the original hypotheses; nested induction is disabled.
  -> auto_list_bound_premise(goal, hints, budget)
    conversion = @d.compute_conv(goal.concl)
    conclusion = dest_binop(conversion.concl, "=")[1]
    successor = auto_loaded_rule("succ_eq_add_one.nat")
    successor_nodes = [8192]
    if successor != nil
      conversion = @k.trans(conversion, auto_recurrence_successors(conclusion, successor, successor_nodes))
      conclusion = dest_binop(conversion.concl, "=")[1]
    nodes = [4096]
    if !auto_small_term?(conclusion, [1024])
      fail("list bound: expanded conclusion limit")
    hyps = []
    conversions = []
    member_rule = auto_loaded_rule("list.forall_cons")
    goal.hyps.each -> (h)
      proof = @k.assume(h[1])
      if member_rule != nil
        simplifier = Simp.new(@d, [make_rule(@d, member_rule, "list.forall_cons")])
        simplifier.step_limit = 512
        step = simplifier.simp_conv_opt(proof.concl, 0)
        if step != nil
          proof = @k.eq_mp(step, proof)
      proof = @k.eq_mp(@d.compute_conv(proof.concl), proof)
      if successor != nil
        proof = @k.eq_mp(auto_recurrence_successors(proof.concl, successor, successor_nodes), proof)
      if !auto_small_term?(proof.concl, nodes)
        fail("list bound: hypothesis limit")
      hyps.push([h[0], proof.concl])
      conversions.push(proof)
    normalized_hints = hints.map -> (hint)
      proof = @k.eq_mp(@d.compute_conv(hint.concl), hint)
      if successor != nil
        proof = @k.eq_mp(auto_recurrence_successors(proof.concl, successor, successor_nodes), proof)
      if !auto_small_term?(proof.concl, nodes)
        fail("list bound: hint limit")
      proof
    result = auto_list_bound_branch(Goal.new(goal.fixes, hyps, conclusion), normalized_hints, budget, [2])
    conversions.each -> (proof) result = @d.prove_hyp(proof, result)
    @k.eq_mp(@k.sym(conversion), result)

  # Split at most two exposed conditional summands, never inside a binder.
  -> auto_list_bound_branch(goal, hints, budget, splits)
    terms = []
    auto_collect_terms(goal.concl, terms)
    if splits[0] > 0 && budget[0] > 0
      terms.each -> (term)
        spine = strip_app(term)
        if spine[0].op == OP_ITE && spine[1].size == 3 && numeric_type?(type_of(term))
          condition = spine[1][0]
          known = goal.hyps.any? -> (h) tm_eq(h[1], condition) || tm_eq(h[1], @k.neg_tm(condition))
          if !known
            splits[0] -= 1
            budget[0] -= 1
            name = "list_condition"
            while goal.hyps.any?(-> (h) h[0] == name)
              name += "_"
            yes = auto_list_bound_branch(goal.add_hyp(name, condition), hints, budget, splits)
            no = auto_list_bound_branch(goal.add_hyp(name, @k.neg_tm(condition)), hints, budget, splits)
            return @k.disj_cases(@k.excluded_middle(condition), yes, no)
    worker = Prover.new(@session)
    worker.registered_search = @registered_search
    ref = GoalRef.new(goal, nil, 0)
    worker.goals = [ref]
    simplified = [ref]
    begin
      simplified = worker.tac_simp(ref, [], true)
    rescue e
      0
    if ref.thm == nil && simplified.size > 0
      worker.tac_auto(simplified[0], 3, hints, budget, [goal.concl])
    if ref.thm == nil || worker.goals.size != 0
      fail("list bound: open branch")
    worker.fit(ref, ref.thm)

  # One list induction for a small numeric bound. Hypotheses mentioning the
  # list are reverted by the existing induction tactic and checked in each case.
  -> auto_list_bound(goal, hints, budget)
    comparison = dest_cmp_rel(goal.concl)
    if comparison == nil || !["≤", "<"].include?(comparison[0]) || !numeric_type?(type_of(comparison[1])) || !auto_small_term?(goal.concl, [256]) || goal.hyps.size > 12 || hints.size > 8 || budget[0] <= 0
      return nil
    indices = auto_recurrence_indices(comparison[1], "list")
    auto_recurrence_indices(comparison[2], "list").each -> (index)
      if indices.size < 2 && !indices.any?(-> (old) tm_eq(old, index))
        indices.push(index)
    indices.each -> (index)
      if budget[0] > 0
        begin
          if !recurrence_formula?(@k, comparison[1], index, [64], [4, []]) || !recurrence_formula?(@k, comparison[2], index, [64], [4, []])
            fail("list bound: unsupported formula")
          name = nil
          goal.fixes.each -> (fix)
            if tm_eq(fix[1], index)
              name = fix[0]
          if name == nil
            fail("list bound: missing binder")
          budget[0] -= 1
          worker = Prover.new(@session)
          root = GoalRef.new(goal, nil, 0)
          worker.goals = [root]
          worker.tac_induction_impl(root, [Tok.new(:id, name, 0, 0)], [], true)
          branches = worker.goals + []
          if branches.size != 2
            fail("list bound: unexpected constructors")
          branches.each -> (branch)
            proof = auto_list_bound_premise(branch.goal, hints, budget)
            worker.close(branch, worker.fit(branch, proof))
          return worker.fit(root, root.thm)
        rescue e
          0
    nil

  -> auto_small_term?(term, nodes)
    nodes[0] -= 1
    if nodes[0] < 0
      return false
    if term.tag == :app
      return auto_small_term?(term.a, nodes) && auto_small_term?(term.b, nodes)
    if term.tag == :lam
      return auto_small_term?(term.b, nodes)
    true

  # Collect linear combinations over a common range or list into one sum.
  # Stop at each sum: its body is checked at a fresh index, never enumerated.
  -> collect_sum_conv(t, fuel, count = nil)
    if count != nil && tm_eq(t, count.concl.a.b)
      return count
    if ((t.search_ops & TERM_FINITE_SUM) == 0 && count == nil) || t.tag != :app || t.a.tag != :app
      return nil
    head = t.a.a
    if is_const?(head, "sum_below") || is_const?(head, "sum_list")
      return @k.refl(t)
    if ![OP_ADD, OP_SUB, OP_MUL].include?(head.op)
      return nil
    fuel[0] -= 1
    if fuel[0] < 0
      fail("sum linearity: term limit")
    # A range length can itself be a scalar multiplying an explicit sum.
    left_count = head.op == OP_MUL && (t.b.search_ops & TERM_FINITE_SUM) != 0 ? nil : count
    right_count = head.op == OP_MUL && (t.a.b.search_ops & TERM_FINITE_SUM) != 0 ? nil : count
    left = collect_sum_conv(t.a.b, fuel, left_count)
    right = collect_sum_conv(t.b, fuel, right_count)
    if head.op == OP_MUL
      if (left == nil) == (right == nil)
        return nil
    elsif left == nil || right == nil
      return nil
    sum = left == nil ? right.concl.b : left.concl.b
    list = is_const?(sum.a.a, "sum_list")
    domain = sum.a.b
    ty = type_of(t)
    if head.op == OP_MUL
      coefficient = left == nil ? t.a.b : t.b
      rule = "const_mul"
      args = list ? [domain, sum.b, coefficient] : [coefficient, sum.b, domain]
    else
      if !tm_eq(sum.a, right.concl.b.a)
        return nil
      rule = head.op == OP_ADD ? "add" : "sub"
      args = list ? [domain, sum.b, right.concl.b.b] : [sum.b, right.concl.b.b, domain]
    law = auto_loaded_rule((list ? "sum_list_" : "sum_") + rule + "." + ty.name)
    if law == nil
      return nil
    if list
      types = {}
      if !ty_match(dest_unop(law.concl, "∀").ty, type_of(domain), types)
        return nil
      law = @k.inst_type(law, types)
    args.each -> (arg) law = @k.spec(arg, law)
    lifted = combination_binop(head.name, ty, left == nil ? @k.refl(t.a.b) : left, right == nil ? @k.refl(t.b) : right)
    if head.op == OP_MUL && left != nil
      commute = auto_loaded_rule("mul_comm." + ty.name)
      if commute == nil
        return nil
      lifted = @k.trans(lifted, @k.spec(coefficient, @k.spec(sum, commute)))
    compressed = @k.eq_mp(@d.beta_eta_conv(law.concl), law)
    @k.trans(lifted, @k.trans(@d.beta_eta_conv(lifted.concl.b), @k.sym(compressed)))

  # The opposite sum fixes the range. Its length is the sum of ones.
  -> collect_counted_sum(term, sum, fuel)
    if !is_const?(sum.a.a, "sum_below") || !tm_contains?(term, sum.a.b)
      return nil
    ty = type_of(sum)
    constant = auto_loaded_rule("sum_const." + ty.name)
    identity = auto_loaded_rule("mul_one." + ty.name)
    if constant == nil || identity == nil
      return nil
    one = mk_lit((ty.name == "rat" || ty.name == "real") ? Q_ONE : 1, ty)
    law = @k.spec(sum.a.b, @k.spec(one, constant))
    length = law.concl.b.a.b
    count = @k.sym(@k.trans(law, @k.spec(length, identity)))
    collect_sum_conv(term, fuel, count)

  -> auto_sum_ring(left, right)
    if !numeric_type?(type_of(left)) || !auto_small_term?(left, [256]) || !auto_small_term?(right, [256])
      return nil
    begin
      fuel = [20]
      a = collect_sum_conv(left, fuel)
      b = collect_sum_conv(right, fuel)
      if a == nil && b != nil
        a = collect_counted_sum(left, b.concl.b, fuel)
      elsif b == nil && a != nil
        b = collect_counted_sum(right, a.concl.b, fuel)
      if a == nil || b == nil || !tm_eq(a.concl.b.a, b.concl.b.a)
        return nil
      if tm_eq(left, a.concl.b) && tm_eq(right, b.concl.b)
        return nil
      f = a.concl.b.b
      g = b.concl.b.b
      index = mk_var(fresh_name("i", [f,g]), type_of(f).dom)
      equation = @k.eq_tm(mk_app(f, index), mk_app(g, index))
      normalized = @d.beta_eta_conv(equation)
      body = normalized.concl.b
      begin
        pointwise = sum_ring_identity(body)
      rescue unexpanded
        rules = auto_relation_definitions([body])
        if rules.empty?()
          return nil
        simp = Simp.new(@d, rules)
        simp.step_limit = 128
        step = simp.simp_definition_conv(body)
        if tm_eq(body, step.concl.b) || !auto_small_term?(step.concl.b, [384])
          return nil
        pointwise = @k.eq_mp(@k.sym(step), sum_ring_identity(step.concl.b))
      functions = funext_proof(f, g, index, @k.eq_mp(@k.sym(normalized), pointwise))
      middle = @d.ap_term(a.concl.b.a, functions)
      @k.trans(a, @k.trans(middle, @k.sym(b)))
    rescue unsupported
      nil

  -> sum_ring_identity(equation)
    left = equation.a.b
    right = equation.b
    nodes = [192]
    recurrence_ring_cost(left, type_of(left).name, nodes, 6)
    recurrence_ring_cost(right, type_of(right).name, nodes, 6)
    @k.ring_eq(left, right)

  # Distribute small summands using proved algebra and sum rules. This final
  # fallback is confined to existing finite sums: four conversions, 128 input
  # nodes each, quadratic summands, 512 simp steps and eight guard checks.
  -> auto_sum_arithmetic(goal, hints)
    if !comparison?(goal.concl)
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    goal.hyps.each -> (h) auto_collect_terms(h[1], terms)
    facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
    comparisons = []
    facts.each -> (th) normalize_comparisons(th, comparisons)
    inferred = []
    attempts = 4
    guards = [8]
    rules_by_type = {}
    terms.each -> (term)
      spine = strip_app(term)
      if attempts > 0 && is_const?(spine[0], "sum_below") && spine[1].size == 2 && numeric_type?(type_of(term)) && spine[1][1].tag == :lam && auto_small_term?(term, [128])
        nodes = [64]
        degree = auto_quadratic_degree(spine[1][1].b, nodes)
        if degree >= 0 && degree <= 2 && nodes[0] >= 0
          attempts -= 1
          suffix = type_of(term).name
          rules = rules_by_type[suffix]
          if rules == nil
            rules = []
            ["left_distrib", "right_distrib", "mul_sub", "sum_add", "sum_sub", "sum_const_mul", "sum_mul_const", "sum_below.single", "sum_below.single_out", "sum_below.zero"].each -> (prefix)
              name = prefix + "." + suffix
              th = auto_loaded_rule(name)
              if th != nil
                rules.push(make_rule(@d, th, name))
            rules_by_type[suffix] = rules
          simplifier = Simp.new(@d, rules)
          simplifier.step_limit = 512
          simplifier.hyp_rules = facts
          prover = self
          simplifier.discharger = -> (condition)
            if guards[0] > 0
              guards[0] -= 1
              begin
                worker = Prover.new(prover.session)
                worker.linarith_proof(Goal.new(goal.fixes, [], condition), comparisons)
              rescue e
                nil
            else
              nil
          begin
            th = simplifier.simp_conv_opt(term, 0)
            if th != nil
              auto_add_fact(inferred, th)
          rescue e
            0
    if inferred.size == 0
      return nil
    auto_arithmetic_proof(goal, facts + inferred, [1])

  # Local quantified bounds may need arithmetic to discharge their guards.
  # Match them backwards, using the same checked, bounded rule search.
  -> auto_local_hints(goal)
    shape = auto_rule_shape(goal.concl)
    if shape == nil
      return []
    out = []
    spine = auto_rule_spine(goal.concl)
    lefts = auto_operand_heads(spine[1][0])
    rights = auto_operand_heads(spine[1][1])
    goal.hyps.each -> (h)
      if dest_unop(h[1], "∀") != nil || dest_binop(h[1], "⇒") != nil
        pattern = auto_rule_shape(h[1])
        if pattern != nil && pattern[0] == shape[0] && (pattern[1] == "*" || lefts.include?(pattern[1])) && (pattern[2] == "*" || rights.include?(pattern[2]))
          out.push(@k.assume(h[1]))
    out

  # Open just a predicate whose defining body is a universal statement.
  # The term and its arguments keep their spelling inside the guards.
  -> quantified_predicate_conv(term)
    head = strip_app(term)[0]
    if head.tag != :const || head.op != OP_NONE
      return nil
    definition = @k.defs[head.name]
    if definition == nil || !auto_small_term?(definition.concl.b, [128]) || !auto_small_term?(term, [128])
      return nil
    body = definition.concl.b
    while body.tag == :lam
      body = body.b
    if dest_unop(body, "∀") == nil
      return nil
    conv = proof_head_conv(term, ["∀"])
    conv != nil && auto_small_term?(conv.concl.b, [256]) ? conv : nil

  # From P(s) = ∀ x, H(s,x) → Q(x), derive Q(x) or restrict P to another
  # parameter. Local facts supply the rule, registered lemmas prove its guards.
  -> auto_predicate_transfer(goal, hints)
    head = strip_app(goal.concl)[0]
    if goal.concl.tag != :app || head.op != OP_NONE || (head.tag != :const && head.tag != :var) || goal.hyps.size + hints.size > 16
      return nil
    direct = []
    wrapped = []
    facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
    facts.each -> (fact)
      rule = fact
      if dest_unop(rule.concl, "∀") == nil
        step = quantified_predicate_conv(rule.concl)
        if step == nil
          next
        rule = @k.eq_mp(step, fact)
        if tm_eq(strip_app(fact.concl)[0], head)
          wrapped.push(rule)
      if tm_eq(strip_app(auto_rule_conclusion(rule.concl))[0], head)
        direct.push(rule)
    if direct.empty?() && wrapped.empty?()
      return nil
    worker = Prover.new(@session, application_conversions)
    worker.registered_search = true
    budget = [24, 4]
    proof = worker.auto_hint_proof(goal, direct, hints, budget, [])
    if proof != nil || wrapped.empty?()
      return proof
    conv = quantified_predicate_conv(goal.concl)
    if conv == nil
      return nil
    ref = GoalRef.new(goal.with_concl(conv.concl.b), nil, 0)
    worker.goals = [ref]
    leaf = worker.tac_intro(ref, [], true)
    proof = worker.auto_hint_proof(leaf.goal, wrapped, hints, budget, [])
    if proof == nil
      return nil
    worker.close(leaf, worker.fit(leaf, proof))
    @k.eq_mp(@k.sym(conv), ref.thm)

  # Small quadratic side conditions may need products of signs or squares.
  # Opaque applications remain atoms; large powers never reach normalization.
  -> auto_quadratic_degree(t, budget, atoms = nil)
    budget[0] -= 1
    if budget[0] < 0
      return -1
    if t.tag == :lit
      return 0
    if t.tag == :app && t.a.tag == :const && t.a.op == OP_NEG
      return auto_quadratic_degree(t.b, budget, atoms)
    spine = strip_app(t)
    if spine[0].tag != :const || spine[1].size != 2
      if atoms != nil && !atoms.any?(-> (old) tm_eq(old, t))
        atoms.push(t)
      return 1
    name = spine[0].name
    args = spine[1]
    if name == "^"
      # The arithmetic checker treats a variable exponent as one atom too.
      # Constant high powers stay excluded: their expansion can be enormous.
      if args[1].tag != :lit
        if atoms != nil && !atoms.any?(-> (old) tm_eq(old, t))
          atoms.push(t)
        return 1
      if args[1].val < 0 || args[1].val > 2
        return -1
      degree = auto_quadratic_degree(args[0], budget, atoms)
      return degree < 0 ? -1 : degree * args[1].val
    if name == "/" && args[1].tag == :lit
      return auto_quadratic_degree(args[0], budget, atoms)
    if !["+", "-", "*"].include?(name)
      if atoms != nil && !atoms.any?(-> (old) tm_eq(old, t))
        atoms.push(t)
      return 1
    left = auto_quadratic_degree(args[0], budget, atoms)
    right = auto_quadratic_degree(args[1], budget, atoms)
    if left < 0 || right < 0
      return -1
    name == "*" ? left + right : (left > right ? left : right)

  # Keep the connected arithmetic component of the goal. Quantified hints
  # may also specialize at incidental terms such as partially applied powers.
  # Conjunctive facts can repeat a comparison; count each conclusion once.
  -> auto_relevant_comparisons(goal, comparisons, additional = [])
    atoms = []
    scan = [64]
    ([goal.concl] + additional).each -> (term)
      cmp = dest_cmp_rel(term)
      auto_quadratic_degree(cmp[1], scan, atoms)
      auto_quadratic_degree(cmp[2], scan, atoms)
    candidates = []
    comparisons.each -> (th)
      sides = dest_cmp_rel(th.concl)
      found = []
      scan = [64]
      left = auto_quadratic_degree(sides[1], scan, found)
      right = auto_quadratic_degree(sides[2], scan, found)
      if scan[0] >= 0 && left >= 0 && left <= 2 && right >= 0 && right <= 2 && !candidates.any?(-> (entry) tm_eq(entry[0].concl, th.concl))
        candidates.push([th, found])
    out = []
    changed = true
    while changed && out.size <= 8
      changed = false
      candidates.each -> (entry)
        if !out.include?(entry[0]) && entry[1].any?(-> (atom) atoms.any?(-> (old) tm_eq(old, atom)))
          out.push(entry[0])
          entry[1].each -> (atom)
            if !atoms.any?(-> (old) tm_eq(old, atom))
              atoms.push(atom)
          changed = true
    out

  # Repeated compound values can form a quadratic problem even when their
  # expanded expressions have higher degree. Prove the stronger statement for
  # fresh variables, then instantiate them and restore the original premises.
  -> auto_compound_occurrences(t, candidate, nodes)
    nodes[0] -= 1
    if nodes[0] < 0
      fail("compound arithmetic: scan limit")
    if tm_eq(t, candidate)
      return 1
    square = dest_binop(t, "^")
    if square != nil && square[1].tag == :lit && square[1].val == 2
      return 2 * auto_compound_occurrences(square[0], candidate, nodes)
    if t.tag == :app
      return auto_compound_occurrences(t.a, candidate, nodes) + auto_compound_occurrences(t.b, candidate, nodes)
    if t.tag == :lam
      return auto_compound_occurrences(t.b, candidate, nodes)
    0

  -> auto_compound_arithmetic(goal, budget, facts)
    if budget.size < 2 || budget[1] <= 0 || !comparison?(goal.concl)
      return nil
    begin
      raw = []
      supplied = facts == nil ? (goal.hyps.map -> (h) @k.assume(h[1])) : facts
      supplied.each -> (th) normalize_comparisons(th, raw)
      ty = type_of(dest_cmp_rel(goal.concl)[1])
      raw = raw.select -> (th) ty_eq(type_of(dest_cmp_rel(th.concl)[1]), ty)
      if raw.size > 16
        return nil
      expressions = [goal.concl] + (raw.map -> (th) th.concl)
      nodes = [512]
      if !expressions.all?(-> (t) auto_small_term?(t, nodes))
        return nil
      terms = []
      expressions.each -> (t) auto_collect_terms(t, terms)
      candidates = []
      scans = [4096]
      terms.each -> (term)
        if candidates.size < 4 && term.tag == :app && ty_eq(type_of(term), ty)
          degree = auto_quadratic_degree(term, [32])
          if degree >= 2 && degree <= 4
            count = 0
            expressions.each -> (t)
              if count < 2
                count += auto_compound_occurrences(t, term, scans)
            if count >= 2
              candidates.push(term)
      if candidates.size == 0
        return nil
      names = {}
      (goal.all_terms + expressions).each -> (t) tm_free_names_into(t, names)
      raw.each -> (th) th.hyps.each -> (h) tm_free_names_into(h, names)
      replacements = []
      abstracted = expressions
      candidates.each -> (term)
        variable = mk_var(fresh_name_from_set("compound", names), ty)
        replacements.push([variable, term])
        abstracted = abstracted.map -> (t) auto_fold_body(t, term, variable)
      assumptions = []
      i = 1
      while i < abstracted.size
        assumptions.push(@k.assume(abstracted[i]))
        i += 1
      probe = goal.with_concl(abstracted[0])
      selected = auto_relevant_comparisons(probe, assumptions)
      if selected.size > 8
        return nil
      nodes = [64]
      ([probe.concl] + (selected.map -> (th) th.concl)).each -> (t)
        cmp = dest_cmp_rel(t)
        [cmp[1], cmp[2]].each -> (side)
          degree = auto_quadratic_degree(side, nodes)
          if degree < 0 || degree > 2
            fail("compound arithmetic: not quadratic")
      if nodes[0] < 0
        return nil
      budget[1] -= 1
      worker = Prover.new(@session)
      proof = @k.inst(worker.quadratic_premise_proof(probe, selected), replacements)
      raw.each -> (th) proof = @d.prove_hyp(th, proof)
      proof
    rescue e
      nil

  -> auto_nonlinear_premise(goal, budget, facts = nil)
    proof = auto_nonlinear_direct(goal, budget, facts)
    if proof == nil
      proof = auto_compound_arithmetic(goal, budget, facts)
    # Keep existing attempts first; use nonzero premises only if they fail.
    proof == nil ? auto_nonlinear_direct(goal, budget, facts, true) : proof

  # Higher-degree terms can cancel against supplied bounds, leaving a sum of
  # squares. Suggest only small square instances, then check a linear
  # certificate; never multiply the higher-degree comparisons together.
  -> auto_square_arithmetic(goal, budget, facts = nil)
    if budget[0] <= 0 || !comparison?(goal.concl)
      return nil
    ty = type_of(dest_cmp_rel(goal.concl)[1])
    if !["int", "rat", "real"].include?(ty.name)
      return nil
    rule = auto_loaded_rule("sq_nonneg." + ty.name)
    if rule == nil
      return nil
    begin
      comparisons = []
      raw = facts == nil ? (goal.hyps.map -> (h) @k.assume(h[1])) : facts
      raw.each -> (th)
        parts = []
        normalize_comparisons(th, parts)
        parts.each -> (part)
          if ty_eq(type_of(dest_cmp_rel(part.concl)[1]), ty)
            auto_add_fact(comparisons, part)
      if comparisons.size > 8
        return nil
      nodes = [256]
      cost = 0
      expressions = [goal.concl] + (comparisons.map -> (th) th.concl)
      if !expressions.all?(-> (term) auto_small_term?(term, nodes))
        return nil
      nodes = [128]
      expressions.each -> (term)
        cmp = dest_cmp_rel(term)
        cost += recurrence_ring_cost(cmp[1], ty.name, nodes) + recurrence_ring_cost(cmp[2], ty.name, nodes)
      if cost > 64
        return nil
      bases = []
      # The goal is inspected only to suggest bases; this assumed theorem is
      # never passed to the arithmetic proof. Each square comes from the lemma.
      nl_cross_square_bases(comparisons + [@k.assume(goal.concl)], ty, bases, {})
      if bases.size == 0
        return nil
      squares = bases.map -> (base) @k.spec(base, rule)
      budget[0] -= 1
      worker = Prover.new(@session)
      worker.linarith_proof(Goal.new(goal.fixes, [], goal.concl), comparisons + squares)
    rescue e
      nil

  # Coefficients only propose the integrand. Rebuild its certificate from
  # monomial integrals, then check both the function and the requested value.
  -> polynomial_integral_certificate(f, a, b, ordered)
    seed = auto_loaded_rule("darboux.const")
    step = auto_loaded_rule("darboux.add_monomial")
    if seed == nil || step == nil
      fail("integral: missing monomial rules")
    x = mk_var(fresh_name("x", [f]), ty_real)
    body = @d.beta_norm_term(mk_app(f, x))
    if !auto_small_term?(body, [512])
      fail("integral: integrand limit")
    begin
      terms = recurrence_atom_coefficients(@k, body, x, x, 16, 256)
    rescue e
      rules = auto_relation_definitions([body])
      if rules.empty?()
        raise e
      body = auto_relation_normalize(body, rules).concl.b
      if !auto_small_term?(body, [512])
        fail("integral: integrand limit")
      terms = recurrence_atom_coefficients(@k, body, x, x, 16, 256)
    cs = terms[1]
    [a, b, cs[0]].each -> (arg) seed = @k.spec(arg, seed)
    cert = @k.mp(seed, ordered)
    zero = mk_lit(Q_ZERO, ty_real)
    i = 1
    while i <= terms[0]
      if !tm_eq(cs[i], zero)
        args = strip_app(cert.concl)[1]
        rule = step
        [a, b, args[0], args[3], cs[i], mk_lit(i, ty_nat)].each -> (arg) rule = @k.spec(arg, rule)
        cert = @d.beta_norm_thm(@k.mp(rule, cert))
      i += 1
    spine = strip_app(cert.concl)
    equal = ring_equality_proof(@k.eq_tm(spine[1][0], f))
    change = @d.ap_term(spine[0], equal)
    [a, b, spine[1][3]].each -> (arg) change = @d.ap_thm(change, arg)
    @k.eq_mp(change, cert)

  -> polynomial_integral_value(left, right)
    recurrence_ring_cost(right, "real", [512], 17)
    folder = Simp.new(@d, [])
    folder.step_limit = 1024
    a = folder.simp_conv(left)
    b = folder.simp_conv(right)
    [a.concl.b, b.concl.b].each -> (t) recurrence_ring_cost(t, "real", [2048], 17)
    begin
      middle = @k.ring_eq(a.concl.b, b.concl.b)
    rescue mismatch
      rules = auto_relation_definitions([b.concl.b])
      if rules.empty?()
        raise mismatch
      b = @k.trans(b, auto_relation_normalize(b.concl.b, rules))
      recurrence_ring_cost(b.concl.b, "real", [512], 17)
      middle = @k.ring_eq(a.concl.b, b.concl.b)
    @k.trans(a, @k.trans(middle, @k.sym(b)))

  -> polynomial_area(f, a, b, value, ordered)
    cert = polynomial_integral_certificate(f, a, b, ordered)
    @k.eq_mp(@d.ap_term(cert.concl.a, polynomial_integral_value(cert.concl.b, value)), cert)

  # Return a checked value for a mean or an oriented integral. Coefficients
  # and endpoints stay symbolic. Only a has_integral goal needs an order fact.
  -> polynomial_integral_call(t)
    if !ty_eq(type_of(t.b), ty_fun(ty_real, ty_real))
      return nil
    alias = proof_head_conv(t, ["quadrature.mean", "darboux.integral"], 4)
    call = alias == nil ? t : alias.concl.b
    f = dest_unop(call, "quadrature.mean")
    if f != nil
      a = mk_lit(Q_NEG_ONE, ty_real)
      b = mk_lit(Q_ONE, ty_real)
      le = @k.mk_const("≤", ty_funs([ty_real, ty_real], ty_bool))
      rule = auto_loaded_rule("quadrature.mean_of_integral")
      if rule == nil
        return nil
      ordered = @d.eqt_elim(@k.compute(mk_apps(le, [a, b])))
      cert = polynomial_integral_certificate(f, a, b, ordered)
      rule = @k.spec(cert.concl.b, @k.spec(f, rule))
      result = @k.mp(rule, fit_concl(cert, rule.concl.a.b))
    elsif head_const?(call, "darboux.integral")
      args = strip_app(call)[1]
      rule = auto_loaded_rule("darboux.integral.orientations")
      if rule == nil
        return nil
      args.each -> (arg) rule = @k.spec(arg, rule)
      a = args[0]
      b = args[1]
      f = args[2]
      le = @k.mk_const("≤", ty_funs([ty_real, ty_real], ty_bool))
      order = mk_apps(le, [a, b])
      forward = polynomial_integral_certificate(f, a, b, @k.assume(order))
      rule = @k.mp(@k.spec(forward.concl.b, rule), @k.disch(order, forward))
      guard = rule.concl.a.b
      reverse_order = guard.a.b
      reverse_value = guard.b.b
      backward = polynomial_area(f, b, a, reverse_value, @k.assume(reverse_order))
      result = @k.mp(rule, @k.disch(reverse_order, backward))
    else
      return nil
    alias == nil ? result : @k.trans(alias, result)

  # Lift evaluated integrals through the surrounding arithmetic by congruence.
  -> polynomial_integral_expr(t, fuel)
    if t.tag != :app || fuel[0] <= 0 || fuel[1] <= 0
      return nil
    fuel[0] -= 1
    if t.a.tag == :app && [OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_POW].include?(t.a.a.op)
      left = polynomial_integral_expr(t.a.b, fuel)
      right = t.a.a.op == OP_POW ? nil : polynomial_integral_expr(t.b, fuel)
      if left == nil
        return right == nil ? nil : @d.ap_term(t.a, right)
      head = @d.ap_term(t.a.a, left)
      return right == nil ? @d.ap_thm(head, t.b) : @k.mk_comb(head, right)
    if t.a.op == OP_NEG
      inner = polynomial_integral_expr(t.b, fuel)
      return inner == nil ? nil : @d.ap_term(t.a, inner)
    result = polynomial_integral_call(t)
    if result != nil
      fuel[1] -= 1
    result

  -> auto_polynomial_integral(goal, hints)
    begin
      if head_const?(goal.concl, "darboux.has_integral")
        args = strip_app(goal.concl)[1]
        le = @k.mk_const("≤", ty_funs([ty_real, ty_real], ty_bool))
        ordered = linarith_proof(goal.with_concl(mk_apps(le, [args[1], args[2]])), hints)
        return polynomial_area(args[0], args[1], args[2], args[3], ordered)
      sides = @k.dest_eq(goal.concl)
      if sides == nil || type_of(sides[0]) != TY_REAL_SINGLETON || tm_eq(sides[0], sides[1])
        return nil
      fuel = [128, 4]
      left = polynomial_integral_expr(sides[0], fuel)
      right = polynomial_integral_expr(sides[1], fuel)
      if left == nil
        return right == nil ? nil : @k.sym(@k.trans(right, polynomial_integral_value(right.concl.b, sides[0])))
      if right == nil
        return @k.trans(left, polynomial_integral_value(left.concl.b, sides[1]))
      value = polynomial_integral_value(left.concl.b, right.concl.b)
      @k.trans(left, @k.trans(value, @k.sym(right)))
    rescue e
      nil

  # Apply the principal-minor criteria to 2Q, so an odd xy coefficient
  # remains integral. The final arithmetic certificate checks the expansion.
  -> auto_binary_form(goal, hints)
    cmp = dest_cmp_rel(goal.concl)
    if cmp == nil || !["<", "≤"].include?(cmp[0]) || goal.hyps.size + hints.size > 12
      return nil
    ty = type_of(cmp[1])
    if ![TY_INT_SINGLETON, TY_RAT_SINGLETON, TY_REAL_SINGLETON].include?(ty)
      return nil
    strict = cmp[0] == "<"
    first = strict ? "quadratic_form.pos." : "quadratic_form.nonneg_of_pos."
    pivot = auto_loaded_rule(first + ty.name)
    if pivot == nil
      return nil
    begin
      nodes = [256]
      raw = hints + (goal.hyps.map -> (h) @k.assume(h[1]))
      if !raw.all?(-> (th) auto_small_term?(th.concl, nodes))
        return nil
      facts = []
      raw.each -> (th) normalize_comparisons(th, facts)
      if !auto_binary_cost_ok?(facts.map -> (th) th.concl)
        return nil
      form = binary_form_coefficients(@k, cmp)
      if form == nil
        return nil
      times = @k.mk_const("*", ty_funs([ty, ty], ty))
      two = mk_lit(ty == TY_INT_SINGLETON ? 2 : [2, 1], ty)
      a = mk_apps(times, [two, form[0]])
      c = mk_apps(times, [two, form[2]])
      forward = [a, form[1], c, form[3], form[4]]
      reverse = [c, form[1], a, form[4], form[3]]
      trials = [[pivot, forward], [pivot, reverse]]
      if !strict
        semidefinite = auto_loaded_rule("quadratic_form.nonneg." + ty.name)
        if semidefinite != nil
          trials.push([semidefinite, forward])
      trials.each -> (trial)
        proof = binary_form_instance(goal, trial[0], trial[1], facts, hints)
        if proof != nil
          return linarith_proof(Goal.new(goal.fixes, [], goal.concl), [proof])
    rescue e
      0
    nil

  -> binary_form_instance(goal, rule, args, facts, hints)
    begin
      args.each -> (arg) rule = @k.spec(arg, rule)
      guard = dest_binop(rule.concl, "⇒")
      while guard != nil
        if dest_binop(guard[0], "∨") != nil
          # Strict positivity also needs a nonzero vector.
          target = goal.with_concl(auto_rule_conclusion(rule.concl))
          return auto_hint_proof(target, [rule], hints, [2, 1], [goal.concl])
        proof = linarith_proof(Goal.new(goal.fixes, [], guard[0]), facts)
        rule = @k.mp(rule, proof)
        guard = dest_binop(rule.concl, "⇒")
      rule
    rescue e
      nil

  # Specialize a loaded field lemma only when its sign or nonzero premise
  # follows from the original facts. Keep the proof of that premise.
  -> auto_guarded_field_rule(name, args, goal, facts)
    rule = auto_loaded_rule(name + "." + type_of(args[0]).name)
    if rule == nil
      return nil
    args.each -> (arg) rule = @k.spec(arg, rule)
    premise = dest_binop(rule.concl, "⇒")
    if premise == nil
      return nil
    guard = facts.find -> (th) tm_eq(th.concl, premise[0])
    if guard == nil
      guard = auto_arithmetic_proof(goal.with_concl(premise[0]), facts, [1])
    guard == nil ? nil : @k.mp(rule, guard)

  # All entries are binary comparisons or quotient applications.
  -> auto_binary_cost_ok?(terms)
    nodes = [160]
    cost = 0
    terms.each -> (term)
      kind = type_of(term.a.b).name
      cost += recurrence_ring_cost(term.a.b, kind, nodes) + recurrence_ring_cost(term.b, kind, nodes)
    cost <= 64

  # A denominator that may vanish has two obligations. Select the matching
  # proved rule only at the root, after the indexed quotient rules.
  -> auto_division_cases(goal, hints)
    sides = dest_cmp_rel(goal.concl)
    if sides == nil || sides[0] == "=" || goal.hyps.size + hints.size > 8
      return nil
    ty = type_of(sides[1])
    if ty != TY_RAT_SINGLETON && ty != TY_REAL_SINGLETON
      return nil
    if dest_binop(sides[1], "/") == nil && dest_binop(sides[2], "/") == nil
      return nil
    facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
    nodes = [256]
    if !auto_small_term?(goal.concl, nodes) || !facts.all?(-> (th) auto_small_term?(th.concl, nodes))
      return nil
    comparisons = []
    facts.each -> (th) normalize_comparisons(th, comparisons)
    op = sides[0] == "<" ? "lt" : "le"
    [1, 2].each -> (i)
      q = dest_binop(sides[i], "/")
      if q == nil || q[1].tag == :lit
        next
      name = i == 1 ? "div_" + op : op + "_div"
      rule = auto_loaded_rule(name + "_of_nonneg_den." + ty.name)
      if rule == nil
        next
      begin
        args = i == 1 ? [q[0], sides[2], q[1]] : [sides[1], q[0], q[1]]
        args.each -> (arg) rule = @k.spec(arg, rule)
        while dest_binop(rule.concl, "⇒") != nil
          premise = rule.concl.a.b
          proof = facts.find -> (th) tm_eq(th.concl, premise)
          if proof == nil
            branch = dest_binop(premise, "⇒")
            target = branch == nil ? premise : branch[1]
            local = branch == nil ? comparisons : comparisons + [@k.assume(branch[0])]
            if local.size > 10 || !auto_binary_cost_ok?([target] + (local.map -> (th) th.concl))
              break
            sub = goal.with_concl(target)
            proof = auto_arithmetic_proof(sub, local, [1])
            if proof == nil && branch != nil
              proof = auto_nonlinear_direct(sub, [1, 1], local)
            if proof != nil && branch != nil
              proof = @k.disch(branch[0], proof)
          if proof == nil
            break
          rule = @k.mp(rule, proof)
        if tm_eq(rule.concl, goal.concl)
          return rule
      rescue e
        0
    nil

  # Clear observed field quotients before polynomial arithmetic. The order
  # equivalences require positive denominators; cancellation only needs ≠ 0.
  -> auto_field_arithmetic(goal, hints)
    cmp = dest_cmp_rel(goal.concl)
    if cmp == nil || goal.hyps.size + hints.size > 8
      return nil
    ty = type_of(cmp[1])
    if ty != TY_RAT_SINGLETON && ty != TY_REAL_SINGLETON
      return nil
    if (goal.concl.search_ops & TERM_DIVMOD) == 0 && !goal.hyps.any?(-> (h) (h[1].search_ops & TERM_DIVMOD) != 0) && !hints.any?(-> (th) (th.concl.search_ops & TERM_DIVMOD) != 0)
      return nil
    begin
      raw = hints + (goal.hyps.map -> (h) @k.assume(h[1]))
      nodes = [256]
      if !auto_small_term?(goal.concl, nodes) || !raw.all?(-> (th) auto_small_term?(th.concl, nodes))
        return nil
      facts = []
      raw.each -> (th) normalize_comparisons(th, facts, true)
      if facts.size > 8
        return nil
      facts = facts.select -> (th)
        relation = numeric_disequality?(th.concl) ? th.concl.b : th.concl
        type_of(dest_cmp_rel(relation)[1]) == ty
      comparisons = facts.select -> (th) comparison?(th.concl)
      terms = []
      expressions = [goal.concl] + (comparisons.map -> (th) th.concl)
      expressions.each -> (term)
        if (term.search_ops & TERM_DIVMOD) != 0
          auto_collect_terms(term, terms)
      quotients = terms.select -> (term) dest_binop(term, "/") != nil && type_of(term) == ty && term.b.tag != :lit
      if quotients.size == 0 || quotients.size > 3
        return nil
      # Include the insides of every quotient. Ring normalization treats the
      # whole quotient as an atom until its denominator enters a guard.
      guard_terms = facts.map -> (th) numeric_disequality?(th.concl) ? th.concl.b : th.concl
      if !auto_binary_cost_ok?([goal.concl] + guard_terms + quotients)
        return nil
      enriched = comparisons + []
      quotients.each -> (quot)
        cancel = auto_guarded_field_rule("mul_div_cancel", [quot.a.b, quot.b], goal, facts)
        if cancel != nil
          auto_add_fact(enriched, cancel)
      comparisons.each -> (th)
        sides = dest_cmp_rel(th.concl)
        op = sides[0] == "=" ? "eq" : (sides[0] == "<" ? "lt" : "le")
        [1, 2].each -> (i)
          q = sides[i]
          if quotients.any?(-> (quot) tm_eq(quot, q))
            args = i == 1 ? [q.a.b, sides[2], q.b] : [sides[1], q.a.b, q.b]
            lemma = i == 1 ? "div_" + op + "_iff" : op + "_div_iff"
            iff = auto_guarded_field_rule(lemma, args, goal, facts)
            if iff != nil
              auto_add_fact(enriched, @k.eq_mp(iff, th))
      if enriched.size == comparisons.size || enriched.size > 10
        return nil
      if !auto_binary_cost_ok?([goal.concl] + (enriched.map -> (th) th.concl))
        return nil
      linear = auto_arithmetic_proof(goal, enriched, [1])
      if linear != nil
        return linear
      Prover.new(@session).quadratic_premise_proof(goal, enriched)
    rescue e
      nil

  -> auto_nonlinear_direct(goal, budget, facts = nil, split_nonzero = false)
    if budget.size < 2 || budget[1] <= 0 || !comparison?(goal.concl)
      return nil
    comparisons = []
    raw = facts == nil ? (goal.hyps.map -> (h) @k.assume(h[1])) : facts
    raw.each -> (th) normalize_comparisons(th, comparisons)
    ty = type_of(dest_cmp_rel(goal.concl)[1])
    disequalities = []
    if split_nonzero
      raw.each -> (th)
        negative = dest_unop(th.concl, "¬")
        equation = negative == nil ? nil : dest_binop(negative, "=")
        if equation != nil && ty_eq(type_of(equation[0]), ty)
          auto_add_fact(disequalities, th)
      if disequalities.size == 0 || disequalities.size > 2
        return nil
    if facts != nil
      comparisons = comparisons.select -> (th) ty_eq(type_of(dest_cmp_rel(th.concl)[1]), ty)
      # Nonzero premises can expose a contradictory component even when the
      # requested conclusion mentions different variables. Seed its atoms too.
      seeds = disequalities.map -> (th) dest_unop(th.concl, "¬")
      comparisons = auto_relevant_comparisons(goal, comparisons, seeds)
    if comparisons.size + disequalities.size > 8 || disequalities.size > 2
      return nil
    nodes = [64]
    nonlinear = false
    ([goal.concl] + (comparisons.map -> (th) th.concl) + (disequalities.map -> (th) dest_unop(th.concl, "¬"))).each -> (term)
      cmp = dest_cmp_rel(term)
      [cmp[1], cmp[2]].each -> (side)
        degree = auto_quadratic_degree(side, nodes)
        if degree < 0 || degree > 2
          nodes[0] = -1
        if degree == 2
          nonlinear = true
    if nodes[0] < 0 || !nonlinear
      return nil
    budget[1] -= 1
    begin
      # Fresh arithmetic state; only checked comparison proofs enter the solver.
      worker = Prover.new(@session)
      return worker.quadratic_premise_proof(goal, comparisons, disequalities)
    rescue e
      0
    if budget[1] <= 0
      return nil
    enriched = auto_equality_products(goal, comparisons, nodes)
    if enriched.size == comparisons.size
      return nil
    budget[1] -= 1
    begin
      worker = Prover.new(@session)
      worker.quadratic_premise_proof(goal, enriched, disequalities)
    rescue e
      nil

  # Multiplying an affine equality by a goal factor is ordinary congruence,
  # with no sign assumption. Keep the first arithmetic attempt unchanged;
  # this bounded retry supplies at most four degree-two equality consequences.
  -> auto_equality_products(goal, comparisons, nodes)
    ty = type_of(dest_cmp_rel(goal.concl)[1])
    terms = []
    auto_collect_terms(goal.concl, terms)
    factors = []
    terms.each -> (term)
      product = dest_binop(term, "*")
      if product != nil
        product.each -> (factor)
          if factor.tag != :lit && ty_eq(type_of(factor), ty) && !factors.any?(-> (old) tm_eq(old, factor))
            degree = auto_quadratic_degree(factor, [16])
            if degree == 1
              factors.push(factor)
    equalities = []
    comparisons.each -> (known)
      eq = @k.dest_eq(known.concl)
      if eq != nil && ty_eq(type_of(eq[0]), ty)
        degree_left = auto_quadratic_degree(eq[0], [32])
        degree_right = auto_quadratic_degree(eq[1], [32])
        if degree_left >= 0 && degree_left <= 1 && degree_right >= 0 && degree_right <= 1
          equalities.push(known)
    out = comparisons + []
    mul = @k.mk_const("*", ty_funs([ty, ty], ty))
    factors.each -> (factor)
      equalities.each -> (known)
        if out.size < comparisons.size + 4 && nodes[0] > 0
          eq = @k.dest_eq(known.concl)
          multiplier = mk_app(mul, factor)
          left = mk_app(multiplier, eq[0])
          right = mk_app(multiplier, eq[1])
          left_degree = auto_quadratic_degree(left, nodes)
          right_degree = auto_quadratic_degree(right, nodes)
          if nodes[0] >= 0 && left_degree <= 2 && right_degree <= 2
            auto_add_fact(out, @k.mk_comb(@k.refl(multiplier), known))
    out

  # Squared bounds often hide an order fact needed by a later product bound.
  # Derive at most two such facts, then replace their squared constraints in
  # the final search. Their checked proofs retain every original dependency.
  -> auto_square_bound_chain(goal, hints, budget)
    if !comparison?(goal.concl) || budget[1] < 2
      return nil
    ty = type_of(dest_cmp_rel(goal.concl)[1])
    raw = []
    goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), raw)
    hints.each -> (hint) normalize_comparisons(hint, raw)
    facts = []
    raw.each -> (th)
      if ty_eq(type_of(dest_cmp_rel(th.concl)[1]), ty)
        auto_add_fact(facts, th)
    if facts.size > 8
      return nil
    nodes = [64]
    ([goal.concl] + facts.map -> (th) th.concl).each -> (term)
      cmp = dest_cmp_rel(term)
      [cmp[1], cmp[2]].each -> (side)
        degree = auto_quadratic_degree(side, nodes)
        if degree < 0 || degree > 2
          nodes[0] = -1
    if nodes[0] < 0
      return nil
    bases = []
    seen = {}
    facts.each -> (th) nl_square_bases(th.concl, ty, bases, seen)
    if bases.size < 2 || bases.size > 4
      return nil
    if budget.size < 3
      budget.push(16)
    inferred = []
    eliminated = []
    power = @k.mk_const("^", ty_funs([ty, TY_NAT_SINGLETON], ty))
    bases.each -> (left)
      bases.each -> (right)
        if !tm_eq(left, right) && budget[1] > 1 && budget[2] > 0 && inferred.size < 2
          relations = dest_cmp_rel(goal.concl)[0] == "<" ? ["<", "≤"] : ["≤"]
          bound = nil
          relations.each -> (relation)
            if bound == nil && budget[1] > 1 && budget[2] > 0
              rel = @k.mk_const(relation, ty_funs([ty, ty], TY_BOOL_SINGLETON))
              square_left = mk_apps(power, [left, mk_lit(2, TY_NAT_SINGLETON)])
              square_right = mk_apps(power, [right, mk_lit(2, TY_NAT_SINGLETON)])
              squared = mk_apps(rel, [square_left, square_right])
              budget[2] -= 1
              ordered_squares = auto_arithmetic_proof(goal.with_concl(squared), facts, [1])
              if ordered_squares != nil
                conclusion = mk_apps(rel, [left, right])
                if !facts.any?(-> (th) tm_eq(th.concl, conclusion))
                  bound = auto_nonlinear_premise(goal.with_concl(conclusion), budget, facts)
          if bound != nil
            inferred.push(bound)
            eliminated.push(left)
            eliminated.push(right)
    if inferred.size == 0
      return nil
    remaining = inferred + []
    facts.each -> (th)
      used = []
      nl_square_bases(th.concl, ty, used, {})
      if !used.any?(-> (base) eliminated.any?(-> (old) tm_eq(old, base)))
        auto_add_fact(remaining, th)
    result = auto_arithmetic_proof(goal, remaining, [1])
    if result != nil
      return result
    auto_nonlinear_premise(goal, budget, remaining)

  -> quadratic_premise_proof(goal, comparisons, disequalities = [])
    @nl_mode = true
    linarith_proof(Goal.new(goal.fixes, [], goal.concl), comparisons + disequalities)

  # Small affine natural-number goals may contain truncated subtraction.
  # Use omega's checked case split, with the same shared auto budget.
  -> auto_natural_arithmetic(goal, budget)
    cmp = dest_cmp_rel(goal.concl)
    if cmp == nil || !ty_eq(type_of(cmp[1]), ty_nat) || budget[0] <= 0 || find_nat_sub(goal, []) == nil
      return nil
    ["le_total.nat", "sub_add_cancel.nat", "sub_eq_zero.nat"].each -> (name)
      if auto_loaded_rule(name) == nil
        return nil
    comparisons = [goal.concl]
    goal.hyps.each -> (h)
      if comparison?(h[1])
        comparisons.push(h[1])
    if comparisons.size > 9
      return nil
    nodes = [64]
    comparisons.each -> (term)
      sides = dest_cmp_rel(term)
      [sides[1], sides[2]].each -> (side)
        degree = auto_quadratic_degree(side, nodes)
        if degree < 0 || degree > 1
          nodes[0] = -1
    if nodes[0] < 0
      return nil
    budget[0] -= 1
    begin
      worker = Prover.new(@session)
      worker.natural_arithmetic_proof(goal)
    rescue e
      nil

  -> natural_arithmetic_proof(goal, extra = [])
    @omega_mode = true
    linarith_proof(goal, extra)

  # A power step can sit inside a larger ring identity. Try its algebra
  # first, then justify the exact change of exponent over the naturals.
  -> auto_power_step(goal, hints)
    if (goal.concl.search_ops & TERM_POWER) == 0 || !auto_small_term?(goal.concl, [128])
      return nil
    terms = []
    auto_collect_terms(goal.concl, terms)
    powers = terms.select -> (t) t.tag == :app && t.a.tag == :app && t.a.a.op == OP_POW && t.b.tag != :lit
    if powers.size < 2 || powers.size > 4 || goal.hyps.size + hints.size > 12
      return nil
    bounds = []
    raw = []
    goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), raw, true)
    hints.each -> (hint) normalize_comparisons(hint, raw, true)
    raw.each -> (th)
      rel = numeric_disequality?(th.concl) ? th.concl.b : th.concl
      if type_of(rel.a.b) == TY_NAT_SINGLETON
        nodes = [64]
        degrees = [rel.a.b, rel.b].map -> (side) auto_quadratic_degree(side, nodes)
        if degrees.all?(-> (d) d >= 0 && d <= 1)
          auto_add_fact(bounds, th)
    if bounds.size > 8
      return nil
    powers.each -> (high)
      rule = auto_loaded_rule("pow_succ." + type_of(high).name)
      if rule != nil
        powers.each -> (low)
          if !tm_eq(low, high) && tm_eq(low.a, high.a)
            proof = power_step_pair(goal, high, low, rule, bounds, hints)
            if proof != nil
              return proof
    nil

  -> power_step_pair(goal, high, low, rule, bounds, hints)
    begin
      step = @k.spec(low.b, @k.spec(low.a.b, rule))
      successor_power = @k.dest_eq(step.concl)[0]
      index = @k.eq_tm(high.b, successor_power.b)
      rewrite = @k.trans(@d.ap_term(high.a, @k.assume(index)), step)
      bridge = power_rewrite_identity(goal.concl, [rewrite])
      index_goal = goal.with_concl(index)
      ascending = power_index_proof(index_goal, bounds, hints)
      if ascending != nil
        return @d.prove_hyp(ascending, bridge)
      # At zero the predecessor saturates. The entire original equation
      # must hold there, for example because a weight vanishes.
      zero = @k.eq_tm(high.b, mk_lit(0, ty_nat))
      base = power_zero_case(goal, @k.assume(zero), bounds)
      nonzero = @k.neg_tm(zero)
      ascending = power_index_proof(index_goal.add_hyp("_nonzero", nonzero), bounds + [@k.assume(nonzero)], hints)
      if ascending != nil
        return @k.disj_cases(@k.excluded_middle(zero), base, @d.prove_hyp(ascending, bridge))
    rescue e
      return nil
    nil

  -> power_zero_case(goal, zero, bounds)
    equations = [zero]
    exponent = zero.concl.a.b
    if exponent.tag != :var
      # An exponent such as m+n can vanish only when both summands do.
      # Only substitute variables whose zero value arithmetic actually proves.
      variables = tm_frees(exponent)
      if variables.size <= 3
        variables.each -> (v)
          if v.ty == TY_NAT_SINGLETON
            claim = @k.eq_tm(v, zero.concl.b)
            th = power_index_proof(goal.with_concl(claim), bounds + [zero], [])
            if th != nil
              equations.push(th)
    power_rewrite_identity(goal.concl, equations)

  -> power_rewrite_identity(conclusion, equations)
    conv = @k.refl(conclusion)
    equations.each -> (eq)
      rewrite = replace_conv_opt(conv.concl.b, eq.concl.a.b, eq)
      if rewrite != nil
        conv = @k.trans(conv, rewrite)
    sides = @k.dest_eq(conv.concl.b)
    sides.each -> (side) recurrence_ring_cost(side, type_of(side).name, [128])
    folder = Simp.new(@d, [])
    folder.step_limit = 256
    conv = @k.trans(conv, folder.simp_conv(conv.concl.b))
    @k.eq_mp(@k.sym(conv), auto_relation_result(conv.concl.b, [1]))

  -> power_index_proof(goal, bounds, hints)
    sides = @k.dest_eq(goal.concl)
    if tm_eq(sides[0], sides[1])
      return @k.refl(sides[0])
    reversed = @k.eq_tm(sides[1], sides[0])
    bounds.each -> (th)
      if tm_eq(th.concl, goal.concl)
        return th
      if tm_eq(th.concl, reversed)
        return @k.sym(th)
    nodes = [64]
    if !sides.all?(-> (side) [0, 1].include?(auto_quadratic_degree(side, nodes)))
      return nil
    begin
      proof = Prover.new(@session).natural_arithmetic_proof(Goal.new(goal.fixes, [], goal.concl), bounds)
      if proof.tags.all?(-> (tag) tag == "oracle:arith" || tag == "oracle:ring" || bounds.any?(-> (th) th.tags.include?(tag)))
        return proof
    rescue e
      0
    rules = hints + auto_local_hints(goal)
    auto_hint_proof(goal, rules, hints, [4, 1], [])

  # Candidate premises are solved in detached
  # proof states; a failed candidate cannot refine or solve the caller's goal.
  -> auto_hint_proof(goal, candidates, hints, budget, seen)
    if budget[0] <= 0
      return nil
    seen.each -> (previous)
      if tm_eq(previous, goal.concl)
        return nil
    # A quantified guard can introduce a fresh i on every application of the
    # same rule, recreating the same pointwise goal under a different name.
    # Abstract just the binders introduced by this premise. Outer variables
    # stay fixed, and the other rules and direct tactics remain available.
    pointwise = nil
    if @auto_rule_path.size > 0
      first = @auto_rule_path.last[2]
      i = goal.fixes.size - 1
      if i >= first
        pointwise = goal.concl
        while i >= first
          pointwise = mk_lam(goal.fixes[i][1], pointwise)
          i -= 1
    candidates.each -> (hint)
      repeated = false
      if pointwise != nil
        repeated = @auto_rule_path.any? -> (entry)
          entry[1] != nil && tm_eq(entry[0], hint.concl) && tm_eq(entry[1], pointwise)
      if !repeated && budget[0] > 0
        budget[0] -= 1
        begin
          applied = instantiate_to(goal, hint, [], goal.concl, true, hints, true)
          result = applied[0]
          applied[1].each -> (premise)
            normalized = @d.beta_norm_term(premise)
            if tm_eq(normalized, goal.concl) || seen.any?(-> (previous) tm_eq(previous, normalized))
              fail("auto: cyclic rule premise")
            sub = Prover.new(@session, application_conversions)
            sub.registered_search = @registered_search
            sub.auto_rule_path = @auto_rule_path + [[hint.concl, pointwise, goal.fixes.size]]
            ref = GoalRef.new(goal.with_concl(normalized), nil, 0)
            sub.goals = [ref]
            sub.tac_auto(ref, 3, hints, budget, seen + [goal.concl])
            if ref.thm == nil || sub.goals.size != 0
              fail("auto: a lemma premise remains open")
            proof = sub.fit(ref, ref.thm)
            # Matching x*x against x² may add a ring conversion to a premise.
            # Reuse the rule's arithmetic oracle if its certificate suffices.
            if proof.tags.include?("oracle:ring") && !result.tags.include?("oracle:ring") && result.tags.include?("oracle:arith") && comparison?(normalized)
              facts = goal.hyps.map -> (h) @k.assume(h[1])
              direct = auto_arithmetic_proof(ref.goal, facts, [1])
              if direct != nil && direct.tags.all?(-> (tag) result.tags.include?(tag))
                proof = direct
            result = @d.prove_hyp(fit_concl(proof, premise), result)
          return fit_concl(result, goal.concl)
        rescue e
          0
    nil

  # A local bound can expose the missing monotonicity step: from c <= b^n,
  # prove b^n <= x^n, then combine the two checked comparisons. Endpoints come
  # from existing facts; strictness, hypotheses and named tags are retained.
  -> auto_bound_chain(goal, hints, budget, seen)
    target = dest_cmp_rel(goal.concl)
    if target == nil || !["≤", "<"].include?(target[0]) || !numeric_type?(type_of(target[1])) || budget[0] <= 0 || seen.size >= 6
      return nil
    if seen.any?(-> (previous) tm_eq(previous, goal.concl))
      return nil
    facts = []
    goal.hyps.each -> (h) normalize_comparisons(@k.assume(h[1]), facts)
    hints.each -> (hint) normalize_comparisons(hint, facts)
    attempted = []
    bridges = [16]
    # Keep exact endpoint chains first. A second pass permits checked affine
    # bridges such as c < c+1 or c-1 < c, without inventing new terms.
    [false, true].each -> (affine)
      facts.each -> (known)
        bound = dest_cmp_rel(known.concl)
        if ["≤", "<"].include?(bound[0]) && ty_eq(type_of(bound[1]), type_of(target[1]))
          [false, true].each -> (upper)
            endpoint = upper ? bound[2] : bound[1]
            outer = upper ? target[2] : target[1]
            exact = tm_eq(endpoint, outer)
            if exact != affine && attempted.size < 4 && budget[0] > 0
              ends = upper ? [target[1], bound[1]] : [bound[2], target[2]]
              relation = target[0] == "<" && bound[0] == "≤" ? "<" : "≤"
              supporting = [known]
              viable = exact
              if affine && bridges[0] > 0
                bridge_ends = upper ? [endpoint, outer] : [outer, endpoint]
                bridge_term = mk_apps(@k.mk_const(relation, ty_funs([type_of(outer), type_of(outer)], ty_bool)), bridge_ends)
                bridge = auto_arithmetic_proof(goal.with_concl(bridge_term), facts, bridges)
                if bridge == nil && relation == "<" && bridges[0] > 0
                  bridge_term = mk_apps(@k.mk_const("≤", ty_funs([type_of(outer), type_of(outer)], ty_bool)), bridge_ends)
                  bridge = auto_arithmetic_proof(goal.with_concl(bridge_term), facts, bridges)
                elsif bridge != nil
                  relation = "≤"
                if bridge != nil
                  supporting.push(bridge)
                  viable = true
              premise = mk_apps(@k.mk_const(relation, ty_funs([type_of(target[1]), type_of(target[1])], ty_bool)), ends)
              if viable && !tm_eq(premise, goal.concl) && !seen.any?(-> (old) tm_eq(old, premise)) && !attempted.any?(-> (old) tm_eq(old, premise))
                attempted.push(premise)
                budget[0] -= 1
                begin
                  sub = Prover.new(@session)
                  sub.registered_search = @registered_search
                  ref = GoalRef.new(goal.with_concl(premise), nil, 0)
                  sub.goals = [ref]
                  sub.tac_auto(ref, 3, hints, budget, seen + [goal.concl])
                  if ref.thm != nil && sub.goals.size == 0
                    supporting.push(sub.fit(ref, ref.thm))
                    result = auto_arithmetic_proof(goal, supporting, [1])
                    if result != nil
                      return result
                rescue e
                  0
    auto_normalized_bound_chain(goal, hints, budget, seen, facts, attempted)

  # Cancel offsets or scalar factors only through a checked arithmetic proof.
  # Seek a bound on an existing application whose head fits the other endpoint;
  # do not enumerate arbitrary term pairs or invent algebraic expressions.
  -> auto_normalized_bound_chain(goal, hints, budget, seen, facts, attempted)
    if budget.size < 3
      budget.push(16)
    if budget[0] <= 0 || budget[2] <= 0 || attempted.size >= 4 || facts.size > 16
      return nil
    target = dest_cmp_rel(goal.concl)
    terms = []
    facts.each -> (known) auto_collect_terms(known.concl, terms)
    [false, true].each -> (upper)
      other = upper ? target[1] : target[2]
      heads = auto_operand_heads(other)
      terms.each -> (pivot)
        if pivot.tag == :app && ty_eq(type_of(pivot), type_of(other)) && !tm_eq(pivot, other) && auto_operand_heads(pivot).any?(-> (head) heads.include?(head)) && budget[0] > 0 && budget[2] > 0 && attempted.size < 4
          ends = upper ? [target[1], pivot] : [pivot, target[2]]
          bound_ends = upper ? [pivot, target[2]] : [target[1], pivot]
          relation = target[0]
          bound = nil
          [relation, "≤"].uniq().each -> (bound_relation)
            if bound == nil && budget[2] > 0
              budget[2] -= 1
              conclusion = mk_apps(@k.mk_const(bound_relation, ty_funs([type_of(other), type_of(other)], ty_bool)), bound_ends)
              bound = auto_arithmetic_proof(goal.with_concl(conclusion), facts, [1])
              if bound == nil
                bound = auto_nonlinear_premise(goal.with_concl(conclusion), budget, facts)
              if bound != nil
                relation = target[0] == "<" && bound_relation == "≤" ? "<" : "≤"
          if bound != nil
            premise = mk_apps(@k.mk_const(relation, ty_funs([type_of(other), type_of(other)], ty_bool)), ends)
            if !tm_eq(premise, goal.concl) && !seen.any?(-> (old) tm_eq(old, premise)) && !attempted.any?(-> (old) tm_eq(old, premise))
              attempted.push(premise)
              budget[0] -= 1
              begin
                sub = Prover.new(@session)
                sub.registered_search = @registered_search
                ref = GoalRef.new(goal.with_concl(premise), nil, 0)
                sub.goals = [ref]
                sub.tac_auto(ref, 3, hints, budget, seen + [goal.concl])
                if ref.thm != nil && sub.goals.size == 0
                  result = auto_arithmetic_proof(goal, [bound, sub.fit(ref, ref.thm)], [1])
                  if result != nil
                    return result
              rescue e
                0
    nil

  # Preserve supplied algebraic interfaces while exposing recursive equations.
  # Their left-hand sides must survive until the corresponding rule can apply.
  -> auto_relation_hint_premise(goal, hints)
    facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
    rules = []
    protected = []
    nodes = [4096]
    facts.each -> (fact)
      if auto_small_term?(fact.concl, [512])
        auto_relation_parts(fact, [8]).each -> (part)
          if rules.size < 32
            rule = make_rule(@d, part, "algebraic interface")
            rules.push(rule)
            if dest_unop(part.concl, "∀") != nil
              auto_relation_heads(rule.lhs, protected, nodes)
    definitions = auto_relation_definitions(goal.all_terms + (hints.map -> (hint) hint.concl))
    visible = definitions.select -> (rule) !protected.include?(rule.head_name)
    simplifier = Simp.new(@d, rules + visible)
    simplifier.hyp_rules = facts
    simplifier.step_limit = 512
    conversion = simplifier.simp_conv(goal.concl, 0)
    conclusion = dest_binop(conversion.concl, "=")[1]
    if tm_eq(conclusion, goal.concl) || !auto_small_term?(conclusion, [1024])
      fail("algebraic interface: no bounded rewrite")
    proof = auto_recurrence_premise(goal.with_concl(conclusion), hints, true, true)
    @k.eq_mp(@k.sym(conversion), proof)

  # A list step may distinguish its finite head. Open the existing induction
  # premise, then check all constructor cases without starting another induction.
  -> auto_list_identity_premise(goal, hints, budget)
    worker = Prover.new(@session)
    root = GoalRef.new(goal, nil, 0)
    worker.goals = [root]
    ref = worker.tac_intro(root, [], true)
    proof = worker.auto_finite_cases(ref.goal, hints, budget)
    if proof == nil
      proof = worker.auto_relation_hint_premise(ref.goal, hints)
    worker.close(ref, worker.fit(ref, proof))
    worker.fit(root, root.thm)

  -> auto_finite_leaf(goal, hints, budget)
    worker = Prover.new(@session)
    ref = GoalRef.new(goal, nil, 0)
    worker.goals = [ref]
    begin
      worker.tac_decide(ref)
      return worker.fit(ref, ref.thm)
    rescue e
      0
    if auto_relation_shape?(goal.concl, [4])
      begin
        return auto_recurrence_premise(goal, hints, true, true)
      rescue e
        0
    begin
      return auto_list_bound_premise(goal, hints, budget)
    rescue e
      0
    auto_relation_hint_premise(goal, hints)

  # Existing cases reconstruction supplies every branch; no constructor is
  # sampled or assumed. The selected types have at most four nullary cases.
  -> auto_finite_split(goal, hints, budget, variables, at)
    if at == variables.size
      if budget[0] <= 0
        fail("finite cases: branch budget exhausted")
      budget[0] -= 1
      return auto_finite_leaf(goal, hints, budget)
    worker = Prover.new(@session)
    root = GoalRef.new(goal, nil, 0)
    worker.goals = [root]
    worker.tac_induction_impl(root, [Tok.new(:id, variables[at][0], 0, 0)], [], false)
    branches = worker.goals + []
    branches.each -> (branch)
      proof = auto_finite_split(branch.goal, hints, budget, variables, at + 1)
      worker.close(branch, proof)
    if root.thm == nil || worker.goals.size != 0
      fail("finite cases: open constructor case")
    worker.fit(root, root.thm)

  # At most two finite variables and sixteen complete branches. Prefer
  # variables in the conclusion; inspect hypotheses when it has none.
  -> auto_finite_cases(goal, hints, budget)
    if budget[0] <= 0 || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256])
      return nil
    variables = []
    cases = 1
    [false, true].each -> (in_hyps)
      if variables.size == 0
        goal.fixes.each -> (fix)
          info = @k.inductive_of_type(fix[1].ty)
          relevant = in_hyps ? goal.hyps.any?(-> (h) tm_free_in?(fix[1], h[1])) : tm_free_in?(fix[1], goal.concl)
          if variables.size < 2 && relevant && info != nil && info.ctors.size > 0 && info.ctors.size <= 4 && info.ctors.all?(-> (ctor) ctor[1].size == 0)
            variables.push(fix)
            cases *= info.ctors.size
    if variables.size == 0 || cases > budget[0]
      return nil
    # Keep a failed case trial from exhausting unrelated hint/rule search.
    # Its own branch and logical work still share the existing bounded fuel.
    trial = [budget[0], budget[1]]
    budget[0] -= 1
    begin
      auto_finite_split(goal, hints, trial, variables, 0)
    rescue e
      nil

  # For P or Q, the Q case is immediate; prove P under not Q. Reconstruct
  # both cases with excluded middle, retaining all arithmetic dependencies.
  -> auto_arithmetic_disjunction(goal, depth, hints, budget, seen)
    parts = dest_binop(goal.concl, "∨")
    if parts == nil || depth <= 1 || budget[0] <= 0 || goal.hyps.size > 12 || hints.size > 8 || !auto_small_term?(goal.concl, [256]) || !parts.all?(-> (part) comparison?(part))
      return nil
    [1, 0].each -> (side)
      if budget[0] > 0
        budget[0] -= 1
        begin
          condition = parts[side]
          name = "arithmetic_case"
          while goal.hyps.any?(-> (hyp) hyp[0] == name)
            name += "_"
          branch = goal.with_concl(parts[1-side]).add_hyp(name, @k.neg_tm(condition))
          worker = Prover.new(@session)
          worker.registered_search = @registered_search
          ref = GoalRef.new(branch, nil, 0)
          worker.goals = [ref]
          worker.tac_auto(ref, depth-1, hints, budget, seen + [goal.concl])
          if ref.thm != nil && worker.goals.size == 0
            proof = worker.fit(ref, ref.thm)
            yes = side == 1 ? @k.disj2(parts[0], @k.assume(condition)) : @k.disj1(@k.assume(condition), parts[1])
            no = side == 1 ? @k.disj1(proof, parts[1]) : @k.disj2(parts[0], proof)
            return @k.disj_cases(@k.excluded_middle(condition), yes, no)
        rescue e
          0
    nil

  # Only shorten a diagnostic with an unconditional, dependency-free equivalence.
  -> show_missing_condition(missing)
    original = tm_show(missing)
    begin
      simp = Simp.new(@d, [], @session.simp_by_head, @session.simp_general)
      simp.step_limit = 128
      conv = simp.simp_conv_opt(missing, 0)
      if conv != nil && conv.hyps.size == 0 && conv.tags.size == 0
        rhs = conv.concl.b
        if rhs.op != OP_TRUE && rhs.op != OP_FALSE
          short = tm_show(rhs)
          if short.size < original.size
            return short
    rescue e
      return original
    original

  # Run once at the tactic boundary, never while auto is exploring a branch.
  -> strict_bound_feedback(goal, hints)
    sides = dest_binop(goal.concl, "<")
    if sides == nil || !numeric_type?(type_of(sides[0]))
      return nil
    ty = type_of(sides[0])
    le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
    th = feedback_proof(goal.with_concl(mk_apps(le, sides)), hints)
    if th == nil
      return nil
    equal = @k.eq_tm(sides[0], sides[1])
    apart = @k.neg_tm(equal)
    nodes = [384]
    small_context = goal.hyps.size <= 12 && goal.hyps.all?(-> (h) auto_small_term?(h[1], nodes))
    small_hints = hints.size <= 8 && hints.all?(-> (hint) auto_small_term?(hint.concl, nodes))
    if small_context && small_hints && auto_small_term?(goal.concl, [96])
      begin
        sides.each -> (side) recurrence_ring_cost(side, ty.name, [96])
        allowed = th.tags + ["oracle:arith", "oracle:ring", "oracle:sat"]
        hints.each -> (hint) allowed = tags_union(allowed, hint.tags)
        same = feedback_proof(goal.with_concl(equal), hints)
        if same != nil
          if !same.tags.include?("sorry") && same.tags.all?(-> (tag) allowed.include?(tag))
            return checked_progress_note(same, nil)
          # The tie conflicts with a proposed repair, but its dependencies
          # cannot justify reporting it. Suppress the other diagnostic routes.
          return false
        note = strict_argument_feedback(goal, sides, th, equal, hints, allowed)
        if note != nil
          return note
      rescue diagnostic_error
        0
    checked_progress_note(th, apart)

  # Try the arguments of the same unary or binary operation. A smaller gap
  # must suffice for strictness, and closing it must force equal endpoints.
  -> strict_argument_feedback(goal, sides, bound, equal, hints, allowed)
    if sides[0].tag != :app || sides[1].tag != :app
      return nil
    left = strip_app(sides[0])
    right = strip_app(sides[1])
    if !tm_eq(left[0], right[0]) || left[1].size != right[1].size || left[1].size > 2
      return nil
    original = show_missing_condition(@k.neg_tm(equal))
    left[1].each_with_index -> (a, i)
      b = right[1][i]
      if tm_eq(a, b)
        ty = type_of(a)
        if a.tag == :lit || !numeric_type?(ty)
          next
        b = mk_lit(ty == ty_rat || ty == ty_real ? Q_ZERO : 0, ty)
      same = @k.eq_tm(a, b)
      missing = @k.neg_tm(same)
      if tm_show(missing).size >= original.size || find_assumption(goal.with_concl(missing)) != nil
        next
      collapse = feedback_proof(goal.with_concl(equal).add_hyp("_same", same), hints)
      if collapse == nil || !collapse.tags.all?(-> (tag) allowed.include?(tag))
        next
      repair = feedback_proof(goal.add_hyp("_apart", missing), hints)
      if repair == nil || !repair.tags.all?(-> (tag) allowed.include?(tag)) || feedback_proof(goal.with_concl(missing), hints) != nil
        next
      forced = feedback_proof(goal.with_concl(same), hints)
      if forced == nil
        return checked_progress_note(bound, missing, nil, [collapse, repair])
      if forced.tags.all?(-> (tag) allowed.include?(tag))
        return checked_progress_note(@d.prove_hyp(forced, collapse), nil)
    nil

  -> feedback_proof(goal, hints)
    ref = GoalRef.new(goal, nil, 0)
    probe = Prover.new(@session, application_conversions)
    probe.registered_search = @registered_search
    probe.goals = [ref]
    begin
      probe.tac_auto(ref, 3, hints, [24, 4], [])
      if ref.thm == nil || probe.goals.size != 0
        return nil
      probe.fit(ref, ref.thm)
    rescue e
      nil

  # A rule offers a repair only after matching the actual goal and discharging
  # every other premise. Explicit hints take priority over library suggestions.
  -> hint_feedback(goal, hints)
    nodes = [128]
    if hints.size > 8 || goal.hyps.size > 12 || !auto_small_term?(goal.concl, nodes)
      return nil
    fuel = [6]
    note = rule_feedback(goal, hints, hints, fuel)
    if note == nil && fuel[0] > 0 && @session.auto_rules.size > 0
      rules = auto_registered_hints(goal)
      # For a specific arithmetic conclusion, a large theorem may already
      # have all but one hypothesis in scope. Check those direct matches
      # before smaller rules with wildcard operands consume the search fuel.
      shape = auto_rule_shape(goal.concl)
      if shape != nil && (shape[1] != "*" || shape[2] != "*")
        key = "math|" + shape.join("|")
      elsif dest_unop(goal.concl, "∃") != nil
        key = auto_relation_operand_key(goal.concl)
      else
        key = nil
      if key != nil
        entries = @session.auto_rule_index[key]
        if entries != nil
          direct = entries.select(-> (entry) @session.theorems[entry[0]] == entry[1]).map -> (entry) entry[2]
          note = direct_rule_feedback(goal, arr_sub(direct, 0, 4), hints)
      if note == nil
        note = auto_quantified_bound(goal, hints, true)
      if note == nil
        note = rule_feedback(goal, arr_sub(rules, 0, 8), hints, fuel)
    if note != nil || (goal.hyps.size == 0 && hints.size == 0)
      return note
    # An unsolicited repair must use the caller's evidence and leave a
    # smaller premise. Limit these probes to assumptions and linear arithmetic.
    defaults = auto_default_hints(goal)
    if defaults.size == 0
      return nil
    facts = (goal.hyps.map -> (h) @k.assume(h[1])) + hints
    input_nodes = [384]
    if !facts.all?(-> (th) auto_small_term?(th.concl, input_nodes))
      return nil
    numeric = []
    facts.each -> (th) normalize_comparisons(th, numeric, true)
    terms = numeric.map -> (th) numeric_disequality?(th.concl) ? th.concl.b : th.concl
    if numeric.size > 12 || !auto_binary_cost_ok?(terms)
      return nil
    rule_feedback(goal, arr_sub(defaults, 0, 12), hints, [8], numeric, 127 - nodes[0])

  -> match_feedback_rule(goal, hint, hints, node_limit)
    if hint.tags.include?("sorry") || !auto_small_term?(hint.concl, [node_limit])
      return nil
    body = hint.concl
    while dest_unop(body, "∀") != nil && body.b.tag == :lam
      body = body.b.b
    if dest_binop(body, "⇒") == nil
      return nil
    instantiate_to(goal, hint, [], goal.concl, true, hints, true)

  -> rule_feedback(goal, candidates, hints, fuel, numeric = nil, missing_limit = 128)
    candidates.each -> (hint)
      if fuel[0] == 0
        return nil
      begin
        applied = match_feedback_rule(goal, hint, hints, 128)
        if applied != nil && (numeric == nil || applied[1].size >= 2)
          note = hint_premise_note(goal, applied, hints, fuel, numeric, missing_limit, 4)
          if note != nil
            return note
      rescue e
        0
    nil

  # For rules with the same conclusion shape, prefer a repair that uses
  # more of the author's facts. Equal scores keep registration order.
  -> direct_rule_feedback(goal, candidates, hints)
    ranked = []
    candidates.each -> (hint)
      begin
        applied = match_feedback_rule(goal, hint, hints, 512)
        if applied != nil && applied[1].size >= 2 && applied[1].size <= 8
          score = goal.hyps.count -> (h) hyps_has?(applied[1], h[1])
          ranked.push([score, applied])
      rescue e
        0
    fuel = [6]
    ranked.sort_by(-> (entry) -entry[0]).each -> (entry)
      if fuel[0] <= 0
        return nil
      begin
        note = hint_premise_note(goal, entry[1], hints, fuel, [], 128, 8)
        if note != nil
          return note
      rescue e
        0
    nil

  -> default_premise_evidence(goal, hints, numeric, fuel)
    given = hints.find -> (th) tm_eq(th.concl, goal.concl)
    if given != nil
      return [given, true]
    if !comparison?(goal.concl) && !numeric_disequality?(goal.concl)
      return [nil, false]
    term = numeric_disequality?(goal.concl) ? goal.concl.b : goal.concl
    if !auto_binary_cost_ok?([term])
      return [nil, false]
    sides = dest_cmp_rel(term)
    if sides != nil && sides[1].tag == :lit && sides[2].tag == :lit
      value = @k.compute(goal.concl)
      if is_const?(value.concl.b, "⊤")
        return [@d.eqt_elim(value), false]
    # Probe under assumptions to distinguish arithmetic truths from facts
    # that use the context. Restore the dependencies of every used hint.
    assumptions = numeric.map -> (th) @k.assume(th.concl)
    proof = auto_arithmetic_proof(goal, assumptions, fuel)
    if proof == nil || proof.hyps.size == 0
      return [proof, false]
    used = proof.hyps
    used.each -> (premise)
      source = numeric.find -> (th) tm_eq(th.concl, premise)
      if source == nil
        return [nil, false]
      proof = @d.prove_hyp(source, proof)
    [proof, true]

  -> hint_premise_note(goal, applied, hints, fuel, numeric, missing_limit, premise_limit)
    if applied[1].size == 0 || applied[1].size > premise_limit
      return nil
    result = applied[0]
    supported = numeric == nil
    known = nil
    missing = nil
    seen = {}
    applied[1].each -> (premise)
      if !tm_set_add?(seen, premise)
        next
      if !auto_small_term?(premise, [128]) || tm_contains?(premise, goal.concl)
        return nil
      sub = goal.with_concl(premise)
      proof = find_assumption(sub)
      if proof == nil
        if fuel[0] <= 0
          return nil
        if numeric == nil
          fuel[0] -= 1
          proof = feedback_proof(sub, hints)
        else
          found = default_premise_evidence(sub, hints, numeric, fuel)
          proof = found[0]
          supported = supported || found[1]
      if proof != nil
        if proof.hyps.size > 0
          supported = true
        known = known == nil ? proof : @k.conj(known, proof)
        result = @d.prove_hyp(proof, result)
      elsif missing == nil
        missing = premise
      else
        return nil
    if !supported || missing == nil || fuel[0] <= 0 || !auto_small_term?(missing, [missing_limit])
      return nil
    fuel[0] -= 1
    if feedback_proof(goal.with_concl(@k.neg_tm(missing)), hints) != nil
      return nil
    ref = GoalRef.new(goal.add_hyp("_premise", missing), nil, 0)
    conditional = @k.disch(missing, fit(ref, result))
    progress = known == nil ? conditional : known
    if dest_binop(auto_rule_conclusion(missing), "∧") != nil
      note = conjunct_premise_note(goal, hints, missing, conditional)
      if note == false
        return nil
      if note != nil
        return note
    if dest_binop(missing, "<") != nil && auto_binary_cost_ok?([missing])
      note = strict_premise_note(goal, hints, missing, conditional, progress)
      if note != nil
        return note
    checked_progress_note(progress, missing, nil, [conditional])

  # A bundled condition may repeat evidence the caller supplied separately.
  # Keep the binders and guards on each part, and check the smaller repair.
  -> conjunct_premise_note(goal, hints, premise, conditional)
    begin
      known = nil
      gap = nil
      parts = auto_relation_parts(@k.assume(premise), [4])
      parts.each -> (part)
        proof = find_assumption(goal.with_concl(part.concl))
        if proof == nil
          proof = hints.find -> (hint) tm_eq(hint.concl, part.concl)
        if proof != nil
          known = known == nil ? proof : @k.conj(known, proof)
        elsif gap == nil || tm_eq(gap, part.concl)
          gap = part.concl
        else
          return nil
      if known == nil || gap == nil
        return nil
      sub = goal.with_concl(premise).add_hyp("_part", gap)
      repair = feedback_proof(sub, hints)
      if repair == nil || !hyps_has?(repair.hyps, gap)
        return nil
      if feedback_proof(goal.with_concl(@k.neg_tm(gap)), hints) != nil
        return false
      checked_progress_note(known, gap, nil, [@k.disch(gap, @k.mp(conditional, repair))])
    rescue unsupported
      nil

  # A local weak bound may express the missing strict comparison in simpler
  # coordinates. Under that bound, check both directions before naming the gap.
  -> strict_premise_note(goal, hints, missing, conditional, progress)
    size = tm_show(@k.neg_tm(@k.eq_tm(missing.a.b, missing.b))).size
    trials = 4
    (hyp_thms(goal) + hints).reverse.each -> (bound)
      sides = dest_binop(bound.concl, "≤")
      if sides == nil || !ty_eq(type_of(sides[0]), type_of(missing.b)) || !auto_binary_cost_ok?([bound.concl])
        next
      equal = @k.eq_tm(sides[0], sides[1])
      apart = @k.neg_tm(equal)
      if tm_show(apart).size > size || bound.tags.include?("sorry")
        next
      if trials == 0
        return nil
      trials -= 1
      begin
        necessary = linarith_proof(Goal.new(goal.fixes, [], apart), [@k.assume(missing)])
        strict = linarith_proof(Goal.new(goal.fixes, [], missing), [bound, @k.assume(apart)])
        if !hyps_has?(necessary.hyps, missing) || !hyps_has?(strict.hyps, apart)
          next
        repair = @k.disch(apart, @k.mp(conditional, strict))
        return checked_progress_note(bound, apart, nil, [repair, @k.disch(missing, necessary), progress])
      rescue e
        0
    nil

  -> checked_progress_note(th, missing, witness = nil, support = [])
    tags = th.tags
    support.each -> (proof) tags = tags_union(tags, proof.tags)
    if tags.include?("sorry")
      return nil
    proved = tm_show(th.concl)
    need = missing == nil ? nil : show_missing_condition(missing)
    deps = tags.select -> (tag) tag.starts_with?("split:")
    if deps.size > 0
      # Split workers can only vouch for premises once their checks finish.
      fields = ["⋯ partial-proof", proved]
      if need != nil
        fields.push(need)
      if witness != nil
        fields.push(witness)
      return fields.join("\t") + "   \[" + deps.join(", ") + "]"
    partial_proof_note(proved, need, witness)

  # Isolate the quantified variable over a dense ordered field. Endpoints are
  # suggestions: the checker proves each original conjunct at the chosen value.
  -> auto_interval_witness(goal, ex, known)
    if (ex.ty != TY_RAT_SINGLETON && ex.ty != TY_REAL_SINGLETON) || !auto_small_term?(ex.b, [128])
      return nil
    parts = witness_components(ex.b)
    if parts.size > 6
      return nil
    ty = ex.ty
    opened = dest_lam_fresh(ex, goal.all_terms)
    v = opened[0]
    lower = []
    upper = []
    symbolic = []
    fixed = nil
    minus = @k.mk_const("-", ty_funs([ty, ty], ty))
    times = @k.mk_const("*", ty_funs([ty, ty], ty))
    begin
      parts.each -> (part)
        cmp = dest_cmp_rel(tm_instantiate(part, v, 0))
        if cmp == nil || !ty_eq(type_of(cmp[1]), ty)
          return nil
        if occurs_bnd(part, 0)
          difference = mk_apps(minus, [cmp[2], cmp[1]])
          poly = recurrence_atom_coefficients(@k, difference, v, v)
          if poly[0] == 0
            next
          slope = poly[1][1]
          if poly[0] != 1
            return nil
          if slope.tag != :lit
            if cmp[0] == "="
              return nil
            symbolic.push([part, slope])
            next
          if tm_eq(cmp[1], v) && !tm_free_in?(v, cmp[2])
            bound = cmp[2]
          elsif tm_eq(cmp[2], v) && !tm_free_in?(v, cmp[1])
            bound = cmp[1]
          else
            scale = mk_lit(q_div(Q_NEG_ONE, slope.val), ty)
            bound = mk_apps(times, [scale, poly[1][0]])
          if cmp[0] == "="
            fixed = bound
          else
            bounds = slope.val[0] > 0 ? lower : upper
            if !bounds.any?(-> (other) tm_eq(other, bound))
              bounds.push(bound)
      # With no surviving coefficient the obligation is independent of x.
      if lower.size + upper.size == 0 && fixed == nil && symbolic.size == 0
        fixed = mk_lit(Q_ZERO, ty)
      facts = []
      known.each -> (th)
        # Root saturation already projected conjunctions and discharged guards.
        if comparison?(th.concl) || dest_unop(th.concl, "¬") != nil
          normalized = []
          normalize_comparisons(th, normalized, true)
          normalized.each -> (bound)
            rel = numeric_disequality?(bound.concl) ? bound.concl.b : bound.concl
            if ty_eq(type_of(rel.a.b), ty)
              begin
                nodes = [128]
                recurrence_ring_cost(rel.a.b, ty.name, nodes)
                recurrence_ring_cost(rel.b, ty.name, nodes)
                auto_add_fact(facts, bound)
              rescue e
                0
          if facts.size > 12
            return nil
      if fixed != nil
        return checked_interval_witness(goal, ex, fixed, facts)
      if symbolic.size > 0
        return interval_at_endpoint(goal, ex, lower, upper, symbolic, facts)
      interval_extremes(ty, lower, upper, facts, [16], -> (w, bounds) checked_interval_witness(goal, ex, w, bounds))
    rescue e
      nil

  # At an endpoint where every variable-slope inequality has a strict
  # margin, the library gives a positive radius for each. Intersect these
  # neighborhoods with the ordinary bounds before checking the witness.
  -> interval_at_endpoint(goal, ex, lower, upper, symbolic, facts)
    ty = ex.ty
    lemma = auto_loaded_rule("affine_step_radius." + ty.name)
    if lemma == nil
      return nil
    zero = mk_lit(Q_ZERO, ty)
    minus = @k.mk_const("-", ty_funs([ty, ty], ty))
    plus = @k.mk_const("+", ty_funs([ty, ty], ty))
    lt = @k.mk_const("<", ty_funs([ty, ty], ty_bool))
    fuel = [16]
    # Zero is also a useful center for bounds that only constrain the slope.
    candidates = (upper.map -> (b) [b, false]) + (lower.map -> (b) [b, true])
    if candidates.size == 0
      candidates.push([zero, true])
    candidates.each -> (candidate)
      if fuel[0] <= 0
        return nil
      anchor = candidate[0]
      right = candidate[1]
      lows = lower + []
      highs = upper + []
      if lower.size + upper.size == 0
        lows.push(anchor)
      bounds = facts + []
      rules = []
      begin
        symbolic.each -> (entry)
          sides = dest_cmp_rel(tm_instantiate(entry[0], anchor, 0))
          margin = mk_apps(minus, [sides[2], sides[1]])
          positive = interval_body_proof(goal, mk_apps(lt, [zero, margin]), facts)
          slope = right ? mk_apps(minus, [zero, entry[1]]) : entry[1]
          radius = @k.mp(@k.spec(margin, @k.spec(slope, lemma)), positive)
          pos = @k.conj1(radius)
          rules.push(@k.conj2(radius))
          bounds.push(pos)
          if right
            highs.push(mk_apps(plus, [anchor, pos.concl.b]))
          else
            lows.push(mk_apps(minus, [anchor, pos.concl.b]))
        verify = -> (w, known)
          delta = right ? mk_apps(minus, [w, anchor]) : mk_apps(minus, [anchor, w])
          positive = interval_body_proof(goal, mk_apps(lt, [zero, delta]), known)
          justified = known + []
          rules.each -> (rule)
            step = @k.mp(@k.spec(delta, rule), positive)
            within = interval_body_proof(goal, dest_binop(step.concl, "⇒")[0], known)
            justified.push(@k.mp(step, within))
          checked_interval_witness(goal, ex, w, justified)
        return interval_extremes(ty, lows, highs, bounds, fuel, verify)
      rescue e
        0
    nil

  -> interval_extremes(ty, lower, upper, facts, fuel, verify)
    if fuel[0] <= 0
      fail("interval witness: case limit")
    if lower.size > 1 || upper.size > 1
      maximum = lower.size > 1
      bounds = maximum ? lower : upper
      a = bounds[0]
      b = bounds[1]
      rest = arr_sub(bounds, 2, bounds.size - 2)
      order = auto_loaded_rule("le_total." + ty.name)
      if order == nil
        fail("interval witness: total order unavailable")
      total = @k.spec(b, @k.spec(a, order))
      cases = dest_binop(total.concl, "∨")
      branches = []
      [0, 1].each -> (side)
        greater = side == 0 ? b : a
        smaller = side == 0 ? a : b
        lows = maximum ? [greater] + rest : lower
        highs = maximum ? upper : [smaller] + rest
        branches.push(interval_extremes(ty, lows, highs, facts + [@k.assume(cases[side])], fuel, verify))
      return @k.disj_cases(total, branches[0], branches[1])
    plus = @k.mk_const("+", ty_funs([ty, ty], ty))
    if lower.size == 0
      w = mk_apps(plus, [upper[0], mk_lit(Q_NEG_ONE, ty)])
    elsif upper.size == 0
      w = mk_apps(plus, [lower[0], mk_lit(Q_ONE, ty)])
    else
      divide = @k.mk_const("/", ty_funs([ty, ty], ty))
      w = mk_apps(divide, [mk_apps(plus, [lower[0], upper[0]]), mk_lit([2, 1], ty)])
    fuel[0] -= 1
    verify.call(w, facts)

  -> checked_interval_witness(goal, ex, w, facts)
    body = tm_instantiate(ex.b, w, 0)
    @k.exists_intro(goal.concl, w, interval_body_proof(goal, body, facts))

  -> interval_body_proof(goal, body, facts)
    pair = dest_binop(body, "∧")
    if pair != nil
      return @k.conj(interval_body_proof(goal, pair[0], facts), interval_body_proof(goal, pair[1], facts))
    nodes = [128]
    ty = type_of(body.a.b).name
    recurrence_ring_cost(body.a.b, ty, nodes)
    recurrence_ring_cost(body.b, ty, nodes)
    linarith_proof(Goal.new(goal.fixes, [], body), facts)

  -> witness_components(term)
    pair = dest_binop(term, "∧")
    if pair == nil
      return [term]
    witness_components(pair[0]) + witness_components(pair[1])

  # Infer witnesses from actual evidence for a conjunct mentioning the binder.
  # All obligations for a candidate use that same substitution.
  -> witness_feedback(goal, hints)
    ex = dest_unop(goal.concl, "∃")
    if ex == nil || ex.tag != :lam || dest_binop(ex.b, "∧") == nil || !auto_small_term?(ex.b, [128])
      return nil
    facts = []
    goal.hyps.each -> (h) auto_add_fact(facts, @k.assume(h[1]))
    hints.each -> (th)
      if !th.tags.include?("sorry") && th.hyps.all?(-> (hyp) goal.hyps.any?(-> (h) tm_eq(h[1], hyp)))
        auto_add_fact(facts, th)
    i = 0
    while i < facts.size && i < 64
      th = facts[i]
      if dest_binop(th.concl, "∧") != nil
        auto_add_fact(facts, @k.conj1(th))
        auto_add_fact(facts, @k.conj2(th))
      i += 1
    v = auto_fresh(goal, facts, [], ex.ty)
    leaves = witness_components(ex.b)
    if ex.ty == TY_RAT_SINGLETON || ex.ty == TY_REAL_SINGLETON
      note = interval_gap_feedback(goal, ex, v, leaves, facts, hints)
      if note != nil
        return note
    flexible = {}
    flexible[v.vkey] = true
    seen = {}
    best = nil
    bounds = facts.select -> (th) comparison?(th.concl)
    fuel = [8]
    leaves.each -> (part)
      if occurs_bnd(part, 0)
        pattern = tm_instantiate(part, v, 0)
        i = 0
        while i < facts.size && seen.size < 12
          th = facts[i]
          i += 1
          mt = Matcher.new(flexible, {})
          if mt.m(pattern, th.concl, 0)
            w = mt.tm[v.vkey]
            if w != nil && auto_small_term?(w, [64]) && tm_set_add?(seen, w)
              progress = witness_conditions(leaves, w, facts, bounds, fuel)
              if progress != nil && (best == nil || progress[0] < best[0])
                best = progress
                if best[0] == 1
                  return checked_progress_note(best[1], best[2], tm_show(w))
    best == nil ? nil : checked_progress_note(best[1], best[2], tm_show(best[3]))

  # A weak comparison suggests a repair only if every witness forces the
  # strict comparison and adding the disequality proves the original goal.
  -> interval_gap_feedback(goal, ex, v, leaves, facts, hints)
    if leaves.size > 6 || facts.size > 16
      return nil
    nodes = [512]
    if !facts.all?(-> (th) auto_small_term?(th.concl, nodes))
      return nil
    lower = []
    upper = []
    strict = false
    ty = ex.ty
    le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
    nodes = [128]
    begin
      leaves.each -> (part)
        cmp = dest_cmp_rel(part)
        if cmp == nil || !ty_eq(type_of(cmp[1]), ty)
          return nil
        recurrence_ring_cost(cmp[1], ty.name, nodes)
        recurrence_ring_cost(cmp[2], ty.name, nodes)
        strict = strict || cmp[0] == "<"
        if occurs_bnd(part, 0)
          if !occurs_bnd(cmp[1], 0)
            lower.push(cmp[1])
          if !occurs_bnd(cmp[2], 0)
            upper.push(cmp[2])
        elsif cmp[0] == "<"
          # A binder-independent strict side condition can be the only gap.
          lower.push(cmp[1])
          upper.push(cmp[2])
      if !strict
        return nil
      candidates = []
      lower.each -> (a)
        upper.each -> (b) candidates.push(mk_apps(le, [a, b]))
      # The context can supply a more natural spelling after rescaling,
      # e.g. 2*a ≤ 3*b for a < 3*x and 2*x < b.
      facts.each -> (th)
        if dest_binop(th.concl, "≤") != nil && ty_eq(type_of(th.concl.a.b), ty)
          candidates.push(th.concl)
      body = @k.assume(tm_instantiate(ex.b, v, 0))
      seen = {}
      trials = [3]
      candidates.each -> (weak)
        if seen.size >= 10 || trials[0] == 0
          return nil
        sides = dest_binop(weak, "≤")
        if !tm_eq(sides[0], sides[1]) && tm_set_add?(seen, weak)
          note = checked_interval_gap(goal, hints, v, body, weak, trials)
          if note != nil
            return note
    rescue e
      return nil
    nil

  -> checked_interval_gap(goal, hints, v, body, weak, trials)
    sides = dest_binop(weak, "≤")
    lt = @k.mk_const("<", type_of(weak.a.a))
    begin
      required = interval_body_proof(goal, mk_apps(lt, sides), [body])
      if !hyps_has?(required.hyps, body.concl)
        return nil
      necessary = @k.choose(v, @k.assume(goal.concl), required)
      trials[0] -= 1
      bound = feedback_proof(goal.with_concl(weak), hints)
      if bound == nil || bound.tags.include?("sorry")
        return nil
      equal = @k.eq_tm(sides[0], sides[1])
      missing = @k.neg_tm(equal)
      if feedback_proof(goal.with_concl(equal), hints) != nil || feedback_proof(goal.with_concl(missing), hints) != nil
        return nil
      repair = feedback_proof(goal.add_hyp("interval_gap", missing), hints)
      if repair == nil || !hyps_has?(repair.hyps, missing)
        return nil
      checked_progress_note(bound, missing, nil, [necessary, @k.disch(missing, repair)])
    rescue e
      nil

  -> witness_conditions(parts, w, facts, bounds, fuel)
    known = nil
    missing = nil
    count = 0
    supported = false
    seen = {}
    parts.reverse.each -> (part)
      leaf = tm_instantiate(part, w, 0)
      proof = nil
      neg = dest_unop(leaf, "¬")
      if neg == nil
        neg = @k.neg_tm(leaf)
      facts.each -> (th)
        if tm_eq(th.concl, neg)
          return nil
        if proof == nil && tm_eq(th.concl, leaf)
          proof = th
      if proof != nil && occurs_bnd(part, 0)
        supported = true
      if !tm_set_add?(seen, leaf)
        next
      if proof == nil
        if witness_trivial(neg) != nil
          return nil
        proof = witness_trivial(leaf)
      comparison = leaf.tag == :app && leaf.a.op == OP_NOT ? leaf.b : leaf
      if proof == nil && comparison?(comparison)
        if fuel[0] == 0
          return nil
        fuel[0] -= 1
        proof = witness_comparison(comparison, bounds)
        if proof != nil && !tm_eq(proof.concl, leaf)
          return nil
      if proof == nil
        if leaf.op == OP_FALSE
          return nil
        missing = missing == nil ? leaf : @k.bin("∧", leaf, missing)
        count += 1
      else
        known = known == nil ? proof : @k.conj(proof, known)
    if !supported || missing == nil || known.tags.include?("sorry")
      return nil
    [count, known, missing, w]

  -> witness_trivial(term)
    if term.op == OP_TRUE
      return @k.truth
    sides = @k.dest_eq(term)
    if sides != nil && tm_eq(sides[0], sides[1])
      return @k.refl(sides[0])
    nil

  # Return a checked bound or its negation when small linear facts settle it.
  -> witness_comparison(leaf, bounds)
    goal = Goal.new([], [], leaf)
    begin
      cmp = dest_cmp_rel(leaf)
      ty = type_of(cmp[1]).name
      nodes = [64]
      recurrence_ring_cost(cmp[1], ty, nodes)
      recurrence_ring_cost(cmp[2], ty, nodes)
      relevant = auto_relevant_comparisons(goal, bounds)
      if relevant.size > 8
        return nil
      worker = Prover.new(@session)
      begin
        return worker.linarith_proof(goal, relevant)
      rescue e
        return worker.linarith_proof(goal.with_concl(@k.neg_tm(leaf)), relevant)
    rescue e
      nil

  # Computing an open finite sum at a literal bound can construct a large
  # symbolic term. Try unconditional indexed identities before rfl and decide.
  -> auto_literal_sum?(term)
    if term.cl
      return false
    sum = dest_binop(term, "sum_below")
    sum != nil && sum[0].tag == :lit && sum[0].val >= 16

  -> auto_sum_identity(goal)
    rules = auto_default_hints(goal).select -> (rule)
      body = rule.concl
      binder = dest_unop(body, "∀")
      while binder != nil && binder.tag == :lam
        body = binder.b
        binder = dest_unop(body, "∀")
      dest_binop(body, "=") != nil
    auto_hint_proof(goal, rules, [], [12, 0], [])

  -> tac_auto(g, depth, hints, budget, seen)
    if depth <= 0
      fail("auto: depth exhausted")
    th = find_assumption(g.goal)
    if th != nil
      return close(g, th)
    if dest_binop(g.goal.concl, "all") != nil
      th = auto_list_evidence(g.goal, hints)
      if th != nil
        return close(g, th)
    if seen.empty?() && @session.theorems["darboux.add_monomial"] != nil
      integral = auto_polynomial_integral(g.goal, hints)
      if integral != nil
        return close(g, fit(g, integral))
    sides = @k.dest_eq(g.goal.concl)
    if sides != nil && !tm_eq(sides[0], sides[1])
      if seen.empty?() && (g.goal.concl.search_ops & TERM_FINITE_SUM) != 0
        summed = auto_sum_ring(sides[0], sides[1])
        if summed != nil
          return close(g, summed)
      if auto_literal_sum?(sides[0]) || auto_literal_sum?(sides[1])
        identity = auto_sum_identity(g.goal)
        if identity != nil
          return close(g, fit(g, identity))
      record = @session.elab.record_layout(type_of(sides[0]))
      if record != nil
        th = record_evidence(g.goal, sides, record, hints)
        if th != nil
          return close(g, th)
    if dest_unop(g.goal.concl, "∀") != nil && g.goal.hyps.size + hints.size <= 12
      facts = hints.select(-> (th) dest_unop(th.concl, "∀") != nil)
      g.goal.hyps.each -> (h)
        if dest_unop(h[1], "∀") != nil
          facts.push(@k.assume(h[1]))
      if !facts.empty?()
        facts.each -> (fact)
          path = pointwise_conjunct_path(fact.concl, g.goal.concl, [32])
          if path != nil
            return close(g, prove_pointwise_conjunct(fact, path, 0))
        th = auto_pointwise_comparison(g.goal, facts)
        if th != nil
          return close(g, fit(g, th))
    if (g.goal.concl.search_ops & TERM_LAMBDA) != 0
      sides = @k.dest_eq(g.goal.concl)
      if sides != nil && auto_small_term?(g.goal.concl, [384])
        th = ring_congruence(sides[0], sides[1], [128], false)
        if th != nil
          return close(g, th)
    # Discharge registered guards already in scope before enumerating their
    # quantified instances. A miss leaves the ordinary search fuel intact.
    if seen.size == 0 && @session.auto_rules.size > 0 && g.goal.hyps.any?(-> (h) dest_unop(h[1], "∀") != nil)
      th = auto_registered_arithmetic(g.goal, hints, [2, 0], seen, true)
      if th != nil
        return close(g, fit(g, th))
    th = auto_polynomial_sign(g.goal, hints)
    if th != nil
      return close(g, th)
    # A rule guard can already be a sum of squares after normalization.
    # Try a linear certificate from the guard's own squares before using
    # the shared nonlinear search budget on its surrounding hypotheses.
    if !seen.empty?() && (g.goal.concl.search_ops & (TERM_POWER | TERM_SQUARE_PRODUCT)) != 0
      th = auto_square_arithmetic(g.goal, budget, [])
      if th != nil
        return close(g, th)
    th = auto_forward(g.goal)
    if th != nil
      return close(g, th)
    c = g.goal.concl
    binder = dest_unop(c, "∃")
    if seen.size == 0 && binder != nil && binder.tag == :lam && auto_small_term?(binder.b, [192])
      begin
        th = PolynomialSign.new(self).existential(g.goal, binder)
        if th != nil
          return close(g, th)
      rescue unsupported_polynomial
        0
    # Introducing a negation loses the predicate head that selects negative
    # lemmas. Try matching those conclusions before changing the goal to False.
    if c.tag == :app && c.a.op == OP_NOT && seen.empty?() && (!hints.empty?() || !@session.auto_rules.empty?())
      candidates = hints + auto_registered_hints(g.goal)
      negative = candidates.select -> (rule) dest_unop(auto_rule_conclusion(rule.concl), "¬") != nil
      proof = auto_hint_proof(g.goal, negative, hints, [8, 1], seen)
      if proof != nil
        return close(g, fit(g, proof))
    if intro_able?(c)
      ng = tac_intro(g, [], true)
      return tac_auto(ng, depth, hints, budget, seen)
    if seen.size == 0
      relation = auto_list_relation(g.goal, hints, budget)
      if relation != nil
        return close(g, fit(g, relation))
      invariant = auto_fold_invariant(g.goal, hints, budget)
      if invariant != nil
        return close(g, fit(g, invariant))
      finite = auto_finite_cases(g.goal, hints, budget)
      if finite != nil
        return close(g, fit(g, finite))
      # Normalize a supplied arithmetic formula once before splitting its
      # conclusions, so the branches share the original nonlinear fuel.
      if hints.size > 0
        trial = [budget[0], budget[1]]
        rewritten = auto_defined_arithmetic(g.goal, hints, trial, true)
        if rewritten != nil
          budget[0] = trial[0]
          budget[1] = trial[1]
          return close(g, fit(g, rewritten))
        # A failed bounded normalization trial must not starve the ordinary
        # proof path, which may need the original spelling of a supplied fact.
        if trial[0] < budget[0]
          budget[0] -= 1
    pq = dest_binop(c, "∧")
    if pq != nil || (dest_binop(c, "=") != nil && type_of(dest_binop(c, "=")[0]).name == "bool")
      refs = tac_constructor(g)
      refs.each -> (r)
        # Each conjunct is a disjoint subtree of the stated goal. Reserve
        # search depth for choices; an equivalence still costs a level.
        tac_auto(r, pq != nil ? depth : depth - 1, hints, budget, seen)
      return 0
    attempts = [:rfl, :decide, :simp, :linarith, :contradiction]
    attempts.each -> (a)
      begin
        case a
        when :rfl
          return tac_rfl(g)
        when :decide
          return tac_decide(g)
        when :simp
          saved = @goals
          r = tac_simp(g, [], true)
          if @goals.size < saved.size
            return r
          if r.size == 1 && r[0] != g && comparison?(r[0].goal.concl)
            begin
              return close(r[0], linarith_proof(r[0].goal, hints))
            rescue e
              0
          @goals = saved
        when :linarith
          return tac_linarith(g, [], false)
        when :contradiction
          return tac_contradiction(g)
      rescue e
        0
    alternatives = dest_binop(g.goal.concl, "∨")
    if alternatives != nil
      cases = auto_polynomial_cases(g.goal, alternatives, hints)
      if cases != nil
        return close(g, fit(g, cases))
    equality = @k.dest_eq(g.goal.concl)
    if equality != nil
      polynomial = auto_polynomial_equation(g.goal, equality, hints)
      if polynomial != nil
        return close(g, polynomial)
    if equality != nil && equality[0].tag == :app && equality[1].tag == :app && tm_eq(strip_app(equality[0])[0], strip_app(equality[1])[0])
      congruent = auto_argument_equal(equality[0], equality[1], (g.goal.hyps.map -> (h) @k.assume(h[1])) + hints, 16, [8])
      if congruent != nil
        return close(g, fit(g, congruent))
    arithmetic = auto_arithmetic_forward(g.goal, [], seen.size > 0 ? budget : nil)
    if arithmetic != nil
      return close(g, fit(g, arithmetic))
    # In arithmetic side conditions, use supplied facts before chasing another
    # backwards rule (which may restate the parent bound through an alias).
    hint_arithmetic = seen.size > 0 && hints.size > 0 && comparison?(g.goal.concl)
    if hint_arithmetic
      arithmetic = auto_arithmetic_forward(g.goal, hints, budget)
      if arithmetic != nil
        return close(g, fit(g, arithmetic))
    natural = auto_natural_arithmetic(g.goal, budget)
    if natural != nil
      return close(g, fit(g, natural))
    hinted = auto_hint_proof(g.goal, hints + auto_local_hints(g.goal) + auto_default_hints(g.goal), hints, budget, seen)
    if hinted != nil
      return close(g, fit(g, hinted))
    if seen.size == 0 && (g.goal.concl.search_ops & TERM_DIVMOD) != 0
      divided = auto_division_cases(g.goal, hints)
      if divided != nil
        return close(g, fit(g, divided))
    if hints.size > 0
      forwarded = comparison?(g.goal.concl) ? nil : auto_forward(g.goal, hints)
      if forwarded != nil
        return close(g, fit(g, forwarded))
      if !hint_arithmetic
        arithmetic = auto_arithmetic_forward(g.goal, hints, seen.size > 0 ? budget : nil)
        if arithmetic != nil
          return close(g, fit(g, arithmetic))
    # Keep direct small product/sign arguments terse as well as rule premises.
    # This uses the same four-attempt nonlinear budget and degree/node limits.
    nonlinear_facts = nil
    if hints.size > 0
      nonlinear_facts = (g.goal.hyps.map -> (h) @k.assume(h[1])) + hints
    nonlinear = auto_nonlinear_premise(g.goal, budget, nonlinear_facts)
    if nonlinear != nil
      return close(g, fit(g, nonlinear))
    squared = auto_square_bound_chain(g.goal, hints, budget)
    if squared != nil
      return close(g, fit(g, squared))
    chained = auto_bound_chain(g.goal, hints, budget, seen)
    if chained != nil
      return close(g, fit(g, chained))
    pq = dest_binop(c, "∨")
    if pq != nil
      trial = [budget[0], budget[1]]
      cases = auto_arithmetic_disjunction(g.goal, depth, hints, trial, seen)
      if cases != nil
        budget[0] = trial[0]
        budget[1] = trial[1]
        return close(g, fit(g, cases))
      if trial[0] < budget[0]
        budget[0] -= 1
      begin
        saved = @goals
        refs = tac_left_right(g, true)
        tac_auto(refs[0], depth - 1, hints, budget, seen)
        return 0
      rescue e
        @goals = saved
      begin
        refs = tac_left_right(g, false)
        tac_auto(refs[0], depth - 1, hints, budget, seen)
        return 0
      rescue e
        @goals = saved
    if seen.size == 0
      arithmetic = cast_arithmetic_proof(g.goal, hints)
      if arithmetic == nil
        arithmetic = auto_subterm_arithmetic(g.goal, hints)
      if arithmetic == nil
        arithmetic = auto_sum_arithmetic(g.goal, hints)
      if arithmetic == nil
        arithmetic = auto_field_arithmetic(g.goal, hints)
      if arithmetic != nil
        return close(g, fit(g, arithmetic))
      # Try a proved equality rule in the other orientation once at the root.
      # Share the existing fuel and remember both goals when solving premises.
      equality = @k.dest_eq(g.goal.concl)
      if equality != nil && type_of(equality[0]).name != "bool"
        power = auto_power_step(g.goal, hints)
        if power != nil
          return close(g, fit(g, power))
        reversed = g.goal.with_concl(@k.eq_tm(equality[1], equality[0]))
        candidates = hints + auto_local_hints(reversed) + auto_default_hints(reversed)
        proof = auto_hint_proof(reversed, candidates, hints, budget, seen + [g.goal.concl])
        if proof != nil
          return close(g, fit(g, @k.sym(proof)))
      aliased = auto_sum_alias_proof(g.goal, hints, budget)
      if aliased != nil
        return close(g, fit(g, aliased))
      polynomial = auto_polynomial_recurrence(g.goal, hints, budget)
      if polynomial != nil
        return close(g, fit(g, polynomial))
      geometric = auto_geometric_equality(g.goal, hints, budget)
      if geometric != nil
        return close(g, fit(g, geometric))
      identity = auto_recurrence_identity(g.goal, hints, budget)
      if identity != nil
        return close(g, fit(g, identity))
      family = auto_recurrence_family(g.goal, hints, budget)
      if family != nil
        return close(g, fit(g, family))
      list_identity = auto_recurrence_identity(g.goal, hints, budget, "list")
      if list_identity != nil
        return close(g, fit(g, list_identity))
      list_bound = auto_list_bound(g.goal, hints, budget)
      if list_bound != nil
        return close(g, fit(g, list_bound))
      defined = auto_defined_arithmetic(g.goal, hints, budget)
      if defined != nil
        return close(g, fit(g, defined))
      # Keep all established paths first: an unsuccessful square trial must
      # not spend the nonlinear fuel needed by induction or rule premises.
      # These are linear certificates with proved squares, not nonlinear
      # product searches. Give the final fallback two shared attempts of its own.
      square_budget = [2]
      squared = auto_square_arithmetic(g.goal, square_budget)
      if squared != nil
        return close(g, fit(g, squared))
      supplied = hints + []
      g.goal.hyps.each -> (hyp)
        if dest_unop(hyp[1], "∀") != nil
          auto_add_fact(supplied, @k.assume(hyp[1]))
      if supplied.size > 0 && supplied.size <= 8
        arithmetic = auto_arithmetic_forward(g.goal, supplied, square_budget, true)
        if arithmetic != nil
          return close(g, fit(g, arithmetic))
    if @registered_search
      proof = auto_hint_proof(g.goal, auto_registered_hints(g.goal), hints, budget, seen)
      if proof == nil
        proof = auto_registered_arithmetic(g.goal, hints, budget, seen)
      if proof != nil
        return close(g, fit(g, proof))
    elsif seen.size == 0 && @session.auto_rules.size > 0
      # A separate late search leaves all established paths and their fuel
      # intact. Rule premises share these bounds and the ordinary cycle checks.
      worker = Prover.new(@session, application_conversions)
      worker.registered_search = true
      registered_budget = [24, 4]
      proof = worker.auto_hint_proof(g.goal, worker.auto_registered_hints(g.goal), hints, registered_budget, [])
      if proof == nil
        proof = worker.auto_registered_arithmetic(g.goal, hints, registered_budget)
      if proof != nil
        return close(g, fit(g, proof))
    if seen.size == 0
      proof = auto_quantified_bound(g.goal, hints)
      if proof != nil
        return close(g, fit(g, proof))
      proof = auto_binary_form(g.goal, hints)
      if proof != nil
        return close(g, fit(g, proof))
      proof = auto_interval_cases(g.goal, hints)
      if proof != nil
        return close(g, fit(g, proof))
      proof = @session.exact_premise(g.goal.concl)
      if proof != nil
        return close(g, proof)
      proof = auto_hint_proof(g.goal, @session.selected_premises(g.goal), hints, [16, 2], [])
      if proof != nil
        return close(g, fit(g, proof))
      proof = auto_predicate_transfer(g.goal, hints)
      if proof != nil
        return close(g, fit(g, proof))
    fail("auto failed")

  -> tac_specialize(g, args)
    goal = g.goal
    e = parse_expr_toks(args)
    sp = @session.elab.ast_spine(e)
    hn = sp[0].s
    th = proof_ast(goal, e, nil)
    old = goal.hyp(hn)
    ng = goal.without_hyp(hn).add_hyp(hn, th.concl)
    refine(g, [ng], ->(ts) @d.prove_hyp(th, ts[0]))

  -> tac_symm(g)
    goal = g.goal
    e = dest_binop(goal.concl, "=")
    if e == nil
      fail("symm: not an equation")
    ng = goal.with_concl(@k.eq_tm(e[1], e[0]))
    refine(g, [ng], ->(ts) @k.sym(ts[0]))

  # Prove that rebuilding a record from its fields gives back the record.
  # Constructor computation closes the single case of structural induction.
  -> record_eta(ty, ctor, projections, types)
    v = mk_var("record", ty)
    rebuilt = mk_apps(ctor, projections.map -> (p) mk_app(p, v))
    predicate = mk_lam(v, @k.eq_tm(rebuilt, v))
    induction = @k.inst_type(@k.axiom(ty.name + "_induct"), types)
    step = @d.beta_norm_thm(@k.spec(predicate, induction))
    args = []
    projections.each_with_index -> (p, i) args.push(mk_var("field" + i.to_s, type_of(p).cod))
    value = mk_apps(ctor, args)
    base = @session.eq_by_compute(mk_apps(ctor, projections.map -> (p) mk_app(p, value)), value)
    @k.mp(step, @d.gen_all(args, base))

  # One subgoal per field in declaration order, and its kernel justification.
  -> record_equation(sides, record)
    ty = type_of(sides[0])
    info = @k.inductives[ty.name]
    types = {}
    info.params.each_with_index -> (param, i) types[param] = ty.args[i]
    ctor = @k.mk_const(record[0], ty_subst(@k.const_type(record[0]), types))
    projections = record[1].map -> (name) @k.mk_const(name, ty_subst(@k.const_type(name), types))
    spines = sides.map -> (term) strip_app(term)
    values = spines.map_with_index -> (spine, i)
      if tm_eq(spine[0], ctor)
        spine[1]
      else
        projections.map -> (p) mk_app(p, sides[i])
    fields = projections.map_with_index -> (p, i) @k.eq_tm(values[0][i], values[1][i])
    just = -> (ts)
      middle = @k.refl(ctor)
      ts.each -> (th) middle = @k.mk_comb(middle, th)
      if !tm_eq(spines[0][0], ctor) || !tm_eq(spines[1][0], ctor)
        eta = record_eta(ty, ctor, projections, types)
        if !tm_eq(spines[0][0], ctor)
          middle = @k.trans(@k.sym(@k.spec(sides[0], eta)), middle)
        if !tm_eq(spines[1][0], ctor)
          middle = @k.trans(middle, @k.spec(sides[1], eta))
      middle
    return [fields, just]

  # The equality graph is shared across nested records. A diagnostic can
  # assume one missing leaf, discharged in the resulting conditional proof.
  -> record_evidence(goal, sides, record, hints, report = false)
    begin
      facts = hints + (goal.hyps.map -> (h) @k.assume(h[1]))
      gap = report ? [nil, nil] : nil
      proof = record_field_proof(sides, record, facts, auto_equality_graph(facts), [32], gap)
      if !report || proof == nil
        return proof
      if gap[0] == nil || gap[1] == nil || facts.any?(-> (fact) tm_eq(fact.concl, @k.neg_tm(gap[1])))
        return nil
      conditional = @k.disch(gap[1], proof)
      checked_progress_note(gap[0], gap[1], nil, [conditional])
    rescue unsupported_layout
      nil

  -> record_field_proof(sides, record, facts, graph, fuel, gap)
    if fuel[0] <= 0
      return nil
    fuel[0] -= 1
    parts = record_equation(sides, record)
    proofs = []
    parts[0].each -> (field)
      ab = @k.dest_eq(field)
      proof = auto_equal(ab[0], ab[1], facts, 3, graph)
      if proof != nil
        if gap != nil && gap[0] == nil && !tm_eq(ab[0], ab[1])
          gap[0] = proof
      else
        nested = @session.elab.record_layout(type_of(ab[0]))
        if nested != nil
          proof = record_field_proof(ab, nested, facts, graph, fuel, gap)
        elsif gap != nil && (gap[1] == nil || tm_eq(gap[1], field))
          gap[1] = field
          proof = @k.assume(field)
        if proof == nil
          return nil
      proofs.push(proof)
    parts[1].call(proofs)

  -> tac_funext(g, args)
    goal = g.goal
    e = dest_binop(goal.concl, "=")
    if e == nil || !type_of(e[0]).fun?
      fail("funext: goal is not an equation of functions")
    nm = "x"
    if args.size > 0
      nm = args[0].text
    ft = type_of(e[0])
    v = mk_var(fresh_name(nm, goal.all_terms), ft.dom)
    lhs = e[0]
    rhs = e[1]
    ng = Goal.new(goal.fixes + [[nm, v]], goal.hyps, @k.eq_tm(@d.beta_norm_term(mk_app(lhs, v)), @d.beta_norm_term(mk_app(rhs, v))))
    refine(g, [ng], ->(ts) funext_proof(lhs, rhs, v, ts[0]))

  -> funext_proof(lhs, rhs, v, pointwise)
    at_v = fit_concl(pointwise, @k.eq_tm(mk_app(lhs, v), mk_app(rhs, v)))
    lifted = @k.abs_rule(v, at_v)
    @k.trans(@k.sym(eta_side(lhs, v)), @k.trans(lifted, eta_side(rhs, v)))

  # ⊢ (λv. f v) = f
  -> eta_side(f, v)
    lam = mk_lam(v, mk_app(f, v))
    @k.eta(lam)

  -> tac_revert(g, args)
    goal = g.goal
    hn = args[0].text
    p = goal.hyp(hn)
    if p == nil
      fail("revert: no hypothesis " + hn)
    ng = goal.without_hyp(hn).with_concl(@k.bin("⇒", p, goal.concl))
    refine(g, [ng], ->(ts) @k.mp(ts[0], @k.assume(p)))

  # calc a = b := proof \n _ = c := proof ...
  -> tac_calc(g, args, block)
    goal = g.goal
    steps = []
    if args.size > 0
      steps.push(args)
    block.each -> (b)
      steps.push(b.toks)
    acc = nil
    prev_rhs = nil
    steps.each -> (st)
      k = find_top(st, ":=", 0)
      if k < 0
        fail("calc: each step needs ':= proof'")
      rel_toks = arr_sub(st, 0, k)
      if rel_toks[0].text == "_" && prev_rhs != nil
        rel_toks = arr_sub(rel_toks, 1, rel_toks.size - 1)
        e = parse_expr_toks([Tok.new(:id, "_calc_prev_", 0, 0)] + rel_toks)
        rel = calc_elab(goal, e, prev_rhs)
      else
        rel = elab_term(goal, rel_toks, ty_bool)
      ptoks = arr_sub(st, k + 1, st.size - k - 1)
      th = nil
      if ptoks.size > 0 && ptoks[0].text == "by"
        th = run_subproof(goal, rel, by_nodes(arr_sub(ptoks, 1, ptoks.size - 1), [], 0))
      else
        th = fit_concl(proof_expr(goal, ptoks, rel), rel)
      if acc == nil
        acc = th
      else
        acc = calc_trans(acc, th)
      prev_rhs = calc_rhs(rel)
    close(g, fit(g, acc))

  -> calc_elab(goal, e, prev)
    fx = goal.fixes + [["_calc_prev_", prev]]
    @session.elab.elab_in(e, fx, ty_bool)

  -> calc_rhs(rel)
    ["=", "<", "≤"].each -> (r)
      d = dest_binop(rel, r)
      if d != nil
        return d[1]
    fail("calc: steps must be =, < or ≤")

  -> calc_rel(t)
    ["=", "<", "≤"].each -> (r)
      d = dest_binop(t, r)
      if d != nil
        return [r, d]
    nil

  -> calc_trans(a, b)
    ra = calc_rel(a.concl)
    rb = calc_rel(b.concl)
    if ra[0] == "="
      # rewrite left side of b
      eq = @k.sym(a)
      head = strip_app(b.concl)[0]
      cong = @k.mk_comb(@d.ap_term(head, eq), @k.refl(rb[1][1]))
      return @k.eq_mp(cong, b)
    if rb[0] == "="
      head = strip_app(a.concl)[0]
      cong = @k.mk_comb(@k.refl(mk_app(head, ra[1][0])), b)
      return @k.eq_mp(cong, a)
    ty = type_of(ra[1][0])
    nm = "le_trans"
    if ra[0] == "<" && rb[0] == "<"
      nm = "lt_trans"
    elsif ra[0] == "<"
      nm = "lt_of_lt_of_le"
    elsif rb[0] == "<"
      nm = "lt_of_le_of_lt"
    l = @session.lemma_at(nm, ty)
    if l == nil
      fail("calc: missing lemma " + nm)
    l = @k.spec(rb[1][1], @k.spec(ra[1][1], @k.spec(ra[1][0], l)))
    @k.mp(@k.mp(l, a), b)

# The term when it mentions no pattern variable, else nil.
-> closed_or_nil(t, pvars)
  tm_frees(t).each -> (v)
    if pvars.has_key?(var_key(v))
      return nil
  t

+ Prover
  # Expand bounded quantifiers over the hypotheses-to-goal implication into a
  # propositional formula, then refute its negation with a checked LRAT proof.
  -> tac_sat_prop(g)
    goal = g.goal
    big = goal.concl
    i = goal.hyps.size - 1
    while i >= 0
      big = @k.bin("⇒", goal.hyps[i][1], big)
      i -= 1
    ev = @k.compute(big, false, true)
    psi = dest_binop(ev.concl, "=")[1]
    th = nil
    if is_const?(psi, "⊤")
      th = @d.eqt_elim(ev)
    else
      negpsi = @k.neg_tm(psi)
      cls = tseitin_refutation_cnf(negpsi)
      lrat = sat_solve_lrat(@session, cls)
      nn = @k.prop_refute(negpsi, lrat)
      psi_th = classical_by_contra(psi, @k.not_elim(nn, @k.assume(negpsi)))
      th = @k.eq_mp(@k.sym(ev), psi_th)
    goal.hyps.each -> (h)
      th = @k.mp(th, @k.assume(h[1]))
    close(g, th)
