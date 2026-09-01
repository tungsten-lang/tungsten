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
    Optim.least_squares_lm(residual, nil, x0, iters)

  # Jacobian-aware overload. `jacobian(x)` returns one row per residual and
  # one column per parameter; callers can supply analytic or AD derivatives.
  -> .least_squares(residual, jacobian, x0, iters)
    Optim.least_squares_lm(residual, jacobian, x0, iters)

  -> .copy_point(source)
    out = []
    source.each -> out.push(item + ~0.0)
    out

  -> .residual_cost(residual_values)
    value = ~0.0
    i = 0
    while i < residual_values.size
      value += residual_values[i] * residual_values[i]
      i += 1
    value

  # Central-difference Jacobian with two reusable point buffers. This retains
  # the old fallback semantics while removing its O(parameters^2) point-copy
  # allocation pattern.
  -> .least_squares_fd_jacobian(residual, x, residual_count)
    parameter_count = x.size
    jacobian = []
    row = 0
    while row < residual_count
      values = []
      parameter_count.times -> values.push(~0.0)
      jacobian.push(values)
      row += 1
    plus_point = Optim.copy_point(x)
    minus_point = Optim.copy_point(x)
    column = 0
    while column < parameter_count
      magnitude = x[column].abs
      h = ~1.0e-6 * (~1.0 + magnitude)
      plus_point[column] = x[column] + h
      minus_point[column] = x[column] - h
      plus = residual(plus_point)
      minus = residual(minus_point)
      if plus.size != residual_count || minus.size != residual_count
        raise "Optim.least_squares residual size changed"
      inverse_width = ~1.0 / (~2.0 * h)
      row = 0
      while row < residual_count
        jacobian[row][column] = (plus[row] - minus[row]) * inverse_width
        row += 1
      plus_point[column] = x[column]
      minus_point[column] = x[column]
      column += 1
    jacobian

  # Cholesky solve for the damped normal equations. Nil signals that numerical
  # roundoff defeated positive definiteness, so LM can increase its damping.
  -> .least_squares_spd_solve(matrix, rhs)
    n = rhs.size
    lower = []
    i = 0
    while i < n
      row = []
      n.times -> row.push(~0.0)
      lower.push(row)
      i += 1
    i = 0
    while i < n
      j = 0
      while j <= i
        value = matrix[i][j]
        k = 0
        while k < j
          value -= lower[i][k] * lower[j][k]
          k += 1
        if i == j
          return nil if value <= ~0.0 || value != value
          lower[i][j] = Math.sqrt(value)
        else
          lower[i][j] = value / lower[j][j]
        j += 1
      i += 1

    y = []
    i = 0
    while i < n
      value = rhs[i]
      j = 0
      while j < i
        value -= lower[i][j] * y[j]
        j += 1
      y.push(value / lower[i][i])
      i += 1
    solution = []
    n.times -> solution.push(~0.0)
    i = n - 1
    while i >= 0
      value = y[i]
      j = i + 1
      while j < n
        value -= lower[j][i] * solution[j]
        j += 1
      solution[i] = value / lower[i][i]
      i -= 1
    solution

  -> .least_squares_lm(residual, jacobian_function, x0, iters)
    x = Optim.copy_point(x0)
    residual_values = residual(x)
    cost = Optim.residual_cost(residual_values)
    damping = ~1.0e-3
    iteration = 0
    while iteration < iters && cost > ~1.0e-24
      jacobian = nil
      if jacobian_function == nil
        jacobian = Optim.least_squares_fd_jacobian(
          residual, x, residual_values.size)
      else
        jacobian = jacobian_function(x)
      if jacobian.size != residual_values.size
        raise "Optim.least_squares Jacobian row count mismatch"
      parameter_count = x.size
      normal = []
      gradient = []
      i = 0
      while i < parameter_count
        row = []
        parameter_count.times -> row.push(~0.0)
        normal.push(row)
        gradient.push(~0.0)
        i += 1

      row = 0
      while row < residual_values.size
        if jacobian[row].size != parameter_count
          raise "Optim.least_squares Jacobian column count mismatch"
        i = 0
        while i < parameter_count
          ji = jacobian[row][i]
          gradient[i] += ji * residual_values[row]
          j = 0
          while j <= i
            normal[i][j] += ji * jacobian[row][j]
            j += 1
          i += 1
        row += 1
      i = 0
      while i < parameter_count
        j = 0
        while j < i
          normal[j][i] = normal[i][j]
          j += 1
        normal[i][i] += damping
        gradient[i] = ~0.0 - gradient[i]
        i += 1

      step = Optim.least_squares_spd_solve(normal, gradient)
      if step == nil
        damping *= ~10.0
        iteration += 1
        next
      candidate = []
      i = 0
      while i < parameter_count
        candidate.push(x[i] + step[i])
        i += 1
      candidate_residual = residual(candidate)
      if candidate_residual.size != residual_values.size
        raise "Optim.least_squares residual size changed"
      candidate_cost = Optim.residual_cost(candidate_residual)
      if candidate_cost < cost
        improvement = cost - candidate_cost
        x = candidate
        residual_values = candidate_residual
        cost = candidate_cost
        damping *= ~0.3
        damping = ~1.0e-15 if damping < ~1.0e-15
        break if improvement < ~1.0e-20
      else
        damping *= ~10.0
      iteration += 1
    {:x => x, :fun => cost}
