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

  # ∂f/∂p of a family at (x, p) by central differences over the maker.
  -> .family_fp(maker, p, x)
    hp = ~1.0e-6 * (~1.0 + Math.hypot(p, ~0.0))
    fp = maker.call(p + hp).f(~0.0, x)
    fm = maker.call(p - hp).f(~0.0, x)
    out = []
    i = 0
    while i < fp.size()
      out = out.push((fp[i] - fm[i]) / (~2.0 * hp))
      i = i + 1
    out

  # Pseudo-arclength continuation of an equilibrium branch — follows the
  # curve f(x, p) = 0 in (x, p) THROUGH folds, where the natural sweep
  # stalls. Tangent predictor (bordered solve against the previous
  # tangent, so orientation is preserved), Newton corrector on the
  # extended system with the arclength constraint, ds halving on
  # corrector failure. Returns {p:, x:, stability:, folds: [indices
  # where the tangent's p-component changes sign], complete: bool}.
  -> .continue_arclength(maker, p_start, x_guess, ds, nsteps)
    sys0 = maker.call(p_start)
    x = Dynamics.fixed_point_flow(sys0, x_guess)
    n = x.size()
    p = p_start
    ps = [p + ~0.0]
    xs = [Dynamics.vcopy(x)]
    cls = [Dynamics.classify_flow(sys0, x)]
    folds = []
    tang = []
    i = 0
    while i < n
      tang = tang.push(~0.0)
      i = i + 1
    tang = tang.push(~1.0)
    step = ds
    complete = true
    k = 0
    while k < nsteps
      sys = maker.call(p)
      j = sys.jac(~0.0, x)
      fpcol = Dynamics.family_fp(maker, p, x)
      big = []
      i = 0
      while i < n
        row = []
        c = 0
        while c < n
          row = row.push(j[i][c])
          c = c + 1
        row = row.push(fpcol[i])
        big = big.push(row)
        i = i + 1
      big = big.push(Dynamics.vcopy(tang))
      rhs = []
      i = 0
      while i < n
        rhs = rhs.push(~0.0)
        i = i + 1
      rhs = rhs.push(~1.0)
      newt = LinAlg.solve(big, rhs)
      tn = LinAlg.norm(newt)
      i = 0
      while i <= n
        newt[i] = newt[i] / tn
        i = i + 1
      if newt[n] * tang[n] < ~0.0 && k > 0
        folds = folds.push(ps.size() - 1)
      tang = newt
      # predictor
      xp = []
      i = 0
      while i < n
        xp = xp.push(x[i] + step * tang[i])
        i = i + 1
      pp = p + step * tang[n]
      # corrector: Newton on [f(x,p); tangᵀ·((x,p) − predictor)]
      ok = false
      attempt = 0
      while attempt < 2
        xc = Dynamics.vcopy(xp)
        pc = pp
        it = 0
        while it < 25
          sysc = maker.call(pc)
          fx = sysc.f(~0.0, xc)
          arc = ~0.0
          i = 0
          while i < n
            arc = arc + tang[i] * (xc[i] - xp[i])
            i = i + 1
          arc = arc + tang[n] * (pc - pp)
          rnorm = Math.hypot(Dynamics.vnorm(fx), arc)
          if rnorm < ~1.0e-10
            ok = true
            it = 25
          else
            jc = sysc.jac(~0.0, xc)
            fpc = Dynamics.family_fp(maker, pc, xc)
            bigc = []
            i = 0
            while i < n
              row = []
              c = 0
              while c < n
                row = row.push(jc[i][c])
                c = c + 1
              row = row.push(fpc[i])
              bigc = bigc.push(row)
              i = i + 1
            bigc = bigc.push(Dynamics.vcopy(tang))
            rhsc = []
            i = 0
            while i < n
              rhsc = rhsc.push(~0.0 - fx[i])
              i = i + 1
            rhsc = rhsc.push(~0.0 - arc)
            dc = LinAlg.solve(bigc, rhsc)
            i = 0
            while i < n
              xc[i] = xc[i] + dc[i]
              i = i + 1
            pc = pc + dc[n]
            it = it + 1
        if ok
          attempt = 2
        else
          step = step * ~0.5
          i = 0
          while i < n
            xp[i] = x[i] + step * tang[i]
            i = i + 1
          pp = p + step * tang[n]
          attempt = attempt + 1
      if ok
        x = xc
        p = pc
        ps = ps.push(p)
        xs = xs.push(Dynamics.vcopy(x))
        cls = cls.push(Dynamics.classify_flow(maker.call(p), x))
        if step * ~1.5 < ds * ~2.0
          step = step * ~1.5
        k = k + 1
      else
        complete = false
        k = nsteps
    {:p => ps, :x => xs, :stability => cls, :folds => folds, :complete => complete}

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

  # Multiple shooting: the period splits into m segments with node
  # states x_0..x_{m−1} and unknown T, Newton-solving
  #   φ_{T/m}(x_i) − x_{i+1 mod m} = 0     (m·n equations)
  #   f(x_0)·δx_0 = 0                       (phase row)
  # with the segment monodromies filling the block Jacobian. More robust
  # than single shooting on stiff or long orbits; Floquet multipliers
  # come from the ordered product M_{m−1}···M_0. Returns the same hash
  # as shoot_periodic plus :nodes.
  -> .shoot_periodic_multi(sys, x0_guess, t_guess, dt, m)
    n = x0_guess.size()
    seg0 = t_guess / m
    steps0 = (seg0 / dt).to_i
    if steps0 < 10
      steps0 = 10
    nodes = [Dynamics.vcopy(x0_guess)]
    xw = Dynamics.vcopy(x0_guess)
    i = 1
    while i < m
      xw = Dynamics.advance(sys, xw, ~0.0, steps0, seg0 / steps0)
      nodes = nodes.push(Dynamics.vcopy(xw))
      i = i + 1
    period = t_guess
    collapsed = false
    it = 0
    while it < 40
      seg = period / m
      steps = (seg / dt).to_i
      if steps < 10
        steps = 10
      ends = []
      mons = []
      si = 0
      while si < m
        pair = Dynamics.monodromy(sys, nodes[si], seg, steps)
        ends = ends.push(pair[0])
        mons = mons.push(pair[1])
        si = si + 1
      total = ~0.0
      si = 0
      while si < m
        nxt = (si + 1) % m
        rvec = Dynamics.vsub(ends[si], nodes[nxt])
        rn = Dynamics.vnorm(rvec)
        total = total + rn * rn
        si = si + 1
      total = Math.sqrt(total)
      if total < ~1.0e-10
        prod = mons[0]
        si = 1
        while si < m
          prod = LinAlg.matmul(mons[si], prod)
          si = si + 1
        mults = LinAlg.eigenvalues(prod)
        return {:x => nodes[0], :period => period, :multipliers => mults, :residual => total, :nodes => nodes}
      dim = m * n + 1
      big = LinAlg.zeros(dim, dim)
      rhs = []
      i = 0
      while i < dim
        rhs = rhs.push(~0.0)
        i = i + 1
      si = 0
      while si < m
        nxt = (si + 1) % m
        fe = sys.f(~0.0, ends[si])
        r = 0
        while r < n
          c = 0
          while c < n
            big[si * n + r][si * n + c] = big[si * n + r][si * n + c] + mons[si][r][c]
            c = c + 1
          big[si * n + r][nxt * n + r] = big[si * n + r][nxt * n + r] - ~1.0
          big[si * n + r][dim - 1] = fe[r] / m
          rhs[si * n + r] = nodes[nxt][r] - ends[si][r]
          r = r + 1
        si = si + 1
      f0 = sys.f(~0.0, nodes[0])
      c = 0
      while c < n
        big[dim - 1][c] = f0[c]
        c = c + 1
      delta = LinAlg.solve(big, rhs)
      damp = ~1.0
      dtd = delta[dim - 1]
      if dtd < ~0.0
        dtd = ~0.0 - dtd
      if dtd > period * ~0.2
        damp = period * ~0.2 / dtd
      si = 0
      while si < m
        r = 0
        while r < n
          nodes[si][r] = nodes[si][r] + damp * delta[si * n + r]
          r = r + 1
        si = si + 1
      period = period + damp * delta[dim - 1]
      if period < dt * ~10.0
        collapsed = true
        it = 40
      else
        it = it + 1
    if collapsed
      raise "Dynamics.shoot_periodic_multi: period collapsed — bad initial guess"
    raise "Dynamics.shoot_periodic_multi: no convergence"

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
