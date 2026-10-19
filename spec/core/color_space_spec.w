# ColorSpace and Transfer (core/color_space.w): RGB <-> XYZ matrices derived
# from the primaries, conversion between spaces, and the sRGB, BT.709 and
# BT.1886 transfer functions.
#
# Run:
#   bin/tungsten spec/core/color_space_spec.w
#   bin/tungsten run --interpret spec/core/color_space_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b, tol)
  (a - b).abs <= tol

-> matrix_near(m, want, tol)
  i = 0
  while i < 3
    j = 0
    while j < 3
      if !near(m[i][j], want[i][j], tol)
        return false
      j += 1
    i += 1
  true

# ---- RGB -> XYZ derived from the chromaticities (SMPTE RP 177-1993) ----
srgb = ColorSpace.srgb
rec709 = ColorSpace.rec709
p3 = ColorSpace.display_p3

# The 4-decimal matrix printed in IEC 61966-2-1:1999 (sRGB) for BT.709
# primaries and D65; the derived matrix rounds to it.
iec = [[~0.4124, ~0.3576, ~0.1805], [~0.2126, ~0.7152, ~0.0722], [~0.0193, ~0.1192, ~0.9505]]
check("BT.709 RGB->XYZ rounds to the published 4-decimal matrix", matrix_near(rec709.to_xyz, iec, ~0.00005))
check("sRGB and Rec.709 share the matrix", matrix_near(srgb.to_xyz, rec709.to_xyz, ~0.0))

# CSS Color 4 (W3C, "Sample code for color conversions") gives the same
# matrices as exact rationals, derived the same way.
css_srgb = [[~506752.0 / ~1228815.0, ~87881.0 / ~245763.0, ~12673.0 / ~70218.0],
            [~87098.0 / ~409605.0, ~175762.0 / ~245763.0, ~12673.0 / ~175545.0],
            [~7918.0 / ~409605.0, ~87881.0 / ~737289.0, ~1001167.0 / ~1053270.0]]
check("sRGB RGB->XYZ matches CSS Color 4 to 1e-9", matrix_near(srgb.to_xyz, css_srgb, ~0.000000001))
css_p3 = [[~608311.0 / ~1250200.0, ~189793.0 / ~714400.0, ~198249.0 / ~1000160.0],
          [~35783.0 / ~156275.0, ~247089.0 / ~357200.0, ~198249.0 / ~2500400.0],
          [~0.0, ~32229.0 / ~714400.0, ~5220557.0 / ~5000800.0]]
check("Display P3 RGB->XYZ matches CSS Color 4 to 1e-9", matrix_near(p3.to_xyz, css_p3, ~0.000000001))

# IEC 61966-2-1 prints the inverse of its rounded forward matrix, so the exact
# inverse agrees with it only to about 4e-4.
iec_inv = [[~3.2406, ~-1.5372, ~-0.4986], [~-0.9689, ~1.8758, ~0.0415], [~0.0557, ~-0.2040, ~1.0570]]
check("XYZ->RGB agrees with the published inverse to 5e-4", matrix_near(rec709.from_xyz, iec_inv, ~0.0005))
ident = [[~1.0, ~0.0, ~0.0], [~0.0, ~1.0, ~0.0], [~0.0, ~0.0, ~1.0]]
check("from_xyz is the inverse of to_xyz", matrix_near(colorspace_mul3(rec709.from_xyz, rec709.to_xyz), ident, ~0.000000000001))
white = colorspace_apply3(rec709.to_xyz, [~1.0, ~1.0, ~1.0])
check("RGB white is D65 with Y = 1", near(white[0], ~0.3127 / ~0.3290, ~0.000000000001) && near(white[1], ~1.0, ~0.000000000001))

# BT.709-6 item 3.2's luma coefficients are the Y row, rounded.
lw = rec709.luma_weights
check("luma weights round to 0.2126, 0.7152, 0.0722", near(lw[0], ~0.2126, ~0.00005) && near(lw[1], ~0.7152, ~0.00005) && near(lw[2], ~0.0722, ~0.00005))

# ---- conversion between spaces ----
check("same primaries give the identity", matrix_near(srgb.matrix_to(:rec709), ident, ~0.000000000001))
p3_to_709 = [[~1.2249, ~-0.2249, ~0.0], [~-0.0421, ~1.0421, ~0.0], [~-0.0196, ~-0.0786, ~1.0983]]
check("Display P3 -> BT.709 linear matrix", matrix_near(p3.matrix_to(rec709), p3_to_709, ~0.00005))
check("P3 white stays white", near(p3.convert([~1.0, ~1.0, ~1.0], :srgb)[1], ~1.0, ~0.000000001))
red = p3.convert([~1.0, ~0.0, ~0.0], "srgb")
check("P3 red is outside BT.709 and clips to sRGB red", near(red[0], ~1.0, ~0.000000000001) && near(red[1], ~0.0, ~0.000000000001) && near(red[2], ~0.0, ~0.000000000001))
check("sRGB -> rec709 is the sRGB -> BT.1886 pixel conversion", near(srgb.convert([~0.5, ~0.5, ~0.5], :rec709)[0], Transfer.srgb_to_bt1886(~0.5), ~0.0))
check("named accepts strings, symbols and spaces", ColorSpace.named("display_p3").name == "display_p3" && ColorSpace.named(:rec709).transfer == :bt1886 && ColorSpace.named(p3).name == "display_p3")
check("names", ColorSpace.names == ["srgb", "rec709", "display_p3", "linear_srgb"])
check("with_transfer keeps the primaries", rec709.with_transfer(:bt709).transfer == :bt709 && rec709.with_transfer(:bt709).same_primaries?(srgb))
unknown = false
begin
  ColorSpace.named("adobe_rgb")
rescue e
  unknown = e.message.include?("adobe_rgb")
check("an unknown name raises", unknown)

# ---- BT.709 OETF (ITU-R BT.709-6 item 1.2) ----
check("OETF(0) = 0 and OETF(1) = 1", near(Transfer.bt709_oetf(~0.0), ~0.0, ~0.0) && near(Transfer.bt709_oetf(~1.0), ~1.0, ~0.000000000001))
check("OETF linear segment is 4.5 L", near(Transfer.bt709_oetf(~0.01), ~0.045, ~0.000000000001))
check("OETF power segment", near(Transfer.bt709_oetf(~0.5), ~1.099 * Math.pow(~0.5, ~0.45) - ~0.099, ~0.000000000001))
# The published constants make the pieces meet to within 2.5e-4 at L = 0.018
# (exact continuity needs BT.2020's 1.0993 / 0.0181).
below = ~4.5 * ~0.018
above = Transfer.bt709_oetf(~0.018)
check("OETF is continuous at the 0.018 breakpoint to 2.5e-4", near(above, below, ~0.00025))
check("OETF is increasing across the breakpoint", Transfer.bt709_oetf(~0.0179999) < Transfer.bt709_oetf(~0.018))
ok = true
l = ~0.0
while l <= ~1.0
  ok = ok && near(Transfer.bt709_inverse_oetf(Transfer.bt709_oetf(l)), l, ~0.000000000001)
  l += ~0.0125
check("inverse OETF round-trips", ok && near(Transfer.bt709_inverse_oetf(~0.081), ~0.018, ~0.0002))

# ---- sRGB (IEC 61966-2-1) ----
check("sRGB EOTF endpoints", near(Transfer.srgb_eotf(~0.0), ~0.0, ~0.0) && near(Transfer.srgb_eotf(~1.0), ~1.0, ~0.000000000001))
check("sRGB EOTF at 0.5", near(Transfer.srgb_eotf(~0.5), Math.pow(~0.555 / ~1.055, ~2.4), ~0.000000000001) && near(Transfer.srgb_eotf(~0.5), ~0.2140411, ~0.0000001))
check("sRGB EOTF is continuous at 0.04045", near(Transfer.srgb_eotf(~0.04045), Math.pow(~0.09545 / ~1.055, ~2.4), ~0.0000001))
check("sRGB inverse breakpoint", near(Transfer.srgb_inverse_eotf(~0.0031308), ~0.04045, ~0.0000001))
ok = true
v = ~0.0
while v <= ~1.0
  ok = ok && near(Transfer.srgb_inverse_eotf(Transfer.srgb_eotf(v)), v, ~0.000000000001)
  v += ~0.0125
check("sRGB round-trips", ok)
check("integers and decimals are accepted", near(Transfer.srgb_eotf(1), ~1.0, ~0.000000000001) && near(Transfer.srgb_eotf(0.5), Transfer.srgb_eotf(~0.5), ~0.0))

# ---- BT.1886 (Annex 1) ----
check("BT.1886 default is V^2.4", near(Transfer.bt1886_eotf(~0.5), Math.pow(~0.5, ~2.4), ~0.000000000001))
check("BT.1886 with Lw, Lb hits black and white", near(Transfer.bt1886_eotf(~0.0, ~100.0, ~0.1), ~0.1, ~0.000000001) && near(Transfer.bt1886_eotf(~1.0, ~100.0, ~0.1), ~100.0, ~0.000000001))
check("BT.1886 inverse with Lw, Lb", near(Transfer.bt1886_inverse_eotf(Transfer.bt1886_eotf(~0.37, ~100.0, ~0.1), ~100.0, ~0.1), ~0.37, ~0.000000001))
check("BT.1886 clamps below black", near(Transfer.bt1886_eotf(~-0.2), ~0.0, ~0.0))

# ---- sRGB display pixel -> BT.1886 pixel ----
check("sRGB -> BT.1886 keeps 0 and 1", near(Transfer.srgb_to_bt1886(~0.0), ~0.0, ~0.0) && near(Transfer.srgb_to_bt1886(~1.0), ~1.0, ~0.000000000001))
check("sRGB -> BT.1886 above the breakpoint is (V + 0.055) / 1.055", near(Transfer.srgb_to_bt1886(~0.5), ~0.555 / ~1.055, ~0.000000000001) && near(Transfer.srgb_to_bt1886(~0.2), ~0.255 / ~1.055, ~0.000000000001))
check("sRGB -> BT.1886 at the sRGB breakpoint", near(Transfer.srgb_to_bt1886(~0.04045), Math.pow(~0.0031308, ~1.0 / ~2.4), ~0.000001))
# Deep shadows lift a lot: sRGB's linear toe gives more light than gamma 2.4.
check("sRGB 10/255 -> BT.1886 0.0893", near(Transfer.srgb_to_bt1886(~10.0 / ~255.0), ~0.0893, ~0.0001))
check("BT.1886 -> sRGB inverts it", near(Transfer.bt1886_to_srgb(Transfer.srgb_to_bt1886(~0.3)), ~0.3, ~0.000000000001))

# ---- generic decode / encode by kind ----
check("decode by kind", near(Transfer.decode(:bt709, ~0.5), Transfer.bt709_inverse_oetf(~0.5), ~0.0) && near(Transfer.decode("linear", ~0.25), ~0.25, ~0.0))
check("encode by kind", near(Transfer.encode(:bt1886, ~0.25), Math.pow(~0.25, ~1.0 / ~2.4), ~0.000000000001))
check("kinds", Transfer.kinds == [:srgb, :bt709, :bt1886, :linear])

<< "ALL PASS color_space_spec ([passed.load()] checks)"
