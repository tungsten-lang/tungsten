# Rewriting: `rw` (one rule, all instances of its first match) and `simp`
# (bottom-up conditional rewriting to a normal form with literal arithmetic).
# Untrusted: every step is a kernel theorem.

+ Simp
  ro :d, :k
  rw :hyp_rules, :discharger, :step_limit, :infer_conditions

  -> new(@d, rules, @base_by_head = nil, @base_general = nil)
    @k = @d.k
    @by_head = {}
    @general = []
    @steps = 0
    @normal_terms = nil
    @step_limit = 20000
    @literal_steps = 128
    @hyp_rules = []
    @discharger = nil
    @infer_conditions = false
    @binder_names = nil
    n = rules.size
    i = 0
    while i < n
      add_rule(rules[i])
      i += 1

  -> add_rule(r)
    @binder_names = nil
    hn = r.head_name
    if hn != nil
      arr = @by_head[hn]
      if arr == nil
        arr = []
        @by_head[hn] = arr
      arr.push(r)
    else
      @general.push(r)

  -> try_rule_list(list, t, depth, at_head = false)
    if list == nil
      return nil
    n = list.size
    i = 0
    while i < n
      if !at_head || list[i].rewrite_head
        th = apply_rule(list[i], t, depth)
        if th != nil
          return th
      i += 1
    nil

  # Try to rewrite t at the top with one rule: returns ⊢ t = t' or nil.
  -> rewrite_top(t, depth, at_head = false)
    hd = t
    while hd.tag == :app
      hd = hd.a
    if hd.tag == :const
      nm = hd.name
      if @base_by_head != nil
        th = try_rule_list(@base_by_head[nm], t, depth, at_head)
        if th != nil
          return th
      th = try_rule_list(@by_head[nm], t, depth, at_head)
      if th != nil
        return th
    if @base_general != nil
      th = try_rule_list(@base_general, t, depth, at_head)
      if th != nil
        return th
    try_rule_list(@general, t, depth, at_head)

  # For an explicitly named definition, view a small natural literal as
  # predecessor + offset when its defining pattern asks for that shape.
  # Build the conversion only at matching positions; all other arguments stay folded.
  -> literal_pattern_conv(pattern, t)
    if pattern.tag != :app
      return nil
    if t.tag == :lit && t.ty == TY_NAT_SINGLETON && t.val <= 32
      if pattern.a.tag != :app || pattern.a.a.op != OP_ADD || pattern.a.b.tag != :var
        return nil
      offset = pattern.b
      if offset.tag != :lit || offset.ty != t.ty || offset.val <= 0 || offset.val > t.val
        return nil
      expanded = mk_app_raw(mk_app_raw(pattern.a.a, mk_lit(t.val - offset.val, t.ty)), offset)
      return @k.sym(@k.compute(expanded))
    if t.tag != :app
      return nil
    f = literal_pattern_conv(pattern.a, t.a)
    x = literal_pattern_conv(pattern.b, t.b)
    if f == nil && x == nil
      return nil
    @k.mk_comb(f == nil ? @k.refl(t.a) : f, x == nil ? @k.refl(t.b) : x)

  -> apply_rule(r, t, depth, try_literals = true)
    mt = Matcher.new(r.pvars, r.tvs)
    if !mt.m(r.lhs, t, 0)
      if try_literals && r.literal_patterns && @literal_steps > 0
        conv = literal_pattern_conv(r.lhs, t)
        if conv != nil
          step = apply_rule(r, conv.concl.b, depth, false)
          if step != nil
            @literal_steps -= 1
            return @k.trans(conv, step)
      # With fixed types and no binders, a failed first-order match cannot
      # change on retry: none of its bindings can introduce a beta/eta step.
      if r.tvs.size == 0 && r.lhs.mx == 0 && ((r.lhs.search_ops | t.search_ops) & TERM_LAMBDA) == 0
        return nil
      mt = Matcher.new(r.pvars, r.tvs).match_instantiated(@d, r.lhs, t)
      if mt == nil
        return nil
    if @infer_conditions
      mt = match_conditions(r, mt)
      if mt == nil
        return nil
    th = r.th
    if mt.ty.size > 0
      th = @k.inst_type(th, mt.ty)
    if mt.tm.size > 0
      th = @k.inst(th, mt.pairs)
    # discharge conditions
    nc = r.conds.size
    i = 0
    while i < nc
      pq = dest_binop(th.concl, "⇒")
      cond = @d.beta_norm_term(pq[0])
      if tm_unmatched_pattern?(r.conds[i], r.pvars, mt.tm)
        return nil
      pc = nil
      if r.cond_tactics != nil && i < r.cond_tactics.size && r.cond_tactics[i] != nil
        pc = r.cond_tactics[i].call(cond)
      if pc == nil
        pc = discharge(cond, depth)
      if pc == nil
        return nil
      if !tm_eq(pc.concl, pq[0])
        pc = @k.eq_mp(@k.sym(@d.beta_norm_conv(pq[0])), pc)
      th = @k.mp(th, pc)
      i += 1
    th = @d.beta_norm_thm(th)
    c = th.concl
    res = nil
    if r.is_eq && dest_binop(c, "=") != nil
      res = th
    else
      u = dest_unop(c, "¬")
      if u != nil
        res = @d.eqf_intro(th)
      else
        res = @d.eqt_intro(th)
    eq_sides = dest_binop(res.concl, "=")
    if !tm_eq(eq_sides[0], t)
      from = @d.beta_eta_conv(t)
      to = @d.beta_eta_conv(eq_sides[0])
      if !tm_eq(dest_binop(from.concl, "=")[1], dest_binop(to.concl, "=")[1])
        return nil
      res = @k.trans(from, @k.trans(@k.sym(to), res))
    if tm_eq(eq_sides[1], t)
      return nil
    res

  # An explicit rw rule may infer missing arguments from existing premises.
  # Ordinary simp only uses arguments determined by the rewritten expression.
  -> match_conditions(r, mt)
    attempts = 32
    i = 0
    while i < r.conds.size
      cond = r.conds[i]
      if tm_unmatched_pattern?(cond, r.pvars, mt.tm)
        found = nil
        j = 0
        while j < @hyp_rules.size && attempts > 0 && found == nil
          attempts -= 1
          found = mt.match_instantiated(@d, cond, @hyp_rules[j].concl)
          j += 1
        if found == nil
          return nil
        mt = found
      i += 1
    mt

  # Inspect the original condition and match bindings. A substituted target
  # variable may share a pattern variable's name without being unresolved.
  -> tm_unmatched_pattern?(t, pvars, bindings)
    if t.cl || pvars.size == 0
      return false
    case t.tag
    when :var
      pvars.has_key?(t.vkey) && !bindings.has_key?(t.vkey)
    when :app
      tm_unmatched_pattern?(t.a, pvars, bindings) || tm_unmatched_pattern?(t.b, pvars, bindings)
    when :lam
      tm_unmatched_pattern?(t.b, pvars, bindings)
    else
      false

  -> discharge(cond, depth)
    if depth > 4
      return nil
    nh = @hyp_rules.size
    i = 0
    while i < nh
      h = @hyp_rules[i]
      if tm_eq(h.concl, cond)
        return h
      i += 1
    th = simp_conv_opt(cond, depth + 1)
    if th != nil
      r = dest_binop(th.concl, "=")[1]
      if r.op == OP_TRUE
        return @d.eqt_elim(th)
    elsif cond.op == OP_TRUE
      return @k.truth
    if @discharger != nil
      return @discharger.call(cond)
    nil

  # Built-in top-level steps: beta, literal arithmetic, reflexive equality.
  -> builtin_top(t)
    if t.tag != :app
      return nil
    if t.a.tag == :lam
      return @k.beta(t)
    hd = t.a
    arity = 1
    while hd.tag == :app
      hd = hd.a
      arity += 1
    if hd.tag != :const
      return nil
    op = hd.op
    if op == OP_NONE
      return nil
    if arity == 2
      lhs = t.a.b
      rhs = t.b
      if op == OP_EQ && tm_eq(lhs, rhs)
        return @d.eqt_intro(@k.refl(lhs))
      if op >= OP_EQ && op <= OP_LE
        if value_tm?(lhs) && value_tm?(rhs)
          th = @k.compute(t)
          if !tm_eq(dest_binop(th.concl, "=")[1], t)
            return th
        return nil
      if op == OP_AND || op == OP_OR || op == OP_IMP
        if bool_lit?(lhs) || bool_lit?(rhs)
          return bool_simp(hd.name, lhs, rhs, t)
        return nil
    if arity == 1
      arg = t.b
      if op == OP_NOT && bool_lit?(arg)
        return @k.compute(t)
      if op >= OP_SUCC && op <= OP_FLOOR && value_tm?(arg)
        th = @k.compute(t)
        if !tm_eq(dest_binop(th.concl, "=")[1], t)
          return th
      return nil
    if arity == 3 && op == OP_ITE
      c_arg = t.a.a.b
      if bool_lit?(c_arg)
        return @k.compute(t)
    nil

  -> bool_lit?(t)
    t.op == OP_TRUE || t.op == OP_FALSE

  -> value_tm?(a)
    a.tag == :lit || a.op == OP_TRUE || a.op == OP_FALSE

  # p ∧ ⊤ = p etc. proved by case analysis-free kernel steps via compute on closed parts
  -> bool_simp(nm, a, b, t)
    if bool_lit?(a) && bool_lit?(b)
      return @k.compute(t)
    @d.bool_lemmas.simp(nm, a, b)

  # Bottom-up simplification: returns nil if unchanged, else ⊢ t = t'
  -> simp_conv_opt(t, depth)
    @steps += 1
    if @steps > @step_limit
      raise "simp: step limit exceeded (looping rules?)"
    memo = @normal_terms != nil && depth == 0 && t.tag == :app
    if memo
      entry = @normal_terms[t.h & 255]
      if entry != nil && tm_eq(entry[0], t)
        return entry[1]
    th = sub_simp_opt(t, depth)
    result = finish_simp_opt(t, depth, th)
    if memo
      @normal_terms[t.h & 255] = [t, result]
    result

  # Continue at the head when the caller already has the child conversions.
  -> finish_simp_opt(t, depth, th)
    cur = th == nil ? t : dest_binop(th.concl, "=")[1]
    rounds = 0
    while rounds < 64
      step = builtin_top(cur)
      if step == nil
        step = rewrite_top(cur, depth)
      if step == nil
        return th
      nxt = dest_binop(step.concl, "=")[1]
      th = th == nil ? step : @k.trans(th, step)
      inner = sub_simp_opt(nxt, depth)
      if inner != nil
        th = @k.trans(th, inner)
        cur = dest_binop(inner.concl, "=")[1]
      else
        cur = nxt
      rounds += 1
    th

  # Bottom-up simplification: ⊢ t = t'
  -> simp_conv(t, depth = 0)
    th = simp_conv_opt(t, depth)
    if th == nil
      return @k.refl(t)
    th

  # A defining equation may duplicate an already normalized argument.
  # Reuse checked subterm conversions for this call with fixed rules.
  -> simp_definition_conv(t, children_only = false)
    @normal_terms = Array.new(256)
    begin
      if children_only
        return sub_simp_opt(t, 0)
      simp_conv(t, 0)
    ensure
      @normal_terms = nil

  # Fixed names in rewrite proofs and local facts must stay free when entering
  # a binder. Cache rule names; hypothesis rules can change between calls.
  -> binder_variable(t)
    if @binder_names == nil
      @binder_names = {}
      lists = @by_head.values + [@general]
      if @base_by_head != nil
        lists += @base_by_head.values
      if @base_general != nil
        lists.push(@base_general)
      lists.each -> (rules)
        rules.each -> (rule)
          tm_frees(rule.th.concl).each -> (variable)
            if !rule.pvars.has_key?(variable.vkey)
              @binder_names[variable.name] = true
          rule.th.hyps.each -> (hyp) tm_free_names_into(hyp, @binder_names)
    names = {}
    @binder_names.each -> (name, _) names[name] = true
    @hyp_rules.each -> (fact)
      tm_free_names_into(fact.concl, names)
      fact.hyps.each -> (hyp) tm_free_names_into(hyp, names)
    tm_free_names_into(t, names)
    hint = t.name == nil || t.name == "" ? "x" : t.name
    mk_var(fresh_name_from_set(hint, names), t.ty)

  -> sub_simp_opt(t, depth)
    case t.tag
    when :app
      f = simp_conv_head_opt(t.a, depth)
      x = simp_conv_opt(t.b, depth)
      if f == nil && x == nil
        return nil
      fth = f == nil ? @k.refl(t.a) : f
      xth = x == nil ? @k.refl(t.b) : x
      @k.mk_comb(fth, xth)
    when :lam
      variable = binder_variable(t)
      inner = simp_conv_opt(tm_instantiate(t.b, variable, 0), depth)
      if inner == nil
        return nil
      @k.abs_rule(variable, inner)
    else
      nil

  # Function equalities apply at call heads. Definition bodies stay deferred so
  # applied equations and induction hypotheses can match before unfolding.
  -> simp_conv_head_opt(t, depth)
    if t.tag == :app || t.tag == :lam
      return simp_conv_opt(t, depth)
    th = nil
    cur = t
    rounds = 0
    while rounds < 64
      step = rewrite_top(cur, depth, true)
      if step == nil
        return th
      th = th == nil ? step : @k.trans(th, step)
      cur = dest_binop(step.concl, "=")[1]
      rounds += 1
    th

# Boolean identities proved from the kernel rules.
+ BoolLemmas
  -> new(@d)
    @k = @d.k

  -> simp(nm, a, b)
    if nm == "∧"
      if b.op == OP_TRUE
        return and_true(a, true)
      if a.op == OP_TRUE
        return and_true(b, false)
      if a.op == OP_FALSE || b.op == OP_FALSE
        return and_false(a, b)
    if nm == "∨"
      if a.op == OP_FALSE
        return or_false(b, false)
      if b.op == OP_FALSE
        return or_false(a, true)
      if a.op == OP_TRUE || b.op == OP_TRUE
        return or_true(a, b)
    if nm == "⇒"
      if a.op == OP_TRUE
        return imp_true_left(b)
      if b.op == OP_TRUE
        return imp_true_right(a)
      if a.op == OP_FALSE
        return imp_false_left(b)
    nil

  # (p ∧ ⊤) = p  or (⊤ ∧ p) = p
  -> and_true(p, right)
    k = @k
    t = k.truth
    conj_tm = right ? k.bin("∧", p, k.truth_tm) : k.bin("∧", k.truth_tm, p)
    h = k.assume(conj_tm)
    pp = right ? k.conj1(h) : k.conj2(h)
    hp = k.assume(p)
    back = right ? k.conj(hp, t) : k.conj(t, hp)
    k.deduct_antisym(back, pp)

  -> and_false(a, b)
    k = @k
    conj_tm = k.bin("∧", a, b)
    h = k.assume(conj_tm)
    f = a.op == OP_FALSE ? k.conj1(h) : k.conj2(h)
    hf = k.assume(k.false_tm)
    back = k.false_elim(hf, conj_tm)
    k.deduct_antisym(back, f)

  -> or_false(p, right)
    k = @k
    disj_tm = right ? k.bin("∨", p, k.false_tm) : k.bin("∨", k.false_tm, p)
    h = k.assume(disj_tm)
    hp = k.assume(p)
    hf = k.assume(k.false_tm)
    fp = k.false_elim(hf, p)
    there = right ? k.disj_cases(h, hp, fp) : k.disj_cases(h, fp, hp)
    back = right ? k.disj1(hp, k.false_tm) : k.disj2(k.false_tm, hp)
    k.deduct_antisym(back, there)

  -> or_true(a, b)
    k = @k
    back = a.op == OP_TRUE ? k.disj1(k.truth, b) : k.disj2(a, k.truth)
    k.deduct_antisym(back, k.truth)

  -> imp_true_left(b)
    k = @k
    imp = k.bin("⇒", k.truth_tm, b)
    there = k.mp(k.assume(imp), k.truth)
    back = k.disch(k.truth_tm, k.assume(b))
    k.deduct_antisym(back, there)

  -> imp_true_right(a)
    k = @k
    back = k.disch(a, k.truth)
    k.deduct_antisym(back, k.truth)

  -> imp_false_left(b)
    k = @k
    back = k.disch(k.false_tm, k.false_elim(k.assume(k.false_tm), b))
    k.deduct_antisym(back, k.truth)
