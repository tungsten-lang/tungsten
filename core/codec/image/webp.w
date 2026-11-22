# core/codec/image/webp — WebP images (RIFF container) in pure Tungsten.
#
#   webp_sniff?(bytes)   "RIFF" .... "WEBP"
#   webp_decode(bytes)   → Bitmap (straight RGBA8); animations fill frames
#
# Simple lossy (VP8 keyframe, core/codec/image/webp_vp8.w), simple lossless (VP8L,
# core/codec/image/webp_vp8l.w) and the extended format (VP8X): ALPH alpha (raw or
# VP8L-compressed, with its spatial filters), and animation (ANIM loop count,
# ANMF frames with offsets, durations, alpha-blend / no-blend and
# dispose-to-background). Like Chrome and libwebp's WebPAnimDecoder, frames
# are composited onto a transparent canvas and disposal clears to transparent
# (the ANIM background colour is only a hint and is ignored). Frame delays are
# the file's raw durations in ms (browsers raise ≤ 10 ms to 100 ms at display
# time). EXIF orientation is not applied (browsers don't for WebP). An ICCP
# profile (VP8X) is applied with core/codec/image/icc.w to each decoded frame before it is
# composited (as Chrome does); profiles core/codec/image/icc.w can't handle leave the pixels
# as they are (treated as sRGB).

use core/codec/image
use icc
use webp_vp8l
use webp_vp8

-> webp_sniff?(b)
  b.size >= 12 && b[0] == 82 && b[1] == 73 && b[2] == 70 && b[3] == 70 && b[8] == 87 && b[9] == 69 && b[10] == 66 && b[11] == 80

-> wp_fail(msg)
  raise ImageError, "webp: " + msg

-> wp_tag(a, o)
  a[o].chr + a[o + 1].chr + a[o + 2].chr + a[o + 3].chr

-> wp_le24(a, o) (u8[] i64) i64
  a[o] | (a[o + 1] << 8) | (a[o + 2] << 16)

# Chunks between start and stop: [[tag, payload_off, payload_len], …].
-> wp_chunks(a, start, stop)
  out = []
  o = start
  while o + 8 <= stop
    tag = wp_tag(a, o)
    n = img_le32(a, o + 4)
    p = o + 8
    n = stop - p if p + n > stop
    out.push([tag, p, n])
    o = p + n + (n & 1)
  out

-> webp_decode(data)
  a = img_bytes(data)
  wp_fail("not a WebP file") if !webp_sniff?(a)
  stop = 8 + img_le32(a, 4)
  stop = a.size if stop > a.size
  chunks = wp_chunks(a, 12, stop)
  wp_fail("no image data") if chunks.size == 0
  first = chunks[0]
  if first[0] == "VP8X"
    wp_fail("truncated VP8X") if first[2] < 10
    flags = a[first[1]]
    cw = wp_le24(a, first[1] + 4) + 1
    ch = wp_le24(a, first[1] + 7) + 1
    img_check_size(cw, ch)
    prof = (flags & 0x20) != 0 ? wp_icc(a, chunks) : nil
    if (flags & 2) != 0
      return wp_animation(a, chunks, cw, ch, prof)
    bm = wp_frame(a, chunks, 1)
    icc_apply(prof, bm.rgba, bm.width * bm.height) if prof != nil
    return bm
  wp_frame(a, chunks, 0)

# The ICCP profile when it is one core/codec/image/icc.w can apply and it isn't (close to) sRGB.
-> wp_icc(a, chunks)
  i = 0
  while i < chunks.size
    c = chunks[i]
    if c[0] == "ICCP"
      p = nil
      begin
        p = icc_parse(a, c[1], c[2])
      rescue e
        p = nil
      return nil if p == nil || p.cmyk? || p.gray? || icc_srgb?(p)
      return p
    i += 1
  nil

# One still image from the chunk list (ALPH + VP8, or VP8L).
-> wp_frame(a, chunks, from)
  alph = nil
  i = from
  while i < chunks.size
    c = chunks[i]
    if c[0] == "ALPH"
      alph = c
    elsif c[0] == "VP8L"
      r = vp8l_decode(a, c[1], c[2])
      bm = Bitmap.new(r[0], r[1])
      wp_argb_to_rgba(r[2], bm.rgba, r[0] * r[1])
      vl_free(r[2])
      return bm
    elsif c[0] == "VP8 "
      bm = vp8_decode(a, c[1], c[2])
      if alph != nil && alph[2] > 0
        wp_apply_alpha(a, alph, bm)
      return bm
    i += 1
  wp_fail("no VP8/VP8L frame")

-> wp_argb_to_rgba(px, out, n) (i64[] u8[] i64) i64
  i = 0 ## i64
  o = 0 ## i64
  while i < n
    p = px[i] ## i64
    out[o] = (p >> 16) & 255
    out[o + 1] = (p >> 8) & 255
    out[o + 2] = p & 255
    out[o + 3] = (p >> 24) & 255
    i += 1
    o += 4
  0

# ALPH: 1 header byte (method, filter, pre-processing), then the plane.
-> wp_apply_alpha(a, c, bm)
  w = bm.width
  h = bm.height
  hdr = a[c[1]]
  method = hdr & 3
  filter = (hdr >> 2) & 3
  wp_fail("bad ALPH header") if method > 1 || (hdr >> 6) != 0
  plane = nil
  if method == 0
    wp_fail("truncated ALPH") if c[2] - 1 < w * h
    plane = u8[w * h]
    wp_copy8(plane, 0, a, c[1] + 1, w * h)
  else
    plane = vp8l_decode_alpha(a, c[1] + 1, c[2] - 1, w, h)
  wp_unfilter(plane, w, h, filter) if filter != 0
  wp_put_alpha(plane, bm.rgba, w * h)
  vl_free(plane)
  nil

-> wp_copy8(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> wp_put_alpha(plane, rgba, n) (u8[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    rgba[i * 4 + 3] = plane[i]
    i += 1
  0

# In-place inverse of the ALPH spatial filters (1 horizontal, 2 vertical,
# 3 gradient), row by row as libwebp's unfilters.
-> wp_unfilter(p, w, h, filter) (u8[] i64 i64 i64) i64
  y = 0 ## i64
  while y < h
    row = y * w
    if y == 0 || filter == 1
      pred = (y == 0 ? 0 : p[row - w]) ## i64
      x = 0 ## i64
      while x < w
        pred = (pred + p[row + x]) & 255 ## i64
        p[row + x] = pred
        x += 1
    elsif filter == 2
      x = 0
      while x < w
        p[row + x] = (p[row + x] + p[row - w + x]) & 255
        x += 1
    else
      top = p[row - w] ## i64
      tl = top
      left = top
      x = 0
      while x < w
        top = p[row - w + x] ## i64
        g = left + top - tl
        g = 0 if g < 0
        g = 255 if g > 255
        left = (p[row + x] + g) & 255 ## i64
        tl = top
        p[row + x] = left
        x += 1
    y += 1
  0

# Composited frames kept for one animation, in pixels (4 bytes each).
WP_MAX_ANIM_PIXELS = 100000000

-> wp_animation(a, chunks, cw, ch, prof)
  loops = 0
  frames = []
  canvas = u8[cw * ch * 4]
  prev = nil
  i = 0
  while i < chunks.size
    c = chunks[i]
    if c[0] == "ANIM" && c[2] >= 6
      loops = img_le16(a, c[1] + 4)
    elsif c[0] == "ANMF" && c[2] >= 16
      o = c[1]
      fx = wp_le24(a, o) * 2
      fy = wp_le24(a, o + 3) * 2
      fw = wp_le24(a, o + 6) + 1
      fh = wp_le24(a, o + 9) + 1
      dur = wp_le24(a, o + 12)
      fl = a[o + 15]
      sub = wp_chunks(a, o + 16, o + c[2])
      if prev != nil && prev[4] == 1
        img_fill_rect(canvas, cw, ch, prev[0], prev[1], prev[2], prev[3], 0)
      bm = wp_frame(a, sub, 0)
      icc_apply(prof, bm.rgba, fw * fh) if prof != nil
      wp_fail("frame size mismatch") if bm.width != fw || bm.height != fh
      wp_fail("frame outside canvas") if fx + fw > cw || fy + fh > ch
      img_blit(canvas, cw, ch, bm.rgba, fw, fh, fx, fy, (fl & 2) != 0 ? 0 : 1)
      vl_free(bm.rgba)
      prev = [fx, fy, fw, fh, fl & 1]
      snap = Bitmap.new(cw, ch, img_copy(canvas))
      frames.push([snap, dur])
      # memory budget: stop at WP_MAX_ANIM_PIXELS composited pixels in total
      # (the animation then plays the frames decoded so far)
      i = chunks.size if frames.size * cw * ch >= WP_MAX_ANIM_PIXELS
    i += 1
  vl_free(canvas)
  wp_fail("animation without frames") if frames.size == 0
  out = Bitmap.new(cw, ch, frames[0][0].rgba)
  if frames.size > 1
    out.frames = frames
    out.loop_count = loops
  out

img_register("webp", ->(b) webp_sniff?(b), ->(b) webp_decode(b))
