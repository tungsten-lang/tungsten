# Fixed points and linear stability. Newton iteration solves f(x) = 0
# (flows) or step(x) − x = 0 (maps) through LinAlg.solve; classification
# reads the Jacobian spectrum from LinAlg.eigenvalues.

+ Dynamics
  # Newton solve for a flow equilibrium near `guess` (autonomous: t = 0).
  -> .fixed_point_flow(sys, guess)
    x = Dynamics.vcopy(guess)
    it = 0
    while it < 60
      fx = sys.f(~0.0, x)
      if Dynamics.vnorm(fx) < ~1.0e-12
        return x
      j = sys.jac(~0.0, x)
      rhs = []
      i = 0
      while i < fx.size()
        rhs = rhs.push(~0.0 - fx[i])
        i = i + 1
      delta = LinAlg.solve(j, rhs)
      i = 0
      while i < x.size()
        x[i] = x[i] + delta[i]
        i = i + 1
      it = it + 1
    raise "Dynamics.fixed_point_flow: no convergence"

  # Newton solve for a map fixed point near `guess`.
  -> .fixed_point_map(msys, guess)
    x = Dynamics.vcopy(guess)
    it = 0
    while it < 60
      sx = msys.step(x)
      gx = Dynamics.vsub(sx, x)
      if Dynamics.vnorm(gx) < ~1.0e-12
        return x
      j = msys.jac(x)
      n = x.size()
      i = 0
      while i < n
        j[i][i] = j[i][i] - ~1.0
        i = i + 1
      rhs = []
      i = 0
      while i < n
        rhs = rhs.push(~0.0 - gx[i])
        i = i + 1
      delta = LinAlg.solve(j, rhs)
      i = 0
      while i < n
        x[i] = x[i] + delta[i]
        i = i + 1
      it = it + 1
    raise "Dynamics.fixed_point_map: no convergence"

  # Jacobian spectrum at a state: [[re, im], …].
  -> .eigenvalues_flow(sys, x)
    LinAlg.eigenvalues(sys.jac(~0.0, x))

  -> .eigenvalues_map(msys, x)
    LinAlg.eigenvalues(msys.jac(x))

  # Classify a flow equilibrium from its Jacobian spectrum:
  # :sink / :spiral_sink / :source / :spiral_source / :saddle /
  # :center (all eigenvalues on the imaginary axis, some rotation) /
  # :nonhyperbolic (a zero eigenvalue).
  -> .classify_flow(sys, x)
    eig = Dynamics.eigenvalues_flow(sys, x)
    Dynamics.classify_spectrum_flow(eig)

  -> .classify_spectrum_flow(eig)
    tol = ~1.0e-7
    neg = 0
    pos = 0
    zero = 0
    rot = false
    i = 0
    while i < eig.size()
      re = eig[i][0]
      im = eig[i][1]
      if im != ~0.0
        rot = true
      if re > tol
        pos = pos + 1
      elsif re < ~0.0 - tol
        neg = neg + 1
      else
        zero = zero + 1
      i = i + 1
    if zero > 0
      if pos == 0 && neg == 0 && rot
        return :center
      return :nonhyperbolic
    if pos > 0 && neg > 0
      return :saddle
    if pos > 0
      if rot
        return :spiral_source
      return :source
    if rot
      return :spiral_sink
    :sink

  # Classify a map fixed point by |λ| against 1:
  # :sink / :source / :saddle / :nonhyperbolic.
  -> .classify_map(msys, x)
    eig = Dynamics.eigenvalues_map(msys, x)
    tol = ~1.0e-7
    inside = 0
    outside = 0
    border = 0
    i = 0
    while i < eig.size()
      mag = Math.hypot(eig[i][0], eig[i][1])
      if mag > ~1.0 + tol
        outside = outside + 1
      elsif mag < ~1.0 - tol
        inside = inside + 1
      else
        border = border + 1
      i = i + 1
    if border > 0
      return :nonhyperbolic
    if outside > 0 && inside > 0
      return :saddle
    if outside > 0
      return :source
    :sink
