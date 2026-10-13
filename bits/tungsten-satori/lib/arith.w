# Linear arithmetic by Fourier-Motzkin elimination. Untrusted search; the
# result is a Farkas certificate checked by KKernel.farkas.

+ LinCon
  # Σ coef[v] * v + c0  (rel)  0   where rel ∈ :ge, :gt, :eq
  ro :coef, :c0, :rel, :deriv
  -> new(@coef, @c0, @rel, @deriv)

-> lin_combine(a, qa, b, qb)
  coef = {}
  a.coef.keys.each -> (v)
    coef[v] = q_mul(a.coef[v], qa)
  b.coef.keys.each -> (v)
    x = q_mul(b.coef[v], qb)
    if coef.has_key?(v)
      s = q_add(coef[v], x)
      if s[0] == 0
        coef.delete(v)
      else
        coef[v] = s
    elsif x[0] != 0
      coef[v] = x
  c0 = q_add(q_mul(a.c0, qa), q_mul(b.c0, qb))
  deriv = {}
  a.deriv.keys.each -> (i)
    deriv[i] = q_mul(a.deriv[i], qa)
  b.deriv.keys.each -> (i)
    x = q_mul(b.deriv[i], qb)
    if deriv.has_key?(i)
      deriv[i] = q_add(deriv[i], x)
    else
      deriv[i] = x
  rel = :ge
  if (a.rel == :gt && qa[0] > 0) || (b.rel == :gt && qb[0] > 0)
    rel = :gt
  if a.rel == :eq && b.rel == :eq
    rel = :eq
  LinCon.new(coef, c0, rel, deriv)

-> lin_contradiction?(c)
  if c.coef.size > 0
    return false
  if c.rel == :eq
    return c.c0[0] != 0
  if c.rel == :gt
    return c.c0[0] <= 0
  c.c0[0] < 0

# thms: comparison theorems at one type. Returns coefficient array or nil.
-> fm_certificate(thms, kind)
  ctx = RingCtx.new("rat")
  cons = []
  i = 0
  while i < thms.size
    th = thms[i]
    rel = nil
    ab = nil
    ["<", "≤", "="].each -> (r)
      if rel == nil
        d = dest_binop(th.concl, r)
        if d != nil
          rel = r
          ab = d
    pa = ring_norm(ab[0], kind, ctx)
    pb = ring_norm(ab[1], kind, ctx)
    diff = poly_add(pb, poly_scale(pa, [-1, 1]))
    coef = {}
    c0 = [0, 1]
    diff.keys.each -> (m)
      if m == ""
        c0 = diff[m]
      else
        coef[m] = diff[m]
    deriv = {}
    deriv[i] = [1, 1]
    r = :ge
    if rel == "<"
      r = :gt
    if rel == "="
      r = :eq
    cons.push(LinCon.new(coef, c0, r, deriv))
    i += 1
  res = fm_solve(cons, 0)
  if res == nil
    return lp_certificate(cons)
  out = []
  i = 0
  while i < thms.size
    if res.deriv.has_key?(i)
      out.push(res.deriv[i])
    else
      out.push([0, 1])
    i += 1
  # an equality-only contradiction with positive constant: flip sign
  if res.rel == :eq && res.c0[0] > 0
    j = 0
    while j < out.size
      out[j] = q_neg(out[j])
      j += 1
  out

-> fm_solve(cons, rounds)
  cons.each -> (c)
    if lin_contradiction?(c)
      return c
  if rounds > 12 || cons.size > 600
    return nil
  # choose a variable: prefer one appearing in an equality, else fewest products
  vars = {}
  cons.each -> (c)
    c.coef.keys.each -> (v)
      vars[v] = true
  if vars.size == 0
    return nil
  best = nil
  best_cost = 0
  vars.keys.sort.each -> (v)
    pos = 0
    neg = 0
    has_eq = false
    cons.each -> (c)
      if c.coef.has_key?(v)
        if c.rel == :eq
          has_eq = true
        if c.coef[v][0] > 0
          pos += 1
        else
          neg += 1
    cost = pos * neg
    if has_eq
      cost = -1
    if best == nil || cost < best_cost
      best = v
      best_cost = cost
  v = best
  eqc = nil
  cons.each -> (c)
    if eqc == nil && c.rel == :eq && c.coef.has_key?(v)
      eqc = c
  out = []
  if eqc != nil
    a = eqc.coef[v]
    cons.each -> (c)
      if !(c == eqc)
        if c.coef.has_key?(v)
          # c - (c_v / a) * eqc
          q = q_neg(q_div(c.coef[v], a))
          out.push(lin_combine(c, [1, 1], eqc, q))
        else
          out.push(c)
    return fm_solve(out, rounds + 1)
  pos = []
  neg = []
  cons.each -> (c)
    if c.coef.has_key?(v)
      if c.coef[v][0] > 0
        pos.push(c)
      else
        neg.push(c)
    else
      out.push(c)
  pos.each -> (p)
    neg.each -> (n)
      # p * (-n_v) + n * p_v eliminates v
      out.push(lin_combine(p, q_neg(n.coef[v]), n, p.coef[v]))
  fm_solve(out, rounds + 1)

# ---------------------------------------------------------------------------
# Complete fallback: the Farkas multipliers as a linear program, solved by an exact two-phase simplex (Bland's rule).
# Constraint i reads Σ coef·v + c0 (rel) 0. We look for weights y (≥ 0 on ≥/>, free on =) whose combination has no
# variables and a contradictory constant: Σ y c0 < 0, or = 0 with positive weight on a strict constraint. The kernel
# re-checks the weights (KKernel.farkas), so this search is untrusted.

-> q0()
  [0, 1]

-> q1()
  [1, 1]

# min c·x  s.t.  A x = b, x ≥ 0 (b ≥ 0). Returns [x, value] or nil (infeasible, or too many pivots).
-> simplex_min(a, b, c, nv)
  m = a.size
  ncol = nv + m
  t = []
  rhs = []
  basis = []
  i = 0
  while i < m
    row = []
    j = 0
    while j < nv
      row.push(a[i][j])
      j += 1
    k = 0
    while k < m
      if k == i
        row.push(q1())
      else
        row.push(q0())
      k += 1
    t.push(row)
    rhs.push(b[i])
    basis.push(nv + i)
    i += 1
  cost1 = []
  j = 0
  while j < ncol
    if j < nv
      cost1.push(q0())
    else
      cost1.push(q1())
    j += 1
  if !simplex_run(t, rhs, basis, cost1, ncol, ncol)
    return nil
  v1 = q0()
  i = 0
  while i < m
    v1 = q_add(v1, q_mul(cost1[basis[i]], rhs[i]))
    i += 1
  if v1[0] > 0
    return nil
  # drive zero-level artificials out of the basis where possible
  i = 0
  while i < m
    if basis[i] >= nv
      j = 0
      done = false
      while j < nv && !done
        if t[i][j][0] != 0
          simplex_pivot(t, rhs, basis, i, j, ncol)
          done = true
        j += 1
    i += 1
  cost2 = []
  j = 0
  while j < ncol
    if j < nv
      cost2.push(c[j])
    else
      cost2.push(q0())
    j += 1
  if !simplex_run(t, rhs, basis, cost2, ncol, nv)
    return nil
  x = []
  j = 0
  while j < nv
    x.push(q0())
    j += 1
  val = q0()
  i = 0
  while i < m
    if basis[i] < nv
      x[basis[i]] = rhs[i]
      val = q_add(val, q_mul(c[basis[i]], rhs[i]))
    i += 1
  [x, val]

-> simplex_pivot(t, rhs, basis, r, j, ncol)
  p = t[r][j]
  k = 0
  while k < ncol
    t[r][k] = q_div(t[r][k], p)
    k += 1
  rhs[r] = q_div(rhs[r], p)
  i = 0
  while i < t.size
    if i != r && t[i][j][0] != 0
      f = t[i][j]
      k = 0
      while k < ncol
        if t[r][k][0] != 0
          t[i][k] = q_sub(t[i][k], q_mul(f, t[r][k]))
        k += 1
      rhs[i] = q_sub(rhs[i], q_mul(f, rhs[r]))
    i += 1
  basis[r] = j
  0

# Bland's rule; columns ≥ allowed may not enter. Returns false when unbounded or out of pivots.
-> simplex_run(t, rhs, basis, cost, ncol, allowed)
  m = t.size
  iter = 0
  while iter < 5000
    iter += 1
    enter = -1
    j = 0
    while j < allowed && enter < 0
      inb = false
      i = 0
      while i < m
        if basis[i] == j
          inb = true
        i += 1
      if !inb
        rc = cost[j]
        i = 0
        while i < m
          if t[i][j][0] != 0
            rc = q_sub(rc, q_mul(cost[basis[i]], t[i][j]))
          i += 1
        if rc[0] < 0
          enter = j
      j += 1
    if enter < 0
      return true
    leave = -1
    best = nil
    i = 0
    while i < m
      if t[i][enter][0] > 0
        ratio = q_div(rhs[i], t[i][enter])
        if leave < 0
          leave = i
          best = ratio
        else
          cmpv = q_cmp(ratio, best)
          if cmpv < 0 || (cmpv == 0 && basis[i] < basis[leave])
            leave = i
            best = ratio
      i += 1
    if leave < 0
      return false
    simplex_pivot(t, rhs, basis, leave, enter, ncol)
  false

# cons: LinCon list. Returns per-constraint weights or nil.
-> lp_certificate(cons)
  atoms = {}
  cons.each -> (c)
    c.coef.keys.each -> (v)
      atoms[v] = true
  vlist = atoms.keys.sort
  # columns: one per ≥/> constraint, two (y⁺, y⁻) per equality
  colcon = []
  colsign = []
  i = 0
  while i < cons.size
    colcon.push(i)
    colsign.push(1)
    if cons[i].rel == :eq
      colcon.push(i)
      colsign.push(-1)
    i += 1
  nv = colcon.size
  rows = []
  b = []
  vlist.each -> (v)
    row = []
    j = 0
    while j < nv
      cf = cons[colcon[j]].coef[v]
      if cf == nil
        row.push(q0())
      elsif colsign[j] > 0
        row.push(cf)
      else
        row.push(q_neg(cf))
      j += 1
    rows.push(row)
    b.push(q0())
  norm = []
  j = 0
  while j < nv
    norm.push(q1())
    j += 1
  rows.push(norm)
  b.push(q1())
  c0 = []
  j = 0
  while j < nv
    k0 = cons[colcon[j]].c0
    if colsign[j] > 0
      c0.push(k0)
    else
      c0.push(q_neg(k0))
    j += 1
  res = simplex_min(rows, b, c0, nv)
  if res == nil
    return nil
  y = res[0]
  if res[1][0] >= 0
    # constant can only reach 0: maximise the weight on strict constraints with Σ y c0 = 0
    rows2 = rows + [c0]
    b2 = b + [q0()]
    cg = []
    j = 0
    while j < nv
      if cons[colcon[j]].rel == :gt
        cg.push([-1, 1])
      else
        cg.push(q0())
      j += 1
    res2 = simplex_min(rows2, b2, cg, nv)
    if res2 == nil || res2[1][0] >= 0
      return nil
    y = res2[0]
  w = []
  i = 0
  while i < cons.size
    w.push(q0())
    i += 1
  j = 0
  while j < nv
    if colsign[j] > 0
      w[colcon[j]] = q_add(w[colcon[j]], y[j])
    else
      w[colcon[j]] = q_sub(w[colcon[j]], y[j])
    j += 1
  w
