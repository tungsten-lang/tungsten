# Exact finite normalization jets for plane curves.
#
# A LocalPlaneBranch is a sheet of a chosen coordinate projection. This layer
# rewrites each sheet as a primitive finite parameterization x=x0+t^e,
# y=y0+sum(a_k*t^k), verifies the substitution by exact coefficient-field
# arithmetic, and records the Newton--Puiseux theorem import needed to pass
# from projection sheets to geometric branches. It is finite jet data, not a
# construction of the complete local normalization ring.

use core/algebra/local_geometry

+ PlaneLocalGeometry
  # Remove a common power from x=t^e and every retained nonzero y exponent.
  # Newton characteristic exponents occur within the retained lift, so the
  # resulting finite parameterization is primitive for the resolved sheet.
  -> .parameter_divisor(series)
    divisor = series.ramification_index
    index = 1
    while index <= series.maximum_index
      coefficient = series.coefficient_index(index)
      if !Expression.zero_expression?(coefficient)
        divisor = FormalPuiseuxSeries.gcd(divisor, index)
      index += 1
    divisor

  # Return [divisor, primitive ramification, parameter order,
  # x(t), y(t), raw displacement coefficients].
  -> .local_parameter_data(sheet, parameter = :t)
    divisor = PlaneLocalGeometry.parameter_divisor(
      sheet.displacement_series)
    if divisor < 1
      raise "local parameter divisor must be positive"
    original_ramification = sheet.ramification_index
    if original_ramification % divisor != 0
      raise "local parameter divisor does not divide ramification"
    ramification = original_ramification / divisor
    maximum_index = sheet.displacement_series.maximum_index
    if maximum_index % divisor != 0
      raise "local parameter precision does not descend to primitive index"
    parameter_order = maximum_index / divisor
    field = sheet.coefficient_field
    source = PlaneLocalGeometry.field_coefficients(
      sheet.displacement_series, field, maximum_index)
    displacement = PlaneLocalGeometry.field_zeros(
      field, parameter_order + 1)
    index = 0
    while index <= maximum_index
      if !field.zero?(source[index])
        if index % divisor != 0
          raise "nonzero Puiseux exponent prevents parameter reduction"
        displacement[index / divisor] = source[index]
      index += 1

    x_coefficients = PlaneLocalGeometry.field_zeros(
      field, parameter_order + 1)
    x_coefficients[0] = field.embed_from(
      sheet.local_polynomial.ring.field, sheet.center_x)
    x_coefficients[ramification] = field.add(
      x_coefficients[ramification], field.one)

    y_coefficients = []
    displacement.each -> y_coefficients.push(item)
    y_coefficients[0] = field.add(
      y_coefficients[0],
      field.embed_from(
        sheet.local_polynomial.ring.field, sheet.center_y))

    [
      divisor,
      ramification,
      parameter_order,
      FormalPowerSeries.new(x_coefficients, parameter, 0),
      FormalPowerSeries.new(y_coefficients, parameter, 0),
      displacement]

  -> .same_newton_edge?(left, right)
    (left.left[0] == right.left[0] &&
     left.left[1] == right.left[1] &&
     left.right[0] == right.right[0] &&
     left.right[1] == right.right[1] &&
     left.characteristic_polynomial ==
       right.characteristic_polynomial)


+ LocalPlaneParametrizationCertificate
  -> new(@sheet, @parameter_divisor, @ramification_index,
         @parameter_order, @x_series, @y_series)
    @verified_cache = nil

  -> sheet
    @sheet

  -> x_series
    @x_series

  -> y_series
    @y_series

  -> parameter_divisor
    @parameter_divisor

  -> ramification_index
    @ramification_index

  -> parameter_order
    @parameter_order

  -> residual_coefficients
    data = PlaneLocalGeometry.local_parameter_data(
      @sheet, @x_series.variable)
    PlaneLocalGeometry.evaluate_field_local(
      @sheet.local_polynomial, @sheet.coefficient_field,
      data[1], data[5], data[2])

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
    return false if !@sheet.certificate.verified?
    expected = PlaneLocalGeometry.local_parameter_data(
      @sheet, @x_series.variable)
    return false if expected[0] != @parameter_divisor
    return false if expected[1] != @ramification_index
    return false if expected[2] != @parameter_order
    return false if expected[3] != @x_series
    return false if expected[4] != @y_series
    PlaneLocalGeometry.field_vanishes_through?(
      @sheet.coefficient_field,
      residual_coefficients, @parameter_order)

  -> certified?
    verified?

  -> arithmetic_replay_checked?
    verified?

  -> kernel_checked?
    true

  -> statement
    ("the displayed local parameterization solves the plane equation " +
     "through parameter order " + @parameter_order.to_s)


+ LocalPlaneParametrization
  -> new(@sheet, parameter = :t)
    data = PlaneLocalGeometry.local_parameter_data(
      @sheet, parameter)
    @parameter_divisor = data[0]
    @ramification_index = data[1]
    @parameter_order = data[2]
    @x_series = data[3]
    @y_series = data[4]
    @certificate = LocalPlaneParametrizationCertificate.new(
      @sheet, @parameter_divisor, @ramification_index,
      @parameter_order, @x_series, @y_series)
    if !@certificate.verified?
      raise "local parameterization certificate did not verify"

  -> sheet
    @sheet

  -> source_polynomial
    @sheet.source_polynomial

  -> coefficient_field
    @sheet.coefficient_field

  -> residue_degree
    @sheet.residue_degree

  -> parameter_divisor
    @parameter_divisor

  -> ramification_index
    @ramification_index

  -> parameter_order
    @parameter_order

  -> parameter
    @x_series.variable

  -> x_series
    @x_series

  -> y_series
    @y_series

  -> certificate
    @certificate

  -> primitive?
    divisor = @ramification_index
    index = 1
    while index <= @parameter_order
      if !Expression.zero_expression?(@y_series.coefficient(index))
        divisor = FormalPuiseuxSeries.gcd(divisor, index)
      index += 1
    divisor == 1

  # This is an orbit weight, not independently the number of branches in the
  # packet. The sum over a certified complete sheet cover is integral.
  -> geometric_branch_weight
    Rational.new(residue_degree, @ramification_index)

  -> to_s
    ("LocalPlaneParametrization(" +
     @sheet.x_variable.to_s + " = " +
     @x_series.to_expression.to_s + ", " +
     @sheet.y_variable.to_s + " = " +
     @y_series.to_expression.to_s + ")")

  -> inspect
    to_s


+ PlaneProjectionSheetCoverCertificate
  -> new(@local_polynomial, @sheets)
    @verified_cache = nil

  -> local_polynomial
    @local_polynomial

  -> sheets
    @sheets

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
    polygon = NewtonPolygon.new(@local_polynomial)
    matched = 0
    valid = true
    polygon.edges.each -> (edge)
      edge.factor_groups.each -> (group)
        factor = group[0]
        multiplicity = group[1]
        group_degree = 0
        group_count = 0
        @sheets.each -> (sheet)
          if (sheet.local_polynomial == @local_polynomial &&
              sheet.certificate.verified? &&
              PlaneLocalGeometry.same_newton_edge?(
                sheet.edge, edge))
            certificate = sheet.certificate
            belongs = false
            if (certificate.class_name ==
                "RecursiveLocalPlaneBranchCertificate")
              belongs = certificate.initial_factor == factor
            else
              belongs = certificate.defining_factor == factor
            if belongs
              group_count += 1
              group_degree += sheet.residue_degree
        valid = false if group_count == 0
        valid = false if (
          group_degree != factor.degree*multiplicity)
        if multiplicity == 1
          valid = false if group_count != 1
        else
          # Recursive repeated factors are currently supported only when
          # rational linear; the child certificates account for all leaves.
          valid = false if factor.degree != 1
        matched += group_count
    valid && matched == @sheets.size

  -> certified?
    verified?

  -> arithmetic_replay_checked?
    verified?

  -> kernel_checked?
    true

  -> statement
    "the displayed sheets cover every resolved Newton-edge factor"


+ PlaneCurveLocalNormalizationCertificate
  -> new(@local_polynomial, @sheets, @parametrizations,
         @sheet_cover_certificate, @branch_weight)
    @verified_cache = nil

  -> local_polynomial
    @local_polynomial

  -> sheets
    @sheets

  -> parametrizations
    @parametrizations

  -> sheet_cover_certificate
    @sheet_cover_certificate

  -> branch_weight
    @branch_weight

  -> theorem
    ("Newton-Puiseux root-of-unity orbits identify primitive " +
     "projection sheets with normalized geometric branches")

  -> theorem_reference
    "classical Newton-Puiseux theorem and parameter-orbit formula"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

  -> verify!
    return false if !@sheet_cover_certificate.verified?
    return false if @sheets.size != @parametrizations.size
    weight = Rational.new(0)
    index = 0
    while index < @sheets.size
      parameterization = @parametrizations[index]
      return false if parameterization.sheet != @sheets[index]
      return false if !parameterization.certificate.verified?
      weight += parameterization.geometric_branch_weight
      index += 1
    weight == @branch_weight && weight.denominator == 1

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

  -> geometric_branch_count
    if !verified?
      raise "local normalization certificate did not verify"
    @branch_weight.numerator

  -> statement
    ("the finite normalization packets represent exactly " +
     geometric_branch_count.to_s + " geometric branches")


+ PlaneCurveLocalNormalization
  -> new(@source_polynomial, @x_variable = 0, @y_variable = 1,
         point = nil, maximum_power = 6,
         search_margin = 0, recursion_limit = 8,
         parameter = :t)
    @point = point == nil ? [0, 0] : point
    if @point.class_name != "Array" || @point.size != 2
      raise "plane normalization point must have two coordinates"
    @local_polynomial = @source_polynomial.local_plane_polynomial(
      @x_variable, @y_variable, @point)
    @sheets = @source_polynomial.puiseux_sheets(
      @x_variable, @y_variable, @point,
      maximum_power, search_margin, recursion_limit)
    @parametrizations = []
    @sheets.each ->
      @parametrizations.push(
        LocalPlaneParametrization.new(item, parameter))
    @sheet_cover_certificate = (
      PlaneProjectionSheetCoverCertificate.new(
        @local_polynomial, @sheets))
    branch_weight = Rational.new(0)
    @parametrizations.each ->
      branch_weight += item.geometric_branch_weight
    @certificate = PlaneCurveLocalNormalizationCertificate.new(
      @local_polynomial, @sheets, @parametrizations,
      @sheet_cover_certificate, branch_weight)
    if !@certificate.verified?
      raise "local normalization certificate did not verify"
    @singularity = @source_polynomial.local_singularity(
      @x_variable, @y_variable, @point)
    @local_delta_invariant = nil

  -> source_polynomial
    @source_polynomial

  -> local_polynomial
    @local_polynomial

  -> point
    @point

  -> x_variable
    @x_variable

  -> y_variable
    @y_variable

  -> projection_sheets
    @sheets

  -> parametrizations
    @parametrizations

  -> parameterization_packets
    @parametrizations

  -> sheet_cover_certificate
    @sheet_cover_certificate

  -> certificate
    @certificate

  -> singularity
    @singularity

  -> geometric_branch_count
    @certificate.geometric_branch_count

  -> branch_count
    geometric_branch_count

  -> finite_jet?
    true

  -> complete_local_ring?
    false

  -> to_s
    ("PlaneCurveLocalNormalization(branches=" +
     geometric_branch_count.to_s + ", packets=" +
     @parametrizations.size.to_s + ")")

  -> inspect
    to_s


+ Polynomial
  -> local_normalization(x_variable = 0, y_variable = 1,
                          point = nil, maximum_power = 6,
                          search_margin = 0,
                          recursion_limit = 8,
                          parameter = :t)
    PlaneCurveLocalNormalization.new(
      self, x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)

  -> local_normalization_data(x_variable = 0, y_variable = 1,
                               point = nil, maximum_power = 6,
                               search_margin = 0,
                               recursion_limit = 8,
                               parameter = :t)
    local_normalization(
      x_variable, y_variable, point, maximum_power,
      search_margin, recursion_limit, parameter)


+ AffineChart
  -> local_normalization(point, maximum_power = 6,
                          search_margin = 0,
                          recursion_limit = 8,
                          parameter = :t)
    if point.class_name != "Array" || point.size != 2
      raise "affine local point must have two coordinates"
    indices = local_coordinate_indices
    @equation.local_normalization(
      indices[0], indices[1], point,
      maximum_power, search_margin,
      recursion_limit, parameter)

  -> local_normalization_data(point, maximum_power = 6,
                               search_margin = 0,
                               recursion_limit = 8,
                               parameter = :t)
    local_normalization(
      point, maximum_power, search_margin,
      recursion_limit, parameter)


+ Curve
  -> local_normalization(point, chart = nil,
                          maximum_power = 6,
                          search_margin = 0,
                          recursion_limit = 8,
                          parameter = :t)
    affine_chart(chart).local_normalization(
      point, maximum_power, search_margin,
      recursion_limit, parameter)

  -> local_normalization_data(point, chart = nil,
                               maximum_power = 6,
                               search_margin = 0,
                               recursion_limit = 8,
                               parameter = :t)
    local_normalization(
      point, chart, maximum_power, search_margin,
      recursion_limit, parameter)


+ Algebra
  -> .local_normalization(polynomial, x_variable = 0,
                           y_variable = 1, point = nil,
                           maximum_power = 6,
                           search_margin = 0,
                           recursion_limit = 8,
                           parameter = :t)
    polynomial.local_normalization(
      x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)

  -> .local_normalization_data(polynomial, x_variable = 0,
                                y_variable = 1, point = nil,
                                maximum_power = 6,
                                search_margin = 0,
                                recursion_limit = 8,
                                parameter = :t)
    Algebra.local_normalization(
      polynomial, x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)
