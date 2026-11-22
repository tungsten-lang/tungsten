# core/codec/image/exr — OpenEXR decoder (single-part scanline and tiled images).
#
# Compression: NONE, RLE, ZIPS, ZIP, PIZ (wavelet + Huffman), PXR24, B44 and
# B44A. Channels HALF, FLOAT and UINT; R/G/B/A (also in a layer, "name.R"),
# or Y (luminance) shown as grey. Tiled files decode their level-0 tiles.
# Values are scene-linear Rec.709 and tone-mapped to sRGB by core/codec/image/imgfloat
# (exposure 1). The data window is the image.
# Not supported (ImageError): DWAA/DWAB, multi-part and deep images,
# subsampled luminance/chroma (RY/BY) images.
#
#   exr_sniff?(bytes)   76 2F 31 01
#   exr_decode(bytes)   → Bitmap

use core/codec/image
use imgfloat

-> exr_sniff?(b)
  b.size >= 8 && b[0] == 0x76 && b[1] == 0x2F && b[2] == 0x31 && b[3] == 0x01

-> exr_s32(v)
  v >= 2147483648 ? v - 4294967296 : v

-> exr_cstr(a, p)
  s = StringBuffer()
  while p < a.size && a[p] != 0
    s.append(a[p].chr)
    p += 1
  [s.to_s, p + 1]

# Lines per compressed block for each compression.
-> exr_lines(c)
  return 16 if c == 3 || c == 5
  return 32 if c == 4 || c == 6 || c == 7
  return 32 if c == 8
  return 256 if c == 9
  1

-> exr_decode(data)
  a = img_bytes(data)
  img_fail("exr: not an OpenEXR image") if !exr_sniff?(a)
  ver = img_le32(a, 4)
  img_fail("exr: multi-part/deep images are not supported") if (ver & 0x1800) != 0
  tiled = (ver & 0x200) != 0
  p = 8
  chans = []      # [name, type, xs, ys]
  comp = 0
  dw = nil
  tile = nil
  while p < a.size && a[p] != 0
    nm = exr_cstr(a, p)
    ty = exr_cstr(a, nm[1])
    sz = img_le32(a, ty[1])
    v = ty[1] + 4
    img_fail("exr: truncated header") if v + sz > a.size
    if nm[0] == "channels"
      q = v
      while q < v + sz && a[q] != 0
        cn = exr_cstr(a, q)
        q = cn[1]
        chans.push([cn[0], img_le32(a, q), exr_s32(img_le32(a, q + 8)), exr_s32(img_le32(a, q + 12))])
        q += 16
    elsif nm[0] == "compression"
      comp = a[v]
    elsif nm[0] == "dataWindow"
      dw = [exr_s32(img_le32(a, v)), exr_s32(img_le32(a, v + 4)), exr_s32(img_le32(a, v + 8)), exr_s32(img_le32(a, v + 12))]
    elsif nm[0] == "tiles"
      tile = [img_le32(a, v), img_le32(a, v + 4), a[v + 8]]
    p = v + sz
  p += 1
  img_fail("exr: no dataWindow") if dw == nil
  img_fail("exr: DWA compression is not supported") if comp == 8 || comp == 9
  img_fail("exr: unknown compression " + comp.to_s) if comp > 7
  w = dw[2] - dw[0] + 1
  h = dw[3] - dw[1] + 1
  img_check_size(w, h)
  img_fail("exr: no channels") if chans.size == 0
  # channels are stored sorted by name (the header lists them sorted)
  ri = exr_find(chans, "R")
  gi = exr_find(chans, "G")
  bi = exr_find(chans, "B")
  ai = exr_find(chans, "A")
  yi = exr_find(chans, "Y")
  if ri < 0 && yi < 0
    img_fail("exr: no R/G/B or Y channel")
  # pixel-level layout: per channel [type, size in bytes, xs, ys]
  nc = chans.size
  ct = i64[nc * 4]
  i = 0
  while i < nc
    c = chans[i]
    ct[i * 4] = c[1]
    ct[i * 4 + 1] = c[1] == 1 ? 2 : 4
    ct[i * 4 + 2] = c[2] < 1 ? 1 : c[2]
    ct[i * 4 + 3] = c[3] < 1 ? 1 : c[3]
    i += 1
  sel = i64[5]
  sel[0] = ri
  sel[1] = gi
  sel[2] = bi
  sel[3] = ai
  sel[4] = yi
  [ri, gi, bi, ai, yi].each ->(k)
    img_fail("exr: subsampled channels are not supported") if k >= 0 && (ct[k * 4 + 2] != 1 || ct[k * 4 + 3] != 1)
  bm = Bitmap.new(w, h)
  tb = imgf_tables()
  dec = ExrBlocks.new(a, comp, ct, nc, sel, w, h, bm.rgba, tb[0], tb[1])
  if tiled
    img_fail("exr: tiled image without tile description") if tile == nil
    tw = tile[0]
    th = tile[1]
    img_fail("exr: bad tile size") if tw <= 0 || th <= 0
    nt = ((w + tw - 1) / tw) * ((h + th - 1) / th)
    k = 0
    while k < nt
      off = img_le32(a, p + k * 8) | (img_le32(a, p + k * 8 + 4) << 32)
      if off > 0 && off + 20 <= a.size
        tx = exr_s32(img_le32(a, off))
        ty2 = exr_s32(img_le32(a, off + 4))
        lx = img_le32(a, off + 8)
        ly = img_le32(a, off + 12)
        ds = img_le32(a, off + 16)
        if lx == 0 && ly == 0 && tx >= 0 && ty2 >= 0
          x0 = tx * tw
          y0 = ty2 * th
          bw2 = x0 + tw > w ? w - x0 : tw
          bh2 = y0 + th > h ? h - y0 : th
          dec.block(off + 20, ds, x0, y0, bw2, bh2) if bw2 > 0 && bh2 > 0
      k += 1
  else
    lpb = exr_lines(comp)
    nb = (h + lpb - 1) / lpb
    k = 0
    while k < nb
      off = img_le32(a, p + k * 8) | (img_le32(a, p + k * 8 + 4) << 32)
      if off > 0 && off + 8 <= a.size
        y = exr_s32(img_le32(a, off)) - dw[1]
        ds = img_le32(a, off + 4)
        lines = y + lpb > h ? h - y : lpb
        dec.block(off + 8, ds, 0, y, w, lines) if y >= 0 && y < h && lines > 0
      k += 1
  bm

# Index of channel "X" (or "<layer>.X" if there is no plain one), -1 if none.
-> exr_find(chans, nm)
  i = 0
  while i < chans.size
    return i if chans[i][0] == nm
    i += 1
  i = 0
  while i < chans.size
    return i if chans[i][0].ends_with?("." + nm)
    i += 1
  -1

+ ExrBlocks
  -> new(@a, @comp, @ct, @nc, @sel, @w, @h, @out, @p2, @lut)

  # Bytes one block of bw x lines takes uncompressed (scanline layout).
  -> raw_size(bw, y0, lines)
    n = 0
    y = y0
    while y < y0 + lines
      c = 0
      while c < @nc
        ys = @ct[c * 4 + 3]
        n += (bw / @ct[c * 4 + 2]) * @ct[c * 4 + 1] if y % ys == 0
        c += 1
      y += 1
    n

  -> block(off, ds, x0, y0, bw, lines)
    return nil if ds <= 0 || off + ds > @a.size
    want = raw_size(bw, y0, lines)
    raw = nil
    if ds >= want || @comp == 0
      raw = u8[want]
      exr_copy(raw, 0, @a, off, ds < want ? ds : want)
    elsif @comp == 1
      t = u8[want]
      exr_rle(@a, off, ds, t, want)
      raw = u8[want]
      exr_unpredict(t, want, raw)
    elsif @comp == 2 || @comp == 3
      t = inflate(off, ds, want)
      return nil if t == nil
      raw = u8[want]
      exr_unpredict(t, want, raw)
    elsif @comp == 5
      t = inflate(off, ds, want)
      return nil if t == nil
      raw = u8[want]
      exr_pxr24(t, raw, @ct, @nc, bw, lines, y0)
    elsif @comp == 4
      raw = u8[want]
      exr_piz(@a, off, ds, raw, want, @ct, @nc, bw, lines, y0)
    else
      raw = u8[want]
      exr_b44(@a, off, ds, raw, @ct, @nc, bw, lines, y0)
    exr_convert(raw, @ct, @nc, @sel, bw, lines, y0, x0, @w, @out, @p2, @lut)
    nil

  -> inflate(off, ds, want)
    z = u8[ds]
    exr_copy(z, 0, @a, off, ds)
    g = nil
    begin
      g = Gzip.inflate_zlib(z, 0, want + 1, false)
    rescue e
      g = nil
    return nil if g == nil
    g = img_bytes(g)
    return g if g.size >= want
    t = u8[want]
    exr_copy(t, 0, g, 0, g.size)
    t

-> exr_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> exr_rle(a, p, ds, out, want) (u8[] i64 i64 u8[] i64) i64
  e = p + ds
  o = 0 ## i64
  while p < e && o < want
    c = a[p] ## i64
    c = c - 256 if c >= 128
    p += 1
    if c < 0
      k = 0 - c
      while k > 0 && p < e && o < want
        out[o] = a[p]
        o += 1
        p += 1
        k -= 1
    else
      break if p >= e
      v = a[p]
      p += 1
      k = c + 1
      while k > 0 && o < want
        out[o] = v
        o += 1
        k -= 1
  o

# ZIP/RLE: undo the byte delta, then de-interleave the two halves.
-> exr_unpredict(t, n, out) (u8[] i64 u8[]) i64
  i = 1 ## i64
  while i < n
    t[i] = (t[i - 1] + t[i] - 128) & 255
    i += 1
  half = (n + 1) / 2
  i = 0
  while i < n
    if (i & 1) == 0
      out[i] = t[i >> 1]
    else
      out[i] = t[half + (i >> 1)]
    i += 1
  0

-> exr_pxr24(t, out, ct, nc, bw, lines, y0) (u8[] u8[] i64[] i64 i64 i64 i64) i64
  ip = 0 ## i64
  op = 0 ## i64
  n = t.size
  y = 0 ## i64
  while y < lines
    c = 0 ## i64
    while c < nc
      if (y0 + y) % ct[c * 4 + 3] == 0
        typ = ct[c * 4]
        cnt = bw / ct[c * 4 + 2]
        pix = 0 ## i64
        j = 0 ## i64
        if typ == 0
          while j < cnt
            d = 0 ## i64
            if ip + j + 3 * cnt < n
              d = (t[ip + j] << 24) | (t[ip + j + cnt] << 16) | (t[ip + j + 2 * cnt] << 8) | t[ip + j + 3 * cnt]
            pix = (pix + d) & 0xFFFFFFFF
            out[op] = pix & 255
            out[op + 1] = (pix >> 8) & 255
            out[op + 2] = (pix >> 16) & 255
            out[op + 3] = (pix >> 24) & 255
            op += 4
            j += 1
          ip += 4 * cnt
        elsif typ == 1
          while j < cnt
            d = 0 ## i64
            d = (t[ip + j] << 8) | t[ip + j + cnt] if ip + j + cnt < n
            pix = (pix + d) & 0xFFFF
            out[op] = pix & 255
            out[op + 1] = pix >> 8
            op += 2
            j += 1
          ip += 2 * cnt
        else
          while j < cnt
            d = 0 ## i64
            d = (t[ip + j] << 24) | (t[ip + j + cnt] << 16) | (t[ip + j + 2 * cnt] << 8) if ip + j + 2 * cnt < n
            pix = (pix + d) & 0xFFFFFFFF
            out[op] = pix & 255
            out[op + 1] = (pix >> 8) & 255
            out[op + 2] = (pix >> 16) & 255
            out[op + 3] = (pix >> 24) & 255
            op += 4
            j += 1
          ip += 3 * cnt
      c += 1
    y += 1
  0

# Convert one decoded block (scanline layout, little-endian samples) to RGBA8.
-> exr_convert(raw, ct, nc, sel, bw, lines, y0, x0, w, out, p2, lut) (u8[] i64[] i64 i64[] i64 i64 i64 i64 i64 u8[] f64[] u8[]) i64
  ri = sel[0]
  gi = sel[1]
  bi = sel[2]
  ai = sel[3]
  yi = sel[4]
  # byte offset of each channel within a full-resolution line
  co = i64[nc + 1]
  p = 0 ## i64
  y = 0 ## i64
  n = raw.size
  while y < lines
    lo = 0 ## i64
    c = 0 ## i64
    while c < nc
      co[c] = -1
      if (y0 + y) % ct[c * 4 + 3] == 0
        co[c] = p + lo
        lo += (bw / ct[c * 4 + 2]) * ct[c * 4 + 1]
      c += 1
    x = 0 ## i64
    while x < bw
      r = ~0.0
      g = ~0.0
      b = ~0.0
      al = ~1.0
      if ri >= 0
        r = exr_sample(raw, co[ri], ct[ri * 4], x, n, p2)
        g = gi >= 0 ? exr_sample(raw, co[gi], ct[gi * 4], x, n, p2) : r
        b = bi >= 0 ? exr_sample(raw, co[bi], ct[bi * 4], x, n, p2) : r
      else
        r = exr_sample(raw, co[yi], ct[yi * 4], x, n, p2)
        g = r
        b = r
      if ai >= 0
        al = exr_sample(raw, co[ai], ct[ai * 4], x, n, p2)
        al = ~1.0 if al > ~1.0
        al = ~0.0 if al < ~0.0
        # EXR colour is premultiplied by alpha
        if al > ~0.0
          r = r / al
          g = g / al
          b = b / al
      imgf_px(out, ((y0 + y) * w + x0 + x) * 4, r, g, b, al, lut)
      x += 1
    p += lo
    y += 1
  0

-> exr_sample(raw, off, typ, x, n, p2) (u8[] i64 i64 i64 i64 f64[]) f64
  return ~0.0 if off < 0
  if typ == 1
    o = off + x * 2
    return ~0.0 if o + 2 > n
    hv = raw[o] | (raw[o + 1] << 8) ## i64
    return imgf_f16(hv, p2)
  o = off + x * 4
  return ~0.0 if o + 4 > n
  v = raw[o] | (raw[o + 1] << 8) | (raw[o + 2] << 16) | (raw[o + 3] << 24)
  return imgf_f32(v, p2) if typ == 2
  v.to_f / ~4294967295.0

# ---- PIZ ----

-> exr_piz(a, p, ds, out, want, ct, nc, bw, lines, y0)
  e = p + ds
  img_fail("exr: truncated PIZ block") if p + 4 > e
  minnz = img_le16(a, p)
  maxnz = img_le16(a, p + 2)
  p += 4
  img_fail("exr: bad PIZ bitmap") if maxnz >= 8192
  bitmap = u8[8192]
  if minnz <= maxnz
    img_fail("exr: truncated PIZ bitmap") if p + maxnz - minnz + 1 > e
    exr_copy(bitmap, minnz, a, p, maxnz - minnz + 1)
    p += maxnz - minnz + 1
  lut = u16[65536]
  maxv = exr_rev_lut(bitmap, lut)
  len = img_le32(a, p)
  p += 4
  img_fail("exr: truncated PIZ data") if p + len > e
  # per channel: start (in u16), nx, ny, size (u16 units)
  cd = i64[nc * 4]
  total = 0
  c = 0
  while c < nc
    xs = ct[c * 4 + 2]
    ys = ct[c * 4 + 3]
    nx = bw / xs
    ny = 0
    y = y0
    while y < y0 + lines
      ny += 1 if y % ys == 0
      y += 1
    sz = ct[c * 4 + 1] / 2
    cd[c * 4] = total
    cd[c * 4 + 1] = nx
    cd[c * 4 + 2] = ny
    cd[c * 4 + 3] = sz
    total += nx * ny * sz
    c += 1
  tmp = u16[total + 1]
  exr_huf_decode(a, p, len, tmp, total)
  c = 0
  while c < nc
    j = 0
    while j < cd[c * 4 + 3]
      exr_wav2(tmp, cd[c * 4] + j, cd[c * 4 + 1], cd[c * 4 + 3], cd[c * 4 + 2], cd[c * 4 + 1] * cd[c * 4 + 3], maxv)
      j += 1
    c += 1
  exr_apply_lut(lut, tmp, total)
  exr_piz_reorder(tmp, out, cd, ct, nc, lines, y0)
  nil

-> exr_rev_lut(bitmap, lut) (u8[] u16[]) i64
  k = 0 ## i64
  i = 0 ## i64
  while i < 65536
    if i == 0 || (bitmap[i >> 3] & (1 << (i & 7))) != 0
      lut[k] = i
      k += 1
    i += 1
  n = k - 1
  while k < 65536
    lut[k] = 0
    k += 1
  n

-> exr_apply_lut(lut, d, n) (u16[] u16[] i64) i64
  i = 0 ## i64
  while i < n
    v = d[i] ## i64
    d[i] = lut[v]
    i += 1
  0

-> exr_piz_reorder(tmp, out, cd, ct, nc, lines, y0) (u16[] u8[] i64[] i64[] i64 i64 i64) i64
  cur = i64[nc]
  c = 0 ## i64
  while c < nc
    cur[c] = cd[c * 4]
    c += 1
  o = 0 ## i64
  y = 0 ## i64
  while y < lines
    c = 0
    while c < nc
      if (y0 + y) % ct[c * 4 + 3] == 0
        n = cd[c * 4 + 1] * cd[c * 4 + 3]
        k = 0 ## i64
        while k < n
          v = tmp[cur[c] + k] ## i64
          if o + 1 < out.size
            out[o] = v & 255
            out[o + 1] = v >> 8
          o += 2
          k += 1
        cur[c] += n
      c += 1
    y += 1
  0

-> exr_wdec14(l, h, r, k) (i64 i64 i64[] i64) i64
  ls = l >= 32768 ? l - 65536 : l
  hs = h >= 32768 ? h - 65536 : h
  ai = ls + (hs & 1) + (hs >> 1)
  r[k] = ai & 65535
  r[k + 1] = (ai - hs) & 65535
  0

-> exr_wdec16(l, h, r, k) (i64 i64 i64[] i64) i64
  bb = (l - (h >> 1)) & 65535
  aa = (h + bb - 32768) & 65535
  r[k] = aa
  r[k + 1] = bb
  0

-> exr_wd(l, h, r, k, w14) (i64 i64 i64[] i64 bool) i64
  if w14
    exr_wdec14(l, h, r, k)
  else
    exr_wdec16(l, h, r, k)
  0

# Inverse 2D Haar-like wavelet (OpenEXR wav2Decode) in place.
-> exr_wav2(d, base, nx, ox, ny, oy, mx) (u16[] i64 i64 i64 i64 i64 i64) i64
  w14 = mx < 16384
  n = nx > ny ? ny : nx
  p = 1 ## i64
  while p <= n
    p = p << 1
  p = p >> 1
  p2 = p
  p = p >> 1
  r = i64[8]
  while p >= 1
    py = base
    ey = base + oy * (ny - p2)
    oy1 = oy * p
    oy2 = oy * p2
    ox1 = ox * p
    ox2 = ox * p2
    while py <= ey
      px = py
      ex = py + ox * (nx - p2)
      while px <= ex
        p01 = px + ox1
        p10 = px + oy1
        p11 = p10 + ox1
        v00 = d[px] ## i64
        v01 = d[p01] ## i64
        v10 = d[p10] ## i64
        v11 = d[p11] ## i64
        exr_wd(v00, v10, r, 0, w14)
        exr_wd(v01, v11, r, 2, w14)
        exr_wd(r[0], r[2], r, 4, w14)
        exr_wd(r[1], r[3], r, 6, w14)
        d[px] = r[4]
        d[p01] = r[5]
        d[p10] = r[6]
        d[p11] = r[7]
        px += ox2
      if (nx & p) != 0
        p10 = px + oy1
        v00 = d[px] ## i64
        v10 = d[p10] ## i64
        exr_wd(v00, v10, r, 0, w14)
        d[px] = r[0]
        d[p10] = r[1]
      py += oy2
    if (ny & p) != 0
      px = py
      ex = py + ox * (nx - p2)
      while px <= ex
        p01 = px + ox1
        v00 = d[px] ## i64
        v01 = d[p01] ## i64
        exr_wd(v00, v01, r, 0, w14)
        d[px] = r[0]
        d[p01] = r[1]
        px += ox2
    p2 = p
    p = p >> 1
  0

# OpenEXR's Huffman coder: a canonical code table of up to 58-bit codes
# (run-length coded lengths), the last symbol (imax) a run-length escape.
-> exr_huf_decode(a, p, len, out, nout)
  img_fail("exr: truncated Huffman header") if len < 20
  im = img_le32(a, p)
  imax = img_le32(a, p + 4)
  nbits = img_le32(a, p + 12)
  img_fail("exr: bad Huffman table") if im >= 65537 || imax >= 65537 || im > imax
  hcode = i64[65537]
  st = i64[4]          # 0 pos, 1 bit buffer, 2 bit count
  st[0] = p + 20
  exr_huf_unpack(a, p + len, im, imax, hcode, st)
  img_fail("exr: bad Huffman table") if st[0] < 0
  exr_huf_canon(hcode)
  dlen = i32[16384]
  dlit = i32[16384]
  dhead = i32[16384]
  lnext = i32[65537]
  ok = exr_huf_build(hcode, im, imax, dlen, dlit, dhead, lnext)
  img_fail("exr: bad Huffman code") if ok != 0
  img_fail("exr: truncated Huffman data") if st[0] + (nbits + 7) / 8 > p + len
  got = exr_huf_run(a, st[0], nbits, hcode, dlen, dlit, dhead, lnext, imax, out, nout)
  img_fail("exr: Huffman data error") if got < 0
  nil

-> exr_getbits(a, e, st, n) (u8[] i64 i64[] i64) i64
  while st[2] < n
    v = 0 ## i64
    if st[0] < e
      v = a[st[0]]
    else
      st[3] = 1
    st[0] += 1
    st[1] = ((st[1] << 8) | v) & 0xFFFFFFFFFFFF
    st[2] += 8
  st[2] -= n
  (st[1] >> st[2]) & ((1 << n) - 1)

-> exr_huf_unpack(a, e, im, imax, hcode, st) (u8[] i64 i64 i64 i64[] i64[]) i64
  st[1] = 0
  st[2] = 0
  while im <= imax
    l = exr_getbits(a, e, st, 6)
    hcode[im] = l
    if l == 63
      zr = exr_getbits(a, e, st, 8) + 6
      return -1 if im + zr > imax + 1
      while zr > 0
        hcode[im] = 0
        im += 1
        zr -= 1
      im -= 1
    elsif l >= 59
      zr = l - 59 + 2
      return -1 if im + zr > imax + 1
      while zr > 0
        hcode[im] = 0
        im += 1
        zr -= 1
      im -= 1
    im += 1
  if st[3] == 1
    st[0] = -1
  0

-> exr_huf_canon(hcode) (i64[]) i64
  n = i64[59]
  i = 0 ## i64
  while i < 65537
    l = hcode[i]
    n[l] += 1 if l < 59
    i += 1
  c = 0 ## i64
  i = 58
  while i > 0
    nc = (c + n[i]) >> 1
    n[i] = c
    c = nc
    i -= 1
  i = 0
  while i < 65537
    l = hcode[i]
    if l > 0 && l < 59
      hcode[i] = l | (n[l] << 6)
      n[l] += 1
    i += 1
  0

-> exr_huf_build(hcode, im, imax, dlen, dlit, dhead, lnext) (i64[] i64 i64 i32[] i32[] i32[] i32[]) i64
  i = 0 ## i64
  while i < 16384
    dhead[i] = -1
    i += 1
  while im <= imax
    hc = hcode[im]
    c = hc >> 6
    l = hc & 63
    return 1 if l > 0 && (c >> l) != 0
    if l > 14
      k = c >> (l - 14)
      return 1 if dlen[k] != 0
      dlit[k] += 1
      lnext[im] = dhead[k]
      dhead[k] = im
    elsif l > 0
      k = c << (14 - l)
      j = (1 ## i64) << (14 - l)
      while j > 0
        return 1 if dlen[k] != 0 || dhead[k] != -1
        dlen[k] = l
        dlit[k] = im
        k += 1
        j -= 1
    im += 1
  0

-> exr_huf_run(a, p, nbits, hcode, dlen, dlit, dhead, lnext, rlc, out, nout) (u8[] i64 i64 i64[] i32[] i32[] i32[] i32[] i64 u16[] i64) i64
  c = 0 ## i64
  lc = 0 ## i64
  o = 0 ## i64
  ie = p + (nbits + 7) / 8
  while p < ie
    c = ((c << 8) | a[p]) & 0xFFFFFFFFFFFFFF
    p += 1
    lc += 8
    while lc >= 14
      k = (c >> (lc - 14)) & 16383
      ln = dlen[k] ## i64
      if ln != 0
        lc -= ln
        sym = dlit[k] ## i64
        if sym == rlc
          if lc < 8
            break if p >= ie
            c = ((c << 8) | a[p]) & 0xFFFFFFFFFFFFFF
            p += 1
            lc += 8
          lc -= 8
          cs = (c >> lc) & 255
          return -1 if o + cs > nout || o == 0
          s = out[o - 1] ## i64
          while cs > 0
            out[o] = s
            o += 1
            cs -= 1
        else
          return -1 if o >= nout
          out[o] = sym
          o += 1
      else
        q = dhead[k] ## i64
        return -1 if q < 0
        found = false
        while q >= 0 && !found
          hc = hcode[q]
          l = hc & 63
          while lc < l && p < ie
            c = ((c << 8) | a[p]) & 0xFFFFFFFFFFFFFF
            p += 1
            lc += 8
          if lc >= l && (hc >> 6) == ((c >> (lc - l)) & (((1 ## i64) << l) - 1))
            lc -= l
            found = true
            if q == rlc
              if lc < 8
                c = ((c << 8) | (p < ie ? a[p] : 0)) & 0xFFFFFFFFFFFFFF
                p += 1
                lc += 8
              lc -= 8
              cs = (c >> lc) & 255
              return -1 if o + cs > nout || o == 0
              s = out[o - 1] ## i64
              while cs > 0
                out[o] = s
                o += 1
                cs -= 1
            else
              return -1 if o >= nout
              out[o] = q
              o += 1
          else
            q = lnext[q]
        return -1 if !found
  i = (8 - nbits) & 7
  c = c >> i
  lc -= i
  while lc > 0
    k = (c << (14 - lc)) & 16383
    ln = dlen[k] ## i64
    return -1 if ln == 0
    lc -= ln
    sym = dlit[k] ## i64
    if sym == rlc
      return -1 if lc < 8
      lc -= 8
      cs = (c >> lc) & 255
      return -1 if o + cs > nout || o == 0
      s = out[o - 1] ## i64
      while cs > 0
        out[o] = s
        o += 1
        cs -= 1
    else
      return -1 if o >= nout
      out[o] = sym
      o += 1
  o

# ---- B44 / B44A: 4x4 blocks of HALF samples (other types stored raw) ----

-> exr_b44(a, p, ds, out, ct, nc, bw, lines, y0) (u8[] i64 i64 u8[] i64[] i64 i64 i64 i64) i64
  e = p + ds
  # decode every channel into its own plane of u16 (or raw bytes), then reorder
  planes = i64[nc * 3]           # byte offset in tmp, nx, ny
  tot = 0 ## i64
  c = 0 ## i64
  while c < nc
    nx = bw / ct[c * 4 + 2]
    ny = 0 ## i64
    y = y0
    while y < y0 + lines
      ny += 1 if y % ct[c * 4 + 3] == 0
      y += 1
    planes[c * 3] = tot
    planes[c * 3 + 1] = nx
    planes[c * 3 + 2] = ny
    tot += nx * ny * ct[c * 4 + 1]
    c += 1
  tmp = u8[tot + 1]
  s = i64[16]
  c = 0
  while c < nc
    nx = planes[c * 3 + 1]
    ny = planes[c * 3 + 2]
    base = planes[c * 3]
    if ct[c * 4] != 1
      n = nx * ny * ct[c * 4 + 1]
      k = 0 ## i64
      while k < n && p < e
        tmp[base + k] = a[p]
        p += 1
        k += 1
    else
      by = 0 ## i64
      while by < ny
        bx = 0 ## i64
        while bx < nx
          if p + 3 <= e && a[p + 2] >= 52
            t = (a[p] << 8) | a[p + 1]
            t = (t & 0x8000) != 0 ? t & 0x7FFF : t ^ 0xFFFF
            k = 0 ## i64
            while k < 16
              s[k] = t
              k += 1
            p += 3
          elsif p + 14 <= e
            exr_unpack14(a, p, s)
            p += 14
          else
            p = e
          yy = 0 ## i64
          while yy < 4
            xx = 0 ## i64
            while xx < 4
              if by + yy < ny && bx + xx < nx
                o = base + ((by + yy) * nx + bx + xx) * 2
                v = s[yy * 4 + xx]
                tmp[o] = v & 255
                tmp[o + 1] = v >> 8
              xx += 1
            yy += 1
          bx += 4
        by += 4
    c += 1
  # reorder to scanlines
  op = 0 ## i64
  cur = i64[nc]
  y = 0
  while y < lines
    c = 0
    while c < nc
      if (y0 + y) % ct[c * 4 + 3] == 0
        n = planes[c * 3 + 1] * ct[c * 4 + 1]
        k = 0 ## i64
        while k < n
          out[op] = tmp[planes[c * 3] + cur[c] + k] if op < out.size
          op += 1
          k += 1
        cur[c] += n
      c += 1
    y += 1
  0

-> exr_unpack14(b, p, s) (u8[] i64 i64[]) i64
  b0 = b[p] ## i64
  b1 = b[p + 1] ## i64
  b2 = b[p + 2] ## i64
  b3 = b[p + 3] ## i64
  b4 = b[p + 4] ## i64
  b5 = b[p + 5] ## i64
  b6 = b[p + 6] ## i64
  b7 = b[p + 7] ## i64
  b8 = b[p + 8] ## i64
  b9 = b[p + 9] ## i64
  b10 = b[p + 10] ## i64
  b11 = b[p + 11] ## i64
  b12 = b[p + 12] ## i64
  b13 = b[p + 13] ## i64
  s[0] = (b0 << 8) | b1
  sh = b2 >> 2
  bias = 0x20 << sh
  s[4] = s[0] + ((((b2 << 4) | (b3 >> 4)) & 0x3F) << sh) - bias
  s[8] = s[4] + ((((b3 << 2) | (b4 >> 6)) & 0x3F) << sh) - bias
  s[12] = s[8] + ((b4 & 0x3F) << sh) - bias
  s[1] = s[0] + ((b5 >> 2) << sh) - bias
  s[5] = s[4] + ((((b5 << 4) | (b6 >> 4)) & 0x3F) << sh) - bias
  s[9] = s[8] + ((((b6 << 2) | (b7 >> 6)) & 0x3F) << sh) - bias
  s[13] = s[12] + ((b7 & 0x3F) << sh) - bias
  s[2] = s[1] + ((b8 >> 2) << sh) - bias
  s[6] = s[5] + ((((b8 << 4) | (b9 >> 4)) & 0x3F) << sh) - bias
  s[10] = s[9] + ((((b9 << 2) | (b10 >> 6)) & 0x3F) << sh) - bias
  s[14] = s[13] + ((b10 & 0x3F) << sh) - bias
  s[3] = s[2] + ((b11 >> 2) << sh) - bias
  s[7] = s[6] + ((((b11 << 4) | (b12 >> 4)) & 0x3F) << sh) - bias
  s[11] = s[10] + ((((b12 << 2) | (b13 >> 6)) & 0x3F) << sh) - bias
  s[15] = s[14] + ((b13 & 0x3F) << sh) - bias
  i = 0 ## i64
  while i < 16
    v = s[i] & 0xFFFF
    s[i] = (v & 0x8000) != 0 ? v & 0x7FFF : v ^ 0xFFFF
    i += 1
  0

img_register("exr", ->(b) exr_sniff?(b), ->(b) exr_decode(b))
