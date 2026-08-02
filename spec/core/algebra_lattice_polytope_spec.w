# Exact Ehrhart, shell-polytope, Newton-polygon, and Laurent-jet regressions.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_lattice_polytope_spec.w
#   bin/tungsten compile spec/core/algebra_lattice_polytope_spec.w \
#     --out /tmp/algebra-lattice-polytope-spec

use algebra

-> polytope_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> same_vector?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

-> enumerate_shell(polytope, dilation)
  dimension = polytope.dimension
  point = []
  dimension.times -> point.push(0)
  count = [0]
  visit = nil
  visit = -> (coordinate)
    if coordinate == dimension
      count[0] += 1 if polytope.lattice_point?(point, dilation)
    else
      value = 0 - dilation
      while value <= dilation
        point[coordinate] = value
        visit.call(coordinate + 1)
        value += 1
  visit.call(0)
  count[0]

# The sharp centered simplex T_n=(n+1)Delta_n-1.
dimension = 1
while dimension <= 5
  model = CenteredEhrhartSimplex.new(dimension)
  simplex = model.simplex
  zeros = []
  dimension.times -> zeros.push(Rational.new(0))
  polytope_check("centered.[dimension].barycenter",
                 same_vector?(model.barycenter, zeros))
  polytope_check("centered.[dimension].normalized_volume",
                 simplex.normalized_volume == (dimension + 1) ** dimension)
  polytope_check("centered.[dimension].volume",
                 simplex.volume == Rational.new(
                   (dimension + 1) ** dimension, dimension.factorial))
  polytope_check("centered.[dimension].unique_interior",
                 model.unique_level_one_interior_lattice_point?)
  polytope_check("centered.[dimension].origin_inside",
                 simplex.interior_contains?(zeros))
  polytope_check("centered.[dimension].jet_count",
                 model.jet_condition_count(4) ==
                   LatticeCombinatorics.binomial(dimension + 3, dimension))
  dimension += 1

triangle = CenteredEhrhartSimplex.new(2)
polytope_check("centered.count.closed",
               triangle.lattice_point_count(2) == 28)
polytope_check("centered.count.interior",
               triangle.interior_lattice_point_count(2) == 10)

# Quotienting the d-dimensional three-sided shell along the diagonal gives a
# reflexive (d-1)-polytope with Ehrhart polynomial (k+1)^d-k^d.
hexagon = DiagonalShellPolytope.new(3)
polytope_check("shell.hexagon.vertices", hexagon.vertices.size == 6)
polytope_check("shell.hexagon.h_star",
               same_vector?(hexagon.h_star_coefficients, [1, 4, 1]))
polytope_check("shell.hexagon.volume", hexagon.volume == Rational.new(3))
polytope_check("shell.hexagon.normalized_volume",
               hexagon.normalized_volume == 6)
polytope_check("shell.hexagon.facets", hexagon.primitive_facets.size == 6)
polytope_check("shell.hexagon.reflexive",
               hexagon.reflexive_by_construction?)
k = 0
while k <= 5
  polytope_check("shell.hexagon.count.[k]",
                 enumerate_shell(hexagon, k) == hexagon.shell_count(k))
  k += 1
k = 1
while k <= 5
  polytope_check("shell.hexagon.reciprocity.[k]",
                 hexagon.reciprocity_holds?(k))
  k += 1

rhombic = DiagonalShellPolytope.new(4)
polytope_check("shell.rhombic.vertices", rhombic.vertices.size == 14)
polytope_check("shell.rhombic.h_star",
               same_vector?(rhombic.h_star_coefficients, [1, 11, 11, 1]))
polytope_check("shell.rhombic.volume", rhombic.volume == Rational.new(4))
polytope_check("shell.rhombic.normalized_volume",
               rhombic.normalized_volume == 24)
polytope_check("shell.rhombic.facets", rhombic.primitive_facets.size == 12)
polytope_check("shell.rhombic.k3", rhombic.shell_count(3) == 175)
polytope_check("shell.rhombic.enumerated",
               enumerate_shell(rhombic, 2) == rhombic.shell_count(2))
polytope_check("shell.rhombic.reciprocity", rhombic.reciprocity_holds?(4))

# The shell-width quartic Newton triangle has area 6, boundary count 8, and
# three interior lattice points, hence toric genus 3 under nondegeneracy.
newton = LatticePolygon.new([[0, 0], [3, 0], [0, 4]])
polytope_check("newton.area", newton.area == Rational.new(6))
polytope_check("newton.boundary", newton.boundary_lattice_point_count == 8)
polytope_check("newton.interior", newton.interior_lattice_point_count == 3)

# Exact Laurent jets at (1,...,1).  Four bivariate monomials have three
# independent conditions below order two, leaving a one-dimensional kernel.
jets = LaurentJetFiltration.new([[0, 0], [1, 0], [0, 1], [1, 1]])
polytope_check("jets.rows", jets.jet_matrix(2).size == 3)
polytope_check("jets.rank", jets.jet_rank(2) == 3)
polytope_check("jets.kernel", jets.vanishing_subspace_dimension(2) == 1)
polytope_check("jets.condition_bound", jets.condition_count_bound(2) == 3)
polytope_check("jets.negative_exponent",
               LaurentJetFiltration.falling_factorial(-1, 3) == -6)

duplicate_raised = false
begin
  LaurentJetFiltration.new([[0], [0]])
rescue error
  duplicate_raised = error.to_s.include?("distinct")
polytope_check("jets.duplicate_exponents.rejected", duplicate_raised)

bad_multi_index_raised = false
begin
  jets.derivative_at_one([0, 0], [1, -1])
rescue error
  bad_multi_index_raised = error.to_s.include?("nonnegative")
polytope_check("jets.multi_index.validated", bad_multi_index_raised)

<< "algebra_lattice_polytope_spec: all checks passed"
