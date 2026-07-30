# Replay-certified S-unit square classes in number fields.
#
# Candidate generators may be found by any algorithm.  Certification checks
# their exact ideal support, then proves independence with homomorphisms to
# F_2: valuations at S, signs at real places, and optional quadratic residue
# characters away from S.  Dirichlet's S-unit theorem supplies the known
# dimension r1+r2+|S|.  That final dimension statement is a named trusted
# theorem import; every field, ideal, sign, residue, and row-reduction
# calculation below is replayed exactly.

+ NumberFieldQuadraticResidueCharacter
  -> new(@prime_ideal)
    if !verified?
      raise "invalid number-field quadratic residue character"

  -> prime_ideal
    @prime_ideal

  -> field
    @prime_ideal.field

  -> residue_field
    @prime_ideal.residue_field

  -> verified?
    return false if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
    return false if !@prime_ideal.certificate.verified?
    @prime_ideal.rational_prime != 2

  -> certified?
    verified?

  # Clear denominators in the certified maximal-order basis.  The displayed
  # rational denominator must be a unit at this residue characteristic; if
  # not, callers should choose another auxiliary prime rather than relying on
  # an unproved local cancellation.
  -> reduction(value)
    element = field.coerce(value)
    raise "zero is not a local unit" if element.zero?
    order = field.certify_maximal_order
    algebra_element = field.generic_algebra_element(element)
    coordinates = order.coordinates(algebra_element)
    denominator = 1 ## big
    coordinates.each -> (coefficient)
      denominator = denominator.lcm(coefficient.denominator)
    if denominator % @prime_ideal.rational_prime == 0
      raise "auxiliary residue prime divides the maximal-order denominator"
    integral = field.multiply(element, denominator)
    reduced = @prime_ideal.reduce(integral)
    if residue_field.zero?(reduced)
      raise "number-field element is not a unit at the auxiliary prime"
    residue_field.divide(
      reduced, residue_field.coerce(denominator))

  -> character(value)
    residue_field.quadratic_character(reduction(value))

  -> bit(value)
    result = character(value)
    raise "quadratic residue character vanished on a claimed unit" if result == 0
    result < 0 ? 1 : 0

  -> to_s
    "QuadraticResidueCharacter(" + @prime_ideal.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSUnitSquareClassBasisCertificate
  -> new(@basis)
    @verified_cache = nil

  -> basis
    @basis

  -> theorem
    "Dirichlet S-unit theorem: dim_F2(O_K,S^*/O_K,S^{*2}) = r1+r2+|S|"

  -> theorem_reference
    "Bruin-Poonen-Stoll section 12.6.4"

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
    expected_class = "NumberFieldSUnitSquareClassBasis"
    return false if @basis.class_name != expected_class
    field = @basis.field
    return false if field.class_name != "NumberField"
    return false if !@basis.archimedean_data.certificate.verified?
    return false if @basis.archimedean_data.field != field

    signature = field.signature
    expected_dimension = signature[0] + signature[1]
    expected_dimension += @basis.s_primes.size
    return false if @basis.expected_dimension != expected_dimension
    return false if @basis.generators.size != expected_dimension

    primes = @basis.s_primes
    i = 0
    while i < primes.size
      prime = primes[i]
      return false if prime.class_name != "NumberFieldPrimeIdeal"
      return false if prime.field != field
      return false if !prime.certificate.verified?
      j = 0
      while j < i
        return false if prime.eql?(primes[j])
        j += 1
      i += 1

    characters = @basis.residue_characters
    i = 0
    while i < characters.size
      character = characters[i]
      character_class = "NumberFieldQuadraticResidueCharacter"
      return false if character.class_name != character_class
      return false if character.field != field
      return false if !character.verified?
      j = 0
      while j < primes.size
        return false if character.prime_ideal.eql?(primes[j])
        j += 1
      j = 0
      while j < i
        return false if character.prime_ideal.eql?(
          characters[j].prime_ideal)
        j += 1
      i += 1

    ideals = @basis.generator_fractional_ideals
    return false if ideals.size != @basis.generators.size
    i = 0
    while i < ideals.size
      return false if !ideals[i].certificate.verified?
      return false if !@basis.support_within_s?(ideals[i])
      i += 1

    recomputed = @basis.compute_local_matrix
    return false if !F2LinearAlgebra.same_matrix?(
      recomputed, @basis.local_matrix)
    rank_certificate = @basis.rank_certificate
    return false if !rank_certificate.verified?
    return false if rank_certificate.width != expected_dimension
    rank_certificate.rank == expected_dimension

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldSUnitSquareClassBasisCertificate(dim "
    text + @basis.expected_dimension.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSUnitSquareClassBasis
  -> new(@field, s_primes, generators,
         residue_characters = nil,
         archimedean_data = nil)
    if @field.class_name != "NumberField"
      raise "S-unit square-class basis needs a NumberField"
    invalid_arrays = s_primes.class_name != "Array"
    invalid_arrays = true if generators.class_name != "Array"
    if invalid_arrays
      raise "S-unit primes and generators must be Arrays"
    @s_primes = []
    s_primes.each -> (prime)
      @s_primes.push(prime)
    @generators = []
    generators.each -> (generator)
      @generators.push(@field.coerce(generator))
    @residue_characters = []
    if residue_characters != nil
      if residue_characters.class_name != "Array"
        raise "residue characters must be an Array"
      residue_characters.each -> (character)
        @residue_characters.push(character)
    @archimedean_data = archimedean_data
    if @archimedean_data == nil
      @archimedean_data = @field.archimedean_data
    @generator_fractional_ideals = []
    @generators.each -> (generator)
      if generator.zero?
        raise "zero cannot generate an S-unit square class"
      @generator_fractional_ideals.push(
        @field.principal_fractional_ideal(generator))
    @local_matrix = compute_local_matrix
    @rank_certificate = compute_rank_certificate
    @certificate_cache = NumberFieldSUnitSquareClassBasisCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "S-unit square-class basis failed certification"

  -> field
    @field

  -> s_primes
    out = []
    @s_primes.each -> (prime)
      out.push(prime)
    out

  -> generators
    out = []
    @generators.each -> (generator)
      out.push(generator)
    out

  -> residue_characters
    out = []
    @residue_characters.each -> (character)
      out.push(character)
    out

  -> archimedean_data
    @archimedean_data

  -> expected_dimension
    signature = @field.signature
    signature[0] + signature[1] + @s_primes.size

  -> dimension
    expected_dimension

  -> generator_fractional_ideals
    out = []
    @generator_fractional_ideals.each -> (ideal)
      out.push(ideal)
    out

  -> support_within_s?(fractional_ideal)
    factors = fractional_ideal.algebra_fractional_ideal.factors
    i = 0
    while i < factors.size
      supported = false
      j = 0
      while j < @s_primes.size
        if factors[i][0].eql?(
             @s_primes[j].algebra_prime_ideal)
          supported = true
        j += 1
      return false if !supported
      i += 1
    true

  -> s_unit_fractional_ideal(value)
    element = @field.coerce(value)
    raise "zero is not an S-unit" if element.zero?
    ideal = @field.principal_fractional_ideal(element)
    if !support_within_s?(ideal)
      raise "number-field element has valuation outside S"
    ideal

  -> s_unit?(value)
    answer = false
    begin
      s_unit_fractional_ideal(value)
      answer = true
    rescue error
      answer = false
    answer

  -> signature_vector_with_ideal(value, fractional_ideal)
    element = @field.coerce(value)
    vector = @archimedean_data.square_class_signature(element)
    @s_primes.each -> (prime)
      valuation = fractional_ideal.valuation(prime)
      vector.push(valuation.abs % 2)
    @residue_characters.each -> (character)
      vector.push(character.bit(element))
    vector

  -> signature_vector(value)
    element = @field.coerce(value)
    ideal = s_unit_fractional_ideal(element)
    signature_vector_with_ideal(element, ideal)

  # Rows are local homomorphisms; columns are the proposed generators.
  -> compute_local_matrix
    rows = []
    row_count = @archimedean_data.real_places.size
    row_count += @s_primes.size
    row_count += @residue_characters.size
    i = 0
    while i < row_count
      rows.push([])
      i += 1
    generator_index = 0
    while generator_index < @generators.size
      vector = signature_vector_with_ideal(
        @generators[generator_index],
        @generator_fractional_ideals[generator_index])
      i = 0
      while i < rows.size
        rows[i].push(vector[i])
        i += 1
      generator_index += 1
    rows

  -> local_matrix
    F2LinearAlgebra.copy_matrix(@local_matrix)

  -> compute_rank_certificate
    system = F2LinearSystem.new(@generators.size)
    @local_matrix.each -> (row)
      system.add_equation(row)
    system.certificate

  -> rank_certificate
    @rank_certificate

  # Unique coordinates of an S-unit class modulo squares.  Full column rank
  # makes the local signature map injective on the certified basis, while
  # Dirichlet's dimension theorem makes that basis exhaustive.
  -> coordinates(value)
    target = signature_vector(value)
    system = F2LinearSystem.new(@generators.size)
    i = 0
    while i < @local_matrix.size
      system.add_equation(@local_matrix[i], target[i])
      i += 1
    solution = system.solve
    if solution.inconsistent?
      raise "S-unit signature is outside the certified square-class basis"
    solution.particular_solution

  -> equivalent_mod_squares?(left, right)
    coordinates(left).to_s == coordinates(right).to_s

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "SUnitSquareClasses(" + @field.to_s + ", dim "
    text + dimension.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSUnitSquareClassBasisSearch
  -> new(@field, s_primes, generators,
         @auxiliary_prime_limit = 1_000,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000,
         archimedean_data = nil)
    if @field.class_name != "NumberField"
      raise "S-unit basis search needs a NumberField"
    if s_primes.class_name != "Array" || generators.class_name != "Array"
      raise "S-unit basis search primes and generators must be Arrays"
    if @auxiliary_prime_limit < 3
      raise "S-unit auxiliary prime limit must be at least three"
    @s_primes = []
    s_primes.each -> (prime)
      @s_primes.push(prime)
    @generators = []
    generators.each -> (generator)
      @generators.push(@field.coerce(generator))
    @archimedean_data = archimedean_data
    if @archimedean_data == nil
      @archimedean_data = @field.archimedean_data
    expected = @field.signature[0] + @field.signature[1]
    expected += @s_primes.size
    if @generators.size != expected
      raise "S-unit basis search has the wrong generator count"
    @generator_fractional_ideals = []
    @generators.each -> (generator)
      if generator.zero?
        raise "zero cannot generate an S-unit square class"
      ideal = @field.principal_fractional_ideal(generator)
      if !support_within_s?(ideal)
        raise "number-field element has valuation outside S"
      @generator_fractional_ideals.push(ideal)
    @residue_characters = []
    @local_rows = base_local_rows
    select_residue_characters
    @basis = NumberFieldSUnitSquareClassBasis.new(
      @field, @s_primes, @generators,
      @residue_characters, @archimedean_data)

  -> support_within_s?(fractional_ideal)
    factors = fractional_ideal.algebra_fractional_ideal.factors
    i = 0
    while i < factors.size
      supported = false
      j = 0
      while j < @s_primes.size
        if factors[i][0].eql?(
             @s_primes[j].algebra_prime_ideal)
          supported = true
        j += 1
      return false if !supported
      i += 1
    true

  -> base_local_rows
    rows = []
    row_count = @archimedean_data.real_places.size
    row_count += @s_primes.size
    row_count.times -> rows.push([])
    generator_index = 0
    while generator_index < @generators.size
      vector = @archimedean_data.square_class_signature(
        @generators[generator_index])
      prime_index = 0
      while prime_index < @s_primes.size
        valuation = @generator_fractional_ideals[
          generator_index].valuation(@s_primes[prime_index])
        vector.push(valuation.abs % 2)
        prime_index += 1
      row_index = 0
      while row_index < rows.size
        rows[row_index].push(vector[row_index])
        row_index += 1
      generator_index += 1
    rows

  -> matrix_rank(rows)
    system = F2LinearSystem.new(@generators.size)
    rows.each -> (row)
      system.add_equation(row)
    system.rank

  -> character_row(character)
    row = []
    @generators.each -> (generator)
      row.push(character.bit(generator))
    row

  -> s_rational_prime?(prime)
    index = 0
    while index < @s_primes.size
      return true if @s_primes[index].rational_prime == prime
      index += 1
    false

  -> try_character(prime_ideal)
    character = NumberFieldQuadraticResidueCharacter.new(
      prime_ideal)
    row = nil
    begin
      row = character_row(character)
    rescue error
      return false
    candidate_rows = F2LinearAlgebra.copy_matrix(
      @local_rows)
    candidate_rows.push(row)
    old_rank = matrix_rank(@local_rows)
    new_rank = matrix_rank(candidate_rows)
    return false if new_rank == old_rank
    @local_rows.push(row)
    @residue_characters.push(character)
    true

  -> select_residue_characters
    target = @generators.size
    return true if matrix_rank(@local_rows) == target
    rational_prime = 3
    while rational_prime <= @auxiliary_prime_limit
      if rational_prime.prime? && !s_rational_prime?(rational_prime)
        decomposition = @field.prime_ideals_above(
          rational_prime,
          @factor_search_limit,
          @generator_search_limit)
        decomposition_index = 0
        while decomposition_index < decomposition.size
          try_character(decomposition[decomposition_index])
          return true if matrix_rank(@local_rows) == target
          decomposition_index += 1
        return true if matrix_rank(@local_rows) == target
      rational_prime += 1
    message = "S-unit auxiliary character search limit exceeded; rank "
    message += matrix_rank(@local_rows).to_s
    raise message + " of " + target.to_s

  -> field
    @field

  -> s_primes
    out = []
    @s_primes.each -> (prime)
      out.push(prime)
    out

  -> generators
    out = []
    @generators.each -> (generator)
      out.push(generator)
    out

  -> residue_characters
    out = []
    @residue_characters.each -> (character)
      out.push(character)
    out

  -> local_rows
    F2LinearAlgebra.copy_matrix(@local_rows)

  -> basis
    @basis

  -> result
    @basis

  -> certificate
    @basis.certificate

  -> certified?
    @basis.certified?


+ NumberFieldIsomorphicSUnitSquareClassBasisCertificate
  -> new(@basis)
    @verified_cache = nil

  -> basis
    @basis

  -> theorem
    "field isomorphisms preserve localized unit square classes"

  -> theorem_reference
    "functoriality of O_K,S^*/O_K,S^{*2} under Q-algebra isomorphism"

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
    expected = "NumberFieldIsomorphicSUnitSquareClassBasis"
    return false if @basis.class_name != expected
    source = @basis.source_field
    model = @basis.model_field
    return false if source.class_name != "NumberField"
    return false if model.class_name != "NumberField"
    isomorphism = source.irreducibility_certificate
    expected_certificate = "NumberFieldIsomorphicModelIrreducibilityCertificate"
    return false if isomorphism.class_name != expected_certificate
    return false if !isomorphism.verified?
    return false if isomorphism.model_field != model
    model_basis = @basis.model_basis
    return false if model_basis.class_name != "NumberFieldSUnitSquareClassBasis"
    return false if model_basis.field != model
    return false if !model_basis.certificate.verified?
    rational_primes = @basis.rational_primes
    i = 0
    while i < rational_primes.size
      return false if !rational_primes[i].prime?
      j = 0
      while j < i
        return false if rational_primes[j] == rational_primes[i]
        j += 1
      i += 1
    expected_model_primes = primes_above(
      model, rational_primes)
    same_prime_sets?(
      expected_model_primes, model_basis.s_primes)

  -> certified?
    verified?


+ NumberFieldIsomorphicSUnitSquareClassBasis
  -> new(@source_field, rational_primes, @model_basis)
    if @source_field.class_name != "NumberField"
      raise "isomorphic S-unit basis needs a source number field"
    if rational_primes.class_name != "Array"
      raise "isomorphic S-unit rational primes must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    isomorphism = @source_field.irreducibility_certificate
    expected = "NumberFieldIsomorphicModelIrreducibilityCertificate"
    if isomorphism.class_name != expected
      raise "source field has no certified isomorphic model"
    @model_field = isomorphism.model_field
    @certificate_cache = NumberFieldIsomorphicSUnitSquareClassBasisCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "isomorphic S-unit square-class transfer failed certification"

  -> source_field
    @source_field

  -> field
    @source_field

  -> model_field
    @model_field

  -> model_basis
    @model_basis

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> dimension
    @model_basis.dimension

  -> source_to_model(value)
    element = @source_field.coerce(value)
    isomorphism = @source_field.irreducibility_certificate
    root = isomorphism.model_root
    result = @model_field.zero
    power = @model_field.one
    element.coefficients.each -> (coefficient)
      result += power * coefficient
      power *= root
    result

  -> coordinates(value)
    @model_basis.coordinates(
      source_to_model(value))

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ EtaleProductSUnitSquareClassQuotientCertificate
  -> new(@quotient)
    @verified_cache = nil

  -> quotient
    @quotient

  -> theorem
    "S-unit square classes commute with finite products, modulo diagonal rational S-units"

  -> theorem_reference
    "Bruin-Poonen-Stoll sections 10 and 12.6"

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

  -> expected_s_primes(field)
    out = []
    @quotient.rational_primes.each -> (rational_prime)
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
    expected = "EtaleProductSUnitSquareClassQuotient"
    return false if @quotient.class_name != expected
    order = @quotient.order
    return false if order.class_name != "EtaleProductOrder"
    return false if !order.certificate.verified?
    rational_primes = @quotient.rational_primes
    i = 0
    while i < rational_primes.size
      return false if !rational_primes[i].prime?
      j = 0
      while j < i
        return false if rational_primes[j] == rational_primes[i]
        j += 1
      i += 1

    nested = @quotient.component_bases
    return false if nested.size != order.component_count
    component_orders = order.component_orders
    ambient_dimension = 0
    component_index = 0
    while component_index < nested.size
      bases = nested[component_index]
      return false if bases.class_name != "Array" || bases.size == 0
      component_order = component_orders[component_index]
      if component_order.class_name == "MonogenicOrder"
        component_polynomial = component_order.source_polynomial.monic
      else
        component_polynomial = component_order.algebra.defining_polynomial.monic
      product = component_polynomial.ring.one
      i = 0
      while i < bases.size
        basis = bases[i]
        basis_class = basis.class_name
        ordinary = basis_class == "NumberFieldSUnitSquareClassBasis"
        transferred = basis_class == "NumberFieldIsomorphicSUnitSquareClassBasis"
        return false if !ordinary && !transferred
        return false if !basis.certificate.verified?
        field = basis.field
        polynomial = field.defining_polynomial
        return false if polynomial.ring != component_polynomial.ring
        j = 0
        while j < i
          previous = bases[j].field.defining_polynomial
          return false if polynomial.gcd(previous).degree != 0
          j += 1
        product *= polynomial.monic
        if ordinary
          expected_primes = expected_s_primes(field)
          return false if !same_prime_sets?(
            expected_primes, basis.s_primes)
        else
          expected_rational = @quotient.rational_primes
          return false if basis.rational_primes.to_s != expected_rational.to_s
        ambient_dimension += basis.dimension
        i += 1
      return false if !product.monic.eql?(component_polynomial)
      component_index += 1

    return false if ambient_dimension != @quotient.ambient_dimension
    matrix = @quotient.compute_diagonal_matrix
    return false if !F2LinearAlgebra.same_matrix?(
      matrix, @quotient.diagonal_matrix)
    certificate = @quotient.diagonal_rank_certificate
    return false if !certificate.verified?
    return false if certificate.width != ambient_dimension
    expected_dimension = ambient_dimension - certificate.rank
    @quotient.dimension == expected_dimension

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductSUnitSquareClassQuotientCertificate(dim "
    text + @quotient.dimension.to_s + ")"

  -> inspect
    to_s


+ EtaleProductSUnitSquareClassQuotient
  -> new(@order, rational_primes, component_bases)
    if @order.class_name != "EtaleProductOrder"
      raise "product S-unit quotient needs an EtaleProductOrder"
    if rational_primes.class_name != "Array"
      raise "product S-unit rational primes must be an Array"
    if component_bases.class_name != "Array"
      raise "product S-unit component bases must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    @component_bases = []
    component_bases.each -> (bases)
      if bases.class_name != "Array"
        raise "each etale component needs an Array of S-unit bases"
      copied = []
      bases.each -> (basis)
        copied.push(basis)
      @component_bases.push(copied)
    @ambient_dimension = 0
    @flat_bases = []
    @component_bases.each -> (bases)
      bases.each -> (basis)
        @flat_bases.push(basis)
        @ambient_dimension += basis.dimension
    @diagonal_matrix = compute_diagonal_matrix
    system = F2LinearSystem.new(@ambient_dimension)
    @diagonal_matrix.each -> (row)
      system.add_equation(row)
    @diagonal_rank_certificate = system.certificate
    @dimension = @ambient_dimension
    @dimension -= @diagonal_rank_certificate.rank
    @certificate_cache = EtaleProductSUnitSquareClassQuotientCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "product S-unit square-class quotient failed certification"

  -> order
    @order

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> component_bases
    out = []
    @component_bases.each -> (bases)
      copied = []
      bases.each -> (basis)
        copied.push(basis)
      out.push(copied)
    out

  -> flat_bases
    out = []
    @flat_bases.each -> (basis)
      out.push(basis)
    out

  -> ambient_dimension
    @ambient_dimension

  -> diagonal_generators
    generators = [-1]
    @rational_primes.each -> (prime)
      generators.push(prime)
    generators

  -> compute_diagonal_matrix
    rows = []
    diagonal_generators.each -> (generator)
      row = []
      @flat_bases.each -> (basis)
        coordinates = basis.coordinates(
          basis.field.coerce(generator))
        coordinates.each -> (bit)
          row.push(bit)
      rows.push(row)
    rows

  -> diagonal_matrix
    F2LinearAlgebra.copy_matrix(@diagonal_matrix)

  -> diagonal_rank_certificate
    @diagonal_rank_certificate

  -> diagonal_rank
    @diagonal_rank_certificate.rank

  -> dimension
    @dimension

  -> reduce_ambient_coordinates(vector)
    F2LinearAlgebra.validate_vector(
      vector, @ambient_dimension)
    work = F2LinearAlgebra.copy_vector(vector)
    rref = @diagonal_rank_certificate.rref
    pivots = @diagonal_rank_certificate.pivots
    row_index = 0
    while row_index < pivots.size
      pivot = pivots[row_index]
      if work[pivot] == 1
        column = 0
        while column < @ambient_dimension
          work[column] = work[column] ^ rref[row_index][column]
          column += 1
      row_index += 1
    out = []
    column = 0
    while column < @ambient_dimension
      out.push(work[column]) if !pivots.include?(column)
      column += 1
    out

  -> quotient_coordinates(vector)
    reduce_ambient_coordinates(vector)

  -> equivalent_mod_diagonal?(left, right)
    first = reduce_ambient_coordinates(left)
    second = reduce_ambient_coordinates(right)
    F2LinearAlgebra.same_vector?(first, second)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductSUnitSquareClassQuotient(dim "
    text + @dimension.to_s + ")"

  -> inspect
    to_s


+ NumberField
  -> s_unit_square_class_basis(
       s_primes, generators,
       residue_characters = nil,
       archimedean_data = nil)
    NumberFieldSUnitSquareClassBasis.new(
      self, s_primes, generators,
      residue_characters, archimedean_data)

  -> certify_s_unit_square_class_basis(
       s_primes, generators,
       auxiliary_prime_limit = 1_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000,
       archimedean_data = nil)
    NumberFieldSUnitSquareClassBasisSearch.new(
      self, s_primes, generators,
      auxiliary_prime_limit,
      factor_search_limit,
      generator_search_limit,
      archimedean_data).basis


+ EtaleProductOrder
  -> s_unit_square_class_quotient(
       rational_primes, component_bases)
    EtaleProductSUnitSquareClassQuotient.new(
      self, rational_primes, component_bases)
