# core/codec/image/tga — Truevision TGA decoder.
#
# Image types 1/2/3 (colour-mapped, true-colour, greyscale) and their RLE
# forms 9/10/11; 8/15/16/24/32-bit pixels and 15/16/24/32-bit colour maps;
# any origin (bottom-left default, top and right flags). 32-bit (and 16-bit
# with an attribute bit) pixels carry alpha when the descriptor says so,
# unless a TGA 2.0 extension area marks the alpha as undefined/ignored, or
# every alpha value is 0 (old writers leave the byte zero), as ImageIO does.
#
# TGA has no magic number, so the sniffer checks that every header field is
# plausible and the pixel data fits (or the TGA 2.0 footer is present); it is
# tried late, after every format that has a signature.
#
#   tga_sniff?(bytes) / tga_decode(bytes) → Bitmap

use core/codec/image

-> tga_footer?(a)
  n = a.size
  return false if n < 44
  sig = "TRUEVISION-XFILE."
  i = 0
  while i < 17
    return false if a[n - 18 + i] != sig.byte_at(i)
    i += 1
  true

-> tga_sniff?(b)
  return false if b.size < 18
  idl = b[0]
  cmt = b[1]
  it = b[2]
  return false if cmt > 1
  return false if it != 1 && it != 2 && it != 3 && it != 9 && it != 10 && it != 11
  cmlen = b[5] | (b[6] << 8)
  cmbits = b[7]
  w = b[12] | (b[13] << 8)
  h = b[14] | (b[15] << 8)
  bpp = b[16]
  desc = b[17]
  return false if w == 0 || h == 0
  return false if (desc & 0xC0) != 0          # interleaving: never used, a strong "not TGA"
  mapped = it == 1 || it == 9
  if mapped
    return false if cmt != 1 || cmlen == 0 || bpp != 8 && bpp != 16
    return false if cmbits != 15 && cmbits != 16 && cmbits != 24 && cmbits != 32
  elsif it == 3 || it == 11
    return false if bpp != 8 && bpp != 16
  else
    return false if bpp != 15 && bpp != 16 && bpp != 24 && bpp != 32
  return false if cmt == 1 && cmbits != 15 && cmbits != 16 && cmbits != 24 && cmbits != 32
  return true if tga_footer?(b)
  # Without the footer insist that uncompressed data fits exactly enough.
  cmb = cmt == 1 ? cmlen * ((cmbits + 7) / 8) : 0
  data = 18 + idl + cmb
  if it < 9
    need = data + w * h * ((bpp + 7) / 8)
    return b.size >= need && b.size <= need + 65536
  b.size > data

-> tga_decode(data)
  a = img_bytes(data)
  img_fail("tga: not a TGA image") if !tga_sniff?(a)
  idl = a[0]
  cmt = a[1]
  it = a[2]
  cmfirst = img_le16(a, 3)
  cmlen = img_le16(a, 5)
  cmbits = a[7]
  w = img_le16(a, 12)
  h = img_le16(a, 14)
  bpp = a[16]
  desc = a[17]
  img_check_size(w, h)
  p = 18 + idl
  # colour map → RGBA u8[256*4] (or larger)
  cm = nil
  if cmt == 1
    cmb = (cmbits + 7) / 8
    cm = u8[(cmfirst + cmlen) * 4 + 4]
    tga_cmap(a, p, cmfirst, cmlen, cmbits, cm)
    p += cmlen * cmb
  abits = desc & 15
  bypp = (bpp + 7) / 8
  # unpack (RLE or raw) into raw pixel bytes in file order
  raw = nil
  if it >= 9
    raw = u8[w * h * bypp]
    tga_rle(a, p, raw, w * h, bypp)
  else
    raw = u8[w * h * bypp]
    n = w * h * bypp
    n = a.size - p if p + n > a.size
    img_fail("tga: truncated") if n < 0
    tga_copy(raw, a, p, n)
  use_alpha = abits > 0 && (bpp == 32 || bpp == 16)
  # TGA 2.0 extension area: attribute type (0 none, 1/2 ignore, 3 alpha, 4 premultiplied)
  if tga_footer?(a)
    ext = img_le32(a, a.size - 26)
    if ext > 0 && ext + 495 <= a.size && img_le16(a, ext) >= 495
      at = a[ext + 494]
      use_alpha = false if at == 0 || at == 1 || at == 2
  if bpp == 32 && use_alpha && !tga_grey_type(it)
    use_alpha = tga_any_alpha(raw, w * h) == 1
  bm = Bitmap.new(w, h)
  grey = it == 3 || it == 11
  tga_expand(raw, w, h, bpp, grey, use_alpha, cm == nil ? u8[4] : cm, cm != nil, (desc & 0x20) != 0, (desc & 0x10) != 0, bm.rgba)
  bm

-> tga_grey_type(it)
  it == 3 || it == 11

-> tga_copy(dst, src, off, n) (u8[] u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[i] = src[off + i]
    i += 1
  n

-> tga_any_alpha(raw, n) (u8[] i64) i64
  i = 0 ## i64
  while i < n
    return 1 if raw[i * 4 + 3] != 0
    i += 1
  0

# 15/16-bit ARRRRRGG GGGBBBBB (little-endian) → 8-bit channels.
-> tga_c5(v) (i64) i64
  (v << 3) | (v >> 2)

-> tga_cmap(a, p, first, len, bits, cm) (u8[] i64 i64 i64 i64 u8[]) i64
  bypp = (bits + 7) / 8
  i = 0 ## i64
  while i < len
    o = p + i * bypp
    d = (first + i) * 4
    if o + bypp <= a.size
      if bypp == 2
        v = a[o] | (a[o + 1] << 8)
        cm[d] = tga_c5((v >> 10) & 31)
        cm[d + 1] = tga_c5((v >> 5) & 31)
        cm[d + 2] = tga_c5(v & 31)
        cm[d + 3] = 255
      else
        cm[d] = a[o + 2]
        cm[d + 1] = a[o + 1]
        cm[d + 2] = a[o]
        cm[d + 3] = bypp == 4 ? a[o + 3] : 255
    i += 1
  0

-> tga_rle(a, p, raw, npx, bypp) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  n = a.size
  while i < npx && p < n
    hd = a[p]
    p += 1
    cnt = (hd & 127) + 1
    if (hd & 128) != 0
      break if p + bypp > n
      k = 0 ## i64
      while k < cnt && i < npx
        j = 0 ## i64
        while j < bypp
          raw[i * bypp + j] = a[p + j]
          j += 1
        i += 1
        k += 1
      p += bypp
    else
      k = 0 ## i64
      while k < cnt && i < npx
        break if p + bypp > n
        j = 0 ## i64
        while j < bypp
          raw[i * bypp + j] = a[p + j]
          j += 1
        p += bypp
        i += 1
        k += 1
  i

-> tga_expand(raw, w, h, bpp, grey, alpha, cm, mapped, top, right, out) (u8[] i64 i64 i64 bool bool u8[] bool bool bool u8[]) i64
  bypp = (bpp + 7) / 8
  ncm = cm.size / 4
  y = 0 ## i64
  while y < h
    dy = top ? y : h - 1 - y
    x = 0 ## i64
    while x < w
      dx = right ? w - 1 - x : x
      s = (y * w + x) * bypp
      d = (dy * w + dx) * 4
      if mapped
        idx = bypp == 2 ? raw[s] | (raw[s + 1] << 8) : raw[s]
        if idx < ncm
          out[d] = cm[idx * 4]
          out[d + 1] = cm[idx * 4 + 1]
          out[d + 2] = cm[idx * 4 + 2]
          out[d + 3] = cm[idx * 4 + 3]
        else
          out[d + 3] = 255
      elsif grey
        g = raw[s]
        out[d] = g
        out[d + 1] = g
        out[d + 2] = g
        out[d + 3] = bypp == 2 && alpha ? raw[s + 1] : 255
        out[d + 3] = 255 if bypp == 2 && !alpha
      elsif bypp == 2
        v = raw[s] | (raw[s + 1] << 8)
        out[d] = tga_c5((v >> 10) & 31)
        out[d + 1] = tga_c5((v >> 5) & 31)
        out[d + 2] = tga_c5(v & 31)
        out[d + 3] = alpha && (v & 0x8000) == 0 ? 0 : 255
      else
        out[d] = raw[s + 2]
        out[d + 1] = raw[s + 1]
        out[d + 2] = raw[s]
        out[d + 3] = bypp == 4 && alpha ? raw[s + 3] : 255
      x += 1
    y += 1
  0

img_register("tga", ->(b) tga_sniff?(b), ->(b) tga_decode(b))
