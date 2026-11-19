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

+ Prover
  ro :k, :d, :session
  rw :goals, :sum_aliases_allowed, :registered_search, :auto_rule_path

  -> new(@session)
    @k = @session.k
    @d = @session.d
    @goals = []
    @auto_rule_path = []
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

  -> fresh_hyp_name
    @hcount += 1
    "h" + @hcount.to_s

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

  # Checked conversion through definitions and repeated-product notation.
  -> try_defeq(th, target)
    begin
      a = @d.beta_eta_conv(th.concl)
      b = @d.beta_eta_conv(target)
      a = @k.trans(a, @k.compute(dest_binop(a.concl, "=")[1]))
      b = @k.trans(b, @k.compute(dest_binop(b.concl, "=")[1]))
      # Unfolding a function alias can expose further beta/eta reductions.
      a = @k.trans(a, @d.beta_eta_conv(dest_binop(a.concl, "=")[1]))
      b = @k.trans(b, @d.beta_eta_conv(dest_binop(b.concl, "=")[1]))
      va = dest_binop(a.concl, "=")[1]
      vb = dest_binop(b.concl, "=")[1]
      if !tm_eq(va, vb)
        # Aliases can occur inside quantified goals as well as at the head.
        a = @k.trans(a, @d.compute_conv(va))
        b = @k.trans(b, @d.compute_conv(vb))
        a = @k.trans(a, @d.beta_eta_conv(dest_binop(a.concl, "=")[1]))
        b = @k.trans(b, @d.beta_eta_conv(dest_binop(b.concl, "=")[1]))
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
    # t1 <;> t2 : run t2 on every goal t1 produces (left-associative)
    k = find_top_last(toks, "<;>")
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
    when "show"
      tac_show(g, args)
    when "obtain", "rcases"
      tac_obtain(g, args)
    when "cases"
      tac_cases(g, args)
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
      begin
        tac_auto(g, 3, hints, [24, 4], [])
      rescue e
        if e.to_s == "auto failed" && @goals.size > 0
          goal = first_goal.goal
          note = strict_bound_feedback(goal, hints)
          if note == nil
            begin
              note = witness_feedback(goal, hints)
              if note == nil
                note = hint_feedback(goal, hints)
            rescue diagnostic_error
              note = nil
          if note
            fail("auto failed\n" + note)
        raise e
    when "specialize"
      tac_specialize(g, args)
    when "symm"
      tac_symm(g)
    when "calc"
      tac_calc(g, args, block)
    when "funext", "ext"
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
    # projections h.1 h.2 h.mp h.mpr h.symm
    if name.include?(".")
      parts = name.split(".")
      base = lookup_proof(goal, arr_sub(parts, 0, parts.size - 1).join("."))
      if base != nil
        return project_proof(base, parts[parts.size - 1])
    nil

  -> project_proof(th, field)
    # A supplied predicate can expose a connective only after beta reduction.
    th = @d.beta_norm_thm(th)
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

  -> proof_name?(goal, e)
    if e.kind == :proj || e.kind == :anon || e.kind == :by
      return true
    if e.kind == :id
      if e.s == "rfl" || e.s == "trivial"
        return true
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
      # `(thm a b).mpr h`: any other head is itself a proof expression
      if head.kind == :proj || head.kind == :paren || head.kind == :app
        r = instantiate_to(goal, proof_ast(goal, head, nil), sp[1], expected, false)
        return r[0]
    if e.kind == :anon
      if expected == nil
        fail("⟨...⟩ needs a known goal")
      return anon_proof(goal, e.kids, expected)
    if e.kind == :app && e.kids[0].kind == :id && e.kids[0].s == "by"
      fail("nested by")
    fail("cannot read proof expression")

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
      return @k.deduct_antisym(@d.undisch(a), @d.undisch(b))
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

  # Instantiate theorem th with explicit args; match its conclusion against
  # `target` (if given). Returns [thm, remaining premise props].
  # With allow_open, unproved premises are returned instead of failing.
  -> instantiate_to(goal, th, args, target, allow_open)
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
    ai = 0
    si = 0
    # ∀-steps filled out of order: Satori hoists every ∀ binder to the front of a statement, so in
    # `thm L a ha u hu` (declared (L a) (ha) (u) (hu)) the term u arrives while the next step is the premise of ha's kind
    filled = {}
    maxused = -1
    while ai < args.size
      a = args[ai]
      isproof = proof_name?(goal, a)
      while si < steps.size && (filled.has_key?(si) || (steps[si][0] == :all && isproof))
        si += 1
      tstep = si
      if !isproof
        # the earliest ∀ binder still unbound (earlier ones may have been skipped by a proof argument)
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
          return instantiate_to(goal, resumed, arr_sub(args, ai, args.size - ai), target, allow_open)
        fail("too many arguments")
      if steps[tstep][0] == :all
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
        if si > maxused
          maxused = si
        prem = steps[si][1]
        prem_i = closed_or_nil(tm_subst(prem, mt.tm), pvars)
        if prem_i != nil
          prem_i = tm_inst_types(prem_i, mt.ty)
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
      # use the shortest telescope prefix whose remainder matches the target
      found = -1
      j = si
      while j <= steps.size && found < 0
        trial = match_application(mt, curs[j], target)
        if trial != nil
          found = j
          mt = trial
        j += 1
      if found < 0 && args.size > 0
        # Expose a supplied predicate's telescope before definitional fitting
        # can erase a premise such as True. `apply` still opens that premise.
        prefix = instantiate_to(goal, th, args, nil, false)
        resumed = @d.beta_norm_thm(prefix[0])
        if !tm_eq(resumed.concl, th.concl)
          return instantiate_to(goal, resumed, [], target, allow_open)
      if found < 0
        # Preserve ordinary premise matching before trying aliases: computing
        # a whole implication can otherwise erase a trivially true premise.
        j = si
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
    # build the theorem
    thx = t
    if mt.ty.size > 0
      thx = k.inst_type(thx, mt.ty)
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
          if target == nil && !allow_open
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
    matched = match_application_squares(mt, pattern, target)
    if matched != nil
      return matched
    # Expose target-side definitions absent from the theorem's vocabulary.
    # Keep shared operations (such as sum_below) folded while inferring args.
    protected = {}
    application_constants(pattern, protected)
    rules = []
    application_aliases(target, protected, {}, rules, [8])
    if rules.size > 0
      folder = Simp.new(@d, rules)
      # Infer arguments before a reflexive equality or other outer proposition
      # simplifies to True and loses the structure needed by the theorem.
      inner = folder.sub_simp_opt(target, 0)
      if inner != nil
        expanded = dest_binop(inner.concl, "=")[1]
        matched = mt.match_instantiated(@d, pattern, expanded)
        if matched == nil
          matched = match_application_squares(mt, pattern, expanded)
        if matched != nil
          return matched
      conv = folder.simp_conv(target, 0)
      expanded = dest_binop(conv.concl, "=")[1]
      matched = mt.match_instantiated(@d, pattern, expanded)
      return matched == nil ? match_application_squares(mt, pattern, expanded) : matched
    nil

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
          rules.push(make_rule(@d, definition, t.name))
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
    names = []
    args.each -> (t)
      names.push(t.text)
    if names.size == 0
      names = ["_"]
    if all
      names = []
    count = 0
    while (all && intro_able?(g.goal.concl)) || count < names.size
      nm = "_"
      if !all
        nm = names[count]
      g = intro1(g, nm)
      count += 1
      if all && count > 64
        break
    g

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
        hn = fresh_hyp_name
      p = pq[0]
      ng = Goal.new(goal.fixes, goal.hyps + [[hn, p]], pq[1])
      refs = refine(g, [ng], ->(ts) @k.disch(p, ts[0]))
      return refs[0]
    np = dest_unop(c, "¬")
    if np != nil
      hn = nm
      if nm == "_"
        hn = fresh_hyp_name
      ng = Goal.new(goal.fixes, goal.hyps + [[hn, np]], @k.false_tm)
      refs = refine(g, [ng], ->(ts) @k.not_intro(np, ts[0]))
      return refs[0]
    # unfold a definition at the head and retry
    fail("intro: goal is not ∀, → or ¬: " + tm_show(c))

  -> tac_apply(g, args)
    if args.size == 0
      fail("apply needs a theorem")
    e = parse_expr_toks(args)
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
        fail("use: goal is not an existential")
      w = elab_term(gg, p, ex.ty)
      body = tm_instantiate(ex.b, w, 0)
      refs = refine(cur, [gg.with_concl(body)], ->(ts) @k.exists_intro(c, w, ts[0]))
      cur = refs[0]
    # try to close trivially
    begin
      tac_trivial(cur)
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
    if proof_toks != nil && proof_toks.size > 0 && proof_toks[0].text == "by"
      th = run_subproof(goal, prop, by_nodes(arr_sub(proof_toks, 1, proof_toks.size - 1), block, line))
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
    n1 = fresh_hyp_name
    n2 = fresh_hyp_name
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
    rewrite_everywhere(g, eqth, v, t)

  -> rewrite_everywhere(g, eqth, v, t)
    goal = g.goal
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
      # ts[0]: hyps[t/v] ⊢ concl[t/v]. Generalize back over v using eqth : v = t.
      res = ts[0]
      # discharge substituted hyps, then re-derive original statement
      imp = res
      i = nh.size - 1
      while i >= 0
        imp = @k.disch(nh[i][1], imp)
        i -= 1
      # imp: ⊢ H1[t] ⇒ ... ⇒ C[t]  ; turn into statement about v via ∀-instantiation
      big = oldc
      j = oldh.size - 1
      while j >= 0
        big = @k.bin("⇒", oldh[j][1], big)
        j -= 1
      lam = mk_lam(v, big)
      # ⊢ (λv. big) t  from imp (beta)
      bt = @k.beta(mk_app(lam, t))
      at_t = @k.eq_mp(@k.sym(bt), fit_concl(imp, dest_binop(bt.concl, "=")[1]))
      # congruence along v = t (sym): (λv.big) t = (λv.big) v
      cong = @d.ap_term(lam, @k.sym(eqth))
      at_v = @k.eq_mp(cong, at_t)
      bv = @k.beta(mk_app(lam, v))
      out = @k.eq_mp(bv, at_v)
      j = 0
      while j < oldh.size
        out = @k.mp(out, @k.assume(oldh[j][1]))
        j += 1
      out
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
    ni = 0
    refs.each -> (rf)
      cur = rf
      while intro_able?(cur.goal.concl) && !(dest_binop(cur.goal.concl, "⇒") != nil && rev_prefix?(cur.goal.concl, revp))
        nm = "_"
        if ni < names.size
          nm = names[ni]
          ni += 1
        cur = intro1(cur, nm)
      # re-introduce reverted hypotheses with their names
      revp.each -> (h)
        if dest_binop(cur.goal.concl, "⇒") != nil
          cur = intro1(cur, h[0])
    0

  -> rev_prefix?(c, revp)
    false

  # rw [h1, ← h2, foo a] (at h)?
  -> tac_rw(g, args)
    at = find_top(args, "at", 0)
    targets = [nil]
    rs = args
    if at >= 0
      # `rw [...] at h1 h2 ⊢` rewrites every listed hypothesis (and the goal for ⊢)
      targets = []
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
    th = rule_theorem(goal, rtoks)
    if rev
      th = sym_rule(th)
    rule = make_rule(@d, th, "rw")
    term = goal.concl
    if target_h != nil
      term = hyp_or_fail(goal, target_h)
    eqth = rewrite_once(rule, term, goal)
    if eqth == nil
      fail("rw: pattern " + tm_show(rule.lhs) + " not found")
    rhs = dest_binop(eqth.concl, "=")[1]
    if target_h == nil
      refine(g, [goal.with_concl(rhs)], ->(ts) @k.eq_mp(@k.sym(eqth), ts[0]))[0]
    else
      old = hyp_or_fail(goal, target_h)
      ng = goal.without_hyp(target_h).add_hyp(target_h, rhs)
      refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))[0]

  -> rule_theorem(goal, toks)
    e = parse_expr_toks(toks)
    if e.kind == :id
      th = lookup_proof(goal, e.s)
      if th == nil
        fail("unknown rule '" + e.s + "'")
      return th
    hd = @session.elab.ast_spine(e)[0]
    if hd.kind != :id
      return proof_ast(goal, e, nil)
    base = lookup_proof(goal, hd.s)
    if base == nil
      fail("unknown rule '" + hd.s + "'")
    r = instantiate_to(goal, base, @session.elab.ast_spine(e)[1], nil, true)
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

  # Rewrites all occurrences of the first instance of the rule found in term.
  -> rewrite_once(rule, term, goal)
    s = Simp.new(@d, [rule])
    s.hyp_rules = hyp_thms(goal)
    s.infer_conditions = true
    inst = find_instance_with_simp(s, rule, term)
    if inst == nil
      return nil
    lhs = dest_binop(inst.concl, "=")[0]
    conv = replace_conv_opt(term, lhs, inst)
    if conv == nil
      return @k.refl(term)
    conv

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
                rules.push(make_rule(@d, eqth, nm))
            else
              th = rule_theorem(goal, r)
              if rev
                th = sym_rule(th)
              rules.push(make_rule(@d, th, nm))
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
    names = args
    if at >= 0
      # `unfold f at h1 h2` unfolds in each listed hypothesis
      if args.size - at - 1 > 1
        cur = g
        k = at + 1
        while k < args.size
          if args[k].text == "⊢"
            cur = tac_unfold(cur, arr_sub(args, 0, at))[0]
          else
            cur = tac_unfold(cur, arr_sub(args, 0, at + 1) + [args[k]])[0]
          k += 1
        return [cur]
      target_h = args[at + 1].text
      names = arr_sub(args, 0, at)
    rules = []
    names.each -> (t)
      nm = t.text
      eqs = @session.eqns_of(nm)
      if eqs.size > 0
        eqs.each -> (e)
          rules.push(make_rule(@d, e, nm))
      # Applied equations do not match a bare function passed as an argument.
      # Its defining equality also unfolds that higher-order occurrence.
      if @k.defs.has_key?(nm)
        rules.push(make_rule(@d, @k.defs[nm], nm, false))
      elsif eqs.size == 0
        fail("unfold: " + nm + " is not a definition")
    s = Simp.new(@d, rules)
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
    if dest_binop(g.goal.concl, "=") != nil
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
    e = dest_binop(c, "=")
    if e == nil
      fail("ring: goal is not an equation")
    begin
      return close(g, fit_concl(@k.ring_eq(e[0], e[1]), g.goal.concl))
    rescue original
      # Try checked defining equations only after ordinary ring normalization.
      # Normalize the two sides separately so the final polynomial check and
      # its trust tag remain the same as an explicit unfold followed by ring.
      begin
        rules = auto_relation_definitions([c])
        simplifier = Simp.new(@d, rules)
        simplifier.step_limit = 4096
        left = simplifier.simp_conv(e[0], 0)
        right = simplifier.simp_conv(e[1], 0)
        lhs = dest_binop(left.concl, "=")[1]
        rhs = dest_binop(right.concl, "=")[1]
        if !tm_eq(lhs, e[0]) || !tm_eq(rhs, e[1])
          proof = @k.trans(left, @k.trans(@k.ring_eq(lhs, rhs), @k.sym(right)))
          return close(g, fit_concl(proof, g.goal.concl))
      rescue e2
        0
      fail(original.to_s)

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
    target = dest_binop(@d.beta_eta_term(g.goal.concl), "=")
    if target == nil || !numeric_type?(type_of(target[0]))
      fail("linear_combination: goal must be an equality over ℕ, ℤ, ℚ or ℝ")
    if args.size == 0
      return tac_ring(g)
    ty = type_of(target[0])
    th = combination_proof(g.goal, parse_expr_toks(args), ty)
    th = fit_concl(th, @d.beta_eta_term(th.concl))
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
    close(g, fit(g, result))

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
    begin
      proof = linarith_proof(goal, extra)
    rescue e
      if !with_casts
        raise e
      proof = cast_arithmetic_proof(goal, extra)
      if proof == nil
        raise e
    close(g, proof)

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
    e = dest_binop(c, "=")
    if e != nil && numeric_type?(type_of(e[0]))
      # prove ≤ both ways then antisymmetry
      ty = type_of(e[0])
      le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
      a = mk_apps(le, [e[0], e[1]])
      b = mk_apps(le, [e[1], e[0]])
      t1 = arith_prove(goal.with_concl(a), extra)
      t2 = arith_prove(goal.with_concl(b), extra)
      anti = @session.lemma_at("le_antisymm", ty)
      return @k.mp(@k.mp(@k.spec(e[1], @k.spec(e[0], anti)), t1), t2)
    arith_prove(goal, extra)

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
      facts.each -> (th)
        key = tm_key(th.concl)
        if !@split_ne.include?(key)
          sides = @k.dest_eq(th.concl.b)
          lem = @session.lemma_at("lt_or_gt_of_ne", type_of(sides[0]))
          if lem != nil
            disj = @k.mp(@k.spec(sides[1], @k.spec(sides[0], lem)), th)
            pq = dest_binop(disj.concl, "∨")
            @split_ne.push(key)
            begin
              left = arith_prove(goal.add_hyp("_lt", pq[0]), extra)
              right = arith_prove(goal.add_hyp("_gt", pq[1]), extra)
            ensure
              @split_ne.pop
            if !hyps_has?(left.hyps, pq[0])
              return left
            if !hyps_has?(right.hyps, pq[1])
              return right
            return @k.disj_cases(disj, left, right)
      raise failure

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
    # omega: split a truncated ℕ subtraction a - b into b ≤ a (a - b + b = a) and a ≤ b (a - b = 0), at most 3 deep
    if @omega_mode && @split_sub.size < 3
      s = find_nat_sub(goal, extra)
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
    arith_prove_core(goal, extra + divmod_facts(goal, extra))

  # the first ℕ subtraction a - b in the goal, hypotheses or extra facts that is not already being split
  -> find_nat_sub(goal, extra)
    ts = [goal.concl]
    goal.hyps.each -> (h)
      ts.push(h[1])
    extra.each -> (t)
      ts.push(t.concl)
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

  -> auto_residue(target, fact)
    source = literal_residue(fact.concl)
    if source == nil
      return nil
    dividend = source[0].a.b
    if !tm_eq(dividend, target[0].a.b)
      return nil
    modulus = source[0].b
    divisor = target[0].b
    if modulus.val % divisor.val != 0 || int_fmod(source[1].val, divisor.val) != target[1].val
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
      if !tm_eq(proof.concl, @k.eq_tm(target[0], target[1]))
        return nil
      if target[2]
        proof = @k.sym(proof)
      return target[3] == nil ? proof : @k.eq_mp(@k.sym(target[3]), proof)
    rescue e
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

  # positivity: sign facts of the goal's subterms (|x| ≥ 0, exp x > 0, √x ≥ 0, x^(2k) ≥ 0), then nlinarith
  -> tac_positivity(g, args)
    facts = []
    seen = {}
    pos_facts(g.goal.concl, facts, seen)
    @nl_mode = true
    begin
      close(g, arith_prove(g.goal, facts))
    rescue e
      @nl_mode = false
      raise e
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
    auto_classical(goal, facts, terms, [], 3, [12], false)

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
          proof = auto_residue(residue, th)
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

  -> auto_rule_spine(t)
    while true
      quant = dest_unop(t, "∀")
      if quant != nil && quant.tag == :lam
        t = quant.b
      else
        implication = dest_binop(t, "⇒")
        if implication == nil
          break
        t = implication[1]
    spine = strip_app(t)
    if spine[0].tag != :const || !["=", "≤", "<"].include?(spine[0].name) || spine[1].size != 2
      return nil
    spine

  -> auto_rule_shape(t)
    spine = auto_rule_spine(t)
    if spine == nil
      return nil
    [spine[0].name, auto_operand_head(spine[1][0]), auto_operand_head(spine[1][1]), ty_show(type_of(spine[1][0]))]

  -> auto_registered_key(term)
    shape = auto_rule_shape(term)
    if shape != nil
      operand = auto_rule_spine(term)[1][0]
      if ty_vars(type_of(operand)).size > 0
        shape[3] = "*"
      return "math|" + shape.join("|")
    while true
      quant = dest_unop(term, "∀")
      implication = dest_binop(term, "⇒")
      if quant != nil
        term = quant.b
      elsif implication != nil
        term = implication[1]
      else
        break
    head = strip_app(term)[0]
    head.tag == :const ? "logic|" + head.name : "*"

  # All registered rules are closed. Their projections and index keys depend
  # only on the library, so detached searches can share one session index.
  -> build_registered_index
    index = {}
    context = Goal.new([], [], @k.false_tm)
    @session.auto_rules.each -> (name, th)
      begin
        auto_relation_parts(th, [32]).each -> (part)
          auto_hint_rules(context, part).each -> (rule)
            key = auto_registered_key(rule.concl)
            bucket = index[key]
            if bucket == nil
              bucket = []
              index[key] = bucket
            bucket.push([name, th, rule])
            shape = auto_rule_shape(rule.concl)
            if shape != nil
              ty = ty_vars(type_of(auto_rule_spine(rule.concl)[1][0])).size > 0 ? "*" : shape[3]
              [[shape[0], shape[1], "?rhs", ty], [shape[0], "?lhs", shape[2], ty]].each -> (parts)
                endpoint_key = "math|" + parts.join("|")
                endpoints = index[endpoint_key]
                if endpoints == nil
                  endpoints = []
                  index[endpoint_key] = endpoints
                endpoints.push([name, th, rule])
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
      keys.push(auto_registered_key(goal.concl))
    out = []
    keys.each -> (key)
      bucket = index[key]
      if bucket != nil
        bucket.each -> (entry)
          # Shadowing a name does not transfer its old registration.
          if @session.theorems[entry[0]] == entry[1]
            auto_add_fact(out, entry[2])
    out

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
        bridge = auto_arithmetic_proof(goal, context + [@k.assume(conclusion)], budget)
        if bridge != nil
          bound = auto_hint_proof(goal.with_concl(conclusion), [instance], supplied, budget, seen + [goal.concl])
          if bound != nil
            return @d.prove_hyp(bound, bridge)
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
          applied = instantiate_to(goal, hint, [], goal.concl, true)
          result = applied[0]
          applied[1].each -> (premise)
            normalized = @d.beta_norm_term(premise)
            if tm_eq(normalized, goal.concl) || seen.any?(-> (previous) tm_eq(previous, normalized))
              fail("auto: cyclic rule premise")
            sub = Prover.new(@session)
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
    probe = Prover.new(@session)
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

  -> rule_feedback(goal, candidates, hints, fuel, numeric = nil, missing_limit = 128)
    candidates.each -> (hint)
      if fuel[0] == 0
        return nil
      if hint.tags.include?("sorry") || !auto_small_term?(hint.concl, [128])
        next
      body = hint.concl
      while dest_unop(body, "∀") != nil && body.b.tag == :lam
        body = body.b.b
      if dest_binop(body, "⇒") == nil
        next
      begin
        applied = instantiate_to(goal, hint, [], goal.concl, true)
        if numeric != nil && applied[1].size < 2
          next
        note = hint_premise_note(goal, applied, hints, fuel, numeric, missing_limit)
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

  -> hint_premise_note(goal, applied, hints, fuel, numeric, missing_limit)
    if applied[1].size == 0 || applied[1].size > 4
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
    checked_progress_note(known == nil ? conditional : known, missing, nil, [conditional])

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
        facts.each -> (th)
          if seen.size >= 12
            break
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
          break
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

  -> tac_auto(g, depth, hints, budget, seen)
    if depth <= 0
      fail("auto: depth exhausted")
    th = find_assumption(g.goal)
    if th != nil
      return close(g, th)
    # Discharge registered guards already in scope before enumerating their
    # quantified instances. A miss leaves the ordinary search fuel intact.
    if seen.size == 0 && @session.auto_rules.size > 0 && g.goal.hyps.any?(-> (h) dest_unop(h[1], "∀") != nil)
      th = auto_registered_arithmetic(g.goal, hints, [2, 0], seen, true)
      if th != nil
        return close(g, fit(g, th))
    th = auto_forward(g.goal)
    if th != nil
      return close(g, th)
    c = g.goal.concl
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
        tac_auto(r, depth - 1, hints, budget, seen)
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
    equality = @k.dest_eq(g.goal.concl)
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
      worker = Prover.new(@session)
      worker.registered_search = true
      registered_budget = [24, 4]
      proof = worker.auto_hint_proof(g.goal, worker.auto_registered_hints(g.goal), hints, registered_budget, [])
      if proof == nil
        proof = worker.auto_registered_arithmetic(g.goal, hints, registered_budget)
      if proof != nil
        return close(g, fit(g, proof))
    if seen.size == 0
      proof = auto_hint_proof(g.goal, @session.selected_premises(g.goal), hints, [16, 2], [])
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
    just = ->(ts)
      a = fit_concl(ts[0], @k.eq_tm(mk_app(lhs, v), mk_app(rhs, v)))
      ab = @k.abs_rule(v, a)
      l2 = eta_side(lhs, v)
      r2 = eta_side(rhs, v)
      @k.trans(@k.sym(l2), @k.trans(ab, r2))
    refine(g, [ng], just)

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
