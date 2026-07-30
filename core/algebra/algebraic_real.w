# Exact arithmetic on certified real algebraic numbers.
#
# Binary operations are eliminated from
#
#   f(a) = 0, g(b) = 0, z = a op b
#
# by an exact block-order Gröbner basis. The eliminant contains every
# conjugate result. Refinable rational intervals for the selected real
# operands are propagated through the operation until exactly one real root
# of the eliminant remains; its irreducible factor and ordered root index form
# the result. No floating-point value participates in selection.

+ AlgebraicRealArithmetic
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .rational?(value)
    AlgebraicRealArithmetic.integer?(value) || value.class_name == "Rational"

  -> .operand?(value)
    AlgebraicRealArithmetic.rational?(value) || value.class_name == "AlgebraicRealRoot"

  -> .normalize_operand(value)
    if value.class_name == "AlgebraicRealRoot"
      if !value.certificate.verified?
        raise "algebraic-real arithmetic needs a certified operand"
      return value.refined(0)
    if !AlgebraicRealArithmetic.rational?(value)
      raise "algebraic-real arithmetic accepts only exact real algebraic values"
    Rational.coerce(value)

  -> .copy_operand(value)
    value.class_name == "AlgebraicRealRoot" ? value.refined(0) : Rational.coerce(value)

  -> .operand_interval(value)
    if value.class_name == "AlgebraicRealRoot"
      return [value.lower_bound, value.upper_bound]
    rational = Rational.coerce(value)
    [rational, rational]

  -> .operand_zero?(value)
    if value.class_name == "AlgebraicRealRoot"
      return value.zero?
    Rational.coerce(value).zero?

  -> .validate_operation(operation)
    name = operation.to_s
    if name != "+" && name != "-" && name != "*" && name != "/"
      raise "unsupported algebraic-real operation: " + name
    name

  -> .embed_operand(value, ring, index)
    if value.class_name == "AlgebraicRealRoot"
      out = []
      value.minimal_polynomial.each_term -> (coefficient, source_exponents)
        exponents = ring.zero_exponents
        exponents[index] = source_exponents[0]
        out.push([coefficient, exponents])
      return Polynomial.new(ring, out)
    ring.generator(index) - Rational.coerce(value)

  -> .squarefree_monic(polynomial)
    result = polynomial.monic
    derivative = result.derivative(0)
    if !derivative.zero?
      result = (result / result.gcd(derivative)).monic
    if result.degree <= 0 || !result.squarefree?
      raise "algebraic-real elimination did not produce a squarefree polynomial"
    result

  # Image of alpha under z = scale*alpha + shift:
  #
  #   scale^n f((z-shift)/scale).
  #
  # This avoids a three-variable elimination whenever one operand is
  # rational, including translations and nonzero rational scalings.
  -> .affine_image_polynomial(root, scale, shift)
    factor = Rational.coerce(scale)
    offset = Rational.coerce(shift)
    raise "algebraic-real affine image needs nonzero scale" if factor.zero?
    ring = PolynomialRing.new([:z], RationalField.new)
    z = ring.generator(0)
    polynomial = root.minimal_polynomial
    result = ring.zero
    i = 0
    while i <= polynomial.degree
      coefficient = polynomial.coeff(i) * factor ** (polynomial.degree - i)
      result += (z - offset)**i * coefficient if !coefficient.zero?
      i += 1
    AlgebraicRealArithmetic.squarefree_monic(result)

  # Image under z = numerator/alpha:
  #
  #   z^n f(numerator/z) = sum c_i numerator^i z^(n-i).
  -> .reciprocal_image_polynomial(root, numerator)
    value = Rational.coerce(numerator)
    raise "reciprocal image numerator must be nonzero" if value.zero?
    ring = PolynomialRing.new([:z], RationalField.new)
    z = ring.generator(0)
    polynomial = root.minimal_polynomial
    result = ring.zero
    i = 0
    while i <= polynomial.degree
      coefficient = polynomial.coeff(i) * value ** i
      result += z**(polynomial.degree - i) * coefficient if !coefficient.zero?
      i += 1
    AlgebraicRealArithmetic.squarefree_monic(result)

  -> .rational_result_polynomial(value)
    rational = Rational.coerce(value)
    ring = PolynomialRing.new([:z], RationalField.new)
    ring.generator(0) - rational

  -> .rational_operand_eliminant(left, right, operation)
    name = operation.to_s
    left_rational = AlgebraicRealArithmetic.rational?(left)
    right_rational = AlgebraicRealArithmetic.rational?(right)
    if left_rational && right_rational
      lhs = Rational.coerce(left)
      rhs = Rational.coerce(right)
      value = lhs + rhs
      value = lhs - rhs if name == "-"
      value = lhs * rhs if name == "*"
      value = lhs / rhs if name == "/"
      return AlgebraicRealArithmetic.rational_result_polynomial(value)
    if left_rational
      lhs = Rational.coerce(left)
      if name == "+"
        return AlgebraicRealArithmetic.affine_image_polynomial(
          right, 1, lhs)
      if name == "-"
        return AlgebraicRealArithmetic.affine_image_polynomial(
          right, -1, lhs)
      if name == "*"
        return AlgebraicRealArithmetic.rational_result_polynomial(0) if lhs.zero?
        return AlgebraicRealArithmetic.affine_image_polynomial(
          right, lhs, 0)
      if name == "/"
        return AlgebraicRealArithmetic.rational_result_polynomial(0) if lhs.zero?
        return AlgebraicRealArithmetic.reciprocal_image_polynomial(
          right, lhs)
    else
      rhs = Rational.coerce(right)
      if name == "+"
        return AlgebraicRealArithmetic.affine_image_polynomial(
          left, 1, rhs)
      if name == "-"
        return AlgebraicRealArithmetic.affine_image_polynomial(
          left, 1, 0 - rhs)
      if name == "*"
        return AlgebraicRealArithmetic.rational_result_polynomial(0) if rhs.zero?
        return AlgebraicRealArithmetic.affine_image_polynomial(
          left, rhs, 0)
      if name == "/"
        raise "division by zero algebraic real" if rhs.zero?
        return AlgebraicRealArithmetic.affine_image_polynomial(
          left, Rational.new(1) / rhs, 0)
    raise "unsupported algebraic-real rational operation"

  # The generator of Q[z] ∩ <f(a), g(b), z-a op b>. Because the operand
  # polynomials are irreducible and separable over characteristic zero, the
  # source algebra is reduced and the elimination ideal is radical; the defensive
  # squarefree reduction below also makes that invariant explicit.
  -> .elimination_polynomial(left, right, operation, pair_limit = 20_000)
    lhs = AlgebraicRealArithmetic.normalize_operand(left)
    rhs = AlgebraicRealArithmetic.normalize_operand(right)
    name = AlgebraicRealArithmetic.validate_operation(operation)
    if name == "/" && AlgebraicRealArithmetic.operand_zero?(rhs)
      raise "division by zero algebraic real"
    rational_operand = AlgebraicRealArithmetic.rational?(lhs)
    rational_operand = rational_operand || AlgebraicRealArithmetic.rational?(rhs)
    if rational_operand
      return AlgebraicRealArithmetic.rational_operand_eliminant(
        lhs, rhs, name)

    ring = PolynomialRing.new(
      [:__left, :__right, :__result],
      RationalField.new,
      MonomialOrder.product(2, :lex, :grevlex))
    left_variable = ring.generator(0)
    right_variable = ring.generator(1)
    result_variable = ring.generator(2)
    left_polynomial = AlgebraicRealArithmetic.embed_operand(lhs, ring, 0)
    right_polynomial = AlgebraicRealArithmetic.embed_operand(rhs, ring, 1)
    relation = result_variable - left_variable - right_variable
    relation = result_variable - left_variable + right_variable if name == "-"
    relation = result_variable - left_variable * right_variable if name == "*"
    relation = result_variable * right_variable - left_variable if name == "/"

    basis = GroebnerBasis.basis(
      [left_polynomial, right_polynomial, relation], pair_limit)
    result_ring = PolynomialRing.new([:z], RationalField.new)
    eliminant = nil
    basis.each -> (polynomial)
      if polynomial.degree_in_prefix(2) == 0
        candidate = polynomial.drop_variables(2, result_ring)
        if !candidate.zero?
          eliminant = candidate if eliminant == nil
          eliminant = eliminant.gcd(candidate) if eliminant != candidate
    if eliminant == nil || eliminant.degree <= 0
      raise "algebraic-real elimination produced no result polynomial"
    AlgebraicRealArithmetic.squarefree_monic(eliminant)

  -> .minimum(values)
    result = values[0]
    values.each -> result = item if item < result
    result

  -> .maximum(values)
    result = values[0]
    values.each -> result = item if item > result
    result

  -> .refine_away_from_zero(value, refinement_limit)
    return value if value.class_name != "AlgebraicRealRoot"
    steps = 0
    while value.lower_bound <= 0 && value.upper_bound >= 0
      if steps >= refinement_limit
        raise "could not certify a nonzero algebraic denominator"
      value.refine!
      steps += 1
    value

  # Exact rational enclosure of the image of the two open operand intervals.
  -> .operation_interval(left, right, operation,
                         refinement_limit = 10_000)
    name = AlgebraicRealArithmetic.validate_operation(operation)
    rhs = right
    if name == "/"
      if AlgebraicRealArithmetic.operand_zero?(rhs)
        raise "division by zero algebraic real"
      rhs = AlgebraicRealArithmetic.refine_away_from_zero(
        rhs, refinement_limit)

    left_interval = AlgebraicRealArithmetic.operand_interval(left)
    right_interval = AlgebraicRealArithmetic.operand_interval(rhs)
    a = left_interval[0]
    b = left_interval[1]
    c = right_interval[0]
    d = right_interval[1]
    return [a + c, b + d] if name == "+"
    return [a - d, b - c] if name == "-"
    if name == "/"
      reciprocal = [Rational.new(1) / d, Rational.new(1) / c]
      c = reciprocal[0]
      d = reciprocal[1]
    products = [a * c, a * d, b * c, b * d]
    [
      AlgebraicRealArithmetic.minimum(products),
      AlgebraicRealArithmetic.maximum(products)
    ]

  -> .unique_irreducible_factors(polynomial, search_limit)
    factors = []
    polynomial.factor(search_limit).each -> (piece)
      if piece.degree > 0
        found = false
        factors.each -> found = true if item == piece
        factors.push(piece.monic) if !found
    factors

  -> .root_count_in(factor, lower, upper)
    if lower == upper
      return factor.at(lower).zero? ? 1 : 0
    factor.sturm_root_count_closed(lower, upper)

  -> .factor_root_in_interval(factors, lower, upper)
    selected = nil
    total = 0
    factors.each -> (factor)
      count = AlgebraicRealArithmetic.root_count_in(
        factor, lower, upper)
      if count > 0
        selected = factor if selected == nil
        total += count
    [selected, total]

  -> .refine_operand!(value)
    value.refine! if value.class_name == "AlgebraicRealRoot"

  -> .result_from_factor(factor, lower, upper)
    if factor.degree == 1
      return (Rational.new(0) - factor.coeff(0)) / factor.coeff(1)
    if factor.at(lower).zero? || factor.at(upper).zero?
      raise "algebraic-real result interval has a root endpoint"
    index = factor.sturm_root_index_before(lower)
    AlgebraicRealRoot.new(factor.monic, lower, upper, index)

  -> .compute(left, right, operation, pair_limit = 20_000,
              factor_limit = 250_000, refinement_limit = 10_000)
    lhs = AlgebraicRealArithmetic.normalize_operand(left)
    rhs = AlgebraicRealArithmetic.normalize_operand(right)
    name = AlgebraicRealArithmetic.validate_operation(operation)
    if name == "/" && AlgebraicRealArithmetic.operand_zero?(rhs)
      raise "division by zero algebraic real"

    eliminant = AlgebraicRealArithmetic.elimination_polynomial(
      lhs, rhs, name, pair_limit)
    factors = AlgebraicRealArithmetic.unique_irreducible_factors(
      eliminant, factor_limit)
    if factors.size == 0
      raise "algebraic-real eliminant has no nonconstant factor"

    steps = 0
    selected = nil
    interval = nil
    while selected == nil
      interval = AlgebraicRealArithmetic.operation_interval(
        lhs, rhs, name, refinement_limit)
      match = AlgebraicRealArithmetic.factor_root_in_interval(
        factors, interval[0], interval[1])
      if match[1] == 1
        candidate = match[0]
        endpoints_clear = !candidate.at(interval[0]).zero?
        endpoints_clear = endpoints_clear && !candidate.at(interval[1]).zero?
        if candidate.degree == 1 || endpoints_clear
          selected = candidate
      elsif match[1] == 0
        raise "algebraic-real enclosure lost the exact operation result"
      if selected == nil
        if steps >= refinement_limit
          raise "algebraic-real result selection refinement limit exceeded"
        AlgebraicRealArithmetic.refine_operand!(lhs)
        AlgebraicRealArithmetic.refine_operand!(rhs)
        steps += 1

    value = AlgebraicRealArithmetic.result_from_factor(
      selected, interval[0], interval[1])
    AlgebraicRealComputation.new(
      lhs, rhs, name, value, eliminant,
      interval[0], interval[1], pair_limit)

  -> .value(left, right, operation)
    AlgebraicRealArithmetic.compute(left, right, operation).value


+ AlgebraicRealOperationCertificate
  -> new(left, right, @operation, result, @elimination_polynomial,
         lower, upper, @pair_limit = 20_000)
    @left = AlgebraicRealArithmetic.copy_operand(left)
    @right = AlgebraicRealArithmetic.copy_operand(right)
    @result = AlgebraicRealArithmetic.copy_operand(result)
    @lower = Rational.coerce(lower)
    @upper = Rational.coerce(upper)

  -> left
    AlgebraicRealArithmetic.copy_operand(@left)

  -> right
    AlgebraicRealArithmetic.copy_operand(@right)

  -> result
    AlgebraicRealArithmetic.copy_operand(@result)

  -> operation
    @operation

  -> elimination_polynomial
    @elimination_polynomial

  -> interval
    [@lower, @upper]

  -> certified_operand?(value)
    return value.certificate.verified? if value.class_name == "AlgebraicRealRoot"
    AlgebraicRealArithmetic.rational?(value)

  -> result_in_interval?
    if @result.class_name == "AlgebraicRealRoot"
      return false if !@result.certificate.verified?
      return false if (@result <=> @lower) <= 0
      return false if (@result <=> @upper) >= 0
      return false if !@elimination_polynomial.rem(
        @result.defining_polynomial.rename_into(
          @elimination_polynomial.ring)).zero?
      return true
    rational = Rational.coerce(@result)
    inside = rational >= @lower && rational <= @upper
    inside && @elimination_polynomial.at(rational).zero?

  -> verified?
    return false if !certified_operand?(@left)
    return false if !certified_operand?(@right)
    name = @operation.to_s
    return false if name != "+" && name != "-" && name != "*" && name != "/"
    if name == "/" && AlgebraicRealArithmetic.operand_zero?(@right)
      return false
    return false if @elimination_polynomial.class_name != "Polynomial"
    return false if @elimination_polynomial.ring.arity != 1
    return false if @elimination_polynomial.ring.field.class_name != "RationalField"
    expected = AlgebraicRealArithmetic.elimination_polynomial(
      @left, @right, name, @pair_limit)
    return false if expected != @elimination_polynomial
    enclosure = AlgebraicRealArithmetic.operation_interval(
      @left, @right, name)
    return false if enclosure[0] != @lower || enclosure[1] != @upper
    count = AlgebraicRealArithmetic.root_count_in(
      @elimination_polynomial, @lower, @upper)
    return false if count != 1
    result_in_interval?

  -> certified?
    verified?

  -> to_s
    "AlgebraicRealOperationCertificate(" + @operation.to_s + ")"

  -> inspect
    to_s


+ AlgebraicRealComputation
  -> new(left, right, @operation, result, @elimination_polynomial,
         lower, upper, @pair_limit = 20_000)
    @left = AlgebraicRealArithmetic.copy_operand(left)
    @right = AlgebraicRealArithmetic.copy_operand(right)
    @value = AlgebraicRealArithmetic.copy_operand(result)
    @lower = Rational.coerce(lower)
    @upper = Rational.coerce(upper)

  -> value
    AlgebraicRealArithmetic.copy_operand(@value)

  -> result
    value

  -> left
    AlgebraicRealArithmetic.copy_operand(@left)

  -> right
    AlgebraicRealArithmetic.copy_operand(@right)

  -> operation
    @operation

  -> elimination_polynomial
    @elimination_polynomial

  -> interval
    [@lower, @upper]

  -> certificate
    AlgebraicRealOperationCertificate.new(
      @left, @right, @operation, @value, @elimination_polynomial,
      @lower, @upper, @pair_limit)

  -> operation_certificate
    certificate

  -> verified?
    certificate.verified?

  -> certified?
    verified?

  -> to_s
    text = "AlgebraicRealComputation(" + @operation.to_s + ", "
    text + @value.to_s + ")"

  -> inspect
    to_s


+ AlgebraicRealRoot
  -> add_with_certificate(other, pair_limit = 20_000,
                          factor_limit = 250_000)
    AlgebraicRealArithmetic.compute(
      self, other, "+", pair_limit, factor_limit)

  -> subtract_with_certificate(other, pair_limit = 20_000,
                               factor_limit = 250_000)
    AlgebraicRealArithmetic.compute(
      self, other, "-", pair_limit, factor_limit)

  -> multiply_with_certificate(other, pair_limit = 20_000,
                               factor_limit = 250_000)
    AlgebraicRealArithmetic.compute(
      self, other, "*", pair_limit, factor_limit)

  -> divide_with_certificate(other, pair_limit = 20_000,
                             factor_limit = 250_000)
    AlgebraicRealArithmetic.compute(
      self, other, "/", pair_limit, factor_limit)

  -> +(other)
    add_with_certificate(other).value

  -> -(other)
    subtract_with_certificate(other).value

  -> *(other)
    multiply_with_certificate(other).value

  -> /(other)
    divide_with_certificate(other).value

  -> negate
    AlgebraicRealArithmetic.compute(0, self, "-").value

  -> -@
    negate

  -> reciprocal
    AlgebraicRealArithmetic.compute(1, self, "/").value

  -> inverse
    reciprocal

  -> inv
    reciprocal

  -> **(exponent)
    if !AlgebraicRealArithmetic.integer?(exponent)
      raise "algebraic-real exponent must be an integer"
    return self.inverse ** (0 - exponent) if exponent < 0
    result = Rational.new(1)
    factor = self
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = AlgebraicRealArithmetic.compute(
          result, factor, "*").value
      remaining = remaining / 2
      if remaining > 0
        factor = AlgebraicRealArithmetic.compute(
          factor, factor, "*").value
    result

  -> pow(exponent)
    self ** exponent

  -> sq
    self ** 2

  -> cube
    self ** 3

  -> abs2
    sq

  -> nonzero?
    !zero?

  -> zero
    Rational.new(0)

  -> one
    Rational.new(1)

  -> min(other)
    (self <=> other) <= 0 ? self : other

  -> max(other)
    (self <=> other) >= 0 ? self : other

  -> between?(lower, upper)
    (self <=> lower) >= 0 && (self <=> upper) <= 0

  -> clamp(lower, upper)
    return lower if (self <=> lower) < 0
    return upper if (self <=> upper) > 0
    self

  -> abs
    negative? ? self.negate : self

  -> floor
    copy = self.refined(0)
    steps = 0
    while true
      lower_floor = copy.lower_bound.floor
      upper_floor = copy.upper_bound.floor
      return lower_floor if lower_floor == upper_floor
      if upper_floor == lower_floor + 1
        comparison = copy <=> upper_floor
        return lower_floor if comparison < 0
        return upper_floor
      if steps >= 10_000
        raise "algebraic-real floor refinement limit exceeded"
      copy.refine!
      steps += 1

  -> ceil
    lower = floor
    (self <=> lower) == 0 ? lower : lower + 1

  -> truncate
    negative? ? ceil : floor

  -> to_i
    truncate

  # Half values round away from zero, matching Rational and Float.
  -> round
    lower = floor
    midpoint = Rational.new(lower * 2 + 1, 2)
    comparison = self <=> midpoint
    return lower if comparison < 0
    return lower + 1 if comparison > 0
    negative? ? lower : lower + 1

  -> integer?
    (self <=> floor) == 0

  -> fractional_part
    self - truncate


+ Algebra
  -> .certified_real_operation(left, operation, right,
                               pair_limit = 20_000,
                               factor_limit = 250_000)
    AlgebraicRealArithmetic.compute(
      left, right, operation, pair_limit, factor_limit)

  -> .real_algebraic_value(left, operation, right)
    AlgebraicRealArithmetic.value(left, right, operation)
