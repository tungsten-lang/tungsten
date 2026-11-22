# core/codec/image/icns — Apple icon images (.icns).
#
# Picks the largest icon the file holds: PNG or JPEG 2000 entries (ic07–ic14,
# icp4–icp6, ic04/ic05 when not ARGB) go through whichever registered decoder
# recognises them; "ARGB" entries (ic04/ic05) and the classic RLE 24-bit
# images (is32/il32/ih32/it32) with their 8-bit masks (s8mk/l8mk/h8mk/t8mk)
# are decoded here.
#
#   icns_sniff?(bytes) / icns_decode(bytes) → Bitmap

use core/codec/image

-> icns_sniff?(b)
  b.size >= 16 && b[0] == 105 && b[1] == 99 && b[2] == 110 && b[3] == 115

-> icns_type(a, o)
  s = StringBuffer()
  i = 0
  while i < 4
    s.append(a[o + i].chr)
    i += 1
  s.to_s

# Edge size of each icon type (0: not an image entry).
-> icns_size(t)
  return 16 if t == "icp4" || t == "is32" || t == "ic04"
  return 32 if t == "icp5" || t == "il32" || t == "ic05" || t == "ic11"
  return 48 if t == "ih32"
  return 64 if t == "icp6" || t == "ic12"
  return 128 if t == "ic07" || t == "it32"
  return 256 if t == "ic08" || t == "ic13"
  return 512 if t == "ic09" || t == "ic14"
  return 1024 if t == "ic10"
  0

-> icns_decode(data)
  a = img_bytes(data)
  img_fail("icns: not an icon file") if !icns_sniff?(a)
  n = img_be32(a, 4)
  n = a.size if n > a.size || n < 8
  entries = []     # [type, off, len, size]
  masks = {}
  p = 8
  while p + 8 <= n
    t = icns_type(a, p)
    len = img_be32(a, p + 4)
    break if len < 8 || p + len > n
    sz = icns_size(t)
    if sz > 0
      entries.push([t, p + 8, len - 8, sz])
    elsif t == "s8mk" || t == "l8mk" || t == "h8mk" || t == "t8mk"
      masks[t] = [p + 8, len - 8]
    p += len
  img_fail("icns: no icon images") if entries.size == 0
  # largest first; modern (PNG/JP2/ARGB) entries before classic RLE ones
  srt = entries.sort_by(->(e) 0 - e[3] * 2 - (icns_classic?(e[0]) ? 0 : 1))
  i = 0
  while i < srt.size
    e = srt[i]
    bm = nil
    begin
      bm = icns_entry(a, e, masks)
    rescue err
      bm = nil
    return bm if bm != nil
    i += 1
  img_fail("icns: no decodable icon image")

-> icns_classic?(t)
  t == "is32" || t == "il32" || t == "ih32" || t == "it32"

-> icns_entry(a, e, masks)
  t = e[0]
  off = e[1]
  len = e[2]
  sz = e[3]
  if icns_classic?(t)
    m = nil
    m = masks["s8mk"] if t == "is32"
    m = masks["l8mk"] if t == "il32"
    m = masks["h8mk"] if t == "ih32"
    m = masks["t8mk"] if t == "it32"
    skip = t == "it32" ? 4 : 0
    bm = Bitmap.new(sz, sz)
    icns_rle(a, off + skip, len - skip, bm.rgba, sz * sz, 0, 3, 4)
    icns_alpha(a, m == nil ? -1 : m[0], m == nil ? 0 : m[1], bm.rgba, sz * sz)
    return bm
  if len >= 4 && a[off] == 65 && a[off + 1] == 82 && a[off + 2] == 71 && a[off + 3] == 66
    # "ARGB": RLE planes A, R, G, B
    bm = Bitmap.new(sz, sz)
    icns_rle_argb(a, off + 4, len - 4, bm.rgba, sz * sz)
    return bm
  sub = u8[len]
  icns_copy(sub, a, off, len)
  img_decode(sub)

-> icns_copy(dst, src, off, n) (u8[] u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[i] = src[off + i]
    i += 1
  n

# Apple's icon RLE: each channel plane separately; a byte < 128 is n+1
# literal bytes, >= 128 repeats the next byte n-125 times. Planes nch at
# channel offsets c0.., stride 4 in out.
-> icns_rle(a, p, len, out, npx, c0, nch, stride) (u8[] i64 i64 u8[] i64 i64 i64 i64) i64
  e = p + len
  e = a.size if e > a.size
  # Uncompressed variant: exactly npx * nch bytes
  if len == npx * nch
    c = 0 ## i64
    while c < nch
      i = 0 ## i64
      while i < npx
        out[i * stride + c0 + c] = a[p + c * npx + i]
        i += 1
      c += 1
    return 0
  c = 0 ## i64
  while c < nch
    i = 0 ## i64
    while i < npx && p < e
      b = a[p] ## i64
      p += 1
      if b < 128
        k = b + 1
        while k > 0 && p < e && i < npx
          out[i * stride + c0 + c] = a[p]
          p += 1
          i += 1
          k -= 1
      else
        k = b - 125
        break if p >= e
        v = a[p]
        p += 1
        while k > 0 && i < npx
          out[i * stride + c0 + c] = v
          i += 1
          k -= 1
    c += 1
  0

-> icns_rle_argb(a, p, len, out, npx) (u8[] i64 i64 u8[] i64) i64
  tmp = u8[npx * 4]
  icns_rle(a, p, len, tmp, npx, 0, 4, 4)
  i = 0 ## i64
  while i < npx
    out[i * 4] = tmp[i * 4 + 1]
    out[i * 4 + 1] = tmp[i * 4 + 2]
    out[i * 4 + 2] = tmp[i * 4 + 3]
    out[i * 4 + 3] = tmp[i * 4]
    i += 1
  0

-> icns_alpha(a, moff, mlen, out, npx) (u8[] i64 i64 u8[] i64) i64
  i = 0 ## i64
  while i < npx
    v = 255 ## i64
    v = a[moff + i] if moff >= 0 && i < mlen && moff + i < a.size
    out[i * 4 + 3] = v
    i += 1
  0

img_register("icns", ->(b) icns_sniff?(b), ->(b) icns_decode(b))
