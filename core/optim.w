# Optim — scalar / vector optimization and root-finding (v0).

+ Optim
  -> .root_bisection(f, a, b)
    lo = a
    hi = b
    fa = f(a)
    i = 0
    while i < 80
      mid = ~0.5 * (lo + hi)
      fm = f(mid)
      if fa * fm <= ~0.0
        hi = mid
      else
        lo = mid
        fa = fm
      i = i + 1
    ~0.5 * (lo + hi)

  -> .root_newton(f, df, x0)
    x = x0
    i = 0
    while i < 50
      fx = f(x)
      d = df(x)
      if d == ~0.0
        raise "Optim.root_newton: zero derivative"
      x = x - fx / d
      afx = fx
      if afx < ~0.0
        afx = ~0.0 - afx
      if afx < ~0.0000000001
        return x
      i = i + 1
    x

  -> .minimize_gd_fd(f, x0, lr, iters)
    x = []
    i = 0
    while i < x0.size()
      x = x.push(x0[i] + ~0.0)
      i = i + 1
    t = 0
    while t < iters
      g = Optim.fd_grad(f, x)
      i = 0
      while i < x.size()
        x[i] = x[i] - lr * g[i]
        i = i + 1
      t = t + 1
    {:x => x, :fun => f(x)}

  -> .fd_grad(f, x)
    h = ~0.000001
    g = []
    i = 0
    while i < x.size()
      xp = []
      xm = []
      j = 0
      while j < x.size()
        xp = xp.push(x[j])
        xm = xm.push(x[j])
        j = j + 1
      xp[i] = xp[i] + h
      xm[i] = xm[i] - h
      g = g.push((f(xp) - f(xm)) / (~2.0 * h))
      i = i + 1
    g

  -> .minimize_nm(f, x0, iters)
    # thin wrapper: coordinate descent fallback for v0
    x = []
    i = 0
    while i < x0.size()
      x = x.push(x0[i] + ~0.0)
      i = i + 1
    t = 0
    while t < iters
      i = 0
      while i < x.size()
        best = f(x)
        step = ~0.01
        x[i] = x[i] + step
        if f(x) > best
          x[i] = x[i] - ~2.0 * step
          if f(x) > best
            x[i] = x[i] + step
        i = i + 1
      t = t + 1
    {:x => x, :fun => f(x)}

  -> .least_squares(residual, x0, iters)
    # Gauss-Newton with FD Jacobian — see optim history for full GE.
    # v0: gradient descent on 0.5||r||^2
    f = -> (x)
      r = residual(x)
      s = ~0.0
      i = 0
      while i < r.size()
        s = s + r[i] * r[i]
        i = i + 1
      s
    Optim.minimize_gd_fd(f, x0, ~0.01, iters)
