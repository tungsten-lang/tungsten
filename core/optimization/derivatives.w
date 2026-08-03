# Optimization derivatives — binary64 finite differences and explicit
# adapters to Calculus automatic differentiation.

+ Optimization
  -> .integer_value?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .copy_numeric_vector(values, name = "optimization vector")
    if values.class_name != "Array" || values.size == 0
      raise name + " must be a nonempty Array"
    answer = []
    i = 0
    while i < values.size
      value = values[i] + ~0.0
      if !Optimization.finite_value?(value)
        raise name + " entries must be finite"
      answer.push(value)
      i += 1
    answer

  -> .copy_vector(values)
    answer = []
    i = 0
    while i < values.size
      answer.push(values[i] + ~0.0)
      i += 1
    answer

  -> .zero_vector(size)
    answer = []
    size.times -> answer.push(~0.0)
    answer

  -> .zero_matrix(rows, columns)
    answer = []
    i = 0
    while i < rows
      answer.push(Optimization.zero_vector(columns))
      i += 1
    answer

  -> .identity_matrix(size)
    answer = Optimization.zero_matrix(size, size)
    i = 0
    while i < size
      answer[i][i] = ~1.0
      i += 1
    answer

  -> .dot(left, right)
    total = ~0.0
    i = 0
    while i < left.size
      total += left[i] * right[i]
      i += 1
    total

  # Scaled sum-of-squares avoids needless overflow and underflow in the norm
  # itself. Squaring the returned norm for an objective can still overflow;
  # callers classify that as a non-finite numerical failure.
  -> .euclidean_norm(values)
    scale = ~0.0
    sum = ~1.0
    i = 0
    while i < values.size
      magnitude = values[i].abs
      if magnitude != ~0.0
        if scale < magnitude
          ratio = scale / magnitude
          sum = ~1.0 + sum * ratio * ratio
          scale = magnitude
        else
          ratio = magnitude / scale
          sum += ratio * ratio
      i += 1
    return ~0.0 if scale == ~0.0
    scale * Math.sqrt(sum)

  -> .infinity_norm(values)
    answer = ~0.0
    i = 0
    while i < values.size
      magnitude = values[i].abs
      answer = magnitude if magnitude > answer
      i += 1
    answer

  -> .finite_vector?(values)
    return false if values.class_name != "Array"
    i = 0
    while i < values.size
      value = values[i]
      return false if value.class_name == "Array"
      numeric = value + ~0.0
      return false if !Optimization.finite_value?(numeric)
      i += 1
    true

  -> .representable_difference_step(value, relative_step = nil)
    step = relative_step
    step = ~1.4901161193847656e-8 if step == nil
    step = step + ~0.0
    if !Optimization.finite_value?(step) || step <= ~0.0
      return nil
    magnitude = value.abs
    magnitude = ~1.0 if magnitude < ~1.0
    increment = step * magnitude
    attempts = 0
    while attempts < 16 && (value + increment == value || value - increment == value)
      increment *= ~2.0
      attempts += 1
    if (!Optimization.finite_value?(increment) ||
        value + increment == value || value - increment == value)
      return nil
    increment

  -> .difference_step(value, relative_step = nil)
    increment = Optimization.representable_difference_step(
      value, relative_step)
    if increment == nil
      raise "finite-difference step must be positive, finite, and representable"
    increment

  -> .finite_difference_derivative(function, point, relative_step = nil)
    x = point + ~0.0
    if !Optimization.finite_value?(x)
      raise "finite-difference point must be finite"
    h = Optimization.difference_step(x, relative_step)
    upper = function(x + h) + ~0.0
    lower = function(x - h) + ~0.0
    if (!Optimization.finite_value?(upper) ||
        !Optimization.finite_value?(lower))
      raise "finite-difference callback returned a non-finite value"
    derivative = (upper - lower) / (~2.0 * h)
    if !Optimization.finite_value?(derivative)
      raise "finite-difference derivative is non-finite"
    derivative

  -> .finite_difference_gradient(function, point, relative_step = nil)
    x = Optimization.copy_numeric_vector(point, "finite-difference point")
    gradient = []
    i = 0
    while i < x.size
      h = Optimization.difference_step(x[i], relative_step)
      upper_point = Optimization.copy_vector(x)
      lower_point = Optimization.copy_vector(x)
      upper_point[i] += h
      lower_point[i] -= h
      upper = function(upper_point) + ~0.0
      lower = function(lower_point) + ~0.0
      if (!Optimization.finite_value?(upper) ||
          !Optimization.finite_value?(lower))
        raise "finite-difference callback returned a non-finite value"
      derivative = (upper - lower) / (~2.0 * h)
      if !Optimization.finite_value?(derivative)
        raise "finite-difference gradient is non-finite"
      gradient.push(derivative)
      i += 1
    gradient

  -> .finite_difference_jacobian(function, point, relative_step = nil)
    x = Optimization.copy_numeric_vector(point, "finite-difference point")
    columns = []
    output_size = nil
    parameter = 0
    while parameter < x.size
      h = Optimization.difference_step(x[parameter], relative_step)
      upper_point = Optimization.copy_vector(x)
      lower_point = Optimization.copy_vector(x)
      upper_point[parameter] += h
      lower_point[parameter] -= h
      upper = function(upper_point)
      lower = function(lower_point)
      if upper.class_name != "Array" || lower.class_name != "Array"
        raise "finite-difference Jacobian callback must return an Array"
      if upper.size == 0 || upper.size != lower.size
        raise "finite-difference Jacobian residual size changed"
      output_size = upper.size if output_size == nil
      if upper.size != output_size
        raise "finite-difference Jacobian residual size changed"
      column = []
      row = 0
      while row < output_size
        upper_value = upper[row] + ~0.0
        lower_value = lower[row] + ~0.0
        if (!Optimization.finite_value?(upper_value) ||
            !Optimization.finite_value?(lower_value))
          raise "finite-difference Jacobian callback returned a non-finite value"
        derivative = (upper_value - lower_value) / (~2.0 * h)
        if !Optimization.finite_value?(derivative)
          raise "finite-difference Jacobian is non-finite"
        column.push(derivative)
        row += 1
      columns.push(column)
      parameter += 1
    jacobian = Optimization.zero_matrix(output_size, x.size)
    parameter = 0
    while parameter < x.size
      row = 0
      while row < output_size
        jacobian[row][parameter] = columns[parameter][row]
        row += 1
      parameter += 1
    jacobian

  # These adapters are opt-in: the callback must use operations supported by
  # Differential. Unsupported operations remain loud and are never silently
  # replaced by finite differences.
  -> .autodiff_gradient_adapter(function)
    -> (point) Calculus.gradient(function, point)

  -> .autodiff_jacobian_adapter(function)
    -> (point) Calculus.jacobian(function, point)
