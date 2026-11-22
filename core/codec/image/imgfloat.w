# core/codec/image/imgfloat — helpers for decoders of floating-point / HDR images
# (Radiance HDR, OpenEXR, PFM, half-float TIFF/DDS/KTX2).
#
# Scene-linear values are tone-mapped to 8-bit sRGB: identity up to
# IMGF_KNEE, then a rational shoulder that approaches 1.0 (so highlights roll
# off instead of clipping), then the sRGB transfer function via a 64K LUT.
#
#   imgf_tables()                  → [pow2 f64[], lut u8[]] (built once, lazily)
#   imgf_f32(bits, p2)             IEEE binary32 bits → f64
#   imgf_f16(bits, p2)             IEEE binary16 bits → f64
#   imgf_px(out, o, r, g, b, a, lut)  store a linear RGB + alpha (0..1) pixel as RGBA8
#   imgf_lin8(v, lut)              linear f64 → sRGB 8-bit code value

IMGF_KNEE = ~0.8
IMGF_STATE = [nil]

-> imgf_tables
  return IMGF_STATE[0] if IMGF_STATE[0] != nil
  p2 = f64[330]
  imgf_fill_pow2(p2)
  lut = u8[65537]
  imgf_fill_lut(lut)
  IMGF_STATE[0] = [p2, lut]
  IMGF_STATE[0]

# p2[k] = 2^(k - 160), built by exact doubling/halving.
-> imgf_fill_pow2(p2) (f64[]) i64
  v = ~1.0
  k = 160 ## i64
  while k < 330
    p2[k] = v
    v = v * ~2.0
    k += 1
  v = ~0.5
  k = 159
  while k >= 0
    p2[k] = v
    v = v * ~0.5
    k -= 1
  0

# lut[i] = sRGB-encoded 8-bit value of linear i / 65536.
-> imgf_fill_lut(lut)
  i = 0
  while i <= 65536
    l = i.to_f / ~65536.0
    s = l <= ~0.0031308 ? l * ~12.92 : ~1.055 * (l ** (~1.0 / ~2.4)) - ~0.055
    v = (s * ~255.0 + ~0.5).to_i
    v = 255 if v > 255
    v = 0 if v < 0
    lut[i] = v
    i += 1
  nil

-> imgf_f32(bits, p2) (i64 f64[]) f64
  e = (bits >> 23) & 255
  m = bits & 0x7FFFFF
  v = ~0.0
  if e == 0
    v = m.to_f * p2[11]
  elsif e == 255
    v = m == 0 ? ~65504.0 : ~0.0
  else
    v = (m + 8388608).to_f * p2[e + 10]
  ((bits >> 31) & 1) == 1 ? ~0.0 - v : v

-> imgf_f16(bits, p2) (i64 f64[]) f64
  e = (bits >> 10) & 31
  m = bits & 1023
  v = ~0.0
  if e == 0
    v = m.to_f * p2[136]
  elsif e == 31
    v = m == 0 ? ~65504.0 : ~0.0
  else
    v = (m + 1024).to_f * p2[e + 135]
  ((bits >> 15) & 1) == 1 ? ~0.0 - v : v

-> imgf_lin8(v, lut) (f64 u8[]) i64
  return 0 if v <= ~0.0
  if v > ~0.8
    x = v - ~0.8
    v = ~0.8 + x / (~1.0 + x / ~0.2)
  k = (v * ~65536.0).to_i
  k = 65536 if k > 65536
  lut[k]

-> imgf_px(out, o, r, g, b, a, lut) (u8[] i64 f64 f64 f64 f64 u8[]) i64
  out[o] = imgf_lin8(r, lut)
  out[o + 1] = imgf_lin8(g, lut)
  out[o + 2] = imgf_lin8(b, lut)
  av = (a * ~255.0 + ~0.5).to_i
  av = 0 if av < 0
  av = 255 if av > 255
  out[o + 3] = av
  0
