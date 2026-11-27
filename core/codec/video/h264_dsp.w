# core/codec/video/h264_dsp — H.264 pixel kernels: inverse transforms, intra prediction,
# motion-compensated interpolation, weighted prediction and the deblocking
# edge filters. All work on raw u8[] planes with explicit offsets/strides.

use h264_intra

-> h264_clip(v) (i64) i64
  if v < 0
    0
  elsif v > 255
    255
  else
    v

-> h264_clip3(lo, hi, v) (i64 i64 i64) i64
  if v < lo
    lo
  elsif v > hi
    hi
  else
    v

# ---------------------------------------------------------------- transforms

# 4x4 inverse transform of coef[c...c+16] (raster), added to dst; zeroes coef.
-> h264_idct4_add(dst, d, stride, coef, c) (u8[] i64 i64 i32[] i64) i64
  h264_idct4_scratch(dst, d, stride, coef, c, i64[16])

-> h264_idct4_scratch(dst, d, stride, coef, c, t) (u8[] i64 i64 i32[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    b = c + i * 4
    d0 = coef[b]
    d1 = coef[b + 1]
    d2 = coef[b + 2]
    d3 = coef[b + 3]
    e = d0 + d2
    f = d0 - d2
    g = (d1 >> 1) - d3
    h = d1 + (d3 >> 1)
    t[i * 4] = e + h
    t[i * 4 + 1] = f + g
    t[i * 4 + 2] = f - g
    t[i * 4 + 3] = e - h
    coef[b] = 0
    coef[b + 1] = 0
    coef[b + 2] = 0
    coef[b + 3] = 0
    i += 1
  j = 0 ## i64
  while j < 4
    d0 = t[j]
    d1 = t[4 + j]
    d2 = t[8 + j]
    d3 = t[12 + j]
    e = d0 + d2
    f = d0 - d2
    g = (d1 >> 1) - d3
    h = d1 + (d3 >> 1)
    p = d + j
    cv = dst[p] + ((e + h + 32) >> 6)
    dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    p += stride
    cv = dst[p] + ((f + g + 32) >> 6)
    dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    p += stride
    cv = dst[p] + ((f - g + 32) >> 6)
    dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    p += stride
    cv = dst[p] + ((e - h + 32) >> 6)
    dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    j += 1
  0

# DC-only 4x4 block.
-> h264_idct4_dc_add(dst, d, stride, coef, c) (u8[] i64 i64 i32[] i64) i64
  dc = (coef[c] + 32) >> 6
  coef[c] = 0
  y = 0 ## i64
  while y < 4
    p = d + y * stride
    cv = dst[p] + dc
    dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    cv = dst[p + 1] + dc
    dst[p + 1] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    cv = dst[p + 2] + dc
    dst[p + 2] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    cv = dst[p + 3] + dc
    dst[p + 3] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
    y += 1
  0

-> h264_idct8_add(dst, d, stride, coef, c) (u8[] i64 i64 i32[] i64) i64
  h264_idct8_scratch(dst, d, stride, coef, c, i64[64])

-> h264_idct8_scratch(dst, d, stride, coef, c, t) (u8[] i64 i64 i32[] i64 i64[]) i64
  pass = 0 ## i64
  while pass < 2
    i = 0 ## i64
    while i < 8
      d0 = 0 ## i64
      d1 = 0 ## i64
      d2 = 0 ## i64
      d3 = 0 ## i64
      d4 = 0 ## i64
      d5 = 0 ## i64
      d6 = 0 ## i64
      d7 = 0 ## i64
      if pass == 0
        b = c + i * 8
        d0 = coef[b]
        d1 = coef[b + 1]
        d2 = coef[b + 2]
        d3 = coef[b + 3]
        d4 = coef[b + 4]
        d5 = coef[b + 5]
        d6 = coef[b + 6]
        d7 = coef[b + 7]
        k = 0 ## i64
        while k < 8
          coef[b + k] = 0
          k += 1
      else
        d0 = t[i]
        d1 = t[8 + i]
        d2 = t[16 + i]
        d3 = t[24 + i]
        d4 = t[32 + i]
        d5 = t[40 + i]
        d6 = t[48 + i]
        d7 = t[56 + i]
      a0 = d0 + d4
      a4 = d0 - d4
      a2 = (d2 >> 1) - d6
      a6 = d2 + (d6 >> 1)
      b0 = a0 + a6
      b2 = a4 + a2
      b4 = a4 - a2
      b6 = a0 - a6
      a1 = d5 - d3 - d7 - (d7 >> 1)
      a3 = d1 + d7 - d3 - (d3 >> 1)
      a5 = d7 - d1 + d5 + (d5 >> 1)
      a7 = d3 + d5 + d1 + (d1 >> 1)
      b1 = a1 + (a7 >> 2)
      b7 = a7 - (a1 >> 2)
      b3 = a3 + (a5 >> 2)
      b5 = (a3 >> 2) - a5
      if pass == 0
        o = i * 8
        t[o] = b0 + b7
        t[o + 1] = b2 + b5
        t[o + 2] = b4 + b3
        t[o + 3] = b6 + b1
        t[o + 4] = b6 - b1
        t[o + 5] = b4 - b3
        t[o + 6] = b2 - b5
        t[o + 7] = b0 - b7
      else
        p = d + i
        cv = dst[p] + ((b0 + b7 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b2 + b5 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b4 + b3 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b6 + b1 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b6 - b1 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b4 - b3 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b2 - b5 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        p += stride
        cv = dst[p] + ((b0 - b7 + 32) >> 6)
        dst[p] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
      i += 1
    pass += 1
  0

# Intra16x16 luma DC: dc[16] raw levels in raster 4x4-block order (row-major
# over the MB); Hadamard, scale with qmul = LevelScale(qP%6,0,0) << (qP/6) and
# store into coef[blk*16] (blk = z-order index).
-> h264_luma_dc(dc, coef, qmul, zidx) (i64[] i32[] i64 i64[]) i64
  t = i64[16]
  i = 0 ## i64
  while i < 4
    a = dc[i * 4]
    b = dc[i * 4 + 1]
    c = dc[i * 4 + 2]
    d = dc[i * 4 + 3]
    t[i * 4] = a + b + c + d
    t[i * 4 + 1] = a + b - c - d
    t[i * 4 + 2] = a - b - c + d
    t[i * 4 + 3] = a - b + c - d
    i += 1
  j = 0 ## i64
  while j < 4
    a = t[j]
    b = t[4 + j]
    c = t[8 + j]
    d = t[12 + j]
    f0 = a + b + c + d
    f1 = a + b - c - d
    f2 = a - b - c + d
    f3 = a - b + c - d
    coef[zidx[j] * 16] = (f0 * qmul + 32) >> 6
    coef[zidx[4 + j] * 16] = (f1 * qmul + 32) >> 6
    coef[zidx[8 + j] * 16] = (f2 * qmul + 32) >> 6
    coef[zidx[12 + j] * 16] = (f3 * qmul + 32) >> 6
    j += 1
  0

# Chroma DC 4:2:0: 2x2 Hadamard of coef[base + k*16], k = 0..3.
-> h264_chroma_dc(coef, base, qmul) (i32[] i64 i64) i64
  c0 = coef[base]
  c1 = coef[base + 16]
  c2 = coef[base + 32]
  c3 = coef[base + 48]
  f0 = c0 + c1 + c2 + c3
  f1 = c0 - c1 + c2 - c3
  f2 = c0 + c1 - c2 - c3
  f3 = c0 - c1 - c2 + c3
  coef[base] = (f0 * qmul) >> 5
  coef[base + 16] = (f1 * qmul) >> 5
  coef[base + 32] = (f2 * qmul) >> 5
  coef[base + 48] = (f3 * qmul) >> 5
  0

# Chroma DC 4:2:2: 2 wide x 4 high; coef[base + k*16], k raster (x + 2y).
-> h264_chroma422_dc(coef, base, qp_dc, ls) (i32[] i64 i64 i64) i64
  c = i64[8]
  k = 0 ## i64
  while k < 8
    c[k] = coef[base + k * 16]
    k += 1
  # f = A4 * c * A2, A4 = [[1,1,1,1],[1,1,-1,-1],[1,-1,-1,1],[1,-1,1,-1]]
  t = i64[8]
  y = 0 ## i64
  while y < 4
    a = c[y * 2]
    b = c[y * 2 + 1]
    t[y * 2] = a + b
    t[y * 2 + 1] = a - b
    y += 1
  x = 0 ## i64
  while x < 2
    a = t[x]
    b = t[2 + x]
    cc = t[4 + x]
    d = t[6 + x]
    f0 = a + b + cc + d
    f1 = a + b - cc - d
    f2 = a - b - cc + d
    f3 = a - b + cc - d
    qd = qp_dc / 6
    if qd >= 6
      coef[base + x * 16] = (f0 * ls) << (qd - 6)
      coef[base + (2 + x) * 16] = (f1 * ls) << (qd - 6)
      coef[base + (4 + x) * 16] = (f2 * ls) << (qd - 6)
      coef[base + (6 + x) * 16] = (f3 * ls) << (qd - 6)
    else
      rr = 1 << (5 - qd)
      coef[base + x * 16] = (f0 * ls + rr) >> (6 - qd)
      coef[base + (2 + x) * 16] = (f1 * ls + rr) >> (6 - qd)
      coef[base + (4 + x) * 16] = (f2 * ls + rr) >> (6 - qd)
      coef[base + (6 + x) * 16] = (f3 * ls + rr) >> (6 - qd)
    x += 1
  0

# ---------------------------------------------------------- intra prediction

# 8x8 reference sample filtering (8.3.2.2.1). top has 16 entries, left 8.
# avail: bit0 left, bit1 top, bit2 topleft, bit3 topright. Writes ft/fl and
# returns the filtered top-left sample.
-> h264_filter8(top, left, tl, avail, ft, fl) (i64[] i64[] i64 i64 i64[] i64[]) i64
  hl = avail & 1
  ht = (avail >> 1) & 1
  htl = (avail >> 2) & 1
  if ht == 1
    if htl == 1
      ft[0] = (tl + 2 * top[0] + top[1] + 2) >> 2
    else
      ft[0] = (3 * top[0] + top[1] + 2) >> 2
    x = 1 ## i64
    while x < 15
      ft[x] = (top[x - 1] + 2 * top[x] + top[x + 1] + 2) >> 2
      x += 1
    ft[15] = (top[14] + 3 * top[15] + 2) >> 2
  if hl == 1
    if htl == 1
      fl[0] = (tl + 2 * left[0] + left[1] + 2) >> 2
    else
      fl[0] = (3 * left[0] + left[1] + 2) >> 2
    y = 1 ## i64
    while y < 7
      fl[y] = (left[y - 1] + 2 * left[y] + left[y + 1] + 2) >> 2
      y += 1
    fl[7] = (left[6] + 3 * left[7] + 2) >> 2
  ftl = tl
  if htl == 1
    if ht == 1 && hl == 1
      ftl = (top[0] + 2 * tl + left[0] + 2) >> 2
    elsif ht == 1
      ftl = (3 * tl + top[0] + 2) >> 2
    elsif hl == 1
      ftl = (3 * tl + left[0] + 2) >> 2
  ftl

-> h264_pred16(dst, d, stride, mode, avail) (u8[] i64 i64 i64 i64) i64
  y = 0 ## i64
  if mode == 0
    while y < 16
      x = 0 ## i64
      while x < 16
        dst[d + y * stride + x] = dst[d - stride + x]
        x += 1
      y += 1
  elsif mode == 1
    while y < 16
      v = dst[d + y * stride - 1]
      x = 0 ## i64
      while x < 16
        dst[d + y * stride + x] = v
        x += 1
      y += 1
  elsif mode == 2
    s = 0 ## i64
    k = 0 ## i64
    if (avail & 3) == 3
      while k < 16
        s += dst[d - stride + k] + dst[d + k * stride - 1]
        k += 1
      s = (s + 16) >> 5
    elsif (avail & 1) == 1
      while k < 16
        s += dst[d + k * stride - 1]
        k += 1
      s = (s + 8) >> 4
    elsif (avail & 2) == 2
      while k < 16
        s += dst[d - stride + k]
        k += 1
      s = (s + 8) >> 4
    else
      s = 128
    while y < 16
      x = 0 ## i64
      while x < 16
        dst[d + y * stride + x] = s
        x += 1
      y += 1
  else
    hh = 0 ## i64
    vv = 0 ## i64
    k = 0 ## i64
    t = d - stride
    while k < 8
      hh += (k + 1) * (dst[t + 8 + k] - dst[t + 6 - k])
      vv += (k + 1) * (dst[d + (8 + k) * stride - 1] - dst[d + (6 - k) * stride - 1])
      k += 1
    a = 16 * (dst[d + 15 * stride - 1] + dst[t + 15])
    b = (5 * hh + 32) >> 6
    c = (5 * vv + 32) >> 6
    while y < 16
      x = 0 ## i64
      while x < 16
        cv = (a + b * (x - 7) + c * (y - 7) + 16) >> 5
        dst[d + y * stride + x] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        x += 1
      y += 1
  0

# Chroma intra prediction, w x h block (8x8 for 4:2:0, 8x16 for 4:2:2).
-> h264_pred_chroma(dst, d, stride, mode, avail, w, h) (u8[] i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  if mode == 0
    by = 0 ## i64
    while by < h
      bx = 0 ## i64
      while bx < w
        st = 0 ## i64
        sl = 0 ## i64
        k = 0 ## i64
        while k < 4
          st += dst[d - stride + bx + k] if (avail & 2) == 2
          sl += dst[d + (by + k) * stride - 1] if (avail & 1) == 1
          k += 1
        hl = avail & 1
        ht = (avail >> 1) & 1
        v = 128 ## i64
        if (bx == 0 && by == 0) || (bx > 0 && by > 0)
          if hl == 1 && ht == 1
            v = (st + sl + 4) >> 3
          elsif hl == 1
            v = (sl + 2) >> 2
          elsif ht == 1
            v = (st + 2) >> 2
        elsif bx > 0
          if ht == 1
            v = (st + 2) >> 2
          elsif hl == 1
            v = (sl + 2) >> 2
        else
          if hl == 1
            v = (sl + 2) >> 2
          elsif ht == 1
            v = (st + 2) >> 2
        yy = 0 ## i64
        while yy < 4
          xx = 0 ## i64
          while xx < 4
            dst[d + (by + yy) * stride + bx + xx] = v
            xx += 1
          yy += 1
        bx += 4
      by += 4
  elsif mode == 1
    while y < h
      v = dst[d + y * stride - 1]
      x = 0 ## i64
      while x < w
        dst[d + y * stride + x] = v
        x += 1
      y += 1
  elsif mode == 2
    while y < h
      x = 0 ## i64
      while x < w
        dst[d + y * stride + x] = dst[d - stride + x]
        x += 1
      y += 1
  else
    xcf = w == 16 ? 4 : 0
    ycf = h == 16 ? 4 : 0
    hh = 0 ## i64
    vv = 0 ## i64
    t = d - stride
    k = 0 ## i64
    while k <= 3 + xcf
      hh += (k + 1) * (dst[t + 4 + xcf + k] - dst[t + 2 + xcf - k])
      k += 1
    k = 0
    while k <= 3 + ycf
      vv += (k + 1) * (dst[d + (4 + ycf + k) * stride - 1] - dst[d + (2 + ycf - k) * stride - 1])
      k += 1
    a = 16 * (dst[d + (h - 1) * stride - 1] + dst[t + w - 1])
    b = ((34 - 29 * (w == 16 ? 1 : 0)) * hh + 32) >> 6
    c = ((34 - 29 * (h == 16 ? 1 : 0)) * vv + 32) >> 6
    while y < h
      x = 0 ## i64
      while x < w
        dst[d + y * stride + x] = h264_clip((a + b * (x - 3 - xcf) + c * (y - 3 - ycf) + 16) >> 5)
        x += 1
      y += 1
  0

# ------------------------------------------------------ motion compensation

# Copy a (w+5)x(h+5) window around (ix-2, iy-2) with edge clamping into emu
# (stride 32); returns nothing — callers then read emu at offset 2*32+2.
-> h264_emu_edge(src, sstride, sw, sh, ix, iy, w, h, emu) (u8[] i64 i64 i64 i64 i64 i64 i64 u8[]) i64
  y = 0 ## i64
  while y < h + 5
    sy = h264_clip3(0, sh - 1, iy - 2 + y)
    x = 0 ## i64
    while x < w + 5
      sx = h264_clip3(0, sw - 1, ix - 2 + x)
      emu[y * 32 + x] = src[sy * sstride + sx]
      x += 1
    y += 1
  0

# 6-tap half-sample at src[s] horizontally (between s and s+1), unrounded.
-> h264_tap6(src, s, step) (u8[] i64 i64) i64
  src[s - 2 * step] - 5 * src[s - step] + 20 * src[s] + 20 * src[s + step] - 5 * src[s + 2 * step] + src[s + 3 * step]

# Luma sample interpolation for a w x h block whose top-left full-sample
# position is s in src (stride ss), fraction (fx, fy) in quarter samples.
# Writes dst[d + y*ds + x].
-> h264_luma_mc(dst, d, ds, src, s, ss, w, h, fx, fy, tmp) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64 i64 i32[]) i64
  y = 0 ## i64
  if fx == 0 && fy == 0
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      while x < w
        dst[b + x] = src[a + x]
        x += 1
      y += 1
    return 0
  if fy == 0
    # a, b, c
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      while x < w
        cv = ((src[a + x - 2] - 5 * src[a + x - 1] + 20 * src[a + x] + 20 * src[a + x + 1] - 5 * src[a + x + 2] + src[a + x + 3]) + 16) >> 5
        v = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        if fx == 1
          v = (v + src[a + x] + 1) >> 1
        elsif fx == 3
          v = (v + src[a + x + 1] + 1) >> 1
        dst[b + x] = v
        x += 1
      y += 1
    return 0
  if fx == 0
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      while x < w
        cv = ((src[a + x - 2 * ss] - 5 * src[a + x - ss] + 20 * src[a + x] + 20 * src[a + x + ss] - 5 * src[a + x + 2 * ss] + src[a + x + 3 * ss]) + 16) >> 5
        v = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        if fy == 1
          v = (v + src[a + x] + 1) >> 1
        elsif fy == 3
          v = (v + src[a + x + ss] + 1) >> 1
        dst[b + x] = v
        x += 1
      y += 1
    return 0
  if fx == 2 || fy == 2
    # j needed: horizontal intermediates for rows -2..h+2 (unclipped)
    r = 0 ## i64
    while r < h + 5
      x = 0 ## i64
      a = s + (r - 2) * ss
      while x < w
        tmp[r * 24 + x] = (src[a + x - 2] - 5 * src[a + x - 1] + 20 * src[a + x] + 20 * src[a + x + 1] - 5 * src[a + x + 2] + src[a + x + 3])
        x += 1
      r += 1
    while y < h
      x = 0 ## i64
      b = d + y * ds
      while x < w
        t = y * 24 + x
        jv = tmp[t] - 5 * tmp[t + 24] + 20 * tmp[t + 48] + 20 * tmp[t + 72] - 5 * tmp[t + 96] + tmp[t + 120]
        cv = (jv + 512) >> 10
        j = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
        v = j
        if fx == 2
          if fy == 1
            v = (j + h264_clip((tmp[t + 48] + 16) >> 5) + 1) >> 1
          elsif fy == 3
            v = (j + h264_clip((tmp[t + 72] + 16) >> 5) + 1) >> 1
        else
          # fy == 2, fx = 1 or 3: average with vertical half sample h or m
          c = s + y * ss + x + (fx == 3 ? 1 : 0)
          cv = ((src[c - 2 * ss] - 5 * src[c - ss] + 20 * src[c] + 20 * src[c + ss] - 5 * src[c + 2 * ss] + src[c + 3 * ss]) + 16) >> 5
          hv = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
          v = (j + hv + 1) >> 1
        dst[b + x] = v
        x += 1
      y += 1
    return 0
  # diagonal quarter positions e, g, p, r: average of a horizontal and a
  # vertical half sample
  while y < h
    x = 0 ## i64
    b = d + y * ds
    while x < w
      hy = s + (y + (fy == 3 ? 1 : 0)) * ss + x
      cv = ((src[hy - 2] - 5 * src[hy - 1] + 20 * src[hy] + 20 * src[hy + 1] - 5 * src[hy + 2] + src[hy + 3]) + 16) >> 5
      hb = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
      vx = s + y * ss + x + (fx == 3 ? 1 : 0)
      cv = ((src[vx - 2 * ss] - 5 * src[vx - ss] + 20 * src[vx] + 20 * src[vx + ss] - 5 * src[vx + 2 * ss] + src[vx + 3 * ss]) + 16) >> 5
      vb = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
      dst[b + x] = (hb + vb + 1) >> 1
      x += 1
    y += 1
  0

# Chroma eighth-sample bilinear interpolation, w x h, with edge clamping
# when the block reaches outside (ix, iy are full-sample coords).
-> h264_chroma_mc(dst, d, ds, src, ss, sw, sh, ix, iy, fx, fy, w, h) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  wa = (8 - fx) * (8 - fy)
  wb = fx * (8 - fy)
  wc = (8 - fx) * fy
  wd = fx * fy
  y = 0 ## i64
  if ix >= 0 && iy >= 0 && ix + w < sw && iy + h < sh
    while y < h
      x = 0 ## i64
      a = (iy + y) * ss + ix
      b = d + y * ds
      while x < w
        dst[b + x] = (wa * src[a + x] + wb * src[a + x + 1] + wc * src[a + x + ss] + wd * src[a + x + ss + 1] + 32) >> 6
        x += 1
      y += 1
  else
    while y < h
      y0 = h264_clip3(0, sh - 1, iy + y)
      y1 = h264_clip3(0, sh - 1, iy + y + 1)
      x = 0 ## i64
      b = d + y * ds
      while x < w
        x0 = h264_clip3(0, sw - 1, ix + x)
        x1 = h264_clip3(0, sw - 1, ix + x + 1)
        dst[b + x] = (wa * src[y0 * ss + x0] + wb * src[y0 * ss + x1] + wc * src[y1 * ss + x0] + wd * src[y1 * ss + x1] + 32) >> 6
        x += 1
      y += 1
  0

# dst = (a + b + 1) >> 1 over w x h (a, b stride 16 temporaries).
-> h264_avg(dst, d, ds, a, b, w, h) (u8[] i64 i64 u8[] u8[] i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      dst[d + y * ds + x] = (a[y * 16 + x] + b[y * 16 + x] + 1) >> 1
      x += 1
    y += 1
  0

# Explicit/implicit weighting of one prediction.
-> h264_weight(dst, d, ds, a, w, h, logwd, wt, off) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  rnd = logwd >= 1 ? (1 << (logwd - 1)) : 0
  while y < h
    x = 0 ## i64
    while x < w
      v = a[y * 16 + x] * wt
      if logwd >= 1
        v = ((v + rnd) >> logwd) + off
      else
        v = v + off
      cv = v
      dst[d + y * ds + x] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
      x += 1
    y += 1
  0

-> h264_biweight(dst, d, ds, a, b, w, h, logwd, w0, w1, off) (u8[] i64 i64 u8[] u8[] i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  rnd = 1 << logwd
  while y < h
    x = 0 ## i64
    while x < w
      v = ((a[y * 16 + x] * w0 + b[y * 16 + x] * w1 + rnd) >> (logwd + 1)) + off
      cv = v
      dst[d + y * ds + x] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
      x += 1
    y += 1
  0

-> h264_copy_block(dst, d, ds, a, w, h) (u8[] i64 i64 u8[] i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      dst[d + y * ds + x] = a[y * 16 + x]
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- deblocking

# Filter one edge of `len` lines. Pixels across the edge are at
# p + k*step (k = -4..3, q0 at k = 0); successive lines are `adv` apart.
# bs4 holds four bS values, one per `len/4` lines. luma: 1 for luma rules.
-> h264_filter_edge(pix, p0, step, adv, len, bs, alpha, beta, tcrow, luma) (u8[] i64 i64 i64 i64 i64[] i64 i64 i64[] i64) i64
  return 0 if alpha == 0 || beta == 0
  per = len >> 2
  i = 0 ## i64
  while i < len
    b = bs[i / per]
    if b > 0
      o = p0 + i * adv
      pp0 = pix[o - step]
      qq0 = pix[o]
      pp1 = pix[o - 2 * step]
      qq1 = pix[o + step]
      dpq = pp0 - qq0
      dpq = 0 - dpq if dpq < 0
      d1 = pp1 - pp0
      d1 = 0 - d1 if d1 < 0
      d2 = qq1 - qq0
      d2 = 0 - d2 if d2 < 0
      if dpq < alpha && d1 < beta && d2 < beta
        if luma == 1
          pp2 = pix[o - 3 * step]
          qq2 = pix[o + 2 * step]
          ap = pp2 - pp0
          ap = 0 - ap if ap < 0
          aq = qq2 - qq0
          aq = 0 - aq if aq < 0
          if b < 4
            tc0 = tcrow[b]
            tc = tc0
            tc += 1 if ap < beta
            tc += 1 if aq < beta
            delta = h264_clip3(0 - tc, tc, (((qq0 - pp0) << 2) + (pp1 - qq1) + 4) >> 3)
            cv = pp0 + delta
            pix[o - step] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
            cv = qq0 - delta
            pix[o] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
            if ap < beta
              pix[o - 2 * step] = pp1 + h264_clip3(0 - tc0, tc0, (pp2 + ((pp0 + qq0 + 1) >> 1) - (pp1 << 1)) >> 1)
            if aq < beta
              pix[o + step] = qq1 + h264_clip3(0 - tc0, tc0, (qq2 + ((pp0 + qq0 + 1) >> 1) - (qq1 << 1)) >> 1)
          else
            small = dpq < ((alpha >> 2) + 2)
            if ap < beta && small
              pp3 = pix[o - 4 * step]
              pix[o - step] = (pp2 + 2 * pp1 + 2 * pp0 + 2 * qq0 + qq1 + 4) >> 3
              pix[o - 2 * step] = (pp2 + pp1 + pp0 + qq0 + 2) >> 2
              pix[o - 3 * step] = (2 * pp3 + 3 * pp2 + pp1 + pp0 + qq0 + 4) >> 3
            else
              pix[o - step] = (2 * pp1 + pp0 + qq1 + 2) >> 2
            if aq < beta && small
              qq3 = pix[o + 3 * step]
              pix[o] = (pp1 + 2 * pp0 + 2 * qq0 + 2 * qq1 + qq2 + 4) >> 3
              pix[o + step] = (pp0 + qq0 + qq1 + qq2 + 2) >> 2
              pix[o + 2 * step] = (2 * qq3 + 3 * qq2 + qq1 + qq0 + pp0 + 4) >> 3
            else
              pix[o] = (2 * qq1 + qq0 + pp1 + 2) >> 2
        else
          if b < 4
            tc = tcrow[b] + 1
            delta = h264_clip3(0 - tc, tc, (((qq0 - pp0) << 2) + (pp1 - qq1) + 4) >> 3)
            cv = pp0 + delta
            pix[o - step] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
            cv = qq0 - delta
            pix[o] = cv < 0 ? 0 : (cv > 255 ? 255 : cv)
          else
            pix[o - step] = (2 * pp1 + pp0 + qq1 + 2) >> 2
            pix[o] = (2 * qq1 + qq0 + pp1 + 2) >> 2
    i += 1
  0
