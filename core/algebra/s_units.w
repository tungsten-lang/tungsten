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
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
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


+ NumberField
  -> s_unit_square_class_basis(
       s_primes, generators,
       residue_characters = nil,
       archimedean_data = nil)
    NumberFieldSUnitSquareClassBasis.new(
      self, s_primes, generators,
      residue_characters, archimedean_data)
