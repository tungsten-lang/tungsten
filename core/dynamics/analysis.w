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

  # Return map of one coordinate over a point sequence:
  # [[v_k, v_{k+1}], …].
  -> .return_map(points, coord)
    out = []
    i = 0
    while i + 1 < points.size()
      out = out.push([points[i][coord], points[i + 1][coord]])
      i = i + 1
    out
