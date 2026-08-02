# Shared exact-symbolic helpers for differential geometry.
#
# Geometry deliberately stores symbolic tensor fields as nested Arrays of
# Expression leaves.  Numeric evaluation is a view obtained by substituting a
# chart point, while the symbolic source remains available for differentiation.

+ Geometry
  -> .zero
    Expression.constant(0)

  -> .one
    Expression.constant(1)

  -> .half
    Expression.constant(Rational.new(1, 2))

  -> .simplify_scalar(value)
    Expression.wrap(value).simplify

  -> .zero_scalar?(value)
    Geometry.simplify_scalar(value) == Geometry.zero

  -> .copy_array(values)
    out = []
    values.each -> (value) out.push(value)
    out

  -> .deep_copy(value)
    return value if value.class_name != "Array"
    out = []
    value.each -> (item) out.push(Geometry.deep_copy(item))
    out

  -> .validate_tensor_shape(value, dimension, depth)
    if depth == 0
      if value.class_name == "Array"
        raise "tensor scalar position contains an Array"
      return true
    if value.class_name != "Array" || value.size != dimension
      raise "tensor component shape does not match chart dimension and rank"
    value.each -> (item)
      Geometry.validate_tensor_shape(item, dimension, depth - 1)
    true

  -> .wrap_tensor(value, dimension, depth)
    Geometry.validate_tensor_shape(value, dimension, depth)
    return Expression.wrap(value) if depth == 0
    out = []
    value.each -> (item)
      out.push(Geometry.wrap_tensor(item, dimension, depth - 1))
    out

  -> .zero_tensor(dimension, depth)
    return Geometry.zero if depth == 0
    out = []
    dimension.times -> out.push(Geometry.zero_tensor(dimension, depth - 1))
    out

  -> .component_at(components, indices)
    value = components
    indices.each -> (index) value = value[index]
    value

  -> .evaluate_tensor(value, bindings)
    if value.class_name != "Array"
      return Expression.wrap(value).evaluate(bindings)
    out = []
    value.each -> (item)
      out.push(Geometry.evaluate_tensor(item, bindings))
    out

  -> .simplify_tensor(value)
    if value.class_name != "Array"
      return Geometry.simplify_scalar(value)
    out = []
    value.each -> (item) out.push(Geometry.simplify_tensor(item))
    out

  -> .matrix_minor(matrix, omitted_row, omitted_column)
    out = []
    row = 0
    while row < matrix.size
      if row != omitted_row
        result_row = []
        column = 0
        while column < matrix.size
          if column != omitted_column
            result_row.push(matrix[row][column])
          column += 1
        out.push(result_row)
      row += 1
    out

  -> .matrix_diagonal?(matrix)
    row = 0
    while row < matrix.size
      column = 0
      while column < matrix.size
        if row != column && !Geometry.zero_scalar?(matrix[row][column])
          return false
        column += 1
      row += 1
    true

  # Exact determinant by a diagonal fast path followed by Laplace expansion.
  # This is intentionally a small-metric algorithm; factorial work is bounded
  # by Metric's dimension guard and keeps Expression coefficients exact.
  -> .matrix_determinant(matrix)
    dimension = matrix.size
    return Geometry.one if dimension == 0
    return Geometry.simplify_scalar(matrix[0][0]) if dimension == 1
    if Geometry.matrix_diagonal?(matrix)
      value = Geometry.one
      i = 0
      while i < dimension
        value *= matrix[i][i]
        i += 1
      return Geometry.simplify_scalar(value)
    value = Geometry.zero
    column = 0
    while column < dimension
      entry = matrix[0][column]
      if !Geometry.zero_scalar?(entry)
        term = entry * Geometry.matrix_determinant(
          Geometry.matrix_minor(matrix, 0, column))
        term = -term if column.odd?
        value += term
      column += 1
    Geometry.simplify_scalar(value)

  -> .matrix_inverse(matrix)
    dimension = matrix.size
    if dimension == 0 || dimension > 6
      raise "symbolic metric inverse supports dimensions 1 through 6"
    determinant = Geometry.matrix_determinant(matrix)
    if Geometry.zero_scalar?(determinant)
      raise "metric matrix is singular"
    inverse = Geometry.zero_tensor(dimension, 2)
    if Geometry.matrix_diagonal?(matrix)
      i = 0
      while i < dimension
        inverse[i][i] = Geometry.simplify_scalar(
          Geometry.one / matrix[i][i])
        i += 1
      return inverse
    row = 0
    while row < dimension
      column = 0
      while column < dimension
        cofactor = Geometry.matrix_determinant(
          Geometry.matrix_minor(matrix, column, row))
        cofactor = -cofactor if (row + column).odd?
        inverse[row][column] = Geometry.simplify_scalar(
          cofactor / determinant)
        column += 1
      row += 1
    inverse
