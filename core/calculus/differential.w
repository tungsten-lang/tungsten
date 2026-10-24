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

  -> new(@value, @gradient, @hessian, trusted)
    if !trusted
      if @gradient.class_name != "Array" || @hessian.class_name != "Array"
        raise "Differential needs Array gradient and Hessian"
      @gradient = Calculus.copy_vector(@gradient)
      @hessian = Calculus.copy_matrix(@hessian)
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
      Calculus.zero_matrix(dimension),
      true)

  -> .variable(value, dimension, index)
    if index < 0 || index >= dimension
      raise "Differential variable index is out of range"
    gradient = Calculus.zero_vector(dimension)
    gradient[index] = ~1.0
    Differential.new(value, gradient, Calculus.zero_matrix(dimension), true)

  ro :value

  -> dimension
    @gradient.size

  -> raw_gradient
    @gradient

  -> raw_hessian
    @hessian

  -> gradient
    Calculus.copy_vector(@gradient)

  -> hessian
    Calculus.copy_matrix(@hessian)

  -> coerce(other)
    if type(other) == "Differential"
      if other.dimension != self.dimension
        raise "Differential dimension mismatch"
      return other
    Differential.constant(other, self.dimension)

  -> +(other)
    if type(other) != "Differential"
      return Differential.new(@value + other, @gradient.dup, Calculus.copy_matrix(@hessian), true)
    rhs = self.coerce(other)
    g = @gradient ## Array
    h = @hessian ## Array
    rhs_gradient = rhs.raw_gradient ## Array
    rhs_hessian = rhs.raw_hessian ## Array
    dim = g.size
    gradient = []
    hessian = []
    if type(@value) == "Float" && type(rhs.value) == "Float"
      i = 0
      while i < dim
        gi = g[i] ## f64
        rgi = rhs_gradient[i] ## f64
        gradient.push(gi + rgi)
        lhs_row = h[i] ## Array
        rhs_row = rhs_hessian[i] ## Array
        row = []
        j = 0
        while j < dim
          lj = lhs_row[j] ## f64
          rj = rhs_row[j] ## f64
          row.push(lj + rj)
          j += 1
        hessian.push(row)
        i += 1
    else
      i = 0
      while i < dim
        gradient.push(g[i] + rhs_gradient[i])
        lhs_row = h[i] ## Array
        rhs_row = rhs_hessian[i] ## Array
        row = []
        j = 0
        while j < dim
          row.push(lhs_row[j] + rhs_row[j])
          j += 1
        hessian.push(row)
        i += 1
    Differential.new(@value + rhs.value, gradient, hessian, true)

  -> -(other)
    if type(other) != "Differential"
      return Differential.new(@value - other, @gradient.dup, Calculus.copy_matrix(@hessian), true)
    rhs = self.coerce(other)
    g = @gradient ## Array
    h = @hessian ## Array
    rhs_gradient = rhs.raw_gradient ## Array
    rhs_hessian = rhs.raw_hessian ## Array
    dim = g.size
    gradient = []
    hessian = []
    if type(@value) == "Float" && type(rhs.value) == "Float"
      i = 0
      while i < dim
        gi = g[i] ## f64
        rgi = rhs_gradient[i] ## f64
        gradient.push(gi - rgi)
        lhs_row = h[i] ## Array
        rhs_row = rhs_hessian[i] ## Array
        row = []
        j = 0
        while j < dim
          lj = lhs_row[j] ## f64
          rj = rhs_row[j] ## f64
          row.push(lj - rj)
          j += 1
        hessian.push(row)
        i += 1
    else
      i = 0
      while i < dim
        gradient.push(g[i] - rhs_gradient[i])
        lhs_row = h[i] ## Array
        rhs_row = rhs_hessian[i] ## Array
        row = []
        j = 0
        while j < dim
          row.push(lhs_row[j] - rhs_row[j])
          j += 1
        hessian.push(row)
        i += 1
    Differential.new(@value - rhs.value, gradient, hessian, true)

  -> -@
    g = @gradient ## Array
    h = @hessian ## Array
    dim = g.size
    gradient = []
    hessian = []
    i = 0
    while i < dim
      gradient.push(~0.0 - g[i])
      lhs_row = h[i] ## Array
      row = []
      j = 0
      while j < dim
        row.push(~0.0 - lhs_row[j])
        j += 1
      hessian.push(row)
      i += 1
    Differential.new(~0.0 - @value, gradient, hessian, true)

  -> *(other)
    if type(other) != "Differential"
      return self.scale(other)
    rhs = self.coerce(other)
    rhs_val = rhs.value
    g = @gradient ## Array
    h = @hessian ## Array
    rhs_gradient = rhs.raw_gradient ## Array
    rhs_hessian = rhs.raw_hessian ## Array
    dim = g.size
    gradient = []
    hessian = []
    if type(@value) == "Float" && type(rhs_val) == "Float"
      vf = @value ## f64
      rvf = rhs_val ## f64
      i = 0
      while i < dim
        gi = g[i] ## f64
        rgi = rhs_gradient[i] ## f64
        gradient.push(gi * rvf + vf * rgi)
        lhs_row = h[i] ## Array
        rhs_row = rhs_hessian[i] ## Array
        row = []
        j = 0
        while j < dim
          lj = lhs_row[j] ## f64
          rj = rhs_row[j] ## f64
          gj = g[j] ## f64
          rgj = rhs_gradient[j] ## f64
          value = lj * rvf + vf * rj + gi * rgj + rgi * gj
          row.push(value)
          j += 1
        hessian.push(row)
        i += 1
      return Differential.new(vf * rvf, gradient, hessian, true)
    i = 0
    while i < dim
      gi = g[i]
      rgi = rhs_gradient[i]
      gradient.push(gi * rhs_val + @value * rgi)
      lhs_row = h[i] ## Array
      rhs_row = rhs_hessian[i] ## Array
      row = []
      j = 0
      while j < dim
        value = lhs_row[j] * rhs_val + @value * rhs_row[j] + gi * rhs_gradient[j] + rgi * g[j]
        row.push(value)
        j += 1
      hessian.push(row)
      i += 1
    Differential.new(@value * rhs_val, gradient, hessian, true)

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
    g = @gradient ## Array
    h = @hessian ## Array
    dim = g.size
    gradient = []
    hessian = []
    if type(first_derivative) == "Float" && type(second_derivative) == "Float" && (dim == 0 || type(g[0]) == "Float")
      fd = first_derivative ## f64
      sd = second_derivative ## f64
      i = 0
      while i < dim
        gi = g[i] ## f64
        gradient.push(fd * gi)
        s_gi = sd * gi
        lhs_row = h[i] ## Array
        row = []
        j = 0
        while j < dim
          gj = g[j] ## f64
          lj = lhs_row[j] ## f64
          cell_value = s_gi * gj + fd * lj
          row.push(cell_value)
          j += 1
        hessian.push(row)
        i += 1
      return Differential.new(result_value, gradient, hessian, true)
    i = 0
    while i < dim
      gi = g[i]
      gradient.push(first_derivative * gi)
      s_gi = second_derivative * gi
      lhs_row = h[i] ## Array
      row = []
      j = 0
      while j < dim
        cell_value = s_gi * g[j] + first_derivative * lhs_row[j]
        row.push(cell_value)
        j += 1
      hessian.push(row)
      i += 1
    Differential.new(result_value, gradient, hessian, true)

  -> exp
    value = Math.exp(@value)
    self.unary_transform(value, value, value)

  -> log
    Calculus.require_real_domain(@value, @value > ~0.0, "Differential.log")
    inverse = ~1.0 / @value
    self.unary_transform(
      Math.log(@value), inverse, ~0.0 - inverse * inverse)

  -> sqrt
    Calculus.require_real_domain(@value, @value > ~0.0, "Differential.sqrt")
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
    Calculus.require_real_domain(@value, @value > ~1.0, "Differential.acosh")
    base = @value * @value - ~1.0
    root = Math.sqrt(base)
    self.unary_transform(
      Math.acosh(@value),
      ~1.0 / root,
      (~0.0 - @value) / (base * root))

  -> atanh
    Calculus.require_real_domain(@value, @value > ~-1.0 && @value < ~1.0, "Differential.atanh")
    base = ~1.0 - @value * @value
    self.unary_transform(
      Math.atanh(@value),
      ~1.0 / base,
      (~2.0 * @value) / (base * base))

  -> expm1
    exponential = Math.exp(@value)
    self.unary_transform(Math.expm1(@value), exponential, exponential)

  -> log1p
    Calculus.require_real_domain(@value, @value > ~-1.0, "Differential.log1p")
    inverse = ~1.0 / (~1.0 + @value)
    self.unary_transform(
      Math.log1p(@value), inverse, ~0.0 - inverse * inverse)

  -> log2
    Calculus.require_real_domain(@value, @value > ~0.0, "Differential.log2")
    inverse_log_two = ~1.4426950408889634
    inverse = ~1.0 / @value
    self.unary_transform(
      Math.log2(@value),
      inverse_log_two * inverse,
      ~0.0 - inverse_log_two * inverse * inverse)

  -> log10
    Calculus.require_real_domain(@value, @value > ~0.0, "Differential.log10")
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

  -> erf
    first = ~2.0 / Math.sqrt(~3.141592653589793)
    first *= Math.exp(~0.0 - @value * @value)
    second = (~0.0 - ~2.0) * @value * first
    self.unary_transform(Special.erf(@value), first, second)

  -> erfc
    first = (~0.0 - ~2.0) / Math.sqrt(~3.141592653589793)
    first *= Math.exp(~0.0 - @value * @value)
    second = (~0.0 - ~2.0) * @value * first
    self.unary_transform(Special.erfc(@value), first, second)

  -> polygamma(order)
    first = Special.polygamma(order + 1, @value)
    second = Special.polygamma(order + 2, @value)
    self.unary_transform(
      Special.polygamma(order, @value), first, second)

  -> digamma
    self.polygamma(0)

  -> trigamma
    self.polygamma(1)

  -> log_gamma
    first = Special.digamma(@value)
    second = Special.trigamma(@value)
    self.unary_transform(Special.log_gamma(@value), first, second)

  -> lgamma
    self.log_gamma

  -> gamma
    value = Special.gamma(@value)
    psi = Special.digamma(@value)
    first = value * psi
    second = value * (psi * psi + Special.trigamma(@value))
    self.unary_transform(value, first, second)

  -> lambert_w
    value = Special.lambert_w(@value)
    if @value == ~0.0
      return self.unary_transform(value, ~1.0, ~-2.0)
    first = value / (@value*(~1.0 + value))
    second = (
      (~0.0 - value*value*(~2.0 + value)) /
      (@value*@value*(~1.0 + value)**3))
    self.unary_transform(value, first, second)

  -> lambertw
    self.lambert_w

  -> asin
    Calculus.require_real_domain(@value, @value > ~-1.0 && @value < ~1.0, "Differential.asin")
    base = ~1.0 - @value * @value
    root = Math.sqrt(base)
    self.unary_transform(
      Math.asin(@value),
      ~1.0 / root,
      @value / (base * root))

  -> acos
    Calculus.require_real_domain(@value, @value > ~-1.0 && @value < ~1.0, "Differential.acos")
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
    Calculus.require_real_domain(exponent, true, "Differential.pow exponent")
    exponent = exponent + ~0.0
    integral = exponent == Math.floor(exponent)
    valid = @value > ~0.0 || integral
    valid = false if @value == ~0.0 && exponent < ~0.0
    Calculus.require_real_domain(@value, valid, "Differential.pow")
    return Differential.constant(~1.0, self.dimension) if exponent == ~0.0
    return self if exponent == ~1.0
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
      if !Calculus.finite_scalar?(point[i])
        raise "calculus point entries must be finite scalars"
      variables.push(Differential.variable(point[i], point.size, i))
      i += 1
    variables

  -> .differential(f, point)
    variables = Calculus.variables(point)
    result = f(variables)
    if result.class_name == "Differential"
      if result.dimension != point.size
        raise "calculus result Differential dimension mismatch"
      if !Calculus.finite_scalar?(result.value)
        raise "calculus result must have a finite scalar value"
      return result
    if !Calculus.finite_scalar?(result)
      raise "calculus scalar function must return a finite scalar or Differential"
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
        if item.dimension != point.size
          raise "jacobian result Differential dimension mismatch"
        if !Calculus.finite_scalar?(item.value)
          raise "jacobian output must have a finite scalar value"
        rows.push(item.gradient)
      else
        if !Calculus.finite_scalar?(item)
          raise "jacobian entries must be finite scalars or Differential values"
        rows.push(Calculus.zero_vector(point.size))
    rows
