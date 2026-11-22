# core/codec/image/png — PNG and APNG decoder (ISO/IEC 15948, APNG 1.0) in Tungsten.
#
# Every colour type and bit depth (grey 1/2/4/8/16, RGB 8/16, palette 1/2/4/8,
# grey+alpha 8/16, RGBA 8/16), Adam7 interlacing, tRNS (palette alpha and
# colour keys), colour: an iCCP profile goes through core/codec/image/icc (when it is a
# matrix/TRC profile), otherwise gAMA (+ cHRM) is honoured the way browsers
# do when no sRGB chunk overrides it. APNG: acTL/fcTL/fdAT with dispose
# (none/background/previous) and blend (source/over) into fully composited
# frames. CRCs are not checked and truncated image data decodes as far as it
# goes (the rest stays transparent), like browsers.
#
#   png_sniff?(bytes)   the 8-byte signature
#   png_decode(bytes)   → Bitmap (raises ImageError)

use core/codec/image
use core/codec/cicp
use icc

PNG_SIG = [137, 80, 78, 71, 13, 10, 26, 10]

-> png_sniff?(b)
  return false if b.size < 8
  i = 0
  while i < 8
    return false if b[i] != PNG_SIG[i]
    i += 1
  true

# Header and colour state for one image, shared by every frame.
+ PngInfo
  rw :w, :h, :ct, :bd, :interlace, :pal, :npal, :key, :gamma, :srgb, :icc, :chrm, :cicp

  -> new
    @pal = nil
    @npal = 0
    @key = nil
    @gamma = nil
    @srgb = false
    @icc = nil
    @chrm = nil
    @cicp = nil

  # Channels per pixel for the colour type.
  -> channels
    return 1 if @ct == 0 || @ct == 3
    return 3 if @ct == 2
    return 2 if @ct == 4
    4

-> png_tag(a, o) (u8[] i64) i64
  (a[o] << 24) | (a[o + 1] << 16) | (a[o + 2] << 8) | a[o + 3]

PNG_IHDR = 0x49484452
PNG_PLTE = 0x504C5445
PNG_IDAT = 0x49444154
PNG_IEND = 0x49454E44
PNG_TRNS = 0x74524E53
PNG_GAMA = 0x67414D41
PNG_SRGB = 0x73524742
PNG_ICCP = 0x69434350
PNG_CHRM = 0x6348524D
PNG_ACTL = 0x6163544C
PNG_FCTL = 0x6663544C
PNG_FDAT = 0x66644154
PNG_CICP = 0x63494350

-> png_decode(data)
  a = img_bytes(data)
  img_fail("png: not a PNG") if !png_sniff?(a)
  info = PngInfo.new
  n = a.size
  pos = 8
  seen_ihdr = false
  idat = []          # [offset, length] of each IDAT chunk
  seen_idat = false
  actl_frames = 0
  plays = 0
  frames = []        # [fctl fields, [[off, len], …]] in order
  cur = nil
  first_is_default = false
  seq = 0            # next expected APNG sequence number
  bad = false        # APNG structure error: show the default image only
  while pos + 8 <= n
    len = img_be32(a, pos)
    tag = png_tag(a, pos + 4)
    d = pos + 8
    break if len < 0 || d + len > n && tag != PNG_IDAT && tag != PNG_FDAT
    len = n - d if d + len > n
    if tag == PNG_IHDR
      img_fail("png: short IHDR") if len < 13
      info.w = img_be32(a, d)
      info.h = img_be32(a, d + 4)
      info.bd = a[d + 8]
      info.ct = a[d + 9]
      info.interlace = a[d + 12]
      img_fail("png: compression/filter method") if a[d + 10] != 0 || a[d + 11] != 0
      png_check_depth(info.ct, info.bd)
      img_check_size(info.w, info.h)
      seen_ihdr = true
    elsif !seen_ihdr
      img_fail("png: first chunk is not IHDR")
    elsif tag == PNG_PLTE
      np = len / 3
      np = 256 if np > 256
      p = u8[1024]
      i = 0
      while i < 256
        p[i * 4 + 3] = 255
        i += 1
      i = 0
      while i < np
        p[i * 4] = a[d + i * 3]
        p[i * 4 + 1] = a[d + i * 3 + 1]
        p[i * 4 + 2] = a[d + i * 3 + 2]
        i += 1
      info.pal = p
      info.npal = np
    elsif tag == PNG_TRNS
      if info.ct == 3
        if info.pal != nil
          i = 0
          while i < len && i < 256
            info.pal[i * 4 + 3] = a[d + i]
            i += 1
      elsif info.ct == 0 && len >= 2
        info.key = [img_be16(a, d)]
      elsif info.ct == 2 && len >= 6
        info.key = [img_be16(a, d), img_be16(a, d + 2), img_be16(a, d + 4)]
    elsif tag == PNG_GAMA && len >= 4
      g = img_be32(a, d)
      info.gamma = g if g > 0
    elsif tag == PNG_SRGB
      info.srgb = true
    elsif tag == PNG_CICP && len >= 4
      info.cicp = [a[d], a[d + 1]]
    elsif tag == PNG_ICCP
      info.icc = [d, len]
    elsif tag == PNG_CHRM && len >= 32
      c = []
      i = 0
      while i < 8
        c.push(img_be32(a, d + i * 4) / ~100000.0)
        i += 1
      info.chrm = c
    elsif tag == PNG_ACTL && len >= 8 && !seen_idat
      bad = true if actl_frames != 0
      actl_frames = img_be32(a, d)
      bad = true if actl_frames <= 0 || actl_frames > 0x7FFFFFFF
      plays = img_be32(a, d + 4)
    elsif tag == PNG_FCTL && len >= 26
      bad = true if img_be32(a, d) != seq
      seq += 1
      bad = true if cur != nil && cur[8].size == 0
      cur = [img_be32(a, d + 4), img_be32(a, d + 8), img_be32(a, d + 12), img_be32(a, d + 16),
        img_be16(a, d + 20), img_be16(a, d + 22), a[d + 24], a[d + 25], []]
      first_is_default = true if !seen_idat && frames.size == 0
      frames.push(cur)
    elsif tag == PNG_IDAT
      seen_idat = true
      idat.push([d, len])
      cur[8].push([d, len]) if cur != nil && first_is_default && frames.size == 1
    elsif tag == PNG_FDAT && len >= 4
      bad = true if img_be32(a, d) != seq || cur == nil || (first_is_default && frames.size == 1)
      seq += 1
      cur[8].push([d + 4, len - 4]) if cur != nil
    elsif tag == PNG_IEND
      break
    pos = d + len + 4
  img_fail("png: no IHDR") if !seen_ihdr
  img_fail("png: no image data") if idat.size == 0
  img_fail("png: palette image without PLTE") if info.ct == 3 && info.pal == nil
  conv = png_colour(a, info)
  base = Bitmap.new(info.w, info.h)
  png_frame(a, info, idat, info.w, info.h, base.rgba)
  png_convert(conv, base.rgba)
  return base if actl_frames == 0 || frames.size == 0
  # APNG. Structural errors (sequence numbers, frame counts, a frame without
  # data or of the wrong size) show the default image, as the spec asks.
  w = info.w
  h = info.h
  bad = true if frames.size != actl_frames || frames[frames.size - 1][8].size == 0
  if first_is_default
    f0 = frames[0]
    img_fail("png: default image's fcTL does not match IHDR") if f0[0] != w || f0[1] != h || f0[2] != 0 || f0[3] != 0
  return base if bad
  canvas = u8[w * h * 4]
  out = []
  fi = 0
  while fi < frames.size
    f = frames[fi]
    fw = f[0]
    fh = f[1]
    fx = f[2]
    fy = f[3]
    return base if fw <= 0 || fh <= 0 || fx < 0 || fy < 0 || fx + fw > w || fy + fh > h
    px = nil
    if fi == 0 && first_is_default
      px = base.rgba
    else
      px = u8[fw * fh * 4]
      st = 1
      begin
        st = png_frame(a, info, f[8], fw, fh, px)
      rescue e
        st = 1
      return base if st != 0
      png_convert(conv, px)
    dispose = f[6]
    dispose = 1 if dispose == 2 && fi == 0
    saved = nil
    saved = img_copy(canvas) if dispose == 2
    img_blit(canvas, w, h, px, fw, fh, fx, fy, f[7] == 1 ? 1 : 0)
    den = f[5] == 0 ? 100 : f[5]
    out.push([Bitmap.new(w, h, img_copy(canvas)), (f[4] * 1000 + den / 2) / den])
    if dispose == 1
      img_fill_rect(canvas, w, h, fx, fy, fw, fh, 0)
    elsif dispose == 2
      canvas = saved
    fi += 1
  res = Bitmap.new(w, h, out[0][0].rgba)
  if out.size > 1
    res.frames = out
    res.loop_count = plays
  res

-> png_check_depth(ct, bd)
  ok = false
  ok = bd == 1 || bd == 2 || bd == 4 || bd == 8 || bd == 16 if ct == 0
  ok = bd == 8 || bd == 16 if ct == 2 || ct == 4 || ct == 6
  ok = bd == 1 || bd == 2 || bd == 4 || bd == 8 if ct == 3
  img_fail("png: bad colour type/bit depth " + ct.to_s + "/" + bd.to_s) if !ok
  nil

# Concatenate the zlib data of `parts` and inflate it (as far as it goes).
-> png_inflate(a, parts, want)
  total = 0
  parts.each ->(p) total += p[1]
  z = u8[total]
  o = 0
  parts.each ->(p)
    png_copy(z, o, a, p[0], p[1])
    o += p[1]
  begin
    return Gzip.inflate_zlib(z, 0, want + 1, false)
  rescue e
    # A truncated or damaged stream: keep what a streaming inflater would
    # have produced by retrying on shorter prefixes is too costly; decode the
    # longest prefix of whole blocks we can.
    nil
  png_inflate_partial(z, want)

# Truncated zlib data: inflate a growing prefix is not possible with a
# one-shot inflater, so binary-search the longest prefix that inflates.
-> png_inflate_partial(z, want)
  lo = 2
  hi = z.size
  best = nil
  tries = 0
  while lo <= hi && tries < 24
    mid = (lo + hi) / 2
    got = nil
    begin
      got = Gzip.inflate_zlib(png_head(z, mid), 0, want + 1, false)
    rescue e
      got = nil
    if got != nil
      best = got
      lo = mid + 1
    else
      hi = mid - 1
    tries += 1
  best

-> png_head(z, n) (u8[] i64) u8[]
  b = u8[n]
  png_copy(b, 0, z, 0, n)
  b

-> png_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i + 8 <= n
    array_store_u64(dst, doff + i, array_load_u64(src, soff + i))
    i += 8
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

ADAM7 = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]

# Decode one image (the default image or an APNG frame) of w x h into out (RGBA8).
-> png_frame(a, info, parts, w, h, out)
  bits = info.channels * info.bd
  bpp = bits < 8 ? 1 : bits / 8
  key = info.key
  k0 = -1
  k1 = -1
  k2 = -1
  if key != nil
    k0 = key[0]
    if key.size == 3
      k1 = key[1]
      k2 = key[2]
  pal = info.pal == nil ? u8[4] : info.pal
  if info.interlace == 0
    rb = (w * bits + 7) / 8
    want = (rb + 1) * h
    raw = png_inflate(a, parts, want)
    return 1 if raw == nil
    rows = raw.size / (rb + 1)
    rows = h if rows > h
    png_unfilter(raw, 0, rows, rb, bpp)
    png_expand(raw, 0, rows, w, rb, info.ct, info.bd, pal, k0, k1, k2, out, 0, 1, 0, 0, w)
    return raw.size < want ? 1 : (raw.size > want ? 2 : 0)
  # Adam7: seven reduced images, one after another.
  want = 0
  p = 0
  while p < 7
    s = ADAM7[p]
    pw = (w - s[0] + s[2] - 1) / s[2]
    ph = (h - s[1] + s[3] - 1) / s[3]
    if pw > 0 && ph > 0
      want += ((pw * bits + 7) / 8 + 1) * ph
    p += 1
  raw = png_inflate(a, parts, want)
  return 1 if raw == nil
  off = 0
  p = 0
  while p < 7
    s = ADAM7[p]
    pw = (w - s[0] + s[2] - 1) / s[2]
    ph = (h - s[1] + s[3] - 1) / s[3]
    if pw > 0 && ph > 0
      rb = (pw * bits + 7) / 8
      avail = (raw.size - off) / (rb + 1)
      rows = ph < avail ? ph : avail
      if rows > 0
        png_unfilter(raw, off, rows, rb, bpp)
        png_expand_step(raw, off, rows, pw, rb, info.ct, info.bd, pal, k0, k1, k2, out, w, s[0], s[1], s[2], s[3])
      off += (rb + 1) * ph
      break if off >= raw.size
    p += 1
  raw.size < want ? 1 : (raw.size > want ? 2 : 0)

# Reverse the per-row filters in place: rows of 1 filter byte + rb bytes at d[off].
-> png_unfilter(d, off, rows, rb, bpp) (u8[] i64 i64 i64 i64) i64
  stride = rb + 1
  y = 0 ## i64
  while y < rows
    r = off + y * stride + 1
    ft = d[r - 1]
    pr = r - stride
    if ft == 1
      i = bpp ## i64
      while i < rb
        d[r + i] = (d[r + i] + d[r + i - bpp]) & 255
        i += 1
    elsif ft == 2
      if y > 0
        i = 0 ## i64
        while i < rb
          d[r + i] = (d[r + i] + d[pr + i]) & 255
          i += 1
    elsif ft == 3
      i = 0 ## i64
      while i < rb
        left = i >= bpp ? d[r + i - bpp] : 0
        up = y > 0 ? d[pr + i] : 0
        d[r + i] = (d[r + i] + ((left + up) >> 1)) & 255
        i += 1
    elsif ft == 4
      if y == 0
        i = bpp ## i64
        while i < rb
          d[r + i] = (d[r + i] + d[r + i - bpp]) & 255
          i += 1
      else
        i = 0 ## i64
        while i < bpp && i < rb
          d[r + i] = (d[r + i] + d[pr + i]) & 255
          i += 1
        while i < rb
          aa = d[r + i - bpp]
          bb = d[pr + i]
          cc = d[pr + i - bpp]
          pp = aa + bb - cc
          pa = pp - aa
          pa = 0 - pa if pa < 0
          pb = pp - bb
          pb = 0 - pb if pb < 0
          pc = pp - cc
          pc = 0 - pc if pc < 0
          pred = cc
          if pa <= pb && pa <= pc
            pred = aa
          elsif pb <= pc
            pred = bb
          d[r + i] = (d[r + i] + pred) & 255
          i += 1
    y += 1
  0

# Expand `rows` unfiltered rows into RGBA8 at out, non-interlaced (row y → out row y).
-> png_expand(d, off, rows, w, rb, ct, bd, pal, k0, k1, k2, out, oo, _s, _x0, _y0, ow) (u8[] i64 i64 i64 i64 i64 i64 u8[] i64 i64 i64 u8[] i64 i64 i64 i64 i64) i64
  png_expand_step(d, off, rows, w, rb, ct, bd, pal, k0, k1, k2, out, ow, 0, 0, 1, 1)

# Expand rows of a (reduced) image into out (width ow) at column x0 + x*dx, row y0 + y*dy.
-> png_expand_step(d, off, rows, w, rb, ct, bd, pal, k0, k1, k2, out, ow, x0, y0, dx, dy) (u8[] i64 i64 i64 i64 i64 i64 u8[] i64 i64 i64 u8[] i64 i64 i64 i64 i64) i64
  stride = rb + 1
  y = 0 ## i64
  while y < rows
    s = off + y * stride + 1
    o = ((y0 + y * dy) * ow + x0) * 4
    step = dx * 4
    x = 0 ## i64
    if ct == 6 && bd == 8
      while x < w
        out[o] = d[s]
        out[o + 1] = d[s + 1]
        out[o + 2] = d[s + 2]
        out[o + 3] = d[s + 3]
        s += 4
        o += step
        x += 1
    elsif ct == 2 && bd == 8
      while x < w
        r = d[s]
        g = d[s + 1]
        b = d[s + 2]
        out[o] = r
        out[o + 1] = g
        out[o + 2] = b
        out[o + 3] = (r == k0 && g == k1 && b == k2) ? 0 : 255
        s += 3
        o += step
        x += 1
    elsif ct == 3
      if bd == 8
        while x < w
          q = d[s] * 4
          out[o] = pal[q]
          out[o + 1] = pal[q + 1]
          out[o + 2] = pal[q + 2]
          out[o + 3] = pal[q + 3]
          s += 1
          o += step
          x += 1
      else
        per = 8 / bd
        mask = ((1 ## i64) << bd) - 1
        while x < w
          sh = 8 - bd * (x % per + 1)
          q = ((d[s + x / per] >> sh) & mask) * 4
          out[o] = pal[q]
          out[o + 1] = pal[q + 1]
          out[o + 2] = pal[q + 2]
          out[o + 3] = pal[q + 3]
          o += step
          x += 1
    elsif ct == 0
      if bd == 16
        while x < w
          v = (d[s] << 8) | d[s + 1]
          g = (v * 255 + 32767) / 65535
          out[o] = g
          out[o + 1] = g
          out[o + 2] = g
          out[o + 3] = v == k0 ? 0 : 255
          s += 2
          o += step
          x += 1
      else
        per = 8 / bd
        mask = ((1 ## i64) << bd) - 1
        scale = 255 / mask
        while x < w
          v = 0 ## i64
          if bd == 8
            v = d[s + x]
          else
            v = (d[s + x / per] >> (8 - bd * (x % per + 1))) & mask
          g = v * scale
          out[o] = g
          out[o + 1] = g
          out[o + 2] = g
          out[o + 3] = v == k0 ? 0 : 255
          o += step
          x += 1
    elsif ct == 4
      if bd == 8
        while x < w
          g = d[s]
          out[o] = g
          out[o + 1] = g
          out[o + 2] = g
          out[o + 3] = d[s + 1]
          s += 2
          o += step
          x += 1
      else
        while x < w
          g = (((d[s] << 8) | d[s + 1]) * 255 + 32767) / 65535
          out[o] = g
          out[o + 1] = g
          out[o + 2] = g
          out[o + 3] = (((d[s + 2] << 8) | d[s + 3]) * 255 + 32767) / 65535
          s += 4
          o += step
          x += 1
    elsif ct == 2
      while x < w
        r = (d[s] << 8) | d[s + 1]
        g = (d[s + 2] << 8) | d[s + 3]
        b = (d[s + 4] << 8) | d[s + 5]
        out[o] = (r * 255 + 32767) / 65535
        out[o + 1] = (g * 255 + 32767) / 65535
        out[o + 2] = (b * 255 + 32767) / 65535
        out[o + 3] = (r == k0 && g == k1 && b == k2) ? 0 : 255
        s += 6
        o += step
        x += 1
    else
      while x < w
        out[o] = (((d[s] << 8) | d[s + 1]) * 255 + 32767) / 65535
        out[o + 1] = (((d[s + 2] << 8) | d[s + 3]) * 255 + 32767) / 65535
        out[o + 2] = (((d[s + 4] << 8) | d[s + 5]) * 255 + 32767) / 65535
        out[o + 3] = (((d[s + 6] << 8) | d[s + 7]) * 255 + 32767) / 65535
        s += 8
        o += step
        x += 1
    y += 1
  0

# ---- colour ----
#
# The conversion to sRGB, decided once per image: nil (none), [:icc, profile]
# or [:lut, u8[256]] (a per-channel curve from gAMA).

-> png_colour(a, info)
  return nil if !img_colour?
  # Precedence (PNG 3rd edition): cICP, then iCCP, then sRGB, then gAMA/cHRM.
  if info.cicp != nil
    t = cicp_transform(info.cicp[0], info.cicp[1])
    return t == nil ? nil : [:cicp, t]
  return nil if info.srgb
  if info.icc != nil
    p = png_icc(a, info.icc[0], info.icc[1])
    return [:icc, p] if p != nil
    return nil
  g = info.gamma
  return nil if g == nil
  # gAMA is the encoding exponent ×100000: file = linear^gamma. sRGB is close to
  # 1/2.2 (45455); browsers leave values within a small band alone.
  return nil if g >= 45000 && g <= 46000
  lut = u8[256]
  # sample = linear^gamma, display ≈ linear^(1/2.2): out = sample^(1 / (gamma · 2.2))
  e = ~1.0 / ((g / ~100000.0) * ~2.2)
  i = 0
  while i < 256
    v = ((i / ~255.0) ** e) * ~255.0 + ~0.5
    lut[i] = v.to_i
    i += 1
  [:lut, lut]

# The iCCP profile parsed by core/codec/image/icc, or nil (unsupported, sRGB-like, or no core/codec/image/icc.w).
-> png_icc(a, d, len)
  z = d
  stop = d + len
  while z < stop && a[z] != 0
    z += 1
  return nil if z + 2 >= stop
  begin
    prof = Gzip.inflate_zlib(png_head_at(a, z + 2, stop - z - 2), 0, 0, false)
    p = icc_parse(prof, 0, prof.size)
    return nil if p == nil || icc_srgb?(p)
    return p
  rescue e
    nil
  nil

-> png_head_at(a, off, n) (u8[] i64 i64) u8[]
  b = u8[n]
  png_copy(b, 0, a, off, n)
  b

-> png_convert(conv, px)
  return nil if conv == nil
  if conv[0] == :lut
    png_lut(px, conv[1])
  elsif conv[0] == :cicp
    cicp_apply(conv[1], px, px.size / 4)
  else
    icc_apply(conv[1], px, px.size / 4)
  nil

-> png_lut(px, lut) (u8[] u8[]) i64
  i = 0 ## i64
  n = px.size
  while i < n
    px[i] = lut[px[i]]
    px[i + 1] = lut[px[i + 1]]
    px[i + 2] = lut[px[i + 2]]
    i += 4
  0

img_register("png", ->(b) png_sniff?(b), ->(b) png_decode(b))
