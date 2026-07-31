# Focused regular-model certificates for bad reduction of plane quartics.
#
# The first implemented shape is an integral smooth rational plane quartic
# whose special fiber has one rational A2 cusp and whose arithmetic surface is
# already regular there. The finite checks identify the unique geometric
# singularity, replay the cusp coefficients, count the genus-two normalization
# over F_p and F_(p^2), and bound the local 2-quotient through the Neron model.

+ PlaneQuarticCuspidalModelArithmetic
  -> .copy_generators(ideal)
    out = []
    ideal.source_generators.each -> out.push(item)
    out

  -> .certified_unit_ideal(generators)
    ideal = Ideal.new(generators)
    basis = ideal.certified_groebner_basis
    basis.membership_certificate(ideal.ring.one)

  -> .support_power_certificate(ideal, polynomial,
                                maximum_exponent = 8)
    exponent = 1
    while exponent <= maximum_exponent
      power = polynomial**exponent
      if ideal.contains?(power)
        basis = ideal.certified_groebner_basis
        return [
          exponent,
          basis.membership_certificate(power)]
      exponent += 1
    raise "singular-locus support power was not found"

  -> .two_adic_valuation(value)
    if value <= 0
      raise "2-adic group-order valuation needs a positive integer"
    valuation = 0
    while value % 2 == 0
      value /= 2
      valuation += 1
    valuation

  -> .normalization_zeta_data(reduction)
    q = reduction.field.order
    first_count = reduction.point_count
    second_count = reduction.extension_curve(2).point_count
    first_power_sum = q + 1 - first_count
    second_power_sum = q**2 + 1 - second_count
    c1 = 0 - first_power_sum
    numerator = first_power_sum**2 - second_power_sum
    if numerator % 2 != 0
      raise "genus-two zeta recurrence was not integral"
    c2 = numerator / 2
    coefficients = [1, c1, c2, q*c1, q**2]
    order = 0
    coefficients.each -> order += item
    [first_count, second_count, coefficients, order]


+ PlaneQuarticCuspidalLocalDimensionCertificate
  -> new(@model)
    @verified_cache = nil
    @diagnostic_stage = :not_started

  -> diagnostic_stage
    @diagnostic_stage

  -> theorem
    "a regular irreducible cuspidal special fiber bounds the odd local 2-quotient by the 2-primary order of its normalization Jacobian"

  -> theorem_reference
    "A2 cusp normalization, generalized Jacobians, Raynaud's component group, prime-to-p Neron specialization, and p-adic Lie-group multiplication by two"

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
    @diagnostic_stage = :model
    expected = "PlaneQuarticCuspidalRegularModel"
    return false if @model.class_name != expected
    curve = @model.curve
    return false if curve.field.class_name != "RationalField"
    return false if curve.degree != 4 || !curve.nonsingular?
    return false if curve.genus != 3
    @diagnostic_stage = :reduction
    prime = @model.prime
    return false if prime <= 3 || !prime.prime?
    reduction = @model.reduction_curve
    expected_reduction = curve.reduce(prime)
    return false if !reduction.equation.eql?(
      expected_reduction.equation)

    point = @model.singular_point
    return false if point.space != reduction.space
    return false if !reduction.contains?(point)
    return false if PadicCurveSpecialFiberArithmetic.smooth?(
      reduction, point)
    @diagnostic_stage = :singular_support
    chart = @model.chart
    return false if reduction.field.zero?(
      point.coordinates[chart])

    @model.empty_complement_certificates.each -> (certificate)
      return false if !certificate.verified?
      return false if !certificate.polynomial.one?
    support = @model.support_certificates
    coordinate_indices = @model.local_coordinate_indices
    return false if support.size != coordinate_indices.size
    index = 0
    while index < support.size
      entry = support[index]
      return false if entry.size != 2
      exponent = entry[0]
      certificate = entry[1]
      return false if exponent < 1 || exponent > 8
      return false if !certificate.verified?
      coordinate_index = coordinate_indices[index]
      coordinate = reduction.space.coords[coordinate_index]
      point_coordinate = point.coordinates[coordinate_index]
      expected_power = (
        coordinate - point_coordinate)**exponent
      return false if certificate.polynomial != expected_power
      index += 1

    @diagnostic_stage = :cusp
    local = reduction.singularity_at(
      point.dehomogenize(chart), chart)
    return false if local.local_polynomial != (
      @model.local_singularity.local_polynomial)
    return false if local.multiplicity != 2
    return false if local.tangent_direction_count != 1
    cone = local.tangent_cone
    tangent_index = @model.tangent_variable_index
    transverse_index = 1 - tangent_index
    tangent_square = [0, 0]
    tangent_square[tangent_index] = 2
    tangent_coefficient = cone.coeff(tangent_square)
    return false if reduction.field.zero?(tangent_coefficient)
    cone.each_term -> (coefficient, exponents)
      if exponents.to_s != tangent_square.to_s
        return false if !reduction.field.zero?(coefficient)
    @diagnostic_stage = :total_space
    cusp_exponents = [0, 0]
    cusp_exponents[transverse_index] = 3
    cusp_coefficient = local.local_polynomial.coeff(
      cusp_exponents)
    return false if reduction.field.zero?(cusp_coefficient)

    source_value = curve.equation.evaluate(
      point.coordinates)
    return false if source_value != @model.source_value
    valuation = PadicField.new(prime, 4).coerce(
      source_value).valuation
    return false if valuation != 1
    return false if valuation != @model.source_value_valuation

    @diagnostic_stage = :normalization_zeta
    data = PlaneQuarticCuspidalModelArithmetic.normalization_zeta_data(
      reduction)
    return false if data[0] != @model.normalization_point_count
    return false if data[1] != @model.normalization_extension_point_count
    return false if data[2].to_s != (
      @model.normalization_zeta_coefficients.to_s)
    return false if data[3] != @model.normalization_jacobian_order
    two_part = PlaneQuarticCuspidalModelArithmetic.two_adic_valuation(
      data[3])
    return false if two_part != @model.dimension_upper_bound
    @diagnostic_stage = :complete
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_cuspidal_regular_model_local_bound

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> singular_locus_replayed?
    true

  -> total_space_regularity_replayed?
    true

  -> normalization_zeta_replayed?
    true

  -> local_dimension_bound_checked?
    verified?


+ PlaneQuarticCuspidalRegularModel
  -> new(@curve, @prime, singular_coordinates)
    if @curve.class_name != "Curve"
      raise "cuspidal regular model needs a Curve"
    if @curve.field.class_name != "RationalField"
      raise "cuspidal regular model currently needs a rational curve"
    if @curve.degree != 4 || !@curve.nonsingular?
      raise "cuspidal regular model needs a smooth rational plane quartic"
    if @prime <= 3 || !@prime.prime?
      raise "focused cuspidal regular model needs an odd prime above 3"
    @reduction_curve = @curve.reduce(@prime)
    @singular_point = @reduction_curve.space.point(
      singular_coordinates)
    if PadicCurveSpecialFiberArithmetic.smooth?(
         @reduction_curve, @singular_point)
      raise "supplied special-fiber point is smooth"

    @chart = 0
    while @reduction_curve.field.zero?(
            @singular_point.coordinates[@chart])
      @chart += 1
    @local_coordinate_indices = []
    index = 0
    while index < @reduction_curve.space.coordinate_count
      @local_coordinate_indices.push(index) if index != @chart
      index += 1
    @local_singularity = @reduction_curve.singularity_at(
      @singular_point.dehomogenize(@chart), @chart)
    if @local_singularity.multiplicity != 2
      raise "focused bad fiber is not a double point"
    cone = @local_singularity.tangent_cone
    first = cone.coeff([2, 0])
    second = cone.coeff([0, 2])
    mixed = cone.coeff([1, 1])
    field = @reduction_curve.field
    if (!field.zero?(first) &&
        field.zero?(second) &&
        field.zero?(mixed))
      @tangent_variable_index = 0
    elsif (field.zero?(first) &&
           !field.zero?(second) &&
           field.zero?(mixed))
      @tangent_variable_index = 1
    else
      raise "focused cusp needs a coordinate-axis double tangent"
    transverse = 1 - @tangent_variable_index
    cusp_exponents = [0, 0]
    cusp_exponents[transverse] = 3
    if field.zero?(
         @local_singularity.local_polynomial.coeff(
           cusp_exponents))
      raise "focused double tangent is not an A2 cusp"

    singular_ideal = @reduction_curve.singular_locus
    ring = @reduction_curve.space.ring
    pivot = ring.generator(@chart)
    @empty_complement_certificates = []
    @local_coordinate_indices.each -> (coordinate_index)
      generators = (
        PlaneQuarticCuspidalModelArithmetic.copy_generators(
          singular_ideal))
      generators.push(pivot)
      generators.push(ring.generator(coordinate_index) - 1)
      @empty_complement_certificates.push(
        PlaneQuarticCuspidalModelArithmetic.certified_unit_ideal(
          generators))

    affine_generators = (
      PlaneQuarticCuspidalModelArithmetic.copy_generators(
        singular_ideal))
    affine_generators.push(pivot - 1)
    affine_ideal = Ideal.new(affine_generators)
    @support_certificates = []
    @local_coordinate_indices.each -> (coordinate_index)
      coordinate = ring.generator(coordinate_index)
      point_coordinate = (
        @singular_point.coordinates[coordinate_index])
      @support_certificates.push(
        PlaneQuarticCuspidalModelArithmetic.support_power_certificate(
          affine_ideal, coordinate - point_coordinate))

    @source_value = @curve.equation.evaluate(
      @singular_point.coordinates)
    @source_value_valuation = PadicField.new(
      @prime, 4).coerce(@source_value).valuation
    if @source_value_valuation != 1
      raise "cuspidal plane model is not regular at the special point"

    zeta = PlaneQuarticCuspidalModelArithmetic.normalization_zeta_data(
      @reduction_curve)
    @normalization_point_count = zeta[0]
    @normalization_extension_point_count = zeta[1]
    @normalization_zeta_coefficients = zeta[2]
    @normalization_jacobian_order = zeta[3]
    @dimension_upper_bound = (
      PlaneQuarticCuspidalModelArithmetic.two_adic_valuation(
        @normalization_jacobian_order))
    @certificate_cache = (
      PlaneQuarticCuspidalLocalDimensionCertificate.new(self))
    if !@certificate_cache.verified?
      raise ("cuspidal regular-model certificate did not verify at " +
             @certificate_cache.diagnostic_stage.to_s)

  -> curve
    @curve

  -> prime
    @prime

  -> reduction_curve
    @reduction_curve

  -> singular_point
    @singular_point

  -> chart
    @chart

  -> local_coordinate_indices
    out = []
    @local_coordinate_indices.each -> out.push(item)
    out

  -> local_singularity
    @local_singularity

  -> tangent_variable_index
    @tangent_variable_index

  -> empty_complement_certificates
    out = []
    @empty_complement_certificates.each -> out.push(item)
    out

  -> support_certificates
    out = []
    @support_certificates.each -> out.push(item)
    out

  -> source_value
    @source_value

  -> source_value_valuation
    @source_value_valuation

  -> normalization_genus
    2

  -> normalization_point_count
    @normalization_point_count

  -> normalization_extension_point_count
    @normalization_extension_point_count

  -> normalization_zeta_coefficients
    out = []
    @normalization_zeta_coefficients.each -> out.push(item)
    out

  -> normalization_zeta_numerator
    IntegerPolynomial.new(
      @normalization_zeta_coefficients)

  -> normalization_jacobian_order
    @normalization_jacobian_order

  -> dimension_upper_bound
    @dimension_upper_bound

  -> rational_prime
    @prime

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ Curve
  -> certify_cuspidal_regular_model(prime,
                                     singular_coordinates)
    PlaneQuarticCuspidalRegularModel.new(
      self, prime, singular_coordinates)
