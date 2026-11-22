# core/codec/image/qoi — QOI ("Quite OK Image", qoiformat.org, spec 1.0) decoder.
#
# RGB and RGBA, sRGB or linear (the colour-space byte is informative only; the
# pixels are taken as sRGB as every viewer does). Truncated data decodes as far
# as it goes; the rest stays transparent.
#
#   qoi_sniff?(bytes)   "qoif"
#   qoi_decode(bytes)   → Bitmap

use core/codec/image

-> qoi_sniff?(b)
  b.size >= 14 && b[0] == 113 && b[1] == 111 && b[2] == 105 && b[3] == 102

-> qoi_decode(data)
  a = img_bytes(data)
  img_fail("qoi: not a QOI image") if !qoi_sniff?(a)
  w = img_be32(a, 4)
  h = img_be32(a, 8)
  ch = a[12]
  img_fail("qoi: bad channel count") if ch != 3 && ch != 4
  img_check_size(w, h)
  bm = Bitmap.new(w, h)
  qoi_run(a, 14, bm.rgba, w * h)
  bm

-> qoi_run(a, p, out, npx) (u8[] i64 u8[] i64) i64
  idx = u8[256]
  r = 0 ## i64
  g = 0 ## i64
  b = 0 ## i64
  al = 255 ## i64
  n = a.size - 8      # the 8-byte end marker
  n = a.size if n < p
  run = 0 ## i64
  i = 0 ## i64
  while i < npx
    if run > 0
      run -= 1
    elsif p < n
      b1 = a[p]
      p += 1
      if b1 == 0xFE
        break if p + 3 > a.size
        r = a[p]
        g = a[p + 1]
        b = a[p + 2]
        p += 3
      elsif b1 == 0xFF
        break if p + 4 > a.size
        r = a[p]
        g = a[p + 1]
        b = a[p + 2]
        al = a[p + 3]
        p += 4
      else
        tag = b1 >> 6
        if tag == 0
          k = (b1 & 63) * 4
          r = idx[k]
          g = idx[k + 1]
          b = idx[k + 2]
          al = idx[k + 3]
        elsif tag == 1
          r = (r + ((b1 >> 4) & 3) - 2) & 255
          g = (g + ((b1 >> 2) & 3) - 2) & 255
          b = (b + (b1 & 3) - 2) & 255
        elsif tag == 2
          break if p >= a.size
          b2 = a[p]
          p += 1
          dg = (b1 & 63) - 32
          r = (r + dg - 8 + ((b2 >> 4) & 15)) & 255
          g = (g + dg) & 255
          b = (b + dg - 8 + (b2 & 15)) & 255
        else
          run = b1 & 63
      k2 = ((r * 3 + g * 5 + b * 7 + al * 11) & 63) * 4
      idx[k2] = r
      idx[k2 + 1] = g
      idx[k2 + 2] = b
      idx[k2 + 3] = al
    else
      break
    o = i * 4
    out[o] = r
    out[o + 1] = g
    out[o + 2] = b
    out[o + 3] = al
    i += 1
  i

img_register("qoi", ->(b) qoi_sniff?(b), ->(b) qoi_decode(b))
