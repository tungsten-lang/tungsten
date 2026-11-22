# core/codec/image/heif_color — Y'CbCr (any bit depth, 4:2:0/4:2:2/4:4:4/mono) to sRGB
# RGBA8 for HEIF/AVIF pictures.
#
# Colour description: CICP (ISO/IEC 23091-2) from the item's colr nclx box,
# else the bitstream's; an ICC colr (matrix/TRC profiles, e.g. Display P3) sets
# primaries and transfer. Matrix coefficients 0 (GBR), 1/5/6/7/9/10/4/12
# (Kr/Kb), 8 (YCgCo); limited or full range. Chroma is upsampled bilinearly
# with centred siting. Pictures in other primaries (P3, BT.2020) or with PQ /
# HLG transfer are linearised, gamut-mapped to BT.709 and (HDR) tone-mapped
# with reference white at 203 nits, then re-encoded as sRGB.

use core/codec/image
use core/codec/image/heif_gpu

-> hc_u16(a, o)
  (a[o] << 8) | a[o + 1]

-> hc_u32(a, o)
  (a[o] << 24) | (a[o + 1] << 16) | (a[o + 2] << 8) | a[o + 3]

-> hc_i32(a, o)
  v = hc_u32(a, o)
  v >= 2147483648 ? v - 4294967296 : v

-> hc_tag(a, o)
  a[o].chr + a[o + 1].chr + a[o + 2].chr + a[o + 3].chr

# Tests may set this false to get code values in the picture's own colour space
# (what ImageIO's raw bitmaps hold) instead of sRGB.
HEIF_COLOR_MANAGE = [true]

# CICP colour primaries: xy of R, G, B, white.
-> hc_primaries(cp)
  case cp
    when 4
      [~0.67, ~0.33, ~0.21, ~0.71, ~0.14, ~0.08, ~0.310, ~0.316]
    when 5
      [~0.64, ~0.33, ~0.29, ~0.60, ~0.15, ~0.06, ~0.3127, ~0.3290]
    when 6, 7
      [~0.630, ~0.340, ~0.310, ~0.595, ~0.155, ~0.070, ~0.3127, ~0.3290]
    when 8
      [~0.681, ~0.319, ~0.243, ~0.692, ~0.145, ~0.049, ~0.310, ~0.316]
    when 9
      [~0.708, ~0.292, ~0.170, ~0.797, ~0.131, ~0.046, ~0.3127, ~0.3290]
    when 11
      [~0.680, ~0.320, ~0.265, ~0.690, ~0.150, ~0.060, ~0.314, ~0.351]
    when 12
      [~0.680, ~0.320, ~0.265, ~0.690, ~0.150, ~0.060, ~0.3127, ~0.3290]
    when 22
      [~0.630, ~0.340, ~0.295, ~0.605, ~0.155, ~0.077, ~0.3127, ~0.3290]
    else
      [~0.64, ~0.33, ~0.30, ~0.60, ~0.15, ~0.06, ~0.3127, ~0.3290]

# Kr, Kb for matrix coefficients mc (12/13: derived from primaries).
-> hc_krkb(mc, cp)
  case mc
    when 1
      [~0.2126, ~0.0722]
    when 4
      [~0.30, ~0.11]
    when 5, 6
      [~0.299, ~0.114]
    when 7
      [~0.212, ~0.087]
    when 9, 10
      [~0.2627, ~0.0593]
    when 12, 13
      m = hc_rgb2xyz(hc_primaries(cp))
      [m[3], m[5]]
    else
      [~0.299, ~0.114]

# 3x3 inverse (row-major Array of 9 floats)
-> hc_inv3(m)
  a = m[0]
  b = m[1]
  c = m[2]
  d = m[3]
  e = m[4]
  f = m[5]
  g = m[6]
  h = m[7]
  i = m[8]
  det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
   (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
   (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]

-> hc_mul3(a, b)
  out = []
  r = 0
  while r < 3
    c = 0
    while c < 3
      out.push(a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c])
      c += 1
    r += 1
  out

# RGB → XYZ for primaries p (xy list), white Y = 1.
-> hc_rgb2xyz(p)
  xr = p[0] / p[1]
  zr = (~1.0 - p[0] - p[1]) / p[1]
  xg = p[2] / p[3]
  zg = (~1.0 - p[2] - p[3]) / p[3]
  xb = p[4] / p[5]
  zb = (~1.0 - p[4] - p[5]) / p[5]
  xw = p[6] / p[7]
  zw = (~1.0 - p[6] - p[7]) / p[7]
  m = [xr, xg, xb, ~1.0, ~1.0, ~1.0, zr, zg, zb]
  s = hc_inv3(m)
  sr = s[0] * xw + s[1] + s[2] * zw
  sg = s[3] * xw + s[4] + s[5] * zw
  sb = s[6] * xw + s[7] + s[8] * zw
  [xr * sr, xg * sg, xb * sb, sr, sg, sb, zr * sr, zg * sg, zb * sb]

# Bradford chromatic adaptation from white (xw, yw) to D65.
-> hc_bradford(xw, yw)
  br = [~0.8951, ~0.2664, ~-0.1614, ~-0.7502, ~1.7135, ~0.0367, ~0.0389, ~-0.0685, ~1.0296]
  sx = xw / yw
  sz = (~1.0 - xw - yw) / yw
  dx = ~0.3127 / ~0.3290
  dz = (~1.0 - ~0.3127 - ~0.3290) / ~0.3290
  s = [br[0] * sx + br[1] + br[2] * sz, br[3] * sx + br[4] + br[5] * sz, br[6] * sx + br[7] + br[8] * sz]
  d = [br[0] * dx + br[1] + br[2] * dz, br[3] * dx + br[4] + br[5] * dz, br[6] * dx + br[7] + br[8] * dz]
  dg = [d[0] / s[0], ~0.0, ~0.0, ~0.0, d[1] / s[1], ~0.0, ~0.0, ~0.0, d[2] / s[2]]
  hc_mul3(hc_inv3(br), hc_mul3(dg, br))

SRGB_XYZ_D50 = [~0.4360747, ~0.3850649, ~0.1430804, ~0.2225045, ~0.7168786, ~0.0606169, ~0.0139322, ~0.0971045, ~0.7141733]

# ---------------------------------------------------------------- ICC (matrix/TRC)

# [colorant matrix (to XYZ D50), [trc r, g, b]] or nil. A trc is [:gamma, g],
# [:table, f64[]] or [:para, type, params].
-> hc_icc_parse(icc)
  return nil if icc.size < 132
  cs = hc_tag(icc, 16)
  return nil if cs != "RGB "
  n = hc_u32(icc, 128)
  tags = {}
  k = 0
  while k < n && 132 + k * 12 + 12 <= icc.size
    o = 132 + k * 12
    tags[hc_tag(icc, o)] = [hc_u32(icc, o + 4), hc_u32(icc, o + 8)]
    k += 1
  ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"].each ->(t)
    return nil if tags[t] == nil
  m = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
  cols = ["rXYZ", "gXYZ", "bXYZ"]
  c = 0
  while c < 3
    o = tags[cols[c]][0]
    return nil if o + 20 > icc.size
    m[c] = hc_s15(icc, o + 8)
    m[3 + c] = hc_s15(icc, o + 12)
    m[6 + c] = hc_s15(icc, o + 16)
    c += 1
  trcs = []
  ["rTRC", "gTRC", "bTRC"].each ->(t)
    trcs.push(hc_icc_trc(icc, tags[t][0], tags[t][1]))
  trcs.each ->(t)
    return nil if t == nil
  [m, trcs]

-> hc_s15(a, o)
  hc_i32(a, o).to_f / ~65536.0

-> hc_icc_trc(a, o, len)
  return nil if o + 12 > a.size
  t = hc_tag(a, o)
  if t == "curv"
    n = hc_u32(a, o + 8)
    return [:gamma, ~1.0] if n == 0
    return [:gamma, hc_u16(a, o + 12).to_f / ~256.0] if n == 1
    tb = f64[n]
    k = 0
    while k < n
      tb[k] = hc_u16(a, o + 12 + 2 * k).to_f / ~65535.0
      k += 1
    return [:table, tb]
  if t == "para"
    ty = hc_u16(a, o + 8)
    np = [1, 3, 4, 5, 7]
    return nil if ty > 4
    ps = []
    k = 0
    while k < np[ty]
      ps.push(hc_s15(a, o + 12 + 4 * k))
      k += 1
    return [:para, ty, ps]
  nil

-> hc_trc_eval(t, x)
  if t[0] == :gamma
    return x ** t[1]
  if t[0] == :table
    tb = t[1]
    n = tb.size
    p = x * (n - 1).to_f
    i = p.floor.to_i
    return tb[n - 1] if i >= n - 1
    return tb[0] if i < 0
    fr = p - i.to_f
    return tb[i] * (~1.0 - fr) + tb[i + 1] * fr
  ty = t[1]
  p = t[2]
  g = p[0]
  if ty == 0
    return x ** g
  a = p[1]
  b = p[2]
  if ty == 1
    return x >= ~0.0 - b / a ? (a * x + b) ** g : ~0.0
  if ty == 2
    return x >= ~0.0 - b / a ? (a * x + b) ** g + p[3] : p[3]
  if ty == 3
    return x >= p[4] ? (a * x + b) ** g : p[3] * x
  x >= p[4] ? (a * x + b) ** g + p[5] : p[3] * x + p[6]

# ---------------------------------------------------------------- transfer functions

-> hc_srgb_encode(l)
  return ~0.0 if l <= ~0.0
  return ~1.0 if l >= ~1.0
  l <= ~0.0031308 ? l * ~12.92 : ~1.055 * (l ** (~1.0 / ~2.4)) - ~0.055

# CICP transfer → linear (scene/display relative, 1.0 = reference white for SDR;
# for PQ/HLG the result is in units of 203-nit reference white).
-> hc_to_linear(tc, v)
  v = ~0.0 if v < ~0.0
  case tc
    when 16
      m1 = ~0.1593017578125
      m2 = ~78.84375
      c1 = ~0.8359375
      c2 = ~18.8515625
      c3 = ~18.6875
      p = v ** (~1.0 / m2)
      n = p - c1
      n = ~0.0 if n < ~0.0
      l = (n / (c2 - c3 * p)) ** (~1.0 / m1)
      return l * ~10000.0 / ~203.0
    when 18
      a = ~0.17883277
      b = ~0.28466892
      c = ~0.55991073
      e = v <= ~0.5 ? v * v / ~3.0 : (Math.exp((v - c) / a) + b) / ~12.0
      # OOTF for a 1000-nit display, gamma 1.2 (applied per channel: no luminance coupling)
      return (e ** ~1.2) * ~1000.0 / ~203.0
    when 8
      return v
    when 4
      return v ** ~2.2
    when 5
      return v ** ~2.8
    when 13
      return v <= ~0.04045 ? v / ~12.92 : ((v + ~0.055) / ~1.055) ** ~2.4
    else
      # BT.709 / 601 / 2020 / unspecified: treat as display gamma like sRGB
      return v <= ~0.04045 ? v / ~12.92 : ((v + ~0.055) / ~1.055) ** ~2.4

# ---------------------------------------------------------------- conversion

# Full-resolution chroma, scaled by 16. mode 0: bilinear, centred siting
# (JPEG / AV1 default); 1: nearest; 2: bilinear, horizontally co-sited
# (MPEG-2 "left" siting, chroma_sample_position 1 / HEVC default).
# HEIF_UPSAMPLE[0] = -1 (auto) follows ImageIO, so Blade renders AVIF/HEIC like
# Safari: nearest when the displayed size is odd, centred bilinear for >8-bit,
# co-sited bilinear for 8-bit.
HEIF_UPSAMPLE = [-1]

-> hc_upsample_mode(pic, dw, dh)
  m = HEIF_UPSAMPLE[0]
  return m if m >= 0
  return 1 if (dw & 1) == 1 || (dh & 1) == 1
  pic.bit_depth > 8 ? 0 : 3

# tw/th: grid tile size in luma samples (0: none); chroma interpolation does
# not cross tile edges (each tile is upsampled on its own, as ImageIO does).
-> hc_upsample(src, cw, ch, dst, w, h, ssx, ssy, mode, tw, th) (u16[] i64 i64 i32[] i64 i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < h
    cy0 = (y >> ssy) ## i64
    cy1 = cy0
    wy0 = 4 ## i64
    wy1 = 0 ## i64
    if ssy == 1 && mode == 3
      wy0 = 4
      wy1 = 0
      if (y & 1) == 1
        wy0 = 2
        wy1 = 2
        cy1 = cy0 + 1
        cy1 = ch - 1 if cy1 >= ch
        cy1 = cy0 if th > 0 && ((y + 1) % th) == 0
    elsif ssy == 1 && mode != 1
      wy0 = 3
      wy1 = 1
      if (y & 1) == 0
        cy1 = cy0 - 1
      else
        cy1 = cy0 + 1
      cy1 = 0 if cy1 < 0
      cy1 = ch - 1 if cy1 >= ch
    cy0 = ch - 1 if cy0 >= ch
    r0 = (cy0 * cw) ## i64
    r1 = (cy1 * cw) ## i64
    o = (y * w) ## i64
    x = 0 ## i64
    if ssx == 0
      while x < w
        dst[o + x] = (src[r0 + x] * wy0 + src[r1 + x] * wy1) * 4
        x += 1
    elsif mode == 1
      while x < w
        cx = (x >> 1) ## i64
        cx = cw - 1 if cx >= cw
        dst[o + x] = (src[r0 + cx] * wy0 + src[r1 + cx] * wy1) * 4
        x += 1
    elsif mode == 2 || mode == 3
      while x < w
        cx0 = (x >> 1) ## i64
        cx0 = cw - 1 if cx0 >= cw
        a = (src[r0 + cx0] * wy0 + src[r1 + cx0] * wy1) ## i64
        if (x & 1) == 0
          dst[o + x] = a * 4
        else
          cx1 = cx0 + 1
          cx1 = cw - 1 if cx1 >= cw
          cx1 = cx0 if tw > 0 && ((x + 1) % tw) == 0
          b = (src[r0 + cx1] * wy0 + src[r1 + cx1] * wy1) ## i64
          dst[o + x] = (a + b) * 2
        x += 1
    else
      while x < w
        cx0 = x >> 1
        cx1 = 0 ## i64
        if (x & 1) == 0
          cx1 = cx0 - 1
          cx1 = 0 if cx1 < 0
        else
          cx1 = cx0 + 1
          cx1 = cw - 1 if cx1 >= cw
        cx0 = cw - 1 if cx0 >= cw
        a = src[r0 + cx0] * wy0 + src[r1 + cx0] * wy1
        b = src[r0 + cx1] * wy0 + src[r1 + cx1] * wy1
        dst[o + x] = a * 3 + b
        x += 1
    y += 1
  0

# Y'CbCr → non-linear R'G'B' (0..1 floats), into f32 planes (or straight to
# 8-bit when lut == nil). k: [yoff, yscale, coff, cscale, crv, cbu, cgu, cgv, mode]
# mode 0: Kr/Kb, 1: identity (GBR), 2: YCgCo, 3: mono.
-> hc_convert8(yp, cb, cr, n, k, out) (u16[] i32[] i32[] i64 f64[] u8[]) i64
  yoff = k[0]
  ys = k[1]
  coff = k[2]
  cs = k[3]
  crv = k[4]
  cbu = k[5]
  cgu = k[6]
  cgv = k[7]
  mode = k[8] ## i64
  i = 0 ## i64
  while i < n
    yy = (yp[i].to_f - yoff) * ys
    r = yy
    g = yy
    b = yy
    if mode != 3
      u = (cb[i].to_f * ~0.0625 - coff) * cs
      v = (cr[i].to_f * ~0.0625 - coff) * cs
      if mode == 0
        r = yy + crv * v
        b = yy + cbu * u
        g = yy - cgu * u - cgv * v
      elsif mode == 1
        g = yy
        b = (cb[i].to_f * ~0.0625 - yoff) * ys
        r = (cr[i].to_f * ~0.0625 - yoff) * ys
      else
        t = yy - u
        g = yy + u
        b = t - v
        r = t + v
    o = i * 4
    out[o] = hc_q8(r)
    out[o + 1] = hc_q8(g)
    out[o + 2] = hc_q8(b)
    out[o + 3] = 255
    i += 1
  0

# Fixed-point (2^20) Kr/Kb or monochrome conversion to 8-bit.
# ik: [ky, kcrv, kcbu, kcgu, kcgv, yoff, coff*16, mono]
-> hc_convert_int(yp, cb, cr, n, ik, out) (u16[] i32[] i32[] i64 i64[] u8[]) i64
  ky = (ik[0]) ## i64
  krv = (ik[1]) ## i64
  kbu = (ik[2]) ## i64
  kgu = (ik[3]) ## i64
  kgv = (ik[4]) ## i64
  yoff = (ik[5]) ## i64
  coff = (ik[6]) ## i64
  mono = (ik[7]) ## i64
  half = 524288 ## i64
  i = 0 ## i64
  while i < n
    yy = ((yp[i] - yoff) * ky + half) ## i64
    r = yy
    g = yy
    b = yy
    if mono == 0
      u = (cb[i] - coff) ## i64
      v = (cr[i] - coff) ## i64
      r = yy + krv * v
      b = yy + kbu * u
      g = yy - kgu * u - kgv * v
    r = r >> 20
    g = g >> 20
    b = b >> 20
    r = 0 if r < 0
    r = 255 if r > 255
    g = 0 if g < 0
    g = 255 if g > 255
    b = 0 if b < 0
    b = 255 if b > 255
    o = (i * 4) ## i64
    out[o] = r
    out[o + 1] = g
    out[o + 2] = b
    out[o + 3] = 255
    i += 1
  0

-> hc_q8(v) (f64) i64
  x = (v * ~255.0 + ~0.5) ## i64
  x = 0 if v < ~0.0
  x = 255 if x > 255
  x

# Colour-managed variant: non-linear → linear via LUT (4096 steps over 0..1,
# interpolated), 3x3 to linear sRGB, tone map, sRGB encode LUT.
-> hc_convert_cm(yp, cb, cr, n, k, lut, mtx, tm, enc, out) (u16[] i32[] i32[] i64 f64[] f64[] f64[] f64[] u8[] u8[]) i64
  yoff = k[0]
  ys = k[1]
  coff = k[2]
  cs = k[3]
  crv = k[4]
  cbu = k[5]
  cgu = k[6]
  cgv = k[7]
  mode = k[8] ## i64
  peak = tm[0]
  hdr = tm[1] ## i64
  i = 0 ## i64
  while i < n
    yy = (yp[i].to_f - yoff) * ys
    r = yy
    g = yy
    b = yy
    if mode != 3
      u = (cb[i].to_f * ~0.0625 - coff) * cs
      v = (cr[i].to_f * ~0.0625 - coff) * cs
      if mode == 0
        r = yy + crv * v
        b = yy + cbu * u
        g = yy - cgu * u - cgv * v
      elsif mode == 1
        b = (cb[i].to_f * ~0.0625 - yoff) * ys
        r = (cr[i].to_f * ~0.0625 - yoff) * ys
      else
        t = yy - u
        g = yy + u
        b = t - v
        r = t + v
    lr = hc_lut(lut, r)
    lg = hc_lut(lut, g)
    lb = hc_lut(lut, b)
    sr = mtx[0] * lr + mtx[1] * lg + mtx[2] * lb
    sg = mtx[3] * lr + mtx[4] * lg + mtx[5] * lb
    sb = mtx[6] * lr + mtx[7] * lg + mtx[8] * lb
    if hdr != 0
      # luminance-preserving extended Reinhard
      l = ~0.2126 * sr + ~0.7152 * sg + ~0.0722 * sb
      if l > ~0.0
        nl = l * (~1.0 + l / (peak * peak)) / (~1.0 + l)
        f = nl / l
        sr = sr * f
        sg = sg * f
        sb = sb * f
    o = i * 4
    out[o] = enc[hc_eidx(sr)]
    out[o + 1] = enc[hc_eidx(sg)]
    out[o + 2] = enc[hc_eidx(sb)]
    out[o + 3] = 255
    i += 1
  0

# Colour-managed variant of hc_convert_int: R'G'B' in 12-bit fixed point index
# the linearising LUT directly.
-> hc_convert_cm_int(yp, cb, cr, n, ik, lut, mtx, tm, enc, out) (u16[] i32[] i32[] i64 i64[] f64[] f64[] f64[] u8[] u8[]) i64
  ky = (ik[0]) ## i64
  krv = (ik[1]) ## i64
  kbu = (ik[2]) ## i64
  kgu = (ik[3]) ## i64
  kgv = (ik[4]) ## i64
  yoff = (ik[5]) ## i64
  coff = (ik[6]) ## i64
  mono = (ik[7]) ## i64
  half = 524288 ## i64
  m0 = mtx[0]
  m1 = mtx[1]
  m2 = mtx[2]
  m3 = mtx[3]
  m4 = mtx[4]
  m5 = mtx[5]
  m6 = mtx[6]
  m7 = mtx[7]
  m8 = mtx[8]
  peak2 = tm[0] * tm[0]
  hdr = tm[1] > ~0.5
  i = 0 ## i64
  while i < n
    yy = ((yp[i] - yoff) * ky + half) ## i64
    r = yy
    g = yy
    b = yy
    if mono == 0
      u = (cb[i] - coff) ## i64
      v = (cr[i] - coff) ## i64
      r = yy + krv * v
      b = yy + kbu * u
      g = yy - kgu * u - kgv * v
    r = r >> 20
    g = g >> 20
    b = b >> 20
    r = 0 if r < 0
    r = 4096 if r > 4096
    g = 0 if g < 0
    g = 4096 if g > 4096
    b = 0 if b < 0
    b = 4096 if b > 4096
    lr = lut[r]
    lg = lut[g]
    lb = lut[b]
    sr = m0 * lr + m1 * lg + m2 * lb
    sg = m3 * lr + m4 * lg + m5 * lb
    sb = m6 * lr + m7 * lg + m8 * lb
    if hdr
      l = ~0.2126 * sr + ~0.7152 * sg + ~0.0722 * sb
      if l > ~0.0
        f = (~1.0 + l / peak2) / (~1.0 + l)
        sr = sr * f
        sg = sg * f
        sb = sb * f
    o = (i * 4) ## i64
    out[o] = enc[hc_eidx(sr)]
    out[o + 1] = enc[hc_eidx(sg)]
    out[o + 2] = enc[hc_eidx(sb)]
    out[o + 3] = 255
    i += 1
  0

-> hc_lut(lut, v) (f64[] f64) f64
  if v <= ~0.0
    return lut[0]
  if v >= ~1.0
    return lut[4096]
  p = v * ~4096.0
  i = p ## i64
  fr = p - i.to_f
  lut[i] + (lut[i + 1] - lut[i]) * fr

-> hc_eidx(v) (f64) i64
  if v <= ~0.0
    return 0
  if v >= ~1.0
    return 16383
  (v * ~16383.0 + ~0.5) ## i64

# dw/dh: displayed size after clap (picks the upsampling, see hc_upsample_mode).
-> heif_pic_to_bitmap(pic, nclx, icc, dw = nil, dh = nil, default_mc = 1)
  # Nothing signalled at all (no colr, no VUI colour description): default_mc
  # (core/codec/image/heif.w passes BT.601 for MIAF files, BT.709 otherwise, as ImageIO does);
  # AV1 always reports its (possibly unspecified = BT.601) values via pic.cicp.
  cp = 2
  tc = 2
  mc = default_mc
  full = false
  if pic.cicp != nil
    cp = pic.cicp[0]
    tc = pic.cicp[1]
    mc = pic.cicp[2]
    full = pic.cicp[3]
  if nclx != nil
    cp = nclx[0]
    tc = nclx[1]
    mc = nclx[2]
    full = nclx[3]
  w = pic.width
  h = pic.height
  n = w * h
  bd = pic.bit_depth
  mx = ((1 << bd) - 1).to_f
  k = f64[9]
  if full
    k[0] = ~0.0
    k[1] = ~1.0 / mx
    k[2] = (1 << (bd - 1)).to_f
    k[3] = ~1.0 / mx
  else
    k[0] = (16 << (bd - 8)).to_f
    k[1] = ~1.0 / (219 << (bd - 8)).to_f
    k[2] = (128 << (bd - 8)).to_f
    k[3] = ~1.0 / (224 << (bd - 8)).to_f
  kk = hc_krkb(mc, cp)
  kr = kk[0]
  kb = kk[1]
  kg = ~1.0 - kr - kb
  k[4] = ~2.0 - ~2.0 * kr
  k[5] = ~2.0 - ~2.0 * kb
  k[6] = k[5] * kb / kg
  k[7] = k[4] * kr / kg
  k[8] = ~0.0
  if pic.mono
    k[8] = ~3.0
  elsif mc == 0
    k[8] = ~1.0
  elsif mc == 8
    k[8] = ~2.0
  cm = HEIF_COLOR_MANAGE[0] ? hc_colour_plan(cp, tc, icc) : nil
  um = hc_upsample_mode(pic, dw == nil ? w : dw, dh == nil ? h : dh)
  if cm == nil && (k[8] == ~0.0 || k[8] == ~3.0) && n >= codec_gpu_min(HEIF_GPU_MIN) && codec_gpu_enabled?()
    # common path on the GPU (core/codec/image/heif_gpu), bit-exact
    bm = Bitmap.new(w, h, metal_array(8, n * 4))
    return bm if heif_gpu_convert(pic, hc_int_coeffs(k, ~255.0, pic.mono), um, bm.rgba)
  cb = i32[1]
  cr = i32[1]
  if !pic.mono
    cb = i32[n]
    cr = i32[n]
    hc_upsample(pic.planes[1], pic.cw, pic.ch, cb, w, h, pic.ssx, pic.ssy, um, pic.tile_w, pic.tile_h)
    hc_upsample(pic.planes[2], pic.cw, pic.ch, cr, w, h, pic.ssx, pic.ssy, um, pic.tile_w, pic.tile_h)
  bm = Bitmap.new(w, h)
  if cm == nil && (k[8] == ~0.0 || k[8] == ~3.0)
    ik = hc_int_coeffs(k, ~255.0, pic.mono)
    hc_convert_int(pic.planes[0], cb, cr, n, ik, bm.rgba)
  elsif cm == nil
    hc_convert8(pic.planes[0], cb, cr, n, k, bm.rgba)
  elsif k[8] == ~0.0 || k[8] == ~3.0
    ik = i64[8]
    sc = ~1048576.0 * ~4096.0
    ik[0] = (k[1] * sc + ~0.5).to_i
    ik[1] = (k[3] * k[4] * sc / ~16.0 + ~0.5).to_i
    ik[2] = (k[3] * k[5] * sc / ~16.0 + ~0.5).to_i
    ik[3] = (k[3] * k[6] * sc / ~16.0 + ~0.5).to_i
    ik[4] = (k[3] * k[7] * sc / ~16.0 + ~0.5).to_i
    ik[5] = k[0].to_i
    ik[6] = k[2].to_i * 16
    ik[7] = pic.mono ? 1 : 0
    hc_convert_cm_int(pic.planes[0], cb, cr, n, ik, cm[0], cm[1], cm[2], cm[3], bm.rgba)
  else
    hc_convert_cm(pic.planes[0], cb, cr, n, k, cm[0], cm[1], cm[2], cm[3], bm.rgba)
  bm

# hc_convert_int's fixed-point (2^20) coefficients for output scale omax.
-> hc_int_coeffs(k, omax, mono)
  ik = i64[8]
  sc = ~1048576.0 * omax
  ik[0] = (k[1] * sc + ~0.5).to_i
  ik[1] = (k[3] * k[4] * sc / ~16.0 + ~0.5).to_i
  ik[2] = (k[3] * k[5] * sc / ~16.0 + ~0.5).to_i
  ik[3] = (k[3] * k[6] * sc / ~16.0 + ~0.5).to_i
  ik[4] = (k[3] * k[7] * sc / ~16.0 + ~0.5).to_i
  ik[5] = k[0].to_i
  ik[6] = k[2].to_i * 16
  ik[7] = mono ? 1 : 0
  ik

# nil when the picture is (close enough to) sRGB already; otherwise
# [linearise lut f64[4097], 3x3 to linear sRGB f64[9], [peak, hdr] f64[2], encode lut u8[16384]].
-> hc_colour_plan(cp, tc, icc)
  prof = icc == nil ? nil : hc_icc_parse(icc)
  m = nil
  lut = f64[4097]
  hdr = false
  if prof != nil
    # colorants (D50 PCS) → sRGB D50 inverse
    m = hc_mul3(hc_inv3(SRGB_XYZ_D50), prof[0])
    if hc_near_identity(m) && hc_trc_srgbish(prof[1])
      return nil
    j = 0
    while j <= 4096
      x = j.to_f / ~4096.0
      # channels share one LUT: average the three curves (they are equal in practice)
      lut[j] = (hc_trc_eval(prof[1][0], x) + hc_trc_eval(prof[1][1], x) + hc_trc_eval(prof[1][2], x)) / ~3.0
      j += 1
  else
    srgb_prims = cp == 1 || cp == 2 || cp == 0 || cp == 3 || cp > 22
    sdr_tc = tc != 16 && tc != 18 && tc != 8 && tc != 4 && tc != 5
    return nil if srgb_prims && sdr_tc
    p = hc_primaries(cp)
    src = hc_rgb2xyz(p)
    if p[6] != ~0.3127 || p[7] != ~0.3290
      src = hc_mul3(hc_bradford(p[6], p[7]), src)
    dst = hc_rgb2xyz(hc_primaries(1))
    m = hc_mul3(hc_inv3(dst), src)
    hdr = tc == 16 || tc == 18
    j = 0
    while j <= 4096
      lut[j] = hc_to_linear(tc, j.to_f / ~4096.0)
      j += 1
  mt = f64[9]
  j = 0
  while j < 9
    mt[j] = m[j]
    j += 1
  tm = f64[2]
  tm[0] = tc == 16 ? ~10000.0 / ~203.0 : ~1000.0 / ~203.0
  tm[1] = hdr ? ~1.0 : ~0.0
  enc = u8[16384]
  j = 0
  while j < 16384
    v = hc_srgb_encode(j.to_f / ~16383.0)
    enc[j] = (v * ~255.0 + ~0.5).to_i
    j += 1
  [lut, mt, tm, enc]

-> hc_near_identity(m)
  j = 0
  while j < 9
    want = (j % 4 == 0) ? ~1.0 : ~0.0
    return false if (m[j] - want).abs > ~0.01
    j += 1
  true

-> hc_trc_srgbish(trcs)
  ok = true
  trcs.each ->(t)
    [~0.2, ~0.5, ~0.8].each ->(x)
      want = ((x + ~0.055) / ~1.055) ** ~2.4
      ok = false if (hc_trc_eval(t, x) - want).abs > ~0.01
  ok

# ---------------------------------------------------------------- alpha

-> heif_apply_alpha(bm, ap, full, premult)
  bd = ap.bit_depth
  lo = 0
  hi = (1 << bd) - 1
  if !full
    lo = 16 << (bd - 8)
    hi = 235 << (bd - 8)
  hc_alpha(bm.rgba, bm.width, bm.height, ap.planes[0], ap.width, ap.height, lo, hi, premult ? 1 : 0)
  nil

-> hc_alpha(px, w, h, a, aw, ah, lo, hi, premult) (u8[] i64 i64 u16[] i64 i64 i64 i64 i64) i64
  rng = (hi - lo) ## i64
  y = 0 ## i64
  while y < h
    ay = (y) ## i64
    ay = (y * ah) / h if ah != h
    x = 0 ## i64
    while x < w
      ax = (x) ## i64
      ax = (x * aw) / w if aw != w
      v = (a[ay * aw + ax] - lo) ## i64
      v = 0 if v < 0
      v = rng if v > rng
      al = ((v * 255 + (rng >> 1)) / rng) ## i64
      o = ((y * w + x) * 4) ## i64
      px[o + 3] = al
      if premult != 0
        if al == 0
          px[o] = 0
          px[o + 1] = 0
          px[o + 2] = 0
        else
          c = 0 ## i64
          while c < 3
            q = ((px[o + c] * 255 + (al >> 1)) / al) ## i64
            q = 255 if q > 255
            px[o + c] = q
            c += 1
      x += 1
    y += 1
  0
