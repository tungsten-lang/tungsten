# core/codec/video/h264_cabac — CABAC arithmetic decoding engine and syntax elements
# (H.264 9.3). Methods of H264Dec. Engine state: @cr (codIRange), @cv (offset
# with @cc extra low bits pre-read), @cp (byte position in @sb). Context
# states in @ctx as (pStateIdx << 1) | valMPS.

use h264_tables

+ H264Dec
  -> cabac_init_tables
    @ctx = i32[1024]
    @lps = i64[H264_LPS.size]
    h264_fill(@lps, H264_LPS)
    @tlps = i64[H264_TRANS_LPS.size]
    h264_fill(@tlps, H264_TRANS_LPS)
    @init_i = i64[H264_CABAC_INIT_I.size]
    h264_fill(@init_i, H264_CABAC_INIT_I)
    @init_pb = i64[H264_CABAC_INIT_PB.size]
    h264_fill(@init_pb, H264_CABAC_INIT_PB)
    @sig8f = i64[H264_SIG8_FRAME.size]
    h264_fill(@sig8f, H264_SIG8_FRAME)
    @last8 = i64[H264_LAST8.size]
    h264_fill(@last8, H264_LAST8)
    0

  # 9.3.1.1 context initialisation for the slice.
  -> cabac_init_slice(slice_qp, is_i, init_idc) (i64 i64 i64) i64
    qp = h264_clip3(0, 51, slice_qp)
    tab = is_i == 1 ? @init_i : @init_pb
    base = is_i == 1 ? 0 : init_idc * 2048
    i = 0 ## i64
    while i < 1024
      m = tab[base + i * 2]
      n = tab[base + i * 2 + 1]
      pre = h264_clip3(1, 126, ((m * qp) >> 4) + n)
      if pre <= 63
        @ctx[i] = (63 - pre) << 1
      else
        @ctx[i] = ((pre - 64) << 1) | 1
      i += 1
    0

  # 9.3.1.2 engine initialisation at byte position bp.
  -> cabac_start(bp) (i64) i64
    b = @sb
    @cp = bp + 2
    @cr = 510
    @cv = (b[bp] << 8) | b[bp + 1]
    @cc = 7
    0

  -> cabac_refill (i64) i64
    while @cc < 0
      @cv = (@cv << 8) | @sb[@cp]
      @cp = @cp + 1
      @cc = @cc + 8
    0

  -> dec(ci) (i64) i64
    s = @ctx[ci]
    st = s >> 1
    mps = s & 1
    r = @cr
    lps = @lps[(st << 2) | ((r >> 6) & 3)]
    r -= lps
    sc = r << @cc
    if @cv < sc
      # MPS
      @ctx[ci] = ((st < 62 ? st + 1 : 62) << 1) | mps
      if r < 256
        r = r << 1
        @cc = @cc - 1
        cabac_refill if @cc < 0
      @cr = r
      mps
    else
      @cv = @cv - sc
      bin = 1 - mps
      if st == 0
        mps = 1 - mps
      @ctx[ci] = (@tlps[st] << 1) | mps
      r = lps
      sh = 0 ## i64
      while r < 256
        r = r << 1
        sh += 1
      @cr = r
      @cc = @cc - sh
      cabac_refill if @cc < 0
      bin

  -> dec_bypass (i64) i64
    @cc = @cc - 1
    cabac_refill if @cc < 0
    sc = @cr << @cc
    if @cv >= sc
      @cv = @cv - sc
      1
    else
      0

  -> dec_term (i64) i64
    r = @cr - 2
    sc = r << @cc
    if @cv >= sc
      @cr = r
      1
    else
      if r < 256
        r = r << 1
        @cc = @cc - 1
        cabac_refill if @cc < 0
      @cr = r
      0

  # Byte position after a terminate bin of 1 (for I_PCM): the arithmetic
  # decoder has consumed up to the bit before the @cc+9 pre-read bits.
  -> cabac_pcm_pos (i64) i64
    # PCM samples start at the first byte boundary at or after the first bit
    # following the 9-bit codIOffset window (verified against the JM traces).
    p = @cp * 8 - @cc
    (p + 7) >> 3

  # ----------------------------------------------------- syntax elements

  -> cb_skip(ctxa, ctxb) (i64 i64) i64
    base = @stype == 1 ? 24 : 11
    dec(base + ctxa + ctxb)

  # I-slice style mb_type (also the intra suffix in P/B); returns 0..25.
  -> cb_mb_type_i(base, inc, is_suffix) (i64 i64 i64) i64
    b0 = 0 ## i64
    if is_suffix == 1
      b0 = dec(base)
    else
      b0 = dec(base + inc)
    return 0 if b0 == 0
    return 25 if dec_term == 1
    t = 1 ## i64
    if is_suffix == 1
      t += 12 * dec(base + 1)
      if dec(base + 2) == 1
        t += 4 + 4 * dec(base + 2)
      t += 2 * dec(base + 3)
      t += dec(base + 3)
    else
      t += 12 * dec(base + 3)
      if dec(base + 4) == 1
        t += 4 + 4 * dec(base + 5)
      t += 2 * dec(base + 6)
      t += dec(base + 7)
    t

  -> cb_mb_type_p (i64) i64
    if dec(14) == 0
      if dec(15) == 0
        return 3 * dec(16)
      else
        return 2 - dec(17)
    5 + cb_mb_type_i(17, 0, 1)

  -> cb_mb_type_b(inc) (i64) i64
    return 0 if dec(27 + inc) == 0
    return 1 + dec(27 + 5) if dec(27 + 3) == 0
    bits = dec(27 + 4) << 3
    bits = bits | (dec(27 + 5) << 2)
    bits = bits | (dec(27 + 5) << 1)
    bits = bits | dec(27 + 5)
    return bits + 3 if bits < 8
    return 23 + cb_mb_type_i(32, 0, 1) if bits == 13
    return 11 if bits == 14
    return 22 if bits == 15
    bits = (bits << 1) | dec(27 + 5)
    bits - 4

  -> cb_sub_p (i64) i64
    return 0 if dec(21) == 1
    return 1 if dec(22) == 0
    dec(23) == 1 ? 2 : 3

  -> cb_sub_b (i64) i64
    return 0 if dec(36) == 0
    return 1 + dec(39) if dec(37) == 0
    t = 3 ## i64
    if dec(38) == 1
      return 11 + dec(39) if dec(39) == 1
      t += 4
    t += 2 * dec(39)
    t += dec(39)
    t

  -> cb_ref(inc) (i64) i64
    v = 0 ## i64
    if dec(54 + inc) == 0
      return 0
    v = 1
    ci = 54 + 4
    while dec(ci) == 1
      v += 1
      ci = 54 + 5
      break if v > 32
    v

  # mvd component; comp 0 = x (ctx 40), 1 = y (47); sum = absMvdA + absMvdB.
  -> cb_mvd(comp, sum) (i64 i64) i64
    base = comp == 0 ? 40 : 47
    inc = 0 ## i64
    if sum > 32
      inc = 2
    elsif sum > 2
      inc = 1
    return 0 if dec(base + inc) == 0
    v = 1 ## i64
    ci = base + 3
    while v < 9 && dec(ci) == 1
      v += 1
      ci += 1 if ci < base + 6
    if v >= 9
      k = 3 ## i64
      while dec_bypass == 1
        v += 1 << k
        k += 1
        break if k > 30
      while k > 0
        k -= 1
        v += dec_bypass << k
    dec_bypass == 1 ? 0 - v : v

  -> cb_dqp (i64) i64
    inc = @last_dqp != 0 ? 1 : 0
    return 0 if dec(60 + inc) == 0
    k = 1 ## i64
    ci = 62
    while dec(ci) == 1
      k += 1
      ci = 63
      break if k > 104
    if (k & 1) == 1
      (k + 1) >> 1
    else
      0 - (k >> 1)

  -> cb_cpm(inc) (i64) i64
    return 0 if dec(64 + inc) == 0
    return 1 if dec(67) == 0
    return 2 if dec(67) == 0
    3

  -> cb_i4mode (i64) i64
    return -1 if dec(68) == 1
    v = dec(69)
    v = v | (dec(69) << 1)
    v | (dec(69) << 2)

  -> cb_t8(inc) (i64) i64
    dec(399 + inc)

  # Residual block (9.3.2.7 / 9.3.3.1.3). cat: ctxBlockCat 0..5. Returns the
  # number of nonzero coefficients written to @cpos/@clev (scan positions).
  -> cb_residual(cat, maxc, cbf_inc) (i64 i64 i64) i64
    if cat != 5
      cbf_base = 85
      cbf_base = 89 if cat == 1
      cbf_base = 93 if cat == 2
      cbf_base = 97 if cat == 3
      cbf_base = 101 if cat == 4
      return 0 if dec(cbf_base + cbf_inc) == 0
    sig = 105 ## i64
    last = 166 ## i64
    alv = 227 ## i64
    if cat == 1
      sig = 120
      last = 181
      alv = 237
    elsif cat == 2
      sig = 134
      last = 195
      alv = 247
    elsif cat == 3
      sig = 149
      last = 210
      alv = 257
    elsif cat == 4
      sig = 152
      last = 213
      alv = 266
    elsif cat == 5
      sig = 402
      last = 417
      alv = 426
    n = 0 ## i64
    i = 0 ## i64
    numc8 = @mbch == 16 ? 2 : 1
    while i < maxc - 1
      si = i
      li = i
      if cat == 3
        si = i / numc8
        si = 2 if si > 2
        li = si
      elsif cat == 5
        si = @sig8f[i]
        li = @last8[i]
      if dec(sig + si) == 1
        @cpos[n] = i
        n += 1
        if dec(last + li) == 1
          i = maxc
          break
      i += 1
    if i == maxc - 1
      @cpos[n] = maxc - 1
      n += 1
    # levels, highest frequency first
    eq1 = 0 ## i64
    gt1 = 0 ## i64
    k = n - 1
    while k >= 0
      inc = 0 ## i64
      if gt1 == 0
        inc = 1 + (eq1 < 3 ? eq1 : 3)
      v = 0 ## i64
      if dec(alv + inc) == 0
        v = 1
      else
        lim = cat == 3 ? 3 : 4
        inc2 = 5 + (gt1 < lim ? gt1 : lim)
        v = 2
        while v < 15 && dec(alv + inc2) == 1
          v += 1
        if v >= 15
          # Exp-Golomb k=0 suffix
          kk = 0 ## i64
          while dec_bypass == 1
            v += 1 << kk
            kk += 1
            break if kk > 30
          while kk > 0
            kk -= 1
            v += dec_bypass << kk
      if v == 1
        eq1 += 1
      else
        gt1 += 1
      @clev[k] = dec_bypass == 1 ? 0 - v : v
      k -= 1
    n
