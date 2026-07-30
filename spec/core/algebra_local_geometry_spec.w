# Newton polygons and certified nondegenerate Puiseux lifting.

use algebra

-> local_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :lex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

branched_equation = y**2 - x*(x + 1)
polygon = branched_equation.newton_polygon
local_check("polygon.edge_count", polygon.edges.size == 1)
local_check("polygon.valuation",
            polygon.valuations[0] == Rational.new(1, 2))
local_check("polygon.characteristic",
            polygon.edges[0].characteristic_polynomial ==
            PolynomialRing.new([:C], Q, :lex).generator(0)**2 - 1)
local_check("polygon.certificate",
            polygon.certificate.verified?)
missing_edge_certificate = NewtonPolygonCertificate.new(
  polygon.polynomial, [])
local_check("polygon.tamper_rejected",
            !missing_edge_certificate.verified?)

branches = branched_equation.puiseux_branches(
  0, 1, nil, 4, 0)
local_check("branches.count", branches.size == 2)
positive = branches.detect ->
  item.leading_coefficient == Rational.new(1)
negative = branches.detect ->
  item.leading_coefficient == Rational.new(-1)
local_check("branches.both_signs",
            positive != nil && negative != nil)
local_check("branches.ramification",
            positive.ramification_index == 2)
local_check("branches.leading",
            positive.series.coefficient(Rational.new(1, 2)) ==
            Expression.constant(1))
local_check("branches.binomial_coefficients",
            positive.series.coefficient(Rational.new(3, 2)) ==
              Expression.constant(Rational.new(1, 2)) &&
            positive.series.coefficient(Rational.new(5, 2)) ==
              Expression.constant(Rational.new(-1, 8)) &&
            positive.series.coefficient(Rational.new(7, 2)) ==
              Expression.constant(Rational.new(1, 16)))
local_check("branches.certificates",
            positive.certificate.verified? &&
            negative.certificate.verified?)
local_check("branches.residual",
            PlaneLocalGeometry.vanishes_through?(
              positive.certificate.residual, 4))

tampered_displacement = (
  positive.displacement_series +
  positive.coordinate_series)
tampered_branch_certificate = LocalPlaneBranchCertificate.new(
  positive.local_polynomial, positive.edge,
  positive.leading_coefficient, positive.coordinate_series,
  tampered_displacement, 4)
local_check("branches.tamper_rejected",
            !tampered_branch_certificate.verified?)

cusp = y**2 - x**3
cusp_branches = cusp.puiseux_branches(0, 1, nil, 4, 0)
cusp_positive = cusp_branches.detect ->
  item.leading_coefficient == Rational.new(1)
local_check("cusp.valuation",
            cusp_positive.valuation == Rational.new(3, 2))
local_check("cusp.exact_branch",
            cusp_positive.series.coefficient(
              Rational.new(3, 2)) == Expression.constant(1))

implicit = y**2 - y - x
implicit_branch = implicit.puiseux_branches(
  0, 1, nil, 4, 0)[0]
local_check("implicit_function.linear",
            implicit_branch.series.coefficient(1) ==
            Expression.constant(-1))
local_check("implicit_function.quartic",
            implicit_branch.series.coefficient(4) ==
            Expression.constant(5))

two_edge_equation = y**3 - x*y + x**3
two_edge_polygon = two_edge_equation.newton_polygon
two_edge_branches = two_edge_equation.puiseux_branches(
  0, 1, nil, 5, 0)
local_check("multiple_edges.valuations",
            two_edge_polygon.valuations.size == 2 &&
            two_edge_polygon.valuations[0] == Rational.new(1, 2) &&
            two_edge_polygon.valuations[1] == Rational.new(2))
local_check("multiple_edges.branch_count",
            two_edge_branches.size == 3)
local_check("multiple_edges.certificates",
            two_edge_branches[0].certificate.verified? &&
            two_edge_branches[1].certificate.verified? &&
            two_edge_branches[2].certificate.verified?)

shifted = (y - 3)**2 - (x - 2)
shifted_branches = shifted.puiseux_branches(
  :x, :y, [2, 3], 3, 0)
local_check("shifted.center",
            shifted_branches[0].series.center ==
            Expression.constant(2))
local_check("shifted.constant",
            shifted_branches[0].series.coefficient(0) ==
            Expression.constant(3))

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
projective_coordinates = P2.coords
X = projective_coordinates[0]
Y = projective_coordinates[1]
Z = projective_coordinates[2]
curve = Curve.new(P2, Y**2*Z - X**3)
curve_polygon = curve.newton_polygon([0, 0], 2)
curve_branches = curve.puiseux_branches([0, 0], 2, 4, 0)
local_check("curve.facade_polygon",
            curve_polygon.valuations[0] == Rational.new(3, 2))
local_check("curve.facade_branches",
            curve_branches.size == 2 &&
            curve_branches[0].certificate.verified?)

facade = Algebra.puiseux_branches(
  branched_equation, 0, 1, nil, 3, 0)
local_check("algebra.facade",
            facade.size == 2 &&
            Algebra.newton_polygon(branched_equation).certificate.verified?)

algebraic_edge = y**2 - x*(x + 1)*2
algebraic_packets = algebraic_edge.puiseux_branches(
  0, 1, nil, 4, 0)
algebraic_packet = algebraic_packets[0]
algebraic_field = algebraic_packet.coefficient_field
algebraic_root = algebraic_packet.leading_coefficient
local_check("algebraic_branch.packet_count",
            algebraic_packets.size == 1)
local_check("algebraic_branch.residue_degree",
            algebraic_packet.residue_degree == 2 &&
            algebraic_field.degree == 2)
local_check("algebraic_branch.trace_norm",
            algebraic_field.trace(algebraic_root) == Rational.new(0) &&
            algebraic_field.norm(algebraic_root) == Rational.new(-2))
local_check("algebraic_branch.coefficient",
            algebraic_packet.series.coefficient(
              Rational.new(3, 2)) ==
            Expression.constant(
              algebraic_field.divide(algebraic_root, 2)))
local_check("algebraic_branch.certificate",
            algebraic_packet.certificate.verified?)
algebraic_expression = Expression.constant(algebraic_root)
local_check("algebraic_branch.expression_arithmetic",
            Expression.zero_expression?(
              algebraic_expression - algebraic_expression))

cubic_algebraic_edge = y**3 - x*2
cubic_packet = cubic_algebraic_edge.puiseux_branches(
  0, 1, nil, 3, 0)[0]
local_check("algebraic_branch.cubic_degree",
            cubic_packet.residue_degree == 3 &&
            cubic_packet.valuation == Rational.new(1, 3))
local_check("algebraic_branch.cubic_norm",
            cubic_packet.coefficient_field.norm(
              cubic_packet.leading_coefficient) == Rational.new(2))
local_check("algebraic_branch.cubic_certificate",
            cubic_packet.certificate.verified?)

mixed_characteristic = (
  y**3 - x*y**2 - x**2*y*2 + x**3*2)
mixed_packets = mixed_characteristic.puiseux_branches(
  0, 1, nil, 3, 0)
local_check("algebraic_branch.mixed_packets",
            mixed_packets.size == 2 &&
            mixed_packets[0].residue_degree +
              mixed_packets[1].residue_degree == 3)
local_check("algebraic_branch.mixed_certificates",
            mixed_packets[0].certificate.verified? &&
            mixed_packets[1].certificate.verified?)

shared_tangent = (y - x)**2 - x**3
shared_branches = shared_tangent.puiseux_branches(
  0, 1, nil, 4, 0, 8)
shared_positive = shared_branches.detect ->
  (item.series.coefficient(Rational.new(3, 2)) ==
   Expression.constant(1))
local_check("recursive_tangent.branch_count",
            shared_branches.size == 2)
local_check("recursive_tangent.coefficients",
            shared_positive.series.coefficient(1) ==
              Expression.constant(1) &&
            shared_positive.series.coefficient(
              Rational.new(3, 2)) == Expression.constant(1))
local_check("recursive_tangent.certificate",
            shared_positive.certificate.class_name ==
              "RecursiveLocalPlaneBranchCertificate" &&
            shared_positive.certificate.verified?)

four_tangent_branches = (
  ((y - x)**2 - x**3) *
  ((y - x)**2 - x**3*4)).puiseux_branches(
    0, 1, nil, 4, 0, 8)
local_check("recursive_tangent.four_branches",
            four_tangent_branches.size == 4)
local_check("recursive_tangent.four_certificates",
            four_tangent_branches[0].certificate.verified? &&
            four_tangent_branches[1].certificate.verified? &&
            four_tangent_branches[2].certificate.verified? &&
            four_tangent_branches[3].certificate.verified?)

recursion_limit_rejected = false
begin
  shared_tangent.puiseux_branches(0, 1, nil, 4, 0, 0)
rescue error
  recursion_limit_rejected = true
local_check("boundary.recursion_limit",
            recursion_limit_rejected)

repeated_algebraic = (y**2 - x*2)**2 - x**3
repeated_algebraic_rejected = false
begin
  repeated_algebraic.puiseux_branches
rescue error
  repeated_algebraic_rejected = true
local_check("boundary.repeated_algebraic_factor",
            repeated_algebraic_rejected)

nonreduced = (y - x)**2
nonreduced_rejected = false
begin
  nonreduced.puiseux_branches
rescue error
  nonreduced_rejected = true
local_check("boundary.nonreduced_component",
            nonreduced_rejected)

off_curve_rejected = false
begin
  branched_equation.puiseux_branches(0, 1, [1, 1])
rescue error
  off_curve_rejected = true
local_check("boundary.center_not_on_curve",
            off_curve_rejected)

vertical_rejected = false
begin
  x.puiseux_branches
rescue error
  vertical_rejected = true
local_check("boundary.vertical_component",
            vertical_rejected)

F5 = Algebra.finite_field(5)
R5 = PolynomialRing.new([:x, :y], F5)
xy5 = R5.generators
finite_equation = xy5[1]**2 - xy5[0]
field_rejected = false
begin
  finite_equation.newton_polygon
rescue error
  field_rejected = true
local_check("boundary.field_rejected",
            field_rejected)
