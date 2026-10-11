# LinProg — dense linear programming by the two-phase simplex method.
#
#   r = LinProg.maximize(c, a, b)          # maximize cᵀx  s.t.  A x ≤ b,  x ≥ 0
#   r[:status]   # :optimal | :infeasible | :unbounded | :unreliable
#   r[:x], r[:value]
#
# `c` has n entries, `a` is an array of m rows of n entries, `b` has m entries
# (any signs). Rows and then columns are equilibrated (scaled to unit maximum)
# before pivoting. Dantzig's rule, switching to Bland's rule after many pivots so
# that degenerate cycling cannot occur; tolerances 1e-11 on the scaled tableau.
# Every "optimal" point is re-checked against the original, unscaled constraints
# (relative tolerance 1e-7); a point that fails is reported as unreliable (status 3)
# rather than optimal: round-off in a dense tableau can otherwise end at an
# infeasible vertex on degenerate, badly scaled problems.
#
# Allocation-free use in hot loops (Tungsten has no garbage collector):
#   ws = LinProg.workspace(mmax, nmax)     # [t, basis, allowed, x]
#   st = linprog_solve(a_flat, b, c, m, n, ws[0], ws[1], ws[2], ws[3])
# with a_flat row-major m×n (f64[]), status 0 optimal, 1 unbounded, 2 infeasible,
# 3 numerically unreliable, the solution in ws[3][0..n−1] and the optimum returned by
# linprog_value(ws[0], m, n).

+ LinProg
  -> .workspace(mmax, nmax)
    w = nmax + mmax + 2
    [f64[(mmax + 1) * w], i64[mmax + 1], i64[w], f64[nmax]]

  -> .maximize(c, a, b)
    n = c.size
    m = b.size
    ws = LinProg.workspace(m, n)
    af = f64[m * n + 1]
    bf = f64[m + 1]
    cf = f64[n + 1]
    i = 0
    while i < m
      row = a[i]
      j = 0
      while j < n
        af[i * n + j] = ~1.0 * row[j]
        j += 1
      bf[i] = ~1.0 * b[i]
      i += 1
    j = 0
    while j < n
      cf[j] = ~1.0 * c[j]
      j += 1
    st = linprog_solve(af, bf, cf, m, n, ws[0], ws[1], ws[2], ws[3])
    if st == 2
      return {:status => :infeasible, :x => nil, :value => nil}
    if st == 1
      return {:status => :unbounded, :x => nil, :value => nil}
    if st == 3
      return {:status => :unreliable, :x => nil, :value => nil}
    x = []
    j = 0
    while j < n
      x.push(ws[3][j])
      j += 1
    {:status => :optimal, :x => x, :value => linprog_value(ws[0], m, n)}

-> linprog_value(t, m, n) (f64[] i64 i64) f64
  w = n + m + 2
  t[m * w + w - 1]

-> linprog_solve(a, b, c, m, n, t, basis, allowed, x) (f64[] f64[] f64[] i64 i64 f64[] i64[] i64[] f64[]) i64
  w = n + m + 2
  i = 0
  while i <= m
    j = 0
    while j < w
      t[i * w + j] = ~0.0
      j += 1
    i += 1
  # equilibration: each row scaled to unit maximum (the slack absorbs the factor), then
  # each column; the column factors wait in x[0..n−1] until the solution is read off
  i = 0
  while i < m
    rmax = ~0.0
    j = 0
    while j < n
      v = a[i * n + j]
      if v < ~0.0
        v = ~0.0 - v
      if v > rmax
        rmax = v
      j += 1
    rs = ~1.0
    if rmax > ~0.0
      rs = ~1.0 / rmax
    j = 0
    while j < n
      t[i * w + j] = a[i * n + j] * rs
      j += 1
    t[i * w + n + i] = ~1.0
    t[i * w + n + m] = ~-1.0
    t[i * w + w - 1] = b[i] * rs
    basis[i] = n + i
    i += 1
  j = 0
  while j < n
    cmax = ~0.0
    i = 0
    while i < m
      v = t[i * w + j]
      if v < ~0.0
        v = ~0.0 - v
      if v > cmax
        cmax = v
      i += 1
    cs = ~1.0
    if cmax > ~0.0
      cs = ~1.0 / cmax
    x[j] = cs
    i = 0
    while i < m
      t[i * w + j] = t[i * w + j] * cs
      i += 1
    j += 1
  j = 0
  while j < w - 1
    allowed[j] = 1
    j += 1
  worst = -1
  wv = ~0.0
  i = 0
  while i < m
    if t[i * w + w - 1] < wv
      wv = t[i * w + w - 1]
      worst = i
    i += 1
  if worst >= 0
    t[m * w + n + m] = ~1.0
    linprog_pivot(t, m + 1, w, worst, n + m)
    basis[worst] = n + m
    st = linprog_run(t, m, w, basis, allowed)
    if st != 0
      return 2
    if t[m * w + w - 1] < ~-1.0e-9
      return 2
    i = 0
    while i < m
      if basis[i] == n + m
        piv = -1
        j = 0
        while j < n + m && piv < 0
          v = t[i * w + j]
          if v > ~1.0e-11 || v < ~-1.0e-11
            piv = j
          j += 1
        if piv >= 0
          linprog_pivot(t, m + 1, w, i, piv)
          basis[i] = piv
      i += 1
  allowed[n + m] = 0
  i = 0
  while i <= m
    t[i * w + n + m] = ~0.0
    i += 1
  j = 0
  while j < w
    t[m * w + j] = ~0.0
    j += 1
  j = 0
  while j < n
    t[m * w + j] = ~0.0 - c[j] * x[j]
    j += 1
  i = 0
  while i < m
    bj = basis[i]
    f = t[m * w + bj]
    if f != ~0.0
      j = 0
      while j < w
        t[m * w + j] = t[m * w + j] - f * t[i * w + j]
        j += 1
    i += 1
  st = linprog_run(t, m, w, basis, allowed)
  if st == 1
    return 1
  # undo the column scaling: x_j = s_j·x'_j
  i = 0
  while i < m
    if basis[i] < n
      t[i * w + w - 1] = t[i * w + w - 1] * x[basis[i]]
    i += 1
  j = 0
  while j < n
    x[j] = ~0.0
    j += 1
  i = 0
  while i < m
    if basis[i] < n
      x[basis[i]] = t[i * w + w - 1]
    i += 1
  linprog_check(a, b, m, n, x)

# 0 when x ≥ 0 and A x ≤ b hold up to a relative 1e-7, else 3 (unreliable)
-> linprog_check(a, b, m, n, x) (f64[] f64[] i64 i64 f64[]) i64
  xmax = ~0.0
  j = 0
  while j < n
    v = x[j]
    if v < ~0.0
      v = ~0.0 - v
    if v > xmax
      xmax = v
    j += 1
  j = 0
  while j < n
    if x[j] < ~-1.0e-7 * (~1.0 + xmax)
      return 3
    j += 1
  i = 0
  while i < m
    s = ~0.0
    mag = ~0.0
    j = 0
    while j < n
      p = a[i * n + j] * x[j]
      s = s + p
      if p < ~0.0
        p = ~0.0 - p
      mag = mag + p
      j += 1
    bb = b[i]
    if bb < ~0.0
      bb = ~0.0 - bb
    if s - b[i] > ~1.0e-7 * (~1.0 + bb + mag)
      return 3
    i += 1
  0

# pivot the tableau on (r, c): rows×w flat, last column the right-hand side
-> linprog_pivot(t, rows, w, r, c) (f64[] i64 i64 i64 i64) i64
  p = t[r * w + c]
  j = 0
  while j < w
    t[r * w + j] = t[r * w + j] / p
    j += 1
  i = 0
  while i < rows
    if i != r
      f = t[i * w + c]
      if f != ~0.0
        j = 0
        while j < w
          t[i * w + j] = t[i * w + j] - f * t[r * w + j]
          j += 1
    i += 1
  0

# simplex iterations: Dantzig's rule, then Bland's rule after 20·(m + w) pivots;
# 0 = optimal, 1 = unbounded
-> linprog_run(t, m, w, basis, allowed) (f64[] i64 i64 i64[] i64[]) i64
  iter = 0
  bland_after = 20 * (m + w)
  while iter < 1000000
    col = -1
    if iter < bland_after
      most = ~-1.0e-11
      j = 0
      while j < w - 1
        if allowed[j] == 1 && t[m * w + j] < most
          most = t[m * w + j]
          col = j
        j += 1
    else
      j = 0
      while j < w - 1 && col < 0
        if allowed[j] == 1 && t[m * w + j] < ~-1.0e-11
          col = j
        j += 1
    if col < 0
      return 0
    row = -1
    best = ~0.0
    i = 0
    while i < m
      v = t[i * w + col]
      if v > ~1.0e-11
        ratio = t[i * w + w - 1] / v
        if row < 0 || ratio < best - ~1.0e-12 || (ratio < best + ~1.0e-12 && basis[i] < basis[row])
          row = i
          best = ratio
      i += 1
    if row < 0
      return 1
    linprog_pivot(t, m + 1, w, row, col)
    basis[row] = col
    iter += 1
  0
