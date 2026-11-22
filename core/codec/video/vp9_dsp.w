# core/codec/video/vp9_dsp — VP9 pixel kernels: inverse transforms (2-D wrappers over
# vp9_tx), intra predictors, 8-tap / bilinear motion compensation and the
# loop filter. 8-bit. Coefficients and transform intermediates are i16[]
# (the 8-bit decoding path's 16-bit storage).
#
# Intra edge convention (as prepared by the decoder): `top` holds the
# top-left sample at index 0 and above samples a[k] at 1+k; `lf` holds the
# left column bottom-to-top (lf[n-1] is the sample next to the top-left)
# except for HOR_UP, which takes it top-to-bottom.

use vp9_tx

-> vp9_clip(v) (i64) i64
  if v < 0
    0
  elsif v > 255
    255
  else
    v

# One 1-D inverse transform: kind 0 idct, 1 iadst, 2 iwht (pass p).
-> vp9_1d(kind, n, inp, io, st, out, oo, pass) (i64 i64 i16[] i64 i64 i16[] i64 i64) i64
  if kind == 0
    if n == 4
      vp9_idct4_1d(inp, io, st, out, oo)
    elsif n == 8
      vp9_idct8_1d(inp, io, st, out, oo)
    elsif n == 16
      vp9_idct16_1d(inp, io, st, out, oo)
    else
      vp9_idct32_1d(inp, io, st, out, oo)
  elsif kind == 1
    if n == 4
      vp9_iadst4_1d(inp, io, st, out, oo)
    elsif n == 8
      vp9_iadst8_1d(inp, io, st, out, oo)
    else
      vp9_iadst16_1d(inp, io, st, out, oo)
  else
    t0 = inp[io]
    t1 = inp[io + 3 * st]
    t2 = inp[io + st]
    t3 = inp[io + 2 * st]
    if pass == 0
      t0 = t0 >> 2
      t1 = t1 >> 2
      t2 = t2 >> 2
      t3 = t3 >> 2
    t0 += t2
    t3 -= t1
    t4 = (t0 - t3) >> 1
    t1 = t4 - t1
    t2 = t4 - t2
    t0 -= t1
    t3 += t2
    out[oo] = t0
    out[oo + 1] = t1
    out[oo + 2] = t2
    out[oo + 3] = t3
  0

# Inverse transform of block[bo...] (n x n, raster) added to dst.
# ka/kb: kind of the first (column) / second (row) pass; bits: final shift.
-> vp9_itxfm_add(dst, d, stride, block, bo, n, ka, kb, bits, eob, tmp, out) (u8[] i64 i64 i16[] i64 i64 i64 i64 i64 i64 i16[] i16[]) i64
  if ka == 0 && kb == 0 && eob == 1
    t = (((block[bo] * 11585 + 8192) >> 14) * 11585 + 8192) >> 14
    block[bo] = 0
    t = (t + (1 << (bits - 1))) >> bits
    y = 0 ## i64
    while y < n
      x = 0 ## i64
      p = d + y * stride
      while x < n
        dst[p + x] = vp9_clip(dst[p + x] + t)
        x += 1
      y += 1
    return 0
  i = 0 ## i64
  while i < n
    vp9_1d(ka, n, block, bo + i, n, tmp, i * n, 0)
    i += 1
  k = 0 ## i64
  while k < n * n
    block[bo + k] = 0
    k += 1
  i = 0
  while i < n
    vp9_1d(kb, n, tmp, i, n, out, 0, 1)
    j = 0 ## i64
    if bits > 0
      r = 1 << (bits - 1)
      while j < n
        p = d + j * stride + i
        dst[p] = vp9_clip(dst[p] + ((out[j] + r) >> bits))
        j += 1
    else
      while j < n
        p = d + j * stride + i
        dst[p] = vp9_clip(dst[p] + out[j])
        j += 1
    i += 1
  0

# ------------------------------------------------------------------ intra

-> vp9_fill(dst, d, stride, n, v) (u8[] i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < n
    x = 0 ## i64
    p = d + y * stride
    while x < n
      dst[p + x] = v
      x += 1
    y += 1
  0

# mode: 0 V, 1 H, 2 DC, 3 D45(DDL), 4 D135(DDR), 5 D117(VR), 6 D153(HD),
# 7 D63(VL), 8 D207(HU), 9 TM, 10 LEFT_DC, 11 TOP_DC, 12 DC128, 13 127, 14 129
-> vp9_ipred(dst, d, s, n, mode, lf, top, v) (u8[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  y = 0 ## i64
  x = 0 ## i64
  tl = top[0]
  if mode == 0
    while y < n
      x = 0
      while x < n
        dst[d + y * s + x] = top[1 + x]
        x += 1
      y += 1
  elsif mode == 1
    while y < n
      vp9_fill_row(dst, d + y * s, n, lf[n - 1 - y])
      y += 1
  elsif mode == 9
    while y < n
      lm = lf[n - 1 - y] - tl
      x = 0
      while x < n
        dst[d + y * s + x] = vp9_clip(top[1 + x] + lm)
        x += 1
      y += 1
  elsif mode == 2 || mode == 10 || mode == 11
    sum = 0 ## i64
    k = 0 ## i64
    sh = 2 ## i64
    sh = 3 if n == 8
    sh = 4 if n == 16
    sh = 5 if n == 32
    if mode == 2
      while k < n
        sum += lf[k] + top[1 + k]
        k += 1
      sum = (sum + n) >> (sh + 1)
    elsif mode == 10
      while k < n
        sum += lf[k]
        k += 1
      sum = (sum + (n >> 1)) >> sh
    else
      while k < n
        sum += top[1 + k]
        k += 1
      sum = (sum + (n >> 1)) >> sh
    vp9_fill(dst, d, s, n, sum)
  elsif mode == 12
    vp9_fill(dst, d, s, n, 128)
  elsif mode == 13
    vp9_fill(dst, d, s, n, 127)
  elsif mode == 14
    vp9_fill(dst, d, s, n, 129)
  elsif mode == 3
    if n == 4
      a0 = top[1]
      a1 = top[2]
      a2 = top[3]
      a3 = top[4]
      a4 = top[5]
      a5 = top[6]
      a6 = top[7]
      a7 = top[8]
      vp9_put4(dst, d, s, 0, 0, (a0 + a1 * 2 + a2 + 2) >> 2)
      v1 = (a1 + a2 * 2 + a3 + 2) >> 2
      vp9_put4(dst, d, s, 1, 0, v1)
      vp9_put4(dst, d, s, 0, 1, v1)
      v2 = (a2 + a3 * 2 + a4 + 2) >> 2
      vp9_put4(dst, d, s, 2, 0, v2)
      vp9_put4(dst, d, s, 1, 1, v2)
      vp9_put4(dst, d, s, 0, 2, v2)
      v3 = (a3 + a4 * 2 + a5 + 2) >> 2
      vp9_put4(dst, d, s, 3, 0, v3)
      vp9_put4(dst, d, s, 2, 1, v3)
      vp9_put4(dst, d, s, 1, 2, v3)
      vp9_put4(dst, d, s, 0, 3, v3)
      v4 = (a4 + a5 * 2 + a6 + 2) >> 2
      vp9_put4(dst, d, s, 3, 1, v4)
      vp9_put4(dst, d, s, 2, 2, v4)
      vp9_put4(dst, d, s, 1, 3, v4)
      v5 = (a5 + a6 * 2 + a7 + 2) >> 2
      vp9_put4(dst, d, s, 3, 2, v5)
      vp9_put4(dst, d, s, 2, 3, v5)
      vp9_put4(dst, d, s, 3, 3, a7)
    else
      i = 0 ## i64
      while i < n - 2
        v[i] = (top[1 + i] + top[2 + i] * 2 + top[3 + i] + 2) >> 2
        i += 1
      v[n - 2] = (top[n - 1] + top[n] * 3 + 2) >> 2
      while y < n
        x = 0
        while x < n
          if x < n - 1 - y
            dst[d + y * s + x] = v[y + x]
          else
            dst[d + y * s + x] = top[n]
          x += 1
        y += 1
  elsif mode == 4
    i = 0 ## i64
    while i < n - 2
      v[i] = (lf[i] + lf[i + 1] * 2 + lf[i + 2] + 2) >> 2
      v[n + 1 + i] = (top[1 + i] + top[2 + i] * 2 + top[3 + i] + 2) >> 2
      i += 1
    v[n - 2] = (lf[n - 2] + lf[n - 1] * 2 + tl + 2) >> 2
    v[n - 1] = (lf[n - 1] + tl * 2 + top[1] + 2) >> 2
    v[n] = (tl + top[1] * 2 + top[2] + 2) >> 2
    while y < n
      x = 0
      while x < n
        dst[d + y * s + x] = v[n - 1 - y + x]
        x += 1
      y += 1
  elsif mode == 5
    if n == 4
      a0 = top[1]
      a1 = top[2]
      a2 = top[3]
      a3 = top[4]
      l0 = lf[3]
      l1 = lf[2]
      l2 = lf[1]
      vp9_put4(dst, d, s, 0, 3, (l0 + l1 * 2 + l2 + 2) >> 2)
      vp9_put4(dst, d, s, 0, 2, (tl + l0 * 2 + l1 + 2) >> 2)
      q = (tl + a0 + 1) >> 1
      vp9_put4(dst, d, s, 0, 0, q)
      vp9_put4(dst, d, s, 1, 2, q)
      q = (l0 + tl * 2 + a0 + 2) >> 2
      vp9_put4(dst, d, s, 0, 1, q)
      vp9_put4(dst, d, s, 1, 3, q)
      q = (a0 + a1 + 1) >> 1
      vp9_put4(dst, d, s, 1, 0, q)
      vp9_put4(dst, d, s, 2, 2, q)
      q = (tl + a0 * 2 + a1 + 2) >> 2
      vp9_put4(dst, d, s, 1, 1, q)
      vp9_put4(dst, d, s, 2, 3, q)
      q = (a1 + a2 + 1) >> 1
      vp9_put4(dst, d, s, 2, 0, q)
      vp9_put4(dst, d, s, 3, 2, q)
      q = (a0 + a1 * 2 + a2 + 2) >> 2
      vp9_put4(dst, d, s, 2, 1, q)
      vp9_put4(dst, d, s, 3, 3, q)
      vp9_put4(dst, d, s, 3, 0, (a2 + a3 + 1) >> 1)
      vp9_put4(dst, d, s, 3, 1, (a1 + a2 * 2 + a3 + 2) >> 2)
    else
      # ve at v[0...], vo at v[64...]
      h2 = n >> 1
      i = 0 ## i64
      while i < h2 - 2
        v[64 + i] = (lf[i * 2 + 3] + lf[i * 2 + 2] * 2 + lf[i * 2 + 1] + 2) >> 2
        v[i] = (lf[i * 2 + 4] + lf[i * 2 + 3] * 2 + lf[i * 2 + 2] + 2) >> 2
        i += 1
      v[64 + h2 - 2] = (lf[n - 1] + lf[n - 2] * 2 + lf[n - 3] + 2) >> 2
      v[h2 - 2] = (tl + lf[n - 1] * 2 + lf[n - 2] + 2) >> 2
      v[h2 - 1] = (tl + top[1] + 1) >> 1
      v[64 + h2 - 1] = (lf[n - 1] + tl * 2 + top[1] + 2) >> 2
      i = 0
      while i < n - 1
        v[h2 + i] = (top[1 + i] + top[2 + i] + 1) >> 1
        v[64 + h2 + i] = (top[i] + top[1 + i] * 2 + top[2 + i] + 2) >> 2
        i += 1
      j = 0 ## i64
      while j < h2
        x = 0
        while x < n
          dst[d + (j * 2) * s + x] = v[h2 - 1 - j + x]
          dst[d + (j * 2 + 1) * s + x] = v[64 + h2 - 1 - j + x]
          x += 1
        j += 1
  elsif mode == 6
    if n == 4
      l0 = lf[3]
      l1 = lf[2]
      l2 = lf[1]
      l3 = lf[0]
      a0 = top[1]
      a1 = top[2]
      a2 = top[3]
      vp9_put4(dst, d, s, 2, 0, (tl + a0 * 2 + a1 + 2) >> 2)
      vp9_put4(dst, d, s, 3, 0, (a0 + a1 * 2 + a2 + 2) >> 2)
      q = (tl + l0 + 1) >> 1
      vp9_put4(dst, d, s, 0, 0, q)
      vp9_put4(dst, d, s, 2, 1, q)
      q = (a0 + tl * 2 + l0 + 2) >> 2
      vp9_put4(dst, d, s, 1, 0, q)
      vp9_put4(dst, d, s, 3, 1, q)
      q = (l0 + l1 + 1) >> 1
      vp9_put4(dst, d, s, 0, 1, q)
      vp9_put4(dst, d, s, 2, 2, q)
      q = (tl + l0 * 2 + l1 + 2) >> 2
      vp9_put4(dst, d, s, 1, 1, q)
      vp9_put4(dst, d, s, 3, 2, q)
      q = (l1 + l2 + 1) >> 1
      vp9_put4(dst, d, s, 0, 2, q)
      vp9_put4(dst, d, s, 2, 3, q)
      q = (l0 + l1 * 2 + l2 + 2) >> 2
      vp9_put4(dst, d, s, 1, 2, q)
      vp9_put4(dst, d, s, 3, 3, q)
      vp9_put4(dst, d, s, 0, 3, (l2 + l3 + 1) >> 1)
      vp9_put4(dst, d, s, 1, 3, (l1 + l2 * 2 + l3 + 2) >> 2)
    else
      i = 0 ## i64
      while i < n - 2
        v[i * 2] = (lf[i + 1] + lf[i] + 1) >> 1
        v[i * 2 + 1] = (lf[i + 2] + lf[i + 1] * 2 + lf[i] + 2) >> 2
        v[n * 2 + i] = (top[i] + top[1 + i] * 2 + top[2 + i] + 2) >> 2
        i += 1
      v[n * 2 - 2] = (tl + lf[n - 1] + 1) >> 1
      v[n * 2 - 4] = (lf[n - 1] + lf[n - 2] + 1) >> 1
      v[n * 2 - 1] = (top[1] + tl * 2 + lf[n - 1] + 2) >> 2
      v[n * 2 - 3] = (tl + lf[n - 1] * 2 + lf[n - 2] + 2) >> 2
      while y < n
        x = 0
        while x < n
          dst[d + y * s + x] = v[n * 2 - 2 - y * 2 + x]
          x += 1
        y += 1
  elsif mode == 7
    if n == 4
      a0 = top[1]
      a1 = top[2]
      a2 = top[3]
      a3 = top[4]
      a4 = top[5]
      a5 = top[6]
      a6 = top[7]
      vp9_put4(dst, d, s, 0, 0, (a0 + a1 + 1) >> 1)
      vp9_put4(dst, d, s, 0, 1, (a0 + a1 * 2 + a2 + 2) >> 2)
      q = (a1 + a2 + 1) >> 1
      vp9_put4(dst, d, s, 1, 0, q)
      vp9_put4(dst, d, s, 0, 2, q)
      q = (a1 + a2 * 2 + a3 + 2) >> 2
      vp9_put4(dst, d, s, 1, 1, q)
      vp9_put4(dst, d, s, 0, 3, q)
      q = (a2 + a3 + 1) >> 1
      vp9_put4(dst, d, s, 2, 0, q)
      vp9_put4(dst, d, s, 1, 2, q)
      q = (a2 + a3 * 2 + a4 + 2) >> 2
      vp9_put4(dst, d, s, 2, 1, q)
      vp9_put4(dst, d, s, 1, 3, q)
      q = (a3 + a4 + 1) >> 1
      vp9_put4(dst, d, s, 3, 0, q)
      vp9_put4(dst, d, s, 2, 2, q)
      q = (a3 + a4 * 2 + a5 + 2) >> 2
      vp9_put4(dst, d, s, 3, 1, q)
      vp9_put4(dst, d, s, 2, 3, q)
      vp9_put4(dst, d, s, 3, 2, (a4 + a5 + 1) >> 1)
      vp9_put4(dst, d, s, 3, 3, (a4 + a5 * 2 + a6 + 2) >> 2)
    else
      i = 0 ## i64
      while i < n - 2
        v[i] = (top[1 + i] + top[2 + i] + 1) >> 1
        v[64 + i] = (top[1 + i] + top[2 + i] * 2 + top[3 + i] + 2) >> 2
        i += 1
      v[n - 2] = (top[n - 1] + top[n] + 1) >> 1
      v[64 + n - 2] = (top[n - 1] + top[n] * 3 + 2) >> 2
      j = 0 ## i64
      while j < n / 2
        x = 0
        while x < n
          if x < n - j - 1
            dst[d + (j * 2) * s + x] = v[j + x]
            dst[d + (j * 2 + 1) * s + x] = v[64 + j + x]
          else
            dst[d + (j * 2) * s + x] = top[n]
            dst[d + (j * 2 + 1) * s + x] = top[n]
          x += 1
        j += 1
  elsif mode == 8
    if n == 4
      l0 = lf[0]
      l1 = lf[1]
      l2 = lf[2]
      l3 = lf[3]
      vp9_put4(dst, d, s, 0, 0, (l0 + l1 + 1) >> 1)
      vp9_put4(dst, d, s, 1, 0, (l0 + l1 * 2 + l2 + 2) >> 2)
      q = (l1 + l2 + 1) >> 1
      vp9_put4(dst, d, s, 0, 1, q)
      vp9_put4(dst, d, s, 2, 0, q)
      q = (l1 + l2 * 2 + l3 + 2) >> 2
      vp9_put4(dst, d, s, 1, 1, q)
      vp9_put4(dst, d, s, 3, 0, q)
      q = (l2 + l3 + 1) >> 1
      vp9_put4(dst, d, s, 0, 2, q)
      vp9_put4(dst, d, s, 2, 1, q)
      q = (l2 + l3 * 3 + 2) >> 2
      vp9_put4(dst, d, s, 1, 2, q)
      vp9_put4(dst, d, s, 3, 1, q)
      vp9_put4(dst, d, s, 0, 3, l3)
      vp9_put4(dst, d, s, 1, 3, l3)
      vp9_put4(dst, d, s, 2, 2, l3)
      vp9_put4(dst, d, s, 2, 3, l3)
      vp9_put4(dst, d, s, 3, 2, l3)
      vp9_put4(dst, d, s, 3, 3, l3)
    else
      i = 0 ## i64
      while i < n - 2
        v[i * 2] = (lf[i] + lf[i + 1] + 1) >> 1
        v[i * 2 + 1] = (lf[i] + lf[i + 1] * 2 + lf[i + 2] + 2) >> 2
        i += 1
      v[n * 2 - 4] = (lf[n - 2] + lf[n - 1] + 1) >> 1
      v[n * 2 - 3] = (lf[n - 2] + lf[n - 1] * 3 + 2) >> 2
      while y < n
        x = 0
        while x < n
          if y * 2 + x < n * 2 - 2
            dst[d + y * s + x] = v[y * 2 + x]
          else
            dst[d + y * s + x] = lf[n - 1]
          x += 1
        y += 1
  0

-> vp9_fill_row(dst, p, n, v) (u8[] i64 i64 i64) i64
  x = 0 ## i64
  while x < n
    dst[p + x] = v
    x += 1
  0

-> vp9_put4(dst, d, s, x, y, v) (u8[] i64 i64 i64 i64 i64) i64
  dst[d + y * s + x] = v
  0

# ------------------------------------------------------ motion compensation

# Predict a w x h block from src (top-left full sample at s, stride ss) with
# sub-sample position (mx, my) in 1/16, filter taps flt[fb...fb+128] (8 per
# phase) or bilinear when bil == 1. avg: average into dst.
-> vp9_mc(dst, d, ds, src, s, ss, w, h, mx, my, flt, fb, bil, avg, tmp) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64 u8[]) i64
  y = 0 ## i64
  if mx == 0 && my == 0
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      if avg == 1
        while x < w
          dst[b + x] = (dst[b + x] + src[a + x] + 1) >> 1
          x += 1
      else
        while x < w
          dst[b + x] = src[a + x]
          x += 1
      y += 1
    return 0
  if bil == 1
    if my == 0
      while y < h
        x = 0 ## i64
        a = s + y * ss
        b = d + y * ds
        while x < w
          v = src[a + x] + ((mx * (src[a + x + 1] - src[a + x]) + 8) >> 4)
          dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
          x += 1
        y += 1
    elsif mx == 0
      while y < h
        x = 0 ## i64
        a = s + y * ss
        b = d + y * ds
        while x < w
          v = src[a + x] + ((my * (src[a + x + ss] - src[a + x]) + 8) >> 4)
          dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
          x += 1
        y += 1
    else
      r = 0 ## i64
      while r < h + 1
        x = 0 ## i64
        a = s + r * ss
        while x < w
          tmp[r * 64 + x] = src[a + x] + ((mx * (src[a + x + 1] - src[a + x]) + 8) >> 4)
          x += 1
        r += 1
      while y < h
        x = 0 ## i64
        b = d + y * ds
        while x < w
          t = y * 64 + x
          v = tmp[t] + ((my * (tmp[t + 64] - tmp[t]) + 8) >> 4)
          dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
          x += 1
        y += 1
    return 0
  if my == 0
    f = fb + mx * 8
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      while x < w
        p = a + x
        v = vp9_clip((flt[f] * src[p - 3] + flt[f + 1] * src[p - 2] + flt[f + 2] * src[p - 1] + flt[f + 3] * src[p] + flt[f + 4] * src[p + 1] + flt[f + 5] * src[p + 2] + flt[f + 6] * src[p + 3] + flt[f + 7] * src[p + 4] + 64) >> 7)
        dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
        x += 1
      y += 1
    return 0
  if mx == 0
    f = fb + my * 8
    while y < h
      x = 0 ## i64
      a = s + y * ss
      b = d + y * ds
      while x < w
        p = a + x
        v = vp9_clip((flt[f] * src[p - 3 * ss] + flt[f + 1] * src[p - 2 * ss] + flt[f + 2] * src[p - ss] + flt[f + 3] * src[p] + flt[f + 4] * src[p + ss] + flt[f + 5] * src[p + 2 * ss] + flt[f + 6] * src[p + 3 * ss] + flt[f + 7] * src[p + 4 * ss] + 64) >> 7)
        dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
        x += 1
      y += 1
    return 0
  fx = fb + mx * 8
  fy = fb + my * 8
  r = 0 ## i64
  while r < h + 7
    x = 0 ## i64
    a = s + (r - 3) * ss
    while x < w
      p = a + x
      tmp[r * 64 + x] = vp9_clip((flt[fx] * src[p - 3] + flt[fx + 1] * src[p - 2] + flt[fx + 2] * src[p - 1] + flt[fx + 3] * src[p] + flt[fx + 4] * src[p + 1] + flt[fx + 5] * src[p + 2] + flt[fx + 6] * src[p + 3] + flt[fx + 7] * src[p + 4] + 64) >> 7)
      x += 1
    r += 1
  while y < h
    x = 0 ## i64
    b = d + y * ds
    while x < w
      p = (y + 3) * 64 + x
      v = vp9_clip((flt[fy] * tmp[p - 192] + flt[fy + 1] * tmp[p - 128] + flt[fy + 2] * tmp[p - 64] + flt[fy + 3] * tmp[p] + flt[fy + 4] * tmp[p + 64] + flt[fy + 5] * tmp[p + 128] + flt[fy + 6] * tmp[p + 192] + flt[fy + 7] * tmp[p + 256] + 64) >> 7)
      dst[b + x] = avg == 1 ? (dst[b + x] + v + 1) >> 1 : v
      x += 1
    y += 1
  0

# Copy a (w+7)x(h+8) window starting at (ix-3, iy-3) with edge clamping into
# emu (stride 80).
-> vp9_emu_edge(src, ss, sw, sh, ix, iy, w, h, emu) (u8[] i64 i64 i64 i64 i64 i64 i64 u8[]) i64
  y = 0 ## i64
  while y < h + 8
    sy = iy - 3 + y
    sy = 0 if sy < 0
    sy = sh - 1 if sy > sh - 1
    x = 0 ## i64
    while x < w + 8
      sx = ix - 3 + x
      sx = 0 if sx < 0
      sx = sw - 1 if sx > sw - 1
      emu[y * 80 + x] = src[sy * ss + sx]
      x += 1
    y += 1
  0

# ------------------------------------------------------------- loop filter

# Filter 8 lines across an edge: lines advance by sa, pixels across the edge
# by sb (q0 at p). wd 4, 8 or 16.
-> vp9_lf(dst, p, sa, sb, e, ii, hh, wd) (u8[] i64 i64 i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < 8
    o = p + i * sa
    p3 = dst[o - 4 * sb]
    p2 = dst[o - 3 * sb]
    p1 = dst[o - 2 * sb]
    p0 = dst[o - sb]
    q0 = dst[o]
    q1 = dst[o + sb]
    q2 = dst[o + 2 * sb]
    q3 = dst[o + 3 * sb]
    fm = vp9_abs(p3 - p2) <= ii && vp9_abs(p2 - p1) <= ii && vp9_abs(p1 - p0) <= ii && vp9_abs(q1 - q0) <= ii && vp9_abs(q2 - q1) <= ii && vp9_abs(q3 - q2) <= ii && vp9_abs(p0 - q0) * 2 + (vp9_abs(p1 - q1) >> 1) <= e
    if fm
      flat8out = false
      flat8in = false
      p7 = 0 ## i64
      p6 = 0 ## i64
      p5 = 0 ## i64
      p4 = 0 ## i64
      q4 = 0 ## i64
      q5 = 0 ## i64
      q6 = 0 ## i64
      q7 = 0 ## i64
      if wd >= 16
        p7 = dst[o - 8 * sb]
        p6 = dst[o - 7 * sb]
        p5 = dst[o - 6 * sb]
        p4 = dst[o - 5 * sb]
        q4 = dst[o + 4 * sb]
        q5 = dst[o + 5 * sb]
        q6 = dst[o + 6 * sb]
        q7 = dst[o + 7 * sb]
        flat8out = vp9_abs(p7 - p0) <= 1 && vp9_abs(p6 - p0) <= 1 && vp9_abs(p5 - p0) <= 1 && vp9_abs(p4 - p0) <= 1 && vp9_abs(q4 - q0) <= 1 && vp9_abs(q5 - q0) <= 1 && vp9_abs(q6 - q0) <= 1 && vp9_abs(q7 - q0) <= 1
      if wd >= 8
        flat8in = vp9_abs(p3 - p0) <= 1 && vp9_abs(p2 - p0) <= 1 && vp9_abs(p1 - p0) <= 1 && vp9_abs(q1 - q0) <= 1 && vp9_abs(q2 - q0) <= 1 && vp9_abs(q3 - q0) <= 1
      if wd >= 16 && flat8out && flat8in
        dst[o - 7 * sb] = (p7 * 7 + p6 * 2 + p5 + p4 + p3 + p2 + p1 + p0 + q0 + 8) >> 4
        dst[o - 6 * sb] = (p7 * 6 + p6 + p5 * 2 + p4 + p3 + p2 + p1 + p0 + q0 + q1 + 8) >> 4
        dst[o - 5 * sb] = (p7 * 5 + p6 + p5 + p4 * 2 + p3 + p2 + p1 + p0 + q0 + q1 + q2 + 8) >> 4
        dst[o - 4 * sb] = (p7 * 4 + p6 + p5 + p4 + p3 * 2 + p2 + p1 + p0 + q0 + q1 + q2 + q3 + 8) >> 4
        dst[o - 3 * sb] = (p7 * 3 + p6 + p5 + p4 + p3 + p2 * 2 + p1 + p0 + q0 + q1 + q2 + q3 + q4 + 8) >> 4
        dst[o - 2 * sb] = (p7 * 2 + p6 + p5 + p4 + p3 + p2 + p1 * 2 + p0 + q0 + q1 + q2 + q3 + q4 + q5 + 8) >> 4
        dst[o - sb] = (p7 + p6 + p5 + p4 + p3 + p2 + p1 + p0 * 2 + q0 + q1 + q2 + q3 + q4 + q5 + q6 + 8) >> 4
        dst[o] = (p6 + p5 + p4 + p3 + p2 + p1 + p0 + q0 * 2 + q1 + q2 + q3 + q4 + q5 + q6 + q7 + 8) >> 4
        dst[o + sb] = (p5 + p4 + p3 + p2 + p1 + p0 + q0 + q1 * 2 + q2 + q3 + q4 + q5 + q6 + q7 * 2 + 8) >> 4
        dst[o + 2 * sb] = (p4 + p3 + p2 + p1 + p0 + q0 + q1 + q2 * 2 + q3 + q4 + q5 + q6 + q7 * 3 + 8) >> 4
        dst[o + 3 * sb] = (p3 + p2 + p1 + p0 + q0 + q1 + q2 + q3 * 2 + q4 + q5 + q6 + q7 * 4 + 8) >> 4
        dst[o + 4 * sb] = (p2 + p1 + p0 + q0 + q1 + q2 + q3 + q4 * 2 + q5 + q6 + q7 * 5 + 8) >> 4
        dst[o + 5 * sb] = (p1 + p0 + q0 + q1 + q2 + q3 + q4 + q5 * 2 + q6 + q7 * 6 + 8) >> 4
        dst[o + 6 * sb] = (p0 + q0 + q1 + q2 + q3 + q4 + q5 + q6 * 2 + q7 * 7 + 8) >> 4
      elsif wd >= 8 && flat8in
        dst[o - 3 * sb] = (p3 * 3 + 2 * p2 + p1 + p0 + q0 + 4) >> 3
        dst[o - 2 * sb] = (p3 * 2 + p2 + 2 * p1 + p0 + q0 + q1 + 4) >> 3
        dst[o - sb] = (p3 + p2 + p1 + 2 * p0 + q0 + q1 + q2 + 4) >> 3
        dst[o] = (p2 + p1 + p0 + 2 * q0 + q1 + q2 + q3 + 4) >> 3
        dst[o + sb] = (p1 + p0 + q0 + 2 * q1 + q2 + q3 * 2 + 4) >> 3
        dst[o + 2 * sb] = (p0 + q0 + q1 + 2 * q2 + q3 * 3 + 4) >> 3
      else
        hev = vp9_abs(p1 - p0) > hh || vp9_abs(q1 - q0) > hh
        if hev
          f = vp9_clip_s8(p1 - q1)
          f = vp9_clip_s8(3 * (q0 - p0) + f)
          f1 = (f + 4 < 127 ? f + 4 : 127) >> 3
          f2 = (f + 3 < 127 ? f + 3 : 127) >> 3
          dst[o - sb] = vp9_clip(p0 + f2)
          dst[o] = vp9_clip(q0 - f1)
        else
          f = vp9_clip_s8(3 * (q0 - p0))
          f1 = (f + 4 < 127 ? f + 4 : 127) >> 3
          f2 = (f + 3 < 127 ? f + 3 : 127) >> 3
          dst[o - sb] = vp9_clip(p0 + f2)
          dst[o] = vp9_clip(q0 - f1)
          f = (f1 + 1) >> 1
          dst[o - 2 * sb] = vp9_clip(p1 + f)
          dst[o + sb] = vp9_clip(q1 - f)
    i += 1
  0

-> vp9_abs(v) (i64) i64
  v < 0 ? 0 - v : v

-> vp9_clip_s8(v) (i64) i64
  if v < -128
    -128
  elsif v > 127
    127
  else
    v

# Scaled-reference prediction (libvpx scaled convolve): source position
# advances by (dx, dy) sixteenths per output sample.
-> vp9_mc_scaled(dst, d, ds, src, s, ss, w, h, mx, my, dx, dy, flt, fb, bil, avg, tmp) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64 u8[]) i64
  if bil == 1
    th = (((h - 1) * dy + my) >> 4) + 2
    r = 0 ## i64
    while r < th
      imx = mx
      ioff = 0 ## i64
      x = 0 ## i64
      a = s + r * ss
      while x < w
        p = a + ioff
        tmp[r * 64 + x] = src[p] + ((imx * (src[p + 1] - src[p]) + 8) >> 4)
        imx += dx
        ioff += imx >> 4
        imx = imx & 15
        x += 1
      r += 1
    t = 0 ## i64
    y = 0 ## i64
    while y < h
      x = 0 ## i64
      while x < w
        v = tmp[t + x] + ((my * (tmp[t + x + 64] - tmp[t + x]) + 8) >> 4)
        q = d + y * ds + x
        dst[q] = avg == 1 ? (dst[q] + v + 1) >> 1 : v
        x += 1
      my += dy
      t += (my >> 4) * 64
      my = my & 15
      y += 1
    return 0
  th = (((h - 1) * dy + my) >> 4) + 8
  r = 0 ## i64
  while r < th
    imx = mx
    ioff = 0 ## i64
    x = 0 ## i64
    a = s + (r - 3) * ss
    while x < w
      p = a + ioff
      f = fb + imx * 8
      tmp[r * 64 + x] = vp9_clip((flt[f] * src[p - 3] + flt[f + 1] * src[p - 2] + flt[f + 2] * src[p - 1] + flt[f + 3] * src[p] + flt[f + 4] * src[p + 1] + flt[f + 5] * src[p + 2] + flt[f + 6] * src[p + 3] + flt[f + 7] * src[p + 4] + 64) >> 7)
      imx += dx
      ioff += imx >> 4
      imx = imx & 15
      x += 1
    r += 1
  t = 3 * 64 ## i64
  y = 0 ## i64
  while y < h
    f = fb + my * 8
    x = 0 ## i64
    while x < w
      p = t + x
      v = vp9_clip((flt[f] * tmp[p - 192] + flt[f + 1] * tmp[p - 128] + flt[f + 2] * tmp[p - 64] + flt[f + 3] * tmp[p] + flt[f + 4] * tmp[p + 64] + flt[f + 5] * tmp[p + 128] + flt[f + 6] * tmp[p + 192] + flt[f + 7] * tmp[p + 256] + 64) >> 7)
      q = d + y * ds + x
      dst[q] = avg == 1 ? (dst[q] + v + 1) >> 1 : v
      x += 1
    my += dy
    t += (my >> 4) * 64
    my = my & 15
    y += 1
  0

# Clamped window copy for scaled MC: (w+8)x(h+8) at (ix-3, iy-3), stride 288.
-> vp9_emu_edge288(src, ss, sw, sh, ix, iy, w, h, emu) (u8[] i64 i64 i64 i64 i64 i64 i64 u8[]) i64
  y = 0 ## i64
  while y < h + 8
    sy = iy - 3 + y
    sy = 0 if sy < 0
    sy = sh - 1 if sy > sh - 1
    x = 0 ## i64
    while x < w + 8
      sx = ix - 3 + x
      sx = 0 if sx < 0
      sx = sw - 1 if sx > sw - 1
      emu[y * 288 + x] = src[sy * ss + sx]
      x += 1
    y += 1
  0
