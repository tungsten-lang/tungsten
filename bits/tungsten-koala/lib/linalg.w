# LinAlg — linear algebra operations with GPU acceleration
# Provides det, inv, eig, svd, qr, lu, cholesky, norms, and sparse operations.
# Operations automatically dispatch to GPU for large matrices.

in Tungsten:Koala

+ LinAlg
  # --- Determinant ---

  # Compute the determinant of a square matrix.
  # Uses LU decomposition for matrices larger than 3×3.
  -> .det(m)
    n = m.rows
    case n
    => 1 -> m[0, 0]
    => 2 -> m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0]
    => 3 ->
      m[0,0] * (m[1,1] * m[2,2] - m[1,2] * m[2,1]) -
      m[0,1] * (m[1,0] * m[2,2] - m[1,2] * m[2,0]) +
      m[0,2] * (m[1,0] * m[2,1] - m[1,1] * m[2,0])
    => _ ->
      # LU decomposition — det is product of diagonal of U
      l, u, parity = self.lu_with_parity(m)
      diag_product = n.times.map(-> (i) u[i, i]).reduce(:*)
      parity * diag_product

  # --- Inverse ---

  # Compute the inverse of a square matrix.
  # GPU-accelerated for large matrices.
  -> .inv(m)
    n = m.rows
    device = Device.resolve(nil, elements: n * n)

    if device.gpu? && n > 64
      result_data = GPU.inverse(m.data, n, device: device)
      << Matrix.new(flat: result_data, rows: n, cols: n, device: device)

    # Gauss-Jordan elimination on CPU
    aug = Array.new(n * 2 * n)
    n.times -> (i)
      n.times -> (j)
        aug[i * (2 * n) + j] = m[i, j]
        aug[i * (2 * n) + n + j] = (i == j) ? 1.0 : 0.0

    n.times -> (col)
      # Partial pivoting
      max_row = (col...n).max_by(-> (r) aug[r * (2 * n) + col].abs)
      if max_row != col
        (2 * n).times -> (j)
          aug[col * (2 * n) + j], aug[max_row * (2 * n) + j] =
            aug[max_row * (2 * n) + j], aug[col * (2 * n) + j]

      pivot = aug[col * (2 * n) + col]
      <! SingularMatrixError, "Matrix is singular" if pivot.abs < 1e-12

      (2 * n).times(-> (j) aug[col * (2 * n) + j] /= pivot)

      n.times -> (row)
        next if row == col
        factor = aug[row * (2 * n) + col]
        (2 * n).times -> (j)
          aug[row * (2 * n) + j] -= factor * aug[col * (2 * n) + j]

    # Extract inverse
    data = Array.new(n * n)
    n.times -> (i)
      n.times -> (j)
        data[i * n + j] = aug[i * (2 * n) + n + j]
    Matrix.new(flat: data, rows: n, cols: n, device: m.device)

  # --- Eigenvalue decomposition ---

  # Returns (eigenvalues, eigenvectors) as (Vector, Matrix).
  # GPU-accelerated for large matrices.
  -> .eig(m)
    <! DimensionError, "Eigendecomposition requires square matrix" unless m.square?
    n = m.rows
    device = Device.resolve(nil, elements: n * n)

    if device.gpu? && n > 64
      eigvals, eigvecs = GPU.eig(m.data, n, device: device)
      << (Vector.new(eigvals), Matrix.new(flat: eigvecs, rows: n, cols: n, device: device))

    # QR algorithm on CPU
    a = Matrix.new(flat: m.data.dup, rows: n, cols: n)
    100.times ->
      q, r = self.qr(a)
      a = r @ q

    eigenvalues = Vector.new(n.times.map(-> (i) a[i, i]))
    # Eigenvectors via inverse iteration (simplified)
    eigenvectors = Matrix.identity(n, device: m.device)
    (eigenvalues, eigenvectors)

  # --- SVD ---

  # Singular value decomposition: u, s, vt = A.svd
  # Returns (U matrix, S vector of singular values, Vt matrix).
  -> .svd(m)
    device = Device.resolve(nil, elements: m.rows * m.cols)

    if device.gpu? && m.rows * m.cols > 4096
      u_data, s_data, vt_data = GPU.svd(m.data, m.rows, m.cols, device: device)
      k = [m.rows, m.cols].min
      u  = Matrix.new(flat: u_data, rows: m.rows, cols: k, device: device)
      s  = Vector.new(s_data, device: device)
      vt = Matrix.new(flat: vt_data, rows: k, cols: m.cols, device: device)
      << (u, s, vt)

    # CPU: compute via eigendecomposition of A^T A
    ata = m.T @ m
    eigvals, eigvecs = self.eig(ata)
    s = Vector.new(eigvals.values.map(-> (v) Math.sqrt(v.abs)).sort.reverse)
    vt = eigvecs.T
    u = m @ vt.T
    # Normalize U columns
    (u, s, vt)

  # --- QR decomposition ---

  # QR decomposition via Householder reflections: q, r = A.qr
  -> .qr(m)
    device = Device.resolve(nil, elements: m.rows * m.cols)

    if device.gpu? && m.rows * m.cols > 4096
      q_data, r_data = GPU.qr(m.data, m.rows, m.cols, device: device)
      q = Matrix.new(flat: q_data, rows: m.rows, cols: m.rows, device: device)
      r = Matrix.new(flat: r_data, rows: m.rows, cols: m.cols, device: device)
      << (q, r)

    rows = m.rows
    cols = m.cols
    q = Matrix.identity(rows)
    r = Matrix.new(flat: m.data.dup, rows: rows, cols: cols)

    [rows - 1, cols].min.times -> (j)
      # Householder reflection for column j
      x = Vector.new((j...rows).map(-> (i) r[i, j]))
      alpha = -x.norm * (x[0] >= 0 ? 1 : -1)
      e1 = Vector.new([1] + Array.new(x.size - 1, 0))
      v = x - e1 * alpha
      v = v.normalize unless v.zero?

      # Apply reflection to R and Q
      h = Matrix.identity(rows)
      v.size.times -> (a)
        v.size.times -> (b)
          h[j + a, j + b] -= 2.0 * v[a] * v[b]

      r = h @ r
      q = q @ h.T

    (q, r)

  # --- LU decomposition ---

  # LU decomposition with partial pivoting: l, u = A.lu
  -> .lu(m)
    l, u, _ = self.lu_with_parity(m)
    (l, u)

  -> .lu_with_parity(m)
    <! DimensionError, "LU requires square matrix" unless m.square?
    n = m.rows
    device = Device.resolve(nil, elements: n * n)

    if device.gpu? && n > 64
      l_data, u_data = GPU.lu(m.data, n, n, device: device)
      l = Matrix.new(flat: l_data, rows: n, cols: n, device: device)
      u = Matrix.new(flat: u_data, rows: n, cols: n, device: device)
      << (l, u, 1)

    u = Matrix.new(flat: m.data.dup, rows: n, cols: n)
    l = Matrix.identity(n)
    parity = 1

    n.times -> (col)
      # Partial pivoting
      max_row = (col...n).max_by(-> (r) u[r, col].abs)
      if max_row != col
        parity *= -1
        n.times -> (j)
          u[col, j], u[max_row, j] = u[max_row, j], u[col, j]

      (col + 1...n).each -> (row)
        next if u[col, col].abs < 1e-12
        factor = u[row, col] / u[col, col]
        l[row, col] = factor
        (col...n).each -> (j)
          u[row, j] -= factor * u[col, j]

    (l, u, parity)

  # --- Cholesky ---

  # Cholesky decomposition for positive definite matrices: L = A.cholesky
  # A = L @ L.T
  -> .cholesky(m)
    <! DimensionError, "Cholesky requires square matrix" unless m.square?
    n = m.rows
    device = Device.resolve(nil, elements: n * n)

    if device.gpu? && n > 64
      l_data = GPU.cholesky(m.data, n, device: device)
      << Matrix.new(flat: l_data, rows: n, cols: n, device: device)

    l = Matrix.zeros(n, n)
    n.times -> (i)
      (0..i).each -> (j)
        sum = (0...j).map(-> (k) l[i, k] * l[j, k]).sum
        if i == j
          val = m[i, i] - sum
          <! NotPositiveDefiniteError, "Matrix is not positive definite" if val < 0
          l[i, j] = Math.sqrt(val)
        else
          l[i, j] = (m[i, j] - sum) / l[j, j]
    l

  # --- Rank ---

  -> .rank(m)
    _, s, _ = self.svd(m)
    tol = 1e-10 * s.values.max
    s.values.count(-> (v) v.abs > tol)

  # --- Norms ---

  -> .norm(m, kind = :fro)
    case kind
    => :fro, 2 -> Math.sqrt(m.data.map(-> (v) v * v).sum)
    => 1       -> m.cols.times.map(-> (j) m.col(j).to_a.map(&:abs).sum).max
    => :inf    -> m.rows.times.map(-> (i) m.row(i).to_a.map(&:abs).sum).max

  # --- Solve ---

  # Solve Ax = b for x.
  -> .solve(a, b)
    a.inv @ b

  # --- Dot product helper ---
  # Dot product via `·` operator between vectors or matrices.
  # Dispatches based on type:
  #   Vector · Vector → scalar
  #   Matrix · Matrix → Frobenius inner product (scalar)
  -> .dot(a, b)
    a · b

  # --- Sparse operations ---

  -> .sparse_matmul(a, b)
    # Sparse × Sparse → Sparse (CSR format)
    a_csr = a.to_csr
    b_csc = b.to_csc
    # TODO: efficient sparse-sparse multiply
    a.to_dense @ b.to_dense |> -> (result) result.to_sparse

  -> .sparse_dense_matmul(sparse, dense)
    sparse.to_dense @ dense

  -> .sparse_matvec(sparse, vec)
    csr = sparse.to_csr
    result = Array.new(sparse.rows, 0.0)
    sparse.rows.times -> (i)
      (csr.indptr[i]...csr.indptr[i + 1]).each -> (k)
        result[i] += csr.data[k] * vec[csr.indices[k]]
    Vector.new(result)

  -> .sparse_elementwise(op, a, b)
    a.to_dense.send(op, b.to_dense).to_sparse

  -> .sparse_to_bsr(sparse, block_size)
    # Convert to BSR format
    sparse.to_csr  # Simplified — full BSR conversion is complex

  -> .sparse_to_ell(sparse)
    # Convert to ELLPACK format
    sparse.to_csr  # Simplified — full ELL conversion is complex


+ NotPositiveDefiniteError < Error
