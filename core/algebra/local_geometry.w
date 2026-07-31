# Exact local geometry for plane equations.
#
# Newton polygons identify rational candidate valuations for y(x) at a chosen
# point. Nondegenerate rational characteristic roots lift by exact Newton
# iteration in FormalPuiseuxSeries. Certificates replay the supporting-edge
# arithmetic and verify the substituted equation through the requested order.

use core/algebra/polynomial_factor
use core/algebra/curves
use core/calculus/puiseux

+ PlaneLocalGeometry
  -> .variable_index(polynomial, variable)
    index = (
      variable.class_name == "Integer" ?
      variable : polynomial.ring.index_of(variable))
    if index == nil || index < 0 || index >= polynomial.ring.arity
      raise "unknown local-geometry variable"
    index

  -> .translated_polynomial(polynomial, x_variable, y_variable,
                            center_x, center_y)
    x_index = PlaneLocalGeometry.variable_index(
      polynomial, x_variable)
    y_index = PlaneLocalGeometry.variable_index(
      polynomial, y_variable)
    raise "local plane variables must be distinct" if x_index == y_index
    index = 0
    while index < polynomial.ring.arity
      if (index != x_index && index != y_index &&
          polynomial.degree_in(index) != 0)
        raise "local plane equation depends on an unselected variable"
      index += 1

    names = [
      polynomial.ring.names[x_index],
      polynomial.ring.names[y_index]]
    local_ring = PolynomialRing.new(
      names, polynomial.ring.field, polynomial.ring.order)
    variables = local_ring.generators
    u = variables[0]
    v = variables[1]
    result = local_ring.zero
    polynomial.each_term -> (coefficient, exponents)
      term = local_ring.constant(coefficient)
      term *= (u + center_x)**exponents[x_index]
      term *= (v + center_y)**exponents[y_index]
      result += term
    result

  -> .zero_coefficients(maximum_index)
    out = []
    index = 0
    while index <= maximum_index
      out.push(Expression.constant(0))
      index += 1
    out

  -> .coordinate_series(variable, center, maximum_power,
                         ramification_index)
    maximum_index = maximum_power*ramification_index
    coefficients = PlaneLocalGeometry.zero_coefficients(maximum_index)
    coefficients[ramification_index] = Expression.constant(1)
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index, variable, center)

  -> .leading_series(variable, center, maximum_power,
                      ramification_index, leading_index,
                      leading_coefficient)
    maximum_index = maximum_power*ramification_index
    if leading_index > maximum_index
      raise "branch leading exponent exceeds requested precision"
    coefficients = PlaneLocalGeometry.zero_coefficients(maximum_index)
    coefficients[leading_index] = (
      Expression.constant(leading_coefficient))
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index, variable, center)

  -> .series_powers(series, maximum_degree, maximum_power)
    powers = [
      FormalPuiseuxSeries.constant(
        1, maximum_power, series.variable, series.center,
        series.ramification_index)]
    degree = 1
    while degree <= maximum_degree
      powers.push(powers[degree - 1]*series)
      degree += 1
    powers

  -> .evaluate(polynomial, x_series, y_series, maximum_power)
    pair = x_series.common_ramification(y_series)
    x_value = pair[0]
    y_value = pair[1]
    if polynomial.ring.arity != 2
      raise "local series evaluation requires a bivariate polynomial"
    x_powers = PlaneLocalGeometry.series_powers(
      x_value, polynomial.degree_in(0), maximum_power)
    y_powers = PlaneLocalGeometry.series_powers(
      y_value, polynomial.degree_in(1), maximum_power)
    result = FormalPuiseuxSeries.constant(
      0, maximum_power, x_value.variable, x_value.center,
      x_value.ramification_index)
    polynomial.each_term -> (coefficient, exponents)
      term = FormalPuiseuxSeries.constant(
        coefficient, maximum_power,
        x_value.variable, x_value.center,
        x_value.ramification_index)
      term *= x_powers[exponents[0]]
      term *= y_powers[exponents[1]]
      result += term
    result

  -> .vanishes_through?(series, maximum_power)
    cutoff = maximum_power*series.ramification_index
    return false if series.maximum_index < cutoff
    index = 0
    while index <= cutoff
      return false if !Expression.zero_expression?(
        series.coefficient_index(index))
      index += 1
    true

  -> .rational_zeros(size)
    PlaneLocalGeometry.field_zeros(RationalField.new, size)

  -> .field_zeros(coefficient_field, size)
    out = []
    size.times -> out.push(coefficient_field.zero)
    out

  -> .rational_convolution(left, right, maximum_index)
    PlaneLocalGeometry.field_convolution(
      RationalField.new, left, right, maximum_index)

  -> .field_convolution(coefficient_field, left, right,
                        maximum_index)
    out = PlaneLocalGeometry.field_zeros(
      coefficient_field, maximum_index + 1)
    i = 0
    while i < left.size && i <= maximum_index
      if !coefficient_field.zero?(left[i])
        j = 0
        available = maximum_index - i
        while j < right.size && j <= available
          if !coefficient_field.zero?(right[j])
            product = coefficient_field.multiply(left[i], right[j])
            out[i + j] = coefficient_field.add(
              out[i + j], product)
          j += 1
      i += 1
    out

  # Evaluate f(s^q, y(s)) over raw Rational coefficient arrays. The local
  # x-coordinate is a monomial, so x^i is just an index shift; only powers of
  # y require convolution. This is the hot exact path used by Hensel lifting.
  -> .evaluate_rational_local(polynomial, ramification_index,
                               y_coefficients, maximum_index)
    PlaneLocalGeometry.evaluate_field_local(
      polynomial, RationalField.new, ramification_index,
      y_coefficients, maximum_index)

  -> .evaluate_field_local(polynomial, coefficient_field,
                            ramification_index,
                            y_coefficients, maximum_index)
    Field.require_supported(coefficient_field)
    y_powers = [
      PlaneLocalGeometry.field_zeros(
        coefficient_field, maximum_index + 1)]
    y_powers[0][0] = coefficient_field.one
    degree = 1
    while degree <= polynomial.degree_in(1)
      y_powers.push(PlaneLocalGeometry.field_convolution(
        coefficient_field, y_powers[degree - 1],
        y_coefficients, maximum_index))
      degree += 1

    result = PlaneLocalGeometry.field_zeros(
      coefficient_field, maximum_index + 1)
    polynomial.each_term -> (coefficient, exponents)
      shift = exponents[0]*ramification_index
      power = y_powers[exponents[1]]
      scalar = coefficient_field.embed_from(
        polynomial.ring.field, coefficient)
      source = 0
      while source < power.size && source + shift <= maximum_index
        if !coefficient_field.zero?(power[source])
          product = coefficient_field.multiply(
            scalar, power[source])
          result[source + shift] = coefficient_field.add(
            result[source + shift], product)
        source += 1
    result

  -> .rational_coefficients(series, maximum_index)
    PlaneLocalGeometry.field_coefficients(
      series, RationalField.new, maximum_index)

  -> .field_coefficients(series, coefficient_field,
                          maximum_index)
    out = []
    index = 0
    while index <= maximum_index
      coefficient = series.coefficient_index(index)
      if !coefficient.constant?
        raise "certified local branch has a symbolic coefficient"
      out.push(coefficient_field.normalize_element(
        coefficient.constant_value))
      index += 1
    out

  -> .field_valuation(coefficient_field, coefficients)
    index = 0
    while index < coefficients.size
      return index if !coefficient_field.zero?(coefficients[index])
      index += 1
    nil

  -> .field_vanishes_through?(coefficient_field, coefficients,
                               maximum_index)
    index = 0
    while index <= maximum_index
      return false if (
        index < coefficients.size &&
        !coefficient_field.zero?(coefficients[index]))
      index += 1
    true

  # Quotient of possibly shifted exact power series. The returned dense array
  # is indexed in the common local parameter and truncated at maximum_index.
  -> .field_series_divide(coefficient_field, numerator,
                           denominator, maximum_index)
    numerator_value = PlaneLocalGeometry.field_valuation(
      coefficient_field, numerator)
    if numerator_value == nil
      return PlaneLocalGeometry.field_zeros(
        coefficient_field, maximum_index + 1)
    denominator_value = PlaneLocalGeometry.field_valuation(
      coefficient_field, denominator)
    raise "local series division by zero" if denominator_value == nil
    quotient_value = numerator_value - denominator_value
    if quotient_value < 0
      raise "local Newton correction acquired a pole"
    shifted_order = maximum_index - quotient_value
    if shifted_order < 0
      return PlaneLocalGeometry.field_zeros(
        coefficient_field, maximum_index + 1)
    inverse_leading = coefficient_field.inverse(
      denominator[denominator_value])
    shifted = []
    order = 0
    while order <= shifted_order
      source_index = numerator_value + order
      value = (
        source_index < numerator.size ?
        numerator[source_index] : coefficient_field.zero)
      divisor_index = 1
      while divisor_index <= order
        denominator_index = denominator_value + divisor_index
        if denominator_index < denominator.size
          product = coefficient_field.multiply(
            denominator[denominator_index],
            shifted[order - divisor_index])
          value = coefficient_field.subtract(value, product)
        divisor_index += 1
      shifted.push(coefficient_field.multiply(
        value, inverse_leading))
      order += 1
    out = PlaneLocalGeometry.field_zeros(
      coefficient_field, maximum_index + 1)
    order = 0
    while order < shifted.size
      out[quotient_value + order] = shifted[order]
      order += 1
    out

  -> .coordinate_parameter?(series, maximum_power)
    cutoff = maximum_power*series.ramification_index
    return false if series.maximum_index < cutoff
    index = 0
    while index <= cutoff
      coefficient = series.coefficient_index(index)
      expected = (
        index == series.ramification_index ?
        Expression.constant(1) : Expression.constant(0))
      return false if coefficient != expected
      index += 1
    true

  -> .rational_residual_series(polynomial, coordinate_series,
                                displacement_series,
                                maximum_power)
    PlaneLocalGeometry.field_residual_series(
      polynomial, RationalField.new, coordinate_series,
      displacement_series, maximum_power)

  -> .field_residual_series(polynomial, coefficient_field,
                             coordinate_series,
                             displacement_series,
                             maximum_power)
    pair = coordinate_series.common_ramification(
      displacement_series)
    coordinate = pair[0]
    displacement = pair[1]
    cutoff = maximum_power*coordinate.ramification_index
    coefficients = PlaneLocalGeometry.field_coefficients(
      displacement, coefficient_field, cutoff)
    residual = PlaneLocalGeometry.evaluate_field_local(
      polynomial, coefficient_field,
      coordinate.ramification_index, coefficients, cutoff)
    FormalPuiseuxSeries.new(
      residual, 0, coordinate.ramification_index,
      coordinate.variable, coordinate.center)

  # Dense exact Newton--Hensel lift. Raw coefficient-field arrays avoid
  # symbolic Expression trees, and full Newton corrections double the known
  # precision instead of solving one coefficient with a fresh evaluation.
  -> .lift_rational_branch(polynomial, variable, center,
                            maximum_power, ramification_index,
                            leading_index, leading_coefficient)
    PlaneLocalGeometry.lift_field_branch(
      polynomial, RationalField.new, variable, center,
      maximum_power, ramification_index,
      leading_index, leading_coefficient)

  -> .lift_field_branch(polynomial, coefficient_field,
                         variable, center,
                         maximum_power, ramification_index,
                         leading_index, leading_coefficient)
    maximum_index = maximum_power*ramification_index
    coefficients = PlaneLocalGeometry.field_zeros(
      coefficient_field, maximum_index + 1)
    coefficients[leading_index] = (
      coefficient_field.normalize_element(leading_coefficient))
    derivative = polynomial.derivative(1)
    derivative_limit = (
      maximum_index +
      polynomial.degree*(
        ramification_index + leading_index))
    derivative_values = PlaneLocalGeometry.evaluate_field_local(
      derivative, coefficient_field, ramification_index,
      coefficients, derivative_limit)
    derivative_index = nil
    index = 0
    while index < derivative_values.size
      if !coefficient_field.zero?(derivative_values[index])
        derivative_index = index
        break
      index += 1
    if derivative_index == nil
      raise "Puiseux Hensel derivative vanished"
    full_evaluation_limit = maximum_index + derivative_index
    evaluation_limit = leading_index + derivative_index + 1
    evaluation_limit = full_evaluation_limit if (
      evaluation_limit > full_evaluation_limit)
    iteration = 0
    iteration_limit = 8*maximum_index + 16
    finished = false
    while iteration < iteration_limit && !finished
      residual = PlaneLocalGeometry.evaluate_field_local(
        polynomial, coefficient_field, ramification_index,
        coefficients, evaluation_limit)
      if PlaneLocalGeometry.field_vanishes_through?(
           coefficient_field, residual, evaluation_limit)
        if evaluation_limit == full_evaluation_limit
          finished = true
        else
          evaluation_limit = 2*evaluation_limit + 1
          evaluation_limit = full_evaluation_limit if (
            evaluation_limit > full_evaluation_limit)
      else
        derivative_values = PlaneLocalGeometry.evaluate_field_local(
          derivative, coefficient_field, ramification_index,
          coefficients, evaluation_limit)
        correction_limit = evaluation_limit - derivative_index
        correction_limit = maximum_index if (
          correction_limit > maximum_index)
        correction = PlaneLocalGeometry.field_series_divide(
          coefficient_field, residual, derivative_values,
          correction_limit)
        if PlaneLocalGeometry.field_vanishes_through?(
             coefficient_field, correction, correction_limit)
          raise "local Newton correction lost retained precision"
        index = 0
        while index <= correction_limit
          coefficients[index] = coefficient_field.subtract(
            coefficients[index], correction[index])
          index += 1
      iteration += 1
    if !finished
      raise "Puiseux field Newton lift did not converge"
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index, variable, center)

  # Replace u by s^q and v by c*s^p+z, then remove the common s-power.
  # This is the recursive Newton-polygon chart for a repeated rational
  # characteristic root c at valuation p/q.
  -> .repeated_root_transform(polynomial, numerator,
                               denominator, root)
    if polynomial.ring.field.class_name != "RationalField"
      raise "repeated-root transform currently requires RationalField"
    ring = PolynomialRing.new(
      [:s, :z], polynomial.ring.field, polynomial.ring.order)
    generators = ring.generators
    s = generators[0]
    z = generators[1]
    result = ring.zero
    polynomial.each_term -> (coefficient, exponents)
      term = ring.constant(coefficient)
      term *= s**(exponents[0]*denominator)
      term *= (s**numerator*root + z)**exponents[1]
      result += term
    minimum_s = nil
    result.each_term -> (coefficient, exponents)
      minimum_s = exponents[0] if (
        minimum_s == nil || exponents[0] < minimum_s)
    terms = []
    result.each_term -> (coefficient, exponents)
      terms.push([
        coefficient,
        [exponents[0] - minimum_s, exponents[1]]
      ])
    Polynomial.new(ring, terms)

  -> .combine_recursive_branch(variable, center,
                                 maximum_power,
                                 initial_numerator,
                                 initial_denominator,
                                 initial_root,
                                 recursive_branch)
    field = recursive_branch.coefficient_field
    recursive = recursive_branch.displacement_series
    recursive_ramification = recursive.ramification_index
    total_ramification = (
      initial_denominator*recursive_ramification)
    maximum_index = maximum_power*total_ramification
    recursive_cutoff = maximum_index
    recursive_coefficients = PlaneLocalGeometry.field_coefficients(
      recursive, field, recursive_cutoff)
    coefficients = PlaneLocalGeometry.field_zeros(
      field, maximum_index + 1)
    index = 0
    while index <= maximum_index
      coefficients[index] = recursive_coefficients[index]
      index += 1
    leading_index = initial_numerator*recursive_ramification
    leading = field.embed_from(RationalField.new, initial_root)
    coefficients[leading_index] = field.add(
      coefficients[leading_index], leading)
    FormalPuiseuxSeries.new(
      coefficients, 0, total_ramification,
      variable, center)

  -> .multiplicity(local_polynomial)
    minimum = nil
    local_polynomial.each_term -> (coefficient, exponents)
      degree = exponents[0] + exponents[1]
      minimum = degree if minimum == nil || degree < minimum
    minimum

  -> .tangent_cone(local_polynomial)
    multiplicity = PlaneLocalGeometry.multiplicity(local_polynomial)
    terms = []
    local_polynomial.each_term -> (coefficient, exponents)
      if exponents[0] + exponents[1] == multiplicity
        terms.push([coefficient, exponents])
    Polynomial.new(local_polynomial.ring, terms)

  -> .tangent_slope_polynomial(tangent_cone)
    field = tangent_cone.ring.field
    ring = PolynomialRing.new([:slope], field, :lex)
    result = ring.zero
    tangent_cone.each_term -> (coefficient, exponents)
      result += ring.monomial(coefficient, [exponents[1]])
    result

  -> .vertical_tangent_multiplicity(tangent_cone,
                                     slope_polynomial)
    tangent_cone.degree - slope_polynomial.degree


+ NewtonPolygonEdge
  -> new(@polynomial, @left, @right)
    dx = @right[0] - @left[0]
    dy = @left[1] - @right[1]
    if dx <= 0 || dy <= 0
      raise "Newton edge must have negative slope"
    @valuation = Rational.new(dx, dy)
    @characteristic_polynomial = build_characteristic_polynomial

  -> polynomial
    @polynomial

  -> left
    @left

  -> right
    @right

  -> valuation
    @valuation

  -> characteristic_polynomial
    @characteristic_polynomial

  -> weight(exponents)
    (@valuation.denominator*exponents[0] +
     @valuation.numerator*exponents[1])

  -> minimum_weight
    minimum = nil
    @polynomial.each_term -> (coefficient, exponents)
      value = weight(exponents)
      minimum = value if minimum == nil || value < minimum
    minimum

  -> support_terms
    minimum = minimum_weight
    out = []
    @polynomial.each_term -> (coefficient, exponents)
      if weight(exponents) == minimum
        out.push([coefficient, exponents])
    out

  -> build_characteristic_polynomial
    terms = support_terms
    minimum_y = nil
    terms.each -> (term)
      power = term[1][1]
      minimum_y = power if minimum_y == nil || power < minimum_y
    ring = PolynomialRing.new([:C], @polynomial.ring.field, :lex)
    result = ring.zero
    terms.each -> (term)
      result += ring.monomial(
        term[0], [term[1][1] - minimum_y])
    result

  -> rational_roots
    out = []
    @characteristic_polynomial.rational_root_candidates.each -> (root)
      if (!root.zero? &&
          @characteristic_polynomial.at(root).zero? &&
          !out.include?(root))
        out.push(root)
    out

  -> irreducible_factors
    out = []
    @characteristic_polynomial.factor.each ->
      out.push(item.monic) if item.degree > 0
    out

  -> factor_groups
    groups = []
    irreducible_factors.each -> (factor)
      found = nil
      index = 0
      while index < groups.size
        found = index if groups[index][0] == factor
        index += 1
      if found == nil
        groups.push([factor, 1])
      else
        groups[found][1] += 1
    groups

  -> characteristic_evaluate(value, coefficient_field = nil)
    field = (
      coefficient_field == nil ?
      @polynomial.ring.field : coefficient_field)
    result = field.zero
    degree = @characteristic_polynomial.degree
    while degree >= 0
      result = field.multiply(result, value)
      coefficient = field.embed_from(
        @characteristic_polynomial.ring.field,
        @characteristic_polynomial.coeff(degree))
      result = field.add(result, coefficient)
      degree -= 1
    result

  -> nondegenerate_root?(root, coefficient_field = nil)
    field = (
      coefficient_field == nil ?
      @polynomial.ring.field : coefficient_field)
    return false if !field.zero?(
      characteristic_evaluate(root, field))
    derivative = @characteristic_polynomial.derivative(0)
    value = field.zero
    degree = derivative.degree
    while degree >= 0
      value = field.multiply(value, root)
      coefficient = field.embed_from(
        derivative.ring.field, derivative.coeff(degree))
      value = field.add(value, coefficient)
      degree -= 1
    !field.zero?(value)

  -> squarefree_characteristic?
    @characteristic_polynomial.gcd(
      @characteristic_polynomial.derivative(0)).degree == 0

  -> fully_split_nondegenerate_over_rationals?
    roots = rational_roots
    return false if roots.size != @characteristic_polynomial.degree
    index = 0
    while index < roots.size
      return false if !nondegenerate_root?(roots[index])
      index += 1
    true

  -> same_point?(left, right)
    (left[0] == right[0] && left[1] == right[1])

  -> verified?
    return false if @polynomial.ring.arity != 2
    return false if @left[0] >= @right[0]
    return false if @left[1] <= @right[1]
    target = weight(@left)
    return false if weight(@right) != target
    support = support_terms
    return false if support.size < 2
    found_left = false
    found_right = false
    support.each -> (term)
      found_left = true if same_point?(term[1], @left)
      found_right = true if same_point?(term[1], @right)
    return false if !found_left || !found_right
    rebuilt = build_characteristic_polynomial
    rebuilt == @characteristic_polynomial

  -> to_s
    ("NewtonEdge(" + @left.to_s + " -> " + @right.to_s +
     ", valuation=" + @valuation.to_s + ")")

  -> inspect
    to_s


+ NewtonPolygonCertificate
  -> new(@polynomial, @edges)

  -> polynomial
    @polynomial

  -> edges
    @edges

  -> verified?
    expected = NewtonPolygon.edge_endpoints(@polynomial)
    return false if expected.size != @edges.size
    index = 0
    while index < @edges.size
      edge = @edges[index]
      return false if !edge.verified?
      return false if !edge.same_point?(
        edge.left, expected[index][0])
      return false if !edge.same_point?(
        edge.right, expected[index][1])
      index += 1
    true

  -> statement
    "these are exactly the negative-slope lower Newton-polygon edges"


+ NewtonPolygon
  -> .cross(origin, left, right)
    ((left[0] - origin[0])*(right[1] - origin[1]) -
     (left[1] - origin[1])*(right[0] - origin[0]))

  -> .points(polynomial)
    points = []
    polynomial.each_term -> (coefficient, exponents)
      existing = nil
      index = 0
      while index < points.size
        existing = index if points[index][0] == exponents[0]
        index += 1
      point = [exponents[0], exponents[1]]
      if existing == nil
        points.push(point)
      elsif point[1] < points[existing][1]
        points[existing] = point
    points.sort -> (left, right)
      if left[0] == right[0]
        left[1] <=> right[1]
      else
        left[0] <=> right[0]

  -> .lower_hull(polynomial)
    hull = []
    NewtonPolygon.points(polynomial).each -> (point)
      while (hull.size >= 2 &&
             NewtonPolygon.cross(
               hull[hull.size - 2],
               hull[hull.size - 1], point) <= 0)
        hull.delete_at(hull.size - 1)
      hull.push(point)
    hull

  -> .edge_endpoints(polynomial)
    hull = NewtonPolygon.lower_hull(polynomial)
    out = []
    index = 0
    while index + 1 < hull.size
      left = hull[index]
      right = hull[index + 1]
      if right[0] > left[0] && right[1] < left[1]
        out.push([left, right])
      index += 1
    out

  -> new(@polynomial)
    if @polynomial.ring.arity != 2
      raise "NewtonPolygon requires a bivariate polynomial"
    if @polynomial.ring.field.class_name != "RationalField"
      raise "NewtonPolygon currently requires the rational field"
    @edges = []
    NewtonPolygon.edge_endpoints(@polynomial).each -> (endpoints)
      @edges.push(NewtonPolygonEdge.new(
        @polynomial, endpoints[0], endpoints[1]))
    @certificate = NewtonPolygonCertificate.new(
      @polynomial, @edges)
    raise "internal Newton-polygon certificate failure" if !@certificate.verified?

  -> polynomial
    @polynomial

  -> edges
    @edges

  -> certificate
    @certificate

  -> valuations
    out = []
    @edges.each -> out.push(item.valuation)
    out

  -> to_s
    "NewtonPolygon(" + @edges.to_s + ")"

  -> inspect
    to_s


+ LocalPlaneBranchCertificate
  -> new(@local_polynomial, @edge, @leading_coefficient,
         @coordinate_series, @displacement_series,
         @maximum_power, coefficient_field = nil,
         defining_factor = nil)
    @coefficient_field = (
      coefficient_field == nil ?
      @local_polynomial.ring.field : coefficient_field)
    if defining_factor == nil
      generator = @edge.characteristic_polynomial.ring.generator(0)
      @defining_factor = (
        generator - @leading_coefficient).monic
    else
      @defining_factor = defining_factor.monic

  -> local_polynomial
    @local_polynomial

  -> edge
    @edge

  -> leading_coefficient
    @leading_coefficient

  -> coordinate_series
    @coordinate_series

  -> displacement_series
    @displacement_series

  -> maximum_power
    @maximum_power

  -> coefficient_field
    @coefficient_field

  -> defining_factor
    @defining_factor

  -> residue_degree
    @defining_factor.degree

  -> residual
    PlaneLocalGeometry.field_residual_series(
      @local_polynomial, @coefficient_field, @coordinate_series,
      @displacement_series, @maximum_power)

  -> verified?
    return false if !@edge.verified?
    return false if !@edge.squarefree_characteristic?
    return false if !@edge.characteristic_polynomial.rem(
      @defining_factor).zero?
    if @defining_factor.degree == 1
      return false if (
        @coefficient_field.class_name != "RationalField")
    else
      return false if (
        @coefficient_field.class_name != "SimpleExtensionField")
      return false if (
        @coefficient_field.defining_polynomial != @defining_factor)
      return false if !@coefficient_field.modulus_certificate.verified?
    return false if !@edge.nondegenerate_root?(
      @leading_coefficient, @coefficient_field)
    return false if !PlaneLocalGeometry.coordinate_parameter?(
      @coordinate_series, @maximum_power)
    return false if (
      @displacement_series.valuation != @edge.valuation)
    leading = @displacement_series.coefficient(@edge.valuation)
    return false if leading != Expression.constant(@leading_coefficient)
    PlaneLocalGeometry.vanishes_through?(
      residual, @maximum_power)

  -> statement
    ("the displayed Puiseux branch solves the local plane equation " +
     "through order " + @maximum_power.to_s)


+ RecursiveLocalPlaneBranchCertificate
  -> new(@local_polynomial, @edge, @initial_factor,
         @initial_root, @transformed_polynomial,
         @recursive_branch, @coordinate_series,
         @displacement_series, @maximum_power)
    @coefficient_field = @recursive_branch.coefficient_field

  -> local_polynomial
    @local_polynomial

  -> edge
    @edge

  -> initial_factor
    @initial_factor

  -> initial_root
    @initial_root

  -> transformed_polynomial
    @transformed_polynomial

  -> recursive_branch
    @recursive_branch

  -> coordinate_series
    @coordinate_series

  -> displacement_series
    @displacement_series

  -> maximum_power
    @maximum_power

  -> coefficient_field
    @coefficient_field

  -> defining_factor
    @recursive_branch.defining_factor

  -> residue_degree
    @recursive_branch.residue_degree

  -> factor_multiplicity
    multiplicity = 0
    @edge.factor_groups.each -> (group)
      multiplicity = group[1] if group[0] == @initial_factor
    multiplicity

  -> residual
    PlaneLocalGeometry.field_residual_series(
      @local_polynomial, @coefficient_field,
      @coordinate_series, @displacement_series,
      @maximum_power)

  -> verified?
    return false if !@edge.verified?
    return false if @initial_factor.degree != 1
    return false if factor_multiplicity < 2
    rational_field = @local_polynomial.ring.field
    return false if !rational_field.zero?(
      @edge.characteristic_evaluate(
        @initial_root, rational_field))
    expected_transform = PlaneLocalGeometry.repeated_root_transform(
      @local_polynomial, @edge.valuation.numerator,
      @edge.valuation.denominator, @initial_root)
    return false if expected_transform != @transformed_polynomial
    return false if !@recursive_branch.certificate.verified?
    expected_series = PlaneLocalGeometry.combine_recursive_branch(
      @coordinate_series.variable, @coordinate_series.center,
      @maximum_power, @edge.valuation.numerator,
      @edge.valuation.denominator, @initial_root,
      @recursive_branch)
    return false if expected_series != @displacement_series
    return false if !PlaneLocalGeometry.coordinate_parameter?(
      @coordinate_series, @maximum_power)
    return false if @displacement_series.valuation != @edge.valuation
    leading = @coefficient_field.embed_from(
      rational_field, @initial_root)
    return false if (
      @displacement_series.coefficient(@edge.valuation) !=
      Expression.constant(leading))
    PlaneLocalGeometry.vanishes_through?(
      residual, @maximum_power)

  -> statement
    ("the recursively transformed Puiseux branch solves the local " +
     "plane equation through order " + @maximum_power.to_s)


+ LocalPlaneBranch
  -> new(@source_polynomial, @local_polynomial,
         @x_variable, @y_variable, @center_x, @center_y,
         @edge, @leading_coefficient,
         @coordinate_series, @displacement_series,
         @maximum_power, coefficient_field = nil,
         defining_factor = nil, supplied_certificate = nil)
    @coefficient_field = (
      coefficient_field == nil ?
      @local_polynomial.ring.field : coefficient_field)
    @defining_factor = defining_factor
    @series = (
      @displacement_series + Expression.constant(@center_y))
    if supplied_certificate == nil
      @certificate = LocalPlaneBranchCertificate.new(
        @local_polynomial, @edge, @leading_coefficient,
        @coordinate_series, @displacement_series,
        @maximum_power, @coefficient_field,
        @defining_factor)
    else
      @certificate = supplied_certificate
    raise "local branch certificate did not verify" if !@certificate.verified?

  -> source_polynomial
    @source_polynomial

  -> local_polynomial
    @local_polynomial

  -> x_variable
    @x_variable

  -> y_variable
    @y_variable

  -> center_x
    @center_x

  -> center_y
    @center_y

  -> edge
    @edge

  -> leading_coefficient
    @leading_coefficient

  -> coordinate_series
    @coordinate_series

  -> displacement_series
    @displacement_series

  -> series
    @series

  -> maximum_power
    @maximum_power

  -> certificate
    @certificate

  -> coefficient_field
    @coefficient_field

  -> defining_factor
    @certificate.defining_factor

  -> residue_degree
    @certificate.residue_degree

  -> rational?
    @coefficient_field.class_name == "RationalField"

  # A ramified y(x) expansion is a sheet of the x-projection. Sheets related
  # by a root-of-unity reparameterization can describe one geometric branch.
  -> projection_sheet?
    true

  -> ramified?
    ramification_index > 1

  -> valuation
    @edge.valuation

  -> ramification_index
    @displacement_series.ramification_index

  -> to_s
    ("LocalPlaneBranch(" + @y_variable.to_s + " = " +
     @series.to_expression.to_s + ")")

  -> inspect
    to_s


+ PlaneTangentDirection
  -> new(@defining_factor, @multiplicity, vertical = false)
    @vertical = vertical
    if @multiplicity < 1
      raise "tangent-direction multiplicity must be positive"
    if !@vertical
      if @defining_factor == nil || @defining_factor.degree < 1
        raise "finite tangent direction needs a defining factor"

  -> .vertical(multiplicity = 1)
    PlaneTangentDirection.new(nil, multiplicity, true)

  -> defining_factor
    @defining_factor

  -> multiplicity
    @multiplicity

  -> vertical?
    @vertical

  -> residue_degree
    @vertical ? 1 : @defining_factor.degree

  -> rational?
    residue_degree == 1

  -> slope
    return nil if @vertical
    if @defining_factor.degree != 1
      raise "algebraic tangent direction has no rational slope"
    field = @defining_factor.ring.field
    field.divide(
      field.negate(@defining_factor.coeff(0)),
      @defining_factor.coeff(1))

  -> residue_field
    return RationalField.new if rational?
    SimpleExtensionField.new(@defining_factor, :slope)

  -> to_s
    if @vertical
      return (
        "TangentDirection(vertical, mult=" +
        @multiplicity.to_s + ")")
    ("TangentDirection(" + @defining_factor.to_s +
     ", mult=" + @multiplicity.to_s + ")")

  -> inspect
    to_s


+ PlaneCurveLocalSingularityCertificate
  -> new(@source_polynomial, @x_variable, @y_variable,
         @point, @local_polynomial, @multiplicity,
         @tangent_cone, @slope_polynomial,
         @vertical_multiplicity, @directions)

  -> verified?
    expected_local = PlaneLocalGeometry.translated_polynomial(
      @source_polynomial, @x_variable, @y_variable,
      @point[0], @point[1])
    return false if expected_local != @local_polynomial
    return false if !@local_polynomial.ring.field.zero?(
      @local_polynomial.coeff([0, 0]))
    expected_multiplicity = PlaneLocalGeometry.multiplicity(
      @local_polynomial)
    return false if expected_multiplicity != @multiplicity
    expected_cone = PlaneLocalGeometry.tangent_cone(
      @local_polynomial)
    return false if expected_cone != @tangent_cone
    return false if !@tangent_cone.homogeneous?
    return false if @tangent_cone.degree != @multiplicity
    expected_slope = PlaneLocalGeometry.tangent_slope_polynomial(
      @tangent_cone)
    return false if expected_slope != @slope_polynomial
    expected_vertical = (
      PlaneLocalGeometry.vertical_tangent_multiplicity(
        @tangent_cone, @slope_polynomial))
    return false if expected_vertical != @vertical_multiplicity

    reconstructed = @slope_polynomial.ring.one
    vertical_seen = false
    direction_index = 0
    while direction_index < @directions.size
      direction = @directions[direction_index]
      if direction.vertical?
        return false if vertical_seen
        vertical_seen = true
        return false if (
          direction.multiplicity != @vertical_multiplicity)
      else
        reconstructed *= (
          direction.defining_factor**direction.multiplicity)
      direction_index += 1
    if @vertical_multiplicity == 0
      return false if vertical_seen
    else
      return false if !vertical_seen
    reconstructed.monic == @slope_polynomial.monic

  -> certified?
    verified?

  -> statement
    "the displayed multiplicity and tangent directions are exact"


+ OrdinaryPlanePointDeltaCertificate
  -> new(@singularity)

  -> singularity
    @singularity

  -> delta
    multiplicity = @singularity.multiplicity
    multiplicity*(multiplicity - 1)/2

  -> theorem
    "an ordinary plane m-fold point has delta invariant m(m-1)/2"

  -> theorem_reference
    "classical ordinary multiple-point delta formula"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

  -> verified?
    (@singularity.certificate.verified? &&
     @singularity.ordinary?)

  -> certified?
    verified?


+ PlaneCurveLocalSingularity
  -> new(@source_polynomial, @x_variable, @y_variable,
         point = nil)
    @point = point == nil ? [0, 0] : point
    if @point.class_name != "Array" || @point.size != 2
      raise "plane singularity point must have two coordinates"
    @local_polynomial = PlaneLocalGeometry.translated_polynomial(
      @source_polynomial, @x_variable, @y_variable,
      @point[0], @point[1])
    if @local_polynomial.zero?
      raise "the zero equation has no finite local multiplicity"
    if !@local_polynomial.ring.field.zero?(
         @local_polynomial.coeff([0, 0]))
      raise "singularity point is not on the plane equation"
    @multiplicity = PlaneLocalGeometry.multiplicity(
      @local_polynomial)
    @tangent_cone = PlaneLocalGeometry.tangent_cone(
      @local_polynomial)
    @slope_polynomial = (
      PlaneLocalGeometry.tangent_slope_polynomial(
        @tangent_cone))
    @vertical_multiplicity = (
      PlaneLocalGeometry.vertical_tangent_multiplicity(
        @tangent_cone, @slope_polynomial))
    @directions = []
    groups = []
    @slope_polynomial.factor.each -> (factor)
      if factor.degree > 0
        monic = factor.monic
        found = nil
        index = 0
        while index < groups.size
          found = index if groups[index][0] == monic
          index += 1
        if found == nil
          groups.push([monic, 1])
        else
          groups[found][1] += 1
    groups.each -> (group)
      @directions.push(
        PlaneTangentDirection.new(group[0], group[1]))
    if @vertical_multiplicity > 0
      @directions.push(
        PlaneTangentDirection.vertical(@vertical_multiplicity))
    @certificate = PlaneCurveLocalSingularityCertificate.new(
      @source_polynomial, @x_variable, @y_variable,
      @point, @local_polynomial, @multiplicity,
      @tangent_cone, @slope_polynomial,
      @vertical_multiplicity, @directions)
    if !@certificate.verified?
      raise "local singularity certificate did not verify"

  -> source_polynomial
    @source_polynomial

  -> point
    @point

  -> local_polynomial
    @local_polynomial

  -> multiplicity
    @multiplicity

  -> tangent_cone
    @tangent_cone

  -> slope_polynomial
    @slope_polynomial

  -> vertical_tangent_multiplicity
    @vertical_multiplicity

  -> tangent_directions
    @directions

  -> certificate
    @certificate

  -> smooth?
    @multiplicity == 1

  -> singular?
    @multiplicity > 1

  -> tangent_direction_count
    count = 0
    @directions.each -> count += item.residue_degree
    count

  -> ordinary?
    return false if tangent_direction_count != @multiplicity
    index = 0
    while index < @directions.size
      return false if @directions[index].multiplicity != 1
      index += 1
    true

  -> ordinary_singularity?
    singular? && ordinary?

  -> delta
    if !ordinary?
      raise "delta formula currently requires an ordinary plane point"
    @multiplicity*(@multiplicity - 1)/2

  -> delta_certificate
    certificate = OrdinaryPlanePointDeltaCertificate.new(self)
    raise "ordinary-point delta certificate did not verify" if !certificate.verified?
    certificate

  -> to_s
    ("PlaneCurveLocalSingularity(mult=" + @multiplicity.to_s +
     ", tangents=" + tangent_direction_count.to_s + ")")

  -> inspect
    to_s


+ Polynomial
  -> local_plane_polynomial(x_variable = 0, y_variable = 1,
                             center = nil)
    point = center == nil ? [0, 0] : center
    if point.class_name != "Array" || point.size != 2
      raise "local plane center must have two coordinates"
    PlaneLocalGeometry.translated_polynomial(
      self, x_variable, y_variable, point[0], point[1])

  -> newton_polygon(x_variable = 0, y_variable = 1,
                     center = nil)
    NewtonPolygon.new(
      local_plane_polynomial(x_variable, y_variable, center))

  -> local_singularity(x_variable = 0, y_variable = 1,
                        point = nil)
    PlaneCurveLocalSingularity.new(
      self, x_variable, y_variable, point)

  -> singularity_at(x_variable = 0, y_variable = 1,
                      point = nil)
    local_singularity(x_variable, y_variable, point)

  -> puiseux_branches(x_variable = 0, y_variable = 1,
                       center = nil, maximum_power = 6,
                       search_margin = 0,
                       recursion_limit = 8)
    FormalPowerSeries.validate_order(maximum_power)
    if !Expression.integer?(search_margin) || search_margin < 0
      raise "local branch search margin must be nonnegative"
    if !Expression.integer?(recursion_limit) || recursion_limit < 0
      raise "local branch recursion limit must be nonnegative"
    point = center == nil ? [0, 0] : center
    local = local_plane_polynomial(
      x_variable, y_variable, point)
    if !local.ring.field.zero?(local.coeff([0, 0]))
      raise "local branch center is not on the plane equation"
    if local.zero?
      raise "the zero equation does not define isolated local branches"
    minimum_y = nil
    local.each_term -> (coefficient, exponents)
      minimum_y = exponents[1] if (
        minimum_y == nil || exponents[1] < minimum_y)
    if minimum_y > 0
      raise (
        "local equation has a common dependent-variable factor; " +
        "extract components before Puiseux lifting")
    polygon = NewtonPolygon.new(local)
    if polygon.edges.size == 0
      raise (
        "no positive-valuation Newton edge; swap the local variables " +
        "or extract a vertical component")
    variable_index = PlaneLocalGeometry.variable_index(
      self, x_variable)
    variable = @ring.names[variable_index]
    dependent_index = PlaneLocalGeometry.variable_index(
      self, y_variable)
    dependent = @ring.names[dependent_index]
    working_power = maximum_power + search_margin
    branches = []

    polygon.edges.each -> (edge)
      edge.factor_groups.each -> (factor_group)
        factor = factor_group[0]
        multiplicity = factor_group[1]
        if multiplicity > 1
          if recursion_limit == 0
            raise "Puiseux repeated-root recursion limit exceeded"
          if factor.degree != 1
            raise (
              "repeated algebraic characteristic factors are not yet " +
              "supported by recursive Puiseux lifting")
          rational_field = local.ring.field
          initial_root = rational_field.divide(
            rational_field.negate(factor.coeff(0)),
            factor.coeff(1))
          transformed = PlaneLocalGeometry.repeated_root_transform(
            local, edge.valuation.numerator,
            edge.valuation.denominator, initial_root)
          recursive_order = (
            working_power*edge.valuation.denominator)
          recursive_branches = transformed.puiseux_branches(
            0, 1, nil, recursive_order, 0,
            recursion_limit - 1)
          recursive_branches.each -> (recursive_branch)
            if recursive_branch.valuation <= edge.valuation.numerator
              raise (
                "recursive Puiseux correction did not increase valuation")
            displacement = PlaneLocalGeometry.combine_recursive_branch(
              variable, point[0], working_power,
              edge.valuation.numerator,
              edge.valuation.denominator, initial_root,
              recursive_branch)
            retained = displacement.truncate(maximum_power)
            coordinate = PlaneLocalGeometry.coordinate_series(
              variable, point[0], maximum_power,
              displacement.ramification_index)
            certificate = RecursiveLocalPlaneBranchCertificate.new(
              local, edge, factor, initial_root, transformed,
              recursive_branch, coordinate, retained, maximum_power)
            branches.push(LocalPlaneBranch.new(
              self, local, variable, dependent,
              point[0], point[1], edge, initial_root,
              coordinate, retained, maximum_power,
              recursive_branch.coefficient_field,
              recursive_branch.defining_factor, certificate))
        else
          if factor.degree == 1
            coefficient_field = local.ring.field
            root = coefficient_field.divide(
              coefficient_field.negate(factor.coeff(0)),
              factor.coeff(1))
          else
            coefficient_field = SimpleExtensionField.new(
              factor, :c)
            root = coefficient_field.generator
          if !edge.nondegenerate_root?(root, coefficient_field)
            raise "simple characteristic factor had a vanishing derivative"
          ramification = edge.valuation.denominator
          leading_index = edge.valuation.numerator
          coordinate = PlaneLocalGeometry.coordinate_series(
            variable, point[0], working_power, ramification)
          displacement = PlaneLocalGeometry.lift_field_branch(
            local, coefficient_field, variable, point[0],
            working_power, ramification, leading_index, root)
          retained = displacement.truncate(maximum_power)
          retained_coordinate = coordinate.truncate(maximum_power)
          branches.push(LocalPlaneBranch.new(
            self, local, variable, dependent,
            point[0], point[1], edge, root,
            retained_coordinate, retained, maximum_power,
            coefficient_field, factor))
    branches

  -> puiseux_sheets(x_variable = 0, y_variable = 1,
                     center = nil, maximum_power = 6,
                     search_margin = 0,
                     recursion_limit = 8)
    puiseux_branches(
      x_variable, y_variable, center,
      maximum_power, search_margin, recursion_limit)


+ AffineChart
  -> local_coordinate_indices
    out = []
    index = 0
    while index < space.coordinate_count
      out.push(index) if index != @index
      index += 1
    out

  -> newton_polygon(point)
    if point.class_name != "Array" || point.size != 2
      raise "affine local point must have two coordinates"
    indices = local_coordinate_indices
    @equation.newton_polygon(indices[0], indices[1], point)

  -> singularity_at(point)
    if point.class_name != "Array" || point.size != 2
      raise "affine local point must have two coordinates"
    indices = local_coordinate_indices
    @equation.singularity_at(
      indices[0], indices[1], point)

  -> puiseux_branches(point, maximum_power = 6,
                       search_margin = 0,
                       recursion_limit = 8)
    if point.class_name != "Array" || point.size != 2
      raise "affine local point must have two coordinates"
    indices = local_coordinate_indices
    @equation.puiseux_branches(
      indices[0], indices[1], point,
      maximum_power, search_margin, recursion_limit)

  -> puiseux_sheets(point, maximum_power = 6,
                     search_margin = 0,
                     recursion_limit = 8)
    puiseux_branches(
      point, maximum_power, search_margin,
      recursion_limit)


+ Curve
  -> newton_polygon(point, chart = nil)
    affine_chart(chart).newton_polygon(point)

  -> singularity_at(point, chart = nil)
    affine_chart(chart).singularity_at(point)

  -> puiseux_branches(point, chart = nil,
                       maximum_power = 6,
                       search_margin = 0,
                       recursion_limit = 8)
    affine_chart(chart).puiseux_branches(
      point, maximum_power, search_margin,
      recursion_limit)

  -> puiseux_sheets(point, chart = nil,
                     maximum_power = 6,
                     search_margin = 0,
                     recursion_limit = 8)
    puiseux_branches(
      point, chart, maximum_power,
      search_margin, recursion_limit)
