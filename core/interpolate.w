# Interpolate — interpolation and numerical quadrature.
#
# Naming elsewhere:
#   SciPy     scipy.interpolate / scipy.integrate
#   MATLAB    interp1 / integral
#   Julia     Interpolations.jl / QuadGK.jl
#   R         stats::approx / integrate
#   NumPy     np.interp (1-D only)
#
# Tungsten: core/interpolate holds both (small surface). For heavy
# adaptive quadrature suites, prefer bits later; v0 is useful defaults.
#
#   Interpolate.linear(xs, ys, x)
#   Interpolate.lagrange(xs, ys, x)
#   Interpolate.spline_natural(xs, ys) → coeffs, then .spline_eval
#   Interpolate.trapz(ys, dx) / .trapz_x(xs, ys)
#   Interpolate.simpson(ys, dx)
#   Interpolate.quad(f, a, b, n)

+ Interpolate
  # ---- 1-D linear ----

  -> .linear(xs, ys, x)
    n = xs.size()
    if n == 0
      return ~0.0
    if x <= xs[0]
      return ys[0]
    if x >= xs[n - 1]
      return ys[n - 1]
    i = 0
    while i < n - 1
      if x >= xs[i] && x <= xs[i + 1]
        t = (x - xs[i]) / (xs[i + 1] - xs[i])
        return ys[i] * (~1.0 - t) + ys[i + 1] * t
      i = i + 1
    ys[n - 1]

  # ---- Lagrange (O(n²); fine for n ≲ 20) ----

  -> .lagrange(xs, ys, x)
    n = xs.size()
    s = ~0.0
    i = 0
    while i < n
      term = ys[i]
      j = 0
      while j < n
        if j != i
          term = term * (x - xs[j]) / (xs[i] - xs[j])
        j = j + 1
      s = s + term
      i = i + 1
    s

  # ---- Natural cubic spline ----
  # Returns [a, b, c, d] coefficient lists for segments (n-1 of each).
  # S_i(x) = a[i] + b[i](x-xs[i]) + c[i](x-xs[i])² + d[i](x-xs[i])³

  -> .spline_natural(xs, ys)
    n = xs.size()
    if n < 2
      raise "Interpolate.spline_natural: need ≥2 points"
    # h[i] = xs[i+1]-xs[i]
    h = []
    i = 0
    while i < n - 1
      h = h.push(xs[i + 1] - xs[i])
      i = i + 1
    # second derivatives via tridiagonal (natural: m0=mn=0)
    # solve for m[1..n-2]
    m = []
    i = 0
    while i < n
      m = m.push(~0.0)
      i = i + 1
    if n == 2
      a = [ys[0]]
      b = [(ys[1] - ys[0]) / h[0]]
      c = [~0.0]
      d = [~0.0]
      return {:xs => xs, :a => a, :b => b, :c => c, :d => d}
    # build system for interior
    nn = n - 2
    A = []
    rhs = []
    i = 0
    while i < nn
      row = []
      j = 0
      while j < nn
        row = row.push(~0.0)
        j = j + 1
      A = A.push(row)
      rhs = rhs.push(~0.0)
      i = i + 1
    i = 0
    while i < nn
      ii = i + 1  # actual index in m
      if i > 0
        A[i][i - 1] = h[ii - 1]
      A[i][i] = ~2.0 * (h[ii - 1] + h[ii])
      if i < nn - 1
        A[i][i + 1] = h[ii]
      rhs[i] = ~6.0 * ((ys[ii + 1] - ys[ii]) / h[ii] - (ys[ii] - ys[ii - 1]) / h[ii - 1])
      i = i + 1
    # Thomas algorithm
    cprime = []
    dprime = []
    i = 0
    while i < nn
      cprime = cprime.push(~0.0)
      dprime = dprime.push(~0.0)
      i = i + 1
    if nn > 1
      cprime[0] = A[0][1] / A[0][0]
    dprime[0] = rhs[0] / A[0][0]
    i = 1
    while i < nn
      denom = A[i][i] - A[i][i - 1] * cprime[i - 1]
      if i < nn - 1
        cprime[i] = A[i][i + 1] / denom
      dprime[i] = (rhs[i] - A[i][i - 1] * dprime[i - 1]) / denom
      i = i + 1
    # back sub
    sol = []
    i = 0
    while i < nn
      sol = sol.push(~0.0)
      i = i + 1
    sol[nn - 1] = dprime[nn - 1]
    i = nn - 2
    while i >= 0
      sol[i] = dprime[i] - cprime[i] * sol[i + 1]
      i = i - 1
    i = 0
    while i < nn
      m[i + 1] = sol[i]
      i = i + 1
    # coefficients
    a = []
    b = []
    c = []
    d = []
    i = 0
    while i < n - 1
      a = a.push(ys[i])
      b = b.push((ys[i + 1] - ys[i]) / h[i] - h[i] * (~2.0 * m[i] + m[i + 1]) / ~6.0)
      c = c.push(m[i] / ~2.0)
      d = d.push((m[i + 1] - m[i]) / (~6.0 * h[i]))
      i = i + 1
    {:xs => xs, :a => a, :b => b, :c => c, :d => d}

  -> .spline_eval(spl, x)
    xs = spl[:xs]
    n = xs.size()
    if x <= xs[0]
      i = 0
    elsif x >= xs[n - 1]
      i = n - 2
    else
      i = 0
      while i < n - 1
        if x >= xs[i] && x <= xs[i + 1]
          # found
          dx = x - xs[i]
          return spl[:a][i] + spl[:b][i] * dx + spl[:c][i] * dx * dx + spl[:d][i] * dx * dx * dx
        i = i + 1
      i = n - 2
    dx = x - xs[i]
    spl[:a][i] + spl[:b][i] * dx + spl[:c][i] * dx * dx + spl[:d][i] * dx * dx * dx

  # ---- quadrature ----

  -> .trapz(ys, dx)
    n = ys.size()
    if n < 2
      return ~0.0
    s = ~0.5 * (ys[0] + ys[n - 1])
    i = 1
    while i < n - 1
      s = s + ys[i]
      i = i + 1
    s * dx

  -> .trapz_x(xs, ys)
    n = xs.size()
    s = ~0.0
    i = 0
    while i < n - 1
      s = s + ~0.5 * (ys[i] + ys[i + 1]) * (xs[i + 1] - xs[i])
      i = i + 1
    s

  -> .simpson(ys, dx)
    n = ys.size()
    if n < 2
      return ~0.0
    if (n - 1) % 2 == 1
      # odd number of intervals required; fall back trapz on last
      return Interpolate.trapz(ys, dx)
    s = ys[0] + ys[n - 1]
    i = 1
    while i < n - 1
      if i % 2 == 1
        s = s + ~4.0 * ys[i]
      else
        s = s + ~2.0 * ys[i]
      i = i + 1
    s * dx / ~3.0

  # Composite trapezoid of f on [a,b] with n panels.
  -> .quad(f, a, b, n = 64)
    if n < 1
      n = 1
    h = (b - a) / (n + ~0.0)
    s = ~0.5 * (f(a) + f(b))
    i = 1
    while i < n
      s = s + f(a + h * (i + ~0.0))
      i = i + 1
    s * h
