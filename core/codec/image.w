# core/codec/image — the image codec contract: Bitmap, the decoder registry
# (Image) and the helpers every decoder in core/codec/image/ builds against.
#
#   use core/codec               # every decoder (or core/codec/image/all, or one: core/codec/image/png)
#   bm = Image.decode(bytes)     # Bitmap; bytes: a String or u8[]; raises ImageError
#   Image.sniff(bytes)           # "png", "jpeg", "webp", "avif", … or nil
#   Image.formats                # registered names, in sniff order
#
# A decoder takes the raw bytes of a resource (u8[]) and returns a Bitmap.
# Decoders register themselves at load time with img_register(name, sniff,
# decode) (Image.register), so each format lives in its own file and a loader
# never names a format:
#
#   img_register("png", ->(b) png_sniff?(b), ->(b) png_decode(b))
#
# sniff(bytes) → true when the bytes look like this format (magic numbers only,
# never a Content-Type: servers mislabel images all the time).
# decode(bytes) → a Bitmap, or raises ImageError with a short reason.
#
# Pixels are straight (not premultiplied) 8-bit RGBA in sRGB. A decoder converts
# from its own colour model (YCbCr, CMYK, ICC profiles, CICP/nclx, 10/12-bit, HDR
# tone-mapped down) and applies orientation (EXIF, irot/imir) before returning.
# ==== end of core header ====

+ ImageError < StandardError

+ Bitmap
  # rgba: ByteArray of width * height * 4.
  # frames: nil for a still; for an animation, [[Bitmap, delay_ms], …] in
  #         display order (each frame fully composited, full canvas size), with
  #         rgba holding the first frame.
  # loop_count: 0 = forever, n = play n times; nil for stills.
  rw :width, :height, :rgba, :frames, :loop_count

  -> new(@width, @height, @rgba = nil)
    @rgba = ByteArray.new(@width * @height * 4) if @rgba == nil
    @frames = nil
    @loop_count = nil

  -> animated?
    @frames != nil && @frames.size > 1

# [[name, sniff, decode], …] in registration order.
IMG_DECODERS = []

-> img_register(name, sniff, decode)
  IMG_DECODERS.push([name, sniff, decode])

# The registered format name for these bytes, or nil.
-> img_sniff(bytes)
  i = 0
  while i < IMG_DECODERS.size
    d = IMG_DECODERS[i]
    return d[0] if d[1].call(bytes)
    i += 1
  nil

# The operating system's image decoder (core/codec/system: ImageIO), used
# for the formats in codec_system_list(), falling back to ours per file.
IMG_SYSTEM = [nil]

-> img_system_register(dec)
  IMG_SYSTEM[0] = dec

-> img_call(dec, bytes)
  dec.call(bytes)

# Decode with whichever registered decoder recognises the bytes.
-> img_decode(bytes)
  if IMG_SYSTEM[0] != nil
    k = img_sniff(bytes)
    if k != nil && codec_system_list().include?(k) && !img_animated_head?(k, bytes)
      bm = nil
      begin
        bm = img_call(IMG_SYSTEM[0], bytes)
      rescue e
        bm = nil
      return bm if bm != nil
  i = 0
  while i < IMG_DECODERS.size
    d = IMG_DECODERS[i]
    return d[2].call(bytes) if d[1].call(bytes)
    i += 1
  raise ImageError.new("unrecognised image format")

# Animated WebP / AVIF sequences stay with our decoders (ImageIO gives only
# the first frame).
-> img_animated_head?(kind, bytes)
  return false if kind != "webp" && kind != "avif"
  n = bytes.size < 1024 ? bytes.size : 1024
  i = 0
  while i + 4 <= n
    if kind == "webp" && bytes[i] == 65 && bytes[i + 1] == 78 && bytes[i + 2] == 73 && bytes[i + 3] == 77
      return true
    if kind == "avif" && bytes[i] == 97 && bytes[i + 1] == 118 && bytes[i + 2] == 105 && bytes[i + 3] == 115
      return true
    i += 1
  false

# ---------------------------------------------------------------------------
# Shared helpers for decoders (added with the Tungsten decoders; all typed so
# they run at machine speed).
#
#   img_bytes(data)                 String or u8[] → u8[] (a String is copied)
#   img_fail(msg)                   raise ImageError
#   img_check_size(w, h)            raise unless 0 < w, h and w*h ≤ IMG_MAX_PIXELS
#   img_be16/img_be32/img_le16/img_le32(a, off)   integer readers (0 past the end)
#   img_exif_orientation(a, off, len)  orientation 1..8 from a TIFF/EXIF block
#                                   (starting at "II*\0"/"MM\0*", or at "Exif\0\0"), 1 if absent
#   img_orient(bm, o)               a Bitmap with EXIF orientation o applied (bm itself for 1)
#   img_blit(dst, dw, dh, src, sw, sh, x, y, blend)
#                                   copy (blend 0) or alpha-composite "source over" in
#                                   straight alpha (blend 1) src at (x, y) into dst; clipped
#   img_fill_rect(dst, dw, dh, x, y, w, h, v)   fill a rect with RGBA value v (u32, R in low byte)
#   img_copy(a)                     a fresh copy of a u8[]
#   img_ycc_to_rgb(y, cb, cr, out, off)  BT.601 full-range (JFIF) YCbCr → RGB at out[off..off+2]
#   img_colour?                     false when IMG_COLOUR[0] = false (tests: skip colour management)
# ---------------------------------------------------------------------------

# IMG_COLOUR[0] = false makes decoders skip colour management (ICC, gAMA,
# cHRM): pixels come back as the file's code values. For tests that compare
# against ImageIO's unmanaged bytes; Blade itself always leaves it true.
IMG_COLOUR = [true]

-> img_colour?
  IMG_COLOUR[0]

# Refuse absurd dimensions before allocating (a 1x1 PNG can claim 2^31 x 2^31).
IMG_MAX_PIXELS = 100000000

-> img_fail(msg)
  raise ImageError.new(msg)

-> img_check_size(w, h)
  img_fail("bad image size " + w.to_s + "x" + h.to_s) if w <= 0 || h <= 0 || w * h > IMG_MAX_PIXELS
  nil

-> img_bytes(data)
  return data if data.is_a?(Array)
  v = ccall("w_string_bytes_view", data) ## u8[]
  img_copy(v)

-> img_copy(a) (u8[]) u8[]
  n = a.size
  b = u8[n]
  i = 0 ## i64
  while i + 8 <= n
    array_store_u64(b, i, array_load_u64(a, i))
    i += 8
  while i < n
    b[i] = a[i]
    i += 1
  b

-> img_be16(a, o) (u8[] i64) i64
  return 0 if o < 0 || o + 2 > a.size
  (a[o] << 8) | a[o + 1]

-> img_be32(a, o) (u8[] i64) i64
  return 0 if o < 0 || o + 4 > a.size
  (a[o] << 24) | (a[o + 1] << 16) | (a[o + 2] << 8) | a[o + 3]

-> img_le16(a, o) (u8[] i64) i64
  return 0 if o < 0 || o + 2 > a.size
  a[o] | (a[o + 1] << 8)

-> img_le32(a, o) (u8[] i64) i64
  return 0 if o < 0 || o + 4 > a.size
  a[o] | (a[o + 1] << 8) | (a[o + 2] << 16) | (a[o + 3] << 24)

-> img_tiff16(a, o, le) (u8[] i64 i64) i64
  le == 1 ? img_le16(a, o) : img_be16(a, o)

-> img_tiff32(a, o, le) (u8[] i64 i64) i64
  le == 1 ? img_le32(a, o) : img_be32(a, o)

-> img_exif_orientation(a, off, len) (u8[] i64 i64) i64
  stop = off + len
  stop = a.size if stop > a.size
  if off + 6 <= stop && a[off] == 69 && a[off + 1] == 120 && a[off + 2] == 105 && a[off + 3] == 102 && a[off + 4] == 0
    off += 6
  return 1 if off + 8 > stop
  le = 0 ## i64
  if a[off] == 73 && a[off + 1] == 73
    le = 1
  elsif a[off] != 77 || a[off + 1] != 77
    return 1
  ifd = off + img_tiff32(a, off + 4, le)
  return 1 if ifd + 2 > stop || ifd < off
  n = img_tiff16(a, ifd, le)
  i = 0 ## i64
  while i < n
    e = ifd + 2 + i * 12
    return 1 if e + 12 > stop
    if img_tiff16(a, e, le) == 0x0112
      v = img_tiff16(a, e + 8, le)
      return v if v >= 1 && v <= 8
      return 1
    i += 1
  1

# EXIF orientation: 1 normal, 2 mirror, 3 rotate 180, 4 flip, 5 transpose,
# 6 rotate 90 CW, 7 transverse, 8 rotate 90 CCW.
-> img_orient(bm, o)
  return bm if o <= 1 || o > 8
  w = bm.width
  h = bm.height
  sw = o >= 5 ? h : w
  sh = o >= 5 ? w : h
  out = Bitmap.new(sw, sh)
  img_orient_px(bm.rgba, w, h, out.rgba, o)
  out

-> img_orient_px(src, w, h, dst, o) (u8[] i64 i64 u8[] i64) i64
  dw = o >= 5 ? h : w
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      dx = x ## i64
      dy = y ## i64
      if o == 2
        dx = w - 1 - x
      elsif o == 3
        dx = w - 1 - x
        dy = h - 1 - y
      elsif o == 4
        dy = h - 1 - y
      elsif o == 5
        dx = y
        dy = x
      elsif o == 6
        dx = h - 1 - y
        dy = x
      elsif o == 7
        dx = h - 1 - y
        dy = w - 1 - x
      elsif o == 8
        dx = y
        dy = w - 1 - x
      d = (dy * dw + dx) * 4
      q = (y * w + x) * 4
      dst[d] = src[q]
      dst[d + 1] = src[q + 1]
      dst[d + 2] = src[q + 2]
      dst[d + 3] = src[q + 3]
      x += 1
    y += 1
  0

-> img_fill_rect(dst, dw, dh, x, y, w, h, v) (u8[] i64 i64 i64 i64 i64 i64 i64) i64
  x0 = x < 0 ? 0 : x
  y0 = y < 0 ? 0 : y
  x1 = x + w > dw ? dw : x + w
  y1 = y + h > dh ? dh : y + h
  yy = y0 ## i64
  while yy < y1
    xx = x0 ## i64
    while xx < x1
      d = (yy * dw + xx) * 4
      dst[d] = v & 255
      dst[d + 1] = (v >> 8) & 255
      dst[d + 2] = (v >> 16) & 255
      dst[d + 3] = (v >> 24) & 255
      xx += 1
    yy += 1
  0

-> img_blit(dst, dw, dh, src, sw, sh, x, y, blend) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64) i64
  y0 = y < 0 ? 0 - y : 0
  x0 = x < 0 ? 0 - x : 0
  y1 = y + sh > dh ? dh - y : sh
  x1 = x + sw > dw ? dw - x : sw
  sy = y0 ## i64
  while sy < y1
    sx = x0 ## i64
    so = (sy * sw + sx) * 4
    d = ((y + sy) * dw + x + sx) * 4
    while sx < x1
      sa = src[so + 3]
      if blend == 0 || sa == 255
        dst[d] = src[so]
        dst[d + 1] = src[so + 1]
        dst[d + 2] = src[so + 2]
        dst[d + 3] = sa
      elsif sa != 0
        da = dst[d + 3]
        if da == 0
          dst[d] = src[so]
          dst[d + 1] = src[so + 1]
          dst[d + 2] = src[so + 2]
          dst[d + 3] = sa
        else
          # out_a = sa + da (1 - sa); out_c = (sc sa + dc da (1 - sa)) / out_a, all /255
          dw2 = da * (255 - sa)
          oa = sa * 255 + dw2
          dst[d] = (src[so] * sa * 255 + dst[d] * dw2 + (oa >> 1)) / oa
          dst[d + 1] = (src[so + 1] * sa * 255 + dst[d + 1] * dw2 + (oa >> 1)) / oa
          dst[d + 2] = (src[so + 2] * sa * 255 + dst[d + 2] * dw2 + (oa >> 1)) / oa
          dst[d + 3] = (oa + 127) / 255
      sx += 1
      so += 4
      d += 4
    sy += 1
  0

-> img_clamp8(v) (i64) i64
  return 0 if v < 0
  return 255 if v > 255
  v

# JFIF full-range BT.601, 16-bit fixed point.
-> img_ycc_to_rgb(y, cb, cr, out, off) (i64 i64 i64 u8[] i64) i64
  u = cb - 128
  v = cr - 128
  out[off] = img_clamp8(y + ((91881 * v + 32768) >> 16))
  out[off + 1] = img_clamp8(y - ((22554 * u + 46802 * v - 32768) >> 16))
  out[off + 2] = img_clamp8(y + ((116130 * u + 32768) >> 16))
  0

# ==== core API ====
# Image — the decoder registry above, as one class:
#   Image.decode(bytes) → Bitmap     Image.sniff(bytes) → name or nil
#   Image.formats → [name, …]        Image.register(name, sniff, decode)
# bytes may be a String or a u8[]. img_decode / img_sniff / img_register are
# the same registry under their decoder-facing names.
+ Image
  -> .decode(bytes)
    img_decode(img_bytes(bytes))

  -> .sniff(bytes)
    img_sniff(img_bytes(bytes))

  -> .formats
    names = []
    i = 0
    while i < IMG_DECODERS.size
      names.push(IMG_DECODERS[i][0])
      i += 1
    names

  -> .register(name, sniff, decode)
    img_register(name, sniff, decode)
