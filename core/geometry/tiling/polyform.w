# A polyform: a finite, edge-connected set of cells of one of the tiling
# grids, stored normalized (translated to the origin corner and sorted) so
# that two translates are `==`. `canonical_key` identifies the free shape —
# its class under the whole point group.
#
# The text form is heesch-sat's shape line, "H x1 y1 x2 y2 ...", with the grid
# letter first (an unclassified "H?" record is accepted too), so Kaplan's
# census files and Heesch witness files parse without conversion.

+ Polyform
  -> new(grid, cells)
    @grid = grid
    @cells = grid.normalize(Polyform.validate(grid, cells))
    @index = TilingGrid.index(@cells)

  -> .validate(grid, cells)
    raise "a polyform needs at least one cell" if cells.class_name != "Array" || cells.size == 0
    seen = {}
    out = []
    i = 0
    while i < cells.size
      c = cells[i]
      raise "cell [i] is not an [x, y] pair" if c.class_name != "Array" || c.size != 2
      raise "cell [TilingGrid.cell_key(c)] is not on the [grid.name] grid" if !grid.cell_valid?(c)
      k = TilingGrid.cell_key(c)
      raise "duplicate cell [k]" if seen.key?(k)
      seen[k] = true
      out.push([c[0], c[1]])
      i += 1
    raise "polyform is not edge-connected" if !grid.connected?(out)
    out

  # Parse "H x1 y1 x2 y2 ..." (or "H? ...").
  -> .parse(text)
    tokens = []
    text.split(" ").each ->(t)
      u = t.strip
      tokens.push(u) if u != ""
    raise "empty shape line" if tokens.size == 0
    head = tokens[0]
    head = head[0] if head.size == 2 && head[1] == "?"
    grid = TilingGrid.for(head)
    raise "shape line has an odd number of coordinates" if (tokens.size - 1) % 2 != 0
    cells = []
    i = 1
    while i < tokens.size
      cells.push([tokens[i].to_i, tokens[i + 1].to_i])
      i += 2
    Polyform.new(grid, cells)

  -> grid
    @grid

  -> cells
    @cells

  -> size
    @cells.size

  -> include?(cell)
    @index.key?(TilingGrid.cell_key(cell))

  -> key
    TilingGrid.key(@cells)

  -> canonical_key
    @grid.canonical_key(@cells)

  -> canonical
    Polyform.new(@grid, @grid.canonical(@cells)[0])

  -> ==(other)
    other.class_name == "Polyform" && other.grid.id == @grid.id && other.key == key

  -> congruent?(other)
    other.grid.id == @grid.id && other.canonical_key == canonical_key

  -> symmetry_order
    @grid.symmetry_order(@cells)

  -> holes
    @grid.holes(@cells)

  -> hole_free?
    holes.size == 0

  # Bounding-box extents [span_x, span_y].
  -> span
    x0 = @cells[0][0]
    x1 = x0
    y0 = @cells[0][1]
    y1 = y0
    i = 1
    while i < @cells.size
      x0 = @cells[i][0] if @cells[i][0] < x0
      x1 = @cells[i][0] if @cells[i][0] > x1
      y0 = @cells[i][1] if @cells[i][1] < y0
      y1 = @cells[i][1] if @cells[i][1] > y1
      i += 1
    [x1 - x0 + 1, y1 - y0 + 1]

  -> halo
    @grid.halo(@cells)

  # The image under orientation `index` (not normalized).
  -> image(index)
    @grid.apply_all(index, @cells)

  # The copy placed by orientation `index` then translation (tx, ty).
  -> placed(index, tx, ty)
    img = image(index)
    out = []
    i = 0
    while i < img.size
      out.push([img[i][0] + tx, img[i][1] + ty])
      i += 1
    out

  -> transformed(xf)
    TilingGrid.transform_all(xf, @cells)

  -> to_s
    parts = [@grid.id]
    i = 0
    while i < @cells.size
      parts.push("[@cells[i][0]] [@cells[i][1]]")
      i += 1
    parts.join(" ")
