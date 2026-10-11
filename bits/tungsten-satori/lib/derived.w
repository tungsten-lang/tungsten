# Derived rules, matching and conversions. Nothing here is trusted: every
# function builds its result through KKernel rules.

+ Derived
  ro :k
  -> new(@k)
    @fresh = 0

  -> fresh_name(base)
    @fresh += 1
    base + "_" + @fresh.to_s

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
    t = th
    while true
      q = dest_unop(t.concl, "∀")
      if q == nil || q.tag != :lam
        return t
      nm = q.name
      if nm == nil || nm == ""
        nm = "x"
      avoid = [t.concl] + t.hyps
      v = mk_var(fresh_name_avoiding(nm, avoid), q.ty)
      t = @k.spec(v, t)

  -> fresh_name_avoiding(base, terms)
    fresh_name_global(base, terms)

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

  # Beta-normalizes every redex in t: ⊢ t = t'
  -> beta_norm_conv(t)
    case t.tag
    when :app
      f = beta_norm_conv(t.a)
      x = beta_norm_conv(t.b)
      th = @k.mk_comb(f, x)
      r = dest_binop(th.concl, "=")[1]
      if r.tag == :app && r.a.tag == :lam
        th2 = @k.trans(th, @k.beta(r))
        r2 = dest_binop(th2.concl, "=")[1]
        return @k.trans(th2, beta_norm_conv(r2))
      th
    when :lam
      p = dest_lam_fresh(t, [t])
      v = p[0]
      inner = beta_norm_conv(p[1])
      @k.abs_rule(v, inner)
    else
      @k.refl(t)

  -> has_beta_redex?(t)
    case t.tag
    when :app
      if t.a.tag == :lam
        return true
      has_beta_redex?(t.a) || has_beta_redex?(t.b)
    when :lam
      has_beta_redex?(t.b)
    else
      false

  # Rewrites a theorem's conclusion to beta-normal form.
  -> beta_norm_thm(th)
    if !has_beta_redex?(th.concl)
      return th
    @k.eq_mp(beta_norm_conv(th.concl), th)

  -> beta_norm_term(t)
    if !has_beta_redex?(t)
      return t
    dest_binop(beta_norm_conv(t).concl, "=")[1]

-> fresh_name_global(base, terms)
  fresh_name(base, terms)

# ---------------------------------------------------------------------------
# Matching. Pattern variables are free variables listed in `pvars` (Hash of
# var_key -> true). Produces term bindings tm (var_key -> term) and type
# bindings ty (tyvar -> type) for the pattern's generic type variables tvs.

+ Matcher
  ro :tm, :ty
  -> new(@pvars, @tvs)
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
    if p.tag == :v
      if @tvs.has_key?(p.name)
        if @ty.has_key?(p.name)
          return ty_eq(@ty[p.name], t)
        @ty[p.name] = t
        return true
      return ty_eq(p, t)
    if t.tag == :v || p.name != t.name || p.args.size != t.args.size
      return false
    i = 0
    while i < p.args.size
      if !match_ty(p.args[i], t.args[i])
        return false
      i += 1
    true

  # depth: number of binders entered (for higher-order patterns).
  -> m(p, t, depth)
    if p.tag == :var && @pvars.has_key?(var_key(p))
      if lam_count_bound(t, 0)
        return false
      return bind(p, t)
    # higher-order pattern: P (bnd i) with P a pattern variable
    if p.tag == :app && p.a.tag == :var && @pvars.has_key?(var_key(p.a)) && p.b.tag == :bnd
      return bind_ho(p.a, p.b.idx, t)
    if p.tag != t.tag
      return false
    case p.tag
    when :const
      p.name == t.name && match_ty(p.ty, t.ty)
    when :var
      p.name == t.name && match_ty(p.ty, t.ty)
    when :bnd
      p.idx == t.idx
    when :lit
      lit_key(p.val) == lit_key(t.val) && match_ty(p.ty, t.ty)
    when :app
      m(p.a, t.a, depth) && m(p.b, t.b, depth)
    else
      match_ty(p.ty, t.ty) && m(p.b, t.b, depth + 1)

  -> bind(p, t)
    k = var_key(p)
    if @tm.has_key?(k)
      return tm_eq(@tm[k], t)
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
    k = var_key(pv)
    if @tm.has_key?(k)
      return tm_eq(eta_contract(@tm[k]), lam)
    @tm[k] = lam
    @pvar_objs[k] = pv
    true

  -> pairs
    out = []
    @tm.keys.each -> (k)
      v = @pvar_objs[k]
      out.push([mk_var(v.name, ty_subst(v.ty, @ty)), @tm[k]])
    out

-> fresh_ty_placeholder
  ty_var("?ho")

# True when every loose bound index in t (relative to `depth`) equals i.
-> only_loose(t, i, depth)
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
  case t.tag
  when :bnd
    if t.idx >= depth && t.idx - depth == i
      mk_bnd(depth, t.ty)
    else
      t
  when :app
    mk_app_raw(reindex(t.a, i, depth), reindex(t.b, i, depth))
  when :lam
    mk_lam_raw(t.name, t.ty, reindex(t.b, i, depth + 1))
  else
    t

# ---------------------------------------------------------------------------
# Rewrite rules: a theorem `hyps ⊢ ∀xs. c1 → ... → l = r` prepared for matching.

+ RewriteRule
  ro :th, :lhs, :rhs, :conds, :pvars, :tvs, :name
  # th: spec'd theorem (free pattern vars) with conclusion `conds → l = r`
  -> new(@th, @lhs, @rhs, @conds, @pvars, @tvs, @name)

-> make_rule(d, th, name)
  k = d.k
  # rename generic type variables to avoid clashes with goal type variables
  tvs = {}
  tm = {}
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
  t = d.spec_all(t)
  pvars = {}
  tm_frees(t.concl).each -> (v)
    free_in_hyp = false
    t.hyps.each -> (h)
      if tm_free_in?(v, h)
        free_in_hyp = true
    if !free_in_hyp
      pvars[var_key(v)] = true
  conds = []
  c = t.concl
  while dest_binop(c, "⇒") != nil
    pq = dest_binop(c, "⇒")
    conds.push(pq[0])
    c = pq[1]
  e = dest_binop(c, "=")
  if e == nil
    # P  ~>  P = True ;  ¬P  ~>  P = False
    u = dest_unop(c, "¬")
    if u != nil
      e = [u, k.false_tm]
    else
      e = [c, k.truth_tm]
  RewriteRule.new(t, e[0], e[1], conds, pvars, tvs, name)


# λx. f x  ~>  f   (when x does not occur in f)
-> eta_contract(t)
  if t.tag == :lam && t.b.tag == :app && t.b.b.tag == :bnd && t.b.b.idx == 0 && !lam_count_bound(t.b.a, 0)
    return t.b.a
  t

+ Matcher
  -> clone
    c = Matcher.new(@pvars, @tvs)
    c.copy_from(@tm, @ty, @pvar_objs)
    c

  -> copy_from(tm, ty, objs)
    tm.keys.each -> (k)
      @tm[k] = tm[k]
    ty.keys.each -> (k)
      @ty[k] = ty[k]
    objs.keys.each -> (k)
      @pvar_objs[k] = objs[k]
