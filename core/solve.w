# Solve — initial-value ODE solvers (SciPy solve_ivp analogue).
#
#     result = Solve.ivp(f, t_span, y0, method: :rk45, dt: ~0.01)
#     # f(t, y) → y'   where y is a list of Floats
#
# Methods:
#   :euler   — forward Euler (debug)
#   :rk4     — classical 4th-order Runge–Kutta
#   :rk45    — adaptive Dormand–Prince 5(4), FSAL, embedded error control
#
# Lives in core/solve (not core/ode): matches SciPy's `solve_ivp` naming and
# leaves room for BVP / DAE later without a rename.

+ Solve
  -> .ivp(f, t_start, t_stop, y0, method = :rk4, dt = ~0.01)
    if method == :euler
      return Solve.euler(f, t_start, t_stop, y0, dt)
    if method == :rk45
      return Solve.rk45(f, t_start, t_stop, y0, dt)
    Solve.rk4(f, t_start, t_stop, y0, dt)

  -> .clone_y(y)
    out = []
    i = 0
    while i < y.size()
      out = out.push(y[i] + ~0.0)
      i = i + 1
    out

  -> .axpy(a, x, y)
    # y + a*x
    out = []
    i = 0
    while i < y.size()
      out = out.push(y[i] + a * x[i])
      i = i + 1
    out

  -> .euler(f, t_start, t_stop, y0, dt)
    t = t_start
    y = Solve.clone_y(y0)
    ts = [t]
    ys = [Solve.clone_y(y)]
    while t < t_stop
      h = dt
      if t + h > t_stop
        h = t_stop - t
      dy = f(t, y)
      y = Solve.axpy(h, dy, y)
      t = t + h
      ts = ts.push(t)
      ys = ys.push(Solve.clone_y(y))
    {:t => ts, :y => ys}

  -> .rk4_step(f, t, y, h)
    k1 = f(t, y)
    y2 = Solve.axpy(h / ~2.0, k1, y)
    k2 = f(t + h / ~2.0, y2)
    y3 = Solve.axpy(h / ~2.0, k2, y)
    k3 = f(t + h / ~2.0, y3)
    y4 = Solve.axpy(h, k3, y)
    k4 = f(t + h, y4)
    out = []
    i = 0
    while i < y.size()
      out = out.push(y[i] + (h / ~6.0) * (k1[i] + ~2.0 * k2[i] + ~2.0 * k3[i] + k4[i]))
      i = i + 1
    out

  -> .rk4(f, t_start, t_stop, y0, dt)
    t = t_start
    y = Solve.clone_y(y0)
    ts = [t]
    ys = [Solve.clone_y(y)]
    while t < t_stop
      h = dt
      if t + h > t_stop
        h = t_stop - t
      y = Solve.rk4_step(f, t, y, h)
      t = t + h
      ts = ts.push(t)
      ys = ys.push(Solve.clone_y(y))
    {:t => ts, :y => ys}

  # y + h·Σ coefs[j]·ks[j], fresh array — one DP stage combination.
  -> .comb(y, h, coefs, ks)
    out = []
    i = 0
    while i < y.size()
      s = ~0.0
      j = 0
      while j < coefs.size()
        s = s + coefs[j] * ks[j][i]
        j = j + 1
      out = out.push(y[i] + h * s)
      i = i + 1
    out

  # Adaptive Dormand-Prince 5(4): the classical DP tableau with the FSAL
  # property (the 7th stage of an accepted step is the next step's k1),
  # embedded 4th-order error control, and 0.2×..5× step adaptation at
  # safety 0.9. Error is scaled per component by atol + rtol·|y|.
  -> .rk45(f, t_start, t_stop, y0, dt0, rtol = ~1.0e-6, atol = ~1.0e-9)
    t = t_start
    y = Solve.clone_y(y0)
    h = dt0
    ts = [t]
    ys = [Solve.clone_y(y)]
    safety = ~0.9
    a21 = ~1.0 / ~5.0
    a31 = ~3.0 / ~40.0
    a32 = ~9.0 / ~40.0
    a41 = ~44.0 / ~45.0
    a42 = ~0.0 - ~56.0 / ~15.0
    a43 = ~32.0 / ~9.0
    a51 = ~19372.0 / ~6561.0
    a52 = ~0.0 - ~25360.0 / ~2187.0
    a53 = ~64448.0 / ~6561.0
    a54 = ~0.0 - ~212.0 / ~729.0
    a61 = ~9017.0 / ~3168.0
    a62 = ~0.0 - ~355.0 / ~33.0
    a63 = ~46732.0 / ~5247.0
    a64 = ~49.0 / ~176.0
    a65 = ~0.0 - ~5103.0 / ~18656.0
    a71 = ~35.0 / ~384.0
    a73 = ~500.0 / ~1113.0
    a74 = ~125.0 / ~192.0
    a75 = ~0.0 - ~2187.0 / ~6784.0
    a76 = ~11.0 / ~84.0
    e1 = ~71.0 / ~57600.0
    e3 = ~0.0 - ~71.0 / ~16695.0
    e4 = ~71.0 / ~1920.0
    e5 = ~0.0 - ~17253.0 / ~339200.0
    e6 = ~22.0 / ~525.0
    e7 = ~0.0 - ~1.0 / ~40.0
    k1 = f(t, y)
    while t < t_stop
      if t + h > t_stop
        h = t_stop - t
      k2 = f(t + h * a21, Solve.comb(y, h, [a21], [k1]))
      k3 = f(t + h * ~0.3, Solve.comb(y, h, [a31, a32], [k1, k2]))
      k4 = f(t + h * ~0.8, Solve.comb(y, h, [a41, a42, a43], [k1, k2, k3]))
      k5 = f(t + h * (~8.0 / ~9.0), Solve.comb(y, h, [a51, a52, a53, a54], [k1, k2, k3, k4]))
      k6 = f(t + h, Solve.comb(y, h, [a61, a62, a63, a64, a65], [k1, k2, k3, k4, k5]))
      y_new = Solve.comb(y, h, [a71, a73, a74, a75, a76], [k1, k3, k4, k5, k6])
      k7 = f(t + h, y_new)
      err = ~0.0
      i = 0
      while i < y.size()
        e = h * (e1 * k1[i] + e3 * k3[i] + e4 * k4[i] + e5 * k5[i] + e6 * k6[i] + e7 * k7[i])
        if e < ~0.0
          e = ~0.0 - e
        ay = y[i]
        if ay < ~0.0
          ay = ~0.0 - ay
        an = y_new[i]
        if an < ~0.0
          an = ~0.0 - an
        if an > ay
          ay = an
        r = e / (atol + rtol * ay)
        if r > err
          err = r
        i = i + 1
      if err <= ~1.0 || h < ~1.0e-12
        y = y_new
        k1 = k7
        t = t + h
        ts = ts.push(t)
        ys = ys.push(Solve.clone_y(y))
        if err < ~1.0e-10
          err = ~1.0e-10
        fac = safety * Math.pow(~1.0 / err, ~0.2)
        if fac > ~5.0
          fac = ~5.0
        if fac < ~0.2
          fac = ~0.2
        h = h * fac
      else
        fac = safety * Math.pow(~1.0 / err, ~0.2)
        if fac < ~0.2
          fac = ~0.2
        if fac > ~0.9
          fac = ~0.9
        h = h * fac
    {:t => ts, :y => ys}
