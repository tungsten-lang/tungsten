# YCbCr and YuvFrame (core/ycbcr.w): BT.709 Y'CbCr, quantization, chroma
# subsampling, pixel packing and the round trip back to a Raster.
#
# Run:
#   bin/tungsten spec/core/ycbcr_spec.w
#   bin/tungsten run --interpret spec/core/ycbcr_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b, tol)
  (a - b).abs <= tol

q8 = YCbCr.bt709
q10 = YCbCr.bt709(10)

# ---- colour bars ----
# Codes computed from BT.709-6 items 3.2-3.4, checked against the published
# BT.709 colour-bar tables of SMPTE RP 219:2002 as reproduced in Wikipedia,
# "SMPTE color bars" (100% and 75% bars, 8- and 10-bit Y'CbCr). That table
# omits 100% green and magenta; those two are computed only.
bars = [[~1.0, ~1.0, ~1.0], [~1.0, ~1.0, ~0.0], [~0.0, ~1.0, ~1.0], [~0.0, ~1.0, ~0.0],
        [~1.0, ~0.0, ~1.0], [~1.0, ~0.0, ~0.0], [~0.0, ~0.0, ~1.0], [~0.0, ~0.0, ~0.0]]
names = ["white", "yellow", "cyan", "green", "magenta", "red", "blue", "black"]
want100 = [[235, 128, 128], [219, 16, 138], [188, 154, 16], [173, 42, 26],
           [78, 214, 230], [63, 102, 240], [32, 240, 118], [16, 128, 128]]
want100_10 = [[940, 512, 512], [877, 64, 553], [754, 615, 64], nil, nil, [250, 409, 960], [127, 960, 471], [64, 512, 512]]
want75 = [[180, 128, 128], [168, 44, 136], [145, 147, 44], [133, 63, 52],
          [63, 193, 204], [51, 109, 212], [28, 212, 120], [16, 128, 128]]
want75_10 = [[721, 512, 512], [674, 176, 543], [581, 589, 176], [534, 253, 207],
             [251, 771, 817], [204, 435, 848], [111, 848, 481], [64, 512, 512]]
i = 0
while i < 8
  c = bars[i]
  check("100% " + names[i] + " 8-bit", q8.encode(c[0], c[1], c[2]) == want100[i])
  if want100_10[i] != nil
    check("100% " + names[i] + " 10-bit", q10.encode(c[0], c[1], c[2]) == want100_10[i])
  check("75% " + names[i] + " 8-bit", q8.encode(~0.75 * c[0], ~0.75 * c[1], ~0.75 * c[2]) == want75[i])
  check("75% " + names[i] + " 10-bit", q10.encode(~0.75 * c[0], ~0.75 * c[1], ~0.75 * c[2]) == want75_10[i])
  i += 1

# ---- signals and levels (BT.709-6 items 3.2, 3.3, 4.6, 4.7) ----
e = q8.forward(~1.0, ~1.0, ~0.0)
check("yellow E'CB is -0.5", near(e[1], ~-0.5, ~0.000000000001))
check("1 - Kr, 1 - Kb give 1.5748 and 1.8556", near(~2.0 * (~1.0 - q8.kr), ~1.5748, ~0.0) && near(~2.0 * (~1.0 - q8.kb), ~1.8556, ~0.000000000001))
check("inverse undoes forward", near(q8.inverse(e[0], e[1], e[2])[0], ~1.0, ~0.000000000001) && near(q8.inverse(e[0], e[1], e[2])[2], ~0.0, ~0.000000000001))
check("8-bit limited scale", q8.luma_scale == 219 && q8.luma_offset == 16 && q8.chroma_scale == 224 && q8.chroma_offset == 128)
check("10-bit limited levels 64..940, 64..960", q10.encode(~0.0, ~0.0, ~0.0)[0] == 64 && q10.encode(~1.0, ~1.0, ~1.0)[0] == 940 && q10.encode(~0.0, ~0.0, ~1.0)[1] == 960)
q12 = YCbCr.bt709(12)
check("12-bit limited levels 256..3760", q12.encode(~0.0, ~0.0, ~0.0)[0] == 256 && q12.encode(~1.0, ~1.0, ~1.0) == [3760, 2048, 2048])
check("video-data ranges: 1..254, 4..1019, 16..4079", q8.code_min == 1 && q8.code_max == 254 && q10.code_min == 4 && q10.code_max == 1019 && q12.code_min == 16 && q12.code_max == 4079)
check("super-white clips to 254, not 255", q8.encode(~1.2, ~1.2, ~1.2)[0] == 254)
check("below-black clips to 1, not 0", q8.encode(~-0.2, ~-0.2, ~-0.2)[0] == 1)

# Full range (H.273 VideoFullRangeFlag = 1): (2^n - 1) E, chroma offset 2^(n-1).
f8 = YCbCr.bt709(8, :full)
check("full range white and black", f8.encode(~1.0, ~1.0, ~1.0) == [255, 128, 128] && f8.encode(~0.0, ~0.0, ~0.0) == [0, 128, 128])
check("full range yellow rounds half away from zero", f8.encode(~1.0, ~1.0, ~0.0) == [237, 1, 140])
check("full range blue Cb clips to 255", f8.encode(~0.0, ~0.0, ~1.0)[1] == 255)
check("10-bit full white", YCbCr.bt709(10, :full).encode(~1.0, ~1.0, ~1.0)[0] == 1023)
check("range names", YCbCr.range_kind("tv") == :limited && YCbCr.range_kind(:pc) == :full)

# BT.709 INT rounds fractions of one half up: 0.5 of the way gives the upper code.
half = (~125.5 - ~16.0) / ~219.0
check("INT rounds .5 up", q8.quantize(half, ~0.0, ~0.0)[0] == 126)

# ---- round trip R'G'B' -> Y'CbCr -> R'G'B' (4:4:4) ----
# 8-bit codes: |error in R'| <= 0.5/219 + 1.5748 * 0.5/224 (0.0058), in B'
# <= 0.5/219 + 1.8556 * 0.5/224 (0.0064), so 8-bit RGB comes back within
# 2 codes (1 for R and G). 10-bit: errors under 0.0016, i.e. under half an
# 8-bit code, so 8-bit RGB comes back exactly. The scalar API on a coarse
# grid here; the frame path on all 16^3 colours of the step-17 grid below.
max8 = 0
max8f = ~0.0
max10 = 0
r = 0
while r <= 255
  g = 0
  while g <= 255
    b = 0
    while b <= 255
      c8 = q8.encode_rgb8(r, g, b)
      back = q8.decode_rgb8(c8[0], c8[1], c8[2])
      d = [(back[0] - r).abs, (back[1] - g).abs, (back[2] - b).abs].max
      max8 = d if d > max8
      fl = q8.decode(c8[0], c8[1], c8[2])
      df = [(fl[0] - r / ~255.0).abs, (fl[1] - g / ~255.0).abs, (fl[2] - b / ~255.0).abs].max
      max8f = df if df > max8f
      c10 = q10.encode_rgb8(r, g, b)
      back10 = q10.decode_rgb8(c10[0], c10[1], c10[2])
      d10 = [(back10[0] - r).abs, (back10[1] - g).abs, (back10[2] - b).abs].max
      max10 = d10 if d10 > max10
      b += 51
    g += 51
  r += 51
check("8-bit round trip within 2 codes", max8 <= 2)
check("8-bit round trip within the quantization bound", max8f <= ~0.5 / ~219.0 + ~1.8556 * ~0.5 / ~224.0)
check("10-bit round trip of 8-bit RGB is exact", max10 == 0)
check("decode clamps to [0, 1]", q8.decode(235, 16, 16)[0] >= ~0.0 && q8.decode(235, 240, 240)[0] <= ~1.0)

# ---- frames: sizes ----
check("I420 1080p size", YuvFrame.byte_size("yuv420p", 1920, 1080) == 3110400)
check("NV12 1080p size", YuvFrame.byte_size("nv12", 1920, 1080) == 3110400)
check("P010 1080p size", YuvFrame.byte_size("p010le", 1920, 1080) == 6220800)
check("yuv420p10le 1080p size", YuvFrame.byte_size("yuv420p10le", 1920, 1080) == 6220800)
check("4:2:2 and 4:4:4 sizes", YuvFrame.byte_size("yuv422p", 1920, 1080) == 4147200 && YuvFrame.byte_size("yuv444p10le", 4, 2) == 48)
check("odd sizes round the chroma up", YuvFrame.byte_size("i420", 5, 3) == 15 + 2 * 6)
fr = YuvFrame.new(5, 3)
check("odd frame chroma planes", fr.chroma_width == 3 && fr.chroma_height == 2 && fr.cb.size == 6)
check("a new frame is black", fr.get(4, 2) == [16, 128, 128])
check("pix_fmt names", fr.pix_fmt == "yuv420p" && YuvFrame.new(2, 2, :yuv422, YCbCr.bt709(10)).pix_fmt == "yuv422p10le")

# ---- frames: chroma filters and siting ----
# A blue pixel at (0, 0) in yellow, 4 x 2. Under :left the first chroma
# sample filters x = -1 (repeated edge), 0, 1 by [1 2 1]/4 and rows 0, 1 by
# [1 1]/2; :center averages the 2 x 2 block; :topleft uses [1 2 1]/4 down too.
img = Raster.new(4, 2, 0xFFFF00)
img.set(0, 0, 0x0000FF)
left = YuvFrame.from_raster(img)
mix_left = q8.encode(~0.625, ~0.625, ~0.375)
check("left siting filter", left.get(0, 0) == [32, mix_left[1], mix_left[2]] && left.get(0, 0) == [32, 100, 131])
center = YuvFrame.from_raster(img, {siting: :center})
mix_center = q8.encode(~0.75, ~0.75, ~0.25)
check("center siting filter", center.get(1, 1)[1] == mix_center[1] && center.get(1, 1)[2] == mix_center[2])
topleft = YuvFrame.from_raster(img, {siting: :topleft})
mix_tl = q8.encode(~0.4375, ~0.4375, ~0.5625)
check("topleft siting filter", topleft.get(0, 0)[1] == mix_tl[1] && topleft.get(0, 0)[2] == mix_tl[2])
check("second chroma sample is pure yellow", left.get(2, 0)[1] == 16 && left.get(3, 1)[2] == 138)
f422 = YuvFrame.from_raster(img, {chroma: :yuv422})
check("4:2:2 filters rows separately", f422.chroma_height == 2 && f422.get(0, 1)[1] == 16 && f422.get(0, 0)[1] == q8.encode(~0.25, ~0.25, ~0.75)[1])

# ---- frames: packing layouts ----
t = Raster.new(4, 2, 0x000000)
t.set(0, 0, 0xFFFFFF)
t.set(2, 0, 0xFF0000)
t.set(3, 1, 0x0000FF)
f = YuvFrame.from_raster(t)
i420 = f.to_i420
check("I420 is Y, then Cb, then Cr", i420.size == 12 && i420[0] == f.y[0] && i420[8] == f.cb[0] && i420[9] == f.cb[1] && i420[10] == f.cr[0] && i420[11] == f.cr[1])
nv12 = f.to_nv12
check("NV12 interleaves Cb Cr after Y", nv12.size == 12 && nv12[7] == f.y[7] && nv12[8] == f.cb[0] && nv12[9] == f.cr[0] && nv12[10] == f.cb[1] && nv12[11] == f.cr[1])
g10 = YuvFrame.from_raster(t, {bits: 10})
p010 = g10.to_p010
y0 = g10.y[0] * 64
check("P010 keeps 10 bits in the high bits, little-endian", p010.size == 24 && p010[0] == y0 % 256 && p010[1] == y0 / 256)
cb0 = g10.cb[0] * 64
cr0 = g10.cr[0] * 64
check("P010 interleaves Cb Cr words", p010[16] == cb0 % 256 && p010[17] == cb0 / 256 && p010[18] == cr0 % 256 && p010[19] == cr0 / 256)
pl10 = g10.to_yuv420p10le
check("yuv420p10le keeps the low bits", pl10.size == 24 && pl10[0] == g10.y[0] % 256 && pl10[1] == g10.y[0] / 256 && pl10[16] == g10.cb[0] % 256)
wrong = false
begin
  f.to_p010
rescue err
  wrong = err.message.include?("p010le")
check("packing an 8-bit frame as P010 raises", wrong)

# Packing then unpacking gives the same planes for every layout.
-> same_planes(a, b)
  n = a.width * a.height
  k = 0
  while k < n
    return false if a.y[k] != b.y[k]
    k += 1
  k = 0
  while k < a.chroma_width * a.chroma_height
    return false if a.cb[k] != b.cb[k] || a.cr[k] != b.cr[k]
    k += 1
  true

img2 = Raster.new(6, 4, 0x204060)
img2.set(1, 1, 0xF0E0D0)
img2.set(4, 2, 0x10FF30)
img2.set(5, 3, 0xFF00FF)
layouts = [["yuv420p", nil], ["nv12", nil], ["yuv422p", {chroma: :yuv422}], ["nv16", {chroma: :yuv422}],
           ["yuv444p", {chroma: :yuv444}], ["yuv420p10le", {bits: 10}], ["p010le", {bits: 10}],
           ["p210le", {chroma: :yuv422, bits: 10}], ["yuv444p12le", {chroma: :yuv444, bits: 12}]]
k = 0
while k < layouts.size
  fmt = layouts[k][0]
  fa = YuvFrame.from_raster(img2, layouts[k][1])
  fb = YuvFrame.from_bytes(fa.to_bytes(fmt), fmt, 6, 4)
  check("pack and unpack " + fmt, same_planes(fa, fb) && fb.pix_fmt == fa.pix_fmt)
  k += 1

# ---- frames: back to a Raster ----
-> max_diff(a, b)
  m = 0
  k = 0
  while k < a.width * a.height
    pa = a.pixels[k]
    pb = b.pixels[k]
    d = [((pa / 65536) % 256 - (pb / 65536) % 256).abs, ((pa / 256) % 256 - (pb / 256) % 256).abs, (pa % 256 - pb % 256).abs].max
    m = d if d > m
    k += 1
  m

grid = Raster.new(64, 64, 0)
k = 0
while k < 4096
  grid.pixels[k] = ((k / 256) * 17) * 65536 + (((k / 16) % 16) * 17) * 256 + (k % 16) * 17
  k += 1
check("16^3 colours: 4:4:4 8-bit round trip within 2 codes", max_diff(grid, YuvFrame.from_raster(grid, {chroma: :yuv444}).to_raster) <= 2)
check("16^3 colours: 4:4:4 10-bit round trip is exact", max_diff(grid, YuvFrame.from_raster(grid, {chroma: :yuv444, bits: 10}).to_raster) == 0)
check("4:4:4 8-bit frame round trip within 2 codes", max_diff(img2, YuvFrame.from_raster(img2, {chroma: :yuv444}).to_raster) <= 2)
check("4:4:4 10-bit frame round trip is exact", max_diff(img2, YuvFrame.from_raster(img2, {chroma: :yuv444, bits: 10}).to_raster) == 0)
flat = Raster.new(6, 4, 0x3A7FC4)
check("a flat 4:2:0 frame round trips exactly at 10 bits", max_diff(flat, YuvFrame.from_raster(flat, {bits: 10}).to_raster) == 0)
check("a flat 4:2:0 frame via I420 bytes round trips within 2 codes", max_diff(flat, YuvFrame.from_bytes(YuvFrame.from_raster(flat).to_i420, "i420", 6, 4).to_raster) <= 2)

# ---- RGBA bytes ----
rgba = u8[6 * 4 * 4]
bgra = u8[6 * 4 * 4]
k = 0
while k < 24
  c = img2.pixels[k]
  rgba[4 * k] = (c / 65536) % 256
  rgba[4 * k + 1] = (c / 256) % 256
  rgba[4 * k + 2] = c % 256
  rgba[4 * k + 3] = 255
  bgra[4 * k] = c % 256
  bgra[4 * k + 1] = (c / 256) % 256
  bgra[4 * k + 2] = (c / 65536) % 256
  bgra[4 * k + 3] = 255
  k += 1
from_r = YuvFrame.from_raster(img2)
check("RGBA bytes give the same frame as the Raster", same_planes(from_r, YuvFrame.from_rgba(rgba, 6, 4)))
check("BGRA bytes too", same_planes(from_r, YuvFrame.from_rgba(bgra, 6, 4, {order: :bgra})))

# ---- transfer: pass-through vs BT.1886 ----
grey = Raster.new(2, 2, 0x808080)
check("pass-through keeps the sRGB code value", YuvFrame.from_raster(grey).get(0, 0)[0] == 126)
check("BT.1886 re-encodes sRGB 128 as Y' 132", YuvFrame.from_raster(grey, {transfer: :bt1886}).get(0, 0)[0] == 132)
shadow = Raster.new(2, 2, 0x0A0A0A)
check("BT.1886 lifts sRGB 10 from Y' 25 to 36", YuvFrame.from_raster(shadow).get(0, 0)[0] == 25 && YuvFrame.from_raster(shadow, {transfer: :bt1886}).get(0, 0)[0] == 36)
check("a BT.1886 frame decodes back to the sRGB pixel", YuvFrame.from_raster(grey, {transfer: :bt1886, bits: 10}).to_raster.get(1, 1) == 0x808080)
check("the frame remembers its transfer", YuvFrame.from_raster(grey, {transfer: :bt1886}).transfer == :bt1886 && YuvFrame.from_raster(grey).transfer == :srgb)

# ---- a Display P3 source ----
p3red = Raster.new(2, 2, 0xFF0000)
check("P3 red clips to BT.709 red", YuvFrame.from_raster(p3red, {source: "display_p3"}).get(0, 0) == [63, 102, 240])
check("P3 grey is unchanged", YuvFrame.from_raster(grey, {source: :display_p3}).get(0, 0)[0] == 126)
# sRGB red in Display P3 is about (0.9175, 0.2003, 0.1386): 8-bit (234, 51, 35).
pr = YuvFrame.from_raster(p3red, {bits: 10}).to_raster("display_p3").get(0, 0)
check("a frame decodes to Display P3", ((pr / 65536) % 256 - 234).abs <= 1 && ((pr / 256) % 256 - 51).abs <= 1 && (pr % 256 - 35).abs <= 1)

<< "ALL PASS ycbcr_spec ([passed.load()] checks)"
