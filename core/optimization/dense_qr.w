# Dense pivoted QR helpers for small binary64 optimization systems.
#
# Modified Gram-Schmidt with column pivoting is used instead of forming J'J
# for Gauss-Newton. The reported condition estimate is the ratio of largest to
# smallest accepted |diag(R)|, not a singular-value condition number.

+ Optimization
  -> .validate_dense_matrix(matrix, rows, columns, name)
    if matrix.class_name != "Array" || matrix.size != rows
      raise name + " must have the expected row count"
    answer = []
    i = 0
    while i < rows
      source = matrix[i]
      if source.class_name != "Array" || source.size != columns
        raise name + " rows must have the expected column count"
      row = []
      j = 0
      while j < columns
        value = source[j] + ~0.0
        if !Optimization.finite_value?(value)
          raise name + " entries must be finite"
        row.push(value)
        j += 1
      answer.push(row)
      i += 1
    answer

  -> .matrix_vector(matrix, vector)
    answer = []
    i = 0
    while i < matrix.size
      answer.push(Optimization.dot(matrix[i], vector))
      i += 1
    answer

  -> .transpose_matrix_vector(matrix, vector)
    columns = matrix[0].size
    answer = Optimization.zero_vector(columns)
    i = 0
    while i < matrix.size
      j = 0
      while j < columns
        answer[j] += matrix[i][j] * vector[i]
        j += 1
      i += 1
    answer

  -> .jacobian_column_norms_squared(matrix)
    columns = matrix[0].size
    answer = Optimization.zero_vector(columns)
    i = 0
    while i < matrix.size
      j = 0
      while j < columns
        answer[j] += matrix[i][j] * matrix[i][j]
        j += 1
      i += 1
    answer

  -> .pivoted_qr_least_squares(matrix, right_hand_side,
                                rank_tolerance)
    rows = matrix.size
    columns = matrix[0].size
    work_columns = []
    permutation = []
    norms_squared = []
    column = 0
    while column < columns
      values = []
      row = 0
      while row < rows
        values.push(matrix[row][column])
        row += 1
      work_columns.push(values)
      permutation.push(column)
      norms_squared.push(Optimization.dot(values, values))
      column += 1

    largest_initial_squared = ~0.0
    norms_squared.each ->
      largest_initial_squared = item if item > largest_initial_squared
    if !Optimization.finite_value?(largest_initial_squared)
      return {"solution": nil, "rank": 0,
              "condition_estimate": nil, "permutation": permutation,
              "r_diagonal": Optimization.zero_vector(columns),
              "finite": false}
    largest_initial = Math.sqrt(largest_initial_squared)
    threshold = rank_tolerance * largest_initial

    r = Optimization.zero_matrix(columns, columns)
    q_transpose_b = Optimization.zero_vector(columns)
    rank = 0
    smallest_diagonal = nil
    largest_diagonal = ~0.0
    k = 0
    while k < columns
      pivot = k
      pivot_norm = norms_squared[k]
      j = k + 1
      while j < columns
        if norms_squared[j] > pivot_norm
          pivot = j
          pivot_norm = norms_squared[j]
        j += 1
      if pivot != k
        temporary_column = work_columns[k]
        work_columns[k] = work_columns[pivot]
        work_columns[pivot] = temporary_column
        temporary_norm = norms_squared[k]
        norms_squared[k] = norms_squared[pivot]
        norms_squared[pivot] = temporary_norm
        temporary_index = permutation[k]
        permutation[k] = permutation[pivot]
        permutation[pivot] = temporary_index
        previous = 0
        while previous < k
          temporary_r = r[previous][k]
          r[previous][k] = r[previous][pivot]
          r[previous][pivot] = temporary_r
          previous += 1
      diagonal = Optimization.euclidean_norm(work_columns[k])
      break if diagonal == ~0.0 || diagonal <= threshold
      if !Optimization.finite_value?(diagonal)
        return {"solution": nil, "rank": rank,
                "condition_estimate": nil,
                "permutation": permutation,
                "r_diagonal": (0...columns).map -> r[i][i],
                "finite": false}
      r[k][k] = diagonal
      largest_diagonal = diagonal if diagonal > largest_diagonal
      if smallest_diagonal == nil || diagonal < smallest_diagonal
        smallest_diagonal = diagonal
      q = []
      row = 0
      while row < rows
        q.push(work_columns[k][row] / diagonal)
        row += 1
      q_transpose_b[k] = Optimization.dot(q, right_hand_side)
      j = k + 1
      while j < columns
        coefficient = Optimization.dot(q, work_columns[j])
        if !Optimization.finite_value?(coefficient)
          return {"solution": nil, "rank": rank,
                  "condition_estimate": nil,
                  "permutation": permutation,
                  "r_diagonal": (0...columns).map -> r[i][i],
                  "finite": false}
        r[k][j] = coefficient
        row = 0
        while row < rows
          work_columns[j][row] -= coefficient * q[row]
          row += 1
        norms_squared[j] = Optimization.dot(
          work_columns[j], work_columns[j])
        if !Optimization.finite_value?(norms_squared[j])
          return {"solution": nil, "rank": rank,
                  "condition_estimate": nil,
                  "permutation": permutation,
                  "r_diagonal": (0...columns).map -> r[i][i],
                  "finite": false}
        j += 1
      rank += 1
      k += 1

    condition = nil
    if rank > 0 && smallest_diagonal != nil && smallest_diagonal > ~0.0
      condition = largest_diagonal / smallest_diagonal
    solution = nil
    if rank == columns
      pivoted_solution = Optimization.zero_vector(columns)
      row = columns - 1
      while row >= 0
        value = q_transpose_b[row]
        j = row + 1
        while j < columns
          value -= r[row][j] * pivoted_solution[j]
          j += 1
        pivoted_solution[row] = value / r[row][row]
        row -= 1
      solution = Optimization.zero_vector(columns)
      j = 0
      while j < columns
        solution[permutation[j]] = pivoted_solution[j]
        j += 1
      if !Optimization.finite_vector?(solution)
        return {"solution": nil, "rank": rank,
                "condition_estimate": condition,
                "permutation": permutation,
                "r_diagonal": (0...columns).map -> r[i][i],
                "finite": false}
    {
      "solution": solution,
      "rank": rank,
      "condition_estimate": condition,
      "permutation": permutation,
      "r_diagonal": (0...columns).map -> r[i][i],
      "finite": true
    }

  -> .augmented_lm_system(jacobian, residual, damping)
    rows = jacobian.size
    columns = jacobian[0].size
    scales = Optimization.jacobian_column_norms_squared(jacobian)
    matrix = []
    i = 0
    while i < rows
      matrix.push(Optimization.copy_vector(jacobian[i]))
      i += 1
    rhs = []
    residual.each -> rhs.push(~0.0 - item)
    column = 0
    while column < columns
      row = Optimization.zero_vector(columns)
      scale = scales[column]
      scale = ~1.0 if scale < ~1.0e-30
      row[column] = Math.sqrt(damping * scale)
      matrix.push(row)
      rhs.push(~0.0)
      column += 1
    {"matrix": matrix, "rhs": rhs, "scales": scales}
