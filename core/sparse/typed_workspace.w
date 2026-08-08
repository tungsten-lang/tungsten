# Typed f64 work buffers for portable sparse iterative methods.
#
# The public sparse matrix remains canonical CSR backed by ordinary Arrays.
# A solve copies that immutable representation once into raw i64/f64 arrays;
# every subsequent SpMV and vector update then avoids per-element boxing.  The
# copy is O(rows + nnz), does not densify, and is local to the solve.

+ SparseF64Workspace
  -> .zeros(n)
    out = f64[n]
    sparse_f64_fill(out, ~0.0, n)
    out

  -> .copy(values)
    n = values.size()
    out = f64[n]
    i = 0
    while i < n
      out[i] = values[i] + ~0.0
      i = i + 1
    out

  -> .matrix(matrix)
    rows = matrix.rows
    nnz = matrix.nnz
    ptr = i64[rows + 1]
    indices = i64[nnz]
    data = f64[nnz]
    i = 0
    while i <= rows
      ptr[i] = matrix.indptr_at(i)
      i = i + 1
    i = 0
    while i < nnz
      indices[i] = matrix.indices_at(i)
      data[i] = matrix.data_at(i) + ~0.0
      i = i + 1
    [ptr, indices, data]

-> sparse_f64_fill(out, value, n) (f64[] f64 i64) i64
  i = 0 ## i64
  while i < n
    out[i] = value
    i = i + 1
  0

-> sparse_f64_copy(source, out, n) (f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    out[i] = source[i]
    i = i + 1
  0

-> sparse_f64_dot(left, right, n) (f64[] f64[] i64) f64
  total = ~0.0
  i = 0 ## i64
  while i < n
    total = total + left[i] * right[i]
    i = i + 1
  total

-> sparse_f64_norm(values, n) (f64[] i64) f64
  Math.sqrt(sparse_f64_dot(values, values, n))

-> sparse_f64_csr_matvec(ptr, indices, data, x, out, rows) (i64[] i64[] f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < rows
    total = ~0.0
    p = ptr[i]
    pend = ptr[i + 1]
    while p < pend
      total = total + data[p] * x[indices[p]]
      p = p + 1
    out[i] = total
    i = i + 1
  0

-> sparse_f64_residual(rhs, product, out, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    out[i] = rhs[i] - product[i]
    i = i + 1
  0

-> sparse_f64_precondition(values, inverse, out, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  if inverse.size() == 0
    while i < n
      out[i] = values[i]
      i = i + 1
    return 0
  while i < n
    out[i] = values[i] * inverse[i]
    i = i + 1
  0

-> sparse_f64_cg_step(x, residual, direction, product, alpha, n) (f64[] f64[] f64[] f64[] f64 i64) i64
  i = 0 ## i64
  while i < n
    x[i] = x[i] + alpha * direction[i]
    residual[i] = residual[i] - alpha * product[i]
    i = i + 1
  0

-> sparse_f64_cg_direction(direction, preconditioned, beta, n) (f64[] f64[] f64 i64) i64
  i = 0 ## i64
  while i < n
    direction[i] = preconditioned[i] + beta * direction[i]
    i = i + 1
  0

-> sparse_f64_bicg_direction(direction, residual, product, beta, omega, n) (f64[] f64[] f64[] f64 f64 i64) i64
  i = 0 ## i64
  while i < n
    direction[i] = residual[i] + beta * (direction[i] - omega * product[i])
    i = i + 1
  0

-> sparse_f64_difference(left, right, scale, out, n) (f64[] f64[] f64 f64[] i64) i64
  i = 0 ## i64
  while i < n
    out[i] = left[i] - scale * right[i]
    i = i + 1
  0

-> sparse_f64_add_scaled(out, values, scale, n) (f64[] f64[] f64 i64) i64
  i = 0 ## i64
  while i < n
    out[i] = out[i] + scale * values[i]
    i = i + 1
  0
