# SparseStorage — validation and canonical CSR construction.
#
# A canonical CSR matrix has monotonically increasing column indices in each
# row, no duplicate coordinates, and no explicitly stored zeros. Keeping that
# invariant in one place makes every operator deterministic and prevents a
# malformed user-supplied pointer array from escaping into native SparseBLAS.

+ SparseStorage
  -> .validate_dimensions(rows, cols)
    if rows < 0 || cols < 0
      raise "SparseMatrix: dimensions must be non-negative"
    true

  -> .validate_csr(rows, cols, indptr, indices, data)
    SparseStorage.validate_dimensions(rows, cols)
    if indptr == nil || indices == nil || data == nil
      raise "SparseMatrix.csr: indptr, indices, and data are required"
    if indptr.size() != rows + 1
      raise "SparseMatrix.csr: indptr length must equal rows + 1"
    if indices.size() != data.size()
      raise "SparseMatrix.csr: indices and data lengths differ"
    if indptr[0] != 0
      raise "SparseMatrix.csr: indptr must start at zero"
    nnz = data.size()
    if indptr[rows] != nnz
      raise "SparseMatrix.csr: indptr must end at nnz"
    i = 0
    while i < rows
      if indptr[i] < 0 || indptr[i] > indptr[i + 1] || indptr[i + 1] > nnz
        raise "SparseMatrix.csr: indptr must be monotone and bounded by nnz"
      i = i + 1
    k = 0
    while k < nnz
      if indices[k] < 0 || indices[k] >= cols
        raise "SparseMatrix.csr: column index out of range"
      k = k + 1
    true

  -> .validate_coo(rows, cols, row_idx, col_idx, values)
    SparseStorage.validate_dimensions(rows, cols)
    if row_idx == nil || col_idx == nil || values == nil
      raise "SparseMatrix.coo: row_idx, col_idx, and values are required"
    if row_idx.size() != col_idx.size() || row_idx.size() != values.size()
      raise "SparseMatrix.coo: coordinate and value lengths differ"
    k = 0
    while k < values.size()
      if row_idx[k] < 0 || row_idx[k] >= rows
        raise "SparseMatrix.coo: row index out of range"
      if col_idx[k] < 0 || col_idx[k] >= cols
        raise "SparseMatrix.coo: column index out of range"
      k = k + 1
    true

  # Validate, sort each row, coalesce duplicate coordinates, and drop stored
  # zeros. The returned arrays do not alias the caller's arrays.
  -> .canonical_csr(rows, cols, indptr, indices, data)
    SparseStorage.validate_csr(rows, cols, indptr, indices, data)
    out_ptr = [0]
    out_indices = []
    out_data = []
    i = 0
    while i < rows
      entries = []
      p = indptr[i]
      pend = indptr[i + 1]
      while p < pend
        entries = entries.push([indices[p], data[p] + ~0.0])
        p = p + 1
      ordered = entries.sort -> (left, right)
        left[0] <=> right[0]
      k = 0
      while k < ordered.size()
        col = ordered[k][0]
        value = ordered[k][1]
        k = k + 1
        while k < ordered.size() && ordered[k][0] == col
          value = value + ordered[k][1]
          k = k + 1
        if value != ~0.0
          out_indices = out_indices.push(col)
          out_data = out_data.push(value)
      out_ptr = out_ptr.push(out_data.size())
      i = i + 1
    [out_ptr, out_indices, out_data]

  -> .copy_coo(rows, cols, row_idx, col_idx, values)
    SparseStorage.validate_coo(rows, cols, row_idx, col_idx, values)
    ri = []
    ci = []
    vv = []
    k = 0
    while k < values.size()
      ri = ri.push(row_idx[k])
      ci = ci.push(col_idx[k])
      vv = vv.push(values[k] + ~0.0)
      k = k + 1
    [ri, ci, vv]
