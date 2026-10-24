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

  -> .minimize_gd_fd(f, x0_in, lr_in, iters)
    x0 = x0_in ## Array
    lr = lr_in ## f64
    n = x0.size
    x = []
    i = 0
    while i < n
      xi = x0[i] ## f64
      x.push(xi + ~0.0)
      i += 1
    t = 0
    while t < iters
      g = Optim.fd_grad(f, x) ## Array
      i = 0
      while i < n
        xi = x[i] ## f64
        gi = g[i] ## f64
        x[i] = xi - lr * gi
        i += 1
      t += 1
    {:x => x, :fun => f(x)}

  -> .fd_grad(f, x)
    result = Optim.fd_grad_result(f, x)
    if !result.converged?
      raise "Optim.fd_grad: numerical gradient " + result.status.to_s
    result.value

  -> .fd_grad_result(f, x, abs_tol = ~1.0e-10, rel_tol = ~1.0e-8)
    Calculus.numerical_gradient(f, x, :central, nil, abs_tol, rel_tol)

  -> .minimize_nm(f, x0_in, iters)
    # thin wrapper: coordinate descent fallback for v0
    x0 = x0_in ## Array
    n = x0.size
    x = []
    i = 0
    while i < n
      xi = x0[i] ## f64
      x.push(xi + ~0.0)
      i += 1
    t = 0
    while t < iters
      i = 0
      while i < n
        best = f(x) ## f64
        step = ~0.01
        xi = x[i] ## f64
        x[i] = xi + step
        fx1 = f(x) ## f64
        if fx1 > best
          x[i] = xi - step
          fx2 = f(x) ## f64
          if fx2 > best
            x[i] = xi
        i += 1
      t += 1
    {:x => x, :fun => f(x)}

  -> .least_squares(residual, x0, iters)
    Optim.least_squares_lm(residual, nil, x0, iters)

  # Jacobian-aware overload. `jacobian(x)` returns one row per residual and
  # one column per parameter; callers can supply analytic or AD derivatives.
  -> .least_squares(residual, jacobian, x0, iters)
    Optim.least_squares_lm(residual, jacobian, x0, iters)

  -> .copy_point(source_in)
    source = source_in ## Array
    n = source.size
    out = []
    i = 0
    while i < n
      si = source[i] ## f64
      out.push(si + ~0.0)
      i += 1
    out

  -> .residual_cost(residual_values)
    rv = residual_values ## Array
    n = rv.size
    value = ~0.0
    i = 0
    while i < n
      r = rv[i] ## f64
      value += r * r
      i += 1
    value

  # Central-difference Jacobian with two reusable point buffers. This retains
  # the old fallback semantics while removing its O(parameters^2) point-copy
  # allocation pattern.
  -> .least_squares_fd_jacobian(residual, x_in, residual_count)
    x = x_in ## Array
    parameter_count = x.size
    jacobian = []
    row = 0
    while row < residual_count
      values = []
      c = 0
      while c < parameter_count
        values.push(~0.0)
        c += 1
      jacobian.push(values)
      row += 1
    plus_point = Optim.copy_point(x) ## Array
    minus_point = Optim.copy_point(x) ## Array
    column = 0
    while column < parameter_count
      xc = x[column] ## f64
      magnitude = xc < ~0.0 ? ~0.0 - xc : xc
      h = ~1.0e-6 * (~1.0 + magnitude)
      plus_point[column] = xc + h
      minus_point[column] = xc - h
      plus = residual(plus_point) ## Array
      minus = residual(minus_point) ## Array
      if plus.size != residual_count || minus.size != residual_count
        raise "Optim.least_squares residual size changed"
      inverse_width = ~1.0 / (~2.0 * h)
      row = 0
      while row < residual_count
        jrow = jacobian[row] ## Array
        pr = plus[row] ## f64
        mr = minus[row] ## f64
        jrow[column] = (pr - mr) * inverse_width
        row += 1
      plus_point[column] = xc
      minus_point[column] = xc
      column += 1
    jacobian

  # Cholesky solve for the damped normal equations. Nil signals that numerical
  # roundoff defeated positive definiteness, so LM can increase its damping.
  -> .least_squares_spd_solve(matrix_in, rhs_in)
    matrix = matrix_in ## Array
    rhs = rhs_in ## Array
    n = rhs.size
    lower = []
    i = 0
    while i < n
      row = []
      c = 0
      while c < n
        row.push(~0.0)
        c += 1
      lower.push(row)
      i += 1
    i = 0
    while i < n
      mat_i = matrix[i] ## Array
      low_i = lower[i] ## Array
      j = 0
      while j <= i
        low_j = lower[j] ## Array
        value = mat_i[j] ## f64
        k = 0
        while k < j
          lik = low_i[k] ## f64
          ljk = low_j[k] ## f64
          value -= lik * ljk
          k += 1
        if i == j
          return nil if value <= ~0.0 || value != value
          low_i[j] = Math.sqrt(value)
        else
          ljj = low_j[j] ## f64
          low_i[j] = value / ljj
        j += 1
      i += 1

    y = []
    i = 0
    while i < n
      low_i = lower[i] ## Array
      value = rhs[i] ## f64
      j = 0
      while j < i
        lij = low_i[j] ## f64
        yj = y[j] ## f64
        value -= lij * yj
        j += 1
      lii = low_i[i] ## f64
      y.push(value / lii)
      i += 1
    solution = []
    i = 0
    while i < n
      solution.push(~0.0)
      i += 1
    i = n - 1
    while i >= 0
      value = y[i] ## f64
      j = i + 1
      while j < n
        low_j = lower[j] ## Array
        lji = low_j[i] ## f64
        sj = solution[j] ## f64
        value -= lji * sj
        j += 1
      low_i = lower[i] ## Array
      lii = low_i[i] ## f64
      solution[i] = value / lii
      i -= 1
    solution

  -> .least_squares_lm(residual, jacobian_function, x0, iters)
    x = Optim.copy_point(x0) ## Array
    residual_values = residual(x) ## Array
    cost = Optim.residual_cost(residual_values) ## f64
    damping = ~1.0e-3
    iteration = 0
    while iteration < iters && cost > ~1.0e-24
      n_res = residual_values.size
      jacobian_raw = nil
      if jacobian_function == nil
        jacobian_raw = Optim.least_squares_fd_jacobian(
          residual, x, n_res)
      else
        jacobian_raw = jacobian_function(x)
      jacobian = jacobian_raw ## Array
      if jacobian.size != n_res
        raise "Optim.least_squares Jacobian row count mismatch"
      parameter_count = x.size
      normal = []
      gradient = []
      i = 0
      while i < parameter_count
        row = []
        c = 0
        while c < parameter_count
          row.push(~0.0)
          c += 1
        normal.push(row)
        gradient.push(~0.0)
        i += 1

      row = 0
      while row < n_res
        jrow = jacobian[row] ## Array
        if jrow.size != parameter_count
          raise "Optim.least_squares Jacobian column count mismatch"
        rv_row = residual_values[row] ## f64
        i = 0
        while i < parameter_count
          ji = jrow[i] ## f64
          gi = gradient[i] ## f64
          gradient[i] = gi + ji * rv_row
          norm_i = normal[i] ## Array
          j = 0
          while j <= i
            jj = jrow[j] ## f64
            nij = norm_i[j] ## f64
            norm_i[j] = nij + ji * jj
            j += 1
          i += 1
        row += 1
      i = 0
      while i < parameter_count
        norm_i = normal[i] ## Array
        j = 0
        while j < i
          norm_j = normal[j] ## Array
          norm_j[i] = norm_i[j]
          j += 1
        nii = norm_i[i] ## f64
        norm_i[i] = nii + damping
        gi = gradient[i] ## f64
        gradient[i] = ~0.0 - gi
        i += 1

      step = Optim.least_squares_spd_solve(normal, gradient)
      if step == nil
        damping *= ~10.0
        iteration += 1
        next
      step_arr = step ## Array
      candidate = []
      i = 0
      while i < parameter_count
        xi = x[i] ## f64
        si = step_arr[i] ## f64
        candidate.push(xi + si)
        i += 1
      candidate_residual = residual(candidate) ## Array
      if candidate_residual.size != n_res
        raise "Optim.least_squares residual size changed"
      candidate_cost = Optim.residual_cost(candidate_residual) ## f64
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
