# core/codec/video/theora — Theora video decoder (Theora I specification), pure Tungsten.
#
# Registered as "theo". cfg.extra holds the three header packets
# (identification, comment, setup) as an Array of byte arrays; samples are
# frame packets. Supports 4:2:0 / 4:2:2 / 4:4:4, intra and inter frames,
# golden frames, the custom and preset mode alphabets, both motion vector
# codings, per-block quantiser indices, the setup header's Huffman tables
# and quantisation matrices, DC prediction, the VP3 IDCT and loop filter.
#
# Frames are decoded in Theora's native orientation (row 0 at the bottom)
# and flipped/cropped to the picture region on output.

use core/codec/media

+ TheoraError < StandardError
  rw :message

  -> new(@message)

  -> to_s
    @message

THEO_HILBERT = [0, 0, 1, 0, 1, 1, 0, 1, 0, 2, 0, 3, 1, 3, 1, 2, 2, 2, 2, 3, 3, 3, 3, 2, 3, 1, 2, 1, 2, 0, 3, 0]
# Preset mode alphabets (modes: 0 INTER_NO_MV 1 INTRA 2 INTER_PLUS_MV
# 3 INTER_LAST_MV 4 INTER_PRIOR_LAST 5 USING_GOLDEN 6 GOLDEN_MV 7 FOURMV)
THEO_ALPHABETS = [3, 4, 2, 0, 1, 5, 6, 7,
  3, 4, 0, 2, 1, 5, 6, 7,
  3, 2, 4, 0, 1, 5, 6, 7,
  3, 2, 0, 4, 1, 5, 6, 7,
  0, 3, 4, 2, 1, 5, 6, 7,
  0, 5, 3, 4, 2, 1, 6, 7]
THEO_ZIGZAG = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
# motion vector VLC: (value + 31, length) in code order
THEO_MV_VLC = [31, 3, 32, 3, 30, 3, 33, 4, 29, 4, 34, 4, 28, 4, 35, 6, 27, 6, 36, 6, 26, 6, 37, 6, 25, 6, 38, 6, 24, 6, 39, 7,
  23, 7, 40, 7, 22, 7, 41, 7, 21, 7, 42, 7, 20, 7, 43, 7, 19, 7, 44, 7, 18, 7, 45, 7, 17, 7, 46, 7, 16, 7, 47, 8,
  15, 8, 48, 8, 14, 8, 49, 8, 13, 8, 50, 8, 12, 8, 51, 8, 11, 8, 52, 8, 10, 8, 53, 8, 9, 8, 54, 8, 8, 8, 55, 8,
  7, 8, 56, 8, 6, 8, 57, 8, 5, 8, 58, 8, 4, 8, 59, 8, 3, 8, 60, 8, 2, 8, 61, 8, 1, 8, 62, 8, 0, 8]
THEO_COMPAT = [1, 0, 1, 1, 1, 2, 2, 1, 3]
THEO_PRED = [0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 128, 0, 0, 0, 53, 75, 0, 128, 0, 0, 0, 64, 0, 64, 0, 128, 0, 0, 0, 0, 53, 75,
  128, 0, 0, 0, 0, 0, 0, 128, 64, 0, 64, 0, 0, 0, 53, 75, 0, 128, 0, 0, -104, 116, 0, 116, 24, 80, 24, 0, -104, 116, 0, 116]

-> theo_clip(v) (i64) i64
  if v < 0
    0
  elsif v > 255
    255
  else
    v

# VP3 integer IDCT of blk[0...64] (natural order, in place for the first
# pass); intra: put with +128, else add to dst.
-> theo_m(a, b) (i64 i64) i64
  (a * b) >> 16

-> theo_idct(dst, d, stride, blk, intra) (u8[] i64 i64 i16[] i64) i64
  r = 0 ## i64
  while r < 8
    o = r * 8
    i0 = blk[o] ## i64
    i1 = blk[o + 1] ## i64
    i2 = blk[o + 2] ## i64
    i3 = blk[o + 3] ## i64
    i4 = blk[o + 4] ## i64
    i5 = blk[o + 5] ## i64
    i6 = blk[o + 6] ## i64
    i7 = blk[o + 7] ## i64
    if (i0 | i1 | i2 | i3 | i4 | i5 | i6 | i7) != 0
      a = theo_m(64277, i1) + theo_m(12785, i7)
      b = theo_m(12785, i1) - theo_m(64277, i7)
      c = theo_m(54491, i3) + theo_m(36410, i5)
      dd = theo_m(54491, i5) - theo_m(36410, i3)
      ad = theo_m(46341, a - c)
      bd = theo_m(46341, b - dd)
      cd = a + c
      ddd = b + dd
      e = theo_m(46341, i0 + i4)
      f = theo_m(46341, i0 - i4)
      g = theo_m(60547, i2) + theo_m(25080, i6)
      h = theo_m(25080, i2) - theo_m(60547, i6)
      ed = e - g
      gd = e + g
      add = f + ad
      bdd = bd - h
      fd = f - ad
      hd = bd + h
      blk[o] = gd + cd
      blk[o + 7] = gd - cd
      blk[o + 1] = add + hd
      blk[o + 2] = add - hd
      blk[o + 3] = ed + ddd
      blk[o + 4] = ed - ddd
      blk[o + 5] = fd + bdd
      blk[o + 6] = fd - bdd
    r += 1
  c0 = 0 ## i64
  while c0 < 8
    i0 = blk[c0] ## i64
    i1 = blk[8 + c0] ## i64
    i2 = blk[16 + c0] ## i64
    i3 = blk[24 + c0] ## i64
    i4 = blk[32 + c0] ## i64
    i5 = blk[40 + c0] ## i64
    i6 = blk[48 + c0] ## i64
    i7 = blk[56 + c0] ## i64
    p = d + c0
    if (i1 | i2 | i3 | i4 | i5 | i6 | i7) != 0
      a = theo_m(64277, i1) + theo_m(12785, i7)
      b = theo_m(12785, i1) - theo_m(64277, i7)
      c = theo_m(54491, i3) + theo_m(36410, i5)
      dd = theo_m(54491, i5) - theo_m(36410, i3)
      ad = theo_m(46341, a - c)
      bd = theo_m(46341, b - dd)
      cd = a + c
      ddd = b + dd
      e = theo_m(46341, i0 + i4) + 8
      f = theo_m(46341, i0 - i4) + 8
      if intra == 1
        e += 16 * 128
        f += 16 * 128
      g = theo_m(60547, i2) + theo_m(25080, i6)
      h = theo_m(25080, i2) - theo_m(60547, i6)
      ed = e - g
      gd = e + g
      add = f + ad
      bdd = bd - h
      fd = f - ad
      hd = bd + h
      if intra == 1
        dst[p] = theo_clip((gd + cd) >> 4)
        dst[p + 7 * stride] = theo_clip((gd - cd) >> 4)
        dst[p + stride] = theo_clip((add + hd) >> 4)
        dst[p + 2 * stride] = theo_clip((add - hd) >> 4)
        dst[p + 3 * stride] = theo_clip((ed + ddd) >> 4)
        dst[p + 4 * stride] = theo_clip((ed - ddd) >> 4)
        dst[p + 5 * stride] = theo_clip((fd + bdd) >> 4)
        dst[p + 6 * stride] = theo_clip((fd - bdd) >> 4)
      else
        dst[p] = theo_clip(dst[p] + ((gd + cd) >> 4))
        dst[p + 7 * stride] = theo_clip(dst[p + 7 * stride] + ((gd - cd) >> 4))
        dst[p + stride] = theo_clip(dst[p + stride] + ((add + hd) >> 4))
        dst[p + 2 * stride] = theo_clip(dst[p + 2 * stride] + ((add - hd) >> 4))
        dst[p + 3 * stride] = theo_clip(dst[p + 3 * stride] + ((ed + ddd) >> 4))
        dst[p + 4 * stride] = theo_clip(dst[p + 4 * stride] + ((ed - ddd) >> 4))
        dst[p + 5 * stride] = theo_clip(dst[p + 5 * stride] + ((fd + bdd) >> 4))
        dst[p + 6 * stride] = theo_clip(dst[p + 6 * stride] + ((fd - bdd) >> 4))
    else
      v = (46341 * i0 + (8 << 16)) >> 20
      k = 0 ## i64
      if intra == 1
        while k < 8
          dst[p + k * stride] = theo_clip(128 + v)
          k += 1
      elsif i0 != 0
        while k < 8
          dst[p + k * stride] = theo_clip(dst[p + k * stride] + v)
          k += 1
    c0 += 1
  k = 0
  while k < 64
    blk[k] = 0
    k += 1
  0

-> theo_dc_add(dst, d, stride, blk) (u8[] i64 i64 i16[]) i64
  v = (blk[0] + 15) >> 5
  blk[0] = 0
  y = 0 ## i64
  while y < 8
    x = 0 ## i64
    while x < 8
      dst[d + y * stride + x] = theo_clip(dst[d + y * stride + x] + v)
      x += 1
    y += 1
  0

# Loop filter across one 8-sample edge; q0 at p, pixels across at step sb,
# lines at step sa.
-> theo_lf(pix, p, sa, sb, lim) (u8[] i64 i64 i64 i64) i64
  k = 0 ## i64
  while k < 8
    o = p + k * sa
    f = (pix[o - 2 * sb] - pix[o + sb]) + (pix[o] - pix[o - sb]) * 3
    f = (f + 4) >> 3
    af = f < 0 ? 0 - f : f
    v = 0 ## i64
    if af < lim
      v = f
    elsif af < 2 * lim
      v = f < 0 ? 0 - (2 * lim - af) : 2 * lim - af
    pix[o - sb] = theo_clip(pix[o - sb] + v)
    pix[o] = theo_clip(pix[o] - v)
    k += 1
  0

# 8x8 block prediction with optional half-sample offsets (no-rounding
# averages) from src at s (any stride; clamped copy done by the caller).
-> theo_mc(dst, d, ds, src, s, ss, hx, hy, dsign) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < 8
    x = 0 ## i64
    a = s + y * ss
    b = d + y * ds
    while x < 8
      v = 0 ## i64
      if hx == 0 && hy == 0
        v = src[a + x]
      elsif hy == 0
        v = (src[a + x] + src[a + x + 1]) >> 1
      elsif hx == 0
        v = (src[a + x] + src[a + x + ss]) >> 1
      elsif dsign == 0
        v = (src[a + x] + src[a + x + ss + 1]) >> 1
      else
        v = (src[a + x + 1] + src[a + x + ss]) >> 1
      dst[b + x] = v
      x += 1
    y += 1
  0

-> theo_emu(src, ss, sw, sh, ix, iy, emu) (u8[] i64 i64 i64 i64 i64 u8[]) i64
  y = 0 ## i64
  while y < 9
    sy = iy + y
    sy = 0 if sy < 0
    sy = sh - 1 if sy > sh - 1
    x = 0 ## i64
    while x < 9
      sx = ix + x
      sx = 0 if sx < 0
      sx = sw - 1 if sx > sw - 1
      emu[y * 16 + x] = src[sy * ss + sx]
      x += 1
    y += 1
  0

+ TheoraDec
  rw :frames_out

  -> new(cfg)
    @frames_out = 0
    @out = []
    @have_headers = false
    @golden = nil
    @last = nil
    @qps = i64[3]
    @last_qps = i64[3]
    @qps[0] = -1
    @last_qps[0] = -1
    @last_qps[1] = -1
    @last_qps[2] = -1
    @qmat = i64[3 * 2 * 3 * 64]
    @flim = i64[64]
    @acscale = i64[64]
    @dcscale = i64[64]
    @bm = i64[384 * 64]
    @qr_count = i64[6]
    @qr_size = i64[6 * 64]
    @qr_base = i64[6 * 64]
    @huff = i64[80 * 64 * 2]
    @blk = i16[64]
    @emu = u8[16 * 16]
    @zz = i64[64]
    @hil = i64[32]
    @mvvlc = i64[256]
    k = 0
    while k < 64
      @zz[k] = THEO_ZIGZAG[k]
      k += 1
    k = 0
    while k < 32
      @hil[k] = THEO_HILBERT[k]
      k += 1
    # MV VLC lookup over 8 bits: (value << 4) | length
    code = 0
    k = 0
    while k < 63
      sym = THEO_MV_VLC[k * 2]
      len = THEO_MV_VLC[k * 2 + 1]
      n = 1 << (8 - len)
      j = 0
      while j < n
        @mvvlc[code + j] = ((sym - 31 + 64) << 4) | len
        j += 1
      code += n
      k += 1
    if cfg != nil && cfg.extra != nil
      hs = cfg.extra
      if hs.is_a?(Array)
        hs.each ->(h)
          header(theo_bytes(h))
    @color_matrix = 6

  -> theo_bytes(h)
    if h.is_a?(String)
      return ccall("w_string_bytes_view", h) ## u8[]
    h

  # -------------------------------------------------------- bit reading

  -> bits(n) (i64) i64
    v = 0 ## i64
    k = 0 ## i64
    b = @bb
    while k < n
      by = @bp >> 3
      bit = 0 ## i64
      bit = (b[by] >> (7 - (@bp & 7))) & 1 if by < @blen
      v = (v << 1) | bit
      @bp = @bp + 1
      k += 1
    v

  -> peek8 (i64) i64
    p0 = @bp
    v = bits(8)
    @bp = p0
    v

  -> left (i64) i64
    @blen * 8 - @bp

  # ------------------------------------------------------------ headers

  -> header(h)
    @bb = h
    @bp = 0
    @blen = h.size
    t = bits(8)
    k = 0
    while k < 6
      bits(8)
      k += 1
    if t == 0x80
      vmaj = bits(8)
      vmin = bits(8)
      vrev = bits(8)
      @version = (vmaj << 16) | (vmin << 8) | vrev
      raise TheoraError.new("theora: unsupported bitstream version") if vmaj != 3 || vmin != 2
      @fmbw = bits(16)
      @fmbh = bits(16)
      @picw = bits(24)
      @pich = bits(24)
      @picx = bits(8)
      @picy = bits(8)
      bits(32)
      bits(32)
      bits(24)
      bits(24)
      cs = bits(8)
      bits(24)
      bits(6)
      bits(5)
      @pf = bits(2)
      raise TheoraError.new("theora: bad pixel format") if @pf == 1
      @color_matrix = 6
      @color_prim = cs == 1 ? 4 : (cs == 2 ? 5 : 2)
      setup_geometry
    elsif t == 0x82
      read_tables
      @have_headers = true
    0

  -> setup_geometry
    @w = @fmbw * 16
    @h = @fmbh * 16
    @cxs = @pf == 3 ? 0 : 1
    @cys = @pf == 0 ? 1 : 0
    @fw0 = @fmbw * 2
    @fh0 = @fmbh * 2
    @fw1 = @fw0 >> @cxs
    @fh1 = @fh0 >> @cys
    @fstart1 = @fw0 * @fh0
    @fstart2 = @fstart1 + @fw1 * @fh1
    @nfrag = @fstart2 + @fw1 * @fh1
    @sbw0 = (@fw0 + 3) >> 2
    @sbh0 = (@fh0 + 3) >> 2
    @sbw1 = (@fw1 + 3) >> 2
    @sbh1 = (@fh1 + 3) >> 2
    @sb1 = @sbw0 * @sbh0
    @sb2 = @sb1 + @sbw1 * @sbh1
    @nsb = @sb2 + @sbw1 * @sbh1
    @mbw = @fmbw
    @mbh = @fmbh
    @sbfrag = i64[@nsb * 16]
    j = 0
    pl = 0
    while pl < 3
      sw = pl == 0 ? @sbw0 : @sbw1
      sh = pl == 0 ? @sbh0 : @sbh1
      fw = pl == 0 ? @fw0 : @fw1
      fh = pl == 0 ? @fh0 : @fh1
      fs = pl == 0 ? 0 : (pl == 1 ? @fstart1 : @fstart2)
      sy = 0
      while sy < sh
        sx = 0
        while sx < sw
          i = 0
          while i < 16
            x = 4 * sx + @hil[i * 2]
            y = 4 * sy + @hil[i * 2 + 1]
            @sbfrag[j] = (x < fw && y < fh) ? fs + y * fw + x : -1
            j += 1
            i += 1
          sx += 1
        sy += 1
      pl += 1
    @mode = i64[@nfrag]
    @qpi = i64[@nfrag]
    @dc = i64[@nfrag]
    @last_zz = i64[@nfrag]
    @next_zz = i64[@nfrag]
    @coef = i16[@nfrag * 64]
    @mvx = i64[@nfrag]
    @mvy = i64[@nfrag]
    @coded = i64[@nfrag]
    @sbcode = i64[@nsb]
    @mbmode = i64[@mbw * @mbh]
    0

  -> read_tables
    n = bits(3)
    k = 0
    while k < 64
      @flim[k] = n > 0 ? bits(n) : 0
      k += 1
    n = bits(4) + 1
    k = 0
    while k < 64
      @acscale[k] = bits(n)
      k += 1
    n = bits(4) + 1
    k = 0
    while k < 64
      @dcscale[k] = bits(n)
      k += 1
    nm = bits(9) + 1
    @nmat = nm
    j = 0
    while j < nm
      k = 0
      while k < 64
        @bm[j * 64 + k] = bits(8)
        k += 1
      j += 1
    lb = 0
    while (1 << lb) < nm
      lb += 1
    # av_log2(matrices - 1) + 1 bits per base matrix index
    nbm = theo_ilog(nm - 1)
    nbm = 1 if nbm < 1
    inter = 0
    while inter < 2
      pl = 0
      while pl < 3
        q = inter * 3 + pl
        newqr = 1
        newqr = bits(1) if inter == 1 || pl > 0
        if newqr == 0
          src = 0
          if inter == 1 && bits(1) == 1
            src = pl
          else
            src = 3 * inter + pl - 1
          @qr_count[q] = @qr_count[src]
          k = 0
          while k < 64
            @qr_size[q * 64 + k] = @qr_size[src * 64 + k]
            @qr_base[q * 64 + k] = @qr_base[src * 64 + k]
            k += 1
        else
          qri = 0
          qi = 0
          while true
            i = bits(nbm)
            raise TheoraError.new("theora: bad base matrix index") if i >= nm
            @qr_base[q * 64 + qri] = i
            break if qi >= 63
            i = bits(theo_ilog(63 - qi)) + 1
            @qr_size[q * 64 + qri] = i
            qri += 1
            qi += i
          raise TheoraError.new("theora: bad quant ranges") if qi > 63
          @qr_count[q] = qri
        pl += 1
      inter += 1
    # Huffman trees: node arrays (64 nodes x 2 children); child >= 0 node,
    # child < 0: leaf token -(child+1)
    t = 0
    while t < 80
      @hn = 1
      @htab = t
      k = 0
      while k < 128
        @huff[t * 128 + k] = 0
        k += 1
      read_huff_node(0, 0)
      t += 1
    0

  -> read_huff_node(node, depth)
    raise TheoraError.new("theora: Huffman tree too deep") if depth > 32
    if bits(1) == 1
      return 0 - bits(5) - 1
    # internal node
    me = @hn
    @hn += 1
    raise TheoraError.new("theora: Huffman tree too large") if me >= 64
    l = read_huff_node(me, depth + 1)
    @huff[@htab * 128 + me * 2] = l
    r = read_huff_node(me, depth + 1)
    @huff[@htab * 128 + me * 2 + 1] = r
    if depth == 0
      # the root is node 0
      @huff[@htab * 128] = l
      @huff[@htab * 128 + 1] = r
    me

  -> huff_read(t) (i64) i64
    b = t * 128
    n = 0 ## i64
    while true
      c = @huff[b + n * 2 + bits(1)]
      return 0 - c - 1 if c < 0
      n = c
    0

  # ------------------------------------------------------------- decode

  -> decode(sample)
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    @pts = sample.pts
    @dur = sample.duration
    return [] if d.size == 0
    if (d[0] & 0x80) != 0
      header(d)
      return []
    raise TheoraError.new("theora: missing headers") if !@have_headers
    decode_frame(d)
    o = @out
    @out = []
    o

  -> flush
    []

  -> reset
    @last = nil
    @golden = nil

  -> decode_frame(d)
    @bb = d
    @bp = 0
    @blen = d.size
    bits(1)
    @key = 1 - bits(1)
    nq = 0
    while true
      @qps[nq] = bits(6)
      nq += 1
      break if nq >= 3 || bits(1) == 0
    @nqps = nq
    k = nq
    while k < 3
      @qps[k] = -1
      k += 1
    if @key == 1
      bits(3)
    raise TheoraError.new("theora: inter frame without a key frame") if @key == 0 && @last == nil
    k = 0
    while k < @nqps
      init_dequant(k) if @qps[k] != @last_qps[k] || @qps[0] != @last_qps[0]
      k += 1
    k = 0
    while k < 3
      @last_qps[k] = @qps[k]
      k += 1
    # allocate the frame
    ys = @w
    cs = @w >> @cxs
    ch = @h >> @cys
    cur_y = u8[ys * @h]
    cur_u = u8[cs * ch]
    cur_v = u8[cs * ch]
    @cy = cur_y
    @cu = cur_u
    @cv = cur_v
    vp_zero(@mode)
    vp_zero(@qpi)
    vp_zero(@dc)
    unpack_superblocks
    unpack_modes
    unpack_vectors
    unpack_qpis
    unpack_coeffs
    render
    lim = @flim[@qps[0]]
    loop_filter(lim) if lim > 0
    f = [cur_y, cur_u, cur_v]
    @golden = f if @key == 1
    @last = f
    emit(f)
    0

  -> init_dequant(qpi)
    q = @qps[qpi]
    acs = @acscale[q]
    inter = 0
    while inter < 2
      pl = 0
      while pl < 3
        dcs = @dcscale[q]
        qt = inter * 3 + pl
        sum = 0
        qri = 0
        while qri < @qr_count[qt]
          sum += @qr_size[qt * 64 + qri]
          break if q <= sum
          qri += 1
        qistart = sum - @qr_size[qt * 64 + qri]
        bmi = @qr_base[qt * 64 + qri]
        bmj = @qr_base[qt * 64 + qri + 1]
        sz = @qr_size[qt * 64 + qri]
        i = 0
        while i < 64
          coeff = (2 * (sum - q) * @bm[bmi * 64 + i] - 2 * (qistart - q) * @bm[bmj * 64 + i] + sz) / (2 * sz)
          qmin = 8 << (inter + (i == 0 ? 1 : 0))
          qscale = i == 0 ? dcs : acs
          v = ((qscale * coeff) / 100) * 4
          v = qmin if v < qmin
          v = 4096 if v > 4096
          @qmat[((qpi * 2 + inter) * 3 + pl) * 64 + i] = v
          i += 1
        pl += 1
      inter += 1
    # all DC coefficients use quantiser 0's DC
    if qpi > 0
      inter = 0
      while inter < 2
        pl = 0
        while pl < 3
          @qmat[((qpi * 2 + inter) * 3 + pl) * 64] = @qmat[((0 * 2 + inter) * 3 + pl) * 64]
          pl += 1
        inter += 1
    0

  # long run (superblock / qpi) VLC
  -> sb_run (i64) i64
    if bits(1) == 0
      return 1
    if bits(1) == 0
      return 2 + bits(1)
    if bits(1) == 0
      return 4 + bits(1)
    if bits(1) == 0
      return 6 + bits(2)
    if bits(1) == 0
      return 10 + bits(3)
    if bits(1) == 0
      return 18 + bits(4)
    34 + bits(12)

  -> frag_run (i64) i64
    if bits(1) == 0
      return 1 + bits(1)
    if bits(1) == 0
      return 3 + bits(1)
    if bits(1) == 0
      return 5 + bits(1)
    if bits(1) == 0
      return 7 + bits(2)
    if bits(1) == 0
      return 11 + bits(2)
    15 + bits(4)

  -> unpack_superblocks
    nsb = @nsb
    sbc = @sbcode
    if @key == 1
      k = 0
      while k < nsb
        sbc[k] = 2
        k += 1
    else
      # partially coded superblocks
      bit = bits(1) ^ 1
      run = 0
      cur = 0
      npart = 0
      while cur < nsb && left > 0
        if run == 4129
          bit = bits(1)
        else
          bit = bit ^ 1
        run = sb_run
        raise TheoraError.new("theora: bad superblock run") if run > nsb - cur
        k = 0
        while k < run
          sbc[cur + k] = bit
          k += 1
        cur += run
        npart += run if bit == 1
      if npart < nsb
        cur = 0
        bit = bits(1) ^ 1
        run = 0
        done = 0
        while done < nsb - npart && left > 0
          if run == 4129
            bit = bits(1)
          else
            bit = bit ^ 1
          run = sb_run
          j = 0
          while j < run
            raise TheoraError.new("theora: bad full superblock run") if cur >= nsb
            if sbc[cur] == 0
              sbc[cur] = 2 * bit
              j += 1
            cur += 1
          done += run
      if npart > 0
        @fbit = bits(1) ^ 1
        @frun = 0
    # coded fragment list in coded order (planes, superblocks, Hilbert order)
    @ncoded = 0
    @ncoded_pl = [0, 0, 0]
    @coded_list = i64[@nfrag] if @coded_list == nil || @coded_list.size != @nfrag
    cl = @coded_list ## i64[]
    run = @frun
    bit = @fbit
    pl = 0
    while pl < 3
      s0 = pl == 0 ? 0 : (pl == 1 ? @sb1 : @sb2)
      s1 = pl == 0 ? @sb1 : (pl == 1 ? @sb2 : nsb)
      n0 = @ncoded
      i = s0
      while i < s1
        j = 0
        while j < 16
          f = @sbfrag[i * 16 + j]
          if f >= 0
            c = sbc[i]
            if @key == 0 && c == 1
              if run == 0
                bit = bit ^ 1
                run = frag_run
              run -= 1
              c = bit
            if c != 0
              @mode[f] = @key == 1 ? 1 : 0
              cl[@ncoded] = f
              @ncoded += 1
            else
              @mode[f] = 8
          j += 1
        i += 1
      @ncoded_pl[pl] = @ncoded - n0
      pl += 1
    0

  -> unpack_modes
    return 0 if @key == 1
    scheme = bits(3)
    alpha = i64[8]
    if scheme == 0
      k = 0
      while k < 8
        alpha[bits(3)] = k
        k += 1
    elsif scheme < 7
      k = 0
      while k < 8
        alpha[k] = THEO_ALPHABETS[(scheme - 1) * 8 + k]
        k += 1
    sy = 0
    while sy < @sbh0
      sx = 0
      while sx < @sbw0
        j = 0
        while j < 4
          mbx = 2 * sx + (j >> 1)
          mby = 2 * sy + (((j >> 1) + j) & 1)
          if mbx < @mbw && mby < @mbh
            mb = mby * @mbw + mbx
            any = false
            k = 0
            while k < 4
              f = (2 * mby + (k >> 1)) * @fw0 + 2 * mbx + (k & 1)
              any = true if @mode[f] != 8
              k += 1
            if !any
              @mbmode[mb] = 0
            else
              m = 0
              if scheme == 7
                m = bits(3)
              else
                u = 0
                while u < 7 && bits(1) == 1
                  u += 1
                m = alpha[u]
              @mbmode[mb] = m
              k = 0
              while k < 4
                f = (2 * mby + (k >> 1)) * @fw0 + 2 * mbx + (k & 1)
                @mode[f] = m if @mode[f] != 8
                k += 1
              set_chroma_modes(mbx, mby, m)
          j += 1
        sx += 1
      sy += 1
    0

  -> set_chroma_modes(mbx, mby, m)
    if @cys == 1
      f = mby * @fw1 + mbx
      @mode[@fstart1 + f] = m if @mode[@fstart1 + f] != 8
      @mode[@fstart2 + f] = m if @mode[@fstart2 + f] != 8
    elsif @cxs == 1
      f = 2 * mby * @fw1 + mbx
      k = 0
      while k < 2
        @mode[@fstart1 + f] = m if @mode[@fstart1 + f] != 8
        @mode[@fstart2 + f] = m if @mode[@fstart2 + f] != 8
        f += @fw1
        k += 1
    else
      k = 0
      while k < 4
        f = (2 * mby + (k >> 1)) * @fw1 + 2 * mbx + (k & 1)
        @mode[@fstart1 + f] = m if @mode[@fstart1 + f] != 8
        @mode[@fstart2 + f] = m if @mode[@fstart2 + f] != 8
        k += 1
    0

  -> read_mv(cm) (i64) i64
    if cm == 0
      v = @mvvlc[peek8]
      @bp = @bp + (v & 15)
      return (v >> 4) - 64
    v = bits(6)
    if v < 2
      0
    elsif (v & 1) == 0
      v >> 1
    else
      0 - (v >> 1)

  -> unpack_vectors
    return 0 if @key == 1
    cm = bits(1)
    lx = 0
    ly = 0
    plx = 0
    ply = 0
    mx = i64[4]
    my = i64[4]
    sy = 0
    while sy < @sbh0
      sx = 0
      while sx < @sbw0
        j = 0
        while j < 4
          mbx = 2 * sx + (j >> 1)
          mby = 2 * sy + (((j >> 1) + j) & 1)
          if mbx < @mbw && mby < @mbh
            mb = mby * @mbw + mbx
            m = @mbmode[mb]
            any = false
            k = 0
            while k < 4
              f = (2 * mby + (k >> 1)) * @fw0 + 2 * mbx + (k & 1)
              any = true if @mode[f] != 8
              k += 1
            if any
              if m == 6 || m == 2
                mx[0] = read_mv(cm)
                my[0] = read_mv(cm)
                if m == 2
                  plx = lx
                  ply = ly
                  lx = mx[0]
                  ly = my[0]
              elsif m == 7
                plx = lx
                ply = ly
                k = 0
                while k < 4
                  f = (2 * mby + (k >> 1)) * @fw0 + 2 * mbx + (k & 1)
                  if @mode[f] != 8
                    mx[k] = read_mv(cm)
                    my[k] = read_mv(cm)
                    lx = mx[k]
                    ly = my[k]
                  else
                    mx[k] = 0
                    my[k] = 0
                  k += 1
              elsif m == 3
                mx[0] = lx
                my[0] = ly
              elsif m == 4
                mx[0] = plx
                my[0] = ply
                plx = lx
                ply = ly
                lx = mx[0]
                ly = my[0]
              else
                mx[0] = 0
                my[0] = 0
              k = 0
              while k < 4
                f = (2 * mby + (k >> 1)) * @fw0 + 2 * mbx + (k & 1)
                if m == 7
                  @mvx[f] = mx[k]
                  @mvy[f] = my[k]
                else
                  @mvx[f] = mx[0]
                  @mvy[f] = my[0]
                k += 1
              # chroma vectors
              if @cys == 1
                cx = mx[0]
                cy = my[0]
                if m == 7
                  cx = theo_rshift(mx[0] + mx[1] + mx[2] + mx[3], 2)
                  cy = theo_rshift(my[0] + my[1] + my[2] + my[3], 2)
                cx = (cx >> 1) | (cx & 1)
                cy = (cy >> 1) | (cy & 1)
                f = mby * @fw1 + mbx
                @mvx[@fstart1 + f] = cx
                @mvy[@fstart1 + f] = cy
                @mvx[@fstart2 + f] = cx
                @mvy[@fstart2 + f] = cy
              elsif @cxs == 1
                c0x = mx[0]
                c0y = my[0]
                c1x = mx[0]
                c1y = my[0]
                if m == 7
                  c0x = theo_rshift(mx[0] + mx[1], 1)
                  c0y = theo_rshift(my[0] + my[1], 1)
                  c1x = theo_rshift(mx[2] + mx[3], 1)
                  c1y = theo_rshift(my[2] + my[3], 1)
                c0x = (c0x >> 1) | (c0x & 1)
                c1x = (c1x >> 1) | (c1x & 1)
                f = 2 * mby * @fw1 + mbx
                @mvx[@fstart1 + f] = c0x
                @mvy[@fstart1 + f] = c0y
                @mvx[@fstart2 + f] = c0x
                @mvy[@fstart2 + f] = c0y
                f += @fw1
                @mvx[@fstart1 + f] = c1x
                @mvy[@fstart1 + f] = c1y
                @mvx[@fstart2 + f] = c1x
                @mvy[@fstart2 + f] = c1y
              else
                k = 0
                while k < 4
                  f = (2 * mby + (k >> 1)) * @fw1 + 2 * mbx + (k & 1)
                  vx = m == 7 ? mx[k] : mx[0]
                  vy = m == 7 ? my[k] : my[0]
                  @mvx[@fstart1 + f] = vx
                  @mvy[@fstart1 + f] = vy
                  @mvx[@fstart2 + f] = vx
                  @mvy[@fstart2 + f] = vy
                  k += 1
          j += 1
        sx += 1
      sy += 1
    0

  -> unpack_qpis
    nb = @ncoded
    cl = @coded_list
    qpi = 0
    while qpi < @nqps - 1 && nb > 0
      i = 0
      done = 0
      nat = 0
      bit = bits(1) ^ 1
      run = 0
      while done < nb && left > 0
        if run == 4129
          bit = bits(1)
        else
          bit = bit ^ 1
        run = sb_run
        done += run
        nat += run if bit == 0
        j = 0
        while j < run
          raise TheoraError.new("theora: bad qpi run") if i >= @ncoded
          f = cl[i]
          if @qpi[f] == qpi
            @qpi[f] += bit
            j += 1
          i += 1
      nb -= nat
      qpi += 1
    0

  # ------------------------------------------------------- coefficients

  -> unpack_coeffs
    cl = @coded_list ## i64[]
    co = @coef
    k = 0
    while k < @ncoded
      f = cl[k]
      b = f * 64
      j = 0
      while j < 64
        co[b + j] = 0
        j += 1
      @next_zz[f] = 0
      @last_zz[f] = 64
      k += 1
    dcy = bits(4)
    dcc = bits(4)
    eob = 0
    n0 = @ncoded_pl[0]
    n1 = @ncoded_pl[1]
    eob = coeff_pass(0, dcy, 0, n0, eob)
    dc_predict(0, @fw0, @fh0)
    eob = coeff_pass(0, dcc, n0, n0 + n1, eob)
    eob = coeff_pass(0, dcc, n0 + n1, @ncoded, eob)
    dc_predict(@fstart1, @fw1, @fh1)
    dc_predict(@fstart2, @fw1, @fh1)
    acy = bits(4)
    acc = bits(4)
    zi = 1
    while zi < 64
      grp = 16
      grp = 32 if zi >= 6
      grp = 48 if zi >= 15
      grp = 64 if zi >= 28
      eob = coeff_pass(zi, grp + acy, 0, n0, eob)
      eob = coeff_pass(zi, grp + acc, n0, n0 + n1, eob)
      eob = coeff_pass(zi, grp + acc, n0 + n1, @ncoded, eob)
      zi += 1
    0

  # Tokens for coefficient index zi over coded blocks [c0, c1) that still
  # need it. Returns the residual EOB run.
  -> coeff_pass(zi, tab, c0, c1, eob)
    cl = @coded_list ## i64[]
    co = @coef ## i16[]
    nz = @next_zz ## i64[]
    k = c0
    while k < c1
      f = cl[k]
      if nz[f] == zi
        if eob > 0
          eob -= 1
          @last_zz[f] = zi
          nz[f] = 64
        else
          t = huff_read(tab)
          if t <= 6
            if t <= 2
              eob = t + 1
            elsif t == 3
              eob = 4 + bits(2)
            elsif t == 4
              eob = 8 + bits(3)
            elsif t == 5
              eob = 16 + bits(4)
            else
              eob = bits(12)
              eob = 1 << 40 if eob == 0
            eob -= 1
            @last_zz[f] = zi
            nz[f] = 64
          else
            v = 0
            run = 0
            if t == 7
              run = bits(3)
            elsif t == 8
              run = bits(6)
            elsif t == 9
              v = 1
            elsif t == 10
              v = -1
            elsif t == 11
              v = 2
            elsif t == 12
              v = -2
            elsif t <= 16
              v = t - 10
              v = 0 - v if bits(1) == 1
            elsif t <= 22
              nb = t == 22 ? 10 : t - 15
              base = THEO_TOKBASE[t - 17]
              x = bits(nb)
              v = base + (x & ((1 << (nb - 1)) - 1))
              v = 0 - v if (x >> (nb - 1)) == 1
            elsif t <= 29
              v = bits(1) == 1 ? -1 : 1
              run = t <= 27 ? t - 22 : (t == 28 ? 6 + bits(2) : 10 + bits(3))
            else
              x = bits(2)
              v = 2 + (x & 1)
              v = 0 - v if (x >> 1) == 1
              run = t == 30 ? 1 : 2 + bits(1)
            p = zi + run
            p = 63 if p > 63
            co[f * 64 + p] = v
            if zi == 0
              @dc[f] = v if run == 0
            nz[f] = p + 1
            if nz[f] >= 64
              @last_zz[f] = 64
      k += 1
    eob

  -> dc_predict(fs, fw, fh)
    last = i64[3]
    i = fs
    y = 0
    while y < fh
      x = 0
      while x < fw
        m = @mode[i]
        if m != 8
          ft = THEO_COMPAT[m]
          tr = 0
          vl = 0
          vul = 0
          vu = 0
          vur = 0
          if x > 0
            vl = @dc[i - 1]
            tr = tr | 1 if THEO_COMPAT[@mode[i - 1]] == ft
          if y > 0
            u = i - fw
            vu = @dc[u]
            tr = tr | 4 if THEO_COMPAT[@mode[u]] == ft
            if x > 0
              vul = @dc[u - 1]
              tr = tr | 8 if THEO_COMPAT[@mode[u - 1]] == ft
            if x + 1 < fw
              vur = @dc[u + 1]
              tr = tr | 2 if THEO_COMPAT[@mode[u + 1]] == ft
          pd = 0
          if tr == 0
            pd = last[ft]
          else
            pd = THEO_PRED[tr * 4] * vul + THEO_PRED[tr * 4 + 1] * vu + THEO_PRED[tr * 4 + 2] * vur + THEO_PRED[tr * 4 + 3] * vl
            pd = pd / 128
            if tr == 15 || tr == 13
              if theo_abs(pd - vu) > 128
                pd = vu
              elsif theo_abs(pd - vl) > 128
                pd = vl
              elsif theo_abs(pd - vul) > 128
                pd = vul
          @dc[i] = theo_i16(@dc[i] + pd)
          last[ft] = @dc[i]
        i += 1
        x += 1
      y += 1
    0

  # ---------------------------------------------------------- rendering

  -> render
    pl = 0
    while pl < 3
      dst = pl == 0 ? @cy : (pl == 1 ? @cu : @cv)
      lst = @last == nil ? dst : @last[pl]
      gld = @golden == nil ? dst : @golden[pl]
      pw = pl == 0 ? @w : @w >> @cxs
      ph = pl == 0 ? @h : @h >> @cys
      fw = pl == 0 ? @fw0 : @fw1
      fh = pl == 0 ? @fh0 : @fh1
      fs = pl == 0 ? 0 : (pl == 1 ? @fstart1 : @fstart2)
      y = 0
      while y < fh
        x = 0
        while x < fw
          render_frag(fs + y * fw + x, dst, lst, gld, pw, ph, x, y, pl)
          x += 1
        y += 1
      pl += 1
    0

  -> render_frag(i, dst, lst, gld, pw, ph, x, y, pl) (i64 u8[] u8[] u8[] i64 i64 i64 i64 i64) i64
    m = @mode[i]
    fp = 8 * y * pw + 8 * x
    if m == 8
      k = 0 ## i64
      while k < 8
        j = 0 ## i64
        while j < 8
          dst[fp + k * pw + j] = lst[fp + k * pw + j]
          j += 1
        k += 1
      return 0
    blk = @blk
    inter = m == 1 ? 0 : 1
    if m != 1
      src = (m == 5 || m == 6) ? gld : lst
      s = fp
      ss = pw
      hx = 0 ## i64
      hy = 0 ## i64
      dsg = 0 ## i64
      if m != 0 && m != 5
        mvx = @mvx[i]
        mvy = @mvy[i]
        sx = (mvx >> 1) + 8 * x
        sy = (mvy >> 1) + 8 * y
        hx = mvx & 1
        hy = mvy & 1
        dsg = ((mvx ^ mvy) < 0) ? 1 : 0
        if sx < 0 || sy < 0 || sx + 9 >= pw || sy + 9 >= ph
          theo_emu(src, pw, pw, ph, sx, sy, @emu)
          src = @emu
          s = 0
          ss = 16
        else
          s = sy * pw + sx
      theo_mc(dst, fp, pw, src, s, ss, hx, hy, dsg)
    # coefficients
    qb = ((@qpi[i] * 2 + inter) * 3 + pl) * 64
    q0 = ((0 * 2 + inter) * 3 + pl) * 64
    co = @coef
    b = i * 64
    last = @last_zz[i]
    if last == 0 && inter == 1
      blk[0] = @dc[i] * @qmat[q0]
      theo_dc_add(dst, fp, pw, blk)
      return 0
    k = 1
    while k < 64
      v = co[b + k]
      if v != 0
        n = @zz[k]
        blk[n] = v * @qmat[qb + n]
      k += 1
    blk[0] = @dc[i] * @qmat[q0]
    theo_idct(dst, fp, pw, blk, inter == 1 ? 0 : 1)
    0

  -> loop_filter(lim)
    pl = 0
    while pl < 3
      dst = pl == 0 ? @cy : (pl == 1 ? @cu : @cv)
      pw = pl == 0 ? @w : @w >> @cxs
      fw = pl == 0 ? @fw0 : @fw1
      fh = pl == 0 ? @fh0 : @fh1
      fs = pl == 0 ? 0 : (pl == 1 ? @fstart1 : @fstart2)
      y = 0
      while y < fh
        x = 0
        while x < fw
          i = fs + y * fw + x
          if @mode[i] != 8
            p = 8 * y * pw + 8 * x
            theo_lf(dst, p, pw, 1, lim) if x > 0
            theo_lf(dst, p, 1, pw, lim) if y > 0
            theo_lf(dst, p + 8, pw, 1, lim) if x < fw - 1 && @mode[i + 1] == 8
            theo_lf(dst, p + 8 * pw, 1, pw, lim) if y < fh - 1 && @mode[i + fw] == 8
          x += 1
        y += 1
      pl += 1
    0

  -> emit(f)
    pw = @picw
    ph = @pich
    top = @h - ph - @picy
    cxs = @cxs
    cys = @cys
    planes = []
    strides = []
    pl = 0
    while pl < 3
      src = f[pl]
      sw = pl == 0 ? @w : @w >> cxs
      sh = pl == 0 ? @h : @h >> cys
      ox = pl == 0 ? @picx : @picx >> cxs
      oy = pl == 0 ? top : top >> cys
      ow = pl == 0 ? pw : (pw + cxs) >> cxs
      oh = pl == 0 ? ph : (ph + cys) >> cys
      o = u8[ow * oh]
      theo_flip_copy(o, ow, oh, src, sw, sh, ox, oy)
      planes.push(o)
      strides.push(ow)
      pl += 1
    chroma = @pf == 0 ? "420" : (@pf == 2 ? "422" : "444")
    vf = VideoFrame.new(pw, ph, planes, strides, chroma, 8, @pts)
    vf.duration = @dur
    vf.matrix = 6
    vf.primaries = @color_prim if @color_prim != nil
    @out.push(vf)
    @frames_out += 1
    0

-> theo_flip_copy(o, ow, oh, src, sw, sh, ox, oy) (u8[] i64 i64 u8[] i64 i64 i64 i64) i64
  r = 0 ## i64
  while r < oh
    sr = sh - 1 - (oy + r)
    x = 0 ## i64
    while x < ow
      o[r * ow + x] = src[sr * sw + ox + x]
      x += 1
    r += 1
  0

THEO_TOKBASE = [7, 9, 13, 21, 37, 69]

-> theo_ilog(v)
  n = 0
  while v > 0
    n += 1
    v = v >> 1
  n

-> theo_rshift(a, b)
  a >= 0 ? (a + (1 << (b - 1))) >> b : 0 - ((0 - a + (1 << (b - 1))) >> b)

-> theo_abs(v)
  v < 0 ? 0 - v : v

-> theo_i16(v)
  ((v + 32768) & 65535) - 32768

-> vp_zero(a) (i64[]) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = 0
    k += 1
  0

vcodec_register("theo", ->(cfg) TheoraDec.new(cfg))
