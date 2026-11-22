# core/codec/image/gputex — GPU texture containers: DDS and KTX2 (first mip level, first
# layer/face), as ImageIO shows them.
#
# Pixel formats: BC1 (DXT1, with 1-bit alpha), BC2 (DXT3), BC3 (DXT5), BC4
# (ATI1, red), BC5 (ATI2, red/green), 8-bit RGBA/BGRA/RGB/R/RG, DDS bit-mask
# formats (RGB, luminance, alpha), and 16/32-bit float RGBA (tone-mapped via
# core/codec/image/imgfloat). KTX2 levels may be zlib-supercompressed.
# Not supported (ImageError): BC6H and BC7, ETC/ASTC/PVRTC, KTX2 BasisLZ
# (ETC1S) and UASTC supercompression (these are GPU transcoding formats that
# WebGL apps decode themselves) and Zstandard supercompression.
#
#   dds_sniff?(b) / dds_decode(b)     "DDS "
#   ktx2_sniff?(b) / ktx2_decode(b)   «KTX 20»

use core/codec/image
use imgfloat

-> dds_sniff?(b)
  b.size >= 128 && b[0] == 68 && b[1] == 68 && b[2] == 83 && b[3] == 32

KTX2_ID = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]

-> ktx2_sniff?(b)
  return false if b.size < 80
  i = 0
  while i < 12
    return false if b[i] != KTX2_ID[i]
    i += 1
  true

# Formats (internal): 1 BC1, 2 BC2, 3 BC3, 4 BC4, 5 BC5, 10 RGBA8, 11 BGRA8,
# 12 BGRX8, 13 RGB8, 14 R8, 15 RG8, 20 RGBA16F, 21 RGBA32F, 30 masks (DDS).

-> dds_decode(data)
  a = img_bytes(data)
  img_fail("dds: not a DDS file") if !dds_sniff?(a)
  h = img_le32(a, 12)
  w = img_le32(a, 16)
  pff = img_le32(a, 80)
  cc = img_le32(a, 84)
  bits = img_le32(a, 88)
  masks = [img_le32(a, 92), img_le32(a, 96), img_le32(a, 100), img_le32(a, 104)]
  off = 128
  fmt = 0
  if (pff & 4) != 0
    if cc == 0x31545844
      fmt = 1
    elsif cc == 0x32545844 || cc == 0x33545844
      fmt = 2
    elsif cc == 0x34545844 || cc == 0x35545844
      fmt = 3
    elsif cc == 0x31495441 || cc == 0x55344342
      fmt = 4
    elsif cc == 0x32495441 || cc == 0x55354342
      fmt = 5
    elsif cc == 113
      fmt = 20
    elsif cc == 116
      fmt = 21
    elsif cc == 0x30315844
      dx = img_le32(a, 128)
      off = 148
      fmt = gtex_dxgi(dx)
    else
      img_fail("dds: unsupported FourCC " + cc.to_s)
  else
    fmt = 30
    img_fail("dds: unsupported bit count " + bits.to_s) if bits != 8 && bits != 16 && bits != 24 && bits != 32
    # DDPF_ALPHAPIXELS / DDPF_ALPHA give an alpha mask; without them ignore it
    masks[3] = 0 if (pff & 3) == 0
    # luminance: one mask in R
    if (pff & 0x20000) != 0
      masks[1] = masks[0]
      masks[2] = masks[0]
    elsif (pff & 2) != 0 && (pff & 0x40) == 0
      masks[0] = 0
      masks[1] = 0
      masks[2] = 0
  img_check_size(w, h)
  bm = Bitmap.new(w, h)
  gtex_decode(a, off, a.size - off, fmt, w, h, bits, masks, bm.rgba)
  bm

-> gtex_dxgi(dx)
  return 10 if dx == 28 || dx == 29 || dx == 27
  return 11 if dx == 87 || dx == 91
  return 12 if dx == 88 || dx == 93
  return 1 if dx == 71 || dx == 72 || dx == 70
  return 2 if dx == 74 || dx == 75 || dx == 73
  return 3 if dx == 77 || dx == 78 || dx == 76
  return 4 if dx == 80 || dx == 79
  return 5 if dx == 83 || dx == 82
  return 14 if dx == 61
  return 15 if dx == 49
  return 20 if dx == 10
  return 21 if dx == 2
  img_fail("dds: BC6H/BC7 textures are not supported") if dx >= 94 && dx <= 99
  img_fail("dds: unsupported DXGI format " + dx.to_s)

-> gtex_vk(vk)
  return 10 if vk == 37 || vk == 43
  return 13 if vk == 23 || vk == 29
  return 11 if vk == 44 || vk == 50
  return 14 if vk == 9 || vk == 15
  return 15 if vk == 16 || vk == 22
  return 1 if vk >= 131 && vk <= 134
  return 2 if vk == 135 || vk == 136
  return 3 if vk == 137 || vk == 138
  return 4 if vk == 139
  return 5 if vk == 141
  return 20 if vk == 97
  return 21 if vk == 109
  img_fail("ktx2: Basis Universal (ETC1S/UASTC) textures are not supported") if vk == 0
  img_fail("ktx2: BC6H/BC7 textures are not supported") if vk >= 143 && vk <= 146
  img_fail("ktx2: unsupported vkFormat " + vk.to_s)

-> ktx2_decode(data)
  a = img_bytes(data)
  img_fail("ktx2: not a KTX2 file") if !ktx2_sniff?(a)
  vk = img_le32(a, 12)
  w = img_le32(a, 20)
  h = img_le32(a, 24)
  h = 1 if h == 0
  sc = img_le32(a, 44)
  img_fail("ktx2: BasisLZ supercompression is not supported") if sc == 1
  img_fail("ktx2: Zstandard supercompression is not supported") if sc == 2
  img_fail("ktx2: unknown supercompression") if sc > 3
  fmt = gtex_vk(vk)
  # level 0 index entry right after the 80-byte header
  loff = img_le32(a, 80) | (img_le32(a, 84) << 32)
  llen = img_le32(a, 88) | (img_le32(a, 92) << 32)
  ulen = img_le32(a, 96) | (img_le32(a, 100) << 32)
  img_fail("ktx2: bad level index") if loff <= 0 || loff + llen > a.size
  img_check_size(w, h)
  src = a
  soff = loff
  slen = llen
  if sc == 3
    z = u8[llen]
    i = 0
    while i < llen
      z[i] = a[loff + i]
      i += 1
    src = img_bytes(Gzip.inflate_zlib(z, 0, ulen + 1, false))
    soff = 0
    slen = src.size
  bm = Bitmap.new(w, h)
  gtex_decode(src, soff, slen, fmt, w, h, 0, [0, 0, 0, 0], bm.rgba)
  bm

-> gtex_decode(a, off, len, fmt, w, h, bits, masks, out)
  if fmt >= 1 && fmt <= 5
    bw = (w + 3) / 4
    bh = (h + 3) / 4
    bsz = (fmt == 1 || fmt == 4) ? 8 : 16
    img_fail("gputex: truncated texture data") if off + bw * bh * bsz > a.size
    gtex_bc(a, off, fmt, w, h, out)
  elsif fmt == 20 || fmt == 21
    bpp = fmt == 20 ? 8 : 16
    img_fail("gputex: truncated texture data") if off + w * h * bpp > a.size
    tb = imgf_tables()
    gtex_float(a, off, fmt == 20 ? 2 : 4, w * h, out, tb[0], tb[1])
  elsif fmt == 30
    bpp = bits / 8
    img_fail("gputex: truncated texture data") if off + w * h * bpp > a.size
    m = i64[4]
    m[0] = masks[0]
    m[1] = masks[1]
    m[2] = masks[2]
    m[3] = masks[3]
    gtex_masks(a, off, bpp, w * h, m, out)
  else
    bpp = 4
    bpp = 3 if fmt == 13
    bpp = 1 if fmt == 14
    bpp = 2 if fmt == 15
    img_fail("gputex: truncated texture data") if off + w * h * bpp > a.size
    gtex_plain(a, off, fmt, w * h, out)
  nil

-> gtex_plain(a, off, fmt, n, out) (u8[] i64 i64 i64 u8[]) i64
  i = 0 ## i64
  while i < n
    d = i * 4
    if fmt == 10
      s = off + i * 4
      out[d] = a[s]
      out[d + 1] = a[s + 1]
      out[d + 2] = a[s + 2]
      out[d + 3] = a[s + 3]
    elsif fmt == 11 || fmt == 12
      s = off + i * 4
      out[d] = a[s + 2]
      out[d + 1] = a[s + 1]
      out[d + 2] = a[s]
      out[d + 3] = fmt == 11 ? a[s + 3] : 255
    elsif fmt == 13
      s = off + i * 3
      out[d] = a[s]
      out[d + 1] = a[s + 1]
      out[d + 2] = a[s + 2]
      out[d + 3] = 255
    elsif fmt == 14
      out[d] = a[off + i]
      out[d + 3] = 255
    else
      out[d] = a[off + i * 2]
      out[d + 1] = a[off + i * 2 + 1]
      out[d + 3] = 255
    i += 1
  0

-> gtex_mshift(m) (i64) i64
  return 0 if m == 0
  s = 0 ## i64
  while (m & 1) == 0
    m = m >> 1
    s += 1
  s

-> gtex_mchan(v, m) (i64 i64) i64
  return -1 if m == 0
  s = gtex_mshift(m)
  mx = m >> s
  ((v & m) >> s) * 255 / mx

-> gtex_masks(a, off, bpp, n, m, out) (u8[] i64 i64 i64 i64[] u8[]) i64
  i = 0 ## i64
  while i < n
    s = off + i * bpp
    v = 0 ## i64
    k = 0 ## i64
    while k < bpp
      bv = a[s + k] ## i64
      v = v | (bv << (8 * k))
      k += 1
    r = gtex_mchan(v, m[0])
    g = gtex_mchan(v, m[1])
    b = gtex_mchan(v, m[2])
    al = gtex_mchan(v, m[3])
    out[i * 4] = r < 0 ? 0 : r
    out[i * 4 + 1] = g < 0 ? 0 : g
    out[i * 4 + 2] = b < 0 ? 0 : b
    out[i * 4 + 3] = al < 0 ? 255 : al
    i += 1
  0

-> gtex_float(a, off, bpc, n, out, p2, lut) (u8[] i64 i64 i64 u8[] f64[] u8[]) i64
  i = 0 ## i64
  while i < n
    s = off + i * bpc * 4
    r = ~0.0
    g = ~0.0
    b = ~0.0
    al = ~1.0
    if bpc == 2
      r = imgf_f16(img_le16(a, s), p2)
      g = imgf_f16(img_le16(a, s + 2), p2)
      b = imgf_f16(img_le16(a, s + 4), p2)
      al = imgf_f16(img_le16(a, s + 6), p2)
    else
      r = imgf_f32(img_le32(a, s), p2)
      g = imgf_f32(img_le32(a, s + 4), p2)
      b = imgf_f32(img_le32(a, s + 8), p2)
      al = imgf_f32(img_le32(a, s + 12), p2)
    al = ~0.0 if al < ~0.0
    al = ~1.0 if al > ~1.0
    imgf_px(out, i * 4, r, g, b, al, lut)
    i += 1
  0

# ---- BC1-BC5 ----

-> gtex_bc(a, off, fmt, w, h, out) (u8[] i64 i64 i64 i64 u8[]) i64
  bw = (w + 3) / 4
  bh = (h + 3) / 4
  bsz = (fmt == 1 || fmt == 4) ? 8 : 16
  blk = u8[64]
  ch = u8[16]
  by = 0 ## i64
  while by < bh
    bx = 0 ## i64
    while bx < bw
      p = off + (by * bw + bx) * bsz
      if fmt == 1
        gtex_bc1(a, p, blk, true)
      elsif fmt == 2
        gtex_bc1(a, p + 8, blk, false)
        k = 0 ## i64
        while k < 16
          v = (a[p + (k >> 1)] >> ((k & 1) * 4)) & 15
          blk[k * 4 + 3] = v * 17
          k += 1
      elsif fmt == 3
        gtex_bc1(a, p + 8, blk, false)
        gtex_bc4(a, p, ch)
        k = 0
        while k < 16
          blk[k * 4 + 3] = ch[k]
          k += 1
      elsif fmt == 4
        gtex_bc4(a, p, ch)
        k = 0
        while k < 16
          blk[k * 4] = ch[k]
          blk[k * 4 + 1] = 0
          blk[k * 4 + 2] = 0
          blk[k * 4 + 3] = 255
          k += 1
      else
        gtex_bc4(a, p, ch)
        k = 0
        while k < 16
          blk[k * 4] = ch[k]
          blk[k * 4 + 2] = 0
          blk[k * 4 + 3] = 255
          k += 1
        gtex_bc4(a, p + 8, ch)
        k = 0
        while k < 16
          blk[k * 4 + 1] = ch[k]
          k += 1
      y = 0 ## i64
      while y < 4
        x = 0 ## i64
        while x < 4
          px = bx * 4 + x
          py = by * 4 + y
          if px < w && py < h
            d = (py * w + px) * 4
            s = (y * 4 + x) * 4
            out[d] = blk[s]
            out[d + 1] = blk[s + 1]
            out[d + 2] = blk[s + 2]
            out[d + 3] = blk[s + 3]
          x += 1
        y += 1
      bx += 1
    by += 1
  0

-> gtex_565(c, rgb) (i64 i64[]) i64
  r = (c >> 11) & 31
  g = (c >> 5) & 63
  b = c & 31
  rgb[0] = (r << 3) | (r >> 2)
  rgb[1] = (g << 2) | (g >> 4)
  rgb[2] = (b << 3) | (b >> 2)
  0

-> gtex_bc1(a, p, blk, alpha_mode) (u8[] i64 u8[] bool) i64
  c0 = img_le16(a, p)
  c1 = img_le16(a, p + 2)
  pal = i64[16]
  rgb = i64[3]
  gtex_565(c0, rgb)
  pal[0] = rgb[0]
  pal[1] = rgb[1]
  pal[2] = rgb[2]
  pal[3] = 255
  gtex_565(c1, rgb)
  pal[4] = rgb[0]
  pal[5] = rgb[1]
  pal[6] = rgb[2]
  pal[7] = 255
  four = c0 > c1 || !alpha_mode
  k = 0 ## i64
  while k < 3
    if four
      pal[8 + k] = (2 * pal[k] + pal[4 + k] + 1) / 3
      pal[12 + k] = (pal[k] + 2 * pal[4 + k] + 1) / 3
    else
      pal[8 + k] = (pal[k] + pal[4 + k]) / 2
      pal[12 + k] = 0
    k += 1
  pal[11] = 255
  pal[15] = four ? 255 : 0
  bits = img_le32(a, p + 4)
  i = 0 ## i64
  while i < 16
    ix = (bits >> (i * 2)) & 3
    blk[i * 4] = pal[ix * 4]
    blk[i * 4 + 1] = pal[ix * 4 + 1]
    blk[i * 4 + 2] = pal[ix * 4 + 2]
    blk[i * 4 + 3] = pal[ix * 4 + 3]
    i += 1
  0

-> gtex_bc4(a, p, ch) (u8[] i64 u8[]) i64
  a0 = a[p] ## i64
  a1 = a[p + 1] ## i64
  pal = i64[8]
  pal[0] = a0
  pal[1] = a1
  if a0 > a1
    k = 1 ## i64
    while k < 7
      pal[k + 1] = ((7 - k) * a0 + k * a1 + 3) / 7
      k += 1
  else
    k = 1
    while k < 5
      pal[k + 1] = ((5 - k) * a0 + k * a1 + 2) / 5
      k += 1
    pal[6] = 0
    pal[7] = 255
  bits = 0 ## i64
  k = 0
  while k < 6
    bv = a[p + 2 + k] ## i64
    bits = bits | (bv << (8 * k))
    k += 1
  i = 0 ## i64
  while i < 16
    ch[i] = pal[(bits >> (i * 3)) & 7]
    i += 1
  0

img_register("dds", ->(b) dds_sniff?(b), ->(b) dds_decode(b))
img_register("ktx2", ->(b) ktx2_sniff?(b), ->(b) ktx2_decode(b))
