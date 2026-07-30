# Certified plane-curve multiplicity, tangent cones, and ordinary points.

use algebra

-> singularity_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :lex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

smooth = (y - x**2).singularity_at
singularity_check("smooth.multiplicity",
                  smooth.multiplicity == 1)
singularity_check("smooth.predicates",
                  smooth.smooth? && !smooth.singular?)
singularity_check("smooth.tangent",
                  smooth.tangent_cone == y)
singularity_check("smooth.delta",
                  smooth.ordinary? && smooth.delta == 0)

node = (y**2 - x**2 - x**3).singularity_at
singularity_check("node.multiplicity",
                  node.multiplicity == 2)
singularity_check("node.tangent_cone",
                  node.tangent_cone == y**2 - x**2)
singularity_check("node.slope_polynomial",
                  node.slope_polynomial ==
                  PolynomialRing.new(
                    [:slope], Q, :lex).generator(0)**2 - 1)
singularity_check("node.directions",
                  node.tangent_directions.size == 2 &&
                  node.tangent_direction_count == 2)
singularity_check("node.ordinary",
                  node.ordinary_singularity?)
singularity_check("node.delta",
                  node.delta == 1)
singularity_check("node.delta_certificate",
                  node.delta_certificate.verified? &&
                  node.delta_certificate.proof_kind ==
                    :trusted_theorem_import &&
                  !node.delta_certificate.kernel_checked?)
singularity_check("node.certificate",
                  node.certificate.verified?)

cusp = (y**2 - x**3).singularity_at
singularity_check("cusp.multiplicity",
                  cusp.multiplicity == 2)
singularity_check("cusp.repeated_tangent",
                  cusp.tangent_direction_count == 1 &&
                  cusp.tangent_directions[0].multiplicity == 2)
singularity_check("cusp.not_ordinary", !cusp.ordinary?)
cusp_delta_rejected = false
begin
  cusp.delta
rescue error
  cusp_delta_rejected = true
singularity_check("cusp.delta_boundary",
                  cusp_delta_rejected)

vertical = (x**2 - y**3).singularity_at
singularity_check("vertical.multiplicity",
                  vertical.vertical_tangent_multiplicity == 2)
singularity_check("vertical.direction",
                  vertical.tangent_directions.size == 1 &&
                  vertical.tangent_directions[0].vertical? &&
                  vertical.tangent_directions[0].multiplicity == 2)

algebraic_node = (y**2 - x**2*2 - x**3).singularity_at
algebraic_direction = algebraic_node.tangent_directions[0]
singularity_check("algebraic_tangent.degree",
                  algebraic_direction.residue_degree == 2 &&
                  !algebraic_direction.rational?)
singularity_check("algebraic_tangent.ordinary",
                  algebraic_node.ordinary? &&
                  algebraic_node.tangent_direction_count == 2)
algebraic_tangent_field = algebraic_direction.residue_field
singularity_check("algebraic_tangent.field",
                  algebraic_tangent_field.degree == 2 &&
                  algebraic_tangent_field.modulus_certificate.verified?)

ordinary_triple_equation = (
  y*(y - x)*(y + x) + x**4)
ordinary_triple = ordinary_triple_equation.singularity_at
singularity_check("triple.multiplicity",
                  ordinary_triple.multiplicity == 3)
singularity_check("triple.directions",
                  ordinary_triple.tangent_direction_count == 3)
singularity_check("triple.ordinary",
                  ordinary_triple.ordinary_singularity?)
singularity_check("triple.delta",
                  ordinary_triple.delta == 3 &&
                  ordinary_triple.delta_certificate.verified?)

shifted_equation = (
  (y - 3)**2 - (x - 2)**2 - (x - 2)**3)
shifted = shifted_equation.singularity_at(
  :x, :y, [2, 3])
singularity_check("shifted.point",
                  shifted.point[0] == 2 &&
                  shifted.point[1] == 3)
singularity_check("shifted.node",
                  shifted.ordinary_singularity? &&
                  shifted.delta == 1)

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
projective_coordinates = P2.coords
X = projective_coordinates[0]
Y = projective_coordinates[1]
Z = projective_coordinates[2]
nodal_cubic = Curve.new(
  P2, Y**2*Z - X**2*Z - X**3)
curve_singularity = nodal_cubic.singularity_at([0, 0], 2)
singularity_check("curve.facade",
                  curve_singularity.ordinary_singularity? &&
                  curve_singularity.delta == 1)
singularity_check("algebra.facade",
                  Algebra.local_singularity(
                    y**2 - x**3).multiplicity == 2)

tampered = PlaneCurveLocalSingularityCertificate.new(
  node.source_polynomial, 0, 1, node.point,
  node.local_polynomial, 3, node.tangent_cone,
  node.slope_polynomial,
  node.vertical_tangent_multiplicity,
  node.tangent_directions)
singularity_check("certificate.tamper_rejected",
                  !tampered.verified?)

off_curve_rejected = false
begin
  (y**2 - x).singularity_at(0, 1, [1, 0])
rescue error
  off_curve_rejected = true
singularity_check("boundary.off_curve",
                  off_curve_rejected)

sheets = (y**2 - x**3).puiseux_sheets(
  0, 1, nil, 3)
singularity_check("sheets.explicit_surface",
                  sheets.size == 2 &&
                  sheets[0].projection_sheet? &&
                  sheets[0].ramified?)
