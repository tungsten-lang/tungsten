# SparseFrame — thin DataFrame ↔ core SparseMatrix bridge.
#
# Dense multi-D and GPU work live on core Tensor. Sparse **matrix**
# algebra lives on core SparseMatrix (CSR / COO, pure SpMV, Accelerate
# SparseBLAS when linked). This file only converts koala DataFrames /
# row arrays to and from SparseMatrix — it does not reimplement SPA.
#
#     sm = SparseFrame.from_rows([[0, 1], [0, 0], [2, 0]])
#     sm.matvec([1, 1])
#     df = SparseFrame.to_frame(sm, ["a", "b"])
#
# Loaded via `use koala` only as a helper namespace; programs that need
# SparseMatrix directly can `use` core sparse without this file.
#
# NOTE: core SparseMatrix uses ~0.0 float forms and while-loops. This
# wrapper stays on koala conventions (no float literals; .to_f).

+ SparseFrame
  # Nested row arrays (or a DataFrame's numeric columns as a Matrix)
  # → core SparseMatrix in COO then CSR. Zeros are dropped. nil when
  # there are no rows.
  -> .from_rows(rows)
    out = nil
    if rows != nil && rows.size > 0
      m = rows.size
      n = rows[0].size
      ri = []
      ci = []
      vv = []
      i = 0
      rows.each -> (row)
        j = 0
        row.each -> (v)
          f = 0.to_f
          f = v.to_f if v != nil
          if f != 0.to_f
            ri.push(i)
            ci.push(j)
            vv.push(f)
          j += 1
        i += 1
      out = SparseMatrix.coo(m, n, ri, ci, vv).to_csr
    out

  # Numeric columns of a DataFrame as SparseMatrix (column order
  # preserved). nil when the frame has no numeric column.
  -> .from_frame(df)
    out = nil
    m = df.to_matrix
    out = SparseFrame.from_rows(m.to_a) if m != nil
    out

  # SparseMatrix → nested dense row arrays (zeros filled).
  -> .to_rows(sm)
    sm.to_dense

  # SparseMatrix → DataFrame with the given column names (or x0..).
  -> .to_frame(sm, names = nil)
    rows = sm.to_dense
    n = 0
    n = rows[0].size if rows.size > 0
    col_names = names
    if col_names == nil
      col_names = []
      j = 0
      while j < n
        col_names.push("x" + j.to_s)
        j += 1
    pairs = []
    j = 0
    while j < n
      col = []
      rows.each -> (r)
        col.push(r[j])
      pairs.push([col_names[j], col])
      j += 1
    DataFrame.new(pairs)
