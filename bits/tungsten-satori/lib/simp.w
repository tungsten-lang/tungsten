# Rewriting: `rw` (one rule, all instances of its first match) and `simp`
# (bottom-up conditional rewriting to a normal form with literal arithmetic).
# Untrusted: every step is a kernel theorem.

+ Simp
  ro :d, :k
  rw :hyp_rules, :discharger

  -> new(@d, rules, @base_by_head = nil, @base_general = nil)
    @k = @d.k
    @by_head = {}
    @general = []
    @steps = 0
    @hyp_rules = []
    @discharger = nil
    n = rules.size
    i = 0
    while i < n
      add_rule(rules[i])
      i += 1

  -> add_rule(r)
    hn = r.head_name
    if hn != nil
      arr = @by_head[hn]
      if arr == nil
        arr = []
        @by_head[hn] = arr
      arr.push(r)
    else
      @general.push(r)

  -> try_rule_list(list, t, depth)
    if list == nil
      return nil
    n = list.size
    i = 0
    while i < n
      th = apply_rule(list[i], t, depth)
      if th != nil
        return th
      i += 1
    nil

  # Try to rewrite t at the top with one rule: returns ⊢ t = t' or nil.
  -> rewrite_top(t, depth)
    hd = t
    while hd.tag == :app
      hd = hd.a
    if hd.tag == :const
      nm = hd.name
      if @base_by_head != nil
        th = try_rule_list(@base_by_head[nm], t, depth)
        if th != nil
          return th
      th = try_rule_list(@by_head[nm], t, depth)
      if th != nil
        return th
    if @base_general != nil
      th = try_rule_list(@base_general, t, depth)
      if th != nil
        return th
    try_rule_list(@general, t, depth)

  -> apply_rule(r, t, depth)
    mt = Matcher.new(r.pvars, r.tvs)
    if !mt.m(r.lhs, t, 0)
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
      return nil
    if tm_eq(eq_sides[1], t)
      return nil
    res

  -> tm_frees_pattern?(t, r)
    if t.cl || r.pvars.size == 0
      return false
    tm_frees_pat_walk?(t, r.pvars)

  -> tm_frees_pat_walk?(t, pvars)
    if t.cl
      return false
    case t.tag
    when :var
      pvars.has_key?(t.vkey)
    when :app
      tm_frees_pat_walk?(t.a, pvars) || tm_frees_pat_walk?(t.b, pvars)
    when :lam
      tm_frees_pat_walk?(t.b, pvars)
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
    if @steps > 20000
      raise "simp: step limit exceeded (looping rules?)"
    th = sub_simp_opt(t, depth)
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
      p = dest_lam_fresh(t, [t])
      inner = simp_conv_opt(p[1], depth)
      if inner == nil
        return nil
      @k.abs_rule(p[0], inner)
    else
      nil

  # The function part of an application: simplify its arguments, not the head itself.
  -> simp_conv_head_opt(t, depth)
    if t.tag == :app || t.tag == :lam
      return simp_conv_opt(t, depth)
    nil

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
