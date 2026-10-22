# studio/raster — the per-pixel kernels: typed top-level functions over f32 planes and raw RGBA8 pointers.
#
# Pixels arrive from CoreGraphics canvases (premultiplied RGBA8, opaque here, so straight) through their data
# pointers and leave as RGBA8 into a layer canvas or packed RGB24 for an encoder. The working image is interleaved
# float RGB in [0, 1] (wb, 3 floats per pixel). Every kernel is a pure function of its inputs: no hidden state.

# ---------------------------------------------------------------------------------------------- load / mix

-> rs_load(src, stride, w, h, wb) (i64 i64 i64 i64 f32[]) i64
  y = 0
  while y < h
    row = y * stride
    o = y * w * 3
    x = 0
    while x < w
      p = row + x * 4
      wb[o] = ((raw_load_u8(src, p) ## f64) * ~0.00392156862745098) ## f32
      wb[o + 1] = ((raw_load_u8(src, p + 1) ## f64) * ~0.00392156862745098) ## f32
      wb[o + 2] = ((raw_load_u8(src, p + 2) ## f64) * ~0.00392156862745098) ## f32
      o += 3
      x += 1
    y += 1
  0

# wb = a * (1 - t) + b * t
-> rs_lerp2(a, b, stride, w, h, t, wb) (i64 i64 i64 i64 i64 f64 f32[]) i64
  s = ~1.0 - t
  y = 0
  while y < h
    row = y * stride
    o = y * w * 3
    x = 0
    while x < w
      p = row + x * 4
      c = 0
      while c < 3
        va = raw_load_u8(a, p + c) ## f64
        vb = raw_load_u8(b, p + c) ## f64
        wb[o + c] = ((va * s + vb * t) * ~0.00392156862745098) ## f32
        c += 1
      o += 3
      x += 1
    y += 1
  0

# s36: a scan line at x = pos reveals b over a (60 px soft edge), with a warm glow while it crosses.
-> rs_wipe(a, b, stride, w, h, pos, glow, wb) (i64 i64 i64 i64 i64 f64 i64 f32[]) i64
  y = 0
  while y < h
    row = y * stride
    o = y * w * 3
    x = 0
    while x < w
      xf = x ## f64
      m = (pos - xf) / ~60.0 + ~0.5
      if m < ~0.0
        m = ~0.0
      if m > ~1.0
        m = ~1.0
      g = ~0.0
      if glow != 0
        d = (xf - pos) / ~9.0
        g = Math.exp(~0.0 - d * d) * ~0.8
      p = row + x * 4
      c = 0
      while c < 3
        va = (raw_load_u8(a, p + c) ## f64) * ~0.00392156862745098
        vb = (raw_load_u8(b, p + c) ## f64) * ~0.00392156862745098
        v = va * (~1.0 - m) + vb * m
        if glow != 0
          tint = ~1.0
          tint = ~0.85 if c == 1
          tint = ~0.5 if c == 2
          v = v + g * tint
          if v > ~1.0
            v = ~1.0
          if v < ~0.0
            v = ~0.0
        wb[o + c] = v ## f32
        c += 1
      o += 3
      x += 1
    y += 1
  0

# ---------------------------------------------------------------------------------------------- fx

-> rs_scale(wb, n, s) (f32[] i64 f64) i64
  i = 0
  while i < n
    wb[i] = ((wb[i] ## f64) * s) ## f32
    i += 1
  0

-> rs_clip(wb, n) (f32[] i64) i64
  i = 0
  while i < n
    v = wb[i] ## f64
    if v < ~0.0
      wb[i] = ~0.0 ## f32
    if v > ~1.0
      wb[i] = ~1.0 ## f32
    i += 1
  0

# rain sheet (w x h2), rolled down by off rows: x += (1 - x) * r * 0.22 * [0.8, 0.9, 1.0]
-> rs_rain(wb, w, h, rain, h2, off) (f32[] i64 i64 f32[] i64 i64) i64
  y = 0
  while y < h
    sy = (y - off) % h2
    sy = sy + h2 if sy < 0
    rrow = sy * w
    o = y * w * 3
    x = 0
    while x < w
      r = (rain[rrow + x] ## f64) * ~0.22
      wb[o] = ((wb[o] ## f64) + (~1.0 - (wb[o] ## f64)) * r * ~0.8) ## f32
      wb[o + 1] = ((wb[o + 1] ## f64) + (~1.0 - (wb[o + 1] ## f64)) * r * ~0.9) ## f32
      wb[o + 2] = ((wb[o + 2] ## f64) + (~1.0 - (wb[o + 2] ## f64)) * r) ## f32
      o += 3
      x += 1
    y += 1
  0

# fog field (fw = 2w wide), shifted right by off columns: x += (0.75 - x) * f * 0.26
-> rs_fog(wb, w, h, fog, fw, off) (f32[] i64 i64 f32[] i64 i64) i64
  y = 0
  while y < h
    frow = y * fw + off
    o = y * w * 3
    x = 0
    while x < w
      f = (fog[frow + x] ## f64) * ~0.26
      c = 0
      while c < 3
        v = wb[o + c] ## f64
        wb[o + c] = (v + (~0.75 - v) * f) ## f32
        c += 1
      o += 3
      x += 1
    y += 1
  0

# Particles (snow, dust/embers): closed-form positions in item-local time t, drawn as discs into pb (max), blurred
# (sigma 1, 7x7) only around each particle, then screened over the image: x += (1 - x) * a * col * op.
# parts: 5 floats per particle (x0, y0, size, speed, phase), as render.py's table.
-> rs_particles(wb, w, h, parts, np, t, snow, pb, bb, gk) (f32[] i64 i64 f64[] i64 f64 i64 f32[] f32[] f64[]) i64
  wf = w ## f64
  hf = h ## f64
  cr = ~1.0
  cg = ~0.85
  cb = ~0.6
  op = ~0.35
  if snow != 0
    cr = ~0.9
    cg = ~0.95
    cb = ~1.0
    op = ~0.55
  # pass 1: discs
  k = 0
  while k < np
    x0 = parts[k * 5]
    y0 = parts[k * 5 + 1]
    sz = parts[k * 5 + 2]
    sp = parts[k * 5 + 3]
    ph = parts[k * 5 + 4]
    px = ~0.0
    py = ~0.0
    r = ~0.0
    fill = ~0.0
    if snow != 0
      py = (y0 * hf + t * (~40.0 + ~70.0 * sp)) % hf
      px = (x0 * wf + ~25.0 * Math.sin(t * ~0.8 + ph * ~6.28) + t * ~12.0) % wf
      r = ~1.0 + sz * ~3.0
      fill = (~120.0 + ~120.0 * sz) / ~255.0
    else
      px = (x0 * wf + t * (~6.0 + ~10.0 * sp) + ~18.0 * Math.sin(t * ~0.3 + ph * ~6.28)) % wf
      py = (y0 * hf - t * (~3.0 + ~6.0 * sp) + ~10.0 * Math.cos(t * ~0.4 + ph * ~6.28)) % hf
      r = ~0.8 + sz * ~2.2
      fill = (~60.0 + ~120.0 * sz) / ~255.0
    px = px + wf if px < ~0.0
    py = py + hf if py < ~0.0
    ax = Math.floor(px - r - ~1.0) ## i64
    bx = Math.floor(px + r + ~1.0) ## i64
    ay = Math.floor(py - r - ~1.0) ## i64
    by = Math.floor(py + r + ~1.0) ## i64
    ax = 0 if ax < 0
    ay = 0 if ay < 0
    bx = w - 1 if bx > w - 1
    by = h - 1 if by > h - 1
    yy = ay
    while yy <= by
      xx = ax
      while xx <= bx
        dx = (xx ## f64) + ~0.5 - px
        dy = (yy ## f64) + ~0.5 - py
        cov = r + ~0.5 - Math.sqrt(dx * dx + dy * dy)
        if cov > ~0.0
          cov = ~1.0 if cov > ~1.0
          v = cov * fill
          i = yy * w + xx
          if v > (pb[i] ## f64)
            pb[i] = v ## f32
        xx += 1
      yy += 1
    k += 1
  # pass 2: blur around each particle into bb (assignment, so overlapping boxes agree)
  k = 0
  while k < np
    box = rs_particle_box(parts, k, w, h, t, snow)
    ax = box % 2048
    ay = (box / 2048) % 1024
    bx = (box / 2097152) % 2048
    by = box / 4294967296
    yy = ay
    while yy <= by
      xx = ax
      while xx <= bx
        acc = ~0.0
        j = -3
        while j <= 3
          sy = yy + j
          if sy >= 0 && sy < h
            i2 = -3
            while i2 <= 3
              sx = xx + i2
              if sx >= 0 && sx < w
                acc = acc + (pb[sy * w + sx] ## f64) * gk[(j + 3) * 7 + i2 + 3]
              i2 += 1
          j += 1
        bb[yy * w + xx] = acc ## f32
        xx += 1
      yy += 1
    k += 1
  # pass 3: screen once per pixel (bb zeroed after use), then clear pb
  k = 0
  while k < np
    box = rs_particle_box(parts, k, w, h, t, snow)
    ax = box % 2048
    ay = (box / 2048) % 1024
    bx = (box / 2097152) % 2048
    by = box / 4294967296
    yy = ay
    while yy <= by
      xx = ax
      while xx <= bx
        i = yy * w + xx
        a = bb[i] ## f64
        if a > ~0.0
          o = i * 3
          v = wb[o] ## f64
          wb[o] = (v + (~1.0 - v) * a * cr * op) ## f32
          v = wb[o + 1] ## f64
          wb[o + 1] = (v + (~1.0 - v) * a * cg * op) ## f32
          v = wb[o + 2] ## f64
          wb[o + 2] = (v + (~1.0 - v) * a * cb * op) ## f32
          bb[i] = ~0.0 ## f32
        xx += 1
      yy += 1
    k += 1
  k = 0
  while k < np
    box = rs_particle_box(parts, k, w, h, t, snow)
    ax = box % 2048
    ay = (box / 2048) % 1024
    bx = (box / 2097152) % 2048
    by = box / 4294967296
    yy = ay
    while yy <= by
      xx = ax
      while xx <= bx
        pb[yy * w + xx] = ~0.0 ## f32
        xx += 1
      yy += 1
    k += 1
  0

# The blur box of particle k (disc box + 3 px), packed ax | ay << 11 | bx << 21 | by << 32 (under 2^47, so the
# boxed return value stays an immediate).
-> rs_particle_box(parts, k, w, h, t, snow) (f64[] i64 i64 i64 f64 i64) i64
  wf = w ## f64
  hf = h ## f64
  x0 = parts[k * 5]
  y0 = parts[k * 5 + 1]
  sz = parts[k * 5 + 2]
  sp = parts[k * 5 + 3]
  ph = parts[k * 5 + 4]
  px = ~0.0
  py = ~0.0
  r = ~0.0
  if snow != 0
    py = (y0 * hf + t * (~40.0 + ~70.0 * sp)) % hf
    px = (x0 * wf + ~25.0 * Math.sin(t * ~0.8 + ph * ~6.28) + t * ~12.0) % wf
    r = ~1.0 + sz * ~3.0
  else
    px = (x0 * wf + t * (~6.0 + ~10.0 * sp) + ~18.0 * Math.sin(t * ~0.3 + ph * ~6.28)) % wf
    py = (y0 * hf - t * (~3.0 + ~6.0 * sp) + ~10.0 * Math.cos(t * ~0.4 + ph * ~6.28)) % hf
    r = ~0.8 + sz * ~2.2
  px = px + wf if px < ~0.0
  py = py + hf if py < ~0.0
  ax = Math.floor(px - r - ~4.0) ## i64
  bx = Math.floor(px + r + ~4.0) ## i64
  ay = Math.floor(py - r - ~4.0) ## i64
  by = Math.floor(py + r + ~4.0) ## i64
  ax = 0 if ax < 0
  ay = 0 if ay < 0
  bx = w - 1 if bx > w - 1
  by = h - 1 if by > h - 1
  ax + ay * 2048 + bx * 2097152 + by * 4294967296

# ---------------------------------------------------------------------------------------------- grade
# render.py grade(): tints by luminance, a soft S-curve, saturation 0.94, bloom from the highlights (luma > 0.68,
# down 8x, blurred, back up bilinear), lift 0.02 / gain 0.965, vignette, luma-weighted grain, clip.
# gp (f64[16]): 0-2 shadow tint, 3-5 highlight tint, 6 contrast mix, 7 saturation, 8-10 bloom tint, 11 lift,
# 12 gain, 13 grain base, 14 grain mid, 15 bloom threshold.

# Pass 1: luminance per pixel into lb, highlight map averaged into the gw x gh grid.
-> rs_grade1(wb, w, h, lb, grid, cnt, gw, gh, thr) (f32[] i64 i64 f32[] f64[] f64[] i64 i64 f64) i64
  n = gw * gh
  i = 0
  while i < n
    grid[i] = ~0.0
    cnt[i] = ~0.0
    i += 1
  inv = ~1.0 / (~1.0 - thr)
  y = 0
  while y < h
    gy = y * gh / h
    o = y * w
    x = 0
    while x < w
      j = (o + x) * 3
      l = (wb[j] ## f64) * ~0.2126 + (wb[j + 1] ## f64) * ~0.7152 + (wb[j + 2] ## f64) * ~0.0722
      lb[o + x] = l ## f32
      hi = (l - thr) * inv
      hi = ~0.0 if hi < ~0.0
      hi = ~1.0 if hi > ~1.0
      hq = Math.floor(hi * ~255.0) ## f64
      g = gy * gw + x * gw / w
      grid[g] = grid[g] + hq
      cnt[g] = cnt[g] + ~1.0
      x += 1
    y += 1
  i = 0
  while i < n
    grid[i] = grid[i] / cnt[i] if cnt[i] > ~0.0
    i += 1
  0

# Separable gaussian on a small grid (edges clamp, as PIL extends them); tmp is gw * gh.
-> rs_blur_grid(grid, tmp, gw, gh, sigma) (f64[] f64[] i64 i64 f64) i64
  rad = Math.ceil(sigma * ~3.0) ## i64
  y = 0
  while y < gh
    x = 0
    while x < gw
      acc = ~0.0
      ws = ~0.0
      k = -rad
      while k <= rad
        sx = x + k
        sx = 0 if sx < 0
        sx = gw - 1 if sx > gw - 1
        kf = k ## f64
        wt = Math.exp(~0.0 - kf * kf / (~2.0 * sigma * sigma))
        acc = acc + grid[y * gw + sx] * wt
        ws = ws + wt
        k += 1
      tmp[y * gw + x] = acc / ws
      x += 1
    y += 1
  y = 0
  while y < gh
    x = 0
    while x < gw
      acc = ~0.0
      ws = ~0.0
      k = -rad
      while k <= rad
        sy = y + k
        sy = 0 if sy < 0
        sy = gh - 1 if sy > gh - 1
        kf = k ## f64
        wt = Math.exp(~0.0 - kf * kf / (~2.0 * sigma * sigma))
        acc = acc + tmp[sy * gw + x] * wt
        ws = ws + wt
        k += 1
      grid[y * gw + x] = acc / ws
      x += 1
    y += 1
  0

# Pass 2: the grade proper, written as opaque RGBA8 at (ox, oy) of the destination canvas. vig and grain are
# planes of vw x vh (the full active picture); the image samples them from column vx0 (panes of the triptych sit
# at the picture's left edge, as render.py graded them on a zero-padded full-width image). The grain plane is read
# with a toroidal offset (gox, goy). Rows from h - fade_rows fade linearly to fade_to; alpha scales the result.
-> rs_grade2(wb, lb, w, h, grid, gw, gh, gp, vig, grain, vw, vh, vx0, gox, goy, fade_rows, fade_to, alpha, dst, stride, ox, oy) (f32[] f32[] i64 i64 f64[] i64 i64 f64[] f32[] f32[] i64 i64 i64 i64 i64 i64 f64 f64 i64 i64 i64 i64) i64
  str = gp[0]
  stg = gp[1]
  stb = gp[2]
  htr = gp[3]
  htg = gp[4]
  htb = gp[5]
  cmix = gp[6]
  sat = gp[7]
  btr = gp[8]
  btg = gp[9]
  btb = gp[10]
  lift = gp[11]
  gain = gp[12]
  gbase = gp[13]
  gmid = gp[14]
  sx = (gw ## f64) / (vw ## f64)
  sy = (gh ## f64) / (vh ## f64)
  y = 0
  while y < h
    # bloom: bilinear sample of the grid at this row (pixel centres, edges clamped)
    fy = ((y ## f64) + ~0.5) * sy - ~0.5
    fy = ~0.0 if fy < ~0.0
    y0 = Math.floor(fy) ## i64
    y1 = y0 + 1
    y1 = gh - 1 if y1 > gh - 1
    ty = fy - (y0 ## f64)
    rowfade = ~1.0
    if fade_rows > 0 && y >= h - fade_rows
      k = y - (h - fade_rows)
      rowfade = ~1.0 + (fade_to - ~1.0) * (k ## f64) / ((fade_rows - 1) ## f64)
    rowfade = rowfade * alpha
    gyy = (y + goy) % vh
    drow = (oy + y) * stride + ox * 4
    o = y * w
    x = 0
    while x < w
      vx = vx0 + x
      fx = ((vx ## f64) + ~0.5) * sx - ~0.5
      fx = ~0.0 if fx < ~0.0
      x0 = Math.floor(fx) ## i64
      x1 = x0 + 1
      x1 = gw - 1 if x1 > gw - 1
      tx = fx - (x0 ## f64)
      b00 = grid[y0 * gw + x0]
      b01 = grid[y0 * gw + x1]
      b10 = grid[y1 * gw + x0]
      b11 = grid[y1 * gw + x1]
      bl = ((b00 * (~1.0 - tx) + b01 * tx) * (~1.0 - ty) + (b10 * (~1.0 - tx) + b11 * tx) * ty) * ~0.00392156862745098
      j = (o + x) * 3
      l = lb[o + x] ## f64
      sh = (~1.0 - l) * (~1.0 - l)
      hl = l * l
      r = (wb[j] ## f64) + sh * str + hl * htr
      g = (wb[j + 1] ## f64) + sh * stg + hl * htg
      b = (wb[j + 2] ## f64) + sh * stb + hl * htb
      s = r * r * (~3.0 - ~2.0 * r)
      s = ~0.0 if s < ~0.0
      s = ~1.0 if s > ~1.0
      r = r * (~1.0 - cmix) + s * cmix
      s = g * g * (~3.0 - ~2.0 * g)
      s = ~0.0 if s < ~0.0
      s = ~1.0 if s > ~1.0
      g = g * (~1.0 - cmix) + s * cmix
      s = b * b * (~3.0 - ~2.0 * b)
      s = ~0.0 if s < ~0.0
      s = ~1.0 if s > ~1.0
      b = b * (~1.0 - cmix) + s * cmix
      r = l + (r - l) * sat
      g = l + (g - l) * sat
      b = l + (b - l) * sat
      r = r + bl * btr
      g = g + bl * btg
      b = b + bl * btb
      r = lift + r * gain
      g = lift + g * gain
      b = lift + b * gain
      vi = y * vw + vx
      v = vig[vi] ## f64
      gr = (grain[gyy * vw + (vx + gox) % vw] ## f64) * (gbase + gmid * l * (~1.0 - l))
      r = r * v + gr
      g = g * v + gr
      b = b * v + gr
      r = ~0.0 if r < ~0.0
      r = ~1.0 if r > ~1.0
      g = ~0.0 if g < ~0.0
      g = ~1.0 if g > ~1.0
      b = ~0.0 if b < ~0.0
      b = ~1.0 if b > ~1.0
      r = r * rowfade
      g = g * rowfade
      b = b * rowfade
      p = drow + x * 4
      raw_store_u8(dst, p, Math.floor(r * ~255.0 + ~0.5) ## i64)
      raw_store_u8(dst, p + 1, Math.floor(g * ~255.0 + ~0.5) ## i64)
      raw_store_u8(dst, p + 2, Math.floor(b * ~255.0 + ~0.5) ## i64)
      raw_store_u8(dst, p + 3, 255)
      x += 1
    y += 1
  0

# ---------------------------------------------------------------------------------------------- planes
# Precomputed fields, all keyed by (seed, owner, purpose) through the counter RNG.

# Grain texture: N(0, 1) clipped as render.py's uint8 round trip ([-3.2, 3.175]), blurred sigma 0.7 (5 taps).
-> rs_grain_tex(key, w, h, buf, tmp) (i64 i64 i64 f32[] f32[]) i64
  n = w * h
  rng_fill_normals(key, n, tmp)
  i = 0
  while i < n
    v = tmp[i] ## f64
    if v < ~0.0 - ~3.2
      tmp[i] = (~0.0 - ~3.2) ## f32
    if v > ~3.175
      tmp[i] = ~3.175 ## f32
    i += 1
  k0 = ~1.0
  k1 = Math.exp((~0.0 - ~1.0) / (~2.0 * ~0.49))
  k2 = Math.exp((~0.0 - ~4.0) / (~2.0 * ~0.49))
  ks = k0 + ~2.0 * k1 + ~2.0 * k2
  k0 = k0 / ks
  k1 = k1 / ks
  k2 = k2 / ks
  y = 0
  while y < h
    x = 0
    while x < w
      xm1 = x - 1
      xm1 = 0 if xm1 < 0
      xm2 = x - 2
      xm2 = 0 if xm2 < 0
      xp1 = x + 1
      xp1 = w - 1 if xp1 > w - 1
      xp2 = x + 2
      xp2 = w - 1 if xp2 > w - 1
      r = y * w
      v = (tmp[r + x] ## f64) * k0 + ((tmp[r + xm1] ## f64) + (tmp[r + xp1] ## f64)) * k1 + ((tmp[r + xm2] ## f64) + (tmp[r + xp2] ## f64)) * k2
      buf[r + x] = v ## f32
      x += 1
    y += 1
  y = 0
  while y < h
    ym1 = y - 1
    ym1 = 0 if ym1 < 0
    ym2 = y - 2
    ym2 = 0 if ym2 < 0
    yp1 = y + 1
    yp1 = h - 1 if yp1 > h - 1
    yp2 = y + 2
    yp2 = h - 1 if yp2 > h - 1
    x = 0
    while x < w
      v = (buf[y * w + x] ## f64) * k0 + ((buf[ym1 * w + x] ## f64) + (buf[yp1 * w + x] ## f64)) * k1 + ((buf[ym2 * w + x] ## f64) + (buf[yp2 * w + x] ## f64)) * k2
      tmp[y * w + x] = v ## f32
      x += 1
    y += 1
  i = 0
  while i < n
    buf[i] = tmp[i]
    i += 1
  0

# Vignette: 1 - amount * clip(nx^2 * ax + ny^2 * ay, 0, cl)^pw, nx/ny in [-1, 1) from the pixel index.
-> rs_vignette(w, h, amount, ax, ay, cl, pw, buf) (i64 i64 f64 f64 f64 f64 f64 f32[]) i64
  y = 0
  while y < h
    ny = ((y ## f64) / (h ## f64) - ~0.5) * ~2.0
    x = 0
    while x < w
      nx = ((x ## f64) / (w ## f64) - ~0.5) * ~2.0
      q = nx * nx * ax + ny * ny * ay
      q = ~0.0 if q < ~0.0
      q = cl if q > cl
      qp = ~0.0
      if q > ~0.0
        qp = Math.exp(pw * Math.log(q))
      buf[y * w + x] = (~1.0 - amount * qp) ## f32
      x += 1
    y += 1
  0

# Box blur (one pass, radius r, edges clamped) along rows of a w x h plane; three passes ~ gaussian.
-> rs_box_rows(src, dst, w, h, r) (f32[] f32[] i64 i64 i64) i64
  inv = ~1.0 / ((2 * r + 1) ## f64)
  y = 0
  while y < h
    row = y * w
    acc = ~0.0
    k = -r
    while k <= r
      sx = k
      sx = 0 if sx < 0
      sx = w - 1 if sx > w - 1
      acc = acc + (src[row + sx] ## f64)
      k += 1
    x = 0
    while x < w
      dst[row + x] = (acc * inv) ## f32
      xa = x + r + 1
      xa = w - 1 if xa > w - 1
      xr = x - r
      xr = 0 if xr < 0
      acc = acc + (src[row + xa] ## f64) - (src[row + xr] ## f64)
      x += 1
    y += 1
  0

-> rs_box_cols(src, dst, w, h, r) (f32[] f32[] i64 i64 i64) i64
  inv = ~1.0 / ((2 * r + 1) ## f64)
  x = 0
  while x < w
    acc = ~0.0
    k = -r
    while k <= r
      sy = k
      sy = 0 if sy < 0
      sy = h - 1 if sy > h - 1
      acc = acc + (src[sy * w + x] ## f64)
      k += 1
    y = 0
    while y < h
      dst[y * w + x] = (acc * inv) ## f32
      ya = y + r + 1
      ya = h - 1 if ya > h - 1
      yr = y - r
      yr = 0 if yr < 0
      acc = acc + (src[ya * w + x] ## f64) - (src[yr * w + x] ## f64)
      y += 1
    x += 1
  0

# Bilinear upsample of a small random field (sw x sh uniforms, in small) to w x h.
-> rs_upsample(small, sw, sh, w, h, dst) (f64[] i64 i64 i64 i64 f32[]) i64
  y = 0
  while y < h
    fy = ((y ## f64) + ~0.5) * (sh ## f64) / (h ## f64) - ~0.5
    fy = ~0.0 if fy < ~0.0
    y0 = Math.floor(fy) ## i64
    y1 = y0 + 1
    y1 = sh - 1 if y1 > sh - 1
    ty = fy - (y0 ## f64)
    x = 0
    while x < w
      fx = ((x ## f64) + ~0.5) * (sw ## f64) / (w ## f64) - ~0.5
      fx = ~0.0 if fx < ~0.0
      x0 = Math.floor(fx) ## i64
      x1 = x0 + 1
      x1 = sw - 1 if x1 > sw - 1
      tx = fx - (x0 ## f64)
      a = small[y0 * sw + x0]
      b = small[y0 * sw + x1]
      c = small[y1 * sw + x0]
      d = small[y1 * sw + x1]
      dst[y * w + x] = ((a * (~1.0 - tx) + b * tx) * (~1.0 - ty) + (c * (~1.0 - tx) + d * tx) * ty) ## f32
      x += 1
    y += 1
  0

-> rs_normalize(buf, n) (f32[] i64) i64
  lo = ~1.0e30
  hi = ~0.0 - ~1.0e30
  i = 0
  while i < n
    v = buf[i] ## f64
    lo = v if v < lo
    hi = v if v > hi
    i += 1
  sc = ~1.0 / (hi - lo + ~0.000001)
  i = 0
  while i < n
    buf[i] = (((buf[i] ## f64) - lo) * sc) ## f32
    i += 1
  0

# Rain sheet: 1400 streaks (1 px, slanted) at random places, lengths and brightness, blurred ~0.6.
-> rs_rain_sheet(key, w, h2, buf, tmp) (i64 i64 i64 f32[] f32[]) i64
  n = w * h2
  i = 0
  while i < n
    buf[i] = ~0.0 ## f32
    i += 1
  k = 0
  while k < 1400
    x = rng_u(key, k * 4) * (w ## f64)
    y = rng_u(key, k * 4 + 1) * (h2 ## f64)
    ln = ~18.0 + rng_u(key, k * 4 + 2) * ~42.0
    v = (~60.0 + rng_u(key, k * 4 + 3) * ~140.0) / ~255.0
    steps = Math.ceil(ln) ## i64
    s = 0
    while s <= steps
      f = (s ## f64) / (steps ## f64)
      px = Math.floor(x - ln * ~0.18 * f + ~0.5) ## i64
      py = Math.floor(y + ln * f + ~0.5) ## i64
      if px >= 0 && px < w && py >= 0 && py < h2
        if v > (buf[py * w + px] ## f64)
          buf[py * w + px] = v ## f32
      s += 1
    k += 1
  rs_box_rows(buf, tmp, w, h2, 1)
  rs_box_cols(tmp, buf, w, h2, 1)
  # a 3x3 box is a little wider than sigma 0.6; mix it back toward the sharp streaks
  0

# ---------------------------------------------------------------------------------------------- compose

-> rs_copy_rgb(src, stride, w, h, out) (i64 i64 i64 i64 u8[]) i64
  y = 0
  while y < h
    row = y * stride
    o = y * w * 3
    x = 0
    while x < w
      p = row + x * 4
      out[o] = raw_load_u8(src, p)
      out[o + 1] = raw_load_u8(src, p + 1)
      out[o + 2] = raw_load_u8(src, p + 2)
      o += 3
      x += 1
    y += 1
  0

# (integer locals before the casts: see selftest in render.w)
-> rs_mix_rgb(a, b, stride, w, h, t, out) (i64 i64 i64 i64 i64 f64 u8[]) i64
  s = ~1.0 - t
  y = 0
  while y < h
    row = y * stride
    o = y * w * 3
    x = 0
    while x < w
      p = row + x * 4
      c = 0
      while c < 3
        ia = raw_load_u8(a, p + c)
        ib = raw_load_u8(b, p + c)
        v = (ia ## f64) * s + (ib ## f64) * t
        q = Math.floor(v + ~0.5) ## i64
        out[o + c] = q
        c += 1
      o += 3
      x += 1
    y += 1
  0

# (the element goes through an integer local: see selftest in render.w)
-> rs_scale_rgb(out, n, s) (u8[] i64 f64) i64
  i = 0
  while i < n
    x = out[i]
    v = (x ## f64) * s
    q = Math.floor(v + ~0.5) ## i64
    out[i] = q
    i += 1
  0

-> rs_copy_rows(src, dst, stride, y0, y1) (i64 i64 i64 i64 i64) i64
  i = y0 * stride
  e = y1 * stride
  while i < e
    raw_store_u8(dst, i, raw_load_u8(src, i))
    i += 1
  0

-> rs_fill_rows(dst, stride, w, y0, y1, r, g, b) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  y = y0
  while y < y1
    p = y * stride
    x = 0
    while x < w
      raw_store_u8(dst, p, r)
      raw_store_u8(dst, p + 1, g)
      raw_store_u8(dst, p + 2, b)
      raw_store_u8(dst, p + 3, 255)
      p += 4
      x += 1
    y += 1
  0

# The card background: base colour + paper * 0.05 * [0.6, 0.85, 1.0], written opaque into a canvas.
-> rs_card_base(paper, w, h, dst, stride) (f32[] i64 i64 i64 i64) i64
  y = 0
  while y < h
    x = 0
    while x < w
      pv = (paper[y * w + x] ## f64) * ~0.05
      r = ~0.04 + pv * ~0.6
      g = ~0.055 + pv * ~0.85
      b = ~0.085 + pv
      p = y * stride + x * 4
      raw_store_u8(dst, p, Math.floor(r * ~255.0) ## i64)
      raw_store_u8(dst, p + 1, Math.floor(g * ~255.0) ## i64)
      raw_store_u8(dst, p + 2, Math.floor(b * ~255.0) ## i64)
      raw_store_u8(dst, p + 3, 255)
      x += 1
    y += 1
  0

# Error-free product (Dekker/Veltkamp): sign of x * m - n, exactly, for the bars' centuries rounding (render.py
# quantized Decimal(gap / 100), the exact value of the double, half up).
-> exact_sign_mul_sub(x, m, n) (f64 f64 f64) i64
  p = x * m
  c = ~134217729.0 * x
  xh = c - (c - x)
  xl = x - xh
  c2 = ~134217729.0 * m
  mh = c2 - (c2 - m)
  ml = m - mh
  e = ((xh * mh - p) + xh * ml + xl * mh) + xl * ml
  d = (p - n) + e
  return 1 if d > ~0.0
  return -1 if d < ~0.0
  0
