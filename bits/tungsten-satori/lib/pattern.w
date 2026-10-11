# Compiles pattern-matching definitions with structural recursion on one
# argument into recursor applications, then proves each equation by
# evaluation (both sides reduce to the same normal form).
#
#   def len : list α → ℕ
#     | [] => 0
#     | x :: xs => 1 + len xs
#
# Supported patterns: constructors applied to variables (`[]`, `x :: xs`,
# `node l v r`, `0`, `n + 1`, `succ n`), or a variable/`_` catch-all, in any
# position. Recursion is structural on the first position holding a
# constructor pattern; constructor patterns elsewhere become nested case
# splits (first matching equation wins).

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

  # The case for constructor `ct` at the recursion position r. Equations compatible
  # with ct (constructor ct or a variable at r) are kept in order. The remaining
  # positions and the constructor's own arguments form a pattern matrix that
  # match_tree compiles to nested (non-recursive) recursor applications; patterns may
  # nest (x :: y :: ys, (a, b), succ (succ n), [a, b]); the first matching equation wins.
  -> build_case(ct, r, others, other_tys, motive, fvar, params, arg_tys, rty)
    cname = ct[0]
    cargs = ct[1]
    eqs = []
    @c.eqns.each -> (eq)
      cl = classify_args(eq[0][r], rty)
      if cl == nil || cl[0] == cname
        eqs.push(eq)
    if eqs.size == 0
      fail("missing case for constructor " + cname)
    first_cl = classify_args(eqs[0][0][r], rty)
    ys = []
    i = 0
    while i < cargs.size
      nm = "y" + i.to_s
      if first_cl != nil && i < first_cl[1].size && first_cl[1][i].kind == :id && var_pattern?(first_cl[1][i])
        nm = first_cl[1][i].s
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
    while j < others.size
      nm = "§o" + j.to_s
      pat = eqs[0][0][others[j]]
      if eqs.size == 1 && pat.kind == :id
        nm = pat.s
      ovs.push(mk_var(nm, arg_tys[others[j]]))
      j += 1
    whole = mk_apps(mk_const_raw(cname_const(cname), ty_funs(cargs, rty)), ys)
    if cname == "zero"
      whole = mk_nat(0)
    # columns: the other argument positions, then the constructor's arguments
    cols = []
    ctys = []
    ovs.each -> (o)
      cols.push(o)
      ctys.push(o.ty)
    ys.each -> (y)
      cols.push(y)
      ctys.push(y.ty)
    rows = []
    envs = []
    eqs.each -> (eq)
      row = []
      others.each -> (oi)
        row.push(eq[0][oi])
      env = []
      cl = classify_args(eq[0][r], rty)
      if cl == nil
        pr = eq[0][r]
        if pr.kind == :id
          env.push([pr.s, whole])
        k = 0
        while k < ys.size
          row.push(ast(:hole, "_", []))
          k += 1
      else
        k = 0
        while k < ys.size
          if k < cl[1].size
            row.push(cl[1][k])
          else
            row.push(ast(:hole, "_", []))
          k += 1
      rows.push(row)
      envs.push(env)
    split = []
    cols.each -> (c)
      split.push(false)
    body = match_tree(eqs, rows, envs, cols, ctys, split, fvar, params, motive, other_tys, 0)
    # replace recursive calls  F params.. args..  with  ih_j others..
    body = replace_rec(body, fvar, params, r, others, ys, rec_idx, ihs)
    if tm_free_in?(fvar, body)
      fail("recursive call is not structural: recurse on a direct constructor argument (a call on a nested sub-pattern such as rest in x :: y :: rest needs a helper function)")
    inner = mk_lams(ovs, body)
    mk_lams(ys + ihs, inner)

  # Compile the pattern matrix: rows[k][c] is equation k's pattern for column c (term
  # cols[c] of type ctys[c]); split[c] marks columns already decomposed.
  -> match_tree(eqs, rows, envs, cols, ctys, split, fvar, params, motive, other_tys, depth)
    if eqs.size == 0
      fail("missing case in a nested pattern")
    res_ty = arg_tys_res(motive, other_tys)
    row = rows[0]
    col = -1
    c = 0
    while c < cols.size && col < 0
      if !split[c] && classify_args(row[c], ctys[c]) != nil
        col = c
      c += 1
    if col < 0
      return match_leaf(eqs[0], row, envs[0], cols, split, fvar, params, res_ty)
    cty = ctys[col]
    cases = []
    ctor_table(cty).each -> (ct)
      zs = []
      zihs = []
      i = 0
      while i < ct[1].size
        zs.push(mk_var("§z" + depth.to_s + "_" + i.to_s, ct[1][i]))
        if ty_eq(ct[1][i], cty)
          zihs.push(mk_var("§zih" + depth.to_s + "_" + i.to_s, res_ty))
        i += 1
      whole = mk_apps(mk_const_raw(cname_const(ct[0]), ty_funs(ct[1], cty)), zs)
      if ct[0] == "zero"
        whole = mk_nat(0)
      eqs2 = []
      rows2 = []
      envs2 = []
      k = 0
      while k < eqs.size
        p = rows[k][col]
        cl = classify_args(p, cty)
        if cl == nil || cl[0] == ct[0]
          env = []
          envs[k].each -> (bb)
            env.push(bb)
          nrow = []
          rows[k].each -> (q)
            nrow.push(q)
          if cl == nil
            if p.kind == :id
              env.push([p.s, whole])
            i = 0
            while i < zs.size
              nrow.push(ast(:hole, "_", []))
              i += 1
          else
            i = 0
            while i < zs.size
              if i < cl[1].size
                nrow.push(cl[1][i])
              else
                nrow.push(ast(:hole, "_", []))
              i += 1
          eqs2.push(eqs[k])
          rows2.push(nrow)
          envs2.push(env)
        k += 1
      cols2 = []
      ctys2 = []
      split2 = []
      j = 0
      while j < cols.size
        cols2.push(cols[j])
        ctys2.push(ctys[j])
        split2.push(split[j] || j == col)
        j += 1
      i = 0
      while i < zs.size
        cols2.push(zs[i])
        ctys2.push(ct[1][i])
        split2.push(false)
        i += 1
      sub = match_tree(eqs2, rows2, envs2, cols2, ctys2, split2, fvar, params, motive, other_tys, depth + 1)
      cases.push(mk_lams(zs + zihs, sub))
    rec2 = recursor(cty, res_ty, cases.size)
    mk_app(mk_apps(rec2, cases), cols[col])

  -> match_leaf(eq, row, env, cols, split, fvar, params, res_ty)
    @e.reset
    params.each -> (p)
      @e.push_local(p.name, p)
    @e.push_local(@c.name, fvar)
    env.each -> (b)
      @e.push_local(b[0], b[1])
    j = 0
    while j < cols.size
      if !split[j]
        p = row[j]
        if p.kind == :id
          @e.push_local(p.s, cols[j])
      j += 1
    body = @e.elab(eq[1])
    @e.unify(@e.tyof(body), res_ty)
    @e.finalize(body, false)

  # Like classify, but returns the argument patterns themselves (which may nest):
  # nil for a variable or `_`, else [constructor name, [argument patterns]].
  -> classify_args(p, rty)
    if p.kind == :hole || (p.kind == :id && !@k.ctor_of.has_key?(p.s) && !(p.s == "zero" && rty.tag == :c && rty.name == "nat"))
      return nil
    if rty.tag == :c && rty.name == "nat"
      if p.kind == :num
        v = p.s.to_i
        if v == 0
          return ["zero", []]
        return ["succ", [ast(:num, (v - 1).to_s, [])]]
      if p.kind == :binop && p.s == "+" && p.kids[1].kind == :num
        v = p.kids[1].s.to_i
        if v == 1
          return ["succ", [p.kids[0]]]
        if v > 1
          return ["succ", [ast(:binop, "+", [p.kids[0], ast(:num, (v - 1).to_s, [])])]]
      if p.kind == :app && p.kids[0].kind == :id && p.kids[0].s == "succ"
        return ["succ", [p.kids[1]]]
      if p.kind == :id && p.s == "zero"
        return ["zero", []]
      fail("unsupported ℕ pattern (use 0, n + 1, succ n or a literal)")
    if p.kind == :list
      if p.kids.size == 0
        return ["nil", []]
      return ["cons", [p.kids[0], ast(:list, "", arr_sub(p.kids, 1, p.kids.size - 1))]]
    if p.kind == :binop && p.s == "::"
      return ["cons", [p.kids[0], p.kids[1]]]
    if p.kind == :tuple && p.kids.size == 2
      return ["pair", [p.kids[0], p.kids[1]]]
    if p.kind == :id
      return [p.s, []]
    if p.kind == :app
      sp = @e.ast_spine(p)
      return [sp[0].s, sp[1]]
    fail("unsupported pattern")

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
      pnames = []
      eq[0].each -> (p)
        pat_names(p, pnames)
      @e.set_auto_names(pnames)
      lhs_ast = ast(:id, name, [])
      params.each -> (p)
        lhs_ast = ast(:app, "", [lhs_ast, ast(:id, p.name, [])])
      eq[0].each -> (p)
        lhs_ast = ast(:app, "", [lhs_ast, pat_to_expr(p)])
      lhs = @e.elab(lhs_ast)
      rhs = @e.elab(eq[1])
      @e.unify(@e.tyof(lhs), @e.tyof(rhs))
      @e.allow_auto = false
      @e.clear_auto_names
      eqn = @e.app2("=", lhs, rhs)
      eqn = @e.finalize(eqn, true)
      @e.check(eqn)
      e2 = dest_binop(eqn, "=")
      th = nil
      begin
        th = @s.eq_by_compute(e2[0], e2[1])
      rescue err
        # a catch-all equation after more specific ones (| xs => …) holds only on the
        # inputs the earlier equations miss, so it is not an unconditional lemma: skip it
        if idx == 0 || !has_var_column?(eq)
          raise err
        th = nil
      idx += 1
      if th != nil
        vars = params + tm_frees(eqn).select ->(v) !params_has?(params, v)
        thg = @s.d.gen_all(vars, th)
        @s.add_theorem(name + ".eq_" + idx.to_s, thg)
        out.push(thg)
    @s.set_eqns(name, out)
    out.each -> (t)
      @s.simp_rules.push(make_rule(@s.d, t, name))
    out

  # does some argument of this equation use a variable or `_` pattern?
  -> has_var_column?(eq)
    eq[0].each -> (p)
      if p.kind == :hole || (p.kind == :id && var_pattern?(p))
        return true
    false

  # variable names bound by a pattern (identifiers that are not constructors or constants)
  -> pat_names(p, out)
    if p.kind == :id
      if !@k.has_const?(p.s) && !@k.ctor_of.has_key?(p.s)
        out.push(p.s)
      return out
    if p.kids != nil
      p.kids.each -> (q)
        pat_names(q, out)
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
