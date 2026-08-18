# Polygons and Pick's theorem, lattice metric invariants, the Conway
# criterion, and crystallographic restriction in n dimensions.
#   bin/tungsten run spec/core/polygon_lattice_spec.w

use geometry
use combinatorics

-> plane_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# ---- polygons, exactly ------------------------------------------------

square = [[0, 0], [1, 0], [1, 1], [0, 1]]
triangle = [[0, 0], [4, 0], [0, 3]]
big = [[0, 0], [4, 0], [4, 4], [0, 4]]

plane_check("polygon.double_area_square", Polygon.double_area(square) == 2)
plane_check("polygon.double_area_triangle", Polygon.double_area(triangle) == 12)
plane_check("polygon.area_halves", Polygon.area(triangle) == 6)
# Orientation reverses with the vertex order; area does not.
plane_check("polygon.ccw", Polygon.counter_clockwise?(square))
plane_check("polygon.reverse_flips", !Polygon.counter_clockwise?(Polygon.reverse(square)))
plane_check("polygon.area_unsigned", Polygon.area(Polygon.reverse(triangle)) == 6)
plane_check("polygon.convex", Polygon.convex?(square))
plane_check("polygon.nonconvex",
            !Polygon.convex?([[0, 0], [4, 0], [4, 4], [2, 1], [0, 4]]))
plane_check("polygon.orientation_left", Polygon.orientation([0, 0], [1, 0], [0, 1]) == 1)
plane_check("polygon.orientation_collinear", Polygon.orientation([0, 0], [1, 1], [2, 2]) == 0)

plane_check("polygon.contains_interior", Polygon.contains?(big, [2, 2]))
plane_check("polygon.excludes_exterior", !Polygon.contains?(big, [9, 9]))
plane_check("polygon.boundary_counts", Polygon.contains?(big, [0, 2]))
plane_check("polygon.on_boundary", Polygon.on_boundary?(big, [4, 3]))

plane_check("polygon.segments_cross",
            Polygon.segments_intersect?([0, 0], [2, 2], [0, 2], [2, 0]))
plane_check("polygon.segments_parallel",
            !Polygon.segments_intersect?([0, 0], [1, 0], [0, 1], [1, 1]))
plane_check("polygon.segments_touch",
            Polygon.segments_intersect?([0, 0], [2, 0], [2, 0], [2, 2]))

# Interior points must not survive the hull; collinear runs collapse.
hull = Polygon.convex_hull([[0, 0], [3, 0], [3, 3], [0, 3], [1, 1], [2, 2]])
plane_check("hull.drops_interior", hull.size == 4)
plane_check("hull.collinear", Polygon.convex_hull([[0, 0], [1, 1], [2, 2], [3, 3]]).size == 2)
plane_check("hull.area", Polygon.double_area(hull) == 18)

# Minkowski sum of two unit squares is the 2 x 2 square.
sum = Polygon.minkowski_sum(square, square)
plane_check("minkowski.square", sum.size == 4 && Polygon.double_area(sum) == 8)
nfp = Polygon.no_fit_polygon(square, square)
plane_check("minkowski.no_fit", Polygon.double_area(nfp) == 8)

# ---- Pick's theorem ---------------------------------------------------

plane_check("pick.square_boundary", Polygon.boundary_points(square) == 4)
plane_check("pick.square_interior", Polygon.interior_points(square) == 0)
plane_check("pick.triangle_boundary", Polygon.boundary_points(triangle) == 8)
plane_check("pick.triangle_interior", Polygon.interior_points(triangle) == 3)
# A = I + B/2 - 1 = 3 + 4 - 1 = 6, which is the shoelace area.
plane_check("pick.recovers_area", Polygon.pick_area(3, 8) == 6)
plane_check("pick.consistent_square", Polygon.pick_consistent?(square))
plane_check("pick.consistent_triangle", Polygon.pick_consistent?(triangle))
# The 4 x 4 square holds 5 x 5 = 25 lattice points.
plane_check("pick.lattice_points", Polygon.lattice_points(big) == 25)

# ---- lattice metric invariants ----------------------------------------

z2 = LatticeMetric.z(2)
z3 = LatticeMetric.z(3)
a2 = LatticeMetric.hexagonal
a3 = LatticeMetric.a(3)
d4 = LatticeMetric.d(4)
e8 = LatticeMetric.e8

# Z^n: n orthogonal directions, so 2n neighbours and 2^n n! symmetries.
plane_check("lattice.z2_kissing", LatticeMetric.kissing_number(z2, 1) == 4)
plane_check("lattice.z3_kissing", LatticeMetric.kissing_number(z3, 1) == 6)
plane_check("lattice.z2_automorphisms", LatticeMetric.automorphism_group_order(z2, 1) == 8)
plane_check("lattice.z3_automorphisms", LatticeMetric.automorphism_group_order(z3, 1) == 48)
plane_check("lattice.z2_unimodular", LatticeMetric.unimodular?(z2))
# The square lattice's Voronoi cell is a square: four facets.
plane_check("lattice.z2_voronoi", LatticeMetric.voronoi_facet_count(z2, 1) == 4)
plane_check("lattice.z3_voronoi", LatticeMetric.voronoi_facet_count(z3, 1) == 6)

# A2 is the hexagonal lattice: six neighbours, hexagonal Voronoi cell, D6.
plane_check("lattice.hex_minimum", LatticeMetric.minimum(a2, 1) == 2)
plane_check("lattice.hex_kissing", LatticeMetric.kissing_number(a2, 1) == 6)
plane_check("lattice.hex_determinant", LatticeMetric.determinant(a2) == 3)
plane_check("lattice.hex_voronoi", LatticeMetric.voronoi_facet_count(a2, 1) == 6)
plane_check("lattice.hex_automorphisms", LatticeMetric.automorphism_group_order(a2, 1) == 12)

# A3 is the face-centred cubic lattice; its Voronoi cell is the rhombic
# dodecahedron, with twelve faces, and it has twelve nearest neighbours.
plane_check("lattice.a3_kissing", LatticeMetric.kissing_number(a3, 1) == 12)
plane_check("lattice.a3_voronoi", LatticeMetric.voronoi_facet_count(a3, 1) == 12)
plane_check("lattice.a3_determinant", LatticeMetric.determinant(a3) == 4)

plane_check("lattice.d4_kissing", LatticeMetric.kissing_number(d4, 2) == 24)
plane_check("lattice.d4_determinant", LatticeMetric.determinant(d4) == 4)

# E8 is even and unimodular — the check that the Cartan matrix is right.
plane_check("lattice.e8_determinant", LatticeMetric.determinant(e8) == 1)
plane_check("lattice.e8_even", LatticeMetric.even?(e8))
plane_check("lattice.e8_unimodular", LatticeMetric.unimodular?(e8))

plane_check("lattice.packing_radius", LatticeMetric.packing_radius_squared(z2, 1) == 0.25)
plane_check("lattice.gram_from_basis",
            LatticeMetric.gram_from_basis([[1, 0], [0, 1]])[0][0] == 1)

# ---- the Conway criterion ---------------------------------------------

plane_check("conway.monomino", ConwayCriterion.satisfied?(Polyomino.from_grid(["#"])))
plane_check("conway.domino", ConwayCriterion.satisfied?(Polyomino.from_grid(["##"])))
plane_check("conway.l_tromino", ConwayCriterion.satisfied?(Polyomino.from_grid(["#.", "##"])))
plane_check("conway.rectangle", ConwayCriterion.satisfied?(Polyomino.from_grid(["###", "###"])))
plane_check("conway.boundary_length",
            ConwayCriterion.boundary_length(Polyomino.from_grid(["##"])) == 6)
# A tile with a hole is not a topological disk, so the criterion cannot apply.
plane_check("conway.holed_excluded",
            !ConwayCriterion.satisfied?(Polyomino.from_grid(["###", "#.#", "###"])))

# Every polyomino of at most six cells satisfies it.
small_all = true
n = 1
while n <= 6
  PolyominoEnumeration.free(n).each ->(shape)
    small_all = false if !ConwayCriterion.satisfied?(shape)
  n += 1
plane_check("conway.all_small_satisfy", small_all)

# But the criterion is only sufficient, so it must also reject: some
# simply-connected octominoes fail it despite tiling the plane.
satisfied = 0
simple = 0
PolyominoEnumeration.free(8).each ->(shape)
  if shape.holes == 0
    simple += 1
    satisfied += 1 if ConwayCriterion.satisfied?(shape)
plane_check("conway.discriminates", satisfied < simple)
plane_check("conway.mostly_satisfied", satisfied * 2 > simple)

# ---- crystallographic restriction, in n dimensions --------------------

plane_check("crystal.totient_5", Crystallography.totient(5) == 4)
plane_check("crystal.totient_12", Crystallography.totient(12) == 4)
plane_check("crystal.totient_prime", Crystallography.totient(7) == 6)

-> same_orders?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

plane_check("crystal.plane_orders",
            same_orders?(Crystallography.allowed_rotation_orders(2), [1, 2, 3, 4, 6]))
# Three dimensions permit no more rotation orders than two do.
plane_check("crystal.space_orders",
            same_orders?(Crystallography.allowed_rotation_orders(3), [1, 2, 3, 4, 6]))
plane_check("crystal.four_dimensions",
            same_orders?(Crystallography.allowed_rotation_orders(4),
                         [1, 2, 3, 4, 5, 6, 8, 10, 12]))
# Five-fold symmetry is impossible in the plane but legal in four dimensions.
plane_check("crystal.no_fivefold_plane", !Crystallography.crystallographic?(5, 2))
plane_check("crystal.fivefold_in_4d", Crystallography.crystallographic?(5, 4))
plane_check("crystal.fivefold_dimension", Crystallography.lowest_dimension_for_rotation(5) == 4)
plane_check("crystal.sevenfold_dimension", Crystallography.lowest_dimension_for_rotation(7) == 6)

plane_check("crystal.bravais_2d", Crystallography.bravais_count(2) == 5)
plane_check("crystal.bravais_3d", Crystallography.bravais_count(3) == 14)
plane_check("crystal.bravais_4d", Crystallography.bravais_count(4) == 64)
plane_check("crystal.point_groups_2d", Crystallography.point_group_count(2) == 10)
plane_check("crystal.point_groups_3d", Crystallography.point_group_count(3) == 32)
plane_check("crystal.space_groups_2d", Crystallography.space_group_count(2) == 17)
plane_check("crystal.space_groups_3d", Crystallography.space_group_count(3) == 230)
plane_check("crystal.space_groups_4d", Crystallography.space_group_count(4) == 4894)
plane_check("crystal.bravais_table_3d", Crystallography.bravais_types_3d.size == 14)
plane_check("crystal.systems_3d", Crystallography.crystal_systems_3d.size == 7)
plane_check("crystal.bravais_table_2d", Crystallography.bravais_types_2d.size == 5)

# The wallpaper count from the classification must agree with the group
# implementation, and with the space-group count in dimension two.
plane_check("crystal.agrees_with_groups",
            Crystallography.space_group_count(2) == WallpaperGroup.all.size)
plane_check("crystal.agrees_with_tables",
            Crystallography.point_group_count(2) == PlaneSymmetry.point_group_count)

<< "polygon and lattice spec complete"
