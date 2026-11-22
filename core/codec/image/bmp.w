# core/codec/image/bmp — BMP and ICO/CUR decoders in Tungsten.
#
# BMP: OS/2 (12-byte) and Windows (40/52/56/108/124-byte) headers; 1/2/4/8-bit
# palettes, 16/24/32-bit, BI_RLE8/BI_RLE4, BI_BITFIELDS/BI_ALPHABITFIELDS,
# embedded PNG (BI_PNG), bottom-up and top-down rows. 32-bit BI_RGB pixels are
# opaque unless the file carries a nonzero alpha byte somewhere, as browsers
# treat the "X" byte.
# ICO/CUR: the largest (then deepest) entry; PNG entries via core/codec/image/png, DIB
# entries with their AND mask for transparency (32-bit entries use alpha).
#
#   bmp_sniff?(b) / bmp_decode(b)
#   ico_sniff?(b) / ico_decode(b)

use core/codec/image
use png

-> bmp_sniff?(b)
  b.size >= 26 && b[0] == 66 && b[1] == 77

# 00 00 01|02 00, then a sane entry count whose directory fits, and a first
# entry with a zero reserved byte (an ISO-BMFF box of size 256/512 — AVIF,
# HEIC — also starts 00 00 01|02 00, followed by "ftyp").
-> ico_sniff?(b)
  return false if b.size < 22 || b[0] != 0 || b[1] != 0 || (b[2] != 1 && b[2] != 2) || b[3] != 0
  n = b[4] | (b[5] << 8)
  n >= 1 && n <= 256 && 6 + n * 16 <= b.size && b[9] == 0

-> bmp_decode(data)
  a = img_bytes(data)
  img_fail("bmp: not a BMP") if !bmp_sniff?(a)
  off = img_le32(a, 10)
  bmp_dib(a, 14, off, false)

# Mask helpers: shift and width of a contiguous bit mask.
-> bmp_shift(m) (i64) i64
  return 0 if m == 0
  s = 0 ## i64
  while (m & 1) == 0
    m = m >> 1
    s += 1
  s

-> bmp_bits(m) (i64) i64
  return 0 if m == 0
  while (m & 1) == 0
    m = m >> 1
  b = 0 ## i64
  while (m & 1) == 1
    m = m >> 1
    b += 1
  b

# Decode a DIB (info header at a[h]); pixel data at a[poff], or right after the
# palette when poff is 0 (ICO). icon: the height is doubled and an AND mask follows.
-> bmp_dib(a, h, poff, icon, limit = 0)
  hs = img_le32(a, h)
  w = 0
  ht = 0
  bpp = 0
  comp = 0
  ncol = 0
  rm = 0
  gm = 0
  bm = 0
  am = 0
  if hs == 12
    w = img_le16(a, h + 4)
    ht = img_le16(a, h + 6)
    bpp = img_le16(a, h + 10)
  elsif hs >= 16
    # Windows (40+) and OS/2 v2 (16..64) headers share the first fields; an
    # OS/2 v2 header may stop early (missing fields are zero).
    w = img_le32(a, h + 4)
    ht = img_le32(a, h + 8)
    ht = ht - 4294967296 if ht >= 2147483648
    bpp = img_le16(a, h + 14)
    comp = hs >= 20 ? img_le32(a, h + 16) : 0
    ncol = hs >= 36 ? img_le32(a, h + 32) : 0
    if hs >= 52 && hs != 64
      rm = img_le32(a, h + 40)
      gm = img_le32(a, h + 44)
      bm = img_le32(a, h + 48)
    am = img_le32(a, h + 52) if hs >= 56 && hs != 64
  else
    img_fail("bmp: unsupported header size " + hs.to_s)
  if comp == 5 || comp == 4
    # Embedded PNG (BI_PNG) / JPEG (BI_JPEG): decode the payload.
    start = poff > 0 ? poff : h + hs
    return img_decode(bmp_slice(a, start, a.size - start))
  top_down = ht < 0
  ht = 0 - ht if ht < 0
  ht = ht / 2 if icon
  img_check_size(w, ht)
  # Bit masks: after a 40-byte header for BI_BITFIELDS, inside larger headers.
  pal_at = h + hs
  if (comp == 3 || comp == 6) && hs == 40
    rm = img_le32(a, h + 40)
    gm = img_le32(a, h + 44)
    bm = img_le32(a, h + 48)
    pal_at = h + 52
    if comp == 6
      am = img_le32(a, h + 52)
      pal_at = h + 56
  if comp != 3 && comp != 6
    if bpp == 16
      rm = 0x7C00
      gm = 0x3E0
      bm = 0x1F
      am = 0
    elsif bpp == 32 || bpp == 24
      rm = 0xFF0000
      gm = 0xFF00
      bm = 0xFF
      # The fourth byte of BI_RGB 32-bit pixels is padding in a BMP; icons
      # (DIBs inside ICO/CUR) do carry alpha there.
      am = bpp == 32 && icon ? 0xFF000000 : 0
  pal = u8[1024]
  if bpp <= 8
    n = ncol == 0 || ncol > ((1 ## i64) << bpp) ? ((1 ## i64) << bpp) : ncol
    esz = hs == 12 ? 3 : 4
    i = 0
    while i < 256
      q = pal_at + i * esz
      if i < n && q + 2 < a.size
        pal[i * 4] = a[q + 2]
        pal[i * 4 + 1] = a[q + 1]
        pal[i * 4 + 2] = a[q]
      pal[i * 4 + 3] = 255
      i += 1
    pal_at += n * esz
  data_at = poff > 0 ? poff : pal_at
  out = Bitmap.new(w, ht)
  px = out.rgba
  zero_alpha = false
  if comp == 1 || comp == 2
    bmp_rle(a, data_at, w, ht, comp == 1 ? 8 : 4, pal, px)
  elsif bpp == 1 || bpp == 2 || bpp == 4 || bpp == 8
    bmp_indexed(a, data_at, w, ht, bpp, pal, px)
  elsif bpp == 24
    bmp_rgb24(a, data_at, w, ht, px)
  elsif bpp == 16 || bpp == 32
    bmp_masked(a, data_at, w, ht, bpp, rm, gm, bm, am, px)
    # 32-bit "BGRX": a zero alpha channel means opaque.
    if bpp == 32 && (am == 0 || bmp_all_zero_alpha(px) == 1)
      zero_alpha = true
      bmp_opaque(px)
  else
    img_fail("bmp: unsupported bit depth " + bpp.to_s)
  if icon && (bpp != 32 || zero_alpha)
    stride = (w * bpp + 31) / 32 * 4
    mstart = data_at + stride * ht
    # A mask that would run past the entry (some writers truncate it) is ignored.
    bmp_and_mask(a, mstart, w, ht, px) if mstart + (w + 31) / 32 * 4 * ht <= limit
  bmp_flip(px, w, ht) if !top_down
  out

-> bmp_slice(a, off, n) (u8[] i64 i64) u8[]
  n = 0 if n < 0
  b = u8[n]
  i = 0 ## i64
  while i < n
    b[i] = a[off + i]
    i += 1
  b

-> bmp_indexed(a, off, w, h, bpp, pal, px) (u8[] i64 i64 i64 i64 u8[] u8[]) i64
  stride = (w * bpp + 31) / 32 * 4
  per = 8 / bpp
  mask = ((1 ## i64) << bpp) - 1
  n = a.size
  y = 0 ## i64
  while y < h
    r = off + y * stride
    o = y * w * 4
    x = 0 ## i64
    while x < w
      bi = r + x / per
      if bi < n
        q = ((a[bi] >> (8 - bpp * (x % per + 1))) & mask) * 4
        px[o] = pal[q]
        px[o + 1] = pal[q + 1]
        px[o + 2] = pal[q + 2]
        px[o + 3] = 255
      o += 4
      x += 1
    y += 1
  0

-> bmp_rgb24(a, off, w, h, px) (u8[] i64 i64 i64 u8[]) i64
  stride = (w * 3 + 3) / 4 * 4
  n = a.size
  y = 0 ## i64
  while y < h
    r = off + y * stride
    o = y * w * 4
    x = 0 ## i64
    while x < w && r + 2 < n
      px[o] = a[r + 2]
      px[o + 1] = a[r + 1]
      px[o + 2] = a[r]
      px[o + 3] = 255
      r += 3
      o += 4
      x += 1
    y += 1
  0

# Scale a masked field to 8 bits (replicating high bits).
-> bmp_field(v, m, sh, bits) (i64 i64 i64 i64) i64
  return 0 if bits == 0
  f = (v & m) >> sh
  return f if bits == 8
  (f * 255 + (((1 ## i64) << bits) - 1) / 2) / (((1 ## i64) << bits) - 1)

-> bmp_masked(a, off, w, h, bpp, rm, gm, bm, am, px) (u8[] i64 i64 i64 i64 i64 i64 i64 i64 u8[]) i64
  stride = (w * bpp + 31) / 32 * 4
  bytes = bpp / 8
  rs = bmp_shift(rm)
  gs = bmp_shift(gm)
  bs = bmp_shift(bm)
  as = bmp_shift(am)
  rb = bmp_bits(rm)
  gb = bmp_bits(gm)
  bb = bmp_bits(bm)
  ab = bmp_bits(am)
  n = a.size
  y = 0 ## i64
  while y < h
    r = off + y * stride
    o = y * w * 4
    x = 0 ## i64
    while x < w && r + bytes <= n
      v = 0 ## i64
      if bytes == 2
        v = a[r] | (a[r + 1] << 8)
      else
        v = a[r] | (a[r + 1] << 8) | (a[r + 2] << 16) | (a[r + 3] << 24)
      px[o] = bmp_field(v, rm, rs, rb)
      px[o + 1] = bmp_field(v, gm, gs, gb)
      px[o + 2] = bmp_field(v, bm, bs, bb)
      px[o + 3] = am == 0 ? 255 : bmp_field(v, am, as, ab)
      r += bytes
      o += 4
      x += 1
    y += 1
  0

-> bmp_all_zero_alpha(px) (u8[]) i64
  i = 3 ## i64
  n = px.size
  while i < n
    return 0 if px[i] != 0
    i += 4
  1

-> bmp_opaque(px) (u8[]) i64
  i = 3 ## i64
  n = px.size
  while i < n
    px[i] = 255
    i += 4
  0

# Bottom-up storage: reverse the row order.
-> bmp_flip(px, w, h) (u8[] i64 i64) i64
  rb = w * 4
  y = 0 ## i64
  while y < h / 2
    p = y * rb
    q = (h - 1 - y) * rb
    i = 0 ## i64
    while i < rb
      t = px[p + i]
      px[p + i] = px[q + i]
      px[q + i] = t
      i += 1
    y += 1
  0

# Icon AND mask (1 bit per pixel, rows padded to 32 bits, bottom-up like the XOR image).
-> bmp_and_mask(a, off, w, h, px) (u8[] i64 i64 i64 u8[]) i64
  stride = (w + 31) / 32 * 4
  n = a.size
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      bi = off + y * stride + x / 8
      if bi < n && ((a[bi] >> (7 - x % 8)) & 1) == 1
        px[(y * w + x) * 4 + 3] = 0
      x += 1
    y += 1
  0

# RLE8 / RLE4 (rows bottom-up in file order; pixels not written stay transparent).
-> bmp_rle(a, off, w, h, bits, pal, px) (u8[] i64 i64 i64 i64 u8[] u8[]) i64
  n = a.size
  p = off
  x = 0 ## i64
  y = 0 ## i64
  while p + 1 < n && y < h
    c = a[p]
    v = a[p + 1]
    p += 2
    if c > 0
      k = 0 ## i64
      while k < c
        idx = v
        if bits == 4
          idx = (k & 1) == 0 ? (v >> 4) : (v & 15)
        if x < w
          q = idx * 4
          o = (y * w + x) * 4
          px[o] = pal[q]
          px[o + 1] = pal[q + 1]
          px[o + 2] = pal[q + 2]
          px[o + 3] = 255
        x += 1
        k += 1
    elsif v == 0
      x = 0
      y += 1
    elsif v == 1
      return 0
    elsif v == 2
      break if p + 1 >= n
      x += a[p]
      y += a[p + 1]
      p += 2
    else
      k = 0 ## i64
      while k < v && p < n
        idx = 0 ## i64
        if bits == 8
          idx = a[p + k]
        else
          b = a[p + k / 2]
          idx = (k & 1) == 0 ? (b >> 4) : (b & 15)
        if x < w
          q = idx * 4
          o = (y * w + x) * 4
          px[o] = pal[q]
          px[o + 1] = pal[q + 1]
          px[o + 2] = pal[q + 2]
          px[o + 3] = 255
        x += 1
        k += 1
      used = bits == 8 ? v : (v + 1) / 2
      p += (used + 1) / 2 * 2
  0

-> ico_decode(data)
  a = img_bytes(data)
  img_fail("ico: not an icon") if !ico_sniff?(a)
  count = img_le16(a, 4)
  best = -1
  best_score = -1
  i = 0
  while i < count
    e = 6 + i * 16
    break if e + 16 > a.size
    w = a[e] == 0 ? 256 : a[e]
    h = a[e + 1] == 0 ? 256 : a[e + 1]
    bpp = img_le16(a, e + 6)
    size = img_le32(a, e + 8)
    off = img_le32(a, e + 12)
    if off + size <= a.size && size > 0
      score = w * h * 64 + bpp
      if score > best_score
        best_score = score
        best = i
    i += 1
  img_fail("ico: no usable entry") if best < 0
  e = 6 + best * 16
  size = img_le32(a, e + 8)
  off = img_le32(a, e + 12)
  if png_sniff?(bmp_slice(a, off, 8))
    return png_decode(bmp_slice(a, off, size))
  bmp_dib(a, off, 0, true, off + size)

img_register("bmp", ->(b) bmp_sniff?(b), ->(b) bmp_decode(b))
img_register("ico", ->(b) ico_sniff?(b), ->(b) ico_decode(b))
