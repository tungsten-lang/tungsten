# Lyapunov exponents. The largest exponent uses Benettin's
# two-trajectory renormalization (no Jacobian needed); full spectra
# integrate the tangent matrix dV/dt = J(x)·V alongside the state and
# re-orthonormalize with LinAlg.qr, accumulating ln of R's diagonal.

+ Dynamics
  # nested-matrix y + a·x, fresh matrix
  -> .maxpy(y, a, x)
    out = []
    r = 0
    while r < y.size()
      row = []
      c = 0
      while c < y[r].size()
        row = row.push(y[r][c] + a * x[r][c])
        c = c + 1
      out = out.push(row)
      r = r + 1
    out

  # One RK4 step of the augmented system (x, V) with V' = J(t, x)·V.
  # Returns [x_next, v_next].
  -> .rk4_tangent_step(sys, t, x, v, h)
    hh = h * ~0.5
    k1x = sys.f(t, x)
    k1v = LinAlg.matmul(sys.jac(t, x), v)
    x2 = Dynamics.vaxpy(x, hh, k1x)
    v2 = Dynamics.maxpy(v, hh, k1v)
    k2x = sys.f(t + hh, x2)
    k2v = LinAlg.matmul(sys.jac(t + hh, x2), v2)
    x3 = Dynamics.vaxpy(x, hh, k2x)
    v3 = Dynamics.maxpy(v, hh, k2v)
    k3x = sys.f(t + hh, x3)
    k3v = LinAlg.matmul(sys.jac(t + hh, x3), v3)
    x4 = Dynamics.vaxpy(x, h, k3x)
    v4 = Dynamics.maxpy(v, h, k3v)
    k4x = sys.f(t + h, x4)
    k4v = LinAlg.matmul(sys.jac(t + h, x4), v4)
    xn = []
    i = 0
    while i < x.size()
      xn = xn.push(x[i] + (k1x[i] + ~2.0 * k2x[i] + ~2.0 * k3x[i] + k4x[i]) * (h / ~6.0))
      i = i + 1
    vn = []
    r = 0
    while r < v.size()
      row = []
      c = 0
      while c < v[r].size()
        row = row.push(v[r][c] + (k1v[r][c] + ~2.0 * k2v[r][c] + ~2.0 * k3v[r][c] + k4v[r][c]) * (h / ~6.0))
        c = c + 1
      vn = vn.push(row)
      r = r + 1
    [xn, vn]

  # Largest Lyapunov exponent of a flow (Benettin). Discards
  # `transient_t`, then runs `run_t`, renormalizing the companion
  # trajectory every 10 steps.
  -> .lyapunov_max(sys, x0, transient_t, run_t, dt)
    d0 = ~1.0e-8
    x = Dynamics.vcopy(x0)
    t = ~0.0
    nt = (transient_t / dt).to_i
    i = 0
    while i < nt
      x = Dynamics.rk4_step(sys, t, x, dt)
      t = t + dt
      i = i + 1
    y = Dynamics.vcopy(x)
    y[0] = y[0] + d0
    total = (run_t / dt).to_i
    blocks = total / 10
    sum = ~0.0
    b = 0
    while b < blocks
      s = 0
      while s < 10
        x = Dynamics.rk4_step(sys, t, x, dt)
        y = Dynamics.rk4_step(sys, t, y, dt)
        t = t + dt
        s = s + 1
      d = Dynamics.vdist(x, y)
      if d > ~0.0
        sum = sum + Math.log(d / d0)
        scale = d0 / d
        i = 0
        while i < x.size()
          y[i] = x[i] + (y[i] - x[i]) * scale
          i = i + 1
      b = b + 1
    sum / (blocks * 10 * dt)

  # Largest Lyapunov exponent of a map via the tangent vector.
  -> .lyapunov_max_map(msys, x0, transient, n)
    x = Dynamics.iterate(msys, x0, transient)
    v = []
    i = 0
    while i < x.size()
      v = v.push(~0.0)
      i = i + 1
    v[0] = ~1.0
    sum = ~0.0
    k = 0
    while k < n
      v = LinAlg.mat_vec(msys.jac(x), v)
      nv = Dynamics.vnorm(v)
      if nv > ~0.0
        sum = sum + Math.log(nv)
        i = 0
        while i < v.size()
          v[i] = v[i] / nv
          i = i + 1
      x = msys.step(x)
      k = k + 1
    sum / n

  # Full Lyapunov spectrum of a flow: `renorms` QR renormalizations of
  # `steps_per` RK4 tangent steps each. Returns exponents ordered as the
  # tangent basis converges (descending in practice).
  -> .lyapunov_spectrum(sys, x0, transient_t, renorms, steps_per, dt)
    n = x0.size()
    x = Dynamics.vcopy(x0)
    t = ~0.0
    nt = (transient_t / dt).to_i
    i = 0
    while i < nt
      x = Dynamics.rk4_step(sys, t, x, dt)
      t = t + dt
      i = i + 1
    v = LinAlg.eye(n)
    sums = []
    i = 0
    while i < n
      sums = sums.push(~0.0)
      i = i + 1
    r = 0
    while r < renorms
      s = 0
      while s < steps_per
        pair = Dynamics.rk4_tangent_step(sys, t, x, v, dt)
        x = pair[0]
        v = pair[1]
        t = t + dt
        s = s + 1
      qr = LinAlg.qr(v)
      v = qr[0]
      i = 0
      while i < n
        rii = qr[1][i][i]
        if rii > ~0.0
          sums[i] = sums[i] + Math.log(rii)
        i = i + 1
      r = r + 1
    span = renorms * steps_per * dt
    out = []
    i = 0
    while i < n
      out = out.push(sums[i] / span)
      i = i + 1
    out

  # Full Lyapunov spectrum of a map (QR each step).
  -> .lyapunov_spectrum_map(msys, x0, transient, n)
    x = Dynamics.iterate(msys, x0, transient)
    d = x.size()
    v = LinAlg.eye(d)
    sums = []
    i = 0
    while i < d
      sums = sums.push(~0.0)
      i = i + 1
    k = 0
    while k < n
      v = LinAlg.matmul(msys.jac(x), v)
      qr = LinAlg.qr(v)
      v = qr[0]
      i = 0
      while i < d
        rii = qr[1][i][i]
        if rii > ~0.0
          sums[i] = sums[i] + Math.log(rii)
        i = i + 1
      x = msys.step(x)
      k = k + 1
    out = []
    i = 0
    while i < d
      out = out.push(sums[i] / n)
      i = i + 1
    out

  # Kaplan-Yorke (Lyapunov) dimension from a spectrum.
  -> .kaplan_yorke(spectrum)
    s = spectrum.sort.reverse
    cum = ~0.0
    k = 0
    while k < s.size()
      if cum + s[k] < ~0.0
        break
      cum = cum + s[k]
      k = k + 1
    if k >= s.size()
      return k + ~0.0
    if k == 0
      return ~0.0
    mag = s[k]
    if mag < ~0.0
      mag = ~0.0 - mag
    k + cum / mag
