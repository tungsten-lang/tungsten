# Exact local plane-curve intersection multiplicities.

use algebra

-> intersection_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :lex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

cusp = y**2 - x**3
cusp_horizontal = cusp.local_intersection(
  y, 0, 1, nil, 4)
intersection_check("cusp.horizontal",
                   cusp_horizontal.multiplicity == 3)
intersection_check("cusp.packet_valuations",
                   cusp_horizontal.packet_intersections.size == 2 &&
                   cusp_horizontal.packet_intersections.all? ->
                     item.valuation == 3 &&
                     item.geometric_contribution ==
                       Rational.new(3, 2))
intersection_check("cusp.packet_certificates",
                   cusp_horizontal.packet_intersections.all? ->
                     item.certificate.verified? &&
                     item.certificate.kernel_checked? &&
                     item.certificate.proof_kind ==
                       :exact_parameter_substitution)
intersection_check("cusp.aggregate_certificate",
                   cusp_horizontal.certificate.verified? &&
                   cusp_horizontal.certificate.proof_kind ==
                     :trusted_theorem_import &&
                   !cusp_horizontal.certificate.kernel_checked?)

intersection_check("cusp.vertical",
                   cusp.local_intersection_multiplicity(
                     x, 0, 1, nil, 4) == 2)

node = y**2 - x**2 - x**3
intersection_check("node.horizontal",
                   node.local_intersection_multiplicity(
                     y, 0, 1, nil, 3) == 2)

tacnode = y**2 - x**4
intersection_check("tacnode.horizontal",
                   tacnode.local_intersection_multiplicity(
                     y, 0, 1, nil, 4) == 4)

parabola = y - x**2
tangent = y - x**2 - x**3
forward = parabola.local_intersection(
  tangent, 0, 1, nil, 4)
reverse = tangent.local_intersection(
  parabola, 0, 1, nil, 4)
intersection_check("smooth_tangent.value",
                   forward.multiplicity == 3)
intersection_check("smooth_tangent.symmetry",
                   reverse.multiplicity == forward.multiplicity)

algebraic = y**2 - x*2
intersection_check("algebraic.packet",
                   algebraic.local_intersection_multiplicity(
                     y, 0, 1, nil, 3) == 1)

shifted_cusp = (y - 3)**2 - (x - 2)**3
intersection_check("shifted.value",
                   shifted_cusp.local_intersection_multiplicity(
                     y - 3, :x, :y, [2, 3], 4) == 3)

normalization = cusp.local_normalization(
  0, 1, nil, 4)
intersection_check("normalization.facade",
                   normalization.intersection_with(y).
                     multiplicity == 3)
intersection_check("algebra.facade",
                   Algebra.local_intersection_multiplicity(
                     cusp, y, 0, 1, nil, 4) == 3)

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
projective_coordinates = P2.coords
X = projective_coordinates[0]
Y = projective_coordinates[1]
Z = projective_coordinates[2]
C = Curve.new(P2, Y**2*Z - X**3)
L = Curve.new(P2, Y*Z)
curve_intersection = C.local_intersection(
  L, [0, 0], 2, 4)
intersection_check("curve.facade",
                   curve_intersection.multiplicity == 3 &&
                   curve_intersection.certificate.verified?)

tampered_packet = (
  LocalPlaneParametrizationIntersectionCertificate.new(
    cusp_horizontal.packet_intersections[0].parametrization,
    cusp_horizontal.target_local_polynomial,
    cusp_horizontal.packet_intersections[0].
      residual_coefficients,
    2))
intersection_check("packet.tamper_rejected",
                   !tampered_packet.verified?)

common_component_rejected = false
begin
  cusp.local_intersection(
    cusp, 0, 1, nil, 4)
rescue error
  common_component_rejected = true
intersection_check("boundary.common_component",
                   common_component_rejected)

insufficient_precision_rejected = false
begin
  parabola.local_intersection(
    y - x**2 - x**10, 0, 1, nil, 4)
rescue error
  insufficient_precision_rejected = true
intersection_check("boundary.precision",
                   insufficient_precision_rejected)
intersection_check("precision.resolved",
                   parabola.local_intersection_multiplicity(
                     y - x**2 - x**10,
                     0, 1, nil, 10) == 10)
