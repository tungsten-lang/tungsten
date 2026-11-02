use algebra/polynomial_resultant
use algebra/polynomial_gcd

# Exact univariate factorization over ℚ and finite fields, with certificates.
# Reopens Polynomial; load after polynomial_resultant.w and polynomial_gcd.w.

+ Polynomial
  -> integer_divisors(value)
    n = value.abs
    return [0] if n == 0
    out = []
    i = 1
    while i * i <= n
      if n % i == 0
        out.push(i)
        other = n / i
        out.push(other) if other != i
      i += 1
    out

  -> rational_root_candidates
    raise "factorization is only implemented over ℚ" if @ring.field.class_name != "RationalField"
    values = coefficients
    common_denominator = 1
    values.each ->
      common_denominator = (common_denominator / common_denominator.gcd(item.denominator)) * item.denominator
    integers = values.map -> item.numerator * (common_denominator / item.denominator)
    numerators = integer_divisors(integers[0])
    denominators = integer_divisors(integers[integers.size - 1])
    out = []
    numerators.each -> (p)
      denominators.each -> (q)
        if q != 0
          positive = Rational.new(p, q)
          out.push(positive) if !out.include?(positive)
          negative = 0 - positive
          out.push(negative) if !out.include?(negative)
    out

  -> signed_integer_divisors(value)
    out = []
    integer_divisors(value).each -> (divisor)
      out.push(divisor)
      out.push(0 - divisor) if divisor != 0
    out

  # Exact Lagrange interpolation through integer samples. A candidate is
  # useful to Kronecker's method only when every resulting coefficient is an
  # integer.
  -> interpolate_integer_factor(points, values)
    x = @ring.generator(0)
    candidate = @ring.zero
    i = 0
    while i < points.size
      term = @ring.constant(values[i])
      denominator = 1
      j = 0
      while j < points.size
        if i != j
          term = term * (x - points[j])
          denominator = denominator * (points[i] - points[j])
        j += 1
      term = term * Rational.new(1, denominator)
      candidate = candidate + term
      i += 1

    integer_coefficients = true
    candidate.coefficients.each ->
      integer_coefficients = false if item.denominator != 1
    return nil if !integer_coefficients
    candidate

  # Kronecker's theorem turns exact factor search into finite interpolation:
  # for a degree-d integer factor g and d+1 distinct sample points ai,
  # g(ai) divides f(ai). Enumerating those signed divisors and interpolating
  # therefore finds every possible factor of degree at most floor(n/2).
  -> kronecker_factor(search_limit = 250_000)
    primitive = primitive_part
    primitive = primitive.negate if primitive.leading_coefficient.negative?
    maximum_degree = primitive.degree / 2
    target_degree = 1
    attempts = 0

    while target_degree <= maximum_degree
      # Gather a few extra non-root samples, then retain those with the
      # smallest divisor sets. This changes only search order, not completeness.
      samples = []
      sample_index = 0
      wanted = target_degree + 5
      while samples.size < wanted
        if sample_index == 0
          point = 0
        else
          magnitude = (sample_index + 1) / 2
          point = sample_index.odd? ? magnitude : 0 - magnitude
        sample_index += 1
        value = primitive.at(point)
        if !value.zero?
          divisors = signed_integer_divisors(value.numerator)
          entry = [point, divisors]
          sample_position = samples.size
          while sample_position > 0 && divisors.size < samples[sample_position - 1][1].size
            sample_position -= 1
          samples.push(entry)
          sample_shift = samples.size - 1
          while sample_shift > sample_position
            samples[sample_shift] = samples[sample_shift - 1]
            sample_shift -= 1
          samples[sample_position] = entry

      count = target_degree + 1
      points = []
      divisor_sets = []
      i = 0
      while i < count
        points.push(samples[i][0])
        divisor_sets.push(samples[i][1])
        i += 1

      indices = []
      i = 0
      while i < count
        indices.push(0)
        i += 1
      finished = false
      while !finished
        attempts += 1
        if attempts > search_limit
          raise "Kronecker factor search limit exceeded"

        values = []
        i = 0
        while i < count
          values.push(divisor_sets[i][indices[i]])
          i += 1
        candidate = interpolate_integer_factor(points, values)
        if candidate.class_name != "Nil" && candidate.degree > 0 && candidate.degree < primitive.degree
          candidate = candidate.primitive_part
          candidate = candidate.negate if candidate.leading_coefficient.negative?
          if primitive.rem(candidate).zero?
            return candidate

        carry_index = count - 1
        while carry_index >= 0
          next_choice = indices[carry_index] + 1
          indices[carry_index] = next_choice
          choice_set = divisor_sets[carry_index]
          choice_count = choice_set.size
          if next_choice != choice_count
            break
          indices[carry_index] = 0
          carry_index -= 1
        finished = true if carry_index < 0

      target_degree += 1
    nil

  # Exact factorization over ℚ as a content unit times monic irreducible
  # factors (with multiplicity). The constant content is always the product of
  # the returned factors' leading coefficients; non-constant factors are monic.
  # The resource limit fails loudly — an unfinished search is never reported as
  # "irreducible".
  -> factor(search_limit = 250_000)
    raise "factorization is only defined for univariate polynomials" if @ring.arity != 1
    if @ring.field.finite_field?
      return factor_finite_field(search_limit)
    if @ring.field.class_name != "RationalField"
      raise "factorization is currently implemented over ℚ and finite fields"
    return [@ring.one] if one?
    return [self] if zero?

    unit = content
    work = primitive_part
    if work.leading_coefficient.negative?
      unit = 0 - unit
      work = work.negate
    monic_work = work.monic
    unit = unit * work.leading_coefficient
    pieces = factor_monic_primitive(monic_work, search_limit)
    return pieces if field_one?(unit) || field_eq?(unit, @ring.field.one)
    [@ring.constant(unit)] + pieces

  # Factor a monic primitive univariate polynomial into monic irreducibles.
  -> factor_monic_primitive(poly, search_limit)
    return [] if poly.one?
    return [poly] if poly.degree <= 1

    x = poly.ring.generator(0)
    root = nil
    poly.rational_root_candidates.each ->
      if root.class_name == "Nil" && poly.at(item).zero?
        root = item
    if root.class_name != "Nil"
      linear = (x - root).monic
      return [linear] + factor_monic_primitive(poly / linear, search_limit)

    # A monic quadratic or cubic over ℚ is reducible exactly when it has a
    # rational root — already exhausted above.
    return [poly] if poly.degree <= 3

    candidate = poly.kronecker_factor(search_limit)
    return [poly] if candidate.class_name == "Nil"
    left = candidate.monic
    right = (poly / left).monic
    factor_monic_primitive(left, search_limit) + factor_monic_primitive(right, search_limit)

  -> factors
    factor

  # Complete univariate factorization over finite fields:
  #   1. Yun squarefree decomposition, including recursive p-th roots when the
  #      derivative vanishes;
  #   2. distinct-degree factorization with X^(q^d)-X;
  #   3. deterministic Cantor-Zassenhaus equal-degree splitting.
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
    order = @ring.field.order
    remaining = code
    terms = []
    exponent = 0
    if order == 2
      while exponent < maximum_degree && remaining > 0
        if (remaining & 1) != 0
          terms.push([1, [exponent]])
        remaining = remaining >> 1
        exponent += 1
    else
      while exponent < maximum_degree && remaining > 0
        coefficient = remaining % order
        if coefficient != 0
          terms.push([coefficient, [exponent]])
        remaining = remaining / order
        exponent += 1
    # Digits arrive from low to high exponent. Reversing in-place yields the
    # canonical descending term order and avoids allocating a second Array.
    lo = 0
    hi = terms.size - 1
    while lo < hi
      tmp = terms[lo]
      terms[lo] = terms[hi]
      terms[hi] = tmp
      lo += 1
      hi -= 1
    Polynomial.new(@ring, terms, true)

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
    @verified_cache = nil

  ro :polynomial

  -> factors
    out = []
    @factors.each -> out.push(item)
    out

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify!
    @verified_cache

  -> verify!
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
    @certificate_cache = PolynomialFactorizationCertificate.new(
      @polynomial, @factors, @search_limit)
    if !@certificate_cache.verified?
      raise "polynomial factorization certificate failed"

  ro :polynomial

  -> factors
    out = []
    @factors.each -> out.push(item)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "PolynomialFactorization(" + @factors.size.to_s + " factors)"

  -> inspect
    to_s
