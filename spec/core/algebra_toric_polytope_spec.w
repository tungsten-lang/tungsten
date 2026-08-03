# Exact sparse Newton polytopes and homogenized Ehrhart cones.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_toric_polytope_spec.w
#   bin/tungsten compile spec/core/algebra_toric_polytope_spec.w \
#     --out /tmp/algebra-toric-polytope-spec

use algebra

-> toric_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> toric_same_vector?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

# The unit segment has h*(t)=1 and codegree/Gorenstein index two.
segment = LatticePolytope.new([[0], [1]])
toric_check("segment.dimension", segment.dimension == 1)
toric_check("segment.vertices",
            segment.vertices.size == 2 &&
            segment.lattice_point?([0]) && segment.lattice_point?([1]))
toric_check("segment.facets", segment.facet_count == 2)
toric_check("segment.saturated", segment.saturated_projection?)
toric_check("segment.count.4", segment.lattice_point_count(4) == 5)
toric_check("segment.interior.4", segment.interior_lattice_point_count(4) == 3)
toric_check("segment.h_star", toric_same_vector?(segment.h_star_coefficients, [1, 0]))
toric_check("segment.normalized_volume", segment.normalized_volume == 1)
toric_check("segment.gorenstein", segment.gorenstein_index == 2)

reflexive_segment = LatticePolytope.new([[-1], [1]])
toric_check("segment.reflexive", reflexive_segment.reflexive?)
translated_reflexive_segment = LatticePolytope.new([[0], [2]])
toric_check("segment.translated_reflexive.strict",
            !translated_reflexive_segment.reflexive?)
toric_check("segment.translated_reflexive.invariant",
            translated_reflexive_segment.reflexive_up_to_translation?)
toric_check("segment.translated_reflexive.center",
            toric_same_vector?(translated_reflexive_segment.reflexive_center, [1]))

# Coordinate projection chooses the saturated second coordinate rather than
# silently treating the first-coordinate image 2Z as Z.
slanted = LatticePolytope.new([[0, 0], [2, 1]])
toric_check("slanted.saturated", slanted.saturated_projection?)
toric_check("slanted.pivot", toric_same_vector?(slanted.pivot_coordinates, [1]))
toric_check("slanted.count.2", slanted.lattice_point_count(2) == 3)

# Standard two-simplex and unit square fixtures.
triangle = LatticePolytope.new([[0, 0], [1, 0], [0, 1]])
toric_check("triangle.dimension", triangle.dimension == 2)
toric_check("triangle.facets", triangle.facet_count == 3)
toric_check("triangle.count.3", triangle.lattice_point_count(3) == 10)
toric_check("triangle.h_star", toric_same_vector?(triangle.h_star_coefficients, [1, 0, 0]))
toric_check("triangle.normalized_volume", triangle.normalized_volume == 1)

horizontal = LatticePolytope.new([[0, 0], [1, 0]])
vertical = LatticePolytope.new([[0, 0], [0, 1]])
square = horizontal.minkowski_sum(vertical)
toric_check("square.vertices", square.vertices.size == 4)
toric_check("square.facets", square.facet_count == 4)
toric_check("square.count.2", square.lattice_point_count(2) == 9)
toric_check("square.h_star", toric_same_vector?(square.h_star_coefficients, [1, 1, 0]))
toric_check("square.normalized_volume", square.normalized_volume == 2)

# Homogeneous supports live in a proper affine hyperplane of the ambient
# lattice.  The exact affine dimension and Ehrhart data must be intrinsic.
ring = PolynomialRing.new([:x1, :x2, :x3], RationalField.new)
x1, x2, x3 = ring.generators
u = x1*x2 + x1*x3 + x2*x3
newton_u = u.newton_polytope
toric_check("newton.factory", newton_u.class_name == "LatticePolytope")
toric_check("newton.ambient", newton_u.ambient_dimension == 3)
toric_check("newton.affine", newton_u.dimension == 2)
toric_check("newton.saturated", newton_u.saturated_projection?)
toric_check("newton.vertices", newton_u.vertices.size == 3)
toric_check("newton.facets", newton_u.facet_count == 3)
toric_check("newton.count.2", newton_u.lattice_point_count(2) == 6)
toric_check("newton.h_star", toric_same_vector?(newton_u.h_star_coefficients, [1, 0, 0]))
toric_check("newton.minimum_weight", newton_u.minimum_weight([1, 1, 0]) == 1)
toric_check("newton.minimizing_face", newton_u.minimizing_face([1, 1, 0]).size == 2)

# Translating the Newton segment of 1+x+x^2 by its unique interior point
# gives x^-1+1+x.  Its fundamental constant terms are the central trinomial
# coefficients.
univariate_ring = PolynomialRing.new([:x], RationalField.new)
x = univariate_ring.generators[0]
central_trinomial_period = (univariate_ring.one + x + x*x).toric_hypersurface_period
toric_check("period.center",
            toric_same_vector?(central_trinomial_period.center, [1]))
toric_check("period.laurent_terms",
            central_trinomial_period.normalized_laurent_terms.size == 3)
toric_check("period.central_trinomial",
            toric_same_vector?(
              central_trinomial_period.coefficients(5), [1, 1, 3, 7, 19, 51]))

cone = newton_u.homogenized_cone
toric_check("cone.dimension", cone.dimension == 3)
toric_check("cone.ambient", cone.ambient_dimension == 4)
toric_check("cone.rays", cone.rays.size == 3)
toric_check("cone.slice.2", cone.slice_lattice_point_count(2) == 6)
toric_check("cone.semigroup.in", cone.contains_semigroup_point?([2, 1, 1, 2]))
toric_check("cone.semigroup.out", !cone.contains_semigroup_point?([2, 0, 0, 0]))
toric_check("cone.hilbert_numerator", toric_same_vector?(cone.hilbert_numerator, [1, 0, 0]))
toric_check("cone.hilbert_denominator", cone.hilbert_denominator_power == 3)

# A zero polynomial has no support polytope.
zero_rejected = false
begin
  ring.zero.newton_polytope
rescue error
  zero_rejected = error.to_s.include?("zero polynomial")
toric_check("newton.zero.rejected", zero_rejected)

period_center_rejected = false
begin
  (univariate_ring.one + x).toric_hypersurface_period
rescue error
  period_center_rejected = error.to_s.include?("one interior lattice point")
toric_check("period.center.rejected", period_center_rejected)

<< "algebra_toric_polytope_spec: all checks passed"
