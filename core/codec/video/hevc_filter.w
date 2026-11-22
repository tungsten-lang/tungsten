# core/codec/video/hevc_filter — HEVC in-loop filters: the deblocking filter (8.7.2) and
# sample adaptive offset (8.7.3), run over a whole decoded picture.
#
# Deblocking reads the per-4x4 maps the slice decoder filled (edge flags,
# QpY, intra / nonzero / pcm / bypass flags, motion for inter blocks) and the
# per-slice table (HS_C_SLT: 8 ints per slice: deblocking disabled, beta
# offset, tc offset, loop filter across slices, slice address).

use hevc_slice

HS_C_SLT = 76
HS_M_BS = 77
HS_SAO_ANY = 78
HS_DBK_ANY = 79

# slice table fields
HL_DBKDIS = 0
HL_BETA = 1
HL_TC = 2
HL_LFS = 3
HL_ADDR = 4

# inter motion map (filled by core/codec/video/hevc_inter.w) at mp[st[HS_MV]]: per 4x4, HMV_N ints:
# mvx0, mvy0, mvx1, mvy1, ref picture id 0 / 1 (-1: list unused), refIdx 0 / 1,
# ref POC 0 / 1, ref long-term 0 / 1
HS_MV = 140
HS_MV_BASE = 141
HMV_N = 12

# ---------------------------------------------------------------- boundary strength

# bs maps: mp[bs + i] bits 0-1 vertical edge bs, bits 2-3 horizontal edge bs.
-> hv_dbk_bs(st, mp) (i64[] i32[]) i64
  w = (st[HS_W]) ## i64
  h = (st[HS_H]) ## i64
  w4 = (st[HS_W4]) ## i64
  eo = (st[HS_M_EDGE]) ## i64
  fo = (st[HS_M_FLAGS]) ## i64
  bo = (st[HS_M_BS]) ## i64
  l = (st[HS_CTB]) ## i64
  cw = (st[HS_CTBW]) ## i64
  sa = (st[HS_C_SADDR]) ## i64
  si = (st[HS_C_SIDX]) ## i64
  ti = (st[HS_C_TILE]) ## i64
  slt = (st[HS_C_SLT]) ## i64
  lft = (st[HS_LF_TILES_P]) ## i64
  y4 = 0 ## i64
  while y4 < (h + 3) >> 2
    x4 = 0 ## i64
    while x4 < (w + 3) >> 2
      i = (y4 * w4 + x4) ## i64
      e = (mp[eo + i]) ## i64
      v = 0 ## i64
      x = (x4 << 2) ## i64
      y = (y4 << 2) ## i64
      cq = ((y >> l) * cw + (x >> l)) ## i64
      sq = (slt + mp[si + cq] * 8) ## i64
      if (e & 3) != 0 && x > 0 && mp[sq + HL_DBKDIS] == 0
        cp = ((y >> l) * cw + ((x - 1) >> l)) ## i64
        ok = 1 ## i64
        if cp != cq
          if mp[sa + cp] != mp[sa + cq] && mp[sq + HL_LFS] == 0
            ok = 0
          if mp[ti + cp] != mp[ti + cq] && lft == 0
            ok = 0
        if ok != 0
          v = hv_bs_one(mp, st[HS_MV], fo, i - 1, i, e & 1)
      hz = 0 ## i64
      if (e & 12) != 0 && y > 0 && mp[sq + HL_DBKDIS] == 0
        cp = ((y - 1) >> l) * cw + (x >> l)
        ok = 1 ## i64
        if cp != cq
          if mp[sa + cp] != mp[sa + cq] && mp[sq + HL_LFS] == 0
            ok = 0
          if mp[ti + cp] != mp[ti + cq] && lft == 0
            ok = 0
        if ok != 0
          hz = hv_bs_one(mp, st[HS_MV], fo, i - w4, i, (e >> 2) & 1)
      mp[bo + i] = v | (hz << 2)
      x4 += 1
    y4 += 1
  0

-> hv_bs_one(mv, mo, fo, ip, iq, tu) (i32[] i64 i64 i64 i64 i64) i64
  fp = (mv[fo + ip]) ## i64
  fq = (mv[fo + iq]) ## i64
  if ((fp | fq) & HM_INTRA) != 0
    return 2
  if tu != 0 && ((fp | fq) & HM_NZ) != 0
    return 1
  # motion (8.7.2.4): different reference pictures / number of MVs / MV difference >= 4
  p = (mo + ip * HMV_N) ## i64
  q = (mo + iq * HMV_N) ## i64
  pr0 = (mv[p + 4]) ## i64
  pr1 = (mv[p + 5]) ## i64
  qr0 = (mv[q + 4]) ## i64
  qr1 = (mv[q + 5]) ## i64
  np = ((pr0 >= 0 ? 1 : 0) + (pr1 >= 0 ? 1 : 0)) ## i64
  nq = ((qr0 >= 0 ? 1 : 0) + (qr1 >= 0 ? 1 : 0)) ## i64
  if np != nq
    return 1
  if np == 1
    rp = (pr0 >= 0 ? pr0 : pr1) ## i64
    rq = (qr0 >= 0 ? qr0 : qr1) ## i64
    if rp != rq
      return 1
    mpx = (pr0 >= 0 ? mv[p] : mv[p + 2]) ## i64
    mpy = (pr0 >= 0 ? mv[p + 1] : mv[p + 3]) ## i64
    mqx = (qr0 >= 0 ? mv[q] : mv[q + 2]) ## i64
    mqy = (qr0 >= 0 ? mv[q + 1] : mv[q + 3]) ## i64
    return hv_mvdiff(mpx, mpy, mqx, mqy)
  # two motion vectors each
  if !((pr0 == qr0 && pr1 == qr1) || (pr0 == qr1 && pr1 == qr0))
    return 1
  if pr0 != pr1
    if pr0 == qr0
      return (hv_mvdiff((mv[p] ## i64), (mv[p + 1] ## i64), (mv[q] ## i64), (mv[q + 1] ## i64)) | hv_mvdiff((mv[p + 2] ## i64), (mv[p + 3] ## i64), (mv[q + 2] ## i64), (mv[q + 3] ## i64)))
    return (hv_mvdiff((mv[p] ## i64), (mv[p + 1] ## i64), (mv[q + 2] ## i64), (mv[q + 3] ## i64)) | hv_mvdiff((mv[p + 2] ## i64), (mv[p + 3] ## i64), (mv[q] ## i64), (mv[q + 1] ## i64)))
  # both refer to the same picture twice
  a = (hv_mvdiff((mv[p] ## i64), (mv[p + 1] ## i64), (mv[q] ## i64), (mv[q + 1] ## i64)) | hv_mvdiff((mv[p + 2] ## i64), (mv[p + 3] ## i64), (mv[q + 2] ## i64), (mv[q + 3] ## i64))) ## i64
  b = (hv_mvdiff((mv[p] ## i64), (mv[p + 1] ## i64), (mv[q + 2] ## i64), (mv[q + 3] ## i64)) | hv_mvdiff((mv[p + 2] ## i64), (mv[p + 3] ## i64), (mv[q] ## i64), (mv[q + 1] ## i64))) ## i64
  a & b

-> hv_mvdiff(ax, ay, bx, by) (i64 i64 i64 i64) i64
  dx = (ax - bx) ## i64
  dy = (ay - by) ## i64
  dx = 0 - dx if dx < 0
  dy = 0 - dy if dy < 0
  if dx >= 4 || dy >= 4
    return 1
  0

# ---------------------------------------------------------------- deblocking

HS_LF_TILES_P = 119

-> hv_deblock(st, mp, tb, px) (i64[] i32[] i32[] u16[]) i64
  hv_dbk_bs(st, mp)
  hv_dbk_luma(st, mp, tb, px, 0)
  if st[HS_CT] != 0
    hv_dbk_chroma(st, mp, tb, px, 0)
  hv_dbk_luma(st, mp, tb, px, 1)
  if st[HS_CT] != 0
    hv_dbk_chroma(st, mp, tb, px, 1)
  0

# no-filter flag for the 4x4 at i: pcm with pcm_loop_filter_disabled, or transquant bypass
-> hv_nofilt(st, mp, i) (i64[] i32[] i64) i64
  f = (mp[st[HS_M_FLAGS] + i]) ## i64
  if (f & HM_TQB) != 0
    return 1
  if (f & HM_PCM) != 0 && st[HS_PCM_LFDIS] != 0
    return 1
  0

-> hv_dbk_luma(st, mp, tb, px, dir) (i64[] i32[] i32[] u16[] i64) i64
  w = (st[HS_W]) ## i64
  h = (st[HS_H]) ## i64
  w4 = (st[HS_W4]) ## i64
  bo = (st[HS_M_BS]) ## i64
  qo = (st[HS_M_QP]) ## i64
  l = (st[HS_CTB]) ## i64
  cw = (st[HS_CTBW]) ## i64
  si = (st[HS_C_SIDX]) ## i64
  slt = (st[HS_C_SLT]) ## i64
  bd = (st[HS_BDY]) ## i64
  mx = ((1 << bd) - 1) ## i64
  py = (st[HS_PY]) ## i64
  # step: for vertical edges (dir 0) samples across the edge are +-1; along the edge +w
  y4 = 0 ## i64
  while y4 < (h + 3) >> 2
    x4 = 0 ## i64
    while x4 < (w + 3) >> 2
      i = (y4 * w4 + x4) ## i64
      bs = 0 ## i64
      if dir == 0
        bs = mp[bo + i] & 3
      else
        bs = (mp[bo + i] >> 2) & 3
      if bs != 0
        x = (x4 << 2) ## i64
        y = (y4 << 2) ## i64
        ip = (dir == 0 ? i - 1 : i - w4) ## i64
        qpl = ((mp[qo + i] + mp[qo + ip] + 1) >> 1) ## i64
        cq = ((y >> l) * cw + (x >> l)) ## i64
        sq = (slt + mp[si + cq] * 8) ## i64
        qb = (qpl + mp[sq + HL_BETA]) ## i64
        qb = 0 if qb < 0
        qb = 51 if qb > 51
        beta = (tb[HT_BETA + qb] << (bd - 8)) ## i64
        qt = (qpl + 2 * (bs - 1) + mp[sq + HL_TC]) ## i64
        qt = 0 if qt < 0
        qt = 53 if qt > 53
        tc = (tb[HT_TC + qt] << (bd - 8)) ## i64
        if tc > 0 || beta > 0
          nfp = (hv_nofilt(st, mp, ip)) ## i64
          nfq = (hv_nofilt(st, mp, i)) ## i64
          o = (py + y * w + x) ## i64
          across = 1 ## i64
          along = (w) ## i64
          if dir != 0
            across = w
            along = 1
          hv_luma_edge(px, o, across, along, beta, tc, nfp, nfq, mx)
      x4 += 1
    y4 += 1
  0

# One 4-sample luma edge segment (8.7.2.5.3 / 8.7.2.5.6-7). o: q0 of line 0.
-> hv_luma_edge(px, o, a, s, beta, tc, nfp, nfq, mx) (u16[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  o3 = (o + 3 * s) ## i64
  dp0 = (hv_abs(px[o - 3 * a] - 2 * px[o - 2 * a] + px[o - a])) ## i64
  dp3 = (hv_abs(px[o3 - 3 * a] - 2 * px[o3 - 2 * a] + px[o3 - a])) ## i64
  dq0 = (hv_abs(px[o + 2 * a] - 2 * px[o + a] + px[o])) ## i64
  dq3 = (hv_abs(px[o3 + 2 * a] - 2 * px[o3 + a] + px[o3])) ## i64
  dpq0 = (dp0 + dq0) ## i64
  dpq3 = (dp3 + dq3) ## i64
  dp = (dp0 + dp3) ## i64
  dq = (dq0 + dq3) ## i64
  dd = (dpq0 + dpq3) ## i64
  if dd >= beta
    return 0
  ds0 = (hv_dsam(px, o, a, 2 * dpq0, beta, tc)) ## i64
  ds3 = (hv_dsam(px, o3, a, 2 * dpq3, beta, tc)) ## i64
  de = 1 ## i64
  de = 2 if ds0 != 0 && ds3 != 0
  dep = 0 ## i64
  deq = 0 ## i64
  side = ((beta + (beta >> 1)) >> 3) ## i64
  dep = 1 if dp < side
  deq = 1 if dq < side
  k = 0 ## i64
  while k < 4
    r = (o + k * s) ## i64
    p0 = (px[r - a]) ## i64
    p1 = (px[r - 2 * a]) ## i64
    p2 = (px[r - 3 * a]) ## i64
    p3 = (px[r - 4 * a]) ## i64
    q0 = (px[r]) ## i64
    q1 = (px[r + a]) ## i64
    q2 = (px[r + 2 * a]) ## i64
    q3 = (px[r + 3 * a]) ## i64
    if de == 2
      t2 = (2 * tc) ## i64
      if nfp == 0
        px[r - a] = hv_clip3(p0 - t2, p0 + t2, (p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3)
        px[r - 2 * a] = hv_clip3(p1 - t2, p1 + t2, (p2 + p1 + p0 + q0 + 2) >> 2)
        px[r - 3 * a] = hv_clip3(p2 - t2, p2 + t2, (2 * p3 + 3 * p2 + p1 + p0 + q0 + 4) >> 3)
      if nfq == 0
        px[r] = hv_clip3(q0 - t2, q0 + t2, (p1 + 2 * p0 + 2 * q0 + 2 * q1 + q2 + 4) >> 3)
        px[r + a] = hv_clip3(q1 - t2, q1 + t2, (p0 + q0 + q1 + q2 + 2) >> 2)
        px[r + 2 * a] = hv_clip3(q2 - t2, q2 + t2, (p0 + q0 + q1 + 3 * q2 + 2 * q3 + 4) >> 3)
    else
      delta = ((9 * (q0 - p0) - 3 * (q1 - p1) + 8) >> 4) ## i64
      if hv_abs(delta) < tc * 10
        delta = hv_clip3(0 - tc, tc, delta)
        if nfp == 0
          px[r - a] = hv_clip3(0, mx, p0 + delta)
        if nfq == 0
          px[r] = hv_clip3(0, mx, q0 - delta)
        if dep != 0 && nfp == 0
          dlp = (hv_clip3(0 - (tc >> 1), tc >> 1, (((p2 + p0 + 1) >> 1) - p1 + delta) >> 1)) ## i64
          px[r - 2 * a] = hv_clip3(0, mx, p1 + dlp)
        if deq != 0 && nfq == 0
          dlq = (hv_clip3(0 - (tc >> 1), tc >> 1, (((q2 + q0 + 1) >> 1) - q1 - delta) >> 1)) ## i64
          px[r + a] = hv_clip3(0, mx, q1 + dlq)
    k += 1
  0

-> hv_dsam(px, o, a, dpq, beta, tc) (u16[] i64 i64 i64 i64 i64) i64
  if dpq >= (beta >> 2)
    return 0
  if hv_abs(px[o - 4 * a] - px[o - a]) + hv_abs(px[o] - px[o + 3 * a]) >= (beta >> 3)
    return 0
  if hv_abs(px[o - a] - px[o]) >= ((5 * tc + 1) >> 1)
    return 0
  1

-> hv_abs(v) (i64) i64
  if v < 0
    return 0 - v
  v

-> hv_clip3(lo, hi, v) (i64 i64 i64) i64
  if v < lo
    return lo
  if v > hi
    return hi
  v

-> hv_dbk_chroma(st, mp, tb, px, dir) (i64[] i32[] i32[] u16[] i64) i64
  w = (st[HS_W]) ## i64
  h = (st[HS_H]) ## i64
  w4 = (st[HS_W4]) ## i64
  bo = (st[HS_M_BS]) ## i64
  qo = (st[HS_M_QP]) ## i64
  l = (st[HS_CTB]) ## i64
  cw = (st[HS_CTBW]) ## i64
  si = (st[HS_C_SIDX]) ## i64
  slt = (st[HS_C_SLT]) ## i64
  bd = (st[HS_BDC]) ## i64
  mx = ((1 << bd) - 1) ## i64
  ssx = (st[HS_SSX]) ## i64
  ssy = (st[HS_SSY]) ## i64
  cwid = (st[HS_CW]) ## i64
  ct = (st[HS_CT]) ## i64
  # edge grid: 8 chroma samples
  gx = (8 << ssx) ## i64
  gy = (8 << ssy) ## i64
  y4 = 0 ## i64
  while y4 < (h + 3) >> 2
    x4 = 0 ## i64
    while x4 < (w + 3) >> 2
      i = (y4 * w4 + x4) ## i64
      x = (x4 << 2) ## i64
      y = (y4 << 2) ## i64
      bs = 0 ## i64
      # chroma edge segments are 4 chroma samples long; each uses the bS of
      # its first sample (8.7.2.5.5)
      if dir == 0
        bs = mp[bo + i] & 3
        bs = 0 if (x % gx) != 0 || ((y >> ssy) & 3) != 0
      else
        bs = (mp[bo + i] >> 2) & 3
        bs = 0 if (y % gy) != 0 || ((x >> ssx) & 3) != 0
      if bs == 2
        ip = (dir == 0 ? i - 1 : i - w4) ## i64
        qpl = ((mp[qo + i] + mp[qo + ip] + 1) >> 1) ## i64
        cq = ((y >> l) * cw + (x >> l)) ## i64
        sq = (slt + mp[si + cq] * 8) ## i64
        c = 1 ## i64
        while c <= 2
          qpi = (qpl + (c == 1 ? st[HS_CBOFF] : st[HS_CROFF])) ## i64
          qpc = (qpi) ## i64
          if ct == 1
            if qpi >= 0 && qpi < 70
              qpc = tb[HT_QPC + qpi]
          else
            qpc = 51 if qpi > 51
          qt = (qpc + 2 + mp[sq + HL_TC]) ## i64
          qt = 0 if qt < 0
          qt = 53 if qt > 53
          tc = (tb[HT_TC + qt] << (bd - 8)) ## i64
          if tc > 0
            po = (c == 1 ? st[HS_PCB] : st[HS_PCR]) ## i64
            xc = (x >> ssx) ## i64
            yc = (y >> ssy) ## i64
            o = (po + yc * cwid + xc) ## i64
            n = 4 ## i64
            across = 1 ## i64
            along = (cwid) ## i64
            if dir == 0
              n = st[HS_CH] - yc if yc + 4 > st[HS_CH]
            else
              n = st[HS_CW] - xc if xc + 4 > st[HS_CW]
              across = cwid
              along = 1
            k = 0 ## i64
            while k < n
              # per-line pcm / bypass exemption, from the luma 4x4 of this line
              li = (i) ## i64
              if dir == 0
                li = i + (((k << ssy) >> 2) * w4)
              else
                li = i + ((k << ssx) >> 2)
              lp = (dir == 0 ? li - 1 : li - w4) ## i64
              nfp = (hv_nofilt(st, mp, lp)) ## i64
              nfq = (hv_nofilt(st, mp, li)) ## i64
              r = (o + k * along) ## i64
              p0 = (px[r - across]) ## i64
              p1 = (px[r - 2 * across]) ## i64
              q0 = (px[r]) ## i64
              q1 = (px[r + across]) ## i64
              delta = (hv_clip3(0 - tc, tc, ((((q0 - p0) << 2) + p1 - q1 + 4) >> 3))) ## i64
              px[r - across] = hv_clip3(0, mx, p0 + delta) if nfp == 0
              px[r] = hv_clip3(0, mx, q0 - delta) if nfq == 0
              k += 1
          c += 1
      x4 += 1
    y4 += 1
  0

# ---------------------------------------------------------------- SAO

# src: copy of the deblocked picture planes (same layout, offsets relative to 0
# for Y and st[HS_PCB]-st[HS_PY] etc.). Writes into px.
-> hv_sao_apply(st, mp, px, src) (i64[] i32[] u16[] u16[]) i64
  cwn = (st[HS_CTBW]) ## i64
  chn = (st[HS_CTBH]) ## i64
  l = (st[HS_CTB]) ## i64
  so = (st[HS_C_SAO]) ## i64
  ct = (st[HS_CT]) ## i64
  nc = 3 ## i64
  nc = 1 if ct == 0
  ry = 0 ## i64
  while ry < chn
    rx = 0 ## i64
    while rx < cwn
      rs = (ry * cwn + rx) ## i64
      c = 0 ## i64
      while c < nc
        typ = (mp[so + rs * 21 + c * 7]) ## i64
        if typ != 0
          hv_sao_ctb(st, mp, px, src, rx, ry, c, so + rs * 21 + c * 7)
        c += 1
      rx += 1
    ry += 1
  0

# can SAO at a sample of CTB (rx, ry) use samples of CTB (nx, ny)? (picture,
# slice and tile boundary rules of 8.7.3)
-> hv_sao_nb_ok(st, mp, rx, ry, nx, ny) (i64[] i32[] i64 i64 i64 i64) i64
  cwn = (st[HS_CTBW]) ## i64
  if nx < 0 || ny < 0 || nx >= cwn || ny >= st[HS_CTBH]
    return 0
  a = (ry * cwn + rx) ## i64
  b = (ny * cwn + nx) ## i64
  if a == b
    return 1
  sa = (st[HS_C_SADDR]) ## i64
  if mp[sa + a] != mp[sa + b]
    slt = (st[HS_C_SLT]) ## i64
    si = (st[HS_C_SIDX]) ## i64
    # the later slice's flag controls its left/upper boundary
    ta = (mp[st[HS_C_RS2TS] + a]) ## i64
    tbb = (mp[st[HS_C_RS2TS] + b]) ## i64
    if tbb < ta
      return 0 if mp[slt + mp[si + a] * 8 + HL_LFS] == 0
    else
      return 0 if mp[slt + mp[si + b] * 8 + HL_LFS] == 0
  if st[HS_LF_TILES_P] == 0 && mp[st[HS_C_TILE] + a] != mp[st[HS_C_TILE] + b]
    return 0
  1

-> hv_sao_ctb(st, mp, px, src, rx, ry, c, po) (i64[] i32[] u16[] u16[] i64 i64 i64 i64) i64
  l = (st[HS_CTB]) ## i64
  ssx = 0 ## i64
  ssy = 0 ## i64
  stride = (st[HS_W]) ## i64
  pw = (st[HS_W]) ## i64
  ph = (st[HS_H]) ## i64
  base = (st[HS_PY]) ## i64
  bd = (st[HS_BDY]) ## i64
  if c > 0
    ssx = st[HS_SSX]
    ssy = st[HS_SSY]
    stride = st[HS_CW]
    pw = st[HS_CW]
    ph = st[HS_CH]
    base = c == 1 ? st[HS_PCB] : st[HS_PCR]
    bd = st[HS_BDC]
  sbase = (base - st[HS_PY]) ## i64
  cs = (1 << l) ## i64
  x0 = ((rx << l) >> ssx) ## i64
  y0 = ((ry << l) >> ssy) ## i64
  wd = (cs >> ssx) ## i64
  hd = (cs >> ssy) ## i64
  wd = pw - x0 if x0 + wd > pw
  hd = ph - y0 if y0 + hd > ph
  mx = ((1 << bd) - 1) ## i64
  typ = (mp[po]) ## i64
  o0 = (mp[po + 2]) ## i64
  o1 = (mp[po + 3]) ## i64
  o2 = (mp[po + 4]) ## i64
  o3 = (mp[po + 5]) ## i64
  # pcm / bypass samples are left unmodified
  chk = 0 ## i64
  if st[HS_TQB] != 0 || (st[HS_PCM] != 0 && st[HS_PCM_LFDIS] != 0)
    chk = 1
  w4 = (st[HS_W4]) ## i64
  fo = (st[HS_M_FLAGS]) ## i64
  if typ == 1
    shift = (bd - 5) ## i64
    bp = (mp[po + 1]) ## i64
    y = 0 ## i64
    while y < hd
      r = ((y0 + y) * stride + x0) ## i64
      x = 0 ## i64
      while x < wd
        v = (src[sbase + r + x]) ## i64
        band = (((v >> shift) - bp) & 31) ## i64
        off = 0 ## i64
        off = o0 if band == 0
        off = o1 if band == 1
        off = o2 if band == 2
        off = o3 if band == 3
        if off != 0
          skip = 0 ## i64
          if chk != 0
            lx = ((x0 + x) << ssx) ## i64
            ly = ((y0 + y) << ssy) ## i64
            f = (mp[fo + (ly >> 2) * w4 + (lx >> 2)]) ## i64
            skip = 1 if (f & HM_TQB) != 0 || ((f & HM_PCM) != 0 && st[HS_PCM_LFDIS] != 0)
          if skip == 0
            nv = (v + off) ## i64
            nv = 0 if nv < 0
            nv = mx if nv > mx
            px[base + r + x] = nv
        x += 1
      y += 1
    return 0
  cls = (mp[po + 1]) ## i64
  hx = -1 ## i64
  hy = 0 ## i64
  if cls == 1
    hx = 0
    hy = -1
  elsif cls == 2
    hx = -1
    hy = -1
  elsif cls == 3
    hx = 1
    hy = -1
  # neighbour CTB usability (3x3 around)
  okm = i64[9]
  j = 0 ## i64
  while j < 3
    i = 0 ## i64
    while i < 3
      okm[j * 3 + i] = hv_sao_nb_ok(st, mp, rx, ry, rx + i - 1, ry + j - 1)
      i += 1
    j += 1
  y = 0
  while y < hd
    yy = (y0 + y) ## i64
    x = 0
    while x < wd
      xx = (x0 + x) ## i64
      ax = (xx + hx) ## i64
      ay = (yy + hy) ## i64
      bx = (xx - hx) ## i64
      by = (yy - hy) ## i64
      ok = 1 ## i64
      if ax < 0 || ay < 0 || ax >= pw || ay >= ph || bx < 0 || by < 0 || bx >= pw || by >= ph
        ok = 0
      else
        cax = 1 ## i64
        cax = 0 if ax < x0
        cax = 2 if ax >= x0 + (cs >> ssx)
        cay = 1 ## i64
        cay = 0 if ay < y0
        cay = 2 if ay >= y0 + (cs >> ssy)
        ok = 0 if okm[cay * 3 + cax] == 0
        cbx = 1 ## i64
        cbx = 0 if bx < x0
        cbx = 2 if bx >= x0 + (cs >> ssx)
        cby = 1 ## i64
        cby = 0 if by < y0
        cby = 2 if by >= y0 + (cs >> ssy)
        ok = 0 if okm[cby * 3 + cbx] == 0
      if ok != 0 && chk != 0
        lx = xx << ssx
        ly = yy << ssy
        f = mp[fo + (ly >> 2) * w4 + (lx >> 2)]
        ok = 0 if (f & HM_TQB) != 0 || ((f & HM_PCM) != 0 && st[HS_PCM_LFDIS] != 0)
      if ok != 0
        v = src[sbase + yy * stride + xx]
        a = (src[sbase + ay * stride + ax]) ## i64
        b = (src[sbase + by * stride + bx]) ## i64
        e = 2 ## i64
        e += 1 if v > a
        e -= 1 if v < a
        e += 1 if v > b
        e -= 1 if v < b
        off = 0 ## i64
        # edgeIdx 0,1,2 -> 1,2,0 ; 3,4 stay; SaoOffsetVal[1..4] = o0..o3
        off = o0 if e == 0
        off = o1 if e == 1
        off = o2 if e == 3
        off = o3 if e == 4
        if off != 0
          nv = v + off
          nv = 0 if nv < 0
          nv = mx if nv > mx
          px[base + yy * stride + xx] = nv
      x += 1
    y += 1
  0
