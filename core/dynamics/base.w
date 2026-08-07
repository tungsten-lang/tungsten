# Dynamics — facade root and system contracts. First worker of
# core/dynamics (dispatch-shim role, per the module-split pattern):
# depends on no sibling worker.
#
# States are plain Arrays of ~f64 Floats. A continuous system (Flow)
# supplies `f(t, x) -> dx/dt`; a discrete system (MapSystem) supplies
# `step(x) -> next state`. Both carry `dim` and a Jacobian: the bases
# give central-difference defaults, and concrete systems override
# `jac` with analytic forms where they are cheap to write.

+ Dynamics
  # -- small dense-vector helpers (plain Arrays of Float) --

  -> .vcopy(x)
    out = []
    i = 0
    while i < x.size()
      out = out.push(x[i] + ~0.0)
      i = i + 1
    out

  # y + a·x, fresh array
  -> .vaxpy(y, a, x)
    out = []
    i = 0
    while i < y.size()
      out = out.push(y[i] + a * x[i])
      i = i + 1
    out

  -> .vsub(a, b)
    out = []
    i = 0
    while i < a.size()
      out = out.push(a[i] - b[i])
      i = i + 1
    out

  -> .vnorm(x)
    s = ~0.0
    i = 0
    while i < x.size()
      s = s + x[i] * x[i]
      i = i + 1
    Math.sqrt(s)

  -> .vdist(a, b)
    s = ~0.0
    i = 0
    while i < a.size()
      d = a[i] - b[i]
      s = s + d * d
      i = i + 1
    Math.sqrt(s)

  # Wrap an angle into [0, 2π) — circle maps and Poincaré phases.
  -> .wrap2pi(v)
    tau = ~6.283185307179586
    w = v
    while w >= tau
      w = w - tau
    while w < ~0.0
      w = w + tau
    w

  # -- central-difference Jacobians (rows ∂f_i/∂x_j) --

  -> .numjac_flow(sys, t, x)
    n = x.size()
    cols = []
    c = 0
    while c < n
      mag = x[c]
      if mag < ~0.0
        mag = ~0.0 - mag
      h = ~1.0e-6 * (~1.0 + mag)
      xp = Dynamics.vcopy(x)
      xp[c] = xp[c] + h
      xm = Dynamics.vcopy(x)
      xm[c] = xm[c] - h
      fp = sys.f(t, xp)
      fm = sys.f(t, xm)
      col = []
      r = 0
      while r < n
        col = col.push((fp[r] - fm[r]) / (~2.0 * h))
        r = r + 1
      cols = cols.push(col)
      c = c + 1
    out = []
    r = 0
    while r < n
      row = []
      c = 0
      while c < n
        row = row.push(cols[c][r])
        c = c + 1
      out = out.push(row)
      r = r + 1
    out

  -> .numjac_map(msys, x)
    n = x.size()
    cols = []
    c = 0
    while c < n
      mag = x[c]
      if mag < ~0.0
        mag = ~0.0 - mag
      h = ~1.0e-6 * (~1.0 + mag)
      xp = Dynamics.vcopy(x)
      xp[c] = xp[c] + h
      xm = Dynamics.vcopy(x)
      xm[c] = xm[c] - h
      fp = msys.step(xp)
      fm = msys.step(xm)
      col = []
      r = 0
      while r < n
        col = col.push((fp[r] - fm[r]) / (~2.0 * h))
        r = r + 1
      cols = cols.push(col)
      c = c + 1
    out = []
    r = 0
    while r < n
      row = []
      c = 0
      while c < n
        row = row.push(cols[c][r])
        c = c + 1
      out = out.push(row)
      r = r + 1
    out

# Continuous-time system contract: subclasses supply `dim` and
# `f(t, x) -> dx/dt` (Array in, Array out; autonomous systems ignore t).
+ Flow
  -> flow?
    true

  -> jac(t, x)
    Dynamics.numjac_flow(self, t, x)

# Discrete-time system contract: subclasses supply `dim` and
# `step(x) -> next state`.
+ MapSystem
  -> flow?
    false

  -> jac(x)
    Dynamics.numjac_map(self, x)

# Separable Hamiltonian H(q, p) = |p|²/2 + V(q). Subclasses supply
# `accel(q) = -∇V(q)` (and optionally `potential(q)` for energy
# reporting). State for the generic Flow interface is [q…, p…].
+ HamiltonianSystem < Flow
  -> f(t, x)
    n = x.size() / 2
    q = []
    i = 0
    while i < n
      q = q.push(x[i])
      i = i + 1
    acc = accel(q)
    out = []
    i = 0
    while i < n
      out = out.push(x[n + i])
      i = i + 1
    i = 0
    while i < n
      out = out.push(acc[i])
      i = i + 1
    out

  -> energy(q, p)
    ke = ~0.0
    i = 0
    while i < p.size()
      ke = ke + p[i] * p[i]
      i = i + 1
    ke * ~0.5 + potential(q)
