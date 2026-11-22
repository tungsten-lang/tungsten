# core/codec/video/hevc — an H.265 / HEVC decoder (ITU-T H.265) in pure Tungsten.
#
# HevcDecoder keeps the decoder state across access units: VPS/SPS/PPS maps,
# the decoded picture buffer (one u16[] holding every picture slot, so inter
# prediction can read references from the same buffer), POC and RPS state,
# and output (bumping) order. decode(sample) takes one access unit of
# length-prefixed (hvcC) or Annex B NAL units and returns the pictures that
# became ready, as VideoFrames in presentation order.
#
# Registered for HEIF items ("hvc1": a HEIC still / grid tile decodes as one
# access unit) and for the media pipeline (vcodec "hvc1" / "hev1").
#
# Files: hevc_tables (constants), hevc_cabac (bits + arithmetic decoder),
# hevc_ps (parameter sets, slice header), hevc_slice (CTU/CU/TU parsing),
# hevc_residual (coefficients, transforms), hevc_pred (intra), hevc_inter
# (inter prediction), hevc_filter (deblocking, SAO).

use core/codec/image/heif
use core/codec/media
use hevc_tables
use hevc_cabac
use hevc_ps
use hevc_slice
use hevc_residual
use hevc_pred
use hevc_inter
use hevc_filter

# One picture in the DPB.
+ HevcPicture
  rw :slot, :poc, :ref, :output, :sps, :w, :h, :id, :is_irap, :pts, :mv, :refpocs, :lt, :dur, :latency

  -> new(@slot, @poc, @sps)
    @ref = 0
    @output = false
    @id = 0
    @is_irap = false
    @pts = nil
    @mv = nil
    @refpocs = nil
    @lt = false
    @dur = nil
    @latency = 0

+ HevcDecoder
  rw :frames_out

  -> new(cfg = nil)
    @vps = {}
    @sps = {}
    @pps = {}
    @len_size = 4
    @tb = hv_tables()
    @cab = i64[HB_SIZE]
    @st = i64[HS_SIZE]
    @cf = i32[HF_SIZE]
    @dpb = []
    @px = nil
    @sao_src = nil
    @nslots = 0
    @slot_size = 0
    @active_sps = nil
    @pic = nil
    @first = true
    @prev_tid0_poc = 0
    @pic_count = 0
    @eos = false
    @pending = []
    @mp = nil
    @mv = nil
    @layout_key = nil
    @cur_pts = nil
    @cur_dur = nil
    @cfg = cfg
    @have_cfg = false
    if cfg != nil && cfg.extra != nil
      hv_parse_hvcc_into(self, cfg.extra)

  -> set_len_size(n)
    @len_size = n
    @have_cfg = true

  # ---- NAL handling

  -> nal(d, o, n)
    return nil if n < 2
    t = (d[o] >> 1) & 63
    layer = ((d[o] & 1) << 5) | (d[o + 1] >> 3)
    tid = (d[o + 1] & 7) - 1
    return nil if layer != 0
    if t == 32
      return nil
    if t == 33
      # a repeated, identical SPS must not reset decoding (DPB, layout caches)
      key = hv_bytes_key(d, o, n)
      r = hv_unescape(d, o + 2, n - 2)
      s = hv_parse_sps(r[0], r[1])
      old = @sps[s[:id]]
      return nil if old != nil && old[:key] == key
      s[:key] = key
      @sps[s[:id]] = s
      return nil
    if t == 34
      key = hv_bytes_key(d, o, n)
      r = hv_unescape(d, o + 2, n - 2)
      p = hv_parse_pps(r[0], r[1], @sps)
      old = @pps[p[:id]]
      return nil if old != nil && old[:key] == key && old[:sps_obj] == @sps[p[:sps]]
      p[:key] = key
      p[:sps_obj] = @sps[p[:sps]]
      @pps[p[:id]] = p
      return nil
    if t == 36 || t == 37
      finish_picture()
      @eos = true
      return nil
    if t <= 21 && (t <= 9 || t >= 16)
      slice(d, o, n, t, tid)
    nil

  # One access unit: NAL units with @len_size-byte length prefixes (or Annex B
  # start codes when the data begins with 00 00 01 / 00 00 00 01).
  -> decode_au(d)
    feed(d)
    finish_picture()

  # NAL units without completing the current picture (a partial access unit).
  -> feed(d)
    n = d.size
    # Annex B only without a configuration record: a 4-byte length such as
    # 00 00 01 34 looks like a start code
    if !@have_cfg && n >= 4 && d[0] == 0 && d[1] == 0 && (d[2] == 1 || (d[2] == 0 && d[3] == 1))
      hv_annexb_each(d, ->(o, l) nal(d, o, l))
    else
      o = 0
      while o + @len_size <= n
        l = 0
        k = 0
        while k < @len_size
          l = (l << 8) | d[o + k]
          k += 1
        o += @len_size
        raise HevcError.new("hevc: NAL length out of range") if o + l > n
        nal(d, o, l)
        o += l
    nil

  # ---- slices

  -> slice(d, o, n, t, tid)
    r = hv_unescape(d, o + 2, n - 2)
    rb = r[0]
    first = (rb[0] & 0x80) != 0
    irap = t >= 16 && t <= 23
    if first
      finish_picture()
    sh = hv_parse_slice_header(rb, r[1], t, @sps, @pps, @last_sh)
    sh[:dependent] ? nil : (@last_sh = sh)
    pps = @pps[sh[:pps_id]]
    sps = @sps[pps[:sps]]
    if first
      # RASL pictures after a CRA/BLA that starts decoding are not decodable
      nrof = irap && (t <= 20 || @first || @eos)
      if irap
        @no_rasl = nrof
      if (t == 8 || t == 9) && @no_rasl
        @skip_pic = true
        return nil
      @skip_pic = false
      start_picture(sps, pps, sh, t, tid, nrof)
    return nil if @skip_pic || @pic == nil
    decode_slice_data(rb, r[1], sh, sps, pps)
    nil

  -> start_picture(sps, pps, sh, t, tid, nrof)
    if t >= 16 && t <= 23 && nrof
      # IRAP with NoRaslOutputFlag (C.5.2.2): prior pictures are output, or
      # discarded when NoOutputOfPriorPicsFlag (always for a CRA); references dropped
      @dpb.each ->(p) p.ref = 0
      flush_output((sh[:no_output_prior] || t == 21) && !@first)
    activate_sps(sps)
    # POC (8.3.1)
    maxlsb = 1 << sps[:log2_poc]
    lsb = sh[:poc_lsb]
    msb = 0
    irap = t >= 16 && t <= 23
    if !(irap && nrof)
      plsb = @prev_tid0_poc & (maxlsb - 1)
      pmsb = @prev_tid0_poc - plsb
      if lsb < plsb && plsb - lsb >= maxlsb / 2
        msb = pmsb + maxlsb
      elsif lsb > plsb && lsb - plsb > maxlsb / 2
        msb = pmsb - maxlsb
      else
        msb = pmsb
    poc = msb + lsb
    slnr = t <= 14 && (t % 2) == 0
    if tid == 0 && !slnr && !(t >= 6 && t <= 9)
      @prev_tid0_poc = poc
    # reference picture set (8.3.2)
    hv_apply_rps(self, sps, sh, poc)
    bump(sps)
    slot = free_slot()
    pic = HevcPicture.new(slot, poc, sps)
    @pic_count += 1
    pic.id = @pic_count
    pic.is_irap = irap
    pic.ref = 1
    pic.output = sh[:pic_output]
    pic.pts = @cur_pts
    pic.dur = @cur_dur
    @dpb.push(pic)
    @pic = pic
    @last_poc = poc
    @first = false
    @eos = false
    @slices = []
    @pic_sps = sps
    @pic_pps = pps
    setup_picture(sps, pps)

  -> activate_sps(sps)
    if @active_sps != sps
      # pictures of the old sequence leave before the buffers are reshaped
      flush_output(false) if @dpb.size > 0
      @dpb = []
      @active_sps = sps
      ct = sps[:chroma_type]
      ssx = (ct == 1 || ct == 2) ? 1 : 0
      ssy = ct == 1 ? 1 : 0
      w = sps[:width]
      h = sps[:height]
      cw = ct == 0 ? 0 : (w >> ssx)
      ch = ct == 0 ? 0 : (h >> ssy)
      @slot_size = w * h + 2 * cw * ch
      need = sps[:max_dec].last + 2
      need = 2 if need < 2
      need = 18 if need > 18
      if @px == nil || @nslots < need || @px.size < need * @slot_size
        @nslots = need
        @px = u16[need * @slot_size]
      w4 = sps[:ctb_w] << (sps[:ctb] - 2)
      h4 = sps[:ctb_h] << (sps[:ctb] - 2)
      @w4 = w4
      @h4 = h4
      nctb = sps[:ctb_w] * sps[:ctb_h]
      @n4 = w4 * h4
      @nctb = nctb
      @mp = i32[@n4 * 7 + nctb * 34 + @nslots * @n4 * HMV_N]
      @layout_key = nil

  -> free_slot
    used = {}
    @dpb.each ->(p) used[p.slot] = true
    s = 0
    while s < @nslots
      return s if !used[s]
      s += 1
    # DPB overflow (non-conforming stream): evict the oldest non-reference
    victim = nil
    @dpb.each ->(p) victim = p if victim == nil && p.ref == 0
    victim = @dpb[0] if victim == nil
    emit(victim) if victim.output
    @dpb.delete(victim)
    victim.slot

  # Fill st registers that depend on SPS / PPS / picture, reset the maps.
  -> setup_picture(sps, pps)
    st = @st
    ct = sps[:chroma_type]
    ssx = (ct == 1 || ct == 2) ? 1 : 0
    ssy = ct == 1 ? 1 : 0
    w = sps[:width]
    h = sps[:height]
    st[HS_W] = w
    st[HS_H] = h
    st[HS_CT] = ct
    st[HS_SSX] = ssx
    st[HS_SSY] = ssy
    st[HS_BDY] = sps[:bd_y]
    st[HS_BDC] = sps[:bd_c]
    st[HS_CTB] = sps[:ctb]
    st[HS_MINCB] = sps[:min_cb]
    st[HS_MINTB] = sps[:min_tb]
    st[HS_MAXTB] = sps[:max_tb]
    st[HS_THD_INTRA] = sps[:thd_intra]
    st[HS_THD_INTER] = sps[:thd_inter]
    st[HS_SL] = sps[:sl_enabled] ? 1 : 0
    st[HS_AMP] = sps[:amp] ? 1 : 0
    st[HS_SAO_EN] = sps[:sao] ? 1 : 0
    st[HS_PCM] = sps[:pcm] ? 1 : 0
    if sps[:pcm]
      st[HS_PCM_BDY] = sps[:pcm_bd_y]
      st[HS_PCM_BDC] = sps[:pcm_bd_c]
      st[HS_PCM_MIN] = sps[:pcm_min]
      st[HS_PCM_MAX] = sps[:pcm_max]
      st[HS_PCM_LFDIS] = sps[:pcm_lf_dis] ? 1 : 0
    st[HS_STRONG] = sps[:strong] ? 1 : 0
    st[HS_TS_ROT] = sps[:ts_rot] ? 1 : 0
    st[HS_TS_CTX] = sps[:ts_ctx] ? 1 : 0
    st[HS_IMPL_RDPCM] = sps[:impl_rdpcm] ? 1 : 0
    st[HS_EXPL_RDPCM] = sps[:expl_rdpcm] ? 1 : 0
    st[HS_SMOOTH_DIS] = sps[:smooth_dis] ? 1 : 0
    st[HS_PERSIST_RICE] = sps[:persist_rice] ? 1 : 0
    st[HS_CTBW] = sps[:ctb_w]
    st[HS_CTBH] = sps[:ctb_h]
    st[HS_W4] = @w4
    st[HS_H4] = @h4
    st[HS_SIGNHIDE] = pps[:sign_hiding] ? 1 : 0
    st[HS_CIP] = pps[:cip] ? 1 : 0
    st[HS_TS] = pps[:ts] ? 1 : 0
    st[HS_LOG2MAXTS] = pps[:log2_max_ts]
    st[HS_CUQPD] = pps[:cuqpd] ? 1 : 0
    st[HS_LOG2QG] = sps[:ctb] - pps[:cuqpd_depth]
    st[HS_CBOFF] = pps[:cb_off]
    st[HS_CROFF] = pps[:cr_off]
    st[HS_TQB] = pps[:tq_bypass] ? 1 : 0
    st[HS_CROSS] = pps[:cross_comp] ? 1 : 0
    raise HevcError.new("hevc: cabac bypass alignment unsupported") if sps[:bypass_align]
    st[HS_CQPO_LIST] = pps[:cqpo_list] ? 1 : 0
    st[HS_LOG2CQPO] = sps[:ctb] - pps[:cqpo_depth]
    st[HS_CQPO_LEN] = pps[:cqpo_cb].size
    i = 0
    while i < pps[:cqpo_cb].size && i < 6
      st[HS_CQPO_CB + i] = pps[:cqpo_cb][i]
      st[HS_CQPO_CR + i] = pps[:cqpo_cr][i]
      i += 1
    st[HS_SAO_SHY] = pps[:sao_shift_y]
    st[HS_SAO_SHC] = pps[:sao_shift_c]
    st[HS_PARMRG] = pps[:par_merge]
    st[HS_LF_TILES_P] = pps[:lf_tiles] ? 1 : 0
    cw = ct == 0 ? 0 : (w >> ssx)
    ch = ct == 0 ? 0 : (h >> ssy)
    st[HS_CW] = cw
    st[HS_CH] = ch
    base = @pic.slot * @slot_size
    st[HS_PY] = base
    st[HS_PCB] = base + w * h
    st[HS_PCR] = base + w * h + cw * ch
    n4 = @n4
    nctb = @nctb
    st[HS_M_DEPTH] = 0
    st[HS_M_IPM] = n4
    st[HS_M_FLAGS] = 2 * n4
    st[HS_M_QP] = 3 * n4
    st[HS_M_EDGE] = 4 * n4
    st[HS_M_ZS] = 5 * n4
    st[HS_M_BS] = 6 * n4
    st[HS_C_SADDR] = 7 * n4
    st[HS_C_TILE] = 7 * n4 + nctb
    st[HS_C_RS2TS] = 7 * n4 + 2 * nctb
    st[HS_C_SIDX] = 7 * n4 + 3 * nctb
    st[HS_C_SAO] = 7 * n4 + 5 * nctb
    st[HS_C_SLT] = 7 * n4 + 26 * nctb
    st[HS_SAO_ANY] = 0
    st[HS_DBK_ANY] = 0
    key = [sps, pps]
    if @layout_key == nil || @layout_key[0] != sps || @layout_key[1] != pps
      @layout_key = key
      @layout = hv_tile_layout(sps, pps)
      hv_fill_layout(@mp, st, @layout, sps)
    hv_reset_maps(@mp, n4, nctb, 7 * n4)
    # scaling factors: PPS lists override SPS lists
    sf = nil
    if sps[:sl_enabled]
      sf = pps[:sl_data] != nil ? pps[:sl_data] : sps[:sl]
    hv_copy_sf(@cf, sf) if sf != nil
    st[HS_MV_BASE] = 7 * n4 + 34 * nctb
    st[HS_MV] = st[HS_MV_BASE] + @pic.slot * n4 * HMV_N
    hv_mv_reset(@mp, st[HS_MV], n4)
    hv_inter_picture_setup(self)
    nil

  # ---- slice data

  -> decode_slice_data(rb, size, sh, sps, pps)
    st = @st
    cab = @cab
    tb = @tb
    mp = @mp
    lay = @layout
    sidx = @slices.size
    @slices.push(sh)
    slt = st[HS_C_SLT] + sidx * 8
    mp[slt + HL_DBKDIS] = sh[:dbk_dis] ? 1 : 0
    mp[slt + HL_BETA] = sh[:beta]
    mp[slt + HL_TC] = sh[:tc]
    mp[slt + HL_LFS] = sh[:lf_slices] ? 1 : 0
    st[HS_DBK_ANY] = 1 if !sh[:dbk_dis]
    st[HS_SAO_ANY] = 1 if sh[:sao_luma] || sh[:sao_chroma]
    if !sh[:dependent]
      @slice_addr = sh[:addr]
    st[HS_SLICE_ADDR] = @slice_addr
    st[HS_SLICE_IDX] = sidx
    st[HS_STYPE] = sh[:type]
    st[HS_SQP] = sh[:qp]
    st[HS_SAO_L] = sh[:sao_luma] ? 1 : 0
    st[HS_SAO_C] = sh[:sao_chroma] ? 1 : 0
    st[HS_SCBOFF] = sh[:cb_off]
    st[HS_SCROFF] = sh[:cr_off]
    st[HS_CQPO_EN] = sh[:cqpo] ? 1 : 0
    st[HS_MAXMERGE] = sh[:max_merge]
    st[HS_NREF0] = sh[:nref0]
    st[HS_NREF1] = sh[:nref1]
    st[HS_MVDL1Z] = sh[:mvd_l1_zero] ? 1 : 0
    st[HS_CUQPO_CB] = 0
    st[HS_CUQPO_CR] = 0
    st[HS_ERROR] = 0
    init_type = 0
    if sh[:type] == 1
      init_type = sh[:cabac_init] ? 2 : 1
    elsif sh[:type] == 0
      init_type = sh[:cabac_init] ? 1 : 2
    hv_inter_slice_setup(self, sh) if sh[:type] != 2
    w = sps[:ctb_w]
    rs2ts = lay[:rs2ts]
    ts2rs = lay[:ts2rs]
    tileid = lay[:tileid]
    colbd = lay[:colbd]
    rowbd = lay[:rowbd]
    ts = rs2ts[sh[:addr]]
    total = w * sps[:ctb_h]
    hv_cabac_start(cab, rb, sh[:data_pos], size)
    rs = ts2rs[ts]
    # initial contexts
    first_in_tile = ts == 0 || tileid[ts] != tileid[ts - 1]
    ctbx = rs % w
    tx0 = hv_tile_start(colbd, ctbx)
    if !sh[:dependent] || first_in_tile
      hv_ctx_init(cab, tb, init_type, sh[:qp])
    elsif pps[:wpp] && ctbx == tx0
      wpp_sync(rs, w, tx0, init_type, sh, tileid, rs2ts, colbd)
    else
      hv_ctx_copy(cab, HB_DS, HB_CTX, HB_STAT_DS, HB_STAT)
    # qPY_PREV restarts at the first QG of a slice (not of a dependent segment), tile or WPP row
    if !sh[:dependent] || first_in_tile || (pps[:wpp] && ctbx == tx0)
      st[HS_LAST_QPY] = sh[:qp]
    first_ctb = true
    loop_on = true
    while loop_on
      rs = ts2rs[ts]
      ctbx = rs % w
      ctby = rs / w
      tx0 = hv_tile_start(colbd, ctbx)
      first_in_tile = ts == 0 || tileid[ts] != tileid[ts - 1]
      if !first_ctb
        if first_in_tile
          hv_ctx_init(cab, tb, init_type, sh[:qp])
          st[HS_LAST_QPY] = sh[:qp]
        elsif pps[:wpp] && ctbx == tx0
          wpp_sync(rs, w, tx0, init_type, sh, tileid, rs2ts, colbd)
          st[HS_LAST_QPY] = sh[:qp]
      first_ctb = false
      mp[st[HS_C_SADDR] + rs] = @slice_addr
      mp[st[HS_C_SIDX] + rs] = sidx
      st[HS_CTB_RS] = rs
      st[HS_CTB_TS] = ts
      st[HS_CTB_X] = ctbx << sps[:ctb]
      st[HS_CTB_Y] = ctby << sps[:ctb]
      if sh[:sao_luma] || sh[:sao_chroma]
        hv_sao(rb, cab, st, tb, mp)
      hv_cqt(rb, cab, st, tb, mp, @px, @cf, ctbx << sps[:ctb], ctby << sps[:ctb], sps[:ctb], 0)
      raise HevcError.new("hevc: inter prediction failed") if st[HS_ERROR] != 0
      eos = hv_term(cab, rb)
      if pps[:wpp] && (ctbx - tx0 == 1)
        hv_ctx_copy(cab, HB_CTX, HB_WPP, HB_STAT, HB_STAT_WPP)
      ts += 1
      if eos != 0 || ts >= total
        if pps[:dep_slices]
          hv_ctx_copy(cab, HB_CTX, HB_DS, HB_STAT, HB_STAT_DS)
        loop_on = false
      else
        nrs = ts2rs[ts]
        if tileid[ts] != tileid[ts - 1] || (pps[:wpp] && (nrs % w) == hv_tile_start(colbd, nrs % w))
          hv_term(cab, rb)
          hv_cabac_start(cab, rb, cab[HB_POS], size)
    nil

  -> wpp_sync(rs, w, tx0, init_type, sh, tileid, rs2ts, colbd)
    st = @st
    mp = @mp
    # top-right CTB (x + 1, y - 1) available: in the same slice and tile, decoded
    ctbx = rs % w
    ctby = rs / w
    ok = false
    if ctby > 0 && ctbx + 1 < w
      tr = rs - w + 1
      if mp[st[HS_C_SADDR] + tr] == @slice_addr && tileid[rs2ts[tr]] == tileid[rs2ts[rs]]
        ok = true
    if ok
      hv_ctx_copy(@cab, HB_WPP, HB_CTX, HB_STAT_WPP, HB_STAT)
    else
      hv_ctx_init(@cab, @tb, init_type, sh[:qp])

  # ---- picture completion

  -> finish_picture
    return nil if @pic == nil
    st = @st
    if st[HS_DBK_ANY] != 0
      hv_deblock(st, @mp, @tb, @px)
    if st[HS_SAO_ANY] != 0 && st[HS_SAO_EN] != 0
      # SAO reads the deblocked picture: one copy, in a buffer kept across
      # pictures (allocating it per picture leaked a picture's worth each time)
      if @sao_src == nil || @sao_src.size != @slot_size
        ccall("w_value_free_w", @sao_src) if @sao_src != nil
        @sao_src = u16[@slot_size]
      src = @sao_src
      hv_copy_u16(@px, st[HS_PY], src, 0, @slot_size)
      hv_sao_apply(st, @mp, @px, src)
    @pic.w = @pic_sps[:width]
    @pic.h = @pic_sps[:height]
    cur = @pic
    @dpb.each ->(p) p.latency = p.latency + 1 if p.output && p != cur
    @pic = nil
    bump(@pic_sps)
    nil

  # C.5.2: output pictures while more are waiting than the reorder depth allows.
  # (a plain loop: `waiting.any?(->(p) p.latency >= maxlat)` crashed --release
  # builds, the closure's environment arriving null under TUNGSTEN_FREE)
  -> hv_any_late(waiting, maxlat)
    i = 0
    while i < waiting.size
      return true if waiting[i].latency >= maxlat
      i += 1
    false

  -> bump(sps)
    reorder = sps[:max_reorder].last
    maxdec = sps[:max_dec].last
    lat = sps[:max_latency].last
    maxlat = lat > 0 ? reorder + lat - 1 : 0
    loop_on = true
    while loop_on
      waiting = @dpb.select(->(p) p.output && p != @pic)
      if waiting.size > reorder || (@dpb.size >= maxdec + 1 && waiting.size > 0)
        best = waiting[0]
        waiting.each ->(p) best = p if p.poc < best.poc
        emit(best)
      elsif maxlat > 0 && hv_any_late(waiting, maxlat)
        best = waiting[0]
        waiting.each ->(p) best = p if p.poc < best.poc
        emit(best)
      else
        loop_on = false
      @dpb = @dpb.select(->(p) p.ref != 0 || p.output || p == @pic)
    nil

  -> flush_output(discard)
    loop_on = true
    while loop_on
      waiting = @dpb.select(->(p) p.output && p != @pic)
      if waiting.size == 0
        loop_on = false
      else
        best = waiting[0]
        waiting.each ->(p) best = p if p.poc < best.poc
        if discard
          best.output = false
        else
          emit(best)
    @dpb = @dpb.select(->(p) p.ref != 0 || p == @pic)
    nil

  -> emit(p)
    p.output = false
    @pending.push(picture_planes(p))
    nil

  # Cropped planes of a picture: [w, h, sps, [u16[] y, cb, cr]]
  -> picture_planes(p)
    sps = p.sps
    ct = sps[:chroma_type]
    ssx = (ct == 1 || ct == 2) ? 1 : 0
    ssy = ct == 1 ? 1 : 0
    w = sps[:width]
    h = sps[:height]
    cw = ct == 0 ? 0 : (w >> ssx)
    ch = ct == 0 ? 0 : (h >> ssy)
    sw = ct == 0 || ct == 3 ? 1 : 2
    shh = ct == 1 ? 2 : 1
    cf = sps[:conf]
    x0 = cf[0] * sw
    x1 = w - cf[1] * sw
    y0 = cf[2] * shh
    y1 = h - cf[3] * shh
    ow = x1 - x0
    oh = y1 - y0
    raise HevcError.new("hevc: bad conformance window") if ow <= 0 || oh <= 0
    base = p.slot * @slot_size
    planes = []
    yp = u16[ow * oh]
    hv_crop(@px, base, w, x0, y0, yp, ow, oh)
    planes.push(yp)
    if ct != 0
      ocw = ow >> ssx
      och = oh >> ssy
      ocw = (ow + (1 << ssx) - 1) >> ssx
      och = (oh + (1 << ssy) - 1) >> ssy
      cb = u16[ocw * och]
      cr = u16[ocw * och]
      hv_crop(@px, base + w * h, cw, x0 >> ssx, y0 >> ssy, cb, ocw, och)
      hv_crop(@px, base + w * h + cw * ch, cw, x0 >> ssx, y0 >> ssy, cr, ocw, och)
      planes.push(cb)
      planes.push(cr)
    {w: ow, h: oh, sps: sps, planes: planes, poc: p.poc, pts: p.pts, dur: p.dur}

  -> take_pending
    out = @pending
    @pending = []
    out

  -> flush_all
    finish_picture()
    flush_output(false)
    take_pending()

  -> reset
    @pic = nil
    @dpb = []
    @pending = []
    @first = true
    @eos = false
    @last_sh = nil
    nil

  # ---- mediacore interface

  -> decode(sample)
    data = sample.is_a?(MediaSample) ? sample.data : sample
    if sample.is_a?(MediaSample)
      @cur_pts = sample.pts
      @cur_dur = sample.duration
    decode_au(data)
    take_pending().map(->(e) hv_video_frame(e))

  -> flush
    flush_all().map(->(e) hv_video_frame(e))

  rw :dpb, :px, :mp, :mv, :st, :tb, :cf, :cab, :slot_size, :pic, :pic_sps, :pic_pps, :nslots, :n4

# ---------------------------------------------------------------- helpers

-> hv_bytes_key(d, o, n0)
  n = n0
  # trailing_zero_8bits are not part of the parameter set
  n -= 1 while n > 0 && d[o + n - 1] == 0
  sb = StringBuffer()
  i = 0
  while i < n
    sb.append(d[o + i].chr)
    i += 1
  sb.to_s

-> hv_tile_start(colbd, x)
  s = 0
  i = 0
  while i < colbd.size - 1
    s = colbd[i] if x >= colbd[i]
    i += 1
  s

-> hv_copy_u16(src, so, dst, d0, n) (u16[] i64 u16[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  0

-> hv_crop(px, base, stride, x0, y0, out, ow, oh) (u16[] i64 i64 i64 i64 u16[] i64 i64) i64
  y = 0 ## i64
  while y < oh
    s = (base + (y0 + y) * stride + x0) ## i64
    o = (y * ow) ## i64
    x = 0 ## i64
    while x < ow
      out[o + x] = px[s + x]
      x += 1
    y += 1
  0

-> hv_copy_sf(cf, sf) (i32[] i32[]) i64
  i = 0 ## i64
  while i < 8160
    cf[HF_SF + i] = sf[i]
    i += 1
  0

-> hv_reset_maps(mp, n4, nctb, cbase) (i32[] i64 i64 i64) i64
  # depth, ipm, flags, qp, edge, bs (skip zs at 5*n4)
  i = 0 ## i64
  while i < 5 * n4
    mp[i] = 0
    i += 1
  i = 6 * n4
  while i < 7 * n4
    mp[i] = 0
    i += 1
  i = 0
  while i < nctb
    mp[cbase + i] = -1
    i += 1
  0

# z-scan order per 4x4 (6.5.2), tile ids, rs->ts into the maps.
-> hv_fill_layout(mp, st, lay, sps)
  w4 = st[HS_W4]
  h4 = st[HS_H4]
  l = sps[:ctb]
  cw = sps[:ctb_w]
  nctb = cw * sps[:ctb_h]
  rs2ts = lay[:rs2ts]
  tileid = lay[:tileid]
  hv_fill_zs(mp, st[HS_M_ZS], w4, h4, l - 2, cw, rs2ts)
  i = 0
  while i < nctb
    mp[st[HS_C_TILE] + i] = tileid[rs2ts[i]]
    mp[st[HS_C_RS2TS] + i] = rs2ts[i]
    i += 1
  nil

-> hv_fill_zs(mp, zo, w4, h4, sh, cw, rs2ts) (i32[] i64 i64 i64 i64 i64 i32[]) i64
  y = 0 ## i64
  while y < h4
    x = 0 ## i64
    while x < w4
      tbx = (x >> sh) ## i64
      tby = (y >> sh) ## i64
      v = (rs2ts[tby * cw + tbx] << (sh * 2)) ## i64
      p = 0 ## i64
      i = 0 ## i64
      while i < sh
        m = (1 << i) ## i64
        if (m & x) != 0
          p += m * m
        if (m & y) != 0
          p += 2 * m * m
        i += 1
      mp[zo + y * w4 + x] = v + p
      x += 1
    y += 1
  0

# Annex B: call f(offset, length) for each NAL unit.
-> hv_annexb_each(d, f)
  n = d.size
  i = 0
  starts = []
  while i + 2 < n
    if d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1
      starts.push(i + 3)
      i += 3
    else
      i += 1
  k = 0
  while k < starts.size
    s = starts[k]
    e = k + 1 < starts.size ? starts[k + 1] - 3 : n
    while e > s && d[e - 1] == 0
      e -= 1
    f.call(s, e - s)
    k += 1
  nil

# hvcC (ISO/IEC 14496-15 8.3.3): length size and parameter-set NAL units.
-> hv_parse_hvcc_into(dec, c)
  return nil if c.size < 23
  dec.set_len_size((c[21] & 3) + 1)
  na = c[22]
  o = 23
  a = 0
  while a < na && o + 3 <= c.size
    cnt = (c[o + 1] << 8) | c[o + 2]
    o += 3
    j = 0
    while j < cnt && o + 2 <= c.size
      l = (c[o] << 8) | c[o + 1]
      o += 2
      raise HevcError.new("hevc: bad hvcC") if o + l > c.size
      dec.nal(c, o, l)
      o += l
      j += 1
    a += 1
  nil

-> hv_cicp(sps)
  return nil if sps[:cp] == nil && !sps[:full_range]
  cp = sps[:cp] == nil ? 2 : sps[:cp]
  tc = sps[:tc] == nil ? 2 : sps[:tc]
  mc = sps[:mc] == nil ? 2 : sps[:mc]
  [cp, tc, mc, sps[:full_range]]

# Pictures with chroma bit depth != luma bit depth (rare RExt streams) are
# delivered at the luma bit depth: VideoFrame / HeifPic carry one depth.
-> hv_same_depth(e)
  sps = e[:sps]
  if sps[:bd_c] != sps[:bd_y] && e[:planes].size == 3
    k = 1
    while k < 3
      hv_rescale(e[:planes][k], e[:planes][k].size, sps[:bd_c], sps[:bd_y])
      k += 1
  e

-> hv_rescale(p, n, from, to) (u16[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    if to > from
      p[i] = p[i] << (to - from)
    else
      v = ((p[i] + (1 << (from - to - 1))) >> (from - to)) ## i64
      v = (1 << to) - 1 if v > (1 << to) - 1
      p[i] = v
    i += 1
  0

-> hv_video_frame(e0)
  e = hv_same_depth(e0)
  sps = e[:sps]
  ct = sps[:chroma_type]
  chroma = ["400", "420", "422", "444"][ct]
  bd = sps[:bd_y]
  planes = []
  strides = []
  # the cropped planes were allocated for this frame alone: an 8-bit frame
  # gets byte copies (the u16 originals are released here) and the consumer
  # owns whatever the frame holds (VideoFrame#owned)
  e[:planes].each ->(p)
    if bd == 8
      b = ByteArray.new(p.size)
      hv_u16_to_u8(p, b, p.size)
      planes.push(b)
      ccall("w_value_free_w", p)
    else
      planes.push(p)
  w = e[:w]
  h = e[:h]
  strides.push(w)
  if ct != 0
    ssx = (ct == 1 || ct == 2) ? 1 : 0
    strides.push((w + (1 << ssx) - 1) >> ssx)
    strides.push((w + (1 << ssx) - 1) >> ssx)
  f = VideoFrame.new(w, h, planes, strides, chroma, bd, e[:pts])
  f.owned = true
  f.duration = e[:dur] if e[:dur] != nil
  c = hv_cicp(sps)
  if c != nil
    f.primaries = c[0]
    f.transfer = c[1]
    f.matrix = c[2]
    f.full_range = c[3]
  f

-> hv_u16_to_u8(p, b, n) (u16[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = p[i]
    i += 1
  0

# ---------------------------------------------------------------- RPS

-> hv_apply_rps(dec, sps, sh, poc)
  dpb = dec.dpb
  t = sh[:nal_type]
  if t == 19 || t == 20
    dpb.each ->(p) p.ref = 0
    dec.rps_lists = [[], [], []]
    return nil
  maxlsb = 1 << sps[:log2_poc]
  before = []
  after = []
  ltc = []
  keep = []
  r = sh[:st_rps]
  if r != nil
    i = 0
    while i < r[:neg].size
      pc = poc + r[:neg][i]
      pic = dpb.find(->(p) p.ref == 1 && !p.lt && p.poc == pc)
      pic = dec.missing_ref(pc) if pic == nil && r[:negu][i]
      if pic != nil
        keep.push(pic)
        before.push(pic) if r[:negu][i]
      i += 1
    i = 0
    while i < r[:pos].size
      pc = poc + r[:pos][i]
      pic = dpb.find(->(p) p.ref == 1 && !p.lt && p.poc == pc)
      pic = dec.missing_ref(pc) if pic == nil && r[:posu][i]
      if pic != nil
        keep.push(pic)
        after.push(pic) if r[:posu][i]
      i += 1
  sh[:lt].each ->(e)
    pl = e[:lsb]
    full = e[:msb_present]
    if full
      pl = pl + poc - e[:msb_cycle] * maxlsb - (poc & (maxlsb - 1))
    pic = nil
    dpb.each ->(p)
      if p.ref == 1 && pic == nil
        pic = p if (full && p.poc == pl) || (!full && (p.poc & (maxlsb - 1)) == pl)
    pic = dec.missing_ref(pl) if pic == nil && e[:used]
    if pic != nil
      pic.lt = true
      keep.push(pic)
      ltc.push(pic) if e[:used]
  dpb.each ->(p)
    p.ref = 0 if !keep.include?(p)
  dec.rps_lists = [before, after, ltc]
  nil

+ HevcDecoder
  rw :rps_lists, :ref_lists, :last_poc

  # A reference the stream needs but we don't have (decoding started at a CRA,
  # or packet loss): a mid-grey picture (8.3.3).
  -> missing_ref(poc)
    sps = @active_sps
    slot = free_slot()
    p = HevcPicture.new(slot, poc, sps)
    p.ref = 1
    p.output = false
    p.w = sps[:width]
    p.h = sps[:height]
    @pic_count += 1
    p.id = @pic_count
    hv_fill_grey(@px, slot * @slot_size, @slot_size, sps[:width] * sps[:height], 1 << (sps[:bd_y] - 1), 1 << (sps[:bd_c] - 1))
    hv_mv_reset(@mp, 7 * @n4 + 34 * @nctb + slot * @n4 * HMV_N, @n4)
    @dpb.push(p)
    p

-> hv_mv_reset(mp, o, n4) (i32[] i64 i64) i64
  i = 0 ## i64
  while i < n4
    b = (o + i * HMV_N) ## i64
    k = 0 ## i64
    while k < HMV_N
      mp[b + k] = 0
      k += 1
    mp[b + 4] = -1
    mp[b + 5] = -1
    mp[b + 6] = -1
    mp[b + 7] = -1
    i += 1
  0

-> hv_fill_grey(px, base, n, ny, vy, vc) (u16[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    px[base + i] = i < ny ? vy : vc
    i += 1
  0

# ---------------------------------------------------------------- HEIF glue

# Decode one HEIF item (an HEVC access unit) to a HeifPic.
-> hv_heif_decode(f, it, data)
  cfgp = it.prop("hvcC")
  raise HeifError.new("heif: hvc1 item without hvcC") if cfgp == nil
  key = cfgp.f[:data]
  dec = HV_HEIF_DEC[0]
  if dec == nil || HV_HEIF_DEC[1] != key
    dec = HevcDecoder.new(nil)
    hv_parse_hvcc_into(dec, key)
    HV_HEIF_DEC[0] = dec
    HV_HEIF_DEC[1] = key
  dec.reset()
  # predictively coded items ('pred' references, HEIF 6.4.9): decode the
  # referenced items first, in order, with the same decoder
  chain = []
  hv_pred_chain(f, it, chain, 0)
  chain.each ->(x)
    dec.decode_au(x == it ? data : heif_item_data(f, x))
  want = dec.last_poc
  out = dec.flush_all()
  raise HeifError.new("heif: HEVC item produced no picture") if out.size == 0
  pick = out.last
  out.each ->(e) pick = e if e[:poc] == want
  hv_heif_pic(pick)

-> hv_pred_chain(f, it, chain, depth)
  raise HeifError.new("heif: pred chain too deep") if depth > 64
  it.ref("pred").each ->(id)
    r = f.item(id)
    raise HeifError.new("heif: missing pred reference") if r == nil
    hv_pred_chain(f, r, chain, depth + 1) if !chain.include?(r)
  chain.push(it) if !chain.include?(it)
  nil

HV_HEIF_DEC = [nil, nil]

-> hv_heif_pic(e0)
  e = hv_same_depth(e0)
  sps = e[:sps]
  ct = sps[:chroma_type]
  ssx = (ct == 1 || ct == 2) ? 1 : 0
  ssy = ct == 1 ? 1 : 0
  pic = HeifPic.new(e[:w], e[:h], sps[:bd_y], ssx, ssy, ct == 0)
  pic.planes = e[:planes]
  pic.cicp = hv_cicp(sps)
  pic

-> hv_heif_track(cfg, sample)
  dec = HevcDecoder.new(nil)
  hv_parse_hvcc_into(dec, cfg) if cfg != nil
  dec.decode_au(sample)
  out = dec.flush_all()
  raise HeifError.new("heif: HEVC track produced no picture") if out.size == 0
  hv_heif_pic(out[0])

heif_codec_register("hvc1", ->(f, it, data) hv_heif_decode(f, it, data))
heif_codec_register("track:hvc1", ->(cfg, sample) hv_heif_track(cfg, sample))
vcodec_register("hvc1", ->(cfg) HevcDecoder.new(cfg))
vcodec_register("hev1", ->(cfg) HevcDecoder.new(cfg))
