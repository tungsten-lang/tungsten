# Orbit analysis: bifurcation sweeps, period detection, Poincaré
# sections, and return maps.

+ Dynamics
  # Bifurcation sweep of a one-parameter map family. `maker` is a 1-arg
  # closure returning the map for a parameter value. For each of `nr`
  # parameters in [r0, r1], discards `transient` iterates and records
  # `samples` values of coordinate 0. Returns {r: [...], x: [...]} as
  # parallel arrays (one entry per recorded sample).
  -> .bifurcation(maker, r0, r1, nr, x0, transient, samples)
    rs = []
    xs = []
    k = 0
    while k < nr
      r = r0 + (r1 - r0) * k / (nr - 1)
      msys = maker.call(r)
      x = Dynamics.iterate(msys, x0, transient)
      s = 0
      while s < samples
        x = msys.step(x)
        rs = rs.push(r)
        xs = xs.push(x[0])
        s = s + 1
      k = k + 1
    {r: rs, x: xs}

  # Period of a map orbit after `transient` iterates: the smallest
  # p ≤ max_p with |x_{k+p} − x_k| < tol in every component; 0 when the
  # orbit does not close (quasi-periodic or chaotic at this resolution).
  -> .period(msys, x0, transient, max_p, tol)
    ref = Dynamics.iterate(msys, x0, transient)
    x = ref
    p = 1
    while p <= max_p
      x = msys.step(x)
      close = true
      i = 0
      while i < ref.size()
        d = x[i] - ref[i]
        if d < ~0.0
          d = ~0.0 - d
        if d >= tol
          close = false
        i = i + 1
      if close
        return p
      p = p + 1
    0

  # Poincaré section of a flow: states where g(x) = normal·x − c crosses
  # zero in the positive direction (g going − to +), located by secant
  # interpolation between RK4 steps. Discards `transient_t` first.
  # Returns {t: [...], points: [...]}.
  -> .poincare(sys, x0, normal, c, transient_t, run_t, dt)
    x = Dynamics.vcopy(x0)
    t = ~0.0
    nt = (transient_t / dt).to_i
    i = 0
    while i < nt
      x = Dynamics.rk4_step(sys, t, x, dt)
      t = t + dt
      i = i + 1
    ts = []
    pts = []
    g = LinAlg.dot(normal, x) - c
    total = (run_t / dt).to_i
    k = 0
    while k < total
      xn = Dynamics.rk4_step(sys, t, x, dt)
      tn = t + dt
      gn = LinAlg.dot(normal, xn) - c
      if g < ~0.0 && gn >= ~0.0
        frac = ~0.0
        if gn - g != ~0.0
          frac = (~0.0 - g) / (gn - g)
        pt = []
        i = 0
        while i < x.size()
          pt = pt.push(x[i] + (xn[i] - x[i]) * frac)
          i = i + 1
        ts = ts.push(t + dt * frac)
        pts = pts.push(pt)
      x = xn
      t = tn
      g = gn
      k = k + 1
    {t: ts, points: pts}

  # Period of a FORCED system's attractor in forcing cycles: strobe the
  # flow every `period` (the forcing period), discard `transient` cycles,
  # then find the smallest p ≤ max_p with |s_p − s_0| < tol. 0 = no
  # period at this resolution (chaos/quasiperiodicity).
  -> .stroboscopic_period(sys, x0, period, transient, max_p, tol, dt)
    steps = (period / dt).to_i
    if steps < 20
      steps = 20
    hh = period / steps
    x = Dynamics.vcopy(x0)
    t = ~0.0
    c = 0
    while c < transient
      x = Dynamics.advance(sys, x, t, steps, hh)
      t = t + period
      c = c + 1
    ref = Dynamics.vcopy(x)
    p = 1
    while p <= max_p
      x = Dynamics.advance(sys, x, t, steps, hh)
      t = t + period
      if Dynamics.vdist(x, ref) < tol
        return p
      p = p + 1
    0

  # Isoperiodic (period-count) diagram over a 2-parameter forced family:
  # maker2 is a 2-arg closure (a, b) → Flow, period_of a 2-arg closure
  # (a, b) → forcing period. Row-major rows[ib][ia] of stroboscopic
  # periods (0 = aperiodic). The GPU twin (hardcoded forced Duffing)
  # lives in doc/examples/gpu_isoperiodic.w.
  -> .isoperiodic_map(maker2, a_lo, a_hi, na, b_lo, b_hi, nb, x0, period_of, transient, max_p, tol, dt)
    rows = []
    ib = 0
    while ib < nb
      row = []
      ia = 0
      while ia < na
        av = a_lo + (a_hi - a_lo) * ia / (na - 1)
        bv = b_lo + (b_hi - b_lo) * ib / (nb - 1)
        sys = maker2.call(av, bv)
        pf = period_of.call(av, bv)
        row = row.push(Dynamics.stroboscopic_period(sys, x0, pf, transient, max_p, tol, dt))
        ia = ia + 1
      rows = rows.push(row)
      ib = ib + 1
    rows

  # Return map of one coordinate over a point sequence:
  # [[v_k, v_{k+1}], …].
  -> .return_map(points, coord)
    out = []
    i = 0
    while i + 1 < points.size()
      out = out.push([points[i][coord], points[i + 1][coord]])
      i = i + 1
    out
