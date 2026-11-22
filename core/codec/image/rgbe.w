# core/codec/image/rgbe — Radiance HDR (RGBE / XYZE, .hdr / .pic) decoder.
#
# "#?RADIANCE" / "#?RGBE" header, FORMAT=32-bit_rle_rgbe or 32-bit_rle_xyze
# (XYZ converted to linear sRGB), all eight resolution-string orientations,
# new-style per-channel RLE scanlines, old-style RLE and flat pixels. Values
# are scene-linear and tone-mapped to sRGB by core/codec/image/imgfloat (the HDR is
# shown at exposure 1, as ImageIO and three.js' RGBELoader do).
#
#   rgbe_sniff?(bytes) / rgbe_decode(bytes) → Bitmap

use core/codec/image
use imgfloat

-> rgbe_sniff?(b)
  return false if b.size < 11 || b[0] != 35 || b[1] != 63
  rgbe_prefix?(b, 2, "RADIANCE") || rgbe_prefix?(b, 2, "RGBE")

-> rgbe_prefix?(b, off, s)
  return false if b.size < off + s.size
  i = 0
  while i < s.size
    return false if b[off + i] != s.byte_at(i)
    i += 1
  true

# Next header line from p: [line String, next pos].
-> rgbe_line(a, p)
  s = StringBuffer()
  while p < a.size && a[p] != 10
    s.append(a[p].chr) if a[p] != 13
    p += 1
  [s.to_s, p + 1]

-> rgbe_decode(data)
  a = img_bytes(data)
  img_fail("hdr: not a Radiance HDR") if !rgbe_sniff?(a)
  p = 0
  xyz = false
  while true
    img_fail("hdr: truncated header") if p >= a.size
    l = rgbe_line(a, p)
    p = l[1]
    break if l[0] == ""
    xyz = true if l[0].starts_with?("FORMAT=32-bit_rle_xyze")
  l = rgbe_line(a, p)
  p = l[1]
  parts = l[0].strip.split(" ").select(->(t) t.size > 0)
  img_fail("hdr: bad resolution string") if parts.size != 4
  # first axis is the slow (scanline) one
  ax1 = parts[0]
  ax2 = parts[2]
  n1 = parts[1].to_i
  n2 = parts[3].to_i
  img_fail("hdr: bad resolution string") if ax1.size != 2 || ax2.size != 2
  ylead = ax1.byte_at(1) == 89     # "Y" first: rows are image rows
  w = ylead ? n2 : n1
  h = ylead ? n1 : n2
  img_check_size(w, h)
  # flips: rows go down for -Y, right for +X
  sl = n1
  sw = n2
  px = u8[sl * sw * 4]
  rgbe_scan(a, p, px, sw, sl)
  bm = Bitmap.new(w, h)
  tb = imgf_tables()
  f1 = ax1.byte_at(0) == 43 ? 1 : 0     # '+' on the slow axis
  f2 = ax2.byte_at(0) == 45 ? 1 : 0     # '-' on the fast axis
  # -Y: first scanline at the top (no flip); +Y: bottom. +X: left to right; -X: right to left.
  rgbe_out(px, sw, sl, ylead ? 1 : 0, f1, f2, xyz ? 1 : 0, bm.rgba, w, tb[0], tb[1])
  bm

# Decode sl scanlines of sw pixels into px (RGBE bytes).
-> rgbe_scan(a, p, px, sw, sl) (u8[] i64 u8[] i64 i64) i64
  n = a.size
  y = 0 ## i64
  while y < sl && p < n
    row = y * sw * 4
    if sw >= 8 && sw < 32768 && p + 4 <= n && a[p] == 2 && a[p + 1] == 2 && (a[p + 2] & 128) == 0 && ((a[p + 2] << 8) | a[p + 3]) == sw
      p += 4
      c = 0 ## i64
      while c < 4
        x = 0 ## i64
        while x < sw && p < n
          cnt = a[p]
          p += 1
          if cnt > 128
            cnt -= 128
            break if p >= n
            v = a[p]
            p += 1
            k = 0 ## i64
            while k < cnt && x < sw
              px[row + x * 4 + c] = v
              x += 1
              k += 1
          else
            k = 0 ## i64
            while k < cnt && x < sw && p < n
              px[row + x * 4 + c] = a[p]
              p += 1
              x += 1
              k += 1
            break if cnt == 0
        c += 1
    else
      # flat or old-style RLE (1,1,1,count repeats the previous pixel)
      x = 0 ## i64
      shift = 0 ## i64
      while x < sw && p + 4 <= n
        if a[p] == 1 && a[p + 1] == 1 && a[p + 2] == 1
          cnt = a[p + 3] << shift
          k = 0 ## i64
          while k < cnt && x < sw
            if x > 0
              q = row + (x - 1) * 4
              px[row + x * 4] = px[q]
              px[row + x * 4 + 1] = px[q + 1]
              px[row + x * 4 + 2] = px[q + 2]
              px[row + x * 4 + 3] = px[q + 3]
            x += 1
            k += 1
          shift += 8
        else
          px[row + x * 4] = a[p]
          px[row + x * 4 + 1] = a[p + 1]
          px[row + x * 4 + 2] = a[p + 2]
          px[row + x * 4 + 3] = a[p + 3]
          x += 1
          shift = 0
        p += 4
    y += 1
  y

-> rgbe_out(px, sw, sl, ylead, f1, f2, xyz, out, w, p2, lut) (u8[] i64 i64 i64 i64 i64 i64 u8[] i64 f64[] u8[]) i64
  i = 0 ## i64
  while i < sl
    j = 0 ## i64
    while j < sw
      s = (i * sw + j) * 4
      e = px[s + 3]
      r = ~0.0
      g = ~0.0
      b = ~0.0
      if e != 0
        # v = (m + 0.5) / 256 * 2^(e - 128)
        f = p2[e - 136 + 160]
        r = (px[s].to_f + ~0.5) * f
        g = (px[s + 1].to_f + ~0.5) * f
        b = (px[s + 2].to_f + ~0.5) * f
      if xyz == 1
        x0 = r
        y0 = g
        z0 = b
        r = ~3.2404542 * x0 - ~1.5371385 * y0 - ~0.4985314 * z0
        g = ~-0.9692660 * x0 + ~1.8760108 * y0 + ~0.0415560 * z0
        b = ~0.0556434 * x0 - ~0.2040259 * y0 + ~1.0572252 * z0
      ii = f1 == 1 ? sl - 1 - i : i
      jj = f2 == 1 ? sw - 1 - j : j
      xx = ylead == 1 ? jj : ii
      yy = ylead == 1 ? ii : jj
      imgf_px(out, (yy * w + xx) * 4, r, g, b, ~1.0, lut)
      j += 1
    i += 1
  0

img_register("hdr", ->(b) rgbe_sniff?(b), ->(b) rgbe_decode(b))
