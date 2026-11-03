# Portable sparse preconditioners with explicit construction failure.
#
# `:ichol0` is zero-fill incomplete Cholesky.  Construction requires an
# exactly symmetric canonical CSR matrix and a finite positive pivot in every
# row.  Any missing diagonal, asymmetry, non-finite factor entry, or nonpositive
# pivot returns nil; iterative callers translate that deterministic setup
# failure to SparseSolveResult(:breakdown, ...).  Factors retain only the input
# lower-triangle pattern and its transpose, so setup and application stay
# sparse.

+ SparsePreconditioner
  -> .nonfinite?(value)
    value.nan? || value.infinite?

  -> .prepare(matrix, kind)
    if kind == :none
      return SparsePreconditioner.new().as_diagonal(SparseF64Workspace.zeros(0))
    if kind == :jacobi
      inverse = f64[matrix.rows]
      i = 0
      while i < matrix.rows
        diagonal = matrix.at(i, i)
        if diagonal == ~0.0 || SparsePreconditioner.nonfinite?(diagonal)
          return nil
        inverse[i] = ~1.0 / diagonal
        i = i + 1
      return SparsePreconditioner.new().as_diagonal(inverse)
    SparsePreconditioner.incomplete_cholesky_zero(matrix)

  -> .incomplete_cholesky_zero(matrix)
    if matrix.rows != matrix.cols
      return nil
    a = matrix.to_csr
    transposed = a.transpose
    i = 0
    while i <= a.rows
      if a.indptr_at(i) != transposed.indptr_at(i)
        return nil
      i = i + 1
    p = 0
    while p < a.nnz
      if a.indices_at(p) != transposed.indices_at(p) || a.data_at(p) != transposed.data_at(p)
        return nil
      p = p + 1

    lower_ptr = [0]
    lower_indices = []
    lower_values = []
    row = 0
    while row < a.rows
      diagonal_found = false
      diagonal_value = ~0.0
      p = a.indptr_at(row)
      pend = a.indptr_at(row + 1)
      while p < pend
        col = a.indices_at(p)
        if col < row
          value = a.data_at(p)
          left = lower_ptr[row]
          left_end = lower_values.size()
          right = lower_ptr[col]
          right_end = lower_ptr[col + 1]
          while left < left_end && right < right_end
            left_col = lower_indices[left]
            right_col = lower_indices[right]
            if left_col >= col || right_col >= col
              break
            if left_col == right_col
              value = value - lower_values[left] * lower_values[right]
              left = left + 1
              right = right + 1
            elsif left_col < right_col
              left = left + 1
            else
              right = right + 1
          diagonal = lower_values[lower_ptr[col + 1] - 1]
          factor_value = value / diagonal
          if SparsePreconditioner.nonfinite?(factor_value)
            return nil
          lower_indices = lower_indices.push(col)
          lower_values = lower_values.push(factor_value)
        elsif col == row
          diagonal_found = true
          diagonal_value = a.data_at(p)
        p = p + 1
      if !diagonal_found || SparsePreconditioner.nonfinite?(diagonal_value)
        return nil
      q = lower_ptr[row]
      while q < lower_values.size()
        diagonal_value = diagonal_value - lower_values[q] * lower_values[q]
        q = q + 1
      if SparsePreconditioner.nonfinite?(diagonal_value) || diagonal_value <= ~0.0
        return nil
      diagonal = Math.sqrt(diagonal_value)
      if SparsePreconditioner.nonfinite?(diagonal) || diagonal <= ~0.0
        return nil
      lower_indices = lower_indices.push(row)
      lower_values = lower_values.push(diagonal)
      lower_ptr = lower_ptr.push(lower_values.size())
      row = row + 1

    lower = SparseMatrix.csr(a.rows, a.cols, lower_ptr, lower_indices, lower_values)
    lower_buffers = SparseF64Workspace.matrix(lower)
    upper_buffers = SparseF64Workspace.matrix(lower.transpose)
    SparsePreconditioner.new().as_incomplete_cholesky(lower_buffers, upper_buffers)

  -> as_diagonal(@inverse)
    @kind = :diagonal
    self

  -> as_incomplete_cholesky(lower, upper)
    @kind = :ichol0
    @lower_ptr = lower[0]
    @lower_indices = lower[1]
    @lower_data = lower[2]
    @upper_ptr = upper[0]
    @upper_indices = upper[1]
    @upper_data = upper[2]
    self

  -> apply(values, out, scratch)
    n = values.size()
    if @kind == :diagonal
      sparse_f64_precondition(values, @inverse, out, n)
      return out
    sparse_f64_forward_solve(@lower_ptr, @lower_indices, @lower_data, values, scratch, n)
    sparse_f64_backward_solve(@upper_ptr, @upper_indices, @upper_data, scratch, out, n)
    out

-> sparse_f64_forward_solve(ptr, indices, data, rhs, out, n) (i64[] i64[] f64[] f64[] f64[] i64) i64
  row = 0 ## i64
  while row < n
    value = rhs[row]
    p = ptr[row]
    pend = ptr[row + 1]
    while p + 1 < pend
      value = value - data[p] * out[indices[p]]
      p = p + 1
    out[row] = value / data[pend - 1]
    row = row + 1
  0

-> sparse_f64_backward_solve(ptr, indices, data, rhs, out, n) (i64[] i64[] f64[] f64[] f64[] i64) i64
  row = n - 1
  while row >= 0
    value = rhs[row]
    p = ptr[row]
    pend = ptr[row + 1]
    diagonal = data[p]
    p = p + 1
    while p < pend
      value = value - data[p] * out[indices[p]]
      p = p + 1
    out[row] = value / diagonal
    row = row - 1
  0
