# YCbCr — R'G'B' <-> Y'CbCr per ITU-R BT.709-6 (Kr = 0.2126, Kb = 0.0722),
# with integer quantization for 8, 10 and 12 bits in limited ("video") or full
# range. YuvFrame — a whole picture as Y'CbCr planes (4:2:0, 4:2:2 or 4:4:4),
# built from a Raster or RGBA bytes and packed as I420, NV12, P010 and the
# other planar / bi-planar layouts encoders take, and back.
#
#   q = YCbCr.bt709                       # 8-bit limited range
#   q.encode(~1.0, ~1.0, ~0.0)            # yellow -> [219, 16, 138]
#   q.decode(219, 16, 138)                # -> R'G'B' in [0, 1]
#
#   f = YuvFrame.from_raster(raster)      # 4:2:0, 8-bit, BT.709, limited, "left" siting
#   File.write_bytes("frame.yuv", f.to_i420)
#   f10 = YuvFrame.from_raster(raster, {bits: 10})
#   p010 = f10.to_p010
#   back = YuvFrame.from_bytes(p010, "p010le", raster.width, raster.height).to_raster
#
# Signals (BT.709-6 items 3.2 and 3.3): E'Y = Kr E'R + Kg E'G + Kb E'B,
# E'CB = (E'B - E'Y) / (2 (1 - Kb)), E'CR = (E'R - E'Y) / (2 (1 - Kr)).
#
# Quantization to n bits:
#   limited  D'Y = INT[(219 E'Y + 16) 2^(n-8)], D'C = INT[(224 E'C + 128) 2^(n-8)]
#            (BT.709-6 item 3.4: 8-bit Y' 16..235, C 16..240; 10-bit 64..940, 64..960)
#   full     D'Y = Round((2^n - 1) E'Y), D'C = Round((2^n - 1) E'C + 2^(n-1))
#            (ITU-T H.273, VideoFullRangeFlag = 1)
# INT and Round both round halves away from zero (BT.709-6 note 2 to item 3.4;
# H.273 Round). Limited-range codes are clipped to the video-data range of
# BT.709-6 item 4.7 (8-bit 1..254, 10-bit 4..1019, 12-bit 16..4079: the rest are
# timing references); full-range codes to 0..2^n - 1. The inverse clamps the
# reconstructed R'G'B' to [0, 1].
#
# Chroma subsampling filters a full-resolution picture before decimating, in
# R'G'B' (the colour-difference signals are linear in R'G'B', so this equals
# filtering Cb and Cr). Each axis that is halved uses, by chroma siting:
#   co-sited with a luma sample   [1 2 1] / 4 centred on it
#   midway between two samples    [1 1] / 2 of the two
# with edge samples repeated. Sitings (H.264/HEVC chroma_sample_loc_type):
#   :left     (0, the H.264 / HEVC / MPEG-2 default) 4:2:0 co-sited
#             horizontally, midway vertically; 4:2:2 co-sited (BT.709-6 item 4.3)
#   :center   (1, MPEG-1 / JPEG) midway on both axes
#   :topleft  (2, BT.2020's 4:2:0) co-sited on both axes
# Upsampling back interpolates linearly between the two nearest chroma
# samples on each axis, at the same sites.
#
# Colour: a frame's R'G'B' are code values with a stated transfer. The
# default, transfer: :passthrough, keeps the source pixels' sRGB code values
# (what an sRGB display shows) and only applies the BT.709 matrix: what
# ffmpeg does for an sRGB PNG tagged bt709, and what players show unchanged.
# transfer: :bt1886 re-encodes them for a BT.1886 reference display (decode
# with the source's EOTF, encode with the inverse BT.1886 EOTF); :bt709 uses
# the camera OETF. doc/color.md compares them. A source with other primaries
# (Display P3) is converted to BT.709 primaries in linear light and clipped.

use core/color_space

# YCbCr — R'G'B' <-> Y'CbCr for a matrix (Kr, Kb), bit depth and range.
+ YCbCr
  ro :kr, :kb, :bits, :range

  -> new(@kr = ~0.2126, @kb = ~0.0722, @bits = 8, @range = :limited)
    @range = YCbCr.range_kind(@range)
    if @bits < 8 || @bits > 16
      raise ArgumentError, "YCbCr: bits must be 8..16, got [@bits]"

  # ITU-R BT.709-6 item 3.2.
  -> .bt709(bits = 8, range = :limited)
    YCbCr.new(~0.2126, ~0.0722, bits, range)

  # ITU-R BT.601-7 (SD); for reading streams tagged smpte170m / bt470bg.
  -> .bt601(bits = 8, range = :limited)
    YCbCr.new(~0.299, ~0.114, bits, range)

  # ITU-R BT.2020-2 non-constant luminance.
  -> .bt2020(bits = 10, range = :limited)
    YCbCr.new(~0.2627, ~0.0593, bits, range)

  -> .matrix(name, bits = 8, range = :limited)
    n = name.to_s
    if n == "bt709"
      return YCbCr.bt709(bits, range)
    if n == "bt601"
      return YCbCr.bt601(bits, range)
    if n == "bt2020"
      return YCbCr.bt2020(bits, range)
    raise ArgumentError, "unknown Y'CbCr matrix '[n]': expected bt709, bt601 or bt2020"

  -> .range_kind(r)
    n = r.to_s
    if n == "limited" || n == "tv" || n == "video"
      return :limited
    if n == "full" || n == "pc"
      return :full
    raise ArgumentError, "unknown range '[n]': expected :limited or :full"

  -> kg
    ~1.0 - @kr - @kb

  -> full?
    @range == :full

  -> to_s
    "Y'CbCr Kr=[@kr] Kb=[@kb] [@bits]-bit [@range]"

  # The quantization: code = Round(scale E + offset), clipped to [code_min, code_max].
  -> luma_scale
    if full?
      return ycbcr_pow2(@bits) - 1
    219 * ycbcr_pow2(@bits - 8)

  -> luma_offset
    if full?
      return 0
    16 * ycbcr_pow2(@bits - 8)

  -> chroma_scale
    if full?
      return ycbcr_pow2(@bits) - 1
    224 * ycbcr_pow2(@bits - 8)

  -> chroma_offset
    if full?
      return ycbcr_pow2(@bits - 1)
    128 * ycbcr_pow2(@bits - 8)

  -> code_min
    if full?
      return 0
    ycbcr_pow2(@bits - 8)

  -> code_max
    if full?
      return ycbcr_pow2(@bits) - 1
    ycbcr_pow2(@bits) - 1 - ycbcr_pow2(@bits - 8)

  # [E'Y, E'CB, E'CR] from R'G'B' (E'Y in [0, 1], E'CB and E'CR in [-0.5, 0.5]).
  -> forward(r, g, b)
    rf = r.to_f
    gf = g.to_f
    bf = b.to_f
    y = @kr * rf + kg * gf + @kb * bf
    [y, (bf - y) / (~2.0 * (~1.0 - @kb)), (rf - y) / (~2.0 * (~1.0 - @kr))]

  # R'G'B' from E'Y, E'CB, E'CR, without clamping.
  -> inverse(y, cb, cr)
    yf = y.to_f
    r = yf + ~2.0 * (~1.0 - @kr) * cr.to_f
    b = yf + ~2.0 * (~1.0 - @kb) * cb.to_f
    [r, (yf - @kr * r - @kb * b) / kg, b]

  # Integer codes [Y', Cb, Cr] for E'Y, E'CB, E'CR.
  -> quantize(y, cb, cr)
    lo = code_min
    hi = code_max
    [ycbcr_code(y.to_f, luma_scale.to_f, luma_offset.to_f, lo, hi),
     ycbcr_code(cb.to_f, chroma_scale.to_f, chroma_offset.to_f, lo, hi),
     ycbcr_code(cr.to_f, chroma_scale.to_f, chroma_offset.to_f, lo, hi)]

  -> dequantize(yc, cbc, crc)
    [(yc.to_f - luma_offset) / luma_scale, (cbc.to_f - chroma_offset) / chroma_scale, (crc.to_f - chroma_offset) / chroma_scale]

  # R'G'B' in [0, 1] -> codes.
  -> encode(r, g, b)
    e = forward(r, g, b)
    quantize(e[0], e[1], e[2])

  # Codes -> R'G'B', clamped to [0, 1].
  -> decode(yc, cbc, crc)
    e = dequantize(yc, cbc, crc)
    rgb = inverse(e[0], e[1], e[2])
    [colorspace_clip01(rgb[0]), colorspace_clip01(rgb[1]), colorspace_clip01(rgb[2])]

  # 8-bit R'G'B' (0..255) -> codes, and codes -> 8-bit R'G'B'.
  -> encode_rgb8(r, g, b)
    encode(r.to_f / ~255.0, g.to_f / ~255.0, b.to_f / ~255.0)

  -> decode_rgb8(yc, cbc, crc)
    rgb = decode(yc, cbc, crc)
    [ycbcr_round(rgb[0] * ~255.0), ycbcr_round(rgb[1] * ~255.0), ycbcr_round(rgb[2] * ~255.0)]

  # Kernel parameters: [kr, kg, kb, luma scale, luma offset, chroma scale, chroma offset].
  -> coefficients
    out = f64[7]
    out[0] = @kr
    out[1] = kg
    out[2] = @kb
    out[3] = luma_scale.to_f
    out[4] = luma_offset.to_f
    out[5] = chroma_scale.to_f
    out[6] = chroma_offset.to_f
    out


# --------------------------------------------------------------------------

# YuvFrame — a picture as Y'CbCr planes (u16 codes, row-major, no padding).
+ YuvFrame
  ro :width, :height, :chroma, :siting, :transfer, :ycbcr, :y, :cb, :cr, :chroma_width, :chroma_height

  # A black frame. chroma: :yuv420, :yuv422 or :yuv444; siting: :left,
  # :center or :topleft; transfer: what its R'G'B' code values mean
  # (:srgb for pass-through, :bt1886 or :bt709).
  -> new(@width, @height, chroma = :yuv420, @ycbcr = YCbCr.bt709, siting = :left, transfer = :srgb)
    @chroma = YuvFrame.chroma_kind(chroma)
    @siting = YuvFrame.siting_kind(siting)
    @transfer = YuvFrame.transfer_kind(transfer)
    @chroma_width = (@width + YuvFrame.h_sub(@chroma) - 1) / YuvFrame.h_sub(@chroma)
    @chroma_height = (@height + YuvFrame.v_sub(@chroma) - 1) / YuvFrame.v_sub(@chroma)
    @y = u16[@width * @height]
    @cb = u16[@chroma_width * @chroma_height]
    @cr = u16[@chroma_width * @chroma_height]
    yuv_fill(@y, @width * @height, @ycbcr.luma_offset)
    yuv_fill(@cb, @chroma_width * @chroma_height, @ycbcr.chroma_offset)
    yuv_fill(@cr, @chroma_width * @chroma_height, @ycbcr.chroma_offset)

  -> .chroma_kind(c)
    n = c.to_s
    if n == "yuv420" || n == "420"
      return :yuv420
    if n == "yuv422" || n == "422"
      return :yuv422
    if n == "yuv444" || n == "444"
      return :yuv444
    raise ArgumentError, "unknown chroma format '[n]': expected :yuv420, :yuv422 or :yuv444"

  -> .siting_kind(s)
    n = s.to_s
    if n == "left" || n == "center" || n == "topleft"
      return n.to_sym
    raise ArgumentError, "unknown chroma siting '[n]': expected :left, :center or :topleft"

  # :passthrough names the sRGB curve: the source's sRGB code values are kept.
  -> .transfer_kind(t)
    if t.to_s == "passthrough"
      return :srgb
    Transfer.kind(t)

  -> .h_sub(chroma)
    chroma == :yuv444 ? 1 : 2

  -> .v_sub(chroma)
    chroma == :yuv420 ? 2 : 1

  -> .option(opts, key, fallback)
    if opts == nil || !opts.has_key?(key)
      return fallback
    opts[key]

  # Options: chroma (:yuv420), bits (8), range (:limited), matrix (:bt709),
  # siting (:left), source ("srgb": the raster's colour space), transfer
  # (:passthrough, :bt1886 or :bt709).
  -> .from_raster(raster, opts = nil)
    YuvFrame.from_pixels(raster.pixels, raster.width, raster.height, opts)

  # Packed 8-bit RGBA (order: :rgba, default) or BGRA (order: :bgra) bytes,
  # `stride` bytes per row (default width * 4). Alpha is ignored: composite
  # onto an opaque background first. Other options as for from_raster.
  -> .from_rgba(bytes, width, height, opts = nil)
    order = YuvFrame.option(opts, :order, :rgba).to_s
    stride = YuvFrame.option(opts, :stride, width * 4)
    if order != "rgba" && order != "bgra"
      raise ArgumentError, "from_rgba: order must be :rgba or :bgra, got '[order]'"
    if bytes.size < stride * (height - 1) + width * 4
      raise ArgumentError, "from_rgba: [bytes.size] bytes is too few for [width]x[height] at stride [stride]"
    px = i64[width * height]
    roff = order == "rgba" ? 0 : 2
    yuv_pack_rgba(bytes, width, height, stride, roff, 1, 2 - roff, px)
    YuvFrame.from_pixels(px, width, height, opts)

  # Packed 0xRRGGBB pixels (Raster#pixels), as from_raster.
  -> .from_pixels(px, width, height, opts = nil)
    q = YCbCr.matrix(YuvFrame.option(opts, :matrix, :bt709), YuvFrame.option(opts, :bits, 8), YuvFrame.option(opts, :range, :limited))
    f = YuvFrame.new(width, height, YuvFrame.option(opts, :chroma, :yuv420), q, YuvFrame.option(opts, :siting, :left), YuvFrame.option(opts, :transfer, :passthrough))
    f.encode_pixels(px, ColorSpace.named(YuvFrame.option(opts, :source, "srgb")))
    f

  # Fill the planes from packed 0xRRGGBB pixels in colour space `source`.
  -> encode_pixels(px, source)
    target = ColorSpace.rec709.with_transfer(@transfer)
    shift = 8
    mask = 255
    scale = ~0.0
    lut = f64[256]
    src = px
    if source.same_primaries?(target)
      k = 0
      while k < 256
        v = k.to_f / ~255.0
        if source.transfer != @transfer
          v = Transfer.encode(@transfer, Transfer.decode(source.transfer, v))
        lut[k] = v
        k += 1
    else
      # Other primaries: convert each pixel in linear light to 16-bit BT.709
      # code values first, then encode those.
      dec = f64[256]
      k = 0
      while k < 256
        dec[k] = Transfer.decode(source.transfer, k.to_f / ~255.0)
        k += 1
      m = source.matrix_to(target)
      mf = f64[9]
      k = 0
      while k < 9
        mf[k] = m[k / 3][k % 3]
        k += 1
      src = i64[@width * @height]
      yuv_gamut16(px, @width * @height, dec, mf, Transfer.code(@transfer), src)
      shift = 16
      mask = 65535
      scale = ~1.0 / ~65535.0
    co = @ycbcr.coefficients
    yuv_luma(src, @width * @height, shift, mask, lut, scale, co, @ycbcr.code_min, @ycbcr.code_max, @y)
    taps = YuvFrame.down_taps(@chroma, @siting)
    geo = i64[10]
    geo[0] = @width
    geo[1] = @height
    geo[2] = shift
    geo[3] = mask
    geo[4] = @ycbcr.code_min
    geo[5] = @ycbcr.code_max
    geo[6] = @chroma_width
    geo[7] = @chroma_height
    geo[8] = YuvFrame.h_sub(@chroma)
    geo[9] = YuvFrame.v_sub(@chroma)
    yuv_chroma(src, geo, lut, scale, co, taps[0], taps[1], taps[0].size, taps[2], taps[3], taps[2].size, @cb, @cr)
    self

  # Decimation taps [h offsets, h weights, v offsets, v weights] around the
  # luma sample (2i, 2j) under each chroma sample.
  -> .down_taps(chroma, siting)
    ho = i64[1]
    hw = f64[1]
    hw[0] = ~1.0
    vo = i64[1]
    vw = f64[1]
    vw[0] = ~1.0
    if YuvFrame.h_sub(chroma) == 2
      if siting == :center
        ho = i64[2]
        ho[1] = 1
        hw = f64[2]
        hw[0] = ~0.5
        hw[1] = ~0.5
      else
        ho = i64[3]
        ho[0] = -1
        ho[2] = 1
        hw = f64[3]
        hw[0] = ~0.25
        hw[1] = ~0.5
        hw[2] = ~0.25
    if YuvFrame.v_sub(chroma) == 2
      if siting == :topleft
        vo = i64[3]
        vo[0] = -1
        vo[2] = 1
        vw = f64[3]
        vw[0] = ~0.25
        vw[1] = ~0.5
        vw[2] = ~0.25
      else
        vo = i64[2]
        vo[1] = 1
        vw = f64[2]
        vw[0] = ~0.5
        vw[1] = ~0.5
    [ho, hw, vo, vw]

  # For each luma coordinate along an axis: the two chroma samples to
  # interpolate between and the weight of the second.
  -> .up_taps(n, cn, sub, cosited)
    near = i64[n]
    far = i64[n]
    t = f64[n]
    yuv_up_taps(n, cn, sub, cosited ? 1 : 0, near, far, t)
    [near, far, t]

  # [Y', Cb, Cr] codes at a pixel (chroma from the sample that covers it).
  -> get(x, yy)
    ci = (yy / YuvFrame.v_sub(@chroma)) * @chroma_width + x / YuvFrame.h_sub(@chroma)
    [@y[yy * @width + x], @cb[ci], @cr[ci]]

  # Back to a Raster in colour space `target` (default "srgb"): upsample the
  # chroma, invert the matrix, clamp R'G'B' to [0, 1], decode with this
  # frame's transfer and re-encode for the target, round to 8 bits.
  -> to_raster(target = "srgb")
    t = ColorSpace.named(target)
    out = Raster.new(@width, @height, 0)
    mine = ColorSpace.rec709.with_transfer(@transfer)
    mode = 0
    lut = f64[1]
    mf = f64[9]
    if !t.same_primaries?(mine)
      mode = 2
      m = mine.matrix_to(t)
      k = 0
      while k < 9
        mf[k] = m[k / 3][k % 3]
        k += 1
    elsif t.transfer != @transfer
      mode = 1
      lut = f64[4097]
      yuv_curve_lut(lut, 4096, Transfer.code(@transfer), Transfer.code(t.transfer))
    hs = YuvFrame.h_sub(@chroma)
    vs = YuvFrame.v_sub(@chroma)
    ht = YuvFrame.up_taps(@width, @chroma_width, hs, @siting != :center)
    vt = YuvFrame.up_taps(@height, @chroma_height, vs, @siting == :topleft)
    geo = i64[6]
    geo[0] = @width
    geo[1] = @height
    geo[2] = @chroma_width
    geo[3] = mode
    geo[4] = Transfer.code(@transfer)
    geo[5] = Transfer.code(t.transfer)
    yuv_to_rgb(@y, @cb, @cr, geo, ht[0], ht[1], ht[2], vt[0], vt[1], vt[2], @ycbcr.coefficients, lut, mf, out.pixels)
    out

  # ffmpeg's name for this frame's planar layout: yuv420p, yuv422p10le, ...
  -> pix_fmt
    YuvFrame.pix_fmt_for(@chroma, @ycbcr.bits)

  -> .pix_fmt_for(chroma, bits)
    base = YuvFrame.chroma_kind(chroma).to_s + "p"
    if bits == 8
      return base
    base + bits.to_s + "le"

  # Layout of a pixel format: [chroma, bits, packing (:planar or :semi), shift].
  # Planar: Y, Cb, Cr planes; semi-planar: Y, then Cb Cr pairs. Samples over
  # 8 bits take two bytes, little-endian, the value shifted left by `shift`
  # (P010 keeps 10 bits in the high bits of each 16-bit word).
  -> .format_info(fmt)
    n = fmt.to_s
    if n == "i420"
      n = "yuv420p"
    if n == "p010"
      n = "p010le"
    if n == "p210"
      n = "p210le"
    if n == "nv12"
      return [:yuv420, 8, :semi, 0]
    if n == "nv16"
      return [:yuv422, 8, :semi, 0]
    if n == "p010le"
      return [:yuv420, 10, :semi, 6]
    if n == "p210le"
      return [:yuv422, 10, :semi, 6]
    chromas = ["420", "422", "444"]
    depths = [10, 12, 16]
    ci = 0
    while ci < 3
      base = "yuv" + chromas[ci] + "p"
      if n == base
        return [YuvFrame.chroma_kind(chromas[ci]), 8, :planar, 0]
      di = 0
      while di < 3
        if n == base + depths[di].to_s + "le"
          return [YuvFrame.chroma_kind(chromas[ci]), depths[di], :planar, 0]
        di += 1
      ci += 1
    raise ArgumentError, "unknown pixel format '[n]': expected yuv420p (i420), yuv422p, yuv444p, their 10le/12le/16le forms, nv12, nv16, p010le or p210le"

  -> .byte_size(fmt, width, height)
    info = YuvFrame.format_info(fmt)
    cw = (width + YuvFrame.h_sub(info[0]) - 1) / YuvFrame.h_sub(info[0])
    ch = (height + YuvFrame.v_sub(info[0]) - 1) / YuvFrame.v_sub(info[0])
    bps = info[1] > 8 ? 2 : 1
    (width * height + 2 * cw * ch) * bps

  # The frame packed as `fmt` (tightly, no row padding).
  -> to_bytes(fmt)
    info = YuvFrame.format_info(fmt)
    if info[0] != @chroma || info[1] != @ycbcr.bits
      raise ArgumentError, "to_bytes: [fmt] is [info[0]] [info[1]]-bit; this frame is [@chroma] [@ycbcr.bits]-bit"
    n = @width * @height
    cn = @chroma_width * @chroma_height
    out = u8[YuvFrame.byte_size(fmt, @width, @height)]
    if info[1] == 8
      yuv_put8(@y, n, out, 0, 1)
      if info[2] == :planar
        yuv_put8(@cb, cn, out, n, 1)
        yuv_put8(@cr, cn, out, n + cn, 1)
      else
        yuv_put8(@cb, cn, out, n, 2)
        yuv_put8(@cr, cn, out, n + 1, 2)
    else
      yuv_put16(@y, n, out, 0, 1, info[3])
      if info[2] == :planar
        yuv_put16(@cb, cn, out, 2 * n, 1, info[3])
        yuv_put16(@cr, cn, out, 2 * (n + cn), 1, info[3])
      else
        yuv_put16(@cb, cn, out, 2 * n, 2, info[3])
        yuv_put16(@cr, cn, out, 2 * n + 2, 2, info[3])
    out

  -> to_i420
    to_bytes("yuv420p")

  -> to_nv12
    to_bytes("nv12")

  -> to_p010
    to_bytes("p010le")

  -> to_yuv420p10le
    to_bytes("yuv420p10le")

  # A frame from packed bytes. Options: range (:limited), matrix (:bt709),
  # siting (:left), transfer (:passthrough); chroma and bits come from fmt.
  -> .from_bytes(bytes, fmt, width, height, opts = nil)
    info = YuvFrame.format_info(fmt)
    want = YuvFrame.byte_size(fmt, width, height)
    if bytes.size != want
      raise ArgumentError, "from_bytes: [fmt] at [width]x[height] is [want] bytes, got [bytes.size]"
    q = YCbCr.matrix(YuvFrame.option(opts, :matrix, :bt709), info[1], YuvFrame.option(opts, :range, :limited))
    f = YuvFrame.new(width, height, info[0], q, YuvFrame.option(opts, :siting, :left), YuvFrame.option(opts, :transfer, :passthrough))
    n = width * height
    cn = f.chroma_width * f.chroma_height
    if info[1] == 8
      yuv_get8(f.y, n, bytes, 0, 1)
      if info[2] == :planar
        yuv_get8(f.cb, cn, bytes, n, 1)
        yuv_get8(f.cr, cn, bytes, n + cn, 1)
      else
        yuv_get8(f.cb, cn, bytes, n, 2)
        yuv_get8(f.cr, cn, bytes, n + 1, 2)
    else
      mask = ycbcr_pow2(info[1]) - 1
      yuv_get16(f.y, n, bytes, 0, 1, info[3], mask)
      if info[2] == :planar
        yuv_get16(f.cb, cn, bytes, 2 * n, 1, info[3], mask)
        yuv_get16(f.cr, cn, bytes, 2 * (n + cn), 1, info[3], mask)
      else
        yuv_get16(f.cb, cn, bytes, 2 * n, 2, info[3], mask)
        yuv_get16(f.cr, cn, bytes, 2 * n + 2, 2, info[3], mask)
    f


# --------------------------------------------------------------------------
# Typed kernels.

-> ycbcr_pow2(n) (i64) i64
  v = 1
  k = 0
  while k < n
    v = v * 2
    k += 1
  v

# H.273 Round: Sign(x) Floor(Abs(x) + 0.5); BT.709's INT for x >= 0. The
# `## i64` conversion truncates, which is Floor for the non-negative operand.
-> ycbcr_round(x) (f64) i64
  if x < ~0.0
    a = ~0.5 - x
    k = a ## i64
    return 0 - k
  a = x + ~0.5
  k = a ## i64
  k

-> ycbcr_code(e, scale, offset, lo, hi) (f64 f64 f64 i64 i64) i64
  c = ycbcr_round(e * scale + offset)
  if c < lo
    return lo
  if c > hi
    return hi
  c

-> yuv_fill(plane, n, v) (u16[] i64 i64) i64
  i = 0
  while i < n
    plane[i] = v
    i += 1
  n

# px: packed channels of `shift` bits (8: 0xRRGGBB; 16: 0xRRRRGGGGBBBB);
# a channel's R' is lut[code], or code x scale when scale > 0 (16-bit code
# values); co: YCbCr#coefficients.
-> yuv_luma(px, n, shift, mask, lut, scale, co, lo, hi, yp) (i64[] i64 i64 i64 f64[] f64 f64[] i64 i64 u16[]) i64
  kr = co[0]
  kg = co[1]
  kb = co[2]
  ys = co[3]
  yo = co[4]
  s2 = shift * 2
  i = 0
  while i < n
    c = px[i]
    rk = (c >> s2) & mask
    gk = (c >> shift) & mask
    bk = c & mask
    r = ~0.0
    g = ~0.0
    b = ~0.0
    if scale > ~0.0
      r = (rk + ~0.0) * scale
      g = (gk + ~0.0) * scale
      b = (bk + ~0.0) * scale
    else
      r = lut[rk]
      g = lut[gk]
      b = lut[bk]
    yp[i] = ycbcr_code(kr * r + kg * g + kb * b, ys, yo, lo, hi)
    i += 1
  n

# geo: [w, h, shift, mask, lo, hi, cw, ch, h_sub, v_sub]; the chroma sample
# (i, j) filters the taps around luma (i h_sub, j v_sub), edges repeated.
-> yuv_chroma(px, geo, lut, scale, co, ho, hw, hn, vo, vw, vn, cbp, crp) (i64[] i64[] f64[] f64 f64[] i64[] f64[] i64 i64[] f64[] i64 u16[] u16[]) i64
  w = geo[0]
  h = geo[1]
  shift = geo[2]
  mask = geo[3]
  lo = geo[4]
  hi = geo[5]
  cw = geo[6]
  ch = geo[7]
  hs = geo[8]
  vs = geo[9]
  s2 = shift * 2
  kr = co[0]
  kg = co[1]
  kb = co[2]
  cs = co[5]
  cof = co[6]
  cbd = ~2.0 * (~1.0 - kb)
  crd = ~2.0 * (~1.0 - kr)
  j = 0
  while j < ch
    i = 0
    while i < cw
      sr = ~0.0
      sg = ~0.0
      sb = ~0.0
      bv = 0
      while bv < vn
        yy = j * vs + vo[bv]
        if yy < 0
          yy = 0
        if yy > h - 1
          yy = h - 1
        a = 0
        while a < hn
          xx = i * hs + ho[a]
          if xx < 0
            xx = 0
          if xx > w - 1
            xx = w - 1
          wt = hw[a] * vw[bv]
          c = px[yy * w + xx]
          rk = (c >> s2) & mask
          gk = (c >> shift) & mask
          bk = c & mask
          if scale > ~0.0
            sr += wt * (rk + ~0.0) * scale
            sg += wt * (gk + ~0.0) * scale
            sb += wt * (bk + ~0.0) * scale
          else
            sr += wt * lut[rk]
            sg += wt * lut[gk]
            sb += wt * lut[bk]
          a += 1
        bv += 1
      yv = kr * sr + kg * sg + kb * sb
      cbp[j * cw + i] = ycbcr_code((sb - yv) / cbd, cs, cof, lo, hi)
      crp[j * cw + i] = ycbcr_code((sr - yv) / crd, cs, cof, lo, hi)
      i += 1
    j += 1
  cw * ch

# 8-bit pixels in another gamut -> 16-bit BT.709 code values: decode (dec:
# code -> linear), matrix m (row-major), clip to [0, 1], encode with `kind`.
-> yuv_gamut16(px, n, dec, m, kind, out) (i64[] i64 f64[] f64[] i64 i64[]) i64
  i = 0
  while i < n
    c = px[i]
    r = dec[(c >> 16) & 255]
    g = dec[(c >> 8) & 255]
    b = dec[c & 255]
    r2 = yuv_unit(m[0] * r + m[1] * g + m[2] * b)
    g2 = yuv_unit(m[3] * r + m[4] * g + m[5] * b)
    b2 = yuv_unit(m[6] * r + m[7] * g + m[8] * b)
    rq = ycbcr_round(~65535.0 * transfer_encode(kind, r2))
    gq = ycbcr_round(~65535.0 * transfer_encode(kind, g2))
    bq = ycbcr_round(~65535.0 * transfer_encode(kind, b2))
    out[i] = (rq << 32) | (gq << 16) | bq
    i += 1
  n

-> yuv_unit(x) (f64) f64
  if x < ~0.0
    return ~0.0
  if x > ~1.0
    return ~1.0
  x

-> yuv_pack_rgba(bytes, w, h, stride, roff, goff, boff, px) (u8[] i64 i64 i64 i64 i64 i64 i64[]) i64
  y = 0
  while y < h
    row = y * stride
    x = 0
    while x < w
      p = row + 4 * x
      r = bytes[p + roff] ## i64
      g = bytes[p + goff] ## i64
      b = bytes[p + boff] ## i64
      px[y * w + x] = (r << 16) | (g << 8) | b
      x += 1
    y += 1
  w * h

# Chroma sample k sits at luma coordinate k * sub when co-sited, k * sub +
# (sub - 1) / 2 when midway; each luma coordinate interpolates its two
# neighbours (clamped at the edges).
-> yuv_up_taps(n, cn, sub, cosited, near, far, t) (i64 i64 i64 i64 i64[] i64[] f64[]) i64
  x = 0
  while x < n
    pos = x.to_f
    if sub == 2
      if cosited == 1
        pos = x.to_f / ~2.0
      else
        pos = (x.to_f - ~0.5) / ~2.0
    k = Math.floor(pos).to_i
    frac = pos - k.to_f
    a = k
    b = k + 1
    if a < 0
      a = 0
    if b < 0
      b = 0
    if a > cn - 1
      a = cn - 1
    if b > cn - 1
      b = cn - 1
    near[x] = a
    far[x] = b
    t[x] = frac
    x += 1
  n

# geo: [w, h, cw, mode, frame transfer, target transfer]; mode 0: R' -> 8 bits
# directly, 1: through the curve table lut (yuv_curve_lut), 2: decode,
# matrix m, clip, encode per pixel.
-> yuv_to_rgb(yp, cbp, crp, geo, xi0, xi1, xt, yi0, yi1, yt, co, lut, m, out) (u16[] u16[] u16[] i64[] i64[] i64[] f64[] i64[] i64[] f64[] f64[] f64[] f64[] i64[]) i64
  w = geo[0]
  h = geo[1]
  cw = geo[2]
  mode = geo[3]
  src_kind = geo[4]
  dst_kind = geo[5]
  kr = co[0]
  kg = co[1]
  kb = co[2]
  ys = co[3]
  yo = co[4]
  cs = co[5]
  cof = co[6]
  crd = ~2.0 * (~1.0 - kr)
  cbd = ~2.0 * (~1.0 - kb)
  y = 0
  while y < h
    ra = yi0[y] * cw
    rb = yi1[y] * cw
    v = yt[y]
    x = 0
    while x < w
      a = xi0[x]
      b = xi1[x]
      u = xt[x]
      c00 = cbp[ra + a] ## f64
      c01 = cbp[ra + b] ## f64
      c10 = cbp[rb + a] ## f64
      c11 = cbp[rb + b] ## f64
      cb = (~1.0 - v) * ((~1.0 - u) * c00 + u * c01) + v * ((~1.0 - u) * c10 + u * c11)
      d00 = crp[ra + a] ## f64
      d01 = crp[ra + b] ## f64
      d10 = crp[rb + a] ## f64
      d11 = crp[rb + b] ## f64
      cr = (~1.0 - v) * ((~1.0 - u) * d00 + u * d01) + v * ((~1.0 - u) * d10 + u * d11)
      yc = yp[y * w + x] ## f64
      ey = (yc - yo) / ys
      epb = (cb - cof) / cs
      epr = (cr - cof) / cs
      r = yuv_unit(ey + crd * epr)
      bl = yuv_unit(ey + cbd * epb)
      g = yuv_unit((ey - kr * (ey + crd * epr) - kb * (ey + cbd * epb)) / kg)
      ro8 = 0
      go8 = 0
      bo8 = 0
      if mode == 0
        ro8 = ycbcr_round(r * ~255.0)
        go8 = ycbcr_round(g * ~255.0)
        bo8 = ycbcr_round(bl * ~255.0)
      elsif mode == 1
        # linear interpolation in the 4097-entry curve table (yuv_curve_lut)
        tr = r * ~4096.0
        ir = tr ## i64
        if ir > 4095
          ir = 4095
        tg = g * ~4096.0
        ig = tg ## i64
        if ig > 4095
          ig = 4095
        tb = bl * ~4096.0
        ib = tb ## i64
        if ib > 4095
          ib = 4095
        ro8 = ycbcr_round(~255.0 * (lut[ir] + (tr - (ir + ~0.0)) * (lut[ir + 1] - lut[ir])))
        go8 = ycbcr_round(~255.0 * (lut[ig] + (tg - (ig + ~0.0)) * (lut[ig + 1] - lut[ig])))
        bo8 = ycbcr_round(~255.0 * (lut[ib] + (tb - (ib + ~0.0)) * (lut[ib + 1] - lut[ib])))
      else
        lr = transfer_decode(src_kind, r)
        lg = transfer_decode(src_kind, g)
        lb = transfer_decode(src_kind, bl)
        ro8 = ycbcr_round(~255.0 * transfer_encode(dst_kind, yuv_unit(m[0] * lr + m[1] * lg + m[2] * lb)))
        go8 = ycbcr_round(~255.0 * transfer_encode(dst_kind, yuv_unit(m[3] * lr + m[4] * lg + m[5] * lb)))
        bo8 = ycbcr_round(~255.0 * transfer_encode(dst_kind, yuv_unit(m[6] * lr + m[7] * lg + m[8] * lb)))
      out[y * w + x] = (ro8 << 16) | (go8 << 8) | bo8
      x += 1
    y += 1
  w * h

# lut[k] = the target code value for frame R' = k / n (k = 0..n): decode with
# the frame's transfer, encode with the target's, clip to [0, 1].
-> yuv_curve_lut(lut, n, src_kind, dst_kind) (f64[] i64 i64 i64) i64
  k = 0
  while k <= n
    v = (k + ~0.0) / (n + ~0.0)
    lut[k] = yuv_unit(transfer_encode(dst_kind, transfer_decode(src_kind, v)))
    k += 1
  n

-> yuv_put8(src, n, out, at, step) (u16[] i64 u8[] i64 i64) i64
  k = 0
  while k < n
    out[at + k * step] = src[k]
    k += 1
  n

-> yuv_put16(src, n, out, at, step, shl) (u16[] i64 u8[] i64 i64 i64) i64
  k = 0
  while k < n
    v = src[k] ## i64
    v = v << shl
    p = at + 2 * k * step
    out[p] = v & 255
    out[p + 1] = (v >> 8) & 255
    k += 1
  n

-> yuv_get8(dst, n, bytes, at, step) (u16[] i64 u8[] i64 i64) i64
  k = 0
  while k < n
    dst[k] = bytes[at + k * step]
    k += 1
  n

-> yuv_get16(dst, n, bytes, at, step, shr, mask) (u16[] i64 u8[] i64 i64 i64 i64) i64
  k = 0
  while k < n
    p = at + 2 * k * step
    lo = bytes[p] ## i64
    hi = bytes[p + 1] ## i64
    dst[k] = ((lo | (hi << 8)) >> shr) & mask
    k += 1
  n
