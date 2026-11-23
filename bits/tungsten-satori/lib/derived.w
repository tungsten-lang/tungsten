# Derived rules, matching and conversions. Nothing here is trusted: every
# function builds its result through KKernel rules.

+ Derived
  ro :k
  -> new(@k)
    @bool_lemmas = nil

  -> bool_lemmas
    if @bool_lemmas == nil
      @bool_lemmas = BoolLemmas.new(self)
    @bool_lemmas

  # ---- small logical rules --------------------------------------------------------

  -> ap_term(f, th)
    @k.mk_comb(@k.refl(f), th)

  -> ap_thm(th, x)
    @k.mk_comb(th, @k.refl(x))

  -> eqt_intro(th)
    @k.deduct_antisym(th, @k.truth)

  -> eqt_elim(th)
    @k.eq_mp(@k.sym(th), @k.truth)

  -> eqf_intro(th)
    p = dest_unop(th.concl, "¬")
    a = @k.not_elim(th, @k.assume(p))
    b = @k.false_elim(@k.assume(@k.false_tm), p)
    @k.sym(@k.deduct_antisym(a, b))

  -> eqf_elim(th)
    e = dest_binop(th.concl, "=")
    p = e[0]
    @k.not_intro(p, @k.eq_mp(th, @k.assume(p)))

  # th1 ⊢ A, th2 has hypothesis A  ->  th2 with A discharged by th1
  -> prove_hyp(th1, th2)
    if !hyps_has?(th2.hyps, th1.concl)
      return th2
    @k.mp(@k.disch(th1.concl, th2), th1)

  -> undisch(th)
    pq = dest_binop(th.concl, "⇒")
    @k.mp(th, @k.assume(pq[0]))

  -> spec_all(th)
    q0 = dest_unop(th.concl, "∀")
    if q0 == nil || q0.tag != :lam
      return th
    used = {}
    tm_free_names_into(th.concl, used)
    nh = th.hyps.size
    hi = 0
    while hi < nh
      tm_free_names_into(th.hyps[hi], used)
      hi += 1
    t = th
    while true
      q = dest_unop(t.concl, "∀")
      if q == nil || q.tag != :lam
        return t
      nm = q.name
      if nm == nil || nm == ""
        nm = "x"
      v = mk_var(fresh_name_from_set(nm, used), q.ty)
      t = @k.spec(v, t)

  -> gen_all(vars, th)
    t = th
    i = vars.size - 1
    while i >= 0
      t = @k.gen(vars[i], t)
      i -= 1
    t

  -> iff_mp(th_iff, th)
    @k.eq_mp(th_iff, th)

  # ⊢ (p → q) from p ⊢ q
  -> imp_intro(p, th)
    @k.disch(p, th)

  # ∀ P, (∃ x, P x) → P (ε P), from the kernel's choice rule.
  -> epsilon_spec
    a = ty_var("a")
    p = mk_var("P", ty_fun(a, ty_bool))
    x = mk_var("x", a)
    px = mk_app(p, x)
    exists = @k.quant("∃", x, px)
    selected = @k.select_rule(mk_lam(x, px), x, @k.assume(px))
    chosen = @k.choose(x, @k.assume(exists), selected)
    result = @k.eq_mp(beta_eta_conv(chosen.concl), chosen)
    @k.gen(p, @k.disch(exists, result))

  # Beta-normalizes every redex in t: returns nil when t is already beta-normal, else ⊢ t = t'
  -> beta_norm_opt(t)
    if (t.search_ops & TERM_BETA_REDEX) == 0
      return nil
    case t.tag
    when :app
      f = beta_norm_opt(t.a)
      x = beta_norm_opt(t.b)
      if f == nil && x == nil
        if t.a.tag == :lam
          th = @k.beta(t)
          r2 = dest_binop(th.concl, "=")[1]
          nxt = beta_norm_opt(r2)
          if nxt == nil
            return th
          return @k.trans(th, nxt)
        return nil
      fth = f == nil ? @k.refl(t.a) : f
      xth = x == nil ? @k.refl(t.b) : x
      th = @k.mk_comb(fth, xth)
      r = dest_binop(th.concl, "=")[1]
      if r.tag == :app && r.a.tag == :lam
        th2 = @k.trans(th, @k.beta(r))
        r2 = dest_binop(th2.concl, "=")[1]
        nxt = beta_norm_opt(r2)
        if nxt == nil
          return th2
        return @k.trans(th2, nxt)
      th
    when :lam
      p = dest_lam_fresh(t, [t])
      inner = beta_norm_opt(p[1])
      if inner == nil
        return nil
      @k.abs_rule(p[0], inner)
    else
      nil

  # Beta-normalizes every redex in t: ⊢ t = t'
  -> beta_norm_conv(t)
    th = beta_norm_opt(t)
    if th == nil
      return @k.refl(t)
    th

  # Rewrites a theorem's conclusion to beta-normal form.
  -> beta_norm_thm(th)
    conv = beta_norm_opt(th.concl)
    if conv == nil
      return th
    @k.eq_mp(conv, th)

  -> beta_norm_term(t)
    conv = beta_norm_opt(t)
    if conv == nil
      return t
    dest_binop(conv.concl, "=")[1]

  # Eta-normalization as a kernel proof, used when matching extensionally
  # equivalent function arguments (for example, f and fun x => f x).
  -> eta_norm_opt(t)
    if (t.search_ops & TERM_ETA_CANDIDATE) == 0
      return nil
    if t.tag == :app
      f = eta_norm_opt(t.a)
      x = eta_norm_opt(t.b)
      if f == nil && x == nil
        return nil
      return @k.mk_comb(f == nil ? @k.refl(t.a) : f, x == nil ? @k.refl(t.b) : x)
    if t.tag == :lam
      used = {}
      tm_free_names_into(t, used)
      v = mk_var(fresh_name_from_set("eta", used), t.ty)
      inner = eta_norm_opt(tm_instantiate(t.b, v, 0))
      th = nil
      current = t
      if inner != nil
        th = @k.abs_rule(v, inner)
        current = dest_binop(th.concl, "=")[1]
      if !tm_eq(eta_contract(current), current)
        eta = @k.eta(current)
        if th == nil
          return eta
        return @k.trans(th, eta)
      return th
    nil

  -> beta_eta_opt(t)
    first = beta_norm_opt(t)
    if first == nil
      return eta_norm_opt(t)
    second = eta_norm_opt(first.concl.b)
    second == nil ? first : @k.trans(first, second)

  -> beta_eta_conv(t)
    conv = beta_eta_opt(t)
    conv == nil ? @k.refl(t) : conv

  -> beta_eta_term(t)
    conv = beta_eta_opt(t)
    conv == nil ? t : conv.concl.b

  # Evaluate beneath binders using fresh free variables and kernel congruence.
  # The evaluator's ordinary (shallow) conversion remains the only computation
  # rule; abstraction closes each opened binder without capturing free names.
  -> compute_conv(t)
    first = @k.compute(t)
    value = dest_binop(first.concl, "=")[1]
    if (value.search_ops & TERM_LAMBDA) == 0
      return first
    @k.trans(first, compute_binders_conv(value))

  -> compute_binders_conv(t)
    if t.tag == :lam
      used = {}
      tm_free_names_into(t, used)
      v = mk_var(fresh_name_from_set("compute", used), t.ty)
      return @k.abs_rule(v, compute_conv(tm_instantiate(t.b, v, 0)))
    if t.tag == :app && (t.search_ops & TERM_LAMBDA) != 0
      return @k.mk_comb(compute_binders_conv(t.a), compute_binders_conv(t.b))
    @k.refl(t)

  # Literal arithmetic for argument inference. Preserve proposition structure,
  # open expressions, powers and definitions; final fitting replays computation.
  -> application_literal_term(t, budget)
    budget[0] -= 1
    if budget[0] < 0
      raise "application: literal normalization limit"
    if t.tag == :lam
      return mk_lam_raw(t.name, t.ty, application_literal_term(t.b, budget))
    if t.tag != :app
      return t
    cur = mk_app_raw(application_literal_term(t.a, budget), application_literal_term(t.b, budget))
    if !["nat", "int", "rat", "real"].include?(type_of(cur).name)
      return cur
    spine = strip_app(cur)
    head = spine[0]
    args = spine[1]
    if head.tag != :const || !args.all?(-> (arg) arg.tag == :lit)
      return cur
    binary = args.size == 2 && head.op >= OP_ADD && head.op <= OP_MOD
    unary = args.size == 1 && head.op >= OP_SUCC && head.op <= OP_FLOOR
    if binary || unary
      return dest_binop(@k.compute(cur).concl, "=")[1]
    cur

# ---------------------------------------------------------------------------
# Matching. Pattern variables are free variables listed in `pvars` (Hash of
# var_key -> true). Produces term bindings tm (var_key -> term) and type
# bindings ty (tyvar -> type) for the pattern's generic type variables tvs.

+ Matcher
  ro :tm, :ty
  -> new(@pvars, @tvs, @literal_offsets = false)
    @tm = {}
    @ty = {}
    @pvar_objs = {}

  -> ty_ok(pt, t)
    pt2 = ty_subst(pt, @ty)
    if pt2.tag == :v && @tvs.has_key?(pt2.name)
      @ty[pt2.name] = t
      return true
    match_ty(pt2, t)

  -> match_ty(p, t)
    if !p.has_var
      return ty_eq(p, t)
    if p.tag == :v
      if @tvs.has_key?(p.name)
        prev = @ty[p.name]
        if prev != nil
          return ty_eq(prev, t)
        @ty[p.name] = t
        return true
      return ty_eq(p, t)
    if t.tag == :v || p.name != t.name || p.args.size != t.args.size
      return false
    i = 0
    n = p.args.size
    while i < n
      if !match_ty(p.args[i], t.args[i])
        return false
      i += 1
    true

  # Infer an index in succ n, n+k or k+n from a natural literal. These
  # proposals are used only for application inference; fitting the resulting
  # theorem still checks the instantiated arithmetic in the kernel.
  -> match_nat_offset(p, t)
    var = p.b
    offset = 1
    if p.a.op != OP_SUCC
      if p.a.tag != :app || p.a.a.op != OP_ADD
        return false
      arg = p.a.b
      if arg.tag == :lit
        offset = arg.val
      elsif p.b.tag == :lit
        offset = p.b.val
        var = arg
      else
        return false
    if var.tag != :var || var.ty != TY_NAT_SINGLETON || !@pvars.has_key?(var.vkey) || t.val < offset
      return false
    bind(var, mk_nat(zsub(t.val, offset)))

  # depth: number of binders entered (for higher-order patterns).
  -> m(p, t, depth, expand_eta = false)
    if p.tag == :var && @pvars.has_key?(p.vkey)
      if t.mx > 0
        return false
      return bind(p, t)
    # higher-order pattern: P (bnd i) with P a pattern variable
    if p.tag == :app && p.a.tag == :var && p.b.tag == :bnd && @pvars.has_key?(p.a.vkey)
      return bind_ho(p.a, p.b.idx, t)
    if p.tag != t.tag
      if @literal_offsets && p.tag == :app && t.tag == :lit && t.ty == TY_NAT_SINGLETON
        return match_nat_offset(p, t)
      # Application inference can encounter a partially applied function where
      # the rule has a lambda. Closed terms may be placed under a fresh binder.
      if expand_eta && p.tag == :lam && t.mx == 0
        ft = type_of(t)
        if ft.fun? && match_ty(p.ty, ft.dom)
          return m(p.b, mk_app(t, mk_bnd(0, ft.dom)), depth + 1, true)
      return false
    case p.tag
    when :const
      p.name == t.name && match_ty(p.ty, t.ty)
    when :var
      p.name == t.name && match_ty(p.ty, t.ty)
    when :bnd
      p.idx == t.idx
    when :lit
      lit_val_eq(p.val, t.val) && match_ty(p.ty, t.ty)
    when :app
      m(p.a, t.a, depth, expand_eta) && m(p.b, t.b, depth, expand_eta)
    else
      match_ty(p.ty, t.ty) && m(p.b, t.b, depth + 1, expand_eta)

  -> bind(p, t)
    k = p.vkey
    prev = @tm[k]
    if prev != nil
      return tm_eq(prev, t)
    if !match_ty(p.ty, type_of(t))
      return false
    @tm[k] = t
    @pvar_objs[k] = p
    true

  # P applied to bound variable i matches t (whose only loose index may be i).
  -> bind_ho(pv, i, t)
    if !only_loose(t, i, 0)
      return false
    ft = pv.ty
    ft2 = ty_subst(ft, @ty)
    if !ft2.fun?
      if !match_ty(ft, ty_fun(fresh_ty_placeholder, type_of(t)))
        return false
    body = reindex(t, i, 0)
    bty = ty_subst(pv.ty, @ty)
    if !bty.fun?
      return false
    lam = eta_contract(mk_lam_raw("x", bty.dom, body))
    if !match_ty(pv.ty, type_of(lam))
      return false
    k = pv.vkey
    prev = @tm[k]
    if prev != nil
      return tm_eq(eta_contract(prev), lam)
    @tm[k] = lam
    @pvar_objs[k] = pv
    true

  -> pairs
    out = Array.new(@tm.size)
    idx = 0
    @tm.each -> (k, val)
      v = @pvar_objs[k]
      out[idx] = [mk_var(v.name, ty_subst(v.ty, @ty)), val]
      idx += 1
    out

-> fresh_ty_placeholder
  ty_var("?ho")

# True when every loose bound index in t (relative to `depth`) equals i.
-> only_loose(t, i, depth)
  if t.mx <= depth
    return true
  case t.tag
  when :bnd
    t.idx < depth || t.idx - depth == i
  when :app
    only_loose(t.a, i, depth) && only_loose(t.b, i, depth)
  when :lam
    only_loose(t.b, i, depth + 1)
  else
    true

# Replace loose index i (at relative depth) by index 0 (relative), for building λ.
-> reindex(t, i, depth)
  if t.mx <= depth
    return t
  case t.tag
  when :bnd
    if t.idx >= depth && t.idx - depth == i
      mk_bnd(depth, t.ty)
    else
      t
  when :app
    a = reindex(t.a, i, depth)
    b = reindex(t.b, i, depth)
    if a == t.a && b == t.b
      return t
    mk_app_raw(a, b)
  when :lam
    b = reindex(t.b, i, depth + 1)
    if b == t.b
      return t
    mk_lam_raw(t.name, t.ty, b)
  else
    t

# ---------------------------------------------------------------------------
# Rewrite rules: a theorem `hyps ⊢ ∀xs. c1 → ... → l = r` prepared for matching.

+ RewriteRule
  ro :th, :lhs, :rhs, :conds, :pvars, :tvs, :name, :head_name, :is_eq, :rewrite_head
  rw :literal_patterns, :cond_tactics
  # th: spec'd theorem (free pattern vars) with conclusion `conds → l = r`
  -> new(@th, @lhs, @rhs, @conds, @pvars, @tvs, @name, @head_name, @is_eq, @rewrite_head)

-> rule_head_const_name(t)
  while t.tag == :app
    t = t.a
  if t.tag == :const
    return t.name
  nil

# Substitution, beta-eta conversion and numeric literal evaluation preserve
# the outer constant of an application returning Prop.
-> distinct_proposition_heads?(pattern, target)
  if !ty_eq(type_of(target), ty_bool)
    return false
  left = rule_head_const_name(pattern)
  right = rule_head_const_name(target)
  left != nil && right != nil && left != right

-> make_rule(d, th, name, rewrite_head = true)
  k = d.k
  tvs = {}
  tyvars = tm_tyvars(th.concl)
  th.hyps.each -> (h)
    tm_tyvars_into(h, tyvars)
  hypvars = []
  th.hyps.each -> (h)
    tm_tyvars_into(h, hypvars)
  ren = {}
  tyvars.each -> (x)
    if !hypvars.include?(x)
      nn = "§" + x
      ren[x] = ty_var(nn)
      tvs[nn] = true
  t = th
  if ren.size > 0
    t = k.inst_type(th, ren)
  fixed = {}
  tm_frees(t.concl).each -> (v)
    fixed[v.vkey] = true
  t = d.spec_all(t)
  pvars = {}
  tm_frees(t.concl).each -> (v)
    free_in_hyp = false
    t.hyps.each -> (h)
      if tm_free_in?(v, h)
        free_in_hyp = true
    if !free_in_hyp && !fixed.has_key?(v.vkey)
      pvars[v.vkey] = true
  conds = []
  c = t.concl
  while true
    pq = dest_binop(c, "⇒")
    if pq == nil
      break
    conds.push(pq[0])
    c = pq[1]
  e = dest_binop(c, "=")
  is_eq = e != nil
  if e == nil
    u = dest_unop(c, "¬")
    if u != nil
      e = [u, k.false_tm]
    else
      e = [c, k.truth_tm]
  RewriteRule.new(t, e[0], e[1], conds, pvars, tvs, name, rule_head_const_name(e[0]), is_eq, rewrite_head)


# λx. f x  ~>  f   (when x does not occur in f)
-> eta_contract(t)
  if t.tag == :lam && t.b.tag == :app && t.b.b.tag == :bnd && t.b.b.idx == 0 && !lam_count_bound(t.b.a, 0)
    return t.b.a
  t

+ Matcher
  # Explicit function arguments can expose beta redexes in the pattern.
  # Normalize after substitution, retaining the original keys for inferred
  # arguments even when known type substitutions change their variable keys.
  -> match_instantiated(d, pattern, target, literals = false)
    if distinct_proposition_heads?(pattern, target)
      return nil
    p = tm_subst(pattern, @tm)
    vars = {}
    origins = {}
    tm_frees(p).each -> (v)
      if @pvars.has_key?(v.vkey)
        typed = mk_var(v.name, ty_subst(v.ty, @ty))
        vars[typed.vkey] = true
        origins[typed.vkey] = v
    trial = Matcher.new(vars, @tvs, literals)
    trial.copy_from({}, @ty, {})
    p = d.beta_eta_term(tm_inst_types(p, @ty))
    t = d.beta_eta_term(target)
    if literals
      p = d.application_literal_term(p, [128])
      t = d.application_literal_term(t, [128])
    matched = trial.m(p, t, 0, true)
    out = clone
    trial.ty.each -> (name, ty)
      out.ty[name] = ty
    origins.each -> (key, v)
      value = trial.tm[key]
      if value != nil && !out.bind(v, value)
        return nil
    if matched
      return out
    # A predicate inferred from an earlier premise can expose more arguments
    # when it is applied later. Retry with those substitutions normalized.
    # Each retry binds a new term variable, and failed trials stay isolated.
    if out.tm.size > @tm.size
      return out.match_instantiated(d, pattern, target, literals)
    nil

  -> same_bindings?(other)
    if @tm.size != other.tm.size || @ty.size != other.ty.size
      return false
    @tm.keys.all?(-> (k) other.tm.has_key?(k) && tm_eq(@tm[k], other.tm[k])) && @ty.keys.all?(-> (k) other.ty.has_key?(k) && ty_eq(@ty[k], other.ty[k]))

  -> clone
    c = Matcher.new(@pvars, @tvs)
    c.copy_from(@tm, @ty, @pvar_objs)
    c

  -> copy_from(tm, ty, objs)
    tm.each -> (k, v)
      @tm[k] = v
    ty.each -> (k, v)
      @ty[k] = v
    objs.each -> (k, v)
      @pvar_objs[k] = v
