# Lattice symmetry groups, animals in three lattices, dimer coverings,
# digital geometry, and the plane symmetry classifications.
#   bin/tungsten run spec/core/lattice_geometry_spec.w

use geometry
use combinatorics

-> lattice_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# ---- point groups, by closure from generators -------------------------

lattice_check("group.square_D4", LatticeSymmetry.square.order == 8)
lattice_check("group.hex_D6", LatticeSymmetry.hexagonal.order == 12)
lattice_check("group.cubic_rotations", LatticeSymmetry.cubic_rotations.order == 24)
lattice_check("group.cubic_full", LatticeSymmetry.cubic.order == 48)
# Half of the full cubic group is orientation preserving.
lattice_check("group.cubic_det_split", LatticeSymmetry.cubic.rotations.order == 24)
lattice_check("group.det_identity",
              LatticeSymmetry.determinant(LatticeSymmetry.identity(3)) == 1)
lattice_check("group.det_reflection",
              LatticeSymmetry.determinant([[0 - 1, 0], [0, 1]]) == 0 - 1)

# ---- animals in three lattices, against OEIS --------------------------

square = Lattice.square
hex = Lattice.hexagonal
cubic = Lattice.cubic
chiral = Lattice.cubic_chiral

sq_fixed = [1, 2, 6, 19, 63, 216]        # A001168
sq_free = [1, 1, 2, 5, 12, 35]           # A000105
hex_fixed = [1, 3, 11, 44, 186, 814]     # A001207
hex_free = [1, 1, 3, 7, 22, 82]          # A000228
cube_fixed = [1, 3, 15, 86, 534, 3481]   # A001931
cube_free = [1, 1, 2, 7, 23, 112]        # A038119, reflections allowed
cube_chiral = [1, 1, 2, 8, 29, 166]      # A000162, rotations only

n = 1
while n <= 6
  lattice_check("A001168.[n]", LatticeAnimal.count_fixed(n, square) == sq_fixed[n - 1])
  lattice_check("A000105.[n]", LatticeAnimal.count_free(n, square) == sq_free[n - 1])
  lattice_check("A001207.[n]", LatticeAnimal.count_fixed(n, hex) == hex_fixed[n - 1])
  lattice_check("A000228.[n]", LatticeAnimal.count_free(n, hex) == hex_free[n - 1])
  lattice_check("A001931.[n]", LatticeAnimal.count_fixed(n, cubic) == cube_fixed[n - 1])
  lattice_check("A038119.[n]", LatticeAnimal.count_free(n, cubic) == cube_free[n - 1])
  lattice_check("A000162.[n]", LatticeAnimal.count_free(n, chiral) == cube_chiral[n - 1])
  n += 1

# The generic square-lattice path must agree with the dedicated polyomino
# enumerator, which was verified independently.
lattice_check("cross_check.square_matches_polyomino",
              LatticeAnimal.count_free(6, square) == PolyominoEnumeration.count_free(6))

# ---- polyiamonds ------------------------------------------------------

iamond_free = [1, 1, 1, 3, 4, 12, 24]    # A000577
n = 1
while n <= 7
  lattice_check("A000577.[n]", Polyiamond.count_free(n) == iamond_free[n - 1])
  n += 1

# ---- dimer coverings --------------------------------------------------

lattice_check("dimer.2x2", DimerCovering.rectangle(2, 2) == 2)
lattice_check("dimer.2x3", DimerCovering.rectangle(2, 3) == 3)
lattice_check("dimer.3x4", DimerCovering.rectangle(3, 4) == 11)
lattice_check("dimer.4x4", DimerCovering.rectangle(4, 4) == 36)
lattice_check("dimer.6x6", DimerCovering.rectangle(6, 6) == 6728)
# The classical Kasteleyn / Fisher-Temperley number for the chessboard.
lattice_check("dimer.8x8", DimerCovering.rectangle(8, 8) == 12988816)
lattice_check("dimer.odd_area", DimerCovering.rectangle(3, 3) == 0)
# A 2 x n strip is counted by the Fibonacci numbers.
lattice_check("dimer.fibonacci",
              DimerCovering.rectangle(2, 4) == 5 && DimerCovering.rectangle(2, 5) == 8)
# Removing two same-coloured corners makes tiling impossible — the mutilated
# chessboard, and the colour argument that proves it.
mutilated = []
y = 0
while y < 8
  x = 0
  while x < 8
    mutilated.push([x, y]) if !(x == 0 && y == 0) && !(x == 7 && y == 7)
    x += 1
  y += 1
lattice_check("dimer.mutilated_chessboard", DimerCovering.region(mutilated) == 0)
lattice_check("dimer.colour_unbalanced", !DimerCovering.colour_balanced?(mutilated))

# ---- digital geometry -------------------------------------------------

diagonal = DigitalGeometry.line(0, 0, 3, 3)
lattice_check("digital.line_diagonal", diagonal.size == 4)
lattice_check("digital.line_endpoints",
              diagonal[0][0] == 0 && diagonal[3][0] == 3 && diagonal[3][1] == 3)
lattice_check("digital.line_vertical", DigitalGeometry.line(0, 0, 0, 4).size == 5)
lattice_check("digital.line_reverse", DigitalGeometry.line(5, 2, 0, 0).size ==
                                      DigitalGeometry.line(0, 0, 5, 2).size)
lattice_check("digital.circle_point", DigitalGeometry.circle(0, 0, 0).size == 1)
lattice_check("digital.circle_unit", DigitalGeometry.circle(0, 0, 1).size == 4)

apart = [[0, 0], [1, 1]]
lattice_check("digital.components_4", DigitalGeometry.connected_components(apart, 4).size == 2)
lattice_check("digital.components_8", DigitalGeometry.connected_components(apart, 8).size == 1)
lattice_check("digital.connected_8", DigitalGeometry.connected?(apart, 8))

block = []
y = 0
while y < 3
  x = 0
  while x < 3
    block.push([x, y])
    x += 1
  y += 1
lattice_check("digital.dilate", DigitalGeometry.dilate([[0, 0]], 4).size == 5)
lattice_check("digital.dilate_8", DigitalGeometry.dilate([[0, 0]], 8).size == 9)
lattice_check("digital.erode_block", DigitalGeometry.erode(block, 4).size == 1)
lattice_check("digital.boundary_block", DigitalGeometry.boundary(block, 4).size == 8)
distances = DigitalGeometry.distance_transform(block, 4)
lattice_check("digital.distance_centre", distances.fetch("1,1", 0) == 2)
lattice_check("digital.distance_corner", distances.fetch("0,0", 0) == 1)
lattice_check("digital.inradius", DigitalGeometry.inradius(block, 4) == 2)

# ---- plane symmetry classification ------------------------------------

lattice_check("plane.wallpaper_17", PlaneSymmetry.wallpaper_count == 17)
lattice_check("plane.frieze_7", PlaneSymmetry.frieze_count == 7)
lattice_check("plane.point_groups_10", PlaneSymmetry.point_group_count == 10)
# The crystallographic restriction: no five-fold symmetry in a lattice.
lattice_check("plane.restriction_allows_6", PlaneSymmetry.crystallographic?(6))
lattice_check("plane.restriction_forbids_5", !PlaneSymmetry.crystallographic?(5))
lattice_check("plane.restriction_forbids_7", !PlaneSymmetry.crystallographic?(7))
lattice_check("plane.p6m_rotation", PlaneSymmetry.wallpaper("p6m")[1] == 6)
lattice_check("plane.square_groups", PlaneSymmetry.wallpaper_with_rotation(4).size == 3)

# ---- Kasteleyn: matchings as a determinant ----------------------------

k22 = Kasteleyn.matrix(2, 2)
lattice_check("kasteleyn.skew_symmetric", Kasteleyn.skew_symmetric?(k22))
lattice_check("kasteleyn.det_2x2", Kasteleyn.determinant(k22) == 4)
# Pf^2 = det is the identity the whole theorem rests on.
lattice_check("kasteleyn.pfaffian_squared",
              Kasteleyn.pfaffian(k22) * Kasteleyn.pfaffian(k22) == Kasteleyn.determinant(k22))
lattice_check("kasteleyn.tilings_2x2", Kasteleyn.tilings(2, 2) == 2)
lattice_check("kasteleyn.tilings_4x4", Kasteleyn.tilings(4, 4) == 36)
lattice_check("kasteleyn.tilings_6x6", Kasteleyn.tilings(6, 6) == 6728)
lattice_check("kasteleyn.tilings_8x8", Kasteleyn.tilings(8, 8) == 12988816)
lattice_check("kasteleyn.odd_grid", Kasteleyn.tilings(3, 3) == 0)

# The Pfaffian route, kept to small grids because the expansion is
# exponential, and it must agree with both other methods.
lattice_check("pfaffian.2x3", Kasteleyn.tilings_by_pfaffian(2, 3) == 3)
lattice_check("pfaffian.2x4", Kasteleyn.tilings_by_pfaffian(2, 4) == 5)
lattice_check("pfaffian.3x4", Kasteleyn.tilings_by_pfaffian(3, 4) == 11)
k34 = Kasteleyn.matrix(3, 4)
lattice_check("pfaffian.identity_3x4",
              Kasteleyn.pfaffian(k34) * Kasteleyn.pfaffian(k34) == Kasteleyn.determinant(k34))

# Three independent methods, one answer.
lattice_check("dimer.methods_agree_4x4",
              Kasteleyn.tilings(4, 4) == DimerCovering.rectangle(4, 4))
lattice_check("dimer.methods_agree_2x4",
              Kasteleyn.tilings_by_pfaffian(2, 4) == DimerCovering.rectangle(2, 4))

# ---- wallpaper groups, as groups --------------------------------------

lattice_check("wallpaper.seventeen", WallpaperGroup.all.size == 17)

expected_orders = [["p1", 1], ["p2", 2], ["pm", 2], ["pg", 2], ["cm", 2],
                   ["pmm", 4], ["pmg", 4], ["pgg", 4], ["cmm", 4], ["p4", 4],
                   ["p4m", 8], ["p4g", 8], ["p3", 3], ["p3m1", 6],
                   ["p31m", 6], ["p6", 6], ["p6m", 12]]
i = 0
while i < expected_orders.size
  group = WallpaperGroup.named(expected_orders[i][0])
  lattice_check("wallpaper.order.[expected_orders[i][0]]",
                group.point_group_order == expected_orders[i][1])
  # Closure is an audit of the generators: wrong ones would not close here.
  lattice_check("wallpaper.closed.[expected_orders[i][0]]", group.closed?)
  i += 1

# The translation part is what separates these pairs: pm has a mirror line,
# pg only a glide, and likewise pmm against pgg.
lattice_check("wallpaper.pm_reflects", WallpaperGroup.pm.has_reflection?)
lattice_check("wallpaper.pm_no_glide", !WallpaperGroup.pm.has_glide?)
lattice_check("wallpaper.pg_glides", WallpaperGroup.pg.has_glide?)
lattice_check("wallpaper.pg_no_mirror", !WallpaperGroup.pg.has_reflection?)
lattice_check("wallpaper.pmm_reflects", WallpaperGroup.pmm.has_reflection?)
lattice_check("wallpaper.pgg_glides", WallpaperGroup.pgg.has_glide?)
lattice_check("wallpaper.pgg_no_mirror", !WallpaperGroup.pgg.has_reflection?)

lattice_check("wallpaper.p1_rotation", WallpaperGroup.p1.highest_rotation_order == 1)
lattice_check("wallpaper.p3_rotation", WallpaperGroup.p3.highest_rotation_order == 3)
lattice_check("wallpaper.p4_rotation", WallpaperGroup.p4.highest_rotation_order == 4)
lattice_check("wallpaper.p6m_rotation", WallpaperGroup.p6m.highest_rotation_order == 6)
lattice_check("wallpaper.orbit_size", WallpaperGroup.p4.orbit([1, 0]).size == 4)
lattice_check("wallpaper.p1_orbit_trivial", WallpaperGroup.p1.orbit([3, 5]).size == 1)

<< "lattice geometry spec complete"
