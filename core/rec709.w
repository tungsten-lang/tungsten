# Rec709 — SDR HD video delivery in one place: the ITU-T H.273 code points
# that tag a stream as Rec.709, the matching ffmpeg flags, and shortcuts to
# the colour space, the Y'CbCr encoder and frame conversion.
# Cicp — an H.273 code-point quadruple (colour primaries, transfer
# characteristics, matrix coefficients, video full range flag), as carried by
# H.264 / HEVC / AV1 headers, the MP4 / MOV `colr` (nclx) box and PNG `cICP`.
#
#   Rec709.cicp.to_a                       # [1, 1, 1, 0]: Y'CbCr video, limited range
#   Rec709.ffmpeg_flags                    # ["-pix_fmt", "yuv420p", "-color_primaries", "bt709", ...]
#   Rec709.ffmpeg_flags("yuv420p10le")
#   f = Rec709.frame(raster)               # YuvFrame: 4:2:0, 8-bit, BT.709, limited range
#   Cicp.for("rec709").to_a                # [1, 1, 0, 1]: an RGB picture (PNG cICP)
#   Cicp.for("display_p3").to_a            # [12, 13, 0, 1]
#
# H.273 code points used here:
#   ColourPrimaries          1 BT.709 / sRGB    12 SMPTE EG 432-1 (P3, D65)
#   TransferCharacteristics  1 BT.709           8 linear    13 IEC 61966-2-1 (sRGB)
#   MatrixCoefficients       0 identity (RGB)   1 BT.709
#   VideoFullRangeFlag       0 limited ("tv")   1 full ("pc")
# H.273 names the BT.709 OETF for TransferCharacteristics 1 and leaves the
# display to BT.1886; players differ in what they do with it (doc/color.md).

use core/color_space
use core/ycbcr

# Cicp — an ITU-T H.273 code-point quadruple: primaries, transfer, matrix, range.
+ Cicp
  ro :primaries, :transfer, :matrix, :full_range

  -> new(@primaries, @transfer, @matrix, @full_range = 0)

  # SDR HD video: BT.709 primaries, transfer and Y'CbCr matrix, limited range.
  -> .rec709
    Cicp.new(1, 1, 1, 0)

  # An RGB picture (a PNG, a frame before Y'CbCr) in a colour space: matrix 0
  # (identity), full range. "rec709" gives 1/1/0/1.
  -> .for(space)
    n = ColorSpace.named(space).name
    if n == "rec709"
      return Cicp.new(1, 1, 0, 1)
    if n == "srgb"
      return Cicp.new(1, 13, 0, 1)
    if n == "display_p3"
      return Cicp.new(12, 13, 0, 1)
    Cicp.new(1, 8, 0, 1)

  # True for RGB code points (matrix 0).
  -> rgb?
    @matrix == 0

  -> to_a
    [@primaries, @transfer, @matrix, @full_range]

  -> to_s
    "[@primaries]/[@transfer]/[@matrix]/[@full_range]"

  # ffmpeg's output tags for these code points (names as `ffmpeg -h full` lists them).
  -> ffmpeg_flags
    ["-color_primaries", Cicp.ffmpeg_name(:primaries, @primaries),
     "-color_trc", Cicp.ffmpeg_name(:transfer, @transfer),
     "-colorspace", Cicp.ffmpeg_name(:matrix, @matrix),
     "-color_range", @full_range == 1 ? "pc" : "tv"]

  -> .ffmpeg_name(field, code)
    names = {}
    if field == :primaries
      names = {1 => "bt709", 4 => "bt470m", 5 => "bt470bg", 6 => "smpte170m", 7 => "smpte240m", 8 => "film", 9 => "bt2020", 10 => "smpte428", 11 => "smpte431", 12 => "smpte432", 22 => "jedec-p22"}
    elsif field == :transfer
      names = {1 => "bt709", 4 => "gamma22", 5 => "gamma28", 6 => "smpte170m", 7 => "smpte240m", 8 => "linear", 13 => "iec61966-2-1", 14 => "bt2020-10", 15 => "bt2020-12", 16 => "smpte2084", 18 => "arib-std-b67"}
    elsif field == :matrix
      names = {0 => "rgb", 1 => "bt709", 5 => "bt470bg", 6 => "smpte170m", 7 => "smpte240m", 9 => "bt2020nc", 10 => "bt2020c"}
    else
      raise ArgumentError, "ffmpeg_name: field must be :primaries, :transfer or :matrix"
    if !names.has_key?(code)
      raise ArgumentError, "ffmpeg_name: no ffmpeg name for [field] [code]"
    names[code]


# Rec709 — SDR HD video: H.273 code points, ffmpeg tags, frame shortcuts.
+ Rec709
  COLOUR_PRIMARIES = 1
  TRANSFER_CHARACTERISTICS = 1
  MATRIX_COEFFICIENTS = 1
  VIDEO_FULL_RANGE_FLAG = 0

  # The H.273 code points, by their H.273 names.
  -> .colour_primaries
    COLOUR_PRIMARIES

  -> .transfer_characteristics
    TRANSFER_CHARACTERISTICS

  -> .matrix_coefficients
    MATRIX_COEFFICIENTS

  -> .video_full_range_flag
    VIDEO_FULL_RANGE_FLAG

  -> .cicp
    Cicp.new(COLOUR_PRIMARIES, TRANSFER_CHARACTERISTICS, MATRIX_COEFFICIENTS, VIDEO_FULL_RANGE_FLAG)

  # Display-referred Rec.709: BT.709 primaries, D65, BT.1886 EOTF.
  -> .space
    ColorSpace.rec709

  -> .ycbcr(bits = 8)
    YCbCr.bt709(bits, :limited)

  # ffmpeg's pix_fmt for a bit depth and chroma format: yuv420p, yuv420p10le, ...
  -> .pix_fmt(bits = 8, chroma = :yuv420)
    YuvFrame.pix_fmt_for(chroma, bits)

  # ffmpeg output options that store and tag a stream as SDR Rec.709:
  # -pix_fmt <fmt> -color_primaries bt709 -color_trc bt709 -colorspace bt709
  # -color_range tv. The tags describe the pixels; they do not convert them.
  # With a siting (:left, :center, :topleft) it adds -chroma_sample_location;
  # untagged 4:2:0 is read as :left (H.264 / HEVC default).
  -> .ffmpeg_flags(pix_fmt = "yuv420p", siting = nil)
    flags = ["-pix_fmt", pix_fmt.to_s] + Rec709.cicp.ffmpeg_flags
    if siting != nil
      flags = flags + ["-chroma_sample_location", YuvFrame.siting_kind(siting).to_s]
    flags

  # A Raster (sRGB by default) as a Rec.709 Y'CbCr frame; options as
  # YuvFrame.from_raster (range and matrix default to limited and bt709).
  -> .frame(raster, opts = nil)
    YuvFrame.from_raster(raster, opts)
