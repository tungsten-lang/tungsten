# core/codec/video/hevc_ps — HEVC parameter sets and slice segment headers (7.3.2,
# 7.3.6): SPS (with VUI, scaling lists, short-term RPS, range extension), PPS
# (tiles, deblocking control, range extension) and the slice header (RPS,
# reference list modification, prediction weights, entry points).
#
# Parameter sets are Hashes with symbol keys. Scaling lists are expanded to
# ScalingFactor arrays (i32[] of 8160: sizeId 0..3 x matrixId 0..5, raster
# order within each m[x][y] as m[y * n + x]).

use hevc_cabac

HV_SF_OFF = [0, 96, 480, 2016]

# ---------------------------------------------------------------- profile/tier/level

-> hv_ptl(b, max_sub)
  b.skip(8)
  b.skip(32)
  b.skip(4)
  b.skip(43)
  b.skip(1)
  b.skip(8)
  pp = []
  lp = []
  i = 0
  while i < max_sub
    pp.push(b.flag())
    lp.push(b.flag())
    i += 1
  if max_sub > 0
    i = max_sub
    while i < 8
      b.skip(2)
      i += 1
  i = 0
  while i < max_sub
    b.skip(88) if pp[i]
    b.skip(8) if lp[i]
    i += 1
  nil

# ---------------------------------------------------------------- scaling lists

# Default lists in coefficient (diagonal scan) order: sl[sizeId][matrixId] = [list, dc]
-> hv_sl_default
  out = []
  s = 0
  while s < 4
    row = []
    m = 0
    while m < 6
      if s == 0
        row.push([Array.new(16, 16), 16])
      else
        row.push([m < 3 ? HV_SL_INTRA.dup : HV_SL_INTER.dup, 16])
      m += 1
    out.push(row)
    s += 1
  out

-> hv_scaling_list_data(b, chroma444)
  sl = hv_sl_default()
  s = 0
  while s < 4
    m = 0
    while m < 6
      step = s == 3 ? 3 : 1
      if b.flag()
        n = s == 0 ? 16 : 64
        nxt = 8
        dc = 16
        if s > 1
          dc = b.se() + 8
          nxt = dc
        lst = []
        i = 0
        while i < n
          d = b.se()
          nxt = (nxt + d + 256) % 256
          lst.push(nxt)
          i += 1
        dc = lst[0] if s <= 1
        sl[s][m] = [lst, dc]
      else
        delta = b.ue()
        if delta != 0
          ref = m - delta * step
          sl[s][m] = [sl[s][ref][0].dup, sl[s][ref][1]]
        else
          d = hv_sl_default()
          sl[s][m] = d[s][m]
      m += step
    s += 1
  # 32x32 chroma (ChromaArrayType 3): from the 16x16 lists' coefficients
  if chroma444
    [1, 2, 4, 5].each ->(m)
      sl[3][m] = [sl[2][m][0].dup, sl[2][m][1]]
  else
    [1, 2, 4, 5].each ->(m)
      sl[3][m] = [sl[2][m][0].dup, sl[2][m][1]]
  sl

# Expand lists into ScalingFactor (7.4.5).
-> hv_scaling_factors(sl)
  tb = hv_tables()
  f = i32[8160]
  s = 0
  while s < 4
    n = 4 << s
    m = 0
    while m < 6
      lst = sl[s][m][0]
      base = HV_SF_OFF[s] + m * n * n
      if s == 0
        i = 0
        while i < 16
          x = tb[HT_SCAN + (2 * 3) * 128 + 2 * i]
          y = tb[HT_SCAN + (2 * 3) * 128 + 2 * i + 1]
          f[base + y * 4 + x] = lst[i]
          i += 1
      else
        rep = n / 8
        i = 0
        while i < 64
          x = tb[HT_SCAN + (3 * 3) * 128 + 2 * i]
          y = tb[HT_SCAN + (3 * 3) * 128 + 2 * i + 1]
          j = 0
          while j < rep
            k = 0
            while k < rep
              f[base + (y * rep + j) * n + x * rep + k] = lst[i]
              k += 1
            j += 1
          i += 1
        f[base] = sl[s][m][1] if s >= 2
      m += 1
    s += 1
  f

-> hv_flat_factors
  f = i32[8160]
  i = 0
  while i < 8160
    f[i] = 16
    i += 1
  f

# ---------------------------------------------------------------- short-term RPS

# Returns {neg: [dpoc...], negu: [used...], pos:, posu:}
-> hv_st_rps(b, idx, num, sets)
  inter = false
  inter = b.flag() if idx != 0
  if inter
    di = 0
    di = b.ue() if idx == num
    ref = sets[idx - (di + 1)]
    sign = b.u(1)
    absd = b.ue() + 1
    drps = sign == 1 ? 0 - absd : absd
    nd = ref[:neg].size + ref[:pos].size
    used = []
    usedelta = []
    j = 0
    while j <= nd
      u = b.flag()
      used.push(u)
      ud = true
      ud = b.flag() if !u
      usedelta.push(ud)
      j += 1
    nn = ref[:neg].size
    np = ref[:pos].size
    neg = []
    negu = []
    j = np - 1
    while j >= 0
      dp = ref[:pos][j] + drps
      if dp < 0 && usedelta[nn + j]
        neg.push(dp)
        negu.push(used[nn + j])
      j -= 1
    if drps < 0 && usedelta[nd]
      neg.push(drps)
      negu.push(used[nd])
    j = 0
    while j < nn
      dp = ref[:neg][j] + drps
      if dp < 0 && usedelta[j]
        neg.push(dp)
        negu.push(used[j])
      j += 1
    pos = []
    posu = []
    j = nn - 1
    while j >= 0
      dp = ref[:neg][j] + drps
      if dp > 0 && usedelta[j]
        pos.push(dp)
        posu.push(used[j])
      j -= 1
    if drps > 0 && usedelta[nd]
      pos.push(drps)
      posu.push(used[nd])
    j = 0
    while j < np
      dp = ref[:pos][j] + drps
      if dp > 0 && usedelta[nn + j]
        pos.push(dp)
        posu.push(used[nn + j])
      j += 1
    return {neg: neg, negu: negu, pos: pos, posu: posu}
  nneg = b.ue()
  npos = b.ue()
  raise HevcError.new("hevc: bad RPS") if nneg > 16 || npos > 16
  neg = []
  negu = []
  pos = []
  posu = []
  p = 0
  i = 0
  while i < nneg
    p = p - (b.ue() + 1)
    neg.push(p)
    negu.push(b.flag())
    i += 1
  p = 0
  i = 0
  while i < npos
    p = p + b.ue() + 1
    pos.push(p)
    posu.push(b.flag())
    i += 1
  {neg: neg, negu: negu, pos: pos, posu: posu}

# ---------------------------------------------------------------- VUI / HRD

-> hv_sub_hrd(b, cnt, subpic)
  k = 0
  while k <= cnt
    b.ue()
    b.ue()
    if subpic
      b.ue()
      b.ue()
    b.skip(1)
    k += 1
  nil

-> hv_hrd(b, common, max_sub)
  nal = false
  vcl = false
  subpic = false
  if common
    nal = b.flag()
    vcl = b.flag()
    if nal || vcl
      subpic = b.flag()
      b.skip(8 + 5 + 1 + 5) if subpic
      b.skip(8)
      b.skip(4) if subpic
      b.skip(15)
  i = 0
  while i <= max_sub
    fixed_gen = b.flag()
    fixed_cvs = true
    fixed_cvs = b.flag() if !fixed_gen
    low_delay = false
    if fixed_cvs
      b.ue()
    else
      low_delay = b.flag()
    cnt = 0
    cnt = b.ue() if !low_delay
    hv_sub_hrd(b, cnt, subpic) if nal
    hv_sub_hrd(b, cnt, subpic) if vcl
    i += 1
  nil

-> hv_vui(b, s)
  if b.flag()
    idc = b.u(8)
    b.skip(32) if idc == 255
  b.skip(1) if b.flag()
  if b.flag()
    b.skip(3)
    s[:full_range] = b.flag()
    if b.flag()
      s[:cp] = b.u(8)
      s[:tc] = b.u(8)
      s[:mc] = b.u(8)
  if b.flag()
    b.ue()
    b.ue()
  b.skip(3)
  if b.flag()
    b.ue()
    b.ue()
    b.ue()
    b.ue()
  if b.flag()
    s[:num_units_in_tick] = b.u(32)
    s[:time_scale] = b.u(32)
    b.ue() if b.flag()
    hv_hrd(b, true, s[:max_sub]) if b.flag()
  if b.flag()
    b.skip(3)
    b.ue()
    b.ue()
    b.ue()
    b.ue()
    b.ue()
  nil

# Parameter-set range checks (H.265 7.4.3 semantics and level 6.2 limits):
# every size later used to allocate or index buffers is validated here, so a
# corrupt or unsupported stream raises HevcError instead of over-allocating.
-> hv_req(cond, msg)
  raise HevcError.new("hevc: " + msg) if !cond
  nil

# ---------------------------------------------------------------- SPS

-> hv_parse_sps(d, n)
  b = HevcBits.new(d, n)
  s = {}
  s[:vps] = b.u(4)
  ms = b.u(3)
  s[:max_sub] = ms
  b.skip(1)
  hv_ptl(b, ms)
  s[:id] = b.ue()
  hv_req(s[:id] <= 15, "SPS id [s[:id]] out of range")
  cf = b.ue()
  hv_req(cf <= 3, "bad chroma_format_idc [cf]")
  sep = false
  sep = b.flag() if cf == 3
  s[:chroma_format] = cf
  s[:separate_planes] = sep
  s[:chroma_type] = sep ? 0 : cf
  s[:width] = b.ue()
  s[:height] = b.ue()
  hv_req(s[:width] > 0 && s[:height] > 0 && s[:width] <= 16888 && s[:height] <= 16888 && s[:width] * s[:height] <= 35651584,
         "picture size [s[:width]]x[s[:height]] out of range")
  s[:conf] = [0, 0, 0, 0]
  if b.flag()
    s[:conf] = [b.ue(), b.ue(), b.ue(), b.ue()]
    sw = (cf == 1 || cf == 2) && !sep ? 2 : 1
    shh = cf == 1 && !sep ? 2 : 1
    hv_req((s[:conf][0] + s[:conf][1]) * sw < s[:width] && (s[:conf][2] + s[:conf][3]) * shh < s[:height], "conformance window outside the picture")
  s[:bd_y] = b.ue() + 8
  s[:bd_c] = b.ue() + 8
  hv_req(s[:bd_y] <= 16 && s[:bd_c] <= 16, "unsupported bit depth [s[:bd_y]]/[s[:bd_c]]")
  s[:log2_poc] = b.ue() + 4
  hv_req(s[:log2_poc] <= 16, "log2_max_pic_order_cnt out of range")
  sub_order = b.flag()
  s[:max_dec] = []
  s[:max_reorder] = []
  s[:max_latency] = []
  i = sub_order ? 0 : ms
  while i <= ms
    md = b.ue() + 1
    mr = b.ue()
    hv_req(md <= 16 && mr < md, "DPB size out of range")
    s[:max_dec].push(md)
    s[:max_reorder].push(mr)
    s[:max_latency].push(b.ue())
    i += 1
  s[:min_cb] = b.ue() + 3
  hv_req(s[:min_cb] <= 6, "bad minimum CB size")
  s[:ctb] = s[:min_cb] + b.ue()
  hv_req(s[:ctb] >= 4 && s[:ctb] <= 6, "bad CTB size")
  hv_req(s[:width] % (1 << s[:min_cb]) == 0 && s[:height] % (1 << s[:min_cb]) == 0, "picture size not a multiple of the minimum CB size")
  s[:min_tb] = b.ue() + 2
  hv_req(s[:min_tb] < s[:min_cb], "bad minimum TB size")
  s[:max_tb] = s[:min_tb] + b.ue()
  hv_req(s[:max_tb] <= 5 && s[:max_tb] <= s[:ctb], "bad maximum TB size")
  s[:thd_inter] = b.ue()
  s[:thd_intra] = b.ue()
  hv_req(s[:thd_inter] <= s[:ctb] - s[:min_tb] && s[:thd_intra] <= s[:ctb] - s[:min_tb], "transform hierarchy too deep")
  s[:sl_enabled] = b.flag()
  s[:sl] = nil
  if s[:sl_enabled]
    if b.flag()
      s[:sl] = hv_scaling_factors(hv_scaling_list_data(b, s[:chroma_type] == 3))
    else
      s[:sl] = hv_scaling_factors(hv_sl_default())
  s[:amp] = b.flag()
  s[:sao] = b.flag()
  s[:pcm] = b.flag()
  if s[:pcm]
    s[:pcm_bd_y] = b.u(4) + 1
    s[:pcm_bd_c] = b.u(4) + 1
    hv_req(s[:pcm_bd_y] <= s[:bd_y] && s[:pcm_bd_c] <= s[:bd_c], "PCM bit depth exceeds the coded bit depth")
    s[:pcm_min] = b.ue() + 3
    s[:pcm_max] = s[:pcm_min] + b.ue()
    hv_req(s[:pcm_min] >= s[:min_cb] && s[:pcm_max] <= 5 && s[:pcm_max] <= s[:ctb], "bad PCM block sizes")
    s[:pcm_lf_dis] = b.flag()
  nst = b.ue()
  raise HevcError.new("hevc: too many RPS") if nst > 64
  s[:num_st] = nst
  sets = []
  i = 0
  while i < nst
    sets.push(hv_st_rps(b, i, nst, sets))
    i += 1
  s[:st_rps] = sets
  s[:lt_present] = b.flag()
  s[:lt_sps] = []
  if s[:lt_present]
    k = b.ue()
    hv_req(k <= 32, "too many long-term reference pictures")
    i = 0
    while i < k
      s[:lt_sps].push([b.u(s[:log2_poc]), b.flag()])
      i += 1
  s[:tmvp] = b.flag()
  s[:strong] = b.flag()
  s[:full_range] = false
  s[:cp] = nil
  if b.flag()
    hv_vui(b, s)
  s[:ts_rot] = false
  s[:ts_ctx] = false
  s[:impl_rdpcm] = false
  s[:expl_rdpcm] = false
  s[:ext_prec] = false
  s[:smooth_dis] = false
  s[:hp_offsets] = false
  s[:persist_rice] = false
  s[:bypass_align] = false
  if b.flag()
    rng = b.flag()
    b.skip(7)
    if rng
      s[:ts_rot] = b.flag()
      s[:ts_ctx] = b.flag()
      s[:impl_rdpcm] = b.flag()
      s[:expl_rdpcm] = b.flag()
      s[:ext_prec] = b.flag()
      s[:smooth_dis] = b.flag()
      s[:hp_offsets] = b.flag()
      s[:persist_rice] = b.flag()
      s[:bypass_align] = b.flag()
  raise HevcError.new("hevc: unsupported bit depth") if s[:bd_y] > 16 || s[:bd_c] > 16
  raise HevcError.new("hevc: extended precision unsupported") if s[:ext_prec]
  raise HevcError.new("hevc: bad CTB size") if s[:ctb] < 4 || s[:ctb] > 6 || s[:max_tb] > 5 || s[:max_tb] > s[:ctb]
  raise HevcError.new("hevc: bad picture size") if s[:width] <= 0 || s[:height] <= 0 || s[:width] * s[:height] > 200000000
  ctbs = 1 << s[:ctb]
  s[:ctb_w] = (s[:width] + ctbs - 1) >> s[:ctb]
  s[:ctb_h] = (s[:height] + ctbs - 1) >> s[:ctb]
  s

# ---------------------------------------------------------------- PPS

-> hv_parse_pps(d, n, spss)
  b = HevcBits.new(d, n)
  p = {}
  p[:id] = b.ue()
  p[:sps] = b.ue()
  hv_req(p[:id] <= 63 && p[:sps] <= 15, "PPS/SPS id out of range")
  p[:dep_slices] = b.flag()
  p[:output_flag_present] = b.flag()
  p[:extra_bits] = b.u(3)
  p[:sign_hiding] = b.flag()
  p[:cabac_init_present] = b.flag()
  p[:nref0] = b.ue() + 1
  p[:nref1] = b.ue() + 1
  hv_req(p[:nref0] <= 15 && p[:nref1] <= 15, "too many default reference indices")
  p[:init_qp] = 26 + b.se()
  hv_req(p[:init_qp] >= -36 && p[:init_qp] <= 51, "init_qp out of range")
  p[:cip] = b.flag()
  p[:ts] = b.flag()
  p[:cuqpd] = b.flag()
  p[:cuqpd_depth] = 0
  p[:cuqpd_depth] = b.ue() if p[:cuqpd]
  hv_req(p[:cuqpd_depth] <= 3, "cu_qp_delta depth out of range")
  p[:cb_off] = b.se()
  p[:cr_off] = b.se()
  hv_req(p[:cb_off] >= -12 && p[:cb_off] <= 12 && p[:cr_off] >= -12 && p[:cr_off] <= 12, "chroma QP offset out of range")
  p[:slice_chroma_offsets] = b.flag()
  p[:wp] = b.flag()
  p[:wbp] = b.flag()
  p[:tq_bypass] = b.flag()
  p[:tiles] = b.flag()
  p[:wpp] = b.flag()
  p[:tile_cols] = 1
  p[:tile_rows] = 1
  p[:uniform] = true
  p[:col_w] = []
  p[:row_h] = []
  p[:lf_tiles] = true
  if p[:tiles]
    p[:tile_cols] = b.ue() + 1
    p[:tile_rows] = b.ue() + 1
    hv_req(p[:tile_cols] <= 20 && p[:tile_rows] <= 22, "too many tiles")
    p[:uniform] = b.flag()
    if !p[:uniform]
      i = 0
      while i < p[:tile_cols] - 1
        p[:col_w].push(b.ue() + 1)
        i += 1
      i = 0
      while i < p[:tile_rows] - 1
        p[:row_h].push(b.ue() + 1)
        i += 1
    p[:lf_tiles] = b.flag()
  p[:lf_slices] = b.flag()
  p[:dbk_override_en] = false
  p[:dbk_dis] = false
  p[:beta] = 0
  p[:tc] = 0
  if b.flag()
    p[:dbk_override_en] = b.flag()
    p[:dbk_dis] = b.flag()
    if !p[:dbk_dis]
      p[:beta] = b.se() * 2
      p[:tc] = b.se() * 2
      hv_req(p[:beta] >= -12 && p[:beta] <= 12 && p[:tc] >= -12 && p[:tc] <= 12, "deblocking offsets out of range")
  p[:sl_data] = nil
  sps = spss[p[:sps]]
  if b.flag()
    p[:sl_data] = hv_scaling_factors(hv_scaling_list_data(b, sps != nil && sps[:chroma_type] == 3))
  p[:lists_mod] = b.flag()
  p[:par_merge] = b.ue() + 2
  hv_req(p[:par_merge] <= 6, "parallel merge level out of range")
  p[:sh_ext] = b.flag()
  p[:log2_max_ts] = 2
  p[:cross_comp] = false
  p[:cqpo_list] = false
  p[:cqpo_depth] = 0
  p[:cqpo_cb] = []
  p[:cqpo_cr] = []
  p[:sao_shift_y] = 0
  p[:sao_shift_c] = 0
  if b.flag()
    rng = b.flag()
    b.skip(7)
    if rng
      p[:log2_max_ts] = b.ue() + 2 if p[:ts]
      hv_req(p[:log2_max_ts] <= 5, "transform-skip size out of range")
      p[:cross_comp] = b.flag()
      p[:cqpo_list] = b.flag()
      if p[:cqpo_list]
        p[:cqpo_depth] = b.ue()
        k = b.ue() + 1
        hv_req(k <= 6, "too many chroma QP offset lists")
        i = 0
        while i < k
          p[:cqpo_cb].push(b.se())
          p[:cqpo_cr].push(b.se())
          i += 1
      p[:sao_shift_y] = b.ue()
      p[:sao_shift_c] = b.ue()
      hv_req(p[:sao_shift_y] <= 6 && p[:sao_shift_c] <= 6, "SAO offset scale out of range")
  p

# Tile layout for pps on sps: colBd/rowBd, CtbAddrRsToTs, TsToRs, TileId (by ts).
-> hv_tile_layout(sps, pps)
  w = sps[:ctb_w]
  h = sps[:ctb_h]
  nc = pps[:tile_cols]
  nr = pps[:tile_rows]
  raise HevcError.new("hevc: bad tile layout") if nc > w || nr > h
  cw = []
  rh = []
  if pps[:uniform]
    i = 0
    while i < nc
      cw.push(((i + 1) * w) / nc - (i * w) / nc)
      i += 1
    i = 0
    while i < nr
      rh.push(((i + 1) * h) / nr - (i * h) / nr)
      i += 1
  else
    s = 0
    pps[:col_w].each ->(x)
      cw.push(x)
      s += x
    cw.push(w - s)
    s = 0
    pps[:row_h].each ->(x)
      rh.push(x)
      s += x
    rh.push(h - s)
    cw.each ->(x) raise HevcError.new("hevc: bad tile columns") if x <= 0
    rh.each ->(x) raise HevcError.new("hevc: bad tile rows") if x <= 0
  colbd = [0]
  cw.each ->(x) colbd.push(colbd.last + x)
  rowbd = [0]
  rh.each ->(x) rowbd.push(rowbd.last + x)
  n = w * h
  rs2ts = i32[n]
  ts2rs = i32[n]
  tileid = i32[n]
  rs = 0
  while rs < n
    tbx = rs % w
    tby = rs / w
    tx = 0
    i = 0
    while i < nc
      tx = i if tbx >= colbd[i]
      i += 1
    ty = 0
    j = 0
    while j < nr
      ty = j if tby >= rowbd[j]
      j += 1
    v = 0
    i = 0
    while i < tx
      v += rh[ty] * cw[i]
      i += 1
    j = 0
    while j < ty
      v += w * rh[j]
      j += 1
    v += (tby - rowbd[ty]) * cw[tx] + tbx - colbd[tx]
    rs2ts[rs] = v
    ts2rs[v] = rs
    rs += 1
  ts = 0
  tid = 0
  j = 0
  while j < nr
    i = 0
    while i < nc
      y = rowbd[j]
      while y < rowbd[j + 1]
        x = colbd[i]
        while x < colbd[i + 1]
          tileid[rs2ts[y * w + x]] = tid
          x += 1
        y += 1
      tid += 1
      i += 1
    j += 1
  {colbd: colbd, rowbd: rowbd, rs2ts: rs2ts, ts2rs: ts2rs, tileid: tileid}

# ---------------------------------------------------------------- slice header

HV_NAL_IDR_W_RADL = 19
HV_NAL_IDR_N_LP = 20

-> hv_ceil_log2(n)
  k = 0
  while (1 << k) < n
    k += 1
  k

-> hv_pred_weights(b, sh, sps, nlist)
  sh[:luma_denom] = b.ue()
  ct = sps[:chroma_type]
  sh[:chroma_denom] = sh[:luma_denom]
  sh[:chroma_denom] = sh[:luma_denom] + b.se() if ct != 0
  shift_y = sps[:hp_offsets] ? 0 : sps[:bd_y] - 8
  shift_c = sps[:hp_offsets] ? 0 : sps[:bd_c] - 8
  half_c = sps[:hp_offsets] ? (1 << (sps[:bd_c] - 1)) : 128
  ws = []
  l = 0
  while l < nlist
    n = l == 0 ? sh[:nref0] : sh[:nref1]
    lf = []
    cf = []
    i = 0
    while i < n
      lf.push(b.flag())
      i += 1
    i = 0
    while i < n
      cf.push(ct != 0 ? b.flag() : false)
      i += 1
    lst = []
    i = 0
    while i < n
      # [lw, lo, cbw, cbo, crw, cro]
      e = [1 << sh[:luma_denom], 0, 1 << sh[:chroma_denom], 0, 1 << sh[:chroma_denom], 0]
      if lf[i]
        e[0] = (1 << sh[:luma_denom]) + b.se()
        e[1] = b.se() << shift_y
      if cf[i]
        j = 0
        while j < 2
          dw = b.se()
          w = (1 << sh[:chroma_denom]) + dw
          dof = b.se()
          o = half_c - ((half_c * w) >> sh[:chroma_denom]) + dof
          o = 0 - half_c if o < 0 - half_c
          o = half_c - 1 if o > half_c - 1
          e[2 + 2 * j] = w
          e[3 + 2 * j] = o << shift_c
          j += 1
      lst.push(e)
      i += 1
    ws.push(lst)
    l += 1
  sh[:weights] = ws
  nil

# Parse a slice segment header. prev: header of the previous independent
# segment (for dependent segments). Returns a Hash; :data_pos is the byte
# offset of slice_segment_data in the rbsp.
-> hv_parse_slice_header(d, n, nal_type, spss, ppss, prev)
  b = HevcBits.new(d, n)
  sh = {}
  sh[:nal_type] = nal_type
  sh[:first] = b.flag()
  sh[:no_output_prior] = false
  sh[:no_output_prior] = b.flag() if nal_type >= 16 && nal_type <= 23
  sh[:pps_id] = b.ue()
  pps = ppss[sh[:pps_id]]
  raise HevcError.new("hevc: missing PPS") if pps == nil
  sps = spss[pps[:sps]]
  raise HevcError.new("hevc: missing SPS") if sps == nil
  sh[:dependent] = false
  sh[:addr] = 0
  if !sh[:first]
    sh[:dependent] = b.flag() if pps[:dep_slices]
    sh[:addr] = b.u(hv_ceil_log2(sps[:ctb_w] * sps[:ctb_h]))
    hv_req(sh[:addr] < sps[:ctb_w] * sps[:ctb_h], "slice address outside the picture")
  if sh[:dependent]
    raise HevcError.new("hevc: dependent slice without a slice") if prev == nil
    prev.each ->(k, v)
      sh[k] = v if k != :first && k != :dependent && k != :addr && k != :entry && k != :data_pos && k != :nal_type && k != :no_output_prior
  else
    b.skip(pps[:extra_bits])
    sh[:type] = b.ue()
    raise HevcError.new("hevc: bad slice type") if sh[:type] > 2
    sh[:pic_output] = true
    sh[:pic_output] = b.flag() if pps[:output_flag_present]
    b.skip(2) if sps[:separate_planes]
    sh[:poc_lsb] = 0
    sh[:st_rps] = nil
    sh[:st_rps_bits] = 0
    sh[:lt] = []
    sh[:tmvp] = false
    if nal_type != HV_NAL_IDR_W_RADL && nal_type != HV_NAL_IDR_N_LP
      sh[:poc_lsb] = b.u(sps[:log2_poc])
      if !b.flag()
        p0 = b.pos
        sh[:st_rps] = hv_st_rps(b, sps[:num_st], sps[:num_st], sps[:st_rps])
        sh[:st_rps_bits] = b.pos - p0
      else
        idx = 0
        idx = b.u(hv_ceil_log2(sps[:num_st])) if sps[:num_st] > 1
        sh[:st_rps] = sps[:st_rps][idx]
      if sps[:lt_present]
        nsps = 0
        nsps = b.ue() if sps[:lt_sps].size > 0
        npics = b.ue()
        i = 0
        while i < nsps + npics
          e = {}
          if i < nsps
            li = 0
            li = b.u(hv_ceil_log2(sps[:lt_sps].size)) if sps[:lt_sps].size > 1
            e[:lsb] = sps[:lt_sps][li][0]
            e[:used] = sps[:lt_sps][li][1]
          else
            e[:lsb] = b.u(sps[:log2_poc])
            e[:used] = b.flag()
          e[:msb_present] = b.flag()
          e[:msb_cycle] = 0
          e[:msb_cycle] = b.ue() if e[:msb_present]
          sh[:lt].push(e)
          i += 1
        # DeltaPocMsbCycleLt accumulates within each group
        i = 0
        while i < sh[:lt].size
          if i != 0 && i != nsps
            sh[:lt][i][:msb_cycle] = sh[:lt][i][:msb_cycle] + sh[:lt][i - 1][:msb_cycle]
          i += 1
      sh[:tmvp] = b.flag() if sps[:tmvp]
    sh[:sao_luma] = false
    sh[:sao_chroma] = false
    if sps[:sao]
      sh[:sao_luma] = b.flag()
      sh[:sao_chroma] = b.flag() if sps[:chroma_type] != 0
    sh[:nref0] = 0
    sh[:nref1] = 0
    sh[:mod0] = nil
    sh[:mod1] = nil
    sh[:mvd_l1_zero] = false
    sh[:cabac_init] = false
    sh[:col_l0] = true
    sh[:col_ref] = 0
    sh[:max_merge] = 5
    sh[:weights] = nil
    if sh[:type] != 2
      sh[:nref0] = pps[:nref0]
      sh[:nref1] = sh[:type] == 0 ? pps[:nref1] : 0
      if b.flag()
        sh[:nref0] = b.ue() + 1
        sh[:nref1] = b.ue() + 1 if sh[:type] == 0
        hv_req(sh[:nref0] <= 15 && sh[:nref1] <= 15, "too many reference indices in slice header")
      total = hv_num_pic_total(sh)
      if pps[:lists_mod] && total > 1
        bits = hv_ceil_log2(total)
        if b.flag()
          sh[:mod0] = []
          i = 0
          while i < sh[:nref0]
            sh[:mod0].push(b.u(bits))
            i += 1
        if sh[:type] == 0 && b.flag()
          sh[:mod1] = []
          i = 0
          while i < sh[:nref1]
            sh[:mod1].push(b.u(bits))
            i += 1
      sh[:mvd_l1_zero] = b.flag() if sh[:type] == 0
      sh[:cabac_init] = b.flag() if pps[:cabac_init_present]
      if sh[:tmvp]
        sh[:col_l0] = b.flag() if sh[:type] == 0
        if (sh[:col_l0] && sh[:nref0] > 1) || (!sh[:col_l0] && sh[:nref1] > 1)
          sh[:col_ref] = b.ue()
      if (pps[:wp] && sh[:type] == 1) || (pps[:wbp] && sh[:type] == 0)
        hv_pred_weights(b, sh, sps, sh[:type] == 0 ? 2 : 1)
      sh[:max_merge] = 5 - b.ue()
    sh[:qp] = pps[:init_qp] + b.se()
    sh[:cb_off] = 0
    sh[:cr_off] = 0
    if pps[:slice_chroma_offsets]
      sh[:cb_off] = b.se()
      sh[:cr_off] = b.se()
    sh[:cqpo] = false
    sh[:cqpo] = b.flag() if pps[:cqpo_list]
    override = false
    override = b.flag() if pps[:dbk_override_en]
    sh[:dbk_dis] = pps[:dbk_dis]
    sh[:beta] = pps[:beta]
    sh[:tc] = pps[:tc]
    if override
      sh[:dbk_dis] = b.flag()
      if !sh[:dbk_dis]
        sh[:beta] = b.se() * 2
        sh[:tc] = b.se() * 2
    sh[:lf_slices] = pps[:lf_slices]
    if pps[:lf_slices] && (sh[:sao_luma] || sh[:sao_chroma] || !sh[:dbk_dis])
      sh[:lf_slices] = b.flag()
  sh[:entry] = []
  if pps[:tiles] || pps[:wpp]
    ne = b.ue()
    raise HevcError.new("hevc: too many entry points") if ne > sps[:ctb_w] * sps[:ctb_h]
    if ne > 0
      bits = b.ue() + 1
      raise HevcError.new("hevc: bad entry point size") if bits > 32
      i = 0
      while i < ne
        sh[:entry].push(b.u(bits) + 1)
        i += 1
  if pps[:sh_ext]
    k = b.ue()
    b.skip(8 * k)
  # byte_alignment(): one bit equal to 1, then zero bits
  b.skip(1)
  b.byte_align()
  sh[:data_pos] = b.pos >> 3
  sh

-> hv_num_pic_total(sh)
  t = 0
  r = sh[:st_rps]
  if r != nil
    r[:negu].each ->(u) t += 1 if u
    r[:posu].each ->(u) t += 1 if u
  sh[:lt].each ->(e) t += 1 if e[:used]
  t
