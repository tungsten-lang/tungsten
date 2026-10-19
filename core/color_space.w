# ColorSpace — RGB colour spaces (primaries, white point and transfer
# function) and conversion between them through CIE XYZ. Transfer — the
# transfer functions of sRGB, BT.709 and BT.1886.
#
#   ColorSpace.rec709.to_xyz                          # derived from the primaries
#   ColorSpace.display_p3.matrix_to(:rec709)          # linear P3 -> linear BT.709
#   ColorSpace.srgb.convert([~1.0, ~0.5, ~0.0], :rec709)
#   ColorSpace.named("display_p3").decode(~0.5)       # code value -> linear light
#   Transfer.bt709_oetf(~0.18)                        # scene light -> camera signal
#   Transfer.srgb_to_bt1886(~0.5)                     # sRGB pixel -> BT.1886 pixel
#
# Code values (R'G'B') and linear light are relative, 0..1. The names match
# the drawing canvas: "srgb", "rec709", "display_p3", "linear_srgb".
#
#   name          primaries, white            transfer (code value -> light)
#   srgb          BT.709, D65                 sRGB EOTF (IEC 61966-2-1)
#   rec709        BT.709, D65                 BT.1886 EOTF, gamma 2.4
#   display_p3    P3 (SMPTE EG 432-1), D65    sRGB EOTF
#   linear_srgb   BT.709, D65                 none
#
# sRGB and Rec.709 share primaries and white point (ITU-R BT.709-6 items 1.3
# and 1.4); they differ only in transfer. "rec709" is display-referred: its
# code values mean the light a BT.1886 reference display makes from them,
# which is how an SDR master is judged (BT.709-6 item 1.2, note 1). The
# BT.709 OETF is a camera's scene-referred encoding; read code values that
# way with `ColorSpace.rec709.with_transfer(:bt709)`. doc/color.md says which
# to use for a video master, and why.
#
# Conversions go through CIE XYZ in linear light. All four spaces have the
# D65 white point, so no chromatic adaptation is needed; matrix_to refuses a
# pair with different white points.

+ ColorSpace
  ro :name, :primaries, :white, :transfer

  # primaries: [xr, yr, xg, yg, xb, yb] and white: [xw, yw], CIE 1931 x, y
  # chromaticities; transfer: a Transfer kind (:srgb, :bt709, :bt1886, :linear).
  -> new(@name, @primaries, @white, @transfer)
    @transfer = Transfer.kind(@transfer)

  # ITU-R BT.709-6 item 1.3 (the sRGB primaries too: IEC 61966-2-1).
  -> .bt709_primaries
    [~0.640, ~0.330, ~0.300, ~0.600, ~0.150, ~0.060]

  # SMPTE EG 432-1 (DCI-P3) primaries; Display P3 pairs them with D65.
  -> .p3_primaries
    [~0.680, ~0.320, ~0.265, ~0.690, ~0.150, ~0.060]

  # CIE D65, as BT.709-6 item 1.4 rounds it.
  -> .d65
    [~0.3127, ~0.3290]

  -> .srgb
    ColorSpace.new("srgb", ColorSpace.bt709_primaries, ColorSpace.d65, :srgb)

  -> .rec709
    ColorSpace.new("rec709", ColorSpace.bt709_primaries, ColorSpace.d65, :bt1886)

  -> .display_p3
    ColorSpace.new("display_p3", ColorSpace.p3_primaries, ColorSpace.d65, :srgb)

  -> .linear_srgb
    ColorSpace.new("linear_srgb", ColorSpace.bt709_primaries, ColorSpace.d65, :linear)

  -> .names
    ["srgb", "rec709", "display_p3", "linear_srgb"]

  # A space by name ("rec709" or :rec709); a ColorSpace is returned as is.
  -> .named(space)
    if space.is_a?(ColorSpace)
      return space
    n = space.to_s
    if n == "srgb"
      return ColorSpace.srgb
    if n == "rec709"
      return ColorSpace.rec709
    if n == "display_p3"
      return ColorSpace.display_p3
    if n == "linear_srgb"
      return ColorSpace.linear_srgb
    raise ArgumentError, "unknown colour space '[n]': expected srgb, rec709, display_p3 or linear_srgb"

  # The same primaries and white point with another transfer function.
  -> with_transfer(kind)
    ColorSpace.new(@name, @primaries, @white, kind)

  -> to_s
    @name

  # Linear RGB -> CIE XYZ, as rows [X, Y, Z], scaled so that R = G = B = 1
  # is the white point with Y = 1 (SMPTE RP 177-1993).
  -> to_xyz
    colorspace_rgb_to_xyz(@primaries, @white)

  -> from_xyz
    colorspace_inverse3(to_xyz)

  # The relative luminance of each primary: the Y row of to_xyz. For BT.709
  # primaries and D65 it rounds to BT.709-6 item 3.2's 0.2126, 0.7152, 0.0722.
  -> luma_weights
    to_xyz[1]

  -> same_primaries?(other)
    o = ColorSpace.named(other)
    colorspace_close?(@primaries, o.primaries) && colorspace_close?(@white, o.white)

  # Linear RGB in this space -> linear RGB in `other` (the identity when the
  # primaries match).
  -> matrix_to(other)
    o = ColorSpace.named(other)
    if !colorspace_close?(@white, o.white)
      raise ArgumentError, "matrix_to: [@name] and [o.name] have different white points (no chromatic adaptation)"
    colorspace_mul3(o.from_xyz, to_xyz)

  # One channel: code value -> linear light, and back.
  -> decode(v)
    Transfer.decode(@transfer, v)

  -> encode(l)
    Transfer.encode(@transfer, l)

  # [r, g, b] code values in this space -> code values in `other`: decode,
  # change primaries in linear light, clip each channel to [0, 1] (so an
  # out-of-gamut colour is clipped, not compressed), encode.
  -> convert(rgb, other)
    o = ColorSpace.named(other)
    lin = [decode(rgb[0]), decode(rgb[1]), decode(rgb[2])]
    if !same_primaries?(o)
      lin = colorspace_apply3(matrix_to(o), lin)
    [o.encode(colorspace_clip01(lin[0])), o.encode(colorspace_clip01(lin[1])), o.encode(colorspace_clip01(lin[2]))]


# --------------------------------------------------------------------------

# Transfer — the sRGB, BT.709 and BT.1886 transfer functions and their
# inverses; every formula keeps its standard's published constants.
+ Transfer
  -> .kinds
    [:srgb, :bt709, :bt1886, :linear]

  # A kind from a Symbol or String: :srgb, :bt709 (the BT.709 OETF),
  # :bt1886 (the BT.1886 EOTF, Lw = 1, Lb = 0) or :linear.
  -> .kind(k)
    n = k.to_s
    if n == "srgb"
      return :srgb
    if n == "bt709"
      return :bt709
    if n == "bt1886"
      return :bt1886
    if n == "linear"
      return :linear
    raise ArgumentError, "unknown transfer '[n]': expected srgb, bt709, bt1886 or linear"

  # The integer the pixel kernels dispatch on.
  -> .code(k)
    n = Transfer.kind(k)
    if n == :linear
      return 0
    if n == :srgb
      return 1
    if n == :bt709
      return 2
    3

  # IEC 61966-2-1 sRGB, display-referred. EOTF: V <= 0.04045 -> V / 12.92,
  # else ((V + 0.055) / 1.055)^2.4. The inverse uses the 0.0031308 breakpoint.
  -> .srgb_eotf(v)
    transfer_srgb_eotf(v.to_f)

  -> .srgb_inverse_eotf(l)
    transfer_srgb_inverse_eotf(l.to_f)

  # ITU-R BT.709-6 item 1.2, scene-referred (camera): V = 1.099 L^0.45 - 0.099
  # for 1 >= L >= 0.018, V = 4.500 L for 0.018 > L >= 0. With the published
  # constants the two pieces meet only to 2.5e-4 (0.0812 vs 0.081); the
  # inverse switches at 0.081 = 4.5 x 0.018, so L -> V -> L is exact.
  -> .bt709_oetf(l)
    transfer_bt709_oetf(l.to_f)

  -> .bt709_inverse_oetf(v)
    transfer_bt709_inverse_oetf(v.to_f)

  # ITU-R BT.1886 Annex 1, the reference display EOTF: L = a max(V + b, 0)^2.4,
  # a = (Lw^(1/2.4) - Lb^(1/2.4))^2.4, b = Lb^(1/2.4) / (Lw^(1/2.4) - Lb^(1/2.4)).
  # Lw and Lb are the white and black luminance (cd/m^2, or relative); the
  # defaults Lw = 1, Lb = 0 give the normalized L = V^2.4.
  -> .bt1886_eotf(v, lw = ~1.0, lb = ~0.0)
    transfer_bt1886_eotf(v.to_f, lw.to_f, lb.to_f)

  -> .bt1886_inverse_eotf(l, lw = ~1.0, lb = ~0.0)
    transfer_bt1886_inverse_eotf(l.to_f, lw.to_f, lb.to_f)

  # An sRGB display pixel -> the BT.1886 pixel that makes the same light:
  # decode with the sRGB EOTF, encode with the inverse BT.1886 EOTF. Above
  # the sRGB breakpoint this is exactly (V + 0.055) / 1.055.
  -> .srgb_to_bt1886(v)
    transfer_bt1886_inverse_eotf(transfer_srgb_eotf(v.to_f), ~1.0, ~0.0)

  -> .bt1886_to_srgb(v)
    transfer_srgb_inverse_eotf(transfer_bt1886_eotf(v.to_f, ~1.0, ~0.0))

  # Code value -> linear light, and back, for a kind.
  -> .decode(kind, v)
    transfer_decode(Transfer.code(kind), v.to_f)

  -> .encode(kind, l)
    transfer_encode(Transfer.code(kind), l.to_f)


# --------------------------------------------------------------------------
# Typed scalar kernels (also called per pixel by core/ycbcr.w).

-> transfer_srgb_eotf(v) (f64) f64
  if v <= ~0.04045
    v / ~12.92
  else
    Math.pow((v + ~0.055) / ~1.055, ~2.4)

-> transfer_srgb_inverse_eotf(l) (f64) f64
  if l <= ~0.0031308
    l * ~12.92
  else
    ~1.055 * Math.pow(l, ~1.0 / ~2.4) - ~0.055

-> transfer_bt709_oetf(l) (f64) f64
  if l < ~0.018
    ~4.5 * l
  else
    ~1.099 * Math.pow(l, ~0.45) - ~0.099

-> transfer_bt709_inverse_oetf(v) (f64) f64
  if v < ~0.081
    v / ~4.5
  else
    Math.pow((v + ~0.099) / ~1.099, ~1.0 / ~0.45)

-> transfer_bt1886_eotf(v, lw, lb) (f64 f64 f64) f64
  wr = Math.pow(lw, ~1.0 / ~2.4)
  br = Math.pow(lb, ~1.0 / ~2.4)
  a = Math.pow(wr - br, ~2.4)
  b = br / (wr - br)
  x = v + b
  if x < ~0.0
    x = ~0.0
  a * Math.pow(x, ~2.4)

-> transfer_bt1886_inverse_eotf(l, lw, lb) (f64 f64 f64) f64
  wr = Math.pow(lw, ~1.0 / ~2.4)
  br = Math.pow(lb, ~1.0 / ~2.4)
  a = Math.pow(wr - br, ~2.4)
  b = br / (wr - br)
  if l <= ~0.0
    return ~0.0 - b
  Math.pow(l / a, ~1.0 / ~2.4) - b

# kind codes: 0 linear, 1 sRGB, 2 BT.709 OETF, 3 BT.1886 (Lw = 1, Lb = 0)
-> transfer_decode(kind, v) (i64 f64) f64
  if kind == 1
    return transfer_srgb_eotf(v)
  if kind == 2
    return transfer_bt709_inverse_oetf(v)
  if kind == 3
    return transfer_bt1886_eotf(v, ~1.0, ~0.0)
  v

-> transfer_encode(kind, l) (i64 f64) f64
  if kind == 1
    return transfer_srgb_inverse_eotf(l)
  if kind == 2
    return transfer_bt709_oetf(l)
  if kind == 3
    return transfer_bt1886_inverse_eotf(l, ~1.0, ~0.0)
  l


# --------------------------------------------------------------------------
# 3x3 matrices as rows [[a, b, c], [d, e, f], [g, h, i]].

# SMPTE RP 177-1993: each primary's XYZ at Y = 1 is (x / y, 1, (1 - x - y) / y);
# scale the columns by S = P^-1 W so that RGB = (1, 1, 1) maps to the white W.
-> colorspace_rgb_to_xyz(p, w)
  xr = p[0] / p[1]
  zr = (~1.0 - p[0] - p[1]) / p[1]
  xg = p[2] / p[3]
  zg = (~1.0 - p[2] - p[3]) / p[3]
  xb = p[4] / p[5]
  zb = (~1.0 - p[4] - p[5]) / p[5]
  prim = [[xr, xg, xb], [~1.0, ~1.0, ~1.0], [zr, zg, zb]]
  white = [w[0] / w[1], ~1.0, (~1.0 - w[0] - w[1]) / w[1]]
  s = colorspace_apply3(colorspace_inverse3(prim), white)
  [[xr * s[0], xg * s[1], xb * s[2]], [s[0], s[1], s[2]], [zr * s[0], zg * s[1], zb * s[2]]]

-> colorspace_inverse3(m)
  a = m[0][0]
  b = m[0][1]
  c = m[0][2]
  d = m[1][0]
  e = m[1][1]
  f = m[1][2]
  g = m[2][0]
  h = m[2][1]
  k = m[2][2]
  co0 = e * k - f * h
  co1 = f * g - d * k
  co2 = d * h - e * g
  det = a * co0 + b * co1 + c * co2
  [[co0 / det, (c * h - b * k) / det, (b * f - c * e) / det],
   [co1 / det, (a * k - c * g) / det, (c * d - a * f) / det],
   [co2 / det, (b * g - a * h) / det, (a * e - b * d) / det]]

-> colorspace_mul3(a, b)
  out = []
  i = 0
  while i < 3
    row = []
    j = 0
    while j < 3
      row.push(a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j])
      j += 1
    out.push(row)
    i += 1
  out

-> colorspace_apply3(m, v)
  [m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
   m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
   m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2]]

-> colorspace_clip01(x)
  if x < ~0.0
    return ~0.0
  if x > ~1.0
    return ~1.0
  x

-> colorspace_close?(a, b)
  if a.size != b.size
    return false
  i = 0
  while i < a.size
    if (a[i] - b[i]).abs > ~0.000000000001
      return false
    i += 1
  true
