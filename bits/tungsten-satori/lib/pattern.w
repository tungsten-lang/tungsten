# Compiles pattern-matching definitions with structural recursion on one
# argument into recursor applications, then proves each equation by
# evaluation (both sides reduce to the same normal form).
#
#   def len : list α → ℕ
#     | [] => 0
#     | x :: xs => 1 + len xs
#
# Supported patterns at the recursion position: constructors applied to
# variables (`[]`, `x :: xs`, `node l v r`, `0`, `n + 1`, `succ n`), or a
# variable/`_` catch-all. Other positions take variables or `_`.

+ PatternDef
  -> new(@s, @c)
    @k = @s.k
    @e = @s.elab

  -> fail(msg)
    raise "def " + @c.name + ": " + msg

  -> compile
    c = @c
    @e.reset
    if c.ty == nil
      fail("pattern definitions need a type")
    fty = @e.elab_type(c.ty)
    # Parameters before the colon become ordinary (variable) pattern arguments,
    # so recursive calls may change them (e.g. accumulators).
    if c.binders.size > 0
      ptys = []
      c.binders.each -> (b)
        ptys.push(@e.elab_type(b.ty))
      fty = ty_funs(ptys, fty)
      neweqs = []
      c.eqns.each -> (eq)
        pats = []
        c.binders.each -> (b)
          pats.push(ast(:id, b.name, []))
        eq[0].each -> (q)
          pats.push(q)
        neweqs.push([pats, eq[1]])
      c.eqns = neweqs
      c.binders = []
    params = []
    nargs = c.eqns[0][0].size
    arg_tys = []
    t = fty
    i = 0
    while i < nargs
      if !t.fun?
        fail("too many patterns for the declared type")
      arg_tys.push(t.dom)
      t = t.cod
      i += 1
    res_ty = t
    c.eqns.each -> (eq)
      if eq[0].size != nargs
        fail("all equations need the same number of patterns")
    # recursion position
    r = -1
    i = 0
    while i < nargs && r < 0
      c.eqns.each -> (eq)
        if r < 0 && !var_pattern?(eq[0][i])
          r = i
      i += 1
    full_ty = fty
    i = params.size - 1
    while i >= 0
      full_ty = ty_fun(params[i].ty, full_ty)
      i -= 1
    if r < 0
      # no recursion: a single equation of variables is an ordinary definition
      if c.eqns.size != 1
        fail("overlapping variable patterns")
      return compile_simple(params, arg_tys, res_ty, full_ty)
    rty = arg_tys[r]
    others = []
    i = 0
    while i < nargs
      if i != r
        others.push(i)
      i += 1
    other_tys = []
    others.each -> (oi)
      other_tys.push(arg_tys[oi])
    motive = ty_funs(other_tys, res_ty)
    ctors = ctor_table(rty)
    # placeholder for recursive calls: params → args → result
    fvar = mk_var("§rec§" + c.name, full_ty)
    cases = []
    ctors.each -> (ct)
      cases.push(build_case(ct, r, others, other_tys, motive, fvar, params, arg_tys, rty))
    rec_c = recursor(rty, motive, cases.size)
    # name := λ params, λ args, rec cases a_r a_others
    avs = []
    i = 0
    while i < nargs
      avs.push(mk_var("a" + i.to_s, arg_tys[i]))
      i += 1
    body = mk_app(mk_apps(rec_c, cases), avs[r])
    others.each -> (oi)
      body = mk_app(body, avs[oi])
    lam = mk_lams(params + avs, body)
    lam = @e.fix_lits(lam)
    @e.check(lam)
    @k.define(c.name, lam)
    prove_equations(params, arg_tys, nargs)

  -> compile_simple(params, arg_tys, res_ty, full_ty)
    eq = @c.eqns[0]
    @e.reset
    vs = []
    i = 0
    while i < eq[0].size
      nm = eq[0][i].s
      if eq[0][i].kind == :hole
        nm = "_" + i.to_s
      v = mk_var(nm, arg_tys[i])
      vs.push(v)
      i += 1
    params.each -> (p)
      @e.push_local(p.name, p)
    vs.each -> (v)
      @e.push_local(v.name, v)
    body = @e.elab(eq[1])
    @e.unify(@e.tyof(body), res_ty)
    body = @e.finalize(body, false)
    lam = mk_lams(params + vs, body)
    @e.check(lam)
    @k.define(@c.name, lam)
    prove_equations(params, arg_tys, eq[0].size)

  -> var_pattern?(p)
    p.kind == :hole || (p.kind == :id && !@k.has_const?(p.s) && !@k.ctor_of.has_key?(p.s))

  # [ctor-name, arg types (instantiated)] for the recursion type
  -> ctor_table(ty)
    if ty.tag == :c && ty.name == "nat"
      return [["zero", []], ["succ", [ty_nat]]]
    info = @k.inductive_of_type(ty)
    if info == nil
      fail("cannot recurse on type " + ty_show(ty))
    m = {}
    i = 0
    while i < info.params.size
      m[info.params[i]] = ty.args[i]
      i += 1
    out = []
    info.ctors.each -> (c)
      args = []
      c[1].each -> (a)
        args.push(ty_subst(a, m))
      out.push([c[0], args])
    out

  -> recursor(ty, motive, ncases)
    if ty.tag == :c && ty.name == "nat"
      return mk_const_raw("nat_rec", ty_funs([motive, ty_funs([ty_nat, motive], motive), ty_nat], motive))
    info = @k.inductive_of_type(ty)
    g = @k.const_type(info.rec_name)
    m = {}
    i = 0
    while i < info.params.size
      m[info.params[i]] = ty.args[i]
      i += 1
    # result type variable of the recursor is the last codomain
    rt = g
    while rt.fun?
      rt = rt.cod
    m[rt.name] = motive
    mk_const_raw(info.rec_name, ty_subst(g, m))

  # Which ctor does pattern p (at the recursion position) denote? Returns
  # [ctor_name, [var names]] or nil for a variable pattern.
  -> classify(p, rty)
    if p.kind == :hole || (p.kind == :id && !@k.ctor_of.has_key?(p.s) && !(p.s == "zero" && rty.name == "nat"))
      return nil
    if rty.name == "nat"
      if p.kind == :num && p.s == "0"
        return ["zero", []]
      if p.kind == :binop && p.s == "+" && p.kids[1].kind == :num && p.kids[1].s == "1" && p.kids[0].kind == :id
        return ["succ", [p.kids[0].s]]
      if p.kind == :app && p.kids[0].kind == :id && p.kids[0].s == "succ" && p.kids[1].kind == :id
        return ["succ", [p.kids[1].s]]
      if p.kind == :id && p.s == "zero"
        return ["zero", []]
      fail("unsupported ℕ pattern (use 0, n + 1 or succ n)")
    if p.kind == :list && p.kids.size == 0
      return ["nil", []]
    if p.kind == :binop && p.s == "::"
      return ["cons", [pat_var(p.kids[0]), pat_var(p.kids[1])]]
    if p.kind == :id
      return [p.s, []]
    if p.kind == :app
      sp = @e.ast_spine(p)
      names = []
      sp[1].each -> (a)
        names.push(pat_var(a))
      return [sp[0].s, names]
    fail("unsupported pattern")

  -> pat_var(a)
    if a.kind == :hole
      return "_"
    if a.kind != :id
      fail("nested patterns are not supported; use a variable")
    a.s

  -> build_case(ct, r, others, other_tys, motive, fvar, params, arg_tys, rty)
    cname = ct[0]
    cargs = ct[1]
    # find the equation for this constructor
    chosen = nil
    names = nil
    @c.eqns.each -> (eq)
      if chosen == nil
        cl = classify(eq[0][r], rty)
        if cl == nil
          chosen = eq
          names = nil
        elsif cl[0] == cname
          chosen = eq
          names = cl[1]
    if chosen == nil
      fail("missing case for constructor " + cname)
    ys = []
    i = 0
    while i < cargs.size
      nm = "y" + i.to_s
      if names != nil && i < names.size && names[i] != "_"
        nm = names[i]
      ys.push(mk_var(nm, cargs[i]))
      i += 1
    ihs = []
    rec_idx = []
    i = 0
    while i < cargs.size
      if ty_eq(cargs[i], rty)
        ihs.push(mk_var("§ih" + i.to_s, motive))
        rec_idx.push(i)
      i += 1
    ovs = []
    j = 0
    others.each -> (oi)
      pat = chosen[0][oi]
      nm = "o" + j.to_s
      if pat.kind == :id
        nm = pat.s
      ovs.push(mk_var(nm, arg_tys[oi]))
      j += 1
    # elaborate the right-hand side
    @e.reset
    params.each -> (p)
      @e.push_local(p.name, p)
    @e.push_local(@c.name, fvar)
    if names == nil
      # variable pattern at r binds the whole constructor application
      pr = chosen[0][r]
      if pr.kind == :id
        whole = mk_apps(mk_const_raw(cname_const(cname), ty_funs(cargs, rty)), ys)
        if cname == "zero"
          whole = mk_nat(0)
        @e.push_local(pr.s, whole)
    ys.each -> (y)
      @e.push_local(y.name, y)
    ovs.each -> (o)
      @e.push_local(o.name, o)
    body = @e.elab(chosen[1])
    @e.unify(@e.tyof(body), arg_tys_res(motive, other_tys))
    body = @e.finalize(body, false)
    # replace recursive calls  F params.. args..  with  ih_j others..
    body = replace_rec(body, fvar, params, r, others, ys, rec_idx, ihs)
    if tm_free_in?(fvar, body)
      fail("recursive call is not structural (must recurse on a constructor argument)")
    inner = mk_lams(ovs, body)
    mk_lams(ys + ihs, inner)

  -> cname_const(n)
    n

  -> arg_tys_res(motive, other_tys)
    t = motive
    other_tys.each -> (x)
      t = t.cod
    t

  -> replace_rec(t, fvar, params, r, others, ys, rec_idx, ihs)
    sp = strip_app(t)
    h = sp[0]
    if h.tag == :var && h.name == fvar.name
      args = sp[1]
      np = params.size
      if args.size >= np + 1 + others.size || args.size >= np + r + 1
        target = args[np + r]
        k = 0
        while k < rec_idx.size
          if tm_eq(target, ys[rec_idx[k]])
            res = ihs[k]
            others.each -> (oi)
              if np + oi < args.size
                res = mk_app_raw(res, replace_rec(args[np + oi], fvar, params, r, others, ys, rec_idx, ihs))
            extra = np + others.size + 1
            while extra < args.size
              res = mk_app_raw(res, replace_rec(args[extra], fvar, params, r, others, ys, rec_idx, ihs))
              extra += 1
            return res
          k += 1
      return t
    case t.tag
    when :app
      mk_app_raw(replace_rec(t.a, fvar, params, r, others, ys, rec_idx, ihs), replace_rec(t.b, fvar, params, r, others, ys, rec_idx, ihs))
    when :lam
      mk_lam_raw(t.name, t.ty, replace_rec(t.b, fvar, params, r, others, ys, rec_idx, ihs))
    else
      t

  # Each equation  ∀ vars, name params pats = rhs  holds by evaluation.
  -> prove_equations(params, arg_tys, nargs)
    name = @c.name
    const = mk_const_raw(name, @k.const_type(name))
    out = []
    idx = 0
    @c.eqns.each -> (eq)
      @e.reset
      @e.allow_auto = true
      params.each -> (p)
        @e.push_local(p.name, p)
      lhs_ast = ast(:id, name, [])
      params.each -> (p)
        lhs_ast = ast(:app, "", [lhs_ast, ast(:id, p.name, [])])
      eq[0].each -> (p)
        lhs_ast = ast(:app, "", [lhs_ast, pat_to_expr(p)])
      lhs = @e.elab(lhs_ast)
      rhs = @e.elab(eq[1])
      @e.unify(@e.tyof(lhs), @e.tyof(rhs))
      @e.allow_auto = false
      eqn = @e.app2("=", lhs, rhs)
      eqn = @e.finalize(eqn, true)
      @e.check(eqn)
      e2 = dest_binop(eqn, "=")
      th = @s.eq_by_compute(e2[0], e2[1])
      vars = params + tm_frees(eqn).select ->(v) !params_has?(params, v)
      thg = @s.d.gen_all(vars, th)
      idx += 1
      @s.add_theorem(name + ".eq_" + idx.to_s, thg)
      out.push(thg)
    @s.set_eqns(name, out)
    out.each -> (t)
      @s.simp_rules.push(make_rule(@s.d, t, name))
    out

  -> pat_to_expr(p)
    if p.kind == :hole
      @hc = (@hc || 0) + 1
      return ast(:id, "hole" + @hc.to_s, [])
    p

-> params_has?(params, v)
  params.each -> (p)
    if p.name == v.name && ty_eq(p.ty, v.ty)
      return true
  false

+ Session
  -> set_eqns(name, eqs)
    @eqns[name] = eqs
