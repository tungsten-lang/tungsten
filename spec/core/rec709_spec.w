# Rec709 and Cicp (core/rec709.w): ITU-T H.273 code points, ffmpeg tags, and
# the optional colour-space chunks of PngEncoder (core/raster.w).
#
# Run:
#   bin/tungsten spec/core/rec709_spec.w
#   bin/tungsten run --interpret spec/core/rec709_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> part(list, start, n)
  out = []
  k = 0
  while k < n
    out.push(list[start + k])
    k += 1
  out

# ---- H.273 code points for SDR Rec.709 ----
check("colour primaries 1", Rec709.colour_primaries == 1)
check("transfer characteristics 1", Rec709.transfer_characteristics == 1)
check("matrix coefficients 1", Rec709.matrix_coefficients == 1)
check("video full range flag 0", Rec709.video_full_range_flag == 0)
check("Rec709.cicp", Rec709.cicp.to_a == [1, 1, 1, 0] && Cicp.rec709.to_a == [1, 1, 1, 0])
check("RGB pictures use matrix 0, full range", Cicp.for("rec709").to_a == [1, 1, 0, 1] && Cicp.for(:srgb).to_a == [1, 13, 0, 1])
check("Display P3 and linear", Cicp.for("display_p3").to_a == [12, 13, 0, 1] && Cicp.for(ColorSpace.linear_srgb).to_a == [1, 8, 0, 1])
check("rgb?", Cicp.for("srgb").rgb? && !Rec709.cicp.rgb?)
check("to_s", Rec709.cicp.to_s == "1/1/1/0")

# ---- ffmpeg tags ----
check("ffmpeg flags for an 8-bit master",
      Rec709.ffmpeg_flags == ["-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv"])
check("ffmpeg flags for 10-bit", Rec709.ffmpeg_flags("yuv420p10le").join(" ") == "-pix_fmt yuv420p10le -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv")
sited = Rec709.ffmpeg_flags("yuv420p", :left)
check("ffmpeg flags with chroma siting", sited.size == 12 && part(sited, 10, 2) == ["-chroma_sample_location", "left"])
check("ffmpeg names for sRGB RGB", Cicp.for("srgb").ffmpeg_flags == ["-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-colorspace", "rgb", "-color_range", "pc"])
check("ffmpeg names for P3", Cicp.ffmpeg_name(:primaries, 12) == "smpte432" && Cicp.ffmpeg_name(:transfer, 16) == "smpte2084" && Cicp.ffmpeg_name(:matrix, 9) == "bt2020nc")
check("pix_fmt", Rec709.pix_fmt == "yuv420p" && Rec709.pix_fmt(10) == "yuv420p10le" && Rec709.pix_fmt(8, :yuv422) == "yuv422p")
check("space and ycbcr", Rec709.space.name == "rec709" && Rec709.space.transfer == :bt1886 && Rec709.ycbcr(10).code_max == 1019)
check("frame", Rec709.frame(Raster.new(4, 2, 0xFFFFFF)).get(3, 1) == [235, 128, 128])

# ---- PNG: untagged output is unchanged ----
# The SHA-256 of PngEncoder output recorded at 84f6c57e6, before the colour
# tags. (Each encode costs the interpreter about 430 MB, so this spec keeps
# to three.)
r = Raster.new(37, 23, 0xFFFFFF)
y = 0
while y < 23
  x = 0
  while x < 37
    r.set(x, y, ((x * 7) % 256) * 65536 + ((y * 11) % 256) * 256 + ((x * y) % 256))
    x += 1
  y += 1
r.disc(18, 11, 6, 0x2266AA)
plain = r.to_png
check("untagged PNG is byte-identical", Digest.sha256(plain) == "08822618bb6810f14062aa5548328974e896ca77f37a7cc4a98e73a48943fab7" && plain.size == 422)
check("no tag, no chunks", PngEncoder.color_chunks(nil).size == 0)

# ---- PNG: tagged chunks ----
# Chunk types after IHDR (which ends at byte 33), in order.
-> chunk_types(png)
  out = []
  pos = 33
  while pos + 8 <= png.size
    n = ((png[pos] * 256 + png[pos + 1]) * 256 + png[pos + 2]) * 256 + png[pos + 3]
    t = [png[pos + 4], png[pos + 5], png[pos + 6], png[pos + 7]]
    name = (t.map -> (b) b.chr).join("")
    out.push(name)
    pos += 12 + n
  out

-> chunk_data(png, kind)
  pos = 33
  while pos + 8 <= png.size
    n = ((png[pos] * 256 + png[pos + 1]) * 256 + png[pos + 2]) * 256 + png[pos + 3]
    t = [png[pos + 4], png[pos + 5], png[pos + 6], png[pos + 7]].map -> (b) b.chr
    if t.join("") == kind
      return part(png, pos + 8, n)
    pos += 12 + n
  nil

# [type name, data bytes] for each chunk color_chunks makes.
-> chunks_of(tag)
  out = []
  list = PngEncoder.color_chunks(tag)
  k = 0
  while k < list.size
    code = list[k][0]
    name = [(code / 16777216) % 256, (code / 65536) % 256, (code / 256) % 256, code % 256].map -> (b) b.chr
    data = list[k][1]
    out.push([name.join(""), part(data, 0, data.size)])
    k += 1
  out

check("untagged chunks", chunk_types(plain) == ["IDAT", "IEND"])
tiny = Raster.new(4, 3, 0x2266AA)
tiny.set(1, 1, 0xFFC24B)
tagged = tiny.to_png(:rec709)
check("rec709 PNG: cHRM and cICP 1/1/0/1 after IHDR", chunk_types(tagged) == ["cHRM", "cICP", "IDAT", "IEND"] && chunk_data(tagged, "cICP") == [1, 1, 0, 1])
check("tagging leaves the pixel data alone", chunk_data(tagged, "IDAT") == chunk_data(tiny.to_png, "IDAT"))
srgb = chunks_of("srgb")
check("sRGB tag: cHRM, gAMA 45455, sRGB perceptual", srgb.map(-> (c) c[0]) == ["cHRM", "gAMA", "sRGB"] && srgb[1][1] == [0, 0, 177, 143] && srgb[2][1] == [0])
check("cHRM is white, red, green, blue x 100000", srgb[0][1].size == 32 && part(srgb[0][1], 0, 8) == [0, 0, 122, 38, 0, 0, 128, 132] && part(srgb[0][1], 8, 8) == [0, 0, 250, 0, 0, 0, 128, 232])
p3 = chunks_of(ColorSpace.display_p3)
check("display_p3 tag: cHRM, gAMA, cICP 12/13/0/1", p3.map(-> (c) c[0]) == ["cHRM", "gAMA", "cICP"] && p3[2][1] == [12, 13, 0, 1])
check("P3 cHRM red is 0.680, 0.320", part(p3[0][1], 8, 8) == [0, 1, 9, 160, 0, 0, 125, 0])
lin = chunks_of("linear_srgb")
check("linear_srgb tag: gAMA 100000, cICP 1/8/0/1", lin[1][1] == [0, 1, 134, 160] && lin[2][1] == [1, 8, 0, 1])
check("a Cicp writes cICP alone", chunks_of(Cicp.for("srgb")).map(-> (c) c[0]) == ["cICP"])
video = false
begin
  PngEncoder.color_chunks(Cicp.rec709)
rescue e
  video = e.message.include?("matrix coefficients 0")
check("a Y'CbCr Cicp is refused for PNG", video)

<< "ALL PASS rec709_spec ([passed.load()] checks)"
