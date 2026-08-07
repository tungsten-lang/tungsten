# Trajectory generation. RK4 is the workhorse for flows (Solve.ivp in
# core/solve.w remains the closure-based general API; these methods take
# system objects and are what the analysis layers step through).
# Symplectic Störmer-Verlet and Yoshida-4 cover Hamiltonian systems
# where long-run energy behavior matters more than one-step accuracy.

+ Dynamics
  -> .rk4_step(sys, t, x, h)
    k1 = sys.f(t, x)
    k2 = sys.f(t + h * ~0.5, Dynamics.vaxpy(x, h * ~0.5, k1))
    k3 = sys.f(t + h * ~0.5, Dynamics.vaxpy(x, h * ~0.5, k2))
    k4 = sys.f(t + h, Dynamics.vaxpy(x, h, k3))
    out = []
    i = 0
    while i < x.size()
      out = out.push(x[i] + (k1[i] + ~2.0 * k2[i] + ~2.0 * k3[i] + k4[i]) * (h / ~6.0))
      i = i + 1
    out

  # Integrate a flow from t_start to t_stop with fixed step dt (RK4).
  # Returns {t: [times], x: [states]} including both endpoints.
  # (Parameter names avoid `t0`/`t1`, which collide with the emitter's
  # %tN temp namespace in generated IR.)
  -> .trajectory(sys, x0, t_start, t_stop, dt)
    ts = [t_start + ~0.0]
    xs = [Dynamics.vcopy(x0)]
    t = t_start
    x = x0
    while t < t_stop - dt * ~0.5
      x = Dynamics.rk4_step(sys, t, x, dt)
      t = t + dt
      ts = ts.push(t)
      xs = xs.push(x)
    {t: ts, x: xs}

  # Advance a flow by n RK4 steps without storing the path.
  -> .advance(sys, x0, t_start, n, dt)
    x = x0
    t = t_start
    i = 0
    while i < n
      x = Dynamics.rk4_step(sys, t, x, dt)
      t = t + dt
      i = i + 1
    x

  # Orbit of a map: [x0, x1, …, xn] (n steps, n+1 states).
  -> .orbit(msys, x0, n)
    out = [Dynamics.vcopy(x0)]
    x = x0
    i = 0
    while i < n
      x = msys.step(x)
      out = out.push(x)
      i = i + 1
    out

  # n-th iterate of a map, no storage.
  -> .iterate(msys, x0, n)
    x = x0
    i = 0
    while i < n
      x = msys.step(x)
      i = i + 1
    x

  # Störmer-Verlet (leapfrog, kick-drift-kick) on a separable
  # HamiltonianSystem. Returns {t:, q:, p:} sampled every step.
  -> .verlet(ham, q0, p0, t_stop, dt)
    ts = [~0.0]
    qs = [Dynamics.vcopy(q0)]
    ps = [Dynamics.vcopy(p0)]
    q = Dynamics.vcopy(q0)
    p = Dynamics.vcopy(p0)
    t = ~0.0
    while t < t_stop - dt * ~0.5
      a = ham.accel(q)
      p = Dynamics.vaxpy(p, dt * ~0.5, a)
      q = Dynamics.vaxpy(q, dt, p)
      a = ham.accel(q)
      p = Dynamics.vaxpy(p, dt * ~0.5, a)
      t = t + dt
      ts = ts.push(t)
      qs = qs.push(q)
      ps = ps.push(p)
    {t: ts, q: qs, p: ps}

  # 4th-order Yoshida composition of Verlet steps.
  -> .yoshida4(ham, q0, p0, t_stop, dt)
    cbrt2 = Math.cbrt(~2.0)
    w1 = ~1.0 / (~2.0 - cbrt2)
    w0 = ~0.0 - cbrt2 * w1
    ts = [~0.0]
    qs = [Dynamics.vcopy(q0)]
    ps = [Dynamics.vcopy(p0)]
    q = Dynamics.vcopy(q0)
    p = Dynamics.vcopy(p0)
    t = ~0.0
    while t < t_stop - dt * ~0.5
      sub = 0
      while sub < 3
        w = w1
        if sub == 1
          w = w0
        h = dt * w
        a = ham.accel(q)
        p = Dynamics.vaxpy(p, h * ~0.5, a)
        q = Dynamics.vaxpy(q, h, p)
        a = ham.accel(q)
        p = Dynamics.vaxpy(p, h * ~0.5, a)
        sub = sub + 1
      t = t + dt
      ts = ts.push(t)
      qs = qs.push(q)
      ps = ps.push(p)
    {t: ts, q: qs, p: ps}
