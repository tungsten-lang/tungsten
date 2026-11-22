# core/codec/video/av1_filter — AV1 in-loop post filters (spec 7.14 - 7.17): deblocking
# loop filter, CDEF, superres upscaling and loop restoration (Wiener and
# self-guided). post_filters runs them in the spec order on @cur and leaves the
# final (LrFrame) picture in @cur. Reopens Av1Decoder.

use av1_tables

-> av1_f_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_SUBSZ = av1_f_i32(AV1_SUBSAMPLED_SIZE)
AV1_CDEF_DIRS = av1_f_i32(AV1_CDEF_DIRECTIONS)
AV1_CDEF_UV_DIR = av1_f_i32(AV1_CDEF_UV_DIR)
AV1_DIV_TABLE = av1_f_i32(AV1_DIV_TABLE)
AV1_UPSCALE_FILTER = av1_f_i32(AV1_UPSCALE_FILTER)
AV1_SGR = av1_f_i32(AV1_SGR_PARAMS)

+ Av1Decoder
  -> post_filters
    if @loop_filter_level[0] != 0 || @loop_filter_level[1] != 0
      loop_filter_frame()
    cdef = @cur
    cdef_ran = false
    if @cdef_on && cdef_needed()
      cdef = cdef_frame()
      cdef_ran = true
    filtered = cdef_ran
    up_cur = @cur
    up_cdef = cdef
    if @use_superres == 1
      up_cdef = upscale_frame(cdef)
      up_cur = filtered ? upscale_frame(@cur) : up_cdef
    if @uses_lr
      @cur = lr_frame(up_cur, up_cdef)
    else
      @cur = up_cdef
    nil

  # ------------------------------------------------------------ deblocking

  -> loop_filter_frame
    p = i32[82]   # writes reach p[18 + s*8 + f*2 + 1] = 81
    p[0] = @loop_filter_level[0]
    p[1] = @loop_filter_level[1]
    p[2] = @loop_filter_level[2]
    p[3] = @loop_filter_level[3]
    p[4] = @loop_filter_sharpness
    p[5] = @loop_filter_delta_enabled
    i = 0
    while i < 8
      p[6 + i] = @loop_filter_ref_deltas[i]
      i += 1
    p[14] = @loop_filter_mode_deltas[0]
    p[15] = @loop_filter_mode_deltas[1]
    p[16] = @delta_lf_multi
    p[17] = @segmentation_enabled
    s = 0
    while s < 8
      f = 0
      while f < 4
        p[18 + s * 8 + f * 2] = @feature_enabled[s][1 + f]
        p[18 + s * 8 + f * 2 + 1] = @feature_data[s][1 + f]
        f += 1
      s += 1
    fr = @cur
    pl = 0
    while pl < @num_planes
      if pl == 0 || @loop_filter_level[1 + pl] != 0
        pass = 0
        while pass < 2
          sx = pl > 0 ? @ssx : 0
          sy = pl > 0 ? @ssy : 0
          av1_lf_plane(fr.planes[pl], fr.strides[pl], pl, pass, @mi_rows, @mi_cols, @mis, sx, sy, @frame_width, @frame_height,
                       @a_mi_sizes, @a_lf_tx[pl], @a_skips, @a_ref0, @a_y_modes, @a_seg_ids, @a_delta_lf, p, @bit_depth,
                       AV1_BW4, AV1_BH4, AV1_TXW, AV1_TXH, AV1_SUBSZ)
          pass += 1
      pl += 1
    nil

  # ------------------------------------------------------------ CDEF

  -> cdef_needed
    # all strengths zero: CDEF is the identity
    i = 0
    while i < @cdef_y_pri.size
      return true if @cdef_y_pri[i] != 0 || @cdef_y_sec[i] != 0 || @cdef_uv_pri[i] != 0 || @cdef_uv_sec[i] != 0
      i += 1
    false

  -> cdef_frame
    src = @cur
    dst = av1_frame_copy(src)
    yp = AV1_CDEF_DIRS
    r = 0
    while r < @mi_rows
      c = 0
      while c < @mi_cols
        idx = @a_cdef_idx[(r & (0 - 16)) * @mis + (c & (0 - 16))]
        if idx != -1
          cdef_block(src, dst, r, c, idx)
        c += 2
      r += 2
    dst

  -> cdef_block(src, dst, r, c, idx)
    mis = @mis
    k = r * mis + c
    skip = @a_skips[k] == 1 && @a_skips[k + mis] == 1 && @a_skips[k + 1] == 1 && @a_skips[k + mis + 1] == 1
    return nil if skip
    cs = @bit_depth - 8
    dv = av1_cdef_dir(src.planes[0], src.strides[0], c * 4, r * 4, @bit_depth, AV1_DIV_TABLE)
    ydir = dv >> 32
    var = dv & 0xFFFFFFFF
    pri = @cdef_y_pri[idx] << cs
    sec = @cdef_y_sec[idx] << cs
    dir = pri == 0 ? 0 : ydir
    vs = (var >> 6) != 0 ? av1_min(av1_floor_log2(var >> 6), 12) : 0
    pri = var != 0 ? (pri * (4 + vs) + 8) >> 4 : 0
    damping = @cdef_damping + cs
    av1_cdef_filter(src.planes[0], dst.planes[0], src.strides[0], c * 4, r * 4, 8, 8, 0, 0, pri, sec, damping, dir, cs, @mi_rows, @mi_cols, AV1_CDEF_DIRS)
    return nil if @num_planes == 1
    pri = @cdef_uv_pri[idx] << cs
    sec = @cdef_uv_sec[idx] << cs
    dir = pri == 0 ? 0 : AV1_CDEF_UV_DIR[(@ssx * 2 + @ssy) * 8 + ydir]
    damping = @cdef_damping + cs - 1
    p = 1
    while p < 3
      av1_cdef_filter(src.planes[p], dst.planes[p], src.strides[p], (c * 4) >> @ssx, (r * 4) >> @ssy, 8 >> @ssx, 8 >> @ssy, @ssx, @ssy, pri, sec, damping, dir, cs, @mi_rows, @mi_cols, AV1_CDEF_DIRS)
      p += 1
    nil

  # ------------------------------------------------------------ superres

  -> upscale_frame(src)
    al = 64
    aw = ((@upscaled_width + al - 1) / al) * al + 32
    out = Av1Frame.new(@upscaled_width, @frame_height, @bit_depth, @ssx, @ssy, @mono, aw, src.heights[0])
    av1_frame_meta(src, out)
    p = 0
    while p < @num_planes
      sx = p > 0 ? @ssx : 0
      sy = p > 0 ? @ssy : 0
      dw = av1_round2(@frame_width, sx)
      uw = av1_round2(@upscaled_width, sx)
      ph = av1_round2(@frame_height, sy)
      av1_upscale(src.planes[p], src.strides[p], out.planes[p], out.strides[p], dw, uw, ph, (@mi_cols >> sx) * 4 - 1, @bit_depth, AV1_UPSCALE_FILTER)
      p += 1
    out

  # ------------------------------------------------------------ loop restoration

  -> lr_frame(cur, cdef)
    out = av1_frame_copy(cdef)
    p = 0
    while p < @num_planes
      if @frame_restoration_type[p] != 0
        lr_plane(p, cur, cdef, out)
      p += 1
    out

  -> lr_plane(p, cur, cdef, out)
    sx = p == 0 ? 0 : @ssx
    sy = p == 0 ? 0 : @ssy
    us = @loop_restoration_size[p]
    urows = @lr_unit_rows[p]
    ucols = @lr_unit_cols[p]
    pex = av1_round2(@upscaled_width, sx) - 1
    pey = av1_round2(@frame_height, sy) - 1
    r0 = 3
    r1 = 11
    if @bit_depth == 12
      r0 = 5
      r1 = 9
    stride = out.strides[p]
    hf = i64[7]
    vf = i64[7]
    nstripes = (@frame_height + 8 + 63) / 64
    s = 0
    while s < nstripes
      ly0 = s * 64 - 8
      ly0 = 0 if ly0 < 0
      ly1 = s * 64 + 56
      ly1 = @frame_height if ly1 > @frame_height
      # luma rows are visited in steps of 4 starting from multiples of 4
      ly1 = ((ly1 + 3) / 4) * 4
      y0 = ly0 >> sy
      y1 = av1_min(ly1 >> sy, pey + 1)
      if y1 > y0
        ss = (-8 + s * 64) >> sy
        se = ss + (64 >> sy) - 1
        ur = av1_min(urows - 1, ((ly0 + 8) >> sy) / us)
        uc = 0
        while uc < ucols
          x0 = uc * us
          x1 = uc == ucols - 1 ? pex + 1 : (uc + 1) * us
          x1 = pex + 1 if x1 > pex + 1
          if x1 > x0
            k = ur * ucols + uc
            rt = @lr_type[p][k]
            if rt == 1
              wn = @lr_wiener[p]
              av1_wiener_coef(wn, k * 6, vf)
              av1_wiener_coef(wn, k * 6 + 3, hf)
              av1_wiener(out.planes[p], cdef.planes[p], cur.planes[p], stride, x0, y0, x1 - x0, y1 - y0, ss, se, pex, pey, hf, vf, @bit_depth, r0, r1)
            elsif rt == 2
              set = @lr_sgr_set[p][k]
              av1_sgr(out.planes[p], cdef.planes[p], cur.planes[p], stride, x0, y0, x1 - x0, y1 - y0, ss, se, pex, pey,
                      set, @lr_sgr_xqd[p][k * 2], @lr_sgr_xqd[p][k * 2 + 1], @bit_depth, AV1_SGR)
          uc += 1
      s += 1
    nil

-> av1_frame_meta(src, out)
  out.render_w = src.render_w
  out.render_h = src.render_h
  out.cp = src.cp
  out.tc = src.tc
  out.mc = src.mc
  out.full_range = src.full_range
  out.frame_type = src.frame_type
  nil

-> av1_frame_copy(src)
  out = Av1Frame.new(src.width, src.height, src.bit_depth, src.ssx, src.ssy, src.mono, src.strides[0], src.heights[0])
  av1_frame_meta(src, out)
  p = 0
  while p < src.planes.size
    av1_copy_u16(src.planes[p], out.planes[p], src.planes[p].size)
    p += 1
  out

-> av1_copy_u16(a, b, n) (u16[] u16[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = a[i]
    i += 1
  0

# ---------------------------------------------------------------- deblocking kernels

-> av1_lf_level(p, seg, rf, mode, dlf, plane, pass) (i32[] i64 i64 i64 i64 i64 i64) i64
  i = (plane == 0 ? pass : plane + 1) ## i64
  base = (dlf + p[i]) ## i64
  base = 0 if base < 0
  base = 63 if base > 63
  lvl = (base) ## i64
  if p[17] == 1 && p[18 + seg * 8 + i * 2] == 1
    lvl = lvl + p[18 + seg * 8 + i * 2 + 1]
    lvl = 0 if lvl < 0
    lvl = 63 if lvl > 63
  if p[5] == 1
    ns = (lvl >> 5) ## i64
    if rf == 0
      lvl = lvl + (p[6] << ns)
    else
      mt = ((mode >= 14 && mode != 16 && mode != 24) ? 1 : 0) ## i64
      lvl = lvl + (p[6 + rf] << ns) + (p[14 + mt] << ns)
    lvl = 0 if lvl < 0
    lvl = 63 if lvl > 63
  lvl

-> av1_lf_plane(pl, stride, plane, pass, mi_rows, mi_cols, mis, ssx, ssy, fw, fh, mi_sizes, lftx, skips, ref0, ymodes, segs, dlfs, p, bd, bw4, bh4, txw, txh, subsz) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 u8[] u8[] u8[] i32[] u8[] u8[] i32[] i32[] i64 i32[] i32[] i32[] i32[] i32[]) i64
  scratch = i64[64]
  rstep = 1 ## i64
  cstep = 1 ## i64
  if plane != 0
    rstep = 1 << ssy
    cstep = 1 << ssx
  dx = (pass == 0 ? 1 : 0) ## i64
  dy = (pass == 1 ? 1 : 0) ## i64
  sharp = p[4] ## i64
  shift = (sharp > 4 ? 2 : (sharp > 0 ? 1 : 0)) ## i64
  row = 0 ## i64
  while row < mi_rows
    col = 0 ## i64
    while col < mi_cols
      x = (col * 4) ## i64
      y = (row * 4) ## i64
      vis = 1 ## i64
      if x >= fw || y >= fh
        vis = 0
      elsif pass == 0 && x == 0
        vis = 0
      elsif pass == 1 && y == 0
        vis = 0
      if vis == 1
        r = (row | ssy) ## i64
        c = (col | ssx) ## i64
        xp = (x >> ssx) ## i64
        yp = (y >> ssy) ## i64
        pr = (r - (dy << ssy)) ## i64
        pc = (c - (dx << ssx)) ## i64
        k = (r * mis + c) ## i64
        ms = (mi_sizes[k]) ## i64
        txs = (lftx[(r >> ssy) * mis + (c >> ssx)]) ## i64
        psz = (subsz[ms * 4 + ssx * 2 + ssy]) ## i64
        skip = (skips[k]) ## i64
        intra = (ref0[k] <= 0 ? 1 : 0) ## i64
        ptxs = (lftx[(pr >> ssy) * mis + (pc >> ssx)]) ## i64
        blk_edge = 0 ## i64
        tx_edge = 0 ## i64
        if pass == 0
          blk_edge = 1 if (xp & (bw4[psz] * 4 - 1)) == 0
          tx_edge = 1 if (xp & (txw[txs] - 1)) == 0
        else
          blk_edge = 1 if (yp & (bh4[psz] * 4 - 1)) == 0
          tx_edge = 1 if (yp & (txh[txs] - 1)) == 0
        apply = 0 ## i64
        if tx_edge == 1 && (blk_edge == 1 || skip == 0 || intra == 1)
          apply = 1
        if apply == 1
          base_sz = 0 ## i64
          if pass == 0
            base_sz = txw[ptxs] < txw[txs] ? txw[ptxs] : txw[txs]
          else
            base_sz = txh[ptxs] < txh[txs] ? txh[ptxs] : txh[txs]
          fsz = (plane == 0 ? (base_sz < 16 ? base_sz : 16) : (base_sz < 8 ? base_sz : 8)) ## i64
          di = (plane == 0 ? pass : plane + 1) ## i64
          dlf = (p[16] == 1 ? dlfs[k * 4 + di] : dlfs[k * 4]) ## i64
          sg0 = segs[k] ## i64
          rf0 = ref0[k] ## i64
          ym0 = ymodes[k] ## i64
          lvl = av1_lf_level(p, sg0, rf0, ym0, dlf, plane, pass)
          if lvl == 0
            kp = (pr * mis + pc) ## i64
            dlf = p[16] == 1 ? dlfs[kp * 4 + di] : dlfs[kp * 4]
            sg0 = segs[kp] ## i64
            rf0 = ref0[kp] ## i64
            ym0 = ymodes[kp] ## i64
            lvl = av1_lf_level(p, sg0, rf0, ym0, dlf, plane, pass)
          if lvl > 0
            limit = 0 ## i64
            if sharp > 0
              limit = lvl >> shift
              limit = 9 - sharp if limit > 9 - sharp
              limit = 1 if limit < 1
            else
              limit = lvl >> shift
              limit = 1 if limit < 1
            blimit = (2 * (lvl + 2) + limit) ## i64
            thresh = (lvl >> 4) ## i64
            i = 0 ## i64
            while i < 4
              av1_lf_sample(pl, stride, xp + dy * i, yp + dx * i, plane, limit, blimit, thresh, dx, dy, fsz, bd, scratch)
              i += 1
      col += cstep
    row += rstep
  0

-> av1_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> av1_lf_sample(pl, stride, x, y, plane, limit, blimit, thresh, dx, dy, fsz, bd, scratch) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  st = (dy * stride + dx) ## i64
  o = (y * stride + x) ## i64
  q0 = pl[o] ## i64
  q1 = pl[o + st] ## i64
  p0 = pl[o - st] ## i64
  p1 = pl[o - 2 * st] ## i64
  sh = (bd - 8) ## i64
  hev = 0 ## i64
  tb = 0 ## i64
  tb = thresh << sh
  hev = 1 if av1_abs(p1 - p0) > tb || av1_abs(q1 - q0) > tb
  flen = 0 ## i64
  if fsz == 4
    flen = 4
  elsif plane != 0
    flen = 6
  elsif fsz == 8
    flen = 8
  else
    flen = 16
  lb = 0 ## i64
  lb = limit << sh
  bb = 0 ## i64
  bb = blimit << sh
  m = 0 ## i64
  m = 1 if av1_abs(p1 - p0) > lb || av1_abs(q1 - q0) > lb
  m = 1 if av1_abs(p0 - q0) * 2 + av1_abs(p1 - q1) / 2 > bb
  q2 = 0 ## i64
  p2 = 0 ## i64
  q3 = 0 ## i64
  p3 = 0 ## i64
  if flen >= 6
    q2 = pl[o + 2 * st] ## i64
    p2 = pl[o - 3 * st] ## i64
    m = 1 if av1_abs(p2 - p1) > lb || av1_abs(q2 - q1) > lb
  if flen >= 8
    q3 = pl[o + 3 * st] ## i64
    p3 = pl[o - 4 * st] ## i64
    m = 1 if av1_abs(p3 - p2) > lb || av1_abs(q3 - q2) > lb
  return 0 if m == 1
  one = 0 ## i64
  one = 1 << sh
  flat = 0 ## i64
  if fsz >= 8
    f = 0 ## i64
    f = 1 if av1_abs(p1 - p0) > one || av1_abs(q1 - q0) > one || av1_abs(p2 - p0) > one || av1_abs(q2 - q0) > one
    if flen >= 8
      f = 1 if av1_abs(p3 - p0) > one || av1_abs(q3 - q0) > one
    flat = f == 0 ? 1 : 0
  flat2 = 0 ## i64
  if fsz >= 16
    q4 = pl[o + 4 * st] ## i64
    q5 = pl[o + 5 * st] ## i64
    q6 = pl[o + 6 * st] ## i64
    p4 = pl[o - 5 * st] ## i64
    p5 = pl[o - 6 * st] ## i64
    p6 = pl[o - 7 * st] ## i64
    f = 0 ## i64
    f = 1 if av1_abs(p6 - p0) > one || av1_abs(q6 - q0) > one || av1_abs(p5 - p0) > one || av1_abs(q5 - q0) > one
    f = 1 if av1_abs(p4 - p0) > one || av1_abs(q4 - q0) > one
    flat2 = f == 0 ? 1 : 0
  if fsz == 4 || flat == 0
    # narrow filter
    lo = 0 ## i64
    lo = 0 - (1 << (bd - 1))
    hi = 0 ## i64
    hi = (1 << (bd - 1)) - 1
    off = 0 ## i64
    off = 128 << sh
    ps1 = (p1 - off) ## i64
    ps0 = (p0 - off) ## i64
    qs0 = (q0 - off) ## i64
    qs1 = (q1 - off) ## i64
    fl = 0 ## i64
    if hev == 1
      fl = av1_c3(lo, hi, ps1 - qs1)
    fl = av1_c3(lo, hi, fl + 3 * (qs0 - ps0))
    f1 = (av1_c3(lo, hi, fl + 4) >> 3) ## i64
    f2 = (av1_c3(lo, hi, fl + 3) >> 3) ## i64
    pl[o] = av1_c3(lo, hi, qs0 - f1) + off
    pl[o - st] = av1_c3(lo, hi, ps0 + f2) + off
    if hev == 0
      fl = (f1 + 1) >> 1
      pl[o + st] = av1_c3(lo, hi, qs1 - fl) + off
      pl[o - 2 * st] = av1_c3(lo, hi, ps1 + fl) + off
  elsif fsz == 8 || flat2 == 0
    av1_lf_wide(pl, o, st, 3, plane, scratch)
  else
    av1_lf_wide(pl, o, st, 4, plane, scratch)
  0

-> av1_c3(lo, hi, v) (i64 i64 i64) i64
  v < lo ? lo : (v > hi ? hi : v)

-> av1_lf_wide(pl, o, st, log2s, plane, src) (u16[] i64 i64 i64 i64 i64[]) i64
  n = 0 ## i64
  if log2s == 4
    n = 6
  elsif plane == 0
    n = 3
  else
    n = 2
  n2 = ((log2s == 3 && plane == 0) ? 0 : 1) ## i64
  # src[k + 16] for k = -(2n+1)..2n, edges replicated (the spec clamps)
  k = (0 - (n + 1)) ## i64
  while k <= n
    src[k + 16] = pl[o + k * st]
    k += 1
  lo = (src[16 - n - 1]) ## i64
  hi = (src[16 + n]) ## i64
  k = 0 - (2 * n + 1)
  while k < 0 - (n + 1)
    src[k + 16] = lo
    k += 1
  k = n + 1
  while k <= 2 * n
    src[k + 16] = hi
    k += 1
  rnd = 0 ## i64
  rnd = (1 << log2s) >> 1
  sum = 0 ## i64
  k = 0 - 2 * n
  while k <= 0
    sum += src[k + 16]
    k += 1
  i = (0 - n) ## i64
  while i < n
    t = (sum + src[i + 16]) ## i64
    if n2 == 1
      t += src[i + 15] + src[i + 17]
    src[48 + i + 8] = (t + rnd) >> log2s
    sum += src[i + n + 17] - src[i - n + 16]
    i += 1
  i = 0 - n
  while i < n
    pl[o + i * st] = src[48 + i + 8]
    i += 1
  0

# ---------------------------------------------------------------- CDEF kernels

# returns (yDir << 32) | var
-> av1_cdef_dir(pl, stride, x0, y0, bd, divt) (u16[] i64 i64 i64 i64 i32[]) i64
  cost = i64[8]
  part = i64[120]
  i = 0 ## i64
  while i < 8
    j = 0 ## i64
    while j < 8
      x = ((pl[(y0 + i) * stride + x0 + j] >> (bd - 8)) - 128) ## i64
      part[0 * 15 + i + j] += x
      part[1 * 15 + i + j / 2] += x
      part[2 * 15 + i] += x
      part[3 * 15 + 3 + i - j / 2] += x
      part[4 * 15 + 7 + i - j] += x
      part[5 * 15 + 3 - i / 2 + j] += x
      part[6 * 15 + j] += x
      part[7 * 15 + i / 2 + j] += x
      j += 1
    i += 1
  i = 0
  while i < 8
    cost[2] += part[30 + i] * part[30 + i]
    cost[6] += part[90 + i] * part[90 + i]
    i += 1
  cost[2] = cost[2] * divt[8]
  cost[6] = cost[6] * divt[8]
  i = 0
  while i < 7
    cost[0] += (part[i] * part[i] + part[14 - i] * part[14 - i]) * divt[i + 1]
    cost[4] += (part[60 + i] * part[60 + i] + part[60 + 14 - i] * part[60 + 14 - i]) * divt[i + 1]
    i += 1
  cost[0] += part[7] * part[7] * divt[8]
  cost[4] += part[67] * part[67] * divt[8]
  i = 1
  while i < 8
    b = (i * 15) ## i64
    j = 0 ## i64
    while j < 5
      cost[i] += part[b + 3 + j] * part[b + 3 + j]
      j += 1
    cost[i] = cost[i] * divt[8]
    j = 0
    while j < 3
      cost[i] += (part[b + j] * part[b + j] + part[b + 10 - j] * part[b + 10 - j]) * divt[2 * j + 2]
      j += 1
    i += 2
  best = 0 ## i64
  ydir = 0 ## i64
  i = 0
  while i < 8
    if cost[i] > best
      best = cost[i]
      ydir = i
    i += 1
  var = ((best - cost[(ydir + 4) & 7]) >> 10) ## i64
  (ydir << 32) | var

-> av1_constrain(diff, thr, damping) (i64 i64 i64) i64
  return 0 if thr == 0
  fl = 0 ## i64
  t = (thr) ## i64
  while t > 1
    t = t >> 1
    fl += 1
  adj = (damping - fl) ## i64
  adj = 0 if adj < 0
  ad = (diff < 0 ? 0 - diff : diff) ## i64
  v = (thr - (ad >> adj)) ## i64
  v = 0 if v < 0
  v = ad if v > ad
  diff < 0 ? 0 - v : v

-> av1_cstr(diff, thr, adj) (i64 i64 i64) i64
  ad = (diff < 0 ? 0 - diff : diff) ## i64
  v = (thr - (ad >> adj)) ## i64
  v = 0 if v < 0
  v = ad if v > ad
  diff < 0 ? 0 - v : v

-> av1_cdef_adj(thr, damping) (i64 i64) i64
  fl = 0 ## i64
  t = (thr) ## i64
  while t > 1
    t = t >> 1
    fl += 1
  adj = (damping - fl) ## i64
  adj = 0 if adj < 0
  adj

# interior 8x8 (or chroma) block: every tap available, no per-tap checks
-> av1_cdef_fast(src, dst, stride, x0, y0, w, h, pri, sec, damping, dir, pt, pt1, dirs) (u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[]) i64
  pa = (av1_cdef_adj(pri, damping)) ## i64
  sa = (av1_cdef_adj(sec, damping)) ## i64
  d1 = ((dir - 2) & 7) ## i64
  d2 = ((dir + 2) & 7) ## i64
  o0 = (dirs[dir * 4] * stride + dirs[dir * 4 + 1]) ## i64
  o1 = (dirs[dir * 4 + 2] * stride + dirs[dir * 4 + 3]) ## i64
  s0 = (dirs[d1 * 4] * stride + dirs[d1 * 4 + 1]) ## i64
  s1 = (dirs[d1 * 4 + 2] * stride + dirs[d1 * 4 + 3]) ## i64
  s2 = (dirs[d2 * 4] * stride + dirs[d2 * 4 + 1]) ## i64
  s3 = (dirs[d2 * 4 + 2] * stride + dirs[d2 * 4 + 3]) ## i64
  i = 0 ## i64
  while i < h
    o = ((y0 + i) * stride + x0) ## i64
    j = 0 ## i64
    while j < w
      q = (o + j) ## i64
      x = src[q] ## i64
      mx = (x) ## i64
      mn = (x) ## i64
      sum = 0 ## i64
      a = src[q + o0] ## i64
      b = src[q - o0] ## i64
      c = src[q + o1] ## i64
      d = src[q - o1] ## i64
      if pri != 0
        sum += pt * (av1_cstr(a - x, pri, pa) + av1_cstr(b - x, pri, pa)) + pt1 * (av1_cstr(c - x, pri, pa) + av1_cstr(d - x, pri, pa))
      mx = a if a > mx
      mx = b if b > mx
      mx = c if c > mx
      mx = d if d > mx
      mn = a if a < mn
      mn = b if b < mn
      mn = c if c < mn
      mn = d if d < mn
      e = src[q + s0] ## i64
      f = src[q - s0] ## i64
      g = src[q + s2] ## i64
      hh = src[q - s2] ## i64
      k1 = src[q + s1] ## i64
      k2 = src[q - s1] ## i64
      k3 = src[q + s3] ## i64
      k4 = src[q - s3] ## i64
      if sec != 0
        sum += 2 * (av1_cstr(e - x, sec, sa) + av1_cstr(f - x, sec, sa) + av1_cstr(g - x, sec, sa) + av1_cstr(hh - x, sec, sa))
        sum += av1_cstr(k1 - x, sec, sa) + av1_cstr(k2 - x, sec, sa) + av1_cstr(k3 - x, sec, sa) + av1_cstr(k4 - x, sec, sa)
      mx = e if e > mx
      mx = f if f > mx
      mx = g if g > mx
      mx = hh if hh > mx
      mx = k1 if k1 > mx
      mx = k2 if k2 > mx
      mx = k3 if k3 > mx
      mx = k4 if k4 > mx
      mn = e if e < mn
      mn = f if f < mn
      mn = g if g < mn
      mn = hh if hh < mn
      mn = k1 if k1 < mn
      mn = k2 if k2 < mn
      mn = k3 if k3 < mn
      mn = k4 if k4 < mn
      neg = (sum < 0 ? 1 : 0) ## i64
      v = (x + ((8 + sum - neg) >> 4)) ## i64
      v = mn if v < mn
      v = mx if v > mx
      dst[q] = v
      j += 1
    i += 1
  0

-> av1_cdef_filter(src, dst, stride, x0, y0, w, h, ssx, ssy, pri, sec, damping, dir, cs, mi_rows, mi_cols, dirs) (u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[]) i64
  pt = (((pri >> cs) & 1) == 0 ? 4 : 3) ## i64
  pt1 = (2) ## i64
  pt1 = 3 if pt == 3
  ylo = 0 ## i64
  ylo = ((y0 - 2) << ssy) >> 2
  yhi = 0 ## i64
  yhi = ((y0 + h + 1) << ssy) >> 2
  xlo = 0 ## i64
  xlo = ((x0 - 2) << ssx) >> 2
  xhi = 0 ## i64
  xhi = ((x0 + w + 1) << ssx) >> 2
  if y0 >= 2 && x0 >= 2 && ylo >= 0 && xlo >= 0 && yhi < mi_rows && xhi < mi_cols
    return av1_cdef_fast(src, dst, stride, x0, y0, w, h, pri, sec, damping, dir, pt, pt1, dirs)
  i = 0 ## i64
  while i < h
    j = 0 ## i64
    while j < w
      sum = 0 ## i64
      x = (src[(y0 + i) * stride + x0 + j]) ## i64
      mx = (x) ## i64
      mn = (x) ## i64
      k = 0 ## i64
      while k < 2
        sg = -1 ## i64
        while sg <= 1
          d = 0 ## i64
          while d < 3
            dd = (dir) ## i64
            if d == 1
              dd = (dir - 2) & 7
            elsif d == 2
              dd = (dir + 2) & 7
            yy = (y0 + i + sg * dirs[dd * 4 + k * 2]) ## i64
            xx = (x0 + j + sg * dirs[dd * 4 + k * 2 + 1]) ## i64
            cr = ((yy << ssy) >> 2) ## i64
            cc = ((xx << ssx) >> 2) ## i64
            if cr >= 0 && cr < mi_rows && cc >= 0 && cc < mi_cols
              pv = (src[yy * stride + xx]) ## i64
              if d == 0
                tap = (k == 0 ? pt : pt1) ## i64
                sum += tap * av1_constrain(pv - x, pri, damping)
              else
                tap = k == 0 ? 2 : 1
                sum += tap * av1_constrain(pv - x, sec, damping)
              mx = pv if pv > mx
              mn = pv if pv < mn
            d += 1
          sg += 2
        k += 1
      neg = (sum < 0 ? 1 : 0) ## i64
      v = (x + ((8 + sum - neg) >> 4)) ## i64
      v = mn if v < mn
      v = mx if v > mx
      dst[(y0 + i) * stride + x0 + j] = v
      j += 1
    i += 1
  0

# ---------------------------------------------------------------- superres

-> av1_upscale(src, ss, dst, ds, dw, uw, ph, max_x, bd, filt) (u16[] i64 u16[] i64 i64 i64 i64 i64 i64 i32[]) i64
  mxv = ((1 << bd) - 1) ## i64
  step = (((dw << 14) + (uw / 2)) / uw) ## i64
  err = ((uw * step) - (dw << 14)) ## i64
  init = ((0 - ((uw - dw) << 13) + uw / 2) / uw + (1 << 7) - err / 2) ## i64
  init = init & 16383
  y = 0 ## i64
  while y < ph
    x = 0 ## i64
    while x < uw
      sx = (0 - (1 << 14) + init + x * step) ## i64
      px = (sx >> 14) ## i64
      sub = ((sx & 16383) >> 8) ## i64
      sum = 0 ## i64
      k = 0 ## i64
      while k < 8
        s = (px + k - 3) ## i64
        s = 0 if s < 0
        s = max_x if s > max_x
        sum += src[y * ss + s] * filt[sub * 8 + k]
        k += 1
      v = ((sum + 64) >> 7) ## i64
      v = 0 if v < 0
      v = mxv if v > mxv
      dst[y * ds + x] = v
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- loop restoration kernels

-> av1_wiener_coef(c, o, f) (i32[] i64 i64[]) i64
  f[3] = 128
  i = 0 ## i64
  while i < 3
    v = (c[o + i]) ## i64
    f[i] = v
    f[6 - i] = v
    f[3] = f[3] - 2 * v
    i += 1
  0

-> av1_lr_src(cdef, cur, stride, x, y, ss, se, pex, pey) (u16[] u16[] i64 i64 i64 i64 i64 i64 i64) i64
  x = pex if x > pex
  x = 0 if x < 0
  y = pey if y > pey
  y = 0 if y < 0
  if y < ss
    y = ss - 2 if y < ss - 2
    return cur[y * stride + x]
  if y > se
    y = se + 2 if y > se + 2
    return cur[y * stride + x]
  cdef[y * stride + x]

# fetch the (h + 6) x (w + 6) source window around a unit once:
# buf[(r + 3) * (w + 6) + c + 3] = lr source sample at (x + c, y + r)
-> av1_lr_fill(buf, cdef, cur, stride, x, y, w, h, ss, se, pex, pey) (i64[] u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  bw = (w + 6) ## i64
  r = -3 ## i64
  while r < h + 3
    c = -3 ## i64
    o = ((r + 3) * bw + 3) ## i64
    while c < w + 3
      buf[o + c] = av1_lr_src(cdef, cur, stride, x + c, y + r, ss, se, pex, pey)
      c += 1
    r += 1
  0

-> av1_wiener(out, cdef, cur, stride, x, y, w, h, ss, se, pex, pey, hf, vf, bd, r0, r1) (u16[] u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64 i64 i64) i64
  off = 0 ## i64
  off = 1 << (bd + 7 - r0 - 1)
  lim = 0 ## i64
  lim = (1 << (bd + 1 + 7 - r0)) - 1
  mx = 0 ## i64
  mx = (1 << bd) - 1
  inter = i64[(h + 6) * w]
  bw = (w + 6) ## i64
  buf = i64[(h + 6) * bw]
  av1_lr_fill(buf, cdef, cur, stride, x, y, w, h, ss, se, pex, pey)
  h0 = (hf[0]) ## i64
  h1 = (hf[1]) ## i64
  h2 = (hf[2]) ## i64
  h3 = (hf[3]) ## i64
  h4 = (hf[4]) ## i64
  h5 = (hf[5]) ## i64
  h6 = (hf[6]) ## i64
  rnd0 = 0 ## i64
  rnd0 = (1 << r0) >> 1
  r = 0 ## i64
  while r < h + 6
    c = 0 ## i64
    while c < w
      q = (r * bw + c) ## i64
      s = (h0 * buf[q] + h1 * buf[q + 1] + h2 * buf[q + 2] + h3 * buf[q + 3] + h4 * buf[q + 4] + h5 * buf[q + 5] + h6 * buf[q + 6]) ## i64
      v = ((s + rnd0) >> r0) ## i64
      v = 0 - off if v < 0 - off
      v = lim - off if v > lim - off
      inter[r * w + c] = v
      c += 1
    r += 1
  r = 0
  while r < h
    c = 0 ## i64
    while c < w
      s = 0 ## i64
      t = 0 ## i64
      while t < 7
        s += vf[t] * inter[(r + t) * w + c]
        t += 1
      v = (s + (1 << (r1 - 1))) >> r1
      v = 0 if v < 0
      v = mx if v > mx
      out[(y + r) * stride + x + c] = v
      c += 1
    r += 1
  0

-> av1_r2(x, n) (i64 i64) i64
  return x if n == 0
  (x + (1 << (n - 1))) >> n

# box filter for one pass into f (h x w); returns 0 when r == 0 (f untouched)
-> av1_box(cdef, cur, stride, x, y, w, h, ss, se, pex, pey, r, eps, bd, pass, f) (u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  return 0 if r == 0
  n = ((2 * r + 1) * (2 * r + 1)) ## i64
  n2e = (n * n * eps) ## i64
  s = (((1 << 20) + n2e / 2) / n2e) ## i64
  aw = (w + 2) ## i64
  ah = (h + 2) ## i64
  aa = i64[aw * ah]
  bb = i64[aw * ah]
  one_over_n = (((1 << 12) + (n / 2)) / n) ## i64
  bw = (w + 6) ## i64
  buf = i64[(h + 6) * bw]
  av1_lr_fill(buf, cdef, cur, stride, x, y, w, h, ss, se, pex, pey)
  i = -1 ## i64
  while i < h + 1
    # pass 0 only reads the rows with odd i
    if pass == 0 && (i & 1) == 0
      i += 1
      next
    j = -1 ## i64
    while j < w + 1
      a = 0 ## i64
      b = 0 ## i64
      dy = (0 - r) ## i64
      while dy <= r
        dx = (0 - r) ## i64
        while dx <= r
          c = (buf[(i + dy + 3) * bw + j + dx + 3]) ## i64
          a += c * c
          b += c
          dx += 1
        dy += 1
      a = av1_r2(a, 2 * (bd - 8))
      d = (av1_r2(b, bd - 8)) ## i64
      p = (a * n - d * d) ## i64
      p = 0 if p < 0
      z = (av1_r2(p * s, 20)) ## i64
      a2 = 0 ## i64
      if z >= 255
        a2 = 256
      elsif z == 0
        a2 = 1
      else
        a2 = ((z << 8) + (z / 2)) / (z + 1)
      b2 = (((1 << 8) - a2) * b * one_over_n) ## i64
      aa[(i + 1) * aw + j + 1] = a2
      bb[(i + 1) * aw + j + 1] = av1_r2(b2, 12)
      j += 1
    i += 1
  i = 0
  while i < h
    shift = (5) ## i64
    shift = 4 if pass == 0 && (i & 1) == 1
    j = 0 ## i64
    while j < w
      a = 0 ## i64
      b = 0 ## i64
      dy = -1 ## i64
      while dy <= 1
        dx = -1 ## i64
        while dx <= 1
          wt = 0 ## i64
          if pass == 0
            if ((i + dy) & 1) != 0
              wt = dx == 0 ? 6 : 5
          else
            wt = (dx == 0 || dy == 0) ? 4 : 3
          k = ((i + dy + 1) * aw + j + dx + 1) ## i64
          a += wt * aa[k]
          b += wt * bb[k]
          dx += 1
        dy += 1
      v = (a * cdef[(y + i) * stride + x + j] + b) ## i64
      f[i * w + j] = av1_r2(v, 8 + shift - 4)
      j += 1
    i += 1
  0

-> av1_sgr(out, cdef, cur, stride, x, y, w, h, ss, se, pex, pey, set, w0, w1, bd, sgr) (u16[] u16[] u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[]) i64
  f0 = i64[w * h]
  f1 = i64[w * h]
  rr0 = sgr[set * 4] ## i64
  rr1 = sgr[set * 4 + 2] ## i64
  e0 = sgr[set * 4 + 1] ## i64
  e1 = sgr[set * 4 + 3] ## i64
  av1_box(cdef, cur, stride, x, y, w, h, ss, se, pex, pey, rr0, e0, bd, 0, f0)
  av1_box(cdef, cur, stride, x, y, w, h, ss, se, pex, pey, rr1, e1, bd, 1, f1)
  w2 = ((1 << 7) - w0 - w1) ## i64
  mx = ((1 << bd) - 1) ## i64
  i = 0 ## i64
  while i < h
    j = 0 ## i64
    while j < w
      u = (cdef[(y + i) * stride + x + j] << 4) ## i64
      v = (w1 * u) ## i64
      if rr0 != 0
        v += w0 * f0[i * w + j]
      else
        v += w0 * u
      if rr1 != 0
        v += w2 * f1[i * w + j]
      else
        v += w2 * u
      s = ((v + (1 << 10)) >> 11) ## i64
      s = 0 if s < 0
      s = mx if s > mx
      out[(y + i) * stride + x + j] = s
      j += 1
    i += 1
  0
