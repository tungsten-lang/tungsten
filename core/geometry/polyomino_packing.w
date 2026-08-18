# Minimum-area rectangle packing of polyominoes, solved exactly.
#
# The question "can these pieces be placed in a W x H rectangle without
# overlap?" is an exact cover instance:
#
#   primary column per piece   — every piece is placed exactly once
#   primary column per cell    — every cell is filled exactly once
#   row per legal placement    — one piece, in one orientation, at one spot
#
# When the rectangle has more cells than the pieces have (area > total), the
# surplus is modelled by one single-cell "blank" row per cell. Blanks let the
# cell columns stay *primary*, which is what makes the search fast: Algorithm
# X branches on the most constrained column, and a cell that only a couple of
# placements can reach is far more constraining than a piece with hundreds of
# possible spots. When area equals the total no blanks are emitted at all,
# since every cell must then be covered by a real piece.
#
# `optimal` walks candidate rectangles in increasing area — breaking ties by
# smaller height, then smaller width — and returns the first that admits a
# packing. That rectangle is therefore of provably minimum area: every
# strictly smaller one was tested and refuted by an exhaustive search.
#
# Placements are reported as [piece_index, rotations, reflect, x, y], where
# the piece is reflected across the y-axis if `reflect`, then rotated
# `rotations` quarter turns clockwise, then translated so that the lowest
# corner of its bounding box sits at (x, y).

+ PolyominoPacking
  -> .total_cells(shapes)
    total = 0
    i = 0
    while i < shapes.size
      total += shapes[i].size
      i += 1
    total

  # Distinct orientations of a shape, each with the offset that normalising
  # the transformed cells removed. Records are
  # [cells, width, height, rotations, reflect, offset_x, offset_y].
  -> .orientation_records(shape)
    records = []
    seen = {}
    base = shape.cells
    f = 0
    while f < 2
      r = 0
      while r < 4
        cells = base
        if f == 1
          cells = PolyominoEnumeration.reflect_cells(cells)
        t = 0
        while t < r
          cells = PolyominoEnumeration.rotate_cells(cells)
          t += 1
        minx = cells[0][0]
        miny = cells[0][1]
        i = 1
        while i < cells.size
          minx = cells[i][0] if cells[i][0] < minx
          miny = cells[i][1] if cells[i][1] < miny
          i += 1
        normalized = Polyomino.normalize(cells)
        key = PolyominoEnumeration.key_of(normalized)
        if !seen.key?(key)
          seen[key] = true
          width = 0
          height = 0
          i = 0
          while i < normalized.size
            width = normalized[i][0] + 1 if normalized[i][0] + 1 > width
            height = normalized[i][1] + 1 if normalized[i][1] + 1 > height
            i += 1
          records.push([normalized, width, height, r, f == 1, minx, miny])
        r += 1
      f += 1
    records

  # Try to place every shape inside width x height. Returns an array of
  # placements, or nil when no packing exists.
  -> .pack(shapes, width, height)
    if shapes.class_name != "Array" || shapes.size == 0
      raise "packing needs a nonempty array of polyominoes"
    if width < 1 || height < 1
      raise "packing rectangle must have positive width and height"
    total = PolyominoPacking.total_cells(shapes)
    area = width * height
    return nil if area < total
    piece_count = shapes.size
    columns = piece_count + area
    cover = ExactCover.new(columns, columns)
    # Row metadata, parallel to the exact-cover row ids.
    meta = []
    i = 0
    while i < piece_count
      records = PolyominoPacking.orientation_records(shapes[i])
      j = 0
      while j < records.size
        record = records[j]
        cells = record[0]
        w = record[1]
        h = record[2]
        x = 0
        while x <= width - w
          y = 0
          while y <= height - h
            indices = [i + 1]
            c = 0
            while c < cells.size
              cx = x + cells[c][0]
              cy = y + cells[c][1]
              indices.push(piece_count + cy * width + cx + 1)
              c += 1
            cover.add_row(indices)
            meta.push([i, record[3], record[4], x - record[5], y - record[6]])
            y += 1
          x += 1
        j += 1
      i += 1
    # Surplus cells are absorbed by single-cell blanks.
    if area > total
      cell = 0
      while cell < area
        cover.add_row([piece_count + cell + 1])
        meta.push(nil)
        cell += 1
    solution = cover.solve
    return nil if solution == nil
    out = []
    i = 0
    while i < solution.size
      record = meta[solution[i]]
      out.push(record) if record != nil
      i += 1
    out

  # A *perfect* tiling: a rectangle whose area equals the piece total, so the
  # pieces fill it with no waste at all. Returns [width, height, placements] or
  # nil when the pieces tile no rectangle. Density is exactly 1 when one
  # exists, which is the best any packing can do — so a group of pieces that
  # tiles a rectangle is an ideal building block for a larger packing.
  -> .exact_tiling(shapes)
    total = PolyominoPacking.total_cells(shapes)
    w = 1
    while w <= total
      if total % w == 0
        placements = PolyominoPacking.pack(shapes, w, total / w)
        return [w, total / w, placements] if placements != nil
      w += 1
    nil

  # Candidate rectangles of at least `total` cells, ordered by area, then
  # height, then width — the tie-break the packing objective asks for.
  -> .candidates(total, max_area)
    out = []
    w = 1
    while w <= max_area
      h = 1
      while w * h <= max_area
        out.push([w * h, h, w]) if w * h >= total
        h += 1
      w += 1
    out.sort ->(a, b)
      if a[0] != b[0]
        a[0] <=> b[0]
      elsif a[1] != b[1]
        a[1] <=> b[1]
      else
        a[2] <=> b[2]

  # Minimum-area packing. Returns [width, height, placements].
  -> .optimal(shapes, max_area)
    total = PolyominoPacking.total_cells(shapes)
    raise "max_area must be at least the total cell count" if max_area < total
    candidates = PolyominoPacking.candidates(total, max_area)
    i = 0
    while i < candidates.size
      h = candidates[i][1]
      w = candidates[i][2]
      placements = PolyominoPacking.pack(shapes, w, h)
      return [w, h, placements] if placements != nil
      i += 1
    nil

  # Cells a placement occupies, following the packing convention exactly:
  # reflect across the y-axis if asked, then rotate clockwise, then translate
  # by (x, y). No normalisation happens in between — the translation in a
  # placement already accounts for where the transform left the shape.
  -> .placed_cells(shape, placement)
    cells = shape.cells
    cells = PolyominoEnumeration.reflect_cells(cells) if placement[2]
    t = 0
    while t < placement[1]
      cells = PolyominoEnumeration.rotate_cells(cells)
      t += 1
    out = []
    i = 0
    while i < cells.size
      out.push([cells[i][0] + placement[3], cells[i][1] + placement[4]])
      i += 1
    out

  # Render a packing as an ASCII grid, one character per piece.
  -> .render(shapes, width, height, placements)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    grid = []
    i = 0
    while i < width * height
      grid.push(".")
      i += 1
    i = 0
    while i < placements.size
      placement = placements[i]
      mark = alphabet[placement[0] % alphabet.size]
      cells = PolyominoPacking.placed_cells(shapes[placement[0]], placement)
      c = 0
      while c < cells.size
        gx = cells[c][0]
        gy = cells[c][1]
        if gy >= 0 && gy < height && gx >= 0 && gx < width
          grid[gy * width + gx] = mark
        c += 1
      i += 1
    rows = []
    y = height - 1
    while y >= 0
      row = ""
      x = 0
      while x < width
        row = row + grid[y * width + x]
        x += 1
      rows.push(row)
      y -= 1
    rows.join("\n")
