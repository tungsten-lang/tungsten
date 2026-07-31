# Certified prime ideals of maximal Z-orders.
#
# A rational prime p is first checked against the Round 2 fixed-point
# criterion.  The reduced finite algebra O/radical(pO) is then split into
# finite fields by its primitive idempotents.  Each projection
#
#   O -> O/radical(pO) -> k_i
#
# is replayed on an order basis; its kernel is a maximal ideal above p.
# Frobenius-lifted idempotents in O/pO give the local dimensions e_i f_i, so
# residue degrees and ramification indices are certified together.

+ OrderResidueFieldMapCertificate
  -> new(@residue_map)
    @verified_cache = nil

  -> residue_map
    @residue_map

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @residue_map.class_name != "OrderResidueFieldMap"
      raise "residue-field-map certificate has the wrong subject"
    residue = @residue_map.residue_algebra
    if !residue.certificate.verified?
      raise "residue-field map has an uncertified reduced algebra"
    field = @residue_map.field
    if field.class_name != "FiniteField"
      raise "residue-field target is not a finite field"
    if field.characteristic != residue.prime
      raise "residue-field characteristic changed"
    if field.degree != @residue_map.residue_degree
      raise "residue-field degree changed"
    found_idempotent = false
    residue.primitive_idempotents.each -> (idempotent)
      found_idempotent = true if residue.equal?(
        idempotent, @residue_map.idempotent)
    if !found_idempotent
      raise "residue-field map uses a nonprimitive idempotent"
    if !field.one?(@residue_map.image(
         @residue_map.order.one))
      raise "residue-field map does not preserve one"
    if !field.zero?(@residue_map.image(
         @residue_map.order.zero))
      raise "residue-field map does not preserve zero"

    order_basis = @residue_map.order.basis
    images = []
    order_basis.each -> (element)
      images.push(@residue_map.image(element))
    image_columns = []
    images.each -> (image)
      image_columns.push(field.element_coefficients(image))
    image_rank = PrimeLinearAlgebra.rank_columns(
      image_columns, residue.prime, field.degree)
    if image_rank != field.degree
      raise "residue-field map is not surjective"

    i = 0
    while i < order_basis.size
      j = 0
      while j < order_basis.size
        source_sum = @residue_map.order.algebra.add(
          order_basis[i], order_basis[j])
        image_sum = field.add(images[i], images[j])
        if !field.equal?(
             @residue_map.image(source_sum), image_sum)
          raise "residue-field map does not preserve addition"
        source_product = @residue_map.order.algebra.multiply(
          order_basis[i], order_basis[j])
        image_product = field.multiply(images[i], images[j])
        if !field.equal?(
             @residue_map.image(source_product), image_product)
          raise "residue-field map does not preserve multiplication"
        j += 1
      i += 1

    kernel = @residue_map.kernel_lattice
    if !@residue_map.order.lattice.contains_lattice?(kernel)
      raise "residue-field kernel is not contained in its order"
    kernel.basis_vectors.each -> (vector)
      element = @residue_map.order.algebra.coerce(vector)
      if !field.zero?(@residue_map.image(element))
        raise "displayed residue-field kernel has a nonzero image"
    index = @residue_map.order.lattice.index_from(kernel)
    if index != field.order
      raise "residue-field kernel has the wrong lattice index"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "OrderResidueFieldMapCertificate(F_"
    text + @residue_map.field.order.to_s + ")"

  -> inspect
    to_s


+ OrderResidueFieldMap
  -> new(@residue_algebra, idempotent,
         @generator_search_limit = 250_000)
    if @residue_algebra.class_name != "OrderResidueAlgebra"
      raise "residue-field map needs an OrderResidueAlgebra"
    if @generator_search_limit < 1
      raise "residue-field generator search limit must be positive"
    @order = @residue_algebra.order
    @prime = @residue_algebra.prime
    @idempotent = @residue_algebra.normalize(idempotent)
    primitive = false
    @residue_algebra.primitive_idempotents.each -> (candidate)
      primitive = true if @residue_algebra.equal?(
        candidate, @idempotent)
    if !primitive
      raise "residue-field map needs a primitive idempotent"
    @component_basis = @residue_algebra.component_basis(
      @idempotent)
    @residue_degree = @component_basis.size
    if @residue_degree < 1
      raise "residue-field component has zero degree"
    @generator = nil
    @minimal_polynomial = nil
    @power_basis = []
    choose_generator
    @kernel_lattice_cache = nil
    @certificate_cache = OrderResidueFieldMapCertificate.new(self)
    if !@certificate_cache.verified?
      raise "residue-field map failed certification"

  -> residue_algebra
    @residue_algebra

  -> order
    @order

  -> prime
    @prime

  -> idempotent
    out = []
    @idempotent.each -> (entry)
      out.push(entry)
    out

  -> residue_degree
    @residue_degree

  -> field
    @field

  -> generator
    out = []
    @generator.each -> (entry)
      out.push(entry)
    out

  -> minimal_polynomial
    @minimal_polynomial

  -> component_basis
    out = []
    @component_basis.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> power_basis
    out = []
    @power_basis.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> candidate_from_code(code)
    remaining = code
    value = @residue_algebra.zero
    i = 0
    while i < @component_basis.size
      coefficient = remaining % @prime
      remaining = remaining / @prime
      if coefficient != 0
        value = @residue_algebra.add(
          value,
          @residue_algebra.scale(
            @component_basis[i], coefficient))
      i += 1
    value

  -> choose_generator
    if @residue_degree == 1
      @generator = @idempotent
      @field = FiniteField.new(@prime)
      @power_basis = [@idempotent]
      ring = PolynomialRing.new(
        [:T], FiniteField.new(@prime))
      @minimal_polynomial = ring.generator(0) - 1
      return self

    candidate_count = @prime ** @residue_degree
    code = 1
    attempts = 0
    while code < candidate_count
      attempts += 1
      if attempts > @generator_search_limit
        raise "residue-field generator search limit exceeded; prime decomposition unknown"
      candidate = candidate_from_code(code)
      polynomial = @residue_algebra.minimal_polynomial(
        candidate, @idempotent)
      if polynomial.degree == @residue_degree
        @generator = candidate
        @minimal_polynomial = polynomial
        @field = FiniteField.new(
          @prime, polynomial.coefficients)
        break
      code += 1
    if @generator == nil
      raise "residue-field generator search exhausted the component"

    @power_basis = []
    value = @idempotent
    i = 0
    while i < @residue_degree
      @power_basis.push(value)
      value = @residue_algebra.multiply(
        value, @generator)
      i += 1
    rank = PrimeLinearAlgebra.rank_columns(
      @power_basis, @prime,
      @residue_algebra.dimension)
    if rank != @residue_degree
      raise "residue-field power basis is dependent"
    self

  -> component_coordinates(value)
    projected = @residue_algebra.multiply(
      @idempotent,
      @residue_algebra.normalize(value))
    PrimeLinearAlgebra.solve_columns(
      @power_basis, projected, @prime)

  -> image_order_coordinates(coordinates)
    reduced = @residue_algebra.project_order_coordinates(
      coordinates)
    @field.encode_coefficients(
      component_coordinates(reduced))

  -> integer_order_coordinates(value)
    element = @order.coerce(value)
    coordinates = @order.coordinates(element)
    out = []
    coordinates.each -> (coefficient)
      if coefficient.denominator != 1
        raise "residue-field source is not integral in its order"
      out.push(coefficient.numerator)
    out

  -> image(value)
    image_order_coordinates(
      integer_order_coordinates(value))

  -> reduce(value)
    image(value)

  -> kernel_basis_vectors
    columns = []
    i = 0
    while i < @order.rank
      coordinates = PrimeLinearAlgebra.zero_vector(
        @order.rank)
      coordinates[i] = 1
      image = image_order_coordinates(coordinates)
      columns.push(@field.element_coefficients(image))
      i += 1
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, @residue_degree, @prime)
    kernel = PrimeLinearAlgebra.kernel_data(
      matrix, @prime, @order.rank)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < @order.rank
        value = i == pivot ? @prime : 0
        vector.push(Rational.new(value))
        i += 1
      relative.push(vector)
    if relative.size != @order.rank
      raise "residue-field kernel lattice has the wrong rank"
    ExactRationalLinearAlgebra.compose_columns(
      @order.basis_vectors, relative)

  -> kernel_lattice
    if @kernel_lattice_cache == nil
      @kernel_lattice_cache = AlgebraOrderLattice.new(
        @order.algebra, kernel_basis_vectors)
    @kernel_lattice_cache

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "OrderResidueFieldMap(p=" + @prime.to_s
    text + ", f=" + @residue_degree.to_s + ")"

  -> inspect
    to_s


+ DedekindLinearRootCertificate
  -> new(@maximal_order_computation, @prime, root)
    @root = PrimeLinearAlgebra.normalize(
      root, @prime)
    source = @maximal_order_computation.source
    polynomial = source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      polynomial.ring.names,
      FiniteField.new(@prime))
    @polynomial = polynomial.change_ring(
      finite_ring).monic
    @factor = finite_ring.generator(0) - @root

  -> maximal_order_computation
    @maximal_order_computation

  -> prime
    @prime

  -> root
    @root

  -> polynomial
    @polynomial

  -> factor
    @factor

  -> polynomial_zero_at_root?
    coefficients = @polynomial.coefficients
    value = 0
    i = coefficients.size - 1
    while i >= 0
      value = PrimeLinearAlgebra.normalize(
        value * @root + coefficients[i],
        @prime)
      i -= 1
    value == 0

  -> verified?
    expected = "MaximalOrderComputation"
    return false if @maximal_order_computation.class_name != expected
    return false if !@maximal_order_computation.certificate.verified?
    return false if @prime < 2 || !@prime.prime?
    return false if @maximal_order_computation.index % @prime == 0
    return false if @root < 0 || @root >= @prime
    source = @maximal_order_computation.source
    source_polynomial = source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      source_polynomial.ring.names,
      FiniteField.new(@prime))
    expected_polynomial = source_polynomial.change_ring(
      finite_ring).monic
    return false if !@polynomial.eql?(expected_polynomial)
    return false if !@factor.eql?(
      finite_ring.generator(0) - @root)
    polynomial_zero_at_root?

  -> certified?
    verified?

  -> proof_kind
    :exact_modular_root

  -> kernel_checked?
    true


+ DedekindOrderResidueFieldMapCertificate
  -> new(@residue_map)
    @verified_cache = nil

  -> residue_map
    @residue_map

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    expected = "DedekindOrderResidueFieldMap"
    return false if @residue_map.class_name != expected
    computation = @residue_map.maximal_order_computation
    return false if computation.class_name != "MaximalOrderComputation"
    return false if !computation.certificate.verified?
    return false if !@residue_map.order.same_order?(
      computation.order)
    return false if !@residue_map.source_order.same_order?(
      computation.source)
    prime = @residue_map.prime
    return false if prime < 2 || !prime.prime?
    return false if computation.index % prime == 0

    factorization = @residue_map.factorization
    root_certificate = @residue_map.root_certificate
    polynomial = nil
    if factorization != nil
      return false if factorization.class_name != "PolynomialFactorization"
      return false if !factorization.certificate.verified?
      polynomial = factorization.polynomial
    else
      expected_root_class = "DedekindLinearRootCertificate"
      return false if root_certificate.class_name != expected_root_class
      return false if !root_certificate.verified?
      return false if root_certificate.maximal_order_computation != computation
      return false if root_certificate.prime != prime
      polynomial = root_certificate.polynomial
    return false if polynomial.ring.field.class_name != "FiniteField"
    return false if !polynomial.ring.field.prime_field?
    return false if polynomial.ring.field.characteristic != prime
    expected_polynomial = computation.source.algebra.defining_polynomial
    finite_ring = PolynomialRing.new(
      expected_polynomial.ring.names,
      FiniteField.new(prime))
    expected_reduction = expected_polynomial.change_ring(
      finite_ring).monic
    return false if !polynomial.eql?(expected_reduction)

    factor = @residue_map.factor
    return false if factor.class_name != "Polynomial"
    return false if factor.ring != polynomial.ring
    return false if factor.degree < 1
    return false if !factor.eql?(factor.monic)
    if factorization != nil
      found = false
      factors = factorization.factors
      i = 0
      while i < factors.size
        found = true if factors[i].eql?(factor)
        i += 1
      return false if !found
    else
      return false if !root_certificate.factor.eql?(factor)

    field = @residue_map.field
    return false if field.class_name != "FiniteField"
    return false if field.characteristic != prime
    return false if field.degree != factor.degree
    if factor.degree == 1
      return false if !field.prime_field?
    else
      return false if field.modulus.to_s != factor.coefficients.to_s

    expected_images = @residue_map.recompute_basis_images
    return false if expected_images.to_s != @residue_map.basis_images.to_s
    order_basis = @residue_map.order.basis
    images = @residue_map.basis_images
    return false if images.size != order_basis.size
    image_columns = []
    i = 0
    while i < images.size
      image_columns.push(field.element_coefficients(
        images[i]))
      i += 1
    image_rank = PrimeLinearAlgebra.rank_columns(
      image_columns, prime, field.degree)
    return false if image_rank != field.degree

    i = 0
    while i < order_basis.size
      return false if !field.equal?(
        @residue_map.image(order_basis[i]),
        images[i])
      j = 0
      while j < order_basis.size
        source_product = @residue_map.order.algebra.multiply(
          order_basis[i], order_basis[j])
        image_product = field.multiply(
          images[i], images[j])
        return false if !field.equal?(
          @residue_map.image(source_product),
          image_product)
        j += 1
      i += 1

    kernel = @residue_map.kernel_lattice
    return false if !@residue_map.order.lattice.contains_lattice?(
      kernel)
    kernel_vectors = kernel.basis_vectors
    i = 0
    while i < kernel_vectors.size
      element = @residue_map.order.algebra.coerce(
        kernel_vectors[i])
      return false if !field.zero?(
        @residue_map.image(element))
      i += 1
    index = @residue_map.order.lattice.index_from(kernel)
    return false if index != field.order
    @verified_cache = true
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_dedekind_residue_map

  -> kernel_checked?
    true

  -> to_s
    text = "DedekindOrderResidueFieldMapCertificate(F_"
    text + @residue_map.field.order.to_s + ")"

  -> inspect
    to_s


+ DedekindOrderResidueFieldMap
  -> new(@maximal_order_computation, @prime,
         @factor, @factorization)
    initialize_dedekind_residue_map(nil)

  -> new(@maximal_order_computation, @prime,
         @factor, @factorization,
         root_certificate)
    initialize_dedekind_residue_map(
      root_certificate)

  -> initialize_dedekind_residue_map(root_certificate)
    expected = "MaximalOrderComputation"
    if @maximal_order_computation.class_name != expected
      raise "Dedekind residue map needs a maximal-order computation"
    if !@maximal_order_computation.certificate.verified?
      raise "Dedekind residue map needs a certified maximal order"
    if @prime < 2 || !@prime.prime?
      raise "Dedekind residue map needs a rational prime"
    if @maximal_order_computation.index % @prime == 0
      raise "Dedekind residue map needs index prime to p"
    @order = @maximal_order_computation.order
    @source_order = @maximal_order_computation.source
    @root_certificate = root_certificate
    if @factor.class_name != "Polynomial" || @factor.degree < 1
      raise "Dedekind residue map needs a nonconstant factor"
    if @factorization == nil && @root_certificate == nil
      raise "Dedekind residue map needs a factor proof"
    @residue_degree = @factor.degree
    if @residue_degree == 1
      @field = FiniteField.new(@prime)
      if @root_certificate == nil
        @root = @field.coerce(0 - @factor.coeff(0))
      else
        @root = @field.coerce(
          @root_certificate.root)
    else
      @field = FiniteField.new(
        @prime, @factor.coefficients)
      @root = @field.generator
    @basis_images = recompute_basis_images
    @kernel_lattice_cache = nil
    @certificate_cache = DedekindOrderResidueFieldMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "Dedekind residue-field map failed certification"

  -> maximal_order_computation
    @maximal_order_computation

  -> order
    @order

  -> source_order
    @source_order

  -> prime
    @prime

  -> factor
    @factor

  -> factorization
    @factorization

  -> root_certificate
    @root_certificate

  -> residue_degree
    @residue_degree

  -> field
    @field

  -> root
    @root

  -> rational_mod_prime(value)
    rational = Rational.coerce(value)
    numerator = PrimeLinearAlgebra.normalize(
      rational.numerator, @prime)
    denominator = PrimeLinearAlgebra.normalize(
      rational.denominator, @prime)
    if denominator == 0
      raise "order basis denominator is not invertible modulo p"
    inverse = PrimeLinearAlgebra.inverse(
      denominator, @prime)
    @field.coerce(numerator * inverse)

  -> evaluate_power_coordinates(coordinates)
    value = @field.zero
    power = @field.one
    i = 0
    while i < coordinates.size
      coefficient = rational_mod_prime(
        coordinates[i])
      if !@field.zero?(coefficient)
        value = @field.add(
          value,
          @field.multiply(coefficient, power))
      power = @field.multiply(power, @root)
      i += 1
    value

  -> recompute_basis_images
    out = []
    @order.basis_vectors.each -> (vector)
      out.push(evaluate_power_coordinates(vector))
    out

  -> basis_images
    out = []
    @basis_images.each -> (image)
      out.push(image)
    out

  -> image_order_coordinates(coordinates)
    if coordinates.class_name != "Array"
      raise "residue-field order coordinates must be an Array"
    if coordinates.size != @order.rank
      raise "residue-field order coordinates have the wrong dimension"
    value = @field.zero
    i = 0
    while i < coordinates.size
      coefficient = @field.coerce(coordinates[i])
      if !@field.zero?(coefficient)
        term = @field.multiply(
          coefficient, @basis_images[i])
        value = @field.add(value, term)
      i += 1
    value

  -> integer_order_coordinates(value)
    element = @order.coerce(value)
    coordinates = @order.coordinates(element)
    out = []
    coordinates.each -> (coefficient)
      if coefficient.denominator != 1
        raise "residue-field source is not integral in its order"
      out.push(coefficient.numerator)
    out

  -> image(value)
    image_order_coordinates(
      integer_order_coordinates(value))

  -> reduce(value)
    image(value)

  -> kernel_basis_vectors
    columns = []
    i = 0
    while i < @order.rank
      columns.push(@field.element_coefficients(
        @basis_images[i]))
      i += 1
    matrix = PrimeLinearAlgebra.matrix_from_columns(
      columns, @residue_degree, @prime)
    kernel = PrimeLinearAlgebra.kernel_data(
      matrix, @prime, @order.rank)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < @order.rank
        value = i == pivot ? @prime : 0
        vector.push(Rational.new(value))
        i += 1
      relative.push(vector)
    if relative.size != @order.rank
      raise "residue-field kernel lattice has the wrong rank"
    ExactRationalLinearAlgebra.compose_columns(
      @order.basis_vectors, relative)

  -> kernel_lattice
    if @kernel_lattice_cache == nil
      @kernel_lattice_cache = AlgebraOrderLattice.new(
        @order.algebra, kernel_basis_vectors)
    @kernel_lattice_cache

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "DedekindOrderResidueFieldMap(p=" + @prime.to_s
    text + ", f=" + @residue_degree.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeIdealCertificate
  -> new(@prime_ideal)
    @verified_cache = nil

  -> prime_ideal
    @prime_ideal

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

  -> order
    @order

  -> algebra
    @order.algebra

  -> residue_map
    @residue_map

  -> lattice
    @lattice

  -> rational_prime
    @residue_map.prime

  -> residue_field
    @residue_map.field

  -> residue_degree
    @residue_map.residue_degree

  -> ramification_index
    @ramification_index

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

  -> decomposition
    @decomposition

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

  -> maximal_order_computation
    @maximal_order_computation

  -> order
    @order

  -> prime
    @prime

  -> factorization
    @factorization

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

  -> decomposition
    @decomposition

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

  -> order
    @order

  -> prime
    @prime

  -> p_maximality_certificate
    @p_maximality_certificate

  -> residue_algebra
    @residue_algebra

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

  -> field
    @field

  -> algebra_prime_ideal
    @algebra_prime_ideal

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

  -> field
    @field

  -> prime
    @algebra_decomposition.prime

  -> algebra_decomposition
    @algebra_decomposition

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

  -> order
    @order

  -> component_index
    @component_index

  -> component_prime_ideal
    @component_prime_ideal

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

  -> order
    @order

  -> prime
    @prime

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

  -> order
    @order

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
