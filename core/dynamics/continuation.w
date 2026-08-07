# Branch continuation and periodic-orbit shooting.
#
# Equilibrium branches follow a fixed point across a parameter sweep
# (secant predictor + the existing Newton corrector), recording the
# stability class at every point — the classification changes mark the
# bifurcations. Periodic orbits solve φ_T(x0) = x0 by single shooting
# on the monodromy matrix (the tangent flow over one period), with a
# bordered phase row for autonomous systems where T is unknown; Floquet
# multipliers come from the monodromy spectrum.

+ Dynamics
  # Follow an equilibrium of the 1-parameter family `maker` (a 1-arg
  # closure returning the Flow for a parameter value) from p0 to p1 in
  # np points. Secant predictor between accepted points. Stops early at
  # a fold/divergence (Newton failure). Returns
  # {p: [...], x: [states], stability: [symbols], complete: bool}.
  -> .continue_equilibria(maker, p0, p1, np, x_guess)
    ps = []
    xs = []
    cls = []
    complete = true
    stepp = (p1 - p0) / (np - 1)
    x = Dynamics.vcopy(x_guess)
    prev = nil
    k = 0
    while k < np
      p = p0 + stepp * k
      sys = maker.call(p)
      guess = Dynamics.vcopy(x)
      if prev != nil
        i = 0
        while i < guess.size()
          guess[i] = ~2.0 * x[i] - prev[i]
          i = i + 1
      xn = nil
      begin
        xn = Dynamics.fixed_point_flow(sys, guess)
      rescue err
        xn = nil
      if xn == nil
        complete = false
        k = np
      else
        ps = ps.push(p)
        xs = xs.push(xn)
        cls = cls.push(Dynamics.classify_flow(sys, xn))
        prev = x
        x = xn
        k = k + 1
    {:p => ps, :x => xs, :stability => cls, :complete => complete}

  # Parameter values where the stability class changes along a branch:
  # [[p_before, p_after, class_before, class_after], …].
  -> .stability_changes(branch)
    out = []
    cls = branch[:stability]
    ps = branch[:p]
    i = 1
    while i < cls.size()
      if cls[i] != cls[i - 1]
        out = out.push([ps[i - 1], ps[i], cls[i - 1], cls[i]])
      i = i + 1
    out

  # Monodromy matrix: the tangent flow of an autonomous system over
  # [0, period] from x0, integrated jointly with the state in `steps`
  # RK4 stages. Returns [x_at_period, M].
  -> .monodromy(sys, x0, period, steps)
    n = x0.size()
    x = Dynamics.vcopy(x0)
    v = LinAlg.eye(n)
    hh = period / steps
    t = ~0.0
    s = 0
    while s < steps
      pair = Dynamics.rk4_tangent_step(sys, t, x, v, hh)
      x = pair[0]
      v = pair[1]
      t = t + hh
      s = s + 1
    [x, v]

  # Single-shooting periodic orbit of an AUTONOMOUS flow: Newton on the
  # bordered system
  #   [ M − I      f(φ_T) ] [δx]   [ x0 − φ_T(x0) ]
  #   [ f(x0)ᵀ        0   ] [δT] = [      0        ]
  # where the phase row f(x0)·δx = 0 pins the orbit parametrization.
  # dt sets the integration resolution (steps = period/dt, min 20).
  # Returns {x: x0, period: T, multipliers: [[re, im]…], residual: r}.
  # The multiplier spectrum always contains the trivial +1.
  -> .shoot_periodic(sys, x0_guess, t_guess, dt)
    n = x0_guess.size()
    x0 = Dynamics.vcopy(x0_guess)
    period = t_guess
    it = 0
    while it < 40
      steps = (period / dt).to_i
      if steps < 20
        steps = 20
      pair = Dynamics.monodromy(sys, x0, period, steps)
      x_end = pair[0]
      m = pair[1]
      res = Dynamics.vsub(x_end, x0)
      rn = Dynamics.vnorm(res)
      if rn < ~1.0e-10
        mults = LinAlg.eigenvalues(m)
        return {:x => x0, :period => period, :multipliers => mults, :residual => rn}
      f_end = sys.f(~0.0, x_end)
      f0 = sys.f(~0.0, x0)
      big = []
      rhs = []
      i = 0
      while i < n
        row = []
        j = 0
        while j < n
          e = m[i][j]
          if i == j
            e = e - ~1.0
          row = row.push(e)
          j = j + 1
        row = row.push(f_end[i])
        big = big.push(row)
        rhs = rhs.push(~0.0 - res[i])
        i = i + 1
      prow = []
      j = 0
      while j < n
        prow = prow.push(f0[j])
        j = j + 1
      prow = prow.push(~0.0)
      big = big.push(prow)
      rhs = rhs.push(~0.0)
      delta = LinAlg.solve(big, rhs)
      i = 0
      while i < n
        x0[i] = x0[i] + delta[i]
        i = i + 1
      period = period + delta[n]
      if period < dt * ~20.0
        raise "Dynamics.shoot_periodic: period collapsed — bad initial guess"
      it = it + 1
    raise "Dynamics.shoot_periodic: no convergence"

  # Single-shooting for a FORCED (non-autonomous) system with known
  # period T (e.g. the forcing period): Newton on (M − I)δx = −res.
  # Returns {x: x0, period: T, multipliers: [[re, im]…], residual: r}.
  -> .shoot_forced(sys, x0_guess, period, dt)
    n = x0_guess.size()
    x0 = Dynamics.vcopy(x0_guess)
    steps = (period / dt).to_i
    if steps < 20
      steps = 20
    it = 0
    while it < 40
      pair = Dynamics.monodromy(sys, x0, period, steps)
      x_end = pair[0]
      m = pair[1]
      res = Dynamics.vsub(x_end, x0)
      rn = Dynamics.vnorm(res)
      if rn < ~1.0e-10
        mults = LinAlg.eigenvalues(m)
        return {:x => x0, :period => period, :multipliers => mults, :residual => rn}
      big = []
      rhs = []
      i = 0
      while i < n
        row = []
        j = 0
        while j < n
          e = m[i][j]
          if i == j
            e = e - ~1.0
          row = row.push(e)
          j = j + 1
        big = big.push(row)
        rhs = rhs.push(~0.0 - res[i])
        i = i + 1
      delta = LinAlg.solve(big, rhs)
      i = 0
      while i < n
        x0[i] = x0[i] + delta[i]
        i = i + 1
      it = it + 1
    raise "Dynamics.shoot_forced: no convergence"
