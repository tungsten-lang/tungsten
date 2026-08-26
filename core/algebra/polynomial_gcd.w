# Multivariate primitive GCD and extended Euclidean algorithm.
# Reopens Polynomial; load after polynomial.w / polynomial_resultant.w.

+ Polynomial
  -> coefficient_in(variable, exponent)
    index = variable.class_name == "Int" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    out = []
    @terms.each -> (term)
      if term[1][index] == exponent
        powers = copy_exponents(term[1])
        powers[index] = 0
        out.push([term[0], powers])
    Polynomial.new(@ring, out)

  -> highest_active_variable(other)
    candidate = @ring.arity - 1
    while candidate >= 0
      if degree_in(candidate) > 0 || other.degree_in(candidate) > 0
        return candidate
      candidate -= 1
    -1

  # Coefficient content with respect to x_variable. The recursive GCD starts
  # at the highest variable the coefficients involve, so `variable` need not
  # be the top active variable (the coefficients of x_1 in F[x_1, x_2, x_3]
  # live in F[x_2, x_3]; starting Euclid at x_0 there never terminated).
  -> content_in(variable)
    result = nil
    exponent = 0
    while exponent <= degree_in(variable)
      coefficient = coefficient_in(variable, exponent)
      if !coefficient.zero?
        if result.class_name == "Nil"
          result = coefficient.monic
        else
          result = result.gcd_recursive(coefficient, result.highest_active_variable(coefficient))
      exponent += 1
    result.class_name == "Nil" ? @ring.zero : result.monic

  -> primitive_part_in(variable)
    return self if zero?
    coefficient_content = content_in(variable)
    return monic if coefficient_content.constant?
    (self / coefficient_content).monic

  # Pseudo-division in one selected variable. Unlike ordinary division, the
  # leading coefficient may itself be a polynomial in lower variables, so
  # each step cross-multiplies instead of entering a rational-function field.
  -> pseudo_remainder(divisor, variable)
    divisor = coerce(divisor)
    raise "polynomial division by zero" if divisor.zero?
    divisor_degree = divisor.degree_in(variable)
    divisor_lc = divisor.coefficient_in(variable, divisor_degree)
    remainder = self
    steps = 0
    while !remainder.zero? && remainder.degree_in(variable) >= divisor_degree
      raise "polynomial pseudo-remainder limit exceeded" if steps >= 20_000
      remainder_degree = remainder.degree_in(variable)
      remainder_lc = remainder.coefficient_in(variable, remainder_degree)
      powers = @ring.zero_exponents
      powers[variable] = remainder_degree - divisor_degree
      shift = @ring.monomial_raw(@ring.field.one, powers)
      remainder = divisor_lc * remainder - remainder_lc * shift * divisor
      steps += 1
    remainder

  # Primitive polynomial-remainder sequence over
  # ℚ[x0, ..., x_variable]. This is intentionally slow but exact. It supplies
  # a real multivariate GCD without requiring rational-function coefficients.
  -> gcd_recursive(other, variable)
    other = coerce(other)
    return other.monic if zero?
    return monic if other.zero?

    active = variable
    while active >= 0 && degree_in(active) == 0 && other.degree_in(active) == 0
      active -= 1
    return @ring.one if active < 0

    if active == 0
      left = self
      right = other
      while !right.zero?
        remainder = left.rem(right)
        left = right
        right = remainder
      return left.monic

    left_content = content_in(active)
    right_content = other.content_in(active)
    common_content = left_content.gcd_recursive(right_content, active - 1)
    left = left_content.constant? ? monic : (self / left_content).monic
    right = right_content.constant? ? other.monic : (other / right_content).monic

    while !right.zero?
      remainder = left.pseudo_remainder(right, active)
      if !remainder.zero?
        remainder = remainder.primitive_part_in(active)
      left = right
      right = remainder

    primitive_gcd = left.primitive_part_in(active)
    (common_content * primitive_gcd).monic

  -> gcd(other)
    other = coerce(other)
    gcd_recursive(other, highest_active_variable(other))

  -> primitive_gcd(other)
    gcd(other).monic

  # Extended Euclidean algorithm over a univariate polynomial ring.
  # Returns [g, s, t] with s*self + t*other = g and g monic.
  -> xgcd(other)
    other = coerce(other)
    raise "extended gcd is only defined for univariate polynomials" if @ring.arity != 1
    old_remainder = self
    remainder = other
    old_left = @ring.one
    left = @ring.zero
    old_right = @ring.zero
    right = @ring.one

    while !remainder.zero?
      step = old_remainder.divmod(remainder)
      quotient = step[0]
      next_remainder = step[1]
      old_remainder = remainder
      remainder = next_remainder

      next_left = old_left - quotient * left
      old_left = left
      left = next_left
      next_right = old_right - quotient * right
      old_right = right
      right = next_right

    return [@ring.zero, @ring.zero, @ring.zero] if old_remainder.zero?
    scale = field_div(@ring.field.one, old_remainder.leading_coefficient)
    powers = @ring.zero_exponents
    [old_remainder.monomial_multiply_raw(powers, scale),
     old_left.monomial_multiply_raw(powers, scale),
     old_right.monomial_multiply_raw(powers, scale)]

  -> squarefree?
    return true if degree <= 0
    common = self
    variable = 0
    while variable < @ring.arity
      common = common.gcd(derivative(variable))
      return true if common.degree == 0
      variable += 1
    common.degree == 0
