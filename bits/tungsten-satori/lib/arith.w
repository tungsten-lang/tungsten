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
    return nil
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
  if rounds > 12 || cons.size > 4000
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
