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


# A line-presented closed point has exact coordinates over its residue
# extension, but evaluating every bitangent function in a tensor product
# L_i tensor K is unnecessary. If g(t) is the monic residue polynomial and
# h(t) is a restricted line, Res(g,h) is the norm of h at that closed point.
# This keeps the result directly in the bitangent field L_i.
+ PlaneQuarticBPSClosedPlaceArithmetic
  -> .number_field_form(field, target_space, coefficients)
    if coefficients.class_name != "Array" || coefficients.size != 3
      raise "closed-place BPS line needs three coefficients"
    terms = []
    index = 0
    while index < coefficients.size
      source = coefficients[index]
      if source.class_name != "EtaleAlgebraElement"
        raise "closed-place BPS coefficient is outside its etale component"
      exponents = [0, 0, 0]
      exponents[index] = 1
      terms.push([
        field.coerce(source.coefficients),
        exponents
      ])
      index += 1
    Polynomial.new(target_space.ring, terms)

  -> .number_field_line(place, field, target_space)
    coefficients = []
    place.line.coefficients.each -> (coefficient)
      coefficients.push(
        field.embed_from(place.curve.field, coefficient))
    Line.raw(target_space, coefficients)

  -> .component_value(function, basis, place)
    if place.class_name != "ClosedPlace" || !place.certified?
      raise "closed-place BPS evaluation needs a certified closed place"
    field = basis.field
    if field.class_name != "NumberField"
      raise "closed-place BPS evaluation needs a number-field S-unit basis"
    if !PlaneQuarticBPSPointDifferenceArithmetic.same_univariate_polynomial?(
           function.algebra.defining_polynomial,
           field.defining_polynomial)
      raise "closed-place BPS evaluation changes its bitangent field"
    target_space = ProjectiveSpace<NumberField, 2>.new(
      field, 2, place.space.coordinate_names)
    target_line = number_field_line(
      place, field, target_space)
    numerator_form = number_field_form(
      field, target_space,
      function.numerator_coefficients)
    denominator_form = number_field_form(
      field, target_space,
      function.denominator_coefficients)
    numerator = target_line.affine_restriction(
      numerator_form, place.parameter_chart)
    denominator = target_line.affine_restriction(
      denominator_form, place.parameter_chart)
    factor = place.defining_polynomial.change_ring(
      numerator.ring)
    numerator_norm = factor.resultant(numerator)
    denominator_norm = factor.resultant(denominator)
    if field.zero?(numerator_norm)
      raise "closed place meets a zero of a BPS function"
    if field.zero?(denominator_norm)
      raise "closed place meets a pole of a BPS function"
    numerator_norm / denominator_norm

  -> .component_values(function_data, space, place)
    functions = function_data.function_components
    nested = space.component_bases
    if functions.size != nested.size
      raise "closed-place BPS component count mismatch"
    out = []
    index = 0
    while index < functions.size
      bases = nested[index]
      if bases.size != 1
        raise "closed-place BPS evaluation currently needs one field basis per etale component"
      out.push(component_value(
        functions[index], bases[0], place))
      index += 1
    out

  -> .quotient_values(function_data, space,
                      positive, negative)
    positive_values = component_values(
      function_data, space, positive)
    negative_values = component_values(
      function_data, space, negative)
    out = []
    index = 0
    while index < positive_values.size
      out.push(
        positive_values[index] / negative_values[index])
      index += 1
    out

  -> .coordinate_certificates(
       space, s_class_two_torsion_proof,
       component_values)
    nested = space.component_bases
    if component_values.size != nested.size
      raise "closed-place BPS coordinate component count mismatch"
    expected_proof = "EtaleProductSClassTwoTorsionProof"
    if s_class_two_torsion_proof.class_name != expected_proof
      raise "closed-place BPS coordinates need a product S-class proof"
    if !s_class_two_torsion_proof.certificate.verified?
      raise "closed-place BPS product S-class proof is uncertified"
    proof_nested = s_class_two_torsion_proof.component_proofs
    if proof_nested.size != nested.size
      raise "closed-place BPS S-class component count mismatch"
    out = []
    index = 0
    while index < nested.size
      bases = nested[index]
      proofs = proof_nested[index]
      if bases.size != 1
        raise "closed-place BPS coordinates currently need one field basis per etale component"
      if proofs.size != 1
        raise "closed-place BPS coordinates currently need one S-class proof per etale component"
      out.push(
        bases[0].l2s_coordinates_with_certificate(
          component_values[index],
          proofs[0]))
      index += 1
    out

  -> .coordinates_from_certificates(
       space, component_values, certificates)
    nested = space.component_bases
    return nil if component_values.size != nested.size
    return nil if certificates.size != nested.size
    out = []
    index = 0
    while index < nested.size
      bases = nested[index]
      return nil if bases.size != 1
      proof = certificates[index]
      return nil if !proof.certificate.verified?
      return nil if proof.basis != bases[0]
      return nil if proof.value != component_values[index]
      proof.vector.each -> out.push(item)
      index += 1
    return nil if out.size != space.dimension
    F2LinearAlgebra.validate_vector(
      out, space.dimension)
    out


+ PlaneQuarticBPSClosedPlaceDifferenceCertificate
  -> new(@descent_value)
    @verified_cache = nil

  -> theorem
    "the BPS explicit map evaluates a closed divisor by residue-field norms; for a line-presented place these norms are exact resultants"

  -> theorem_reference
    "Bruin-Poonen-Stoll sections 6.4-6.5 and the resultant norm identity"

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
    expected = "PlaneQuarticBPSClosedPlaceDifferenceDescentValue"
    return false if @descent_value.class_name != expected
    data = @descent_value.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    space = @descent_value.space
    return false if space.class_name != (
      "EtaleProductSUnitSquareClassSpace")
    return false if !space.certificate.verified?
    if !PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
         data, space)
      return false
    s_class_proof = (
      @descent_value.s_class_two_torsion_proof)
    return false if s_class_proof.class_name != (
      "EtaleProductSClassTwoTorsionProof")
    return false if !s_class_proof.certificate.verified?
    return false if s_class_proof.order != space.order
    return false if s_class_proof.rational_primes.to_s != (
      space.rational_primes.to_s)
    positive = @descent_value.positive_place
    negative = @descent_value.negative_place
    return false if positive.class_name != "ClosedPlace"
    return false if negative.class_name != "ClosedPlace"
    return false if !positive.certified? || !negative.certified?
    return false if positive.curve != data.curve
    return false if negative.curve != data.curve
    return false if positive.degree != negative.degree
    expected_values = (
      PlaneQuarticBPSClosedPlaceArithmetic.quotient_values(
        data, space, positive, negative))
    supplied_values = @descent_value.component_values
    return false if expected_values.size != supplied_values.size
    index = 0
    while index < expected_values.size
      return false if expected_values[index] != (
        supplied_values[index])
      index += 1
    coordinates = (
      PlaneQuarticBPSClosedPlaceArithmetic.coordinates_from_certificates(
          space, expected_values,
          @descent_value.coordinate_certificates))
    return false if coordinates == nil
    return false if !F2LinearAlgebra.same_vector?(
      coordinates, @descent_value.coordinates)
    norm_vector = space.norm_map.apply(coordinates)
    return false if !F2LinearAlgebra.same_vector?(
      norm_vector, @descent_value.norm_vector)
    F2LinearAlgebra.zero_vector?(norm_vector)

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_closed_divisor_map_with_exact_resultant_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> known_jacobian_image_element?
    verified?


+ PlaneQuarticBPSClosedPlaceDifferenceDescentValue
  -> new(@function_data, @space,
         @s_class_two_torsion_proof,
         @positive_place,
         @negative_place)
    if @function_data.class_name != (
         "PlaneQuarticBPSFunctionData")
      raise "closed-place BPS difference needs certified function data"
    if !@function_data.certificate.verified?
      raise "closed-place BPS function data is uncertified"
    if @space.class_name != (
         "EtaleProductSUnitSquareClassSpace")
      raise "closed-place BPS difference needs a product S-unit space"
    if !@space.certificate.verified?
      raise "closed-place BPS S-unit space is uncertified"
    expected_proof = "EtaleProductSClassTwoTorsionProof"
    if @s_class_two_torsion_proof.class_name != expected_proof
      raise "closed-place BPS difference needs a product S-class proof"
    if !@s_class_two_torsion_proof.certificate.verified?
      raise "closed-place BPS product S-class proof is uncertified"
    if @s_class_two_torsion_proof.order != @space.order
      raise "closed-place BPS S-class proof changes the etale order"
    if @s_class_two_torsion_proof.rational_primes.to_s != (
         @space.rational_primes.to_s)
      raise "closed-place BPS S-class proof changes S"
    if !PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
           @function_data, @space)
      raise "closed-place BPS space changes the etale components"
    if @positive_place.class_name != "ClosedPlace"
      raise "closed-place BPS positive term is not a closed place"
    if @negative_place.class_name != "ClosedPlace"
      raise "closed-place BPS negative term is not a closed place"
    if !@positive_place.certified? || !@negative_place.certified?
      raise "closed-place BPS difference contains an uncertified place"
    if @positive_place.curve != @function_data.curve
      raise "closed-place BPS positive term changes the curve"
    if @negative_place.curve != @function_data.curve
      raise "closed-place BPS negative term changes the curve"
    if @positive_place.degree != @negative_place.degree
      raise "closed-place BPS difference must have degree zero"
    @component_values = (
      PlaneQuarticBPSClosedPlaceArithmetic.quotient_values(
        @function_data, @space,
        @positive_place, @negative_place))
    @coordinate_certificates = (
      PlaneQuarticBPSClosedPlaceArithmetic.coordinate_certificates(
          @space, @s_class_two_torsion_proof,
          @component_values))
    @coordinates = (
      PlaneQuarticBPSClosedPlaceArithmetic.coordinates_from_certificates(
          @space, @component_values,
          @coordinate_certificates))
    if @coordinates == nil
      raise "closed-place BPS coordinate certificates do not replay"
    @norm_vector = @space.norm_map.apply(
      @coordinates)
    if !F2LinearAlgebra.zero_vector?(@norm_vector)
      raise "closed-place BPS value violates the global norm condition"
    @certificate_cache = (
      PlaneQuarticBPSClosedPlaceDifferenceCertificate.new(
        self))
    if !@certificate_cache.verified?
      raise "closed-place BPS descent value failed certification"

  -> function_data
    @function_data

  -> space
    @space

  -> s_class_two_torsion_proof
    @s_class_two_torsion_proof

  -> positive_place
    @positive_place

  -> negative_place
    @negative_place

  -> component_values
    out = []
    @component_values.each -> out.push(item)
    out

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
+ PlaneQuarticBPSKnownLocalImageCertificate
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
    image_class = @image.class_name
    supported_image = image_class == "PlaneQuarticBPSKnownLocalImage"
    supported_image = true if image_class == "PlaneQuarticBPSKnownOddLocalImage"
    return false if !supported_image
    local_map = @image.local_map
    map_class = local_map.class_name
    supported_map = map_class == "EtaleProductOddLocalSquareClassMap"
    supported_map = true if map_class == "EtaleProductDyadicLocalSquareClassMap"
    return false if !supported_map
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
    :global_to_local_functoriality_exact_span

  -> arithmetic_replay_checked?
    true

  -> lower_bound_checked?
    true

  -> complete_local_image_checked?
    false

  -> kernel_checked?
    false


+ PlaneQuarticBPSKnownLocalImage
  -> new(@local_map, global_values)
    map_class = @local_map.class_name
    supported = map_class == "EtaleProductOddLocalSquareClassMap"
    supported = true if map_class == "EtaleProductDyadicLocalSquareClassMap"
    if !supported
      raise "known local image needs a product localization map"
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
    @certificate_cache = PlaneQuarticBPSKnownLocalImageCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "known local image failed certification"

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


+ PlaneQuarticBPSKnownOddLocalImage < PlaneQuarticBPSKnownLocalImage


+ PlaneQuarticBPSKnownOddLocalImageCertificate < PlaneQuarticBPSKnownLocalImageCertificate


+ PlaneQuarticBPSFunctionData
  -> certify_point_difference(space, positive, negative)
    PlaneQuarticBPSPointDifferenceDescentValue.new(
      self, space, positive, negative)

  -> certify_closed_place_difference(
       space, s_class_two_torsion_proof,
       positive, negative)
    PlaneQuarticBPSClosedPlaceDifferenceDescentValue.new(
      self, space, s_class_two_torsion_proof,
      positive, negative)


+ PlaneQuarticTwoDescentSetup
  -> certify_point_difference_descent_value(positive, negative)
    if @bps_function_data == nil
      raise "certify BPS divisor/function data before evaluating point differences"
    if @s_unit_square_class_space == nil
      raise "certify the true S-unit square-class space before evaluating point differences"
    @bps_function_data.certify_point_difference(
      @s_unit_square_class_space,
      positive, negative)

  -> certify_closed_place_difference_descent_value(
       positive, negative)
    if @bps_function_data == nil
      raise "certify BPS divisor/function data before evaluating closed-place differences"
    if @s_unit_square_class_space == nil
      raise "certify the true S-unit square-class space before evaluating closed-place differences"
    @bps_function_data.certify_closed_place_difference(
      @s_unit_square_class_space,
      @s_class_two_torsion_proof,
      positive, negative)


+ EtaleProductOddLocalSquareClassMap
  -> certify_known_jacobian_image(global_values)
    PlaneQuarticBPSKnownOddLocalImage.new(
      self, global_values)


+ EtaleProductDyadicLocalSquareClassMap
  -> certify_known_jacobian_image(global_values)
    PlaneQuarticBPSKnownLocalImage.new(
      self, global_values)
