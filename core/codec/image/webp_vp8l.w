# core/codec/image/webp_vp8l — WebP lossless (VP8L) bitstream decoder.
#
# vp8l_decode(a, off, len) → [width, height, argb] where argb is an i64[] of
# 0xAARRGGBB pixels. vp8l_decode_alpha(a, off, len, w, h) → u8[] alpha plane
# (the ALPH chunk's lossless mode: a headerless VP8L stream, alpha = green).
#
# Follows the WebP Lossless Bitstream spec (RFC 9649) and libwebp's decoder:
# LSB-first bit reader over a zero-padded copy of the payload; canonical prefix
# codes in two-level lookup tables (8-bit root, subtables for longer codes);
# colour cache; LZ77 backward references with the 120-entry distance map;
# inverse transforms (predictor, cross-colour, subtract-green, colour indexing
# with pixel bundling) applied in reverse order.
#
# Table entries: value in bits 0..19, code length in 20..27, bit 28 marks a
# root entry that points at a subtable (value = offset, length = subtable bits).

use core/codec/image

VL_CODE_TO_PLANE = [
  0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a, 0x26, 0x2a,
  0x38, 0x05, 0x37, 0x39, 0x15, 0x1b, 0x36, 0x3a, 0x25, 0x2b, 0x48, 0x04,
  0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b, 0x46, 0x4a, 0x24, 0x2c, 0x58, 0x45,
  0x4b, 0x34, 0x3c, 0x03, 0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d,
  0x44, 0x4c, 0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e,
  0x66, 0x6a, 0x22, 0x2e, 0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b, 0x32, 0x3e,
  0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f, 0x64, 0x6c, 0x42, 0x4e,
  0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b, 0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e,
  0x00, 0x74, 0x7c, 0x41, 0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d,
  0x51, 0x5f, 0x40, 0x72, 0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70]
VL_CL_ORDER = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
VL_ALPHABET = [280, 256, 256, 256, 40]

-> vl_free(a)
  begin
    ccall("w_value_free_w", a)
  rescue e
    nil
  nil

# Decoder state: st[0] bit position, st[1] limit (last safe byte index for an
# 8-byte load), st[2] payload bit length.
-> vl_bits(buf, st, n) (u8[] i64[] i64) i64
  bp = st[0] ## i64
  i = bp >> 3 ## i64
  i = st[1] if i > st[1]
  v = (array_load_u64(buf, i) >> (bp & 7)) & (((1 ## i64) << n) - 1) ## i64
  st[0] = bp + n
  v

# Decode one symbol with the tree whose table starts at ht[off].
-> vl_sym(buf, st, ht, off) (u8[] i64[] i64[] i64) i64
  bp = st[0] ## i64
  i = bp >> 3 ## i64
  i = st[1] if i > st[1]
  bits = array_load_u64(buf, i) >> (bp & 7) ## i64
  e = ht[off + (bits & 255)] ## i64
  if e >= 0x10000000
    sb = (e >> 20) & 255 ## i64
    e = ht[off + (e & 0xFFFFF) + ((bits >> 8) & (((1 ## i64) << sb) - 1))] ## i64
  st[0] = bp + ((e >> 20) & 255)
  e & 0xFFFFF

# Build the lookup table for code lengths lens[0...n] at ht[base]. Returns the
# table size, or -1 for an invalid code. ht must have room for 33024 entries.
# rev and work are scratch i64[] of at least n entries / 16 + 256 entries.
-> vl_build(lens, n, ht, base, rev, work) (i64[] i64 i64[] i64 i64[] i64[]) i64
  k = 0 ## i64
  while k < 16
    work[k] = 0
    k += 1
  nz = 0 ## i64
  last = 0 ## i64
  s = 0 ## i64
  while s < n
    l = lens[s] ## i64
    if l > 0
      work[l] += 1
      nz += 1
      last = s
    s += 1
  if nz == 0
    return -1
  if nz == 1
    k = 0
    while k < 256
      ht[base + k] = last
      k += 1
    return 256
  # Kraft: over-subscribed codes are invalid; incomplete ones also (as libwebp)
  left = 1 ## i64
  l = 1 ## i64
  while l < 16
    left = (left << 1) - work[l] ## i64
    return -1 if left < 0
    l += 1
  return -1 if left != 0
  # canonical first code per length (work[16 + l])
  code = 0 ## i64
  l = 1
  while l < 16
    work[16 + l] = code
    code = (code + work[l]) << 1 ## i64
    l += 1
  # sub-table sizes per root index (work[32 + idx])
  k = 0
  while k < 256
    work[32 + k] = 0
    ht[base + k] = 0
    k += 1
  s = 0
  while s < n
    l = lens[s] ## i64
    if l > 0
      c = work[16 + l] ## i64
      work[16 + l] = c + 1
      r = 0 ## i64
      j = 0 ## i64
      while j < l
        r = (r << 1) | ((c >> j) & 1) ## i64
        j += 1
      rev[s] = r
      if l > 8
        idx = r & 255 ## i64
        sb = l - 8
        work[32 + idx] = sb if sb > work[32 + idx]
    s += 1
  size = 256 ## i64
  k = 0
  while k < 256
    sb = work[32 + k] ## i64
    if sb > 0
      ht[base + k] = 0x10000000 | (sb << 20) | size
      j = 0
      while j < ((1 ## i64) << sb)
        ht[base + size + j] = 0
        j += 1
      size += 1 << sb
    k += 1
  s = 0
  while s < n
    l = lens[s] ## i64
    if l > 0
      r = rev[s] ## i64
      e = s | (l << 20) ## i64
      if l <= 8
        k = r
        while k < 256
          ht[base + k] = e
          k += 1 << l
      else
        root = ht[base + (r & 255)] ## i64
        so = base + (root & 0xFFFFF) ## i64
        sb = (root >> 20) & 255 ## i64
        k = r >> 8 ## i64
        while k < ((1 ## i64) << sb)
          ht[so + k] = e
          k += 1 << (l - 8)
    s += 1
  size

+ Vp8lDecoder
  # buf: padded payload; st: bit state; ht: all prefix-code tables of the
  # current image stream level (grown as needed).
  rw :buf, :st, :ht, :hsize, :rev, :work, :lens
  -> new(@buf, @st)
    @ht = i64[65536]
    @hsize = 0
    @rev = i64[2400]
    @work = i64[300]
    @lens = i64[2400]

  -> fail(msg)
    raise ImageError, "webp lossless: " + msg

  -> bits(n)
    vl_bits(@buf, @st, n)

  -> eos?
    @st[0] > @st[2]

  -> ensure_room
    if @hsize + 33100 > @ht.size
      bigger = i64[@ht.size * 2]
      i = 0
      n = @hsize
      vl_copy64(bigger, @ht, n)
      vl_free(@ht)
      @ht = bigger
    nil

  # Read one prefix code of `alpha` symbols; returns its table offset in @ht.
  -> read_code(alpha)
    lens = @lens
    vl_zero(lens, alpha)
    if bits(1) == 1
      ns = bits(1) + 1
      first8 = bits(1)
      s = bits(first8 == 0 ? 1 : 8)
      fail("bad symbol") if s >= alpha
      lens[s] = 1
      if ns == 2
        s2 = bits(8)
        fail("bad symbol") if s2 >= alpha
        lens[s2] = 1
    else
      cl = i64[19]
      nc = bits(4) + 4
      fail("bad code length count") if nc > 19
      i = 0
      while i < nc
        cl[VL_CL_ORDER[i]] = bits(3)
        i += 1
      ensure_room()
      cbase = @hsize
      sz = vl_build(cl, 19, @ht, cbase, @rev, @work)
      fail("bad code-length code") if sz < 0
      max_sym = alpha
      if bits(1) == 1
        nb = 2 + 2 * bits(3)
        max_sym = 2 + bits(nb)
        fail("bad max symbol") if max_sym > alpha
      r = vl_read_lengths(@buf, @st, @ht, cbase, lens, alpha, max_sym)
      fail("bad code lengths") if r < 0
      vl_free(cl)
    fail("truncated") if eos?
    ensure_room()
    base = @hsize
    sz = vl_build(lens, alpha, @ht, base, @rev, @work)
    fail("bad prefix code") if sz < 0
    @hsize = base + sz
    base

  # Decode an entropy-coded image of xs x ys pixels (level0: the main image,
  # which may use a meta prefix image). Returns i64[] ARGB.
  -> image_stream(xs, ys, level0)
    cbits = 0
    if bits(1) == 1
      cbits = bits(4)
      fail("bad colour cache bits") if cbits < 1 || cbits > 11
    meta = nil
    mbits = 30
    mw = 1
    ngroups = 1
    if level0 && bits(1) == 1
      mbits = bits(3) + 2
      mw = vl_sub(xs, mbits)
      mh = vl_sub(ys, mbits)
      saved = @hsize
      mimg = image_stream(mw, mh, false)
      @hsize = saved
      meta = i64[mw * mh]
      ngroups = vl_meta_groups(mimg, meta, mw * mh)
      vl_free(mimg)
    if meta == nil
      meta = i64[1]
    saved_h = @hsize
    hoff = i64[ngroups * 5]
    g = 0
    while g < ngroups
      j = 0
      while j < 5
        alpha = VL_ALPHABET[j]
        alpha += ((1 ## i64) << cbits) if j == 0 && cbits > 0
        hoff[g * 5 + j] = read_code(alpha)
        j += 1
      g += 1
    out = i64[xs * ys]
    cache = i64[cbits > 0 ? ((1 ## i64) << cbits) : 1]
    r = vl_pixels(@buf, @st, @ht, hoff, meta, mbits, mw, out, xs, ys, cache, cbits)
    vl_free(cache)
    vl_free(hoff)
    vl_free(meta)
    @hsize = saved_h
    fail("bad backward reference") if r == -1
    fail("bad colour cache index") if r == -2
    fail("truncated") if r == -3 || eos?
    out

  # The main image: transforms, then the entropy-coded pixels, then the
  # inverse transforms. Returns i64[] ARGB of w x h.
  -> decode_main(w, h)
    transforms = []
    seen = 0
    xs = w
    while bits(1) == 1
      ty = bits(2)
      fail("duplicate transform") if (seen & ((1 ## i64) << ty)) != 0
      seen = seen | ((1 ## i64) << ty)
      if ty == 0 || ty == 1
        tb = bits(3) + 2
        data = image_stream(vl_sub(xs, tb), vl_sub(h, tb), false)
        transforms.push([ty, tb, xs, data])
      elsif ty == 3
        nc = bits(8) + 1
        tb = nc > 16 ? 0 : (nc > 4 ? 1 : (nc > 2 ? 2 : 3))
        pal = image_stream(nc, 1, false)
        full = i64[1 << (8 >> tb)]
        vl_palette(pal, nc, full)
        vl_free(pal)
        transforms.push([ty, tb, xs, full])
        xs = vl_sub(xs, tb)
      else
        transforms.push([ty, 0, xs, nil])
    px = image_stream(xs, h, true)
    i = transforms.size - 1
    while i >= 0
      t = transforms[i]
      ty = t[0]
      if ty == 0
        vl_inv_predict(px, t[2], h, t[3], t[1])
      elsif ty == 1
        vl_inv_cross(px, t[2], h, t[3], t[1])
      elsif ty == 2
        vl_add_green(px, t[2] * h)
      else
        out = i64[t[2] * h]
        vl_inv_index(px, xs, out, t[2], h, t[3], t[1])
        vl_free(px)
        px = out
      xs = t[2]
      vl_free(t[3]) if t[3] != nil
      i -= 1
    px

-> vl_copy64(dst, src, n) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < n
    dst[i] = src[i]
    i += 1
  n

-> vl_zero(a, n) (i64[] i64) i64
  i = 0 ## i64
  while i < n
    a[i] = 0
    i += 1
  n

-> vl_sub(size, b) (i64 i64) i64
  (size + ((1 ## i64) << b) - 1) >> b

-> vl_meta_groups(mimg, meta, n) (i64[] i64[] i64) i64
  mx = 0 ## i64
  i = 0 ## i64
  while i < n
    g = (mimg[i] >> 8) & 0xFFFF ## i64
    meta[i] = g
    mx = g if g > mx
    i += 1
  mx + 1

-> vl_read_lengths(buf, st, ht, cbase, lens, alpha, max_sym) (u8[] i64[] i64[] i64 i64[] i64 i64) i64
  prev = 8 ## i64
  s = 0 ## i64
  left = max_sym ## i64
  while s < alpha
    if left == 0
      return 0
    left -= 1
    c = vl_sym(buf, st, ht, cbase)
    if c < 16
      lens[s] = c
      s += 1
      prev = c if c != 0
    else
      extra = 2 ## i64
      off = 3 ## i64
      if c == 17
        extra = 3
      elsif c == 18
        extra = 7
        off = 11
      rep = vl_bits(buf, st, extra) + off
      return -1 if s + rep > alpha
      v = c == 16 ? prev : 0
      while rep > 0
        lens[s] = v
        s += 1
        rep -= 1
  0

-> vl_plane_dist(xs, code) (i64 i64) i64
  return code - 120 if code > 120
  dc = VL_CODE_TO_PLANE[code - 1]
  d = (dc >> 4) * xs + 8 - (dc & 15) ## i64
  d >= 1 ? d : 1

# The entropy-coded pixels. Returns 0, or -1 bad reference, -2 bad cache
# index, -3 ran past the end of the data.
-> vl_pixels(buf, st, ht, hoff, meta, mbits, mw, out, xs, ys, cache, cbits) (u8[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64) i64
  total = xs * ys
  pos = 0 ## i64
  x = 0 ## i64
  y = 0 ## i64
  csize = cbits > 0 ? ((1 ## i64) << cbits) : 0
  cshift = 32 - cbits
  limit = st[2] + 64
  lim = st[1]
  bp = st[0]
  one = 1 ## i64
  ii = 0 ## i64
  bb = 0 ## i64
  e = 0 ## i64
  code = 0 ## i64
  r = 0 ## i64
  b = 0 ## i64
  a = 0 ## i64
  ds = 0 ## i64
  while pos < total
    g = meta[(y >> mbits) * mw + (x >> mbits)] * 5 ## i64
    ii = bp >> 3
    ii = lim if ii > lim
    bb = array_load_u64(buf, ii) >> (bp & 7)
    e = ht[hoff[g] + (bb & 255)]
    if e >= 0x10000000
      e = ht[hoff[g] + (e & 0xFFFFF) + ((bb >> 8) & ((one << ((e >> 20) & 255)) - 1))]
    bp += (e >> 20) & 255
    code = e & 0xFFFFF
    if code < 256
      ii = bp >> 3
      ii = lim if ii > lim
      bb = array_load_u64(buf, ii) >> (bp & 7)
      e = ht[hoff[g + 1] + (bb & 255)]
      if e >= 0x10000000
        e = ht[hoff[g + 1] + (e & 0xFFFFF) + ((bb >> 8) & ((one << ((e >> 20) & 255)) - 1))]
      bp += (e >> 20) & 255
      r = e & 0xFFFFF
      ii = bp >> 3
      ii = lim if ii > lim
      bb = array_load_u64(buf, ii) >> (bp & 7)
      e = ht[hoff[g + 2] + (bb & 255)]
      if e >= 0x10000000
        e = ht[hoff[g + 2] + (e & 0xFFFFF) + ((bb >> 8) & ((one << ((e >> 20) & 255)) - 1))]
      bp += (e >> 20) & 255
      b = e & 0xFFFFF
      ii = bp >> 3
      ii = lim if ii > lim
      bb = array_load_u64(buf, ii) >> (bp & 7)
      e = ht[hoff[g + 3] + (bb & 255)]
      if e >= 0x10000000
        e = ht[hoff[g + 3] + (e & 0xFFFFF) + ((bb >> 8) & ((one << ((e >> 20) & 255)) - 1))]
      bp += (e >> 20) & 255
      a = e & 0xFFFFF
      p = (a << 24) | (r << 16) | (code << 8) | b ## i64
      out[pos] = p
      if csize > 0
        cache[((p * 0x1e35a7bd) & (0xFFFFFFFF ## i64)) >> cshift] = p
      pos += 1
      x += 1
      if x == xs
        x = 0
        y += 1
        return vl_ret(st, bp, -3) if bp > limit
    elsif code < 280
      ls = code - 256
      len = ls + 1
      if ls >= 4
        eb = (ls - 2) >> 1 ## i64
        len = ((2 + (ls & 1)) << eb) + vl_bits_at(buf, bp, lim, eb) + 1
        bp += eb ## i64
      ii = bp >> 3
      ii = lim if ii > lim
      bb = array_load_u64(buf, ii) >> (bp & 7)
      e = ht[hoff[g + 4] + (bb & 255)]
      if e >= 0x10000000
        e = ht[hoff[g + 4] + (e & 0xFFFFF) + ((bb >> 8) & ((one << ((e >> 20) & 255)) - 1))]
      bp += (e >> 20) & 255
      ds = e & 0xFFFFF
      dcode = ds + 1
      if ds >= 4
        eb = (ds - 2) >> 1 ## i64
        dcode = ((2 + (ds & 1)) << eb) + vl_bits_at(buf, bp, lim, eb) + 1
        bp += eb ## i64
      dist = vl_plane_dist(xs, dcode)
      return vl_ret(st, bp, -1) if dist > pos || pos + len > total
      k = 0 ## i64
      while k < len
        p = out[pos - dist] ## i64
        out[pos] = p
        if csize > 0
          cache[((p * 0x1e35a7bd) & (0xFFFFFFFF ## i64)) >> cshift] = p
        pos += 1
        k += 1
      x += len
      while x >= xs
        x -= xs
        y += 1
      return vl_ret(st, bp, -3) if bp > limit
    else
      ci = code - 280
      return vl_ret(st, bp, -2) if ci >= csize
      p = cache[ci] ## i64
      out[pos] = p
      pos += 1
      x += 1
      if x == xs
        x = 0
        y += 1
        return vl_ret(st, bp, -3) if bp > limit
  st[0] = bp
  0

-> vl_ret(st, bp, code) (i64[] i64 i64) i64
  st[0] = bp
  code

-> vl_bits_at(buf, bp, lim, n) (u8[] i64 i64 i64) i64
  i = bp >> 3 ## i64
  i = lim if i > lim
  (array_load_u64(buf, i) >> (bp & 7)) & (((1 ## i64) << n) - 1)

# Colour-indexing palette: delta-coded entries summed per channel; the rest of
# the 2^(8 >> bits) table stays transparent black.
-> vl_palette(pal, nc, full) (i64[] i64 i64[]) i64
  full[0] = pal[0]
  i = 1 ## i64
  while i < nc
    full[i] = vl_add(pal[i], full[i - 1])
    i += 1
  0

-> vl_add(a, b) (i64 i64) i64
  (((a & (0xFF00FF00 ## i64)) + (b & (0xFF00FF00 ## i64))) & (0xFF00FF00 ## i64)) | (((a & 0x00FF00FF) + (b & 0x00FF00FF)) & 0x00FF00FF)

-> vl_avg2(a, b) (i64 i64) i64
  (((a ^ b) & (0xFEFEFEFE ## i64)) >> 1) + (a & b)

-> vl_clip255(v) (i64) i64
  return 0 if v < 0
  return 255 if v > 255
  v

-> vl_absi(v) (i64) i64
  v < 0 ? 0 - v : v

-> vl_select(a, b, c) (i64 i64 i64) i64
  pa = 0 ## i64
  sh = 0 ## i64
  while sh < 32
    ac = (a >> sh) & 255 ## i64
    bc = (b >> sh) & 255 ## i64
    cc = (c >> sh) & 255 ## i64
    pa += ((bc - cc) < 0 ? 0 - (bc - cc) : (bc - cc)) - ((ac - cc) < 0 ? 0 - (ac - cc) : (ac - cc))
    sh += 8
  pa <= 0 ? a : b

-> vl_clamp_full(c0, c1, c2) (i64 i64 i64) i64
  o = 0 ## i64
  sh = 0 ## i64
  while sh < 32
    v = ((((c0 >> sh) & 255) + ((c1 >> sh) & 255) - ((c2 >> sh) & 255)) < 0 ? 0 : ((((c0 >> sh) & 255) + ((c1 >> sh) & 255) - ((c2 >> sh) & 255)) > 255 ? 255 : (((c0 >> sh) & 255) + ((c1 >> sh) & 255) - ((c2 >> sh) & 255)))) ## i64
    o = o | (v << sh) ## i64
    sh += 8
  o

-> vl_clamp_half(c0, c1, c2) (i64 i64 i64) i64
  ave = vl_avg2(c0, c1)
  o = 0 ## i64
  sh = 0 ## i64
  while sh < 32
    a = (ave >> sh) & 255 ## i64
    b = (c2 >> sh) & 255 ## i64
    d = a - b
    # C's (a - b) / 2 truncates toward zero
    h = d >= 0 ? d >> 1 : 0 - ((0 - d) >> 1)
    o = o | (((a + h) < 0 ? 0 : ((a + h) > 255 ? 255 : (a + h))) << sh) ## i64
    sh += 8
  o

-> vl_predict(mode, px, pos, w) (i64 i64[] i64 i64) i64
  l = px[pos - 1] ## i64
  t = px[pos - w] ## i64
  if mode == 1
    return l
  if mode == 2
    return t
  if mode == 3
    return px[pos - w + 1]
  if mode == 4
    return px[pos - w - 1]
  if mode == 5
    return vl_avg2(vl_avg2(l, px[pos - w + 1]), t)
  if mode == 6
    return vl_avg2(l, px[pos - w - 1])
  if mode == 7
    return vl_avg2(l, t)
  if mode == 8
    return vl_avg2(px[pos - w - 1], t)
  if mode == 9
    return vl_avg2(t, px[pos - w + 1])
  if mode == 10
    return vl_avg2(vl_avg2(l, px[pos - w - 1]), vl_avg2(t, px[pos - w + 1]))
  if mode == 11
    return vl_select(t, l, px[pos - w - 1])
  if mode == 12
    return vl_clamp_full(l, t, px[pos - w - 1])
  if mode == 13
    return vl_clamp_half(l, t, px[pos - w - 1])
  (0xFF000000 ## i64)

-> vl_inv_predict(px, w, h, data, bits) (i64[] i64 i64 i64[] i64) i64
  return 0 if w * h == 0
  px[0] = vl_add(px[0], (0xFF000000 ## i64))
  x = 1 ## i64
  while x < w
    px[x] = vl_add(px[x], px[x - 1])
    x += 1
  tw = vl_sub(w, bits)
  y = 1 ## i64
  while y < h
    row = y * w
    px[row] = vl_add(px[row], px[row - w])
    trow = (y >> bits) * tw ## i64
    x = 1
    while x < w
      mode = (data[trow + (x >> bits)] >> 8) & 15 ## i64
      pos = row + x
      # run of pixels sharing this tile's mode
      tend = ((x >> bits) + 1) << bits ## i64
      tend = w if tend > w
      if mode == 1
        while x < tend
          px[row + x] = vl_add(px[row + x], px[row + x - 1])
          x += 1
      elsif mode == 2
        while x < tend
          px[row + x] = vl_add(px[row + x], px[row + x - w])
          x += 1
      else
        while x < tend
          pos = row + x
          px[pos] = vl_add(px[pos], vl_predict(mode, px, pos, w))
          x += 1
    y += 1
  0

-> vl_s8(v) (i64) i64
  v >= 128 ? v - 256 : v

-> vl_inv_cross(px, w, h, data, bits) (i64[] i64 i64 i64[] i64) i64
  tw = vl_sub(w, bits)
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      m = data[(y >> bits) * tw + (x >> bits)] ## i64
      g2r = ((m & 255) >= 128 ? (m & 255) - 256 : (m & 255)) ## i64
      g2b = (((m >> 8) & 255) >= 128 ? ((m >> 8) & 255) - 256 : ((m >> 8) & 255)) ## i64
      r2b = (((m >> 16) & 255) >= 128 ? ((m >> 16) & 255) - 256 : ((m >> 16) & 255)) ## i64
      tend = ((x >> bits) + 1) << bits ## i64
      tend = w if tend > w
      while x < tend
        pos = y * w + x
        p = px[pos] ## i64
        g = (((p >> 8) & 255) >= 128 ? ((p >> 8) & 255) - 256 : ((p >> 8) & 255)) ## i64
        r = ((p >> 16) & 255) + ((g2r * g) >> 5) ## i64
        r = r & 255 ## i64
        b = (p & 255) + ((g2b * g) >> 5) + ((r2b * ((r) >= 128 ? (r) - 256 : (r))) >> 5) ## i64
        b = b & 255 ## i64
        px[pos] = (p & (0xFF00FF00 ## i64)) | (r << 16) | b
        x += 1
    y += 1
  0

-> vl_add_green(px, n) (i64[] i64) i64
  i = 0 ## i64
  while i < n
    p = px[i] ## i64
    g = (p >> 8) & 255 ## i64
    px[i] = (p & (0xFF00FF00 ## i64)) | (((((p >> 16) & 255) + g) & 255) << 16) | (((p & 255) + g) & 255)
    i += 1
  0

-> vl_inv_index(src, sw, out, w, h, pal, bits) (i64[] i64 i64[] i64 i64 i64[] i64) i64
  bpp = 8 >> bits ## i64
  mask = ((1 ## i64) << bpp) - 1 ## i64
  ppb = 1 << bits ## i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      p = src[y * sw + (x >> bits)] ## i64
      idx = ((p >> 8) & 255) >> (bpp * (x & (ppb - 1))) ## i64
      out[y * w + x] = pal[idx & mask]
      x += 1
    y += 1
  0

# -> [w, h, argb]
-> vp8l_decode(a, off, len)
  raise ImageError, "webp lossless: truncated header" if len < 5 || off + len > a.size
  raise ImageError, "webp lossless: bad signature" if a[off] != 0x2f
  buf = vl_padded(a, off + 1, len - 1)
  st = i64[3]
  st[1] = buf.size - 8
  st[2] = (len - 1) * 8
  d = Vp8lDecoder.new(buf, st)
  w = d.bits(14) + 1
  h = d.bits(14) + 1
  d.bits(1)
  ver = d.bits(3)
  raise ImageError, "webp lossless: bad version" if ver != 0
  img_check_size(w, h)
  px = d.decode_main(w, h)
  vl_free(d.ht)
  vl_free(buf)
  [w, h, px]

-> vp8l_decode_alpha(a, off, len, w, h)
  buf = vl_padded(a, off, len)
  st = i64[3]
  st[1] = buf.size - 8
  st[2] = len * 8
  d = Vp8lDecoder.new(buf, st)
  px = d.decode_main(w, h)
  out = u8[w * h]
  vl_green(px, out, w * h)
  vl_free(px)
  vl_free(d.ht)
  vl_free(buf)
  out

-> vl_green(px, out, n) (i64[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    out[i] = (px[i] >> 8) & 255
    i += 1
  0

-> vl_padded(a, off, len) (u8[] i64 i64) u8[]
  len = 0 if len < 0
  b = u8[len + 16]
  i = 0 ## i64
  while i < len
    b[i] = a[off + i]
    i += 1
  b
