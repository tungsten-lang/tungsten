# core/codec/video/h264_dbk — H.264 deblocking filter (8.7), run over the whole picture
# after its last slice. Methods of H264Dec.

use h264_dsp

+ H264Dec
  # Row-pipelined deblocking on a worker thread: row r is filtered once
  # rows 0..r+1 are decoded (row r+1's intra prediction needs row r
  # unfiltered). @dbk_prog counts decoded rows (sequentially consistent).
  -> deblock_start
    @dbk_thread = nil
    return 0 if @mbh < 3 || @pps_groups > 1 || @dbk_threads == 0
    @dbk_prog.store(0)
    @dbk_ooo = 0
    @expect_mb = 0
    me = self
    @dbk_thread = Thread.new ->
      me.deblock_rows
    0

  -> deblock_rows
    r = 0
    mbh = @mbh
    mbw = @mbw
    while r < mbh
      need = r + 2
      need = mbh if need > mbh || @dbk_ooo == 1
      while @dbk_prog.load < need
        need = mbh if @dbk_ooo == 1
      mb = r * mbw
      e = mb + mbw
      while mb < e
        deblock_mb(mb) if @slice_tab[mb] >= @pic_first_slice
        mb += 1
      r += 1
    0

  -> deblock_picture
    return 0 if @nmb == nil
    if @dbk_thread != nil
      @dbk_prog.store(@mbh)
      @dbk_thread.join
      @dbk_thread = nil
      return 0
    mb = 0
    while mb < @nmb
      deblock_mb(mb) if @slice_tab[mb] >= @pic_first_slice
      mb += 1
    0

  -> mvdiff(i, j, li, lj) (i64 i64 i64 i64) i64
    dx = @cur_mv[i * 4 + li * 2] - @cur_mv[j * 4 + lj * 2]
    dy = @cur_mv[i * 4 + li * 2 + 1] - @cur_mv[j * 4 + lj * 2 + 1]
    dx = 0 - dx if dx < 0
    dy = 0 - dy if dy < 0
    (dx >= 4 || dy >= 4) ? 1 : 0

  # Boundary strength between 4x4 blocks p (in MB pm) and q (in MB qm).
  -> bs_calc(pm, qm, pg, qg, plocal, qlocal, mbedge) (i64 i64 i64 i64 i64 i64 i64) i64
    if ((@mbinfo[pm] | @mbinfo[qm]) & 1) == 1
      return mbedge == 1 ? 4 : 3
    if ((@nzmask[pm] >> plocal) & 1) == 1 || ((@nzmask[qm] >> qlocal) & 1) == 1
      return 2
    pr0 = @cur_rid[pg * 2]
    pr1 = @cur_rid[pg * 2 + 1]
    qr0 = @cur_rid[qg * 2]
    qr1 = @cur_rid[qg * 2 + 1]
    np = (pr0 >= 0 ? 1 : 0) + (pr1 >= 0 ? 1 : 0)
    nq = (qr0 >= 0 ? 1 : 0) + (qr1 >= 0 ? 1 : 0)
    return 1 if np != nq
    if np == 1
      lp = pr0 >= 0 ? 0 : 1
      lq = qr0 >= 0 ? 0 : 1
      return 1 if (lp == 0 ? pr0 : pr1) != (lq == 0 ? qr0 : qr1)
      return mvdiff(pg, qg, lp, lq)
    return 0 if np == 0
    return 1 if !((pr0 == qr0 && pr1 == qr1) || (pr0 == qr1 && pr1 == qr0))
    if pr0 != pr1
      if pr0 == qr0
        return (mvdiff(pg, qg, 0, 0) == 1 || mvdiff(pg, qg, 1, 1) == 1) ? 1 : 0
      return (mvdiff(pg, qg, 0, 1) == 1 || mvdiff(pg, qg, 1, 0) == 1) ? 1 : 0
    a = (mvdiff(pg, qg, 0, 0) == 1 || mvdiff(pg, qg, 1, 1) == 1)
    b = (mvdiff(pg, qg, 0, 1) == 1 || mvdiff(pg, qg, 1, 0) == 1)
    (a && b) ? 1 : 0

  -> deblock_mb(mb) (i64) i64
    idc = @dbk_tab[mb * 3]
    return 0 if idc == 1
    offa = @dbk_tab[mb * 3 + 1]
    offb = @dbk_tab[mb * 3 + 2]
    mbx = mb % @mbw
    mby = mb / @mbw
    info = @mbinfo[mb]
    t8 = (info >> 5) & 1
    sl = @slice_tab[mb]
    left = 0 ## i64
    top = 0 ## i64
    if mbx > 0 && @slice_tab[mb - 1] >= @pic_first_slice
      left = 1 if idc != 2 || @slice_tab[mb - 1] == sl
    if mby > 0 && @slice_tab[mb - @mbw] >= @pic_first_slice
      top = 1 if idc != 2 || @slice_tab[mb - @mbw] == sl
    qp = @qp_tab[mb]
    lw = @lw
    cw = @cw
    bs = @bsv
    gx0 = mbx * 4
    gy0 = mby * 4
    dir = 0 ## i64
    while dir < 2
      e = 0 ## i64
      while e < 4
        doit = 1 ## i64
        luma_on = 1 ## i64
        if e > 0 && t8 == 1 && (e & 1) == 1
          luma_on = 0
          # 4:2:2 chroma keeps its 4x4 horizontal edges (rows 4 and 12)
          doit = (@cfmt == 2 && dir == 1) ? 1 : 0
        doit = 0 if e == 0 && dir == 0 && left == 0
        doit = 0 if e == 0 && dir == 1 && top == 0
        if doit == 1
          pm = mb
          if e == 0
            pm = dir == 0 ? mb - 1 : mb - @mbw
          any = 0 ## i64
          k = 0 ## i64
          while k < 4
            qx = 0 ## i64
            qy = 0 ## i64
            px = 0 ## i64
            py = 0 ## i64
            if dir == 0
              qx = e
              qy = k
              px = e - 1
              py = k
            else
              qx = k
              qy = e
              px = k
              py = e - 1
            pg = (gy0 + py) * @w4 + gx0 + px
            qg = (gy0 + qy) * @w4 + gx0 + qx
            pl = ((py + 4) & 3) * 4 + ((px + 4) & 3)
            ql = qy * 4 + qx
            b = bs_calc(pm, mb, pg, qg, pl, ql, e == 0 ? 1 : 0)
            bs[k] = b
            any += b
            k += 1
          if any > 0
            qpav = (@qp_tab[pm] + qp + 1) >> 1
            ia = h264_clip3(0, 51, qpav + offa)
            ib = h264_clip3(0, 51, qpav + offb)
            tc = @tcrow
            k = 0
            while k < 4
              tc[k] = @tc0[(ia + 52) * 4 + k]
              k += 1
            o = (mby * 16) * lw + mbx * 16
            if luma_on == 1
              if dir == 0
                h264_filter_edge(@cur_y, o + e * 4, 1, lw, 16, bs, @alpha[ia + 52], @beta[ib + 52], tc, 1)
              else
                h264_filter_edge(@cur_y, o + e * 4 * lw, lw, 1, 16, bs, @alpha[ia + 52], @beta[ib + 52], tc, 1)
            if @cfmt != 0 && (e & 1) == 0 && luma_on == 1
              c = 0 ## i64
              while c < 2
                qpav = (@qpc_tab[pm * 2 + c] + @qpc_tab[mb * 2 + c] + 1) >> 1
                ia = h264_clip3(0, 51, qpav + offa)
                ib = h264_clip3(0, 51, qpav + offb)
                k = 0
                while k < 4
                  tc[k] = @tc0[(ia + 52) * 4 + k]
                  k += 1
                pl2 = c == 0 ? @cur_cb : @cur_cr
                oc = (mby * @mbch) * cw + mbx * 8
                if dir == 0
                  h264_filter_edge(pl2, oc + e * 2, 1, cw, @mbch, bs, @alpha[ia + 52], @beta[ib + 52], tc, 0)
                elsif @mbch == 8
                  h264_filter_edge(pl2, oc + e * 2 * cw, cw, 1, 8, bs, @alpha[ia + 52], @beta[ib + 52], tc, 0)
                c += 1
            if @cfmt == 2 && dir == 1
              # 4:2:2 horizontal chroma edges at chroma rows 0, 4, 8, 12 map
              # to luma edges 0, 1, 2, 3 with bS from those edges (8.7.2)
              c = 0
              while c < 2
                qpav = (@qpc_tab[pm * 2 + c] + @qpc_tab[mb * 2 + c] + 1) >> 1
                ia = h264_clip3(0, 51, qpav + offa)
                ib = h264_clip3(0, 51, qpav + offb)
                k = 0
                while k < 4
                  tc[k] = @tc0[(ia + 52) * 4 + k]
                  k += 1
                pl2 = c == 0 ? @cur_cb : @cur_cr
                oc = (mby * 16) * cw + mbx * 8
                h264_filter_edge(pl2, oc + e * 4 * cw, cw, 1, 8, bs, @alpha[ia + 52], @beta[ib + 52], tc, 0)
                c += 1
        e += 1
      dir += 1
    0
