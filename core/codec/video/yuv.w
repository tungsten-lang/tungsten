# core/codec/video/yuv — VideoFrame (planar Y'CbCr, CICP) → straight RGBA8 sRGB.
#
#   rgba = yuv_to_rgba(frame)            # ByteArray of w * h * 4 (visible size, crop applied)
#   yuv_to_rgba_into(frame, rgba)        # into an existing buffer (reused per frame)
#
# Matrix coefficients (CICP MatrixCoefficients): 1 BT.709, 5/6 BT.601, 9/10
# BT.2020 (non-constant luminance), 4 FCC, 7 SMPTE 240M, 0 identity (GBR
# planes); 2 (unspecified) picks BT.709 for HD sizes and BT.601 below 720
# lines. Limited ("video") or full range, 8 bits (u8[] planes) or 9–16 bits
# (u16[] planes). 4:2:0, 4:2:2, 4:4:4 and 4:0:0. Chroma is taken from the
# co-sited sample (nearest neighbour); the conversion is integer fixed point.
# Wide-gamut / HDR frames (primaries other than BT.709, PQ or HLG transfer)
# are converted to sRGB afterwards by core/codec/cicp, which tone-maps PQ/HLG to SDR.
#
use core/codec/cicp

# Rows are split across worker threads for large frames (the kernels are
# allocation-free typed loops over shared buffers).

# [Kr, Kb] for a matrix code (nil: identity).
-> yuv_kr_kb(m, h)
  m = (h >= 720 ? 1 : 6) if m == 2 || m == 3 || m > 14
  return nil if m == 0
  return [~0.299, ~0.114] if m == 5 || m == 6
  return [~0.2627, ~0.0593] if m == 9 || m == 10
  return [~0.30, ~0.11] if m == 4
  return [~0.212, ~0.087] if m == 7
  [~0.2126, ~0.0722]

# Fixed-point coefficients (Q16, output in 0..255 units for 8-bit input):
# [ys, yo, crr, cbg, crg, cbb, co] — R = (ys(Y-yo) + crr(V-co)) >> 16, …
-> yuv_coeffs(frame)
  kk = yuv_kr_kb(frame.matrix, frame.height)
  d = frame.bit_depth
  full = frame.full_range == true
  sc = (1 << (d - 8)).to_f
  if kk == nil
    return nil
  kr = kk[0]
  kb = kk[1]
  kg = ~1.0 - kr - kb
  ys = full ? ~255.0 / ~255.0 : ~255.0 / ~219.0
  cs = full ? ~255.0 / ~255.0 : ~255.0 / ~224.0
  if full && d > 8
    # full range at n bits: (2^n - 1) maps to 255
    ys = ~255.0 / ((1 << d) - 1).to_f * sc
    cs = ys
  q = ~65536.0 / sc
  crr = cs * ~2.0 * (~1.0 - kr)
  cbb = cs * ~2.0 * (~1.0 - kb)
  crg = cs * ~2.0 * (~1.0 - kr) * kr / kg
  cbg = cs * ~2.0 * (~1.0 - kb) * kb / kg
  yo = full ? 0 : (16 << (d - 8))
  [(ys * q).round, yo, (crr * q).round, (cbg * q).round, (crg * q).round, (cbb * q).round, 128 << (d - 8)]

-> yuv_row8(yp, up, vp, out, w, yoff, coff, ooff, sx, k) (u8[] u8[] u8[] u8[] i64 i64 i64 i64 i64 i64[]) i64
  ys = k[0]
  yo = k[1]
  crr = k[2]
  cbg = k[3]
  crg = k[4]
  cbb = k[5]
  co = k[6]
  x = 0 ## i64
  o = ooff
  while x < w
    ci = coff + (x >> sx)
    u = up[ci] - co
    v = vp[ci] - co
    rr = crr * v + 32768
    gg = 32768 - cbg * u - crg * v
    bb = cbb * u + 32768
    c = ys * (yp[yoff + x] - yo)
    r = (c + rr) >> 16
    g = (c + gg) >> 16
    b = (c + bb) >> 16
    r = 0 if r < 0
    r = 255 if r > 255
    g = 0 if g < 0
    g = 255 if g > 255
    b = 0 if b < 0
    b = 255 if b > 255
    out[o] = r
    out[o + 1] = g
    out[o + 2] = b
    out[o + 3] = 255
    o += 4
    x += 1
    if sx == 1 && x < w
      c = ys * (yp[yoff + x] - yo)
      r = (c + rr) >> 16
      g = (c + gg) >> 16
      b = (c + bb) >> 16
      r = 0 if r < 0
      r = 255 if r > 255
      g = 0 if g < 0
      g = 255 if g > 255
      b = 0 if b < 0
      b = 255 if b > 255
      out[o] = r
      out[o + 1] = g
      out[o + 2] = b
      out[o + 3] = 255
      o += 4
      x += 1
  w

-> yuv_rows8(yp, up, vp, out, w, y0, y1, cx, cy, ystr, cstr, sx, sy, k) (u8[] u8[] u8[] u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  y = y0
  while y < y1
    yuv_row8(yp, up, vp, out, w, (y + cy) * ystr + cx, ((y + cy) >> sy) * cstr + (cx >> sx), y * w * 4, sx, k)
    y += 1
  y1 - y0

-> yuv_rows16(yp, up, vp, out, w, y0, y1, cx, cy, ystr, cstr, sx, sy, k) (u16[] u16[] u16[] u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  ys = k[0]
  yo = k[1]
  crr = k[2]
  cbg = k[3]
  crg = k[4]
  cbb = k[5]
  co = k[6]
  y = y0
  while y < y1
    yoff = (y + cy) * ystr + cx
    coff = ((y + cy) >> sy) * cstr
    o = y * w * 4
    x = 0 ## i64
    while x < w
      ci = coff + ((x + cx) >> sx)
      u = up[ci] - co
      v = vp[ci] - co
      c = ys * (yp[yoff + x] - yo)
      r = (c + crr * v + 32768) >> 16
      g = (c - cbg * u - crg * v + 32768) >> 16
      b = (c + cbb * u + 32768) >> 16
      r = 0 if r < 0
      r = 255 if r > 255
      g = 0 if g < 0
      g = 255 if g > 255
      b = 0 if b < 0
      b = 255 if b > 255
      out[o] = r
      out[o + 1] = g
      out[o + 2] = b
      out[o + 3] = 255
      o += 4
      x += 1
    y += 1
  y1 - y0

# Grey (4:0:0) and identity (GBR) planes.
-> yuv_rows_grey8(yp, out, w, y0, y1, cx, cy, ystr, ys, yo) (u8[] u8[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  y = y0
  while y < y1
    yoff = (y + cy) * ystr + cx
    o = y * w * 4
    x = 0 ## i64
    while x < w
      v = (ys * (yp[yoff + x] - yo) + 32768) >> 16
      v = 0 if v < 0
      v = 255 if v > 255
      out[o] = v
      out[o + 1] = v
      out[o + 2] = v
      out[o + 3] = 255
      o += 4
      x += 1
    y += 1
  y1 - y0

-> yuv_rows_gbr8(gp, bp, rp, out, w, y0, y1, cx, cy, str) (u8[] u8[] u8[] u8[] i64 i64 i64 i64 i64 i64) i64
  y = y0
  while y < y1
    off = (y + cy) * str + cx
    o = y * w * 4
    x = 0 ## i64
    while x < w
      out[o] = rp[off + x]
      out[o + 1] = gp[off + x]
      out[o + 2] = bp[off + x]
      out[o + 3] = 255
      o += 4
      x += 1
    y += 1
  y1 - y0

YUV_THREADS = [4]

-> yuv_to_rgba(frame)
  c = frame.crop
  w = c == nil ? frame.width : c[2]
  h = c == nil ? frame.height : c[3]
  out = ByteArray.new(w * h * 4)
  yuv_to_rgba_into(frame, out)
  out

# Convert into out (w * h * 4 for the visible size); returns out.
-> yuv_to_rgba_into(frame, out)
  c = frame.crop
  cx = c == nil ? 0 : c[0]
  cy = c == nil ? 0 : c[1]
  w = c == nil ? frame.width : c[2]
  h = c == nil ? frame.height : c[3]
  ch = frame.chroma
  sx = ch == "420" || ch == "422" ? 1 : 0
  sy = ch == "420" ? 1 : 0
  pl = frame.planes
  st = frame.strides
  k = yuv_coeffs(frame)
  hi = frame.bit_depth > 8
  if ch == "400" || pl.size < 3
    kk = yuv_coeffs(frame)
    ys = kk == nil ? 65536 : kk[0]
    yo = kk == nil ? 0 : kk[1]
    yuv_rows_grey8(pl[0], out, w, 0, h, cx, cy, st[0], ys, yo) if !hi
    yuv_cicp(frame, out, w * h)
    return out
  if k == nil
    yuv_rows_gbr8(pl[0], pl[1], pl[2], out, w, 0, h, cx, cy, st[0]) if !hi
    yuv_cicp(frame, out, w * h)
    return out
  ka = i64[7]
  i = 0
  while i < 7
    ka[i] = k[i]
    i += 1
  nt = YUV_THREADS[0]
  nt = 1 if w * h < 400000
  if nt <= 1
    if hi
      yuv_rows16(pl[0], pl[1], pl[2], out, w, 0, h, cx, cy, st[0], st[1], sx, sy, ka)
    else
      yuv_rows8(pl[0], pl[1], pl[2], out, w, 0, h, cx, cy, st[0], st[1], sx, sy, ka)
  else
    band = ((h / nt) + 1) & -2
    ths = []
    j = 0
    while j < nt
      y0 = j * band
      y1 = y0 + band
      y1 = h if y1 > h || j == nt - 1
      if y0 < y1
        a0 = pl[0]
        a1 = pl[1]
        a2 = pl[2]
        s0 = st[0]
        s1 = st[1]
        if hi
          ths.push(Thread.new ->
            yuv_rows16(a0, a1, a2, out, w, y0, y1, cx, cy, s0, s1, sx, sy, ka))
        else
          ths.push(Thread.new ->
            yuv_rows8(a0, a1, a2, out, w, y0, y1, cx, cy, s0, s1, sx, sy, ka))
      j += 1
    ths.each ->(t) t.join
  yuv_cicp(frame, out, w * h)
  out

YUV_CICP_CACHE = {}

# Non-sRGB primaries or an HDR / non-709 transfer: convert with core/codec/cicp.
-> yuv_cicp(frame, out, npix)
  p = frame.primaries
  t = frame.transfer
  return nil if (p == 1 || p == 2) && (t == 1 || t == 2 || t == 6 || t == 13 || t == 14 || t == 15)
  key = p * 1000 + t
  tr = nil
  if YUV_CICP_CACHE.has_key?(key)
    tr = YUV_CICP_CACHE[key]
  else
    tr = cicp_transform(p, t)
    YUV_CICP_CACHE[key] = tr
  cicp_apply(tr, out, npix) if tr != nil
  nil
