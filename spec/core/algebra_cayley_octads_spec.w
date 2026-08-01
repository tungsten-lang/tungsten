# Exact determinantal-representation and Cayley-octad replay using the Edge
# quartic from Plaumann--Sturmfels--Vinzant, equations (1.5) and (3.6).
#
#   bin/tungsten run spec/core/algebra_cayley_octads_spec.w
#   bin/tungsten compile spec/core/algebra_cayley_octads_spec.w \
#     --out /tmp/algebra-cayley-octads-spec

use algebra

-> octad_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

plane = Algebra.rational_projective_plane
X = plane.coords[0]
Y = plane.coords[1]
Z = plane.coords[2]
equation = (X**4 + Y**4 + Z**4) * 25
equation = equation - (X**2*Y**2 + X**2*Z**2 + Y**2*Z**2) * 34
E = Curve.new(plane, equation)

a = [
  [0, 1, 2, 0],
  [1, 0, 0, -2],
  [2, 0, 0, 1],
  [0, -2, 1, 0]
]
b = [
  [0, 2, 0, 1],
  [2, 0, 1, 0],
  [0, 1, 0, -2],
  [1, 0, -2, 0]
]
c = [
  [0, 0, 1, -2],
  [0, 0, 2, 1],
  [1, 2, 0, 0],
  [-2, 1, 0, 0]
]

representation = PlaneQuarticSymmetricDeterminantalRepresentation.new(
  E, [a, b, c])
octad_check("representation.certified", representation.certified?, true)
octad_check("representation.scalar", representation.determinant_scalar,
            Rational.new(1))
octad_check("representation.replays_quartic",
            representation.determinant.eql?(E.equation), true)

# Dixon's constructive inverse direction.  Starting only from the Edge
# quartic and the azygetic triple in PSV Example 2.6, recover and certify a
# symmetric linear determinantal representation by exact linear algebra.
dixon_lines = [
  Line.new(E.space, [0, 1, 2]),
  Line.new(E.space, [-2, 0, 1]),
  Line.new(E.space, [1, -2, 0])
]
dixon = E.dixon_representation(dixon_lines)
octad_check("dixon.contact_space_dimension",
            dixon.contact_space_dimension, 4)
octad_check("dixon.relation_count",
            dixon.relation_certificates.size, 6)
octad_check("dixon.relations_replay",
            dixon.relation_certificates.all? -> item.verified?, true)
octad_check("dixon.cubic_determinant_nonzero",
            dixon.cubic_matrix_determinant.zero?, false)
octad_check("dixon.representation_certified",
            dixon.representation.certified?, true)
octad_check("dixon.producer_certified", dixon.certified?, true)
octad_check("dixon.existence_theorem_boundary",
            dixon.certificate.existence_theorem_kernel_checked?, false)

space = Algebra.rational_projective_three_space
points = [
  space.point([1, 0, 0, 0]),
  space.point([0, 1, 0, 0]),
  space.point([0, 0, 1, 0]),
  space.point([0, 0, 0, 1]),
  space.point([-1, 3, 1, -1]),
  space.point([1, -1, 3, -1]),
  space.point([1, 1, 1, 3]),
  space.point([3, 1, -1, -1])
]
matrix = representation.cayley_octad(points)
octad_check("octad.certified", matrix.certified?, true)
octad_check("octad.common_zeros",
            matrix.points_are_common_quadric_zeros?, true)
octad_check("octad.general_position",
            matrix.every_four_points_span?, true)
octad_check("octad.bitangent_count", matrix.bitangent_lines.size, 28)
octad_check("octad.all_bitangents",
            matrix.bitangent_lines.all? ->
              E.geometric_bitangent_line?(item), true)
octad_check("octad.principal_minors",
            matrix.principal_minors_replay_quartic?, true)
octad_check("octad.theorem_boundary",
            matrix.certificate.complete_intersection_kernel_checked?, false)

expected_first = Line.new(E.space, [1, 2, 0])
octad_check("octad.first_bitangent",
            matrix.bitangent_line(0, 1).eql?(expected_first), true)

bad_a = representation.matrices[0]
bad_a[0][1] = Rational.new(2)
bad_representation = PlaneQuarticSymmetricDeterminantalRepresentation.new(
  E, [bad_a, b, c])
octad_check("tamper.asymmetric_matrix_rejected",
            bad_representation.certified?, false)

bad_points = matrix.points
bad_points[7] = bad_points[0]
bad_octad = representation.cayley_octad(bad_points)
octad_check("tamper.duplicate_point_rejected",
            bad_octad.certified?, false)

off_quadric = matrix.points
off_quadric[7] = space.point([1, 1, 1, 1])
off_quadric_octad = representation.cayley_octad(off_quadric)
octad_check("tamper.off_quadric_point_rejected",
            off_quadric_octad.certified?, false)

constructed = CayleyOctadNet.new(points, E.space)
octad_check("producer.nullspace_dimension",
            constructed.net_basis_vectors.size, 3)
octad_check("producer.certified", constructed.certified?, true)
octad_check("producer.smooth_quartic",
            constructed.curve.nonsingular?, true)
octad_check("producer.bitangent_count",
            constructed.bitangent_matrix.bitangent_lines.size, 28)
octad_check("producer.principal_minors",
            constructed.bitangent_matrix.principal_minors_replay_quartic?,
            true)

# Elsenhans--Jahnel Example 2.12.  The construction stays over Q: the
# universal point lives in the degree-eight etale algebra rather than a
# materialized splitting field.
polynomial_ring = PolynomialRing.new([:t], RationalField.new)
t = polynomial_ring.generator(0)
octic = t**8 - t**6*5 - t**5 + t**4*7 + t**3 + t**2*4 + 1
etale_octad = Algebra.trace_zero_cayley_octad(octic, E.space)
octad_check("etale.degree", etale_octad.etale_algebra.dimension, 8)
octad_check("etale.trace_zero",
            etale_octad.etale_algebra.generator.trace,
            Rational.new(0))
octad_check("etale.universal_common_zero",
            etale_octad.matrices.all? ->
              etale_octad.quadratic_value(
                item, etale_octad.universal_point).zero?, true)
octad_check("etale.certified", etale_octad.certified?, true)
octad_check("etale.smooth_hesse_quartic",
            etale_octad.curve.nonsingular?, true)
octad_check("etale.theorem_boundary",
            etale_octad.certificate.geometric_octad_theorem_kernel_checked?,
            false)

# Shell-width candidate after the theta/Frobenius layer selects Q(i) for the
# two-point octad component.  Multiplying its trace -2 quadratic model by the
# trace +2 sextic model produces a trace-zero octic, hence an explicit
# rational Cayley-octad net with the required 2+6 etale decomposition.
shell_sextic = t**6 - t**5*2 + t**4 - t**3*2 - t**2 + 1
shell_quadratic = t**2 + t*2 + 2
shell_octic = shell_sextic * shell_quadratic
shell_etale_octad = Algebra.trace_zero_cayley_octad(
  shell_octic, E.space, [shell_sextic, shell_quadratic])
octad_check("shell_etale.trace_zero_coefficient",
            shell_octic.coeff([7]), Rational.new(0))
octad_check("shell_etale.component_degrees",
            shell_etale_octad.component_degrees.to_s, "\[6, 2\]")
octad_check("shell_etale.certified",
            shell_etale_octad.certified?, true)
octad_check("shell_etale.smooth_hesse_quartic",
            shell_etale_octad.curve.nonsingular?, true)
octad_check("shell_etale.geometric_theorem_boundary",
            shell_etale_octad.certificate.geometric_octad_theorem_kernel_checked?,
            false)

nonzero_trace = Algebra.trace_zero_cayley_octad(
  octic + t**7, E.space)
octad_check("tamper.nonzero_trace_rejected",
            nonzero_trace.certified?, false)

<< "algebra_cayley_octads_spec: all checks passed"
