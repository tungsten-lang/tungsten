# Solve — initial-value ODE solvers (SciPy solve_ivp analogue).
#
#     result = Solve.ivp(f, t_span, y0, method: :rk45, dt: ~0.01)
#     # f(t, y) → y'   where y is a list of Floats
#
# Methods:
#   :euler   — forward Euler (debug)
#   :rk4     — classical 4th-order Runge–Kutta
#   :rk45    — adaptive Dormand–Prince 5(4) (simplified step control)
#
# Lives in core/solve (not core/ode): matches SciPy's `solve_ivp` naming and
# leaves room for BVP / DAE later without a rename.

+ Solve
  -> .ivp(f, t0, t1, y0, method = :rk4, dt = ~0.01)
    if method == :euler
      return Solve.euler(f, t0, t1, y0, dt)
    if method == :rk45
      return Solve.rk45(f, t0, t1, y0, dt)
    Solve.rk4(f, t0, t1, y0, dt)

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

  -> .euler(f, t0, t1, y0, dt)
    t = t0
    y = Solve.clone_y(y0)
    ts = [t]
    ys = [Solve.clone_y(y)]
    while t < t1
      h = dt
      if t + h > t1
        h = t1 - t
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

  -> .rk4(f, t0, t1, y0, dt)
    t = t0
    y = Solve.clone_y(y0)
    ts = [t]
    ys = [Solve.clone_y(y)]
    while t < t1
      h = dt
      if t + h > t1
        h = t1 - t
      y = Solve.rk4_step(f, t, y, h)
      t = t + h
      ts = ts.push(t)
      ys = ys.push(Solve.clone_y(y))
    {:t => ts, :y => ys}

  # Adaptive RK45 — Heun/Euler pair for step control (not full DP5, but
  # robust and dependency-free). Error estimate = ||y_heun − y_euler||.
  -> .rk45(f, t0, t1, y0, dt0)
    t = t0
    y = Solve.clone_y(y0)
    h = dt0
    ts = [t]
    ys = [Solve.clone_y(y)]
    atol = ~1.0e-6
    rtol = ~1.0e-4
    safety = ~0.9
    while t < t1
      if t + h > t1
        h = t1 - t
      k1 = f(t, y)
      y_eu = Solve.axpy(h, k1, y)
      k2 = f(t + h, y_eu)
      # Heun
      y_h = []
      i = 0
      while i < y.size()
        y_h = y_h.push(y[i] + ~0.5 * h * (k1[i] + k2[i]))
        i = i + 1
      # error
      err = ~0.0
      i = 0
      while i < y.size()
        e = y_h[i] - y_eu[i]
        if e < ~0.0
          e = ~0.0 - e
        ay = y[i]
        if ay < ~0.0
          ay = ~0.0 - ay
        scale = atol + rtol * ay
        r = e / scale
        if r > err
          err = r
        i = i + 1
      if err <= ~1.0 || h < ~1.0e-12
        y = y_h
        t = t + h
        ts = ts.push(t)
        ys = ys.push(Solve.clone_y(y))
        # grow step
        if err < ~1.0e-8
          err = ~1.0e-8
        fac = safety * Math.pow(~1.0 / err, ~0.2)
        if fac > ~2.0
          fac = ~2.0
        if fac < ~0.5
          fac = ~0.5
        h = h * fac
      else
        fac = safety * Math.pow(~1.0 / err, ~0.25)
        if fac < ~0.2
          fac = ~0.2
        if fac > ~0.8
          fac = ~0.8
        h = h * fac
    {:t => ts, :y => ys}
