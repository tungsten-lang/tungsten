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

  -> search
    @search

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

  -> coefficient_bound
    @coefficient_bound

  -> element_limit
    @element_limit

  -> odd_power_limit
    @odd_power_limit

  -> reduction_producer
    @reduction_producer

  -> ideal_attempt_limit
    @ideal_attempt_limit

  -> total_element_limit
    @total_element_limit

  -> prime_start_index
    @prime_start_index

  -> prime_count
    @prime_count

  -> relation_anchor_index
    @relation_anchor_index

  -> minimum_odd_power
    @minimum_odd_power

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

  -> ideal
    @ideal

  -> field
    @field

  -> generator
    @generator

  -> found?
    @generator != nil

  -> tested_elements
    @tested_elements

  -> reduction_producer
    @reduction_producer

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

  -> slice
    @slice

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

  -> field
    @field

  -> prime
    @prime

  -> bound
    @bound

  -> reduced_polynomial
    @reduced_polynomial

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

  -> factor_base
    @factor_base

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

  -> field
    @field

  -> rational_prime_limit
    @rational_prime_limit

  -> factor_search_limit
    @factor_search_limit

  -> generator_search_limit
    @generator_search_limit

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

  -> bound
    @bound

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

  -> factor_base
    @factor_base

  -> field
    @factor_base.field

  -> element
    @element

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


+ NumberFieldSClassTwoTorsionCertificate
  -> new(@proof)
    @verified_cache = nil

  -> proof
    @proof

  -> theorem
    "Minkowski generation plus an odd relation-lattice quotient"

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
    expected_class = "NumberFieldSClassTwoTorsionProof"
    return false if @proof.class_name != expected_class
    factor_base = @proof.factor_base
    return false if !factor_base.certificate.verified?
    relations = @proof.principal_relations
    relation_rows = []
    i = 0
    while i < relations.size
      relation = relations[i]
      relation_class = "NumberFieldPrincipalClassRelation"
      return false if relation.class_name != relation_class
      return false if relation.factor_base != factor_base
      return false if !relation.verified?
      relation_rows.push(relation.vector)
      i += 1

    expected_rows = @proof.s_prime_rows
    relation_rows.each -> (row)
      expected_rows.push(row)
    return false if !F2LinearAlgebra.same_matrix?(
      expected_rows, @proof.relation_matrix)
    rank_certificate = @proof.rank_certificate
    return false if !rank_certificate.verified?
    return false if rank_certificate.width != factor_base.size
    rank_certificate.rank == factor_base.size

  -> certified?
    verified?

  -> proves_two_torsion_trivial?
    verified?

  -> to_s
    text = "NumberFieldSClassTwoTorsionCertificate(rank "
    text + @proof.rank_certificate.rank.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSClassTwoTorsionProof
  -> new(@factor_base, relation_evidence)
    expected_class = "NumberFieldMinkowskiFactorBase"
    if @factor_base.class_name != expected_class
      raise "S-class proof needs a Minkowski factor base"
    if relation_evidence.class_name != "Array"
      raise "S-class principal relations must be an Array"
    @principal_relations = []
    relation_evidence.each -> (evidence)
      if evidence.class_name == "NumberFieldPrincipalClassRelation"
        if evidence.factor_base != @factor_base || !evidence.verified?
          raise "S-class relation certificate has the wrong factor base"
        @principal_relations.push(evidence)
      else
        @principal_relations.push(
          NumberFieldPrincipalClassRelation.new(
            @factor_base, evidence))
    @relation_matrix = s_prime_rows
    @principal_relations.each -> (relation)
      @relation_matrix.push(relation.vector)
    @rank_certificate = compute_rank_certificate
    @certificate_cache = NumberFieldSClassTwoTorsionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "relations do not certify trivial S-class-group 2-torsion"

  -> field
    @factor_base.field

  -> factor_base
    @factor_base

  -> s_primes
    @factor_base.s_primes

  -> principal_relations
    out = []
    @principal_relations.each -> (relation)
      out.push(relation)
    out

  -> relation_elements
    out = []
    @principal_relations.each -> (relation)
      out.push(relation.element)
    out

  -> s_prime_rows
    rows = []
    @factor_base.s_primes.each -> (prime)
      index = @factor_base.index_of(prime)
      if index == nil
        raise "S-prime is absent from its factor base"
      row = []
      @factor_base.size.times -> row.push(0)
      row[index] = 1
      rows.push(row)
    rows

  -> relation_matrix
    F2LinearAlgebra.copy_matrix(@relation_matrix)

  -> compute_rank_certificate
    system = F2LinearSystem.new(@factor_base.size)
    @relation_matrix.each -> (row)
      system.add_equation(row)
    system.certificate

  -> rank_certificate
    @rank_certificate

  -> two_torsion_trivial?
    certificate.verified?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "SClassTwoTorsionProof(" + field.to_s
    text + ", factor base " + @factor_base.size.to_s + ")"

  -> inspect
    to_s


+ NumberFieldIsomorphicSClassTwoTorsionCertificate
  -> new(@proof)
    @verified_cache = nil

  -> proof
    @proof

  -> theorem
    "field isomorphisms preserve localized ideal class groups"

  -> theorem_reference
    "functoriality of Cl(O_K,S) under Q-algebra isomorphism"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> same_prime_sets?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      found = false
      j = 0
      while j < right.size
        found = true if left[i].eql?(right[j])
        j += 1
      return false if !found
      i += 1
    true

  -> primes_above(field, rational_primes)
    out = []
    rational_primes.each -> (rational_prime)
      field.prime_ideals_above(
        rational_prime).each -> (prime)
        out.push(prime)
    out

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
    expected = "NumberFieldIsomorphicSClassTwoTorsionProof"
    return false if @proof.class_name != expected
    source = @proof.source_field
    model = @proof.model_field
    return false if source.class_name != "NumberField"
    return false if model.class_name != "NumberField"
    isomorphism = source.irreducibility_certificate
    expected_certificate = "NumberFieldIsomorphicModelIrreducibilityCertificate"
    return false if isomorphism.class_name != expected_certificate
    return false if !isomorphism.verified?
    return false if isomorphism.model_field != model

    rational_primes = @proof.rational_primes
    i = 0
    while i < rational_primes.size
      prime = rational_primes[i]
      return false if !prime.prime?
      j = 0
      while j < i
        return false if rational_primes[j] == prime
        j += 1
      i += 1

    model_proof = @proof.model_proof
    expected_proof = "NumberFieldSClassTwoTorsionProof"
    return false if model_proof.class_name != expected_proof
    return false if model_proof.field != model
    return false if !model_proof.certificate.verified?
    expected_model_primes = primes_above(
      model, rational_primes)
    return false if !same_prime_sets?(
      expected_model_primes, model_proof.s_primes)

    expected_source_primes = primes_above(
      source, rational_primes)
    same_prime_sets?(
      expected_source_primes, @proof.s_primes)

  -> certified?
    verified?

  -> proves_two_torsion_trivial?
    verified?

  -> to_s
    "NumberFieldIsomorphicSClassTwoTorsionCertificate"

  -> inspect
    to_s


+ NumberFieldIsomorphicSClassTwoTorsionProof
  -> new(@source_field, rational_primes,
         @model_proof)
    if @source_field.class_name != "NumberField"
      raise "isomorphic S-class proof needs a source number field"
    if rational_primes.class_name != "Array"
      raise "isomorphic S-class rational primes must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    certificate = @source_field.irreducibility_certificate
    expected = "NumberFieldIsomorphicModelIrreducibilityCertificate"
    if certificate.class_name != expected
      raise "source field has no certified isomorphic model"
    @model_field = certificate.model_field
    @s_primes = []
    @rational_primes.each -> (rational_prime)
      @source_field.prime_ideals_above(
        rational_prime).each -> (prime)
        @s_primes.push(prime)
    @certificate_cache = NumberFieldIsomorphicSClassTwoTorsionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "isomorphic S-class 2-torsion transfer failed certification"

  -> source_field
    @source_field

  -> field
    @source_field

  -> model_field
    @model_field

  -> model_proof
    @model_proof

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> s_primes
    out = []
    @s_primes.each -> (prime)
      out.push(prime)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> two_torsion_trivial?
    certified?

  -> to_s
    text = "IsomorphicSClassTwoTorsionProof("
    text + @source_field.to_s + " via "
    text + @model_field.to_s + ")"

  -> inspect
    to_s


# The exact sequence
#
#   O_{K,S}^*/O_{K,S}^{*2} -> L(2,S) -> Cl(O_K,S)[2]
#
# identifies the finite-support square classes L(2,S) with the S-unit square
# classes when the localized class group has no 2-torsion.  Unlike ordinary
# NumberFieldSUnitCoordinates, the representative below may have nonzero
# valuations outside S, but every such valuation must be even.  Auxiliary
# quadratic characters are selected away from the representative's support,
# and all ideal, sign, residue, and F2 calculations are replayed exactly.
+ NumberFieldL2SCoordinatesCertificate
  -> new(@coordinates)
    @verified_cache = nil

  -> theorem
    "the S-class exact sequence identifies L(2,S) with S-unit square classes when Cl(O_K,S)[2] is trivial"

  -> theorem_reference
    "Bruin-Poonen-Stoll section 12.6.4"

  -> proof_kind
    :trusted_s_class_exact_sequence_with_exact_coordinate_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> same_prime_sets?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      found = false
      j = 0
      while j < right.size
        found = true if left[i].eql?(right[j])
        j += 1
      return false if !found
      i += 1
    true

  -> verify!
    expected = "NumberFieldL2SCoordinates"
    return false if @coordinates.class_name != expected
    basis = @coordinates.basis
    return false if basis.class_name != "NumberFieldSUnitSquareClassBasis"
    return false if !basis.certificate.verified?
    proof = @coordinates.s_class_two_torsion_proof
    return false if proof.class_name != "NumberFieldSClassTwoTorsionProof"
    return false if !proof.certificate.verified?
    return false if proof.field != basis.field
    return false if !same_prime_sets?(
      proof.s_primes, basis.s_primes)

    value = @coordinates.value
    return false if value.zero? || value.field != basis.field
    computation = @coordinates.principal_computation
    return false if !computation.certificate.verified?
    return false if !computation.order.same_order?(
      basis.field.certify_maximal_order)
    return false if computation.value != basis.field.generic_algebra_element(
      value)
    ideal = @coordinates.fractional_ideal
    return false if !computation.ideal.eql?(
      ideal.algebra_fractional_ideal)
    return false if !ideal.certificate.verified?
    return false if !@coordinates.outside_s_valuations_even?

    coordinate_basis = @coordinates.coordinate_basis
    return false if coordinate_basis.class_name != (
      "NumberFieldSUnitSquareClassBasis")
    return false if !coordinate_basis.certificate.verified?
    return false if coordinate_basis.field != basis.field
    return false if coordinate_basis.generators.to_s != (
      basis.generators.to_s)
    return false if !same_prime_sets?(
      coordinate_basis.s_primes, basis.s_primes)
    target = coordinate_basis.signature_vector_with_ideal(
      value, ideal)
    system = F2LinearSystem.new(coordinate_basis.dimension)
    matrix = coordinate_basis.local_matrix
    index = 0
    while index < matrix.size
      system.add_equation(matrix[index], target[index])
      index += 1
    solution = system.solve
    return false if solution.inconsistent?
    F2LinearAlgebra.same_vector?(
      solution.particular_solution,
      @coordinates.vector)

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> certified?
    verified?


+ NumberFieldL2SCoordinates
  -> new(@basis, @s_class_two_torsion_proof, value,
         auxiliary_prime_limit = 1_000)
    if @basis.class_name != "NumberFieldSUnitSquareClassBasis"
      raise "L(2,S) coordinates need an ordinary certified S-unit basis"
    if !@basis.certificate.verified?
      raise "L(2,S) coordinate basis is uncertified"
    expected_proof = "NumberFieldSClassTwoTorsionProof"
    if @s_class_two_torsion_proof.class_name != expected_proof
      raise "L(2,S) coordinates need an ordinary S-class proof"
    if !@s_class_two_torsion_proof.certificate.verified?
      raise "L(2,S) S-class proof is uncertified"
    if @s_class_two_torsion_proof.field != @basis.field
      raise "L(2,S) basis and S-class proof change fields"
    if !same_prime_sets?(
         @s_class_two_torsion_proof.s_primes,
         @basis.s_primes)
      raise "L(2,S) basis and S-class proof change S"
    @value = @basis.field.coerce(value)
    raise "zero has no multiplicative L(2,S) coordinates" if @value.zero?
    algebra_value = @basis.field.generic_algebra_element(
      @value)
    order = @basis.field.certify_maximal_order
    @principal_computation = order.principal_fractional_ideal_with_certificate(
      algebra_value)
    @fractional_ideal = NumberFieldFractionalIdeal.new(
      @basis.field, @principal_computation.ideal)
    if !outside_s_valuations_even?
      raise "number-field element has odd valuation outside S"

    @coordinate_basis = @basis
    begin
      @coordinate_basis.signature_vector_with_ideal(
        @value, @fractional_ideal)
    rescue error
      search = NumberFieldSUnitSquareClassBasisSearch.new(
        @basis.field, @basis.s_primes,
        @basis.generators, auxiliary_prime_limit,
        250_000, 250_000,
        @basis.archimedean_data, [@value])
      @coordinate_basis = search.basis
    target = @coordinate_basis.signature_vector_with_ideal(
      @value, @fractional_ideal)
    system = F2LinearSystem.new(@coordinate_basis.dimension)
    matrix = @coordinate_basis.local_matrix
    index = 0
    while index < matrix.size
      system.add_equation(matrix[index], target[index])
      index += 1
    solution = system.solve
    if solution.inconsistent?
      raise "L(2,S) signature is outside the certified square-class basis"
    @vector = solution.particular_solution
    @certificate_cache = NumberFieldL2SCoordinatesCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "L(2,S) coordinates failed certification"

  -> same_prime_sets?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      found = false
      j = 0
      while j < right.size
        found = true if left[i].eql?(right[j])
        j += 1
      return false if !found
      i += 1
    true

  -> s_prime_factor?(algebra_prime)
    index = 0
    while index < @basis.s_primes.size
      prime = @basis.s_primes[index]
      return true if prime.algebra_prime_ideal.eql?(algebra_prime)
      index += 1
    false

  -> outside_s_valuations_even?
    factors = @fractional_ideal.algebra_fractional_ideal.factors
    index = 0
    while index < factors.size
      factor = factors[index]
      if !s_prime_factor?(factor[0]) && factor[1].abs.odd?
        return false
      index += 1
    true

  -> basis
    @basis

  -> field
    @basis.field

  -> s_class_two_torsion_proof
    @s_class_two_torsion_proof

  -> value
    @value

  -> principal_computation
    @principal_computation

  -> fractional_ideal
    @fractional_ideal

  -> coordinate_basis
    @coordinate_basis

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> coordinates
    vector

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldIsomorphicL2SCoordinatesCertificate
  -> new(@coordinates)
    @verified_cache = nil

  -> theorem
    "field isomorphisms preserve L(2,S), localized class groups, and square-class coordinates"

  -> theorem_reference
    "functoriality of localized square classes under Q-algebra isomorphism"

  -> proof_kind
    :trusted_isomorphic_l2s_coordinate_transfer

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> verify!
    expected = "NumberFieldIsomorphicL2SCoordinates"
    return false if @coordinates.class_name != expected
    basis = @coordinates.basis
    expected_basis = "NumberFieldIsomorphicSUnitSquareClassBasis"
    return false if basis.class_name != expected_basis
    return false if !basis.certificate.verified?
    proof = @coordinates.s_class_two_torsion_proof
    expected_proof = "NumberFieldIsomorphicSClassTwoTorsionProof"
    return false if proof.class_name != expected_proof
    return false if !proof.certificate.verified?
    return false if proof.source_field != basis.source_field
    return false if proof.model_field != basis.model_field
    value = @coordinates.value
    return false if value.zero? || value.field != basis.field
    inner = @coordinates.model_coordinates
    return false if inner.class_name != "NumberFieldL2SCoordinates"
    return false if !inner.certificate.verified?
    return false if inner.basis != basis.model_basis
    return false if inner.s_class_two_torsion_proof != proof.model_proof
    return false if inner.value != basis.source_to_model(value)
    F2LinearAlgebra.same_vector?(
      inner.vector, @coordinates.vector)

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> certified?
    verified?


+ NumberFieldIsomorphicL2SCoordinates
  -> new(@basis, @s_class_two_torsion_proof, value,
         auxiliary_prime_limit = 1_000)
    expected_basis = "NumberFieldIsomorphicSUnitSquareClassBasis"
    if @basis.class_name != expected_basis
      raise "isomorphic L(2,S) coordinates need a transferred basis"
    if !@basis.certificate.verified?
      raise "isomorphic L(2,S) basis is uncertified"
    expected_proof = "NumberFieldIsomorphicSClassTwoTorsionProof"
    if @s_class_two_torsion_proof.class_name != expected_proof
      raise "isomorphic L(2,S) coordinates need a transferred S-class proof"
    if !@s_class_two_torsion_proof.certificate.verified?
      raise "isomorphic L(2,S) S-class proof is uncertified"
    if @s_class_two_torsion_proof.source_field != @basis.source_field
      raise "isomorphic L(2,S) basis and proof change source fields"
    if @s_class_two_torsion_proof.model_field != @basis.model_field
      raise "isomorphic L(2,S) basis and proof change model fields"
    @value = @basis.field.coerce(value)
    model_value = @basis.source_to_model(@value)
    @model_coordinates = NumberFieldL2SCoordinates.new(
      @basis.model_basis,
      @s_class_two_torsion_proof.model_proof,
      model_value, auxiliary_prime_limit)
    @vector = @model_coordinates.vector
    @certificate_cache = NumberFieldIsomorphicL2SCoordinatesCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "isomorphic L(2,S) coordinates failed certification"

  -> basis
    @basis

  -> field
    @basis.field

  -> s_class_two_torsion_proof
    @s_class_two_torsion_proof

  -> value
    @value

  -> model_coordinates
    @model_coordinates

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> coordinates
    vector

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldSUnitSquareClassBasis
  -> l2s_coordinates_with_certificate(
       value, s_class_two_torsion_proof,
       auxiliary_prime_limit = 1_000)
    NumberFieldL2SCoordinates.new(
      self, s_class_two_torsion_proof,
      value, auxiliary_prime_limit)


+ NumberFieldIsomorphicSUnitSquareClassBasis
  -> l2s_coordinates_with_certificate(
       value, s_class_two_torsion_proof,
       auxiliary_prime_limit = 1_000)
    NumberFieldIsomorphicL2SCoordinates.new(
      self, s_class_two_torsion_proof,
      value, auxiliary_prime_limit)


+ NumberFieldSClassTwoTorsionSearch
  -> new(@field, s_primes = nil,
         @coefficient_bound = 4,
         @element_limit = 100_000,
         rational_prime_limit = 100_000,
         factor_search_limit = 250_000,
         generator_search_limit = 250_000,
         ideal_generator_bounds = nil,
         initial_relation_elements = nil,
         @require_complete = true)
    if @field.class_name != "NumberField"
      raise "S-class relation search needs a NumberField"
    if @coefficient_bound < 0 || @element_limit < 1
      raise "S-class relation search bounds must be positive"
    if ideal_generator_bounds == nil
      ideal_generator_bounds = NumberFieldIdealGeneratorBounds.new
    if ideal_generator_bounds.class_name != "NumberFieldIdealGeneratorBounds"
      raise "S-class ideal-generator bounds have the wrong type"
    @ideal_generator_coefficient_bound = ideal_generator_bounds.coefficient_bound
    @ideal_generator_element_limit = ideal_generator_bounds.element_limit
    @ideal_generator_odd_power_limit = ideal_generator_bounds.odd_power_limit
    @ideal_generator_reduction_producer = ideal_generator_bounds.reduction_producer
    @ideal_generator_attempt_limit = ideal_generator_bounds.ideal_attempt_limit
    @ideal_generator_total_element_limit = ideal_generator_bounds.total_element_limit
    @ideal_generator_prime_start = ideal_generator_bounds.prime_start_index
    @ideal_generator_prime_count = ideal_generator_bounds.prime_count
    @ideal_generator_minimum_odd_power = ideal_generator_bounds.minimum_odd_power
    @ideal_generator_use_anchored_relations = ideal_generator_bounds.use_anchored_relations?
    @factor_base = NumberFieldMinkowskiFactorBase.new(
      @field, s_primes, rational_prime_limit,
      factor_search_limit, generator_search_limit)
    @relation_elements = []
    @relation_vectors = []
    @principal_relations = []
    @tested_elements = 0
    @tested_ideal_elements = 0
    @tested_ideals = 0
    @attempted_factor_base_indices = []
    @resolved_factor_base_indices = []
    @principal_relation_anchor_index = ideal_generator_bounds.relation_anchor_index
    if @principal_relation_anchor_index != nil
      if @principal_relation_anchor_index >= @factor_base.size
        raise "principal relation anchor is outside the factor base"
    @allowed_rational_primes = []
    @factor_base_prime_groups = []
    @factor_base_index_groups = []
    prime_index = 0
    @factor_base.primes.each -> (prime)
      rational_prime = prime.rational_prime
      group_index = rational_prime_group_index(
        rational_prime)
      if group_index == nil
        @allowed_rational_primes.push(rational_prime)
        @factor_base_prime_groups.push([])
        @factor_base_index_groups.push([])
        group_index = @allowed_rational_primes.size - 1
      @factor_base_prime_groups[group_index].push(prime)
      @factor_base_index_groups[group_index].push(prime_index)
      prime_index += 1
    initialize_rank_tracker
    seed_initial_relations(initial_relation_elements)
    seed_rational_relations if @rank < @factor_base.size
    search if @rank < @factor_base.size
    seed_principal_factor_base_generators if @rank < @factor_base.size
    @proof = nil
    if @rank == @factor_base.size
      @proof = NumberFieldSClassTwoTorsionProof.new(
        @factor_base, @principal_relations)
    elsif @require_complete
      message = "S-class relation search limit exceeded; rank "
      message += @rank.to_s + " of " + @factor_base.size.to_s
      message += " after " + @tested_elements.to_s + " order elements and "
      message += @tested_ideal_elements.to_s + " ideal elements in "
      message += @tested_ideals.to_s + " ideal searches; "
      raise message + "2-torsion remains unknown"

  -> field
    @field

  -> factor_base
    @factor_base

  -> relation_elements
    out = []
    @relation_elements.each -> (element)
      out.push(element)
    out

  -> relation_vectors
    F2LinearAlgebra.copy_matrix(
      @relation_vectors)

  -> relation_coordinate_witnesses
    out = []
    @relation_elements.each -> (element)
      coefficients = []
      element.coefficients.each -> (coefficient)
        coefficients.push(coefficient)
      out.push(coefficients)
    out

  -> rank
    @rank

  -> complete?
    @proof != nil

  -> require_complete?
    @require_complete

  -> tested_elements
    @tested_elements

  -> tested_ideal_elements
    @tested_ideal_elements

  -> tested_ideals
    @tested_ideals

  -> attempted_factor_base_indices
    out = []
    @attempted_factor_base_indices.each -> (index)
      out.push(index)
    out

  -> resolved_factor_base_indices
    out = []
    @resolved_factor_base_indices.each -> (index)
      out.push(index)
    out

  -> principal_relation_anchor_index
    @principal_relation_anchor_index

  -> unresolved_factor_base_indices
    out = []
    @attempted_factor_base_indices.each -> (index)
      out.push(index) if !@resolved_factor_base_indices.include?(index)
    out

  -> s_prime_rows
    rows = []
    @factor_base.s_primes.each -> (prime)
      row = []
      @factor_base.size.times -> row.push(0)
      row[@factor_base.index_of(prime)] = 1
      rows.push(row)
    rows

  -> current_rows
    rows = s_prime_rows
    @relation_vectors.each -> (vector)
      rows.push(F2LinearAlgebra.copy_vector(vector))
    rows

  -> matrix_rank(rows)
    system = F2LinearSystem.new(@factor_base.size)
    rows.each -> (row)
      system.add_equation(row)
    system.rank

  -> initialize_rank_tracker
    @pivot_rows = []
    @factor_base.size.times -> @pivot_rows.push(nil)
    @rank = 0
    rows = s_prime_rows
    i = 0
    while i < rows.size
      add_rank_row(rows[i])
      i += 1

  -> seed_initial_relations(elements)
    return nil if elements == nil
    if elements.class_name != "Array"
      raise "initial S-class relations must be an Array"
    i = 0
    while i < elements.size
      element = @field.coerce(elements[i])
      evidence = NumberFieldPrincipalClassRelation.new(
        @factor_base, element)
      add_relation_if_independent(
        element, evidence.vector, evidence)
      i += 1
    nil

  -> reduced_rank_row(vector)
    F2LinearAlgebra.validate_vector(
      vector, @factor_base.size)
    work = F2LinearAlgebra.copy_vector(vector)
    pivot = 0
    while pivot < @factor_base.size
      if work[pivot] == 1 && @pivot_rows[pivot] != nil
        column = pivot
        while column < @factor_base.size
          work[column] = work[column] ^ @pivot_rows[pivot][column]
          column += 1
      pivot += 1
    work

  -> rank_row_independent?(vector)
    work = reduced_rank_row(vector)
    !F2LinearAlgebra.zero_vector?(work)

  -> add_rank_row(vector)
    work = reduced_rank_row(vector)
    pivot = 0
    while pivot < @factor_base.size && work[pivot] == 0
      pivot += 1
    return false if pivot == @factor_base.size
    @pivot_rows[pivot] = work
    @rank += 1
    true

  -> primitive_vector?(vector)
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

  -> integral_element(vector, basis)
    result = @field.zero
    i = 0
    while i < vector.size
      if vector[i] != 0
        result += basis[i] * vector[i]
      i += 1
    result

  -> reduced_order_basis
    out = []
    reduced = @field.certify_maximal_order.approximate_frobenius_basis
    reduced.each -> (generic)
      out.push(@field.generic_order_vector_to_element(
        generic.coefficients))
    out

  -> reduced_order_coordinate_basis
    @field.certify_maximal_order.approximate_frobenius_coordinate_basis

  -> order_coordinates(vector, basis)
    coordinates = []
    coordinate = 0
    while coordinate < @field.degree
      value = 0 ## big
      basis_index = 0
      while basis_index < vector.size
        value += vector[basis_index] * basis[basis_index][coordinate]
        basis_index += 1
      coordinates.push(value)
      coordinate += 1
    coordinates

  -> element_from_order_coordinates(coordinates)
    generic = @field.certify_maximal_order.element(
      coordinates)
    @field.generic_order_vector_to_element(
      generic.coefficients)

  -> integer_norm_support_within_factor_base?(norm)
    return false if norm == 0
    remaining = norm.abs
    i = 0
    while i < @allowed_rational_primes.size
      rational_prime = @allowed_rational_primes[i]
      while remaining % rational_prime == 0
        remaining = remaining / rational_prime
      i += 1
    remaining == 1

  -> rational_prime_group_index(rational_prime)
    i = 0
    while i < @allowed_rational_primes.size
      return i if @allowed_rational_primes[i] == rational_prime
      i += 1
    nil

  # The factorization of the rational element p has valuation e(P/p) at
  # every P above p.  The residue-degree identity detects whether this factor
  # base contains all of those primes without constructing any ideal powers.
  -> rational_prime_relation(rational_prime)
    group_index = rational_prime_group_index(
      rational_prime)
    return nil if group_index == nil
    primes = @factor_base_prime_groups[group_index]
    indices = @factor_base_index_groups[group_index]
    accounted_degree = 0
    vector = []
    @factor_base.size.times -> vector.push(0)
    i = 0
    while i < primes.size
      prime = primes[i]
      ramification = prime.ramification_index
      accounted_degree += ramification * prime.residue_degree
      vector[indices[i]] = ramification % 2
      i += 1
    return nil if accounted_degree != @field.degree
    vector

  # Compute a candidate relation directly against the already-certified
  # factor-base primes.  Search candidates are producer calculations; every
  # independent row is promoted to a NumberFieldPrincipalClassRelation,
  # which replays the exact valuation calculation before the row enters the
  # proof.
  #
  # The exponent of p in |Norm(element)| must equal
  #
  #   sum over P above p of f(P/p) * v_P(element).
  #
  # Requiring equality detects a prime divisor above p that is absent from
  # the displayed factor base.
  -> integral_factor_base_relation(order_element, norm)
    return nil if norm == 0
    remaining = norm.abs
    vector = []
    @factor_base.size.times -> vector.push(0)
    group_index = 0
    while group_index < @allowed_rational_primes.size
      rational_prime = @allowed_rational_primes[group_index]
      rational_exponent = 0
      while remaining % rational_prime == 0
        remaining = remaining / rational_prime
        rational_exponent += 1
      if rational_exponent > 0
        accounted_exponent = 0
        primes = @factor_base_prime_groups[group_index]
        indices = @factor_base_index_groups[group_index]
        local_index = 0
        while local_index < primes.size
          prime = primes[local_index]
          valuation = prime.algebra_prime_ideal.valuation(
            order_element, rational_exponent)
          if valuation > 0
            vector[indices[local_index]] = valuation.abs % 2
            accounted_exponent += prime.residue_degree * valuation
          local_index += 1
        return nil if accounted_exponent != rational_exponent
      group_index += 1
    return nil if remaining != 1
    vector

  # A principal ideal supported on the factor base can only have rational norm
  # primes represented by that base.  Strip those primes before asking the
  # ideal layer for residue-algebra decompositions; this cheaply rejects small
  # elements whose norms contain very large irrelevant prime factors.
  -> norm_support_within_factor_base?(element)
    norm = element.norm
    return false if norm == 0
    parts = [norm.numerator.abs, norm.denominator]
    part_index = 0
    while part_index < parts.size
      remaining = parts[part_index]
      allowed_index = 0
      while allowed_index < @allowed_rational_primes.size
        rational_prime = @allowed_rational_primes[allowed_index]
        while remaining % rational_prime == 0
          remaining = remaining / rational_prime
        allowed_index += 1
      return false if remaining != 1
      part_index += 1
    true

  -> candidate_relation(element)
    return nil if !norm_support_within_factor_base?(element)
    relation_from_supported_element(element)

  -> relation_from_supported_element(element)
    coordinates = @field.maximal_order_coordinates(element)
    if coordinates != nil
      order = @field.certify_maximal_order
      order_element = order.element(coordinates)
      norm = order.norm_from_coordinates(coordinates)
      return integral_factor_base_relation(
        order_element, norm)
    ideal = @field.principal_fractional_ideal(element)
    factors = ideal.algebra_fractional_ideal.factors
    vector = []
    @factor_base.size.times -> vector.push(0)
    i = 0
    while i < factors.size
      factor = factors[i]
      prime = NumberFieldPrimeIdeal.new(@field, factor[0])
      index = @factor_base.index_of(prime)
      return nil if index == nil
      vector[index] = factor[1].abs % 2
      i += 1
    vector

  -> candidate_relation_from_order_coordinates(coordinates)
    order = @field.certify_maximal_order
    norm = order.norm_from_coordinates(coordinates)
    return nil if !integer_norm_support_within_factor_base?(
      norm)
    order_element = order.element(coordinates)
    relation = integral_factor_base_relation(
      order_element, norm)
    return nil if relation == nil
    element = element_from_order_coordinates(
      coordinates)
    [element, relation]

  -> add_relation_if_independent(
       element, relation, evidence = nil)
    if add_rank_row(relation)
      if evidence == nil
        evidence = NumberFieldPrincipalClassRelation.new(
          @factor_base, element)
      if evidence.factor_base != @factor_base
        raise "principal relation evidence changes the factor base"
      if !evidence.verified?
        raise "principal relation evidence is not certified"
      if !F2LinearAlgebra.same_vector?(
           evidence.vector, relation)
        raise "principal relation producer disagrees with its certificate"
      @relation_elements.push(element)
      @relation_vectors.push(evidence.vector)
      @principal_relations.push(evidence)
      return true
    false

  # A principal factor-base ideal contributes a unit-vector relation.  Search
  # in a floating Frobenius-LLL producer basis of that ideal before enumerating
  # arbitrary order elements.  The producer makes no theorem claim; every
  # accepted generator is replayed through the ordinary exact principal-ideal
  # relation certificate.
  -> ideal_search_budget_exhausted?
    return true if @tested_ideals >= @ideal_generator_attempt_limit
    @tested_ideal_elements >= @ideal_generator_total_element_limit

  -> try_principal_ideal_relation(ideal, relation)
    return false if ideal_search_budget_exhausted?
    remaining_limit = @ideal_generator_total_element_limit
    remaining_limit -= @tested_ideal_elements
    element_limit = @ideal_generator_element_limit
    element_limit = remaining_limit if remaining_limit < element_limit
    @tested_ideals += 1
    search = ideal.principal_generator_search(
      @ideal_generator_coefficient_bound,
      element_limit,
      @ideal_generator_reduction_producer)
    @tested_ideal_elements += search.tested_elements
    return false if !search.certified?
    add_relation_if_independent(
      search.generator, relation)
    true

  -> anchored_relation(prime_index, unit)
    return false if @principal_relation_anchor_index == nil
    anchor_index = @principal_relation_anchor_index
    return false if anchor_index == prime_index
    anchor = @factor_base.primes[anchor_index]
    prime = @factor_base.primes[prime_index]

    pair = []
    @factor_base.size.times -> pair.push(0)
    pair[anchor_index] = 1
    pair[prime_index] = 1
    pair_ideal = anchor.as_ideal * prime.as_ideal
    return true if try_principal_ideal_relation(
      pair_ideal, pair)
    return false if ideal_search_budget_exhausted?

    square_ideal = anchor.as_ideal ** 2
    square_ideal = square_ideal * prime.as_ideal
    try_principal_ideal_relation(
      square_ideal, unit)

  -> seed_principal_factor_base_generators
    prime_index = @ideal_generator_prime_start
    stop_index = @factor_base.size
    if @ideal_generator_prime_count != nil
      requested_stop = prime_index + @ideal_generator_prime_count
      stop_index = requested_stop if requested_stop < stop_index
    while prime_index < stop_index
      unit = []
      @factor_base.size.times -> unit.push(0)
      unit[prime_index] = 1
      if rank_row_independent?(unit)
        @attempted_factor_base_indices.push(prime_index)
        prime = @factor_base.primes[prime_index]
        found = false
        if @ideal_generator_use_anchored_relations
          found = anchored_relation(
            prime_index, unit)
        found_by_power = false
        odd_power = @ideal_generator_odd_power_limit
        odd_power -= 1 if odd_power.even?
        while odd_power >= @ideal_generator_minimum_odd_power && !found
          return nil if ideal_search_budget_exhausted?
          ideal = prime.as_ideal ** odd_power
          found_by_power = try_principal_ideal_relation(
            ideal, unit)
          found = found_by_power
          odd_power -= 2
        if found
          @resolved_factor_base_indices.push(prime_index)
          if found_by_power && @principal_relation_anchor_index == nil
            @principal_relation_anchor_index = prime_index
          return true if @rank == @factor_base.size
      prime_index += 1
    nil

  # Rational primes give inexpensive canonical principal relations.  They are
  # not primitive coefficient vectors, so seed them explicitly before the
  # bounded small-element enumeration.
  -> seed_rational_relations
    rational_prime = 2
    while rational_prime <= @factor_base.bound
      if rational_prime.prime?
        @tested_elements += 1
        return nil if @tested_elements > @element_limit
        relation = rational_prime_relation(rational_prime)
        if relation != nil
          element = @field.coerce(rational_prime)
          add_relation_if_independent(element, relation)
          return true if @rank == @factor_base.size
      rational_prime += 1
    nil

  -> search
    basis = reduced_order_coordinate_basis
    height = 1
    while height <= @coefficient_bound
      radix = 2 * height + 1
      code = 0
      total = radix ** basis.size
      while code < total
        vector = []
        remaining = code
        i = 0
        while i < basis.size
          digit = remaining % radix
          vector.push(centered_coefficient(digit))
          remaining = remaining / radix
          i += 1
        selected_vector = vector_height(vector) == height
        selected_vector = false if !primitive_vector?(vector)
        if selected_vector
          @tested_elements += 1
          if @tested_elements > @element_limit
            return nil
          coordinates = order_coordinates(
            vector, basis)
          candidate = candidate_relation_from_order_coordinates(
            coordinates)
          if candidate != nil
            element = candidate[0]
            relation = candidate[1]
            add_relation_if_independent(element, relation)
            return true if @rank == @factor_base.size
        code += 1
      height += 1
    nil

  -> proof
    @proof

  -> result
    @proof

  -> certificate
    if @proof == nil
      raise "incomplete S-class search has no certificate"
    @proof.certificate

  -> certified?
    @proof != nil && @proof.certified?

  -> to_s
    text = "SClassTwoTorsionSearch(rank "
    text += @rank.to_s + "/" + @factor_base.size.to_s
    text + ", tested " + @tested_elements.to_s + ")"

  -> inspect
    to_s


+ EtaleProductSClassTwoTorsionCertificate
  -> new(@proof)
    @verified_cache = nil

  -> proof
    @proof

  -> theorem
    "class groups and S-class groups commute with finite products"

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

  -> same_prime_sets?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      found = false
      j = 0
      while j < right.size
        found = true if left[i].eql?(right[j])
        j += 1
      return false if !found
      i += 1
    true

  -> expected_s_primes(field)
    out = []
    @proof.rational_primes.each -> (rational_prime)
      field.prime_ideals_above(
        rational_prime).each -> (prime)
        out.push(prime)
    out

  -> verify!
    expected_class = "EtaleProductSClassTwoTorsionProof"
    return false if @proof.class_name != expected_class
    order = @proof.order
    return false if order.class_name != "EtaleProductOrder"
    return false if !order.certificate.verified?
    rational_primes = @proof.rational_primes
    i = 0
    while i < rational_primes.size
      return false if !rational_primes[i].prime?
      j = 0
      while j < i
        return false if rational_primes[j] == rational_primes[i]
        j += 1
      i += 1
    component_proofs = @proof.component_proofs
    return false if component_proofs.size != order.component_count
    component_orders = order.component_orders
    component_index = 0
    while component_index < component_proofs.size
      proofs = component_proofs[component_index]
      return false if proofs.class_name != "Array"
      return false if proofs.size == 0
      component_order = component_orders[component_index]
      if component_order.class_name == "MonogenicOrder"
        component_polynomial = component_order.source_polynomial.monic
      else
        component_polynomial = component_order.algebra.defining_polynomial.monic
      product = component_polynomial.ring.one
      i = 0
      while i < proofs.size
        field_proof = proofs[i]
        proof_class = field_proof.class_name
        ordinary = proof_class == "NumberFieldSClassTwoTorsionProof"
        transferred = proof_class == "NumberFieldIsomorphicSClassTwoTorsionProof"
        return false if !ordinary && !transferred
        return false if !field_proof.certificate.verified?
        field = field_proof.field
        polynomial = RationalUnivariatePolynomialTransport.into(
          field.defining_polynomial,
          component_polynomial.ring)
        return false if polynomial == nil
        j = 0
        while j < i
          previous = RationalUnivariatePolynomialTransport.into(
            proofs[j].field.defining_polynomial,
            component_polynomial.ring)
          return false if previous == nil
          return false if polynomial.gcd(previous).degree != 0
          j += 1
        product *= polynomial.monic
        expected_primes = expected_s_primes(field)
        return false if !same_prime_sets?(
          expected_primes, field_proof.s_primes)
        i += 1
      return false if !product.monic.eql?(component_polynomial)
      component_index += 1
    true

  -> certified?
    verified?

  -> proves_two_torsion_trivial?
    verified?

  -> to_s
    text = "EtaleProductSClassTwoTorsionCertificate("
    text + @proof.field_count.to_s + " fields)"

  -> inspect
    to_s


+ EtaleProductSClassTwoTorsionProof
  -> new(@order, rational_primes, component_proofs)
    if @order.class_name != "EtaleProductOrder"
      raise "product S-class proof needs an EtaleProductOrder"
    if rational_primes.class_name != "Array"
      raise "product S-class rational primes must be an Array"
    if component_proofs.class_name != "Array"
      raise "product S-class component proofs must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    @component_proofs = []
    component_proofs.each -> (proofs)
      if proofs.class_name != "Array"
        raise "each etale component needs an Array of field proofs"
      copied = []
      proofs.each -> (proof)
        copied.push(proof)
      @component_proofs.push(copied)
    @certificate_cache = EtaleProductSClassTwoTorsionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "product S-class 2-torsion proof failed certification"

  -> order
    @order

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> component_proofs
    out = []
    @component_proofs.each -> (proofs)
      copied = []
      proofs.each -> (proof)
        copied.push(proof)
      out.push(copied)
    out

  -> field_count
    count = 0
    @component_proofs.each -> (proofs)
      count += proofs.size
    count

  -> certificate
    @certificate_cache

  -> two_torsion_trivial?
    certificate.verified?

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductSClassTwoTorsionProof("
    text + field_count.to_s + " fields)"

  -> inspect
    to_s


+ NumberField
  -> minkowski_factor_base(
       s_primes = nil,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    NumberFieldMinkowskiFactorBase.new(
      self, s_primes, rational_prime_limit,
      factor_search_limit, generator_search_limit)

  -> certify_s_class_two_torsion(
       s_primes = nil,
       coefficient_bound = 4,
       element_limit = 100_000,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000,
       ideal_generator_bounds = nil)
    NumberFieldSClassTwoTorsionSearch.new(
      self, s_primes, coefficient_bound,
      element_limit, rational_prime_limit,
      factor_search_limit,
      generator_search_limit,
      ideal_generator_bounds).proof

  -> search_s_class_two_torsion(
       s_primes = nil,
       coefficient_bound = 4,
       element_limit = 100_000,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000,
       ideal_generator_bounds = nil,
       initial_relation_elements = nil)
    NumberFieldSClassTwoTorsionSearch.new(
      self, s_primes, coefficient_bound,
      element_limit, rational_prime_limit,
      factor_search_limit,
      generator_search_limit,
      ideal_generator_bounds,
      initial_relation_elements, false)

  -> certify_s_class_two_torsion_from_relations(
       s_primes, relation_elements,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    factor_base = NumberFieldMinkowskiFactorBase.new(
      self, s_primes, rational_prime_limit,
      factor_search_limit, generator_search_limit)
    NumberFieldSClassTwoTorsionProof.new(
      factor_base, relation_elements)

  -> certify_s_class_two_torsion_via_isomorphic_model(
       rational_primes,
       coefficient_bound = 4,
       element_limit = 100_000,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000,
       ideal_generator_bounds = nil)
    certificate = irreducibility_certificate
    expected = "NumberFieldIsomorphicModelIrreducibilityCertificate"
    if certificate.class_name != expected
      raise "number field has no certified isomorphic model"
    model = certificate.model_field
    model_s_primes = []
    rational_primes.each -> (rational_prime)
      model.prime_ideals_above(
        rational_prime,
        factor_search_limit,
        generator_search_limit).each -> (prime)
        model_s_primes.push(prime)
    model_proof = model.certify_s_class_two_torsion(
      model_s_primes, coefficient_bound,
      element_limit, rational_prime_limit,
      factor_search_limit,
      generator_search_limit,
      ideal_generator_bounds)
    NumberFieldIsomorphicSClassTwoTorsionProof.new(
      self, rational_primes, model_proof)
