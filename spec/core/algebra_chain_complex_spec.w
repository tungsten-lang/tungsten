# Chain complexes of free abelian groups: d d = 0, integral homology with
# torsion, Betti numbers, Euler characteristics, and the standard spaces.
#   bin/tungsten run spec/core/algebra_chain_complex_spec.w
#   bin/tungsten compile spec/core/algebra_chain_complex_spec.w \
#     --out /tmp/algebra-chain-complex-spec

use algebra

-> chain_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> chain_z(rank)
  FinitelyGeneratedAbelianGroup.free(rank)

-> chain_zmod(order)
  FinitelyGeneratedAbelianGroup.cyclic(order)

-> chain_same?(left, right)
  SmithNormalForm.same_vector?(left, right)

# Homology groups of a complex equal an expected list, degree by degree.
-> chain_homology_is?(complex, expected)
  groups = complex.homology_groups
  return false if groups.size != expected.size
  k = 0
  while k < groups.size
    return false if !(groups[k] == expected[k])
    k += 1
  true

trivial = FinitelyGeneratedAbelianGroup.trivial

# --- The standard one-vertex cellular models ---------------------------------
point = IntegerChainComplex.point
chain_check("point.homology", chain_homology_is?(point, [chain_z(1)]))
chain_check("point.euler", point.euler_characteristic == 1 && point.betti_euler_characteristic == 1)
chain_check("point.acyclic", point.acyclic? && point.certified?)
chain_check("point.top_degree", point.top_degree == 0 && point.dimension(0) == 1 && point.dimension(1) == 0)

circle = IntegerChainComplex.circle
chain_check("circle.homology", chain_homology_is?(circle, [chain_z(1), chain_z(1)]))
chain_check("circle.betti", chain_same?(circle.betti_numbers, [1, 1]))
chain_check("circle.euler", circle.euler_characteristic == 0)
chain_check("circle.homology_sphere", circle.homology_sphere?(1) && !circle.homology_sphere?(2))
chain_check("circle.sphere_one_is_circle", chain_homology_is?(IntegerChainComplex.sphere(1), [chain_z(1), chain_z(1)]))

zero_sphere = IntegerChainComplex.sphere(0)
chain_check("sphere0.two_points", chain_homology_is?(zero_sphere, [chain_z(2)]) && zero_sphere.euler_characteristic == 2)
two_sphere = IntegerChainComplex.sphere(2)
chain_check("sphere2.dimensions", chain_same?(two_sphere.dimensions, [1, 0, 1]))
chain_check("sphere2.homology", chain_homology_is?(two_sphere, [chain_z(1), trivial, chain_z(1)]))
chain_check("sphere2.zero_rank_boundaries",
            two_sphere.boundary(1) == nil && two_sphere.boundary(2) == nil &&
            two_sphere.boundary_rank(1) == 0 && two_sphere.boundary_rank(2) == 0)
chain_check("sphere2.euler", two_sphere.euler_characteristic == 2 && two_sphere.betti_euler_characteristic == 2)
chain_check("sphere2.homology_sphere", two_sphere.homology_sphere?(2) && !two_sphere.homology_sphere?(1))
three_sphere = IntegerChainComplex.sphere(3)
chain_check("sphere3.homology", chain_homology_is?(three_sphere, [chain_z(1), trivial, trivial, chain_z(1)]))
chain_check("sphere3.euler_zero", three_sphere.euler_characteristic == 0)
chain_check("sphere.euler_parity",
            IntegerChainComplex.sphere(4).euler_characteristic == 2 &&
            IntegerChainComplex.sphere(5).euler_characteristic == 0)
chain_check("sphere.certified", two_sphere.certified? && three_sphere.certified?)

torus = IntegerChainComplex.torus
chain_check("torus.homology", chain_homology_is?(torus, [chain_z(1), chain_z(2), chain_z(1)]))
chain_check("torus.betti", chain_same?(torus.betti_numbers, [1, 2, 1]) && torus.betti(1) == 2)
chain_check("torus.euler", torus.euler_characteristic == 0)
chain_check("torus.torsion_free", torus.torsion(1).size == 0 && torus.torsion(2).size == 0)
chain_check("torus.certified", torus.certified?)

klein = IntegerChainComplex.klein_bottle
chain_check("klein.h1", klein.homology(1) == FinitelyGeneratedAbelianGroup.new(1, [2]))
chain_check("klein.h2_trivial", klein.homology(2).trivial?)
chain_check("klein.torsion", chain_same?(klein.torsion(1), [2]))
chain_check("klein.betti", chain_same?(klein.betti_numbers, [1, 1, 0]))
chain_check("klein.euler", klein.euler_characteristic == 0 && klein.betti_euler_characteristic == 0)
chain_check("klein.certified", klein.certified?)

projective = IntegerChainComplex.projective_plane
chain_check("rp2.homology", chain_homology_is?(projective, [chain_z(1), chain_zmod(2), trivial]))
chain_check("rp2.euler", projective.euler_characteristic == 1)
chain_check("rp2.certified", projective.certified?)

lens5 = IntegerChainComplex.lens_space(5)
chain_check("lens5.homology", chain_homology_is?(lens5, [chain_z(1), chain_zmod(5), trivial, chain_z(1)]))
chain_check("lens5.euler", lens5.euler_characteristic == 0)
chain_check("lens5.not_homology_sphere", !lens5.homology_sphere?(3))
chain_check("lens1.is_three_sphere", IntegerChainComplex.lens_space(1).homology_sphere?(3))
lens_ok = true
p = 2
while p <= 7
  lens = IntegerChainComplex.lens_space(p)
  lens_ok = false if !(lens.homology(1) == chain_zmod(p))
  lens_ok = false if !lens.certified?
  p += 1
chain_check("lens.h1_cyclic_grid", lens_ok)
# p = 0 is S^1 x S^2: H = (Z, Z, Z, Z).
chain_check("lens0.s1_times_s2",
            chain_homology_is?(IntegerChainComplex.lens_space(0), [chain_z(1), chain_z(1), chain_z(1), chain_z(1)]))

# --- Simplicial and Delta-complex fixtures --------------------------------------
# Triangle boundary: vertices v0 v1 v2, edges e0 = v0 v1, e1 = v1 v2,
# e2 = v2 v0.
triangle_boundary = IntegerChainComplex.new(
  [3, 3], [[[-1, 0, 1], [1, -1, 0], [0, 1, -1]]])
chain_check("triangle_boundary.homology", chain_homology_is?(triangle_boundary, [chain_z(1), chain_z(1)]))
chain_check("triangle_boundary.ranks",
            triangle_boundary.boundary_rank(1) == 2 && triangle_boundary.cycle_rank(1) == 1 &&
            triangle_boundary.cycle_rank(0) == 3)
chain_check("triangle_boundary.certified", triangle_boundary.certified?)
# Filling the triangle with one 2-cell whose boundary is e0 + e1 + e2.
filled_triangle = IntegerChainComplex.new(
  [3, 3, 1], [[[-1, 0, 1], [1, -1, 0], [0, 1, -1]], [[1], [1], [1]]])
chain_check("filled_triangle.acyclic", filled_triangle.acyclic?)
chain_check("filled_triangle.homology", chain_homology_is?(filled_triangle, [chain_z(1), trivial, trivial]))
chain_check("filled_triangle.euler", filled_triangle.euler_characteristic == 1)
chain_check("filled_triangle.certified", filled_triangle.certified?)

# Hatcher's Delta-complex torus: one vertex, edges a b c, faces U L with
# dU = dL = a + b - c.
delta_torus = IntegerChainComplex.new(
  [1, 3, 2], [[[0, 0, 0]], [[1, 1], [1, 1], [-1, -1]]])
chain_check("delta_torus.homology", chain_homology_is?(delta_torus, [chain_z(1), chain_z(2), chain_z(1)]))
chain_check("delta_torus.euler", delta_torus.euler_characteristic == 0)
chain_check("delta_torus.certified", delta_torus.certified?)
# Hatcher's Klein bottle: dU = a + b - c, dL = a - b + c.
delta_klein = IntegerChainComplex.new(
  [1, 3, 2], [[[0, 0, 0]], [[1, 1], [1, -1], [-1, 1]]])
chain_check("delta_klein.homology",
            chain_homology_is?(delta_klein, [chain_z(1), FinitelyGeneratedAbelianGroup.new(1, [2]), trivial]))
chain_check("delta_klein.certified", delta_klein.certified?)
# Hatcher's RP^2: vertices v w, edges a b (v -> w) and c (w -> w... no: c
# from v to v is a loop), faces dU = -a + b + c, dL = a - b + c.
delta_rp2 = IntegerChainComplex.new(
  [2, 3, 2], [[[-1, -1, 0], [1, 1, 0]], [[-1, 1], [1, -1], [1, 1]]])
chain_check("delta_rp2.homology", chain_homology_is?(delta_rp2, [chain_z(1), chain_zmod(2), trivial]))
chain_check("delta_rp2.euler", delta_rp2.euler_characteristic == 1)
chain_check("delta_rp2.certified", delta_rp2.certified?)

# --- Mixed free and torsion parts ---------------------------------------------
mixed = IntegerChainComplex.new([1, 2, 1], [[[0, 0]], [[3], [0]]])
chain_check("mixed.h1", mixed.homology(1) == FinitelyGeneratedAbelianGroup.new(1, [3]))
chain_check("mixed.h2_trivial", mixed.homology(2).trivial?)
chain_check("mixed.betti_and_torsion", chain_same?(mixed.betti_numbers, [1, 1, 0]) && chain_same?(mixed.torsion(1), [3]))
chain_check("mixed.certified", mixed.certified?)
# Two cells with boundary 2 and 3 on the same loop: 6-torsion... no, the
# image is generated by 2 and 3, hence everything: H_1 = 0 and H_2 = Z.
coprime = IntegerChainComplex.new([1, 1, 2], [[[0]], [[2, 3]]])
chain_check("coprime.h1_trivial", coprime.homology(1).trivial?)
chain_check("coprime.h2_free", coprime.homology(2) == chain_z(1))
chain_check("coprime.certified", coprime.certified?)
# Boundaries 4 and 6 generate 2Z: H_1 = Z/2, H_2 = Z.
even = IntegerChainComplex.new([1, 1, 2], [[[0]], [[4, 6]]])
chain_check("even.h1", even.homology(1) == chain_zmod(2) && even.homology(2) == chain_z(1))
# Disjoint union of two circles.
two_circles = IntegerChainComplex.new([2, 2], [[[0, 0], [0, 0]]])
chain_check("two_circles.homology", chain_homology_is?(two_circles, [chain_z(2), chain_z(2)]))
chain_check("two_circles.euler", two_circles.euler_characteristic == 0)
# A wedge of two circles.
wedge = IntegerChainComplex.new([1, 2], [[[0, 0]]])
chain_check("wedge.homology", chain_homology_is?(wedge, [chain_z(1), chain_z(2)]))
# Zero-dimensional chain groups in the middle are skipped, not multiplied.
gap = IntegerChainComplex.new([1, 0, 2, 0, 1], [[], [], [], []])
chain_check("gap.homology", chain_homology_is?(gap, [chain_z(1), trivial, chain_z(2), trivial, chain_z(1)]))
chain_check("gap.euler", gap.euler_characteristic == 4 && gap.betti_euler_characteristic == 4)
chain_check("gap.certified", gap.certified?)

# --- Accessors and out-of-range degrees --------------------------------------
chain_check("access.homology_out_of_range", torus.homology(-1).trivial? && torus.homology(5).trivial?)
chain_check("access.boundary_out_of_range", torus.boundary(0) == nil && torus.boundary(3) == nil)
chain_check("access.boundary_matrix", SmithNormalForm.same_matrix?(klein.boundary(2), [[0], [2]]))
chain_check("access.dimension_out_of_range", torus.dimension(-1) == 0 && torus.dimension(3) == 0)
chain_check("access.homology_groups_size", torus.homology_groups.size == 3)
chain_check("access.to_s", klein.to_s.include?("Z (+) Z/2"))
chain_check("access.certificate_kind",
            torus.certificate.proof_kind == :smith_normal_form_homology &&
            torus.certificate.kernel_checked? && torus.certificate.complex == torus)

# --- Validation ------------------------------------------------------------------
dd_raised = false
begin
  IntegerChainComplex.new([1, 2, 1], [[[1, 0]], [[1], [0]]])
rescue error
  dd_raised = true
chain_check("validate.d_squared_nonzero", dd_raised)
shape_raised = false
begin
  IntegerChainComplex.new([2, 2], [[[1, 0]]])
rescue error
  shape_raised = true
chain_check("validate.wrong_row_count", shape_raised)
width_raised = false
begin
  IntegerChainComplex.new([1, 2], [[[1]]])
rescue error
  width_raised = true
chain_check("validate.wrong_column_count", width_raised)
count_raised = false
begin
  IntegerChainComplex.new([1, 1], [])
rescue error
  count_raised = true
chain_check("validate.missing_boundary", count_raised)
negative_raised = false
begin
  IntegerChainComplex.new([1, -1], [[[0]]])
rescue error
  negative_raised = true
chain_check("validate.negative_rank", negative_raised)
empty_raised = false
begin
  IntegerChainComplex.new([], [])
rescue error
  empty_raised = true
chain_check("validate.no_chain_groups", empty_raised)
chain_check("validate.foreign_certificate", !IntegerChainComplexCertificate.new("nope").verified?)

<< "algebra_chain_complex_spec: all checks passed"
