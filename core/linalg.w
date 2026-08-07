# LinAlg — dense linear algebra over nested lists / flat f64 storage.
#
# Matrices are list-of-rows (row-major). Vectors are 1-D lists of Float.
# No Grid type — multi-D dense lives on Tensor (CPU/Metal faces later).
#
# Accelerated paths: core/blas.w (sgemm, sgemv, dgesv, …) when linked.

+ LinAlg
  -> .rows(a)
    a.size()

  -> .cols(a)
    if a.size() == 0
      return 0
    a[0].size()

  -> .zeros(m, n)
    out = []
    i = 0
    while i < m
      row = []
      j = 0
      while j < n
        row = row.push(~0.0)
        j = j + 1
      out = out.push(row)
      i = i + 1
    out

  -> .eye(n)
    a = LinAlg.zeros(n, n)
    i = 0
    while i < n
      a[i][i] = ~1.0
      i = i + 1
    a

  -> .matmul(a, b)
    m = LinAlg.rows(a)
    k = LinAlg.cols(a)
    n = LinAlg.cols(b)
    out = LinAlg.zeros(m, n)
    i = 0
    while i < m
      j = 0
      while j < n
        s = ~0.0
        t = 0
        while t < k
          s = s + a[i][t] * b[t][j]
          t = t + 1
        out[i][j] = s
        j = j + 1
      i = i + 1
    out

  -> .dot(u, v)
    s = ~0.0
    i = 0
    while i < u.size()
      s = s + u[i] * v[i]
      i = i + 1
    s

  -> .norm(v)
    Math.sqrt(LinAlg.dot(v, v))

  # GE with partial pivoting: A n×n nested, b length n → x length n
  -> .solve(a, b)
    n = LinAlg.rows(a)
    aw = LinAlg.copy_mat(a)
    bw = []
    i = 0
    while i < n
      bw = bw.push(b[i] + ~0.0)
      i = i + 1
    k = 0
    while k < n
      piv = k
      maxv = aw[k][k]
      if maxv < ~0.0
        maxv = ~0.0 - maxv
      i = k + 1
      while i < n
        v = aw[i][k]
        if v < ~0.0
          v = ~0.0 - v
        if v > maxv
          maxv = v
          piv = i
        i = i + 1
      if maxv == ~0.0
        raise "LinAlg.solve: singular"
      if piv != k
        tmp = aw[k]
        aw[k] = aw[piv]
        aw[piv] = tmp
        tb = bw[k]
        bw[k] = bw[piv]
        bw[piv] = tb
      i = k + 1
      while i < n
        f = aw[i][k] / aw[k][k]
        j = k
        while j < n
          aw[i][j] = aw[i][j] - f * aw[k][j]
          j = j + 1
        bw[i] = bw[i] - f * bw[k]
        i = i + 1
      k = k + 1
    x = []
    i = 0
    while i < n
      x = x.push(~0.0)
      i = i + 1
    i = n - 1
    while i >= 0
      s = bw[i]
      j = i + 1
      while j < n
        s = s - aw[i][j] * x[j]
        j = j + 1
      x[i] = s / aw[i][i]
      i = i - 1
    x

  -> .copy_mat(a)
    out = []
    i = 0
    while i < a.size()
      row = []
      j = 0
      while j < a[i].size()
        row = row.push(a[i][j] + ~0.0)
        j = j + 1
      out = out.push(row)
      i = i + 1
    out

  -> .det(a)
    n = LinAlg.rows(a)
    aw = LinAlg.copy_mat(a)
    sign = ~1.0
    k = 0
    while k < n
      piv = k
      maxv = aw[k][k]
      if maxv < ~0.0
        maxv = ~0.0 - maxv
      i = k + 1
      while i < n
        v = aw[i][k]
        if v < ~0.0
          v = ~0.0 - v
        if v > maxv
          maxv = v
          piv = i
        i = i + 1
      if maxv == ~0.0
        return ~0.0
      if piv != k
        sign = ~0.0 - sign
        tmp = aw[k]
        aw[k] = aw[piv]
        aw[piv] = tmp
      i = k + 1
      while i < n
        f = aw[i][k] / aw[k][k]
        j = k
        while j < n
          aw[i][j] = aw[i][j] - f * aw[k][j]
          j = j + 1
        i = i + 1
      k = k + 1
    d = sign
    i = 0
    while i < n
      d = d * aw[i][i]
      i = i + 1
    d

  -> .cholesky(a)
    n = LinAlg.rows(a)
    L = LinAlg.zeros(n, n)
    i = 0
    while i < n
      j = 0
      while j <= i
        s = a[i][j]
        k = 0
        while k < j
          s = s - L[i][k] * L[j][k]
          k = k + 1
        if i == j
          if s <= ~0.0
            raise "LinAlg.cholesky: not SPD"
          L[i][j] = Math.sqrt(s)
        else
          L[i][j] = s / L[j][j]
        j = j + 1
      i = i + 1
    L

  -> .transpose(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    out = LinAlg.zeros(n, m)
    i = 0
    while i < m
      j = 0
      while j < n
        out[j][i] = a[i][j]
        j = j + 1
      i = i + 1
    out

  -> .mat_vec(a, v)
    out = []
    i = 0
    while i < a.size()
      out = out.push(LinAlg.dot(a[i], v))
      i = i + 1
    out

  # Thin QR by modified Gram-Schmidt: a m×n (m ≥ n) → [q, r] with q m×n
  # (orthonormal columns) and r n×n upper triangular. A dependent column
  # leaves a zero column in q and a zero on r's diagonal rather than
  # raising — Lyapunov-spectrum renormalization treats that as collapse.
  -> .qr(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    q = LinAlg.copy_mat(a)
    r = LinAlg.zeros(n, n)
    j = 0
    while j < n
      i = 0
      while i < j
        s = ~0.0
        t = 0
        while t < m
          s = s + q[t][i] * q[t][j]
          t = t + 1
        r[i][j] = s
        t = 0
        while t < m
          q[t][j] = q[t][j] - s * q[t][i]
          t = t + 1
        i = i + 1
      s = ~0.0
      t = 0
      while t < m
        s = s + q[t][j] * q[t][j]
        t = t + 1
      nrm = Math.sqrt(s)
      r[j][j] = nrm
      if nrm > ~0.0
        t = 0
        while t < m
          q[t][j] = q[t][j] / nrm
          t = t + 1
      j = j + 1
    [q, r]

  # Characteristic polynomial of an n×n float matrix via Faddeev-LeVerrier.
  # Returns descending coefficients [1, c1, …, cn] of λⁿ + c1·λⁿ⁻¹ + … + cn.
  # Numerically fine at the Jacobian sizes stability analysis uses (n ≲ 10).
  -> .charpoly(a)
    n = LinAlg.rows(a)
    coeffs = [~1.0]
    m = LinAlg.eye(n)
    k = 1
    while k <= n
      m = LinAlg.matmul(a, m)
      tr = ~0.0
      i = 0
      while i < n
        tr = tr + m[i][i]
        i = i + 1
      ck = (~0.0 - tr) / k
      coeffs = coeffs.push(ck)
      i = 0
      while i < n
        m[i][i] = m[i][i] + ck
        i = i + 1
      k = k + 1
    coeffs

  # All complex roots of a float-coefficient polynomial (descending
  # coefficients, coeffs[0] ≠ 0) by Durand-Kerner iteration on split
  # re/im floats. Returns [[re, im], …]; near-real roots snap to im = 0.
  -> .poly_roots(coeffs)
    n = coeffs.size() - 1
    if n < 1
      return []
    c = []
    i = 0
    while i <= n
      c = c.push(coeffs[i] / coeffs[0])
      i = i + 1
    bound = ~0.0
    i = 1
    while i <= n
      v = c[i]
      if v < ~0.0
        v = ~0.0 - v
      if v > bound
        bound = v
      i = i + 1
    bound = bound + ~1.0
    zr = []
    zi = []
    k = 0
    while k < n
      ang = (~6.283185307179586 * k) / n + ~0.4
      zr = zr.push(bound * Math.cos(ang))
      zi = zi.push(bound * Math.sin(ang))
      k = k + 1
    iter = 0
    while iter < 400
      moved = ~0.0
      k = 0
      while k < n
        pr = c[0]
        pim = ~0.0
        i = 1
        while i <= n
          t = pr * zr[k] - pim * zi[k] + c[i]
          pim = pr * zi[k] + pim * zr[k]
          pr = t
          i = i + 1
        dr = ~1.0
        dim = ~0.0
        j = 0
        while j < n
          if j != k
            xr = zr[k] - zr[j]
            xi = zi[k] - zi[j]
            t = dr * xr - dim * xi
            dim = dr * xi + dim * xr
            dr = t
          j = j + 1
        den = dr * dr + dim * dim
        if den > ~0.0
          qr = (pr * dr + pim * dim) / den
          qi = (pim * dr - pr * dim) / den
          zr[k] = zr[k] - qr
          zi[k] = zi[k] - qi
          step = Math.hypot(qr, qi)
          if step > moved
            moved = step
        k = k + 1
      if moved < ~1.0e-13
        iter = 400
      iter = iter + 1
    out = []
    k = 0
    while k < n
      re = zr[k]
      im = zi[k]
      mag = re
      if mag < ~0.0
        mag = ~0.0 - mag
      lim = im
      if lim < ~0.0
        lim = ~0.0 - lim
      if lim < ~1.0e-8 * (~1.0 + mag)
        im = ~0.0
      out = out.push([re, im])
      k = k + 1
    out

  # Eigenvalues of an n×n float matrix → [[re, im], …] (unordered).
  # Route: characteristic polynomial + Durand-Kerner — robust at the small
  # dimensions dynamical-systems Jacobians have. Large dense eigen is a
  # LAPACK-bridge follow-up.
  -> .eigenvalues(a)
    LinAlg.poly_roots(LinAlg.charpoly(a))
