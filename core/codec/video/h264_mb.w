# core/codec/video/h264_mb — H.264 slice data and macroblock layer: parsing (CAVLC and
# CABAC), intra prediction, motion vector prediction, direct modes, motion
# compensation and residual reconstruction (7.3.4-7.3.5, 8.3, 8.4, 8.5).
# Methods of H264Dec.
#
# Per-picture state lives in raster arrays: per macroblock (@mbinfo, @qp_tab,
# @cbp_tab, …) and per 4x4 luma block over the whole picture (@nnz, @i4m,
# @mvd, @dir, and the picture's mv/refi/rid). @slice_tab holds a unique slice
# number per MB, so availability is "same slice number".

use h264_dsp

+ H264Dec
  -> mb_addr_of(gx, gy) (i64 i64) i64
    (gy >> 2) * @mbw + (gx >> 2)

  -> avail_mb(a) (i64) i64
    @slice_tab[a] == @slice_num ? 1 : 0

  # Availability of the 4x4 block at global (gx, gy) as a neighbour of the
  # partition whose first block is local (cbx, cby) in the current MB.
  -> blk_avail(gx, gy, cbx, cby) (i64 i64 i64 i64) i64
    return 0 if gx < 0 || gy < 0 || gx >= @w4
    mx = gx >> 2
    my = gy >> 2
    if mx == @mbx && my == @mby
      return @zidx[(gy & 3) * 4 + (gx & 3)] < @zidx[cby * 4 + cbx] ? 1 : 0
    return 0 if my > @mby || (my == @mby && mx > @mbx)
    avail_mb(my * @mbw + mx)

  # Availability for intra sample prediction (constrained_intra_pred aware).
  -> ip_avail(gx, gy, cbx, cby) (i64 i64 i64 i64) i64
    return 0 if blk_avail(gx, gy, cbx, cby) == 0
    return 1 if @constrained == 0
    (@mbinfo[(gy >> 2) * @mbw + (gx >> 2)] & 1) == 1 ? 1 : 0

  # ------------------------------------------------------------ slice data

  -> decode_slice_data(sl, rblen)
    rb = @sb
    e = rblen - 1
    while e >= 0 && rb[e] == 0
      e -= 1
    stop = 0
    if e >= 0
      v = rb[e]
      t = 0
      while (v & 1) == 0
        v = v >> 1
        t += 1
      stop = e * 8 + 7 - t
    @sstop = stop
    @sp = sl.data_bit_pos
    @stype = sl.p? ? 0 : (sl.b? ? 1 : 2)
    @cabac = @pps.cabac
    @qp = sl.qp
    @dbk_idc = sl.dbk_idc
    @alpha_off = sl.alpha_off
    @beta_off = sl.beta_off
    @cqp0 = @pps.cqp_off
    @cqp1 = @pps.cqp_off2
    @constrained = @pps.constrained_intra
    @t8mode = @pps.transform8x8
    @direct_spatial = sl.direct_spatial
    @direct8x8 = @sps.direct8x8
    @col = nil
    @col_short = 1
    if @stype == 1
      @col = @ref_list[1][0]
      @col_short = @col.ref == 2 ? 0 : 1
      @col_mv = @col.mv
      @col_refi = @col.refi
      @col_rid = @col.rid
    @last_dqp = 0
    mb = sl.first_mb
    if @cabac == 1
      @sp = (@sp + 7) & (0 - 8)
      cabac_init_slice(@qp, @stype == 2 ? 1 : 0, sl.cabac_init)
      cabac_start(@sp >> 3)
    skip_run = -1
    guard = 0
    while mb < @nmb
      set_mb(mb)
      if @stype != 2 && @cabac == 0
        skip_run = rb_ue if skip_run < 0
        if skip_run > 0
          decode_skip
          skip_run -= 1
          mb = next_mb(mb)
          break if skip_run == 0 && rb_more == 0
          next
        skip_run = -1
        decode_mb
        mb = next_mb(mb)
        break if rb_more == 0
      elsif @stype != 2
        ca = (@mba >= 0 && (@mbinfo[@mba] & 2) == 0) ? 1 : 0
        cb = (@mbb >= 0 && (@mbinfo[@mbb] & 2) == 0) ? 1 : 0
        if cb_skip(ca, cb) == 1
          decode_skip
          @last_dqp = 0
        else
          decode_mb
        mb = next_mb(mb)
        break if dec_term == 1
      else
        decode_mb
        mb = next_mb(mb)
        if @cabac == 1
          break if dec_term == 1
        else
          break if rb_more == 0
    0

  -> next_mb(mb)
    return mb + 1 if @mbmap == nil || @pps.num_slice_groups <= 1
    g = @mbmap[mb]
    n = mb + 1
    while n < @nmb && @mbmap[n] != g
      n += 1
    n

  -> set_mb(mb) (i64) i64
    @mb = mb
    @mbx = mb % @mbw
    @mby = mb / @mbw
    if @dbk_thread != nil
      @dbk_ooo = 1 if mb != @expect_mb
      @expect_mb = mb + 1
      @dbk_prog.store(@mby) if @mbx == 0
    @slice_tab[mb] = @slice_num
    @mba = (@mbx > 0 && @slice_tab[mb - 1] == @slice_num) ? mb - 1 : -1
    @mbb = (@mby > 0 && @slice_tab[mb - @mbw] == @slice_num) ? mb - @mbw : -1
    @gx0 = @mbx * 4
    @gy0 = @mby * 4
    0

  # Clear the per-4x4 state of the current MB that later blocks may read.
  -> clear_mb_state(inter) (i64) i64
    y = 0 ## i64
    w4 = @w4
    while y < 4
      x = 0 ## i64
      i = (@gy0 + y) * w4 + @gx0
      while x < 4
        @nnz[i + x] = 0
        @dir[i + x] = 0
        k = (i + x) * 4
        @mvd[k] = 0
        @mvd[k + 1] = 0
        @mvd[k + 2] = 0
        @mvd[k + 3] = 0
        @i4m[i + x] = inter == 1 ? -2 : -1
        x += 1
      y += 1
    if @cfmt != 0
      rows = @mbch / 4
      c = 0 ## i64
      while c < 2
        base = c * @cw4 * @ch4
        y = 0
        while y < rows
          x = 0
          while x < 2
            @nnzc[base + (@mby * rows + y) * @cw4 + @mbx * 2 + x] = 0
            x += 1
          y += 1
        c += 1
    0

  # Set ref/mv for the 4x4 blocks of a region (local coords, 4x4 units).
  -> set_motion(bx, by, bw, bh, l, r, mx, my) (i64 i64 i64 i64 i64 i64 i64 i64) i64
    rid = -1 ## i64
    rid = @rid_l[l * 32 + r] if r >= 0
    y = 0 ## i64
    while y < bh
      x = 0 ## i64
      i = (@gy0 + by + y) * @w4 + @gx0 + bx
      while x < bw
        j = i + x
        @cur_ref[j * 2 + l] = r
        @cur_rid[j * 2 + l] = rid
        @cur_mv[j * 4 + l * 2] = mx
        @cur_mv[j * 4 + l * 2 + 1] = my
        x += 1
      y += 1
    0

  -> set_mvd(bx, by, bw, bh, l, dx, dy) (i64 i64 i64 i64 i64 i64 i64) i64
    ax = dx < 0 ? 0 - dx : dx
    ay = dy < 0 ? 0 - dy : dy
    ax = 70 if ax > 70
    ay = 70 if ay > 70
    y = 0 ## i64
    while y < bh
      x = 0 ## i64
      i = (@gy0 + by + y) * @w4 + @gx0 + bx
      while x < bw
        @mvd[(i + x) * 4 + l * 2] = ax
        @mvd[(i + x) * 4 + l * 2 + 1] = ay
        x += 1
      y += 1
    0

  # Intra MB: refs -1, mvs 0 in both lists.
  -> set_intra_motion (i64) i64
    y = 0 ## i64
    while y < 4
      x = 0 ## i64
      i = (@gy0 + y) * @w4 + @gx0
      while x < 4
        j = i + x
        @cur_ref[j * 2] = -1
        @cur_ref[j * 2 + 1] = -1
        @cur_rid[j * 2] = -1
        @cur_rid[j * 2 + 1] = -1
        @cur_mv[j * 4] = 0
        @cur_mv[j * 4 + 1] = 0
        @cur_mv[j * 4 + 2] = 0
        @cur_mv[j * 4 + 3] = 0
        x += 1
      y += 1
    0

  # --------------------------------------------------------- MV prediction

  # Neighbour fetch into @nr/@nmx/@nmy; returns availability.
  -> nbr(l, gx, gy, cbx, cby) (i64 i64 i64 i64 i64) i64
    if blk_avail(gx, gy, cbx, cby) == 0
      @nr = -1
      @nmx = 0
      @nmy = 0
      return 0
    j = gy * @w4 + gx
    @nr = @cur_ref[j * 2 + l]
    if @nr < 0
      @nmx = 0
      @nmy = 0
    else
      @nmx = @cur_mv[j * 4 + l * 2]
      @nmy = @cur_mv[j * 4 + l * 2 + 1]
    1

  # 8.4.1.3: predicted mv for a partition (local 4x4 coords bx,by size bw x
  # bh) in list l with reference r. shape 1 = 16x8, 2 = 8x16; part 0/1.
  -> mvpred(l, bx, by, bw, bh, r, shape, part) (i64 i64 i64 i64 i64 i64 i64 i64) i64
    gx = @gx0 + bx
    gy = @gy0 + by
    ava = nbr(l, gx - 1, gy, bx, by)
    ra = @nr
    ax = @nmx
    ay = @nmy
    avb = nbr(l, gx, gy - 1, bx, by)
    rb = @nr
    bxv = @nmx
    byv = @nmy
    avc = nbr(l, gx + bw, gy - 1, bx, by)
    if avc == 0
      avc = nbr(l, gx - 1, gy - 1, bx, by)
    rc = @nr
    cx = @nmx
    cy = @nmy
    if shape == 1
      if part == 0 && rb == r
        @pmx = bxv
        @pmy = byv
        return 0
      if part == 1 && ra == r
        @pmx = ax
        @pmy = ay
        return 0
    elsif shape == 2
      if part == 0 && ra == r
        @pmx = ax
        @pmy = ay
        return 0
      if part == 1 && rc == r
        @pmx = cx
        @pmy = cy
        return 0
    if avb == 0 && avc == 0 && ava == 1
      rb = ra
      rc = ra
      bxv = ax
      byv = ay
      cx = ax
      cy = ay
    m = 0 ## i64
    m += 1 if ra == r
    m += 1 if rb == r
    m += 1 if rc == r
    if m == 1
      if ra == r
        @pmx = ax
        @pmy = ay
      elsif rb == r
        @pmx = bxv
        @pmy = byv
      else
        @pmx = cx
        @pmy = cy
      return 0
    @pmx = h264_median(ax, bxv, cx)
    @pmy = h264_median(ay, byv, cy)
    0

  -> pskip_mv (i64) i64
    gx = @gx0
    gy = @gy0
    ava = nbr(0, gx - 1, gy, 0, 0)
    ra = @nr
    ax = @nmx
    ay = @nmy
    avb = nbr(0, gx, gy - 1, 0, 0)
    rb = @nr
    bxv = @nmx
    byv = @nmy
    if ava == 0 || avb == 0 || (ra == 0 && ax == 0 && ay == 0) || (rb == 0 && bxv == 0 && byv == 0)
      @pmx = 0
      @pmy = 0
      return 0
    mvpred(0, 0, 0, 4, 4, 0, 0, 0)

  # ---------------------------------------------------------------- direct

  # Spatial direct: MB-level reference indices and mv predictors.
  -> direct_spatial_setup (i64) i64
    l = 0 ## i64
    while l < 2
      gx = @gx0
      gy = @gy0
      nbr(l, gx - 1, gy, 0, 0)
      ra = @nr
      nbr(l, gx, gy - 1, 0, 0)
      rb = @nr
      if nbr(l, gx + 4, gy - 1, 0, 0) == 0
        nbr(l, gx - 1, gy - 1, 0, 0)
      rc = @nr
      r = h264_minpos(ra, h264_minpos(rb, rc))
      @dir_ref[l] = r
      l += 1
    if @dir_ref[0] < 0 && @dir_ref[1] < 0
      @dir_ref[0] = 0
      @dir_ref[1] = 0
      @dir_mv[0] = 0
      @dir_mv[1] = 0
      @dir_mv[2] = 0
      @dir_mv[3] = 0
      @dir_zero = 1
      return 0
    @dir_zero = 0
    l = 0
    while l < 2
      if @dir_ref[l] >= 0
        mvpred(l, 0, 0, 4, 4, @dir_ref[l], 0, 0)
        @dir_mv[l * 2] = @pmx
        @dir_mv[l * 2 + 1] = @pmy
      else
        @dir_mv[l * 2] = 0
        @dir_mv[l * 2 + 1] = 0
      l += 1
    0

  # Direct prediction for the 8x8 blocks set in mask (bit b8).
  -> direct_pred(mask) (i64) i64
    direct_spatial_setup if @direct_spatial == 1
    b8 = 0 ## i64
    while b8 < 4
      if ((mask >> b8) & 1) == 1
        bx0 = (b8 & 1) * 2
        by0 = (b8 >> 1) * 2
        if @direct8x8 == 1
          cx = (b8 & 1) * 3
          cy = (b8 >> 1) * 3
          direct_block(bx0, by0, 2, cx, cy)
        else
          k = 0 ## i64
          while k < 4
            direct_block(bx0 + (k & 1), by0 + (k >> 1), 1, bx0 + (k & 1), by0 + (k >> 1))
            k += 1
        y = 0 ## i64
        while y < 2
          x = 0 ## i64
          while x < 2
            @dir[(@gy0 + by0 + y) * @w4 + @gx0 + bx0 + x] = 1
            x += 1
          y += 1
      b8 += 1
    0

  # Derive direct motion for a size x size (4x4 units) block at local (bx,by)
  # from the co-located block at local (cx, cy).
  -> direct_block(bx, by, size, cx, cy) (i64 i64 i64 i64 i64) i64
    ci = (@gy0 + cy) * @w4 + @gx0 + cx
    colr = @col_refi ## i32[]
    colm = @col_mv ## i32[]
    colid = @col_rid ## i32[]
    cr0 = colr[ci * 2]
    cr1 = colr[ci * 2 + 1]
    colref = -1 ## i64
    cmx = 0 ## i64
    cmy = 0 ## i64
    crid = -1 ## i64
    if cr0 >= 0
      colref = cr0
      cmx = colm[ci * 4]
      cmy = colm[ci * 4 + 1]
      crid = colid[ci * 2]
    elsif cr1 >= 0
      colref = cr1
      cmx = colm[ci * 4 + 2]
      cmy = colm[ci * 4 + 3]
      crid = colid[ci * 2 + 1]
    if @direct_spatial == 1
      r0 = @dir_ref[0]
      r1 = @dir_ref[1]
      m0x = @dir_mv[0]
      m0y = @dir_mv[1]
      m1x = @dir_mv[2]
      m1y = @dir_mv[3]
      if @dir_zero == 0 && @col_short == 1 && colref == 0 && cmx >= -1 && cmx <= 1 && cmy >= -1 && cmy <= 1
        if r0 == 0
          m0x = 0
          m0y = 0
        if r1 == 0
          m1x = 0
          m1y = 0
      set_motion(bx, by, size, size, 0, r0, r0 >= 0 ? m0x : 0, r0 >= 0 ? m0y : 0)
      set_motion(bx, by, size, size, 1, r1, r1 >= 0 ? m1x : 0, r1 >= 0 ? m1y : 0)
    else
      r0 = 0 ## i64
      if colref >= 0
        k = 0 ## i64
        found = -1 ## i64
        while k < @nref0 && found < 0
          found = k if @rid_l[k] == crid
          k += 1
        r0 = found >= 0 ? found : 0
      dsf = @dsf_tab[r0]
      m0x = cmx
      m0y = cmy
      m1x = 0 ## i64
      m1y = 0 ## i64
      if dsf != 9999
        m0x = (dsf * cmx + 128) >> 8
        m0y = (dsf * cmy + 128) >> 8
        m1x = m0x - cmx
        m1y = m0y - cmy
      set_motion(bx, by, size, size, 0, r0, m0x, m0y)
      set_motion(bx, by, size, size, 1, 0, m1x, m1y)
    0

  # ------------------------------------------------------------- skip MBs

  -> decode_skip (i64) i64
    mb = @mb
    clear_mb_state(1)
    if @stype == 0
      pskip_mv
      set_motion(0, 0, 4, 4, 0, 0, @pmx, @pmy)
      set_motion(0, 0, 4, 4, 1, -1, 0, 0)
      mc_block(0, 0, 4, 4)
      @mbinfo[mb] = 2
    else
      direct_pred(15)
      mc_direct(15)
      @mbinfo[mb] = 2 | 64
    @qp_tab[mb] = @qp
    @qpc_tab[mb * 2] = chroma_qp(@qp, @cqp0)
    @qpc_tab[mb * 2 + 1] = chroma_qp(@qp, @cqp1)
    @cbp_tab[mb] = 0
    @cbf_tab[mb] = 0
    @cpm_tab[mb] = 0
    @nzmask[mb] = 0
    store_dbk(mb)
    0

  -> store_dbk(mb) (i64) i64
    @dbk_tab[mb * 3] = @dbk_idc
    @dbk_tab[mb * 3 + 1] = @alpha_off
    @dbk_tab[mb * 3 + 2] = @beta_off
    0

  -> chroma_qp(qp, off) (i64 i64) i64
    @qpc_tab_c[h264_clip3(0, 51, qp + off)]

  # ------------------------------------------------------- macroblock layer

  -> decode_mb (i64) i64
    mb = @mb
    raw = 0 ## i64
    if @cabac == 1
      if @stype == 2
        inc = 0 ## i64
        inc += 1 if @mba >= 0 && (@mbinfo[@mba] & 8) == 0
        inc += 1 if @mbb >= 0 && (@mbinfo[@mbb] & 8) == 0
        raw = cb_mb_type_i(3, inc, 0)
      elsif @stype == 0
        raw = cb_mb_type_p
      else
        inc = 0 ## i64
        inc += 1 if @mba >= 0 && (@mbinfo[@mba] & 66) == 0
        inc += 1 if @mbb >= 0 && (@mbinfo[@mbb] & 66) == 0
        raw = cb_mb_type_b(inc)
    else
      raw = rb_ue
    it = -1 ## i64
    if @stype == 2
      it = raw
    elsif @stype == 0
      it = raw - 5 if raw >= 5
    else
      it = raw - 23 if raw >= 23
    << "mb [mb] raw=[raw] qp=[@qp] sp=[@sp]" if @dbg == 1
    if it >= 0
      decode_intra(it)
    else
      decode_inter(raw)
    0

  # ---------------------------------------------------------------- intra

  -> pred_mode_nxn(gx, gy) (i64 i64) i64
    a = -3 ## i64
    b = -3 ## i64
    if gx > 0 && avail_mb(mb_addr_of(gx - 1, gy)) == 1
      a = @i4m[gy * @w4 + gx - 1]
    if gy > 0 && avail_mb(mb_addr_of(gx, gy - 1)) == 1
      b = @i4m[(gy - 1) * @w4 + gx]
    return 2 if a == -3 || b == -3
    return 2 if @constrained == 1 && (a == -2 || b == -2)
    a = 2 if a < 0
    b = 2 if b < 0
    a < b ? a : b

  -> decode_intra(it) (i64) i64
    mb = @mb
    clear_mb_state(0)
    set_intra_motion
    @mbinfo[mb] = 1
    if it == 25
      decode_pcm
      return 0
    t8 = 0 ## i64
    i16 = it >= 1 ? 1 : 0
    cbp = 0 ## i64
    i16mode = 0 ## i64
    if i16 == 1
      i16mode = (it - 1) % 4
      cbp = (((it - 1) / 4) % 3) << 4
      cbp = cbp | 15 if it >= 13
      @mbinfo[mb] = 1 | 4
    else
      @mbinfo[mb] = 1 | 8
      if @t8mode == 1
        if @cabac == 1
          inc = 0 ## i64
          inc += 1 if @mba >= 0 && (@mbinfo[@mba] & 32) != 0
          inc += 1 if @mbb >= 0 && (@mbinfo[@mbb] & 32) != 0
          t8 = cb_t8(inc)
        else
          t8 = rb_u(1)
      if t8 == 1
        @mbinfo[mb] = 1 | 8 | 32
        b8 = 0 ## i64
        while b8 < 4
          bx = (b8 & 1) * 2
          by = (b8 >> 1) * 2
          gx = @gx0 + bx
          gy = @gy0 + by
          pm = pred_mode_nxn(gx, gy)
          m = read_i4mode
          mode = pm
          if m >= 0
            mode = m < pm ? m : m + 1
          @i4m[gy * @w4 + gx] = mode
          @i4m[gy * @w4 + gx + 1] = mode
          @i4m[(gy + 1) * @w4 + gx] = mode
          @i4m[(gy + 1) * @w4 + gx + 1] = mode
          b8 += 1
      else
        blk = 0 ## i64
        while blk < 16
          gx = @gx0 + @blkx[blk]
          gy = @gy0 + @blky[blk]
          pm = pred_mode_nxn(gx, gy)
          m = read_i4mode
          mode = pm
          if m >= 0
            mode = m < pm ? m : m + 1
          @i4m[gy * @w4 + gx] = mode
          blk += 1
    cpm = 0 ## i64
    if @cfmt != 0
      if @cabac == 1
        inc = 0 ## i64
        inc += 1 if @mba >= 0 && (@mbinfo[@mba] & 17) == 1 && @cpm_tab[@mba] != 0
        inc += 1 if @mbb >= 0 && (@mbinfo[@mbb] & 17) == 1 && @cpm_tab[@mbb] != 0
        cpm = cb_cpm(inc)
      else
        cpm = rb_ue
    @cpm_tab[mb] = cpm
    if i16 == 0
      cbp = read_cbp(1)
    @cbp_tab[mb] = cbp
    read_qp_and_residual(cbp, i16, t8, 1)
    # reconstruction
    if i16 == 1
      recon_i16(i16mode)
    elsif t8 == 1
      recon_i8
    else
      recon_i4
    recon_chroma_intra(cpm) if @cfmt != 0
    recon_chroma_residual(cbp) if @cfmt != 0
    store_dbk(mb)
    0

  -> read_i4mode (i64) i64
    if @cabac == 1
      return cb_i4mode
    return -1 if rb_u(1) == 1
    rb_u(3)

  -> decode_pcm (i64) i64
    mb = @mb
    p = 0 ## i64
    if @cabac == 1
      p = cabac_pcm_pos
    else
      @sp = (@sp + 7) & (0 - 8)
      p = @sp >> 3
    b = @sb
    y = 0 ## i64
    while y < 16
      x = 0 ## i64
      o = (@mby * 16 + y) * @lw + @mbx * 16
      while x < 16
        @cur_y[o + x] = b[p]
        p += 1
        x += 1
      y += 1
    if @cfmt != 0
      c = 0 ## i64
      while c < 2
        pl = c == 0 ? @cur_cb : @cur_cr
        y = 0
        while y < @mbch
          x = 0
          o = (@mby * @mbch + y) * @cw + @mbx * 8
          while x < 8
            pl[o + x] = b[p]
            p += 1
            x += 1
          y += 1
        c += 1
    if @cabac == 1
      cabac_start(p)
    else
      @sp = p * 8
    @mbinfo[mb] = 1 | 16
    @qp_tab[mb] = 0
    @qpc_tab[mb * 2] = chroma_qp(0, @cqp0)
    @qpc_tab[mb * 2 + 1] = chroma_qp(0, @cqp1)
    @cbp_tab[mb] = 0x2F
    @cbf_tab[mb] = 7
    @cpm_tab[mb] = 0
    @nzmask[mb] = 0xFFFF
    @last_dqp = 0
    y = 0
    while y < 4
      x = 0
      while x < 4
        @nnz[(@gy0 + y) * @w4 + @gx0 + x] = 16
        x += 1
      y += 1
    if @cfmt != 0
      rows = @mbch / 4
      c = 0
      while c < 2
        base = c * @cw4 * @ch4
        y = 0
        while y < rows
          x = 0
          while x < 2
            @nnzc[base + (@mby * rows + y) * @cw4 + @mbx * 2 + x] = 16
            x += 1
          y += 1
        c += 1
    store_dbk(mb)
    0

  -> read_cbp(intra) (i64) i64
    if @cabac == 0
      k = rb_ue
      if @cfmt == 0 || @cfmt == 3
        # Table 9-4 columns for monochrome / 4:4:4
        return h264_cbp_mono(k, intra)
      return intra == 1 ? @i4cbp[k] : @intercbp[k]
    luma = 0 ## i64
    b8 = 0 ## i64
    while b8 < 4
      ca = 0 ## i64
      cb = 0 ## i64
      if (b8 & 1) == 0
        if @mba >= 0
          ca = ((@cbp_tab[@mba] >> (b8 + 1)) & 1) == 0 ? 1 : 0
      else
        ca = ((luma >> (b8 - 1)) & 1) == 0 ? 1 : 0
      if b8 < 2
        if @mbb >= 0
          cb = ((@cbp_tab[@mbb] >> (b8 + 2)) & 1) == 0 ? 1 : 0
      else
        cb = ((luma >> (b8 - 2)) & 1) == 0 ? 1 : 0
      luma = luma | (dec(73 + ca + 2 * cb) << b8)
      b8 += 1
    chroma = 0 ## i64
    if @cfmt == 1 || @cfmt == 2
      ca = (@mba >= 0 && (@cbp_tab[@mba] >> 4) != 0) ? 1 : 0
      cb = (@mbb >= 0 && (@cbp_tab[@mbb] >> 4) != 0) ? 1 : 0
      if dec(77 + ca + 2 * cb) == 1
        ca = (@mba >= 0 && (@cbp_tab[@mba] >> 4) == 2) ? 1 : 0
        cb = (@mbb >= 0 && (@cbp_tab[@mbb] >> 4) == 2) ? 1 : 0
        chroma = 1 + dec(81 + ca + 2 * cb)
    luma | (chroma << 4)

  # mb_qp_delta (when coded) and residual().
  -> read_qp_and_residual(cbp, i16, t8, intra) (i64 i64 i64 i64) i64
    mb = @mb
    if cbp != 0 || i16 == 1
      dqp = 0 ## i64
      if @cabac == 1
        dqp = cb_dqp
      else
        dqp = rb_se
      @last_dqp = dqp
      @qp = ((@qp + dqp + 52) % 52 + 52) % 52
    else
      @last_dqp = 0
    @qp_tab[mb] = @qp
    @qpc_tab[mb * 2] = chroma_qp(@qp, @cqp0)
    @qpc_tab[mb * 2 + 1] = chroma_qp(@qp, @cqp1)
    residual(cbp, i16, t8, intra)
    0

  # coded_block_flag ctxIdxInc for luma 4x4 blocks (cat 1/2).
  -> cbf_luma(gx, gy, intra) (i64 i64 i64) i64
    ca = 0 ## i64
    cb = 0 ## i64
    if gx > 0 && ((gx & 3) != 0 || @mba >= 0)
      ca = @nnz[gy * @w4 + gx - 1] != 0 ? 1 : 0
    else
      ca = intra
    if gy > 0 && ((gy & 3) != 0 || @mbb >= 0)
      cb = @nnz[(gy - 1) * @w4 + gx] != 0 ? 1 : 0
    else
      cb = intra
    ca + 2 * cb

  -> cbf_chroma_ac(c, gx, gy, intra) (i64 i64 i64 i64) i64
    base = c * @cw4 * @ch4
    rows = @mbch / 4
    ca = 0 ## i64
    cb = 0 ## i64
    if gx > 0 && ((gx & 1) != 0 || @mba >= 0)
      ca = @nnzc[base + gy * @cw4 + gx - 1] != 0 ? 1 : 0
    else
      ca = intra
    if gy > 0 && ((gy % rows) != 0 || @mbb >= 0)
      cb = @nnzc[base + (gy - 1) * @cw4 + gx] != 0 ? 1 : 0
    else
      cb = intra
    ca + 2 * cb

  -> cbf_dc(bit, intra) (i64 i64) i64
    ca = intra
    cb = intra
    ca = (@cbf_tab[@mba] >> bit) & 1 if @mba >= 0
    cb = (@cbf_tab[@mbb] >> bit) & 1 if @mbb >= 0
    ca + 2 * cb

  # Place n decoded levels into coef[base + raster] with dequantisation.
  # kind 0: 4x4 (start = scan offset 0/1), 1: 8x8 CABAC, 2: 8x8 CAVLC
  # interleave i.
  -> place4(n, start, base, dqb) (i64 i64 i64 i64) i64
    k = 0 ## i64
    while k < n
      pos = @zz4[@cpos[k] + start]
      @coef[base + pos] = (@clev[k] * @dq4[dqb + pos] + 8) >> 4
      k += 1
    0

  -> place8(n, inter, base, dqb) (i64 i64 i64 i64) i64
    k = 0 ## i64
    while k < n
      pos = @zz8[@cpos[k] * inter + (inter == 4 ? base & 3 : 0)]
      @coef[(base & (0 - 4)) + pos] = (@clev[k] * @dq8[dqb + pos] + 32) >> 6
      k += 1
    0

  -> residual(cbp, i16, t8, intra) (i64 i64 i64 i64) i64
    mb = @mb
    qp = @qp
    ly = intra == 1 ? 0 : 3
    nzm = 0 ## i64
    cbf = 0 ## i64
    w4 = @w4
    if i16 == 1
      n = 0 ## i64
      if @cabac == 1
        n = cb_residual(0, 16, cbf_dc(0, 1))
      else
        n = cavlc_block(nc_luma(@gx0, @gy0), 16)
      dc = @dcb
      k = 0 ## i64
      while k < 16
        dc[k] = 0
        k += 1
      if n > 0
        cbf = cbf | 1
        k = 0
        while k < n
          dc[@zz4[@cpos[k]]] = @clev[k]
          k += 1
        h264_luma_dc(dc, @coef, @dq4[(ly * 52 + qp) * 16], @zidx)
      if (cbp & 15) != 0
        blk = 0 ## i64
        while blk < 16
          gx = @gx0 + @blkx[blk]
          gy = @gy0 + @blky[blk]
          n = 0
          if @cabac == 1
            n = cb_residual(1, 15, cbf_luma(gx, gy, 1))
          else
            n = cavlc_block(nc_luma(gx, gy), 15)
          @nnz[gy * w4 + gx] = n
          if n > 0
            place4(n, 1, blk * 16, (ly * 52 + qp) * 16)
            nzm = nzm | (1 << (@blky[blk] * 4 + @blkx[blk]))
          blk += 1
    else
      b8 = 0 ## i64
      while b8 < 4
        if ((cbp >> b8) & 1) == 1
          if t8 == 1
            dqb = ((intra == 1 ? 0 : 1) * 52 + qp) * 64
            any = 0 ## i64
            if @cabac == 1
              n = cb_residual(5, 64, 0)
              place8(n, 1, b8 * 64, dqb)
              any = n
              i = 0 ## i64
              while i < 4
                blk = b8 * 4 + i
                @nnz[(@gy0 + @blky[blk]) * w4 + @gx0 + @blkx[blk]] = n
                i += 1
            else
              i = 0 ## i64
              while i < 4
                blk = b8 * 4 + i
                gx = @gx0 + @blkx[blk]
                gy = @gy0 + @blky[blk]
                n = cavlc_block(nc_luma(gx, gy), 16)
                @nnz[gy * w4 + gx] = n
                place8(n, 4, b8 * 64 + i, dqb)
                any += n
                i += 1
            if any > 0
              bx = (b8 & 1) * 2
              by = (b8 >> 1) * 2
              nzm = nzm | (0x33 << (by * 4 + bx))
          else
            i = 0 ## i64
            while i < 4
              blk = b8 * 4 + i
              gx = @gx0 + @blkx[blk]
              gy = @gy0 + @blky[blk]
              n = 0 ## i64
              if @cabac == 1
                n = cb_residual(2, 16, cbf_luma(gx, gy, intra))
              else
                n = cavlc_block(nc_luma(gx, gy), 16)
              @nnz[gy * w4 + gx] = n
              if n > 0
                place4(n, 0, blk * 16, (ly * 52 + qp) * 16)
                nzm = nzm | (1 << (@blky[blk] * 4 + @blkx[blk]))
              i += 1
        b8 += 1
    # chroma
    cc = cbp >> 4
    if @cfmt != 0 && cc != 0
      nblk = @mbch == 16 ? 8 : 4
      c = 0 ## i64
      while c < 2
        n = 0 ## i64
        if @cabac == 1
          n = cb_residual(3, nblk, cbf_dc(1 + c, intra))
        else
          n = cavlc_block(nblk == 8 ? -2 : -1, nblk)
        if n > 0
          cbf = cbf | (2 << c)
          k = 0 ## i64
          while k < n
            p = @cpos[k]
            p = h264_c422_scan(p) if nblk == 8
            @coef[256 + c * 128 + p * 16] = @clev[k]
            k += 1
        c += 1
      if cc == 2
        rows = @mbch / 4
        c = 0
        while c < 2
          lst = (intra == 1 ? 1 : 4) + c
          qpc = @qpc_tab[mb * 2 + c]
          base = c * @cw4 * @ch4
          b = 0 ## i64
          while b < nblk
            gx = @mbx * 2 + (b & 1)
            gy = @mby * rows + (b >> 1)
            n = 0 ## i64
            if @cabac == 1
              n = cb_residual(4, 15, cbf_chroma_ac(c, gx, gy, intra))
            else
              n = cavlc_block(nc_chroma(c, gx, gy), 15)
            @nnzc[base + gy * @cw4 + gx] = n
            place4(n, 1, 256 + c * 128 + b * 16, (lst * 52 + qpc) * 16) if n > 0
            b += 1
          c += 1
    @cbf_tab[mb] = cbf
    @nzmask[mb] = nzm
    0

  # ------------------------------------------------------- reconstruction

  -> recon_i4 (i64) i64
    lw = @lw
    dst = @cur_y
    top = @top
    left = @left
    blk = 0 ## i64
    while blk < 16
      bx = @blkx[blk]
      by = @blky[blk]
      gx = @gx0 + bx
      gy = @gy0 + by
      d = gy * 4 * lw + gx * 4
      al = ip_avail(gx - 1, gy, bx, by)
      at = ip_avail(gx, gy - 1, bx, by)
      atr = ip_avail(gx + 1, gy - 1, bx, by)
      atl = ip_avail(gx - 1, gy - 1, bx, by)
      k = 0 ## i64
      if at == 1
        while k < 4
          top[k] = dst[d - lw + k]
          k += 1
        k = 4
        while k < 8
          top[k] = atr == 1 ? dst[d - lw + k] : top[3]
          k += 1
      k = 0
      if al == 1
        while k < 4
          left[k] = dst[d + k * lw - 1]
          k += 1
      tl = 128 ## i64
      tl = dst[d - lw - 1] if atl == 1
      mode = @i4m[gy * @w4 + gx]
      h264_pred_nxn(dst, d, lw, 4, mode, top, left, tl, al | (at << 1))
      h264_idct4_scratch(dst, d, lw, @coef, blk * 16, @idct_scratch) if @nnz[gy * @w4 + gx] > 0
      blk += 1
    0

  -> recon_i8 (i64) i64
    lw = @lw
    dst = @cur_y
    top = @top
    left = @left
    b8 = 0 ## i64
    while b8 < 4
      bx = (b8 & 1) * 2
      by = (b8 >> 1) * 2
      gx = @gx0 + bx
      gy = @gy0 + by
      d = gy * 4 * lw + gx * 4
      al = ip_avail(gx - 1, gy, bx, by)
      at = ip_avail(gx, gy - 1, bx, by)
      atr = ip_avail(gx + 2, gy - 1, bx, by)
      atl = ip_avail(gx - 1, gy - 1, bx, by)
      k = 0 ## i64
      if at == 1
        while k < 8
          top[k] = dst[d - lw + k]
          k += 1
        k = 8
        while k < 16
          top[k] = atr == 1 ? dst[d - lw + k] : top[7]
          k += 1
      k = 0
      if al == 1
        while k < 8
          left[k] = dst[d + k * lw - 1]
          k += 1
      tl = 128 ## i64
      tl = dst[d - lw - 1] if atl == 1
      ftl = h264_filter8(top, left, tl, al | (at << 1) | (atl << 2) | (atr << 3), @ft, @fl)
      mode = @i4m[gy * @w4 + gx]
      h264_pred_nxn(dst, d, lw, 8, mode, @ft, @fl, ftl, al | (at << 1))
      if ((@nzmask[@mb] >> (by * 4 + bx)) & 1) == 1
        h264_idct8_scratch(dst, d, lw, @coef, b8 * 64, @idct_scratch)
      else
        k = 0
        while k < 64
          @coef[b8 * 64 + k] = 0
          k += 1
      b8 += 1
    0

  -> recon_i16(mode) (i64) i64
    lw = @lw
    dst = @cur_y
    d = @mby * 16 * lw + @mbx * 16
    al = ip_avail(@gx0 - 1, @gy0, 0, 0)
    at = ip_avail(@gx0, @gy0 - 1, 0, 0)
    h264_pred16(dst, d, lw, mode, al | (at << 1))
    recon_luma_residual4(d)
    0

  -> recon_luma_residual4(d) (i64) i64
    lw = @lw
    dst = @cur_y
    blk = 0 ## i64
    while blk < 16
      bd = d + @blky[blk] * 4 * lw + @blkx[blk] * 4
      if @nnz[(@gy0 + @blky[blk]) * @w4 + @gx0 + @blkx[blk]] > 0
        h264_idct4_scratch(dst, bd, lw, @coef, blk * 16, @idct_scratch)
      elsif @coef[blk * 16] != 0
        h264_idct4_dc_add(dst, bd, lw, @coef, blk * 16)
      blk += 1
    0

  -> recon_chroma_intra(mode) (i64) i64
    cw = @cw
    d = @mby * @mbch * cw + @mbx * 8
    al = ip_avail(@gx0 - 1, @gy0, 0, 0)
    at = ip_avail(@gx0, @gy0 - 1, 0, 0)
    h264_pred_chroma(@cur_cb, d, cw, mode, al | (at << 1), 8, @mbch)
    h264_pred_chroma(@cur_cr, d, cw, mode, al | (at << 1), 8, @mbch)
    0

  -> recon_chroma_residual(cbp) (i64) i64
    return 0 if (cbp >> 4) == 0
    cw = @cw
    d = @mby * @mbch * cw + @mbx * 8
    nblk = @mbch == 16 ? 8 : 4
    rows = @mbch / 4
    intra = @mbinfo[@mb] & 1
    c = 0 ## i64
    while c < 2
      base = 256 + c * 128
      qpc = @qpc_tab[@mb * 2 + c]
      lst = (intra == 1 ? 1 : 4) + c
      if nblk == 4
        h264_chroma_dc(@coef, base, @dq4[(lst * 52 + qpc) * 16])
      else
        qdc = qpc + 3
        h264_chroma422_dc(@coef, base, qdc, @dq4[(lst * 52 + (qdc % 6)) * 16])
      dst = c == 0 ? @cur_cb : @cur_cr
      cb = c * @cw4 * @ch4
      b = 0 ## i64
      while b < nblk
        bd = d + (b >> 1) * 4 * cw + (b & 1) * 4
        gx = @mbx * 2 + (b & 1)
        gy = @mby * rows + (b >> 1)
        if @nnzc[cb + gy * @cw4 + gx] > 0
          h264_idct4_scratch(dst, bd, cw, @coef, base + b * 16, @idct_scratch)
        elsif @coef[base + b * 16] != 0
          h264_idct4_dc_add(dst, bd, cw, @coef, base + b * 16)
        b += 1
      c += 1
    0

  # ---------------------------------------------------------------- inter

  -> read_ref(l, bx, by) (i64 i64 i64) i64
    n = l == 0 ? @nref0 : @nref1
    return 0 if n <= 1
    if @cabac == 0
      return rb_te(n - 1)
    gx = @gx0 + bx
    gy = @gy0 + by
    ca = 0 ## i64
    cb = 0 ## i64
    if blk_avail(gx - 1, gy, bx, by) == 1
      j = gy * @w4 + gx - 1
      ca = 1 if @cur_ref[j * 2 + l] > 0 && @dir[j] == 0 && (@mbinfo[mb_addr_of(gx - 1, gy)] & 2) == 0
    if blk_avail(gx, gy - 1, bx, by) == 1
      j = (gy - 1) * @w4 + gx
      cb = 1 if @cur_ref[j * 2 + l] > 0 && @dir[j] == 0 && (@mbinfo[mb_addr_of(gx, gy - 1)] & 2) == 0
    rr = cb_ref(ca + 2 * cb)
    << "  ref_idx l[l] [rr] (ctx [ca + 2 * cb])" if @dbg == 1
    rr

  # Read an mvd pair and derive the mv for a partition (assumes the
  # partition's ref was already stored).
  -> read_mv(l, bx, by, bw, bh, shape, part) (i64 i64 i64 i64 i64 i64 i64) i64
    r = @cur_ref[((@gy0 + by) * @w4 + @gx0 + bx) * 2 + l]
    dx = 0 ## i64
    dy = 0 ## i64
    if @cabac == 1
      gx = @gx0 + bx
      gy = @gy0 + by
      sx = 0 ## i64
      sy = 0 ## i64
      if blk_avail(gx - 1, gy, bx, by) == 1
        j = (gy * @w4 + gx - 1) * 4 + l * 2
        sx += @mvd[j]
        sy += @mvd[j + 1]
      if blk_avail(gx, gy - 1, bx, by) == 1
        j = ((gy - 1) * @w4 + gx) * 4 + l * 2
        sx += @mvd[j]
        sy += @mvd[j + 1]
      dx = cb_mvd(0, sx)
      dy = cb_mvd(1, sy)
    else
      dx = rb_se
      dy = rb_se
    set_mvd(bx, by, bw, bh, l, dx, dy)
    << "  mvd l[l] blk([bx],[by]) [dx] [dy]" if @dbg == 1
    mvpred(l, bx, by, bw, bh, r, shape, part)
    set_motion(bx, by, bw, bh, l, r, @pmx + dx, @pmy + dy)
    0

  -> decode_inter(raw) (i64) i64
    mb = @mb
    clear_mb_state(1)
    @mbinfo[mb] = 0
    t8ok = 1 ## i64
    shape = 0 ## i64
    np = 1 ## i64
    is8 = 0 ## i64
    direct16 = 0 ## i64
    ref0 = 0 ## i64
    if @stype == 0
      if raw < 3
        shape = raw
        np = raw == 0 ? 1 : 2
        @pdir[0] = 1
        @pdir[1] = 1
      else
        is8 = 1
        ref0 = raw == 4 ? 1 : 0
    else
      if raw == 0
        direct16 = 1
      elsif raw <= 3
        shape = 0
        np = 1
        @pdir[0] = raw
      elsif raw < 22
        shape = (raw & 1) == 0 ? 1 : 2
        np = 2
        k = (raw - 4) >> 1
        @pdir[0] = H264_B_DIRS[k * 2]
        @pdir[1] = H264_B_DIRS[k * 2 + 1]
      else
        is8 = 1
    if direct16 == 1
      @mbinfo[mb] = 64
      direct_pred(15)
      t8ok = @direct8x8
    elsif is8 == 1
      # sub_mb_type
      b8 = 0 ## i64
      dmask = 0 ## i64
      while b8 < 4
        s = 0 ## i64
        if @cabac == 1
          s = @stype == 0 ? cb_sub_p : cb_sub_b
        else
          s = rb_ue
        @sub[b8] = s
        << "  sub_mb_type [s]" if @dbg == 1
        if @stype == 1 && s == 0
          dmask = dmask | (1 << b8)
          t8ok = 0 if @direct8x8 == 0
        elsif @stype == 0
          t8ok = 0 if s != 0
        else
          t8ok = 0 if s > 3
        b8 += 1
      direct_pred(dmask) if dmask != 0
      # refs
      l = 0 ## i64
      while l < 2
        b8 = 0
        while b8 < 4
          s = @sub[b8]
          dr = 0 ## i64
          if @stype == 0
            dr = 1
          else
            dr = H264_BSUB_DIR[s]
          bx = (b8 & 1) * 2
          by = (b8 >> 1) * 2
          if !(@stype == 1 && s == 0)
            if (dr & (1 << l)) != 0
              r = 0 ## i64
              r = read_ref(l, bx, by) if ref0 == 0
              set_motion(bx, by, 2, 2, l, r, 0, 0)
            else
              set_motion(bx, by, 2, 2, l, -1, 0, 0)
          b8 += 1
        l += 1
        l = 2 if @stype == 0
      if @stype == 0
        b8 = 0
        while b8 < 4
          set_motion((b8 & 1) * 2, (b8 >> 1) * 2, 2, 2, 1, -1, 0, 0)
          b8 += 1
      # mvds
      l = 0
      while l < 2
        b8 = 0
        while b8 < 4
          s = @sub[b8]
          if !(@stype == 1 && s == 0)
            dr = 1 ## i64
            ss = s
            if @stype == 1
              dr = H264_BSUB_DIR[s]
              ss = H264_BSUB_SHAPE[s]
            if (dr & (1 << l)) != 0
              bx = (b8 & 1) * 2
              by = (b8 >> 1) * 2
              if ss == 0
                read_mv(l, bx, by, 2, 2, 0, 0)
              elsif ss == 1
                read_mv(l, bx, by, 2, 1, 0, 0)
                read_mv(l, bx, by + 1, 2, 1, 0, 0)
              elsif ss == 2
                read_mv(l, bx, by, 1, 2, 0, 0)
                read_mv(l, bx + 1, by, 1, 2, 0, 0)
              else
                read_mv(l, bx, by, 1, 1, 0, 0)
                read_mv(l, bx + 1, by, 1, 1, 0, 0)
                read_mv(l, bx, by + 1, 1, 1, 0, 0)
                read_mv(l, bx + 1, by + 1, 1, 1, 0, 0)
          b8 += 1
        l += 1
        l = 2 if @stype == 0
    else
      # 16x16, 16x8, 8x16
      pw = shape == 2 ? 2 : 4
      ph = shape == 1 ? 2 : 4
      l = 0 ## i64
      while l < 2
        p = 0 ## i64
        while p < np
          bx = shape == 2 ? p * 2 : 0
          by = shape == 1 ? p * 2 : 0
          if (@pdir[p] & (1 << l)) != 0
            r = read_ref(l, bx, by)
            set_motion(bx, by, pw, ph, l, r, 0, 0)
          else
            set_motion(bx, by, pw, ph, l, -1, 0, 0)
          p += 1
        l += 1
      l = 0
      while l < 2
        p = 0
        while p < np
          bx = shape == 2 ? p * 2 : 0
          by = shape == 1 ? p * 2 : 0
          read_mv(l, bx, by, pw, ph, shape, p) if (@pdir[p] & (1 << l)) != 0
          p += 1
        l += 1
    # motion compensation
    if direct16 == 1
      mc_direct(15)
    elsif is8 == 1
      b8 = 0 ## i64
      while b8 < 4
        s = @sub[b8]
        bx = (b8 & 1) * 2
        by = (b8 >> 1) * 2
        if @stype == 1 && s == 0
          mc_direct(1 << b8)
        else
          ss = @stype == 1 ? H264_BSUB_SHAPE[s] : s
          if ss == 0
            mc_block(bx, by, 2, 2)
          elsif ss == 1
            mc_block(bx, by, 2, 1)
            mc_block(bx, by + 1, 2, 1)
          elsif ss == 2
            mc_block(bx, by, 1, 2)
            mc_block(bx + 1, by, 1, 2)
          else
            mc_block(bx, by, 1, 1)
            mc_block(bx + 1, by, 1, 1)
            mc_block(bx, by + 1, 1, 1)
            mc_block(bx + 1, by + 1, 1, 1)
        b8 += 1
    else
      if shape == 0
        mc_block(0, 0, 4, 4)
      elsif shape == 1
        mc_block(0, 0, 4, 2)
        mc_block(0, 2, 4, 2)
      else
        mc_block(0, 0, 2, 4)
        mc_block(2, 0, 2, 4)
    # residual
    cbp = read_cbp(0)
    << "  cbp [cbp]" if @dbg == 1
    @cbp_tab[mb] = cbp
    @cpm_tab[mb] = 0
    t8 = 0 ## i64
    if (cbp & 15) != 0 && @t8mode == 1 && t8ok == 1
      if @cabac == 1
        inc = 0 ## i64
        inc += 1 if @mba >= 0 && (@mbinfo[@mba] & 32) != 0
        inc += 1 if @mbb >= 0 && (@mbinfo[@mbb] & 32) != 0
        t8 = cb_t8(inc)
      else
        t8 = rb_u(1)
    @mbinfo[mb] = @mbinfo[mb] | 32 if t8 == 1
    read_qp_and_residual(cbp, 0, t8, 0)
    d = @mby * 16 * @lw + @mbx * 16
    if t8 == 1
      b8 = 0
      while b8 < 4
        bx = (b8 & 1) * 2
        by = (b8 >> 1) * 2
        if ((@nzmask[mb] >> (by * 4 + bx)) & 1) == 1
          h264_idct8_scratch(@cur_y, d + by * 4 * @lw + bx * 4, @lw, @coef, b8 * 64, @idct_scratch)
        b8 += 1
    elsif (cbp & 15) != 0
      recon_luma_residual4(d)
    recon_chroma_residual(cbp) if @cfmt != 0
    store_dbk(mb)
    0

  # MC for direct-predicted 8x8 blocks in mask.
  -> mc_direct(mask) (i64) i64
    b8 = 0 ## i64
    if mask == 15 && @direct8x8 == 1
      # merge to 16x16 when all four 8x8 blocks share motion
      if same_motion(0, 0, 2, 0) == 1 && same_motion(0, 0, 0, 2) == 1 && same_motion(0, 0, 2, 2) == 1
        mc_block(0, 0, 4, 4)
        return 0
    while b8 < 4
      if ((mask >> b8) & 1) == 1
        bx = (b8 & 1) * 2
        by = (b8 >> 1) * 2
        if @direct8x8 == 1
          mc_block(bx, by, 2, 2)
        else
          mc_block(bx, by, 1, 1)
          mc_block(bx + 1, by, 1, 1)
          mc_block(bx, by + 1, 1, 1)
          mc_block(bx + 1, by + 1, 1, 1)
      b8 += 1
    0

  -> same_motion(ax, ay, bx, by) (i64 i64 i64 i64) i64
    i = (@gy0 + ay) * @w4 + @gx0 + ax
    j = (@gy0 + by) * @w4 + @gx0 + bx
    return 0 if @cur_ref[i * 2] != @cur_ref[j * 2] || @cur_ref[i * 2 + 1] != @cur_ref[j * 2 + 1]
    k = 0 ## i64
    while k < 4
      return 0 if @cur_mv[i * 4 + k] != @cur_mv[j * 4 + k]
      k += 1
    1

  # Motion-compensate the region (local 4x4 units) using the motion stored
  # for its top-left block.
  -> mc_block(bx, by, bw, bh) (i64 i64 i64 i64) i64
    j = (@gy0 + by) * @w4 + @gx0 + bx
    r0 = @cur_ref[j * 2]
    r1 = @cur_ref[j * 2 + 1]
    px = (@gx0 + bx) * 4
    py = (@gy0 + by) * 4
    w = bw * 4
    h = bh * 4
    lw = @lw
    ld = py * lw + px
    cw = @cw
    cscale = @mbch == 16 ? 1 : 2
    cd = (py / cscale) * cw + px / 2
    chh = h / cscale
    if r0 >= 0 && r1 >= 0
      p0 = @ref_list[0][r0]
      p1 = @ref_list[1][r1]
      m0x = @cur_mv[j * 4]
      m0y = @cur_mv[j * 4 + 1]
      m1x = @cur_mv[j * 4 + 2]
      m1y = @cur_mv[j * 4 + 3]
      w0 = 0 ## i64
      w1 = 0 ## i64
      lo = 0 ## i64
      logwd = 0 ## i64
      if @wmode == 2
        iw = @implicit_w[r0 * 32 + r1]
        w0 = iw >> 16
        w1 = iw & 0xFFFF
        logwd = 5
      plane = 0 ## i64
      while plane < 3
        if plane == 0
          luma_pred(p0.y, m0x, m0y, px, py, w, h, @pb0)
          luma_pred(p1.y, m1x, m1y, px, py, w, h, @pb1)
        elsif @cfmt != 0
          src0 = plane == 1 ? p0.cb : p0.cr
          src1 = plane == 1 ? p1.cb : p1.cr
          chroma_pred(src0, m0x, m0y, px / 2, py / cscale, w / 2, chh, @pb0)
          chroma_pred(src1, m1x, m1y, px / 2, py / cscale, w / 2, chh, @pb1)
        if plane == 0 || @cfmt != 0
          dst = @cur_y
          dd = ld
          ds = lw
          bw2 = w
          bh2 = h
          if plane > 0
            dst = plane == 1 ? @cur_cb : @cur_cr
            dd = cd
            ds = cw
            bw2 = w / 2
            bh2 = chh
          if @wmode == 0
            h264_avg(dst, dd, ds, @pb0, @pb1, bw2, bh2)
          elsif @wmode == 2
            h264_biweight(dst, dd, ds, @pb0, @pb1, bw2, bh2, 5, w0, w1, 0)
          else
            b0 = r0 * 8 + (plane == 0 ? 0 : (plane == 1 ? 2 : 4))
            b1 = 256 + r1 * 8 + (plane == 0 ? 0 : (plane == 1 ? 2 : 4))
            lg = plane == 0 ? @luma_log2 : @chroma_log2
            off = (@wtab[b0 + 1] + @wtab[b1 + 1] + 1) >> 1
            h264_biweight(dst, dd, ds, @pb0, @pb1, bw2, bh2, lg, @wtab[b0], @wtab[b1], off)
        plane += 1
    else
      l = r0 >= 0 ? 0 : 1
      r = r0 >= 0 ? r0 : r1
      return 0 if r < 0
      p = @ref_list[l][r]
      raise H264Error.new("h264: missing reference l=[l] r=[r] n=[@ref_list[l].size] stype=[@stype] mb=[@mb]") if p == nil
      mx = @cur_mv[j * 4 + l * 2]
      my = @cur_mv[j * 4 + l * 2 + 1]
      if @wmode == 1
        b = l * 256 + r * 8
        luma_pred(p.y, mx, my, px, py, w, h, @pb0)
        h264_weight(@cur_y, ld, lw, @pb0, w, h, @luma_log2, @wtab[b], @wtab[b + 1])
        if @cfmt != 0
          chroma_pred(p.cb, mx, my, px / 2, py / cscale, w / 2, chh, @pb0)
          h264_weight(@cur_cb, cd, cw, @pb0, w / 2, chh, @chroma_log2, @wtab[b + 2], @wtab[b + 3])
          chroma_pred(p.cr, mx, my, px / 2, py / cscale, w / 2, chh, @pb0)
          h264_weight(@cur_cr, cd, cw, @pb0, w / 2, chh, @chroma_log2, @wtab[b + 4], @wtab[b + 5])
      else
        luma_pred(p.y, mx, my, px, py, w, h, @pb0)
        h264_copy_block(@cur_y, ld, lw, @pb0, w, h)
        if @cfmt != 0
          chroma_pred(p.cb, mx, my, px / 2, py / cscale, w / 2, chh, @pb0)
          h264_copy_block(@cur_cb, cd, cw, @pb0, w / 2, chh)
          chroma_pred(p.cr, mx, my, px / 2, py / cscale, w / 2, chh, @pb0)
          h264_copy_block(@cur_cr, cd, cw, @pb0, w / 2, chh)
    0

  # Luma prediction into out (stride 16).
  -> luma_pred(src, mx, my, px, py, w, h, out) (u8[] i64 i64 i64 i64 i64 i64 u8[]) i64
    ix = px + (mx >> 2)
    iy = py + (my >> 2)
    fx = mx & 3
    fy = my & 3
    lw = @lw
    if ix - 2 >= 0 && iy - 2 >= 0 && ix + w + 3 <= lw && iy + h + 3 <= @lh
      h264_luma_mc(out, 0, 16, src, iy * lw + ix, lw, w, h, fx, fy, @tmp)
    else
      h264_emu_edge(src, lw, lw, @lh, ix, iy, w, h, @emu)
      h264_luma_mc(out, 0, 16, @emu, 2 * 32 + 2, 32, w, h, fx, fy, @tmp)
    0

  -> chroma_pred(src, mx, my, cx, cy, w, h, out) (u8[] i64 i64 i64 i64 i64 i64 u8[]) i64
    myc = my
    fy = 0 ## i64
    iy = 0 ## i64
    if @mbch == 16
      # 4:2:2: vertical chroma mv is in quarter samples
      iy = cy + (my >> 2)
      fy = (my & 3) << 1
    else
      iy = cy + (myc >> 3)
      fy = myc & 7
    ix = cx + (mx >> 3)
    fx = mx & 7
    h264_chroma_mc(out, 0, 16, src, @cw, @cw, @ch, ix, iy, fx, fy, w, h)
    0

H264_B_DIRS = [1, 1, 2, 2, 1, 2, 2, 1, 1, 3, 2, 3, 3, 1, 3, 2, 3, 3]
H264_BSUB_DIR = [0, 1, 2, 3, 1, 1, 2, 2, 3, 3, 1, 2, 3]
H264_BSUB_SHAPE = [0, 0, 0, 0, 1, 2, 1, 2, 1, 2, 3, 3, 3]

-> h264_median(a, b, c) (i64 i64 i64) i64
  mx = a > b ? a : b
  mn = a < b ? a : b
  if c > mx
    mx
  elsif c < mn
    mn
  else
    c

-> h264_minpos(a, b) (i64 i64) i64
  if a >= 0 && b >= 0
    a < b ? a : b
  else
    a > b ? a : b

# 4:2:2 chroma DC scan: coefficient index → block raster index (x + 2y)
H264_C422_SCAN = [0, 2, 1, 4, 6, 3, 5, 7]

-> h264_c422_scan(p) (i64) i64
  H264_C422_SCAN[p]

-> h264_cbp_mono(k, intra)
  # Table 9-4(b): chroma_format_idc 0 or 3
  i_tab = [15, 0, 7, 11, 13, 14, 3, 5, 10, 12, 1, 2, 4, 8, 6, 9]
  p_tab = [0, 1, 2, 4, 8, 3, 5, 10, 12, 15, 7, 11, 13, 14, 6, 9]
  intra == 1 ? i_tab[k] : p_tab[k]
