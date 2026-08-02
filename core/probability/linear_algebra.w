# Checked dense linear algebra used by multivariate probability algorithms.
#
# Core LinAlg supplies general matrix operations.  This layer adds probability-
# specific shape/domain checks, symmetric-positive-definite factorization, and
# triangular solves without widening LinAlg's public contract.

use core/math
use core/linalg
use core/probability/primitives

+ ProbabilityLinearAlgebra
  -> .absolute(value)
    value < ~0.0 ? ~0.0 - value : value

  -> .vector(values, parameter = "vector")
    if values.class_name != "Array" || values.size == 0
      raise "probability " + parameter + " must be a nonempty Array"
    copy = []
    i = 0
    while i < values.size
      copy.push(ProbabilityNumerics.finite_float(
        values[i], parameter + " entry"))
      i += 1
    copy

  -> .vector_dimension(values, dimension, parameter = "vector")
    copy = ProbabilityLinearAlgebra.vector(values, parameter)
    if copy.size != dimension
      raise "probability " + parameter + " has the wrong dimension"
    copy

  -> .matrix(values, parameter = "matrix")
    if values.class_name != "Array" || values.size == 0
      raise "probability " + parameter + " must be a nonempty Array"
    width = nil
    matrix = []
    i = 0
    while i < values.size
      row = values[i]
      if row.class_name != "Array" || row.size == 0
        raise "probability " + parameter + " rows must be nonempty Arrays"
      width = row.size if width == nil
      if row.size != width
        raise "probability " + parameter + " rows must have equal size"
      matrix.push(ProbabilityLinearAlgebra.vector(
        row, parameter + " row"))
      i += 1
    matrix

  -> .square_matrix(values, dimension = nil, parameter = "matrix")
    matrix = ProbabilityLinearAlgebra.matrix(values, parameter)
    if matrix.size != matrix[0].size
      raise "probability " + parameter + " must be square"
    if dimension != nil && matrix.size != dimension
      raise "probability " + parameter + " has the wrong dimension"
    matrix

  -> .copy_matrix(matrix)
    copy = []
    i = 0
    while i < matrix.size
      copy.push(ProbabilityNumerics.copy_array(matrix[i]))
      i += 1
    copy

  -> .symmetric_matrix(values, dimension = nil, parameter = "covariance")
    matrix = ProbabilityLinearAlgebra.square_matrix(
      values, dimension, parameter)
    tolerance = ~1.0e-12
    i = 0
    while i < matrix.size
      j = 0
      while j < i
        difference = ProbabilityLinearAlgebra.absolute(
          matrix[i][j] - matrix[j][i])
        scale = ProbabilityLinearAlgebra.absolute(matrix[i][j])
        other_scale = ProbabilityLinearAlgebra.absolute(matrix[j][i])
        scale = other_scale if other_scale > scale
        scale = ~1.0 if scale < ~1.0
        if difference > tolerance*scale
          raise "probability " + parameter + " must be symmetric"
        average = ~0.5*(matrix[i][j] + matrix[j][i])
        matrix[i][j] = average
        matrix[j][i] = average
        j += 1
      i += 1
    matrix

  # Unpivoted Cholesky is appropriate only after explicit SPD validation.
  # It deliberately rejects semidefinite matrices rather than adding jitter.
  -> .cholesky(values, parameter = "covariance")
    matrix = ProbabilityLinearAlgebra.symmetric_matrix(
      values, nil, parameter)
    dimension = matrix.size
    lower = LinAlg.zeros(dimension, dimension)
    i = 0
    while i < dimension
      j = 0
      while j <= i
        total = matrix[i][j]
        k = 0
        while k < j
          total -= lower[i][k]*lower[j][k]
          k += 1
        if i == j
          if total <= ~0.0 || total != total
            raise "probability " + parameter + " must be positive definite"
          lower[i][j] = Math.sqrt(total)
        else
          lower[i][j] = total / lower[j][j]
        j += 1
      i += 1
    lower

  -> .lower_solve(lower, values)
    dimension = lower.size
    vector = ProbabilityLinearAlgebra.vector_dimension(
      values, dimension, "triangular right-hand side")
    solution = []
    i = 0
    while i < dimension
      total = vector[i]
      j = 0
      while j < i
        total -= lower[i][j]*solution[j]
        j += 1
      if lower[i][i] == ~0.0
        raise "probability triangular system is singular"
      solution.push(total / lower[i][i])
      i += 1
    solution

  -> .lower_transpose_solve(lower, values)
    dimension = lower.size
    vector = ProbabilityLinearAlgebra.vector_dimension(
      values, dimension, "triangular right-hand side")
    solution = []
    dimension.times -> solution.push(~0.0)
    i = dimension - 1
    while i >= 0
      total = vector[i]
      j = i + 1
      while j < dimension
        total -= lower[j][i]*solution[j]
        j += 1
      if lower[i][i] == ~0.0
        raise "probability triangular system is singular"
      solution[i] = total / lower[i][i]
      i -= 1
    solution

  -> .solve_spd(matrix, values)
    lower = ProbabilityLinearAlgebra.cholesky(matrix)
    ProbabilityLinearAlgebra.solve_spd_from_cholesky(lower, values)

  -> .solve_spd_from_cholesky(lower, values)
    intermediate = ProbabilityLinearAlgebra.lower_solve(lower, values)
    ProbabilityLinearAlgebra.lower_transpose_solve(lower, intermediate)

  -> .dot(left, right)
    if left.size != right.size
      raise "probability dot product dimensions must match"
    products = []
    i = 0
    while i < left.size
      products.push(left[i]*right[i])
      i += 1
    ProbabilityNumerics.sum(products)

  -> .matvec(matrix, vector)
    if matrix.size == 0 || matrix[0].size != vector.size
      raise "probability matrix-vector dimensions must match"
    result = []
    i = 0
    while i < matrix.size
      result.push(ProbabilityLinearAlgebra.dot(matrix[i], vector))
      i += 1
    result

  -> .transpose(matrix)
    result = LinAlg.zeros(matrix[0].size, matrix.size)
    i = 0
    while i < matrix.size
      j = 0
      while j < matrix[0].size
        result[j][i] = matrix[i][j]
        j += 1
      i += 1
    result

  -> .matmul(left, right)
    if left.size == 0 || right.size == 0 || left[0].size != right.size
      raise "probability matrix dimensions must match"
    LinAlg.matmul(left, right)

  -> .subtract(left, right)
    if left.size != right.size
      raise "probability vector dimensions must match"
    result = []
    i = 0
    while i < left.size
      result.push(left[i] - right[i])
      i += 1
    result

  -> .add(left, right)
    if left.size != right.size
      raise "probability vector dimensions must match"
    result = []
    i = 0
    while i < left.size
      result.push(left[i] + right[i])
      i += 1
    result

  -> .scale(vector, scalar)
    result = []
    i = 0
    while i < vector.size
      result.push(vector[i]*scalar)
      i += 1
    result

  -> .log_determinant_from_cholesky(lower)
    logs = []
    i = 0
    while i < lower.size
      logs.push(Math.log(lower[i][i]))
      i += 1
    ~2.0*ProbabilityNumerics.sum(logs)

  -> .mahalanobis_squared(lower, difference)
    standardized = ProbabilityLinearAlgebra.lower_solve(lower, difference)
    ProbabilityLinearAlgebra.dot(standardized, standardized)

  -> .validate_indices(indices, dimension, parameter = "indices")
    if indices.class_name != "Array" || indices.size == 0
      raise "probability " + parameter + " must be a nonempty Array"
    seen = []
    dimension.times -> seen.push(false)
    copy = []
    i = 0
    while i < indices.size
      index = indices[i]
      if !ProbabilityNumerics.integer?(index) || index < 0 || index >= dimension
        raise "probability " + parameter + " entry is out of range"
      if seen[index]
        raise "probability " + parameter + " entries must be unique"
      seen[index] = true
      copy.push(index)
      i += 1
    copy

  -> .subvector(vector, indices)
    result = []
    i = 0
    while i < indices.size
      result.push(vector[indices[i]])
      i += 1
    result

  -> .submatrix(matrix, row_indices, column_indices)
    result = []
    i = 0
    while i < row_indices.size
      row = []
      j = 0
      while j < column_indices.size
        row.push(matrix[row_indices[i]][column_indices[j]])
        j += 1
      result.push(row)
      i += 1
    result
