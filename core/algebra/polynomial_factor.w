# Exact univariate factorization over ℚ.
# Reopens Polynomial; load after polynomial_gcd.w.
# Finite-field factorization is layered in polynomial_factor_finite.w.

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
