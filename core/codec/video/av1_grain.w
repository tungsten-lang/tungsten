# core/codec/video/av1_grain — AV1 film grain synthesis (spec 7.18.3), applied to a copy
# of each output frame (reference frames stay grain-free).
#
#   out = av1_apply_grain(frame, grain_params_hash, matrix_coefficients)

use av1_tables

-> av1_fg_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_GAUSS_T = av1_fg_i32(AV1_GAUSSIAN_SEQUENCE)

-> av1_fg_points(pts)
  out = i32[32]
  i = 0
  while i < pts.size
    out[i * 2] = pts[i][0]
    out[i * 2 + 1] = pts[i][1]
    i += 1
  out

-> av1_fg_coefs(a)
  out = i32[a.size + 1]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

-> av1_apply_grain(fr, g, mc)
  out = av1_frame_copy(fr)
  bd = fr.bit_depth
  w = fr.width
  h = fr.height
  ssx = fr.ssx
  ssy = fr.ssy
  np = fr.planes.size
  mono = np == 1
  st = i64[1]
  seed = g[:seed]
  gc = 128 << (bd - 8)
  gmin = 0 - gc
  gmax = (256 << (bd - 8)) - 1 - gc
  ny = g[:y_points].size
  ncb = g[:cb_points].size
  ncr = g[:cr_points].size
  cfl = g[:cfl]
  lag = g[:lag]
  ar_shift = g[:ar_shift]
  wshift = 12 - bd + g[:grain_scale_shift]
  # luma grain 82 x 73
  lg = i32[82 * 73]
  st[0] = seed
  av1_fg_white(lg, 82, 73, st, AV1_GAUSS_T, wshift, ny > 0 ? 1 : 0)
  av1_fg_ar_luma(lg, lag, av1_fg_coefs(g[:ar_y]), ar_shift, gmin, gmax) if ny > 0
  cw = ssx == 1 ? 44 : 82
  ch = ssy == 1 ? 38 : 73
  cbg = i32[cw * ch]
  crg = i32[cw * ch]
  if !mono
    st[0] = seed ^ 0xb524
    av1_fg_white(cbg, cw, ch, st, AV1_GAUSS_T, wshift, (ncb > 0 || cfl == 1) ? 1 : 0)
    st[0] = seed ^ 0x49d8
    av1_fg_white(crg, cw, ch, st, AV1_GAUSS_T, wshift, (ncr > 0 || cfl == 1) ? 1 : 0)
    if ncb > 0 || cfl == 1
      av1_fg_ar_chroma(cbg, cw, ch, lg, lag, av1_fg_coefs(g[:ar_cb]), ny > 0 ? 1 : 0, ssx, ssy, ar_shift, gmin, gmax)
    if ncr > 0 || cfl == 1
      av1_fg_ar_chroma(crg, cw, ch, lg, lag, av1_fg_coefs(g[:ar_cr]), ny > 0 ? 1 : 0, ssx, ssy, ar_shift, gmin, gmax)
  # scaling luts
  luts = []
  p = 0
  while p < np
    key = (p == 0 || cfl == 1) ? :y_points : (p == 1 ? :cb_points : :cr_points)
    luts.push(i32[257])
    av1_fg_lut(luts[p], av1_fg_points(g[key]), g[key].size)
    p += 1
  # random offsets per (stripe, 32-wide block)
  nstripes = ((h + 1) / 2 + 15) / 16
  nblk = ((w + 1) / 2 + 15) / 16
  offs = i32[nstripes * nblk]
  av1_fg_offsets(offs, nstripes, nblk, seed, st)
  ov = g[:overlap]
  sw = nblk * 32 + 34
  grains = [lg, cbg, crg]
  gws = [82, cw, cw]
  noise = []
  p = 0
  while p < np
    psx = p > 0 ? ssx : 0
    psy = p > 0 ? ssy : 0
    noise.push(i32[((w + psx) >> psx) * ((h + psy) >> psy)])
    p += 1
  stripes = i32[nstripes * 34 * sw]
  p = 0
  while p < np
    psx = p > 0 ? ssx : 0
    psy = p > 0 ? ssy : 0
    av1_fg_stripes(stripes, sw, grains[p], gws[p], offs, nstripes, nblk, psx, psy, ov, gmin, gmax)
    av1_fg_image(noise[p], (w + psx) >> psx, (h + psy) >> psy, stripes, sw, psy, ov, gmin, gmax)
    p += 1
  minv = 0
  maxl = (256 << (bd - 8)) - 1
  maxc = maxl
  if g[:clip_restricted] == 1
    minv = 16 << (bd - 8)
    maxl = 235 << (bd - 8)
    maxc = mc == 0 ? maxl : (240 << (bd - 8))
  ssh = g[:scaling_shift]
  if !mono
    pw = (w + ssx) >> ssx
    ph = (h + ssy) >> ssy
    if ncb > 0 || cfl == 1
      av1_fg_blend_chroma(out.planes[1], out.strides[1], fr.planes[0], fr.strides[0], noise[1], pw, ph, w, ssx, ssy, cfl,
                          g[:cb_luma_mult] == nil ? 0 : g[:cb_luma_mult], g[:cb_mult] == nil ? 0 : g[:cb_mult], g[:cb_offset] == nil ? 0 : g[:cb_offset],
                          luts[1], bd, ssh, minv, maxc)
    if ncr > 0 || cfl == 1
      av1_fg_blend_chroma(out.planes[2], out.strides[2], fr.planes[0], fr.strides[0], noise[2], pw, ph, w, ssx, ssy, cfl,
                          g[:cr_luma_mult] == nil ? 0 : g[:cr_luma_mult], g[:cr_mult] == nil ? 0 : g[:cr_mult], g[:cr_offset] == nil ? 0 : g[:cr_offset],
                          luts[2], bd, ssh, minv, maxc)
  if ny > 0
    av1_fg_blend_luma(out.planes[0], out.strides[0], noise[0], w, h, luts[0], bd, ssh, minv, maxl)
  out.show = true
  out

-> av1_fg_rand(st, bits) (i64[] i64) i64
  r = (st[0]) ## i64
  bit = (((r >> 0) ^ (r >> 1) ^ (r >> 3) ^ (r >> 12)) & 1) ## i64
  r = (r >> 1) | (bit * 32768)
  st[0] = r
  m = 0 ## i64
  m = (1 << bits) - 1
  (r >> (16 - bits)) & m

-> av1_fg_white(buf, w, h, st, gauss, shift, en) (i32[] i64 i64 i64[] i32[] i64 i64) i64
  rnd = 0 ## i64
  if shift > 0
    rnd = (1 << shift) >> 1
  i = 0 ## i64
  n = (w * h) ## i64
  while i < n
    g = 0 ## i64
    if en == 1
      g = gauss[av1_fg_rand(st, 11)]
    buf[i] = (g + rnd) >> shift
    i += 1
  0

-> av1_fg_ar_luma(lg, lag, coef, shift, gmin, gmax) (i32[] i64 i32[] i64 i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << shift) >> 1
  y = 3 ## i64
  while y < 73
    x = 3 ## i64
    while x < 79
      s = 0 ## i64
      pos = 0 ## i64
      dr = (0 - lag) ## i64
      done = false
      while dr <= 0 && !done
        dc = (0 - lag) ## i64
        while dc <= lag
          if dr == 0 && dc == 0
            done = true
            break
          c = coef[pos] ## i64
          v = lg[(y + dr) * 82 + x + dc] ## i64
          s += v * c
          pos += 1
          dc += 1
        dr += 1
      v = lg[y * 82 + x] + ((s + rnd) >> shift)
      v = gmin if v < gmin
      v = gmax if v > gmax
      lg[y * 82 + x] = v
      x += 1
    y += 1
  0

-> av1_fg_ar_chroma(cg, cw, ch, lg, lag, coef, use_luma, ssx, ssy, shift, gmin, gmax) (i32[] i64 i64 i32[] i64 i32[] i64 i64 i64 i64 i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << shift) >> 1
  y = 3 ## i64
  while y < ch
    x = 3 ## i64
    while x < cw - 3
      s = 0 ## i64
      pos = 0 ## i64
      dr = (0 - lag) ## i64
      done = false
      while dr <= 0 && !done
        dc = (0 - lag) ## i64
        while dc <= lag
          c = coef[pos] ## i64
          if dr == 0 && dc == 0
            if use_luma == 1
              luma = 0 ## i64
              lx = (((x - 3) << ssx) + 3) ## i64
              ly = (((y - 3) << ssy) + 3) ## i64
              i = 0 ## i64
              while i <= ssy
                j = 0 ## i64
                while j <= ssx
                  luma += lg[(ly + i) * 82 + lx + j]
                  j += 1
                i += 1
              sh = (ssx + ssy) ## i64
              if sh > 0
                luma = (luma + (1 << (sh - 1))) >> sh
              s += luma * c
            done = true
            break
          v = cg[(y + dr) * cw + x + dc] ## i64
          s += v * c
          pos += 1
          dc += 1
        dr += 1
      v = cg[y * cw + x] + ((s + rnd) >> shift)
      v = gmin if v < gmin
      v = gmax if v > gmax
      cg[y * cw + x] = v
      x += 1
    y += 1
  0

-> av1_fg_lut(lut, pts, n) (i32[] i32[] i64) i64
  x = 0 ## i64
  if n == 0
    while x < 256
      lut[x] = 0
      x += 1
    return 0
  x0 = pts[0] ## i64
  y0 = pts[1] ## i64
  while x < x0
    lut[x] = y0
    x += 1
  i = 0 ## i64
  while i < n - 1
    ya = pts[i * 2 + 1] ## i64
    yb = pts[i * 2 + 3] ## i64
    xa = pts[i * 2] ## i64
    xb = pts[i * 2 + 2] ## i64
    dy = (yb - ya) ## i64
    dx = (xb - xa) ## i64
    delta = (dy * ((65536 + (dx >> 1)) / dx)) ## i64
    x = 0
    while x < dx
      lut[xa + x] = ya + ((x * delta + 32768) >> 16)
      x += 1
    i += 1
  xl = pts[(n - 1) * 2] ## i64
  yl = pts[(n - 1) * 2 + 1] ## i64
  x = xl
  while x < 256
    lut[x] = yl
    x += 1
  0

-> av1_fg_offsets(offs, nstripes, nblk, seed, st) (i32[] i64 i64 i64 i64[]) i64
  s = 0 ## i64
  while s < nstripes
    r = (seed) ## i64
    r = r ^ (((s * 37 + 178) & 255) * 256)
    r = r ^ ((s * 173 + 105) & 255)
    st[0] = r
    b = 0 ## i64
    while b < nblk
      offs[s * nblk + b] = av1_fg_rand(st, 8)
      b += 1
    s += 1
  0

# noise stripes of one plane: stripe s row i column c at (s * 34 + i) * sw + c
-> av1_fg_stripes(ns, sw, gr, gw, offs, nstripes, nblk, psx, psy, ov, gmin, gmax) (i32[] i64 i32[] i64 i32[] i64 i64 i64 i64 i64 i64 i64) i64
  s = 0 ## i64
  rows = (34 >> psy) ## i64
  cols = (34 >> psx) ## i64
  while s < nstripes
    b = 0 ## i64
    while b < nblk
      x = (b * 16) ## i64
      rv = offs[s * nblk + b] ## i64
      ox = (rv >> 4) ## i64
      oy = (rv & 15) ## i64
      pox = (psx == 1 ? 6 + ox : 9 + ox * 2) ## i64
      poy = (psy == 1 ? 6 + oy : 9 + oy * 2) ## i64
      i = 0 ## i64
      while i < rows
        j = 0 ## i64
        while j < cols
          g = gr[(poy + i) * gw + pox + j] ## i64
          if psx == 0
            o = ((s * 34 + i) * sw + x * 2 + j) ## i64
            if j < 2 && ov == 1 && x > 0
              old = ns[o] ## i64
              if j == 0
                g = old * 27 + g * 17
              else
                g = old * 17 + g * 27
              g = (g + 16) >> 5
              g = gmin if g < gmin
              g = gmax if g > gmax
            ns[o] = g
          else
            o = (s * 34 + i) * sw + x + j
            if j == 0 && ov == 1 && x > 0
              old = ns[o] ## i64
              g = old * 23 + g * 22
              g = (g + 16) >> 5
              g = gmin if g < gmin
              g = gmax if g > gmax
            ns[o] = g
          j += 1
        i += 1
      b += 1
    s += 1
  0

-> av1_fg_image(img, pw, ph, ns, sw, psy, ov, gmin, gmax) (i32[] i64 i64 i32[] i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < ph
    ln = (y >> (5 - psy)) ## i64
    i = (y - ln * (32 >> psy)) ## i64
    x = 0 ## i64
    while x < pw
      g = ns[(ln * 34 + i) * sw + x] ## i64
      if psy == 0
        if i < 2 && ln > 0 && ov == 1
          old = ns[((ln - 1) * 34 + i + 32) * sw + x] ## i64
          if i == 0
            g = old * 27 + g * 17
          else
            g = old * 17 + g * 27
          g = (g + 16) >> 5
          g = gmin if g < gmin
          g = gmax if g > gmax
      else
        if i < 1 && ln > 0 && ov == 1
          old = ns[((ln - 1) * 34 + i + 16) * sw + x] ## i64
          g = old * 23 + g * 22
          g = (g + 16) >> 5
          g = gmin if g < gmin
          g = gmax if g > gmax
      img[y * pw + x] = g
      x += 1
    y += 1
  0

-> av1_fg_scale(lut, idx, bd) (i32[] i64 i64) i64
  sh = (bd - 8) ## i64
  x = (idx >> sh) ## i64
  rem = 0 ## i64
  rem = idx - (x << sh)
  if bd == 8 || x == 255
    return lut[x]
  a = lut[x] ## i64
  b = lut[x + 1] ## i64
  a + (((b - a) * rem + (1 << (sh - 1))) >> sh)

-> av1_fg_blend_chroma(cp, cs, yp, ys, noise, pw, ph, w, ssx, ssy, cfl, lmult, mult, offset, lut, bd, ssh, minv, maxc) (u16[] i64 u16[] i64 i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[] i64 i64 i64 i64) i64
  mx = 0 ## i64
  mx = (1 << bd) - 1
  rnd = 0 ## i64
  rnd = (1 << ssh) >> 1
  offv = 0 ## i64
  offv = (offset - 256) << (bd - 8)
  y = 0 ## i64
  while y < ph
    x = 0 ## i64
    while x < pw
      lx = (x << ssx) ## i64
      ly = (y << ssy) ## i64
      lnx = (lx + 1) ## i64
      lnx = w - 1 if lnx > w - 1
      avg = 0 ## i64
      if ssx == 1
        a = yp[ly * ys + lx] ## i64
        b = yp[ly * ys + lnx] ## i64
        avg = (a + b + 1) >> 1
      else
        avg = yp[ly * ys + lx]
      orig = cp[y * cs + x] ## i64
      merged = 0 ## i64
      if cfl == 1
        merged = avg
      else
        comb = (avg * (lmult - 128) + orig * (mult - 128)) ## i64
        merged = (comb >> 6) + offv
        merged = 0 if merged < 0
        merged = mx if merged > mx
      n = noise[y * pw + x] ## i64
      n = (av1_fg_scale(lut, merged, bd) * n + rnd) >> ssh
      v = (orig + n) ## i64
      v = minv if v < minv
      v = maxc if v > maxc
      cp[y * cs + x] = v
      x += 1
    y += 1
  0

-> av1_fg_blend_luma(yp, ys, noise, w, h, lut, bd, ssh, minv, maxl) (u16[] i64 i32[] i64 i64 i32[] i64 i64 i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << ssh) >> 1
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      orig = yp[y * ys + x] ## i64
      n = noise[y * w + x] ## i64
      n = (av1_fg_scale(lut, orig, bd) * n + rnd) >> ssh
      v = (orig + n) ## i64
      v = minv if v < minv
      v = maxl if v > maxl
      yp[y * ys + x] = v
      x += 1
    y += 1
  0
