# Canvas — sub-character resolution drawing via Unicode braille.
#
# A port of asciimoo/drawille's core. Each terminal character cell is a
# 2-wide × 4-tall grid of braille dots (U+2800..U+28FF), so a `cols × rows`
# canvas addresses a (cols*2) × (rows*4) pixel grid. Origin is top-left;
# `py` grows downward (screen coordinates), so callers flip the y-axis.
#
# The braille dot numbering (matching the Unicode block layout):
#
#     (0,0)=0x01   (1,0)=0x08
#     (0,1)=0x02   (1,1)=0x10
#     (0,2)=0x04   (1,2)=0x20
#     (0,3)=0x40   (1,3)=0x80
#
# A cell's character is U+2800 + (OR of its lit dot bits).

+ Canvas
  ro :cols
  ro :rows

  -> new(cols, rows)
    @cols = cols
    @rows = rows
    @cells = []
    n = cols * rows
    i = 0
    while i < n
      @cells.push(0)
      i += 1

  -> pixel_width
    @cols * 2

  -> pixel_height
    @rows * 4

  # Braille dot bit for a sub-cell position (dx in 0..1, dy in 0..3).
  -> dot_bit(dx, dy)
    if dy == 0
      if dx == 0
        return 1
      return 8
    if dy == 1
      if dx == 0
        return 2
      return 16
    if dy == 2
      if dx == 0
        return 4
      return 32
    if dx == 0
      return 64
    128

  # Turn on the pixel at (px, py). Out-of-bounds pixels are ignored so a
  # caller can sample past the edges without bounds-checking every point.
  -> set(px, py)
    if px < 0 || py < 0
      return self
    if px >= pixel_width() || py >= pixel_height()
      return self
    col = px / 2
    row = py / 4
    idx = row * @cols + col
    @cells[idx] = @cells[idx] | dot_bit(px % 2, py % 4)
    self

  # Bresenham line from (x0,y0) to (x1,y1) in pixel coords — lights every
  # pixel along the segment so a vector arrow stays connected at any slope.
  # Integer-only; out-of-bounds pixels fall through `set`'s bounds check.
  -> line(x0, y0, x1, y1)
    dx = x1 - x0
    if dx < 0
      dx = 0 - dx
    dy = y1 - y0
    if dy < 0
      dy = 0 - dy
    sx = -1
    if x0 < x1
      sx = 1
    sy = -1
    if y0 < y1
      sy = 1
    err = dx - dy
    x = x0
    y = y0
    done = false
    while !done
      set(x, y)
      if x == x1 && y == y1
        done = true
      else
        e2 = err * 2
        if e2 > 0 - dy
          err = err - dy
          x = x + sx
        if e2 < dx
          err = err + dx
          y = y + sy
    self

  # Midpoint circle of radius r centered at (cx,cy), pixel coords. Eight-way
  # symmetry lights the rim only (no fill). With a square pixel grid
  # (cols = 2·rows ⇒ pixel_width == pixel_height) this draws a true circle.
  -> circle(cx, cy, r)
    if r < 1
      return self
    x = r
    y = 0
    err = 1 - r
    while x >= y
      set(cx + x, cy + y)
      set(cx + y, cy + x)
      set(cx - y, cy + x)
      set(cx - x, cy + y)
      set(cx - x, cy - y)
      set(cx - y, cy - x)
      set(cx + y, cy - x)
      set(cx + x, cy - y)
      y = y + 1
      if err < 0
        err = err + 2 * y + 1
      else
        x = x - 1
        err = err + 2 * (y - x) + 1
    self

  # True when the cell has no lit dots (so an axis/space can show through).
  -> cell_empty?(col, row)
    @cells[row * @cols + col] == 0

  # The braille glyph for a cell (U+2800 when empty).
  -> cell_char(col, row)
    (0x2800 + @cells[row * @cols + col]).chr()
