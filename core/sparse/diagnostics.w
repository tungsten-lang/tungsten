# SparseDiagnostics — storage-aware diagnostics that do not pretend to be a
# floating-point SVD. Structural rank is the maximum bipartite matching size
# of the sparsity pattern: it is an upper bound on numerical rank and is exact
# for generic nonzero values, but it cannot detect value-dependent dependence.

+ SparseDiagnostics
  -> .structural_rank(matrix)
    a = matrix.to_csr
    match_row = []
    i = 0
    while i < a.rows
      match_row = match_row.push(-1)
      i = i + 1
    match_col = []
    j = 0
    while j < a.cols
      match_col = match_col.push(-1)
      j = j + 1
    rank = 0
    root = 0
    while root < a.rows
      seen_row = []
      parent_row = []
      i = 0
      while i < a.rows
        seen_row = seen_row.push(false)
        parent_row = parent_row.push(-1)
        i = i + 1
      seen_col = []
      parent_col = []
      j = 0
      while j < a.cols
        seen_col = seen_col.push(false)
        parent_col = parent_col.push(-1)
        j = j + 1
      queue = [root]
      seen_row[root] = true
      head = 0
      free_col = -1
      while head < queue.size() && free_col == -1
        row = queue[head]
        head = head + 1
        p = a.indptr_at(row)
        pend = a.indptr_at(row + 1)
        while p < pend && free_col == -1
          col = a.indices_at(p)
          if seen_col[col] == false
            seen_col[col] = true
            parent_col[col] = row
            matched = match_col[col]
            if matched == -1
              free_col = col
            elsif seen_row[matched] == false
              seen_row[matched] = true
              parent_row[matched] = col
              queue = queue.push(matched)
          p = p + 1
      if free_col != -1
        col = free_col
        while col != -1
          row = parent_col[col]
          previous = match_row[row]
          match_row[row] = col
          match_col[col] = row
          col = previous
        rank = rank + 1
      root = root + 1
    rank
