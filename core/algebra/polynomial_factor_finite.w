# Complete univariate factorization over finite fields.
#
# The pipeline is exact:
#   1. Yun squarefree decomposition, including recursive p-th roots when the
#      derivative vanishes;
#   2. distinct-degree factorization with X^(q^d)-X;
#   3. deterministic Cantor-Zassenhaus equal-degree splitting.
#
# Candidate enumeration is resource-bounded and raises "unknown" on
# exhaustion. PolynomialFactorizationCertificate independently checks the
# product, monicity, and Rabin irreducibility of every returned factor.

+ Polynomial
  -> require_finite_factor_domain
    if @ring.arity != 1 || !@ring.field.finite_field?
      raise "finite-field factorization needs a univariate polynomial over a finite field"
    @ring.field.prepare_arithmetic!

  # In a perfect finite field, the p-th root of a coefficient is inverse
  # Frobenius. A polynomial has a p-th root only when every exponent is
  # divisible by p.
  -> finite_pth_root
    field = require_finite_factor_domain
    characteristic = field.characteristic
    out = []
    self.each_term -> (coefficient, exponents)
      exponent = exponents[0]
      if exponent % characteristic != 0
        raise "finite-field polynomial is not a p-th power"
      root = field.inverse_frobenius(coefficient)
      out.push([root, [exponent / characteristic]])
    Polynomial.new(@ring, out)

  # Returns [squarefree monic factor, multiplicity] pairs.
  -> finite_squarefree_decomposition
    field = require_finite_factor_domain
    return [] if degree <= 0
    polynomial = monic
    derivative_polynomial = polynomial.derivative(0)
    if derivative_polynomial.zero?
      root = polynomial.finite_pth_root
      out = []
      root.finite_squarefree_decomposition.each -> (entry)
        out.push([entry[0], entry[1] * field.characteristic])
      return out

    common = polynomial.finite_fast_gcd(derivative_polynomial)
    remaining = (polynomial / common).monic
    multiplicity = 1
    out = []
    while !remaining.one?
      shared = remaining.finite_fast_gcd(common)
      piece = (remaining / shared).monic
      out.push([piece, multiplicity]) if piece.degree > 0
      remaining = shared.monic
      common = (common / shared).monic
      multiplicity += 1

    if !common.one?
      root = common.finite_pth_root
      root.finite_squarefree_decomposition.each -> (entry)
        out.push([
          entry[0],
          entry[1] * field.characteristic])
    out

  # Returns [product of all irreducibles of degree d, d] pairs.
  -> finite_distinct_degree_decomposition
    field = require_finite_factor_domain
    return [] if degree <= 0
    work = monic
    x = @ring.generator(0)
    frobenius = x.rem(work)
    factor_degree = 1
    out = []
    while work.degree >= factor_degree * 2
      frobenius = frobenius.power_mod(field.order, work)
      common = (frobenius - x).finite_fast_gcd(work).monic
      if common.degree > 0
        out.push([common, factor_degree])
        work = (work / common).monic
        break if work.one?
        frobenius = frobenius.rem(work)
      factor_degree += 1
    if !work.one?
      out.push([work, work.degree])
    out

  # Interpret code in base q as a polynomial of degree below maximum_degree.
  # Digits are already packed elements of the owning finite field, so raw
  # monomial construction is required.
  -> finite_factor_candidate(code, maximum_degree)
    field = @ring.field
    remaining = code
    polynomial = @ring.zero
    exponent = 0
    while exponent < maximum_degree
      coefficient = remaining % field.order
      if !field.zero?(coefficient)
        polynomial = polynomial + @ring.monomial_raw(
          field.element_from_index(coefficient), [exponent])
      remaining = remaining / field.order
      exponent += 1
    polynomial

  -> proper_finite_factor?(factor, polynomial)
    factor.degree > 0 && factor.degree < polynomial.degree

  -> finite_fast_gcd(other)
    other = @ring.coerce(other)
    left = coefficients
    right = other.coefficients
    while right.size > 0
      remainder = dense_element_remainder(left, right)
      left = right
      right = remainder
    return @ring.zero if left.size == 0
    scale = @ring.field.inverse(left[left.size - 1])
    normalized = []
    left.each ->
      normalized.push(@ring.field.multiply(item, scale))
    polynomial_from_dense_elements(normalized)

  # Split a squarefree product whose irreducible factors all have degree d.
  # Candidate enumeration makes Cantor-Zassenhaus deterministic and
  # reproducible. The explicit limit is per recursive split.
  -> finite_equal_degree_factors(factor_degree, search_limit = 250_000)
    field = require_finite_factor_domain
    polynomial = monic
    return [polynomial] if polynomial.degree == factor_degree
    if polynomial.degree % factor_degree != 0
      raise "equal-degree factorization received incompatible degrees"

    code = 1
    attempts = 0
    candidate_limit = field.order ** polynomial.degree
    while code < candidate_limit
      attempts += 1
      if attempts > search_limit
        raise "finite-field equal-degree factor search limit exceeded; factorization unknown"
      candidate = finite_factor_candidate(code, polynomial.degree)
      split = candidate.finite_fast_gcd(polynomial).monic

      if !proper_finite_factor?(split, polynomial)
        if field.characteristic == 2
          trace = @ring.zero
          term = candidate.rem(polynomial)
          iterations = field.absolute_degree * factor_degree
          i = 0
          while i < iterations
            trace = (trace + term).rem(polynomial)
            term = term.power_mod(2, polynomial)
            i += 1
          split = trace.finite_fast_gcd(polynomial).monic
        else
          exponent = (field.order ** factor_degree - 1) / 2
          residue = candidate.power_mod(exponent, polynomial)
          split = (residue - @ring.one).finite_fast_gcd(
            polynomial).monic

      if proper_finite_factor?(split, polynomial)
        quotient = (polynomial / split).monic
        left = split.finite_equal_degree_factors(
          factor_degree, search_limit)
        right = quotient.finite_equal_degree_factors(
          factor_degree, search_limit)
        return left + right
      code += 1
    raise "finite-field equal-degree factor search exhausted the candidate space"

  # Rabin irreducibility over F_q, including extension coefficient fields.
  -> finite_field_irreducible?
    field = require_finite_factor_domain
    return false if degree <= 0
    polynomial = monic
    return true if polynomial.degree == 1
    x = @ring.generator(0)
    critical_degrees = []
    field.prime_divisors(polynomial.degree).each ->
      critical_degrees.push(polynomial.degree / item)
    frobenius = x
    iteration = 1
    while iteration <= polynomial.degree
      frobenius = frobenius.power_mod(field.order, polynomial)
      if critical_degrees.include?(iteration)
        common = (frobenius - x).finite_fast_gcd(polynomial)
        return false if common.degree > 0
      iteration += 1
    (frobenius - x).rem(polynomial).zero?

  -> sort_finite_factors(factors)
    factors.sort -> (left, right)
      comparison = left.degree <=> right.degree
      comparison = left.to_s <=> right.to_s if comparison == 0
      comparison

  # Unit times monic irreducibles, with multiplicity, matching the rational
  # factor API.
  -> factor_finite_field(search_limit = 250_000)
    field = require_finite_factor_domain
    return [self] if zero?
    return [@ring.one] if one?
    limit_class = search_limit.class_name
    if limit_class != "Integer" && limit_class != "Int" && limit_class != "BigInt"
      raise "finite-field factor search limit must be an integer"
    raise "finite-field factor search limit must be positive" if search_limit < 1

    unit = leading_coefficient
    work = monic
    factors = []
    work.finite_squarefree_decomposition.each -> (squarefree_entry)
      squarefree = squarefree_entry[0]
      multiplicity = squarefree_entry[1]
      squarefree.finite_distinct_degree_decomposition.each -> (degree_entry)
        block = degree_entry[0]
        factor_degree = degree_entry[1]
        irreducibles = block.finite_equal_degree_factors(
          factor_degree, search_limit)
        irreducibles.each -> (factor)
          i = 0
          while i < multiplicity
            factors.push(factor.monic)
            i += 1

    factors = sort_finite_factors(factors)
    if !field.one?(unit)
      factors = [
        @ring.monomial_raw(unit, @ring.zero_exponents)
      ] + factors
    factors

  -> factor_with_certificate(search_limit = 250_000)
    PolynomialFactorization.new(
      self, self.factor(search_limit), search_limit)

  -> factorization(search_limit = 250_000)
    self.factor_with_certificate(search_limit)


+ PolynomialFactorizationCertificate
  -> new(@polynomial, factors, @search_limit = 250_000)
    @factors = []
    factors.each -> @factors.push(item)

  -> polynomial
    @polynomial

  -> factors
    out = []
    @factors.each -> out.push(item)
    out

  -> verified?
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @factors.size == 0
    if @polynomial.zero?
      return @factors.size == 1 && @factors[0].zero?

    product = @polynomial.ring.one
    constants = 0
    factor_index = 0
    while factor_index < @factors.size
      factor = @factors[factor_index]
      return false if factor.class_name != "Polynomial"
      return false if factor.ring != @polynomial.ring
      return false if factor.zero?
      product = product * factor
      if factor.constant?
        constants += 1
      else
        return false if !factor.eql?(factor.monic)
        if @polynomial.ring.field.finite_field?
          return false if !factor.finite_field_irreducible?
        elsif @polynomial.ring.field.class_name == "RationalField"
          pieces = factor.factor(@search_limit)
          nonconstant = []
          pieces.each ->
            nonconstant.push(item) if item.degree > 0
          return false if nonconstant.size != 1
          return false if !nonconstant[0].eql?(factor)
        else
          return false
      factor_index += 1
    return false if constants > 1
    product.eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "PolynomialFactorizationCertificate(" + @polynomial.to_s + ")"

  -> inspect
    to_s


+ PolynomialFactorization
  -> new(@polynomial, factors, @search_limit = 250_000)
    @factors = []
    factors.each -> @factors.push(item)
    if !certificate.verified?
      raise "polynomial factorization certificate failed"

  -> polynomial
    @polynomial

  -> factors
    out = []
    @factors.each -> out.push(item)
    out

  -> certificate
    PolynomialFactorizationCertificate.new(
      @polynomial, @factors, @search_limit)

  -> certified?
    certificate.verified?

  -> to_s
    "PolynomialFactorization(" + @factors.size.to_s + " factors)"

  -> inspect
    to_s
