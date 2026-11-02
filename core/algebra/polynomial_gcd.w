use algebra/polynomial

# Multivariate primitive GCD, Brown's modular finite-field GCD, and extended
# Euclidean algorithm. Reopens Polynomial; load after polynomial.w.

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

  # Dense coefficient array in one variable of a polynomial that involves
  # only that variable.
  -> dense_coefficients_in(index)
    out = []
    limit = degree_in(index)
    i = 0
    while i <= limit
      out.push(@ring.field.zero)
      i += 1
    @terms.each -> (term)
      out[term[1][index]] = term[0]
    out

  -> polynomial_from_dense_in(values, index)
    terms = []
    i = 0
    while i < values.size
      if !field_zero?(values[i])
        powers = @ring.zero_exponents
        powers[index] = i
        terms.push([values[i], powers])
      i += 1
    Polynomial.new(@ring, terms)

  # Euclid on dense coefficient arrays for two polynomials in one active
  # variable; returns the monic GCD.
  -> dense_gcd_in(other, index)
    left = dense_element_trim(dense_coefficients_in(index))
    right = dense_element_trim(other.dense_coefficients_in(index))
    while right.size > 0
      remainder = dense_element_remainder(left, right)
      left = right
      right = remainder
    return @ring.zero if left.size == 0
    polynomial_from_dense_in(left, index).monic

  # Variables (indices) that appear in either polynomial.
  -> active_variables_with(other)
    out = []
    i = 0
    while i < @ring.arity
      if degree_in(i) > 0 || other.degree_in(i) > 0
        out.push(i)
      i += 1
    out

  # GCD of the coefficients in `main` (polynomials in the other variables).
  -> modular_content_in(main)
    result = @ring.zero
    exponent = 0
    limit = degree_in(main)
    while exponent <= limit
      coefficient = coefficient_in(main, exponent)
      if !coefficient.zero?
        result = result.zero? ? coefficient.monic : result.modular_gcd(coefficient)
        return @ring.one if result.constant?
      exponent += 1
    result

  # Modular GCD; monic, same contract as `gcd`.
  -> modular_gcd(other)
    other = coerce(other)
    return other.monic if zero?
    return monic if other.zero?
    active = active_variables_with(other)
    return @ring.one if active.size == 0
    if active.size == 1
      return dense_gcd_in(other, active[0])
    raise "modular gcd requires a finite coefficient field" if !@ring.field.finite_field?
    result = modular_gcd_active(other, active)
    result.class_name == "Nil" ? gcd_recursive(other, highest_active_variable(other)) : result

  # Returns nil when the field runs out of evaluation points or verification
  # fails, so the caller can fall back to the exact remainder sequence.
  -> modular_gcd_active(other, active)
    main = active[active.size - 1]
    evaluated = active[0]
    left_content = modular_content_in(main)
    right_content = other.modular_content_in(main)
    common_content = left_content.modular_gcd(right_content)
    left = left_content.constant? ? monic : (self / left_content).monic
    right = right_content.constant? ? other.monic : (other / right_content).monic
    left_lc = left.coefficient_in(main, left.degree_in(main))
    right_lc = right.coefficient_in(main, right.degree_in(main))
    gamma = left_lc.modular_gcd(right_lc)
    left_eval_degree = left.degree_in(evaluated)
    right_eval_degree = right.degree_in(evaluated)
    minimum_eval_degree = left_eval_degree < right_eval_degree ? left_eval_degree : right_eval_degree
    bound = gamma.degree_in(evaluated) + minimum_eval_degree
    field = @ring.field
    return nil if field.order <= bound + 1

    interpolant = @ring.zero
    node_product = @ring.one
    nodes = []
    image_degree = -1
    point = 0
    while point < field.order
      value = field.element_from_index(point)
      point += 1
      next if field.zero?(left_lc.substitute_element(evaluated, value).leading_coefficient)
      next if field.zero?(right_lc.substitute_element(evaluated, value).leading_coefficient)
      left_image = left.substitute_element(evaluated, value)
      right_image = right.substitute_element(evaluated, value)
      image_gcd = left_image.modular_gcd(right_image)
      image_main_degree = image_gcd.degree_in(main)
      return common_content.monic if image_main_degree == 0
      if image_degree >= 0 && image_main_degree > image_degree
        next
      if image_degree < 0 || image_main_degree < image_degree
        image_degree = image_main_degree
        interpolant = @ring.zero
        node_product = @ring.one
        nodes = []
      scaled = image_gcd * gamma.substitute_element(evaluated, value)
      difference = scaled - interpolant.substitute_element(evaluated, value)
      if !difference.zero?
        denominator = field.one
        nodes.each -> (node)
          denominator = field.multiply(denominator, field.subtract(value, node))
        scale = field.divide(field.one, denominator)
        correction = node_product.monomial_multiply_raw(@ring.zero_exponents, scale) * difference
        interpolant = interpolant + correction
      powers = @ring.zero_exponents
      powers[evaluated] = 1
      node_factor = @ring.monomial_raw(field.one, powers) - @ring.constant(value)
      node_product = node_product * node_factor
      nodes.push(value)
      if nodes.size > bound
        candidate = interpolant
        candidate_content = candidate.modular_content_in(main)
        if !candidate_content.constant?
          candidate = candidate / candidate_content
        candidate = candidate.monic
        if left.divmod(candidate)[1].zero? && right.divmod(candidate)[1].zero?
          return (common_content * candidate).monic
        return nil
    nil

  -> gcd(other)
    other = coerce(other)
    if @ring.field.finite_field? && @ring.arity >= 2
      return modular_gcd(other)
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
