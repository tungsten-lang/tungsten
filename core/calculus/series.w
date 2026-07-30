# FormalPowerSeries — exact truncated Taylor algebra.
#
# Coefficient n is the coefficient of (x - center)^n. Unlike TaylorJet, every
# coefficient is an Expression, so Rational values, named constants, radicals,
# parameters, and transcendental constants stay exact. The fixed truncation
# order is explicit; operations never imply convergence or a numerical error
# bound.

use core/expression

+ FormalPowerSeries
  -> new(coefficients, variable = :x, center = 0)
    if coefficients.class_name != "Array" || coefficients.size == 0
      raise "FormalPowerSeries needs a nonempty coefficient Array"
    @variable_text = variable.to_s
    if @variable_text.empty?
      raise "FormalPowerSeries variable name cannot be empty"
    @center = Expression.wrap(center)
    @coefficients = []
    coefficients.each -> (coefficient)
      @coefficients.push(Expression.wrap(coefficient))

  -> .validate_order(order)
    if !Expression.integer?(order) || order < 0
      raise "formal series order must be a nonnegative integer"
    order

  -> .constant(value, order, variable = :x, center = 0)
    FormalPowerSeries.validate_order(order)
    coefficients = [Expression.wrap(value)]
    order.times -> coefficients.push(Expression.constant(0))
    FormalPowerSeries.new(coefficients, variable, center)

  -> .variable(variable, center, order)
    series = FormalPowerSeries.constant(center, order, variable, center)
    if order > 0
      coefficients = series.coefficients
      coefficients[1] = Expression.constant(1)
      return FormalPowerSeries.new(coefficients, variable, center)
    series

  -> variable
    @variable_text.to_sym

  -> variable_text
    @variable_text

  -> center
    @center

  -> order
    @coefficients.size - 1

  -> value
    @coefficients[0]

  -> coefficients
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient)
    out

  -> coefficient(index)
    return Expression.constant(0) if index < 0 || index > order
    @coefficients[index]

  -> same_expansion_point?(other)
    other.variable_text == @variable_text && other.center == @center

  -> coerce(other)
    if other.class_name == "FormalPowerSeries"
      if other.order != order
        raise "formal series order mismatch"
      if !same_expansion_point?(other)
        raise "formal series expansion-point mismatch"
      return other
    FormalPowerSeries.constant(other, order, variable, @center)

  -> zero?
    i = 0
    while i <= order
      return false if !Expression.zero_expression?(@coefficients[i])
      i += 1
    true

  -> constant_series?
    i = 1
    while i <= order
      return false if !Expression.zero_expression?(@coefficients[i])
      i += 1
    true

  # First retained nonzero power. Nil means every retained coefficient is
  # zero, so the true valuation is beyond the current precision or infinite.
  -> valuation
    i = 0
    while i <= order
      return i if !Expression.zero_expression?(@coefficients[i])
      i += 1
    nil

  -> +(other)
    rhs = coerce(other)
    out = []
    i = 0
    while i <= order
      out.push(@coefficients[i] + rhs.coefficient(i))
      i += 1
    FormalPowerSeries.new(out, variable, @center)

  -> -(other)
    rhs = coerce(other)
    out = []
    i = 0
    while i <= order
      out.push(@coefficients[i] - rhs.coefficient(i))
      i += 1
    FormalPowerSeries.new(out, variable, @center)

  -> -@
    out = []
    @coefficients.each -> (coefficient)
      out.push(-coefficient)
    FormalPowerSeries.new(out, variable, @center)

  -> *(other)
    rhs = coerce(other)
    out = []
    n = 0
    while n <= order
      value = Expression.constant(0)
      k = 0
      while k <= n
        value += @coefficients[k] * rhs.coefficient(n - k)
        k += 1
      out.push(value)
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> scale(scalar)
    factor = Expression.wrap(scalar)
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient * factor)
    FormalPowerSeries.new(out, variable, @center)

  -> /(other)
    rhs = coerce(other)
    if Expression.zero_expression?(rhs.value)
      denominator_valuation = rhs.valuation
      if denominator_valuation == nil
        raise "formal series denominator is zero through the retained order"
      numerator_valuation = valuation
      if numerator_valuation != nil && numerator_valuation < denominator_valuation
        raise "formal series quotient needs negative Laurent powers"
      quotient_order = order - denominator_valuation
      numerator_coefficients = []
      denominator_coefficients = []
      i = 0
      while i <= quotient_order
        numerator_coefficients.push(coefficient(i + denominator_valuation))
        denominator_coefficients.push(rhs.coefficient(i + denominator_valuation))
        i += 1
      shifted_numerator = FormalPowerSeries.new(
        numerator_coefficients, variable, @center)
      shifted_denominator = FormalPowerSeries.new(
        denominator_coefficients, variable, @center)
      return shifted_numerator / shifted_denominator
    out = []
    n = 0
    while n <= order
      value = @coefficients[n]
      k = 1
      while k <= n
        value -= rhs.coefficient(k) * out[n - k]
        k += 1
      out.push(value / rhs.value)
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> reciprocal
    FormalPowerSeries.constant(1, order, variable, @center) / self

  -> integer_power(exponent)
    return FormalPowerSeries.constant(1, order, variable, @center) if exponent == 0
    return integer_power(0 - exponent).reciprocal if exponent < 0
    result = FormalPowerSeries.constant(1, order, variable, @center)
    factor = self
    power = exponent
    while power > 0
      result = result * factor if power.odd?
      power = power / 2
      factor = factor * factor if power > 0
    result

  # Solve y'/y = exponent * a'/a with y(0) = a(0)^exponent.
  # This supports symbolic constant exponents without introducing log(a0).
  -> power_constant(exponent)
    power = Expression.wrap(exponent)
    if Expression.zero_expression?(value)
      raise "nonintegral formal power needs a nonzero constant term"
    if order == 0
      return FormalPowerSeries.new(
        [value ** power], variable, @center)
    base = truncate(order - 1)
    logarithmic_derivative = (derivative / base).scale(power)
    out = [value ** power]
    n = 1
    while n <= order
      coefficient_value = Expression.constant(0)
      k = 0
      while k < n
        coefficient_value += logarithmic_derivative.coefficient(k) * out[n - 1 - k]
        k += 1
      out.push(coefficient_value / Expression.constant(n))
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> **(exponent)
    if exponent.class_name == "FormalPowerSeries"
      rhs = coerce(exponent)
      if rhs.constant_series?
        raw = rhs.value
        if raw.constant? && Expression.integer?(raw.constant_value)
          return integer_power(raw.constant_value)
        return power_constant(raw)
      return (rhs * self.log).exp
    power = Expression.wrap(exponent)
    if power.constant?
      raw = power.constant_value
      return integer_power(raw) if Expression.integer?(raw)
    power_constant(power)

  -> pow(exponent)
    self ** exponent

  -> derivative
    if order == 0
      return FormalPowerSeries.new(
        [Expression.constant(0)], variable, @center)
    out = []
    i = 0
    while i < order
      out.push(@coefficients[i + 1] * Expression.constant(i + 1))
      i += 1
    FormalPowerSeries.new(out, variable, @center)

  -> antiderivative(constant = 0)
    out = [Expression.wrap(constant)]
    i = 1
    while i <= order + 1
      out.push(@coefficients[i - 1] / Expression.constant(i))
      i += 1
    FormalPowerSeries.new(out, variable, @center)

  -> derivative_value(derivative_order = 1)
    FormalPowerSeries.validate_order(derivative_order)
    return Expression.constant(0) if derivative_order > order
    result = @coefficients[derivative_order]
    i = 2
    while i <= derivative_order
      result *= Expression.constant(i)
      i += 1
    result

  -> derivatives
    out = []
    i = 0
    while i <= order
      out.push(derivative_value(i))
      i += 1
    out

  -> exp
    out = [value.exp]
    n = 1
    while n <= order
      coefficient_value = Expression.constant(0)
      k = 1
      while k <= n
        factor = @coefficients[k] * Expression.constant(k)
        coefficient_value += factor * out[n - k]
        k += 1
      out.push(coefficient_value / Expression.constant(n))
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> log
    if Expression.zero_expression?(value)
      raise "formal series log needs a nonzero constant term"
    if order == 0
      return FormalPowerSeries.new(
        [value.log], variable, @center)
    quotient = derivative / truncate(order - 1)
    out = [value.log]
    n = 1
    while n <= order
      out.push(quotient.coefficient(n - 1) / Expression.constant(n))
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> sin_cos
    sine = [value.sin]
    cosine = [value.cos]
    n = 1
    while n <= order
      sine_value = Expression.constant(0)
      cosine_value = Expression.constant(0)
      k = 1
      while k <= n
        factor = @coefficients[k] * Expression.constant(k)
        sine_value += factor * cosine[n - k]
        cosine_value -= factor * sine[n - k]
        k += 1
      sine.push(sine_value / Expression.constant(n))
      cosine.push(cosine_value / Expression.constant(n))
      n += 1
    [
      FormalPowerSeries.new(sine, variable, @center),
      FormalPowerSeries.new(cosine, variable, @center)
    ]

  -> sin
    sin_cos[0]

  -> cos
    sin_cos[1]

  -> tan
    pair = sin_cos
    pair[0] / pair[1]

  -> sinh_cosh
    hyperbolic_sine = [value.sinh]
    hyperbolic_cosine = [value.cosh]
    n = 1
    while n <= order
      sine_value = Expression.constant(0)
      cosine_value = Expression.constant(0)
      k = 1
      while k <= n
        factor = @coefficients[k] * Expression.constant(k)
        sine_value += factor * hyperbolic_cosine[n - k]
        cosine_value += factor * hyperbolic_sine[n - k]
        k += 1
      hyperbolic_sine.push(sine_value / Expression.constant(n))
      hyperbolic_cosine.push(cosine_value / Expression.constant(n))
      n += 1
    [
      FormalPowerSeries.new(hyperbolic_sine, variable, @center),
      FormalPowerSeries.new(hyperbolic_cosine, variable, @center)
    ]

  -> sinh
    sinh_cosh[0]

  -> cosh
    sinh_cosh[1]

  -> tanh
    pair = sinh_cosh
    pair[0] / pair[1]

  -> asin
    if order == 0
      return FormalPowerSeries.new(
        [value.asin], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (one - self * self).sqrt.truncate(order - 1)
    slope = derivative / denominator
    slope.antiderivative(value.asin)

  -> acos
    if order == 0
      return FormalPowerSeries.new(
        [value.acos], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (one - self * self).sqrt.truncate(order - 1)
    slope = -(derivative / denominator)
    slope.antiderivative(value.acos)

  -> atan
    if order == 0
      return FormalPowerSeries.new(
        [value.atan], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (one + self * self).truncate(order - 1)
    slope = derivative / denominator
    slope.antiderivative(value.atan)

  -> asinh
    if order == 0
      return FormalPowerSeries.new(
        [value.asinh], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (one + self * self).sqrt.truncate(order - 1)
    slope = derivative / denominator
    slope.antiderivative(value.asinh)

  -> acosh
    if order == 0
      return FormalPowerSeries.new(
        [value.acosh], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (self * self - one).sqrt.truncate(order - 1)
    slope = derivative / denominator
    slope.antiderivative(value.acosh)

  -> atanh
    if order == 0
      return FormalPowerSeries.new(
        [value.atanh], variable, @center)
    one = FormalPowerSeries.constant(1, order, variable, @center)
    denominator = (one - self * self).truncate(order - 1)
    slope = derivative / denominator
    slope.antiderivative(value.atanh)

  -> expm1
    self.exp - FormalPowerSeries.constant(1, order, variable, @center)

  -> log1p
    (self + 1).log

  -> log2
    self.log / FormalPowerSeries.constant(
      Expression.constant(2).log, order, variable, @center)

  -> log10
    self.log / FormalPowerSeries.constant(
      Expression.constant(10).log, order, variable, @center)

  -> cbrt
    return FormalPowerSeries.constant(0, order, variable, @center) if zero?
    power_constant(Expression.constant(Rational.new(1, 3)))

  -> sqrt
    root = value.sqrt
    if Expression.zero_expression?(root)
      return FormalPowerSeries.constant(0, order, variable, @center) if zero?
      raise "formal series sqrt is singular at a zero constant term"
    out = [root]
    n = 1
    while n <= order
      coefficient_value = @coefficients[n]
      k = 1
      while k < n
        coefficient_value -= out[k] * out[n - k]
        k += 1
      denominator = Expression.constant(2) * root
      out.push(coefficient_value / denominator)
      n += 1
    FormalPowerSeries.new(out, variable, @center)

  -> constant_sign
    if value.named_constant?
      name = value.named_constant_name
      return 1 if name == :pi || name == :e
    if value.constant?
      scalar = value.constant_value
      if Expression.scalar_value?(scalar)
        return 1 if scalar > 0
        return -1 if scalar < 0
        return 0 if scalar == 0
      return 1 if scalar.respond_to?("positive?") && scalar.positive?
      return -1 if scalar.respond_to?("negative?") && scalar.negative?
      return 0 if Expression.zero_value?(scalar)
    nil

  -> abs
    sign = constant_sign
    return self if sign == 1
    return -self if sign == -1
    return FormalPowerSeries.constant(0, order, variable, @center) if zero?
    raise "formal series abs needs a known nonzero sign at the center"

  -> erf
    if order == 0
      return FormalPowerSeries.new(
        [value.erf], variable, @center)
    exponential = (-(self * self)).exp.truncate(order - 1)
    slope = derivative * exponential
    scale = Expression.constant(2) / Expression.pi.sqrt
    slope.scale(scale).antiderivative(value.erf)

  -> erfc
    if order == 0
      return FormalPowerSeries.new(
        [value.erfc], variable, @center)
    exponential = (-(self * self)).exp.truncate(order - 1)
    slope = derivative * exponential
    scale = Expression.constant(-2) / Expression.pi.sqrt
    slope.scale(scale).antiderivative(value.erfc)

  -> compose(delta)
    inner = coerce(delta)
    if !Expression.zero_expression?(inner.value)
      raise "formal series composition needs a zero-constant inner series"
    result = FormalPowerSeries.constant(0, order, variable, @center)
    i = order
    while i >= 0
      result = result * inner + @coefficients[i]
      i -= 1
    result

  -> evaluate_delta(delta)
    value_at_delta = Expression.wrap(delta)
    result = Expression.constant(0)
    i = order
    while i >= 0
      result = result * value_at_delta + @coefficients[i]
      i -= 1
    result

  -> at(point)
    evaluate_delta(Expression.wrap(point) - @center)

  -> to_expression
    symbol = Expression.variable(@variable_text)
    delta = symbol - @center
    terms = []
    i = 0
    while i <= order
      if !Expression.zero_expression?(@coefficients[i])
        if i == 0
          terms.push(@coefficients[i])
        else
          terms.push(@coefficients[i] * delta**i)
      i += 1
    Expression.sum(terms)

  -> truncate(new_order)
    FormalPowerSeries.validate_order(new_order)
    if new_order > order
      raise "formal series truncation cannot invent higher coefficients"
    coefficients = []
    i = 0
    while i <= new_order
      coefficients.push(coefficient(i))
      i += 1
    FormalPowerSeries.new(coefficients, variable, @center)

  -> expand_coefficients
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient.expand)
    FormalPowerSeries.new(out, variable, @center)

  -> ==/1
    other = @1
    return false if other.class_name != "FormalPowerSeries"
    return false if other.order != order || !same_expansion_point?(other)
    i = 0
    while i <= order
      return false if @coefficients[i] != other.coefficient(i)
      i += 1
    true

  -> !=/1
    !(self == @1)

  -> to_s
    delta = @center == Expression.constant(0) ? @variable_text : "(" + @variable_text + " - " + @center.to_s + ")"
    "Series(" + to_expression.to_s + " + O(" + delta + "^" + (order + 1).to_s + "))"

  -> inspect
    to_s


+ Expression
  -> .apply_series_unary(operation, series)
    return series.exp if operation == "exp"
    return series.log if operation == "log"
    return series.sqrt if operation == "sqrt"
    return series.sin if operation == "sin"
    return series.cos if operation == "cos"
    return series.tan if operation == "tan"
    return series.sinh if operation == "sinh"
    return series.cosh if operation == "cosh"
    return series.tanh if operation == "tanh"
    return series.asin if operation == "asin"
    return series.acos if operation == "acos"
    return series.atan if operation == "atan"
    return series.asinh if operation == "asinh"
    return series.acosh if operation == "acosh"
    return series.atanh if operation == "atanh"
    return series.expm1 if operation == "expm1"
    return series.log1p if operation == "log1p"
    return series.log2 if operation == "log2"
    return series.log10 if operation == "log10"
    return series.cbrt if operation == "cbrt"
    return series.abs if operation == "abs"
    return series.erf if operation == "erf"
    return series.erfc if operation == "erfc"
    raise "formal series does not support symbolic operation: " + operation

  -> .series_from_expression(expression, variable, center, order)
    if expression.constant? || expression.named_constant?
      return FormalPowerSeries.constant(
        expression, order, variable, center)
    if expression.variable?
      if expression.variable_text == variable.to_s
        return FormalPowerSeries.variable(variable, center, order)
      return FormalPowerSeries.constant(
        expression, order, variable, center)

    arguments = expression.arguments
    if expression.operation == "add"
      result = FormalPowerSeries.constant(0, order, variable, center)
      arguments.each -> (argument)
        result += Expression.series_from_expression(
          argument, variable, center, order)
      return result
    if expression.operation == "multiply"
      result = FormalPowerSeries.constant(1, order, variable, center)
      arguments.each -> (argument)
        result *= Expression.series_from_expression(
          argument, variable, center, order)
      return result
    if expression.operation == "divide"
      numerator = Expression.series_from_expression(
        arguments[0], variable, center, order)
      denominator = Expression.series_from_expression(
        arguments[1], variable, center, order)
      if Expression.zero_expression?(denominator.value)
        expanded_order = order + 8
        maximum_order = order + 256
        denominator_valuation = nil
        while denominator_valuation == nil && expanded_order <= maximum_order
          denominator = Expression.series_from_expression(
            arguments[1], variable, center, expanded_order)
          denominator_valuation = denominator.valuation
          if denominator_valuation == nil
            if expanded_order == maximum_order
              expanded_order = maximum_order + 1
            else
              expanded_order = expanded_order * 2 + 1
              expanded_order = maximum_order if expanded_order > maximum_order
        if denominator_valuation == nil
          raise "formal denominator leading term exceeds the series search limit"
        needed_order = order + denominator_valuation
        if expanded_order < needed_order
          expanded_order = needed_order
          denominator = Expression.series_from_expression(
            arguments[1], variable, center, expanded_order)
        numerator = Expression.series_from_expression(
          arguments[0], variable, center, expanded_order)
        quotient = numerator / denominator
        if quotient.order < order
          raise "formal quotient has insufficient retained precision"
        return quotient.truncate(order)
      return numerator / denominator
    if expression.operation == "power"
      base = Expression.series_from_expression(
        arguments[0], variable, center, order)
      exponent = Expression.series_from_expression(
        arguments[1], variable, center, order)
      return base ** exponent
    argument = Expression.series_from_expression(
      arguments[0], variable, center, order)
    Expression.apply_series_unary(expression.operation, argument)

  -> series(variable, center = 0, order = 6)
    FormalPowerSeries.validate_order(order)
    Expression.series_from_expression(self, variable, center, order)

  -> formal_series(variable, center = 0, order = 6)
    FormalPowerSeries.validate_order(order)
    Expression.series_from_expression(self, variable, center, order)

  # Exact finite-point limit for expressions admitting an ordinary formal
  # Taylor expansion after removable factors are cancelled.
  -> limit(variable, point, order = 8)
    FormalPowerSeries.validate_order(order)
    Expression.series_from_expression(self, variable, point, order).value
