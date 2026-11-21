# Hermitian forms, definite/indefinite unitary groups U(H), Hermitian lattices,
# lattice theta series, and Stepanov-style finite-field path quadric sums.
#
# Computational core for the automorphic / unitary-group / theta-lift machinery
# referenced in Phase 0–3 of Satori RH Route B.

use calculus

+ HermitianForm
  ro :matrix, :dimension

  -> .to_complex(x)
    return x if x.class_name == "Complex" || x.class_name == "Complex<f64>"
    Complex<f64>.real(x + ~0.0)

  -> .mat_mul(a, b)
    m = a.size
    k = b.size
    n = b[0].size
    out = []
    i = 0
    while i < m
      row = []
      j = 0
      while j < n
        sum = Complex<f64>.zero
        t = 0
        while t < k
          sum += a[i][t] * b[t][j]
          t += 1
        row.push(sum)
        j += 1
      out.push(row)
      i += 1
    out

  -> .mat_adjoint(a)
    m = a.size
    n = a[0].size
    out = []
    j = 0
    while j < n
      row = []
      i = 0
      while i < m
        row.push(a[i][j].conjugate)
        i += 1
      out.push(row)
      j += 1
    out

  -> .mat_det(mat)
    n = mat.size
    return Complex<f64>.one if n == 0
    work = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(mat[i][j])
        j += 1
      work.push(row)
      i += 1
    det = Complex<f64>.one
    k = 0
    while k < n
      piv = k
      best = work[k][k].abs
      i = k + 1
      while i < n
        v = work[i][k].abs
        if v > best
          best = v
          piv = i
        i += 1
      return Complex<f64>.zero if best <= ~1.0e-14
      if piv != k
        tmp = work[k]
        work[k] = work[piv]
        work[piv] = tmp
        det = Complex<f64>.zero - det
      pv = work[k][k]
      det = det * pv
      i = k + 1
      while i < n
        factor = work[i][k] / pv
        j = k + 1
        while j < n
          work[i][j] = work[i][j] - factor * work[k][j]
          j += 1
        i += 1
      k += 1
    det

  -> new(rows)
    @dimension = rows.size
    raise "HermitianForm requires a non-empty square matrix" if @dimension == 0
    @matrix = []
    rows.each -> (r)
      raise "HermitianForm matrix must be square" if r.size != @dimension
      crow = []
      r.each -> (x) crow.push(HermitianForm.to_complex(x))
      @matrix.push(crow)

  -> .identity(n)
    rows = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(i == j ? Complex<f64>.one : Complex<f64>.zero)
        j += 1
      rows.push(row)
      i += 1
    HermitianForm.new(rows)

  -> hermitian?(tol = ~1.0e-9)
    i = 0
    while i < @dimension
      j = i
      while j < @dimension
        return false if (@matrix[i][j] - @matrix[j][i].conjugate).abs > tol
        j += 1
      i += 1
    true

  # Sylvester criterion: all leading principal minors strictly positive real.
  -> positive_definite?(tol = ~1.0e-9)
    return false if !hermitian?(tol)
    k = 1
    while k <= @dimension
      sub = []
      i = 0
      while i < k
        row = []
        j = 0
        while j < k
          row.push(@matrix[i][j])
          j += 1
        sub.push(row)
        i += 1
      d = HermitianForm.mat_det(sub)
      return false if d.imag.abs > tol || d.real <= tol
      k += 1
    true

  # u^* H v
  -> inner_product(u, v)
    raise "vector length mismatch" if u.size != @dimension || v.size != @dimension
    total = Complex<f64>.zero
    i = 0
    while i < @dimension
      ui = HermitianForm.to_complex(u[i]).conjugate
      j = 0
      while j < @dimension
        vj = HermitianForm.to_complex(v[j])
        total += ui * @matrix[i][j] * vj
        j += 1
      i += 1
    total

  -> norm_sq(v)
    inner_product(v, v).real


+ UnitaryGroup
  ro :form

  -> new(@form)
    raise "UnitaryGroup requires a Hermitian form" if !@form.hermitian?

  -> .definite(n)
    UnitaryGroup.new(HermitianForm.identity(n))

  -> dimension
    @form.dimension

  -> identity
    HermitianForm.identity(@form.dimension).matrix

  -> member?(u, tol = ~1.0e-9)
    return false if u.size != dimension
    u_adj = HermitianForm.mat_adjoint(u)
    prod = HermitianForm.mat_mul(HermitianForm.mat_mul(u_adj, @form.matrix), u)
    i = 0
    while i < dimension
      j = 0
      while j < dimension
        return false if (prod[i][j] - @form.matrix[i][j]).abs > tol
        j += 1
      i += 1
    true

  -> multiply(a, b)
    HermitianForm.mat_mul(a, b)

  -> adjoint(u)
    HermitianForm.mat_adjoint(u)

  -> determinant(u)
    HermitianForm.mat_det(u)


# Definite Hermitian lattice over Z[i] with integer/Gaussian Hermitian Gram matrix H,
# plus finite-field Stepanov path-quadric Fourier sums (Alpöge remark.pdf footnote 3).
+ ThetaKernel
  ro :form

  -> new(@form)
    raise "ThetaKernel requires a positive-definite Hermitian form" if !@form.positive_definite?

  # Exact representation count r_L(m) for vectors v in Z[i]^d with |Re v_j|, |Im v_j| <= bound
  # and v^* H v = m (within tol).
  -> representation_counts(max_norm, bound = 3, tol = ~1.0e-9)
    counts = Array.new(max_norm + 1, 0)
    d = @form.dimension
    # Enumerate coordinates in [-bound, bound]^2 per complex dimension
    coords = []
    a = 0 - bound
    while a <= bound
      b = 0 - bound
      while b <= bound
        coords.push(Complex<f64>.real(a + ~0.0) + Complex<f64>.i.scale(b + ~0.0))
        b += 1
      a += 1
    m = coords.size
    total = 1
    k = 0
    while k < d
      total = total * m
      k += 1
    idx = 0
    while idx < total
      vec = []
      rem = idx
      j = 0
      while j < d
        vec.push(coords[rem % m])
        rem = rem / m
        j += 1
      ns = @form.norm_sq(vec)
      nr = ns.round
      if nr >= 0 && nr <= max_norm && (ns - (nr + ~0.0)).abs <= tol
        counts[nr] = counts[nr] + 1
      idx += 1
    counts

  # Evaluate truncated theta series sum_{m=0}^{max_norm} r_L(m) * q^m at complex q (|q| < 1).
  -> theta_series(q, max_norm, bound = 3)
    counts = representation_counts(max_norm, bound)
    total = Complex<f64>.zero
    q_pow = Complex<f64>.one
    m = 0
    while m <= max_norm
      c = counts[m]
      if c != 0
        total += q_pow.scale(c + ~0.0)
      q_pow = q_pow * q
      m += 1
    total

  # Alpöge remark.pdf footnote 3 toy sum over F_q:
  #   sum_{h in F_q} sum_{x_1,...,x_k in F_q} t(x_1)...t(x_k) e_q(h (x_1 x_2 + ... + x_{k-1} x_k))
  # Equals q * N where N = sum_{x_1 x_2 + ... + x_{k-1} x_k = 0 (mod q)} t(x_1)...t(x_k),
  # and equals M^k + R where M = sum_x t(x) is the h = 0 mode and R is the h != 0 remainder.
  # Returns [qN, M_pow_k, R] (as Complex<f64>).
  -> .stepanov_path_sum(q, k, t_values)
    raise "stepanov_path_sum requires k >= 2 and t_values.size == q" if k < 2 || t_values.size != q
    two_pi = ~6.28318530717958647693
    # Compute M = sum_x t(x)
    m_sum = Complex<f64>.zero
    t_values.each -> (v) m_sum += HermitianForm.to_complex(v)
    m_pow = Complex<f64>.one
    i = 0
    while i < k
      m_pow = m_pow * m_sum
      i += 1
    # DP over x_1..x_k for each fixed h in F_q: dp[last_x] = sum_{x_1..x_j} t(x_1)..t(x_j) e_q(h * path)
    total_all = Complex<f64>.zero
    rem_sum = Complex<f64>.zero
    h = 0
    while h < q
      dp = []
      x = 0
      while x < q
        dp.push(HermitianForm.to_complex(t_values[x]))
        x += 1
      step = 2
      while step <= k
        ndp = []
        y = 0
        while y < q
          ty = HermitianForm.to_complex(t_values[y])
          acc = Complex<f64>.zero
          x = 0
          while x < q
            phase = Complex<f64>.cis(two_pi * (((h * x * y) % q) + ~0.0) / (q + ~0.0))
            acc += dp[x] * phase
            x += 1
          ndp.push(acc * ty)
          y += 1
        dp = ndp
        step += 1
      sh = Complex<f64>.zero
      dp.each -> (v) sh += v
      total_all += sh
      rem_sum += sh if h != 0
      h += 1
    [total_all, m_pow, rem_sum]
