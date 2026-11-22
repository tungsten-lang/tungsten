# core/codec/cicp — CICP (ITU-T H.273) colour description → sRGB, shared by decoders
# (PNG cICP, AVIF/HEIF nclx colr, JPEG XL, video stills).
#
#   t = cicp_transform(primaries, transfer)   → CicpTransform, or nil when the
#        pixels are already sRGB (primaries 1/2 with transfer 13, or
#        unspecified) or the combination is unknown (then leave pixels alone)
#   cicp_apply(t, rgba, npix)                 convert straight RGBA8 in place
#   t.to_srgb(r, g, b)                        one pixel of normalised code
#        values (0..1 floats, any bit depth) → [r, g, b] sRGB floats 0..1
#        (for 10/12-bit decoders that convert before quantising)
#
# Primaries: 1 BT.709/sRGB, 4 BT.470M, 5 BT.601-625, 6/7 BT.601-525/SMPTE240,
# 9 BT.2020, 10 XYZ, 11 DCI-P3, 12 Display P3, 22 EBU 3213. Transfer: 1/6/14/15
# BT.709, 4 gamma 2.2, 5 gamma 2.8, 8 linear, 13 sRGB, 16 PQ (SMPTE 2084),
# 18 HLG. HDR (PQ/HLG) is tone-mapped to SDR: reference white at 203 cd/m² and
# a Reinhard-style shoulder above it, applied to the maximum channel so hues hold.
# Matrix coefficients (YCbCr→RGB) are the decoder's business, not this file's.

CICP_PRIMS = {1 => [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290],
  2 => [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290],
  4 => [0.67, 0.33, 0.21, 0.71, 0.14, 0.08, 0.310, 0.316],
  5 => [0.64, 0.33, 0.29, 0.60, 0.15, 0.06, 0.3127, 0.3290],
  6 => [0.630, 0.340, 0.310, 0.595, 0.155, 0.070, 0.3127, 0.3290],
  7 => [0.630, 0.340, 0.310, 0.595, 0.155, 0.070, 0.3127, 0.3290],
  9 => [0.708, 0.292, 0.170, 0.797, 0.131, 0.046, 0.3127, 0.3290],
  11 => [0.680, 0.320, 0.265, 0.690, 0.150, 0.060, 0.314, 0.351],
  12 => [0.680, 0.320, 0.265, 0.690, 0.150, 0.060, 0.3127, 0.3290],
  22 => [0.630, 0.340, 0.295, 0.605, 0.155, 0.077, 0.3127, 0.3290]}

-> cicp_known_transfer?(t)
  t == 1 || t == 2 || t == 6 || t == 14 || t == 15 || t == 4 || t == 5 || t == 8 || t == 13 || t == 16 || t == 18

-> cicp_transform(primaries, transfer)
  p = primaries == 2 ? 1 : primaries
  tr = transfer == 2 ? 13 : transfer
  return nil if !CICP_PRIMS.has_key?(p) || !cicp_known_transfer?(tr)
  return nil if p == 1 && tr == 13
  CicpTransform.new(p, tr)

# Row-major 3x3 helpers on f64[9].
-> cicp_mul(a, b) (f64[] f64[]) f64[]
  r = f64[9]
  i = 0 ## i64
  while i < 3
    j = 0 ## i64
    while j < 3
      r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
      j += 1
    i += 1
  r

-> cicp_inv(m) (f64[]) f64[]
  a = m[0]
  b = m[1]
  c = m[2]
  d = m[3]
  e = m[4]
  f = m[5]
  g = m[6]
  h = m[7]
  k = m[8]
  det = a * (e * k - f * h) - b * (d * k - f * g) + c * (d * h - e * g)
  r = f64[9]
  r[0] = (e * k - f * h) / det
  r[1] = (c * h - b * k) / det
  r[2] = (b * f - c * e) / det
  r[3] = (f * g - d * k) / det
  r[4] = (a * k - c * g) / det
  r[5] = (c * d - a * f) / det
  r[6] = (d * h - e * g) / det
  r[7] = (b * g - a * h) / det
  r[8] = (a * e - b * d) / det
  r

# RGB → XYZ for chromaticities [rx, ry, gx, gy, bx, by, wx, wy].
-> cicp_rgb_to_xyz(c)
  m = f64[9]
  i = 0
  while i < 3
    x = c[i * 2].to_f
    y = c[i * 2 + 1].to_f
    m[i] = x / y
    m[3 + i] = ~1.0
    m[6 + i] = (~1.0 - x - y) / y
    i += 1
  wx = c[6].to_f
  wy = c[7].to_f
  w0 = wx / wy
  w2 = (~1.0 - wx - wy) / wy
  inv = cicp_inv(m)
  s0 = inv[0] * w0 + inv[1] + inv[2] * w2
  s1 = inv[3] * w0 + inv[4] + inv[5] * w2
  s2 = inv[6] * w0 + inv[7] + inv[8] * w2
  r = f64[9]
  j = 0
  while j < 3
    r[j * 3] = m[j * 3] * s0
    r[j * 3 + 1] = m[j * 3 + 1] * s1
    r[j * 3 + 2] = m[j * 3 + 2] * s2
    j += 1
  r

# Bradford adaptation from white (wx, wy) to D65.
-> cicp_adapt(wx, wy)
  bf = %f64[0.8951 0.2664 -0.1614 -0.7502 1.7135 0.0367 0.0389 -0.0685 1.0296]
  sx = wx / wy
  sz = (~1.0 - wx - wy) / wy
  dx = ~0.3127 / ~0.3290
  dz = (~1.0 - ~0.3127 - ~0.3290) / ~0.3290
  s = f64[3]
  d = f64[3]
  i = 0
  while i < 3
    s[i] = bf[i * 3] * sx + bf[i * 3 + 1] + bf[i * 3 + 2] * sz
    d[i] = bf[i * 3] * dx + bf[i * 3 + 1] + bf[i * 3 + 2] * dz
    i += 1
  dg = f64[9]
  dg[0] = d[0] / s[0]
  dg[4] = d[1] / s[1]
  dg[8] = d[2] / s[2]
  cicp_mul(cicp_inv(bf), cicp_mul(dg, bf))

# Code value (0..1) → linear light, relative to SDR reference white (1.0).
-> cicp_eotf(tr, v0) (i64 f64) f64
  v = v0 < ~0.0 ? ~0.0 : v0
  if tr == 13
    return v <= ~0.04045 ? v / ~12.92 : ((v + ~0.055) / ~1.055) ** ~2.4
  if tr == 1 || tr == 6 || tr == 14 || tr == 15
    return v < ~0.081 ? v / ~4.5 : ((v + ~0.099) / ~1.099) ** (~1.0 / ~0.45)
  if tr == 4
    return v ** ~2.2
  if tr == 5
    return v ** ~2.8
  if tr == 8
    return v
  if tr == 16
    # PQ: absolute cd/m², normalised so 203 cd/m² (BT.2408 reference white) = 1.
    m1 = ~0.1593017578125
    m2 = ~78.84375
    c1 = ~0.8359375
    c2 = ~18.8515625
    c3 = ~18.6875
    p = v ** (~1.0 / m2)
    num = p - c1
    num = ~0.0 if num < ~0.0
    return ((num / (c2 - c3 * p)) ** (~1.0 / m1)) * ~10000.0 / ~203.0
  # HLG (inverse OETF; scene light ×12 → reference white ≈ 0.75 code value)
  a = ~0.17883277
  b = ~0.28466892
  c = ~0.55991073
  lin = v <= ~0.5 ? (v * v) / ~3.0 : (Math.exp((v - c) / a) + b) / ~12.0
  lin * ~3.7743

-> cicp_srgb_oetf(l0) (f64) f64
  l = l0 < ~0.0 ? ~0.0 : (l0 > ~1.0 ? ~1.0 : l0)
  l <= ~0.0031308 ? l * ~12.92 : ~1.055 * (l ** (~1.0 / ~2.4)) - ~0.055

+ CicpTransform
  ro :primaries, :transfer, :matrix, :hdr

  -> new(@primaries, @transfer)
    c = CICP_PRIMS[@primaries]
    to_xyz = cicp_rgb_to_xyz(c)
    srgb = cicp_inv(cicp_rgb_to_xyz(CICP_PRIMS[1]))
    ad = cicp_adapt(c[6].to_f, c[7].to_f)
    @matrix = cicp_mul(srgb, cicp_mul(ad, to_xyz))
    @hdr = @transfer == 16 || @transfer == 18
    @lin = f64[256]
    i = 0
    while i < 256
      @lin[i] = cicp_eotf(@transfer, i / ~255.0)
      i += 1
    @enc = u8[4097]
    k = 0
    while k <= 4096
      @enc[k] = (cicp_srgb_oetf(k / ~4096.0) * ~255.0 + ~0.5).to_i
      k += 1

  -> to_srgb(r, g, b)
    out = f64[3]
    cicp_px(cicp_eotf(@transfer, r), cicp_eotf(@transfer, g), cicp_eotf(@transfer, b), @matrix, @hdr ? 1 : 0, out)
    [cicp_srgb_oetf(out[0]), cicp_srgb_oetf(out[1]), cicp_srgb_oetf(out[2])]

  -> apply(rgba, npix)
    cicp_apply_px(rgba, npix, @lin, @matrix, @hdr ? 1 : 0, @enc)

# Linear (r, g, b) in the source primaries → linear sRGB in out[0..2].
-> cicp_px(r, g, b, m, hdr, out) (f64 f64 f64 f64[] i64 f64[]) i64
  x = m[0] * r + m[1] * g + m[2] * b
  y = m[3] * r + m[4] * g + m[5] * b
  z = m[6] * r + m[7] * g + m[8] * b
  if hdr == 1
    mx = x
    mx = y if y > mx
    mx = z if z > mx
    if mx > ~0.8
      # shoulder: 0.8 → 0.8, ∞ → 1.0
      t = mx - ~0.8
      nm = ~0.8 + ~0.2 * t / (t + ~0.2)
      k = nm / mx
      x = x * k
      y = y * k
      z = z * k
  out[0] = x
  out[1] = y
  out[2] = z
  0

-> cicp_apply_px(px, n, lin, m, hdr, enc) (u8[] i64 f64[] f64[] i64 u8[]) i64
  out = f64[3]
  i = 0 ## i64
  while i < n
    o = i * 4
    cicp_px(lin[px[o]], lin[px[o + 1]], lin[px[o + 2]], m, hdr, out)
    c = 0 ## i64
    while c < 3
      v = out[c]
      v = ~0.0 if v < ~0.0
      v = ~1.0 if v > ~1.0
      px[o + c] = enc[(v * ~4096.0 + ~0.5) ## i64]
      c += 1
    i += 1
  0

-> cicp_apply(t, rgba, npix)
  t.apply(rgba, npix)
  nil
