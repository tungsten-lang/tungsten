# Differential — second-order multivariate automatic differentiation.
#
# A value carries its gradient and Hessian.  Unary transcendental functions
# apply the exact chain rule; binary arithmetic composes the tensors directly.
# This gives gradients, Jacobians, and Hessians in one function evaluation.

+ Differential
  -> new(@value, gradient, hessian)
    if gradient.class_name != "Array" || hessian.class_name != "Array"
      raise "Differential needs Array gradient and Hessian"
    @gradient = Calculus.copy_vector(gradient)
    @hessian = Calculus.copy_matrix(hessian)
    if @hessian.size != @gradient.size
      raise "Differential Hessian dimension mismatch"
    i = 0
    while i < @hessian.size
      if @hessian[i].size != @gradient.size
        raise "Differential Hessian must be square"
      i += 1

  -> .constant(value, dimension)
    Differential.new(
      value,
      Calculus.zero_vector(dimension),
      Calculus.zero_matrix(dimension))

  -> .variable(value, dimension, index)
    if index < 0 || index >= dimension
      raise "Differential variable index is out of range"
    gradient = Calculus.zero_vector(dimension)
    gradient[index] = ~1.0
    Differential.new(value, gradient, Calculus.zero_matrix(dimension))

  -> value
    @value

  -> dimension
    @gradient.size

  -> gradient
    Calculus.copy_vector(@gradient)

  -> hessian
    Calculus.copy_matrix(@hessian)

  -> coerce(other)
    if other.class_name == "Differential"
      if other.dimension != self.dimension
        raise "Differential dimension mismatch"
      return other
    Differential.constant(other, self.dimension)

  -> +(other)
    rhs = self.coerce(other)
    gradient = []
    hessian = Calculus.zero_matrix(self.dimension)
    i = 0
    while i < self.dimension
      gradient.push(@gradient[i] + rhs.gradient[i])
      j = 0
      while j < self.dimension
        hessian[i][j] = @hessian[i][j] + rhs.hessian[i][j]
        j += 1
      i += 1
    Differential.new(@value + rhs.value, gradient, hessian)

  -> -(other)
    rhs = self.coerce(other)
    gradient = []
    hessian = Calculus.zero_matrix(self.dimension)
    rhs_gradient = rhs.gradient
    rhs_hessian = rhs.hessian
    i = 0
    while i < self.dimension
      gradient.push(@gradient[i] - rhs_gradient[i])
      j = 0
      while j < self.dimension
        hessian[i][j] = @hessian[i][j] - rhs_hessian[i][j]
        j += 1
      i += 1
    Differential.new(@value - rhs.value, gradient, hessian)

  -> -@
    Differential.constant(~0.0, self.dimension) - self

  -> *(other)
    rhs = self.coerce(other)
    rhs_gradient = rhs.gradient
    rhs_hessian = rhs.hessian
    gradient = []
    hessian = Calculus.zero_matrix(self.dimension)
    i = 0
    while i < self.dimension
      gradient.push(@gradient[i] * rhs.value + @value * rhs_gradient[i])
      j = 0
      while j < self.dimension
        value = @hessian[i][j] * rhs.value + @value * rhs_hessian[i][j] + @gradient[i] * rhs_gradient[j] + rhs_gradient[i] * @gradient[j]
        hessian[i][j] = value
        j += 1
      i += 1
    Differential.new(@value * rhs.value, gradient, hessian)

  -> scale(scalar)
    self.unary_transform(@value * scalar, scalar, ~0.0)

  -> reciprocal
    raise "Differential division by zero" if @value == ~0.0
    inverse = ~1.0 / @value
    self.unary_transform(
      inverse,
      ~0.0 - inverse * inverse,
      ~2.0 * inverse * inverse * inverse)

  -> /(other)
    self * self.coerce(other).reciprocal

  -> unary_transform(result_value, first_derivative, second_derivative)
    gradient = []
    hessian = Calculus.zero_matrix(self.dimension)
    i = 0
    while i < self.dimension
      gradient.push(first_derivative * @gradient[i])
      j = 0
      while j < self.dimension
        cell_value = second_derivative * @gradient[i] * @gradient[j] + first_derivative * @hessian[i][j]
        hessian[i][j] = cell_value
        j += 1
      i += 1
    Differential.new(result_value, gradient, hessian)

  -> exp
    value = Math.exp(@value)
    self.unary_transform(value, value, value)

  -> log
    inverse = ~1.0 / @value
    self.unary_transform(
      Math.log(@value), inverse, ~0.0 - inverse * inverse)

  -> sqrt
    value = Math.sqrt(@value)
    first = ~1.0 / (~2.0 * value)
    second = ~0.0 - ~1.0 / (~4.0 * value * value * value)
    self.unary_transform(value, first, second)

  -> sin
    self.unary_transform(
      Math.sin(@value), Math.cos(@value), ~0.0 - Math.sin(@value))

  -> cos
    self.unary_transform(
      Math.cos(@value), ~0.0 - Math.sin(@value), ~0.0 - Math.cos(@value))

  -> tan
    value = Math.tan(@value)
    first = ~1.0 + value * value
    self.unary_transform(value, first, ~2.0 * value * first)

  -> sinh
    self.unary_transform(
      Math.sinh(@value), Math.cosh(@value), Math.sinh(@value))

  -> cosh
    self.unary_transform(
      Math.cosh(@value), Math.sinh(@value), Math.cosh(@value))

  -> tanh
    value = Math.tanh(@value)
    first = ~1.0 - value * value
    self.unary_transform(value, first, ~0.0 - ~2.0 * value * first)

  -> asinh
    base = ~1.0 + @value * @value
    root = Math.sqrt(base)
    self.unary_transform(
      Math.asinh(@value),
      ~1.0 / root,
      (~0.0 - @value) / (base * root))

  -> acosh
    base = @value * @value - ~1.0
    root = Math.sqrt(base)
    self.unary_transform(
      Math.acosh(@value),
      ~1.0 / root,
      (~0.0 - @value) / (base * root))

  -> atanh
    base = ~1.0 - @value * @value
    self.unary_transform(
      Math.atanh(@value),
      ~1.0 / base,
      (~2.0 * @value) / (base * base))

  -> expm1
    exponential = Math.exp(@value)
    self.unary_transform(Math.expm1(@value), exponential, exponential)

  -> log1p
    inverse = ~1.0 / (~1.0 + @value)
    self.unary_transform(
      Math.log1p(@value), inverse, ~0.0 - inverse * inverse)

  -> log2
    inverse_log_two = ~1.4426950408889634
    inverse = ~1.0 / @value
    self.unary_transform(
      Math.log2(@value),
      inverse_log_two * inverse,
      ~0.0 - inverse_log_two * inverse * inverse)

  -> log10
    inverse_log_ten = ~0.4342944819032518
    inverse = ~1.0 / @value
    self.unary_transform(
      Math.log10(@value),
      inverse_log_ten * inverse,
      ~0.0 - inverse_log_ten * inverse * inverse)

  -> cbrt
    value = Math.cbrt(@value)
    raise "Differential.cbrt is singular at zero" if value == ~0.0
    first = ~1.0 / (~3.0 * value * value)
    second = (~-2.0) / (~9.0 * value * value * value * value * value)
    self.unary_transform(value, first, second)

  -> abs
    raise "Differential.abs is not differentiable at zero" if @value == ~0.0
    if @value < ~0.0
      return self.unary_transform(~0.0 - @value, ~-1.0, ~0.0)
    self.unary_transform(@value, ~1.0, ~0.0)

  -> asin
    base = ~1.0 - @value * @value
    root = Math.sqrt(base)
    self.unary_transform(
      Math.asin(@value),
      ~1.0 / root,
      @value / (base * root))

  -> acos
    base = ~1.0 - @value * @value
    root = Math.sqrt(base)
    self.unary_transform(
      Math.acos(@value),
      ~0.0 - ~1.0 / root,
      ~0.0 - @value / (base * root))

  -> atan
    base = ~1.0 + @value * @value
    self.unary_transform(
      Math.atan(@value),
      ~1.0 / base,
      (~0.0 - ~2.0 * @value) / (base * base))

  -> pow(exponent)
    return Differential.constant(~1.0, self.dimension) if exponent == 0
    return self if exponent == 1
    value = Math.pow(@value, exponent)
    first = exponent * Math.pow(@value, exponent - ~1.0)
    second = exponent * (exponent - ~1.0) * Math.pow(@value, exponent - ~2.0)
    self.unary_transform(value, first, second)

  -> **(exponent)
    self.pow(exponent)

  -> to_s
    "Differential(value=" + @value.to_s + ", gradient=" + @gradient.to_s + ")"

  -> inspect
    self.to_s


+ Calculus
  -> .variables(point)
    if point.class_name != "Array"
      raise "calculus point must be an Array"
    variables = []
    i = 0
    while i < point.size
      variables.push(Differential.variable(point[i], point.size, i))
      i += 1
    variables

  -> .differential(f, point)
    variables = Calculus.variables(point)
    result = f(variables)
    if result.class_name == "Differential"
      return result
    Differential.constant(result, point.size)

  -> .value_gradient_hessian(f, point)
    result = Calculus.differential(f, point)
    {
      "value": result.value,
      "gradient": result.gradient,
      "hessian": result.hessian
    }

  -> .gradient(f, point)
    Calculus.differential(f, point).gradient

  -> .hessian(f, point)
    Calculus.differential(f, point).hessian

  -> .jacobian(f, point)
    variables = Calculus.variables(point)
    outputs = f(variables)
    if outputs.class_name != "Array"
      raise "jacobian function must return an Array"
    rows = []
    outputs.each ->
      if item.class_name == "Differential"
        rows.push(item.gradient)
      else
        rows.push(Calculus.zero_vector(point.size))
    rows
