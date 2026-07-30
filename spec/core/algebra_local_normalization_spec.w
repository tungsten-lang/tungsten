# Exact finite local normalization packets and geometric branch counts.

use algebra

-> normalization_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :lex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

cusp = (y**2 - x**3).local_normalization(
  0, 1, nil, 3)
normalization_check("cusp.sheet_count",
                    cusp.projection_sheets.size == 2)
normalization_check("cusp.branch_count",
                    cusp.geometric_branch_count == 1)
normalization_check("cusp.finite_boundary",
                    cusp.finite_jet? &&
                    !cusp.complete_local_ring?)
normalization_check("cusp.cover_certificate",
                    cusp.sheet_cover_certificate.verified? &&
                    cusp.sheet_cover_certificate.kernel_checked?)
normalization_check("cusp.theorem_certificate",
                    cusp.certificate.verified? &&
                    cusp.certificate.proof_kind ==
                      :trusted_theorem_import &&
                    !cusp.certificate.kernel_checked?)

positive = cusp.parametrizations.detect ->
  item.y_series.coefficient(3) == Expression.constant(1)
normalization_check("cusp.parameterization",
                    positive.ramification_index == 2 &&
                    positive.primitive? &&
                    positive.x_series.coefficient(2) ==
                      Expression.constant(1) &&
                    positive.y_series.coefficient(3) ==
                      Expression.constant(1))
normalization_check("cusp.parameter_certificate",
                    positive.certificate.verified? &&
                    positive.certificate.kernel_checked? &&
                    positive.certificate.residual_coefficients.all? ->
                      Q.zero?(item))
normalization_check("cusp.orbit_weight",
                    positive.geometric_branch_weight ==
                      Rational.new(1, 2))
reducible_parameter = FormalPuiseuxSeries.new(
  [0, 0, 1, 0, 0, 0, 1], 0, 4, :x, 0)
normalization_check("parameter.common_power",
                    PlaneLocalGeometry.parameter_divisor(
                      reducible_parameter) == 2)

node = (y**2 - x**2 - x**3).local_normalization(
  0, 1, nil, 3)
normalization_check("node.branch_count",
                    node.projection_sheets.size == 2 &&
                    node.geometric_branch_count == 2)
normalization_check("node.delta",
                    node.delta == 1 &&
                    node.delta_certificate.verified?)

algebraic = (y**2 - x*2).local_normalization(
  0, 1, nil, 3)
normalization_check("algebraic.packet",
                    algebraic.parametrizations.size == 1 &&
                    algebraic.parametrizations[0].residue_degree == 2)
normalization_check("algebraic.branch_count",
                    algebraic.parametrizations[0].
                      geometric_branch_weight == Rational.new(1) &&
                    algebraic.geometric_branch_count == 1)

cubic_packet = (y**3 - x*2).local_normalization(
  0, 1, nil, 3)
normalization_check("cubic.packet",
                    cubic_packet.parametrizations.size == 1 &&
                    cubic_packet.parametrizations[0].
                      residue_degree == 3 &&
                    cubic_packet.parametrizations[0].
                      ramification_index == 3 &&
                    cubic_packet.geometric_branch_count == 1)

shared_tangent = (
  (y - x)**2 - x**3).local_normalization(
    0, 1, nil, 3)
normalization_check("shared_tangent.branch_count",
                    shared_tangent.projection_sheets.size == 2 &&
                    shared_tangent.geometric_branch_count == 1)
normalization_check("shared_tangent.recursive_replay",
                    shared_tangent.parametrizations.all? ->
                      item.certificate.verified?)

four_sheets = (
  (y**2 - x**3)*(y**2 - x*2)).local_normalization(
    0, 1, nil, 3)
normalization_check("mixed_packets.branch_count",
                    four_sheets.projection_sheets.size == 3 &&
                    four_sheets.geometric_branch_count == 2)

shifted = (
  (y - 3)**2 - (x - 2)**3).local_normalization(
    :x, :y, [2, 3], 3)
normalization_check("shifted.coordinates",
                    shifted.parametrizations[0].
                      x_series.coefficient(0) ==
                        Expression.constant(2) &&
                    shifted.parametrizations[0].
                      y_series.coefficient(0) ==
                        Expression.constant(3) &&
                    shifted.geometric_branch_count == 1)

normalization_check("algebra.facade",
                    Algebra.local_normalization(
                      y**2 - x**3, 0, 1, nil, 3).
                      geometric_branch_count == 1)

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
projective_coordinates = P2.coords
X = projective_coordinates[0]
Y = projective_coordinates[1]
Z = projective_coordinates[2]
C = Curve.new(P2, Y**2*Z - X**3)
curve_normalization = C.local_normalization(
  [0, 0], 2, 3)
normalization_check("curve.facade",
                    curve_normalization.geometric_branch_count == 1 &&
                    curve_normalization.certificate.verified?)

tampered_parameter = LocalPlaneParametrizationCertificate.new(
  positive.sheet, positive.parameter_divisor,
  positive.ramification_index + 1,
  positive.parameter_order,
  positive.x_series, positive.y_series)
normalization_check("parameter.tamper_rejected",
                    !tampered_parameter.verified?)

tampered_normalization = (
  PlaneCurveLocalNormalizationCertificate.new(
    cusp.local_polynomial,
    cusp.projection_sheets,
    cusp.parametrizations,
    cusp.sheet_cover_certificate,
    Rational.new(2)))
normalization_check("normalization.tamper_rejected",
                    !tampered_normalization.verified?)
incomplete_cover = PlaneProjectionSheetCoverCertificate.new(
  cusp.local_polynomial, [cusp.projection_sheets[0]])
normalization_check("cover.incomplete_rejected",
                    !incomplete_cover.verified?)

normalization_check("delta.general",
                    cusp.delta == 1 &&
                    cusp.delta_certificate.verified? &&
                    cusp.delta_certificate.proof_kind ==
                      :trusted_theorem_import)
