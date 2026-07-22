# LinAlg — dense linear algebra over koala Matrix / Vector
# (pure Tungsten, CPU-only: Gaussian elimination with partial pivoting
# for square systems, Householder QR for least squares)
#
#     LinAlg.det(m)        # determinant (float; 0 when singular)
#     LinAlg.solve(m, b)   # x with m*x = b, as a Vector
#     LinAlg.inv(m)        # inverse Matrix (Gauss-Jordan)
#     LinAlg.qr(m)         # { q: Matrix, r: Matrix } — reduced QR
#     LinAlg.lstsq(a, b)   # least-squares x minimizing |a*x - b|, Vector
#
# Shape rule: nil for non-square input, for a size-mismatched b, and
# for singular systems in solve/inv. det of a singular square matrix
# is 0, not nil. All arithmetic is done on float copies — inputs are
# never mutated. Singularity is detected as an exactly-zero pivot
# column after partial pivoting (no epsilon tolerance yet); the QR
# routines use the scaled rank test in .rank_tol instead.
#
# WHY QR EXISTS (the numerics that motivated it): the textbook route to
# a least-squares fit is the normal equations, X^T X beta = X^T y —
# LinAlg.solve applied to a matrix product. It is also the wrong route.
# Forming X^T X SQUARES the condition number, so a design with
# cond(X) = 1e6 hands Gaussian elimination a system with cond = 1e12
# and burns twelve of f64's ~sixteen digits before the solve begins.
# Householder QR factors X itself — X = QR with Q orthonormal — and
# orthogonal transforms preserve the 2-norm exactly, so the error
# stays proportional to cond(X), not cond(X)^2. On the Vandermonde
# design in spec/linalg_spec.w that is a max coefficient error of
# 6.94e-11 against the normal equations' 5.26e-4 — four correct digits
# against eleven. LinearRegression's OLS path (alpha = 0) therefore
# goes through .lstsq; see lib/linear_regression.w.
#
# Householder reflections are used rather than (modified) Gram-Schmidt:
# each reflection is exactly orthogonal to working precision, so Q's
# columns stay orthonormal no matter how badly the input columns
# cluster — the property classical Gram-Schmidt loses first, and the
# whole reason for preferring QR here.
#
# Still deliberately NOT ported from the draft: eig / svd / cholesky /
# rank and every GPU dispatch path — the draft algorithms were sketches
# (eig eigenvectors were a placeholder identity; svd/rank sat on eig),
# and GPU belongs to the core Math/Metal machinery, not koala. The QR
# here is likewise NOT rank-revealing: there is no column pivoting, so
# a numerically dependent column is reported (nil) rather than worked
# around.
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

  # --- Householder QR and least squares ---

  # Relative cutoff for calling a QR pivot numerically zero. Column k is
  # linearly dependent on columns 0..k-1 when the part of it orthogonal
  # to them has shrunk below rank_tol × the column's own norm.
  #
  # 1e-12 sits four orders above f64 epsilon (2.2e-16) and six orders
  # below the smallest HONEST pivot in the ill-conditioned designs the
  # specs exercise (2.5e-6 relative on the Vandermonde), so it separates
  # "genuinely dependent" from "merely ill-conditioned" with six decades
  # of margin either side. Exactly collinear columns land at 0.
  -> .rank_tol
    1.to_f / 1000000000000.to_f

  # Householder triangularization, in place, on `a`: nr float rows of
  # `width` entries. The first `nc` columns are reflected to upper
  # triangular form and EVERY trailing column rides along — so an
  # augmented right-hand side (width = nc + 1) comes out as Q^T b for
  # free, with Q never formed.
  #
  # Returns the nc Householder vectors (each nr long, zero above its
  # own index) so a caller that wants Q can replay them; nil when a
  # column fails the .rank_tol test.
  -> .householder(a, nr, nc, width)
    tol = LinAlg.rank_tol
    # column norms BEFORE any reflection — the yardstick for rank
    norms = []
    nc.times -> (j)
      s = 0.to_f
      nr.times -> (i)
        s += a[i][j] * a[i][j]
      norms.push(Math.sqrt(s))
    vs = []
    ok = true
    nc.times -> (k)
      if ok
        # norm of the sub-column a[k..][k] still to be annihilated
        s = 0.to_f
        nr.times -> (i)
          s += a[i][k] * a[i][k] if i >= k
        nrm = Math.sqrt(s)
        if nrm <= norms[k] * tol
          ok = false
        else
          # reflect a[k..][k] onto -sign(a[k][k]) * nrm * e1; the sign
          # choice is what keeps v away from cancellation
          alpha = 0.to_f - nrm
          alpha = nrm if a[k][k] < 0
          v = []
          nr.times -> (i)
            if i < k
              v.push(0.to_f)
            else
              v.push(a[i][k])
          v[k] = v[k] - alpha
          vtv = 0.to_f
          nr.times -> (i)
            vtv += v[i] * v[i] if i >= k
          if vtv > 0
            width.times -> (j)
              if j > k
                d = 0.to_f
                nr.times -> (i)
                  d += v[i] * a[i][j] if i >= k
                f = (d + d) / vtv
                nr.times -> (i)
                  a[i][j] = a[i][j] - f * v[i] if i >= k
          a[k][k] = alpha
          nr.times -> (i)
            a[i][k] = 0.to_f if i > k
          vs.push(v)
    out = nil
    out = vs if ok
    out

  # Reduced ("thin") QR of an nr×nc matrix with nr >= nc:
  # m = q.matmul(r), q is nr×nc with orthonormal columns, r is nc×nc
  # upper triangular. Returns { q: Matrix, r: Matrix }.
  #
  # nil when the matrix is empty, when it is wider than it is tall
  # (nr < nc — no thin QR exists), or when a column is numerically
  # dependent on its predecessors (see .rank_tol; this QR does not
  # pivot, so it reports rank deficiency instead of surviving it).
  -> .qr(m)
    out = nil
    nr = m.row_count
    nc = m.col_count
    if nr > 0 && nc > 0 && nr >= nc
      a = LinAlg.float_rows(m)
      vs = LinAlg.householder(a, nr, nc, nc)
      if vs != nil
        # Q = H(0) H(1) ... H(nc-1) applied to the first nc identity
        # columns — replay the reflectors in REVERSE order.
        qrows = []
        nr.times -> (i)
          row = []
          nc.times -> (j)
            if i == j
              row.push(1.to_f)
            else
              row.push(0.to_f)
          qrows.push(row)
        nc.times -> (t)
          k = nc - 1 - t
          v = vs[k]
          vtv = 0.to_f
          nr.times -> (i)
            vtv += v[i] * v[i]
          if vtv > 0
            nc.times -> (j)
              d = 0.to_f
              nr.times -> (i)
                d += v[i] * qrows[i][j]
              f = (d + d) / vtv
              nr.times -> (i)
                qrows[i][j] = qrows[i][j] - f * v[i]
        rrows = []
        nc.times -> (i)
          row = []
          nc.times -> (j)
            if j < i
              row.push(0.to_f)
            else
              row.push(a[i][j])
          rrows.push(row)
        out = { q: Matrix.new(qrows), r: Matrix.new(rrows) }
    out

  # Least squares: the x minimizing |a*x - b| in the 2-norm, as a
  # Vector — by Householder QR on `a` itself with back substitution
  # through R. X^T X is NEVER formed, so the condition number is not
  # squared (see the header note).
  #
  # b may be a Vector or a plain array. nil when a is empty, when it
  # has fewer rows than columns (underdetermined), when b's size does
  # not match a's row count, or when a's columns are numerically
  # dependent (.rank_tol).
  -> .lstsq(a, b)
    out = nil
    bvals = b.to_a
    nr = a.row_count
    nc = a.col_count
    if nr > 0 && nc > 0 && nr >= nc && nr == bvals.size
      rows = LinAlg.float_rows(a)
      i = 0
      rows.each -> (row)
        row.push(bvals[i].to_f)
        i += 1
      # width nc + 1: the augmented column comes back as (Q^T b)
      vs = LinAlg.householder(rows, nr, nc, nc + 1)
      if vs != nil
        vals = []
        nc.times -> (t)
          vals.push(0.to_f)
        # back substitution through the upper-triangular R
        nc.times -> (t)
          k = nc - 1 - t
          s = rows[k][nc]
          nc.times -> (j)
            s = s - rows[k][j] * vals[j] if j > k
          vals[k] = s / rows[k][k]
        out = Vector.new(vals)
    out
