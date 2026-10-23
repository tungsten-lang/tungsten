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
    lo = 0
    hi = n - 1
    while hi - lo > 1
      mid = (lo + hi) >> 1
      if xs[mid] <= x
        lo = mid
      else
        hi = mid
    x_lo = xs[lo]
    t = (x - x_lo) / (xs[lo + 1] - x_lo)
    ys[lo] * (~1.0 - t) + ys[lo + 1] * t

  # ---- Lagrange (O(n²); fine for n ≲ 20) ----

  -> .lagrange(xs, ys, x)
    n = xs.size()
    s = ~0.0
    i = 0
    while i < n
      term = ys[i]
      xi = xs[i]
      j = 0
      while j < n
        if j != i
          xj = xs[j]
          term = term * (x - xj) / (xi - xj)
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
    if n == 2
      h0 = xs[1] - xs[0]
      return {:xs => xs, :a => [ys[0]], :b => [(ys[1] - ys[0]) / h0], :c => [~0.0], :d => [~0.0]}
    # h[i] = xs[i+1]-xs[i]
    h = f64[n - 1]
    yv = f64[n]
    xv_prev = xs[0]
    yv[0] = ys[0]
    i = 0
    while i < n - 1
      xv_next = xs[i + 1]
      h[i] = xv_next - xv_prev
      yv[i + 1] = ys[i + 1]
      xv_prev = xv_next
      i = i + 1
    # second derivatives via O(n) tridiagonal Thomas algorithm (natural: m[0]=m[n-1]=0)
    m = f64[n]
    nn = n - 2
    cprime = f64[nn]
    dprime = f64[nn]
    h0 = h[0]
    h1 = h[1]
    diag0 = ~2.0 * (h0 + h1)
    rhs0 = ~6.0 * ((yv[2] - yv[1]) / h1 - (yv[1] - yv[0]) / h0)
    if nn > 1
      cprime[0] = h1 / diag0
    dprime[0] = rhs0 / diag0
    i = 1
    while i < nn
      ii = i + 1
      h_prev = h[ii - 1]
      h_curr = h[ii]
      denom = ~2.0 * (h_prev + h_curr) - h_prev * cprime[i - 1]
      if i < nn - 1
        cprime[i] = h_curr / denom
      rhs_i = ~6.0 * ((yv[ii + 1] - yv[ii]) / h_curr - (yv[ii] - yv[ii - 1]) / h_prev)
      dprime[i] = (rhs_i - h_prev * dprime[i - 1]) / denom
      i = i + 1
    # back substitution directly into m[1..nn]
    m[nn] = dprime[nn - 1]
    i = nn - 2
    while i >= 0
      m[i + 1] = dprime[i] - cprime[i] * m[i + 2]
      i = i - 1
    # coefficients
    a = []
    b = []
    c = []
    d = []
    i = 0
    while i < n - 1
      hi = h[i]
      mi = m[i]
      mi1 = m[i + 1]
      yi = yv[i]
      a.push(yi)
      b.push((yv[i + 1] - yi) / hi - hi * (~2.0 * mi + mi1) / ~6.0)
      c.push(mi / ~2.0)
      d.push((mi1 - mi) / (~6.0 * hi))
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
      lo = 0
      hi = n - 1
      while hi - lo > 1
        mid = (lo + hi) >> 1
        if xs[mid] <= x
          lo = mid
        else
          hi = mid
      i = lo
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
