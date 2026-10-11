# Raster — an RGB pixel canvas with PNG and animated-GIF encoders.
#
# Colors are packed integers 0xRRGGBB. Coordinates are pixels with the origin
# at the top-left. The encoders are self-contained (no zlib, no libpng):
#
#   r = Raster.new(320, 200)            # white background
#   r.disc(160, 100, 40, 0x2266AA)
#   r.line(0, 0, 319, 199, 0xCC3311)
#   r.text(8, 8, "N = 42", 0x000000, 2)
#   r.write_png("out.png")
#
#   gif = GifAnimation.new(320, 200)     # palette is collected from frames
#   gif.add_frame(r, 8)                  # delay in 1/100 s
#   gif.write("out.gif")
#
# PNG output is RGB8 with per-row adaptive filtering and a fixed-Huffman
# LZ77 deflate stream; GIF output is 8-bit indexed LZW with an infinite-loop
# extension. Frames with more than 256 distinct colors are quantized to a
# 6x7x6 color cube.

+ Raster
  ro :width, :height, :pixels

  -> new(@width, @height, background = 0xFFFFFF)
    @pixels = i64[@width * @height]
    raster_fill(@pixels, @width * @height, background)

  -> fill(color)
    raster_fill(@pixels, @width * @height, color)
    self

  -> set(x, y, color)
    if x >= 0 && y >= 0 && x < @width && y < @height
      @pixels[y * @width + x] = color
    self

  -> get(x, y)
    @pixels[y * @width + x]

  # Alpha-blend `color` over the pixel with opacity alpha in [0, 1].
  -> blend(x, y, color, alpha)
    if x >= 0 && y >= 0 && x < @width && y < @height
      a = (alpha * ~256.0).to_i
      raster_blend(@pixels, y * @width + x, color, a)
    self

  -> fill_rect(x0, y0, w, h, color)
    raster_rect(@pixels, @width, @height, x0, y0, w, h, color)
    self

  -> rect(x0, y0, w, h, color)
    line(x0, y0, x0 + w - 1, y0, color)
    line(x0, y0 + h - 1, x0 + w - 1, y0 + h - 1, color)
    line(x0, y0, x0, y0 + h - 1, color)
    line(x0 + w - 1, y0, x0 + w - 1, y0 + h - 1, color)
    self

  -> line(x0, y0, x1, y1, color, thickness = 1)
    if thickness <= 1
      raster_line(@pixels, @width, @height, x0.to_i, y0.to_i, x1.to_i, y1.to_i, color)
    else
      r = thickness / 2
      raster_thick_line(@pixels, @width, @height, x0.to_i, y0.to_i, x1.to_i, y1.to_i, r.to_i, color)
    self

  -> disc(cx, cy, radius, color)
    raster_disc(@pixels, @width, @height, cx.to_i, cy.to_i, radius.to_i, color)
    self

  -> circle(cx, cy, radius, color)
    raster_circle(@pixels, @width, @height, cx.to_i, cy.to_i, radius.to_i, color)
    self

  # Even-odd scanline fill of a polygon given parallel x and y arrays.
  -> polygon(xs, ys, color)
    n = xs.size
    px = f64[n]
    py = f64[n]
    i = 0
    while i < n
      px[i] = xs[i] + ~0.0
      py[i] = ys[i] + ~0.0
      i += 1
    raster_polygon(@pixels, @width, @height, px, py, n, color)
    self

  # 5x7 bitmap text; lowercase letters render as capitals.
  -> text(x, y, s, color, scale = 1)
    cx = x
    table = RasterFont.build
    i = 0
    while i < s.size
      code = s[i].ord
      if code >= 97 && code <= 122
        code = code - 32
      rows = RasterFont.glyph(table, code)
      r = 0
      while r < 7
        bits = rows[r]
        c = 0
        while c < 5
          if (bits / (2 ** (4 - c))) % 2 == 1
            raster_rect(@pixels, @width, @height, cx + c * scale, y + r * scale, scale, scale, color)
          c += 1
        r += 1
      cx += 6 * scale
      i += 1
    self

  -> text_width(s, scale = 1)
    s.size * 6 * scale

  # Map a value in [0, 1] to a perceptual blue-to-yellow ramp (viridis-like).
  -> .ramp(t)
    t = t + ~0.0
    if t < ~0.0
      t = ~0.0
    if t > ~1.0
      t = ~1.0
    stops = [0x440154, 0x3B528B, 0x21908D, 0x5DC863, 0xFDE725]
    seg = t * ~4.0
    k = seg.floor.to_i
    if k >= 4
      k = 3
    f = seg - k
    Raster.mix(stops[k], stops[k + 1], f)

  # Diverging red-white-blue ramp for signed values in [-1, 1].
  -> .diverging(t)
    t = t + ~0.0
    if t < ~-1.0
      t = ~-1.0
    if t > ~1.0
      t = ~1.0
    if t < ~0.0
      Raster.mix(0xF7F7F7, 0xB2182B, -t)
    else
      Raster.mix(0xF7F7F7, 0x2166AC, t)

  -> .mix(c0, c1, f)
    f = f + ~0.0
    r = ((c0 / 65536) % 256) * (~1.0 - f) + ((c1 / 65536) % 256) * f
    g = ((c0 / 256) % 256) * (~1.0 - f) + ((c1 / 256) % 256) * f
    b = (c0 % 256) * (~1.0 - f) + (c1 % 256) * f
    r.round.to_i * 65536 + g.round.to_i * 256 + b.round.to_i

  -> .rgb(r, g, b)
    r.to_i * 65536 + g.to_i * 256 + b.to_i

  -> to_png
    PngEncoder.encode(@pixels, @width, @height)

  -> write_png(path)
    File.write_bytes(path, to_png)
    path


# --------------------------------------------------------------------------
# Typed pixel kernels (machine-speed loops; see doc/TUNGSTEN_FOR_LLMS.md).

-> raster_fill(px, n, color) (i64[] i64 i64) i64
  i = 0
  while i < n
    px[i] = color
    i += 1
  n

-> raster_blend(px, idx, color, a) (i64[] i64 i64 i64) i64
  old = px[idx]
  inv = 256 - a
  r = (((old / 65536) % 256) * inv + ((color / 65536) % 256) * a) / 256
  g = (((old / 256) % 256) * inv + ((color / 256) % 256) * a) / 256
  b = ((old % 256) * inv + (color % 256) * a) / 256
  px[idx] = r * 65536 + g * 256 + b
  idx

-> raster_rect(px, w, h, x0, y0, rw, rh, color) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  ya = y0
  if ya < 0
    ya = 0
  yb = y0 + rh
  if yb > h
    yb = h
  xa = x0
  if xa < 0
    xa = 0
  xb = x0 + rw
  if xb > w
    xb = w
  y = ya
  while y < yb
    x = xa
    while x < xb
      px[y * w + x] = color
      x += 1
    y += 1
  0

-> raster_line(px, w, h, x0, y0, x1, y1, color) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  dx = x1 - x0
  if dx < 0
    dx = 0 - dx
  dy = y1 - y0
  if dy < 0
    dy = 0 - dy
  sx = 1
  if x0 > x1
    sx = -1
  sy = 1
  if y0 > y1
    sy = -1
  err = dx - dy
  x = x0
  y = y0
  steps = 0
  limit = dx + dy + 2
  while steps < limit
    if x >= 0 && y >= 0 && x < w && y < h
      px[y * w + x] = color
    if x == x1 && y == y1
      steps = limit
    else
      e2 = 2 * err
      if e2 > 0 - dy
        err -= dy
        x += sx
      if e2 < dx
        err += dx
        y += sy
      steps += 1
  0

-> raster_disc(px, w, h, cx, cy, r, color) (i64[] i64 i64 i64 i64 i64 i64) i64
  y = 0 - r
  while y <= r
    yy = cy + y
    if yy >= 0 && yy < h
      x = 0 - r
      while x <= r
        if x * x + y * y <= r * r + r
          xx = cx + x
          if xx >= 0 && xx < w
            px[yy * w + xx] = color
        x += 1
    y += 1
  0

-> raster_circle(px, w, h, cx, cy, r, color) (i64[] i64 i64 i64 i64 i64 i64) i64
  x = r
  y = 0
  err = 1 - r
  while x >= y
    raster_plot8(px, w, h, cx, cy, x, y, color)
    y += 1
    if err < 0
      err += 2 * y + 1
    else
      x -= 1
      err += 2 * (y - x) + 1
  0

-> raster_plot8(px, w, h, cx, cy, x, y, color) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  raster_dot(px, w, h, cx + x, cy + y, color)
  raster_dot(px, w, h, cx - x, cy + y, color)
  raster_dot(px, w, h, cx + x, cy - y, color)
  raster_dot(px, w, h, cx - x, cy - y, color)
  raster_dot(px, w, h, cx + y, cy + x, color)
  raster_dot(px, w, h, cx - y, cy + x, color)
  raster_dot(px, w, h, cx + y, cy - x, color)
  raster_dot(px, w, h, cx - y, cy - x, color)
  0

-> raster_dot(px, w, h, x, y, color) (i64[] i64 i64 i64 i64 i64) i64
  if x >= 0 && y >= 0 && x < w && y < h
    px[y * w + x] = color
  0

-> raster_thick_line(px, w, h, x0, y0, x1, y1, r, color) (i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  dx = x1 - x0
  if dx < 0
    dx = 0 - dx
  dy = y1 - y0
  if dy < 0
    dy = 0 - dy
  sx = 1
  if x0 > x1
    sx = -1
  sy = 1
  if y0 > y1
    sy = -1
  err = dx - dy
  x = x0
  y = y0
  steps = 0
  limit = dx + dy + 2
  while steps < limit
    raster_disc(px, w, h, x, y, r, color)
    if x == x1 && y == y1
      steps = limit
    else
      e2 = 2 * err
      if e2 > 0 - dy
        err -= dy
        x += sx
      if e2 < dx
        err += dx
        y += sy
      steps += 1
  0

-> raster_polygon(px, w, h, xs, ys, n, color) (i64[] i64 i64 f64[] f64[] i64 i64) i64
  ymin = ys[0]
  ymax = ys[0]
  i = 1
  while i < n
    if ys[i] < ymin
      ymin = ys[i]
    if ys[i] > ymax
      ymax = ys[i]
    i += 1
  ya = ymin.floor.to_i
  if ya < 0
    ya = 0
  yb = ymax.ceil.to_i
  if yb > h - 1
    yb = h - 1
  cross = f64[n + 1]
  y = ya
  while y <= yb
    sy = y + ~0.5
    m = 0
    i = 0
    while i < n
      j = i + 1
      if j == n
        j = 0
      yi = ys[i]
      yj = ys[j]
      if (yi <= sy && yj > sy) || (yj <= sy && yi > sy)
        cross[m] = xs[i] + (sy - yi) / (yj - yi) * (xs[j] - xs[i])
        m += 1
      i += 1
    # insertion sort of crossings
    a = 1
    while a < m
      v = cross[a]
      b = a - 1
      while b >= 0 && cross[b] > v
        cross[b + 1] = cross[b]
        b -= 1
      cross[b + 1] = v
      a += 1
    k = 0
    while k + 1 < m
      xa = (cross[k] - ~0.5).ceil.to_i
      xb = (cross[k + 1] - ~0.5).floor.to_i
      if xa < 0
        xa = 0
      if xb > w - 1
        xb = w - 1
      x = xa
      while x <= xb
        px[y * w + x] = color
        x += 1
      k += 2
    y += 1
  0


# --------------------------------------------------------------------------
# PNG: RGB8, adaptive filters, zlib(fixed-Huffman deflate), CRC-32, Adler-32.

+ PngEncoder
  -> .encode(pixels, width, height)
    stride = width * 3 + 1
    raw = u8[stride * height]
    png_filter_rows(pixels, width, height, raw)
    cap = stride * height + (stride * height) / 4 + 1024
    z = u8[cap]
    head = i64[32768]
    prev = i64[32768]
    zlen = png_zlib(raw, stride * height, z, head, prev)
    out = u8[zlen + 57]
    pos = png_write_signature(out)
    ihdr = u8[13]
    png_put32(ihdr, 0, width)
    png_put32(ihdr, 4, height)
    ihdr[8] = 8
    ihdr[9] = 2
    ihdr[10] = 0
    ihdr[11] = 0
    ihdr[12] = 0
    crc = i64[256]
    png_crc_table(crc)
    pos = png_chunk(out, pos, 1229472850, ihdr, 13, crc)
    pos = png_chunk(out, pos, 1229209940, z, zlen, crc)
    empty = u8[1]
    pos = png_chunk(out, pos, 1229278788, empty, 0, crc)
    out

-> png_write_signature(out) (u8[]) i64
  out[0] = 137
  out[1] = 80
  out[2] = 78
  out[3] = 71
  out[4] = 13
  out[5] = 10
  out[6] = 26
  out[7] = 10
  8

-> png_put32(buf, at, v) (u8[] i64 i64) i64
  buf[at] = (v / 16777216) % 256
  buf[at + 1] = (v / 65536) % 256
  buf[at + 2] = (v / 256) % 256
  buf[at + 3] = v % 256
  at + 4

-> png_crc_table(t) (i64[]) i64
  n = 0
  while n < 256
    c = n
    k = 0
    while k < 8
      if c % 2 == 1
        c = 3988292384 ^ (c / 2)
      else
        c = c / 2
      k += 1
    t[n] = c
    n += 1
  0

-> png_crc_byte(t, crc, b) (i64[] i64 i64) i64
  t[(crc ^ b) % 256] ^ (crc / 256)

# Writes length, type, data and CRC; returns the new position.
-> png_chunk(out, pos, kind, data, n, t) (u8[] i64 i64 u8[] i64 i64[]) i64
  p = png_put32(out, pos, n)
  p = png_put32(out, p, kind)
  crc = 4294967295
  k = 0
  while k < 4
    ob = out[pos + 4 + k] ## i64
    crc = png_crc_byte(t, crc, ob)
    k += 1
  i = 0
  while i < n
    out[p] = data[i]
    db = data[i] ## i64
    crc = png_crc_byte(t, crc, db)
    p += 1
    i += 1
  png_put32(out, p, crc ^ 4294967295)

-> png_abs(v) (i64) i64
  if v < 0
    0 - v
  else
    v

-> png_paeth(a, b, c) (i64 i64 i64) i64
  p = a + b - c
  pa = png_abs(p - a)
  pb = png_abs(p - b)
  pc = png_abs(p - c)
  if pa <= pb && pa <= pc
    a
  elsif pb <= pc
    b
  else
    c

# Chooses per row the filter (none/sub/up/paeth) with the least absolute sum.
-> png_filter_rows(px, w, h, raw) (i64[] i64 i64 u8[]) i64
  stride = w * 3 + 1
  cur = i64[w * 3]
  up = i64[w * 3]
  y = 0
  while y < h
    x = 0
    while x < w
      c = px[y * w + x]
      cur[3 * x] = (c / 65536) % 256
      cur[3 * x + 1] = (c / 256) % 256
      cur[3 * x + 2] = c % 256
      x += 1
    best = 0
    best_cost = 0
    f = 0
    while f < 4
      cost = 0
      i = 0
      while i < w * 3
        a = 0
        if i >= 3
          a = cur[i - 3]
        b = up[i]
        cc = 0
        if i >= 3
          cc = up[i - 3]
        v = cur[i]
        if f == 1
          v = (cur[i] - a + 256) % 256
        elsif f == 2
          v = (cur[i] - b + 256) % 256
        elsif f == 3
          v = (cur[i] - png_paeth(a, b, cc) + 256) % 256
        if v < 128
          cost += v
        else
          cost += 256 - v
        i += 1
      if f == 0 || cost < best_cost
        best = f
        best_cost = cost
      f += 1
    base = y * stride
    raw[base] = best
    if best == 3
      raw[base] = 4
    i = 0
    while i < w * 3
      a = 0
      if i >= 3
        a = cur[i - 3]
      b = up[i]
      cc = 0
      if i >= 3
        cc = up[i - 3]
      v = cur[i]
      if best == 1
        v = (cur[i] - a + 256) % 256
      elsif best == 2
        v = (cur[i] - b + 256) % 256
      elsif best == 3
        v = (cur[i] - png_paeth(a, b, cc) + 256) % 256
      raw[base + 1 + i] = v
      i += 1
    i = 0
    while i < w * 3
      up[i] = cur[i]
      i += 1
    y += 1
  0

# Bit writer state lives in st: st[0] = bit buffer, st[1] = bit count, st[2] = byte position.
-> png_bits(out, st, value, nbits) (u8[] i64[] i64 i64) i64
  buf = st[0] + value * (2 ** st[1])
  cnt = st[1] + nbits
  pos = st[2]
  while cnt >= 8
    out[pos] = buf % 256
    buf = buf / 256
    cnt -= 8
    pos += 1
  st[0] = buf
  st[1] = cnt
  st[2] = pos
  pos

-> png_rev(code, len) (i64 i64) i64
  r = 0
  i = 0
  while i < len
    r = r * 2 + (code / (2 ** i)) % 2
    i += 1
  r

# Emits one literal/length symbol with the fixed Huffman code.
-> png_lit(out, st, sym) (u8[] i64[] i64) i64
  if sym < 144
    png_bits(out, st, png_rev(48 + sym, 8), 8)
  elsif sym < 256
    png_bits(out, st, png_rev(400 + sym - 144, 9), 9)
  elsif sym < 280
    png_bits(out, st, png_rev(sym - 256, 7), 7)
  else
    png_bits(out, st, png_rev(192 + sym - 280, 8), 8)

-> png_length(out, st, len, lbase, lextra) (u8[] i64[] i64 i64[] i64[]) i64
  code = 28
  while lbase[code] > len
    code -= 1
  png_lit(out, st, 257 + code)
  if lextra[code] > 0
    png_bits(out, st, len - lbase[code], lextra[code])
  0

-> png_distance(out, st, dist, dbase, dextra) (u8[] i64[] i64 i64[] i64[]) i64
  code = 29
  while dbase[code] > dist
    code -= 1
  png_bits(out, st, png_rev(code, 5), 5)
  if dextra[code] > 0
    png_bits(out, st, dist - dbase[code], dextra[code])
  0

# zlib stream of fixed-Huffman deflate with a hash-chain LZ77 matcher.
-> png_zlib(src, n, out, head, prev) (u8[] i64 u8[] i64[] i64[]) i64
  out[0] = 120
  out[1] = 1
  st = i64[3]
  st[2] = 2
  lbase = i64[29]
  lextra = i64[29]
  dbase = i64[30]
  dextra = i64[30]
  png_fill_tables(lbase, lextra, dbase, dextra)
  i = 0
  while i < 32768
    head[i] = -1
    i += 1
  png_bits(out, st, 1, 1)
  png_bits(out, st, 1, 2)
  i = 0
  while i < n
    best_len = 0
    best_dist = 0
    if i + 2 < n
      s0 = src[i] ## i64
      s1 = src[i + 1] ## i64
      s2 = src[i + 2] ## i64
      hsh = ((s0 * 1024) ^ (s1 * 32) ^ s2) % 32768
      cand = head[hsh]
      chain = 0
      while cand >= 0 && chain < 48 && i - cand <= 32768
        len = 0
        while len < 258 && i + len < n && src[cand + len] == src[i + len]
          len += 1
        if len > best_len
          best_len = len
          best_dist = i - cand
        cand = prev[cand % 32768]
        chain += 1
      prev[i % 32768] = head[hsh]
      head[hsh] = i
    if best_len >= 3
      png_length(out, st, best_len, lbase, lextra)
      png_distance(out, st, best_dist, dbase, dextra)
      k = 1
      while k < best_len
        j = i + k
        if j + 2 < n
          t0 = src[j] ## i64
          t1 = src[j + 1] ## i64
          t2 = src[j + 2] ## i64
          h2 = ((t0 * 1024) ^ (t1 * 32) ^ t2) % 32768
          prev[j % 32768] = head[h2]
          head[h2] = j
        k += 1
      i += best_len
    else
      lit = src[i] ## i64
      png_lit(out, st, lit)
      i += 1
  png_lit(out, st, 256)
  if st[1] > 0
    png_bits(out, st, 0, 8 - st[1])
  pos = st[2]
  a = 1
  b = 0
  i = 0
  while i < n
    sv = src[i] ## i64
    a = (a + sv) % 65521
    b = (b + a) % 65521
    i += 1
  png_put32(out, pos, b * 65536 + a)

-> png_fill_tables(lbase, lextra, dbase, dextra) (i64[] i64[] i64[] i64[]) i64
  i = 0
  v = 3
  while i < 28
    e = 0
    if i >= 8
      e = (i - 4) / 4
    lbase[i] = v
    lextra[i] = e
    v += 2 ** e
    i += 1
  lbase[28] = 258
  lextra[28] = 0
  i = 0
  v = 1
  while i < 30
    e = 0
    if i >= 4
      e = (i - 2) / 2
    dbase[i] = v
    dextra[i] = e
    v += 2 ** e
    i += 1
  0


# --------------------------------------------------------------------------
# Animated GIF (GIF89a, global palette, LZW, loop forever).

+ GifAnimation
  ro :width, :height, :frames

  -> new(@width, @height)
    @frames = []
    @delays = []
    @colors = {}
    @palette = []

  # Adds a Raster frame shown for delay_cs hundredths of a second.
  -> add_frame(raster, delay_cs = 8)
    copy = i64[@width * @height]
    i = 0
    while i < @width * @height
      copy[i] = raster.pixels[i]
      i += 1
    @frames.push(copy)
    @delays.push(delay_cs)
    self

  -> build_palette
    seen = {}
    list = []
    @frames.each -> (fr)
      i = 0
      n = @width * @height
      while i < n && list.size <= 256
        c = fr[i]
        if !seen.has_key?(c)
          seen[c] = list.size
          list.push(c)
        i += 1
    if list.size <= 256
      @palette = list
      @quantize = false
    else
      @palette = []
      r = 0
      while r < 6
        g = 0
        while g < 7
          b = 0
          while b < 6
            @palette.push(Raster.rgb((r * 255) / 5, (g * 255) / 6, (b * 255) / 5))
            b += 1
          g += 1
        r += 1
      @quantize = true
    @index = {}
    k = 0
    while k < @palette.size
      @index[@palette[k]] = k
      k += 1
    @palette

  -> write(path)
    File.write_bytes(path, encode)
    path

  -> encode
    build_palette
    bits = 1
    while 2 ** bits < @palette.size
      bits += 1
    if bits < 2
      bits = 2
    size = 2 ** bits
    n = @width * @height
    total = 64 + size * 3 + @frames.size * (n * 2 + n / 128 + 64)
    out = u8[total]
    pos = gif_header(out, @width, @height, bits)
    pal = i64[size]
    k = 0
    while k < @palette.size
      pal[k] = @palette[k]
      k += 1
    pos = gif_palette(out, pos, pal, size)
    pos = gif_loop(out, pos)
    idx = i64[n]
    dict_key = i64[16384]
    dict_val = i64[16384]
    st = i64[4]
    f = 0
    while f < @frames.size
      fr = @frames[f]
      i = 0
      while i < n
        c = fr[i]
        if @quantize
          r = ((c / 65536) % 256 * 5 + 127) / 255
          g = ((c / 256) % 256 * 6 + 127) / 255
          b = (c % 256 * 5 + 127) / 255
          idx[i] = r * 42 + g * 6 + b
        else
          idx[i] = @index[c]
        i += 1
      pos = gif_frame(out, pos, idx, n, @width, @height, @delays[f], bits, dict_key, dict_val, st)
      f += 1
    out[pos] = 59
    pos += 1
    result = u8[pos]
    i = 0
    while i < pos
      result[i] = out[i]
      i += 1
    result

-> gif_header(out, w, h, bits) (u8[] i64 i64 i64) i64
  out[0] = 71
  out[1] = 73
  out[2] = 70
  out[3] = 56
  out[4] = 57
  out[5] = 97
  out[6] = w % 256
  out[7] = w / 256
  out[8] = h % 256
  out[9] = h / 256
  out[10] = 128 + (bits - 1) * 16 + (bits - 1)
  out[11] = 0
  out[12] = 0
  13

-> gif_palette(out, pos, pal, size) (u8[] i64 i64[] i64) i64
  p = pos
  k = 0
  while k < size
    c = pal[k]
    out[p] = (c / 65536) % 256
    out[p + 1] = (c / 256) % 256
    out[p + 2] = c % 256
    p += 3
    k += 1
  p

-> gif_loop(out, pos) (u8[] i64) i64
  bytes = [33, 255, 11, 78, 69, 84, 83, 67, 65, 80, 69, 50, 46, 48, 3, 1, 0, 0, 0]
  p = pos
  bytes.each -> (b)
    out[p] = b
    p += 1
  p

# st: 0 = bit buffer, 1 = bit count, 2 = output position, 3 = sub-block start.
-> gif_emit(out, st, code, size) (u8[] i64[] i64 i64) i64
  buf = st[0] + code * (2 ** st[1])
  cnt = st[1] + size
  while cnt >= 8
    gif_byte(out, st, buf % 256)
    buf = buf / 256
    cnt -= 8
  st[0] = buf
  st[1] = cnt
  0

-> gif_byte(out, st, b) (u8[] i64[] i64) i64
  if st[2] - st[3] == 256
    out[st[3]] = 255
    st[3] = st[2]
    st[2] = st[2] + 1
  out[st[2]] = b
  st[2] = st[2] + 1
  0

-> gif_frame(out, pos, idx, n, w, h, delay, bits, dkey, dval, st) (u8[] i64 i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  p = pos
  out[p] = 33
  out[p + 1] = 249
  out[p + 2] = 4
  out[p + 3] = 0
  out[p + 4] = delay % 256
  out[p + 5] = delay / 256
  out[p + 6] = 0
  out[p + 7] = 0
  p += 8
  out[p] = 44
  out[p + 1] = 0
  out[p + 2] = 0
  out[p + 3] = 0
  out[p + 4] = 0
  out[p + 5] = w % 256
  out[p + 6] = w / 256
  out[p + 7] = h % 256
  out[p + 8] = h / 256
  out[p + 9] = 0
  p += 10
  out[p] = bits
  p += 1
  st[0] = 0
  st[1] = 0
  st[3] = p
  st[2] = p + 1
  clear = 2 ** bits
  eoi = clear + 1
  size = bits + 1
  nxt = clear + 2
  i = 0
  while i < 16384
    dkey[i] = -1
    i += 1
  gif_emit(out, st, clear, size)
  cur = idx[0]
  i = 1
  while i < n
    k = idx[i]
    key = cur * 4096 + k
    slot = (key * 2654435761) % 16384
    found = -1
    while dkey[slot] >= 0 && found < 0
      if dkey[slot] == key
        found = dval[slot]
      else
        slot = (slot + 1) % 16384
    if found >= 0
      cur = found
    else
      gif_emit(out, st, cur, size)
      if nxt < 4096
        dkey[slot] = key
        dval[slot] = nxt
        nxt += 1
        if nxt > 2 ** size && size < 12
          size += 1
      else
        gif_emit(out, st, clear, size)
        j = 0
        while j < 16384
          dkey[j] = -1
          j += 1
        size = bits + 1
        nxt = clear + 2
      cur = k
    i += 1
  gif_emit(out, st, cur, size)
  gif_emit(out, st, eoi, size)
  if st[1] > 0
    gif_byte(out, st, st[0] % 256)
  out[st[3]] = st[2] - st[3] - 1
  out[st[2]] = 0
  st[2] + 1


# --------------------------------------------------------------------------
# 5x7 glyphs: seven row bitmasks (bit 4 = leftmost column) per character.

+ RasterFont
  -> .glyph(table, code)
    if table.has_key?(code)
      table[code]
    else
      [31, 17, 17, 17, 17, 17, 31]

  -> .build
    t = {}
    t[32] = [0, 0, 0, 0, 0, 0, 0]
    t[33] = [4, 4, 4, 4, 4, 0, 4]
    t[35] = [10, 10, 31, 10, 31, 10, 10]
    t[37] = [24, 25, 2, 4, 8, 19, 3]
    t[40] = [2, 4, 8, 8, 8, 4, 2]
    t[41] = [8, 4, 2, 2, 2, 4, 8]
    t[42] = [0, 4, 21, 14, 21, 4, 0]
    t[43] = [0, 4, 4, 31, 4, 4, 0]
    t[44] = [0, 0, 0, 0, 12, 4, 8]
    t[45] = [0, 0, 0, 31, 0, 0, 0]
    t[46] = [0, 0, 0, 0, 0, 12, 12]
    t[47] = [0, 1, 2, 4, 8, 16, 0]
    t[48] = [14, 17, 19, 21, 25, 17, 14]
    t[49] = [4, 12, 4, 4, 4, 4, 14]
    t[50] = [14, 17, 1, 2, 4, 8, 31]
    t[51] = [31, 2, 4, 2, 1, 17, 14]
    t[52] = [2, 6, 10, 18, 31, 2, 2]
    t[53] = [31, 16, 30, 1, 1, 17, 14]
    t[54] = [6, 8, 16, 30, 17, 17, 14]
    t[55] = [31, 1, 2, 4, 8, 8, 8]
    t[56] = [14, 17, 17, 14, 17, 17, 14]
    t[57] = [14, 17, 17, 15, 1, 2, 12]
    t[58] = [0, 12, 12, 0, 12, 12, 0]
    t[59] = [0, 12, 12, 0, 12, 4, 8]
    t[60] = [2, 4, 8, 16, 8, 4, 2]
    t[61] = [0, 0, 31, 0, 31, 0, 0]
    t[62] = [8, 4, 2, 1, 2, 4, 8]
    t[63] = [14, 17, 1, 2, 4, 0, 4]
    t[65] = [14, 17, 17, 31, 17, 17, 17]
    t[66] = [30, 17, 17, 30, 17, 17, 30]
    t[67] = [14, 17, 16, 16, 16, 17, 14]
    t[68] = [28, 18, 17, 17, 17, 18, 28]
    t[69] = [31, 16, 16, 30, 16, 16, 31]
    t[70] = [31, 16, 16, 30, 16, 16, 16]
    t[71] = [14, 17, 16, 23, 17, 17, 15]
    t[72] = [17, 17, 17, 31, 17, 17, 17]
    t[73] = [14, 4, 4, 4, 4, 4, 14]
    t[74] = [7, 2, 2, 2, 2, 18, 12]
    t[75] = [17, 18, 20, 24, 20, 18, 17]
    t[76] = [16, 16, 16, 16, 16, 16, 31]
    t[77] = [17, 27, 21, 21, 17, 17, 17]
    t[78] = [17, 17, 25, 21, 19, 17, 17]
    t[79] = [14, 17, 17, 17, 17, 17, 14]
    t[80] = [30, 17, 17, 30, 16, 16, 16]
    t[81] = [14, 17, 17, 17, 21, 18, 13]
    t[82] = [30, 17, 17, 30, 20, 18, 17]
    t[83] = [15, 16, 16, 14, 1, 1, 30]
    t[84] = [31, 4, 4, 4, 4, 4, 4]
    t[85] = [17, 17, 17, 17, 17, 17, 14]
    t[86] = [17, 17, 17, 17, 17, 10, 4]
    t[87] = [17, 17, 17, 21, 21, 21, 10]
    t[88] = [17, 17, 10, 4, 10, 17, 17]
    t[89] = [17, 17, 17, 10, 4, 4, 4]
    t[90] = [31, 1, 2, 4, 8, 16, 31]
    t[91] = [14, 8, 8, 8, 8, 8, 14]
    t[93] = [14, 2, 2, 2, 2, 2, 14]
    t[94] = [4, 10, 17, 0, 0, 0, 0]
    t[95] = [0, 0, 0, 0, 0, 0, 31]
    t[124] = [4, 4, 4, 4, 4, 4, 4]
    t
