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
    if polynomial.ring.field.class_name != "RationalField"
      raise "local Puiseux geometry currently requires the rational field"
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
    out = []
    size.times -> out.push(Rational.new(0))
    out

  -> .rational_convolution(left, right, maximum_index)
    out = PlaneLocalGeometry.rational_zeros(maximum_index + 1)
    i = 0
    while i < left.size && i <= maximum_index
      if !left[i].zero?
        j = 0
        available = maximum_index - i
        while j < right.size && j <= available
          if !right[j].zero?
            out[i + j] += left[i]*right[j]
          j += 1
      i += 1
    out

  # Evaluate f(s^q, y(s)) over raw Rational coefficient arrays. The local
  # x-coordinate is a monomial, so x^i is just an index shift; only powers of
  # y require convolution. This is the hot exact path used by Hensel lifting.
  -> .evaluate_rational_local(polynomial, ramification_index,
                               y_coefficients, maximum_index)
    if polynomial.ring.field.class_name != "RationalField"
      raise "rational local evaluation requires RationalField"
    y_powers = [
      PlaneLocalGeometry.rational_zeros(maximum_index + 1)]
    y_powers[0][0] = Rational.new(1)
    degree = 1
    while degree <= polynomial.degree_in(1)
      y_powers.push(PlaneLocalGeometry.rational_convolution(
        y_powers[degree - 1], y_coefficients,
        maximum_index))
      degree += 1

    result = PlaneLocalGeometry.rational_zeros(maximum_index + 1)
    polynomial.each_term -> (coefficient, exponents)
      shift = exponents[0]*ramification_index
      power = y_powers[exponents[1]]
      source = 0
      while source < power.size && source + shift <= maximum_index
        if !power[source].zero?
          result[source + shift] += coefficient*power[source]
        source += 1
    result

  -> .rational_coefficients(series, maximum_index)
    out = []
    index = 0
    while index <= maximum_index
      coefficient = series.coefficient_index(index)
      if !coefficient.constant?
        raise "certified rational local branch has a symbolic coefficient"
      out.push(Rational.coerce(coefficient.constant_value))
      index += 1
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
    pair = coordinate_series.common_ramification(
      displacement_series)
    coordinate = pair[0]
    displacement = pair[1]
    cutoff = maximum_power*coordinate.ramification_index
    coefficients = PlaneLocalGeometry.rational_coefficients(
      displacement, cutoff)
    residual = PlaneLocalGeometry.evaluate_rational_local(
      polynomial, coordinate.ramification_index,
      coefficients, cutoff)
    FormalPuiseuxSeries.new(
      residual, 0, coordinate.ramification_index,
      coordinate.variable, coordinate.center)

  # Coefficient-by-coefficient Newton--Hensel lift. If y=c*s^p+... and the
  # leading coefficient of f_y(s^q,y) is D*s^d, then the coefficient a_n
  # first enters f in degree n+d with coefficient D. Exact division therefore
  # determines a_n without rebuilding symbolic Expression trees.
  -> .lift_rational_branch(polynomial, variable, center,
                            maximum_power, ramification_index,
                            leading_index, leading_coefficient)
    maximum_index = maximum_power*ramification_index
    coefficients = PlaneLocalGeometry.rational_zeros(maximum_index + 1)
    coefficients[leading_index] = Rational.coerce(leading_coefficient)
    derivative = polynomial.derivative(1)
    derivative_limit = (
      maximum_index +
      polynomial.degree*(
        ramification_index + leading_index))
    derivative_values = PlaneLocalGeometry.evaluate_rational_local(
      derivative, ramification_index,
      coefficients, derivative_limit)
    derivative_index = nil
    index = 0
    while index < derivative_values.size
      if !derivative_values[index].zero?
        derivative_index = index
        break
      index += 1
    if derivative_index == nil
      raise "Puiseux Hensel derivative vanished"
    derivative_leading = derivative_values[derivative_index]

    index = leading_index + 1
    while index <= maximum_index
      target = index + derivative_index
      residual = PlaneLocalGeometry.evaluate_rational_local(
        polynomial, ramification_index,
        coefficients, target)[target]
      coefficients[index] = (
        residual.negate / derivative_leading)
      index += 1
    FormalPuiseuxSeries.new(
      coefficients, 0, ramification_index, variable, center)


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

  -> nondegenerate_root?(root)
    return false if !@characteristic_polynomial.at(root).zero?
    !@characteristic_polynomial.derivative(0).at(root).zero?

  -> fully_split_nondegenerate_over_rationals?
    roots = rational_roots
    return false if roots.size != @characteristic_polynomial.degree
    roots.each ->
      return false if !nondegenerate_root?(item)
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
         @maximum_power)

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

  -> residual
    PlaneLocalGeometry.rational_residual_series(
      @local_polynomial, @coordinate_series,
      @displacement_series, @maximum_power)

  -> verified?
    return false if !@edge.verified?
    return false if !@edge.nondegenerate_root?(@leading_coefficient)
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


+ LocalPlaneBranch
  -> new(@source_polynomial, @local_polynomial,
         @x_variable, @y_variable, @center_x, @center_y,
         @edge, @leading_coefficient,
         @coordinate_series, @displacement_series,
         @maximum_power)
    @series = (
      @displacement_series + Expression.constant(@center_y))
    @certificate = LocalPlaneBranchCertificate.new(
      @local_polynomial, @edge, @leading_coefficient,
      @coordinate_series, @displacement_series,
      @maximum_power)
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

  -> valuation
    @edge.valuation

  -> ramification_index
    @displacement_series.ramification_index

  -> to_s
    ("LocalPlaneBranch(" + @y_variable.to_s + " = " +
     @series.to_expression.to_s + ")")

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

  -> puiseux_branches(x_variable = 0, y_variable = 1,
                       center = nil, maximum_power = 6,
                       search_margin = 8)
    FormalPowerSeries.validate_order(maximum_power)
    if !Expression.integer?(search_margin) || search_margin < 0
      raise "local branch search margin must be nonnegative"
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
    polygon.edges.each -> (edge)
      if !edge.fully_split_nondegenerate_over_rationals?
        raise (
          "automatic Puiseux lifting currently requires every " +
          "characteristic polynomial to split into distinct nonzero " +
          "rational roots; inspect newton_polygon for the unresolved edge")
    variable_index = PlaneLocalGeometry.variable_index(
      self, x_variable)
    variable = @ring.names[variable_index]
    dependent_index = PlaneLocalGeometry.variable_index(
      self, y_variable)
    dependent = @ring.names[dependent_index]
    working_power = maximum_power + search_margin
    branches = []

    polygon.edges.each -> (edge)
      edge.rational_roots.each -> (root)
        if edge.nondegenerate_root?(root)
          ramification = edge.valuation.denominator
          leading_index = edge.valuation.numerator
          coordinate = PlaneLocalGeometry.coordinate_series(
            variable, point[0], working_power, ramification)
          displacement = PlaneLocalGeometry.lift_rational_branch(
            local, variable, point[0], working_power,
            ramification, leading_index, root)
          if !PlaneLocalGeometry.vanishes_through?(
               PlaneLocalGeometry.rational_residual_series(
                 local, coordinate, displacement, working_power),
               working_power)
            raise "Puiseux Hensel lift did not reach requested precision"
          retained = displacement.truncate(maximum_power)
          retained_coordinate = coordinate.truncate(maximum_power)
          branches.push(LocalPlaneBranch.new(
            self, local, variable, dependent,
            point[0], point[1], edge, root,
            retained_coordinate, retained, maximum_power))
    branches


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

  -> puiseux_branches(point, maximum_power = 6,
                       search_margin = 8)
    if point.class_name != "Array" || point.size != 2
      raise "affine local point must have two coordinates"
    indices = local_coordinate_indices
    @equation.puiseux_branches(
      indices[0], indices[1], point,
      maximum_power, search_margin)


+ Curve
  -> newton_polygon(point, chart = nil)
    affine_chart(chart).newton_polygon(point)

  -> puiseux_branches(point, chart = nil,
                       maximum_power = 6,
                       search_margin = 8)
    affine_chart(chart).puiseux_branches(
      point, maximum_power, search_margin)
