# Certified prime ideal decomposition in orders, number fields, and etale products.

+ AlgebraPrimeIdealCertificate
  -> new(@prime_ideal)
    @verified_cache = nil

  ro :prime_ideal

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @prime_ideal.class_name != "AlgebraPrimeIdeal"
      raise "prime-ideal certificate has the wrong subject"
    map = @prime_ideal.residue_map
    if !map.certificate.verified?
      raise "prime ideal has an uncertified residue-field map"
    if !@prime_ideal.lattice.same_lattice?(
         map.kernel_lattice)
      raise "prime-ideal lattice is not the residue-map kernel"
    if !@prime_ideal.ideal?
      raise "residue-map kernel is not an order ideal"
    if @prime_ideal.index != @prime_ideal.norm
      raise "prime-ideal index and norm disagree"
    expected_norm = @prime_ideal.rational_prime ** @prime_ideal.residue_degree
    if @prime_ideal.norm != expected_norm
      raise "prime-ideal norm is not p^f"
    if map.class_name == "OrderResidueFieldMap"
      local_dimension = map.residue_algebra.local_dimension(
        map.idempotent)
      expected_local = @prime_ideal.ramification_index
      expected_local *= @prime_ideal.residue_degree
      if local_dimension != expected_local
        raise "prime-ideal ramification data has the wrong local dimension"
    @verified_cache = true
    true

  -> prime?
    verified?

  -> maximal?
    verified?

  -> certified?
    verified?

  -> to_s
    text = "AlgebraPrimeIdealCertificate(p="
    text + @prime_ideal.rational_prime.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeIdeal
  -> new(@residue_map, @ramification_index)
    map_name = @residue_map.class_name
    supported = map_name == "OrderResidueFieldMap"
    supported = true if map_name == "DedekindOrderResidueFieldMap"
    if !supported
      raise "prime ideal needs a certified order residue-field map"
    if @ramification_index < 1
      raise "prime-ideal ramification index must be positive"
    @order = @residue_map.order
    @lattice = @residue_map.kernel_lattice
    @certificate_cache = AlgebraPrimeIdealCertificate.new(self)
    if !@certificate_cache.verified?
      raise "prime ideal failed certification"

  ro :order

  -> algebra
    @order.algebra

  ro :residue_map, :lattice

  -> rational_prime
    @residue_map.prime

  -> residue_field
    @residue_map.field

  -> residue_degree
    @residue_map.residue_degree

  ro :ramification_index

  -> norm
    residue_field.order

  -> index
    @order.lattice.index_from(@lattice)

  -> basis_vectors
    @lattice.basis_vectors

  -> basis
    out = []
    basis_vectors.each -> (vector)
      out.push(@order.algebra.coerce(vector))
    out

  -> contains?(value)
    element = @order.coerce(value)
    residue_field.zero?(@residue_map.image(element))

  -> reduce(value)
    @residue_map.image(value)

  -> ideal?
    order_basis = @order.basis
    ideal_basis = basis
    i = 0
    while i < order_basis.size
      j = 0
      while j < ideal_basis.size
        product = @order.algebra.multiply(
          order_basis[i], ideal_basis[j])
        return false if !@lattice.contains_vector?(
          product.coefficients)
        j += 1
      i += 1
    true

  -> eql?(other)
    return false if other.class_name != "AlgebraPrimeIdeal"
    return false if other.order != @order
    @lattice.same_lattice?(other.lattice)

  -> ==/1
    self.eql?(@1)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> prime?
    certificate.verified?

  -> maximal?
    certificate.verified?

  -> to_s
    text = "PrimeIdeal(p=" + rational_prime.to_s
    text + ", e=" + @ramification_index.to_s
    text + ", f=" + residue_degree.to_s + ")"

  -> inspect
    to_s


+ DedekindAlgebraPrimeDecompositionCertificate
  -> new(@decomposition)
    @verified_cache = nil

  ro :decomposition

  -> theorem
    "Dedekind factorization theorem away from the power-order index"

  -> theorem_reference
    "Dedekind-Kummer theorem"

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    expected = "DedekindAlgebraPrimeDecomposition"
    return false if @decomposition.class_name != expected
    computation = @decomposition.maximal_order_computation
    return false if computation.class_name != "MaximalOrderComputation"
    return false if !computation.certificate.verified?
    return false if !@decomposition.order.same_order?(
      computation.order)
    prime = @decomposition.prime
    return false if prime < 2 || !prime.prime?
    return false if computation.index % prime == 0

    factorization = @decomposition.factorization
    return false if factorization.class_name != "PolynomialFactorization"
    return false if !factorization.certificate.verified?
    factors = @decomposition.distinct_factors
    multiplicities = @decomposition.multiplicities
    ideals = @decomposition.prime_ideals
    return false if factors.size == 0
    return false if multiplicities.size != factors.size
    return false if ideals.size != factors.size

    reconstructed = factorization.polynomial.ring.one
    degree_sum = 0
    norm_product = 1 ## big
    i = 0
    while i < factors.size
      factor = factors[i]
      multiplicity = multiplicities[i]
      return false if multiplicity < 1
      power = 0
      while power < multiplicity
        reconstructed = reconstructed * factor
        power += 1

      ideal = ideals[i]
      return false if !ideal.certificate.verified?
      return false if !ideal.order.same_order?(
        @decomposition.order)
      return false if ideal.rational_prime != prime
      return false if ideal.residue_degree != factor.degree
      return false if ideal.ramification_index != multiplicity
      return false if ideal.residue_map.class_name != "DedekindOrderResidueFieldMap"
      return false if !ideal.residue_map.factor.eql?(factor)
      j = 0
      while j < i
        return false if ideal.eql?(ideals[j])
        j += 1
      degree_sum += multiplicity * factor.degree
      norm_product *= ideal.norm ** multiplicity
      i += 1

    return false if !reconstructed.eql?(
      factorization.polynomial)
    return false if degree_sum != @decomposition.order.rank
    expected_norm = prime ** @decomposition.order.rank
    return false if norm_product != expected_norm
    @verified_cache = true
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> to_s
    text = "DedekindAlgebraPrimeDecompositionCertificate(p="
    text + @decomposition.prime.to_s + ")"

  -> inspect
    to_s


+ DedekindAlgebraPrimeDecomposition
  -> new(@maximal_order_computation, @prime,
         @factor_search_limit = 250_000)
    expected = "MaximalOrderComputation"
    if @maximal_order_computation.class_name != expected
      raise "Dedekind prime decomposition needs a maximal-order computation"
    if !@maximal_order_computation.certificate.verified?
      raise "Dedekind prime decomposition needs a certified maximal order"
    if @prime < 2 || !@prime.prime?
      raise "Dedekind prime decomposition needs a rational prime"
    if @maximal_order_computation.index % @prime == 0
      raise "Dedekind prime decomposition needs index prime to p"
    @order = @maximal_order_computation.order
    source_polynomial = @maximal_order_computation.source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      source_polynomial.ring.names,
      FiniteField.new(@prime))
    reduced = source_polynomial.change_ring(
      finite_ring).monic
    @factorization = reduced.factor_with_certificate(
      @factor_search_limit)
    if !@factorization.certificate.verified?
      raise "Dedekind modular factorization failed certification"
    group_factors
    @prime_ideals = []
    i = 0
    while i < @distinct_factors.size
      map = DedekindOrderResidueFieldMap.new(
        @maximal_order_computation, @prime,
        @distinct_factors[i], @factorization)
      @prime_ideals.push(AlgebraPrimeIdeal.new(
        map, @multiplicities[i]))
      i += 1
    @certificate_cache = DedekindAlgebraPrimeDecompositionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "Dedekind prime decomposition failed certification"

  -> group_factors
    @distinct_factors = []
    @multiplicities = []
    source = @factorization.factors
    i = 0
    while i < source.size
      factor = source[i]
      if factor.degree > 0
        index = nil
        j = 0
        while j < @distinct_factors.size
          if index == nil && @distinct_factors[j].eql?(factor)
            index = j
          j += 1
        if index == nil
          @distinct_factors.push(factor)
          @multiplicities.push(1)
        else
          @multiplicities[index] += 1
      i += 1
    if @distinct_factors.size == 0
      raise "Dedekind factorization has no nonconstant factors"

  ro :maximal_order_computation, :order, :prime, :factorization

  -> distinct_factors
    out = []
    @distinct_factors.each -> (factor)
      out.push(factor)
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

  -> factors
    out = []
    i = 0
    while i < @prime_ideals.size
      out.push([
        @prime_ideals[i],
        @multiplicities[i]
      ])
      i += 1
    out

  -> residue_degrees
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.residue_degree)
    out

  -> ramification_indices
    out = []
    @multiplicities.each -> (multiplicity)
      out.push(multiplicity)
    out

  -> norms
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.norm)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "DedekindAlgebraPrimeDecomposition(p="
    text + @prime.to_s
    text + ", factors=" + @prime_ideals.size.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeDecompositionCertificate
  -> new(@decomposition)
    @verified_cache = nil

  ro :decomposition

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @decomposition.class_name != "AlgebraPrimeDecomposition"
      raise "prime-decomposition certificate has the wrong subject"
    if !@decomposition.p_maximality_certificate.verified?
      raise "prime decomposition needs a p-maximal order"
    if !@decomposition.residue_algebra.certificate.verified?
      raise "prime decomposition has an uncertified residue algebra"
    ideals = @decomposition.prime_ideals
    idempotents = @decomposition.residue_algebra.primitive_idempotents
    if ideals.size == 0 || ideals.size != idempotents.size
      raise "prime decomposition has the wrong number of factors"
    degree_sum = 0
    norm_product = 1 ## big
    i = 0
    while i < ideals.size
      ideal = ideals[i]
      if !ideal.certificate.verified?
        raise "prime decomposition contains an uncertified ideal"
      if ideal.order != @decomposition.order
        raise "prime decomposition ideal has the wrong order"
      if ideal.rational_prime != @decomposition.prime
        raise "prime decomposition ideal lies over the wrong prime"
      if !@decomposition.residue_algebra.equal?(
           ideal.residue_map.idempotent, idempotents[i])
        raise "prime decomposition changed an idempotent projection"
      j = 0
      while j < i
        if ideal.eql?(ideals[j])
          raise "prime decomposition repeats a prime ideal"
        j += 1
      degree_sum += ideal.ramification_index * ideal.residue_degree
      norm_product *= ideal.norm ** ideal.ramification_index
      i += 1
    if degree_sum != @decomposition.order.rank
      raise "sum of e*f does not equal the order rank"
    expected_norm = @decomposition.prime ** @decomposition.order.rank
    if norm_product != expected_norm
      raise "prime-factor norms do not reconstruct norm(pO)"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "AlgebraPrimeDecompositionCertificate(p="
    text + @decomposition.prime.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeDecomposition
  -> new(@order, @prime,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000)
    if @order.class_name != "AlgebraOrder"
      raise "prime decomposition needs an AlgebraOrder"
    if @prime < 2 || !@prime.prime?
      raise "prime decomposition needs a rational prime"
    @p_maximality_certificate = PMaximalOrderCertificate.new(
      @order, @prime, @order)
    if !@p_maximality_certificate.verified?
      raise "order is not p-maximal; compute a p-maximal overorder first"
    @residue_algebra = OrderResidueAlgebra.new(
      @order, @prime, @factor_search_limit)
    @prime_ideals = []
    @residue_algebra.primitive_idempotents.each -> (idempotent)
      map = OrderResidueFieldMap.new(
        @residue_algebra, idempotent,
        @generator_search_limit)
      local_dimension = @residue_algebra.local_dimension(
        idempotent)
      if local_dimension % map.residue_degree != 0
        raise "local residue dimension is not divisible by its residue degree"
      ramification_index = local_dimension / map.residue_degree
      @prime_ideals.push(AlgebraPrimeIdeal.new(
        map, ramification_index))
    @certificate_cache = AlgebraPrimeDecompositionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "prime decomposition failed certification"

  ro :order, :prime, :p_maximality_certificate, :residue_algebra

  -> prime_ideals
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal)
    out

  -> factors
    out = []
    @prime_ideals.each -> (ideal)
      out.push([ideal, ideal.ramification_index])
    out

  -> residue_degrees
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.residue_degree)
    out

  -> ramification_indices
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.ramification_index)
    out

  -> norms
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.norm)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "AlgebraPrimeDecomposition(p=" + @prime.to_s
    text + ", factors=" + @prime_ideals.size.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrder
  -> p_maximality_certificate(prime)
    PMaximalOrderCertificate.new(
      self, prime, self)

  -> p_maximal?(prime)
    p_maximality_certificate(prime).verified?

  -> prime_decomposition(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    AlgebraPrimeDecomposition.new(
      self, prime, factor_search_limit,
      generator_search_limit)

  -> prime_ideals_above(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).prime_ideals

  -> factor_rational_prime(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).factors


+ NumberFieldPrimeIdealCertificate
  -> new(@prime_ideal)
    @verified_cache = nil

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify!
    @verified_cache

  -> verify!
    return false if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
    algebra_ideal = @prime_ideal.algebra_prime_ideal
    return false if !algebra_ideal.certificate.verified?
    field = @prime_ideal.field
    return false if !algebra_ideal.order.same_order?(
      field.certify_maximal_order)
    order_vectors = algebra_ideal.order.basis_vectors
    i = 0
    while i < order_vectors.size
      element = field.generic_order_vector_to_element(
        order_vectors[i])
      coordinates = field.maximal_order_coordinates(element)
      return false if coordinates == nil
      expected = PrimeLinearAlgebra.zero_vector(
        order_vectors.size)
      expected[i] = 1
      return false if coordinates.to_s != expected.to_s
      i += 1
    ideal_vectors = algebra_ideal.basis_vectors
    i = 0
    while i < ideal_vectors.size
      element = field.generic_order_vector_to_element(
        ideal_vectors[i])
      return false if !@prime_ideal.contains?(element)
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldPrimeIdealCertificate("
    text + @prime_ideal.to_s + ")"

  -> inspect
    to_s


+ NumberFieldPrimeIdeal
  -> new(@field, @algebra_prime_ideal)
    if @field.class_name != "NumberField"
      raise "number-field prime ideal needs a NumberField"
    if @algebra_prime_ideal.class_name != "AlgebraPrimeIdeal"
      raise "number-field prime ideal needs an AlgebraPrimeIdeal"
    if !@algebra_prime_ideal.order.same_order?(
         @field.certify_maximal_order)
      raise "number-field prime ideal belongs to a different maximal order"
    @certificate_cache = NumberFieldPrimeIdealCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "number-field prime ideal failed certification"

  ro :field, :algebra_prime_ideal

  -> rational_prime
    @algebra_prime_ideal.rational_prime

  -> residue_field
    @algebra_prime_ideal.residue_field

  -> residue_degree
    @algebra_prime_ideal.residue_degree

  -> ramification_index
    @algebra_prime_ideal.ramification_index

  -> norm
    @algebra_prime_ideal.norm

  -> basis
    out = []
    @algebra_prime_ideal.basis_vectors.each -> (vector)
      out.push(@field.generic_order_vector_to_element(
        vector))
    out

  -> contains?(value)
    coordinates = @field.maximal_order_coordinates(value)
    return false if coordinates == nil
    residue_field.zero?(
      @algebra_prime_ideal.residue_map.image_order_coordinates(
        coordinates))

  -> reduce(value)
    coordinates = @field.maximal_order_coordinates(value)
    if coordinates == nil
      raise "number-field element is not integral at the displayed maximal order"
    @algebra_prime_ideal.residue_map.image_order_coordinates(
      coordinates)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> prime?
    certified?

  -> maximal?
    certified?

  -> eql?(other)
    return false if other.class_name != "NumberFieldPrimeIdeal"
    return false if other.field != @field
    @algebra_prime_ideal.eql?(
      other.algebra_prime_ideal)

  -> ==/1
    self.eql?(@1)

  -> to_s
    text = "NumberFieldPrimeIdeal(p=" + rational_prime.to_s
    text + ", e=" + ramification_index.to_s
    text + ", f=" + residue_degree.to_s + ")"

  -> inspect
    to_s


+ NumberFieldPrimeDecomposition
  -> new(@field, @algebra_decomposition)
    if @field.class_name != "NumberField"
      raise "number-field prime decomposition needs a NumberField"
    decomposition_name = @algebra_decomposition.class_name
    supported = decomposition_name == "AlgebraPrimeDecomposition"
    supported = true if decomposition_name == "DedekindAlgebraPrimeDecomposition"
    if !supported
      raise "number-field prime decomposition needs an algebra decomposition"
    @prime_ideals = []
    @algebra_decomposition.prime_ideals.each -> (ideal)
      @prime_ideals.push(
        NumberFieldPrimeIdeal.new(@field, ideal))
    if !certified?
      raise "number-field prime decomposition failed certification"

  ro :field

  -> prime
    @algebra_decomposition.prime

  ro :algebra_decomposition

  -> prime_ideals
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal)
    out

  -> factors
    out = []
    @prime_ideals.each -> (ideal)
      out.push([ideal, ideal.ramification_index])
    out

  -> residue_degrees
    @algebra_decomposition.residue_degrees

  -> ramification_indices
    @algebra_decomposition.ramification_indices

  -> norms
    @algebra_decomposition.norms

  -> certificate
    @algebra_decomposition.certificate

  -> certified?
    return false if !@algebra_decomposition.certificate.verified?
    i = 0
    while i < @prime_ideals.size
      return false if !@prime_ideals[i].certificate.verified?
      i += 1
    true

  -> to_s
    text = "NumberFieldPrimeDecomposition(p=" + prime.to_s
    text + ", factors=" + @prime_ideals.size.to_s + ")"

  -> inspect
    to_s


+ NumberField
  -> generic_order_vector_to_element(vector)
    if vector.class_name != "Array" || vector.size != @degree
      raise "generic order vector has the wrong number-field dimension"
    scale = monogenic_order.generator_scale
    coefficients = []
    power = 1 ## big
    i = 0
    while i < @degree
      coefficients.push(
        Rational.coerce(vector[i]) * power)
      power *= scale
      i += 1
    coerce(coefficients)

  # Integer coordinates in the certified generic maximal-order basis, or nil
  # when the element is not integral.
  -> maximal_order_coordinates(value)
    element = coerce(value)
    if @generic_integral_basis_inverse == nil
      basis = generic_integral_basis
      columns = []
      basis.each -> (basis_element)
        columns.push(basis_element.coefficients)
      matrix = ExactRationalLinearAlgebra.matrix_from_columns(
        columns)
      @generic_integral_basis_inverse = ExactRationalLinearAlgebra.inverse(
        matrix)
    coordinates = ExactRationalLinearAlgebra.matrix_vector(
      @generic_integral_basis_inverse,
      element.coefficients)
    out = []
    i = 0
    while i < coordinates.size
      coefficient = coordinates[i]
      return nil if coefficient.denominator != 1
      out.push(coefficient.numerator)
      i += 1
    out

  -> prime_decomposition(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    if @prime_decomposition_primes_cache == nil
      @prime_decomposition_primes_cache = []
      @prime_decompositions_cache = []
    cache_index = 0
    while cache_index < @prime_decomposition_primes_cache.size
      if @prime_decomposition_primes_cache[cache_index] == prime
        return @prime_decompositions_cache[cache_index]
      cache_index += 1
    order = certify_maximal_order
    computation = maximal_order_computation
    prime_class = prime.class_name
    integer_prime = prime_class == "Integer" || prime_class == "Int"
    integer_prime = true if prime_class == "BigInt"
    use_dedekind = integer_prime && prime >= 2
    use_dedekind = use_dedekind && prime.prime?
    if use_dedekind
      use_dedekind = computation.index % prime != 0
    if use_dedekind
      algebra_decomposition = DedekindAlgebraPrimeDecomposition.new(
        computation, prime, factor_search_limit)
    else
      algebra_decomposition = order.prime_decomposition(
        prime, factor_search_limit,
        generator_search_limit)
    result = NumberFieldPrimeDecomposition.new(
      self, algebra_decomposition)
    @prime_decomposition_primes_cache.push(prime)
    @prime_decompositions_cache.push(result)
    result

  -> prime_ideals_above(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).prime_ideals

  -> factor_rational_prime(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).factors


+ EtaleProductPrimeIdealCertificate
  -> new(@prime_ideal)

  -> verified?
    return false if @prime_ideal.class_name != "EtaleProductPrimeIdeal"
    component = @prime_ideal.component_prime_ideal
    return false if !component.certificate.verified?
    orders = @prime_ideal.order.component_algebra_orders
    index = @prime_ideal.component_index
    return false if index < 0 || index >= orders.size
    component.order.same_order?(orders[index])

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductPrimeIdealCertificate("
    text + @prime_ideal.to_s + ")"

  -> inspect
    to_s


+ EtaleProductPrimeIdeal
  -> new(@order, @component_index,
         @component_prime_ideal)
    if @order.class_name != "EtaleProductOrder"
      raise "product prime ideal needs an EtaleProductOrder"
    if @component_prime_ideal.class_name != "AlgebraPrimeIdeal"
      raise "product prime ideal needs an AlgebraPrimeIdeal component"
    if !certificate.verified?
      raise "product prime ideal failed certification"

  ro :order, :component_index, :component_prime_ideal

  -> rational_prime
    @component_prime_ideal.rational_prime

  -> residue_field
    @component_prime_ideal.residue_field

  -> residue_degree
    @component_prime_ideal.residue_degree

  -> ramification_index
    @component_prime_ideal.ramification_index

  -> norm
    @component_prime_ideal.norm

  -> contains?(value)
    element = @order.coerce(value)
    @component_prime_ideal.contains?(
      element.components[@component_index])

  -> reduce(value)
    element = @order.coerce(value)
    @component_prime_ideal.reduce(
      element.components[@component_index])

  -> certificate
    EtaleProductPrimeIdealCertificate.new(self)

  -> certified?
    certificate.verified?

  -> prime?
    certified?

  -> maximal?
    certified?

  -> eql?(other)
    return false if other.class_name != "EtaleProductPrimeIdeal"
    return false if other.order != @order
    return false if other.component_index != @component_index
    @component_prime_ideal.eql?(
      other.component_prime_ideal)

  -> ==/1
    self.eql?(@1)

  -> to_s
    text = "EtaleProductPrimeIdeal(component="
    text + @component_index.to_s
    text += ", p=" + rational_prime.to_s
    text + ", e=" + ramification_index.to_s
    text + ", f=" + residue_degree.to_s + ")"

  -> inspect
    to_s


+ EtaleProductPrimeDecompositionCertificate
  -> new(@decomposition)

  -> verified?
    wrong_class = @decomposition.class_name != "EtaleProductPrimeDecomposition"
    return false if wrong_class
    components = @decomposition.component_decompositions
    wrong_size = components.size != @decomposition.order.component_count
    return false if wrong_size
    degree_sum = 0
    i = 0
    while i < components.size
      component = components[i]
      return false if !component.certificate.verified?
      return false if component.prime != @decomposition.prime
      component_ideals = component.prime_ideals
      j = 0
      while j < component_ideals.size
        ideal = component_ideals[j]
        degree_sum += ideal.ramification_index * ideal.residue_degree
        j += 1
      i += 1
    return false if degree_sum != @decomposition.order.rank
    ideals = @decomposition.prime_ideals
    expected_count = 0
    components.each -> (component)
      expected_count += component.prime_ideals.size
    return false if ideals.size != expected_count
    cursor = 0
    component_index = 0
    while component_index < components.size
      component_ideals = components[
        component_index].prime_ideals
      ideal_index = 0
      while ideal_index < component_ideals.size
        ideal = ideals[cursor]
        return false if !ideal.certificate.verified?
        return false if ideal.component_index != component_index
        return false if !ideal.component_prime_ideal.eql?(
          component_ideals[ideal_index])
        cursor += 1
        ideal_index += 1
      component_index += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductPrimeDecompositionCertificate(p="
    text + @decomposition.prime.to_s + ")"

  -> inspect
    to_s


+ EtaleProductPrimeDecomposition
  -> new(@order, @prime,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000)
    if @order.class_name != "EtaleProductOrder"
      raise "product prime decomposition needs an EtaleProductOrder"
    @component_decompositions = []
    @prime_ideals = []
    components = @order.component_algebra_orders
    i = 0
    while i < components.size
      decomposition = components[i].prime_decomposition(
        @prime, @factor_search_limit,
        @generator_search_limit)
      @component_decompositions.push(decomposition)
      decomposition.prime_ideals.each -> (ideal)
        @prime_ideals.push(EtaleProductPrimeIdeal.new(
          @order, i, ideal))
      i += 1
    if !certificate.verified?
      raise "product prime decomposition failed certification"

  ro :order, :prime

  -> component_decompositions
    out = []
    @component_decompositions.each -> (decomposition)
      out.push(decomposition)
    out

  -> prime_ideals
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal)
    out

  -> factors
    out = []
    @prime_ideals.each -> (ideal)
      out.push([ideal, ideal.ramification_index])
    out

  -> residue_degrees
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.residue_degree)
    out

  -> ramification_indices
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.ramification_index)
    out

  -> norms
    out = []
    @prime_ideals.each -> (ideal)
      out.push(ideal.norm)
    out

  -> certificate
    EtaleProductPrimeDecompositionCertificate.new(
      self)

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductPrimeDecomposition(p=" + @prime.to_s
    text + ", factors=" + @prime_ideals.size.to_s + ")"

  -> inspect
    to_s


+ EtaleProductOrder
  -> prime_decomposition(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    EtaleProductPrimeDecomposition.new(
      self, prime, factor_search_limit,
      generator_search_limit)

  -> prime_ideals_above(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).prime_ideals

  -> factor_rational_prime(
       prime, factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    prime_decomposition(
      prime, factor_search_limit,
      generator_search_limit).factors


+ EtaleProductSPrimeDataCertificate
  -> new(@data)

  -> verified?
    return false if @data.class_name != "EtaleProductSPrimeData"
    return false if !@data.order.certificate.verified?
    primes = @data.rational_primes
    decompositions = @data.decompositions
    return false if primes.size == 0
    return false if primes.size != decompositions.size
    i = 0
    while i < primes.size
      prime = primes[i]
      return false if prime < 2 || !prime.prime?
      previous = 0
      while previous < i
        return false if primes[previous] == prime
        previous += 1
      decomposition = decompositions[i]
      return false if decomposition.order != @data.order
      return false if decomposition.prime != prime
      return false if !decomposition.certificate.verified?
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductSPrimeDataCertificate("
    text + @data.rational_primes.to_s + ")"

  -> inspect
    to_s


+ EtaleProductSPrimeData
  -> new(@order, rational_primes,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000)
    if @order.class_name != "EtaleProductOrder"
      raise "S-prime data needs an EtaleProductOrder"
    invalid_primes = rational_primes.class_name != "Array"
    if !invalid_primes
      invalid_primes = true if rational_primes.size == 0
    if invalid_primes
      raise "S-prime data needs rational primes"
    @rational_primes = []
    @decompositions = []
    rational_primes.each -> (prime)
      if prime < 2 || !prime.prime?
        raise "S contains a nonprime finite place"
      if @rational_primes.include?(prime)
        raise "S contains a repeated rational prime"
      @rational_primes.push(prime)
      @decompositions.push(@order.prime_decomposition(
        prime, @factor_search_limit,
        @generator_search_limit))
    if !certificate.verified?
      raise "S-prime data failed certification"

  ro :order

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> decompositions
    out = []
    @decompositions.each -> (decomposition)
      out.push(decomposition)
    out

  -> prime_ideals
    out = []
    @decompositions.each -> (decomposition)
      decomposition.prime_ideals.each -> (ideal)
        out.push(ideal)
    out

  -> prime_ideals_above(prime)
    index = nil
    i = 0
    while i < @rational_primes.size
      if index == nil
        index = i if @rational_primes[i] == prime
      i += 1
    return [] if index == nil
    @decompositions[index].prime_ideals

  -> factor_count
    prime_ideals.size

  -> certificate
    EtaleProductSPrimeDataCertificate.new(self)

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductSPrimeData(S="
    text += @rational_primes.to_s
    text + ", factors=" + factor_count.to_s + ")"

  -> inspect
    to_s


+ EtaleProductOrder
  -> s_prime_data(
       rational_primes,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    EtaleProductSPrimeData.new(
      self, rational_primes,
      factor_search_limit,
      generator_search_limit)
