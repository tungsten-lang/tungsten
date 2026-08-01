# Exact global norm maps for finite S-unit square-class spaces.
#
# Arithmetic in this file constructs the homomorphism
#
#   N : L(2,S) -> Q(S,2)
#
# on certified component bases.  Applying its kernel to a plane-quartic
# descent is a separate theorem step: PlaneQuarticBPSNormConstraintCertificate
# checks the true BPS setup and records Lemma 6.16 as a trusted theorem import.

+ RationalSUnitSquareClassSpaceCertificate
  -> new(@space)

  -> space
    @space

  -> proof_kind
    :exact_rational_square_classes

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    verified?

  -> verified?
    return false if @space.class_name != "RationalSUnitSquareClassSpace"
    primes = @space.rational_primes
    return false if @space.dimension != primes.size + 1
    i = 0
    while i < primes.size
      return false if !primes[i].prime?
      j = 0
      while j < i
        return false if primes[j] == primes[i]
        j += 1
      i += 1
    expected = []
    @space.dimension.times -> (row)
      vector = []
      @space.dimension.times -> (column)
        vector.push(row == column ? 1 : 0)
      expected.push(vector)
    F2LinearAlgebra.same_matrix?(
      @space.generator_coordinates, expected)

  -> certified?
    verified?


# Q(S,2) = <-1,S> inside Q^x/Q^{x2}.  Coordinates accept square factors away
# from S but reject an odd outside valuation instead of silently discarding it.
+ RationalSUnitSquareClassSpace
  -> new(rational_primes)
    if rational_primes.class_name != "Array"
      raise "rational S-unit primes must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    @dimension = @rational_primes.size + 1
    @certificate_cache = RationalSUnitSquareClassSpaceCertificate.new(self)
    if !@certificate_cache.verified?
      raise "rational S-unit square-class space failed certification"

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> generators
    out = [-1]
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> dimension
    @dimension

  -> generator_coordinates
    out = []
    @dimension.times -> (row)
      vector = []
      @dimension.times -> (column)
        vector.push(row == column ? 1 : 0)
      out.push(vector)
    out

  -> coordinates(value)
    rational = Rational.coerce(value)
    raise "zero has no rational square class" if rational.zero?
    numerator = rational.numerator
    denominator = rational.denominator
    sign = numerator < 0 ? 1 : 0
    numerator = numerator.abs
    out = [sign]
    @rational_primes.each -> (prime)
      parity = 0
      while numerator % prime == 0
        numerator = numerator / prime
        parity = parity ^ 1
      while denominator % prime == 0
        denominator = denominator / prime
        parity = parity ^ 1
      out.push(parity)
    numerator_root = numerator.isqrt
    denominator_root = denominator.isqrt
    outside_square = numerator_root * numerator_root == numerator
    outside_square = false if denominator_root * denominator_root != denominator
    if !outside_square
      raise "rational square class is ramified outside S"
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "RationalSUnitSquareClassSpace(dim " + @dimension.to_s + ")"

  -> inspect
    to_s


+ EtaleProductSUnitNormArithmetic
  -> .field_and_generators(basis)
    if basis.class_name == "NumberFieldSUnitSquareClassBasis"
      return [basis.field, basis.generators]
    if basis.class_name == "NumberFieldIsomorphicSUnitSquareClassBasis"
      model_basis = basis.model_basis
      return [model_basis.field, model_basis.generators]
    raise "unsupported S-unit basis in norm map"

  -> .matrix(source, target)
    rows = []
    target.dimension.times ->
      row = []
      source.dimension.times -> row.push(0)
      rows.push(row)
    column = 0
    source.flat_bases.each -> (basis)
      data = EtaleProductSUnitNormArithmetic.field_and_generators(
        basis)
      field = data[0]
      generators = data[1]
      if generators.size != basis.dimension
        raise "S-unit basis dimension disagrees with its generators"
      generators.each -> (generator)
        norm = field.norm(generator)
        coordinates = target.coordinates(norm)
        row = 0
        while row < target.dimension
          rows[row][column] = coordinates[row]
          row += 1
        column += 1
    if column != source.dimension
      raise "norm matrix does not cover the source basis"
    rows


+ EtaleProductSUnitNormMapCertificate
  -> new(@norm_map)
    @verified_cache = nil

  -> norm_map
    @norm_map

  -> proof_kind
    :exact_norm_matrix

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    verified?

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
    expected = "EtaleProductSUnitNormMap"
    return false if @norm_map.class_name != expected
    source = @norm_map.source
    target = @norm_map.target
    return false if source.class_name != "EtaleProductSUnitSquareClassSpace"
    return false if !source.certificate.verified?
    return false if target.class_name != "RationalSUnitSquareClassSpace"
    return false if !target.certificate.verified?
    return false if source.rational_primes.to_s != target.rational_primes.to_s
    matrix = EtaleProductSUnitNormArithmetic.matrix(source, target)
    return false if !F2LinearAlgebra.same_matrix?(
      matrix, @norm_map.matrix)
    certificate = @norm_map.kernel_certificate
    return false if !certificate.verified?
    return false if certificate.width != source.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      certificate.matrix, matrix)
    right = certificate.source_right_hand_side
    i = 0
    while i < right.size
      return false if right[i] != 0
      i += 1
    true

  -> certified?
    verified?


+ EtaleProductSUnitNormMap
  -> new(@source)
    if @source.class_name != "EtaleProductSUnitSquareClassSpace"
      raise "S-unit norm map needs a true product square-class space"
    if !@source.certificate.verified?
      raise "S-unit norm map source is uncertified"
    @target = RationalSUnitSquareClassSpace.new(
      @source.rational_primes)
    @matrix = EtaleProductSUnitNormArithmetic.matrix(
      @source, @target)
    system = F2LinearSystem.new(@source.dimension)
    @matrix.each -> (row)
      system.add_equation(row)
    @kernel_certificate = system.certificate
    @certificate_cache = EtaleProductSUnitNormMapCertificate.new(self)
    if !@certificate_cache.verified?
      raise "S-unit norm map failed certification"

  -> source
    @source

  -> target
    @target

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> kernel_certificate
    @kernel_certificate

  -> kernel_dimension
    @kernel_certificate.kernel_dimension

  -> kernel_basis
    @kernel_certificate.kernel_basis

  -> apply(vector)
    F2LinearAlgebra.validate_vector(
      vector, @source.dimension)
    out = []
    @matrix.each -> (row)
      value = 0
      column = 0
      while column < row.size
        value = value ^ (row[column] * vector[column])
        column += 1
      out.push(value)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSNormConstraintCertificate
  -> new(@constraint)
    @verified_cache = nil

  -> constraint
    @constraint

  -> theorem
    "the true plane-quartic descent image lies in the norm-one square classes"

  -> theorem_reference
    "Bruin-Poonen-Stoll Lemma 6.16, via the section 6.5 true setup"

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
    expected = "PlaneQuarticBPSNormConstraint"
    return false if @constraint.class_name != expected
    setup = @constraint.setup
    return false if setup.class_name != "PlaneQuarticTwoDescentSetup"
    return false if !setup.true_setup? || !setup.certified?
    class_proof = @constraint.s_class_two_torsion_proof
    return false if class_proof == nil
    return false if !class_proof.certificate.verified?
    source = @constraint.source
    return false if source == nil || !source.certificate.verified?
    return false if class_proof.order != source.order
    if class_proof.rational_primes.to_s != (
         source.rational_primes.to_s)
      return false
    function_data = setup.bps_function_data
    return false if function_data == nil
    return false if !function_data.certificate.verified?
    source_components = source.order.component_orders
    function_components = (
      function_data.etale_algebra.component_polynomials)
    return false if source_components.size != (
      function_components.size)
    i = 0
    while i < source_components.size
      order = source_components[i]
      polynomial = order.algebra.defining_polynomial
      if order.class_name == "MonogenicOrder"
        polynomial = order.source_polynomial
      transported = RationalUnivariatePolynomialTransport.into(
        polynomial, function_components[i].ring)
      return false if transported == nil
      return false if !transported.monic.eql?(
        function_components[i].monic)
      i += 1
    norm_map = @constraint.norm_map
    return false if norm_map.source != source
    return false if !norm_map.certificate.verified?
    true

  -> verify_selmer_constraint(name, width, matrix, right_hand_side)
    return false if name.to_s != "global norm"
    return false if width != @constraint.norm_map.source.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      matrix, @constraint.matrix)
    return false if right_hand_side.size != matrix.size
    i = 0
    while i < right_hand_side.size
      return false if right_hand_side[i] != 0
      i += 1
    true

  -> certified?
    verified?


+ PlaneQuarticBPSNormConstraint
  -> new(@setup)
    @source = @setup.s_unit_square_class_space
    @s_class_two_torsion_proof = (
      @setup.s_class_two_torsion_proof)
    initialize_norm_constraint

  -> new(@setup, @source, @s_class_two_torsion_proof)
    initialize_norm_constraint

  -> initialize_norm_constraint
    @norm_map = EtaleProductSUnitNormMap.new(
      @source)
    @certificate_cache = PlaneQuarticBPSNormConstraintCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "plane-quartic BPS norm constraint failed certification"
    self

  -> setup
    @setup

  -> source
    @source

  -> s_class_two_torsion_proof
    @s_class_two_torsion_proof

  -> norm_map
    @norm_map

  -> matrix
    @norm_map.matrix

  -> dimension
    @norm_map.kernel_dimension

  -> basis
    @norm_map.kernel_basis

  -> constraint_block
    right = []
    matrix.size.times -> right.push(0)
    SelmerConstraintBlock.new(
      "global norm", @norm_map.source.dimension,
      matrix, right, certificate)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ EtaleProductSUnitSquareClassSpace
  -> norm_map
    EtaleProductSUnitNormMap.new(self)


+ PlaneQuarticTwoDescentSetup
  -> certify_global_norm_condition
    if @s_unit_square_class_space == nil
      raise "certify the true S-unit square-class space before the global norm condition"
    if !true_setup? || !certified?
      raise "certify the BPS divisor and function data before the global norm condition"
    @global_norm_constraint = PlaneQuarticBPSNormConstraint.new(self)
    @global_norm_constraint

  -> global_norm_constraint
    @global_norm_constraint

  # Bind a certified isomorphic presentation of the bitangent fields.  This
  # is needed when local BPS function evaluation uses the raw bitangent
  # generator while integral/maximal-order arithmetic uses a scaled one.
  -> certify_global_norm_condition(
       source, s_class_two_torsion_proof)
    @global_norm_constraint = PlaneQuarticBPSNormConstraint.new(
      self, source, s_class_two_torsion_proof)
    @global_norm_constraint
