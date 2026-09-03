# Discrete lattice geometry: polyominoes on the integer grid Z x Z.
#
# The rest of `core/geometry/` is smooth differential geometry — charts,
# metrics, curvature. This file is its discrete counterpart: finite
# edge-connected sets of unit cells, the dihedral group D4 acting on them,
# and the canonical forms that identify them up to symmetry.
#
# Cells are stored *normalized* — translated so the minimum x and the minimum
# y are both zero — and sorted in (x, y) order. Two polyominoes that differ
# only by a translation are therefore `==`, and `key` is a faithful identity
# for the translation class (a "fixed" polyomino).
#
# The D4 action follows the lattice-packing convention
# `reflect -> rotate -> translate`, applied in that order:
#
#   reflect across the y-axis      (x, y) -> (-x,  y)
#   rotate 90 degrees clockwise    (x, y) -> ( y, -x)
#
# `orientations` returns the distinct images under that action (1, 2, 4 or 8
# of them) and `canonical` is the lexicographically smallest of them — the
# identity of the *free* polyomino, its class under rotation and reflection.

+ Polyomino
  -> new(cells)
    @cells = Polyomino.normalize(Polyomino.validate(cells))
    @width = 0
    @height = 0
    i = 0
    while i < @cells.size
      cell = @cells[i]
      @width = cell[0] + 1 if cell[0] + 1 > @width
      @height = cell[1] + 1 if cell[1] + 1 > @height
      i += 1

  # ---- construction helpers -------------------------------------------

  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .cell_key(x, y)
    "[x],[y]"

  -> .of(cells)
    Polyomino.new(cells)

  # Build from an ASCII grid, e.g. ["##.", ".##"]. Any character other than
  # a space or "." marks an occupied cell. Row 0 is the top row, so y grows
  # downward, matching how the grids are written.
  -> .from_grid(rows)
    if rows.class_name != "Array" || rows.size == 0
      raise "a polyomino grid needs a nonempty array of rows"
    cells = []
    y = 0
    while y < rows.size
      row = rows[y]
      raise "polyomino grid rows must be strings" if row.class_name != "String"
      x = 0
      while x < row.size
        ch = row[x]
        cells.push([x, y]) if ch != "." && ch != " "
        x += 1
      y += 1
    Polyomino.new(cells)

  -> .validate(cells)
    if cells.class_name != "Array" || cells.size == 0
      raise "a polyomino needs a nonempty array of \[x, y] cells"
    seen = {}
    out = []
    i = 0
    while i < cells.size
      cell = cells[i]
      if cell.class_name != "Array" || cell.size != 2
        raise "polyomino cell [i] must be a two-element \[x, y] array"
      x = cell[0]
      y = cell[1]
      if !Polyomino.integer?(x) || !Polyomino.integer?(y)
        raise "polyomino cell [i] must have integer coordinates"
      key = Polyomino.cell_key(x, y)
      raise "polyomino repeats the cell ([x], [y])" if seen.key?(key)
      seen[key] = true
      out.push([x, y])
      i += 1
    if !Polyomino.connected?(out)
      raise "polyomino cells must be edge-connected (4-connectivity)"
    out

  # 4-connectivity test over a raw cell list, by breadth-first search.
  -> .connected?(cells)
    return true if cells.size <= 1
    present = {}
    i = 0
    while i < cells.size
      present[Polyomino.cell_key(cells[i][0], cells[i][1])] = true
      i += 1
    seen = {}
    start = cells[0]
    seen[Polyomino.cell_key(start[0], start[1])] = true
    queue = [start]
    head = 0
    reached = 1
    while head < queue.size
      cell = queue[head]
      head += 1
      x = cell[0]
      y = cell[1]
      dx = [1, -1, 0, 0]
      dy = [0, 0, 1, -1]
      d = 0
      while d < 4
        nx = x + dx[d]
        ny = y + dy[d]
        key = Polyomino.cell_key(nx, ny)
        if present.key?(key) && !seen.key?(key)
          seen[key] = true
          reached += 1
          queue.push([nx, ny])
        d += 1
    reached == cells.size

  -> .sort_cells(cells)
    cells.sort ->(a, b)
      if a[0] != b[0]
        a[0] <=> b[0]
      else
        a[1] <=> b[1]

  # Translate so the lower-left corner of the bounding box sits at the
  # origin, then sort. This is the normal form for a translation class.
  -> .normalize(cells)
    minx = cells[0][0]
    miny = cells[0][1]
    i = 1
    while i < cells.size
      minx = cells[i][0] if cells[i][0] < minx
      miny = cells[i][1] if cells[i][1] < miny
      i += 1
    out = []
    i = 0
    while i < cells.size
      out.push([cells[i][0] - minx, cells[i][1] - miny])
      i += 1
    Polyomino.sort_cells(out)

  # ---- measurements ---------------------------------------------------

  -> cells
    out = []
    i = 0
    while i < @cells.size
      out.push([@cells[i][0], @cells[i][1]])
      i += 1
    out

  -> size
    @cells.size

  -> order
    @cells.size

  -> width
    @width

  -> height
    @height

  -> bounding_area
    @width * @height

  # Cells of the bounding box the polyomino does not occupy.
  -> slack
    bounding_area - size

  -> square?
    @width == @height

  -> include?(x, y)
    i = 0
    while i < @cells.size
      return true if @cells[i][0] == x && @cells[i][1] == y
      i += 1
    false

  # Number of unit edges on the boundary: every cell contributes 4, and each
  # shared edge between two cells removes 2.
  -> perimeter
    shared = 0
    present = {}
    i = 0
    while i < @cells.size
      present[Polyomino.cell_key(@cells[i][0], @cells[i][1])] = true
      i += 1
    i = 0
    while i < @cells.size
      x = @cells[i][0]
      y = @cells[i][1]
      shared += 1 if present.key?(Polyomino.cell_key(x + 1, y))
      shared += 1 if present.key?(Polyomino.cell_key(x, y + 1))
      i += 1
    4 * @cells.size - 2 * shared

  # Enclosed empty regions. Flood the complement inward from a one-cell
  # margin around the bounding box; whatever empty cell the flood cannot
  # reach is enclosed, and each 4-connected group of those is one hole.
  -> holes
    present = {}
    i = 0
    while i < @cells.size
      present[Polyomino.cell_key(@cells[i][0], @cells[i][1])] = true
      i += 1
    outside = {}
    queue = [[-1, -1]]
    outside[Polyomino.cell_key(-1, -1)] = true
    head = 0
    while head < queue.size
      cell = queue[head]
      head += 1
      dx = [1, -1, 0, 0]
      dy = [0, 0, 1, -1]
      d = 0
      while d < 4
        nx = cell[0] + dx[d]
        ny = cell[1] + dy[d]
        d += 1
        next if nx < -1 || ny < -1 || nx > @width || ny > @height
        key = Polyomino.cell_key(nx, ny)
        next if present.key?(key) || outside.key?(key)
        outside[key] = true
        queue.push([nx, ny])
    count = 0
    seen = {}
    y = 0
    while y < @height
      x = 0
      while x < @width
        key = Polyomino.cell_key(x, y)
        if !present.key?(key) && !outside.key?(key) && !seen.key?(key)
          count += 1
          seen[key] = true
          region = [[x, y]]
          rhead = 0
          while rhead < region.size
            cell = region[rhead]
            rhead += 1
            dx = [1, -1, 0, 0]
            dy = [0, 0, 1, -1]
            d = 0
            while d < 4
              nx = cell[0] + dx[d]
              ny = cell[1] + dy[d]
              d += 1
              nkey = Polyomino.cell_key(nx, ny)
              next if present.key?(nkey) || outside.key?(nkey) || seen.key?(nkey)
              seen[nkey] = true
              region.push([nx, ny])
        x += 1
      y += 1
    count

  -> simply_connected?
    holes == 0

  # ---- the D4 action --------------------------------------------------

  -> reflected
    out = []
    i = 0
    while i < @cells.size
      out.push([0 - @cells[i][0], @cells[i][1]])
      i += 1
    Polyomino.new(out)

  -> rotated
    out = []
    i = 0
    while i < @cells.size
      out.push([@cells[i][1], 0 - @cells[i][0]])
      i += 1
    Polyomino.new(out)

  -> rotated(times)
    raise "rotation count must be an integer" if !Polyomino.integer?(times)
    turns = times % 4
    turns += 4 if turns < 0
    shape = self
    i = 0
    while i < turns
      shape = shape.rotated
      i += 1
    shape

  # The packing convention: reflect first (across the y-axis), then rotate
  # `rotations` quarter turns clockwise, then normalize the translation.
  -> transform(rotations, reflect)
    shape = self
    shape = shape.reflected if reflect
    shape.rotated(rotations)

  # Distinct images under D4 — 8 for a shape with no symmetry, fewer when
  # the shape is symmetric.
  -> orientations
    out = []
    seen = {}
    f = 0
    while f < 2
      r = 0
      while r < 4
        shape = transform(r, f == 1)
        key = shape.key
        if !seen.key?(key)
          seen[key] = true
          out.push(shape)
        r += 1
      f += 1
    out

  # Order of the stabilizer subgroup: 8 / (number of distinct images).
  -> symmetry_order
    8 / orientations.size

  -> key
    parts = []
    i = 0
    while i < @cells.size
      parts.push("[@cells[i][0]],[@cells[i][1]]")
      i += 1
    parts.join(";")

  # Lexicographically smallest image under D4 — the identity of the free
  # polyomino (its equivalence class under rotation and reflection).
  -> canonical
    best = nil
    best_key = nil
    orientations.each ->(shape)
      k = shape.key
      if best_key == nil || Polyomino.key_less?(k, best_key)
        best_key = k
        best = shape
    best

  -> .key_less?(left, right)
    return left.size < right.size if left.size != right.size
    left < right

  -> free_key
    canonical.key

  -> ==(other)
    return false if other.class_name != "Polyomino"
    key == other.key

  # Same free polyomino: equal up to rotation, reflection and translation.
  -> congruent?(other)
    raise "congruent? needs a Polyomino" if other.class_name != "Polyomino"
    free_key == other.free_key

  # ---- rendering ------------------------------------------------------

  -> to_grid
    rows = []
    y = @height - 1
    while y >= 0
      row = ""
      x = 0
      while x < @width
        row = row + (include?(x, y) ? "#" : ".")
        x += 1
      rows.push(row)
      y -= 1
    rows

  -> to_s
    to_grid.join("\n")
