# Rewriting: `rw` (one rule, all instances of its first match) and `simp`
# (bottom-up conditional rewriting to a normal form with literal arithmetic).
# Untrusted: every step is a kernel theorem.

+ Simp
  ro :d, :k
  rw :hyp_rules, :discharger

  -> new(@d, rules)
    @k = @d.k
    @by_head = {}
    @general = []
    @steps = 0
    @hyp_rules = []
    @discharger = nil
    rules.each -> (r)
      add_rule(r)

  -> add_rule(r)
    h = strip_app(r.lhs)[0]
    if h.tag == :const
      if !@by_head.has_key?(h.name)
        @by_head[h.name] = []
      @by_head[h.name].push(r)
    else
      @general.push(r)

  -> rules_for(t)
    h = strip_app(t)[0]
    out = []
    if h.tag == :const && @by_head.has_key?(h.name)
      out = @by_head[h.name]
    out + @general

  # Try to rewrite t at the top with one rule: returns ⊢ t = t' or nil.
  -> rewrite_top(t, depth)
    rules_for(t).each -> (r)
      th = apply_rule(r, t, depth)
      if th != nil
        return th
    nil

  -> apply_rule(r, t, depth)
    mt = Matcher.new(r.pvars, r.tvs)
    if !mt.m(r.lhs, t, 0)
      return nil
    th = r.th
    if mt.ty.size > 0
      th = @k.inst_type(th, mt.ty)
    th = @k.inst(th, mt.pairs)
    # discharge conditions
    i = 0
    while i < r.conds.size
      pq = dest_binop(th.concl, "⇒")
      cond = @d.beta_norm_term(pq[0])
      if tm_frees_pattern?(cond, r)
        return nil
      pc = discharge(cond, depth)
      if pc == nil
        return nil
      if !tm_eq(pc.concl, pq[0])
        pc = @k.eq_mp(@k.sym(@d.beta_norm_conv(pq[0])), pc)
      th = @k.mp(th, pc)
      i += 1
    th = @d.beta_norm_thm(th)
    c = th.concl
    e = dest_binop(c, "=")
    res = nil
    if e != nil && r_is_equation?(r)
      res = th
    else
      u = dest_unop(c, "¬")
      if u != nil
        res = @d.eqf_intro(th)
      else
        res = @d.eqt_intro(th)
    lhs = dest_binop(res.concl, "=")[0]
    if !tm_eq(lhs, t)
      return nil
    rhs = dest_binop(res.concl, "=")[1]
    if tm_eq(rhs, t)
      return nil
    res

  -> r_is_equation?(r)
    !(is_const?(r.rhs, "⊤") && dest_binop(r.th.concl, "=") == nil) && !(is_const?(r.rhs, "⊥") && dest_binop(r.th.concl, "=") == nil) && rule_concl_eq?(r)

  -> rule_concl_eq?(r)
    c = r.th.concl
    while dest_binop(c, "⇒") != nil
      c = dest_binop(c, "⇒")[1]
    dest_binop(c, "=") != nil

  -> tm_frees_pattern?(t, r)
    tm_frees(t).each -> (v)
      if r.pvars.has_key?(var_key(v))
        return true
    false

  -> discharge(cond, depth)
    if depth > 4
      return nil
    @hyp_rules.each -> (h)
      if tm_eq(h.concl, cond)
        return h
    th = simp_conv(cond, depth + 1)
    r = dest_binop(th.concl, "=")[1]
    if is_const?(r, "⊤")
      return @d.eqt_elim(th)
    if @discharger != nil
      return @discharger.call(cond)
    nil

  # Built-in top-level steps: beta, literal arithmetic, reflexive equality.
  -> builtin_top(t)
    if t.tag == :app && t.a.tag == :lam
      return @k.beta(t)
    sp = strip_app(t)
    h = sp[0]
    args = sp[1]
    if h.tag == :const
      nm = h.name
      if nm == "=" && args.size == 2 && tm_eq(args[0], args[1])
        return @d.eqt_intro(@k.refl(args[0]))
      if args.size >= 1 && all_values?(args) && ["+", "-", "*", "/", "%", "^", "<", "≤", "=", "succ", "neg", "abs", "int_of_nat", "rat_of_int", "real_of_rat", "nat_of_int", "floor", "∧", "∨", "⇒", "¬", "ite"].include?(nm)
        th = @k.compute(t)
        if !tm_eq(dest_binop(th.concl, "=")[1], t)
          return th
      if nm == "ite" && args.size == 3 && (is_const?(args[0], "⊤") || is_const?(args[0], "⊥"))
        th = @k.compute(mk_apps(h, args))
        return th
      if (nm == "∧" || nm == "∨" || nm == "⇒") && args.size == 2 && (bool_lit?(args[0]) || bool_lit?(args[1]))
        th = bool_simp(nm, args[0], args[1], t)
        if th != nil
          return th
      if nm == "¬" && args.size == 1 && bool_lit?(args[0])
        return @k.compute(t)
    nil

  -> bool_lit?(t)
    is_const?(t, "⊤") || is_const?(t, "⊥")

  # p ∧ ⊤ = p etc. proved by case analysis-free kernel steps via compute on closed parts
  -> bool_simp(nm, a, b, t)
    if bool_lit?(a) && bool_lit?(b)
      return @k.compute(t)
    lib = BoolLemmas.new(@d)
    lib.simp(nm, a, b)

  -> all_values?(args)
    args.each -> (a)
      if !(a.tag == :lit || is_const?(a, "⊤") || is_const?(a, "⊥"))
        return false
    true

  # Bottom-up simplification: ⊢ t = t'
  -> simp_conv(t, depth = 0)
    @steps += 1
    if @steps > 20000
      raise "simp: step limit exceeded (looping rules?)"
    th = sub_simp(t, depth)
    cur = dest_binop(th.concl, "=")[1]
    rounds = 0
    while rounds < 64
      step = builtin_top(cur)
      if step == nil
        step = rewrite_top(cur, depth)
      if step == nil
        return th
      nxt = dest_binop(step.concl, "=")[1]
      th = @k.trans(th, step)
      inner = sub_simp(nxt, depth)
      th = @k.trans(th, inner)
      cur = dest_binop(th.concl, "=")[1]
      rounds += 1
    th

  -> sub_simp(t, depth)
    case t.tag
    when :app
      f = simp_conv_head(t.a, depth)
      x = simp_conv(t.b, depth)
      @k.mk_comb(f, x)
    when :lam
      p = dest_lam_fresh(t, [t])
      inner = simp_conv(p[1], depth)
      @k.abs_rule(p[0], inner)
    else
      @k.refl(t)

  # The function part of an application: simplify its arguments, not the head itself.
  -> simp_conv_head(t, depth)
    case t.tag
    when :app
      simp_conv(t, depth)
    when :lam
      simp_conv(t, depth)
    else
      @k.refl(t)

# Boolean identities proved from the kernel rules.
+ BoolLemmas
  -> new(@d)
    @k = @d.k

  -> simp(nm, a, b)
    k = @k
    if nm == "∧"
      if is_const?(b, "⊤")
        return and_true(a, true)
      if is_const?(a, "⊤")
        return and_true(b, false)
      if is_const?(a, "⊥") || is_const?(b, "⊥")
        return and_false(a, b)
    if nm == "∨"
      if is_const?(a, "⊥")
        return or_false(b, false)
      if is_const?(b, "⊥")
        return or_false(a, true)
      if is_const?(a, "⊤") || is_const?(b, "⊤")
        return or_true(a, b)
    if nm == "⇒"
      if is_const?(a, "⊤")
        return imp_true_left(b)
      if is_const?(b, "⊤")
        return imp_true_right(a)
      if is_const?(a, "⊥")
        return imp_false_left(b)
    nil

  # (p ∧ ⊤) = p  or (⊤ ∧ p) = p
  -> and_true(p, right)
    k = @k
    t = k.truth
    conj_tm = nil
    if right
      conj_tm = k.bin("∧", p, k.truth_tm)
    else
      conj_tm = k.bin("∧", k.truth_tm, p)
    h = k.assume(conj_tm)
    pp = nil
    if right
      pp = k.conj1(h)
    else
      pp = k.conj2(h)
    hp = k.assume(p)
    back = nil
    if right
      back = k.conj(hp, t)
    else
      back = k.conj(t, hp)
    k.deduct_antisym(back, pp)

  -> and_false(a, b)
    k = @k
    conj_tm = k.bin("∧", a, b)
    h = k.assume(conj_tm)
    f = nil
    if is_const?(a, "⊥")
      f = k.conj1(h)
    else
      f = k.conj2(h)
    hf = k.assume(k.false_tm)
    back = k.false_elim(hf, conj_tm)
    k.deduct_antisym(back, f)

  -> or_false(p, right)
    k = @k
    disj_tm = nil
    if right
      disj_tm = k.bin("∨", p, k.false_tm)
    else
      disj_tm = k.bin("∨", k.false_tm, p)
    h = k.assume(disj_tm)
    hp = k.assume(p)
    hf = k.assume(k.false_tm)
    fp = k.false_elim(hf, p)
    there = nil
    if right
      there = k.disj_cases(h, hp, fp)
    else
      there = k.disj_cases(h, fp, hp)
    back = nil
    if right
      back = k.disj1(hp, k.false_tm)
    else
      back = k.disj2(k.false_tm, hp)
    k.deduct_antisym(back, there)

  -> or_true(a, b)
    k = @k
    disj_tm = k.bin("∨", a, b)
    there = k.assume(disj_tm)
    th_t = k.truth
    there2 = k.disch(disj_tm, th_t)
    back = nil
    if is_const?(a, "⊤")
      back = k.disj1(k.truth, b)
    else
      back = k.disj2(a, k.truth)
    k.deduct_antisym(back, k.truth)

  -> imp_true_left(b)
    k = @k
    imp = k.bin("⇒", k.truth_tm, b)
    there = k.mp(k.assume(imp), k.truth)
    back = k.disch(k.truth_tm, k.assume(b))
    k.deduct_antisym(back, there)

  -> imp_true_right(a)
    k = @k
    imp = k.bin("⇒", a, k.truth_tm)
    there = k.truth
    back = k.disch(a, k.truth)
    k.deduct_antisym(back, there)

  -> imp_false_left(b)
    k = @k
    imp = k.bin("⇒", k.false_tm, b)
    back = k.disch(k.false_tm, k.false_elim(k.assume(k.false_tm), b))
    k.deduct_antisym(back, k.truth)
