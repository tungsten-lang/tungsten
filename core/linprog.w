# LinProg — dense linear programming by the two-phase simplex method.
#
#   r = LinProg.maximize(c, a, b)          # maximize cᵀx  s.t.  A x ≤ b,  x ≥ 0
#   r[:status]   # :optimal | :infeasible | :unbounded
#   r[:x], r[:value]
#
# `c` has n entries, `a` is an array of m rows of n entries, `b` has m entries
# (any signs). Bland's rule (smallest improving index, smallest leaving basis
# index) guarantees termination; tolerances are absolute, 1e-11. Meant for the
# small and medium dense problems of local optimization (sequential linear
# programming), not for large sparse models.

+ LinProg
  -> .maximize(c, a, b)
    n = c.size
    m = b.size
    # columns: n originals, m slacks, 1 auxiliary, then the right-hand side
    w = n + m + 2
    t = f64[(m + 1) * w]
    basis = i64[m + 1]
    i = 0
    while i < m
      row = a[i]
      j = 0
      while j < n
        t[i * w + j] = ~1.0 * row[j]
        j += 1
      t[i * w + n + i] = ~1.0
      t[i * w + n + m] = ~-1.0
      t[i * w + w - 1] = ~1.0 * b[i]
      basis[i] = n + i
      i += 1
    # phase 1 if some b < 0: maximize −aux
    worst = -1
    wv = ~0.0
    i = 0
    while i < m
      if t[i * w + w - 1] < wv
        wv = t[i * w + w - 1]
        worst = i
      i += 1
    allowed = i64[w]
    j = 0
    while j < w - 1
      allowed[j] = 1
      j += 1
    if worst >= 0
      j = 0
      while j < w
        t[m * w + j] = ~0.0
        j += 1
      t[m * w + n + m] = ~1.0
      linprog_pivot(t, m + 1, w, worst, n + m)
      basis[worst] = n + m
      st = linprog_run(t, m, w, basis, allowed)
      if st != 0 || t[m * w + w - 1] < ~-1.0e-9
        return {:status => :infeasible, :x => nil, :value => nil}
      # drive the auxiliary variable out of the basis
      i = 0
      while i < m
        if basis[i] == n + m
          j = 0
          piv = -1
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
    # phase 2 objective row: −c, reduced against the current basis
    j = 0
    while j < w
      t[m * w + j] = ~0.0
      j += 1
    j = 0
    while j < n
      t[m * w + j] = ~0.0 - c[j]
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
      return {:status => :unbounded, :x => nil, :value => nil}
    x = []
    j = 0
    while j < n
      x.push(~0.0)
      j += 1
    i = 0
    while i < m
      if basis[i] < n
        x[basis[i]] = t[i * w + w - 1]
      i += 1
    {:status => :optimal, :x => x, :value => t[m * w + w - 1]}

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

# simplex iterations with Bland's rule; 0 = optimal, 1 = unbounded
-> linprog_run(t, m, w, basis, allowed) (f64[] i64 i64 i64[] i64[]) i64
  iter = 0
  while iter < 1000000
    col = -1
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
