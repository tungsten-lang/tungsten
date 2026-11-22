# core/codec/video/h264_cavlc — slice-data bit reading and CAVLC residual decoding
# (H.264 9.1 / 9.2). Methods of H264Dec; the slice RBSP is @sb with bit
# position @sp.

use h264_tables

# Fill a direct-lookup VLC table: lut[base + code << (nbits-len) ...] =
# (symbol << 5) | len, for symbols lens[off...off+n].
-> h264_vlc_fill(lens, bits, off, n, lut, base, nbits)
  s = 0
  while s < n
    l = lens[off + s]
    if l > 0
      c = bits[off + s] << (nbits - l)
      k = 0
      cnt = 1 << (nbits - l)
      while k < cnt
        lut[base + c + k] = (s << 5) | l
        k += 1
    s += 1
  0

-> h264_clz32(v) (i64) i64
  return 32 if v == 0
  n = 0 ## i64
  if (v & 0xFFFF0000) == 0
    n += 16
    v = v << 16
  if (v & 0xFF000000) == 0
    n += 8
    v = v << 8
  if (v & 0xF0000000) == 0
    n += 4
    v = v << 4
  if (v & 0xC0000000) == 0
    n += 2
    v = v << 2
  if (v & 0x80000000) == 0
    n += 1
  n

+ H264Dec
  -> cavlc_init
    @ct_lut = i32[4 * 65536]
    t = 0
    while t < 4
      h264_vlc_fill(H264_COEFF_TOKEN_LEN, H264_COEFF_TOKEN_BITS, t * 68, 68, @ct_lut, t * 65536, 16)
      t += 1
    @ctc_lut = i32[256]
    h264_vlc_fill(H264_CHROMA_DC_COEFF_TOKEN_LEN, H264_CHROMA_DC_COEFF_TOKEN_BITS, 0, 20, @ctc_lut, 0, 8)
    @ctc2_lut = i32[8192]
    h264_vlc_fill(H264_CHROMA422_DC_COEFF_TOKEN_LEN, H264_CHROMA422_DC_COEFF_TOKEN_BITS, 0, 36, @ctc2_lut, 0, 13)
    @tz_lut = i32[15 * 512]
    t = 0
    while t < 15
      h264_vlc_fill(H264_TOTAL_ZEROS_LEN, H264_TOTAL_ZEROS_BITS, t * 16, 16, @tz_lut, t * 512, 9)
      t += 1
    @tzc_lut = i32[3 * 8]
    t = 0
    while t < 3
      h264_vlc_fill(H264_CHROMA_DC_TOTAL_ZEROS_LEN, H264_CHROMA_DC_TOTAL_ZEROS_BITS, t * 4, 4, @tzc_lut, t * 8, 3)
      t += 1
    @tzc2_lut = i32[7 * 32]
    t = 0
    while t < 7
      h264_vlc_fill(H264_CHROMA422_DC_TOTAL_ZEROS_LEN, H264_CHROMA422_DC_TOTAL_ZEROS_BITS, t * 8, 8, @tzc2_lut, t * 32, 5)
      t += 1
    @rb_lut = i32[7 * 2048]
    t = 0
    while t < 7
      h264_vlc_fill(H264_RUN_LEN, H264_RUN_BITS, t * 16, 16, @rb_lut, t * 2048, 11)
      t += 1
    @i4cbp = i64[H264_GOLOMB_TO_INTRA4X4_CBP.size]
    h264_fill(@i4cbp, H264_GOLOMB_TO_INTRA4X4_CBP)
    @intercbp = i64[H264_GOLOMB_TO_INTER_CBP.size]
    h264_fill(@intercbp, H264_GOLOMB_TO_INTER_CBP)
    0

  # ------------------------------------------------------------ bit reading

  -> rb_peek(n) (i64) i64
    b = @sb
    p = @sp >> 3
    v = (b[p] << 48) | (b[p + 1] << 40) | (b[p + 2] << 32) | (b[p + 3] << 24) | (b[p + 4] << 16) | (b[p + 5] << 8) | b[p + 6]
    (v >> (56 - (@sp & 7) - n)) & ((1 << n) - 1)

  -> rb_u(n) (i64) i64
    return 0 if n == 0
    v = rb_peek(n)
    @sp = @sp + n
    v

  -> rb_ue (i64) i64
    v = rb_peek(32)
    lz = h264_clz32(v)
    if lz > 15
      @sp = @sp + lz + 1
      return (1 << lz) - 1 + rb_u(lz)
    @sp = @sp + 2 * lz + 1
    (v >> (31 - 2 * lz)) - 1

  -> rb_se (i64) i64
    k = rb_ue
    if (k & 1) == 1
      (k + 1) >> 1
    else
      0 - (k >> 1)

  -> rb_te(mx) (i64) i64
    if mx > 1
      rb_ue
    elsif mx == 1
      1 - rb_u(1)
    else
      0

  -> rb_more (i64) i64
    @sp < @sstop ? 1 : 0

  # --------------------------------------------------------- CAVLC residual

  # Decode one residual block; nc = predicted nC (-1 chroma DC 4:2:0, -2
  # chroma DC 4:2:2). Writes n (scan position, level) pairs to @cpos/@clev
  # and returns TotalCoeff.
  -> cavlc_block(nc, maxc) (i64 i64) i64
    sym = 0 ## i64
    if nc == -1
      v = @ctc_lut[rb_peek(8)]
      @sp = @sp + (v & 31)
      sym = v >> 5
    elsif nc == -2
      v = @ctc2_lut[rb_peek(13)]
      @sp = @sp + (v & 31)
      sym = v >> 5
    else
      t = 3 ## i64
      if nc < 2
        t = 0
      elsif nc < 4
        t = 1
      elsif nc < 8
        t = 2
      v = @ct_lut[t * 65536 + rb_peek(16)]
      @sp = @sp + (v & 31)
      sym = v >> 5
    total = sym >> 2
    t1 = sym & 3
    return 0 if total == 0
    lv = @dcb
    suffix_len = 0 ## i64
    suffix_len = 1 if total > 10 && t1 < 3
    i = 0 ## i64
    while i < total
      if i < t1
        lv[i] = 1 - 2 * rb_u(1)
      else
        pk = rb_peek(32)
        prefix = h264_clz32(pk)
        if prefix >= 32
          prefix = 0
          while rb_u(1) == 0
            prefix += 1
        else
          @sp = @sp + prefix + 1
        code = (prefix < 15 ? prefix : 15) << suffix_len
        size = suffix_len
        size = 4 if prefix == 14 && suffix_len == 0
        size = prefix - 3 if prefix >= 15
        code += rb_u(size) if size > 0
        code += 15 if prefix >= 15 && suffix_len == 0
        code += (1 << (prefix - 3)) - 4096 if prefix >= 16
        code += 2 if i == t1 && t1 < 3
        lev = 0 ## i64
        if (code & 1) == 0
          lev = (code + 2) >> 1
        else
          lev = (0 - code - 1) >> 1
        lv[i] = lev
        suffix_len = 1 if suffix_len == 0
        al = lev < 0 ? 0 - lev : lev
        suffix_len += 1 if al > (3 << (suffix_len - 1)) && suffix_len < 6
      i += 1
    zeros = 0 ## i64
    if total < maxc
      if nc == -1
        v = @tzc_lut[(total - 1) * 8 + rb_peek(3)]
        @sp = @sp + (v & 31)
        zeros = v >> 5
      elsif nc == -2
        v = @tzc2_lut[(total - 1) * 32 + rb_peek(5)]
        @sp = @sp + (v & 31)
        zeros = v >> 5
      else
        v = @tz_lut[(total - 1) * 512 + rb_peek(9)]
        @sp = @sp + (v & 31)
        zeros = v >> 5
    # runs: coefficient i (highest frequency first) sits at scan position
    pos = total + zeros - 1
    i = 0
    while i < total
      @cpos[i] = pos
      @clev[i] = lv[i]
      if i < total - 1
        run = 0 ## i64
        if zeros > 0
          zl = zeros < 7 ? zeros : 7
          v = @rb_lut[(zl - 1) * 2048 + rb_peek(11)]
          @sp = @sp + (v & 31)
          run = v >> 5
        zeros -= run
        pos = pos - 1 - run
      i += 1
    if @dbg == 1
      ss = "blk nc=[nc] maxc=[maxc] total=[total] t1=[t1]:"
      i = 0
      while i < total
        ss = ss + " [@cpos[i]]:[@clev[i]]"
        i += 1
      << ss
    total

  # nC for luma block at global 4x4 coords (gx, gy).
  -> nc_luma(gx, gy) (i64 i64) i64
    na = -1 ## i64
    nb = -1 ## i64
    if gx > 0 && avail_mb(mb_addr_of(gx - 1, gy)) == 1
      na = @nnz[gy * @w4 + gx - 1]
    if gy > 0 && avail_mb(mb_addr_of(gx, gy - 1)) == 1
      nb = @nnz[(gy - 1) * @w4 + gx]
    if na >= 0 && nb >= 0
      (na + nb + 1) >> 1
    elsif na >= 0
      na
    elsif nb >= 0
      nb
    else
      0

  -> nc_chroma(c, gx, gy) (i64 i64 i64) i64
    sx = @mbch == 16 ? 2 : 2
    na = -1 ## i64
    nb = -1 ## i64
    base = c * @cw4 * @ch4
    rows = @mbch / 4
    if gx > 0 && avail_mb((gy / rows) * @mbw + (gx - 1) / 2) == 1
      na = @nnzc[base + gy * @cw4 + gx - 1]
    if gy > 0 && avail_mb(((gy - 1) / rows) * @mbw + gx / 2) == 1
      nb = @nnzc[base + (gy - 1) * @cw4 + gx]
    if na >= 0 && nb >= 0
      (na + nb + 1) >> 1
    elsif na >= 0
      na
    elsif nb >= 0
      nb
    else
      0
