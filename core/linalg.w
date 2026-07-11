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
