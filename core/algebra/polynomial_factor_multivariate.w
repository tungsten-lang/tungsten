# Bivariate factorization over finite fields by Hensel lifting.
#
# For f(x, y) over a finite field the pipeline is exact:
#   1. content in the main variable and squarefree part via multivariate gcd;
#   2. a specialization point a with lc_y(f)(a) != 0 and f(a, y) squarefree;
#   3. univariate factorization of f(a, y) (polynomial_factor_finite.w);
#   4. linear multifactor Hensel lifting of the monic factors modulo
#      (x - a)^k with k > deg_x f, in dense truncated-series arithmetic;
#   5. Zassenhaus recombination: lc_y(f) * (subset product), primitive part,
#      trial division;
#   6. multiplicities by trial division; inseparable leftovers (zero
#      derivative in the main variable) by swapping the main variable or
#      taking a p-th root.
# Reopens Polynomial; load after polynomial_factor_finite.w / polynomial_gcd.w.
#
# Three or more variables use the same pipeline with the ideal
# m = (x_1 - a_1, ..., x_r - a_r) of the auxiliary variables in place of
# (x - a): a point a with lc_y(f)(a) != 0 and f(a, y) squarefree (the point
# with the fewest univariate factors among a few good ones), univariate
# factorization of f(a, y), Hensel lifting of the monic factors modulo
# m^(D + 1) with D the total degree of f in the auxiliary variables (one
# m-adic layer per step, the linear correction solved through the
# univariate Bezout cofactors), and the same recombination: candidates
# lc_y(current) * (subset product), shifted back, made primitive in y by the
# modular multivariate content, accepted by exact trial division. Truncated
# power series are ordinary sparse polynomials in the shifted variables cut
# at total degree D, so the lifting cost is governed by the number of
# monomials of degree <= D in r variables rather than by any dense grid.

+ Polynomial
  -> require_multivariate_factor_domain
    if !@ring.field.finite_field?
      raise "multivariate factorization needs a finite coefficient field"
    if @ring.arity < 2
      raise "multivariate factorization needs at least two variables"
    @ring.field.prepare_arithmetic!

  # ---------------------------------------------------------------------
  # Dense univariate helpers on arrays of normalized field elements.

  -> mf_dense_trim(values)
    out = []
    values.each -> out.push(item)
    while out.size > 0 && field_zero?(out[out.size - 1])
      out.delete_at(out.size - 1)
    out

  -> mf_dense_pad(values, size)
    out = []
    values.each -> out.push(item)
    while out.size < size
      out.push(@ring.field.zero)
    out

  -> mf_dense_zero?(values)
    i = 0
    while i < values.size
      return false if !field_zero?(values[i])
      i += 1
    true

  -> mf_dense_add(left, right)
    size = left.size
    size = right.size if right.size > size
    out = []
    i = 0
    while i < size
      a = i < left.size ? left[i] : @ring.field.zero
      b = i < right.size ? right[i] : @ring.field.zero
      out.push(field_add(a, b))
      i += 1
    out

  -> mf_dense_sub(left, right)
    size = left.size
    size = right.size if right.size > size
    out = []
    i = 0
    while i < size
      a = i < left.size ? left[i] : @ring.field.zero
      b = i < right.size ? right[i] : @ring.field.zero
      out.push(field_add(a, field_neg(b)))
      i += 1
    out

  # Product truncated to `size` coefficients.
  -> mf_series_mul(left, right, size)
    out = []
    i = 0
    while i < size
      out.push(@ring.field.zero)
      i += 1
    i = 0
    while i < left.size && i < size
      if !field_zero?(left[i])
        j = 0
        while j < right.size && i + j < size
          if !field_zero?(right[j])
            out[i + j] = field_add(out[i + j], field_mul(left[i], right[j]))
          j += 1
      i += 1
    out

  # Multiplicative inverse of a series with a unit constant term.
  -> mf_series_inverse(values, size)
    raise "series inverse of a non-unit" if values.size == 0 || field_zero?(values[0])
    lead = field_div(@ring.field.one, values[0])
    out = [lead]
    i = 1
    while i < size
      acc = @ring.field.zero
      j = 1
      while j <= i
        a = j < values.size ? values[j] : @ring.field.zero
        if !field_zero?(a)
          acc = field_add(acc, field_mul(a, out[i - j]))
        j += 1
      out.push(field_neg(field_mul(acc, lead)))
      i += 1
    out

  # Taylor shift a(x) -> a(x + c), exact, in place on a copy.
  -> mf_dense_shift(values, c)
    out = []
    values.each -> out.push(item)
    n = out.size
    return out if field_zero?(c)
    i = 0
    while i < n
      j = n - 2
      while j >= i
        out[j] = field_add(out[j], field_mul(c, out[j + 1]))
        j -= 1
      i += 1
    out

  -> mf_dense_eval(values, point)
    acc = @ring.field.zero
    i = values.size - 1
    while i >= 0
      acc = field_add(field_mul(acc, point), values[i])
      i -= 1
    acc

  -> mf_dense_monic(values)
    trimmed = mf_dense_trim(values)
    return trimmed if trimmed.size == 0
    scale = field_div(@ring.field.one, trimmed[trimmed.size - 1])
    out = []
    trimmed.each -> out.push(field_mul(item, scale))
    out

  -> mf_dense_gcd(left, right)
    a = mf_dense_trim(left)
    b = mf_dense_trim(right)
    while b.size > 0
      remainder = dense_element_remainder(a, b)
      a = b
      b = remainder
    mf_dense_monic(a)

  # Exact dense division; raises when the remainder is nonzero.
  -> mf_dense_div(dividend, divisor)
    a = mf_dense_trim(dividend)
    b = mf_dense_trim(divisor)
    raise "dense polynomial division by zero" if b.size == 0
    return [] if a.size == 0
    raise "dense polynomial division is not exact" if a.size < b.size
    quotient = []
    i = 0
    while i <= a.size - b.size
      quotient.push(@ring.field.zero)
      i += 1
    lead = field_div(@ring.field.one, b[b.size - 1])
    while a.size >= b.size
      shift = a.size - b.size
      scale = field_mul(a[a.size - 1], lead)
      quotient[shift] = scale
      i = 0
      while i < b.size
        a[shift + i] = field_add(a[shift + i], field_neg(field_mul(scale, b[i])))
        i += 1
      a = mf_dense_trim(a)
      break if a.size == 0
    raise "dense polynomial division is not exact" if a.size != 0
    quotient

  # ---------------------------------------------------------------------
  # Row form: rows[j] is the dense coefficient (in `other`) of main^j.

  -> mf_rows(main, other)
    dy = degree_in(main)
    dx = degree_in(other)
    rows = []
    j = 0
    while j <= dy
      rows.push(mf_dense_pad([], dx + 1))
      j += 1
    @terms.each -> (term)
      rows[term[1][main]][term[1][other]] = term[0]
    rows

  -> mf_from_rows(rows, main, other)
    terms = []
    j = 0
    while j < rows.size
      i = 0
      while i < rows[j].size
        if !field_zero?(rows[j][i])
          exponents = @ring.zero_exponents
          exponents[main] = j
          exponents[other] = i
          terms.push([rows[j][i], exponents])
        i += 1
      j += 1
    Polynomial.new(@ring, terms)

  -> mf_uni_from_dense(uni, values)
    uni.zero.polynomial_from_dense_elements(mf_dense_trim(values))

  -> mf_uni_to_dense(polynomial)
    polynomial.zero? ? [] : polynomial.coefficients

  # Univariate polynomial in `variable` (the other variable absent) as a
  # polynomial of the univariate ring `uni`.
  -> mf_project(uni, variable)
    values = []
    @terms.each -> (term)
      exponent = term[1][variable]
      while values.size <= exponent
        values.push(@ring.field.zero)
      values[exponent] = term[0]
    mf_uni_from_dense(uni, values)

  -> mf_embed(uni_polynomial, variable)
    values = mf_uni_to_dense(uni_polynomial)
    terms = []
    i = 0
    while i < values.size
      if !field_zero?(values[i])
        exponents = @ring.zero_exponents
        exponents[variable] = i
        terms.push([values[i], exponents])
      i += 1
    Polynomial.new(@ring, terms)

  -> mf_product_of(list)
    acc = @ring.one
    list.each -> acc = acc * item
    acc

  # p-th root of a polynomial all of whose exponents are multiples of p.
  -> mf_pth_root
    characteristic = @ring.field.characteristic
    out = []
    @terms.each -> (term)
      exponents = []
      i = 0
      while i < term[1].size
        if term[1][i] % characteristic != 0
          raise "polynomial is not a p-th power"
        exponents.push(term[1][i] / characteristic)
        i += 1
      out.push([@ring.field.inverse_frobenius(term[0]), exponents])
    Polynomial.new(@ring, out)

  # ---------------------------------------------------------------------
  # Hensel lifting of a monic-in-main polynomial given as rows of series.

  # Product of factor rows truncated to `size` series coefficients.
  -> mf_rows_product(factors, size)
    acc = [mf_dense_pad([@ring.field.one], size)]
    factors.each -> (factor)
      out = []
      total = acc.size + factor.size - 1
      j = 0
      while j < total
        out.push(mf_dense_pad([], size))
        j += 1
      a = 0
      while a < acc.size
        b = 0
        while b < factor.size
          out[a + b] = mf_dense_add(out[a + b], mf_series_mul(acc[a], factor[b], size))
          b += 1
        a += 1
      acc = out
    acc

  # Lift monic coprime univariate factors (polynomials of `uni`) of the
  # specialization at x = 0 to factors of `target` modulo x^size.
  -> mf_hensel_lift(uni, target, base_factors, size)
    count = base_factors.size
    cofactors = []
    i = 0
    while i < count
      others = uni.one
      j = 0
      while j < count
        others = others * base_factors[j] if j != i
        j += 1
      bezout = others.xgcd(base_factors[i])
      if !bezout[0].one?
        raise "Hensel lifting needs coprime specialized factors"
      cofactors.push(bezout[1].rem(base_factors[i]))
      i += 1

    lifted = []
    base_factors.each -> (factor)
      rows = []
      mf_uni_to_dense(factor).each -> (coefficient)
        rows.push(mf_dense_pad([coefficient], size))
      lifted.push(rows)

    t = 1
    while t < size
      product = mf_rows_product(lifted, t + 1)
      error = []
      j = 0
      while j < target.size
        left = j < product.size ? product[j] : []
        value = t < target[j].size ? target[j][t] : @ring.field.zero
        current = t < left.size ? left[t] : @ring.field.zero
        error.push(field_add(value, field_neg(current)))
        j += 1
      if !mf_dense_zero?(error)
        error_polynomial = mf_uni_from_dense(uni, error)
        i = 0
        while i < count
          delta = (error_polynomial * cofactors[i]).rem(base_factors[i])
          delta_values = mf_uni_to_dense(delta)
          j = 0
          while j < delta_values.size
            lifted[i][j][t] = field_add(lifted[i][j][t], delta_values[j])
            j += 1
          i += 1
      t += 1
    lifted

  # ---------------------------------------------------------------------
  # Recombination.

  -> mf_next_combination(indices, pool_size)
    k = indices.size
    i = k - 1
    while i >= 0 && indices[i] == pool_size - k + i
      i -= 1
    return false if i < 0
    indices[i] = indices[i] + 1
    j = i + 1
    while j < k
      indices[j] = indices[j - 1] + 1
      j += 1
    true

  # Candidate factor from a subset of lifted factors: lc * product, shifted
  # back by -a, made primitive in `other`.
  -> mf_candidate(subset_rows, leading, size, point, main, other)
    scaled = mf_rows_product(subset_rows, size)
    rows = []
    j = 0
    while j < scaled.size
      row = mf_series_mul(leading, scaled[j], size)
      rows.push(mf_dense_shift(row, field_neg(point)))
      j += 1
    content = []
    rows.each -> (row)
      content = mf_dense_gcd(content, row)
    if content.size > 1
      reduced = []
      rows.each -> (row)
        reduced.push(mf_dense_div(row, content))
      rows = reduced
    mf_from_rows(rows, main, other).monic

  # Irreducible factors of a squarefree polynomial, primitive in `main`,
  # with positive degree in `main`.
  -> mf_factor_squarefree(main, other, search_limit)
    return [self.monic] if degree_in(main) == 1
    field = @ring.field
    uni = PolynomialRing.new([:mf_y], field)
    rows = mf_rows(main, other)
    dy = rows.size - 1
    size = degree_in(other) + 1

    point = nil
    index = 0
    specialized = nil
    while index < field.order && point.class_name == "Nil"
      candidate = field.element_from_index(index)
      if !field_zero?(mf_dense_eval(rows[dy], candidate))
        values = []
        rows.each -> (row)
          values.push(mf_dense_eval(row, candidate))
        polynomial = mf_uni_from_dense(uni, values)
        derivative_polynomial = polynomial.derivative(0)
        if !derivative_polynomial.zero?
          if polynomial.finite_fast_gcd(derivative_polynomial).degree == 0
            point = candidate
            specialized = polynomial.monic
      index += 1
    if point.class_name == "Nil"
      raise "no squarefree specialization point in the coefficient field; factorization unknown"

    base_factors = []
    specialized.factor(search_limit).each -> (factor)
      base_factors.push(factor.monic) if factor.degree > 0
    return [self.monic] if base_factors.size == 1

    shifted = []
    rows.each -> (row)
      shifted.push(mf_dense_pad(mf_dense_shift(row, point), size))
    inverse = mf_series_inverse(shifted[dy], size)
    target = []
    shifted.each -> (row)
      target.push(mf_series_mul(row, inverse, size))
    lifted = mf_hensel_lift(uni, target, base_factors, size)

    factors = []
    remaining = []
    i = 0
    while i < lifted.size
      remaining.push(i)
      i += 1
    current = self
    current_leading = mf_dense_pad(mf_dense_shift(current.mf_rows(main, other)[current.degree_in(main)], point), size)
    trials = 0
    subset_size = 1
    while subset_size < remaining.size
      indices = []
      i = 0
      while i < subset_size
        indices.push(i)
        i += 1
      found = false
      searching = true
      while searching
        trials += 1
        if trials > search_limit
          raise "multivariate factor recombination limit exceeded; factorization unknown"
        subset = []
        indices.each -> subset.push(lifted[remaining[item]])
        candidate = mf_candidate(subset, current_leading, size, point, main, other)
        if candidate.degree_in(main) > 0
          step = current.divmod(candidate)
          if step[1].zero?
            factors.push(candidate)
            current = step[0]
            kept = []
            i = 0
            while i < remaining.size
              kept.push(remaining[i]) if !indices.include?(i)
              i += 1
            remaining = kept
            current_rows = current.mf_rows(main, other)
            current_leading = mf_dense_pad(mf_dense_shift(current_rows[current.degree_in(main)], point), size)
            found = true
            searching = false
        if searching
          searching = mf_next_combination(indices, remaining.size)
      if !found
        subset_size += 1
    if current.degree_in(main) > 0
      factors.push(current.monic)
    factors

  # ---------------------------------------------------------------------
  # Public entry points.

  # Returns [[factor, multiplicity], ...]; a leading [constant, 1] entry
  # carries the unit when it is not one. Nonconstant factors are monic in
  # the ring's monomial order.
  -> factor_multivariate(search_limit = 250_000)
    require_multivariate_factor_domain
    limit_class = search_limit.class_name
    if limit_class != "Integer" && limit_class != "Int" && limit_class != "BigInt"
      raise "multivariate factor search limit must be an integer"
    raise "multivariate factor search limit must be positive" if search_limit < 1
    return [[self, 1]] if zero?
    return [[self, 1]] if constant?

    entries = mf_factor_entries(search_limit)
    product = @ring.one
    entries.each -> (entry)
      product = product * (entry[0] ** entry[1])
    unit = self / product
    raise "multivariate factorization lost a unit" if !unit.constant?
    sorted = mf_sort_entries(entries)
    if !unit.one?
      sorted = [[unit, 1]] + sorted
    sorted

  # Flat list matching Polynomial#factor: unit first, then monic irreducibles
  # repeated with multiplicity.
  -> multivariate_factors(search_limit = 250_000)
    out = []
    factor_multivariate(search_limit).each -> (entry)
      i = 0
      while i < entry[1]
        out.push(entry[0])
        i += 1
    out

  -> factor_multivariate_with_certificate(search_limit = 250_000)
    PolynomialMultivariateFactorization.new(
      self, factor_multivariate(search_limit), search_limit)

  -> mf_sort_entries(entries)
    entries.sort -> (left, right)
      comparison = left[0].degree <=> right[0].degree
      comparison = left[0].to_s <=> right[0].to_s if comparison == 0
      comparison

  -> mf_merge_entries(entries, factor, multiplicity)
    i = 0
    while i < entries.size
      if entries[i][0].eql?(factor)
        entries[i][1] = entries[i][1] + multiplicity
        return entries
      i += 1
    entries.push([factor, multiplicity])
    entries

  # Variables with positive degree.
  -> mf_active_variables
    out = []
    i = 0
    while i < @ring.arity
      out.push(i) if degree_in(i) > 0
      i += 1
    out

  # Irreducible factors with multiplicities of a nonconstant polynomial.
  -> mf_factor_entries(search_limit)
    return mf_factor_entries_bivariate(search_limit) if @ring.arity == 2
    entries = []
    active = mf_active_variables
    return entries if active.size == 0
    uni = PolynomialRing.new([:mf_u], @ring.field)
    if active.size == 1
      mf_project(uni, active[0]).monic.factor(search_limit).each -> (factor)
        if factor.degree > 0
          entries = mf_merge_entries(entries, mf_embed(factor, active[0]).monic, 1)
      return entries

    # Main variable: the active variable of largest degree with a nonzero
    # derivative (separable); fall back to a p-th root when none exists.
    main = nil
    best = -1
    active.each -> (variable)
      if !derivative(variable).zero? && degree_in(variable) > best
        main = variable
        best = degree_in(variable)
    if main.class_name == "Nil"
      root = mf_pth_root
      root.mf_factor_entries(search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1] * @ring.field.characteristic)
      return entries

    content = modular_content_in(main)
    work = self
    if !content.constant?
      content.mf_factor_entries(search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1])
      work = (self / content).monic
    work.mf_factor_entries_hensel(main, search_limit).each -> (entry)
      entries = mf_merge_entries(entries, entry[0], entry[1])
    entries

  # Arity three or more: squarefree part, Hensel factorization,
  # multiplicities by trial division, leftovers recursively.
  -> mf_factor_entries_hensel(main, search_limit)
    entries = []
    derivative_polynomial = derivative(main)
    common = gcd(derivative_polynomial)
    squarefree = common.constant? ? self.monic : (self / common).monic
    squarefree_content = squarefree.modular_content_in(main)
    if !squarefree_content.constant?
      squarefree = (squarefree / squarefree_content).monic
    irreducibles = squarefree.mf_factor_squarefree_hensel(main, search_limit)
    current = self
    irreducibles.each -> (factor)
      multiplicity = 0
      dividing = true
      while dividing
        step = current.divmod(factor)
        if step[1].zero?
          current = step[0]
          multiplicity += 1
        else
          dividing = false
      entries = mf_merge_entries(entries, factor, multiplicity) if multiplicity > 0
    if !current.constant?
      current.mf_factor_entries(search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1])
    entries

  # Auxiliary variables: every variable other than `main`, in ring order.
  -> mf_auxiliary_variables(main)
    out = []
    i = 0
    while i < @ring.arity
      out.push(i) if i != main
      i += 1
    out

  # Largest total degree in the auxiliary variables over all terms.
  -> mf_aux_total_degree(aux)
    best = 0
    @terms.each -> (term)
      total = 0
      aux.each -> total += term[1][item]
      best = total if total > best
    best

  # Drop every term whose total degree in the auxiliary variables exceeds
  # `bound` (reduction modulo m^(bound + 1)).
  -> mf_truncate(aux, bound)
    out = []
    @terms.each -> (term)
      total = 0
      aux.each -> total += term[1][item]
      out.push([term[0], copy_exponents(term[1])]) if total <= bound
    Polynomial.new(@ring, out)

  # Product of `list` reduced modulo m^(bound + 1) after every step.
  -> mf_truncated_product(list, aux, bound)
    acc = @ring.one
    list.each -> acc = (acc * item).mf_truncate(aux, bound)
    acc

  # Exact substitution x_variable -> x_variable + c.
  -> mf_shift_one(variable, c)
    return self if field_zero?(c)
    limit = degree_in(variable)
    linear_exponents = @ring.zero_exponents
    linear_exponents[variable] = 1
    linear = @ring.monomial_raw(@ring.field.one, linear_exponents)
    linear = linear + @ring.monomial_raw(c, @ring.zero_exponents)
    buckets = []
    e = 0
    while e <= limit
      buckets.push([])
      e += 1
    @terms.each -> (term)
      exponents = copy_exponents(term[1])
      e = exponents[variable]
      exponents[variable] = 0
      buckets[e].push([term[0], exponents])
    out = @ring.zero
    power = @ring.one
    e = 0
    while e <= limit
      if buckets[e].size > 0
        out = out + Polynomial.new(@ring, buckets[e]) * power
      power = power * linear if e < limit
      e += 1
    out

  # Shift every auxiliary variable by the point (or by its negative).
  -> mf_shift(aux, point, negate)
    result = self
    i = 0
    while i < aux.size
      c = negate ? field_neg(point[i]) : point[i]
      result = result.mf_shift_one(aux[i], c)
      i += 1
    result

  # Substitute the auxiliary variables by the point (exponents set to zero).
  -> mf_specialize_aux(aux, point)
    result = self
    i = 0
    while i < aux.size
      result = result.substitute_element(aux[i], point[i])
      i += 1
    result

  # Inverse of a polynomial in the auxiliary variables with a nonzero
  # constant term, modulo m^(bound + 1).
  -> mf_series_inverse_aux(aux, bound)
    constant_term = coeff(@ring.zero_exponents)
    raise "series inverse of a non-unit" if field_zero?(constant_term)
    scale = field_div(@ring.field.one, constant_term)
    rest = self - @ring.monomial_raw(constant_term, @ring.zero_exponents)
    ratio = rest.monomial_multiply_element(@ring.zero_exponents, field_neg(scale))
    acc = @ring.one
    power = @ring.one
    k = 1
    while k <= bound
      power = (power * ratio).mf_truncate(aux, bound)
      break if power.zero?
      acc = acc + power
      k += 1
    acc.monomial_multiply_element(@ring.zero_exponents, scale)

  # A specialization point for the auxiliary variables: lc_main(self)(a) != 0
  # and self(a, main) squarefree. Among up to three good points (exhaustive
  # over small point sets, a fixed pseudo-random sequence otherwise) the one
  # whose univariate image has the fewest irreducible factors is kept, to
  # limit extraneous factors in the recombination. Returns
  # [point, monic univariate factors] or nil.
  -> mf_specialization_point(uni, main, aux, search_limit)
    field = @ring.field
    dy = degree_in(main)
    leading = coefficient_in(main, dy)
    total_points = field.order ** aux.size
    exhaustive = total_points <= 4096
    tries = exhaustive ? total_points : 512
    point = nil
    base_factors = nil
    good = 0
    index = 0
    state = 20260826
    while index < tries && good < 3
      candidate = []
      remaining = index
      aux.each ->
        if exhaustive
          candidate.push(field.element_from_index(remaining % field.order))
          remaining = remaining / field.order
        else
          state = (state * 1103515245 + 12345) % 2147483648
          candidate.push(field.element_from_index(state % field.order))
      index += 1
      next if leading.mf_specialize_aux(aux, candidate).zero?
      image = mf_specialize_aux(aux, candidate).mf_project(uni, main)
      derivative_image = image.derivative(0)
      next if derivative_image.zero?
      next if image.finite_fast_gcd(derivative_image).degree != 0
      good += 1
      factors = []
      image.monic.factor(search_limit).each -> (factor)
        factors.push(factor.monic) if factor.degree > 0
      if base_factors == nil || factors.size < base_factors.size
        point = candidate
        base_factors = factors
      break if base_factors.size == 1
    return nil if point == nil
    [point, base_factors]

  # Lift monic coprime univariate factors (polynomials of `uni`) of
  # target(0, main) to factors of `target` modulo m^(bound + 1); `target` is
  # monic in `main` with coefficients already reduced modulo m^(bound + 1).
  -> mf_hensel_lift_aux(uni, main, aux, target, base_factors, bound)
    count = base_factors.size
    cofactors = []
    moduli = []
    lifted = []
    i = 0
    while i < count
      others = uni.one
      j = 0
      while j < count
        others = others * base_factors[j] if j != i
        j += 1
      bezout = others.xgcd(base_factors[i])
      if !bezout[0].one?
        raise "Hensel lifting needs coprime specialized factors"
      cofactors.push(mf_embed(bezout[1].rem(base_factors[i]), main))
      moduli.push(mf_embed(base_factors[i], main))
      lifted.push(mf_embed(base_factors[i], main))
      i += 1
    t = 1
    while t <= bound
      product = mf_truncated_product(lifted, aux, t)
      error = target.mf_truncate(aux, t) - product
      if !error.zero?
        i = 0
        while i < count
          delta = (error * cofactors[i]).rem(moduli[i])
          lifted[i] = lifted[i] + delta
          i += 1
      t += 1
    lifted

  # Candidate factor from a subset of lifted factors: lc * product modulo
  # m^(bound + 1), shifted back by -a, made primitive in `main`.
  -> mf_candidate_aux(subset, leading, aux, bound, point, main)
    scaled = mf_truncated_product([leading] + subset, aux, bound)
    back = scaled.mf_shift(aux, point, true)
    content = back.modular_content_in(main)
    back = back / content if !content.constant?
    back.monic

  # Irreducible factors of a squarefree polynomial primitive in `main`,
  # with positive degree in `main`, by multivariate Hensel lifting.
  -> mf_factor_squarefree_hensel(main, search_limit)
    return [self.monic] if degree_in(main) == 1
    aux = mf_auxiliary_variables(main)
    uni = PolynomialRing.new([:mf_y], @ring.field)
    dy = degree_in(main)
    bound = mf_aux_total_degree(aux)

    found = mf_specialization_point(uni, main, aux, search_limit)
    if found == nil
      raise "no squarefree specialization point in the coefficient field; factorization unknown"
    point = found[0]
    base_factors = found[1]
    return [self.monic] if base_factors.size == 1

    shifted = mf_shift(aux, point, false)
    inverse = shifted.coefficient_in(main, dy).mf_series_inverse_aux(aux, bound)
    target = (shifted * inverse).mf_truncate(aux, bound)
    lifted = mf_hensel_lift_aux(uni, main, aux, target, base_factors, bound)

    factors = []
    remaining = []
    i = 0
    while i < lifted.size
      remaining.push(i)
      i += 1
    current = self
    current_leading = shifted.coefficient_in(main, dy)
    trials = 0
    subset_size = 1
    while subset_size < remaining.size
      indices = []
      i = 0
      while i < subset_size
        indices.push(i)
        i += 1
      found_subset = false
      searching = true
      while searching
        trials += 1
        if trials > search_limit
          raise "multivariate factor recombination limit exceeded; factorization unknown"
        subset = []
        indices.each -> subset.push(lifted[remaining[item]])
        candidate = mf_candidate_aux(subset, current_leading, aux, bound, point, main)
        if candidate.degree_in(main) > 0
          step = current.divmod(candidate)
          if step[1].zero?
            factors.push(candidate)
            current = step[0]
            kept = []
            i = 0
            while i < remaining.size
              kept.push(remaining[i]) if !indices.include?(i)
              i += 1
            remaining = kept
            current_leading = current.coefficient_in(main, current.degree_in(main)).mf_shift(aux, point, false)
            found_subset = true
            searching = false
        if searching
          searching = mf_next_combination(indices, remaining.size)
      if !found_subset
        subset_size += 1
    if current.degree_in(main) > 0
      factors.push(current.monic)
    factors

  # Exactly two variables: the direct Hensel pipeline above.
  -> mf_factor_entries_bivariate(search_limit)
    entries = []
    uni = PolynomialRing.new([:mf_u], @ring.field)
    main = 1
    other = 0
    if degree_in(main) == 0
      main = 0
      other = 1
    if degree_in(other) == 0
      mf_project(uni, main).monic.factor(search_limit).each -> (factor)
        if factor.degree > 0
          entries = mf_merge_entries(entries, mf_embed(factor, main).monic, 1)
      return entries

    content = content_in(main)
    work = self
    if !content.constant?
      content.mf_factor_entries(search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1])
      work = (self / content).monic

    derivative_polynomial = work.derivative(main)
    if derivative_polynomial.zero?
      if work.derivative(other).zero?
        root = work.mf_pth_root
        root.mf_factor_entries(search_limit).each -> (entry)
          entries = mf_merge_entries(entries, entry[0], entry[1] * @ring.field.characteristic)
        return entries
      work.mf_factor_entries_with_main(other, main, search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1])
      return entries

    work.mf_factor_entries_with_main(main, other, search_limit).each -> (entry)
      entries = mf_merge_entries(entries, entry[0], entry[1])
    entries

  # Factor a polynomial that is primitive in `main` with nonzero derivative
  # in `main`: squarefree part, irreducibles, multiplicities, leftovers.
  -> mf_factor_entries_with_main(main, other, search_limit)
    entries = []
    derivative_polynomial = derivative(main)
    common = gcd(derivative_polynomial)
    squarefree = common.constant? ? self.monic : (self / common).monic
    squarefree_content = squarefree.content_in(main)
    if !squarefree_content.constant?
      squarefree = (squarefree / squarefree_content).monic
    irreducibles = squarefree.mf_factor_squarefree(main, other, search_limit)
    current = self
    irreducibles.each -> (factor)
      multiplicity = 0
      dividing = true
      while dividing
        step = current.divmod(factor)
        if step[1].zero?
          current = step[0]
          multiplicity += 1
        else
          dividing = false
      entries = mf_merge_entries(entries, factor, multiplicity) if multiplicity > 0
    if !current.constant?
      current.mf_factor_entries(search_limit).each -> (entry)
        entries = mf_merge_entries(entries, entry[0], entry[1])
    entries


+ PolynomialMultivariateFactorization
  -> new(@polynomial, entries, @search_limit = 250_000)
    @entries = []
    entries.each -> (entry)
      @entries.push([entry[0], entry[1]])
    @verified_cache = nil

  -> polynomial
    @polynomial

  -> entries
    out = []
    @entries.each -> (entry)
      out.push([entry[0], entry[1]])
    out

  -> factors
    out = []
    @entries.each -> (entry)
      i = 0
      while i < entry[1]
        out.push(entry[0])
        i += 1
    out

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify!
    @verified_cache

  # The product identity holds and every nonconstant factor is monic and
  # indivisible: its own recombination returns it as the single factor.
  -> verify!
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity < 2
    return false if @entries.size == 0
    if @polynomial.zero?
      return @entries.size == 1 && @entries[0][0].zero?
    product = @polynomial.ring.one
    constants = 0
    @entries.each -> (entry)
      factor = entry[0]
      return false if factor.class_name != "Polynomial"
      return false if factor.ring != @polynomial.ring
      return false if factor.zero? || entry[1] < 1
      product = product * (factor ** entry[1])
      if factor.constant?
        constants += 1
      else
        return false if !factor.eql?(factor.monic)
        pieces = factor.factor_multivariate(@search_limit)
        nonconstant = []
        pieces.each -> (piece)
          nonconstant.push(piece) if !piece[0].constant?
        return false if nonconstant.size != 1
        return false if nonconstant[0][1] != 1
        return false if !nonconstant[0][0].eql?(factor)
    return false if constants > 1
    product.eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "PolynomialMultivariateFactorization(" + @entries.size.to_s + " entries)"

  -> inspect
    to_s
