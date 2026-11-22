# core/codec/image/tiff — TIFF 6.0 (and BigTIFF) decoder in Tungsten.
#
# First image (IFD 0) of the file, as Safari shows. Supported:
#   byte order II / MM; classic and BigTIFF (version 43) headers
#   strips and tiles; chunky and planar (PlanarConfiguration 2) layouts
#   compression: none, LZW (MSB-first, early change), Deflate (8 / 32946),
#     PackBits, JPEG (7, "new-style" with JPEGTables; YCbCr or RGB)
#   predictors: horizontal differencing (2) for 8/16/32-bit samples and the
#     floating-point predictor (3)
#   photometric: WhiteIsZero, BlackIsZero, RGB, palette, CMYK (Separated,
#     InkSet 1: an embedded CMYK ICC profile via core/codec/image/icc when it has a LUT,
#     else the naive formula), YCbCr (through JPEG, or uncompressed 1x1)
#   1/2/4/8/16-bit integer samples, 16/32/64-bit IEEE float (scene-linear,
#     tone-mapped via core/codec/image/imgfloat), extra samples (associated alpha is
#     un-premultiplied, unassociated used as is), Orientation, ICC (RGB/grey)
# Not supported (ImageError): CCITT fax (2/3/4), old-style JPEG (6), LZMA,
# ZSTD, WebP-in-TIFF, CIELab and other photometric spaces.
#
#   tiff_sniff?(bytes)  "II*\0" / "MM\0*" (and BigTIFF "II+\0" / "MM\0+")
#   tiff_decode(bytes)  → Bitmap

use core/codec/image
use imgfloat

-> tiff_sniff?(b)
  return false if b.size < 8
  return (b[2] == 42 || b[2] == 43) && b[3] == 0 if b[0] == 73 && b[1] == 73
  return b[2] == 0 && (b[3] == 42 || b[3] == 43) if b[0] == 77 && b[1] == 77
  false

-> tif_u64(a, o, le) (u8[] i64 i64) i64
  lo = img_tiff32(a, o, le)
  hi = img_tiff32(a, o + 4, le)
  le == 1 ? lo | (hi << 32) : (lo << 32) | hi

# Values of one IFD entry as an Array of Integers (rationals as [num, den]).
-> tif_values(a, le, big, typ, cnt, voff)
  sz = 1
  sz = 2 if typ == 3 || typ == 8
  sz = 4 if typ == 4 || typ == 9 || typ == 11 || typ == 13
  sz = 8 if typ == 5 || typ == 10 || typ == 12 || typ == 16 || typ == 17 || typ == 18
  inline = big ? 8 : 4
  off = voff
  if sz * cnt > inline
    off = big ? tif_u64(a, voff, le) : img_tiff32(a, voff, le)
  out = []
  img_fail("tiff: bad tag data") if off < 0 || off + sz * cnt > a.size
  i = 0
  while i < cnt
    o = off + i * sz
    if sz == 1
      out.push(a[o])
    elsif sz == 2
      out.push(img_tiff16(a, o, le))
    elsif sz == 4
      out.push(img_tiff32(a, o, le))
    elsif typ == 5 || typ == 10
      out.push(img_tiff32(a, o, le))
    else
      out.push(tif_u64(a, o, le))
    i += 1
  out

# Byte range [off, len] of an UNDEFINED/BYTE entry (ICC, JPEGTables).
-> tif_blob(a, le, big, cnt, voff)
  inline = big ? 8 : 4
  off = voff
  off = (big ? tif_u64(a, voff, le) : img_tiff32(a, voff, le)) if cnt > inline
  return nil if off < 0 || off + cnt > a.size
  [off, cnt]

-> tiff_decode(data)
  a = img_bytes(data)
  img_fail("tiff: not a TIFF") if !tiff_sniff?(a)
  le = a[0] == 73 ? 1 : 0
  big = img_tiff16(a, 2, le) == 43
  ifd = big ? tif_u64(a, 8, le) : img_tiff32(a, 4, le)
  img_fail("tiff: bad IFD offset") if ifd < 8 || ifd + 2 > a.size
  n = big ? tif_u64(a, ifd, le) : img_tiff16(a, ifd, le)
  es = big ? 20 : 12
  base = ifd + (big ? 8 : 2)
  img_fail("tiff: bad IFD") if n > 4096 || base + n * es > a.size
  tags = {}
  blobs = {}
  i = 0
  while i < n
    e = base + i * es
    tag = img_tiff16(a, e, le)
    typ = img_tiff16(a, e + 2, le)
    cnt = big ? tif_u64(a, e + 4, le) : img_tiff32(a, e + 4, le)
    voff = e + (big ? 12 : 8)
    if tag == 34675 || tag == 347
      blobs[tag] = tif_blob(a, le, big, cnt, voff)
    elsif typ >= 1 && typ <= 18 && cnt < 50000000
      begin
        tags[tag] = tif_values(a, le, big, typ, cnt, voff)
      rescue e2
        nil
    i += 1
  tf = TiffImage.new(a, le, tags, blobs)
  tf.decode

+ TiffImage
  -> new(@a, @le, @tags, @blobs)
    @w = tag1(256, 0)
    @h = tag1(257, 0)
    bl = @tags[258]
    @bps = bl == nil ? 1 : bl[0]
    @comp = tag1(259, 1)
    @photo = tag1(262, -1)
    @spp = tag1(277, 1)
    @planar = tag1(284, 1)
    @pred = tag1(317, 1)
    @fmt = tag1(339, 1)
    @orient = tag1(274, 1)
    ex = @tags[338]
    @extra = ex == nil ? [] : ex
    if @photo == -1
      @photo = @spp >= 3 ? 2 : 1
    img_check_size(@w, @h)
    img_fail("tiff: unsupported bits per sample " + @bps.to_s) if @bps != 1 && @bps != 2 && @bps != 4 && @bps != 8 && @bps != 16 && @bps != 32 && @bps != 64
    img_fail("tiff: bad samples per pixel") if @spp < 1 || @spp > 16
    img_fail("tiff: float samples must be 16/32/64-bit") if @fmt == 3 && @bps < 16

  -> tag1(t, d)
    v = @tags[t]
    v == nil || v.size == 0 ? d : v[0]

  -> decode
    if @comp == 7
      return finish(decode_jpeg())
    img_fail("tiff: unsupported compression " + @comp.to_s) if @comp != 1 && @comp != 5 && @comp != 8 && @comp != 32946 && @comp != 32773
    img_fail("tiff: unsupported photometric " + @photo.to_s) if @photo > 6 || @photo == 4
    ycc = @photo == 6
    if ycc
      ss = @tags[530]
      img_fail("tiff: subsampled YCbCr without JPEG") if ss != nil && (ss[0] != 1 || ss[1] != 1)
    tiled = @tags[322] != nil
    offs = tiled ? @tags[324] : @tags[273]
    cnts = tiled ? @tags[325] : @tags[279]
    img_fail("tiff: no image data") if offs == nil
    bw = tiled ? tag1(322, 0) : @w
    bh = tiled ? tag1(323, 0) : tag1(278, @h)
    bh = @h if bh <= 0 || bh > @h
    img_fail("tiff: bad tile size") if bw <= 0 || bh <= 0
    across = (@w + bw - 1) / bw
    down = (@h + bh - 1) / bh
    nplanes = @planar == 2 ? @spp : 1
    sppb = @planar == 2 ? 1 : @spp
    rowb = (bw * sppb * @bps + 7) / 8
    isf = @fmt == 3
    fl = isf ? f64[@w * @h * @spp] : f64[1]
    sm = isf ? u16[1] : u16[@w * @h * @spp]
    pl = 0
    while pl < nplanes
      by = 0
      while by < down
        bx = 0
        while bx < across
          k = pl * across * down + by * across + bx
          if k < offs.size
            off = offs[k]
            len = cnts == nil || k >= cnts.size ? @a.size - off : cnts[k]
            len = @a.size - off if off + len > @a.size
            rows = tiled ? bh : (by == down - 1 ? @h - by * bh : bh)
            want = rowb * rows
            raw = off >= 0 && len > 0 ? block(off, len, want) : nil
            if raw != nil
              tif_predict(raw, rowb, rows, bw, sppb, @bps, @pred, @le) if @pred > 1
              x0 = bx * bw
              y0 = by * bh
              if isf
                tif_put_float(raw, rowb, rows, bw, sppb, @bps, @le, fl, @w, @h, @spp, x0, y0, pl, imgf_tables()[0])
              else
                tif_put(raw, rowb, rows, bw, sppb, @bps, @le, sm, @w, @h, @spp, x0, y0, pl)
          bx += 1
        by += 1
      pl += 1
    bm = Bitmap.new(@w, @h)
    if isf
      tb = imgf_tables()
      tif_float_rgba(fl, @w * @h, @spp, @photo, alpha_idx(), bm.rgba, tb[1])
    else
      to_rgba(sm, bm)
    finish(bm)

  # Index of the alpha sample (or -1) and whether it is premultiplied.
  -> alpha_idx
    base = (@photo == 2 || @photo == 6) ? 3 : (@photo == 5 ? 4 : 1)
    return -1 if @spp <= base || @extra.size == 0
    (@extra[0] == 1 || @extra[0] == 2) ? base : -1

  -> premultiplied?
    @extra.size > 0 && @extra[0] == 1

  -> block(off, len, want)
    if @comp == 1
      out = u8[want]
      n = len < want ? len : want
      tif_copy(out, 0, @a, off, n)
      return out
    if @comp == 32773
      out = u8[want]
      tif_packbits(@a, off, len, out, want)
      return out
    if @comp == 5
      out = u8[want]
      tif_lzw(@a, off, len, out, want)
      return out
    # Deflate (zlib)
    z = u8[len]
    tif_copy(z, 0, @a, off, len)
    got = nil
    begin
      got = Gzip.inflate_zlib(z, 0, want + 1, false)
    rescue e
      got = nil
    return nil if got == nil
    g = img_bytes(got)
    return g if g.size >= want
    out = u8[want]
    tif_copy(out, 0, g, 0, g.size)
    out

  -> to_rgba(sm, bm)
    mx = (1 << (@bps > 16 ? 16 : @bps)) - 1
    ai = alpha_idx()
    out = bm.rgba
    npx = @w * @h
    if @photo == 3
      cm = @tags[320]
      img_fail("tiff: palette image without ColorMap") if cm == nil
      ncol = cm.size / 3
      pal = u8[ncol * 4]
      j = 0
      while j < ncol
        pal[j * 4] = cm[j] >> 8
        pal[j * 4 + 1] = cm[ncol + j] >> 8
        pal[j * 4 + 2] = cm[2 * ncol + j] >> 8
        pal[j * 4 + 3] = 255
        j += 1
      tif_pal(sm, npx, @spp, pal, ncol, out)
      return nil
    if @photo == 5
      img_fail("tiff: CMYK needs 4 samples") if @spp < 4
      ink = u8[npx * 4]
      tif_scale(sm, npx, @spp, 0, 4, mx, ink)
      p = icc_profile()
      if p != nil && p.cmyk
        icc_apply_cmyk(p, ink, out, npx)
      else
        tif_cmyk(ink, npx, out)
      tif_alpha(sm, npx, @spp, ai, mx, out, premultiplied?()) if ai >= 0
      return nil
    if @photo == 2 || @photo == 6
      img_fail("tiff: RGB needs 3 samples") if @spp < 3
      tif_scale(sm, npx, @spp, 0, 3, mx, out)
      tif_ycc(out, npx) if @photo == 6
    else
      tif_grey(sm, npx, @spp, mx, @photo == 0, out)
    tif_opaque(out, npx)
    tif_alpha(sm, npx, @spp, ai, mx, out, premultiplied?()) if ai >= 0
    p = icc_profile()
    icc_apply(p, out, npx) if p != nil && !p.cmyk && img_colour?()
    nil

  -> icc_profile
    b = @blobs[34675]
    return nil if b == nil || !img_colour?()
    p = icc_parse(@a, b[0], b[1])
    return nil if p == nil
    return nil if !p.cmyk && icc_srgb?(p)
    p

  -> finish(bm)
    img_orient(bm, @orient)

  # JPEG-compressed strips/tiles: each is a JPEG stream sharing JPEGTables.
  -> decode_jpeg
    tiled = @tags[322] != nil
    offs = tiled ? @tags[324] : @tags[273]
    cnts = tiled ? @tags[325] : @tags[279]
    img_fail("tiff: no image data") if offs == nil || cnts == nil
    img_fail("tiff: planar JPEG is not supported") if @planar == 2 && @spp > 1
    img_fail("tiff: unsupported JPEG photometric " + @photo.to_s) if @photo != 6 && @photo != 2 && @photo != 1
    bw = tiled ? tag1(322, 0) : @w
    bh = tiled ? tag1(323, 0) : tag1(278, @h)
    bh = @h if bh <= 0 || bh > @h
    across = (@w + bw - 1) / bw
    tb = @blobs[347]
    bm = Bitmap.new(@w, @h)
    k = 0
    while k < offs.size && k < cnts.size
      off = offs[k]
      len = cnts[k]
      if off > 0 && len > 2 && off + len <= @a.size
        js = tif_jpeg_stream(@a, off, len, tb, @photo == 2)
        sub = nil
        begin
          sub = jpeg_decode(js)
        rescue e
          sub = nil
        if sub != nil
          x0 = (k % across) * bw
          y0 = (k / across) * bh
          img_blit(bm.rgba, @w, @h, sub.rgba, sub.width, sub.height, x0, y0, 0)
      k += 1
    bm

# SOI + JPEGTables (without its SOI/EOI) [+ Adobe APP14 transform 0 for RGB]
# + the strip without its SOI.
-> tif_jpeg_stream(a, off, len, tb, rgb)
  tlen = 0
  if tb != nil && tb[1] >= 4
    tlen = tb[1] - 4
  app = rgb ? 16 : 0
  body = len
  boff = off
  if a[off] == 0xFF && a[off + 1] == 0xD8
    boff += 2
    body -= 2
  out = u8[2 + app + tlen + body]
  out[0] = 0xFF
  out[1] = 0xD8
  p = 2
  if rgb
    hdr = [0xFF, 0xEE, 0, 14, 65, 100, 111, 98, 101, 0, 100, 0, 0, 0, 0, 0]
    i = 0
    while i < 16
      out[p + i] = hdr[i]
      i += 1
    p += 16
  tif_copy(out, p, a, tb[0] + 2, tlen) if tlen > 0
  p += tlen
  tif_copy(out, p, a, boff, body)
  out

-> tif_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> tif_packbits(a, p, len, out, want) (u8[] i64 i64 u8[] i64) i64
  e = p + len
  e = a.size if e > a.size
  o = 0 ## i64
  while p < e && o < want
    c = a[p]
    p += 1
    if c < 128
      k = c + 1
      while k > 0 && p < e && o < want
        out[o] = a[p]
        o += 1
        p += 1
        k -= 1
    elsif c > 128
      k = 257 - c
      break if p >= e
      v = a[p]
      p += 1
      while k > 0 && o < want
        out[o] = v
        o += 1
        k -= 1
  o

# TIFF LZW: MSB-first codes of 9..12 bits, 256 clear, 257 end of information,
# the code width grows one code early ("early change").
-> tif_lzw(a, p, len, out, want) (u8[] i64 i64 u8[] i64) i64
  e = p + len
  e = a.size if e > a.size
  prefix = i32[4096]
  suffix = u8[4096]
  first = u8[4096]
  lens = i32[4096]
  i = 0 ## i64
  while i < 256
    prefix[i] = -1
    suffix[i] = i
    first[i] = i
    lens[i] = 1
    i += 1
  nxt = 258 ## i64
  width = 9 ## i64
  bitbuf = 0 ## i64
  nbits = 0 ## i64
  old = -1 ## i64
  o = 0 ## i64
  while o < want
    while nbits < width && p < e
      bitbuf = ((bitbuf << 8) | a[p]) & 0xFFFFFFFF
      p += 1
      nbits += 8
    break if nbits < width
    code = (bitbuf >> (nbits - width)) & ((1 << width) - 1)
    nbits -= width
    if code == 257
      break
    if code == 256
      nxt = 258
      width = 9
      old = -1
    else
      if old == -1
        break if code > 255
        out[o] = code
        o += 1
        old = code
      else
        ln = 0 ## i64
        if code < nxt
          ln = lens[code]
          # write the string for code backwards
          q = code
          k = o + ln - 1
          while q >= 0
            out[k] = suffix[q] if k < want
            k -= 1
            q = prefix[q]
          fc = first[code]
          if nxt < 4096
            prefix[nxt] = old
            suffix[nxt] = fc
            first[nxt] = first[old]
            lens[nxt] = lens[old] + 1
            nxt += 1
          o += ln
        elsif code == nxt && nxt < 4096
          fo = first[old]
          prefix[nxt] = old
          suffix[nxt] = fo
          first[nxt] = fo
          lens[nxt] = lens[old] + 1
          ln = lens[nxt]
          q = nxt
          k = o + ln - 1
          while q >= 0
            out[k] = suffix[q] if k < want
            k -= 1
            q = prefix[q]
          nxt += 1
          o += ln
        else
          break
        old = code
      if nxt + 1 >= (1 << width) && width < 12
        width += 1
  o

# Undo the horizontal (2) or floating-point (3) predictor in place.
-> tif_predict(d, rowb, rows, bw, spp, bps, pred, le) (u8[] i64 i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < rows
    r = y * rowb
    if pred == 2
      if bps == 8
        i = spp ## i64
        while i < bw * spp
          d[r + i] = (d[r + i] + d[r + i - spp]) & 255
          i += 1
      elsif bps == 16
        i = spp ## i64
        while i < bw * spp
          o = r + i * 2
          q = o - spp * 2
          v = le == 1 ? d[o] | (d[o + 1] << 8) : (d[o] << 8) | d[o + 1]
          pv = le == 1 ? d[q] | (d[q + 1] << 8) : (d[q] << 8) | d[q + 1]
          v = (v + pv) & 65535
          if le == 1
            d[o] = v & 255
            d[o + 1] = v >> 8
          else
            d[o] = v >> 8
            d[o + 1] = v & 255
          i += 1
      elsif bps == 32
        i = spp ## i64
        while i < bw * spp
          o = r + i * 4
          q = o - spp * 4
          v = img_tiff32(d, o, le)
          pv = img_tiff32(d, q, le)
          v = (v + pv) & 0xFFFFFFFF
          if le == 1
            d[o] = v & 255
            d[o + 1] = (v >> 8) & 255
            d[o + 2] = (v >> 16) & 255
            d[o + 3] = v >> 24
          else
            d[o] = v >> 24
            d[o + 1] = (v >> 16) & 255
            d[o + 2] = (v >> 8) & 255
            d[o + 3] = v & 255
          i += 1
    elsif pred == 3
      # bytes are differenced across the whole row, then stored as planes of
      # most- to least-significant bytes; rebuild big- or little-endian samples
      bpsb = bps / 8
      n = bw * spp * bpsb
      i = spp ## i64
      while i < n
        d[r + i] = (d[r + i] + d[r + i - spp]) & 255
        i += 1
      tmp = u8[n]
      i = 0
      while i < n
        tmp[i] = d[r + i]
        i += 1
      cnt = bw * spp
      s = 0 ## i64
      while s < cnt
        b = 0 ## i64
        while b < bpsb
          v = tmp[b * cnt + s]
          if le == 1
            d[r + s * bpsb + (bpsb - 1 - b)] = v
          else
            d[r + s * bpsb + b] = v
          b += 1
        s += 1
    y += 1
  0

# Unpack one decoded block of integer samples into the sample plane.
-> tif_put(d, rowb, rows, bw, sppb, bps, le, sm, w, h, spp, x0, y0, pl) (u8[] i64 i64 i64 i64 i64 i64 u16[] i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < rows
    iy = y0 + y
    break if iy >= h
    r = y * rowb
    x = 0 ## i64
    while x < bw
      ix = x0 + x
      if ix < w
        c = 0 ## i64
        while c < sppb
          si = x * sppb + c
          v = 0 ## i64
          if bps == 8
            v = d[r + si]
          elsif bps == 16
            o = r + si * 2
            v = le == 1 ? d[o] | (d[o + 1] << 8) : (d[o] << 8) | d[o + 1]
          elsif bps == 32
            # keep the top 16 bits
            o = r + si * 4
            v = le == 1 ? d[o + 2] | (d[o + 3] << 8) : (d[o] << 8) | d[o + 1]
          elsif bps == 64
            o = r + si * 8
            v = le == 1 ? d[o + 6] | (d[o + 7] << 8) : (d[o] << 8) | d[o + 1]
          else
            bit = si * bps
            byte = d[r + (bit >> 3)]
            v = (byte >> (8 - bps - (bit & 7))) & ((1 << bps) - 1)
          ch = sppb == 1 ? pl : c
          sm[(iy * w + ix) * spp + ch] = v
          c += 1
      x += 1
    y += 1
  0

-> tif_put_float(d, rowb, rows, bw, sppb, bps, le, fl, w, h, spp, x0, y0, pl, p2) (u8[] i64 i64 i64 i64 i64 i64 f64[] i64 i64 i64 i64 i64 i64 f64[]) i64
  y = 0 ## i64
  while y < rows
    iy = y0 + y
    break if iy >= h
    r = y * rowb
    x = 0 ## i64
    while x < bw
      ix = x0 + x
      if ix < w
        c = 0 ## i64
        while c < sppb
          si = x * sppb + c
          v = ~0.0
          if bps == 16
            v = imgf_f16(img_tiff16(d, r + si * 2, le), p2)
          elsif bps == 32
            v = imgf_f32(img_tiff32(d, r + si * 4, le), p2)
          else
            # binary64: high word carries sign/exponent; keep 32 bits of mantissa
            o = r + si * 8
            hi = le == 1 ? img_tiff32(d, o + 4, le) : img_tiff32(d, o, le)
            e = (hi >> 20) & 2047
            m = hi & 0xFFFFF
            if e > 0 && e < 2047
              # rebias to binary32 when in range
              e2 = e - 1023 + 127
              if e2 >= 255
                v = ~65504.0
              elsif e2 > 0
                v = imgf_f32((e2 << 23) | (m << 3), p2)
              v = ~0.0 - v if (hi >> 31) == 1
          ch = sppb == 1 ? pl : c
          fl[(iy * w + ix) * spp + ch] = v
          c += 1
      x += 1
    y += 1
  0

-> tif_float_rgba(fl, npx, spp, photo, ai, out, lut) (f64[] i64 i64 i64 i64 u8[] u8[]) i64
  i = 0 ## i64
  while i < npx
    k = i * spp
    r = fl[k]
    g = r
    b = r
    if spp >= 3 && photo == 2
      g = fl[k + 1]
      b = fl[k + 2]
    elsif photo == 0
      r = ~1.0 - r
      g = r
      b = r
    al = ai >= 0 ? fl[k + ai] : ~1.0
    al = ~1.0 if al > ~1.0
    al = ~0.0 if al < ~0.0
    imgf_px(out, i * 4, r, g, b, al, lut)
    i += 1
  0

-> tif_scale(sm, npx, spp, c0, nc, mx, out) (u16[] i64 i64 i64 i64 i64 u8[]) i64
  i = 0 ## i64
  half = mx / 2
  sh = 0 ## i64
  while i < npx
    c = 0 ## i64
    while c < nc
      v = sm[i * spp + c0 + c] ## i64
      out[i * 4 + c] = mx == 255 ? v : (v * 255 + half) / mx
      c += 1
    i += 1
  0

-> tif_grey(sm, npx, spp, mx, inv, out) (u16[] i64 i64 i64 bool u8[]) i64
  i = 0 ## i64
  half = mx / 2
  while i < npx
    v = sm[i * spp] ## i64
    g = (v * 255 + half) / mx
    g = 255 - g if inv
    out[i * 4] = g
    out[i * 4 + 1] = g
    out[i * 4 + 2] = g
    i += 1
  0

-> tif_opaque(out, npx) (u8[] i64) i64
  i = 0 ## i64
  while i < npx
    out[i * 4 + 3] = 255
    i += 1
  0

-> tif_alpha(sm, npx, spp, ai, mx, out, pre) (u16[] i64 i64 i64 i64 u8[] bool) i64
  i = 0 ## i64
  half = mx / 2
  while i < npx
    v = sm[i * spp + ai] ## i64
    al = (v * 255 + half) / mx
    out[i * 4 + 3] = al
    if pre
      if al == 0
        out[i * 4] = 0
        out[i * 4 + 1] = 0
        out[i * 4 + 2] = 0
      elsif al < 255
        c = 0 ## i64
        while c < 3
          x = (out[i * 4 + c] * 255 + al / 2) / al
          out[i * 4 + c] = x > 255 ? 255 : x
          c += 1
    i += 1
  0

-> tif_pal(sm, npx, spp, pal, ncol, out) (u16[] i64 i64 u8[] i64 u8[]) i64
  i = 0 ## i64
  while i < npx
    v = sm[i * spp] ## i64
    if v < ncol
      out[i * 4] = pal[v * 4]
      out[i * 4 + 1] = pal[v * 4 + 1]
      out[i * 4 + 2] = pal[v * 4 + 2]
    out[i * 4 + 3] = 255
    i += 1
  0

# Naive CMYK (0 = no ink) → RGB, alpha 255.
-> tif_cmyk(ink, npx, out) (u8[] i64 u8[]) i64
  i = 0 ## i64
  while i < npx
    o = i * 4
    k = 255 - ink[o + 3]
    out[o] = ((255 - ink[o]) * k + 127) / 255
    out[o + 1] = ((255 - ink[o + 1]) * k + 127) / 255
    out[o + 2] = ((255 - ink[o + 2]) * k + 127) / 255
    out[o + 3] = 255
    i += 1
  0

# Uncompressed full-resolution YCbCr (TIFF default coefficients = BT.601).
-> tif_ycc(px, npx) (u8[] i64) i64
  i = 0 ## i64
  while i < npx
    o = i * 4
    y0 = px[o] ## i64
    cb = px[o + 1] ## i64
    cr = px[o + 2] ## i64
    img_ycc_to_rgb(y0, cb, cr, px, o)
    i += 1
  0

img_register("tiff", ->(b) tiff_sniff?(b), ->(b) tiff_decode(b))
