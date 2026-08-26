# Zero-dimensional ideals: standard monomials and the length dim_F F[x]/I.
# Reopens GroebnerBasis and Ideal; load after groebner.w.

+ GroebnerBasis
  # Leading exponent vectors of a Gröbner basis (nonzero elements only).
  -> .leading_exponent_list(polynomials)
    out = []
    polynomials.each -> (polynomial)
      out.push(polynomial.leading_exponents) if !polynomial.zero?
    out

  # For each variable, the least exponent e such that x_i^e is a leading
  # monomial, or nil when no pure power of x_i leads. The ideal is
  # zero-dimensional exactly when every entry is present.
  -> .pure_power_bounds(polynomials)
    return [] if polynomials.size == 0
    arity = polynomials[0].ring.arity
    bounds = []
    arity.times -> bounds.push(nil)
    GroebnerBasis.leading_exponent_list(polynomials).each -> (exponents)
      active = -1
      count = 0
      i = 0
      while i < arity
        if exponents[i] > 0
          active = i
          count += 1
        i += 1
      if count == 0
        # A nonzero constant leads: the unit ideal, every bound is zero.
        j = 0
        while j < arity
          bounds[j] = 0
          j += 1
      elsif count == 1
        if bounds[active] == nil || exponents[active] < bounds[active]
          bounds[active] = exponents[active]
    bounds

  -> .zero_dimensional_basis?(polynomials)
    bounds = GroebnerBasis.pure_power_bounds(polynomials)
    i = 0
    while i < bounds.size
      return false if bounds[i] == nil
      i += 1
    true

  # Exponent vectors of the monomials not divisible by any leading monomial.
  -> .standard_monomials_of(polynomials)
    if !GroebnerBasis.zero_dimensional_basis?(polynomials)
      raise "standard monomials are only finite for zero-dimensional ideals"
    bounds = GroebnerBasis.pure_power_bounds(polynomials)
    leading = GroebnerBasis.leading_exponent_list(polynomials)
    arity = bounds.size
    out = []
    current = []
    arity.times -> current.push(0)
    total = 1
    bounds.each -> (bound) total = total * bound
    step = 0
    while step < total
      rest = step
      i = 0
      while i < arity
        current[i] = rest % bounds[i]
        rest = rest / bounds[i]
        i += 1
      standard = true
      leading.each -> (exponents)
        standard = false if GroebnerBasis.monomial_divides?(exponents, current)
      if standard
        copy = []
        current.each -> (value) copy.push(value)
        out.push(copy)
      step += 1
    out

  -> .length_of(polynomials)
    GroebnerBasis.standard_monomials_of(polynomials).size

  -> zero_dimensional?
    GroebnerBasis.zero_dimensional_basis?(@polynomials)

  -> standard_monomials
    GroebnerBasis.standard_monomials_of(@polynomials)

  -> standard_monomial_polynomials
    ring = @polynomials[0].ring
    out = []
    standard_monomials.each -> (exponents)
      out.push(ring.monomial(ring.field.one, exponents))
    out

  -> length
    GroebnerBasis.length_of(@polynomials)

+ Ideal
  -> zero_dimensional?
    GroebnerBasis.zero_dimensional_basis?(self.basis)

  -> standard_monomials
    GroebnerBasis.standard_monomials_of(self.basis)

  -> length
    GroebnerBasis.length_of(self.basis)
