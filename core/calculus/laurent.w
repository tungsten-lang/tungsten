# FormalLaurentSeries — exact truncated meromorphic local algebra.
#
# Coefficients are exact Expressions indexed by integral powers of
# (x-center), including finitely many negative powers.  Missing powers below
# `minimum_power` are exact zero; powers above `maximum_power` are unknown.
# This models poles and residues, not logarithmic terms, fractional powers, or
# essential singularities.

use core/calculus/series

+ FormalLaurentSeries
  -> new(coefficients, minimum_power = 0,
         variable = :x, center = 0)
    if coefficients.class_name != "Array" || coefficients.size == 0
      raise "FormalLaurentSeries needs a nonempty coefficient Array"
    if !Expression.integer?(minimum_power)
      raise "Laurent minimum power must be an integer"
    @variable_text = variable.to_s
    if @variable_text.empty?
      raise "FormalLaurentSeries variable name cannot be empty"
    @center = Expression.wrap(center)
    @minimum_power = minimum_power
    @maximum_power = minimum_power + coefficients.size - 1
    @coefficients = []
    coefficients.each -> (coefficient)
      @coefficients.push(Expression.wrap(coefficient))
    normalize_leading_zeros

  -> .constant(value, maximum_power,
               variable = :x, center = 0)
    if !Expression.integer?(maximum_power) || maximum_power < 0
      raise "Laurent constant precision must be nonnegative"
    coefficients = [Expression.wrap(value)]
    maximum_power.times ->
      coefficients.push(Expression.constant(0))
    FormalLaurentSeries.new(
      coefficients, 0, variable, center)

  -> .from_power_series(series)
    if series.class_name != "FormalPowerSeries"
      raise "Laurent conversion needs a FormalPowerSeries"
    FormalLaurentSeries.new(
      series.coefficients, 0,
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
      @minimum_power += 1
      index += 1
    self

  -> variable
    @variable_text.to_sym

  -> variable_text
    @variable_text

  -> center
    @center

  -> minimum_power
    @minimum_power

  -> maximum_power
    @maximum_power

  -> order
    @maximum_power

  -> coefficient(power)
    return Expression.constant(0) if power < @minimum_power
    return Expression.constant(0) if power > @maximum_power
    @coefficients[power - @minimum_power]

  -> coefficients
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient)
    out

  -> same_expansion_point?(other)
    (other.variable_text == @variable_text &&
     other.center == @center)

  -> zero?
    index = 0
    while index < @coefficients.size
      return false if !Expression.zero_expression?(
        @coefficients[index])
      index += 1
    true

  -> valuation
    return nil if zero?
    @minimum_power

  -> pole_order
    value = valuation
    return nil if value == nil
    value < 0 ? 0 - value : 0

  -> regular?
    value = valuation
    value == nil || value >= 0

  -> pole?
    !regular?

  -> residue
    coefficient(-1)

  -> coerce(other)
    if other.class_name == "FormalLaurentSeries"
      if !same_expansion_point?(other)
        raise "Laurent series expansion-point mismatch"
      return other
    if @maximum_power < 0
      raise "cannot add a scalar beyond retained Laurent precision"
    FormalLaurentSeries.constant(
      other, @maximum_power, variable, @center)

  -> +(other)
    rhs = coerce(other)
    upper = @maximum_power < rhs.maximum_power ? @maximum_power : rhs.maximum_power
    lower = @minimum_power < rhs.minimum_power ? @minimum_power : rhs.minimum_power
    if upper < lower
      raise "Laurent addition has no common retained precision"
    out = []
    power = lower
    while power <= upper
      out.push(coefficient(power) + rhs.coefficient(power))
      power += 1
    FormalLaurentSeries.new(out, lower, variable, @center)

  -> -(other)
    self + coerce(other).negate

  -> negate
    out = []
    @coefficients.each -> (coefficient)
      out.push(-coefficient)
    FormalLaurentSeries.new(
      out, @minimum_power, variable, @center)

  -> -@
    negate

  -> *(other)
    rhs = coerce(other)
    if zero? || rhs.zero?
      return FormalLaurentSeries.constant(
        0, 0, variable, @center)
    left_value = valuation
    right_value = rhs.valuation
    lower = left_value + right_value
    left_known = @maximum_power + right_value
    right_known = rhs.maximum_power + left_value
    upper = left_known < right_known ? left_known : right_known
    if upper < lower
      raise "Laurent multiplication has insufficient retained precision"
    out = []
    power = lower
    while power <= upper
      value = Expression.constant(0)
      left_power = left_value
      while left_power <= @maximum_power
        right_power = power - left_power
        if (right_power >= right_value &&
            right_power <= rhs.maximum_power)
          value += (
            coefficient(left_power) *
            rhs.coefficient(right_power))
        left_power += 1
      out.push(value)
      power += 1
    FormalLaurentSeries.new(out, lower, variable, @center)

  -> scale(value)
    factor = Expression.wrap(value)
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient*factor)
    FormalLaurentSeries.new(
      out, @minimum_power, variable, @center)

  -> /(other)
    rhs = coerce(other)
    raise "Laurent division by zero series" if rhs.zero?
    if zero?
      return FormalLaurentSeries.constant(
        0, 0, variable, @center)
    left_value = valuation
    right_value = rhs.valuation
    left_tail = @maximum_power - left_value
    right_tail = rhs.maximum_power - right_value
    quotient_order = left_tail < right_tail ? left_tail : right_tail
    numerator_coefficients = []
    denominator_coefficients = []
    index = 0
    while index <= quotient_order
      numerator_coefficients.push(
        coefficient(left_value + index))
      denominator_coefficients.push(
        rhs.coefficient(right_value + index))
      index += 1
    numerator = FormalPowerSeries.new(
      numerator_coefficients, variable, @center)
    denominator = FormalPowerSeries.new(
      denominator_coefficients, variable, @center)
    quotient = numerator / denominator
    FormalLaurentSeries.new(
      quotient.coefficients,
      left_value - right_value,
      variable, @center)

  -> reciprocal
    precision = @maximum_power
    precision = 0 if precision < 0
    FormalLaurentSeries.constant(
      1, precision, variable, @center) / self

  -> integer_power(exponent)
    if !Expression.integer?(exponent)
      raise "Laurent integer power needs an integer exponent"
    if exponent == 0
      return FormalLaurentSeries.constant(
        1, @maximum_power, variable, @center)
    return integer_power(0 - exponent).reciprocal if exponent < 0
    result = FormalLaurentSeries.constant(
      1, @maximum_power, variable, @center)
    factor = self
    remaining = exponent
    while remaining > 0
      result = result*factor if remaining.odd?
      remaining /= 2
      factor = factor*factor if remaining > 0
    result

  -> **(exponent)
    integer_power(exponent)

  -> derivative
    out = []
    power = @minimum_power
    while power <= @maximum_power
      out.push(coefficient(power)*Expression.constant(power))
      power += 1
    result = FormalLaurentSeries.new(
      out, @minimum_power - 1, variable, @center)
    if result.zero? && result.maximum_power < 0
      return FormalLaurentSeries.constant(
        0, 0, variable, @center)
    result

  -> antiderivative(constant = 0)
    if !Expression.zero_expression?(coefficient(-1))
      raise "Laurent antiderivative needs a logarithmic term"
    lower = @minimum_power + 1
    upper = @maximum_power + 1
    lower = 0 if lower > 0
    out = []
    power = lower
    while power <= upper
      if power == 0
        out.push(Expression.wrap(constant))
      else
        out.push(
          coefficient(power - 1) /
          Expression.constant(power))
      power += 1
    FormalLaurentSeries.new(out, lower, variable, @center)

  -> principal_part
    if @minimum_power >= 0
      return FormalLaurentSeries.constant(
        0, 0, variable, @center)
    upper = @maximum_power < -1 ? @maximum_power : -1
    out = []
    power = @minimum_power
    while power <= upper
      out.push(coefficient(power))
      power += 1
    FormalLaurentSeries.new(
      out, @minimum_power, variable, @center)

  -> regular_part
    if @maximum_power < 0
      return FormalLaurentSeries.constant(
        0, 0, variable, @center)
    out = []
    power = 0
    while power <= @maximum_power
      out.push(coefficient(power))
      power += 1
    FormalLaurentSeries.new(out, 0, variable, @center)

  -> to_power_series(requested_order = nil)
    if !regular?
      raise "a Laurent pole cannot be converted to a power series"
    upper = requested_order == nil ? @maximum_power : requested_order
    if upper > @maximum_power
      raise "power-series conversion cannot invent coefficients"
    if upper < 0
      raise "power-series conversion needs nonnegative precision"
    out = []
    power = 0
    while power <= upper
      out.push(coefficient(power))
      power += 1
    FormalPowerSeries.new(out, variable, @center)

  -> truncate(new_maximum_power)
    if !Expression.integer?(new_maximum_power)
      raise "Laurent truncation power must be an integer"
    if new_maximum_power > @maximum_power
      raise "Laurent truncation cannot invent higher coefficients"
    if new_maximum_power < @minimum_power
      raise "Laurent truncation discards every retained coefficient"
    count = new_maximum_power - @minimum_power + 1
    out = []
    index = 0
    while index < count
      out.push(@coefficients[index])
      index += 1
    FormalLaurentSeries.new(
      out, @minimum_power, variable, @center)

  -> to_expression
    symbol = Expression.variable(@variable_text)
    delta = symbol - @center
    terms = []
    power = @minimum_power
    while power <= @maximum_power
      value = coefficient(power)
      if !Expression.zero_expression?(value)
        if power == 0
          terms.push(value)
        else
          terms.push(value*delta**power)
      power += 1
    Expression.sum(terms)

  -> ==(other)
    return false if other == nil
    return false if other.class_name != "FormalLaurentSeries"
    return false if !same_expansion_point?(other)
    return false if @minimum_power != other.minimum_power
    return false if @maximum_power != other.maximum_power
    power = @minimum_power
    while power <= @maximum_power
      return false if coefficient(power) != other.coefficient(power)
      power += 1
    true

  -> eql?(other)
    self == other

  -> to_s
    if @center == Expression.constant(0)
      delta = @variable_text
    else
      delta = '(' + @variable_text + ' - ' + @center.to_s + ')'
    ("LaurentSeries(" + to_expression.to_s +
     " + O(" + delta + "^" +
     (@maximum_power + 1).to_s + "))")

  -> inspect
    to_s


+ FormalPowerSeries
  -> to_laurent
    FormalLaurentSeries.from_power_series(self)


+ Expression
  -> .laurent_from_expression(expression, variable,
                               center, maximum_power)
    if (expression.constant? || expression.named_constant? ||
        !expression.depends_on?(variable))
      return FormalLaurentSeries.constant(
        expression, maximum_power, variable, center)
    if expression.variable?
      power = FormalPowerSeries.variable(
        variable, center, maximum_power)
      return power.to_laurent

    arguments = expression.arguments
    if expression.operation == "add"
      result = FormalLaurentSeries.constant(
        0, maximum_power, variable, center)
      arguments.each -> (argument)
        result += Expression.laurent_from_expression(
          argument, variable, center, maximum_power)
      return result
    if expression.operation == "multiply"
      result = FormalLaurentSeries.constant(
        1, maximum_power, variable, center)
      arguments.each -> (argument)
        result *= Expression.laurent_from_expression(
          argument, variable, center, maximum_power)
      return result
    if expression.operation == "divide"
      numerator = Expression.laurent_from_expression(
        arguments[0], variable, center, maximum_power)
      denominator = Expression.laurent_from_expression(
        arguments[1], variable, center, maximum_power)
      return numerator / denominator
    if expression.operation == "power"
      exponent = arguments[1]
      if (exponent.constant? &&
          Expression.integer?(exponent.constant_value))
        base = Expression.laurent_from_expression(
          arguments[0], variable, center, maximum_power)
        return base.integer_power(exponent.constant_value)

    argument = Expression.laurent_from_expression(
      arguments[0], variable, center, maximum_power)
    if !argument.regular?
      raise (
        "symbolic operation " + expression.operation +
        " at a pole is not a Laurent series")
    power_argument = argument.to_power_series(maximum_power)
    if expression.operation == "polygamma"
      result = power_argument.polygamma(
        arguments[0].constant_value)
    elsif expression.operation == "power"
      exponent = Expression.series_from_expression(
        arguments[1], variable, center, maximum_power)
      result = power_argument ** exponent
    else
      result = Expression.apply_series_unary(
        expression.operation, power_argument)
    result.to_laurent

  -> laurent_series(variable, center = 0,
                     maximum_power = 6,
                     search_margin = 8)
    FormalPowerSeries.validate_order(maximum_power)
    if !Expression.integer?(search_margin) || search_margin < 0
      raise "Laurent search margin must be nonnegative"
    working_power = maximum_power + search_margin
    result = Expression.laurent_from_expression(
      self, variable, center, working_power)
    if result.zero? || result.minimum_power > maximum_power
      return FormalLaurentSeries.constant(
        0, maximum_power, variable, center)
    if result.maximum_power < maximum_power
      raise "Laurent series has insufficient retained precision"
    result.truncate(maximum_power)

  -> residue(variable, point = 0,
              search_margin = 8)
    laurent_series(
      variable, point, 0, search_margin).residue

  -> pole_order_at(variable, point = 0,
                    search_margin = 8)
    laurent_series(
      variable, point, 0, search_margin).pole_order
