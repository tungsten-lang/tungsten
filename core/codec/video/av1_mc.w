# core/codec/video/av1_mc — AV1 inter prediction (spec 7.11.3): compute_prediction,
# motion vector scaling, block inter prediction (8-tap subpel filters with
# reference scaling and edge clamping), local / global warp (setup shear,
# warp estimation), OBMC, wedge / difference-weight / interintra masks,
# distance weights and the final blends. Reopens Av1Decoder.

use av1_tables

-> av1_mc_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

# OBMC masks concatenated: the mask of length L starts at offset L
-> av1_mc_obmc
  out = i32[64]
  t = [AV1_OBMC_MASK_2, AV1_OBMC_MASK_4, AV1_OBMC_MASK_8, AV1_OBMC_MASK_16, AV1_OBMC_MASK_32]
  k = 0
  while k < 5
    n = 2 << k
    i = 0
    while i < n
      out[n + i] = t[k][i]
      i += 1
    k += 1
  out

AV1_SUBPEL_T = av1_mc_i32(AV1_SUBPEL_FILTERS)
AV1_WARPF_T = av1_mc_i32(AV1_WARPED_FILTERS)
AV1_DIVLUT_T = av1_mc_i32(AV1_DIV_LUT)
AV1_OBMC_T = av1_mc_obmc()
AV1_IIW_T = av1_mc_i32(AV1_II_WEIGHTS_1D)
AV1_QDW_T = av1_mc_i32(AV1_QUANT_DIST_WEIGHT)
AV1_QDL_T = av1_mc_i32(AV1_QUANT_DIST_LOOKUP)
# optional tool usage counters (debug): AV1_STATS[0] = {} enables
AV1_STATS = [nil]
# wedge masks are built on first use: [u8 data, i32 offsets by block size]
AV1_WEDGE = [nil, nil]

+ Av1Decoder
  -> mc_begin
    @pred0 = i32[128 * 128]
    @pred1 = i32[128 * 128]
    @mc_tmp = i32[272 * 128]
    @mask = i32[128 * 128]
    @obmc_buf = i32[128 * 128]
    @warp_tmp = i32[15 * 8]
    @shear = i64[5]
    @gmp = i64[6]
    @mask_stride = 0
    nil

  # ------------------------------------------------------------ compute_prediction (5.11.33)

  -> compute_prediction
    sb_mask = @sb128 == 1 ? 31 : 15
    sbr = @mi_row & sb_mask
    sbc = @mi_col & sb_mask
    np = @has_chroma ? 3 : 1
    mis = @mis
    @local_valid = 0
    plane = 0
    while plane < np
      psz = get_plane_residual_size(@mi_size, plane)
      n4w = AV1_BW4[psz]
      n4h = AV1_BH4[psz]
      log2w = 2 + AV1_MIWL[psz]
      log2h = 2 + AV1_MIHL[psz]
      sx = plane > 0 ? @ssx : 0
      sy = plane > 0 ? @ssy : 0
      base_x = (@mi_col >> sx) * 4
      base_y = (@mi_row >> sy) * 4
      cand_row = (@mi_row >> sy) << sy
      cand_col = (@mi_col >> sx) << sx
      @is_inter_intra = @is_inter == 1 && @ref_frame1 == 0
      if @is_inter_intra
        im = @interintra_mode
        mode = im == 3 ? 9 : im
        ar = @block_decoded[plane][((sbr >> sy) - 1 + 1) * 34 + (sbc >> sx) + n4w + 1] == 1
        bl = @block_decoded[plane][((sbr >> sy) + n4h + 1) * 34 + (sbc >> sx) - 1 + 1] == 1
        predict_intra(plane, base_x, base_y, plane == 0 ? @avail_l : @avail_l_chroma, plane == 0 ? @avail_u : @avail_u_chroma, ar, bl, mode, log2w, log2h)
      pred_w = (@bw4 * 4) >> sx
      pred_h = (@bh4 * 4) >> sy
      some_intra = false
      r = 0
      while r < (n4h << sy)
        c = 0
        while c < (n4w << sx)
          # positions past the mi grid belong to this (inter) block's own
          # off-frame extension in the spec's unbounded arrays: never intra
          if cand_row + r < @mi_rows && cand_col + c < @mi_cols
            some_intra = true if @a_ref0[(cand_row + r) * mis + cand_col + c] == 0
          c += 1
        r += 1
      if some_intra
        pred_w = n4w * 4
        pred_h = n4h * 4
        cand_row = @mi_row
        cand_col = @mi_col
      r = 0
      y = 0
      while y < n4h * 4
        c = 0
        x = 0
        while x < n4w * 4
          predict_inter(plane, base_x + x, base_y + y, pred_w, pred_h, cand_row + r, cand_col + c)
          c += 1
          x += pred_w
        r += 1
        y += pred_h
      plane += 1
    nil

  # ------------------------------------------------------------ predict_inter (7.11.3.1)

  -> predict_inter(plane, x, y, w, h, cand_row, cand_col)
    k = cand_row * @mis + cand_col
    is_comp = @a_ref1[k] > 0
    r0 = 3
    r1 = is_comp ? 7 : 11
    if @bit_depth == 12
      r0 = 5
      r1 -= 2 if !is_comp
    post = 14 - r0 - r1
    @round0 = r0
    @round1 = r1
    if plane == 0 && @motion_mode == 2
      warp_estimation()
      if @local_valid == 1
        @local_valid = av1_setup_shear(@lwp, AV1_DIVLUT_T, @shear)
    fr = @cur
    dst = fr.planes[plane]
    ds = fr.strides[plane]
    ref_list = 0
    while ref_list < (is_comp ? 2 : 1)
      rf = ref_list == 0 ? @a_ref0[k] : @a_ref1[k]
      glob = (@y_mode == 16 || @y_mode == 24) && rf > 0 && @gm_type[rf] > 1
      global_valid = 0
      if glob
        load_gm(rf)
        global_valid = av1_setup_shear(@gmp, AV1_DIVLUT_T, @shear)
      use_warp = 0
      if w < 8 || h < 8
        use_warp = 0
      elsif @force_integer_mv == 1
        use_warp = 0
      elsif @motion_mode == 2 && @local_valid == 1
        use_warp = 1
      elsif glob && !is_scaled(rf) && global_valid == 1
        use_warp = 2
      m0 = @a_mvs[k * 4 + ref_list * 2]
      m1 = @a_mvs[k * 4 + ref_list * 2 + 1]
      ref_idx = @use_intrabc == 0 ? @ref_frame_idx[rf - 1] : -1
      if use_warp != 0
        block_warp(use_warp, plane, rf, x, y, w, h, ref_list == 0 ? @pred0 : @pred1)
      else
        mv_scale(plane, ref_idx, x, y, m0, m1)
        block_inter(plane, ref_idx, @start_x, @start_y, @step_x, @step_y, w, h, k, ref_list == 0 ? @pred0 : @pred1)
      ref_list += 1
    ct = @compound_type
    av1_stat_block(self, is_comp, plane, k) if AV1_STATS[0] != nil
    if ct == 0 && plane == 0
      wedge_mask(w, h)
    elsif ct == 3
      av1_ii_mask(@mask, w, h, @interintra_mode, AV1_IIW_T)
      @mask_stride = w
    elsif ct == 1 && plane == 0
      av1_diffwtd_mask(@mask, @pred0, @pred1, w, h, (@bit_depth - 8) + post, @mask_type)
      @mask_stride = w
    mx = (1 << @bit_depth) - 1
    if !is_comp && !@is_inter_intra
      av1_put1(dst, ds, x, y, w, h, @pred0, mx)
    elsif ct == 2
      av1_put_avg(dst, ds, x, y, w, h, @pred0, @pred1, 1 + post, mx)
    elsif ct == 4
      distance_weights(k)
      av1_put_dist(dst, ds, x, y, w, h, @pred0, @pred1, @fwd_weight, @bck_weight, 4 + post, mx)
    else
      sx = plane > 0 ? @ssx : 0
      sy = plane > 0 ? @ssy : 0
      mode = 0
      if (sx == 0 && sy == 0) || (@interintra == 1 && @wedge_interintra == 0)
        mode = 0
      elsif sx == 1 && sy == 0
        mode = 1
      else
        mode = 2
      av1_mask_blend(dst, ds, x, y, w, h, @pred0, @pred1, @mask, @mask_stride, mode, post, mx, @interintra)
    overlapped_mc(plane, w, h) if @motion_mode == 1
    nil

  -> stat_block(is_comp, k)
    av1_stat("blocks")
    av1_stat("intrabc") if @use_intrabc == 1
    av1_stat("compound") if is_comp
    av1_stat("ct" + @compound_type.to_s) if is_comp || @interintra == 1
    av1_stat("interintra") if @interintra == 1
    av1_stat("obmc") if @motion_mode == 1
    av1_stat("localwarp") if @motion_mode == 2
    av1_stat("localwarp_valid") if @motion_mode == 2 && @local_valid == 1
    av1_stat("globalmode") if @y_mode == 16 || @y_mode == 24
    av1_stat("gmwarp") if (@y_mode == 16 || @y_mode == 24) && @gm_type[@a_ref0[k]] > 1
    av1_stat("skipmode") if @skip_mode == 1
    av1_stat("scaled") if @use_intrabc == 0 && is_scaled(@a_ref0[k])
    av1_stat("dual") if @a_interp[k * 2] != @a_interp[k * 2 + 1]
    av1_stat("filt" + @a_interp[k * 2].to_s)
    av1_stat("tmvp") if @use_ref_frame_mvs == 1
    nil

  -> load_gm(rf)
    g = @gm_params[rf]
    i = 0
    while i < 6
      @gmp[i] = g[i]
      i += 1
    nil

  # motion vector scaling (7.11.3.3): sets @start_x/y, @step_x/y
  -> mv_scale(plane, ref_idx, x, y, m0, m1)
    ruw = 0
    rh = 0
    if ref_idx < 0
      ruw = @upscaled_width
      rh = @frame_height
    else
      ruw = @ref_upscaled_w[ref_idx]
      rh = @ref_frame_h[ref_idx]
    fw = @frame_width
    fh = @frame_height
    xs = ((ruw << 14) + (fw / 2)) / fw
    ys = ((rh << 14) + (fh / 2)) / fh
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    ox = (x << 4) + ((2 * m1) >> sx) + 8
    oy = (y << 4) + ((2 * m0) >> sy) + 8
    bx = ox * xs - (8 << 14)
    by = oy * ys - (8 << 14)
    @start_x = av1_round2signed(bx, 8) + 32
    @start_y = av1_round2signed(by, 8) + 32
    @step_x = av1_round2signed(xs, 4)
    @step_y = av1_round2signed(ys, 4)
    nil

  # block inter prediction (7.11.3.4) into out (stride w)
  -> block_inter(plane, ref_idx, sx0, sy0, stx, sty, w, h, k, out)
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    fr = ref_idx < 0 ? @cur : @ref_frames[ref_idx]
    raise Av1Error.new("av1: missing reference frame") if fr == nil || fr.planes.size <= plane
    lx = 0
    ly = 0
    if ref_idx < 0
      lx = ((@mi_cols * 4 + sx) >> sx) - 1
      ly = ((@mi_rows * 4 + sy) >> sy) - 1
    else
      lx = ((@ref_upscaled_w[ref_idx] + sx) >> sx) - 1
      ly = ((@ref_frame_h[ref_idx] + sy) >> sy) - 1
    # conformance limits (2x down .. 16x up); keeps the intermediate buffer in range
    raise Av1Error.new("av1: invalid reference scaling") if stx > 2048 || sty > 2048 || stx < 64 || sty < 64
    fx = @a_interp[k * 2 + 1]
    fy = @a_interp[k * 2]
    if w <= 4
      if fx == 0 || fx == 2
        fx = 4
      elsif fx == 1
        fx = 5
    if h <= 4
      if fy == 0 || fy == 2
        fy = 4
      elsif fy == 1
        fy = 5
    av1_mc(fr.planes[plane], fr.strides[plane], lx, ly, sx0, sy0, stx, sty, w, h, fx, fy, @round0, @round1, AV1_SUBPEL_T, @mc_tmp, out)
    nil

  # ------------------------------------------------------------ warp

  -> block_warp(use_warp, plane, rf, x, y, w, h, out)
    ref_idx = @ref_frame_idx[rf - 1]
    fr = @ref_frames[ref_idx]
    raise Av1Error.new("av1: missing reference frame") if fr == nil || fr.planes.size <= plane
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    lx = ((@ref_upscaled_w[ref_idx] + sx) >> sx) - 1
    ly = ((@ref_frame_h[ref_idx] + sy) >> sy) - 1
    load_gm(rf) if use_warp == 2
    av1_setup_shear(use_warp == 2 ? @gmp : @lwp, AV1_DIVLUT_T, @shear)
    av1_warp_block(fr.planes[plane], fr.strides[plane], lx, ly, sx, sy, x, y, w, h, use_warp == 2 ? @gmp : @lwp, @shear, @round0, @round1, AV1_WARPF_T, @warp_tmp, out)
    nil

  -> warp_estimation
    w4 = @bw4
    h4 = @bh4
    mid_y = @mi_row * 4 + h4 * 2 - 1
    mid_x = @mi_col * 4 + w4 * 2 - 1
    @local_valid = av1_warp_est(@cand_list, @num_samples, @mv[0], @mv[1], mid_y, mid_x, AV1_DIVLUT_T, @lwp)
    nil

  # ------------------------------------------------------------ OBMC (7.11.3.9)

  -> overlapped_mc(plane, w, h)
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    mis = @mis
    fr = @cur
    dst = fr.planes[plane]
    ds = fr.strides[plane]
    mx = (1 << @bit_depth) - 1
    if @avail_u
      if get_plane_residual_size(@mi_size, plane) >= 3
        x4 = @mi_col
        y4 = @mi_row
        n = 0
        lim = av1_min(4, AV1_MIWL[@mi_size])
        e = av1_min(@mi_cols, @mi_col + @bw4)
        while n < lim && x4 < e
          cr = @mi_row - 1
          cc = x4 | 1
          k = cr * mis + cc
          step = av1_clip3(2, 16, AV1_BW4[@a_mi_sizes[k]])
          if @a_ref0[k] > 0
            n += 1
            pw = av1_min(w, (step * 4) >> sx)
            ph = av1_min(h >> 1, 32 >> sy)
            predict_overlap(plane, k, x4, y4, pw, ph, 0, ph, dst, ds, mx)
          x4 += step
    if @avail_l
      x4 = @mi_col
      y4 = @mi_row
      n = 0
      lim = av1_min(4, AV1_MIHL[@mi_size])
      e = av1_min(@mi_rows, @mi_row + @bh4)
      while n < lim && y4 < e
        cc = @mi_col - 1
        cr = y4 | 1
        k = cr * mis + cc
        step = av1_clip3(2, 16, AV1_BH4[@a_mi_sizes[k]])
        if @a_ref0[k] > 0
          n += 1
          pw = av1_min(w >> 1, 32 >> sx)
          ph = av1_min(h, (step * 4) >> sy)
          predict_overlap(plane, k, x4, y4, pw, ph, 1, pw, dst, ds, mx)
        y4 += step
    nil

  -> predict_overlap(plane, k, x4, y4, pw, ph, pass, mlen, dst, ds, mx)
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    m0 = @a_mvs[k * 4]
    m1 = @a_mvs[k * 4 + 1]
    ref_idx = @ref_frame_idx[@a_ref0[k] - 1]
    px = (x4 * 4) >> sx
    py = (y4 * 4) >> sy
    mv_scale(plane, ref_idx, px, py, m0, m1)
    block_inter(plane, ref_idx, @start_x, @start_y, @step_x, @step_y, pw, ph, k, @obmc_buf)
    moff = mlen
    moff = 32 if mlen > 32 || (mlen != 2 && mlen != 4 && mlen != 8 && mlen != 16)
    av1_obmc_blend(dst, ds, px, py, pw, ph, @obmc_buf, AV1_OBMC_T, moff, pass, mx)
    nil

  # ------------------------------------------------------------ masks / weights

  -> wedge_mask(w, h)
    av1_wedge_init() if AV1_WEDGE[0] == nil
    data = AV1_WEDGE[0]
    off = AV1_WEDGE[1][@mi_size] + ((@wedge_sign * 16 + @wedge_index) * w * h)
    av1_u8_to_i32(data, off, @mask, w * h)
    @mask_stride = w
    nil

  -> distance_weights(k)
    d0 = 0
    d1 = 0
    h = @order_hints[@a_ref1[k]]
    d0 = av1_clip3(0, 31, av1_abs(get_relative_dist(h, @order_hint)))
    h = @order_hints[@a_ref0[k]]
    d1 = av1_clip3(0, 31, av1_abs(get_relative_dist(h, @order_hint)))
    order = d0 <= d1 ? 1 : 0
    if d0 == 0 || d1 == 0
      @fwd_weight = AV1_QDL_T[3 * 2 + order]
      @bck_weight = AV1_QDL_T[3 * 2 + 1 - order]
      return nil
    i = 0
    while i < 3
      c0 = AV1_QDW_T[i * 2 + order]
      c1 = AV1_QDW_T[i * 2 + 1 - order]
      if order == 1
        break if d0 * c0 > d1 * c1
      else
        break if d0 * c0 < d1 * c1
      i += 1
    @fwd_weight = AV1_QDL_T[i * 2 + order]
    @bck_weight = AV1_QDL_T[i * 2 + 1 - order]
    nil

-> av1_stat(name)
  h = AV1_STATS[0]
  h[name] = (h[name] == nil ? 0 : h[name]) + 1

-> av1_stat_block(d, is_comp, plane, k)
  return nil if plane != 0
  d.stat_block(is_comp, k)

# ---------------------------------------------------------------- wedge table

-> av1_wedge_init
  mm = i32[6 * 4096]
  ev = av1_mc_i32(AV1_WEDGE_MASTER_OBLIQUE_EVEN)
  od = av1_mc_i32(AV1_WEDGE_MASTER_OBLIQUE_ODD)
  vt = av1_mc_i32(AV1_WEDGE_MASTER_VERTICAL)
  av1_wedge_master(mm, ev, od, vt)
  offs = i32[22]
  total = 0
  b = 3
  while b < 22
    if AV1_WEDGE_BITS[b] > 0
      offs[b] = total
      total += 2 * 16 * AV1_BW4[b] * 4 * AV1_BH4[b] * 4
    b += 1
  data = u8[total]
  cb = AV1_WEDGE_CODEBOOK
  b = 3
  while b < 22
    if AV1_WEDGE_BITS[b] > 0
      w = AV1_BW4[b] * 4
      h = AV1_BH4[b] * 4
      shape = 2
      if AV1_BH4[b] > AV1_BW4[b]
        shape = 0
      elsif AV1_BH4[b] < AV1_BW4[b]
        shape = 1
      wedge = 0
      while wedge < 16
        e = (shape * 16 + wedge) * 3
        dir = cb[e]
        xoff = 32 - ((cb[e + 1] * w) >> 3)
        yoff = 32 - ((cb[e + 2] * h) >> 3)
        av1_wedge_fill(mm, data, offs[b], w, h, dir, xoff, yoff, wedge)
        wedge += 1
    b += 1
  AV1_WEDGE[1] = offs
  AV1_WEDGE[0] = data
  nil

-> av1_wedge_master(mm, ev, od, vt) (i32[] i32[] i32[] i32[]) i64
  j = 0 ## i64
  while j < 64
    shift = 16 ## i64
    i = 0 ## i64
    while i < 64
      a = (j - shift) ## i64
      a = 0 if a < 0
      a = 63 if a > 63
      mm[3 * 4096 + i * 64 + j] = ev[a]
      shift -= 1
      b = (j - shift) ## i64
      b = 0 if b < 0
      b = 63 if b > 63
      mm[3 * 4096 + (i + 1) * 64 + j] = od[b]
      mm[4096 + i * 64 + j] = vt[j]
      mm[4096 + (i + 1) * 64 + j] = vt[j]
      i += 2
    j += 1
  i = 0
  while i < 64
    j = 0
    while j < 64
      msk = mm[3 * 4096 + i * 64 + j] ## i64
      mm[2 * 4096 + j * 64 + i] = msk
      mm[4 * 4096 + i * 64 + 63 - j] = 64 - msk
      mm[5 * 4096 + (63 - j) * 64 + i] = 64 - msk
      mm[j * 64 + i] = mm[4096 + i * 64 + j]
      j += 1
    i += 1
  0

-> av1_wedge_fill(mm, data, off, w, h, dir, xoff, yoff, wedge) (i32[] u8[] i64 i64 i64 i64 i64 i64 i64) i64
  base = (dir * 4096) ## i64
  sum = 0 ## i64
  i = 0 ## i64
  while i < w
    sum += mm[base + yoff * 64 + xoff + i]
    i += 1
  i = 1
  while i < h
    sum += mm[base + (yoff + i) * 64 + xoff]
    i += 1
  avg = ((sum + (w + h - 1) / 2) / (w + h - 1)) ## i64
  flip = 0 ## i64
  flip = 1 if avg < 32
  o1 = (off + (flip * 16 + wedge) * w * h) ## i64
  o2 = (off + ((1 - flip) * 16 + wedge) * w * h) ## i64
  i = 0
  while i < h
    j = 0 ## i64
    while j < w
      v = mm[base + (yoff + i) * 64 + xoff + j] ## i64
      data[o1 + i * w + j] = v
      data[o2 + i * w + j] = 64 - v
      j += 1
    i += 1
  0

-> av1_u8_to_i32(src, off, dst, n) (u8[] i64 i32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[i] = src[off + i]
    i += 1
  0

# ---------------------------------------------------------------- kernels

# Block inter prediction: horizontal then vertical 8-tap filtering.
-> av1_mc(ref, stride, lastx, lasty, x, y, xs, ys, w, h, fx, fy, r0, r1, filt, tmp, out) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[] i32[] i32[]) i64
  x0 = (x >> 10) ## i64
  y0 = (y >> 10) ## i64
  if xs == 1024 && ys == 1024 && x0 >= 3 && y0 >= 3 && x0 + w + 4 <= lastx && y0 + h + 4 <= lasty
    return av1_mc_fast(ref, stride, x0, y0, (x >> 6) & 15, (y >> 6) & 15, w, h, fx, fy, r0, r1, filt, tmp, out)
  h1 = 0 ## i64
  h1 = (1 << r0) >> 1
  h2 = 0 ## i64
  h2 = (1 << r1) >> 1
  ih = ((((h - 1) * ys + 1023) >> 10) + 8) ## i64
  r = 0 ## i64
  while r < ih
    yy = (y0 + r - 3) ## i64
    yy = 0 if yy < 0
    yy = lasty if yy > lasty
    ro = (yy * stride) ## i64
    c = 0 ## i64
    while c < w
      p = (x + xs * c) ## i64
      fo = (fx * 128 + ((p >> 6) & 15) * 8) ## i64
      xb = ((p >> 10) - 3) ## i64
      s = 0 ## i64
      t = 0 ## i64
      while t < 8
        xx = (xb + t) ## i64
        xx = 0 if xx < 0
        xx = lastx if xx > lastx
        f = filt[fo + t] ## i64
        v = ref[ro + xx] ## i64
        s += f * v
        t += 1
      tmp[r * w + c] = (s + h1) >> r0
      c += 1
    r += 1
  r = 0
  while r < h
    p = (y & 1023) + ys * r
    fo = fy * 128 + ((p >> 6) & 15) * 8
    base = (p >> 10) ## i64
    c = 0 ## i64
    while c < w
      s = 0 ## i64
      t = 0 ## i64
      while t < 8
        f = filt[fo + t] ## i64
        v = tmp[(base + t) * w + c] ## i64
        s += f * v
        t += 1
      out[r * w + c] = (s + h2) >> r1
      c += 1
    r += 1
  0

# unscaled, no edge clamping needed
-> av1_mc_fast(ref, stride, x0, y0, px, py, w, h, fx, fy, r0, r1, filt, tmp, out) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[] i32[] i32[]) i64
  h1 = 0 ## i64
  h1 = (1 << r0) >> 1
  h2 = 0 ## i64
  h2 = (1 << r1) >> 1
  r = 0 ## i64
  c = 0 ## i64
  if px == 0 && py == 0
    sh = (14 - r0 - r1) ## i64
    while r < h
      o = ((y0 + r) * stride + x0) ## i64
      ob = (r * w) ## i64
      c = 0
      while c < w
        v = ref[o + c] ## i64
        out[ob + c] = v << sh
        c += 1
      r += 1
    return 0
  fo = (fx * 128 + px * 8) ## i64
  a0 = filt[fo] ## i64
  a1 = filt[fo + 1] ## i64
  a2 = filt[fo + 2] ## i64
  a3 = filt[fo + 3] ## i64
  a4 = filt[fo + 4] ## i64
  a5 = filt[fo + 5] ## i64
  a6 = filt[fo + 6] ## i64
  a7 = filt[fo + 7] ## i64
  if py == 0
    while r < h
      o = (y0 + r) * stride + x0 - 3
      ob = r * w
      c = 0
      while c < w
        q = (o + c) ## i64
        s = (a0 * ref[q] + a1 * ref[q + 1] + a2 * ref[q + 2] + a3 * ref[q + 3] + a4 * ref[q + 4] + a5 * ref[q + 5] + a6 * ref[q + 6] + a7 * ref[q + 7]) ## i64
        t = ((s + h1) >> r0) ## i64
        out[ob + c] = (t * 128 + h2) >> r1
        c += 1
      r += 1
    return 0
  ih = (h + 7) ## i64
  if px == 0
    sh0 = (7 - r0) ## i64
    while r < ih
      o = (y0 - 3 + r) * stride + x0
      ob = r * w
      c = 0
      while c < w
        v = ref[o + c] ## i64
        tmp[ob + c] = v << sh0
        c += 1
      r += 1
  else
    while r < ih
      o = (y0 - 3 + r) * stride + x0 - 3
      ob = r * w
      c = 0
      while c < w
        q = o + c
        s = a0 * ref[q] + a1 * ref[q + 1] + a2 * ref[q + 2] + a3 * ref[q + 3] + a4 * ref[q + 4] + a5 * ref[q + 5] + a6 * ref[q + 6] + a7 * ref[q + 7]
        tmp[ob + c] = (s + h1) >> r0
        c += 1
      r += 1
  gofs = (fy * 128 + py * 8) ## i64
  b0 = filt[gofs] ## i64
  b1 = filt[gofs + 1] ## i64
  b2 = filt[gofs + 2] ## i64
  b3 = filt[gofs + 3] ## i64
  b4 = filt[gofs + 4] ## i64
  b5 = filt[gofs + 5] ## i64
  b6 = filt[gofs + 6] ## i64
  b7 = filt[gofs + 7] ## i64
  r = 0
  while r < h
    ob = r * w
    c = 0
    while c < w
      q = ob + c
      s = b0 * tmp[q] + b1 * tmp[q + w] + b2 * tmp[q + 2 * w] + b3 * tmp[q + 3 * w] + b4 * tmp[q + 4 * w] + b5 * tmp[q + 5 * w] + b6 * tmp[q + 6 * w] + b7 * tmp[q + 7 * w]
      out[q] = (s + h2) >> r1
      c += 1
    r += 1
  0

-> av1_put1(dst, ds, x, y, w, h, p, mx) (u16[] i64 i64 i64 i64 i64 i32[] i64) i64
  r = 0 ## i64
  while r < h
    o = ((y + r) * ds + x) ## i64
    c = 0 ## i64
    while c < w
      v = p[r * w + c] ## i64
      v = 0 if v < 0
      v = mx if v > mx
      dst[o + c] = v
      c += 1
    r += 1
  0

-> av1_put_avg(dst, ds, x, y, w, h, p0, p1, sh, mx) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << sh) >> 1
  r = 0 ## i64
  while r < h
    o = ((y + r) * ds + x) ## i64
    c = 0 ## i64
    while c < w
      a = p0[r * w + c] ## i64
      b = p1[r * w + c] ## i64
      v = ((a + b + rnd) >> sh) ## i64
      v = 0 if v < 0
      v = mx if v > mx
      dst[o + c] = v
      c += 1
    r += 1
  0

-> av1_put_dist(dst, ds, x, y, w, h, p0, p1, fw, bw, sh, mx) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i64 i64 i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << sh) >> 1
  r = 0 ## i64
  while r < h
    o = ((y + r) * ds + x) ## i64
    c = 0 ## i64
    while c < w
      a = p0[r * w + c] ## i64
      b = p1[r * w + c] ## i64
      v = ((fw * a + bw * b + rnd) >> sh) ## i64
      v = 0 if v < 0
      v = mx if v > mx
      dst[o + c] = v
      c += 1
    r += 1
  0

# mask blend (7.11.3.14); mode 0 = mask at plane resolution, 1 = 2x1, 2 = 2x2
-> av1_mask_blend(dst, ds, x, y, w, h, p0, p1, mask, ms, mode, post, mx, ii) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i32[] i64 i64 i64 i64 i64) i64
  rp = 0 ## i64
  rp = (1 << post) >> 1
  sh = (6 + post) ## i64
  rb = 0 ## i64
  rb = (1 << sh) >> 1
  r = 0 ## i64
  while r < h
    o = ((y + r) * ds + x) ## i64
    c = 0 ## i64
    while c < w
      m = 0 ## i64
      if mode == 0
        m = mask[r * ms + c]
      elsif mode == 1
        m = (mask[r * ms + 2 * c] + mask[r * ms + 2 * c + 1] + 1) >> 1
      else
        q = (2 * r * ms + 2 * c) ## i64
        m = (mask[q] + mask[q + 1] + mask[q + ms] + mask[q + ms + 1] + 2) >> 2
      a = p0[r * w + c] ## i64
      if ii == 1
        a = (a + rp) >> post
        a = 0 if a < 0
        a = mx if a > mx
        b = dst[o + c] ## i64
        dst[o + c] = (m * b + (64 - m) * a + 32) >> 6
      else
        b = p1[r * w + c] ## i64
        v = ((m * a + (64 - m) * b + rb) >> sh) ## i64
        v = 0 if v < 0
        v = mx if v > mx
        dst[o + c] = v
      c += 1
    r += 1
  0

-> av1_diffwtd_mask(mask, p0, p1, w, h, sh, mt) (i32[] i32[] i32[] i64 i64 i64 i64) i64
  rnd = 0 ## i64
  rnd = (1 << sh) >> 1
  i = 0 ## i64
  n = (w * h) ## i64
  while i < n
    a = p0[i] ## i64
    b = p1[i] ## i64
    d = (a - b) ## i64
    d = 0 - d if d < 0
    d = (d + rnd) >> sh
    m = (38 + d / 16) ## i64
    m = 0 if m < 0
    m = 64 if m > 64
    if mt == 1
      mask[i] = 64 - m
    else
      mask[i] = m
    i += 1
  0

-> av1_ii_mask(mask, w, h, mode, iiw) (i32[] i64 i64 i64 i32[]) i64
  mwh = (w > h ? w : h) ## i64
  scale = (128 / mwh) ## i64
  i = 0 ## i64
  while i < h
    j = 0 ## i64
    while j < w
      v = 32 ## i64
      if mode == 1
        v = iiw[i * scale]
      elsif mode == 2
        v = iiw[j * scale]
      elsif mode == 3
        mn = (i < j ? i : j) ## i64
        v = iiw[mn * scale]
      mask[i * w + j] = v
      j += 1
    i += 1
  0

-> av1_obmc_blend(dst, ds, x, y, w, h, p, mask, moff, pass, mx) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i64 i64 i64) i64
  i = 0 ## i64
  while i < h
    o = ((y + i) * ds + x) ## i64
    j = 0 ## i64
    while j < w
      v = p[i * w + j] ## i64
      v = 0 if v < 0
      v = mx if v > mx
      m = 0 ## i64
      if pass == 0
        m = mask[moff + i]
      else
        m = mask[moff + j]
      d = dst[o + j] ## i64
      dst[o + j] = (m * d + (64 - m) * v + 32) >> 6
      j += 1
    i += 1
  0

# resolve divisor (7.11.3.7): returns divShift, stores divFactor in out[0]
-> av1_resolve_div(d, lut, out) (i64 i32[] i64[]) i64
  a = (d < 0 ? 0 - d : d) ## i64
  n = 0 ## i64
  t = (a) ## i64
  while t > 1
    t = t >> 1
    n += 1
  e = 0 ## i64
  e = a - (1 << n)
  f = 0 ## i64
  if n > 8
    f = (e + (1 << (n - 9))) >> (n - 8)
  else
    f = e << (8 - n)
  fac = lut[f] ## i64
  if d < 0
    fac = 0 - fac
  out[0] = fac
  n + 14

-> av1_r2s(x, n) (i64 i64) i64
  if n == 0
    return x
  r = 0 ## i64
  r = (1 << n) >> 1
  if x >= 0
    return (x + r) >> n
  0 - ((0 - x + r) >> n)

# setup shear (7.11.3.6): out = [alpha, beta, gamma, delta]; returns warpValid
-> av1_setup_shear(p, lut, out) (i64[] i32[] i64[]) i64
  a0 = (p[2] - 65536) ## i64
  a0 = -32768 if a0 < -32768
  a0 = 32767 if a0 > 32767
  b0 = (p[3]) ## i64
  b0 = -32768 if b0 < -32768
  b0 = 32767 if b0 > 32767
  ds = (av1_resolve_div(p[2], lut, out)) ## i64
  df = (out[0]) ## i64
  v = (p[4] * 65536) ## i64
  g0 = (av1_r2s(v * df, ds)) ## i64
  g0 = -32768 if g0 < -32768
  g0 = 32767 if g0 > 32767
  w = (p[3] * p[4]) ## i64
  d0 = (p[5] - av1_r2s(w * df, ds) - 65536) ## i64
  d0 = -32768 if d0 < -32768
  d0 = 32767 if d0 > 32767
  al = (av1_r2s(a0, 6) * 64) ## i64
  be = (av1_r2s(b0, 6) * 64) ## i64
  ga = (av1_r2s(g0, 6) * 64) ## i64
  de = (av1_r2s(d0, 6) * 64) ## i64
  out[0] = al
  out[1] = be
  out[2] = ga
  out[3] = de
  aa = (al < 0 ? 0 - al : al) ## i64
  ab = (be < 0 ? 0 - be : be) ## i64
  ag = (ga < 0 ? 0 - ga : ga) ## i64
  ad = (de < 0 ? 0 - de : de) ## i64
  if 4 * aa + 7 * ab >= 65536
    return 0
  if 4 * ag + 4 * ad >= 65536
    return 0
  1

-> av1_ls_product(a, b) (i64 i64) i64
  ((a * b) >> 2) + (a + b)

# warp estimation (7.11.3.8): least squares fit into lwp; returns LocalValid
-> av1_warp_est(cl, ns, mv0, mv1, mid_y, mid_x, lut, lwp) (i32[] i64 i64 i64 i64 i64 i32[] i64[]) i64
  a00 = 0 ## i64
  a01 = 0 ## i64
  a11 = 0 ## i64
  bx0 = 0 ## i64
  bx1 = 0 ## i64
  by0 = 0 ## i64
  by1 = 0 ## i64
  suy = (mid_y * 8) ## i64
  sux = (mid_x * 8) ## i64
  duy = (suy + mv0) ## i64
  dux = (sux + mv1) ## i64
  i = 0 ## i64
  while i < ns
    c0 = cl[i * 4] ## i64
    c1 = cl[i * 4 + 1] ## i64
    c2 = cl[i * 4 + 2] ## i64
    c3 = cl[i * 4 + 3] ## i64
    sy = (c0 - suy) ## i64
    sx = (c1 - sux) ## i64
    dy = (c2 - duy) ## i64
    dx = (c3 - dux) ## i64
    e1 = (sx - dx) ## i64
    e1 = 0 - e1 if e1 < 0
    e2 = (sy - dy) ## i64
    e2 = 0 - e2 if e2 < 0
    if e1 < 256 && e2 < 256
      a00 += av1_ls_product(sx, sx) + 8
      a01 += av1_ls_product(sx, sy) + 4
      a11 += av1_ls_product(sy, sy) + 8
      bx0 += av1_ls_product(sx, dx) + 8
      bx1 += av1_ls_product(sy, dx) + 4
      by0 += av1_ls_product(sx, dy) + 4
      by1 += av1_ls_product(sy, dy) + 8
    i += 1
  det = (a00 * a11 - a01 * a01) ## i64
  if det == 0
    return 0
  tmp = i64[1]
  ds = (av1_resolve_div(det, lut, tmp)) ## i64
  df = (tmp[0]) ## i64
  ds -= 16
  if ds < 0
    df = df << (0 - ds)
    ds = 0
  lwp[2] = av1_warp_diag(a11 * bx0 - a01 * bx1, df, ds)
  lwp[3] = av1_warp_nondiag(0 - a01 * bx0 + a00 * bx1, df, ds)
  lwp[4] = av1_warp_nondiag(a11 * by0 - a01 * by1, df, ds)
  lwp[5] = av1_warp_diag(0 - a01 * by0 + a00 * by1, df, ds)
  vx = (mv1 * 8192 - (mid_x * (lwp[2] - 65536) + mid_y * lwp[3])) ## i64
  vy = (mv0 * 8192 - (mid_x * lwp[4] + mid_y * (lwp[5] - 65536))) ## i64
  cl8 = (8388608) ## i64
  vx = 0 - cl8 if vx < 0 - cl8
  vx = cl8 - 1 if vx > cl8 - 1
  vy = 0 - cl8 if vy < 0 - cl8
  vy = cl8 - 1 if vy > cl8 - 1
  lwp[0] = vx
  lwp[1] = vy
  1

-> av1_warp_nondiag(v, df, ds) (i64 i64 i64) i64
  r = (av1_r2s(v * df, ds)) ## i64
  r = -8191 if r < -8191
  r = 8191 if r > 8191
  r

-> av1_warp_diag(v, df, ds) (i64 i64 i64) i64
  r = (av1_r2s(v * df, ds)) ## i64
  r = 57345 if r < 57345
  r = 73727 if r > 73727
  r

# block warp (7.11.3.5) over all 8x8 sub-blocks of a w x h block
-> av1_warp_block(ref, stride, lastx, lasty, sx, sy, x, y, w, h, p, sh, r0, r1, wf, tmp, out) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64 i64 i32[] i32[] i32[]) i64
  al = (sh[0]) ## i64
  be = (sh[1]) ## i64
  ga = (sh[2]) ## i64
  de = (sh[3]) ## i64
  h1 = 0 ## i64
  h1 = (1 << r0) >> 1
  h2 = 0 ## i64
  h2 = (1 << r1) >> 1
  i8 = 0 ## i64
  while i8 * 8 < h
    j8 = 0 ## i64
    while j8 * 8 < w
      srcx = 0 ## i64
      srcx = (x + j8 * 8 + 4) << sx
      srcy = 0 ## i64
      srcy = (y + i8 * 8 + 4) << sy
      dstx = (p[2] * srcx + p[3] * srcy + p[0]) ## i64
      dsty = (p[4] * srcx + p[5] * srcy + p[1]) ## i64
      x4 = (dstx >> sx) ## i64
      y4 = (dsty >> sy) ## i64
      ix4 = (x4 >> 16) ## i64
      sx4 = (x4 & 65535) ## i64
      iy4 = (y4 >> 16) ## i64
      sy4 = (y4 & 65535) ## i64
      i1 = -7 ## i64
      while i1 < 8
        yy = (iy4 + i1) ## i64
        yy = 0 if yy < 0
        yy = lasty if yy > lasty
        ro = (yy * stride) ## i64
        i2 = -4 ## i64
        while i2 < 4
          sxx = (sx4 + al * i2 + be * i1) ## i64
          offs = (((sxx + 512) >> 10) + 64) ## i64
          s = 0 ## i64
          i3 = 0 ## i64
          while i3 < 8
            xx = (ix4 + i2 - 3 + i3) ## i64
            xx = 0 if xx < 0
            xx = lastx if xx > lastx
            f = wf[offs * 8 + i3] ## i64
            v = ref[ro + xx] ## i64
            s += f * v
            i3 += 1
          tmp[(i1 + 7) * 8 + i2 + 4] = (s + h1) >> r0
          i2 += 1
        i1 += 1
      lh = (h - i8 * 8 - 4) ## i64
      lh = 4 if lh > 4
      lw = (w - j8 * 8 - 4) ## i64
      lw = 4 if lw > 4
      i1 = -4
      while i1 < lh
        i2 = -4 ## i64
        while i2 < lw
          syy = (sy4 + ga * i2 + de * i1) ## i64
          offs = ((syy + 512) >> 10) + 64
          s = 0 ## i64
          i3 = 0 ## i64
          while i3 < 8
            f = wf[offs * 8 + i3] ## i64
            v = tmp[(i1 + i3 + 4) * 8 + i2 + 4] ## i64
            s += f * v
            i3 += 1
          out[(i8 * 8 + i1 + 4) * w + j8 * 8 + i2 + 4] = (s + h2) >> r1
          i2 += 1
        i1 += 1
      j8 += 1
    i8 += 1
  0
