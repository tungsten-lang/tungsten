# Exact local intersection multiplicities from normalization packets.
#
# Each target germ is substituted into every primitive source
# parameterization. The first nonzero exact coefficient gives its parameter
# valuation. Finite substitution is replay-checked; summing valuations over
# normalized geometric branches is recorded as a classical theorem import.

use core/algebra/local_invariants

+ PlaneLocalGeometry
  -> .same_field_coefficients?(coefficient_field, left, right)
    return false if left.size != right.size
    index = 0
    while index < left.size
      return false if !coefficient_field.equal?(
        left[index], right[index])
      index += 1
    true


+ LocalPlaneParametrizationIntersectionCertificate
  -> new(@parametrization, @target_local_polynomial,
         @residual_coefficients, @valuation)
    @verified_cache = nil

  -> parametrization
    @parametrization

  -> target_local_polynomial
    @target_local_polynomial

  -> residual_coefficients
    @residual_coefficients

  -> valuation
    @valuation

  -> proof_kind
    :exact_parameter_substitution

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
    return false if !@parametrization.certificate.verified?
    sheet = @parametrization.sheet
    data = PlaneLocalGeometry.local_parameter_data(
      sheet, @parametrization.parameter)
    expected = PlaneLocalGeometry.evaluate_field_local(
      @target_local_polynomial,
      @parametrization.coefficient_field,
      data[1], data[5], data[2])
    return false if !PlaneLocalGeometry.same_field_coefficients?(
      @parametrization.coefficient_field,
      expected, @residual_coefficients)
    expected_valuation = PlaneLocalGeometry.field_valuation(
      @parametrization.coefficient_field, expected)
    return false if expected_valuation == nil
    expected_valuation == @valuation

  -> certified?
    verified?

  -> statement
    ("the target germ has parameter valuation " +
     @valuation.to_s + " on the displayed normalization packet")


+ LocalPlaneParametrizationIntersection
  -> new(@parametrization, @target_local_polynomial)
    if (@target_local_polynomial.ring !=
        @parametrization.sheet.local_polynomial.ring)
      raise "local intersection equations use different local rings"
    sheet = @parametrization.sheet
    data = PlaneLocalGeometry.local_parameter_data(
      sheet, @parametrization.parameter)
    @residual_coefficients = (
      PlaneLocalGeometry.evaluate_field_local(
        @target_local_polynomial,
        @parametrization.coefficient_field,
        data[1], data[5], data[2]))
    @valuation = PlaneLocalGeometry.field_valuation(
      @parametrization.coefficient_field,
      @residual_coefficients)
    if @valuation == nil
      raise (
        "target vanishes through the retained normalization order; " +
        "increase maximum_power or test for a common component")
    @certificate = (
      LocalPlaneParametrizationIntersectionCertificate.new(
        @parametrization, @target_local_polynomial,
        @residual_coefficients, @valuation))
    if !@certificate.verified?
      raise "local parameter-intersection certificate did not verify"

  -> parametrization
    @parametrization

  -> target_local_polynomial
    @target_local_polynomial

  -> residual_coefficients
    @residual_coefficients

  -> valuation
    @valuation

  -> geometric_contribution
    (@parametrization.geometric_branch_weight*
     Rational.new(@valuation))

  -> certificate
    @certificate

  -> to_s
    ("LocalPlaneParametrizationIntersection(valuation=" +
     @valuation.to_s + ", contribution=" +
     geometric_contribution.to_s + ")")

  -> inspect
    to_s


+ PlaneCurveLocalIntersectionCertificate
  -> new(@normalization, @target_local_polynomial,
         @packet_intersections, @multiplicity)
    @verified_cache = nil

  -> normalization
    @normalization

  -> target_local_polynomial
    @target_local_polynomial

  -> packet_intersections
    @packet_intersections

  -> multiplicity
    @multiplicity

  -> theorem
    ("local intersection multiplicity is the sum of target-function " +
     "valuations on normalized geometric branches")

  -> theorem_reference
    "classical branch-valuation formula for plane-curve intersections"

  -> theorem_dependencies
    [@normalization.certificate.theorem, theorem]

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

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
    return false if !@normalization.certificate.verified?
    parameters = @normalization.parametrizations
    return false if parameters.size != @packet_intersections.size
    total = Rational.new(0)
    index = 0
    while index < parameters.size
      intersection = @packet_intersections[index]
      return false if (
        intersection.parametrization != parameters[index])
      return false if (
        intersection.target_local_polynomial !=
          @target_local_polynomial)
      return false if !intersection.certificate.verified?
      total += intersection.geometric_contribution
      index += 1
    return false if total.denominator != 1
    total.numerator == @multiplicity

  -> certified?
    verified?

  -> statement
    ("the two local plane germs have intersection multiplicity " +
     @multiplicity.to_s)


+ PlaneCurveLocalIntersection
  -> new(@normalization, @target_polynomial,
         target_x_variable = nil,
         target_y_variable = nil)
    x_variable = (
      target_x_variable == nil ?
      @normalization.x_variable : target_x_variable)
    y_variable = (
      target_y_variable == nil ?
      @normalization.y_variable : target_y_variable)
    point = @normalization.point
    @target_local_polynomial = (
      PlaneLocalGeometry.translated_polynomial(
        @target_polynomial, x_variable, y_variable,
        point[0], point[1]))
    @packet_intersections = []
    @normalization.parametrizations.each ->
      @packet_intersections.push(
        LocalPlaneParametrizationIntersection.new(
          item, @target_local_polynomial))
    total = Rational.new(0)
    @packet_intersections.each ->
      total += item.geometric_contribution
    if total.denominator != 1
      raise "local intersection packet sum was not integral"
    @multiplicity = total.numerator
    @certificate = PlaneCurveLocalIntersectionCertificate.new(
      @normalization, @target_local_polynomial,
      @packet_intersections, @multiplicity)
    if !@certificate.verified?
      raise "local intersection certificate did not verify"

  -> normalization
    @normalization

  -> source_polynomial
    @normalization.source_polynomial

  -> target_polynomial
    @target_polynomial

  -> target_local_polynomial
    @target_local_polynomial

  -> point
    @normalization.point

  -> packet_intersections
    @packet_intersections

  -> multiplicity
    @multiplicity

  -> intersection_multiplicity
    @multiplicity

  -> certificate
    @certificate

  -> to_s
    ("PlaneCurveLocalIntersection(multiplicity=" +
     @multiplicity.to_s + ")")

  -> inspect
    to_s


+ PlaneCurveLocalNormalization
  -> intersection_with(target_polynomial,
                        target_x_variable = nil,
                        target_y_variable = nil)
    PlaneCurveLocalIntersection.new(
      self, target_polynomial,
      target_x_variable, target_y_variable)


+ Polynomial
  -> local_intersection(other, x_variable = 0,
                         y_variable = 1, point = nil,
                         maximum_power = 6,
                         search_margin = 0,
                         recursion_limit = 8,
                         parameter = :t)
    normalization = local_normalization(
      x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)
    normalization.intersection_with(
      other, x_variable, y_variable)

  -> local_intersection_multiplicity(other, x_variable = 0,
                                      y_variable = 1,
                                      point = nil,
                                      maximum_power = 6,
                                      search_margin = 0,
                                      recursion_limit = 8,
                                      parameter = :t)
    local_intersection(
      other, x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter).multiplicity


+ Curve
  -> local_intersection(other, point, chart = nil,
                         maximum_power = 6,
                         search_margin = 0,
                         recursion_limit = 8,
                         parameter = :t)
    source_chart = affine_chart(chart)
    target_chart = other.affine_chart(chart)
    indices = source_chart.local_coordinate_indices
    normalization = source_chart.equation.local_normalization(
      indices[0], indices[1], point,
      maximum_power, search_margin,
      recursion_limit, parameter)
    normalization.intersection_with(
      target_chart.equation, indices[0], indices[1])

  -> local_intersection_multiplicity(other, point,
                                      chart = nil,
                                      maximum_power = 6,
                                      search_margin = 0,
                                      recursion_limit = 8,
                                      parameter = :t)
    local_intersection(
      other, point, chart, maximum_power,
      search_margin, recursion_limit,
      parameter).multiplicity


+ Algebra
  -> .local_intersection(left, right,
                          x_variable = 0,
                          y_variable = 1,
                          point = nil,
                          maximum_power = 6,
                          search_margin = 0,
                          recursion_limit = 8,
                          parameter = :t)
    left.local_intersection(
      right, x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)

  -> .local_intersection_multiplicity(
       left, right, x_variable = 0,
       y_variable = 1, point = nil,
       maximum_power = 6,
       search_margin = 0,
       recursion_limit = 8,
       parameter = :t)
    Algebra.local_intersection(
      left, right, x_variable, y_variable,
      point, maximum_power, search_margin,
      recursion_limit, parameter).multiplicity
