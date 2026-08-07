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
# Solve.rk45_dense returns a DenseSolution: the continuous solution,
# sampled anywhere in range via the method's free order-4 interpolant
# (`sol.at(t)` / `sol.at_many(ts)`), SciPy dense_output analogue.
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
    r = Solve.rk45_run(f, t_start, t_stop, y0, dt0, rtol, atol, false)
    {:t => r[:t], :y => r[:y]}

  # Dense-output DP5(4): same integration, but every accepted step also
  # keeps its size and seven stage slopes, which feed the method's free
  # order-4 interpolant. Returns a DenseSolution — `sol.at(t)` samples
  # the continuous solution anywhere in [t_start, t_stop].
  -> .rk45_dense(f, t_start, t_stop, y0, dt0, rtol = ~1.0e-6, atol = ~1.0e-9)
    r = Solve.rk45_run(f, t_start, t_stop, y0, dt0, rtol, atol, true)
    DenseSolution.new(r[:t], r[:y], r[:h], r[:k])

  -> .rk45_run(f, t_start, t_stop, y0, dt0, rtol, atol, record)
    t = t_start
    y = Solve.clone_y(y0)
    h = dt0
    ts = [t]
    ys = [Solve.clone_y(y)]
    hs = []
    ks = []
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
        if record
          hs = hs.push(h)
          ks = ks.push([k1, k2, k3, k4, k5, k6, k7])
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
    {:t => ts, :y => ys, :h => hs, :k => ks}

# Continuous DP5(4) solution. Each accepted step keeps its size and the
# seven stage slopes; sampling evaluates the method's free order-4
# interpolant bᵢ(θ) (the classical P-matrix continuous extension, whose
# θ=1 row sums are exactly the 5th-order weights, so `at(t_stop)`
# reproduces the discrete endpoint).
+ DenseSolution
  -> new(@ts, @ys, @hs, @ks)
    self

  -> t_start
    @ts.first

  -> t_stop
    @ts.last

  -> size
    @ts.size()

  # Solution vector at time tq (raises outside the integrated range).
  -> at(tq)
    n = @ts.size()
    if tq < @ts.first - ~1.0e-12 || tq > @ts.last + ~1.0e-12
      raise "DenseSolution.at: time outside the integrated range"
    lo = 0
    hi = n - 1
    while hi - lo > 1
      mid = (lo + hi) / 2
      if @ts[mid] <= tq
        lo = mid
      else
        hi = mid
    h = @hs[lo]
    theta = ~0.0
    if h != ~0.0
      theta = (tq - @ts[lo]) / h
    if theta < ~0.0
      theta = ~0.0
    if theta > ~1.0
      theta = ~1.0
    p12 = ~0.0 - ~8048581381.0 / ~2820520608.0
    p13 = ~8663915743.0 / ~2820520608.0
    p14 = ~0.0 - ~12715105075.0 / ~11282082432.0
    p32 = ~131558114200.0 / ~32700410799.0
    p33 = ~0.0 - ~68118460800.0 / ~10900136933.0
    p34 = ~87487479700.0 / ~32700410799.0
    p42 = ~0.0 - ~1754552775.0 / ~470086768.0
    p43 = ~14199869525.0 / ~1410260304.0
    p44 = ~0.0 - ~10690763975.0 / ~1880347072.0
    p52 = ~127303824393.0 / ~49829197408.0
    p53 = ~0.0 - ~318862633887.0 / ~49829197408.0
    p54 = ~701980252875.0 / ~199316789632.0
    p62 = ~0.0 - ~282668133.0 / ~205662961.0
    p63 = ~2019193451.0 / ~616988883.0
    p64 = ~0.0 - ~1453857185.0 / ~822651844.0
    p72 = ~40617522.0 / ~29380423.0
    p73 = ~0.0 - ~110615467.0 / ~29380423.0
    p74 = ~69997945.0 / ~29380423.0
    th2 = theta * theta
    b1 = theta * (~1.0 + theta * (p12 + theta * (p13 + theta * p14)))
    b3 = th2 * (p32 + theta * (p33 + theta * p34))
    b4 = th2 * (p42 + theta * (p43 + theta * p44))
    b5 = th2 * (p52 + theta * (p53 + theta * p54))
    b6 = th2 * (p62 + theta * (p63 + theta * p64))
    b7 = th2 * (p72 + theta * (p73 + theta * p74))
    kk = @ks[lo]
    base = @ys[lo]
    out = []
    i = 0
    while i < base.size()
      s = b1 * kk[0][i] + b3 * kk[2][i] + b4 * kk[3][i] + b5 * kk[4][i] + b6 * kk[5][i] + b7 * kk[6][i]
      out = out.push(base[i] + h * s)
      i = i + 1
    out

  # Sample many times at once: [at(t) for each t].
  -> at_many(tqs)
    out = []
    i = 0
    while i < tqs.size()
      out = out.push(at(tqs[i]))
      i = i + 1
    out
