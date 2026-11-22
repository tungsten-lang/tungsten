# core/codec/video/h264 — H.264 / AVC video decoder (ITU-T H.264), pure Tungsten.
#
# Registered as "avc1"/"avc3" (avcC config, length-prefixed samples) and
# "h264" (Annex B start-code streams). Decodes progressive 8-bit 4:2:0
# Constrained Baseline / Main / High: CAVLC and CABAC, I/P/B slices, all intra
# modes, quarter-sample MC, multiple refs, weighted prediction, spatial and
# temporal direct, 8x8 transform, scaling matrices, deblocking, POC types
# 0/1/2, MMCO and sliding-window marking, and DPB output ordering.
#
# Files: h264_bits (NAL/RBSP/headers), h264_tables, h264_dsp (pixel kernels),
# h264_cavlc / h264_cabac (entropy decoding), h264_mb (macroblock layer,
# prediction and reconstruction), h264_dbk (deblocking), h264 (this file:
# sequence/picture management and the Decoder API).

use core/codec/media
use h264_tables
use h264_bits
use h264_dsp
use h264_cavlc
use h264_cabac
use h264_mb
use h264_dbk

H264_MB_INTRA = 1
H264_MB_SKIP = 2
H264_MB_I16 = 4
H264_MB_INXN = 8
H264_MB_PCM = 16
H264_MB_T8 = 32
H264_MB_DIRECT = 64

+ H264Pic
  rw :y, :cb, :cr, :poc, :top_poc, :bot_poc, :frame_num, :frame_num_wrap, :lt_idx, :ref, :waiting, :serial, :mv, :refi, :rid, :pts, :dur, :idr, :mmco5, :nonexist, :pic_num, :key

  -> new(@serial)
    @ref = 0
    @waiting = 0
    @lt_idx = -1
    @nonexist = 0
    @mmco5 = 0
    @idr = 0
    @pts = ~0.0
    @dur = ~0.0
    @key = false
    @poc = 0
    @top_poc = 0
    @bot_poc = 0
    @frame_num = 0
    @frame_num_wrap = 0
    @pic_num = 0

# Level limits: [level_idc, MaxDpbMbs]
H264_LEVEL_DPB = [[9, 396], [10, 396], [11, 900], [12, 2376], [13, 2376], [20, 2376], [21, 4752], [22, 8100], [30, 8100], [31, 18000], [32, 20480], [40, 32768], [41, 32768], [42, 34816], [50, 110400], [51, 184320], [52, 184320], [60, 696320], [61, 696320], [62, 696320]]

+ H264Dec
  rw :frames_out, :annexb, :au_complete

  -> new(cfg)
    @spss = {}
    @ppss = {}
    @nal_len_size = 4
    @annexb = true
    @cfg = cfg
    @seq_sps = nil
    @serial = 0
    @slice_counter = 0
    @dpb = []
    @out = []
    @cur = nil
    @prev_ref_frame_num = 0
    @prev_poc_msb = 0
    @prev_poc_lsb = 0
    @prev_fno = 0
    @prev_frame_num = 0
    @prev_mmco5 = 0
    @prev_top_poc = 0
    @max_lt_idx = -1
    @pts = ~0.0
    @dur = ~0.0
    @key = false
    @frames_out = 0
    @au_complete = true
    @dq_pps = nil
    @mbmap = nil
    @sb = u8[16]
    @cur_y = u8[16]
    @cur_cb = u8[16]
    @cur_cr = u8[16]
    @cur_mv = i32[16]
    @cur_ref = i32[16]
    @cur_rid = i32[16]
    @dq_qp_dirty = 1
    @dbk_thread = nil
    @dbk_prog = Atomic.new(0)
    @dbk_ooo = 0
    @expect_mb = 0
    @pps_groups = 1
    @dbk_threads = env("H264_NO_THREADS") != nil ? 0 : 1
    @dbg = 0
    @dbg_pic = env("H264_DEBUG") != nil ? env("H264_DEBUG").to_i : -1
    @npics = 0
    tables_init
    cavlc_init
    cabac_init_tables
    if cfg != nil && cfg.extra != nil
      parse_avcc(cfg.extra)

  # Fixed tables as typed arrays.
  -> tables_init
    @zz4 = i64[H264_ZIGZAG4.size]
    h264_fill(@zz4, H264_ZIGZAG4)
    @zz8 = i64[H264_ZIGZAG8.size]
    h264_fill(@zz8, H264_ZIGZAG8)
    @fs4 = i64[H264_FIELD4.size]
    h264_fill(@fs4, H264_FIELD4)
    @fs8 = i64[H264_FIELD8.size]
    h264_fill(@fs8, H264_FIELD8)
    # 8x8 CAVLC: coefficient k of interleaved block i is zigzag8[4k+i]
    @blkx = i64[16]
    @blky = i64[16]
    @zidx = i64[16]
    b = 0
    while b < 16
      x = ((b >> 2) & 1) * 2 + (b & 1)
      y = ((b >> 3) & 1) * 2 + ((b >> 1) & 1)
      @blkx[b] = x
      @blky[b] = y
      @zidx[y * 4 + x] = b
      b += 1
    @alpha = i64[H264_ALPHA.size]
    h264_fill(@alpha, H264_ALPHA)
    @beta = i64[H264_BETA.size]
    h264_fill(@beta, H264_BETA)
    @tc0 = i64[H264_TC0.size]
    h264_fill(@tc0, H264_TC0)
    @qpc_tab_c = i64[H264_QPC.size]
    h264_fill(@qpc_tab_c, H264_QPC)
    @coef = i32[16 * 16 + 2 * 8 * 16]
    @tmp = i32[24 * 22]
    @emu = u8[32 * 24]
    @pb0 = u8[256]
    @pb1 = u8[256]
    @top = i64[16]
    @left = i64[8]
    @ft = i64[16]
    @fl = i64[8]
    @cpos = i64[64]
    @clev = i64[64]
    @dcb = i64[16]
    @sub = i64[4]
    @pdir = i64[4]
    @refi = i64[8]
    @bsv = i64[4]
    @tcrow = i64[4]
    @dq4 = i32[6 * 52 * 16]
    @dq8 = i32[6 * 52 * 64]
    @rid_l = i64[64]
    @rpoc_l = i64[64]
    @rlt_l = i64[64]
    @wtab = i64[2 * 32 * 8]
    @implicit_w = i64[32 * 32]
    @dsf_tab = i64[32]
    @dir_ref = i64[2]
    @dir_mv = i64[4]

  -> h264_fill(r, a)
    i = 0
    while i < a.size
      r[i] = a[i]
      i += 1
    r

  -> h264_i64(a)
    r = i64[a.size]
    i = 0
    while i < a.size
      r[i] = a[i]
      i += 1
    r

  -> parse_avcc(ex)
    b = ex
    if ex.is_a?(String)
      b = ccall("w_string_bytes_view", ex) ## u8[]
    return 0 if b.size < 7
    if b[0] != 1
      # not an avcC record; treat as Annex B parameter sets
      decode_nals(b, b.size, true)
      return 0
    @annexb = false
    @nal_len_size = (b[4] & 3) + 1
    n = b[5] & 31
    p = 6
    i = 0
    while i < n && p + 2 <= b.size
      l = (b[p] << 8) | b[p + 1]
      p += 2
      handle_nal(b, p, p + l) if p + l <= b.size
      p += l
      i += 1
    if p < b.size
      n = b[p]
      p += 1
      i = 0
      while i < n && p + 2 <= b.size
        l = (b[p] << 8) | b[p + 1]
        p += 2
        handle_nal(b, p, p + l) if p + l <= b.size
        p += l
        i += 1
    0

  # ------------------------------------------------------------ decoder API

  -> decode(sample)
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    @pts = sample.pts
    @dur = sample.duration
    @key = sample.key
    ab = @annexb
    if d.size >= 4 && d[0] == 0 && d[1] == 0 && (d[2] == 1 || (d[2] == 0 && d[3] == 1))
      ab = true
    decode_nals(d, d.size, ab)
    # a container sample is a whole access unit: finish it now (raw Annex B
    # feeders clear au_complete and let picture boundaries be detected)
    finish_picture if @au_complete
    take_output

  -> flush
    finish_picture
    while bump_one
      0
    take_output

  -> reset
    finish_picture
    @dpb = []
    @out = []
    @cur = nil
    @prev_ref_frame_num = 0
    @prev_poc_msb = 0
    @prev_poc_lsb = 0
    @prev_fno = 0
    @prev_mmco5 = 0

  -> take_output
    o = @out
    @out = []
    o

  -> decode_nals(d, len, ab)
    spans = ab ? h264_annexb_spans(d, len) : h264_length_spans(d, len, @nal_len_size)
    i = 0
    while i < spans.size
      handle_nal(d, spans[i], spans[i + 1])
      i += 2
    0

  -> handle_nal(d, s, e)
    return 0 if e <= s
    hdr = d[s]
    typ = hdr & 31
    ref_idc = (hdr >> 5) & 3
    if typ == 7
      rb = h264_unescape(d, s + 1, e)
      sps = H264SPS.parse(H264Bits.new(rb, h264_rbsp_len(rb)))
      @spss[sps.id] = sps
    elsif typ == 8
      rb = h264_unescape(d, s + 1, e)
      pps = H264PPS.parse(H264Bits.new(rb, h264_rbsp_len(rb)), @spss)
      @ppss[pps.id] = pps
      @dq_pps = nil if @dq_pps != nil && @dq_pps.id == pps.id
    elsif typ == 1 || typ == 5
      @sb = h264_unescape(d, s + 1, e)
      rbl = @sb.size - 16
      r = H264Bits.new(@sb, rbl)
      sl = H264Slice.parse(r, typ, ref_idc, @spss, @ppss)
      decode_slice(sl, rbl)
    elsif typ == 11 || typ == 10
      finish_picture
    0

  # ------------------------------------------------------- sequence set-up

  -> activate_sps(sps)
    return 0 if @seq_sps == sps
    raise H264Error, "h264: only 8-bit video is supported" if sps.bit_depth != 8 || sps.bit_depth_c != 8
    raise H264Error, "h264: interlaced (field/MBAFF) coding is not supported" if sps.frame_mbs_only == 0
    raise H264Error, "h264: 4:4:4 is not supported" if sps.chroma_format == 3
    if @seq_sps == nil || @seq_sps.mbw != sps.mbw || @seq_sps.mbh != sps.mbh || @seq_sps.chroma_format != sps.chroma_format
      # new geometry: output everything decoded so far
      while bump_one
        0
      @dpb = []
    @seq_sps = sps
    @mbw = sps.mbw
    @mbh = sps.mbh
    @nmb = @mbw * @mbh
    @w4 = @mbw * 4
    @h4 = @mbh * 4
    @n4 = @w4 * @h4
    @cfmt = sps.chroma_format
    @lw = @mbw * 16
    @lh = @mbh * 16
    @mbcw = 8
    @mbch = @cfmt == 2 ? 16 : 8
    @mbcw = 0 if @cfmt == 0
    @mbch = 0 if @cfmt == 0
    @cw = @mbw * 8
    @ch = @mbh * @mbch
    @cw4 = @mbw * 2
    @ch4 = @mbh * (@mbch / 4)
    @slice_tab = i32[@nmb]
    k = 0
    while k < @nmb
      @slice_tab[k] = -1
      k += 1
    @mbinfo = i32[@nmb]
    @qp_tab = i32[@nmb]
    @qpc_tab = i32[@nmb * 2]
    @cbp_tab = i32[@nmb]
    @cbf_tab = i32[@nmb]
    @cpm_tab = i32[@nmb]
    @nzmask = i32[@nmb]
    @dbk_tab = i32[@nmb * 3]
    @nnz = u8[@n4]
    @nnzc = u8[2 * @cw4 * (@ch4 > 0 ? @ch4 : 1)]
    @i4m = i32[@n4]
    @mvd = i32[@n4 * 4]
    @dir = u8[@n4]
    # DPB size from the level limits (A.3.1) or the VUI
    fs = @mbw * @mbh
    mx = 0
    H264_LEVEL_DPB.each ->(e)
      mx = e[1] if e[0] <= sps.level
    mx = 696320 if mx == 0
    dpb = mx / fs
    dpb = 16 if dpb > 16
    dpb = sps.max_dec_buf if sps.max_dec_buf >= 0 && sps.has_restrict == 1
    dpb = sps.max_refs if dpb < sps.max_refs
    dpb = 1 if dpb < 1
    @dpb_size = dpb
    @num_reorder = sps.num_reorder >= 0 ? sps.num_reorder : dpb
    0

  # Dequantisation tables for a PPS: dq4[(list*52+qp)*16 + pos] =
  # (weightScale * normAdjust) << (qp/6), raster pos.
  -> build_dq(pps)
    return 0 if @dq_pps == pps
    @dq_pps = pps
    dq4i = h264_i64(H264_DEQUANT4_INIT)
    dq8i = h264_i64(H264_DEQUANT8_INIT)
    sc8 = h264_i64(H264_DEQUANT8_INIT_SCAN)
    l = 0
    while l < 6
      q = 0
      while q < 52
        k = 0
        while k < 16
          pos = @zz4[k]
          x = pos & 3
          y = pos >> 2
          idx = (x & 1) + (y & 1)
          v = pps.sl4[l * 16 + k] * dq4i[(q % 6) * 3 + idx]
          @dq4[(l * 52 + q) * 16 + pos] = v << (q / 6)
          k += 1
        q += 1
      l += 1
    l = 0
    while l < 6
      q = 0
      while q < 52
        k = 0
        while k < 64
          pos = @zz8[k]
          x = pos & 7
          y = pos >> 3
          idx = sc8[((x & 3) << 2) | (y & 3)]
          v = pps.sl8[(l < 2 ? l : l) * 64 + k] * dq8i[(q % 6) * 6 + idx]
          @dq8[(l * 52 + q) * 64 + pos] = v << (q / 6)
          k += 1
        q += 1
      l += 1
    0

  # ------------------------------------------------------- picture handling

  -> new_picture?(sl)
    return true if @cur == nil
    return true if sl.first_mb == 0 && @slice_tab[0] >= @pic_first_slice
    p = @cur_slice
    return true if p.frame_num != sl.frame_num || p.pps_id != sl.pps_id
    return true if (p.nal_ref_idc == 0) != (sl.nal_ref_idc == 0)
    return true if p.is_idr != sl.is_idr
    return true if sl.is_idr == 1 && p.idr_pic_id != sl.idr_pic_id
    return true if p.poc_lsb != sl.poc_lsb || p.delta_poc_bottom != sl.delta_poc_bottom
    return true if p.delta_poc0 != sl.delta_poc0 || p.delta_poc1 != sl.delta_poc1
    false

  -> decode_slice(sl, rblen)
    pps = @ppss[sl.pps_id]
    sps = @spss[pps.sps_id]
    return 0 if sl.redundant_cnt > 0
    if new_picture?(sl)
      finish_picture
      activate_sps(sps)
      start_picture(sl, sps)
      @first_slice_of_pic = true
    @cur_slice = sl
    @sps = sps
    @pps = pps
    build_dq(pps)
    if @first_slice_of_pic
      @first_slice_of_pic = false
      @pps_groups = pps.num_slice_groups
      deblock_start
    if pps.num_slice_groups > 1
      @mbmap = h264_slice_group_map(pps, sps, sl, @mbw, @mbh)
    else
      @mbmap = nil
    build_ref_lists(sl)
    setup_weights(sl)
    @slice_counter += 1
    @slice_num = @slice_counter
    decode_slice_data(sl, rblen)
    0

  -> start_picture(sl, sps)
    # frame_num gaps
    mfn = 1 << sps.log2_max_frame_num
    if sl.is_idr == 0 && sl.frame_num != @prev_ref_frame_num && sl.frame_num != (@prev_ref_frame_num + 1) % mfn
      fill_frame_gap(sl, sps)
    @serial += 1
    pic = H264Pic.new(@serial)
    @cur_y = u8[@lw * @lh]
    @cur_cb = u8[@cfmt != 0 ? @cw * @ch : 1]
    @cur_cr = u8[@cfmt != 0 ? @cw * @ch : 1]
    @cur_mv = i32[@n4 * 4]
    @cur_ref = i32[@n4 * 2]
    @cur_rid = i32[@n4 * 2]
    pic.y = @cur_y
    pic.cb = @cur_cb
    pic.cr = @cur_cr
    pic.mv = @cur_mv
    pic.refi = @cur_ref
    pic.rid = @cur_rid
    pic.frame_num = sl.frame_num
    pic.idr = sl.is_idr
    pic.pts = @pts
    pic.dur = @dur
    pic.key = @key
    compute_poc(pic, sl, sps)
    @pic_first_slice = @slice_counter + 1
    @dbg = @npics == @dbg_pic ? 1 : 0
    @npics += 1
    @cur = pic
    @cur_ref_idc = sl.nal_ref_idc
    0

  -> compute_poc(pic, sl, sps)
    if sps.poc_type == 0
      if sl.is_idr == 1
        @prev_poc_msb = 0
        @prev_poc_lsb = 0
      elsif @prev_mmco5 == 1
        @prev_poc_msb = 0
        @prev_poc_lsb = @prev_top_poc
      maxl = 1 << sps.log2_max_poc_lsb
      lsb = sl.poc_lsb
      msb = @prev_poc_msb
      if lsb < @prev_poc_lsb && @prev_poc_lsb - lsb >= maxl / 2
        msb = @prev_poc_msb + maxl
      elsif lsb > @prev_poc_lsb && lsb - @prev_poc_lsb > maxl / 2
        msb = @prev_poc_msb - maxl
      pic.top_poc = msb + lsb
      pic.bot_poc = pic.top_poc + sl.delta_poc_bottom
      @poc_msb = msb
    else
      mfn = 1 << sps.log2_max_frame_num
      fno = 0
      if sl.is_idr == 0
        pf = @prev_mmco5 == 1 ? 0 : @prev_fno
        fno = @prev_frame_num > sl.frame_num ? pf + mfn : pf
      @fno = fno
      if sps.poc_type == 1
        n = sps.poc_cycle.size
        absn = n != 0 ? fno + sl.frame_num : 0
        absn -= 1 if sl.nal_ref_idc == 0 && absn > 0
        exp = 0
        if absn > 0
          per = 0
          sps.poc_cycle.each ->(o)
            per += o
          cyc = (absn - 1) / n
          inc = (absn - 1) % n
          exp = cyc * per
          i = 0
          while i <= inc
            exp += sps.poc_cycle[i]
            i += 1
        exp += sps.offset_non_ref if sl.nal_ref_idc == 0
        pic.top_poc = exp + sl.delta_poc0
        pic.bot_poc = pic.top_poc + sps.offset_top_bottom + sl.delta_poc1
      else
        t = 0
        if sl.is_idr == 0
          t = sl.nal_ref_idc == 0 ? 2 * (fno + sl.frame_num) - 1 : 2 * (fno + sl.frame_num)
        pic.top_poc = t
        pic.bot_poc = t
    pic.poc = pic.top_poc < pic.bot_poc ? pic.top_poc : pic.bot_poc
    0

  -> fill_frame_gap(sl, sps)
    mfn = 1 << sps.log2_max_frame_num
    gfn = (@prev_ref_frame_num + 1) % mfn
    guard = 0
    while gfn != sl.frame_num && guard < 64
      @serial += 1
      p = H264Pic.new(@serial)
      p.nonexist = 1
      p.frame_num = gfn
      p.y = u8[@lw * @lh]
      if @cfmt != 0
        p.cb = u8[@cw * @ch]
        p.cr = u8[@cw * @ch]
      p.mv = i32[@n4 * 4]
      p.refi = i32[@n4 * 2]
      p.rid = i32[@n4 * 2]
      # copy the most recent reference so concealment looks sane
      lastr = nil
      @dpb.each ->(q)
        lastr = q if q.ref != 0 && (lastr == nil || q.serial > lastr.serial)
      if lastr != nil
        p.y = lastr.y.slice(0, lastr.y.size)
        p.cb = lastr.cb.slice(0, lastr.cb.size) if @cfmt != 0
        p.cr = lastr.cr.slice(0, lastr.cr.size) if @cfmt != 0
      sliding_window(gfn, sps)
      p.ref = 1
      @dpb.push(p)
      @prev_ref_frame_num = gfn
      @prev_frame_num = gfn
      gfn = (gfn + 1) % mfn
      guard += 1
    0

  # After all slices of the current picture: deblock, mark, store, output.
  -> finish_picture
    return 0 if @cur == nil
    pic = @cur
    @cur = nil
    deblock_picture
    sl = @cur_slice
    sps = @seq_sps
    mmco5 = 0
    if @cur_ref_idc != 0
      mmco5 = mark_references(pic, sl, sps)
    if mmco5 == 1
      # 8.2.1: after MMCO 5 the picture behaves as frame_num 0, POC rebased
      t = pic.poc
      pic.top_poc -= t
      pic.bot_poc -= t
      pic.poc = 0
      pic.frame_num = 0
    if pic.idr == 1 || mmco5 == 1
      no_out = sl.no_output_prior == 1
      # output everything still waiting (prior pictures precede this one)
      if no_out
        @dpb.each ->(q)
          q.waiting = 0
      else
        while bump_one
          0
      @dpb = @dpb.select ->(q) q.ref != 0
    # POC state for the next picture
    if @cur_ref_idc != 0
      @prev_mmco5 = mmco5
      @prev_top_poc = pic.top_poc
      if sps.poc_type == 0
        if mmco5 == 1
          @prev_poc_msb = 0
          @prev_poc_lsb = pic.top_poc
        else
          @prev_poc_msb = @poc_msb
          @prev_poc_lsb = sl.poc_lsb
      @prev_ref_frame_num = mmco5 == 1 ? 0 : sl.frame_num
    if sps.poc_type != 0
      @prev_fno = mmco5 == 1 ? 0 : @fno
      @prev_frame_num = mmco5 == 1 ? 0 : sl.frame_num
      @prev_mmco5 = mmco5
    @prev_frame_num = sl.frame_num if sps.poc_type == 0
    # store
    @dpb = @dpb.select ->(q) q.ref != 0 || q.waiting == 1
    pic.waiting = 1
    while @dpb.size >= @dpb_size && bump_one
      @dpb = @dpb.select ->(q) q.ref != 0 || q.waiting == 1
    @dpb.push(pic)
    while waiting_count > @num_reorder && bump_one
      0
    @dpb = @dpb.select ->(q) q.ref != 0 || q.waiting == 1
    0

  -> waiting_count
    n = 0
    @dpb.each ->(q)
      n += 1 if q.waiting == 1
    n

  # Output the waiting picture with the smallest POC. Returns false if none.
  -> bump_one
    best = nil
    @dpb.each ->(q)
      if q.waiting == 1 && q.nonexist == 0
        best = q if best == nil || q.poc < best.poc
    if best == nil
      @dpb.each ->(q)
        q.waiting = 0
      return false
    best.waiting = 0
    emit(best)
    true

  -> emit(p)
    sps = @seq_sps
    cl = sps.crop[0]
    cr = sps.crop[1]
    ct = sps.crop[2]
    cb = sps.crop[3]
    w = @lw - cl - cr
    h = @lh - ct - cb
    y = p.y
    u = p.cb
    v = p.cr
    ls = @lw
    cs = @cw
    if cl != 0 || ct != 0
      y = h264_crop_plane(p.y, @lw, cl, ct, w, h)
      ls = w
      if @cfmt != 0
        sx = 2
        sy = @cfmt == 1 ? 2 : 1
        u = h264_crop_plane(p.cb, @cw, cl / sx, ct / sy, (w + 1) / sx, (h + sy - 1) / sy)
        v = h264_crop_plane(p.cr, @cw, cl / sx, ct / sy, (w + 1) / sx, (h + sy - 1) / sy)
        cs = (w + 1) / sx
    chroma = "420"
    chroma = "422" if @cfmt == 2
    chroma = "400" if @cfmt == 0
    planes = [y, u, v]
    if @cfmt == 0
      g = u8[((w + 1) / 2) * ((h + 1) / 2)]
      k = 0
      while k < g.size
        g[k] = 128
        k += 1
      planes = [y, g, g]
      cs = (w + 1) / 2
      chroma = "420"
    f = VideoFrame.new(w, h, planes, [ls, cs, cs], chroma, 8, p.pts)
    f.duration = p.dur
    if sps.vui_colour == 1
      f.primaries = sps.primaries
      f.transfer = sps.transfer
      f.matrix = sps.matrix
    elsif h < 720
      f.matrix = 6
      f.primaries = 6
      f.transfer = 6
    f.full_range = sps.full_range == 1
    @out.push(f)
    @frames_out += 1
    0

# 8.2.2: macroblock to slice group map (frame coding).
-> h264_slice_group_map(pps, sps, sl, w, h)
  n = w * h
  m = i64[n]
  ng = pps.num_slice_groups
  t = pps.sg_type
  if t == 0
    i = 0
    while i < n
      g = 0
      while g < ng && i < n
        rl = pps.sg_run_length[g]
        j = 0
        while j < rl && i + j < n
          m[i + j] = g
          j += 1
        i += rl
        g += 1
  elsif t == 1
    i = 0
    while i < n
      m[i] = ((i % w) + (((i / w) * ng) / 2)) % ng
      i += 1
  elsif t == 2
    i = 0
    while i < n
      m[i] = ng - 1
      i += 1
    g = ng - 2
    while g >= 0
      tl = pps.sg_top_left[g]
      br = pps.sg_bottom_right[g]
      y = tl / w
      while y <= br / w
        x = tl % w
        while x <= br % w
          m[y * w + x] = g
          x += 1
        y += 1
      g -= 1
  elsif t >= 3 && t <= 5
    d = pps.sg_change_dir
    units0 = sl.sg_change_cycle * pps.sg_change_rate
    units0 = n if units0 > n
    if t == 3
      i = 0
      while i < n
        m[i] = 1
        i += 1
      x = (w - d) / 2
      y = (h - d) / 2
      lb = x
      tb = y
      rb = x
      bb = y
      xd = d - 1
      yd = d
      k = 0
      while k < units0
        vac = m[y * w + x] == 1 ? 1 : 0
        m[y * w + x] = 0 if vac == 1
        if xd == -1 && x == lb
          lb = lb - 1 > 0 ? lb - 1 : 0
          x = lb
          xd = 0
          yd = 2 * d - 1
        elsif xd == 1 && x == rb
          rb = rb + 1 < w - 1 ? rb + 1 : w - 1
          x = rb
          xd = 0
          yd = 1 - 2 * d
        elsif yd == -1 && y == tb
          tb = tb - 1 > 0 ? tb - 1 : 0
          y = tb
          xd = 1 - 2 * d
          yd = 0
        elsif yd == 1 && y == bb
          bb = bb + 1 < h - 1 ? bb + 1 : h - 1
          y = bb
          xd = 2 * d - 1
          yd = 0
        else
          x += xd
          y += yd
        k += vac
    else
      upper = d == 1 ? n - units0 : units0
      if t == 4
        i = 0
        while i < n
          m[i] = i < upper ? d : 1 - d
          i += 1
      else
        k = 0
        j = 0
        while j < w
          i = 0
          while i < h
            m[i * w + j] = k < upper ? d : 1 - d
            k += 1
            i += 1
          j += 1
  else
    i = 0
    while i < n
      m[i] = pps.sg_ids[i]
      i += 1
  m

-> h264_crop_plane(src, stride, x0, y0, w, h)
  o = u8[w * h]
  y = 0
  while y < h
    x = 0
    while x < w
      o[y * w + x] = src[(y0 + y) * stride + x0 + x]
      x += 1
    y += 1
  o

+ H264Dec
  # ---------------------------------------------------- reference marking

  -> sliding_window(cur_fn, sps)
    nshort = 0
    nlong = 0
    @dpb.each ->(q)
      nshort += 1 if q.ref == 1
      nlong += 1 if q.ref == 2
    mx = sps.max_refs
    mx = 1 if mx < 1
    if nshort + nlong >= mx && nshort > 0
      # remove the short-term ref with the smallest FrameNumWrap
      mfn = 1 << sps.log2_max_frame_num
      best = nil
      bw = 0
      @dpb.each ->(q)
        if q.ref == 1
          w = q.frame_num > cur_fn ? q.frame_num - mfn : q.frame_num
          if best == nil || w < bw
            best = q
            bw = w
      best.ref = 0 if best != nil
    0

  # Returns 1 when MMCO 5 was executed.
  -> mark_references(pic, sl, sps)
    mmco5 = 0
    if sl.is_idr == 1
      @dpb.each ->(q)
        q.ref = 0
      if sl.long_term_ref == 1
        pic.ref = 2
        pic.lt_idx = 0
        @max_lt_idx = 0
      else
        pic.ref = 1
        @max_lt_idx = -1
      return 0
    mfn = 1 << sps.log2_max_frame_num
    cur_pic_num = sl.frame_num
    long_set = false
    if sl.adaptive_marking == 1
      sl.mmco.each ->(op)
        o = op[0]
        if o == 1
          pn = cur_pic_num - (op[1] + 1)
          @dpb.each ->(q)
            if q.ref == 1
              w = q.frame_num > sl.frame_num ? q.frame_num - mfn : q.frame_num
              q.ref = 0 if w == pn
        elsif o == 2
          @dpb.each ->(q)
            q.ref = 0 if q.ref == 2 && q.lt_idx == op[2]
        elsif o == 3
          pn = cur_pic_num - (op[1] + 1)
          @dpb.each ->(q)
            q.ref = 0 if q.ref == 2 && q.lt_idx == op[2]
          @dpb.each ->(q)
            if q.ref == 1
              w = q.frame_num > sl.frame_num ? q.frame_num - mfn : q.frame_num
              if w == pn
                q.ref = 2
                q.lt_idx = op[2]
        elsif o == 4
          @max_lt_idx = op[1] - 1
          @dpb.each ->(q)
            q.ref = 0 if q.ref == 2 && q.lt_idx > @max_lt_idx
        elsif o == 5
          @dpb.each ->(q)
            q.ref = 0
          @max_lt_idx = -1
          mmco5 = 1
        elsif o == 6
          @dpb.each ->(q)
            q.ref = 0 if q.ref == 2 && q.lt_idx == op[2]
          pic.ref = 2
          pic.lt_idx = op[2]
          long_set = true
    else
      sliding_window(sl.frame_num, sps)
    pic.ref = 1 if !long_set
    mmco5

  # ------------------------------------------------- reference list init

  -> build_ref_lists(sl)
    @nref0 = sl.num_ref[0]
    @nref1 = sl.num_ref[1]
    @ref_list = [[], []]
    return 0 if sl.i?
    sps = @seq_sps
    mfn = 1 << sps.log2_max_frame_num
    refs = @dpb.select ->(q) q.ref != 0
    refs.each ->(q)
      if q.ref == 1
        q.frame_num_wrap = q.frame_num > sl.frame_num ? q.frame_num - mfn : q.frame_num
        q.pic_num = q.frame_num_wrap
    shorts = refs.select ->(q) q.ref == 1
    longs = refs.select ->(q) q.ref == 2
    longs = longs.sort_by ->(q) q.lt_idx
    cur_poc = @cur.poc
    if sl.p?
      l0 = shorts.sort_by ->(q) 0 - q.pic_num
      l0 = l0 + longs
      @ref_list[0] = l0
    else
      before = shorts.select ->(q) q.poc < cur_poc
      after = shorts.select ->(q) q.poc > cur_poc
      before = before.sort_by ->(q) 0 - q.poc
      after = after.sort_by ->(q) q.poc
      l0 = before + after + longs
      l1 = after + before + longs
      if l1.size > 1 && l0.size == l1.size
        same = true
        k = 0
        while k < l0.size
          same = false if l0[k] != l1[k]
          k += 1
        if same
          t = l1[0]
          l1[0] = l1[1]
          l1[1] = t
      @ref_list[0] = l0
      @ref_list[1] = l1
    nl = sl.b? ? 2 : 1
    l = 0
    while l < nl
      lst = @ref_list[l]
      n = sl.num_ref[l]
      # truncate / extend to num_ref_idx_active
      lst = lst.slice(0, n) if lst.size > n
      while lst.size < n
        lst.push(nil)
      ms = sl.mods[l]
      if ms.size > 0
        pred = sl.frame_num
        ridx = 0
        k = 0
        while k < ms.size
          op = ms[k]
          v = ms[k + 1]
          target = nil
          if op == 0 || op == 1
            if op == 0
              pn = pred - (v + 1)
              pn += mfn if pn < 0
            else
              pn = pred + (v + 1)
              pn -= mfn if pn >= mfn
            pred = pn
            pnum = pn > sl.frame_num ? pn - mfn : pn
            shorts.each ->(q)
              target = q if q.pic_num == pnum
          elsif op == 2
            longs.each ->(q)
              target = q if q.lt_idx == v
          if target != nil
            # insert at ridx, remove later duplicate
            nl2 = []
            j = 0
            while j < ridx
              nl2.push(lst[j])
              j += 1
            nl2.push(target)
            j = ridx
            while j < lst.size
              q = lst[j]
              nl2.push(q) if q == nil || q != target
              j += 1
            lst = nl2.slice(0, n)
            while lst.size < n
              lst.push(nil)
            ridx += 1
          k += 2
      # fill holes with something decodable
      fb = nil
      lst.each ->(q)
        fb = q if fb == nil && q != nil
      fb = refs[0] if fb == nil && refs.size > 0
      fb = @cur if fb == nil
      k = 0
      while k < n
        lst[k] = fb if lst[k] == nil
        k += 1
      @ref_list[l] = lst
      k = 0
      while k < n && k < 32
        q = lst[k]
        @rid_l[l * 32 + k] = q.serial
        @rpoc_l[l * 32 + k] = q.poc
        @rlt_l[l * 32 + k] = q.ref == 2 ? 1 : 0
        k += 1
      l += 1
    0

  # Weighted prediction mode and tables for this slice.
  -> setup_weights(sl)
    @wmode = 0
    pps = @pps
    if sl.p? && pps.weighted_pred == 1
      @wmode = 1
    elsif sl.b? && pps.weighted_bipred == 1
      @wmode = 1
    elsif sl.b? && pps.weighted_bipred == 2
      @wmode = 2
    if @wmode == 1
      @luma_log2 = sl.luma_log2
      @chroma_log2 = sl.chroma_log2
      l = 0
      while l < 2
        w = sl.weights[l]
        if w != nil
          k = 0
          while k < 32 * 8
            @wtab[l * 256 + k] = w[k]
            k += 1
        l += 1
    if @wmode == 2
      cur = @cur.poc
      i = 0
      while i < @nref0
        j = 0
        while j < @nref1
          p0 = @rpoc_l[i]
          p1 = @rpoc_l[32 + j]
          tb = h264_clip3(-128, 127, cur - p0)
          td = h264_clip3(-128, 127, p1 - p0)
          w0 = 32
          w1 = 32
          if td != 0 && @rlt_l[i] == 0 && @rlt_l[32 + j] == 0
            tx = (16384 + (td < 0 ? 0 - td : td) / 2) / td
            dsf = h264_clip3(-1024, 1023, (tb * tx + 32) >> 6)
            if (dsf >> 2) >= -64 && (dsf >> 2) <= 128
              w0 = 64 - (dsf >> 2)
              w1 = dsf >> 2
          @implicit_w[i * 32 + j] = (w0 << 16) | w1
          j += 1
        i += 1
    # temporal direct scale factors (per refIdxL0, against list1[0])
    if sl.b? && sl.direct_spatial == 0
      cur = @cur.poc
      i = 0
      while i < @nref0
        p0 = @rpoc_l[i]
        p1 = @rpoc_l[32]
        tb = h264_clip3(-128, 127, cur - p0)
        td = h264_clip3(-128, 127, p1 - p0)
        if td == 0 || @rlt_l[i] == 1
          @dsf_tab[i] = 9999
        else
          tx = (16384 + (td < 0 ? 0 - td : td) / 2) / td
          @dsf_tab[i] = h264_clip3(-1024, 1023, (tb * tx + 32) >> 6)
        i += 1
    0

-> h264_new_decoder(cfg)
  H264Dec.new(cfg)

vcodec_register("avc1", ->(cfg) H264Dec.new(cfg))
vcodec_register("avc3", ->(cfg) H264Dec.new(cfg))
vcodec_register("h264", ->(cfg) H264Dec.new(cfg))
