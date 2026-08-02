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

# Keep the glyph table in Drawille rather than converting every cell through
# Integer#chr. Both engines now implement UTF-8 chr consistently; the literal
# table avoids repeated encoding work and remains deterministic in the REPL.
DRAWILLE_BRAILLE_GLYPHS = "\u2800\u2801\u2802\u2803\u2804\u2805\u2806\u2807\u2808\u2809\u280a\u280b\u280c\u280d\u280e\u280f\u2810\u2811\u2812\u2813\u2814\u2815\u2816\u2817\u2818\u2819\u281a\u281b\u281c\u281d\u281e\u281f\u2820\u2821\u2822\u2823\u2824\u2825\u2826\u2827\u2828\u2829\u282a\u282b\u282c\u282d\u282e\u282f\u2830\u2831\u2832\u2833\u2834\u2835\u2836\u2837\u2838\u2839\u283a\u283b\u283c\u283d\u283e\u283f\u2840\u2841\u2842\u2843\u2844\u2845\u2846\u2847\u2848\u2849\u284a\u284b\u284c\u284d\u284e\u284f\u2850\u2851\u2852\u2853\u2854\u2855\u2856\u2857\u2858\u2859\u285a\u285b\u285c\u285d\u285e\u285f\u2860\u2861\u2862\u2863\u2864\u2865\u2866\u2867\u2868\u2869\u286a\u286b\u286c\u286d\u286e\u286f\u2870\u2871\u2872\u2873\u2874\u2875\u2876\u2877\u2878\u2879\u287a\u287b\u287c\u287d\u287e\u287f\u2880\u2881\u2882\u2883\u2884\u2885\u2886\u2887\u2888\u2889\u288a\u288b\u288c\u288d\u288e\u288f\u2890\u2891\u2892\u2893\u2894\u2895\u2896\u2897\u2898\u2899\u289a\u289b\u289c\u289d\u289e\u289f\u28a0\u28a1\u28a2\u28a3\u28a4\u28a5\u28a6\u28a7\u28a8\u28a9\u28aa\u28ab\u28ac\u28ad\u28ae\u28af\u28b0\u28b1\u28b2\u28b3\u28b4\u28b5\u28b6\u28b7\u28b8\u28b9\u28ba\u28bb\u28bc\u28bd\u28be\u28bf\u28c0\u28c1\u28c2\u28c3\u28c4\u28c5\u28c6\u28c7\u28c8\u28c9\u28ca\u28cb\u28cc\u28cd\u28ce\u28cf\u28d0\u28d1\u28d2\u28d3\u28d4\u28d5\u28d6\u28d7\u28d8\u28d9\u28da\u28db\u28dc\u28dd\u28de\u28df\u28e0\u28e1\u28e2\u28e3\u28e4\u28e5\u28e6\u28e7\u28e8\u28e9\u28ea\u28eb\u28ec\u28ed\u28ee\u28ef\u28f0\u28f1\u28f2\u28f3\u28f4\u28f5\u28f6\u28f7\u28f8\u28f9\u28fa\u28fb\u28fc\u28fd\u28fe\u28ff".chars()

+ Canvas
  ro :cols
  ro :rows

  -> new(cols, rows)
    # Terminal plots should never allocate an accidental unbounded bitmap.
    # These limits still permit a plot much larger than a normal terminal.
    @cols = cols
    @rows = rows
    @cols = 1 if @cols < 1
    @rows = 1 if @rows < 1
    @cols = 240 if @cols > 240
    @rows = 100 if @rows > 100
    @cells = []
    n = @cols * @rows
    i = 0
    while i < n
      @cells.push(0)
      i += 1

  -> clear
    i = 0
    while i < @cells.size()
      @cells[i] = 0
      i += 1
    self

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

  # Cohen-Sutherland clipping keeps Bresenham work proportional to the
  # visible canvas, even when a projected endpoint is extremely far away.
  -> outcode(x, y)
    code = 0
    code = code | 1 if x < 0
    code = code | 2 if x >= pixel_width()
    code = code | 4 if y < 0
    code = code | 8 if y >= pixel_height()
    code

  -> clip_line(x0, y0, x1, y1)
    xmin = 0
    ymin = 0
    xmax = pixel_width() - 1
    ymax = pixel_height() - 1
    c0 = outcode(x0, y0)
    c1 = outcode(x1, y1)
    attempts = 0
    while attempts < 16
      return [x0, y0, x1, y1] if (c0 | c1) == 0
      return [] if (c0 & c1) != 0
      code = c0 == 0 ? c1 : c0
      x = 0
      y = 0
      if (code & 8) != 0
        return [] if y1 == y0
        x = x0 + (x1 - x0) * (ymax - y0) / (y1 - y0)
        y = ymax
      elsif (code & 4) != 0
        return [] if y1 == y0
        x = x0 + (x1 - x0) * (ymin - y0) / (y1 - y0)
        y = ymin
      elsif (code & 2) != 0
        return [] if x1 == x0
        y = y0 + (y1 - y0) * (xmax - x0) / (x1 - x0)
        x = xmax
      else
        return [] if x1 == x0
        y = y0 + (y1 - y0) * (xmin - x0) / (x1 - x0)
        x = xmin
      if code == c0
        x0 = x
        y0 = y
        c0 = outcode(x0, y0)
      else
        x1 = x
        y1 = y
        c1 = outcode(x1, y1)
      attempts += 1
    []

  # Bresenham line from (x0,y0) to (x1,y1) in pixel coords — lights every
  # pixel along the segment so a vector arrow stays connected at any slope.
  # Integer-only; out-of-bounds pixels fall through `set`'s bounds check.
  -> line(x0, y0, x1, y1)
    clipped = clip_line(x0, y0, x1, y1)
    return self if clipped.size() == 0
    x0 = clipped[0]
    y0 = clipped[1]
    x1 = clipped[2]
    y1 = clipped[3]
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

  -> polyline(points)
    return self if points.size() < 2
    i = 1
    while i < points.size()
      line(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1])
      i += 1
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
    DRAWILLE_BRAILLE_GLYPHS[@cells[row * @cols + col]]

  -> to_s
    out = ""
    row = 0
    while row < @rows
      col = 0
      while col < @cols
        if cell_empty?(col, row)
          out += " "
        else
          out += cell_char(col, row)
        col += 1
      out += "\n" if row + 1 < @rows
      row += 1
    out
