# core/codec/video/vp8 — VP8 video decoder (RFC 6386), pure Tungsten.
#
# Registered as "vp08". Key and inter frames, segmentation, both loop filter
# types with per-segment / reference / mode deltas, B_PRED and 16x16 intra
# with libvpx's 127/129 frame-edge rules, nearest/near/new and split motion
# vectors, six-tap (version 0) and bilinear (versions 1-3) motion
# compensation, golden/altref management with sign bias, and probability
# persistence (refresh_entropy_probs).
#
# Shares the boolean decoder (vp8bd_*), the DCT token reader (vp8_coeffs),
# the coefficient tables and the loop filter (vp8_filter_frame) with the
# WebP lossy decoder in core/codec/image/webp_vp8.w; that code is libvpx-exact for key frames
# and is used here unchanged.

use core/codec/media
use core/codec/image
use vp8_core_tables
use vp8_core
use h264_intra
use vp8_tables

+ VP8VError < StandardError
  rw :message

  -> new(@message)

  -> to_s
    @message

+ VP8VFrame
  rw :y, :u, :v, :w, :h

  -> new(@y, @u, @v, @w, @h)

VP8V_SIXTAP = [0, 0, 128, 0, 0, 0, 0, -6, 123, 12, -1, 0, 2, -11, 108, 36, -8, 1, 0, -9, 93, 50, -6, 0,
  3, -16, 77, 77, -16, 3, 0, -6, 50, 93, -9, 0, 1, -8, 36, 108, -11, 2, 0, -1, 12, 123, -6, 0]
VP8V_PRED4_FROM16 = [2, 1, 0, 9]

-> vp8v_clip(v) (i64) i64
  if v < 0
    0
  elsif v > 255
    255
  else
    v

# Six-tap (bil 0) or bilinear (bil 1) prediction, eighth-sample (mx, my).
-> vp8v_mc(dst, d, ds, src, s, ss, w, h, mx, my, bil, flt, tmp) (u8[] i64 i64 u8[] i64 i64 i64 i64 i64 i64 i64 i64[] u8[]) i64
  y = 0 ## i64
  if mx == 0 && my == 0
    while y < h
      x = 0 ## i64
      while x < w
        dst[d + y * ds + x] = src[s + y * ss + x]
        x += 1
      y += 1
    return 0
  if bil == 1
    # two passes: horizontal into h+1 rows, then vertical
    r = 0 ## i64
    while r < h + 1
      x = 0 ## i64
      a = s + r * ss
      while x < w
        tmp[r * 32 + x] = (src[a + x] * (128 - mx * 16) + src[a + x + 1] * (mx * 16) + 64) >> 7
        x += 1
      r += 1
    while y < h
      x = 0 ## i64
      while x < w
        t = y * 32 + x
        dst[d + y * ds + x] = (tmp[t] * (128 - my * 16) + tmp[t + 32] * (my * 16) + 64) >> 7
        x += 1
      y += 1
    return 0
  fx = mx * 6
  fy = my * 6
  if my == 0
    while y < h
      x = 0 ## i64
      a = s + y * ss
      while x < w
        p = a + x
        dst[d + y * ds + x] = vp8v_clip((flt[fx] * src[p - 2] + flt[fx + 1] * src[p - 1] + flt[fx + 2] * src[p] + flt[fx + 3] * src[p + 1] + flt[fx + 4] * src[p + 2] + flt[fx + 5] * src[p + 3] + 64) >> 7)
        x += 1
      y += 1
    return 0
  if mx == 0
    while y < h
      x = 0 ## i64
      a = s + y * ss
      while x < w
        p = a + x
        dst[d + y * ds + x] = vp8v_clip((flt[fy] * src[p - 2 * ss] + flt[fy + 1] * src[p - ss] + flt[fy + 2] * src[p] + flt[fy + 3] * src[p + ss] + flt[fy + 4] * src[p + 2 * ss] + flt[fy + 5] * src[p + 3 * ss] + 64) >> 7)
        x += 1
      y += 1
    return 0
  r = 0 ## i64
  while r < h + 5
    x = 0 ## i64
    a = s + (r - 2) * ss
    while x < w
      p = a + x
      tmp[r * 32 + x] = vp8v_clip((flt[fx] * src[p - 2] + flt[fx + 1] * src[p - 1] + flt[fx + 2] * src[p] + flt[fx + 3] * src[p + 1] + flt[fx + 4] * src[p + 2] + flt[fx + 5] * src[p + 3] + 64) >> 7)
      x += 1
    r += 1
  while y < h
    x = 0 ## i64
    while x < w
      p = (y + 2) * 32 + x
      dst[d + y * ds + x] = vp8v_clip((flt[fy] * tmp[p - 64] + flt[fy + 1] * tmp[p - 32] + flt[fy + 2] * tmp[p] + flt[fy + 3] * tmp[p + 32] + flt[fy + 4] * tmp[p + 64] + flt[fy + 5] * tmp[p + 96] + 64) >> 7)
      x += 1
    y += 1
  0

# Clamped copy of a (w+5)x(h+5) window at (ix-2, iy-2) into emu (stride 32).
-> vp8v_emu(src, ss, sw, sh, ix, iy, w, h, emu) (u8[] i64 i64 i64 i64 i64 i64 i64 u8[]) i64
  y = 0 ## i64
  while y < h + 5
    sy = iy - 2 + y
    sy = 0 if sy < 0
    sy = sh - 1 if sy > sh - 1
    x = 0 ## i64
    while x < w + 5
      sx = ix - 2 + x
      sx = 0 if sx < 0
      sx = sw - 1 if sx > sw - 1
      emu[y * 32 + x] = src[sy * ss + sx]
      x += 1
    y += 1
  0

# 4x4 inverse DCT added to dst (any stride); co[ci...ci+16] raster; zeroes co.
-> vp8v_idct_add(dst, d, stride, co, ci, tmp) (u8[] i64 i64 i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    i0 = co[ci + i]
    i4 = co[ci + 4 + i]
    i8 = co[ci + 8 + i]
    i12 = co[ci + 12 + i]
    a = i0 + i8
    bb = i0 - i8
    c = ((i4 * 35468) >> 16) - (((i12 * 20091) >> 16) + i12)
    dd = (((i4 * 20091) >> 16) + i4) + ((i12 * 35468) >> 16)
    tmp[i * 4] = a + dd
    tmp[i * 4 + 1] = bb + c
    tmp[i * 4 + 2] = bb - c
    tmp[i * 4 + 3] = a - dd
    i += 1
  i = 0
  while i < 4
    dc = tmp[i] + 4
    a = dc + tmp[8 + i]
    bb = dc - tmp[8 + i]
    c = ((tmp[4 + i] * 35468) >> 16) - (((tmp[12 + i] * 20091) >> 16) + tmp[12 + i])
    dd = (((tmp[4 + i] * 20091) >> 16) + tmp[4 + i]) + ((tmp[12 + i] * 35468) >> 16)
    o = d + i * stride
    dst[o] = vp8v_clip(dst[o] + ((a + dd) >> 3))
    dst[o + 1] = vp8v_clip(dst[o + 1] + ((bb + c) >> 3))
    dst[o + 2] = vp8v_clip(dst[o + 2] + ((bb - c) >> 3))
    dst[o + 3] = vp8v_clip(dst[o + 3] + ((a - dd) >> 3))
    i += 1
  k = 0 ## i64
  while k < 16
    co[ci + k] = 0
    k += 1
  0

# 16x16 / 8x8 intra (mode 0 DC, 1 H, 2 V, 3 TM) with libvpx edge rules.
-> vp8v_pred_big(dst, d, s, n, mode, mbx, mby) (u8[] i64 i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  if mode == 0
    v = 128 ## i64
    sum = 0 ## i64
    k = 0 ## i64
    sh = n == 16 ? 4 : 3
    if mbx > 0 && mby > 0
      while k < n
        sum += dst[d - s + k] + dst[d + k * s - 1]
        k += 1
      v = (sum + n) >> (sh + 1)
    elsif mby > 0
      while k < n
        sum += dst[d - s + k]
        k += 1
      v = (sum + (n >> 1)) >> sh
    elsif mbx > 0
      while k < n
        sum += dst[d + k * s - 1]
        k += 1
      v = (sum + (n >> 1)) >> sh
    while y < n
      x = 0 ## i64
      while x < n
        dst[d + y * s + x] = v
        x += 1
      y += 1
    return 0
  while y < n
    lft = mbx > 0 ? dst[d + y * s - 1] : 129
    x = 0 ## i64
    while x < n
      top = mby > 0 ? dst[d - s + x] : 127
      v = 0 ## i64
      if mode == 1
        v = lft
      elsif mode == 2
        v = top
      else
        tl = 127 ## i64
        if mby > 0
          tl = mbx > 0 ? dst[d - s - 1] : 129
        v = vp8v_clip(top + lft - tl)
      dst[d + y * s + x] = v
      x += 1
    y += 1
  0

+ VP8VDec
  rw :frames_out

  -> new(cfg)
    @frames_out = 0
    @cur = nil
    @last = nil
    @golden = nil
    @altref = nil
    @mbw = 0
    @mbh = 0
    @out = []
    @tb = vp8_tables()
    @prob = i64[1056]
    @prob_save = i64[1056]
    @p16 = i64[4]
    @pc = i64[3]
    @mvc = i64[38]
    @segp = i64[3]
    @misc = i64[8]
    @misc_save = i64[8]
    @p16_save = i64[4]
    @pc_save = i64[3]
    @mvc_save = i64[38]
    @segp_save = i64[3]
    @seg_q = i64[4]
    @seg_lf = i64[4]
    @lf_ref = i64[4]
    @lf_mode = i64[8]
    @qm = i64[24]
    @br = i64[6]
    @parts = []
    @co = i64[400]
    @tmp = i64[16]
    @dcb = i64[16]
    @top4 = i64[8]
    @left4 = i64[4]
    @emu = u8[32 * 32]
    @mct = u8[32 * 32]
    @flt = i64[48]
    k = 0
    while k < 48
      @flt[k] = VP8V_SIXTAP[k]
      k += 1
    @t16i = vp8_arr(VP8V_PRED16X16_TREE_INTRA)
    @t16 = vp8_arr(VP8V_PRED16X16_TREE_INTER)
    @t4 = vp8_arr(VP8V_PRED4X4_TREE)
    @tc = vp8_arr(VP8V_PRED8X8C_TREE)
    @p16i = vp8_arr(VP8V_PRED16X16_PROB_INTRA)
    @pci = vp8_arr(VP8V_PRED8X8C_PROB_INTRA)
    @p4inter = vp8_arr(VP8V_PRED4X4_PROB_INTER)
    @p4intra = vp8_arr(VP8V_PRED4X4_PROB_INTRA)
    @modectx = vp8_arr(VP8V_MODE_CONTEXTS)
    @mbsplits = vp8_arr(VP8V_MBSPLITS)
    @mbfirst = vp8_arr(VP8V_MBFIRSTIDX)
    @splitcnt = vp8_arr(VP8V_MBSPLIT_COUNT)
    @splitprob = vp8_arr(VP8V_MBSPLIT_PROB)
    @submvp = vp8_arr(VP8V_SUBMV_PROB)
    @mvup = vp8_arr(VP8V_MV_UPDATE_PROB)
    @segmap = u8[1]
    @bmodes = i64[16]
    @nzb = i64[24]

  # ---------------------------------------------------------------- API

  -> decode(sample)
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    @pts = sample.pts
    @dur = sample.duration
    decode_frame(d, d.size)
    o = @out
    @out = []
    o

  -> flush
    []

  -> reset
    @last = nil
    @golden = nil
    @altref = nil

  -> emit(f)
    vf = VideoFrame.new(f.w, f.h, [f.y, f.u, f.v], [@mbw * 16, @mbw * 8, @mbw * 8], "420", 8, @pts)
    vf.duration = @dur
    vf.matrix = 6
    vf.primaries = 6
    vf.transfer = 6
    @out.push(vf)
    @frames_out += 1
    0

  -> bit(p) (i64) i64
    vp8bd_bit(@bd, @br, p)

  -> uint(n) (i64) i64
    vp8bd_value(@bd, @br, n)

  -> sint(n) (i64) i64
    return 0 if bit(128) == 0
    v = uint(n)
    bit(128) == 1 ? 0 - v : v

  -> tree(t, pr, po) (i64[] i64[] i64) i64
    i = 0 ## i64
    while true
      i = t[i * 2 + bit(pr[po + i])]
      break if i <= 0
    0 - i

  # --------------------------------------------------------------- header

  -> decode_frame(d, n)
    raise VP8VError.new("vp8: truncated frame") if n < 3
    tag = d[0] | (d[1] << 8) | (d[2] << 16)
    key = (tag & 1) == 0 ? 1 : 0
    @profile = (tag >> 1) & 7
    show = (tag >> 4) & 1
    psize = tag >> 5
    p = 3
    if key == 1
      raise VP8VError.new("vp8: bad start code") if d[3] != 0x9d || d[4] != 0x01 || d[5] != 0x2a
      w = (d[6] | (d[7] << 8)) & 0x3fff
      h = (d[8] | (d[9] << 8)) & 0x3fff
      p = 10
      set_size(w, h)
      reset_probs
    else
      raise VP8VError.new("vp8: inter frame without a key frame") if @last == nil
    raise VP8VError.new("vp8: bad partition size") if p + psize > n
    @bd = d
    vp8bd_init(d, @br, p, psize)
    if key == 1
      uint(1)
      uint(1)
    @seg_enabled = uint(1)
    @seg_update = 0
    if @seg_enabled == 1
      @seg_update = uint(1)
      if uint(1) == 1
        @seg_abs = uint(1)
        k = 0
        while k < 4
          @seg_q[k] = sint(7)
          k += 1
        k = 0
        while k < 4
          @seg_lf[k] = sint(6)
          k += 1
      if @seg_update == 1
        k = 0
        while k < 3
          @segp[k] = uint(1) == 1 ? uint(8) : 255
          k += 1
    @simple = uint(1)
    @level = uint(6)
    @sharp = uint(3)
    @lfd = uint(1)
    if @lfd == 1 && uint(1) == 1
      k = 0
      while k < 4
        if uint(1) == 1
          v = uint(6)
          v = 0 - v if uint(1) == 1
          @lf_ref[k] = v
        k += 1
      k = 4
      while k < 8
        if uint(1) == 1
          v = uint(6)
          v = 0 - v if uint(1) == 1
          @lf_mode[k] = v
        k += 1
    # token partitions
    np = 1 << uint(2)
    ps = p + psize
    rem = n - ps - 3 * (np - 1)
    raise VP8VError.new("vp8: bad partitions") if rem < 0
    pp = ps + 3 * (np - 1)
    @parts = []
    k = 0
    while k < np
      sz = rem
      if k < np - 1
        sz = d[ps + k * 3] | (d[ps + k * 3 + 1] << 8) | (d[ps + k * 3 + 2] << 16)
        raise VP8VError.new("vp8: bad partition size") if sz > rem
      s = i64[6]
      vp8bd_init(d, s, pp, sz)
      @parts.push(s)
      pp += sz
      rem -= sz
      k += 1
    # quantisers
    yac = uint(7)
    dq = [sint(4), sint(4), sint(4), sint(4), sint(4)]
    k = 0
    while k < 4
      b = yac
      if @seg_enabled == 1
        b = @seg_q[k]
        b += yac if @seg_abs == 0
      @qm[k * 6] = VP8_KDC[vp8_qclip(b + dq[0], 127)]
      @qm[k * 6 + 1] = VP8_KAC[vp8_qclip(b, 127)]
      @qm[k * 6 + 2] = VP8_KDC[vp8_qclip(b + dq[1], 127)] * 2
      y2ac = (VP8_KAC[vp8_qclip(b + dq[2], 127)] * 101581) >> 16
      @qm[k * 6 + 3] = y2ac < 8 ? 8 : y2ac
      uvdc = VP8_KDC[vp8_qclip(b + dq[3], 127)]
      @qm[k * 6 + 4] = uvdc > 132 ? 132 : uvdc
      @qm[k * 6 + 5] = VP8_KAC[vp8_qclip(b + dq[4], 127)]
      k += 1
    upd_golden = 0
    upd_alt = 0
    @upd_last = 1
    if key == 0
      ug = uint(1)
      ua = uint(1)
      upd_golden = ug == 1 ? 4 : uint(2)
      upd_alt = ua == 1 ? 4 : uint(2)
      @sign_golden = uint(1)
      @sign_alt = uint(1)
    else
      upd_golden = 4
      upd_alt = 4
      @sign_golden = 0
      @sign_alt = 0
    upd_probs = uint(1)
    if upd_probs == 0
      save_probs
    @upd_last = uint(1) if key == 0
    # coefficient probability updates
    up = VP8_COEFFS_UPDATE
    k = 0
    while k < 1056
      @prob[k] = uint(8) if bit(up[k]) == 1
      k += 1
    @skip_enabled = uint(1)
    @misc[0] = @skip_enabled == 1 ? uint(8) : 0
    if key == 0
      @misc[1] = uint(8)
      @misc[2] = uint(8)
      @misc[3] = uint(8)
      if uint(1) == 1
        k = 0
        while k < 4
          @p16[k] = uint(8)
          k += 1
      if uint(1) == 1
        k = 0
        while k < 3
          @pc[k] = uint(8)
          k += 1
      k = 0
      while k < 38
        if bit(@mvup[k]) == 1
          v = uint(7) << 1
          @mvc[k] = v == 0 ? 1 : v
        k += 1
    @key = key
    decode_mbs
    # references
    cur = @cur
    ng = @golden
    na = @altref
    ng = cur if upd_golden == 4
    ng = @last if upd_golden == 1
    ng = @altref if upd_golden == 2
    na = cur if upd_alt == 4
    na = @last if upd_alt == 1
    na = @golden if upd_alt == 2
    @golden = ng
    @altref = na
    @last = cur if @upd_last == 1
    restore_probs if upd_probs == 0
    if show == 1
      emit(cur)
    0

  -> set_size(w, h)
    mbw = (w + 15) >> 4
    mbh = (h + 15) >> 4
    if mbw != @mbw || mbh != @mbh
      @mbw = mbw
      @mbh = mbh
      @segmap = u8[mbw * mbh]
      n = (mbw + 2) * (mbh + 2)
      @mb_mode = i64[n]
      @mb_ref = i64[n]
      @mb_mv = i64[n * 2]
      @mb_part = i64[n]
      @mb_bmv = i64[n * 32]
      @top_nnz = i64[mbw * 9]
      @top_b = i64[mbw * 4]
      @fi = i64[mbw * mbh * 4]
    @w = w
    @h = h
    0

  -> reset_probs
    k = 0
    while k < 1056
      @prob[k] = VP8_COEFFS_PROBA0[k]
      k += 1
    k = 0
    while k < 4
      @p16[k] = VP8V_PRED16X16_PROB_INTER[k]
      @seg_q[k] = 0
      @seg_lf[k] = 0
      @lf_ref[k] = 0
      k += 1
    k = 0
    while k < 3
      @pc[k] = VP8V_PRED8X8C_PROB_INTER[k]
      @segp[k] = 255
      k += 1
    k = 0
    while k < 38
      @mvc[k] = VP8V_MV_DEFAULT_PROB[k]
      k += 1
    k = 0
    while k < 8
      @lf_mode[k] = 0
      k += 1
    @seg_abs = 0
    0

  -> save_probs
    vp8v_copy(@prob_save, @prob, 1056)
    vp8v_copy(@p16_save, @p16, 4)
    vp8v_copy(@pc_save, @pc, 3)
    vp8v_copy(@mvc_save, @mvc, 38)
    vp8v_copy(@segp_save, @segp, 3)
    0

  -> restore_probs
    vp8v_copy(@prob, @prob_save, 1056)
    vp8v_copy(@p16, @p16_save, 4)
    vp8v_copy(@pc, @pc_save, 3)
    vp8v_copy(@mvc, @mvc_save, 38)
    vp8v_copy(@segp, @segp_save, 3)
    0

  # ------------------------------------------------------------ macroblocks

  -> decode_mbs
    mbw = @mbw
    mbh = @mbh
    ys = mbw * 16
    uvs = mbw * 8
    cy = u8[ys * mbh * 16]
    cu = u8[uvs * mbh * 8]
    cv = u8[uvs * mbh * 8]
    @cur = VP8VFrame.new(cy, cu, cv, @w, @h)
    @cy = cy
    @cu = cu
    @cv = cv
    vp8v_zero(@mb_mode)
    vp8v_zero(@mb_ref)
    vp8v_zero(@mb_mv)
    vp8v_zero(@mb_part)
    vp8v_zero(@mb_bmv)
    vp8v_zero(@top_nnz)
    vp8v_set(@top_b, 2)
    ftype = @level == 0 ? 0 : (@simple == 1 ? 1 : 2)
    @ftype = ftype
    mby = 0
    while mby < mbh
      @tok = @parts[mby % @parts.size]
      @left_nnz = i64[9]
      @left_b = i64[4]
      vp8v_set(@left_b, 2)
      mbx = 0
      while mbx < mbw
        decode_mb(mbx, mby)
        mbx += 1
      mby += 1
    vp8_filter_frame(cy, cu, cv, mbw, mbh, @fi, ftype) if ftype > 0
    0

  -> decode_mb(mbx, mby)
    mbw = @mbw
    mi = (mby + 1) * (mbw + 2) + mbx + 1
    # segment
    seg = 0
    if @seg_update == 1
      b = bit(@segp[0])
      seg = bit(@segp[1 + b]) + 2 * b
      @segmap[mby * mbw + mbx] = seg
    elsif @seg_enabled == 1
      seg = @segmap[mby * mbw + mbx]
    skip = @skip_enabled == 1 ? bit(@misc[0]) : 0
    mode = 0
    ref = 0
    bm = @bmodes
    if @key == 1
      mode = tree(@t16i, @p16i, 0)
      if mode == 4
        k = 0
        while k < 16
          x = k & 3
          y = k >> 2
          a = @top_b[mbx * 4 + x]
          l = @left_b[y]
          v = tree(@t4, @p4intra, (a * 10 + l) * 9)
          bm[k] = v
          @top_b[mbx * 4 + x] = v
          @left_b[y] = v
          k += 1
      else
        v = VP8V_PRED4_FROM16[mode]
        k = 0
        while k < 4
          @top_b[mbx * 4 + k] = v
          @left_b[k] = v
          k += 1
      @cmode = tree(@tc, @pci, 0)
      @mb_part[mi] = 4
    elsif bit(@misc[1]) == 1
      if bit(@misc[2]) == 1
        ref = bit(@misc[3]) == 1 ? 3 : 2
      else
        ref = 1
      @mb_ref[mi] = ref
      mode = decode_mvs(mi, mbx, mby, ref)
    else
      mode = tree(@t16, @p16, 0)
      if mode == 4
        k = 0
        while k < 16
          bm[k] = tree(@t4, @p4inter, 0)
          k += 1
      @cmode = tree(@tc, @pc, 0)
      @mb_part[mi] = 4
      @mb_mv[mi * 2] = 0
      @mb_mv[mi * 2 + 1] = 0
      @mb_bmv[mi * 32] = 0
      @mb_bmv[mi * 32 + 1] = 0
    @mb_mode[mi] = mode
    # residual tokens
    co = @co
    has_y2 = mode != 4 && mode != 7
    nzy = 0 ## i64
    tn = mbx * 9
    if skip == 0
      skip = decode_tokens(seg, has_y2, tn)
    else
      k = 0
      while k < 8
        @top_nnz[tn + k] = 0
        @left_nnz[k] = 0
        k += 1
      if has_y2
        @top_nnz[tn + 8] = 0
        @left_nnz[8] = 0
    # reconstruction
    ys = mbw * 16
    uvs = mbw * 8
    yd = mby * 16 * ys + mbx * 16
    cd = mby * 8 * uvs + mbx * 8
    if ref == 0
      if mode == 4
        pred_b(mbx, mby, yd, ys, skip)
      else
        vp8v_pred_big(@cy, yd, ys, 16, mode, mbx, mby)
      vp8v_pred_big(@cu, cd, uvs, 8, @cmode, mbx, mby)
      vp8v_pred_big(@cv, cd, uvs, 8, @cmode, mbx, mby)
    else
      inter_pred(mi, mbx, mby, ref)
    if skip == 0
      if mode != 4
        k = 0
        while k < 16
          if @nzb[k] != 0
            vp8v_idct_add(@cy, yd + (k >> 2) * 4 * ys + (k & 3) * 4, ys, co, k * 16, @tmp)
          k += 1
      k = 0
      while k < 8
        pl = k < 4 ? @cu : @cv
        b = k & 3
        if @nzb[16 + k] != 0
          vp8v_idct_add(pl, cd + (b >> 1) * 4 * uvs + (b & 1) * 4, uvs, co, 256 + k * 16, @tmp)
        k += 1
    # loop filter strength
    if @ftype > 0
      lv = @level
      if @seg_enabled == 1
        lv = @seg_lf[seg]
        lv += @level if @seg_abs == 0
      if @lfd == 1
        lv += @lf_ref[ref]
        lv += @lf_mode[mode] if mode >= 4
      lv = 0 if lv < 0
      lv = 63 if lv > 63
      f = (mby * mbw + mbx) * 4
      if lv > 0
        il = lv
        if @sharp > 0
          il = il >> ((@sharp + 3) >> 2)
          il = 9 - @sharp if il > 9 - @sharp
        il = 1 if il < 1
        @fi[f] = 2 * lv + il
        @fi[f + 1] = il
        @fi[f + 2] = (skip == 0 || mode == 4 || mode == 7) ? 1 : 0
        hev = 0
        if @key == 1
          hev = lv >= 40 ? 2 : (lv >= 15 ? 1 : 0)
        else
          hev = lv >= 40 ? 3 : (lv >= 20 ? 2 : (lv >= 15 ? 1 : 0))
        @fi[f + 3] = hev
      else
        @fi[f] = 0
    0

  # Tokens for one MB into @co (Y blocks 0..15, U 16..19, V 20..23 at
  # k*16; Y2 handled in place). Returns 1 when nothing was coded.
  -> decode_tokens(seg, has_y2, tn)
    co = @co
    tok = @tok
    qo = seg * 6
    nzb = @nzb
    total = 0
    first = 0
    t = 3
    if has_y2
      dc = @dcb
      k = 0
      while k < 16
        dc[k] = 0
        k += 1
      c = @top_nnz[tn + 8] + @left_nnz[8]
      nz = vp8_coeffs(@bd, tok, @prob, 1, c, @qm[qo + 2], @qm[qo + 3], 0, dc, 0, @tb)
      f = nz > 0 ? 1 : 0
      @top_nnz[tn + 8] = f
      @left_nnz[8] = f
      total += nz
      if nz > 1
        vp8_wht(dc, co, 0, @tmp)
      else
        dc0 = (dc[0] + 3) >> 3
        k = 0
        while k < 16
          co[k * 16] = dc0
          k += 1
      first = 1
      t = 0
    y = 0
    while y < 4
      x = 0
      while x < 4
        k = y * 4 + x
        ctx = @left_nnz[y] + @top_nnz[tn + x]
        nz = vp8_coeffs(@bd, tok, @prob, t, ctx, @qm[qo], @qm[qo + 1], first, co, k * 16, @tb)
        f = nz > first ? 1 : 0
        @left_nnz[y] = f
        @top_nnz[tn + x] = f
        total += f
        nzb[k] = (f == 1 || co[k * 16] != 0) ? 1 : 0
        x += 1
      y += 1
    ch = 0
    while ch < 2
      y = 0
      while y < 2
        x = 0
        while x < 2
          k = 16 + ch * 4 + y * 2 + x
          ctx = @left_nnz[4 + ch * 2 + y] + @top_nnz[tn + 4 + ch * 2 + x]
          nz = vp8_coeffs(@bd, tok, @prob, 2, ctx, @qm[qo + 4], @qm[qo + 5], 0, co, k * 16, @tb)
          f = nz > 0 ? 1 : 0
          @left_nnz[4 + ch * 2 + y] = f
          @top_nnz[tn + 4 + ch * 2 + x] = f
          total += f
          nzb[k] = f
          x += 1
        y += 1
      ch += 1
    total == 0 ? 1 : 0

  # B_PRED: per 4x4 prediction + residual in raster order.
  -> pred_b(mbx, mby, yd, ys, skip)
    dst = @cy
    top = @top4
    left = @left4
    bm = @bmodes
    lastcol = mbx == @mbw - 1
    k = 0
    while k < 16
      x = k & 3
      y = k >> 2
      d = yd + y * 4 * ys + x * 4
      gy = mby * 4 + y
      gx = mbx * 4 + x
      # above (and above-right) samples
      j = 0
      while j < 4
        top[j] = gy == 0 ? 127 : dst[d - ys + j]
        j += 1
      if mby == 0 && (y == 0 || x == 3)
        j = 4
        while j < 8
          top[j] = 127
          j += 1
      elsif x == 3
        ar = yd - ys + 16
        j = 4
        while j < 8
          top[j] = lastcol ? dst[yd - ys + 15] : dst[ar + j - 4]
          j += 1
      else
        j = 4
        while j < 8
          top[j] = dst[d - ys + j]
          j += 1
      j = 0
      while j < 4
        left[j] = gx == 0 ? 129 : dst[d + j * ys - 1]
        j += 1
      tl = 0
      if gy == 0
        tl = 127
      elsif gx == 0
        tl = 129
      else
        tl = dst[d - ys - 1]
      m = bm[k]
      vp8v_pred4(dst, d, ys, m, top, left, tl)
      if skip == 0 && @nzb[k] != 0
        vp8v_idct_add(dst, d, ys, @co, k * 16, @tmp)
      k += 1
    0

  -> vp8v_pred4(dst, d, s, m, top, left, tl)
    if m == 0
      j = 0
      while j < 4
        a0 = j == 0 ? tl : top[j - 1]
        v = (a0 + 2 * top[j] + top[j + 1] + 2) >> 2
        y = 0
        while y < 4
          dst[d + y * s + j] = v
          y += 1
        j += 1
    elsif m == 1
      y = 0
      while y < 4
        a = y == 0 ? tl : left[y - 1]
        b = left[y]
        c = y == 3 ? left[3] : left[y + 1]
        v = (a + 2 * b + c + 2) >> 2
        x = 0
        while x < 4
          dst[d + y * s + x] = v
          x += 1
        y += 1
    elsif m == 2
      sum = 4
      j = 0
      while j < 4
        sum += top[j] + left[j]
        j += 1
      v = sum >> 3
      y = 0
      while y < 4
        x = 0
        while x < 4
          dst[d + y * s + x] = v
          x += 1
        y += 1
    elsif m == 9
      y = 0
      while y < 4
        x = 0
        while x < 4
          dst[d + y * s + x] = vp8v_clip(top[x] + left[y] - tl)
          x += 1
        y += 1
    elsif m == 7
      t = top
      vp8v_put(dst, d, s, 0, 0, (t[0] + t[1] + 1) >> 1)
      q = (t[1] + t[2] + 1) >> 1
      vp8v_put(dst, d, s, 1, 0, q)
      vp8v_put(dst, d, s, 0, 2, q)
      q = (t[2] + t[3] + 1) >> 1
      vp8v_put(dst, d, s, 2, 0, q)
      vp8v_put(dst, d, s, 1, 2, q)
      q = (t[3] + t[4] + 1) >> 1
      vp8v_put(dst, d, s, 3, 0, q)
      vp8v_put(dst, d, s, 2, 2, q)
      vp8v_put(dst, d, s, 0, 1, (t[0] + 2 * t[1] + t[2] + 2) >> 2)
      q = (t[1] + 2 * t[2] + t[3] + 2) >> 2
      vp8v_put(dst, d, s, 1, 1, q)
      vp8v_put(dst, d, s, 0, 3, q)
      q = (t[2] + 2 * t[3] + t[4] + 2) >> 2
      vp8v_put(dst, d, s, 2, 1, q)
      vp8v_put(dst, d, s, 1, 3, q)
      q = (t[3] + 2 * t[4] + t[5] + 2) >> 2
      vp8v_put(dst, d, s, 3, 1, q)
      vp8v_put(dst, d, s, 2, 3, q)
      vp8v_put(dst, d, s, 3, 2, (t[4] + 2 * t[5] + t[6] + 2) >> 2)
      vp8v_put(dst, d, s, 3, 3, (t[5] + 2 * t[6] + t[7] + 2) >> 2)
    else
      h264_pred_nxn(dst, d, s, 4, m, top, left, tl, 3)
    0

  -> vp8v_put(dst, d, s, x, y, v)
    dst[d + y * s + x] = v
    0

  # ------------------------------------------------------------- motion

  -> clamp_mvx(v, mbx)
    lo = -64 - 64 * mbx
    hi = ((@mbw - 1) << 6) + 64 - 64 * mbx
    v < lo ? lo : (v > hi ? hi : v)

  -> clamp_mvy(v, mby)
    lo = -64 - 64 * mby
    hi = ((@mbh - 1) << 6) + 64 - 64 * mby
    v < lo ? lo : (v > hi ? hi : v)

  -> read_mv_comp(po)
    p = @mvc
    x = 0
    if bit(p[po]) == 1
      i = 0
      while i < 3
        x += bit(p[po + 9 + i]) << i
        i += 1
      i = 9
      while i > 3
        x += bit(p[po + 9 + i]) << i
        i -= 1
      x += 8 if (x & 0xFFF0) == 0 || bit(p[po + 12]) == 1
    else
      ps = po + 2
      b = bit(p[ps])
      ps += 1 + 3 * b
      x += 4 * b
      b = bit(p[ps])
      ps += 1 + b
      x += 2 * b
      x += bit(p[ps])
    (x != 0 && bit(p[po + 1]) == 1) ? 0 - x : x

  -> sign_bias(r)
    return @sign_golden if r == 2
    return @sign_alt if r == 3
    0

  # Returns the MB mode (5 zero, 6 mv, 7 split) and fills mv/bmv.
  -> decode_mvs(mi, mbx, mby, ref)
    mbw = @mbw
    edges = [mi - (mbw + 2), mi - 1, mi - (mbw + 2) - 1]
    nmx = [0, 0, 0, 0]
    nmy = [0, 0, 0, 0]
    cnt = [0, 0, 0, 0]
    idx = 0
    cb = sign_bias(ref)
    n = 0
    while n < 3
      e = edges[n]
      er = @mb_ref[e]
      if er != 0
        mx = @mb_mv[e * 2]
        my = @mb_mv[e * 2 + 1]
        if mx != 0 || my != 0
          if cb != sign_bias(er)
            mx = 0 - mx
            my = 0 - my
          if n == 0 || mx != nmx[idx] || my != nmy[idx]
            idx += 1
            nmx[idx] = mx
            nmy[idx] = my
          cnt[idx] += n != 2 ? 2 : 1
        else
          cnt[0] += n != 2 ? 2 : 1
      n += 1
    mc = @modectx
    @mb_part[mi] = 4
    if bit(mc[cnt[0] * 4]) == 1
      if cnt[3] > 0 && nmx[1] == nmx[3] && nmy[1] == nmy[3]
        cnt[1] += 1
      if cnt[2] > cnt[1]
        t = cnt[1]
        cnt[1] = cnt[2]
        cnt[2] = t
        t = nmx[1]
        nmx[1] = nmx[2]
        nmx[2] = t
        t = nmy[1]
        nmy[1] = nmy[2]
        nmy[2] = t
      if bit(mc[cnt[1] * 4 + 1]) == 1
        if bit(mc[cnt[2] * 4 + 2]) == 1
          bi = cnt[1] >= cnt[0] ? 1 : 0
          mvx = clamp_mvx(nmx[bi], mbx)
          mvy = clamp_mvy(nmy[bi], mby)
          sc = (@mb_mode[edges[1]] == 7 ? 1 : 0) + (@mb_mode[edges[0]] == 7 ? 1 : 0)
          sc = sc * 2 + (@mb_mode[edges[2]] == 7 ? 1 : 0)
          if bit(mc[sc * 4 + 3]) == 1
            num = decode_split(mi, mvx, mvy)
            @mb_mv[mi * 2] = @mb_bmv[mi * 32 + (num - 1) * 2]
            @mb_mv[mi * 2 + 1] = @mb_bmv[mi * 32 + (num - 1) * 2 + 1]
            return 7
          mvy += read_mv_comp(0)
          mvx += read_mv_comp(19)
          set_mv(mi, mvx, mvy)
          return 6
        set_mv(mi, clamp_mvx(nmx[2], mbx), clamp_mvy(nmy[2], mby))
        return 6
      set_mv(mi, clamp_mvx(nmx[1], mbx), clamp_mvy(nmy[1], mby))
      return 6
    set_mv(mi, 0, 0)
    5

  -> set_mv(mi, x, y)
    @mb_mv[mi * 2] = x
    @mb_mv[mi * 2 + 1] = y
    @mb_bmv[mi * 32] = x
    @mb_bmv[mi * 32 + 1] = y
    0

  -> decode_split(mi, bmx, bmy)
    lm = mi - 1
    tm = mi - (@mbw + 2)
    part = 3
    if bit(@splitprob[0]) == 1
      if bit(@splitprob[1]) == 1
        part = bit(@splitprob[2])
      else
        part = 2
    num = @splitcnt[part]
    @mb_part[mi] = part
    lsplit = @mb_part[lm] * 16
    tsplit = @mb_part[tm] * 16
    csplit = part * 16
    n = 0
    while n < num
      k = @mbfirst[part * 16 + n]
      lx = 0
      ly = 0
      if (k & 3) == 0
        j = @mbsplits[lsplit + k + 3]
        lx = @mb_bmv[lm * 32 + j * 2]
        ly = @mb_bmv[lm * 32 + j * 2 + 1]
      else
        j = @mbsplits[csplit + k - 1]
        lx = @mb_bmv[mi * 32 + j * 2]
        ly = @mb_bmv[mi * 32 + j * 2 + 1]
      ax = 0
      ay = 0
      if k <= 3
        j = @mbsplits[tsplit + k + 12]
        ax = @mb_bmv[tm * 32 + j * 2]
        ay = @mb_bmv[tm * 32 + j * 2 + 1]
      else
        j = @mbsplits[csplit + k - 4]
        ax = @mb_bmv[mi * 32 + j * 2]
        ay = @mb_bmv[mi * 32 + j * 2 + 1]
      lnz = (lx != 0 || ly != 0) ? 1 : 0
      anz = (ax != 0 || ay != 0) ? 1 : 0
      sp = 0
      if lx == ax && ly == ay
        sp = 4 - lnz
      elsif anz == 0
        sp = 2
      else
        sp = 1 - lnz
      o = mi * 32 + n * 2
      if bit(@submvp[sp * 3]) == 1
        if bit(@submvp[sp * 3 + 1]) == 1
          if bit(@submvp[sp * 3 + 2]) == 1
            @mb_bmv[o + 1] = bmy + read_mv_comp(0)
            @mb_bmv[o] = bmx + read_mv_comp(19)
          else
            @mb_bmv[o] = 0
            @mb_bmv[o + 1] = 0
        else
          @mb_bmv[o] = ax
          @mb_bmv[o + 1] = ay
      else
        @mb_bmv[o] = lx
        @mb_bmv[o + 1] = ly
      n += 1
    num

  -> ref_frame(r)
    return @last if r == 1
    return @golden if r == 2
    @altref

  -> inter_pred(mi, mbx, mby, ref)
    rf = ref_frame(ref)
    rf = @last if rf == nil
    part = @mb_part[mi]
    x0 = mbx * 16
    y0 = mby * 16
    if part == 4
      mc_part(rf, x0, y0, 0, 0, 16, 16, @mb_mv[mi * 2], @mb_mv[mi * 2 + 1])
    elsif part == 0
      mc_part(rf, x0, y0, 0, 0, 16, 8, @mb_bmv[mi * 32], @mb_bmv[mi * 32 + 1])
      mc_part(rf, x0, y0, 0, 8, 16, 8, @mb_bmv[mi * 32 + 2], @mb_bmv[mi * 32 + 3])
    elsif part == 1
      mc_part(rf, x0, y0, 0, 0, 8, 16, @mb_bmv[mi * 32], @mb_bmv[mi * 32 + 1])
      mc_part(rf, x0, y0, 8, 0, 8, 16, @mb_bmv[mi * 32 + 2], @mb_bmv[mi * 32 + 3])
    elsif part == 2
      k = 0
      while k < 4
        mc_part(rf, x0, y0, (k & 1) * 8, (k >> 1) * 8, 8, 8, @mb_bmv[mi * 32 + k * 2], @mb_bmv[mi * 32 + k * 2 + 1])
        k += 1
    else
      k = 0
      while k < 16
        mc_luma(rf, x0 + (k & 3) * 4, y0 + (k >> 2) * 4, 4, 4, @mb_bmv[mi * 32 + k * 2], @mb_bmv[mi * 32 + k * 2 + 1])
        k += 1
      y = 0
      while y < 2
        x = 0
        while x < 2
          b = mi * 32
          i0 = (2 * y * 4 + 2 * x) * 2
          i1 = (2 * y * 4 + 2 * x + 1) * 2
          i2 = ((2 * y + 1) * 4 + 2 * x) * 2
          i3 = ((2 * y + 1) * 4 + 2 * x + 1) * 2
          ux = @mb_bmv[b + i0] + @mb_bmv[b + i1] + @mb_bmv[b + i2] + @mb_bmv[b + i3]
          uy = @mb_bmv[b + i0 + 1] + @mb_bmv[b + i1 + 1] + @mb_bmv[b + i2 + 1] + @mb_bmv[b + i3 + 1]
          ux = (ux + 2 + (ux < 0 ? -1 : 0)) >> 2
          uy = (uy + 2 + (uy < 0 ? -1 : 0)) >> 2
          if @profile == 3
            ux = ux & (0 - 8)
            uy = uy & (0 - 8)
          mc_chroma(rf, mbx * 8 + x * 4, mby * 8 + y * 4, 4, 4, ux, uy)
          x += 1
        y += 1
    0

  -> mc_part(rf, x0, y0, bx, by, w, h, mx, my)
    mc_luma(rf, x0 + bx, y0 + by, w, h, mx, my)
    ux = mx
    uy = my
    if @profile == 3
      ux = ux & (0 - 8)
      uy = uy & (0 - 8)
    mc_chroma(rf, (x0 + bx) >> 1, (y0 + by) >> 1, w >> 1, h >> 1, ux, uy)
    0

  -> mc_luma(rf, px, py, w, h, mvx, mvy)
    ys = @mbw * 16
    src = rf.y ## u8[]
    fx = (mvx * 2) & 7
    fy = (mvy * 2) & 7
    ix = px + (mvx >> 2)
    iy = py + (mvy >> 2)
    sw = @mbw * 16
    sh = @mbh * 16
    s = iy * ys + ix
    ss = ys
    if ix < 2 || iy < 2 || ix + w + 3 > sw || iy + h + 3 > sh
      vp8v_emu(src, ys, sw, sh, ix, iy, w, h, @emu)
      src = @emu
      s = 2 * 32 + 2
      ss = 32
    vp8v_mc(@cy, py * ys + px, ys, src, s, ss, w, h, fx, fy, @profile == 0 ? 0 : 1, @flt, @mct)
    0

  -> mc_chroma(rf, px, py, w, h, mvx, mvy)
    uvs = @mbw * 8
    fx = mvx & 7
    fy = mvy & 7
    ix = px + (mvx >> 3)
    iy = py + (mvy >> 3)
    sw = @mbw * 8
    sh = @mbh * 8
    pl = 0
    while pl < 2
      src = (pl == 0 ? rf.u : rf.v) ## u8[]
      s = iy * uvs + ix
      ss = uvs
      if ix < 2 || iy < 2 || ix + w + 3 > sw || iy + h + 3 > sh
        vp8v_emu(src, uvs, sw, sh, ix, iy, w, h, @emu)
        src = @emu
        s = 2 * 32 + 2
        ss = 32
      dst = (pl == 0 ? @cu : @cv) ## u8[]
      vp8v_mc(dst, py * uvs + px, uvs, src, s, ss, w, h, fx, fy, @profile == 0 ? 0 : 1, @flt, @mct)
      pl += 1
    0

-> vp8v_copy(dst, src, n)
  k = 0
  while k < n
    dst[k] = src[k]
    k += 1
  0

-> vp8v_zero(a) (i64[]) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = 0
    k += 1
  0

-> vp8v_set(a, v) (i64[] i64) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = v
    k += 1
  0

vcodec_register("vp08", ->(cfg) VP8VDec.new(cfg))
