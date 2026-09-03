# Polyform grids and shapes: square, hexagonal, iamond.
# Run:
#   bin/tungsten spec/core/tiling_grid_spec.w

use geometry

-> tiling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

square = TilingGrid.square
hex = TilingGrid.hexagonal
iamond = TilingGrid.iamond

# ---- point groups ------------------------------------------------------

tiling_check("orientations.square", square.orientation_count == 8)
tiling_check("orientations.hex", hex.orientation_count == 12)
tiling_check("orientations.iamond", iamond.orientation_count == 12)
tiling_check("orientations.identity", hex.orientation(0) == [1, 0, 0, 0, 1, 0])

# Composing two orientations gives an orientation: the tables are closed.
[square, hex, iamond].each ->(grid)
  closed = true
  i = 0
  while i < grid.orientation_count
    j = 0
    while j < grid.orientation_count
      p = grid.orientation(i)
      q = grid.orientation(j)
      # q after p, as an affine map
      comp = [q[0] * p[0] + q[1] * p[3], q[0] * p[1] + q[1] * p[4], q[0] * p[2] + q[1] * p[5] + q[2],
              q[3] * p[0] + q[4] * p[3], q[3] * p[1] + q[4] * p[4], q[3] * p[2] + q[4] * p[5] + q[5]]
      closed = false if !grid.transform_legal?(comp)
      j += 1
    i += 1
  tiling_check("group.closed.[grid.name]", closed)

# A shear has determinant one and is not a motion.
tiling_check("shear.rejected", !square.transform_legal?([1, 1, 0, 0, 1, 0]))
tiling_check("reflection.detected", hex.reflection?(hex.orientation(6)))
tiling_check("rotation.detected", !hex.reflection?(hex.orientation(1)))

# ---- adjacency -----------------------------------------------------------

tiling_check("degree.square", square.edge_degree == 4 && square.contact_degree == 8)
tiling_check("degree.hex", hex.edge_degree == 6 && hex.contact_degree == 6)
tiling_check("degree.iamond", iamond.edge_degree == 3 && iamond.contact_degree == 12)
tiling_check("halo.square_cell", square.halo([[0, 0]]).size == 8)
tiling_check("halo.hex_cell", hex.halo([[0, 0]]).size == 6)
tiling_check("halo.iamond_cell", iamond.halo([[0, 0]]).size == 12)

# Iamond cells sit on x ≡ y (mod 3); translations are multiples of three.
tiling_check("iamond.valid_up", iamond.cell_valid?([0, 0]) && iamond.up?([0, 0]))
tiling_check("iamond.valid_down", iamond.cell_valid?([1, 1]) && !iamond.up?([1, 1]))
tiling_check("iamond.invalid", !iamond.cell_valid?([0, 1]) && !iamond.cell_valid?([2, 2]))
tiling_check("iamond.translation", iamond.translation_legal?(3, -6) && !iamond.translation_legal?(1, 1))
tiling_check("iamond.edge_neighbours_valid",
             iamond.edge_neighbours([0, 0]).select(->(c) !iamond.cell_valid?(c)).size == 0)

# ---- holes and connectivity ------------------------------------------------

ring6 = [[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]]
tiling_check("holes.hex_ring", hex.holes(ring6).size == 1)
tiling_check("holes.square_ring",
             square.holes([[0, 0], [1, 0], [2, 0], [0, 1], [2, 1], [0, 2], [1, 2], [2, 2]]).size == 1)
tiling_check("holes.hex_flower", hex.holes(ring6 + [[0, 0]]).size == 0)
tiling_check("connected.yes", hex.connected?([[0, 0], [1, 0], [1, 1]]))
tiling_check("connected.no", !hex.connected?([[0, 0], [2, 0]]))

# ---- polyforms ------------------------------------------------------------

eleven = Polyform.parse("H -3 2 -3 4 -2 2 -2 4 -1 1 -1 3 0 0 0 1 0 2 0 3 1 0")
tiling_check("parse.normalized", eleven.to_s == "H 0 2 0 4 1 2 1 4 2 1 2 3 3 0 3 1 3 2 3 3 4 0")
tiling_check("parse.size", eleven.size == 11)
tiling_check("parse.span", eleven.span == [5, 5])
tiling_check("parse.halo", eleven.halo.size == 21)
tiling_check("parse.hole_free", eleven.hole_free?)
tiling_check("parse.unclassified_marker", Polyform.parse("H? 0 0 1 0").size == 2)

rotated = Polyform.new(hex, eleven.image(3))
tiling_check("congruent.rotated", rotated.congruent?(eleven))
tiling_check("congruent.not_equal_as_fixed", !(rotated == eleven) || rotated.key == eleven.key)
tiling_check("canonical.stable", eleven.canonical.canonical_key == eleven.canonical_key)
tiling_check("symmetry.asymmetric", eleven.symmetry_order == 1)
tiling_check("symmetry.flower", Polyform.new(hex, ring6 + [[0, 0]]).symmetry_order == 12)
tiling_check("symmetry.bar", Polyform.parse("H 0 0 1 0 2 0").symmetry_order == 4)
tiling_check("symmetry.square", Polyform.parse("O 0 0 1 0 0 1 1 1").symmetry_order == 8)
tiling_check("symmetry.triangle", Polyform.parse("I 0 0").symmetry_order == 6)

seven = Polyform.parse("I -8 1 -6 0 -3 -3 -2 -5 -5 1 -3 0 -2 -2")
tiling_check("iamond.parse", seven.size == 7 && seven.hole_free?)
tiling_check("iamond.normalized_residues",
             seven.cells.select(->(c) !iamond.cell_valid?(c)).size == 0)

bad = 0
begin
  Polyform.new(hex, [[0, 0], [2, 0]])
rescue e
  bad += 1
begin
  Polyform.new(hex, [[0, 0], [0, 0]])
rescue e
  bad += 1
begin
  Polyform.new(iamond, [[0, 0], [0, 1]])
rescue e
  bad += 1
tiling_check("validation.rejections", bad == 3)

<< "tiling grid spec: all checks passed"
