# Discrete lattice geometry, polyomino enumeration, and exact cover.
# Run in both engines:
#   bin/tungsten run spec/core/polyomino_spec.w
#   bin/tungsten compile spec/core/polyomino_spec.w \
#     --out /tmp/polyomino-spec --no-lto

use geometry
use combinatorics

-> polyomino_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# ---- lattice geometry -------------------------------------------------

l = Polyomino.new([[0, 0], [1, 0], [0, 1]])
polyomino_check("tromino.size", l.size == 3)
polyomino_check("tromino.bbox", l.width == 2 && l.height == 2)
polyomino_check("tromino.slack", l.slack == 1)
polyomino_check("tromino.perimeter", l.perimeter == 8)
polyomino_check("tromino.holes", l.holes == 0)
# The L-tromino is mirror-symmetric across a diagonal: orbit 4, stabiliser 2.
polyomino_check("tromino.orbit", l.orientations.size == 4)
polyomino_check("tromino.stabiliser", l.symmetry_order == 2)

square = Polyomino.from_grid(["##", "##"])
polyomino_check("square.orbit", square.orientations.size == 1)
polyomino_check("square.stabiliser", square.symmetry_order == 8)
polyomino_check("square.perimeter", square.perimeter == 8)

# Translation is quotiented out; the grid parser agrees with explicit cells.
polyomino_check("translation.invariance",
                Polyomino.new([[5, 7], [6, 7], [5, 8]]) == l)

# The smallest polyomino enclosing a hole is the 8-cell ring.
ring = Polyomino.from_grid(["###", "#.#", "###"])
polyomino_check("ring.size", ring.size == 8)
polyomino_check("ring.holes", ring.holes == 1)
polyomino_check("ring.not_simply_connected", !ring.simply_connected?)
polyomino_check("tromino.simply_connected", l.simply_connected?)

# S and Z tetrominoes: distinct as fixed pieces, one shape as free pieces.
s = Polyomino.from_grid([".##", "##."])
z = Polyomino.from_grid(["##.", ".##"])
polyomino_check("chirality.distinct_fixed", s != z)
polyomino_check("chirality.same_free", s.congruent?(z))

# Rotating four times is the identity; reflecting twice likewise.
polyomino_check("rotation.order4", l.rotated(4) == l)
polyomino_check("rotation.composition", l.rotated(1).rotated(3) == l)
polyomino_check("reflection.involution", l.reflected.reflected == l)

# Disconnected and malformed inputs are rejected.
disconnected = false
begin
  Polyomino.new([[0, 0], [5, 5]])
rescue e
  disconnected = true
polyomino_check("validation.connectivity", disconnected)

duplicated = false
begin
  Polyomino.new([[0, 0], [0, 0]])
rescue e
  duplicated = true
polyomino_check("validation.duplicate", duplicated)

# ---- enumeration, against OEIS ----------------------------------------

# A001168 (fixed), A000988 (one-sided), A000105 (free).
fixed_counts = [1, 2, 6, 19, 63, 216, 760, 2725]
one_sided_counts = [1, 1, 2, 7, 18, 60, 196, 704]
free_counts = [1, 1, 2, 5, 12, 35, 108, 369]
n = 1
while n <= 8
  polyomino_check("A001168.[n]", PolyominoEnumeration.count_fixed(n) == fixed_counts[n - 1])
  polyomino_check("A000988.[n]", PolyominoEnumeration.count_one_sided(n) == one_sided_counts[n - 1])
  polyomino_check("A000105.[n]", PolyominoEnumeration.count_free(n) == free_counts[n - 1])
  n += 1

# Every enumerated shape has the cell count it was asked for, and the free
# shapes are pairwise incongruent.
pentominoes = PolyominoEnumeration.free(5)
sizes_ok = true
pentominoes.each ->(shape)
  sizes_ok = false if shape.size != 5
polyomino_check("free.sizes", sizes_ok)
keys = {}
distinct = true
pentominoes.each ->(shape)
  distinct = false if keys.key?(shape.free_key)
  keys[shape.free_key] = true
polyomino_check("free.pairwise_distinct", distinct)

# ---- exact cover ------------------------------------------------------

# Knuth's example from the dancing-links paper: a unique cover.
knuth = ExactCover.new(7, 7)
knuth.add_row([3, 5, 6])
knuth.add_row([1, 4, 7])
knuth.add_row([2, 3, 6])
knuth.add_row([1, 4])
knuth.add_row([2, 7])
knuth.add_row([4, 5, 7])
polyomino_check("dlx.knuth_solution", same_rows?(knuth.solve.sort, [0, 3, 4]))

knuth_all = ExactCover.new(7, 7)
knuth_all.add_row([3, 5, 6])
knuth_all.add_row([1, 4, 7])
knuth_all.add_row([2, 3, 6])
knuth_all.add_row([1, 4])
knuth_all.add_row([2, 7])
knuth_all.add_row([4, 5, 7])
polyomino_check("dlx.unique", knuth_all.count_solutions(50) == 1)

unsatisfiable = ExactCover.new(2, 2)
unsatisfiable.add_row([1])
polyomino_check("dlx.unsatisfiable", unsatisfiable.solve == nil)

# A secondary column may be left uncovered.
optional = ExactCover.new(2, 1)
optional.add_row([1])
polyomino_check("dlx.secondary_optional", optional.solve != nil)

# ---- exact packing ----------------------------------------------------

# The 12 pentominoes tile a 6 x 10 rectangle.
tiling = PolyominoPacking.pack(pentominoes, 10, 6)
polyomino_check("packing.pentomino_6x10", tiling != nil)
polyomino_check("packing.all_placed", tiling.size == 12)
polyomino_check("packing.exact_cover",
                packing_valid?(pentominoes, 10, 6, tiling) == 60)

# exact_tiling finds a zero-waste rectangle when one exists, and reports none
# when the pieces cannot tile any rectangle at all.
perfect = PolyominoPacking.exact_tiling(pentominoes)
polyomino_check("tiling.pentominoes_found", perfect != nil)
polyomino_check("tiling.zero_waste", perfect[0] * perfect[1] == 60)
polyomino_check("tiling.valid",
                packing_valid?(pentominoes, perfect[0], perfect[1], perfect[2]) == 60)
# A single L-tromino has 3 cells, so only 1x3 and 3x1 are candidates, and an
# L does not fit in either.
polyomino_check("tiling.none_for_L", PolyominoPacking.exact_tiling([l]) == nil)
# A 2x2 square tiles itself.
polyomino_check("tiling.square_self", PolyominoPacking.exact_tiling([square]) != nil)

# The 5 tetrominoes cannot tile 4 x 5 — the classic colouring obstruction —
# so their minimum enclosing rectangle has area 21, not 20.
tetrominoes = PolyominoEnumeration.free(4)
polyomino_check("packing.tetromino_4x5_impossible",
                PolyominoPacking.pack(tetrominoes, 5, 4) == nil)
best = PolyominoPacking.optimal(tetrominoes, 30)
polyomino_check("packing.tetromino_optimal_area", best[0] * best[1] == 21)
polyomino_check("packing.tetromino_optimal_valid",
                packing_valid?(tetrominoes, best[0], best[1], best[2]) == 20)

<< "polyomino spec complete"

# ---- helpers ----------------------------------------------------------

-> same_rows?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

# Replays placements through the packing convention and returns the number of
# covered cells, raising on any overlap or out-of-bounds cell.
-> packing_valid?(shapes, width, height, placements)
  seen = {}
  covered = 0
  i = 0
  while i < placements.size
    cells = PolyominoPacking.placed_cells(shapes[placements[i][0]], placements[i])
    c = 0
    while c < cells.size
      x = cells[c][0]
      y = cells[c][1]
      raise "placement leaves the rectangle at ([x], [y])" if x < 0 || y < 0 || x >= width || y >= height
      key = "[x],[y]"
      raise "placements overlap at ([x], [y])" if seen.key?(key)
      seen[key] = true
      covered += 1
      c += 1
    i += 1
  covered
