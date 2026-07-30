# Finite-field reductions of plane curves and exact zeta numerators.
#
# The finite-field elements themselves stay packed Integers owned by a
# FiniteField context.  The zeta numerator is deliberately a dense integer
# polynomial: #J(F_q) = L(1) must be an Integer, not a Rational with
# denominator one leaking through the public API.

+ IntegerPolynomial
  -> new(coefficients)
    raise "integer-polynomial coefficients must be an Array" if coefficients.class_name != "Array"
    @coefficients = []
    coefficients.each -> (coefficient)
      coefficient_class = coefficient.class_name
      if coefficient_class == "Rational"
        raise "integer polynomial needs integral coefficients" if coefficient.denominator != 1
        coefficient = coefficient.numerator
        coefficient_class = coefficient.class_name
      if coefficient_class != "Integer" && coefficient_class != "Int" && coefficient_class != "BigInt"
        raise "integer polynomial needs integral coefficients"
      @coefficients.push(coefficient)
    while @coefficients.size > 1 && @coefficients[@coefficients.size - 1] == 0
      @coefficients.delete_at(@coefficients.size - 1)
    @coefficients.push(0) if @coefficients.size == 0

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  -> coefficient(index)
    return 0 if index < 0 || index >= @coefficients.size
    @coefficients[index]

  -> []/1
    coefficient(@1)

  -> degree
    @coefficients.size - 1

  -> zero?
    @coefficients.size == 1 && @coefficients[0] == 0

  -> one?
    @coefficients.size == 1 && @coefficients[0] == 1

  -> at(value)
    result = 0
    i = degree
    while i >= 0
      result = result * value + @coefficients[i]
      i -= 1
    result

  -> rational_polynomial(name = :T)
    ring = PolynomialRing.new([name], RationalField.new)
    out = ring.zero
    variable = ring.generator(0)
    i = 0
    while i < @coefficients.size
      out = out + variable**i * @coefficients[i] if @coefficients[i] != 0
      i += 1
    out

  -> discriminant
    rational_polynomial.discriminant

  -> factors
    rational_polynomial.factor

  -> factor
    factors

  -> irreducible?
    factors.size == 1 && factors[0].degree == degree

  -> galois_group
    rational_polynomial.galois_group

  -> ==/1
    other = @1
    return false if other.class_name != "IntegerPolynomial"
    @coefficients.to_s == other.coefficients.to_s

  -> to_s
    rational_polynomial.to_s

  -> inspect
    to_s


+ CurveZetaFunction
  -> new(@curve)
    if @curve.field.class_name != "FiniteField"
      raise "curve zeta functions require a finite coefficient field"
    if !@curve.field.prime_field?
      raise "zeta numerator currently requires a curve over a prime field"
    if !@curve.nonsingular?
      raise "zeta numerator requires a nonsingular reduction"
    @counts = []
    @numerator = build_numerator

  -> curve
    @curve

  -> counts
    out = []
    @counts.each -> out.push(item)
    out

  -> numerator
    @numerator

  -> denominator
    q = @curve.field.order
    IntegerPolynomial.new([1, 0 - (q + 1), q])

  -> build_numerator
    genus = @curve.genus
    q = @curve.field.order
    degree = 1
    while degree <= genus
      extension_curve = @curve.extension_curve(degree)
      @counts.push(extension_curve.point_count)
      degree += 1

    # If S_n = q^n + 1 - #C(F_{q^n}), Newton's recurrence for
    # L(T) = exp(-sum S_n T^n/n) is
    #   k*c_k = -sum_{i=1}^k S_i*c_{k-i}.
    coefficients = [1]
    k = 1
    while k <= genus
      total = 0
      i = 1
      while i <= k
        power_sum = q**i + 1 - @counts[i - 1]
        total += power_sum * coefficients[k - i]
        i += 1
      numerator = 0 - total
      if numerator % k != 0
        raise "zeta Newton recurrence did not produce an integer coefficient"
      coefficients.push(numerator / k)
      k += 1

    while coefficients.size < 2 * genus + 1
      coefficients.push(0)
    k = 0
    while k < genus
      coefficients[2 * genus - k] = q**(genus - k) * coefficients[k]
      k += 1
    IntegerPolynomial.new(coefficients)

  -> to_s
    "Zeta(" + @numerator.to_s + " / " + denominator.to_s + ")"

  -> inspect
    to_s


+ Polynomial
  # Exact coefficient base change. External scalar coercion is correct when
  # changing fields (for example Q -> F_p or F_p -> F_{p^n}); retaining the
  # same field uses normalization so packed extension residues are preserved.
  -> change_ring(target_ring)
    if target_ring.class_name != "PolynomialRing"
      raise "polynomial base change needs a PolynomialRing"
    if target_ring.arity != @ring.arity
      raise "polynomial base change requires equal arity"
    i = 0
    while i < @ring.names.size
      if @ring.names[i].to_s != target_ring.names[i].to_s
        raise "polynomial base change requires matching generator names"
      i += 1
    out = []
    self.each_term -> (coefficient, exponents)
      converted = target_ring.field.embed_from(
        @ring.field, coefficient)
      out.push([converted, exponents])
    Polynomial.new(target_ring, out)

+ Curve
  -> finite_field?
    field.finite_field?

  -> change_field(target_field)
    target_field = Field.require_supported(target_field)
    target_space = ProjectiveSpace<FiniteField, 2>.new(
      target_field, 2, @space.coordinate_names)
    Curve.new(target_space, @equation.change_ring(target_space.ring))

  -> reduce(characteristic)
    if field.class_name != "RationalField"
      raise "reduction modulo p requires a curve over ℚ"
    change_field(FiniteField.new(characteristic))

  -> extension_curve(degree)
    if !finite_field?
      raise "finite extension requires a finite-field curve"
    if !field.prime_field?
      raise "extension_curve currently starts from a prime field"
    return self if degree == 1
    change_field(field.extension(degree))

  # Exact projective point count. The direct q^2 affine scan is intentionally
  # the small-field reference path; larger fields use fiber_root_count below.
  -> point_count
    if !finite_field?
      raise "point_count requires a finite-field curve"
    field.prepare_arithmetic!
    q = field.order
    count = q <= 64 ? direct_affine_point_count : fiber_affine_point_count
    count + points_at_infinity_count

  # Trace of geometric Frobenius on H^1:
  #   a_q = q + 1 - #C(F_q).
  # This needs only the base-field point count, unlike the full zeta
  # numerator, and is therefore the right primitive for prime-sum estimates.
  -> frobenius_trace
    if !finite_field?
      raise "frobenius_trace requires a finite-field curve"
    field.order + 1 - point_count

  -> direct_affine_point_count
    q = field.order
    total = 0
    y_index = 0
    while y_index < q
      y = field.element_from_index(y_index)
      x_index = 0
      while x_index < q
        x = field.element_from_index(x_index)
        value = @equation.evaluate_raw([x, y, field.one])
        total += 1 if field.zero?(value)
        x_index += 1
      y_index += 1
    total

  # Count roots in each affine fiber by deg gcd(g(X), X^q-X). The temporary
  # dense kernel keeps every intermediate degree below deg(g), avoiding both a
  # degree-q polynomial and general sparse-Polynomial allocation per fiber.
  -> fiber_affine_point_count
    # Plane quartics in the shell-width workflow are cubic in the affine
    # X-coordinate.  Keep their quotient-ring arithmetic in fixed locals:
    # allocating several short coefficient arrays for every element of
    # F_{p^3} otherwise dominates both memory and runtime.
    cubic_count = cubic_affine_point_count
    return cubic_count if cubic_count != nil

    q = field.order
    total = 0
    y_index = 0
    while y_index < q
      y = field.element_from_index(y_index)
      y_powers = [field.one]
      y_degree = @equation.degree_in(1)
      power = 1
      while power <= y_degree
        y_powers.push(field.multiply(y_powers[power - 1], y))
        power += 1

      coefficients = []
      exponent = 0
      maximum = @equation.degree_in(0)
      while exponent <= maximum
        coefficient = field.zero
        @equation.each_term -> (term_coefficient, powers)
          if powers[0] == exponent
            value = term_coefficient
            if powers[1] > 0
              value = field.multiply(value, y_powers[powers[1]])
            # The affine chart has Z = 1.
            coefficient = field.add(coefficient, value)
        coefficients.push(coefficient)
        exponent += 1

      fiber = dense_trim(coefficients)
      if dense_zero?(fiber)
        total += q
      else
        total += dense_finite_root_count(fiber, q)
      y_index += 1
    total

  # Fast exact path for an affine equation
  #
  #   a3*X^3 + a2(Y)*X^2 + a1(Y)*X + a0(Y).
  #
  # It still computes deg gcd(g, X^q-X), but represents F_q[X]/(g) by three
  # scalar locals.  Returning nil means that the leading X^3 coefficient is
  # not a nonzero constant, so the generic dense path must handle the curve.
  -> cubic_affine_point_count
    return nil if @equation.degree_in(0) != 3

    maximum_y_degree = @equation.degree_in(1)
    by_x = []
    x_exponent = 0
    while x_exponent <= 3
      coefficients = []
      y_exponent = 0
      while y_exponent <= maximum_y_degree
        coefficients.push(field.zero)
        y_exponent += 1
      by_x.push(coefficients)
      x_exponent += 1

    @equation.each_term -> (term_coefficient, powers)
      x_exponent = powers[0]
      y_exponent = powers[1]
      by_x[x_exponent][y_exponent] = field.add(
        by_x[x_exponent][y_exponent], term_coefficient)

    x_exponent = 0
    while x_exponent <= 3
      by_x[x_exponent] = dense_trim(by_x[x_exponent])
      x_exponent += 1

    return nil if by_x[3].size != 1
    y_exponent = 1
    while y_exponent < by_x[3].size
      return nil if !field.zero?(by_x[3][y_exponent])
      y_exponent += 1
    leading = by_x[3][0]
    return nil if field.zero?(leading)
    inverse_leading = field.inverse(leading)

    q = field.order
    total = 0
    y_index = 0
    while y_index < q
      y = field.element_from_index(y_index)
      m0 = field.multiply(dense_at(by_x[0], y), inverse_leading)
      m1 = field.multiply(dense_at(by_x[1], y), inverse_leading)
      m2 = field.multiply(dense_at(by_x[2], y), inverse_leading)
      total += monic_cubic_finite_root_count(m0, m1, m2, q)
      y_index += 1
    total

  -> dense_at(coefficients, value)
    return field.zero if coefficients.size == 0
    result = field.zero
    index = coefficients.size - 1
    while index >= 0
      result = field.add(field.multiply(result, value), coefficients[index])
      index -= 1
    result

  # Number of distinct F_q-roots of a cubic.  The binary powering computes
  # X^q mod g in F_q[X]/(g); the final degree-<=2 Euclidean step is expanded
  # directly.  No heap object is created in the per-fiber hot loop.
  -> cubic_finite_root_count(a0, a1, a2, a3, q)
    inverse_leading = field.inverse(a3)
    m0 = field.multiply(a0, inverse_leading)
    m1 = field.multiply(a1, inverse_leading)
    m2 = field.multiply(a2, inverse_leading)
    monic_cubic_finite_root_count(m0, m1, m2, q)

  -> monic_cubic_finite_root_count(m0, m1, m2, q)
    # result = 1, factor = X in F_q[X]/(X^3+m2*X^2+m1*X+m0)
    r0 = field.one
    r1 = field.zero
    r2 = field.zero
    s0 = field.zero
    s1 = field.one
    s2 = field.zero
    remaining = q

    while remaining > 0
      if remaining.odd?
        d0 = field.multiply(r0, s0)
        d1 = field.add(field.multiply(r0, s1), field.multiply(r1, s0))
        d2 = field.add(
          field.add(field.multiply(r0, s2), field.multiply(r1, s1)),
          field.multiply(r2, s0))
        d3 = field.add(field.multiply(r1, s2), field.multiply(r2, s1))
        d4 = field.multiply(r2, s2)

        d3 = field.subtract(d3, field.multiply(d4, m2))
        d2 = field.subtract(d2, field.multiply(d4, m1))
        d1 = field.subtract(d1, field.multiply(d4, m0))
        d2 = field.subtract(d2, field.multiply(d3, m2))
        d1 = field.subtract(d1, field.multiply(d3, m1))
        d0 = field.subtract(d0, field.multiply(d3, m0))
        r0 = d0
        r1 = d1
        r2 = d2

      remaining = remaining / 2
      if remaining > 0
        d0 = field.multiply(s0, s0)
        d1 = field.add(field.multiply(s0, s1), field.multiply(s1, s0))
        d2 = field.add(
          field.add(field.multiply(s0, s2), field.multiply(s1, s1)),
          field.multiply(s2, s0))
        d3 = field.add(field.multiply(s1, s2), field.multiply(s2, s1))
        d4 = field.multiply(s2, s2)

        d3 = field.subtract(d3, field.multiply(d4, m2))
        d2 = field.subtract(d2, field.multiply(d4, m1))
        d1 = field.subtract(d1, field.multiply(d4, m0))
        d2 = field.subtract(d2, field.multiply(d3, m2))
        d1 = field.subtract(d1, field.multiply(d3, m1))
        d0 = field.subtract(d0, field.multiply(d3, m0))
        s0 = d0
        s1 = d1
        s2 = d2

    h0 = r0
    h1 = field.subtract(r1, field.one)
    h2 = r2

    if field.zero?(h2)
      if field.zero?(h1)
        return field.zero?(h0) ? 3 : 0

      # Evaluate the monic cubic at -h0/h1 after multiplying through by
      # h1^3.  This avoids a finite-field inversion in every linear fiber.
      negative_h0 = field.subtract(field.zero, h0)
      negative_h0_squared = field.multiply(negative_h0, negative_h0)
      h1_squared = field.multiply(h1, h1)
      value = field.add(
        field.add(
          field.multiply(negative_h0_squared, negative_h0),
          field.multiply(
            field.multiply(m2, negative_h0_squared), h1)),
        field.add(
          field.multiply(
            field.multiply(m1, negative_h0), h1_squared),
          field.multiply(field.multiply(m0, h1_squared), h1)))
      return field.zero?(value) ? 1 : 0

    # Pseudo-divide the monic cubic by h2*X^2+h1*X+h0.  The following is
    # h2^2 times the linear remainder, so no inverse is needed:
    #
    #   R1 = h1^2 - h2*h0 - m2*h2*h1 + m1*h2^2
    #   R0 = h1*h0 - m2*h2*h0 + m0*h2^2.
    h2_squared = field.multiply(h2, h2)
    remainder1 = field.subtract(
      field.add(
        field.subtract(
          field.multiply(h1, h1), field.multiply(h2, h0)),
        field.multiply(m1, h2_squared)),
      field.multiply(field.multiply(m2, h2), h1))
    remainder0 = field.add(
      field.subtract(
        field.multiply(h1, h0),
        field.multiply(field.multiply(m2, h2), h0)),
      field.multiply(m0, h2_squared))

    if field.zero?(remainder1)
      return field.zero?(remainder0) ? 2 : 0

    # The linear remainder has root -R0/R1.  Multiply h(root) by R1^2
    # before testing it, again retaining exactness without division.
    remainder0_squared = field.multiply(remainder0, remainder0)
    remainder1_squared = field.multiply(remainder1, remainder1)
    quadratic_value = field.add(
      field.subtract(
        field.multiply(h2, remainder0_squared),
        field.multiply(
          field.multiply(h1, remainder0), remainder1)),
      field.multiply(h0, remainder1_squared))
    field.zero?(quadratic_value) ? 1 : 0

  -> dense_copy(values)
    out = []
    values.each -> out.push(item)
    out

  -> dense_trim(values)
    out = dense_copy(values)
    while out.size > 0 && field.zero?(out[out.size - 1])
      out.delete_at(out.size - 1)
    out

  -> dense_zero?(values)
    values.size == 0

  -> dense_remainder(dividend, divisor)
    divisor = dense_trim(divisor)
    raise "dense polynomial division by zero" if dense_zero?(divisor)
    remainder = dense_trim(dividend)
    divisor_degree = divisor.size - 1
    divisor_leading = divisor[divisor_degree]
    while remainder.size > 0 && remainder.size - 1 >= divisor_degree
      remainder_degree = remainder.size - 1
      scale = field.divide(remainder[remainder_degree], divisor_leading)
      shift = remainder_degree - divisor_degree
      i = 0
      while i <= divisor_degree
        target = shift + i
        remainder[target] = field.subtract(
          remainder[target], field.multiply(scale, divisor[i]))
        i += 1
      remainder = dense_trim(remainder)
    remainder

  -> dense_multiply_mod(left, right, modulus)
    return [] if dense_zero?(left) || dense_zero?(right)
    product = []
    size = left.size + right.size - 1
    i = 0
    while i < size
      product.push(field.zero)
      i += 1
    i = 0
    while i < left.size
      j = 0
      while j < right.size
        product[i + j] = field.add(
          product[i + j], field.multiply(left[i], right[j]))
        j += 1
      i += 1
    dense_remainder(product, modulus)

  -> dense_x_power_mod(exponent, modulus)
    result = [field.one]
    factor = dense_remainder([field.zero, field.one], modulus)
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = dense_multiply_mod(result, factor, modulus)
      remaining = remaining / 2
      if remaining > 0
        factor = dense_multiply_mod(factor, factor, modulus)
    result

  -> dense_subtract(left, right)
    size = left.size > right.size ? left.size : right.size
    out = []
    i = 0
    while i < size
      a = i < left.size ? left[i] : field.zero
      b = i < right.size ? right[i] : field.zero
      out.push(field.subtract(a, b))
      i += 1
    dense_trim(out)

  -> dense_gcd(left, right)
    a = dense_trim(left)
    b = dense_trim(right)
    while !dense_zero?(b)
      remainder = dense_remainder(a, b)
      a = b
      b = remainder
    return [] if dense_zero?(a)
    inverse = field.inverse(a[a.size - 1])
    out = []
    coefficient_field = field
    a.each -> out.push(coefficient_field.multiply(item, inverse))
    dense_trim(out)

  -> dense_finite_root_count(polynomial, q)
    return 0 if polynomial.size <= 1
    x_power = dense_x_power_mod(q, polynomial)
    frobenius = dense_subtract(x_power, [field.zero, field.one])
    dense_gcd(polynomial, frobenius).size - 1

  -> points_at_infinity_count
    q = field.order
    total = 0
    slope_index = 0
    while slope_index < q
      slope = field.element_from_index(slope_index)
      value = @equation.evaluate_raw([field.one, slope, field.zero])
      total += 1 if field.zero?(value)
      slope_index += 1
    value = @equation.evaluate_raw([field.zero, field.one, field.zero])
    total += 1 if field.zero?(value)
    total

  -> zeta
    if @zeta_cache == nil
      @zeta_cache = CurveZetaFunction.new(self)
    @zeta_cache

  -> weil_cubic
    if !finite_field? || !field.prime_field?
      raise "Weil cubic requires a curve over a prime field"
    coefficients = zeta.numerator.coefficients
    if coefficients.size != 7
      raise "Weil cubic is currently implemented for genus three"
    q = field.order
    e1 = 0 - coefficients[1]
    e2 = coefficients[2] - 3 * q
    e3 = 0 - coefficients[3] + 2 * q * coefficients[1]
    ring = PolynomialRing.new([:x], RationalField.new)
    x = ring.generator(0)
    WeilCubic.new(x**3 - x**2 * e1 + x * e2 - e3)


+ WeilCubic
  -> coefficients
    @polynomial.coefficients

  -> degree
    @polynomial.degree

  -> at(value)
    @polynomial.at(value)

  -> irreducible?
    @polynomial.irreducible?

  -> roots_in(number_field)
    @polynomial.roots_in(number_field)

  -> field_discriminant
    @polynomial.field_discriminant

  -> to_s
    @polynomial.to_s

  -> inspect
    to_s
