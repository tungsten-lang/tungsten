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
    a = m.to_a
    nr = a.size
    if nr > 0
      nc = a[0].size
      i = 0
      while i < nr
        r = a[i]
        row = []
        j = 0
        while j < nc
          row.push(r[j].to_f)
          j += 1
        rows.push(row)
        i += 1
    rows

  # Determinant; nil unless square. 0 when singular.
  -> .det(m)
    out = nil
    if m.square?
      n = m.row_count
      a = LinAlg.float_rows(m)
      detv = 1.to_f
      singular = false
      k = 0
      while k < n
        if !singular
          # partial pivot: largest |a[t][k]| for t >= k
          best = -1
          bestv = 0.to_f
          t = k
          while t < n
            av = a[t][k]
            av = 0.to_f - av if av < 0.to_f
            if av > bestv
              bestv = av
              best = t
            t += 1
          if best == -1 || bestv == 0
            singular = true
          else
            if best != k
              tmp = a[k]
              a[k] = a[best]
              a[best] = tmp
              detv = 0.to_f - detv
            ak = a[k]
            piv = ak[k]
            detv = detv * piv
            r = k + 1
            while r < n
              ar = a[r]
              factor = ar[k] / piv
              c = k
              while c < n
                ar[c] = ar[c] - factor * ak[c]
                c += 1
              r += 1
        k += 1
      out = 0.to_f
      out = detv if !singular
    out

  # Gauss-Jordan reduction in place on n rows of width m (augmented).
  # Returns the reduced rows, or nil if the left n×n block is singular.
  -> .reduce_rows(a, n, m)
    ok = true
    k = 0
    while k < n
      if ok
        best = -1
        bestv = 0.to_f
        t = k
        while t < n
          av = a[t][k]
          av = 0.to_f - av if av < 0.to_f
          if av > bestv
            bestv = av
            best = t
          t += 1
        if best == -1 || bestv == 0
          ok = false
        else
          if best != k
            tmp = a[k]
            a[k] = a[best]
            a[best] = tmp
          ak = a[k]
          piv = ak[k]
          c = 0
          while c < m
            ak[c] = ak[c] / piv
            c += 1
          r = 0
          while r < n
            if r != k
              ar = a[r]
              factor = ar[k]
              c = 0
              while c < m
                ar[c] = ar[c] - factor * ak[c]
                c += 1
            r += 1
      k += 1
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
      while i < n
        a[i].push(bvals[i].to_f)
        i += 1
      red = LinAlg.reduce_rows(a, n, n + 1)
      if red != nil
        vals = []
        i = 0
        while i < n
          vals.push(red[i][n])
          i += 1
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
      while i < n
        row = a[i]
        j = 0
        while j < n
          if i == j
            row.push(1.to_f)
          else
            row.push(0.to_f)
          j += 1
        i += 1
      red = LinAlg.reduce_rows(a, n, 2 * n)
      if red != nil
        rows = []
        i = 0
        while i < n
          row = red[i]
          rr = []
          j = 0
          while j < n
            rr.push(row[n + j])
            j += 1
          rows.push(rr)
          i += 1
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
    j = 0
    while j < nc
      s = 0.to_f
      i = 0
      while i < nr
        v_ij = a[i][j]
        s += v_ij * v_ij
        i += 1
      norms.push(Math.sqrt(s))
      j += 1
    vs = []
    ok = true
    k = 0
    while k < nc
      if ok
        # norm of the sub-column a[k..][k] still to be annihilated
        s = 0.to_f
        i = k
        while i < nr
          aik = a[i][k]
          s += aik * aik
          i += 1
        nrm = Math.sqrt(s)
        if nrm <= norms[k] * tol
          ok = false
        else
          # reflect a[k..][k] onto -sign(a[k][k]) * nrm * e1; the sign
          # choice is what keeps v away from cancellation
          alpha = 0.to_f - nrm
          alpha = nrm if a[k][k] < 0
          v = []
          i = 0
          while i < k
            v.push(0.to_f)
            i += 1
          while i < nr
            v.push(a[i][k])
            i += 1
          v[k] = v[k] - alpha
          vtv = 0.to_f
          i = k
          while i < nr
            vi = v[i]
            vtv += vi * vi
            i += 1
          if vtv > 0
            j = k + 1
            while j < width
              d = 0.to_f
              i = k
              while i < nr
                d += v[i] * a[i][j]
                i += 1
              f = (d + d) / vtv
              i = k
              while i < nr
                a[i][j] = a[i][j] - f * v[i]
                i += 1
              j += 1
          a[k][k] = alpha
          i = k + 1
          while i < nr
            a[i][k] = 0.to_f
            i += 1
          vs.push(v)
      k += 1
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
        i = 0
        while i < nr
          row = []
          j = 0
          while j < nc
            if i == j
              row.push(1.to_f)
            else
              row.push(0.to_f)
            j += 1
          qrows.push(row)
          i += 1
        t = 0
        while t < nc
          k = nc - 1 - t
          v = vs[k]
          vtv = 0.to_f
          i = k
          while i < nr
            vi = v[i]
            vtv += vi * vi
            i += 1
          if vtv > 0
            j = 0
            while j < nc
              d = 0.to_f
              i = k
              while i < nr
                d += v[i] * qrows[i][j]
                i += 1
              f = (d + d) / vtv
              i = k
              while i < nr
                qrows[i][j] = qrows[i][j] - f * v[i]
                i += 1
              j += 1
          t += 1
        rrows = []
        i = 0
        while i < nc
          ai = a[i]
          row = []
          j = 0
          while j < nc
            if j < i
              row.push(0.to_f)
            else
              row.push(ai[j])
            j += 1
          rrows.push(row)
          i += 1
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
      while i < nr
        rows[i].push(bvals[i].to_f)
        i += 1
      # width nc + 1: the augmented column comes back as (Q^T b)
      vs = LinAlg.householder(rows, nr, nc, nc + 1)
      if vs != nil
        vals = []
        t = 0
        while t < nc
          vals.push(0.to_f)
          t += 1
        # back substitution through the upper-triangular R
        t = 0
        while t < nc
          k = nc - 1 - t
          rk = rows[k]
          s = rk[nc]
          j = k + 1
          while j < nc
            s = s - rk[j] * vals[j]
            j += 1
          vals[k] = s / rk[k]
          t += 1
        out = Vector.new(vals)
    out
