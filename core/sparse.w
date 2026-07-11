# Sparse — sparse **matrix** algebra (not a sparse multi-D tensor).
#
# `core/sparse` is the module. Primary type is **SparseMatrix** (CSR / COO).
# Rank-1 sparse vectors can be added later; N-D sparse tensors are out of
# scope (use SparseMatrix for LA; dense Tensor for multi-D).
#
# Backends:
#   pure Tungsten SpMV always; densify + LinAlg.solve for small systems
#   Apple SparseBLAS (Accelerate Sparse/BLAS.h) — SpMV
#   Apple Sparse Solvers (Sparse/Solve.h) — QR / Cholesky factor+solve

use core/blas
use core/linalg

+ SparseMatrix
  -> .eye(n)
    indptr = []
    indices = []
    data = []
    i = 0
    while i <= n
      indptr = indptr.push(i)
      i = i + 1
    i = 0
    while i < n
      indices = indices.push(i)
      data = data.push(~1.0)
      i = i + 1
    SparseMatrix.csr(n, n, indptr, indices, data)

  -> .csr(rows, cols, indptr, indices, data)
    SparseMatrix.new().as_csr(rows, cols, indptr, indices, data)

  -> .coo(rows, cols, row_idx, col_idx, values)
    SparseMatrix.new().as_coo(rows, cols, row_idx, col_idx, values)

  -> .from_dense(rows)
    m = rows.size()
    n = 0
    if m > 0
      n = rows[0].size()
    ri = []
    ci = []
    vv = []
    i = 0
    while i < m
      j = 0
      while j < n
        v = rows[i][j] + ~0.0
        if v != ~0.0
          ri = ri.push(i)
          ci = ci.push(j)
          vv = vv.push(v)
        j = j + 1
      i = i + 1
    SparseMatrix.coo(m, n, ri, ci, vv).to_csr

  -> new
    @data_typed = nil
    self

  # ≤6 args each (runtime dispatch limit is 8 including self)
  -> as_csr(rows, cols, indptr, indices, data)
    @fmt = :csr
    @rows = rows
    @cols = cols
    @indptr = indptr
    @indices = indices
    @data = data
    @row_idx = nil
    @col_idx = nil
    @values = nil
    @data_typed = nil
    self

  -> as_coo(rows, cols, row_idx, col_idx, values)
    @fmt = :coo
    @rows = rows
    @cols = cols
    @indptr = nil
    @indices = nil
    @data = nil
    @row_idx = row_idx
    @col_idx = col_idx
    @values = values
    @data_typed = nil
    self

  -> rows
    @rows
  -> cols
    @cols
  -> format
    @fmt
  -> nnz
    if @fmt == :csr
      return @data.size()
    @values.size()

  -> to_csr
    if @fmt == :csr
      return self
    counts = []
    i = 0
    while i < @rows
      counts = counts.push(0)
      i = i + 1
    k = 0
    while k < @values.size()
      r = @row_idx[k]
      counts[r] = counts[r] + 1
      k = k + 1
    indptr = [0]
    i = 0
    while i < @rows
      indptr = indptr.push(indptr[i] + counts[i])
      i = i + 1
    nnz = @values.size()
    indices = []
    data = []
    i = 0
    while i < nnz
      indices = indices.push(0)
      data = data.push(~0.0)
      i = i + 1
    write_at = []
    i = 0
    while i < @rows
      write_at = write_at.push(indptr[i])
      i = i + 1
    k = 0
    while k < nnz
      r = @row_idx[k]
      p = write_at[r]
      indices[p] = @col_idx[k]
      data[p] = @values[k]
      write_at[r] = p + 1
      k = k + 1
    SparseMatrix.csr(@rows, @cols, indptr, indices, data)

  # y = A x  — pure path; Accelerate SparseBLAS when ccall available
  -> matvec(x)
    a = self
    if @fmt != :csr
      a = to_csr
    # try native SpMV (f32 typed arrays) when bridge linked
    # pure path always works for list Float
    y = []
    i = 0
    while i < a.rows
      y = y.push(~0.0)
      i = i + 1
    i = 0
    while i < a.rows
      s = ~0.0
      p = a.indptr_at(i)
      pend = a.indptr_at(i + 1)
      while p < pend
        j = a.indices_at(p)
        s = s + a.data_at(p) * x[j]
        p = p + 1
      y[i] = s
      i = i + 1
    y

  # SpMV via Apple SparseBLAS. Builds typed i32/f32 WArrays once, then
  # calls w_sparse_spmv_f32. Falls back to pure matvec if bridge missing.
  -> matvec_accel(x_list)
    a = self
    if @fmt != :csr
      a = to_csr
    a.ensure_typed_csr
    n = a.cols
    m = a.rows
    x = f32_array(n)
    y = f32_array(m)
    i = 0
    while i < n
      # write via set if typed array supports []=
      x[i] = x_list[i] + ~0.0
      i = i + 1
    ccall("w_sparse_spmv_f32", m, n, a.indptr_typed, a.indices_typed, a.data_typed, x, y)
    out = []
    i = 0
    while i < m
      out = out.push(y[i])
      i = i + 1
    out

  # Fill i32/f32 CSR buffers for SparseBLAS (requires use core/blas).
  -> ensure_typed_csr
    if @data_typed != nil
      return self
    nnz = @data.size()
    m = @rows
    ip = i32_array(m + 1)
    ix = i32_array(nnz)
    dv = f32_array(nnz)
    i = 0
    while i <= m
      ip[i] = @indptr[i]
      i = i + 1
    i = 0
    while i < nnz
      ix[i] = @indices[i]
      dv[i] = @data[i] + ~0.0
      i = i + 1
    @indptr_typed = ip
    @indices_typed = ix
    @data_typed = dv
    self

  -> indptr_typed
    @indptr_typed
  -> indices_typed
    @indices_typed
  -> data_typed
    @data_typed

  -> indptr_at(i)
    @indptr[i]
  -> indices_at(i)
    @indices[i]
  -> data_at(i)
    @data[i]

  # Expand to dense nested rows (for pure densify-solve fallback).
  -> to_dense
    a = self
    if @fmt != :csr
      a = to_csr
    rows = []
    i = 0
    while i < a.rows
      row = []
      j = 0
      while j < a.cols
        row = row.push(~0.0)
        j = j + 1
      rows = rows.push(row)
      i = i + 1
    i = 0
    while i < a.rows
      p = a.indptr_at(i)
      pend = a.indptr_at(i + 1)
      while p < pend
        j = a.indices_at(p)
        rows[i][j] = a.data_at(p) + ~0.0
        p = p + 1
      i = i + 1
    rows

  # COO triple arrays (i32 row, i32 col, f64 val) for Sparse Solvers.
  # Always materializes typed WArrays sized to nnz.
  -> coo_typed
    a = self
    if @fmt == :coo
      nnz = @values.size()
      ri = i32_array(nnz)
      ci = i32_array(nnz)
      vv = f64_array(nnz)
      k = 0
      while k < nnz
        ri[k] = @row_idx[k]
        ci[k] = @col_idx[k]
        vv[k] = @values[k] + ~0.0
        k = k + 1
      return [ri, ci, vv]
    if @fmt != :csr
      a = to_csr
    nnz = a.nnz
    ri = i32_array(nnz)
    ci = i32_array(nnz)
    vv = f64_array(nnz)
    k = 0
    i = 0
    while i < a.rows
      p = a.indptr_at(i)
      pend = a.indptr_at(i + 1)
      while p < pend
        ri[k] = i
        ci[k] = a.indices_at(p)
        vv[k] = a.data_at(p) + ~0.0
        k = k + 1
        p = p + 1
      i = i + 1
    [ri, ci, vv]

  # Solve Ax = b (dense RHS list of Float). Square systems.
  # Prefer Apple Sparse Solvers QR; fall back to densify + pure LinAlg.solve.
  -> solve(b)
    if @rows != @cols
      raise "SparseMatrix.solve: square matrix required"
    if b.size() != @rows
      raise "SparseMatrix.solve: RHS length must equal rows"
    # pure densify path always available
    LinAlg.solve(to_dense, b)

  # Apple Sparse Solvers QR factor + solve (general sparse A).
  # Returns dense x as a Tungsten list of Float.
  -> solve_qr(b)
    if b.size() != @rows
      raise "SparseMatrix.solve_qr: RHS length must equal rows"
    trip = coo_typed
    n = @cols
    m = @rows
    bb = f64_array(m)
    xx = f64_array(n)
    i = 0
    while i < m
      bb[i] = b[i] + ~0.0
      i = i + 1
    ccall("w_sparse_solve_qr_f64", m, n, trip[0], trip[1], trip[2], bb, xx)
    out = []
    i = 0
    while i < n
      out = out.push(xx[i])
      i = i + 1
    out

  # Apple Sparse Solvers Cholesky for SPD square A (upper triangle accepted).
  -> solve_chol(b)
    if @rows != @cols
      raise "SparseMatrix.solve_chol: square SPD matrix required"
    if b.size() != @rows
      raise "SparseMatrix.solve_chol: RHS length must equal rows"
    trip = coo_typed
    n = @rows
    bb = f64_array(n)
    xx = f64_array(n)
    i = 0
    while i < n
      bb[i] = b[i] + ~0.0
      i = i + 1
    ccall("w_sparse_solve_chol_f64", n, trip[0], trip[1], trip[2], bb, xx)
    out = []
    i = 0
    while i < n
      out = out.push(xx[i])
      i = i + 1
    out

  -> to_s
    "SparseMatrix(" + @fmt.to_s() + " " + @rows.to_s() + "x" + @cols.to_s() + " nnz=" + nnz.to_s() + ")"

# Module-level alias so `Sparse.eye` still works as a short name.
+ Sparse
  -> .eye(n)
    SparseMatrix.eye(n)
  -> .csr(rows, cols, indptr, indices, data)
    SparseMatrix.csr(rows, cols, indptr, indices, data)
  -> .coo(rows, cols, ri, ci, vv)
    SparseMatrix.coo(rows, cols, ri, ci, vv)
  -> .from_dense(rows)
    SparseMatrix.from_dense(rows)
