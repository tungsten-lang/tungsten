# core/codec/video/vp8_core — the VP8 bitstream core shared by the WebP lossy
# decoder (core/codec/image/webp_vp8) and the VP8 video decoder
# (core/codec/video/vp8): the boolean entropy decoder (vp8bd_*), the DCT token
# reader (vp8_coeffs), dequantisation tables, inverse WHT/DCT and the loop
# filter (vp8_filter_frame). libvpx/libwebp-exact.

use core/codec/image/webp_vp8l
use vp8_core_tables

VP8_KDC = [4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15, 16, 17, 17, 18, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26,
  27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54,
  55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 76, 77, 78, 79, 80, 81, 82, 83,
  84, 85, 86, 87, 88, 89, 91, 93, 95, 96, 98, 100, 101, 102, 104, 106, 108, 110, 112, 114, 116, 118, 122, 124, 126, 128, 130, 132, 134, 136,
  138, 140, 143, 145, 148, 151, 154, 157]
VP8_KAC = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
  34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 60, 62, 64, 66, 68,
  70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108, 110, 112, 114, 116, 119, 122, 125, 128, 131, 134,
  137, 140, 143, 146, 149, 152, 155, 158, 161, 164, 167, 170, 173, 177, 181, 185, 189, 193, 197, 201, 205, 209, 213, 217, 221, 225, 229, 234, 239, 245,
  249, 254, 259, 264, 269, 274, 279, 284]
# tb layout: [0,16) zigzag, [16,33) bands (+ sentinel), [36,40) start of the
# cat3..cat6 extra-bit probabilities (each list 0-terminated) at [40, 67).
VP8_TB = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15,
  0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0, 0, 0, 0,
  40, 44, 49, 55,
  173, 148, 140, 0,
  176, 155, 140, 135, 0,
  180, 157, 141, 134, 130, 0,
  254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129, 0]

-> vp8_arr(list)
  a = i64[list.size]
  i = 0
  while i < list.size
    a[i] = list[i]
    i += 1
  a

# ---- boolean decoder: s = [value, range-1, bits, pos, end, eof] ----

-> vp8bd_init(a, s, off, len) (u8[] i64[] i64 i64) i64
  s[0] = 0
  s[1] = 254
  s[2] = -8
  s[3] = off
  s[4] = off + len
  s[5] = 0
  vp8bd_load(a, s)

-> vp8bd_load(a, s) (u8[] i64[]) i64
  pos = s[3]
  if pos + 6 <= s[4]
    v = (a[pos] << 40) | (a[pos + 1] << 32) | (a[pos + 2] << 24) | (a[pos + 3] << 16) | (a[pos + 4] << 8) | a[pos + 5]
    s[0] = (s[0] << 48) | v
    s[2] = s[2] + 48
    s[3] = pos + 6
  elsif pos < s[4]
    s[0] = (s[0] << 8) | a[pos]
    s[2] = s[2] + 8
    s[3] = pos + 1
  elsif s[5] == 0
    s[0] = s[0] << 8
    s[2] = s[2] + 8
    s[5] = 1
  else
    s[2] = 0
  0

-> vp8bd_bit(a, s, prob) (u8[] i64[] i64) i64
  if s[2] < 0
    vp8bd_load(a, s)
  range = s[1]
  pos = s[2]
  split = (range * prob) >> 8
  bit = 0 ## i64
  if (s[0] >> pos) > split
    range = range - split
    s[0] = s[0] - ((split + 1) << pos)
    bit = 1
  else
    range = split + 1
  while range < 128
    range = range << 1
    pos -= 1
  s[1] = range - 1
  s[2] = pos
  bit

-> vp8bd_value(a, s, n) (u8[] i64[] i64) i64
  v = 0 ## i64
  while n > 0
    n -= 1
    v = v | (vp8bd_bit(a, s, 128) << n)
  v

# Tokens of one 4x4 block into out[ooff + zigzag[n]]; returns the index after
# the last non-zero coefficient (as libwebp's GetCoeffs).
-> vp8_coeffs(a, s, prob, t, ctx, dqdc, dqac, n, out, ooff, tb) (u8[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64 i64[]) i64
  # the boolean decoder is inlined here (the hottest loop): value / range /
  # bits live in locals and are written back before any call and on return
  value = s[0]
  range = s[1]
  bits = s[2]
  bit = 0 ## i64
  b1 = 0 ## i64
  b0 = 0 ## i64
  r = 0 ## i64
  p = ((t * 8 + tb[16 + n]) * 3 + ctx) * 11
  while n < 16
    if bits < 0
      s[0] = value
      s[2] = bits
      vp8bd_load(a, s)
      value = s[0]
      bits = s[2]
    split = (range * (prob[p])) >> 8
    if (value >> bits) > split
      r = range - split
      value = value - ((split + 1) << bits)
      bit = 1
    else
      r = split + 1
      bit = 0
    sh = tb[128 + r]
    range = (r << sh) - 1
    bits -= sh
    if bit == 0
      s[0] = value
      s[1] = range
      s[2] = bits
      return n
    zero = 1 ## i64
    while zero == 1
      if bits < 0
        s[0] = value
        s[2] = bits
        vp8bd_load(a, s)
        value = s[0]
        bits = s[2]
      split = (range * (prob[p + 1])) >> 8
      if (value >> bits) > split
        r = range - split
        value = value - ((split + 1) << bits)
        bit = 1
      else
        r = split + 1
        bit = 0
      sh = tb[128 + r]
      range = (r << sh) - 1
      bits -= sh
      if bit == 0
        n += 1
        if n == 16
          s[0] = value
          s[1] = range
          s[2] = bits
          return 16
        p = (t * 8 + tb[16 + n]) * 33
      else
        zero = 0
    pc = (t * 8 + tb[17 + n]) * 33
    v = 1 ## i64
    if bits < 0
      s[0] = value
      s[2] = bits
      vp8bd_load(a, s)
      value = s[0]
      bits = s[2]
    split = (range * (prob[p + 2])) >> 8
    if (value >> bits) > split
      r = range - split
      value = value - ((split + 1) << bits)
      bit = 1
    else
      r = split + 1
      bit = 0
    sh = tb[128 + r]
    range = (r << sh) - 1
    bits -= sh
    if bit == 0
      p = pc + 11
    else
      # GetLargeValue, inlined
      if bits < 0
        s[0] = value
        s[2] = bits
        vp8bd_load(a, s)
        value = s[0]
        bits = s[2]
      split = (range * (prob[p + 3])) >> 8
      if (value >> bits) > split
        r = range - split
        value = value - ((split + 1) << bits)
        bit = 1
      else
        r = split + 1
        bit = 0
      sh = tb[128 + r]
      range = (r << sh) - 1
      bits -= sh
      if bit == 0
        if bits < 0
          s[0] = value
          s[2] = bits
          vp8bd_load(a, s)
          value = s[0]
          bits = s[2]
        split = (range * (prob[p + 4])) >> 8
        if (value >> bits) > split
          r = range - split
          value = value - ((split + 1) << bits)
          bit = 1
        else
          r = split + 1
          bit = 0
        sh = tb[128 + r]
        range = (r << sh) - 1
        bits -= sh
        if bit == 0
          v = 2
        else
          if bits < 0
            s[0] = value
            s[2] = bits
            vp8bd_load(a, s)
            value = s[0]
            bits = s[2]
          split = (range * (prob[p + 5])) >> 8
          if (value >> bits) > split
            r = range - split
            value = value - ((split + 1) << bits)
            bit = 1
          else
            r = split + 1
            bit = 0
          sh = tb[128 + r]
          range = (r << sh) - 1
          bits -= sh
          v = 3 + bit
      else
        if bits < 0
          s[0] = value
          s[2] = bits
          vp8bd_load(a, s)
          value = s[0]
          bits = s[2]
        split = (range * (prob[p + 6])) >> 8
        if (value >> bits) > split
          r = range - split
          value = value - ((split + 1) << bits)
          bit = 1
        else
          r = split + 1
          bit = 0
        sh = tb[128 + r]
        range = (r << sh) - 1
        bits -= sh
        if bit == 0
          if bits < 0
            s[0] = value
            s[2] = bits
            vp8bd_load(a, s)
            value = s[0]
            bits = s[2]
          split = (range * (prob[p + 7])) >> 8
          if (value >> bits) > split
            r = range - split
            value = value - ((split + 1) << bits)
            bit = 1
          else
            r = split + 1
            bit = 0
          sh = tb[128 + r]
          range = (r << sh) - 1
          bits -= sh
          if bit == 0
            if bits < 0
              s[0] = value
              s[2] = bits
              vp8bd_load(a, s)
              value = s[0]
              bits = s[2]
            split = (range * (159)) >> 8
            if (value >> bits) > split
              r = range - split
              value = value - ((split + 1) << bits)
              bit = 1
            else
              r = split + 1
              bit = 0
            sh = tb[128 + r]
            range = (r << sh) - 1
            bits -= sh
            v = 5 + bit
          else
            if bits < 0
              s[0] = value
              s[2] = bits
              vp8bd_load(a, s)
              value = s[0]
              bits = s[2]
            split = (range * (165)) >> 8
            if (value >> bits) > split
              r = range - split
              value = value - ((split + 1) << bits)
              bit = 1
            else
              r = split + 1
              bit = 0
            sh = tb[128 + r]
            range = (r << sh) - 1
            bits -= sh
            v = 7 + 2 * bit
            if bits < 0
              s[0] = value
              s[2] = bits
              vp8bd_load(a, s)
              value = s[0]
              bits = s[2]
            split = (range * (145)) >> 8
            if (value >> bits) > split
              r = range - split
              value = value - ((split + 1) << bits)
              bit = 1
            else
              r = split + 1
              bit = 0
            sh = tb[128 + r]
            range = (r << sh) - 1
            bits -= sh
            v += bit
        else
          if bits < 0
            s[0] = value
            s[2] = bits
            vp8bd_load(a, s)
            value = s[0]
            bits = s[2]
          split = (range * (prob[p + 8])) >> 8
          if (value >> bits) > split
            r = range - split
            value = value - ((split + 1) << bits)
            b1 = 1
          else
            r = split + 1
            b1 = 0
          sh = tb[128 + r]
          range = (r << sh) - 1
          bits -= sh
          if bits < 0
            s[0] = value
            s[2] = bits
            vp8bd_load(a, s)
            value = s[0]
            bits = s[2]
          split = (range * (prob[p + 9 + b1])) >> 8
          if (value >> bits) > split
            r = range - split
            value = value - ((split + 1) << bits)
            b0 = 1
          else
            r = split + 1
            b0 = 0
          sh = tb[128 + r]
          range = (r << sh) - 1
          bits -= sh
          cat = 2 * b1 + b0
          v = 0
          k = tb[36 + cat]
          while tb[k] != 0
            if bits < 0
              s[0] = value
              s[2] = bits
              vp8bd_load(a, s)
              value = s[0]
              bits = s[2]
            split = (range * (tb[k])) >> 8
            if (value >> bits) > split
              r = range - split
              value = value - ((split + 1) << bits)
              bit = 1
            else
              r = split + 1
              bit = 0
            sh = tb[128 + r]
            range = (r << sh) - 1
            bits -= sh
            v = v + v + bit
            k += 1
          v += 3 + (8 << cat)
      p = pc + 22
    # sign bit (VP8GetSigned)
    if bits < 0
      s[0] = value
      s[2] = bits
      vp8bd_load(a, s)
      value = s[0]
      bits = s[2]
    split = range >> 1
    if (value >> bits) > split
      range = (range - 1) | 1
      value = value - ((split + 1) << bits)
      v = 0 - v
    else
      range = range | 1
    bits -= 1
    x = v * (n > 0 ? dqac : dqdc)
    out[ooff + tb[n]] = ((x + 32768) & 65535) - 32768
    n += 1
  s[0] = value
  s[1] = range
  s[2] = bits
  16

-> vp8_wht(inp, out, o, tmp) (i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    a0 = inp[i] + inp[12 + i]
    a1 = inp[4 + i] + inp[8 + i]
    a2 = inp[4 + i] - inp[8 + i]
    a3 = inp[i] - inp[12 + i]
    tmp[i] = a0 + a1
    tmp[8 + i] = a0 - a1
    tmp[4 + i] = a3 + a2
    tmp[12 + i] = a3 - a2
    i += 1
  i = 0
  while i < 4
    dc = tmp[i * 4] + 3
    a0 = dc + tmp[3 + i * 4]
    a1 = tmp[1 + i * 4] + tmp[2 + i * 4]
    a2 = tmp[1 + i * 4] - tmp[2 + i * 4]
    a3 = dc - tmp[3 + i * 4]
    b = o + i * 64
    out[b] = vp8_i16((a0 + a1) >> 3)
    out[b + 16] = vp8_i16((a3 + a2) >> 3)
    out[b + 32] = vp8_i16((a0 - a1) >> 3)
    out[b + 48] = vp8_i16((a3 - a2) >> 3)
    i += 1
  0

-> vp8_i16(x) (i64) i64
  ((x + 32768) & 65535) - 32768

-> vp8_sclip1(v) (i64) i64
  return -128 if v < -128
  return 127 if v > 127
  v

-> vp8_f2(p, o, s) (u8[] i64 i64) i64
  p1 = p[o - 2 * s]
  p0 = p[o - s]
  q0 = p[o]
  q1 = p[o + s]
  a = 3 * (q0 - p0) + ((p1 - q1) < -128 ? -128 : ((p1 - q1) > 127 ? 127 : (p1 - q1)))
  a1 = (((a + 4) >> 3) < -16 ? -16 : (((a + 4) >> 3) > 15 ? 15 : ((a + 4) >> 3)))
  a2 = (((a + 3) >> 3) < -16 ? -16 : (((a + 3) >> 3) > 15 ? 15 : ((a + 3) >> 3)))
  p[o - s] = ((p0 + a2) < 0 ? 0 : ((p0 + a2) > 255 ? 255 : (p0 + a2)))
  p[o] = ((q0 - a1) < 0 ? 0 : ((q0 - a1) > 255 ? 255 : (q0 - a1)))
  0

-> vp8_f4(p, o, s) (u8[] i64 i64) i64
  p1 = p[o - 2 * s]
  p0 = p[o - s]
  q0 = p[o]
  q1 = p[o + s]
  a = 3 * (q0 - p0)
  a1 = (((a + 4) >> 3) < -16 ? -16 : (((a + 4) >> 3) > 15 ? 15 : ((a + 4) >> 3)))
  a2 = (((a + 3) >> 3) < -16 ? -16 : (((a + 3) >> 3) > 15 ? 15 : ((a + 3) >> 3)))
  a3 = (a1 + 1) >> 1
  p[o - 2 * s] = ((p1 + a3) < 0 ? 0 : ((p1 + a3) > 255 ? 255 : (p1 + a3)))
  p[o - s] = ((p0 + a2) < 0 ? 0 : ((p0 + a2) > 255 ? 255 : (p0 + a2)))
  p[o] = ((q0 - a1) < 0 ? 0 : ((q0 - a1) > 255 ? 255 : (q0 - a1)))
  p[o + s] = ((q1 - a3) < 0 ? 0 : ((q1 - a3) > 255 ? 255 : (q1 - a3)))
  0

-> vp8_f6(p, o, s) (u8[] i64 i64) i64
  p2 = p[o - 3 * s]
  p1 = p[o - 2 * s]
  p0 = p[o - s]
  q0 = p[o]
  q1 = p[o + s]
  q2 = p[o + 2 * s]
  a = ((3 * (q0 - p0) + vp8_sclip1(p1 - q1)) < -128 ? -128 : ((3 * (q0 - p0) + vp8_sclip1(p1 - q1)) > 127 ? 127 : (3 * (q0 - p0) + vp8_sclip1(p1 - q1))))
  a1 = (27 * a + 63) >> 7
  a2 = (18 * a + 63) >> 7
  a3 = (9 * a + 63) >> 7
  p[o - 3 * s] = ((p2 + a3) < 0 ? 0 : ((p2 + a3) > 255 ? 255 : (p2 + a3)))
  p[o - 2 * s] = ((p1 + a2) < 0 ? 0 : ((p1 + a2) > 255 ? 255 : (p1 + a2)))
  p[o - s] = ((p0 + a1) < 0 ? 0 : ((p0 + a1) > 255 ? 255 : (p0 + a1)))
  p[o] = ((q0 - a1) < 0 ? 0 : ((q0 - a1) > 255 ? 255 : (q0 - a1)))
  p[o + s] = ((q1 - a2) < 0 ? 0 : ((q1 - a2) > 255 ? 255 : (q1 - a2)))
  p[o + 2 * s] = ((q2 - a3) < 0 ? 0 : ((q2 - a3) > 255 ? 255 : (q2 - a3)))
  0

# Simple filter along one edge of 16 pixels.
-> vp8_simple(p, o, hs, vs, thresh) (u8[] i64 i64 i64 i64) i64
  t2 = 2 * thresh + 1
  i = 0 ## i64
  while i < 16
    q = o + i * vs
    if 4 * ((p[q - hs] - p[q]) < 0 ? 0 - (p[q - hs] - p[q]) : (p[q - hs] - p[q])) + ((p[q - 2 * hs] - p[q + hs]) < 0 ? 0 - (p[q - 2 * hs] - p[q + hs]) : (p[q - 2 * hs] - p[q + hs])) <= t2
      vp8_f2(p, q, hs)
    i += 1
  0

# Normal filter along one edge (kind 6: macroblock edge, 4: inner edge).
-> vp8_loop(p, o, hs, vs, size, thresh, ithresh, hevt, kind) (u8[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  t2 = 2 * thresh + 1
  i = 0 ## i64
  while i < size
    q = o + i * vs
    p3 = p[q - 4 * hs]
    p2 = p[q - 3 * hs]
    p1 = p[q - 2 * hs]
    p0 = p[q - hs]
    q0 = p[q]
    q1 = p[q + hs]
    q2 = p[q + 2 * hs]
    q3 = p[q + 3 * hs]
    if 4 * ((p0 - q0) < 0 ? 0 - (p0 - q0) : (p0 - q0)) + ((p1 - q1) < 0 ? 0 - (p1 - q1) : (p1 - q1)) <= t2
      if ((p3 - p2) < 0 ? 0 - (p3 - p2) : (p3 - p2)) <= ithresh && ((p2 - p1) < 0 ? 0 - (p2 - p1) : (p2 - p1)) <= ithresh && ((p1 - p0) < 0 ? 0 - (p1 - p0) : (p1 - p0)) <= ithresh && ((q3 - q2) < 0 ? 0 - (q3 - q2) : (q3 - q2)) <= ithresh && ((q2 - q1) < 0 ? 0 - (q2 - q1) : (q2 - q1)) <= ithresh && ((q1 - q0) < 0 ? 0 - (q1 - q0) : (q1 - q0)) <= ithresh
        if ((p1 - p0) < 0 ? 0 - (p1 - p0) : (p1 - p0)) > hevt || ((q1 - q0) < 0 ? 0 - (q1 - q0) : (q1 - q0)) > hevt
          vp8_f2(p, q, hs)
        elsif kind == 6
          vp8_f6(p, q, hs)
        else
          vp8_f4(p, q, hs)
    i += 1
  0

# fi per macroblock (4 entries): limit, ilevel, inner, hev_thresh.
-> vp8_filter_frame(yp, up, vp, mbw, mbh, fi, ftype) (u8[] u8[] u8[] i64 i64 i64[] i64) i64
  ys = mbw * 16
  uvs = mbw * 8
  mby = 0 ## i64
  while mby < mbh
    mbx = 0 ## i64
    while mbx < mbw
      f = (mby * mbw + mbx) * 4
      limit = fi[f]
      if limit > 0
        il = fi[f + 1]
        inner = fi[f + 2]
        hev = fi[f + 3]
        yo = mby * 16 * ys + mbx * 16
        if ftype == 1
          vp8_simple(yp, yo, 1, ys, limit + 4) if mbx > 0
          if inner == 1
            vp8_simple(yp, yo + 4, 1, ys, limit)
            vp8_simple(yp, yo + 8, 1, ys, limit)
            vp8_simple(yp, yo + 12, 1, ys, limit)
          vp8_simple(yp, yo, ys, 1, limit + 4) if mby > 0
          if inner == 1
            vp8_simple(yp, yo + 4 * ys, ys, 1, limit)
            vp8_simple(yp, yo + 8 * ys, ys, 1, limit)
            vp8_simple(yp, yo + 12 * ys, ys, 1, limit)
        else
          uo = mby * 8 * uvs + mbx * 8
          if mbx > 0
            vp8_loop(yp, yo, 1, ys, 16, limit + 4, il, hev, 6)
            vp8_loop(up, uo, 1, uvs, 8, limit + 4, il, hev, 6)
            vp8_loop(vp, uo, 1, uvs, 8, limit + 4, il, hev, 6)
          if inner == 1
            vp8_loop(yp, yo + 4, 1, ys, 16, limit, il, hev, 4)
            vp8_loop(yp, yo + 8, 1, ys, 16, limit, il, hev, 4)
            vp8_loop(yp, yo + 12, 1, ys, 16, limit, il, hev, 4)
            vp8_loop(up, uo + 4, 1, uvs, 8, limit, il, hev, 4)
            vp8_loop(vp, uo + 4, 1, uvs, 8, limit, il, hev, 4)
          if mby > 0
            vp8_loop(yp, yo, ys, 1, 16, limit + 4, il, hev, 6)
            vp8_loop(up, uo, uvs, 1, 8, limit + 4, il, hev, 6)
            vp8_loop(vp, uo, uvs, 1, 8, limit + 4, il, hev, 6)
          if inner == 1
            vp8_loop(yp, yo + 4 * ys, ys, 1, 16, limit, il, hev, 4)
            vp8_loop(yp, yo + 8 * ys, ys, 1, 16, limit, il, hev, 4)
            vp8_loop(yp, yo + 12 * ys, ys, 1, 16, limit, il, hev, 4)
            vp8_loop(up, uo + 4 * uvs, uvs, 1, 8, limit, il, hev, 4)
            vp8_loop(vp, uo + 4 * uvs, uvs, 1, 8, limit, il, hev, 4)
      mbx += 1
    mby += 1
  0

# ---- YUV → RGB (libwebp's fixed point) and the fancy upsampler ----

-> vp8_qclip(v, m) (i64 i64) i64
  return 0 if v < 0
  return m if v > m
  v

# VP8_TB plus, at [128, 384), the renormalisation shift for each range.
-> vp8_tables
  tb = i64[384]
  i = 0
  while i < VP8_TB.size
    tb[i] = VP8_TB[i]
    i += 1
  r = 1
  while r < 256
    sh = 0
    while (r << sh) < 128
      sh += 1
    tb[128 + r] = sh
    r += 1
  tb
