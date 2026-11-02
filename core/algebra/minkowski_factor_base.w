# Unconditional certificates that an S-class group has no 2-torsion.
#
# Minkowski's ideal-class theorem says that prime ideals of norm at most an
# explicit bound generate Cl(O_K).  We add the displayed S-prime classes as
# relations and replay principal-ideal relations among that finite factor
# base.  Full rank modulo 2 means that the integral relation lattice has odd
# index in Z^n.  Since Cl(O_K,S) is a quotient of that odd finite group, its
# 2-torsion is trivial.
#
# The ideal arithmetic, prime decompositions, relation vectors, and F2 rank
# are replayed exactly.  Minkowski's theorem is a named trusted theorem import.

+ NumberFieldIdealGeneratorCertificate
  -> new(@search)

  ro :search

  -> proof_kind
    :exact_principal_ideal

  -> kernel_checked?
    true

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    expected = "NumberFieldIdealGeneratorSearch"
    return false if @search.class_name != expected
    ideal = @search.ideal
    return false if ideal.class_name != "NumberFieldIdeal"
    return false if !ideal.certificate.verified?
    field = ideal.field
    generator = @search.generator
    return false if generator == nil
    return false if generator.field != field
    return false if !generator.integral?
    return false if generator.norm.abs != Rational.new(ideal.norm)
    principal = field.principal_ideal(generator)
    principal.eql?(ideal)

  -> certified?
    verified?

  -> to_s
    "NumberFieldIdealGeneratorCertificate"

  -> inspect
    to_s


+ NumberFieldIdealGeneratorBounds
  -> new(@coefficient_bound = 2,
         @element_limit = 100_000,
         @odd_power_limit = 3,
         @reduction_producer = :approximate,
         @ideal_attempt_limit = 100_000,
         @total_element_limit = 100_000_000,
         @prime_start_index = 0,
         @prime_count = nil,
         @relation_anchor_index = nil,
         @minimum_odd_power = 1,
         @use_anchored_relations = true)
    if @coefficient_bound < 1 || @element_limit < 1
      raise "principal-generator search bounds must be positive"
    if @odd_power_limit < 1
      raise "principal ideal odd-power limit must be positive"
    if @minimum_odd_power < 1 || @minimum_odd_power.even?
      raise "principal ideal minimum power must be positive and odd"
    if @minimum_odd_power > @odd_power_limit
      raise "principal ideal minimum power exceeds its power limit"
    if @ideal_attempt_limit < 1 || @total_element_limit < 1
      raise "principal ideal total search bounds must be positive"
    if !IntegerLinearAlgebra.integer_value?(@prime_start_index)
      raise "principal ideal prime start must be an integer"
    if @prime_start_index < 0
      raise "principal ideal prime start must be nonnegative"
    if @prime_count != nil
      if !IntegerLinearAlgebra.integer_value?(@prime_count)
        raise "principal ideal prime count must be an integer"
      if @prime_count < 1
        raise "principal ideal prime count must be positive"
    if @relation_anchor_index != nil
      if !IntegerLinearAlgebra.integer_value?(@relation_anchor_index)
        raise "principal relation anchor must be an integer"
      if @relation_anchor_index < 0
        raise "principal relation anchor must be nonnegative"
    supported = @reduction_producer == :approximate
    supported = true if @reduction_producer == :exact
    if !supported
      raise "principal-generator reduction must be exact or approximate"

  ro :coefficient_bound, :element_limit, :odd_power_limit, :reduction_producer, :ideal_attempt_limit
  ro :total_element_limit, :prime_start_index, :prime_count, :relation_anchor_index
  ro :minimum_odd_power

  -> use_anchored_relations?
    @use_anchored_relations


+ NumberFieldIdealGeneratorSearch
  -> new(@ideal, @coefficient_bound = 2,
         @element_limit = 100_000,
         @reduction_producer = :approximate)
    if @ideal.class_name != "NumberFieldIdeal"
      raise "principal-generator search needs a NumberFieldIdeal"
    if @coefficient_bound < 1 || @element_limit < 1
      raise "principal-generator search bounds must be positive"
    @field = @ideal.field
    @generator = nil
    @tested_elements = 0
    if @reduction_producer == :exact
      @coordinate_basis = @ideal.algebra_ideal.reduced_frobenius_coordinate_basis
    elsif @reduction_producer == :approximate
      @coordinate_basis = @ideal.algebra_ideal.approximate_frobenius_coordinate_basis
    else
      raise "principal-generator reduction must be exact or approximate"
    search
    @certificate_cache = NumberFieldIdealGeneratorCertificate.new(
      self)

  ro :ideal, :field, :generator

  -> found?
    @generator != nil

  ro :tested_elements, :reduction_producer

  -> primitive_oriented_vector?(vector)
    divisor = 0
    first_nonzero = nil
    vector.each -> (coefficient)
      if coefficient != 0
        divisor = divisor.gcd(coefficient.abs)
        first_nonzero = coefficient if first_nonzero == nil
    return false if first_nonzero == nil
    first_nonzero > 0 && divisor == 1

  -> vector_height(vector)
    height = 0
    vector.each -> (coefficient)
      height = coefficient.abs if coefficient.abs > height
    height

  -> centered_coefficient(digit)
    return 0 if digit == 0
    return (digit + 1) / 2 if digit.odd?
    0 - digit / 2

  -> order_coordinates(vector)
    coordinates = []
    i = 0
    while i < @ideal.order.rank
      value = 0 ## big
      basis_index = 0
      while basis_index < vector.size
        term = vector[basis_index] * @coordinate_basis[basis_index][i]
        value += term
        basis_index += 1
      coordinates.push(value)
      i += 1
    coordinates

  -> candidate_generator(coordinates)
    norm = @ideal.order.norm_from_coordinates(
      coordinates)
    return nil if norm.abs != @ideal.norm
    generic = @ideal.order.element(coordinates)
    element = @field.generic_order_vector_to_element(
      generic.coefficients)
    return nil if element.norm.abs != Rational.new(@ideal.norm)
    return element if @field.principal_ideal(
      element).eql?(@ideal)
    nil

  -> search
    height = 1
    while height <= @coefficient_bound
      radix = 2 * height + 1
      code = 0
      total = radix ** @coordinate_basis.size
      while code < total
        vector = []
        remaining = code
        i = 0
        while i < @coordinate_basis.size
          digit = remaining % radix
          vector.push(centered_coefficient(digit))
          remaining = remaining / radix
          i += 1
        selected = vector_height(vector) == height
        selected = false if !primitive_oriented_vector?(vector)
        if selected
          @tested_elements += 1
          return nil if @tested_elements > @element_limit
          coordinates = order_coordinates(vector)
          element = candidate_generator(coordinates)
          if element != nil
            @generator = element
            return element
        code += 1
      height += 1
    nil

  -> certificate
    @certificate_cache

  -> certified?
    found? && certificate.verified?

  -> result
    @generator

  -> to_s
    text = "NumberFieldIdealGeneratorSearch(tested "
    text + @tested_elements.to_s + ")"

  -> inspect
    to_s


+ NumberFieldIdeal
  -> principal_generator_search(
       coefficient_bound = 2,
       element_limit = 100_000,
       reduction_producer = :approximate)
    NumberFieldIdealGeneratorSearch.new(
      self, coefficient_bound, element_limit,
      reduction_producer)

  -> principal_generator(
       coefficient_bound = 2,
       element_limit = 100_000,
       reduction_producer = :approximate)
    search = principal_generator_search(
      coefficient_bound, element_limit,
      reduction_producer)
    if !search.found?
      raise "principal-generator search limit exceeded; principality unknown"
    search.generator


+ NumberFieldPrimeIdeal
  -> principal_generator_search(
       coefficient_bound = 2,
       element_limit = 100_000,
       reduction_producer = :approximate)
    as_ideal.principal_generator_search(
      coefficient_bound, element_limit,
      reduction_producer)

  -> principal_generator(
       coefficient_bound = 2,
       element_limit = 100_000,
       reduction_producer = :approximate)
    as_ideal.principal_generator(
      coefficient_bound, element_limit,
      reduction_producer)


+ NumberFieldMinkowskiLinearPrimeSliceCertificate
  -> new(@slice)
    @verified_cache = nil

  ro :slice

  -> theorem
    "Dedekind-Kummer correspondence between linear factors and degree-one primes"

  -> theorem_reference
    "Dedekind factorization theorem away from the power-order index"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> polynomial_zero_at?(polynomial, root, prime)
    coefficients = polynomial.coefficients
    value = 0
    i = coefficients.size - 1
    while i >= 0
      value = PrimeLinearAlgebra.normalize(
        value * root + coefficients[i],
        prime)
      i -= 1
    value == 0

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    expected = "NumberFieldMinkowskiLinearPrimeSlice"
    return false if @slice.class_name != expected
    field = @slice.field
    return false if field.class_name != "NumberField"
    prime = @slice.prime
    bound = @slice.bound
    return false if prime < 2 || !prime.prime?
    return false if prime > bound
    return false if prime * prime <= bound
    computation = field.maximal_order_computation
    return false if computation == nil
    return false if !computation.certificate.verified?
    return false if computation.index % prime == 0

    polynomial = @slice.reduced_polynomial
    finite_field = polynomial.ring.field
    return false if finite_field.class_name != "FiniteField"
    return false if !finite_field.prime_field?
    return false if finite_field.characteristic != prime
    source = computation.source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      source.ring.names, FiniteField.new(prime))
    expected_polynomial = source.change_ring(
      finite_ring).monic
    return false if !polynomial.eql?(expected_polynomial)

    expected_roots = []
    constant = 0
    while constant < prime
      root = PrimeLinearAlgebra.normalize(
        0 - constant, prime)
      if polynomial_zero_at?(
           polynomial, root, prime)
        expected_roots.push(root)
      constant += 1
    roots = @slice.roots
    return false if roots.to_s != expected_roots.to_s
    certificates = @slice.root_certificates
    ideals = @slice.prime_ideals
    multiplicities = @slice.multiplicities
    return false if certificates.size != roots.size
    return false if ideals.size != roots.size
    return false if multiplicities.size != roots.size

    i = 0
    while i < roots.size
      root_certificate = certificates[i]
      expected_class = "DedekindLinearRootCertificate"
      return false if root_certificate.class_name != expected_class
      return false if !root_certificate.verified?
      return false if root_certificate.root != roots[i]
      factor = root_certificate.factor
      work = polynomial
      multiplicity = 0
      while work.degree > 0 && work.rem(factor).zero?
        work = work / factor
        multiplicity += 1
      return false if multiplicity < 1
      return false if multiplicities[i] != multiplicity

      ideal = ideals[i]
      return false if !ideal.certificate.verified?
      return false if ideal.field != field
      return false if ideal.rational_prime != prime
      return false if ideal.residue_degree != 1
      return false if ideal.ramification_index != multiplicity
      map = ideal.algebra_prime_ideal.residue_map
      return false if map.root_certificate != root_certificate
      j = 0
      while j < i
        return false if ideal.eql?(ideals[j])
        j += 1
      i += 1
    true

  -> certified?
    verified?


+ NumberFieldMinkowskiLinearPrimeSlice
  -> new(@field, @prime, @bound)
    if @field.class_name != "NumberField"
      raise "Minkowski prime slice needs a NumberField"
    if @prime < 2 || !@prime.prime?
      raise "Minkowski prime slice needs a rational prime"
    if @prime > @bound || @prime * @prime <= @bound
      raise "linear Minkowski slice needs p <= B < p^2"
    @field.certify_maximal_order
    computation = @field.maximal_order_computation
    if computation.index % @prime == 0
      raise "linear Minkowski slice needs index prime to p"
    source = computation.source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      source.ring.names, FiniteField.new(@prime))
    @reduced_polynomial = source.change_ring(
      finite_ring).monic
    @roots = []
    @root_certificates = []
    @multiplicities = []
    @prime_ideals = []
    enumerate_degree_one_primes(computation)
    @certificate_cache = NumberFieldMinkowskiLinearPrimeSliceCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "linear Minkowski prime slice failed certification"

  -> enumerate_degree_one_primes(computation)
    constant = 0
    while constant < @prime
      root = PrimeLinearAlgebra.normalize(
        0 - constant, @prime)
      if polynomial_zero_at_root?(root)
        root_certificate = DedekindLinearRootCertificate.new(
          computation, @prime, root)
        factor = root_certificate.factor
        work = @reduced_polynomial
        multiplicity = 0
        while work.degree > 0 && work.rem(factor).zero?
          work = work / factor
          multiplicity += 1
        map = DedekindOrderResidueFieldMap.new(
          computation, @prime, factor, nil,
          root_certificate)
        algebra_ideal = AlgebraPrimeIdeal.new(
          map, multiplicity)
        @roots.push(root)
        @root_certificates.push(root_certificate)
        @multiplicities.push(multiplicity)
        @prime_ideals.push(NumberFieldPrimeIdeal.new(
          @field, algebra_ideal))
      constant += 1

  -> polynomial_zero_at_root?(root)
    coefficients = @reduced_polynomial.coefficients
    value = 0
    i = coefficients.size - 1
    while i >= 0
      value = PrimeLinearAlgebra.normalize(
        value * root + coefficients[i],
        @prime)
      i -= 1
    value == 0

  ro :field, :prime, :bound, :reduced_polynomial

  -> roots
    out = []
    @roots.each -> (root)
      out.push(root)
    out

  -> root_certificates
    out = []
    @root_certificates.each -> (certificate)
      out.push(certificate)
    out

  -> multiplicities
    out = []
    @multiplicities.each -> (multiplicity)
      out.push(multiplicity)
    out

  -> prime_ideals
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldMinkowskiFactorBaseCertificate
  -> new(@factor_base)
    @verified_cache = nil

  ro :factor_base

  -> theorem
    "Minkowski ideal-class theorem"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    expected_class = "NumberFieldMinkowskiFactorBase"
    return false if @factor_base.class_name != expected_class
    field = @factor_base.field
    return false if field.class_name != "NumberField"
    return false if !field.maximal_order_certificate.verified?
    expected_bound = @factor_base.compute_bound
    return false if @factor_base.bound != expected_bound
    limit_exceeded = @factor_base.bound > @factor_base.rational_prime_limit
    return false if limit_exceeded

    s_primes = @factor_base.s_primes
    i = 0
    while i < s_primes.size
      prime = s_primes[i]
      return false if prime.class_name != "NumberFieldPrimeIdeal"
      return false if prime.field != field
      return false if !prime.certificate.verified?
      j = 0
      while j < i
        return false if prime.eql?(s_primes[j])
        j += 1
      i += 1

    slices = @factor_base.minkowski_prime_slices
    expected = []
    rational_prime = 2
    slice_index = 0
    while rational_prime <= @factor_base.bound
      if rational_prime.prime?
        return false if slice_index >= slices.size
        slice = slices[slice_index]
        slice_class = slice.class_name
        full = slice_class == "NumberFieldPrimeDecomposition"
        linear = slice_class == "NumberFieldMinkowskiLinearPrimeSlice"
        return false if !full && !linear
        return false if slice.field != field
        return false if slice.prime != rational_prime
        return false if !slice.certificate.verified?
        slice.prime_ideals.each -> (prime)
          expected.push(prime) if prime.norm <= @factor_base.bound
        slice_index += 1
      rational_prime += 1
    return false if slice_index != slices.size
    actual = @factor_base.minkowski_primes
    return false if !@factor_base.same_prime_lists?(
      expected, actual)
    i = 0
    while i < actual.size
      return false if actual[i].norm > @factor_base.bound
      i += 1

    combined = []
    actual.each -> (prime)
      combined.push(prime)
    s_primes.each -> (prime)
      found = false
      combined.each -> (existing)
        found = true if existing.eql?(prime)
      combined.push(prime) if !found
    @factor_base.same_prime_lists?(
      combined, @factor_base.primes)

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldMinkowskiFactorBaseCertificate(bound "
    text + @factor_base.bound.to_s + ")"

  -> inspect
    to_s


+ NumberFieldMinkowskiFactorBase
  -> new(@field, s_primes = nil,
         @rational_prime_limit = 100_000,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000)
    if @field.class_name != "NumberField"
      raise "Minkowski factor base needs a NumberField"
    @s_primes = []
    if s_primes != nil
      if s_primes.class_name != "Array"
        raise "Minkowski S-primes must be an Array"
      s_primes.each -> (prime)
        @s_primes.push(prime)
    @bound = compute_bound
    if @bound > @rational_prime_limit
      raise "Minkowski factor-base prime limit exceeded; class-group proof unknown"
    @minkowski_prime_slices = []
    @minkowski_primes = enumerate_minkowski_primes
    @primes = []
    @minkowski_primes.each -> (prime)
      @primes.push(prime)
    @s_primes.each -> (prime)
      found = false
      @primes.each -> (existing)
        found = true if existing.eql?(prime)
      @primes.push(prime) if !found
    @certificate_cache = NumberFieldMinkowskiFactorBaseCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "Minkowski factor base failed certification"

  ro :field, :rational_prime_limit, :factor_search_limit, :generator_search_limit

  -> compute_bound
    degree = @field.degree
    complex_pairs = @field.signature[1]
    discriminant = @field.field_discriminant.abs
    square_root = discriminant.isqrt
    square_root += 1 if square_root * square_root < discriminant
    numerator = (4 ** complex_pairs) * degree.factorial
    numerator *= square_root
    denominator = (3 ** complex_pairs) * (degree ** degree)
    quotient = numerator / denominator
    quotient += 1 if numerator % denominator != 0
    quotient < 1 ? 1 : quotient

  ro :bound

  -> enumerate_minkowski_primes
    if @minkowski_primes != nil
      return minkowski_primes
    out = []
    rational_prime = 2
    while rational_prime <= @bound
      if rational_prime.prime?
        index = @field.maximal_order_index
        use_linear_slice = rational_prime * rational_prime > @bound
        use_linear_slice = false if index % rational_prime == 0
        if use_linear_slice
          slice = NumberFieldMinkowskiLinearPrimeSlice.new(
            @field, rational_prime, @bound)
        else
          slice = @field.prime_decomposition(
            rational_prime, @factor_search_limit,
            @generator_search_limit)
        @minkowski_prime_slices.push(slice)
        slice.prime_ideals.each -> (prime)
          out.push(prime) if prime.norm <= @bound
      rational_prime += 1
    out

  -> same_prime_lists?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !left[i].eql?(right[i])
      i += 1
    true

  -> minkowski_primes
    out = []
    @minkowski_primes.each -> (prime)
      out.push(prime)
    out

  -> minkowski_prime_slices
    out = []
    @minkowski_prime_slices.each -> (slice)
      out.push(slice)
    out

  -> minkowski_decompositions
    minkowski_prime_slices

  -> s_primes
    out = []
    @s_primes.each -> (prime)
      out.push(prime)
    out

  -> primes
    out = []
    @primes.each -> (prime)
      out.push(prime)
    out

  -> size
    @primes.size

  -> index_of(prime_ideal)
    i = 0
    while i < @primes.size
      return i if @primes[i].eql?(prime_ideal)
      i += 1
    nil

  -> include?(prime_ideal)
    index_of(prime_ideal) != nil

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "MinkowskiFactorBase(" + @field.to_s
    text + ", bound " + @bound.to_s
    text + ", primes " + size.to_s + ")"

  -> inspect
    to_s


+ NumberFieldPrincipalClassRelation
  -> new(@factor_base, value)
    expected_class = "NumberFieldMinkowskiFactorBase"
    if @factor_base.class_name != expected_class
      raise "principal class relation needs a Minkowski factor base"
    @element = @factor_base.field.coerce(value)
    if @element.zero?
      raise "zero has no principal ideal-class relation"
    @vector = compute_vector
    @verified_cache = @vector != nil
    if !@verified_cache
      raise "principal ideal is not supported on the displayed factor base"

  ro :factor_base

  -> field
    @factor_base.field

  ro :element

  -> fractional_ideal
    field.principal_fractional_ideal(@element)

  -> compute_vector
    coordinates = field.maximal_order_coordinates(
      @element)
    if coordinates != nil
      return compute_integral_vector(coordinates)
    fractional = fractional_ideal
    return nil if !fractional.certificate.verified?
    compute_vector_from_fractional_ideal(
      fractional)

  # For algebraic integers, certify the relation directly from exact
  # P-adic valuations.  The norm identity
  #
  #   ord_p |Norm(a)| = sum(P above p) f(P/p) ord_P(a)
  #
  # proves that no omitted prime above p divides (a).  This avoids building,
  # factoring, and retaining a generic principal ideal for every relation.
  # Non-integral elements continue through the general fractional-ideal
  # certificate below.
  -> compute_integral_vector(coordinates)
    order = field.certify_maximal_order
    order_element = order.element(coordinates)
    norm = order.norm_from_coordinates(coordinates)
    return nil if norm == 0
    remaining = norm.abs
    primes = @factor_base.primes
    vector = []
    primes.size.times -> vector.push(0)
    handled_rational_primes = []
    prime_index = 0
    while prime_index < primes.size
      rational_prime = primes[prime_index].rational_prime
      if !handled_rational_primes.include?(rational_prime)
        handled_rational_primes.push(rational_prime)
        rational_exponent = 0
        while remaining % rational_prime == 0
          remaining = remaining / rational_prime
          rational_exponent += 1
        if rational_exponent > 0
          accounted_exponent = 0
          local_index = 0
          while local_index < primes.size
            prime = primes[local_index]
            if prime.rational_prime == rational_prime
              valuation = prime.algebra_prime_ideal.valuation(
                order_element, rational_exponent)
              vector[local_index] = valuation.abs % 2
              accounted_exponent += prime.residue_degree * valuation
            local_index += 1
          return nil if accounted_exponent != rational_exponent
      prime_index += 1
    return nil if remaining != 1
    vector

  -> compute_vector_from_fractional_ideal(fractional_ideal)
    vector = []
    @factor_base.size.times -> vector.push(0)
    algebra_ideal = fractional_ideal.algebra_fractional_ideal
    factors = algebra_ideal.factors
    factor_index = 0
    while factor_index < factors.size
      factor = factors[factor_index]
      number_field_prime = NumberFieldPrimeIdeal.new(
        field, factor[0])
      index = @factor_base.index_of(number_field_prime)
      return nil if index == nil
      vector[index] = factor[1].abs % 2
      factor_index += 1
    vector

  -> vector
    return nil if @vector == nil
    F2LinearAlgebra.copy_vector(@vector)

  -> verified?
    return false if !@factor_base.certificate.verified?
    @verified_cache

  -> certified?
    verified?

  -> to_s
    "PrincipalClassRelation(" + @element.to_s + ")"

  -> inspect
    to_s


