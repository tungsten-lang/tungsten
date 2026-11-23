# Linear arithmetic by Fourier-Motzkin elimination. Untrusted search; the
# result is a Farkas certificate checked by KKernel.farkas.

+ LinCon
  # Σ coef[v] * v + c0  (rel)  0   where rel ∈ :ge, :gt, :eq
  ro :coef, :c0, :rel, :deriv
  -> new(@coef, @c0, @rel, @deriv)

-> lin_combine(a, qa, b, qb)
  coef = {}
  a.coef.each -> (v, cv)
    coef[v] = q_mul(cv, qa)
  b.coef.each -> (v, cv)
    x = q_mul(cv, qb)
    prev = coef[v]
    if prev != nil
      s = q_add(prev, x)
      if s[0] == 0
        coef.delete(v)
      else
        coef[v] = s
    elsif x[0] != 0
      coef[v] = x
  c0 = q_add(q_mul(a.c0, qa), q_mul(b.c0, qb))
  deriv = {}
  a.deriv.each -> (i, dv)
    deriv[i] = q_mul(dv, qa)
  b.deriv.each -> (i, dv)
    x = q_mul(dv, qb)
    prev_d = deriv[i]
    if prev_d != nil
      deriv[i] = q_add(prev_d, x)
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

# Extracts [rel_str, lhs, rhs] for <, ≤, = without intermediate arrays.
-> dest_cmp_rel(t)
  if t.tag == :app && t.a.tag == :app && t.a.a.tag == :const
    op = t.a.a.op
    if op == OP_LT
      return ["<", t.a.b, t.b]
    if op == OP_LE
      return ["≤", t.a.b, t.b]
    if op == OP_EQ
      return ["=", t.a.b, t.b]
  nil

# thms: comparison theorems at one type. Returns coefficient array or nil.
-> fm_certificate(thms, kind)
  ctx = RingCtx.new("rat")
  n = thms.size
  cons = Array.new(n)
  i = 0
  while i < n
    th = thms[i]
    cmp = dest_cmp_rel(th.concl)
    rel = cmp[0]
    pa = ring_norm(cmp[1], kind, ctx)
    pb = ring_norm(cmp[2], kind, ctx)
    diff = poly_add(pb, poly_scale(pa, Q_NEG_ONE))
    coef = {}
    c0 = Q_ZERO
    diff.each -> (m, qv)
      if m == 0
        c0 = qv
      else
        coef[m] = qv
    deriv = {}
    deriv[i] = Q_ONE
    r = :ge
    if rel == "<"
      r = :gt
    elsif rel == "="
      r = :eq
    cons[i] = LinCon.new(coef, c0, r, deriv)
    i += 1
  res = fm_solve(cons, 0)
  if res == :limit
    return lp_certificate(cons)
  if res == nil
    return nil
  out = Array.new(n)
  i = 0
  while i < n
    dv = res.deriv[i]
    if dv != nil
      out[i] = dv
    else
      out[i] = Q_ZERO
    i += 1
  # an equality-only contradiction with positive constant: flip sign
  if res.rel == :eq && res.c0[0] > 0
    j = 0
    while j < n
      out[j] = q_neg(out[j])
      j += 1
  out

# A contradictory row carries its derivation. No variables left means
# the rational constraints are feasible. Only a cutoff needs simplex.
-> fm_solve(cons, rounds)
  nc = cons.size
  ci = 0
  while ci < nc
    if lin_contradiction?(cons[ci])
      return cons[ci]
    ci += 1
  if rounds > 12 || nc > 600
    return :limit
  # Single pass over sparse nonzeros to count pos/neg/equality occurrences per variable.
  pos_cnt = {}
  neg_cnt = {}
  eq_vars = {}
  vars = {}
  ci = 0
  while ci < nc
    c = cons[ci]
    is_eq = c.rel == :eq
    c.coef.each -> (v, qv)
      vars[v] = true
      if is_eq
        eq_vars[v] = true
      if qv[0] > 0
        p = pos_cnt[v]
        pos_cnt[v] = p == nil ? 1 : p + 1
      else
        ng = neg_cnt[v]
        neg_cnt[v] = ng == nil ? 1 : ng + 1
    ci += 1
  if vars.size == 0
    return nil
  best = nil
  best_cost = 0
  vkeys = vars.keys.sort
  vk_len = vkeys.size
  vi = 0
  while vi < vk_len
    v = vkeys[vi]
    cost = 0
    if eq_vars.has_key?(v)
      cost = -1
    else
      pc = pos_cnt[v] || 0
      nc2 = neg_cnt[v] || 0
      cost = pc * nc2
    if best == nil || cost < best_cost
      best = v
      best_cost = cost
      if cost == -1
        break
    vi += 1
  v = best
  eqc = nil
  if eq_vars.has_key?(v)
    ci = 0
    while ci < nc
      c = cons[ci]
      if c.rel == :eq && c.coef.has_key?(v)
        eqc = c
        break
      ci += 1
  out = []
  if eqc != nil
    a = eqc.coef[v]
    ci = 0
    while ci < nc
      c = cons[ci]
      if !(c == eqc)
        cv = c.coef[v]
        if cv != nil
          # c - (c_v / a) * eqc
          q = q_neg(q_div(cv, a))
          out.push(lin_combine(c, Q_ONE, eqc, q))
        else
          out.push(c)
      ci += 1
    return fm_solve(out, rounds + 1)
  pos = []
  neg = []
  ci = 0
  while ci < nc
    c = cons[ci]
    cv = c.coef[v]
    if cv != nil
      if cv[0] > 0
        pos.push(c)
      else
        neg.push(c)
    else
      out.push(c)
    ci += 1
  np = pos.size
  nn = neg.size
  pi = 0
  while pi < np
    p = pos[pi]
    pv = p.coef[v]
    ni = 0
    while ni < nn
      n = neg[ni]
      out.push(lin_combine(p, q_neg(n.coef[v]), n, pv))
      ni += 1
    pi += 1
  fm_solve(out, rounds + 1)

# ---------------------------------------------------------------------------
# Complete fallback: the Farkas multipliers as a linear program, solved by an exact two-phase simplex (Bland's rule).

-> q0()
  Q_ZERO

-> q1()
  Q_ONE

-> simplex_init_rc(t, basis, cost, ncol)
  m = t.size
  rc = Array.new(ncol)
  j = 0
  while j < ncol
    rc[j] = cost[j]
    j += 1
  i = 0
  while i < m
    cb = cost[basis[i]]
    if cb[0] != 0
      row = t[i]
      k = 0
      while k < ncol
        rk = row[k]
        if rk[0] != 0
          rc[k] = q_sub(rc[k], q_mul(cb, rk))
        k += 1
    i += 1
  i = 0
  while i < m
    rc[basis[i]] = Q_ZERO
    i += 1
  rc

# min c·x  s.t.  A x = b, x ≥ 0 (b ≥ 0). Returns [x, value] or nil (infeasible, or too many pivots).
-> simplex_min(a, b, c, nv)
  m = a.size
  ncol = nv + m
  t = Array.new(m)
  rhs = Array.new(m)
  basis = Array.new(m)
  in_basis = Array.new(ncol, false)
  i = 0
  while i < m
    row = Array.new(ncol, Q_ZERO)
    ai = a[i]
    j = 0
    while j < nv
      row[j] = ai[j]
      j += 1
    row[nv + i] = Q_ONE
    t[i] = row
    rhs[i] = b[i]
    basis[i] = nv + i
    in_basis[nv + i] = true
    i += 1
  cost1 = Array.new(ncol, Q_ZERO)
  j = nv
  while j < ncol
    cost1[j] = Q_ONE
    j += 1
  if !simplex_run(t, rhs, basis, in_basis, cost1, ncol, ncol)
    return nil
  v1 = Q_ZERO
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
      row_i = t[i]
      j = 0
      while j < nv
        if row_i[j][0] != 0
          simplex_pivot(t, rhs, basis, in_basis, nil, i, j, ncol)
          break
        j += 1
    i += 1
  cost2 = Array.new(ncol, Q_ZERO)
  j = 0
  while j < nv
    cost2[j] = c[j]
    j += 1
  if !simplex_run(t, rhs, basis, in_basis, cost2, ncol, nv)
    return nil
  x = Array.new(nv, Q_ZERO)
  val = Q_ZERO
  i = 0
  while i < m
    bi = basis[i]
    if bi < nv
      x[bi] = rhs[i]
      val = q_add(val, q_mul(c[bi], rhs[i]))
    i += 1
  [x, val]

-> simplex_pivot(t, rhs, basis, in_basis, rc, r, j, ncol)
  row_r = t[r]
  p = row_r[j]
  nz_k = []
  nz_v = []
  if !(p[0] == 1 && p[1] == 1)
    inv_p = q_div(Q_ONE, p)
    k = 0
    while k < ncol
      rk = row_r[k]
      if rk[0] != 0
        nv = q_mul(rk, inv_p)
        row_r[k] = nv
        nz_k.push(k)
        nz_v.push(nv)
      k += 1
    if rhs[r][0] != 0
      rhs[r] = q_mul(rhs[r], inv_p)
  else
    k = 0
    while k < ncol
      rk = row_r[k]
      if rk[0] != 0
        nz_k.push(k)
        nz_v.push(rk)
      k += 1
  nnz = nz_k.size
  rhs_r = rhs[r]
  rhs_r_nz = rhs_r[0] != 0
  m = t.size
  i = 0
  while i < m
    if i != r
      row_i = t[i]
      f = row_i[j]
      if f[0] != 0
        idx = 0
        while idx < nnz
          col = nz_k[idx]
          row_i[col] = q_sub(row_i[col], q_mul(f, nz_v[idx]))
          idx += 1
        if rhs_r_nz
          rhs[i] = q_sub(rhs[i], q_mul(f, rhs_r))
    i += 1
  if rc != nil
    rcj = rc[j]
    if rcj[0] != 0
      idx = 0
      while idx < nnz
        col = nz_k[idx]
        rc[col] = q_sub(rc[col], q_mul(rcj, nz_v[idx]))
        idx += 1
      rc[j] = Q_ZERO
  old_b = basis[r]
  in_basis[old_b] = false
  basis[r] = j
  in_basis[j] = true
  0

# Bland's rule; columns ≥ allowed may not enter. Returns false when unbounded or out of pivots.
-> simplex_run(t, rhs, basis, in_basis, cost, ncol, allowed)
  m = t.size
  rc = simplex_init_rc(t, basis, cost, ncol)
  iter = 0
  while iter < 5000
    iter += 1
    enter = -1
    j = 0
    while j < allowed
      if !in_basis[j] && rc[j][0] < 0
        enter = j
        break
      j += 1
    if enter < 0
      return true
    leave = -1
    best = nil
    i = 0
    while i < m
      te = t[i][enter]
      if te[0] > 0
        ratio = q_div(rhs[i], te)
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
    simplex_pivot(t, rhs, basis, in_basis, rc, leave, enter, ncol)
  false

# cons: LinCon list. Returns per-constraint weights or nil.
-> lp_certificate(cons)
  atoms = {}
  nc = cons.size
  ci = 0
  while ci < nc
    cons[ci].coef.each -> (v, _qv)
      atoms[v] = true
    ci += 1
  vlist = atoms.keys.sort
  # columns: one per ≥/> constraint, two (y⁺, y⁻) per equality
  colcon = []
  colsign = []
  i = 0
  while i < nc
    colcon.push(i)
    colsign.push(1)
    if cons[i].rel == :eq
      colcon.push(i)
      colsign.push(-1)
    i += 1
  nv = colcon.size
  nv_vars = vlist.size
  rows = Array.new(nv_vars + 1)
  b = Array.new(nv_vars + 1, Q_ZERO)
  vi = 0
  while vi < nv_vars
    v = vlist[vi]
    row = Array.new(nv, Q_ZERO)
    j = 0
    while j < nv
      cf = cons[colcon[j]].coef[v]
      if cf != nil
        if colsign[j] > 0
          row[j] = cf
        else
          row[j] = q_neg(cf)
      j += 1
    rows[vi] = row
    vi += 1
  rows[nv_vars] = Array.new(nv, Q_ONE)
  b[nv_vars] = Q_ONE
  c0 = Array.new(nv)
  j = 0
  while j < nv
    k0 = cons[colcon[j]].c0
    if colsign[j] > 0
      c0[j] = k0
    else
      c0[j] = q_neg(k0)
    j += 1
  res = simplex_min(rows, b, c0, nv)
  if res == nil
    return nil
  y = res[0]
  if res[1][0] >= 0
    # constant can only reach 0: maximise the weight on strict constraints with Σ y c0 = 0
    rows2 = rows + [c0]
    b2 = b + [Q_ZERO]
    cg = Array.new(nv, Q_ZERO)
    j = 0
    while j < nv
      if cons[colcon[j]].rel == :gt
        cg[j] = Q_NEG_ONE
      j += 1
    res2 = simplex_min(rows2, b2, cg, nv)
    if res2 == nil || res2[1][0] >= 0
      return nil
    y = res2[0]
  w = Array.new(nc, Q_ZERO)
  j = 0
  while j < nv
    idx = colcon[j]
    if colsign[j] > 0
      w[idx] = q_add(w[idx], y[j])
    else
      w[idx] = q_sub(w[idx], y[j])
    j += 1
  w

# ---------------------------------------------------------------------------
# Integer Chvátal-Gomory cutting-plane search for ℕ and ℤ.
# Emits a DAG of [:comb, ...] and [:div, ...] steps checked by KKernel.int_farkas.

+ IntCon
  ro :coef, :c0, :rel, :row_id
  -> new(@coef, @c0, @rel, @row_id)

-> int_con_contradiction?(c)
  if c.coef.size > 0
    return false
  if c.rel == :eq
    return c.c0[0] != 0
  if c.rel == :gt
    return c.c0[0] <= 0
  c.c0[0] < 0

-> int_con_tighten(c, nth, steps)
  if c.coef.size == 0
    return c
  lcm_d = 1
  c.coef.each -> (_v, qv)
    if qv[1] > 1
      lcm_d = zmul(int_fdiv(lcm_d, int_gcd(lcm_d, qv[1])), qv[1])
  cur = c
  if lcm_d > 1
    q_sc = [lcm_d, 1]
    ncoef = {}
    cur.coef.each -> (v, qv)
      ncoef[v] = q_mul(qv, q_sc)
    nc0 = q_mul(cur.c0, q_sc)
    steps.push([:comb, [[cur.row_id, q_sc]]])
    cur = IntCon.new(ncoef, nc0, cur.rel, nth + steps.size - 1)
  g = 0
  cur.coef.each -> (_v, qv)
    av = qv[0] < 0 ? zsub(0, qv[0]) : qv[0]
    g = g == 0 ? av : int_gcd(g, av)
  if cur.rel == :eq
    if cur.c0[1] != 1 || int_fmod(cur.c0[0], g) != 0
      steps.push([:div, cur.row_id])
      return IntCon.new({}, Q_NEG_ONE, :ge, nth + steps.size - 1)
    if g > 1
      steps.push([:div, cur.row_id])
      dcoef = {}
      cur.coef.each -> (v, qv)
        dcoef[v] = [int_fdiv(qv[0], g), 1]
      dc0 = cur.c0[0] == 0 ? Q_ZERO : [int_fdiv(cur.c0[0], g), 1]
      return IntCon.new(dcoef, dc0, :eq, nth + steps.size - 1)
    return cur
  if g > 1 || cur.c0[1] > 1 || cur.rel == :gt
    steps.push([:div, cur.row_id])
    denom = zmul(cur.c0[1], g)
    num_adj = cur.rel == :gt ? zsub(cur.c0[0], 1) : cur.c0[0]
    fc = int_fdiv(num_adj, denom)
    dcoef = {}
    cur.coef.each -> (v, qv)
      dcoef[v] = [int_fdiv(qv[0], g), 1]
    dc0 = fc == 0 ? Q_ZERO : [fc, 1]
    return IntCon.new(dcoef, dc0, :ge, nth + steps.size - 1)
  cur

-> int_con_combine(a, qa, b, qb, nth, steps)
  coef = {}
  a.coef.each -> (v, cv)
    x = q_mul(cv, qa)
    if x[0] != 0
      coef[v] = x
  b.coef.each -> (v, cv)
    x = q_mul(cv, qb)
    prev = coef[v]
    if prev != nil
      s = q_add(prev, x)
      if s[0] == 0
        coef.delete(v)
      else
        coef[v] = s
    elsif x[0] != 0
      coef[v] = x
  c0 = q_add(q_mul(a.c0, qa), q_mul(b.c0, qb))
  rel = :ge
  if (a.rel == :gt && qa[0] > 0) || (b.rel == :gt && qb[0] > 0)
    rel = :gt
  if a.rel == :eq && b.rel == :eq
    rel = :eq
  steps.push([:comb, [[a.row_id, qa], [b.row_id, qb]]])
  raw = IntCon.new(coef, c0, rel, nth + steps.size - 1)
  int_con_tighten(raw, nth, steps)

-> int_fm_solve(cons, rounds, nth, steps)
  nc = cons.size
  ci = 0
  while ci < nc
    if int_con_contradiction?(cons[ci])
      return cons[ci]
    ci += 1
  if rounds > 12 || nc > 400
    return nil
  pos_cnt = {}
  neg_cnt = {}
  eq_vars = {}
  vars = {}
  ci = 0
  while ci < nc
    c = cons[ci]
    is_eq = c.rel == :eq
    c.coef.each -> (v, qv)
      vars[v] = true
      if is_eq && (eq_vars[v] == nil || qv[0].abs < eq_vars[v])
        eq_vars[v] = qv[0].abs
      if qv[0] > 0
        p = pos_cnt[v]
        pos_cnt[v] = p == nil ? 1 : p + 1
      else
        ng = neg_cnt[v]
        neg_cnt[v] = ng == nil ? 1 : ng + 1
    ci += 1
  if vars.size == 0
    return nil
  best = nil
  best_cost = 0
  vkeys = vars.keys.sort
  vi = 0
  while vi < vkeys.size
    v = vkeys[vi]
    cost = eq_vars.has_key?(v) ? (0 - 1000000 + eq_vars[v]) : ((pos_cnt[v] || 0) * (neg_cnt[v] || 0))
    if best == nil || cost < best_cost
      best = v
      best_cost = cost
    vi += 1
  v = best
  if eq_vars.has_key?(v)
    eqc = nil
    ci = 0
    while ci < nc
      c = cons[ci]
      if c.rel == :eq && c.coef.has_key?(v) && (eqc == nil || c.coef[v][0].abs < eqc.coef[v][0].abs)
        eqc = c
      ci += 1
    a = eqc.coef[v]
    out = []
    ci = 0
    while ci < nc
      c = cons[ci]
      if !(c == eqc)
        cv = c.coef[v]
        if cv != nil
          q = q_neg(q_div(cv, a))
          comb = int_con_combine(c, Q_ONE, eqc, q, nth, steps)
          if int_con_contradiction?(comb)
            return comb
          out.push(comb)
        else
          out.push(c)
      ci += 1
    return int_fm_solve(out, rounds + 1, nth, steps)
  pos = []
  neg = []
  out = []
  ci = 0
  while ci < nc
    c = cons[ci]
    cv = c.coef[v]
    if cv != nil
      if cv[0] > 0
        pos.push(c)
      else
        neg.push(c)
    else
      out.push(c)
    ci += 1
  pi = 0
  while pi < pos.size
    p = pos[pi]
    pv = p.coef[v]
    ni = 0
    while ni < neg.size
      n = neg[ni]
      comb = int_con_combine(p, q_neg(n.coef[v]), n, pv, nth, steps)
      if int_con_contradiction?(comb)
        return comb
      out.push(comb)
      ni += 1
    pi += 1
  int_fm_solve(out, rounds + 1, nth, steps)

-> int_fm_certificate(thms, kind)
  if !(kind == "nat" || kind == "int")
    return nil
  ctx = RingCtx.new("int")
  nth = thms.size
  steps = []
  cons = Array.new(nth)
  i = 0
  while i < nth
    th = thms[i]
    cmp = dest_cmp_rel(th.concl)
    pa = ring_norm(cmp[1], kind, ctx)
    pb = ring_norm(cmp[2], kind, ctx)
    diff = poly_add(pb, poly_scale(pa, Q_NEG_ONE))
    coef = {}
    c0 = Q_ZERO
    diff.each -> (m, qv)
      if m == 0
        c0 = qv
      else
        coef[m] = qv
    r = cmp[0] == "<" ? :gt : (cmp[0] == "=" ? :eq : :ge)
    raw = IntCon.new(coef, c0, r, i)
    cons[i] = int_con_tighten(raw, nth, steps)
    if int_con_contradiction?(cons[i])
      res0 = cons[i]
      if res0.row_id < nth
        w0 = (res0.rel == :eq && res0.c0[0] > 0) ? Q_NEG_ONE : Q_ONE
        steps.push([:comb, [[res0.row_id, w0]]])
      return steps
    i += 1
  res = int_fm_solve(cons, 0, nth, steps)
  if res == nil
    return nil
  if res.row_id < nth
    w = (res.rel == :eq && res.c0[0] > 0) ? Q_NEG_ONE : Q_ONE
    steps.push([:comb, [[res.row_id, w]]])
  elsif res.row_id != nth + steps.size - 1
    steps.push([:comb, [[res.row_id, Q_ONE]]])
  steps
