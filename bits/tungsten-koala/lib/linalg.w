# LinAlg — dense linear algebra over koala Matrix / Vector
# (pure Tungsten, CPU-only: Gaussian elimination with partial pivoting)
#
#     LinAlg.det(m)        # determinant (float; 0 when singular)
#     LinAlg.solve(m, b)   # x with m*x = b, as a Vector
#     LinAlg.inv(m)        # inverse Matrix (Gauss-Jordan)
#
# Shape rule: nil for non-square input, for a size-mismatched b, and
# for singular systems in solve/inv. det of a singular square matrix
# is 0, not nil. All arithmetic is done on float copies — inputs are
# never mutated. Singularity is detected as an exactly-zero pivot
# column after partial pivoting (no epsilon tolerance yet).
#
# Deliberately NOT ported from the draft: eig / svd / qr / cholesky /
# rank and every GPU dispatch path — the draft algorithms were sketches
# (eig eigenvectors were a placeholder identity; svd/rank sat on eig),
# and GPU belongs to the core Math/Metal machinery, not koala.
#
# NOTE: methods containing closures avoid early `return` (see stats.w).
+ LinAlg
  # |x| as a float.
  -> .fabs(x)
    out = x.to_f
    out = 0.to_f - out if out < 0
    out

  # Entries of m as fresh float rows (working copy for elimination).
  -> .float_rows(m)
    rows = []
    m.to_a.each -> (r)
      row = []
      r.each -> (v)
        row.push(v.to_f)
      rows.push(row)
    rows

  # Determinant; nil unless square. 0 when singular.
  -> .det(m)
    out = nil
    if m.square?
      n = m.row_count
      a = LinAlg.float_rows(m)
      detv = 1.to_f
      singular = false
      n.times -> (k)
        if !singular
          # partial pivot: largest |a[t][k]| for t >= k
          best = -1
          bestv = 0.to_f
          n.times -> (t)
            if t >= k
              av = LinAlg.fabs(a[t][k])
              if av > bestv
                bestv = av
                best = t
          if best == -1 || bestv == 0
            singular = true
          else
            if best != k
              tmp = a[k]
              a[k] = a[best]
              a[best] = tmp
              detv = 0.to_f - detv
            piv = a[k][k]
            detv = detv * piv
            n.times -> (r)
              if r > k
                factor = a[r][k] / piv
                n.times -> (c)
                  a[r][c] = a[r][c] - factor * a[k][c] if c >= k
      out = 0.to_f
      out = detv if !singular
    out

  # Gauss-Jordan reduction in place on n rows of width m (augmented).
  # Returns the reduced rows, or nil if the left n×n block is singular.
  -> .reduce_rows(a, n, m)
    ok = true
    n.times -> (k)
      if ok
        best = -1
        bestv = 0.to_f
        n.times -> (t)
          if t >= k
            av = LinAlg.fabs(a[t][k])
            if av > bestv
              bestv = av
              best = t
        if best == -1 || bestv == 0
          ok = false
        else
          if best != k
            tmp = a[k]
            a[k] = a[best]
            a[best] = tmp
          piv = a[k][k]
          m.times -> (c)
            a[k][c] = a[k][c] / piv
          n.times -> (r)
            if r != k
              factor = a[r][k]
              m.times -> (c)
                a[r][c] = a[r][c] - factor * a[k][c]
    out = nil
    out = a if ok
    out

  # Solve m * x = b (b: Vector or plain array) -> Vector of floats.
  # nil when m is not square, b's size mismatches, or m is singular.
  -> .solve(m, b)
    out = nil
    bvals = b.to_a
    if m.square? && m.row_count == bvals.size
      n = m.row_count
      a = LinAlg.float_rows(m)
      i = 0
      a.each -> (row)
        row.push(bvals[i].to_f)
        i += 1
      red = LinAlg.reduce_rows(a, n, n + 1)
      if red != nil
        vals = []
        red.each -> (row)
          vals.push(row[n])
        out = Vector.new(vals)
    out

  # Inverse via Gauss-Jordan on [A | I] -> Matrix of floats.
  # nil when m is not square or is singular.
  -> .inv(m)
    out = nil
    if m.square?
      n = m.row_count
      a = LinAlg.float_rows(m)
      i = 0
      a.each -> (row)
        n.times -> (j)
          if i == j
            row.push(1.to_f)
          else
            row.push(0.to_f)
        i += 1
      red = LinAlg.reduce_rows(a, n, 2 * n)
      if red != nil
        rows = []
        red.each -> (row)
          rr = []
          n.times -> (j)
            rr.push(row[n + j])
          rows.push(rr)
        out = Matrix.new(rows)
    out
