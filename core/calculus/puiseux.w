# FormalPuiseuxSeries — exact rational-power local algebra.
#
# Index k represents (x-center)^(k/e), where e is the positive ramification
# index. Arithmetic refines operands to the least common ramification index.
# Coefficients remain exact Expressions. This is a finite formal truncation:
# it chooses one symbolic root branch and does not claim analytic convergence.

use core/calculus/laurent

+ FormalPuiseuxSeries
  -> new(coefficients, minimum_index = 0,
         ramification_index = 1,
         variable = :x, center = 0)
    if coefficients.class_name != "Array" || coefficients.size == 0
      raise "FormalPuiseuxSeries needs a nonempty coefficient Array"
    if (!Expression.integer?(minimum_index) ||
        !Expression.integer?(ramification_index) ||
        ramification_index < 1)
      raise "Puiseux indices need an integral index and positive ramification"
    @variable_text = variable.to_s
    raise "Puiseux variable name cannot be empty" if @variable_text.empty?
    @center = Expression.wrap(center)
    @minimum_index = minimum_index
    @ramification_index = ramification_index
    @maximum_index = minimum_index + coefficients.size - 1
    @coefficients = []
    coefficients.each -> (coefficient)
      @coefficients.push(Expression.wrap(coefficient))
    normalize_leading_zeros

  -> .gcd(left, right)
    a = left.abs
    b = right.abs
    while b != 0
      temporary = a % b
      a = b
      b = temporary
    a

  -> .lcm(left, right)
    (left / FormalPuiseuxSeries.gcd(left, right))*right

  -> .constant(value, maximum_power,
               variable = :x, center = 0,
               ramification_index = 1)
    if !Expression.integer?(maximum_power) || maximum_power < 0
      raise "Puiseux constant precision must be nonnegative"
    FormalPuiseuxSeries.constant_through_index(
      value, maximum_power*ramification_index,
      variable, center, ramification_index)

  -> .constant_through_index(value, maximum_index,
                             variable = :x, center = 0,
                             ramification_index = 1)
    if !Expression.integer?(maximum_index) || maximum_index < 0
      raise "Puiseux constant index must be nonnegative"
    coefficients = [Expression.wrap(value)]
    maximum_index.times ->
      coefficients.push(Expression.constant(0))
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index,
      variable, center)

  -> .from_laurent(series)
    if series.class_name != "FormalLaurentSeries"
      raise "Puiseux conversion needs a FormalLaurentSeries"
    FormalPuiseuxSeries.new(
      series.coefficients, series.minimum_power, 1,
      series.variable, series.center)

  -> .from_power_series(series, ramification_index = 1)
    if series.class_name != "FormalPowerSeries"
      raise "Puiseux conversion needs a FormalPowerSeries"
    if ramification_index == 1
      return FormalPuiseuxSeries.new(
        series.coefficients, 0, 1,
        series.variable, series.center)
    coefficients = []
    index = 0
    while index <= series.order*ramification_index
      coefficients.push(Expression.constant(0))
      index += 1
    power = 0
    while power <= series.order
      coefficients[power*ramification_index] = (
        series.coefficient(power))
      power += 1
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index,
      series.variable, series.center)

  # The source variable is the local parameter s itself, with
  # s^e = x-center. Unlike from_power_series, consecutive source
  # coefficients therefore remain consecutive Puiseux indices.
  -> .from_parameter_series(series, ramification_index)
    if series.class_name != "FormalPowerSeries"
      raise "Puiseux parameter conversion needs a FormalPowerSeries"
    FormalPuiseuxSeries.new(
      series.coefficients, 0, ramification_index,
      series.variable, series.center)

  -> normalize_leading_zeros
    first_nonzero = nil
    index = 0
    while index < @coefficients.size
      if (first_nonzero == nil &&
          !Expression.zero_expression?(@coefficients[index]))
        first_nonzero = index
      index += 1
    return self if first_nonzero == nil
    index = 0
    while index < first_nonzero
      @coefficients.delete_at(0)
      @minimum_index += 1
      index += 1
    self

  -> variable
    @variable_text.to_sym

  -> variable_text
    @variable_text

  -> center
    @center

  -> ramification_index
    @ramification_index

  -> minimum_index
    @minimum_index

  -> maximum_index
    @maximum_index

  -> minimum_exponent
    Rational.new(@minimum_index, @ramification_index)

  -> maximum_exponent
    Rational.new(@maximum_index, @ramification_index)

  -> coefficient_index(index)
    return Expression.constant(0) if index < @minimum_index
    return Expression.constant(0) if index > @maximum_index
    @coefficients[index - @minimum_index]

  -> coefficient(exponent)
    power = Rational.coerce(exponent)
    scaled = power*Rational.new(@ramification_index)
    if scaled.denominator != 1
      return Expression.constant(0)
    coefficient_index(scaled.numerator)

  -> coefficients
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient)
    out

  -> zero?
    index = 0
    while index < @coefficients.size
      return false if !Expression.zero_expression?(
        @coefficients[index])
      index += 1
    true

  -> valuation_index
    return nil if zero?
    @minimum_index

  -> valuation
    index = valuation_index
    return nil if index == nil
    Rational.new(index, @ramification_index)

  -> regular?
    value = valuation_index
    value == nil || value >= 0

  -> same_expansion_point?(other)
    (other.variable_text == @variable_text &&
     other.center == @center)

  -> refine_ramification(new_ramification)
    if new_ramification % @ramification_index != 0
      raise "new Puiseux ramification must refine the old one"
    return self if new_ramification == @ramification_index
    scale = new_ramification / @ramification_index
    lower = @minimum_index*scale
    upper = @maximum_index*scale
    out = []
    index = lower
    while index <= upper
      if index % scale == 0
        out.push(coefficient_index(index / scale))
      else
        out.push(Expression.constant(0))
      index += 1
    FormalPuiseuxSeries.new(
      out, lower, new_ramification,
      variable, @center)

  -> common_ramification(other)
    target = FormalPuiseuxSeries.lcm(
      @ramification_index, other.ramification_index)
    [refine_ramification(target),
     other.refine_ramification(target)]

  -> coerce(other)
    if other.class_name == "FormalPuiseuxSeries"
      if !same_expansion_point?(other)
        raise "Puiseux series expansion-point mismatch"
      return other
    if @maximum_index < 0
      raise "cannot add a scalar beyond retained Puiseux precision"
    FormalPuiseuxSeries.constant_through_index(
      other, @maximum_index, variable, @center,
      @ramification_index)

  -> +(other)
    pair = common_ramification(coerce(other))
    left = pair[0]
    right = pair[1]
    upper = (
      left.maximum_index < right.maximum_index ?
      left.maximum_index : right.maximum_index)
    lower = (
      left.minimum_index < right.minimum_index ?
      left.minimum_index : right.minimum_index)
    if upper < lower
      raise "Puiseux addition has no common retained precision"
    out = []
    index = lower
    while index <= upper
      out.push(
        left.coefficient_index(index) +
        right.coefficient_index(index))
      index += 1
    FormalPuiseuxSeries.new(
      out, lower, left.ramification_index,
      variable, @center)

  -> negate
    out = []
    @coefficients.each -> (coefficient)
      out.push(-coefficient)
    FormalPuiseuxSeries.new(
      out, @minimum_index, @ramification_index,
      variable, @center)

  -> -@
    negate

  -> -(other)
    self + coerce(other).negate

  -> *(other)
    pair = common_ramification(coerce(other))
    left = pair[0]
    right = pair[1]
    if left.zero? || right.zero?
      maximum_power = (
        left.maximum_index / left.ramification_index)
      maximum_power = 0 if maximum_power < 0
      return FormalPuiseuxSeries.constant(
        0, maximum_power, variable, @center,
        left.ramification_index)
    left_value = left.valuation_index
    right_value = right.valuation_index
    lower = left_value + right_value
    upper_left = left.maximum_index + right_value
    upper_right = right.maximum_index + left_value
    upper = upper_left < upper_right ? upper_left : upper_right
    out = []
    index = lower
    while index <= upper
      value = Expression.constant(0)
      left_index = left_value
      while left_index <= left.maximum_index
        right_index = index - left_index
        if (right_index >= right_value &&
            right_index <= right.maximum_index)
          value += (
            left.coefficient_index(left_index) *
            right.coefficient_index(right_index))
        left_index += 1
      out.push(value)
      index += 1
    FormalPuiseuxSeries.new(
      out, lower, left.ramification_index,
      variable, @center)

  -> /(other)
    pair = common_ramification(coerce(other))
    left = pair[0]
    right = pair[1]
    raise "Puiseux division by zero series" if right.zero?
    if left.zero?
      return FormalPuiseuxSeries.constant(
        0, 0, variable, @center,
        left.ramification_index)
    left_value = left.valuation_index
    right_value = right.valuation_index
    left_tail = left.maximum_index - left_value
    right_tail = right.maximum_index - right_value
    quotient_order = (
      left_tail < right_tail ? left_tail : right_tail)
    numerator_coefficients = []
    denominator_coefficients = []
    index = 0
    while index <= quotient_order
      numerator_coefficients.push(
        left.coefficient_index(left_value + index))
      denominator_coefficients.push(
        right.coefficient_index(right_value + index))
      index += 1
    numerator = FormalPowerSeries.new(
      numerator_coefficients, variable, @center)
    denominator = FormalPowerSeries.new(
      denominator_coefficients, variable, @center)
    quotient = numerator / denominator
    FormalPuiseuxSeries.new(
      quotient.coefficients,
      left_value - right_value,
      left.ramification_index,
      variable, @center)

  -> integer_power(exponent)
    if !Expression.integer?(exponent)
      raise "Puiseux integer power needs an integer"
    if exponent == 0
      maximum_index = @maximum_index
      maximum_index = 0 if maximum_index < 0
      return FormalPuiseuxSeries.constant_through_index(
        1, maximum_index, variable, @center,
        @ramification_index)
    if exponent < 0
      maximum_index = @maximum_index
      maximum_index = 0 if maximum_index < 0
      one = FormalPuiseuxSeries.constant_through_index(
        1, maximum_index, variable, @center,
        @ramification_index)
      return one / integer_power(0 - exponent)
    maximum_index = @maximum_index
    maximum_index = 0 if maximum_index < 0
    result = FormalPuiseuxSeries.constant_through_index(
      1, maximum_index,
      variable, @center, @ramification_index)
    factor = self
    remaining = exponent
    while remaining > 0
      result = result*factor if remaining.odd?
      remaining /= 2
      factor = factor*factor if remaining > 0
    result

  # Factor c*s^v*U(s), U(0)=1, and apply the exact formal binomial series.
  # If exponent=p/q, the new ramification is e*q and unit index n becomes
  # n*q while the leading monomial index becomes v*p.
  -> rational_power(exponent)
    power = Rational.coerce(exponent)
    return integer_power(power.numerator) if power.denominator == 1
    raise "Puiseux rational power of zero is unsupported" if zero?
    numerator = power.numerator
    denominator = power.denominator
    value_index = valuation_index
    leading = coefficient_index(value_index)
    unit_order = @maximum_index - value_index
    unit_coefficients = []
    index = 0
    while index <= unit_order
      unit_coefficients.push(
        coefficient_index(value_index + index) / leading)
      index += 1
    unit = FormalPowerSeries.new(
      unit_coefficients, variable, @center)
    powered_unit = unit.power_constant(Expression.constant(power))
    new_ramification = @ramification_index*denominator
    leading_index = value_index*numerator
    maximum_index = (
      leading_index + powered_unit.order*denominator)
    out = []
    index = leading_index
    while index <= maximum_index
      out.push(Expression.constant(0))
      index += 1
    unit_index = 0
    scale = leading ** Expression.constant(power)
    while unit_index <= powered_unit.order
      target = leading_index + unit_index*denominator
      out[target - leading_index] = (
        powered_unit.coefficient(unit_index)*scale)
      unit_index += 1
    FormalPuiseuxSeries.new(
      out, leading_index, new_ramification,
      variable, @center)

  -> **(exponent)
    return integer_power(exponent) if Expression.integer?(exponent)
    rational_power(exponent)

  -> derivative
    out = []
    index = @minimum_index
    while index <= @maximum_index
      out.push(
        coefficient_index(index) *
        Expression.constant(
          Rational.new(index, @ramification_index)))
      index += 1
    result = FormalPuiseuxSeries.new(
      out, @minimum_index - @ramification_index,
      @ramification_index, variable, @center)
    if result.zero? && result.maximum_index < 0
      return FormalPuiseuxSeries.constant(
        0, 0, variable, @center,
        @ramification_index)
    result

  -> to_power_series_in_parameter(requested_index = nil)
    if !regular?
      raise "a Puiseux pole cannot be converted to a parameter power series"
    upper = (
      requested_index == nil ? @maximum_index : requested_index)
    if upper > @maximum_index
      raise "parameter-series conversion cannot invent coefficients"
    out = []
    index = 0
    while index <= upper
      out.push(coefficient_index(index))
      index += 1
    FormalPowerSeries.new(out, variable, @center)

  -> truncate(maximum_exponent)
    power = Rational.coerce(maximum_exponent)
    scaled = power*Rational.new(@ramification_index)
    if scaled.denominator != 1
      raise "Puiseux truncation is not on the ramification lattice"
    upper = scaled.numerator
    if upper > @maximum_index
      raise "Puiseux truncation cannot invent higher coefficients"
    if upper < @minimum_index
      raise "Puiseux truncation discards every retained coefficient"
    out = []
    index = @minimum_index
    while index <= upper
      out.push(coefficient_index(index))
      index += 1
    FormalPuiseuxSeries.new(
      out, @minimum_index, @ramification_index,
      variable, @center)

  -> to_expression
    symbol = Expression.variable(@variable_text)
    delta = symbol - @center
    terms = []
    index = @minimum_index
    while index <= @maximum_index
      value = coefficient_index(index)
      if !Expression.zero_expression?(value)
        exponent = Rational.new(index, @ramification_index)
        if exponent.zero?
          terms.push(value)
        else
          terms.push(value*delta**Expression.constant(exponent))
      index += 1
    Expression.sum(terms)

  -> ==(other)
    return false if other == nil
    return false if other.class_name != "FormalPuiseuxSeries"
    pair = common_ramification(other)
    left = pair[0]
    right = pair[1]
    return false if left.minimum_index != right.minimum_index
    return false if left.maximum_index != right.maximum_index
    index = left.minimum_index
    while index <= left.maximum_index
      return false if (
        left.coefficient_index(index) !=
        right.coefficient_index(index))
      index += 1
    true

  -> eql?(other)
    self == other

  -> to_s
    if @center == Expression.constant(0)
      delta = @variable_text
    else
      delta = '(' + @variable_text + ' - ' + @center.to_s + ')'
    next_exponent = Rational.new(
      @maximum_index + 1, @ramification_index)
    ("PuiseuxSeries(" + to_expression.to_s +
     " + O(" + delta + "^" +
     next_exponent.to_s + "))")

  -> inspect
    to_s


+ FormalLaurentSeries
  -> to_puiseux
    FormalPuiseuxSeries.from_laurent(self)


+ Expression
  -> .puiseux_from_expression(expression, variable,
                               center, maximum_power)
    if (expression.constant? || expression.named_constant? ||
        !expression.depends_on?(variable))
      return FormalPuiseuxSeries.constant(
        expression, maximum_power, variable, center)
    if expression.variable?
      return FormalPowerSeries.variable(
        variable, center, maximum_power).to_laurent.to_puiseux

    arguments = expression.arguments
    if expression.operation == "add"
      result = FormalPuiseuxSeries.constant(
        0, maximum_power, variable, center)
      arguments.each -> (argument)
        result += Expression.puiseux_from_expression(
          argument, variable, center, maximum_power)
      return result
    if expression.operation == "multiply"
      result = FormalPuiseuxSeries.constant(
        1, maximum_power, variable, center)
      arguments.each -> (argument)
        result *= Expression.puiseux_from_expression(
          argument, variable, center, maximum_power)
      return result
    if expression.operation == "divide"
      numerator = Expression.puiseux_from_expression(
        arguments[0], variable, center, maximum_power)
      denominator = Expression.puiseux_from_expression(
        arguments[1], variable, center, maximum_power)
      return numerator / denominator
    if expression.operation == "power"
      exponent = arguments[1]
      if exponent.constant?
        raw = exponent.constant_value
        if Expression.integer?(raw) || raw.class_name == "Rational"
          base = Expression.puiseux_from_expression(
            arguments[0], variable, center, maximum_power)
          return base.rational_power(raw)
    if (expression.operation == "sqrt" ||
        expression.operation == "cbrt")
      base = Expression.puiseux_from_expression(
        arguments[0], variable, center, maximum_power)
      denominator = expression.operation == "sqrt" ? 2 : 3
      return base.rational_power(Rational.new(1, denominator))

    argument_index = (
      expression.operation == "polygamma" ? 1 : 0)
    argument = Expression.puiseux_from_expression(
      arguments[argument_index], variable, center, maximum_power)
    if !argument.regular?
      raise (
        "symbolic operation " + expression.operation +
        " at a Puiseux pole is not a Puiseux series")
    parameter_series = (
      argument.to_power_series_in_parameter)
    if expression.operation == "polygamma"
      result = parameter_series.polygamma(
        arguments[0].constant_value)
    elsif expression.operation == "power"
      raise "Puiseux power exponent must be a rational constant"
    else
      result = Expression.apply_series_unary(
        expression.operation, parameter_series)
    FormalPuiseuxSeries.from_parameter_series(
      result, argument.ramification_index)

  -> puiseux_series(variable, center = 0,
                     maximum_power = 6,
                     search_margin = 8)
    FormalPowerSeries.validate_order(maximum_power)
    if !Expression.integer?(search_margin) || search_margin < 0
      raise "Puiseux search margin must be nonnegative"
    working_power = maximum_power + search_margin
    result = Expression.puiseux_from_expression(
      self, variable, center, working_power)
    if result.zero? || result.minimum_exponent > maximum_power
      return FormalPuiseuxSeries.constant(
        0, maximum_power, variable, center)
    if result.maximum_exponent < maximum_power
      raise "Puiseux series has insufficient retained precision"
    result.truncate(maximum_power)
