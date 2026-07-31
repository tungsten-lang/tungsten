# Certified BPS descent values of rational point differences.
#
# For a true plane-quartic setup with functions f_l = l/l_0, the divisor
# class [P-Q] maps to f(P)/f(Q) in the finite etale square-class target. Exact
# point evaluation and S-unit coordinates are replayed here. The connecting
# explicit-descent theorem is named rather than claimed as a kernel proof.

+ PlaneQuarticBPSPointDifferenceArithmetic
  -> .same_univariate_polynomial?(left, right)
    return false if left.degree != right.degree
    left_coefficients = left.monic.coefficients
    right_coefficients = right.monic.coefficients
    return false if left_coefficients.size != right_coefficients.size
    index = 0
    while index < left_coefficients.size
      return false if left_coefficients[index] != right_coefficients[index]
      index += 1
    true

  -> .point(function_data, value)
    curve = function_data.curve
    if value.class_name == "ProjectivePoint"
      if value.space != curve.space
        raise "BPS point difference changes projective space"
      if !curve.contains?(value)
        raise "BPS point difference contains an off-curve point"
      return value
    if value.class_name != "Array"
      raise "BPS point difference needs projective points or coordinates"
    point = curve.space.point(value)
    if !curve.contains?(point)
      raise "BPS point difference contains off-curve coordinates"
    point

  -> .same_component_polynomials?(function_data, space)
    source = function_data.etale_algebra.component_polynomials
    target = space.order.component_orders
    return false if source.size != target.size
    index = 0
    while index < source.size
      order = target[index]
      polynomial = nil
      if order.class_name == "MonogenicOrder"
        polynomial = order.source_polynomial
      else
        polynomial = order.algebra.defining_polynomial
      return false if !same_univariate_polynomial?(
        source[index], polynomial)
      index += 1
    true

  -> .coordinate_certificates(space, etale_value)
    if etale_value.class_name != "EtaleAlgebraElement"
      raise "BPS point difference needs an etale-algebra value"
    components = etale_value.components
    nested = space.component_bases
    if components.size != nested.size
      raise "BPS point difference component count mismatch"
    out = []
    component_index = 0
    while component_index < components.size
      component = components[component_index]
      bases = nested[component_index]
      bases.each -> (basis)
        field = basis.field
        field_value = field.coerce(
          component.polynomial.coefficients)
        out.push(
          basis.coordinates_with_certificate(
            field_value))
      component_index += 1
    out

  -> .coordinates_from_certificates(
       space, etale_value, certificates)
    components = etale_value.components
    nested = space.component_bases
    out = []
    proof_index = 0
    component_index = 0
    while component_index < components.size
      component = components[component_index]
      bases = nested[component_index]
      basis_index = 0
      while basis_index < bases.size
        basis = bases[basis_index]
        if proof_index >= certificates.size
          raise "BPS point-difference coordinate proof count mismatch"
        proof = certificates[proof_index]
        return nil if !proof.certificate.verified?
        return nil if proof.basis != basis
        expected_value = basis.field.coerce(
          component.polynomial.coefficients)
        return nil if proof.value != expected_value
        proof.vector.each -> out.push(item)
        proof_index += 1
        basis_index += 1
      component_index += 1
    return nil if proof_index != certificates.size
    if out.size != space.dimension
      raise "BPS point-difference coordinates have the wrong dimension"
    F2LinearAlgebra.validate_vector(
      out, space.dimension)
    out

  -> .coordinates(space, etale_value)
    proofs = coordinate_certificates(
      space, etale_value)
    coordinates_from_certificates(
      space, etale_value, proofs)


+ PlaneQuarticBPSPointDifferenceCertificate
  -> new(@descent_value)
    @verified_cache = nil

  -> theorem
    "the BPS explicit map sends [P-Q] to the square class f(P)/f(Q)"

  -> theorem_reference
    "Bruin-Poonen-Stoll sections 6.4-6.5"

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
    expected = "PlaneQuarticBPSPointDifferenceDescentValue"
    return false if @descent_value.class_name != expected
    data = @descent_value.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    space = @descent_value.space
    return false if space.class_name != "EtaleProductSUnitSquareClassSpace"
    return false if !space.certificate.verified?
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      data, space)
    return false if !compatible
    positive = @descent_value.positive_point
    negative = @descent_value.negative_point
    return false if positive.space != data.curve.space
    return false if negative.space != data.curve.space
    return false if !data.curve.contains?(positive)
    return false if !data.curve.contains?(negative)
    positive_value = data.evaluate(positive)
    negative_value = data.evaluate(negative)
    return false if !positive_value.unit? || !negative_value.unit?
    expected_value = positive_value / negative_value
    return false if expected_value != @descent_value.etale_value
    coordinates = PlaneQuarticBPSPointDifferenceArithmetic.coordinates_from_certificates(
      space, expected_value,
      @descent_value.coordinate_certificates)
    return false if coordinates == nil
    return false if !F2LinearAlgebra.same_vector?(
      coordinates, @descent_value.coordinates)
    norm_map = space.norm_map
    norm_vector = norm_map.apply(coordinates)
    return false if !F2LinearAlgebra.same_vector?(
      norm_vector, @descent_value.norm_vector)
    F2LinearAlgebra.zero_vector?(norm_vector)

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_explicit_map_with_exact_evaluation_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> known_jacobian_image_element?
    verified?


+ PlaneQuarticBPSPointDifferenceDescentValue
  -> new(@function_data, @space, positive, negative)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "BPS point difference needs certified function data"
    if !@function_data.certificate.verified?
      raise "BPS point-difference function data is uncertified"
    if @space.class_name != "EtaleProductSUnitSquareClassSpace"
      raise "BPS point difference needs a product S-unit space"
    if !@space.certificate.verified?
      raise "BPS point-difference S-unit space is uncertified"
    if !PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
         @function_data, @space)
      raise "BPS point-difference space changes the etale components"
    @positive_point = PlaneQuarticBPSPointDifferenceArithmetic.point(
      @function_data, positive)
    @negative_point = PlaneQuarticBPSPointDifferenceArithmetic.point(
      @function_data, negative)
    positive_value = @function_data.evaluate(
      @positive_point)
    negative_value = @function_data.evaluate(
      @negative_point)
    if !positive_value.unit? || !negative_value.unit?
      raise "BPS point difference meets a zero or pole of the function family"
    @etale_value = positive_value / negative_value
    @coordinate_certificates = PlaneQuarticBPSPointDifferenceArithmetic.coordinate_certificates(
      @space, @etale_value)
    @coordinates = PlaneQuarticBPSPointDifferenceArithmetic.coordinates_from_certificates(
      @space, @etale_value,
      @coordinate_certificates)
    if @coordinates == nil
      raise "BPS point-difference coordinate certificates do not replay"
    @norm_vector = @space.norm_map.apply(
      @coordinates)
    if !F2LinearAlgebra.zero_vector?(@norm_vector)
      raise "BPS point-difference value violates the global norm condition"
    @certificate_cache = PlaneQuarticBPSPointDifferenceCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "BPS point-difference descent value failed certification"

  -> function_data
    @function_data

  -> space
    @space

  -> positive_point
    @positive_point

  -> negative_point
    @negative_point

  -> etale_value
    @etale_value

  -> coordinate_certificates
    out = []
    @coordinate_certificates.each -> out.push(item)
    out

  -> coordinates
    F2LinearAlgebra.copy_vector(@coordinates)

  -> norm_vector
    F2LinearAlgebra.copy_vector(@norm_vector)

  -> zero_class?
    F2LinearAlgebra.zero_vector?(@coordinates)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


# Rational divisor differences provide a replayable lower bound for a local
# Jacobian image. They cannot prove that the displayed span is the complete
# local image; callers must not use this object as a Selmer upper bound.
+ PlaneQuarticBPSKnownOddLocalImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "restriction sends rational Jacobian classes into the odd local Jacobian image"

  -> theorem_reference
    "functoriality of the BPS descent map under Q -> Q_p"

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
    expected = "PlaneQuarticBPSKnownOddLocalImage"
    return false if @image.class_name != expected
    local_map = @image.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    values = @image.global_values
    vectors = @image.vectors
    return false if values.size != vectors.size
    index = 0
    while index < values.size
      value = values[index]
      return false if value.class_name != "PlaneQuarticBPSPointDifferenceDescentValue"
      return false if !value.certificate.verified?
      return false if value.space != local_map.source
      expected_vector = local_map.apply(
        value.coordinates)
      return false if !F2LinearAlgebra.same_vector?(
        expected_vector, vectors[index])
      index += 1
    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, vectors)
    return false if !span.source_right_hand_side.all? -> item == 0
    return false if span.rank != @image.dimension
    basis = @image.basis
    return false if basis.size != span.rank
    reduced = span.rref
    index = 0
    while index < basis.size
      return false if !F2LinearAlgebra.same_vector?(
        basis[index], reduced[index])
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_global_to_local_functoriality_with_exact_span_replay

  -> arithmetic_replay_checked?
    true

  -> lower_bound_checked?
    true

  -> complete_local_image_checked?
    false

  -> kernel_checked?
    false


+ PlaneQuarticBPSKnownOddLocalImage
  -> new(@local_map, global_values)
    expected = "EtaleProductOddLocalSquareClassMap"
    if @local_map.class_name != expected
      raise "known local image needs an odd product localization map"
    if !@local_map.certificate.verified?
      raise "known local image has an uncertified localization map"
    if global_values.class_name != "Array"
      raise "known local image needs an array of global BPS values"
    @global_values = []
    @vectors = []
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    global_values.each -> (value)
      value_class = "PlaneQuarticBPSPointDifferenceDescentValue"
      if value.class_name != value_class
        raise "known local image needs certified BPS point differences"
      if !value.certificate.verified?
        raise "known local image contains an uncertified BPS value"
      if value.space != @local_map.source
        raise "known local image changes the global S-unit space"
      vector = @local_map.apply(value.coordinates)
      @global_values.push(value)
      @vectors.push(vector)
      system.add_equation(vector)
    @span_certificate = system.certificate
    @certificate_cache = PlaneQuarticBPSKnownOddLocalImageCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "known odd local image failed certification"

  -> local_map
    @local_map

  -> rational_prime
    @local_map.rational_prime

  -> global_values
    out = []
    @global_values.each -> out.push(item)
    out

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> dimension
    @span_certificate.rank

  -> basis
    out = []
    reduced = @span_certificate.rref
    index = 0
    while index < @span_certificate.rank
      out.push(F2LinearAlgebra.copy_vector(
        reduced[index]))
      index += 1
    out

  -> span_certificate
    @span_certificate

  -> lower_bound_only?
    true

  -> complete?
    false

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSFunctionData
  -> certify_point_difference(space, positive, negative)
    PlaneQuarticBPSPointDifferenceDescentValue.new(
      self, space, positive, negative)


+ PlaneQuarticTwoDescentSetup
  -> certify_point_difference_descent_value(positive, negative)
    if @bps_function_data == nil
      raise "certify BPS divisor/function data before evaluating point differences"
    if @s_unit_square_class_space == nil
      raise "certify the true S-unit square-class space before evaluating point differences"
    @bps_function_data.certify_point_difference(
      @s_unit_square_class_space,
      positive, negative)


+ EtaleProductOddLocalSquareClassMap
  -> certify_known_jacobian_image(global_values)
    PlaneQuarticBPSKnownOddLocalImage.new(
      self, global_values)
