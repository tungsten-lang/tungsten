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

+ Prover
  ro :k, :d, :session
  rw :goals

  -> new(@session)
    @k = @session.k
    @d = @session.d
    @goals = []
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

  # Definitional unfolding: both sides compute to the same value.
  -> try_defeq(th, target)
    begin
      a = @k.compute(th.concl)
      b = @k.compute(target)
      va = dest_binop(a.concl, "=")[1]
      vb = dest_binop(b.concl, "=")[1]
      if tm_eq(va, vb)
        return @k.eq_mp(@k.sym(b), @k.eq_mp(a, th))
    rescue e
      return nil
    nil

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
    # t1 <;> t2 : run t2 on every goal t1 produces (left-associative)
    k = find_top_last(toks, "<;>")
    if k >= 0
      run_then_all(arr_sub(toks, 0, k), arr_sub(toks, k + 1, toks.size - k - 1), n.line)
      run_block(n.block)
      return
    parts = semi_parts(toks)
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
    when "unfold"
      tac_unfold(g, args)
    when "decide"
      tac_decide(g)
    when "norm_num"
      tac_norm_num(g, args)
    when "ring"
      tac_ring(g)
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
      tac_auto(g, 3)
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
      fail("unknown tactic '" + name + "'")

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
    case field
    when "1", "left"
      @k.conj1(th)
    when "2", "right"
      @k.conj2(th)
    when "mp"
      e = dest_binop(th.concl, "=")
      @k.disch(e[0], @k.eq_mp(th, @k.assume(e[0])))
    when "mpr"
      e = dest_binop(th.concl, "=")
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
    th3 = try_defeq(th, target)
    if th3 != nil
      return th3
    fail("mismatch: have " + tm_show(th.concl) + " but need " + tm_show(target))

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
    # telescope: walk ∀ and ⇒, creating pattern vars
    steps = []
    pvars = {}
    avoid = goal.all_terms + [t.concl]
    cur = t.concl
    th_cur = t
    curs = [cur]
    while true
      q = dest_unop(cur, "∀")
      if q != nil && q.tag == :lam
        nm = q.name
        if nm == nil || nm == ""
          nm = "x"
        v = mk_var(fresh_name("?" + nm, avoid), q.ty)
        avoid.push(v)
        pvars[var_key(v)] = true
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
        elsif nq != nil && target != nil && is_const?(target, "⊥")
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
      if si >= steps.size
        fail("too many arguments")
      st = steps[si]
      tstep = si
      if st[0] != :all && !isproof
        # the earliest ∀ binder still unbound (earlier ones may have been skipped by a proof argument)
        j = 0
        while j < steps.size && !(steps[j][0] == :all && !filled.has_key?(j) && !mt.tm.has_key?(var_key(steps[j][1])))
          j += 1
        if j < steps.size
          tstep = j
      if steps[tstep][0] == :all
        v = steps[tstep][1]
        vt = ty_subst(v.ty, mt.ty)
        term = nil
        if vt.tag == :v && tvs.has_key?(vt.name)
          term = elab_term_ast(goal, a, nil)
        else
          term = elab_term_ast(goal, a, vt)
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
        prem = st[1]
        prem_i = tm_subst(prem, mt.tm)
        pth = proof_ast(goal, a, closed_or_nil(prem_i, pvars))
        if !mt.m(prem, pth.concl, 0)
          b1 = @d.beta_norm_thm(pth)
          if !mt.m(prem, b1.concl, 0)
            fail("argument proves " + tm_show(pth.concl) + " but the premise is " + tm_show(prem))
          pth = b1
        proofs[si] = pth
        si += 1
      ai += 1
    if target != nil
      # use the shortest telescope prefix whose remainder matches the target
      tb = @d.beta_norm_term(target)
      found = -1
      j = si
      while j <= steps.size && found < 0
        trial = mt.clone
        if trial.m(curs[j], target, 0) || trial.m(curs[j], tb, 0)
          found = j
          mt = trial
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
            fv = mk_var(fresh_name(v.name.slice(1, v.name.size - 1), avoid), ty_subst(v.ty, mt.ty))
            avoid.push(fv)
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

  -> tac_induction_impl(g, target, names, use_ih)
    goal = g.goal
    vname = target[0].text
    v = nil
    goal.fixes.each -> (f)
      if f[0] == vname || f[1].name == vname
        v = f[1]
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
    r = instantiate_to(goal, lookup_proof(goal, @session.elab.ast_spine(e)[0].s), @session.elab.ast_spine(e)[1], nil, true)
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
    tm_frees(u.concl).each -> (v)
      inhyp = false
      u.hyps.each -> (h)
        if tm_free_in?(v, h)
          inhyp = true
      if !inhyp
        fv.push(v)
    i = fv.size - 1
    while i >= 0
      out = @k.gen(fv[i], out)
      i -= 1
    out

  # Rewrites all occurrences of the first instance of the rule found in term.
  -> rewrite_once(rule, term, goal)
    inst = find_instance(rule, term, goal)
    if inst == nil
      return nil
    lhs = dest_binop(inst.concl, "=")[0]
    replace_conv(term, lhs, inst)

  -> find_instance(rule, t, goal)
    s = Simp.new(@d, [rule])
    s.hyp_rules = hyp_thms(goal)
    th = s.apply_rule(rule, t, 0)
    if th != nil
      return th
    case t.tag
    when :app
      r = find_instance(rule, t.a, goal)
      if r != nil
        return r
      return find_instance(rule, t.b, goal)
    when :lam
      if lam_count_bound(t.b, 0)
        return nil
      return find_instance(rule, t.b, goal)
    nil

  # ⊢ t = t[rhs/lhs] for all occurrences of lhs (not under binders that capture it).
  -> replace_conv(t, lhs, eqth)
    if tm_eq(t, lhs)
      return eqth
    case t.tag
    when :app
      a = replace_conv(t.a, lhs, eqth)
      b = replace_conv(t.b, lhs, eqth)
      return @k.mk_comb(a, b)
    when :lam
      p = dest_lam_fresh(t, [t, lhs])
      inner = replace_conv(p[1], lhs, eqth)
      bad = false
      inner.hyps.each -> (h)
        if tm_free_in?(p[0], h)
          bad = true
      if bad
        return @k.refl(t)
      return @k.abs_rule(p[0], inner)
    @k.refl(t)

  -> hyp_thms(goal)
    out = []
    goal.hyps.each -> (h)
      out.push(@k.assume(h[1]))
    out

  -> simp_rules_from(goal, toks, only)
    rules = []
    if !only
      @session.simp_rules.each -> (r)
        rules.push(r)
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
              rules.push(make_rule(@d, @session.k.defs[nm], nm))
              @session.eqns_of(nm).each -> (eqth)
                rules.push(make_rule(@d, eqth, nm))
            else
              th = rule_theorem(goal, r)
              if rev
                th = sym_rule(th)
              rules.push(make_rule(@d, th, nm))
    rules

  -> tac_simp(g, args, all)
    goal = g.goal
    at = find_top(args, "at", 0)
    target_h = nil
    rs = args
    if at >= 0
      target_h = args[at + 1].text
      rs = arr_sub(args, 0, at)
    only = false
    if rs.size > 0 && rs[0].text == "only"
      only = true
      rs = arr_sub(rs, 1, rs.size - 1)
    rules = simp_rules_from(goal, rs, only)
    if all
      goal.hyps.each -> (h)
        rules.push(make_rule(@d, @k.assume(h[1]), h[0]))
    s = Simp.new(@d, rules)
    s.hyp_rules = hyp_thms(goal)
    prover = self
    s.discharger = ->(c) prover.try_arith_discharge(goal, c)
    if target_h != nil
      old = hyp_or_fail(goal, target_h)
      eqth = s.simp_conv(old, 0)
      newp = dest_binop(eqth.concl, "=")[1]
      if is_const?(newp, "⊥")
        f = @k.eq_mp(eqth, @k.assume(old))
        return close(g, @k.false_elim(f, goal.concl))
      ng = goal.without_hyp(target_h).add_hyp(target_h, newp)
      return refine(g, [ng], ->(ts) @d.prove_hyp(@k.eq_mp(eqth, @k.assume(old)), ts[0]))
    eqth = s.simp_conv(goal.concl, 0)
    rhs = dest_binop(eqth.concl, "=")[1]
    if is_const?(rhs, "⊤")
      return close(g, @d.eqt_elim(eqth))
    if tm_eq(rhs, goal.concl)
      # try closing with assumptions / decide
      th = find_assumption(goal)
      if th != nil
        return close(g, th)
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
      sub.tac_linarith(root, [])
      return root.thm
    rescue e
      return nil

  -> tac_unfold(g, args)
    at = find_top(args, "at", 0)
    target_h = nil
    names = args
    if at >= 0
      # `unfold f at h1 h2` unfolds in each listed hypothesis
      if args.size - at - 1 > 1
        cur = g
        k = at + 1
        while k < args.size
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
      elsif @k.defs.has_key?(nm)
        rules.push(make_rule(@d, @k.defs[nm], nm))
      else
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
    c = g.goal.concl
    e = dest_binop(c, "=")
    if e == nil
      fail("ring: goal is not an equation")
    close(g, @k.ring_eq(e[0], e[1]))

  # Linear arithmetic over hypotheses and the negated goal.
  -> tac_linarith(g, args)
    goal = g.goal
    c = goal.concl
    extra = []
    if args.size > 0
      inner = args
      if inner[0].text == "\["
        inner = arr_sub(inner, 1, inner.size - 2)
      split_top(inner, ",").each -> (p)
        if p.size > 0
          extra.push(proof_expr(goal, p))
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
      return close(g, @k.mp(@k.mp(@k.spec(e[1], @k.spec(e[0], anti)), t1), t2))
    close(g, arith_prove(goal, extra))

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
    # split numeric disequalities a ≠ b into a < b ∨ b < a (at most 4 of them)
    goal.hyps.each -> (h)
      e = dest_unop(h[1], "¬")
      if e != nil
        d = dest_binop(e, "=")
        if d != nil && numeric_type?(type_of(d[0])) && (extra.size < 100)
          lem = @session.lemma_at("lt_or_gt_of_ne", type_of(d[0]))
          if lem != nil && !@split_ne.include?(tm_key(h[1]))
            if @split_ne.size < 4
              @split_ne.push(tm_key(h[1]))
              disj = @k.mp(@k.spec(d[1], @k.spec(d[0], lem)), @k.assume(h[1]))
              pq = dest_binop(disj.concl, "∨")
              g1 = Goal.new(goal.fixes, goal.hyps + [["_lt", pq[0]]], c)
              g2 = Goal.new(goal.fixes, goal.hyps + [["_gt", pq[1]]], c)
              t1 = arith_prove(g1, extra)
              t2 = arith_prove(g2, extra)
              @split_ne.pop
              return @k.disj_cases(disj, t1, t2)
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
    ts = [goal.concl]
    goal.hyps.each -> (h)
      ts.push(h[1])
    extra.each -> (t)
      ts.push(t.concl)
    seen = {}
    out = []
    ts.each -> (t)
      collect_divmod(t, seen, out)
    out

  -> collect_divmod(t, seen, out)
    if t.tag != :app
      return 0
    sp = strip_app(t)
    h = sp[0]
    sp[1].each -> (a)
      collect_divmod(a, seen, out)
    if h.tag == :const && (h.name == "/" || h.name == "%") && sp[1].size == 2
      ty = type_of(t)
      k = sp[1][1]
      x = sp[1][0]
      if (ty_eq(ty, ty_nat) || ty_eq(ty, ty_int)) && k.tag == :lit && k.val > 0
        key = tm_key(x) + "/" + tm_key(k)
        if !seen.has_key?(key)
          seen[key] = true
          begin
            dam = @session.lemma_at("div_add_mod", ty)
            mnn = @session.lemma_at("mod_nonneg", ty)
            mlt = @session.lemma_at("mod_lt", ty)
            lt = @k.mk_const("<", ty_funs([ty, ty], ty_bool))
            kpos = arith_prove_core(Goal.new([], [], mk_apps(lt, [mk_lit(0, ty), k])), [])
            out.push(@k.spec(k, @k.spec(x, dam)))
            out.push(@k.mp(@k.spec(k, @k.spec(x, mnn)), kpos))
            out.push(@k.mp(@k.spec(k, @k.spec(x, mlt)), kpos))
          rescue e
            0
    0

  -> arith_prove_core(goal, extra)
    c = goal.concl
    # negate goal into a comparison hypothesis
    hyps = []
    goal.hyps.each -> (h)
      hyps.push(@k.assume(h[1]))
    extra.each -> (t)
      hyps.push(t)
    neg = nil
    if is_const?(c, "⊥")
      neg = nil
    else
      neg = @k.neg_tm(c)
      hyps.push(@k.assume(neg))
    # fold closed numeric subterms (1 / 2 ^ 4 ↦ 1/16) with simp's literal evaluation
    folder = Simp.new(@d, [])
    folded = []
    bottom = nil
    hyps.each -> (h)
      begin
        eqth = folder.simp_conv(h.concl, 0)
        rhs = dest_binop(eqth.concl, "=")[1]
        if tm_eq(rhs, h.concl)
          folded.push(h)
        elsif is_const?(rhs, "⊥")
          # a closed hypothesis (or negated closed goal) that evaluates to false
          bottom = @k.eq_mp(eqth, h)
        elsif !is_const?(rhs, "⊤")
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
      d = nil
      ["<", "≤", "="].each -> (r)
        if d == nil
          d = dest_binop(t.concl, r)
      ty = type_of(d[0])
      if !by_type.has_key?(ty.key)
        by_type[ty.key] = []
      by_type[ty.key].push(t)
    by_type.keys.each -> (key)
      ts = by_type[key]
      ty = type_of(first_side(ts[0]))
      ts2 = ts
      if ty.name == "nat"
        ts2 = ts + nat_nonneg(ts)
      if @nl_mode && ty.name != "nat"
        ts2 = ts2 + nl_products(ts, ty)
      if ty.name == "nat" || ty.name == "int"
        ts2 = integer_strengthen(ts2, ty)
      coeffs = fm_certificate(ts2, ty.name)
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
    if h.tag != :const || seen.has_key?(tm_key(t))
      return 0
    seen[tm_key(t)] = true
    ty = type_of(t)
    args = sp[1]
    begin
      if h.name == "abs" && args.size == 1
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
      elsif h.name == "^" && args.size == 2 && args[1].tag == :lit
        n = args[1].val
        l = @session.lemma_at("sq_nonneg", ty)
        if l != nil && n.class_name == "Int" && n >= 2 && n % 2 == 0
          base = args[0]
          if n > 2
            base = mk_apps(@k.mk_const("^", ty_funs([ty, ty_nat], ty)), [args[0], mk_lit(n / 2, ty_nat)])
          out.push(@k.spec(base, l))
    rescue e
      0
    0

  # nlinarith: for each hypothesis a ≤ b (a < b) the fact 0 ≤ b - a (0 < b - a), then every pairwise product of those
  # differences, proved with mul_nonneg / mul_pos. Linear arithmetic then treats the expanded monomials as atoms.
  -> nl_products(ts, ty)
    zero = nil
    if ty.name == "int"
      zero = mk_lit(0, ty)
    else
      zero = mk_lit([0, 1], ty)
    minus = @k.mk_const("-", ty_funs([ty, ty], ty))
    le = @k.mk_const("≤", ty_funs([ty, ty], ty_bool))
    lt = @k.mk_const("<", ty_funs([ty, ty], ty_bool))
    mn = @session.lemma_at("mul_nonneg", ty)
    mp = @session.lemma_at("mul_pos", ty)
    if mn == nil || mp == nil
      return []
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
          dt = mk_apps(minus, [d[1], d[0]])
          begin
            nn = arith_prove_core(Goal.new([], [], mk_apps(le, [zero, dt])), [t])
            ps = nil
            if strict
              ps = arith_prove_core(Goal.new([], [], mk_apps(lt, [zero, dt])), [t])
            terms.push(dt)
            nns.push(nn)
            poss.push(ps)
          rescue e
            0
    @nl_mode = saved
    out = []
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

  -> first_side(th)
    ["<", "≤", "="].each -> (r)
      d = dest_binop(th.concl, r)
      if d != nil
        return d[0]
    nil

  # Turns hypothesis theorems into comparison theorems (a < b, a ≤ b, a = b).
  -> normalize_comparisons(th, out)
    p = th.concl
    if comparison?(p)
      out.push(th)
      return
    pq = dest_binop(p, "∧")
    if pq != nil
      normalize_comparisons(@k.conj1(th), out)
      normalize_comparisons(@k.conj2(th), out)
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
    ctx = RingCtx.new("nat")
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
      if ty_eq(type_of(p), ty_nat)
        add_nat_atom(p, seen, out, l)
    when :var
      if ty_eq(p.ty, ty_nat)
        add_nat_atom(p, seen, out, l)
    when :const
      if ty_eq(p.ty, ty_nat)
        add_nat_atom(p, seen, out, l)
    0

  -> add_nat_atom(t, seen, out, l)
    key = tm_key(t)
    if !seen.has_key?(key)
      seen[key] = true
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

  -> tac_auto(g, depth)
    if depth <= 0
      fail("auto: depth exhausted")
    th = find_assumption(g.goal)
    if th != nil
      return close(g, th)
    c = g.goal.concl
    if intro_able?(c)
      ng = tac_intro(g, [], true)
      return tac_auto(ng, depth)
    pq = dest_binop(c, "∧")
    if pq != nil || (dest_binop(c, "=") != nil && type_of(dest_binop(c, "=")[0]).name == "bool")
      refs = tac_constructor(g)
      refs.each -> (r)
        tac_auto(r, depth - 1)
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
          @goals = saved
        when :linarith
          return tac_linarith(g, [])
        when :contradiction
          return tac_contradiction(g)
      rescue e
        0
    pq = dest_binop(c, "∨")
    if pq != nil
      begin
        saved = @goals
        refs = tac_left_right(g, true)
        tac_auto(refs[0], depth - 1)
        return 0
      rescue e
        @goals = saved
      begin
        refs = tac_left_right(g, false)
        tac_auto(refs[0], depth - 1)
        return 0
      rescue e
        @goals = saved
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
