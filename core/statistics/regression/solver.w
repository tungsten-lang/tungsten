# Rank-revealing dense least-squares substrate for Statistics regression.
#
# Column-pivoted Householder QR avoids forming normal equations for the fit.
# The inverse cross-product is recovered from R only after full-rank status has
# been established. The reported condition estimate is the ratio of extreme
# |diag(R)| values, a useful QR diagnostic but not an exact 2-norm condition.

+ StatisticsRegressionSolveResult
  -> new(@coefficients, @bread, @permutation, @rank,
         @condition_estimate)

  -> coefficients
    Statistics.copy_vector(@coefficients)

  -> bread
    Statistics.copy_matrix(@bread)

  -> permutation
    copy = []
    @permutation.each -> (value)
      copy.push(value)
    copy

  ro :rank, :condition_estimate


+ StatisticsRegressionSolver
  -> .column_tail_norm(matrix, column, first_row)
    scale = ~0.0
    sum_squares = ~1.0
    row = first_row
    while row < matrix.size
      magnitude = matrix[row][column].abs
      if magnitude != ~0.0
        if scale < magnitude
          ratio = scale / magnitude
          sum_squares = ~1.0 + sum_squares * ratio * ratio
          scale = magnitude
        else
          ratio = magnitude / scale
          sum_squares += ratio * ratio
      row += 1
    return ~0.0 if scale == ~0.0
    scale * Math.sqrt(sum_squares)

  -> .swap_columns(matrix, left, right)
    if left == right
      return
    row = 0
    while row < matrix.size
      temporary = matrix[row][left]
      matrix[row][left] = matrix[row][right]
      matrix[row][right] = temporary
      row += 1

  -> .inverse_upper_triangular(upper)
    size = upper.size
    inverse = LinAlg.zeros(size, size)
    column = 0
    while column < size
      row = size - 1
      while row >= 0
        value = row == column ? ~1.0 : ~0.0
        index = row + 1
        while index < size
          value -= upper[row][index] * inverse[index][column]
          index += 1
        inverse[row][column] = value / upper[row][row]
        row -= 1
      column += 1
    inverse

  -> .solve(design, response, tolerance)
    row_count = design.size
    if row_count == 0
      raise "linear regression requires positive-weight observations"
    column_count = design[0].size
    if column_count == 0
      raise "linear regression requires at least one parameter"
    if row_count < column_count
      raise "linear regression is underdetermined"
    if response.size != row_count
      raise "linear regression design and response lengths differ"
    if tolerance <= ~0.0 || tolerance >= ~1.0
      raise "linear regression tolerance must be strictly between zero and one"

    matrix = LinAlg.copy_mat(design)
    transformed_response = Statistics.copy_vector(response)
    permutation = []
    column = 0
    while column < column_count
      permutation.push(column)
      column += 1

    initial_norm = ~0.0
    column = 0
    while column < column_count
      norm = StatisticsRegressionSolver.column_tail_norm(matrix, column, 0)
      initial_norm = norm if norm > initial_norm
      column += 1
    dimension = row_count > column_count ? row_count : column_count
    threshold = tolerance * initial_norm * (dimension + ~0.0)

    rank = 0
    step = 0
    while step < column_count
      pivot = step
      pivot_norm = StatisticsRegressionSolver.column_tail_norm(
        matrix, step, step)
      column = step + 1
      while column < column_count
        norm = StatisticsRegressionSolver.column_tail_norm(
          matrix, column, step)
        if norm > pivot_norm
          pivot = column
          pivot_norm = norm
        column += 1
      if pivot_norm <= threshold
        raise "linear regression design is rank deficient at rank " + rank.to_s

      StatisticsRegressionSolver.swap_columns(matrix, step, pivot)
      if pivot != step
        temporary = permutation[step]
        permutation[step] = permutation[pivot]
        permutation[pivot] = temporary

      alpha = matrix[step][step] >= ~0.0 ? ~0.0 - pivot_norm : pivot_norm
      vector = []
      row = step
      while row < row_count
        value = matrix[row][step]
        value -= alpha if row == step
        vector.push(value)
        row += 1
      vector_square = ~0.0
      index = 0
      while index < vector.size
        vector_square += vector[index] * vector[index]
        index += 1
      if vector_square == ~0.0
        raise "linear regression QR reflection became singular"
      beta = ~2.0 / vector_square

      column = step
      while column < column_count
        projection = ~0.0
        index = 0
        while index < vector.size
          projection += vector[index] * matrix[step + index][column]
          index += 1
        projection *= beta
        index = 0
        while index < vector.size
          matrix[step + index][column] -= projection * vector[index]
          index += 1
        column += 1
      projection = ~0.0
      index = 0
      while index < vector.size
        projection += vector[index] * transformed_response[step + index]
        index += 1
      projection *= beta
      index = 0
      while index < vector.size
        transformed_response[step + index] -= projection * vector[index]
        index += 1
      matrix[step][step] = alpha
      row = step + 1
      while row < row_count
        matrix[row][step] = ~0.0
        row += 1
      rank += 1
      step += 1

    upper = LinAlg.zeros(column_count, column_count)
    row = 0
    while row < column_count
      column = row
      while column < column_count
        upper[row][column] = matrix[row][column]
        column += 1
      row += 1

    pivot_coefficients = []
    column_count.times ->
      pivot_coefficients.push(~0.0)
    row = column_count - 1
    while row >= 0
      value = transformed_response[row]
      column = row + 1
      while column < column_count
        value -= upper[row][column] * pivot_coefficients[column]
        column += 1
      pivot_coefficients[row] = value / upper[row][row]
      Statistics.finite_result(
        pivot_coefficients[row], "linear regression coefficient")
      row -= 1

    coefficients = []
    column_count.times ->
      coefficients.push(~0.0)
    column = 0
    while column < column_count
      coefficients[permutation[column]] = pivot_coefficients[column]
      column += 1

    inverse_upper = StatisticsRegressionSolver.inverse_upper_triangular(upper)
    pivot_bread = LinAlg.zeros(column_count, column_count)
    row = 0
    while row < column_count
      column = 0
      while column < column_count
        value = ~0.0
        index = 0
        while index < column_count
          value += inverse_upper[row][index] * inverse_upper[column][index]
          index += 1
        pivot_bread[row][column] = value
        column += 1
      row += 1
    bread = LinAlg.zeros(column_count, column_count)
    row = 0
    while row < column_count
      column = 0
      while column < column_count
        bread[permutation[row]][permutation[column]] = pivot_bread[row][column]
        Statistics.finite_result(
          bread[permutation[row]][permutation[column]],
          "linear regression covariance substrate")
        column += 1
      row += 1

    largest_diagonal = ~0.0
    smallest_diagonal = nil
    index = 0
    while index < column_count
      magnitude = upper[index][index].abs
      largest_diagonal = magnitude if magnitude > largest_diagonal
      if smallest_diagonal == nil || magnitude < smallest_diagonal
        smallest_diagonal = magnitude
      index += 1
    condition_estimate = largest_diagonal / smallest_diagonal
    Statistics.finite_result(condition_estimate, "linear regression condition estimate")
    if condition_estimate > ~1.0 / tolerance
      raise "linear regression design is ill-conditioned at the requested tolerance"

    StatisticsRegressionSolveResult.new(
      coefficients, bread, permutation, rank, condition_estimate)
