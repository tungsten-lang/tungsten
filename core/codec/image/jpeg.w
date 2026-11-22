# core/codec/image/jpeg — a JPEG (ITU T.81 / JFIF / Adobe) decoder in Tungsten.
#
#   jpeg_sniff?(bytes)   FF D8 FF
#   jpeg_decode(bytes)   → Bitmap (straight sRGB RGBA8), raises ImageError
#
# Supported: baseline and extended sequential (8- and 12-bit precision; 12-bit
# is reduced to 8), progressive (spectral selection and successive
# approximation), Huffman and arithmetic entropy coding, restart intervals
# (a damaged or missing RSTn resynchronises at the next one), any sampling
# factors 1..4 (2x horizontal and/or vertical chroma use libjpeg's "fancy"
# triangle upsampling, but — like Apple's ImageIO decoder, measured against it —
# each MCU is upsampled on its own, replicating its edge samples instead of
# reading the neighbouring MCU; other ratios replicate), greyscale, RGB, YCbCr, CMYK and
# YCCK (Adobe APP14 transform flag; Adobe CMYK is stored inverted), EXIF
# orientation (APP1) and embedded ICC profiles (APP2, matrix/TRC profiles via
# core/codec/image/icc). A truncated file decodes what is there; missing blocks are grey.
# Not supported (ImageError): lossless (SOF3/SOF7/SOF11/SOF15) and
# hierarchical (SOF5-7, SOF13-15) JPEG. CMYK is converted with the naive
# formula (embedded CMYK profiles are LUT-based and not applied).
#
# Layout: every scan decodes into one i32[] of coefficients (all components, 64
# per block, natural order), then each block is dequantised and run through
# libjpeg's accurate integer IDCT (jidctint "islow") into a per-component u8
# plane, the planes are upsampled and colour-converted into RGBA.
#
# Hot state lives in typed arrays so the inner loops are machine code:
#   st  i64[16]  bit reader: 0 pos, 1 bit buffer, 2 bits in buffer, 3 marker/EOF
#                reached, 4 EOB run, 5 zero bytes fed past the end of the data
#   ci  i64[64]  per component (16 each): 0 coefficient offset, 1 blocks per row
#                (allocated), 2 h, 3 v, 4 DC table, 5 AC table, 6 quant table,
#                7 blocks across the component, 8 blocks down, 9 DC predictor,
#                10 id, 11 allocated block rows, 12 arith DC context (last diff class)
#   sc  i64[32]  scan: 0 ncomp, 1 Ss, 2 Se, 3 Ah, 4 Al, 5 restart interval,
#                6 MCUs across, 7 MCUs down, 8 progressive, 9..12 component
#                indexes, 13 arithmetic
#   hh  i64[...] Huffman tables 0-3 DC, 4-7 AC: 9-bit lookahead (len << 8 | sym)
#                at t*512, maxcode at 4096 + t*18, value offset at 4240 + t*18,
#                values at 4384 + t*256

use core/codec/image

-> jpeg_sniff?(b)
  b.size >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF

img_register("jpeg", ->(b) jpeg_sniff?(b), ->(b) jpeg_decode(b))

-> jpeg_decode(data)
  JpegDecoder.new(img_bytes(data)).decode

JPEG_ZZ_LIST = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
  28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
  63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63]

JPEG_STATE = [nil]

# Zigzag → natural order, padded with 63s so a corrupt run past 63 stays in the block.
-> jpeg_zz
  if JPEG_STATE[0] == nil
    z = i64[80]
    k = 0
    while k < 80
      z[k] = JPEG_ZZ_LIST[k]
      k += 1
    JPEG_STATE[0] = z
  JPEG_STATE[0]

+ JpegDecoder
  ro :coefs, :qt

  -> new(@d)
    @qt = i64[256]
    @hh = i64[4384 + 8 * 256]
    @ci = i64[64]
    @sc = i64[32]
    @st = i64[16]
    @ncomp = 0
    @w = 0
    @h = 0
    @prec = 8
    @prog = false
    @arith = false
    @frame = false
    @scans = 0
    @restart = 0
    @adobe = -1
    @jfif = false
    @orient = 1
    @icc = []
    @coefs = nil
    @hmax = 1
    @vmax = 1
    @mcux = 0
    @mcuy = 0
    # arithmetic conditioning: DC L/U at k, AC Kx at 8 + k (defaults 0, 1, 5)
    @ac_cond = i64[16]
    k = 0
    while k < 4
      @ac_cond[k] = 0
      @ac_cond[4 + k] = 1
      @ac_cond[8 + k] = 5
      k += 1

  -> decode
    d = @d
    n = d.size
    img_fail("not a JPEG") if !jpeg_sniff?(d)
    pos = 2
    done = false
    while !done
      # next marker: skip anything that is not FF xx (garbage between segments)
      while pos < n && d[pos] != 0xFF
        pos += 1
      while pos < n && d[pos] == 0xFF
        pos += 1
      break if pos >= n
      m = d[pos]
      pos += 1
      if m == 0xD9
        done = true
      elsif m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)
        nil
      else
        break if pos + 2 > n
        len = img_be16(d, pos)
        img_fail("bad JPEG segment length") if len < 2
        seg = pos + 2
        slen = len - 2
        # truncated segment: stop here, keep what decoded
        break if seg + slen > n
        if m == 0xDA
          img_fail("JPEG scan before frame header") if !@frame
          pos = scan(seg, slen)
        else
          segment(m, seg, slen)
          pos = seg + slen
    img_fail("JPEG has no frame") if !@frame
    img_fail("JPEG has no image data") if @scans == 0
    finish

  -> segment(m, p, len)
    d = @d
    if m == 0xC0 || m == 0xC1 || m == 0xC2 || m == 0xC9 || m == 0xCA
      frame(m, p, len)
    elsif m == 0xC3 || m == 0xC7 || m == 0xCB || m == 0xCF
      img_fail("lossless JPEG is not supported")
    elsif m == 0xC5 || m == 0xC6 || m == 0xCD || m == 0xCE
      img_fail("hierarchical JPEG is not supported")
    elsif m == 0xC4
      dht(p, len)
    elsif m == 0xDB
      dqt(p, len)
    elsif m == 0xCC
      dac(p, len)
    elsif m == 0xDD
      @restart = img_be16(d, p)
    elsif m == 0xE0
      @jfif = true if len >= 5 && d[p] == 74 && d[p + 1] == 70 && d[p + 2] == 73 && d[p + 3] == 70 && d[p + 4] == 0
    elsif m == 0xE1
      if len >= 6 && d[p] == 69 && d[p + 1] == 120 && d[p + 2] == 105 && d[p + 3] == 102 && d[p + 4] == 0
        @orient = img_exif_orientation(d, p, len)
    elsif m == 0xE2
      if len > 14 && jpeg_tag?(d, p, "ICC_PROFILE")
        @icc.push([d[p + 12], p + 14, len - 14])
    elsif m == 0xEE
      if len >= 12 && d[p] == 65 && d[p + 1] == 100 && d[p + 2] == 111 && d[p + 3] == 98 && d[p + 4] == 101
        @adobe = d[p + 11]
    nil

  -> frame(m, p, len)
    d = @d
    img_fail("JPEG has two frames") if @frame
    img_fail("short JPEG frame header") if len < 6
    @prog = m == 0xC2 || m == 0xCA
    @arith = m == 0xC9 || m == 0xCA
    @prec = d[p]
    img_fail("JPEG precision " + @prec.to_s + " is not supported") if @prec != 8 && @prec != 12
    @h = img_be16(d, p + 1)
    @w = img_be16(d, p + 3)
    @ncomp = d[p + 5]
    img_fail("JPEG with height 0 (DNL) is not supported") if @h == 0
    img_check_size(@w, @h)
    img_fail("JPEG with " + @ncomp.to_s + " components") if @ncomp < 1 || @ncomp > 4 || @ncomp == 2
    img_fail("short JPEG frame header") if len < 6 + @ncomp * 3
    ci = @ci
    c = 0
    while c < @ncomp
      q = p + 6 + c * 3
      ci[c * 16 + 10] = d[q]
      hs = d[q + 1] >> 4
      vs = d[q + 1] & 15
      img_fail("bad JPEG sampling factors") if hs < 1 || hs > 4 || vs < 1 || vs > 4
      ci[c * 16 + 2] = hs
      ci[c * 16 + 3] = vs
      ci[c * 16 + 6] = d[q + 2] & 3
      @hmax = hs if hs > @hmax
      @vmax = vs if vs > @vmax
      c += 1
    @mcux = (@w + 8 * @hmax - 1) / (8 * @hmax)
    @mcuy = (@h + 8 * @vmax - 1) / (8 * @vmax)
    total = 0
    c = 0
    while c < @ncomp
      b = c * 16
      hs = ci[b + 2]
      vs = ci[b + 3]
      ci[b + 0] = total
      ci[b + 1] = @mcux * hs
      ci[b + 11] = @mcuy * vs
      cw = (@w * hs + @hmax - 1) / @hmax
      chh = (@h * vs + @vmax - 1) / @vmax
      ci[b + 7] = (cw + 7) / 8
      ci[b + 8] = (chh + 7) / 8
      total += ci[b + 1] * ci[b + 11] * 64
      c += 1
    @coefs = i32[total]
    @frame = true
    nil

  -> dqt(p, len)
    d = @d
    zz = jpeg_zz()
    e = p + len
    while p < e
      pq = d[p] >> 4
      tq = d[p] & 3
      p += 1
      return nil if p + (pq == 0 ? 64 : 128) > e
      k = 0
      while k < 64
        v = 0
        if pq == 0
          v = d[p]
          p += 1
        else
          v = img_be16(d, p)
          p += 2
        @qt[tq * 64 + zz[k]] = v
        k += 1
    nil

  -> dht(p, len)
    d = @d
    e = p + len
    while p + 17 <= e
      tc = d[p] >> 4
      th = d[p] & 3
      img_fail("bad JPEG Huffman table class") if tc > 1
      t = tc * 4 + th
      counts = i64[17]
      total = 0
      k = 1
      while k <= 16
        counts[k] = d[p + k]
        total += counts[k]
        k += 1
      p += 17
      img_fail("bad JPEG Huffman table") if total > 256 || p + total > e
      k = 0
      while k < total
        @hh[4384 + t * 256 + k] = d[p + k]
        k += 1
      p += total
      img_fail("bad JPEG Huffman table") if jpeg_huff_build(@hh, t, counts) < 0
    nil

  # DAC: arithmetic conditioning (Tc 0: DC L in low nibble, U in high; Tc 1: AC Kx).
  -> dac(p, len)
    d = @d
    e = p + len
    while p + 2 <= e
      tc = d[p] >> 4
      tb = d[p] & 3
      v = d[p + 1]
      if tc == 0
        @ac_cond[tb] = v & 15
        @ac_cond[4 + tb] = v >> 4
      else
        @ac_cond[8 + tb] = v
      p += 2
    nil

  # Start of scan: read its header, decode its entropy-coded data; returns the
  # position after the data.
  -> scan(p, len)
    d = @d
    sc = @sc
    ci = @ci
    ns = d[p]
    img_fail("bad JPEG scan header") if ns < 1 || ns > 4 || len < 4 + ns * 2
    k = 0
    while k < ns
      cid = d[p + 1 + k * 2]
      tb = d[p + 2 + k * 2]
      c = 0
      while c < @ncomp && ci[c * 16 + 10] != cid
        c += 1
      img_fail("JPEG scan names an unknown component") if c >= @ncomp
      sc[9 + k] = c
      ci[c * 16 + 4] = (tb >> 4) & 3
      ci[c * 16 + 5] = tb & 3
      k += 1
    q = p + 1 + ns * 2
    sc[0] = ns
    sc[1] = d[q]
    sc[2] = d[q + 1]
    sc[3] = d[q + 2] >> 4
    sc[4] = d[q + 2] & 15
    sc[5] = @restart
    sc[6] = @mcux
    sc[7] = @mcuy
    sc[8] = @prog ? 1 : 0
    sc[13] = @arith ? 1 : 0
    if !@prog
      sc[1] = 0
      sc[2] = 63
      sc[3] = 0
      sc[4] = 0
    elsif sc[1] > sc[2] || sc[2] > 63 || (sc[1] == 0 && sc[2] != 0) || (sc[1] > 0 && ns != 1)
      # an invalid progressive scan: skip its data
      return jpeg_skip_scan(d, p + len)
    st = @st
    st[0] = p + len
    st[1] = 0
    st[2] = 0
    st[3] = 0
    st[4] = 0
    st[5] = 0
    c = 0
    while c < 4
      ci[c * 16 + 9] = 0
      ci[c * 16 + 12] = 0
      c += 1
    @scans += 1
    if @arith
      ar = JpegArith.new(@ac_cond)
      ar.run(d, st, @coefs, ci, sc)
    else
      jpeg_scan_huff(d, st, @hh, @coefs, ci, sc, jpeg_zz())
    jpeg_skip_scan(d, st[0])

  # ---- reconstruction ----

  -> finish
    w = @w
    h = @h
    ci = @ci
    planes = []
    c = 0
    while c < @ncomp
      b = c * 16
      bw = ci[b + 1]
      bh = ci[b + 11]
      pl = u8[bw * 8 * bh * 8]
      jpeg_idct_plane(@coefs, ci[b], bw, ci[b + 7] < bw ? ci[b + 7] + 1 : bw, ci[b + 8] < bh ? ci[b + 8] + 1 : bh, @qt, ci[b + 6] * 64, pl, @prec)
      planes.push(pl)
      c += 1
    # full-resolution planes
    full = []
    strides = []
    c = 0
    while c < @ncomp
      b = c * 16
      hs = ci[b + 2]
      vs = ci[b + 3]
      pw = ci[b + 1] * 8
      if hs == @hmax && vs == @vmax
        full.push(planes[c])
        strides.push(pw)
      else
        cw = (w * hs + @hmax - 1) / @hmax
        chh = (h * vs + @vmax - 1) / @vmax
        out = u8[w * h]
        jpeg_upsample(planes[c], pw, cw, chh, out, w, h, hs, vs, @hmax, @vmax)
        full.push(out)
        strides.push(w)
      c += 1
    bm = Bitmap.new(w, h)
    rgba = bm.rgba
    mode = colour_mode()
    if @ncomp == 1
      jpeg_gray(full[0], strides[0], rgba, w, h)
    elsif @ncomp == 3
      jpeg_rgb(full[0], strides[0], full[1], strides[1], full[2], strides[2], rgba, w, h, mode)
    else
      ink = u8[w * h * 4]
      jpeg_ink(full[0], strides[0], full[1], strides[1], full[2], strides[2], full[3], strides[3], ink, w, h, mode)
      p = icc_profile()
      if p != nil && p.cmyk?
        icc_apply_cmyk(p, ink, rgba, w * h)
      else
        jpeg_ink_rgb(ink, rgba, w * h)
    apply_icc(rgba, w * h) if @icc.size > 0 && @ncomp != 4
    img_orient(bm, @orient)

  # 0 YCbCr, 1 RGB (3 components); 4 components: 2 YCCK, 3 CMYK inverted (Adobe), 4 CMYK plain
  -> colour_mode
    ci = @ci
    if @ncomp == 3
      return 0 if @jfif
      if @adobe >= 0
        return @adobe == 0 ? 1 : 0
      return 1 if ci[10] == 82 && ci[26] == 71 && ci[42] == 66
      return 0
    if @adobe >= 0
      return @adobe == 2 ? 2 : 3
    4

  -> apply_icc(rgba, npix)
    p = icc_profile()
    return nil if p == nil
    return nil if p.cmyk? || p.gray? != (@ncomp == 1)
    return nil if icc_srgb?(p)
    icc_apply(p, rgba, npix)
    nil

  # The embedded ICC profile (APP2 chunks in sequence order), parsed, or nil.
  -> icc_profile
    return nil if @icc.size == 0
    chunks = @icc.sort_by(->(c) c[0])
    total = 0
    chunks.each ->(c) total += c[2]
    buf = u8[total]
    o = 0
    chunks.each ->(c)
      k = 0
      while k < c[2]
        buf[o + k] = @d[c[1] + k]
        k += 1
      o += c[2]
    icc_parse(buf, 0, total)

-> jpeg_tag?(d, p, s)
  k = 0
  while k < s.size
    return false if d[p + k] != s.byte_at(k)
    k += 1
  d[p + s.size] == 0

# Position of the next marker that is not a stuffed byte or an RSTn at or after p.
-> jpeg_skip_scan(d, p) (u8[] i64) i64
  n = d.size
  while p + 1 < n
    if d[p] == 0xFF
      m = d[p + 1]
      if m != 0 && m != 0xFF && (m < 0xD0 || m > 0xD7)
        return p
    p += 1
  n

# ---------------------------------------------------------------------------
# Huffman tables and the bit reader
# ---------------------------------------------------------------------------

-> jpeg_huff_build(hh, t, counts) (i64[] i64 i64[]) i64
  lb = t * 512
  i = 0 ## i64
  while i < 512
    hh[lb + i] = 0
    i += 1
  mb = 4096 + t * 18
  vb = 4240 + t * 18
  code = 0 ## i64
  idx = 0 ## i64
  l = 1 ## i64
  while l <= 16
    nl = counts[l]
    if nl > 0
      hh[vb + l] = idx - code
      return -1 if code + nl > (1 << l)
      k = 0 ## i64
      while k < nl
        if l <= 9
          sym = hh[4384 + t * 256 + idx]
          base = code << (9 - l)
          cnt = 1 << (9 - l)
          j = 0 ## i64
          while j < cnt
            hh[lb + base + j] = (l << 8) | sym
            j += 1
        code += 1
        idx += 1
        k += 1
      hh[mb + l] = code - 1
    else
      hh[mb + l] = -1
    code = code << 1
    l += 1
  hh[mb + 17] = 0x7FFFFFFF
  0

# Top up the bit buffer to more than 56 bits. Past a marker or the end of the
# data it feeds zero bytes (counted in st[5]).
-> jpeg_fill(d, st) (u8[] i64[]) i64
  pos = st[0]
  buf = st[1]
  cnt = st[2]
  n = d.size
  while cnt <= 56
    if st[3] != 0
      buf = buf << 8
      cnt += 8
      st[5] = st[5] + 1
    elsif pos >= n
      st[3] = 1
    else
      b = d[pos]
      if b == 0xFF
        nb = 0xD9 ## i64
        nb = d[pos + 1] if pos + 1 < n
        if nb == 0
          pos += 2
          buf = (buf << 8) | 0xFF
          cnt += 8
        elsif nb == 0xFF
          pos += 1
        else
          st[3] = 1
      else
        pos += 1
        buf = (buf << 8) | b
        cnt += 8
  st[0] = pos
  st[1] = buf
  st[2] = cnt
  0

-> jpeg_bits(d, st, n) (u8[] i64[] i64) i64
  return 0 if n == 0
  jpeg_fill(d, st) if st[2] < n
  cnt = st[2] - n
  st[2] = cnt
  (st[1] >> cnt) & ((1 << n) - 1)

-> jpeg_extend(v, s) (i64 i64) i64
  return v if s == 0 || v >= (1 << (s - 1))
  v - (1 << s) + 1

-> jpeg_huff(d, st, hh, t) (u8[] i64[] i64[] i64) i64
  jpeg_fill(d, st) if st[2] < 16
  cnt = st[2]
  buf = st[1]
  e = hh[t * 512 + ((buf >> (cnt - 9)) & 511)]
  if e != 0
    st[2] = cnt - (e >> 8)
    return e & 255
  code = (buf >> (cnt - 16)) & 0xFFFF
  mb = 4096 + t * 18
  l = 10 ## i64
  while l <= 16 && (code >> (16 - l)) > hh[mb + l]
    l += 1
  if l > 16
    st[2] = cnt - 16
    return 0
  st[2] = cnt - l
  idx = hh[4240 + t * 18 + l] + (code >> (16 - l))
  return 0 if idx < 0 || idx > 255
  hh[4384 + t * 256 + idx]

# True when the reader has consumed bits that were never in the data.
-> jpeg_overrun(st) (i64[]) i64
  return 0 if st[3] == 0
  st[2] < st[5] * 8 ? 1 : 0

# Restart: drop buffered bits, expect RSTn at the reader position (searching
# forward past damage), reset the predictors and the EOB run.
-> jpeg_restart(d, st, ci) (u8[] i64[] i64[]) i64
  n = d.size
  pos = st[0]
  found = 0 ## i64
  while pos + 1 < n && found == 0
    if d[pos] == 0xFF && d[pos + 1] >= 0xD0 && d[pos + 1] <= 0xD7
      pos += 2
      found = 1
    elsif d[pos] == 0xFF && d[pos + 1] != 0 && d[pos + 1] != 0xFF
      # another marker: the scan's data ends here
      found = 2
    else
      pos += 1
  st[0] = pos
  st[1] = 0
  st[2] = 0
  st[3] = found == 1 ? 0 : 1
  st[4] = 0
  st[5] = 0
  c = 0 ## i64
  while c < 4
    ci[c * 16 + 9] = 0
    ci[c * 16 + 12] = 0
    c += 1
  found

# ---------------------------------------------------------------------------
# Huffman scans
# ---------------------------------------------------------------------------

-> jpeg_scan_huff(d, st, hh, co, ci, sc, zz) (u8[] i64[] i64[] i32[] i64[] i64[] i64[]) i64
  ns = sc[0]
  ss = sc[1]
  se = sc[2]
  ah = sc[3]
  al = sc[4]
  ri = sc[5]
  mode = 0 ## i64
  if sc[8] != 0
    if ss == 0
      mode = ah == 0 ? 1 : 2
    else
      mode = ah == 0 ? 3 : 4
  total = 0 ## i64
  nx = 0 ## i64
  if ns == 1
    c = sc[9]
    nx = ci[c * 16 + 7]
    total = nx * ci[c * 16 + 8]
  else
    nx = sc[6]
    total = nx * sc[7]
  m = 0 ## i64
  left = ri ## i64
  while m < total
    if ri > 0 && left == 0
      r = jpeg_restart(d, st, ci)
      return 0 if r != 1
      left = ri
    my = m / nx
    mx = m - my * nx
    if ns == 1
      c = sc[9]
      b = c * 16
      off = ci[b] + (my * ci[b + 1] + mx) * 64
      jpeg_block(d, st, hh, co, off, ci, c, zz, mode, ss, se, al)
    else
      k = 0 ## i64
      while k < ns
        c = sc[9 + k]
        b = c * 16
        hs = ci[b + 2]
        vs = ci[b + 3]
        v = 0 ## i64
        while v < vs
          u = 0 ## i64
          while u < hs
            off = ci[b] + ((my * vs + v) * ci[b + 1] + mx * hs + u) * 64
            jpeg_block(d, st, hh, co, off, ci, c, zz, mode, ss, se, al)
            u += 1
          v += 1
        k += 1
    left -= 1
    m += 1
    # past the end of the data and no restart to resynchronise at: stop
    return 0 if jpeg_overrun(st) == 1 && (ri == 0 || left != 0)
  0

-> jpeg_block(d, st, hh, co, off, ci, c, zz, mode, ss, se, al) (u8[] i64[] i64[] i32[] i64 i64[] i64 i64[] i64 i64 i64 i64) i64
  b = c * 16
  if mode == 0
    s = jpeg_huff(d, st, hh, ci[b + 4])
    diff = 0 ## i64
    diff = jpeg_extend(jpeg_bits(d, st, s), s) if s != 0
    pred = ci[b + 9] + diff
    ci[b + 9] = pred
    co[off] = pred
    act = ci[b + 5] + 4
    k = 1 ## i64
    while k < 64
      rs = jpeg_huff(d, st, hh, act)
      r = rs >> 4
      s = rs & 15
      if s != 0
        k += r
        v = jpeg_extend(jpeg_bits(d, st, s), s)
        co[off + zz[k]] = v if k < 64
        k += 1
      elsif r == 15
        k += 16
      else
        k = 64
    return 0
  if mode == 1
    s = jpeg_huff(d, st, hh, ci[b + 4])
    diff = 0 ## i64
    diff = jpeg_extend(jpeg_bits(d, st, s), s) if s != 0
    pred = ci[b + 9] + diff
    ci[b + 9] = pred
    co[off] = pred << al
    return 0
  if mode == 2
    co[off] = co[off] | (1 << al) if jpeg_bits(d, st, 1) != 0
    return 0
  act = ci[b + 5] + 4
  if mode == 3
    eob = st[4]
    if eob > 0
      st[4] = eob - 1
      return 0
    k = ss ## i64
    while k <= se
      rs = jpeg_huff(d, st, hh, act)
      r = rs >> 4
      s = rs & 15
      if s != 0
        k += r
        v = jpeg_extend(jpeg_bits(d, st, s), s)
        co[off + zz[k]] = v << al if k < 64
        k += 1
      elsif r == 15
        k += 16
      else
        eob = 1 << r
        eob += jpeg_bits(d, st, r) if r != 0
        st[4] = eob - 1
        k = 64
    return 0
  # mode 4: AC successive-approximation refinement (libjpeg decode_mcu_AC_refine)
  p1 = 1 << al
  m1 = 0 - p1
  k = ss ## i64
  eob = st[4]
  if eob == 0
    while k <= se
      rs = jpeg_huff(d, st, hh, act)
      r = rs >> 4
      s = rs & 15
      if s != 0
        s = jpeg_bits(d, st, 1) != 0 ? p1 : m1
      elsif r != 15
        eob = 1 << r
        eob += jpeg_bits(d, st, r) if r != 0
        break
      going = 1 ## i64
      while k <= se && going == 1
        pz = off + zz[k]
        cf = co[pz]
        if cf != 0
          if jpeg_bits(d, st, 1) != 0
            if (cf & p1) == 0
              co[pz] = cf >= 0 ? cf + p1 : cf + m1
          k += 1
        else
          r -= 1
          if r < 0
            going = 0
          else
            k += 1
      if s != 0 && k <= 63
        co[off + zz[k]] = s
      k += 1
  if eob > 0
    while k <= se
      pz = off + zz[k]
      cf = co[pz]
      if cf != 0
        if jpeg_bits(d, st, 1) != 0
          if (cf & p1) == 0
            co[pz] = cf >= 0 ? cf + p1 : cf + m1
      k += 1
    eob -= 1
  st[4] = eob
  0

# ---------------------------------------------------------------------------
# IDCT (libjpeg jidctint.c, accurate integer)
# ---------------------------------------------------------------------------

# Blocks [0, nbx) x [0, nby) of one component into its plane (stride bw * 8).
-> jpeg_idct_plane(co, base, bw, nbx, nby, qt, qo, pl, prec) (i32[] i64 i64 i64 i64 i64[] i64 u8[] i64) i64
  ws = i64[64]
  stride = bw * 8
  by = 0 ## i64
  while by < nby
    bx = 0 ## i64
    while bx < nbx
      jpeg_idct(co, base + (by * bw + bx) * 64, qt, qo, ws, pl, by * 8 * stride + bx * 8, stride, prec)
      bx += 1
    by += 1
  0

-> jpeg_idct(co, o, qt, qo, ws, out, oo, stride, prec) (i32[] i64 i64[] i64 i64[] u8[] i64 i64 i64) i64
  # pass 1: columns, results scaled up by 2^2 (PASS1_BITS)
  c = 0 ## i64
  while c < 8
    i = o + c
    q = qo + c
    if co[i + 8] == 0 && co[i + 16] == 0 && co[i + 24] == 0 && co[i + 32] == 0 && co[i + 40] == 0 && co[i + 48] == 0 && co[i + 56] == 0
      dc = (co[i] * qt[q]) << 2
      ws[c] = dc
      ws[c + 8] = dc
      ws[c + 16] = dc
      ws[c + 24] = dc
      ws[c + 32] = dc
      ws[c + 40] = dc
      ws[c + 48] = dc
      ws[c + 56] = dc
    else
      z2 = co[i + 16] * qt[q + 16]
      z3 = co[i + 48] * qt[q + 48]
      z1 = (z2 + z3) * 4433
      tmp2 = z1 - z3 * 15137
      tmp3 = z1 + z2 * 6270
      z2 = co[i] * qt[q]
      z3 = co[i + 32] * qt[q + 32]
      tmp0 = (z2 + z3) << 13
      tmp1 = (z2 - z3) << 13
      tmp10 = tmp0 + tmp3
      tmp13 = tmp0 - tmp3
      tmp11 = tmp1 + tmp2
      tmp12 = tmp1 - tmp2
      tmp0 = co[i + 56] * qt[q + 56]
      tmp1 = co[i + 40] * qt[q + 40]
      tmp2 = co[i + 24] * qt[q + 24]
      tmp3 = co[i + 8] * qt[q + 8]
      z1 = tmp0 + tmp3
      z2 = tmp1 + tmp2
      z3 = tmp0 + tmp2
      z4 = tmp1 + tmp3
      z5 = (z3 + z4) * 9633
      tmp0 = tmp0 * 2446
      tmp1 = tmp1 * 16819
      tmp2 = tmp2 * 25172
      tmp3 = tmp3 * 12299
      z1 = z1 * -7373
      z2 = z2 * -20995
      z3 = z3 * -16069 + z5
      z4 = z4 * -3196 + z5
      tmp0 += z1 + z3
      tmp1 += z2 + z4
      tmp2 += z2 + z3
      tmp3 += z1 + z4
      ws[c] = (tmp10 + tmp3 + 1024) >> 11
      ws[c + 56] = (tmp10 - tmp3 + 1024) >> 11
      ws[c + 8] = (tmp11 + tmp2 + 1024) >> 11
      ws[c + 48] = (tmp11 - tmp2 + 1024) >> 11
      ws[c + 16] = (tmp12 + tmp1 + 1024) >> 11
      ws[c + 40] = (tmp12 - tmp1 + 1024) >> 11
      ws[c + 24] = (tmp13 + tmp0 + 1024) >> 11
      ws[c + 32] = (tmp13 - tmp0 + 1024) >> 11
    c += 1
  # pass 2: rows, descale by 2^(13 + 2 + 3), level shift, clamp
  center = prec == 12 ? 2048 : 128
  maxv = prec == 12 ? 4095 : 255
  sh = prec == 12 ? 4 : 0
  r = 0 ## i64
  while r < 8
    w = r * 8
    p = oo + r * stride
    if ws[w + 1] == 0 && ws[w + 2] == 0 && ws[w + 3] == 0 && ws[w + 4] == 0 && ws[w + 5] == 0 && ws[w + 6] == 0 && ws[w + 7] == 0
      v = jpeg_px((ws[w] + 16) >> 5, center, maxv, sh)
      out[p] = v
      out[p + 1] = v
      out[p + 2] = v
      out[p + 3] = v
      out[p + 4] = v
      out[p + 5] = v
      out[p + 6] = v
      out[p + 7] = v
    else
      z2 = ws[w + 2]
      z3 = ws[w + 6]
      z1 = (z2 + z3) * 4433
      tmp2 = z1 - z3 * 15137
      tmp3 = z1 + z2 * 6270
      tmp0 = (ws[w] + ws[w + 4]) << 13
      tmp1 = (ws[w] - ws[w + 4]) << 13
      tmp10 = tmp0 + tmp3
      tmp13 = tmp0 - tmp3
      tmp11 = tmp1 + tmp2
      tmp12 = tmp1 - tmp2
      tmp0 = ws[w + 7]
      tmp1 = ws[w + 5]
      tmp2 = ws[w + 3]
      tmp3 = ws[w + 1]
      z1 = tmp0 + tmp3
      z2 = tmp1 + tmp2
      z3 = tmp0 + tmp2
      z4 = tmp1 + tmp3
      z5 = (z3 + z4) * 9633
      tmp0 = tmp0 * 2446
      tmp1 = tmp1 * 16819
      tmp2 = tmp2 * 25172
      tmp3 = tmp3 * 12299
      z1 = z1 * -7373
      z2 = z2 * -20995
      z3 = z3 * -16069 + z5
      z4 = z4 * -3196 + z5
      tmp0 += z1 + z3
      tmp1 += z2 + z4
      tmp2 += z2 + z3
      tmp3 += z1 + z4
      out[p] = jpeg_px((tmp10 + tmp3 + 131072) >> 18, center, maxv, sh)
      out[p + 7] = jpeg_px((tmp10 - tmp3 + 131072) >> 18, center, maxv, sh)
      out[p + 1] = jpeg_px((tmp11 + tmp2 + 131072) >> 18, center, maxv, sh)
      out[p + 6] = jpeg_px((tmp11 - tmp2 + 131072) >> 18, center, maxv, sh)
      out[p + 2] = jpeg_px((tmp12 + tmp1 + 131072) >> 18, center, maxv, sh)
      out[p + 5] = jpeg_px((tmp12 - tmp1 + 131072) >> 18, center, maxv, sh)
      out[p + 3] = jpeg_px((tmp13 + tmp0 + 131072) >> 18, center, maxv, sh)
      out[p + 4] = jpeg_px((tmp13 - tmp0 + 131072) >> 18, center, maxv, sh)
    r += 1
  0

-> jpeg_px(v, center, maxv, sh) (i64 i64 i64 i64) i64
  v += center
  return 0 if v < 0
  return maxv >> sh if v > maxv
  return v if sh == 0
  v = (v + 8) >> 4
  v > 255 ? 255 : v

# ---------------------------------------------------------------------------
# Upsampling and colour conversion
# ---------------------------------------------------------------------------

# Component plane src (stride ss, real size cw x chh) to w x h in out.
-> jpeg_upsample(src, ss, cw, chh, out, w, h, hs, vs, hmax, vmax) (u8[] i64 i64 i64 u8[] i64 i64 i64 i64 i64 i64) i64
  fx = hmax / hs
  fy = vmax / vs
  exact = (hmax % hs == 0 && vmax % vs == 0) ? 1 : 0
  if exact == 1 && fx == 2 && fy == 1
    y = 0 ## i64
    while y < h
      jpeg_h2_row(src, y * ss, cw, out, y * w, w)
      y += 1
    return 0
  if exact == 1 && fx == 1 && fy == 2
    y = 0 ## i64
    while y < h
      r = y >> 1
      o = r - 1
      bias = 1 ## i64
      if (y & 1) == 1
        o = r + 1
        bias = 2
      r = chh - 1 if r > chh - 1
      o = 0 if o < 0
      o = chh - 1 if o > chh - 1
      o = r if (o >> 3) != (r >> 3)
      x = 0 ## i64
      while x < w
        out[y * w + x] = (src[r * ss + x] * 3 + src[o * ss + x] + bias) >> 2
        x += 1
      y += 1
    return 0
  if exact == 1 && fx == 2 && fy == 2
    y = 0 ## i64
    while y < h
      r = y >> 1
      o = (y & 1) == 1 ? r + 1 : r - 1
      r = chh - 1 if r > chh - 1
      o = 0 if o < 0
      o = chh - 1 if o > chh - 1
      if (o >> 3) != (r >> 3)
        o = r if (o < r && JPEG_H2V2[0] == 1) || (o > r && JPEG_H2V2[1] == 1)
      if JPEG_H2V2[2] == 1
        sx = 0 ## i64
        while sx < cw
          n8 = cw - sx
          n8 = 8 if n8 > 8
          jpeg_h2v2_row(src, r * ss + sx, o * ss + sx, n8, out, y * w + sx * 2, w - sx * 2)
          sx += 8
      else
        jpeg_h2v2_row(src, r * ss, o * ss, cw, out, y * w, w)
      y += 1
    return 0
  if exact == 1 && JPEG_UPS[0] != 0
    jpeg_ups_bilinear(src, ss, cw, chh, out, w, h, fx, fy, JPEG_UPS[1], JPEG_UPS[2])
    return 0
  # generic: replicate
  y = 0 ## i64
  while y < h
    sy = (y * vs) / vmax
    sy = chh - 1 if sy > chh - 1
    x = 0 ## i64
    while x < w
      sx = (x * hs) / hmax
      sx = cw - 1 if sx > cw - 1
      out[y * w + x] = src[sy * ss + sx]
      x += 1
    y += 1
  0

# Upsampling choices, tuned against ImageIO (kept as data so a test can flip
# them): JPEG_UPS = [bilinear for factors other than 2 (else replicate), keep
# horizontal context inside the MCU, keep vertical context inside the MCU];
# JPEG_H2V2 = [2x2 chroma: no context from the MCU row above, none from below,
# none from the MCU to the left/right]. 2x1 chroma uses libjpeg's row-wide
# context and 1x2 MCU-local context, which is what ImageIO does.
JPEG_UPS = [1, 1, 1]
JPEG_H2V2 = [1, 1, 1]

# Centred bilinear for integer factors fx, fy: output sample j of source
# sample i sits at i + (2j + 1 - f) / 2f. With lx/ly set, a neighbour in another
# MCU (8 source samples) is replaced by the edge sample.
-> jpeg_ups_bilinear(src, ss, cw, chh, out, w, h, fx, fy, lx, ly) (u8[] i64 i64 i64 u8[] i64 i64 i64 i64 i64 i64) i64
  tmp = i64[w * chh]
  # horizontal: tmp scaled by 2fx
  r = 0 ## i64
  while r < chh
    x = 0 ## i64
    while x < w
      i = x / fx
      j = x - i * fx
      i = cw - 1 if i > cw - 1
      t = 2 * j + 1 - fx
      nb = i ## i64
      wt = 0 ## i64
      if t < 0
        nb = i - 1
        wt = 0 - t
      else
        nb = i + 1
        wt = t
      nb = 0 if nb < 0
      nb = cw - 1 if nb > cw - 1
      nb = i if lx == 1 && (nb >> 3) != (i >> 3)
      tmp[r * w + x] = src[r * ss + i] * (2 * fx - wt) + src[r * ss + nb] * wt
      x += 1
    r += 1
  den = 4 * fx * fy
  y = 0 ## i64
  while y < h
    i = y / fy
    j = y - i * fy
    i = chh - 1 if i > chh - 1
    t = 2 * j + 1 - fy
    nb = i ## i64
    wt = 0 ## i64
    if t < 0
      nb = i - 1
      wt = 0 - t
    else
      nb = i + 1
      wt = t
    nb = 0 if nb < 0
    nb = chh - 1 if nb > chh - 1
    nb = i if ly == 1 && (nb >> 3) != (i >> 3)
    x = 0 ## i64
    while x < w
      out[y * w + x] = (tmp[i * w + x] * (2 * fy - wt) + tmp[nb * w + x] * wt + (den >> 1)) / den
      x += 1
    y += 1
  0

-> jpeg_h2_row(src, so, cw, out, oo, w) (u8[] i64 i64 u8[] i64 i64) i64
  if cw == 1
    out[oo] = src[so]
    out[oo + 1] = src[so] if w > 1
    return 0
  out[oo] = src[so]
  v = (src[so] * 3 + src[so + 1] + 2) >> 2
  out[oo + 1] = v if w > 1
  i = 1 ## i64
  while i < cw - 1
    s = src[so + i] * 3
    x = i * 2
    out[oo + x] = (s + src[so + i - 1] + 1) >> 2 if x < w
    out[oo + x + 1] = (s + src[so + i + 1] + 2) >> 2 if x + 1 < w
    i += 1
  l = cw - 1
  x = l * 2
  out[oo + x] = (src[so + l] * 3 + src[so + l - 1] + 1) >> 2 if x < w
  out[oo + x + 1] = src[so + l] if x + 1 < w
  0

-> jpeg_h2v2_row(src, r0, r1, cw, out, oo, w) (u8[] i64 i64 i64 u8[] i64 i64) i64
  this = src[r0] * 3 + src[r1]
  if cw == 1
    out[oo] = (this * 4 + 8) >> 4
    out[oo + 1] = (this * 4 + 7) >> 4 if w > 1
    return 0
  nxt = src[r0 + 1] * 3 + src[r1 + 1]
  out[oo] = (this * 4 + 8) >> 4
  out[oo + 1] = (this * 3 + nxt + 7) >> 4 if w > 1
  last = this
  this = nxt
  i = 1 ## i64
  while i < cw - 1
    nxt = src[r0 + i + 1] * 3 + src[r1 + i + 1]
    x = i * 2
    out[oo + x] = (this * 3 + last + 8) >> 4 if x < w
    out[oo + x + 1] = (this * 3 + nxt + 7) >> 4 if x + 1 < w
    last = this
    this = nxt
    i += 1
  x = (cw - 1) * 2
  out[oo + x] = (this * 3 + last + 8) >> 4 if x < w
  out[oo + x + 1] = (this * 4 + 7) >> 4 if x + 1 < w
  0

-> jpeg_gray(p, ps, out, w, h) (u8[] i64 u8[] i64 i64) i64
  y = 0 ## i64
  o = 0 ## i64
  while y < h
    i = y * ps
    x = 0 ## i64
    while x < w
      v = p[i + x]
      out[o] = v
      out[o + 1] = v
      out[o + 2] = v
      out[o + 3] = 255
      o += 4
      x += 1
    y += 1
  0

-> jpeg_rgb(p0, s0, p1, s1, p2, s2, out, w, h, mode) (u8[] i64 u8[] i64 u8[] i64 u8[] i64 i64 i64) i64
  y = 0 ## i64
  o = 0 ## i64
  while y < h
    i0 = y * s0
    i1 = y * s1
    i2 = y * s2
    x = 0 ## i64
    if mode == 1
      while x < w
        out[o] = p0[i0 + x]
        out[o + 1] = p1[i1 + x]
        out[o + 2] = p2[i2 + x]
        out[o + 3] = 255
        o += 4
        x += 1
    else
      while x < w
        yy = p0[i0 + x]
        cb = p1[i1 + x] - 128
        cr = p2[i2 + x] - 128
        r = yy + ((91881 * cr + 32768) >> 16)
        g = yy + ((-22554 * cb - 46802 * cr + 32768) >> 16)
        b = yy + ((116130 * cb + 32768) >> 16)
        r = 0 if r < 0
        r = 255 if r > 255
        g = 0 if g < 0
        g = 255 if g > 255
        b = 0 if b < 0
        b = 255 if b > 255
        out[o] = r
        out[o + 1] = g
        out[o + 2] = b
        out[o + 3] = 255
        o += 4
        x += 1
    y += 1
  0

# Four planes → ink in the ICC convention (0 = no ink), 4 bytes per pixel.
# mode 2 YCCK (Adobe), 3 Adobe CMYK (stored inverted), 4 plain CMYK.
-> jpeg_ink(p0, s0, p1, s1, p2, s2, p3, s3, out, w, h, mode) (u8[] i64 u8[] i64 u8[] i64 u8[] i64 u8[] i64 i64 i64) i64
  y = 0 ## i64
  o = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      c = p0[y * s0 + x]
      m = p1[y * s1 + x]
      ye = p2[y * s2 + x]
      k = p3[y * s3 + x]
      if mode == 2
        # YCCK: the encoder took R = 255 - stored C (= the ink) and so on, so
        # YCbCr → RGB gives the C, M, Y ink directly; K is stored inverted
        cb = m - 128
        cr = ye - 128
        r = c + ((91881 * cr + 32768) >> 16)
        g = c + ((-22554 * cb - 46802 * cr + 32768) >> 16)
        b = c + ((116130 * cb + 32768) >> 16)
        r = 0 if r < 0
        r = 255 if r > 255
        g = 0 if g < 0
        g = 255 if g > 255
        b = 0 if b < 0
        b = 255 if b > 255
        c = r
        m = g
        ye = b
        k = 255 - k
      elsif mode == 3
        c = 255 - c
        m = 255 - m
        ye = 255 - ye
        k = 255 - k
      out[o] = c
      out[o + 1] = m
      out[o + 2] = ye
      out[o + 3] = k
      o += 4
      x += 1
    y += 1
  0

# Ink → RGB without a profile: R = (1 - C)(1 - K), the formula browsers use.
-> jpeg_ink_rgb(ink, out, n) (u8[] u8[] i64) i64
  i = 0 ## i64
  o = 0 ## i64
  while i < n
    kk = 255 - ink[o + 3]
    out[o] = ((255 - ink[o]) * kk + 127) / 255
    out[o + 1] = ((255 - ink[o + 1]) * kk + 127) / 255
    out[o + 2] = ((255 - ink[o + 2]) * kk + 127) / 255
    out[o + 3] = 255
    o += 4
    i += 1
  0

# ---------------------------------------------------------------------------
# Arithmetic decoding (T.81 Annex D/F/G; after libjpeg's jdarith.c)
# ---------------------------------------------------------------------------

# Probability state machine (T.81 Table D.2, libjpeg jaricom.c packing):
# Qe << 16 | Next_Index_MPS << 8 | Switch_MPS << 7 | Next_Index_LPS. Entry 113 is
# the fixed 0.5 estimate used for signs and DC refinement.
JPEG_ARITAB = [1511850369, 629539342, 286524176, 134939666, 64488724, 31065623, 15009561, 7276572, 3541278, 1706529, 854819, 396297,
  199946, 68876, 1518276495, 1059393572, 754061606, 545002023, 398005032, 293737514, 216995115, 161551917, 120526638,
  89921584, 67508529, 50534963, 37755700, 28384310, 21241144, 16064057, 12001083, 9052220, 6824254, 5120575, 3875616,
  2885921, 1524704677, 1212950080, 973940545, 787556419, 639576388, 523446853, 430451526, 353905736, 293023049,
  242495050, 201011019, 167260237, 140587342, 117846607, 97334064, 81671218, 68105522, 56833587, 47462196, 39598133,
  33044790, 27540023, 23083832, 19217465, 16137530, 13319739, 11222845, 9379901, 1527923137, 1292124752, 1093419857,
  936920146, 803751251, 691816020, 595150678, 517949527, 447301975, 391006792, 337922888, 295455818, 258690378,
  223432267, 196497229, 171978829, 1479692752, 1293701720, 1133400921, 1004360794, 888034651, 783177308, 697980765,
  622217046, 1433426392, 1286167135, 1155095392, 1042439265, 941907299, 850681443, 773281373, 1453875423, 1330012517,
  1206215270, 1104110439, 1010656360, 928931171, 1378969193, 1276077930, 1178167403, 1096704871, 1445423849, 1357343596,
  1267033965, 1435987310, 1347382127, 1511026670, 1428319600, 1508601840, 1511879025]

JPEG_ARI_STATE = [nil]

-> jpeg_aritab
  if JPEG_ARI_STATE[0] == nil
    t = i64[114]
    k = 0
    while k < 114
      t[k] = JPEG_ARITAB[k]
      k += 1
    JPEG_ARI_STATE[0] = t
  JPEG_ARI_STATE[0]

# Decoder state ar i64[8]: 0 C, 1 A, 2 CT, 3 position, 4 marker reached, 5 spectral
# overflow (skip the rest of the scan). Statistics: one u8[] — DC bins (64 per
# table) at t*64, AC bins (256 per table) at 256 + t*256, the fixed bin at 1280.
+ JpegArith
  -> new(@cond)

  -> run(d, st, co, ci, sc)
    stats = u8[1284]
    ar = i64[8]
    ar[3] = st[0]
    jpeg_ari_reset(ar, stats)
    jpeg_ari_scan(d, ar, co, ci, sc, stats, @cond, jpeg_zz(), jpeg_aritab())
    st[0] = ar[3]
    nil

-> jpeg_ari_reset(ar, stats) (i64[] u8[]) i64
  ar[0] = 0
  ar[1] = 0
  ar[2] = -16
  ar[5] = 0
  k = 0 ## i64
  while k < 1280
    stats[k] = 0
    k += 1
  stats[1280] = 113
  0

# Next data byte (0 after a marker or the end), libjpeg get_byte + stuffing.
-> jpeg_ari_byte(d, ar) (u8[] i64[]) i64
  return 0 if ar[4] != 0
  pos = ar[3]
  n = d.size
  if pos >= n
    ar[4] = 1
    return 0
  b = d[pos]
  pos += 1
  if b == 0xFF
    while pos < n && d[pos] == 0xFF
      pos += 1
    if pos < n && d[pos] == 0
      pos += 1
    else
      ar[4] = 1
      ar[3] = pos - 1
      return 0
  ar[3] = pos
  b

-> jpeg_ari_decode(d, ar, stats, si, tab) (u8[] i64[] u8[] i64 i64[]) i64
  a = ar[1]
  c = ar[0]
  ct = ar[2]
  while a < 0x8000
    ct -= 1
    if ct < 0
      data = jpeg_ari_byte(d, ar)
      c = ((c << 8) | data) & 0xFFFFFFFFFF
      ct += 8
      if ct < 0
        ct += 1
        a = 0x8000 if ct == 0
    a = a << 1
  sv = stats[si]
  e = tab[sv & 0x7F]
  nl = e & 0xFF
  nm = (e >> 8) & 0xFF
  qe = e >> 16
  a -= qe
  temp = a << ct
  if c >= temp
    c -= temp
    if a < qe
      a = qe
      stats[si] = (sv & 0x80) ^ nm
    else
      a = qe
      stats[si] = (sv & 0x80) ^ nl
      sv = sv ^ 0x80
  elsif a < 0x8000
    if a < qe
      stats[si] = (sv & 0x80) ^ nl
      sv = sv ^ 0x80
    else
      stats[si] = (sv & 0x80) ^ nm
  ar[0] = c
  ar[1] = a
  ar[2] = ct
  sv >> 7

-> jpeg_ari_scan(d, ar, co, ci, sc, stats, cond, zz, tab) (u8[] i64[] i32[] i64[] i64[] u8[] i64[] i64[] i64[]) i64
  ns = sc[0]
  ss = sc[1]
  se = sc[2]
  ah = sc[3]
  al = sc[4]
  ri = sc[5]
  mode = 0 ## i64
  if sc[8] != 0
    if ss == 0
      mode = ah == 0 ? 1 : 2
    else
      mode = ah == 0 ? 3 : 4
  total = 0 ## i64
  nx = 0 ## i64
  if ns == 1
    c = sc[9]
    nx = ci[c * 16 + 7]
    total = nx * ci[c * 16 + 8]
  else
    nx = sc[6]
    total = nx * sc[7]
  m = 0 ## i64
  left = ri ## i64
  while m < total
    if ri > 0 && left == 0
      # restart: find RSTn, reset the coder and statistics
      n = d.size
      pos = ar[3]
      found = 0 ## i64
      while pos + 1 < n && found == 0
        if d[pos] == 0xFF && d[pos + 1] >= 0xD0 && d[pos + 1] <= 0xD7
          pos += 2
          found = 1
        elsif d[pos] == 0xFF && d[pos + 1] != 0 && d[pos + 1] != 0xFF
          found = 2
        else
          pos += 1
      return 0 if found != 1
      ar[3] = pos
      ar[4] = 0
      jpeg_ari_reset(ar, stats)
      c = 0 ## i64
      while c < 4
        ci[c * 16 + 9] = 0
        ci[c * 16 + 12] = 0
        c += 1
      left = ri
    my = m / nx
    mx = m - my * nx
    if ar[5] == 0
      if ns == 1
        c = sc[9]
        b = c * 16
        off = ci[b] + (my * ci[b + 1] + mx) * 64
        jpeg_ari_block(d, ar, co, off, ci, c, stats, cond, zz, tab, mode, ss, se, al)
      else
        k = 0 ## i64
        while k < ns
          c = sc[9 + k]
          b = c * 16
          hs = ci[b + 2]
          vs = ci[b + 3]
          v = 0 ## i64
          while v < vs
            u = 0 ## i64
            while u < hs
              off = ci[b] + ((my * vs + v) * ci[b + 1] + mx * hs + u) * 64
              jpeg_ari_block(d, ar, co, off, ci, c, stats, cond, zz, tab, mode, ss, se, al)
              u += 1
            v += 1
          k += 1
    left -= 1
    m += 1
    return 0 if ar[4] != 0 && ri == 0 && ar[5] != 0
  0

# DC difference (F.19-F.24) with statistics for table t; returns the difference.
-> jpeg_ari_dc(d, ar, ci, b, stats, cond, tab) (u8[] i64[] i64[] i64 u8[] i64[] i64[]) i64
  t = ci[b + 4]
  base = t * 64
  si = base + ci[b + 12]
  if jpeg_ari_decode(d, ar, stats, si, tab) == 0
    ci[b + 12] = 0
    return 0
  sign = jpeg_ari_decode(d, ar, stats, si + 1, tab)
  si = si + 2 + sign
  mg = jpeg_ari_decode(d, ar, stats, si, tab)
  if mg != 0
    si = base + 20
    while jpeg_ari_decode(d, ar, stats, si, tab) != 0
      mg = mg << 1
      if mg == 0x8000
        ar[5] = 1
        return 0
      si += 1
  lo = (1 << cond[t]) >> 1
  hi = (1 << cond[4 + t]) >> 1
  if mg < lo
    ci[b + 12] = 0
  elsif mg > hi
    ci[b + 12] = 12 + sign * 4
  else
    ci[b + 12] = 4 + sign * 4
  v = mg
  si += 14
  mg = mg >> 1
  while mg != 0
    v = v | mg if jpeg_ari_decode(d, ar, stats, si, tab) != 0
    mg = mg >> 1
  v += 1
  v = 0 - v if sign != 0
  v

# An AC magnitude and sign after the "nonzero" decision at bin si (F.21-F.24).
-> jpeg_ari_acval(d, ar, stats, si, t, k, cond, tab) (u8[] i64[] u8[] i64 i64 i64 i64[] i64[]) i64
  sign = jpeg_ari_decode(d, ar, stats, 1280, tab)
  si += 2
  mg = jpeg_ari_decode(d, ar, stats, si, tab)
  if mg != 0
    if jpeg_ari_decode(d, ar, stats, si, tab) != 0
      mg = mg << 1
      si = 256 + t * 256 + (k <= cond[8 + t] ? 189 : 217)
      while jpeg_ari_decode(d, ar, stats, si, tab) != 0
        mg = mg << 1
        if mg == 0x8000
          ar[5] = 1
          return 0
        si += 1
  v = mg
  si += 14
  mg = mg >> 1
  while mg != 0
    v = v | mg if jpeg_ari_decode(d, ar, stats, si, tab) != 0
    mg = mg >> 1
  v += 1
  v = 0 - v if sign != 0
  v

-> jpeg_ari_block(d, ar, co, off, ci, c, stats, cond, zz, tab, mode, ss, se, al) (u8[] i64[] i32[] i64 i64[] i64 u8[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  b = c * 16
  if mode == 0 || mode == 1
    diff = jpeg_ari_dc(d, ar, ci, b, stats, cond, tab)
    return 0 if ar[5] != 0
    pred = ci[b + 9] + diff
    ci[b + 9] = pred
    co[off] = mode == 0 ? pred : pred << al
    return 0 if mode == 1
    ss = 1
    se = 63
  if mode == 2
    co[off] = co[off] | (1 << al) if jpeg_ari_decode(d, ar, stats, 1280, tab) != 0
    return 0
  t = ci[b + 5]
  ab = 256 + t * 256
  if mode == 0 || mode == 3
    k = ss ## i64
    while k <= se
      si = ab + 3 * (k - 1)
      return 0 if jpeg_ari_decode(d, ar, stats, si, tab) != 0
      while jpeg_ari_decode(d, ar, stats, si + 1, tab) == 0
        si += 3
        k += 1
        if k > se
          ar[5] = 1
          return 0
      v = jpeg_ari_acval(d, ar, stats, si, t, k, cond, tab)
      return 0 if ar[5] != 0
      co[off + zz[k]] = mode == 0 ? v : v << al
      k += 1
    return 0
  # mode 4: AC refinement
  p1 = 1 << al
  m1 = 0 - p1
  kex = se ## i64
  while kex > 0 && co[off + zz[kex]] == 0
    kex -= 1
  k = ss ## i64
  while k <= se
    si = ab + 3 * (k - 1)
    if k > kex
      return 0 if jpeg_ari_decode(d, ar, stats, si, tab) != 0
    going = 1 ## i64
    while going == 1
      pz = off + zz[k]
      cf = co[pz]
      if cf != 0
        if jpeg_ari_decode(d, ar, stats, si + 2, tab) != 0
          co[pz] = cf < 0 ? cf + m1 : cf + p1
        going = 0
      elsif jpeg_ari_decode(d, ar, stats, si + 1, tab) != 0
        co[pz] = jpeg_ari_decode(d, ar, stats, 1280, tab) != 0 ? m1 : p1
        going = 0
      else
        si += 3
        k += 1
        if k > se
          ar[5] = 1
          return 0
    k += 1
  0
