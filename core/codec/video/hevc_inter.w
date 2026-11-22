# core/codec/video/hevc_inter — HEVC inter prediction (8.5.3): prediction unit syntax,
# merge candidates (spatial, temporal, combined bi-predictive, zero), AMVP with
# MV scaling, temporal MV prediction from the collocated picture, luma 8-tap /
# chroma 4-tap fractional interpolation and default / explicit weighted
# sample prediction. Motion is stored per 4x4 in the picture's motion map
# (HMV_N ints, see core/codec/video/hevc_filter.w) for neighbours, TMVP and deblocking.

use hevc_slice
use hevc_filter

HS_I_WP = 160
HS_I_LD = 161
HS_I_CD = 162
HS_I_TMVP = 163
HS_I_COLMV = 164
HS_I_NOBWD = 165
HS_I_COLL0 = 166
HS_I_POC = 167
HS_I_SLOT = 168
HS_I_COLPOC = 169
HS_I_REF = 176
HS_I_W = 320

HMC_N = 6

# ---------------------------------------------------------------- CU / PU syntax

-> hv_inter_cu(d, cab, st, tb, mp, px, cf, x0, y0, log2, part) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64) i64
  s = (1 << log2) ## i64
  h = (s >> 1) ## i64
  q = (s >> 2) ## i64
  if part == 0
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s, s, x0, y0, s, 0, 0)
  elsif part == 1
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s, h, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0 + h, s, h, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0, y0 + h, s, 1)
  elsif part == 2
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, h, s, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0 + h, y0, h, s, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0 + h, y0, s, 0)
  elsif part == 3
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, h, h, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0 + h, y0, h, h, x0, y0, s, 1, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0 + h, h, h, x0, y0, s, 2, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0 + h, y0 + h, h, h, x0, y0, s, 3, 0)
    hv_pu_edge(st, mp, x0, y0 + h, s, 1)
    hv_pu_edge(st, mp, x0 + h, y0, s, 0)
  elsif part == 4
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s, q, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0 + q, s, s - q, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0, y0 + q, s, 1)
  elsif part == 5
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s, s - q, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0 + s - q, s, q, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0, y0 + s - q, s, 1)
  elsif part == 6
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, q, s, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0 + q, y0, s - q, s, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0 + q, y0, s, 0)
  else
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s - q, s, x0, y0, s, 0, 0)
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0 + s - q, y0, q, s, x0, y0, s, 1, 0)
    hv_pu_edge(st, mp, x0 + s - q, y0, s, 0)
  0

# internal PU boundary for deblocking (only on the 8x8 grid)
-> hv_pu_edge(st, mp, x, y, s, horiz) (i64[] i32[] i64 i64 i64 i64) i64
  w4 = (st[HS_W4]) ## i64
  eo = (st[HS_M_EDGE]) ## i64
  if horiz != 0
    if (y & 7) != 0
      return 0
    k = 0 ## i64
    while k < s && x + k < st[HS_W]
      i = (eo + (y >> 2) * w4 + ((x + k) >> 2)) ## i64
      mp[i] = mp[i] | 8
      k += 4
  else
    if (x & 7) != 0
      return 0
    k = 0
    while k < s && y + k < st[HS_H]
      i = eo + ((y + k) >> 2) * w4 + (x >> 2)
      mp[i] = mp[i] | 2
      k += 4
  0

-> hv_inter_pu(d, cab, st, tb, mp, px, cf, xp, yp, w, h, xc, yc, s, pidx, skip) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  mc = (HF_MC + 40) ## i64
  merge = 1 ## i64
  if skip == 0
    merge = hv_bin(cab, d, tb, HC_MERGE_FLAG)
  st[HS_MERGE] = merge if pidx == 0
  if merge != 0
    midx = 0 ## i64
    maxm = (st[HS_MAXMERGE]) ## i64
    if maxm > 1
      if hv_bin(cab, d, tb, HC_MERGE_IDX) != 0
        midx = 1
        while midx < maxm - 1 && hv_bypass(cab, d) != 0
          midx += 1
    hv_merge(st, mp, cf, xp, yp, w, h, xc, yc, s, pidx, midx)
  else
    ipi = 0 ## i64
    if st[HS_STYPE] == 0
      if w + h != 12
        depth = (mp[st[HS_M_DEPTH] + (yc >> 2) * st[HS_W4] + (xc >> 2)]) ## i64
        if hv_bin(cab, d, tb, HC_INTER_PRED + depth) != 0
          ipi = 2
        else
          ipi = hv_bin(cab, d, tb, HC_INTER_PRED + 4)
      else
        ipi = hv_bin(cab, d, tb, HC_INTER_PRED + 4)
    ri0 = -1 ## i64
    ri1 = -1 ## i64
    mvd0x = 0 ## i64
    mvd0y = 0 ## i64
    mvd1x = 0 ## i64
    mvd1y = 0 ## i64
    mvp0 = 0 ## i64
    mvp1 = 0 ## i64
    if ipi != 1
      ri0 = hv_ref_idx(d, cab, tb, st[HS_NREF0])
      hv_mvd(d, cab, tb, cf, mc + 10)
      mvd0x = cf[mc + 10]
      mvd0y = cf[mc + 11]
      mvp0 = hv_bin(cab, d, tb, HC_MVP)
    if ipi != 0
      ri1 = hv_ref_idx(d, cab, tb, st[HS_NREF1])
      if st[HS_MVDL1Z] != 0 && ipi == 2
        mvd1x = 0
        mvd1y = 0
      else
        hv_mvd(d, cab, tb, cf, mc + 10)
        mvd1x = cf[mc + 10]
        mvd1y = cf[mc + 11]
      mvp1 = hv_bin(cab, d, tb, HC_MVP)
    cf[mc + 4] = ri0
    cf[mc + 5] = ri1
    if ri0 >= 0
      hv_amvp(st, mp, cf, xp, yp, w, h, xc, yc, s, pidx, 0, ri0, mvp0)
      cf[mc] = hv_wrap16(cf[HF_MC + 30] + mvd0x)
      cf[mc + 1] = hv_wrap16(cf[HF_MC + 31] + mvd0y)
    if ri1 >= 0
      hv_amvp(st, mp, cf, xp, yp, w, h, xc, yc, s, pidx, 1, ri1, mvp1)
      cf[mc + 2] = hv_wrap16(cf[HF_MC + 30] + mvd1x)
      cf[mc + 3] = hv_wrap16(cf[HF_MC + 31] + mvd1y)
  hv_store_motion(st, mp, cf, mc, xp, yp, w, h)
  hv_mc(st, tb, px, cf, mc, xp, yp, w, h)
  0

-> hv_wrap16(v) (i64) i64
  u = ((v + 65536) & 65535) ## i64
  if u >= 32768
    return u - 65536
  u

-> hv_ref_idx(d, cab, tb, n) (u8[] i64[] i32[] i64) i64
  if n <= 1
    return 0
  cmax = (n - 1) ## i64
  i = 0 ## i64
  while i < cmax
    b = 0 ## i64
    if i < 2
      b = hv_bin(cab, d, tb, HC_REF_IDX + i)
    else
      b = hv_bypass(cab, d)
    if b == 0
      return i
    i += 1
  cmax

-> hv_mvd(d, cab, tb, cf, o) (u8[] i64[] i32[] i32[] i64) i64
  g0x = (hv_bin(cab, d, tb, HC_MVD_G0)) ## i64
  g0y = (hv_bin(cab, d, tb, HC_MVD_G0)) ## i64
  g1x = 0 ## i64
  g1y = 0 ## i64
  g1x = hv_bin(cab, d, tb, HC_MVD_G1) if g0x != 0
  g1y = hv_bin(cab, d, tb, HC_MVD_G1) if g0y != 0
  vx = 0 ## i64
  vy = 0 ## i64
  if g0x != 0
    vx = 1
    vx = 2 + hv_eg(cab, d, 1) if g1x != 0
    vx = 0 - vx if hv_bypass(cab, d) != 0
  if g0y != 0
    vy = 1
    vy = 2 + hv_eg(cab, d, 1) if g1y != 0
    vy = 0 - vy if hv_bypass(cab, d) != 0
  cf[o] = vx
  cf[o + 1] = vy
  0

# k-th order Exp-Golomb, bypass bins (9.3.3.3)
-> hv_eg(cab, d, k) (i64[] u8[] i64) i64
  v = 0 ## i64
  kk = (k) ## i64
  while hv_bypass(cab, d) != 0
    v += 1 << kk
    kk += 1
    if kk > 31
      return v
  v + hv_bypass_n(cab, d, kk)

# ---------------------------------------------------------------- motion storage

-> hv_store_motion(st, mp, cf, mc, xp, yp, w, h) (i64[] i32[] i32[] i64 i64 i64 i64 i64) i64
  w4 = (st[HS_W4]) ## i64
  mo = (st[HS_MV]) ## i64
  ri0 = (cf[mc + 4]) ## i64
  ri1 = (cf[mc + 5]) ## i64
  p0 = -1 ## i64
  p1 = -1 ## i64
  poc0 = 0 ## i64
  poc1 = 0 ## i64
  lt0 = 0 ## i64
  lt1 = 0 ## i64
  if ri0 >= 0
    e = (HS_I_REF + ri0 * 4) ## i64
    p0 = st[e + 2]
    poc0 = st[e + 1]
    lt0 = st[e + 3]
  if ri1 >= 0
    e = HS_I_REF + (16 + ri1) * 4
    p1 = st[e + 2]
    poc1 = st[e + 1]
    lt1 = st[e + 3]
  y = (yp >> 2) ## i64
  while y < (yp + h) >> 2
    x = (xp >> 2) ## i64
    while x < (xp + w) >> 2
      b = (mo + (y * w4 + x) * HMV_N) ## i64
      mp[b] = cf[mc]
      mp[b + 1] = cf[mc + 1]
      mp[b + 2] = cf[mc + 2]
      mp[b + 3] = cf[mc + 3]
      mp[b + 4] = p0
      mp[b + 5] = p1
      mp[b + 6] = ri0
      mp[b + 7] = ri1
      mp[b + 8] = poc0
      mp[b + 9] = poc1
      mp[b + 10] = lt0
      mp[b + 11] = lt1
      x += 1
    y += 1
  0

# prediction block availability (6.4.2); returns the motion-map base or -1
-> hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xn, yn) (i64[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if xc <= xn && yc <= yn && xn < xc + s && yn < yc + s
    same = 1
  a = 0 ## i64
  if same == 0
    a = hv_avail(st, mp, xp, yp, xn, yn)
  elsif (w << 1) == s && (h << 1) == s && pidx == 1 && yc + h <= yn && xc + w > xn
    a = 0
  else
    a = 1
  if a == 0
    return -1
  w4 = (st[HS_W4]) ## i64
  i = ((yn >> 2) * w4 + (xn >> 2)) ## i64
  if (mp[st[HS_M_FLAGS] + i] & HM_INTRA) != 0
    return -1
  st[HS_MV] + i * HMV_N

# ---------------------------------------------------------------- merge (8.5.3.2.2-5)

HV_L0CAND = [0, 1, 0, 2, 1, 2, 0, 3, 1, 3, 2, 3]
HV_L1CAND = [1, 0, 2, 0, 2, 1, 3, 0, 3, 1, 3, 2]

# candidate k at cf[HF_MC + k*6]: mv0x mv0y mv1x mv1y ri0 ri1
-> hv_cand_from(mp, b, cf, o) (i32[] i64 i32[] i64) i64
  cf[o] = mp[b]
  cf[o + 1] = mp[b + 1]
  cf[o + 2] = mp[b + 2]
  cf[o + 3] = mp[b + 3]
  cf[o + 4] = mp[b + 6]
  cf[o + 5] = mp[b + 7]
  0

-> hv_same_motion(mp, a, b) (i32[] i64 i64) i64
  if a < 0 || b < 0
    return 0
  if mp[a + 6] != mp[b + 6] || mp[a + 7] != mp[b + 7]
    return 0
  if mp[a + 6] >= 0 && (mp[a] != mp[b] || mp[a + 1] != mp[b + 1])
    return 0
  if mp[a + 7] >= 0 && (mp[a + 2] != mp[b + 2] || mp[a + 3] != mp[b + 3])
    return 0
  1

-> hv_merge(st, mp, cf, xp0, yp0, w0, h0, xc, yc, s, pidx0, midx) (i64[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  xp = (xp0) ## i64
  yp = (yp0) ## i64
  w = (w0) ## i64
  h = (h0) ## i64
  pidx = (pidx0) ## i64
  pml = (st[HS_PARMRG]) ## i64
  if pml > 2 && s == 8
    xp = xc
    yp = yc
    w = s
    h = s
    pidx = 0
  part = (st[HS_CU_PART]) ## i64
  n = 0 ## i64
  # A1
  xa1 = (xp - 1) ## i64
  ya1 = (yp + h - 1) ## i64
  a1 = -1 ## i64
  if !((xp >> pml) == (xa1 >> pml) && (yp >> pml) == (ya1 >> pml)) && !((part == 2 || part == 6 || part == 7) && pidx == 1)
    a1 = hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xa1, ya1)
  if a1 >= 0
    hv_cand_from(mp, a1, cf, HF_MC + n * HMC_N)
    n += 1
  # B1
  xb1 = (xp + w - 1) ## i64
  yb1 = (yp - 1) ## i64
  b1 = -1 ## i64
  if !((xp >> pml) == (xb1 >> pml) && (yp >> pml) == (yb1 >> pml)) && !((part == 1 || part == 4 || part == 5) && pidx == 1)
    b1 = hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xb1, yb1)
  b1r = (b1) ## i64
  b1 = -1 if b1 >= 0 && hv_same_motion(mp, a1, b1) != 0
  if b1 >= 0
    hv_cand_from(mp, b1, cf, HF_MC + n * HMC_N)
    n += 1
  # B0
  xb0 = (xp + w) ## i64
  yb0 = (yp - 1) ## i64
  b0 = -1 ## i64
  if !((xp >> pml) == (xb0 >> pml) && (yp >> pml) == (yb0 >> pml))
    b0 = hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xb0, yb0)
    b0 = -1 if b0 >= 0 && hv_same_motion(mp, b1r, b0) != 0
  if b0 >= 0
    hv_cand_from(mp, b0, cf, HF_MC + n * HMC_N)
    n += 1
  # A0
  xa0 = (xp - 1) ## i64
  ya0 = (yp + h) ## i64
  a0 = -1 ## i64
  if !((xp >> pml) == (xa0 >> pml) && (yp >> pml) == (ya0 >> pml))
    a0 = hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xa0, ya0)
    a0 = -1 if a0 >= 0 && hv_same_motion(mp, a1, a0) != 0
  if a0 >= 0
    hv_cand_from(mp, a0, cf, HF_MC + n * HMC_N)
    n += 1
  # B2
  if n < 4
    xb2 = (xp - 1) ## i64
    yb2 = (yp - 1) ## i64
    b2 = -1 ## i64
    if !((xp >> pml) == (xb2 >> pml) && (yp >> pml) == (yb2 >> pml))
      b2 = hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xb2, yb2)
      b2 = -1 if b2 >= 0 && (hv_same_motion(mp, a1, b2) != 0 || hv_same_motion(mp, b1r, b2) != 0)
    if b2 >= 0
      hv_cand_from(mp, b2, cf, HF_MC + n * HMC_N)
      n += 1
  maxm = (st[HS_MAXMERGE]) ## i64
  # temporal
  if n < maxm || midx >= n
    if midx >= n && st[HS_I_TMVP] != 0
      o = (HF_MC + n * HMC_N) ## i64
      f0 = (hv_tmvp(st, mp, cf, xp, yp, w, h, 0, 0, o)) ## i64
      f1 = 0 ## i64
      if st[HS_STYPE] == 0
        f1 = hv_tmvp(st, mp, cf, xp, yp, w, h, 1, 0, o + 2)
      if f0 != 0 || f1 != 0
        cf[o + 4] = f0 != 0 ? 0 : -1
        cf[o + 5] = f1 != 0 ? 0 : -1
        n += 1
  if midx < n
    hv_merge_pick(st, cf, midx, w0, h0)
    return 0
  # combined bi-predictive
  if st[HS_STYPE] == 0 && n > 1 && n < maxm
    norig = (n) ## i64
    ci = 0 ## i64
    while ci < norig * (norig - 1) && n < maxm
      l0 = (HF_MC + HV_L0CAND[ci] * HMC_N) ## i64
      l1 = (HF_MC + HV_L1CAND[ci] * HMC_N) ## i64
      if cf[l0 + 4] >= 0 && cf[l1 + 5] >= 0
        p0 = (st[HS_I_REF + cf[l0 + 4] * 4 + 2]) ## i64
        p1 = (st[HS_I_REF + (16 + cf[l1 + 5]) * 4 + 2]) ## i64
        if p0 != p1 || cf[l0] != cf[l1 + 2] || cf[l0 + 1] != cf[l1 + 3]
          o = HF_MC + n * HMC_N
          cf[o] = cf[l0]
          cf[o + 1] = cf[l0 + 1]
          cf[o + 2] = cf[l1 + 2]
          cf[o + 3] = cf[l1 + 3]
          cf[o + 4] = cf[l0 + 4]
          cf[o + 5] = cf[l1 + 5]
          n += 1
      ci += 1
  # zero candidates
  nref = (st[HS_NREF0]) ## i64
  if st[HS_STYPE] == 0 && st[HS_NREF1] < nref
    nref = st[HS_NREF1]
  zi = 0 ## i64
  while n <= midx
    o = HF_MC + n * HMC_N
    r = (zi < nref ? zi : 0) ## i64
    cf[o] = 0
    cf[o + 1] = 0
    cf[o + 2] = 0
    cf[o + 3] = 0
    cf[o + 4] = r
    cf[o + 5] = st[HS_STYPE] == 0 ? r : -1
    n += 1
    zi += 1
  hv_merge_pick(st, cf, midx, w0, h0)
  0

-> hv_merge_pick(st, cf, midx, w, h) (i64[] i32[] i64 i64 i64) i64
  o = (HF_MC + midx * HMC_N) ## i64
  mc = (HF_MC + 40) ## i64
  k = 0 ## i64
  while k < 6
    cf[mc + k] = cf[o + k]
    k += 1
  if cf[mc + 4] >= 0 && cf[mc + 5] >= 0 && w + h == 12
    cf[mc + 5] = -1
  0

# ---------------------------------------------------------------- AMVP (8.5.3.2.6-7)

-> hv_scale_mv(v, td0, tb0) (i64 i64 i64) i64
  td = (hv_clip3(-128, 127, td0)) ## i64
  tbv = (hv_clip3(-128, 127, tb0)) ## i64
  if td == 0
    return v
  atd = (td < 0 ? 0 - td : td) ## i64
  tx = ((16384 + (atd >> 1)) / td) ## i64
  dsf = (hv_clip3(-4096, 4095, (tbv * tx + 32) >> 6)) ## i64
  p = (dsf * v) ## i64
  ap = (p < 0 ? 0 - p : p) ## i64
  r = ((ap + 127) >> 8) ## i64
  r = 0 - r if p < 0
  hv_clip3(-32768, 32767, r)

# candidate mv from neighbour b for target picture (list X, ref poc/pid/lt);
# mode 0: same picture only; mode 1: any (scaled). Writes cf[o], cf[o+1]; returns 1 if found
-> hv_amvp_nb(st, mp, cf, b, lx, tpid, tpoc, tlt, mode, o) (i64[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64) i64
  if b < 0
    return 0
  ly = (1 - lx) ## i64
  cur = (st[HS_I_POC]) ## i64
  k = 0 ## i64
  while k < 2
    l = (k == 0 ? lx : ly) ## i64
    if mp[b + 6 + l] >= 0
      if mode == 0
        if mp[b + 4 + l] == tpid
          cf[o] = mp[b + 2 * l]
          cf[o + 1] = mp[b + 2 * l + 1]
          return 1
      else
        nlt = (mp[b + 10 + l]) ## i64
        if nlt == tlt
          mx = (mp[b + 2 * l]) ## i64
          my = (mp[b + 2 * l + 1]) ## i64
          if nlt == 0 && tlt == 0
            td = (cur - mp[b + 8 + l]) ## i64
            tbb = (cur - tpoc) ## i64
            if td != tbb
              mx = hv_scale_mv(mx, td, tbb)
              my = hv_scale_mv(my, td, tbb)
          cf[o] = mx
          cf[o + 1] = my
          return 1
    k += 1
  0

# result in cf[HF_MC + 30, 31]
-> hv_amvp(st, mp, cf, xp, yp, w, h, xc, yc, s, pidx, lx, ri, flag) (i64[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  e = (HS_I_REF + (lx * 16 + ri) * 4) ## i64
  tpoc = (st[e + 1]) ## i64
  tpid = (st[e + 2]) ## i64
  tlt = (st[e + 3]) ## i64
  oa = (HF_MC) ## i64
  ob = (HF_MC + 2) ## i64
  a0 = (hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xp - 1, yp + h)) ## i64
  a1 = (hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xp - 1, yp + h - 1)) ## i64
  scaled = ((a0 >= 0 || a1 >= 0) ? 1 : 0) ## i64
  fa = (hv_amvp_nb(st, mp, cf, a0, lx, tpid, tpoc, tlt, 0, oa)) ## i64
  fa = hv_amvp_nb(st, mp, cf, a1, lx, tpid, tpoc, tlt, 0, oa) if fa == 0
  fa = hv_amvp_nb(st, mp, cf, a0, lx, tpid, tpoc, tlt, 1, oa) if fa == 0
  fa = hv_amvp_nb(st, mp, cf, a1, lx, tpid, tpoc, tlt, 1, oa) if fa == 0
  b0 = (hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xp + w, yp - 1)) ## i64
  b1 = (hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xp + w - 1, yp - 1)) ## i64
  b2 = (hv_pb_avail(st, mp, xc, yc, s, xp, yp, w, h, pidx, xp - 1, yp - 1)) ## i64
  fb = (hv_amvp_nb(st, mp, cf, b0, lx, tpid, tpoc, tlt, 0, ob)) ## i64
  fb = hv_amvp_nb(st, mp, cf, b1, lx, tpid, tpoc, tlt, 0, ob) if fb == 0
  fb = hv_amvp_nb(st, mp, cf, b2, lx, tpid, tpoc, tlt, 0, ob) if fb == 0
  if scaled == 0 && fb != 0 && fa == 0
    fa = 1
    cf[oa] = cf[ob]
    cf[oa + 1] = cf[ob + 1]
  if scaled == 0
    fb = hv_amvp_nb(st, mp, cf, b0, lx, tpid, tpoc, tlt, 1, ob)
    fb = hv_amvp_nb(st, mp, cf, b1, lx, tpid, tpoc, tlt, 1, ob) if fb == 0
    fb = hv_amvp_nb(st, mp, cf, b2, lx, tpid, tpoc, tlt, 1, ob) if fb == 0
  if fa != 0 && fb != 0 && cf[oa] == cf[ob] && cf[oa + 1] == cf[ob + 1]
    fb = 0
  n = 0 ## i64
  lo = (HF_MC + 20) ## i64
  if fa != 0
    cf[lo] = cf[oa]
    cf[lo + 1] = cf[oa + 1]
    n += 1
  if fb != 0
    cf[lo + 2 * n] = cf[ob]
    cf[lo + 2 * n + 1] = cf[ob + 1]
    n += 1
  if n < 2 && flag >= n && st[HS_I_TMVP] != 0
    if hv_tmvp(st, mp, cf, xp, yp, w, h, lx, ri, lo + 2 * n) != 0
      n += 1
  while n < 2
    cf[lo + 2 * n] = 0
    cf[lo + 2 * n + 1] = 0
    n += 1
  cf[HF_MC + 30] = cf[lo + 2 * flag]
  cf[HF_MC + 31] = cf[lo + 2 * flag + 1]
  0

# ---------------------------------------------------------------- TMVP (8.5.3.2.8-9)

-> hv_tmvp(st, mp, cf, xp, yp, w, h, lx, ri, o) (i64[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64) i64
  if st[HS_I_COLMV] < 0
    return 0
  xbr = (xp + w) ## i64
  ybr = (yp + h) ## i64
  l = (st[HS_CTB]) ## i64
  if (yp >> l) == (ybr >> l) && ybr < st[HS_H] && xbr < st[HS_W]
    if hv_col_mv(st, mp, cf, (xbr >> 4) << 4, (ybr >> 4) << 4, lx, ri, o) != 0
      return 1
  xct = (xp + (w >> 1)) ## i64
  yct = (yp + (h >> 1)) ## i64
  hv_col_mv(st, mp, cf, (xct >> 4) << 4, (yct >> 4) << 4, lx, ri, o)

-> hv_col_mv(st, mp, cf, x, y, lx, ri, o) (i64[] i32[] i32[] i64 i64 i64 i64 i64) i64
  b = (st[HS_I_COLMV] + ((y >> 2) * st[HS_W4] + (x >> 2)) * HMV_N) ## i64
  r0 = (mp[b + 6]) ## i64
  r1 = (mp[b + 7]) ## i64
  if r0 < 0 && r1 < 0
    return 0
  lc = 0 ## i64
  if r0 < 0
    lc = 1
  elsif r1 >= 0
    if st[HS_I_NOBWD] != 0
      lc = lx
    else
      lc = st[HS_I_COLL0]
  e = (HS_I_REF + (lx * 16 + ri) * 4) ## i64
  tpoc = (st[e + 1]) ## i64
  tlt = (st[e + 3]) ## i64
  if mp[b + 10 + lc] != tlt
    return 0
  mx = (mp[b + 2 * lc]) ## i64
  my = (mp[b + 2 * lc + 1]) ## i64
  colpoc = (st[HS_I_COLPOC]) ## i64
  cpd = (colpoc - mp[b + 8 + lc]) ## i64
  cud = (st[HS_I_POC] - tpoc) ## i64
  if tlt == 0 && cpd != cud
    mx = hv_scale_mv(mx, cpd, cud)
    my = hv_scale_mv(my, cpd, cud)
  cf[o] = mx
  cf[o + 1] = my
  1

# ---------------------------------------------------------------- motion compensation (8.5.3.3)

-> hv_mc(st, tb, px, cf, mc, xp, yp, w, h) (i64[] i32[] u16[] i32[] i64 i64 i64 i64 i64) i64
  ri0 = cf[mc + 4] ## i64
  ri1 = cf[mc + 5] ## i64
  mv0x = cf[mc] ## i64
  mv0y = cf[mc + 1] ## i64
  mv1x = cf[mc + 2] ## i64
  mv1y = cf[mc + 3] ## i64
  ct = (st[HS_CT]) ## i64
  ncomp = (ct == 0 ? 1 : 3) ## i64
  c = 0 ## i64
  while c < ncomp
    if ri0 >= 0
      hv_mc_comp(st, tb, px, cf, HS_I_REF + ri0 * 4, mv0x, mv0y, xp, yp, w, h, c, HF_P0)
    if ri1 >= 0
      hv_mc_comp(st, tb, px, cf, HS_I_REF + (16 + ri1) * 4, mv1x, mv1y, xp, yp, w, h, c, HF_P1)
    hv_weighted(st, px, cf, xp, yp, w, h, c, ri0, ri1)
    c += 1
  0

# Interpolate one component of one reference into cf[dst] (14-bit intermediate).
-> hv_mc_comp(st, tb, px, cf, re, mvx, mvy, xp, yp, w, h, c, dst) (i64[] i32[] u16[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  rbase = (st[re]) ## i64
  pw = (st[HS_W]) ## i64
  ph = (st[HS_H]) ## i64
  bd = (st[HS_BDY]) ## i64
  if c > 0
    rbase = rbase + pw * ph
    if c == 2
      rbase = rbase + st[HS_CW] * st[HS_CH]
    bd = st[HS_BDC]
  if c == 0
    return hv_mc_luma(px, rbase, pw, ph, tb, cf, xp + (mvx >> 2), yp + (mvy >> 2), mvx & 3, mvy & 3, w, h, bd, dst)
  ssx = (st[HS_SSX]) ## i64
  ssy = (st[HS_SSY]) ## i64
  # chroma mv in 1/8 (4:2:0) or 1/4-on-1/8 units
  mcx = (mvx * 2 / (1 << ssx)) ## i64
  mcy = (mvy * 2 / (1 << ssy)) ## i64
  if ssx == 0
    mcx = mvx * 2
  if ssy == 0
    mcy = mvy * 2
  if ssx == 1
    mcx = mvx
  if ssy == 1
    mcy = mvy
  hv_mc_chroma(px, rbase, st[HS_CW], st[HS_CH], tb, cf, (xp >> ssx) + (mcx >> 3), (yp >> ssy) + (mcy >> 3), mcx & 7, mcy & 7, w >> ssx, h >> ssy, bd, dst)

# Copy the (w + 2*m - 1) x (h + 2*m - 1) source window starting at (xi - m + 1,
# yi - m + 1) into cf[HF_PS], clamping coordinates to the picture (reference
# sample padding, 8.5.3.3.3.1). Returns the window stride.
-> hv_mc_fetch(px, rb, pw, ph, cf, xi, yi, w, h, m) (u16[] i64 i64 i64 i32[] i64 i64 i64 i64 i64) i64
  ww = (w + 2 * m - 1) ## i64
  hh = (h + 2 * m - 1) ## i64
  x0 = (xi - m + 1) ## i64
  y0 = (yi - m + 1) ## i64
  inside = 0 ## i64
  if x0 >= 0 && y0 >= 0 && x0 + ww <= pw && y0 + hh <= ph
    inside = 1
  y = 0 ## i64
  while y < hh
    yy = (y0 + y) ## i64
    if inside == 0
      yy = 0 if yy < 0
      yy = ph - 1 if yy >= ph
    r = (rb + yy * pw) ## i64
    o = (HF_PS + y * ww) ## i64
    x = 0 ## i64
    if inside != 0
      q = (r + x0) ## i64
      while x < ww
        cf[o + x] = px[q + x]
        x += 1
    else
      while x < ww
        xx = (x0 + x) ## i64
        xx = 0 if xx < 0
        xx = pw - 1 if xx >= pw
        cf[o + x] = px[r + xx]
        x += 1
    y += 1
  ww

-> hv_mc_luma(px, rb, pw, ph, tb, cf, xi, yi, fx, fy, w, h, bd, dst) (u16[] i64 i64 i64 i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  sh1 = (bd - 8) ## i64
  sh1 = 4 if sh1 > 4
  sh3 = (14 - bd) ## i64
  sh3 = 2 if sh3 < 2
  if fx == 0 && fy == 0
    y = 0 ## i64
    while y < h
      yy = (yi + y) ## i64
      yy = 0 if yy < 0
      yy = ph - 1 if yy >= ph
      r = (rb + yy * pw) ## i64
      o = (dst + y * w) ## i64
      x = 0 ## i64
      if xi >= 0 && xi + w <= pw
        q = (r + xi) ## i64
        while x < w
          cf[o + x] = px[q + x] << sh3
          x += 1
      else
        while x < w
          xx = (xi + x) ## i64
          xx = 0 if xx < 0
          xx = pw - 1 if xx >= pw
          cf[o + x] = px[r + xx] << sh3
          x += 1
      y += 1
    return 0
  sw = (hv_mc_fetch(px, rb, pw, ph, cf, xi, yi, w, h, 4)) ## i64
  if fy == 0
    fo = (HT_LFILT + fx * 8) ## i64
    hv_filt8_h(cf, tb, fo, HF_PS + 3 * sw, sw, dst, w, w, h, sh1)
    return 0
  if fx == 0
    fo = HT_LFILT + fy * 8
    hv_filt8_v(cf, tb, fo, HF_PS + 3, sw, dst, w, w, h, sh1)
    return 0
  hv_filt8_h(cf, tb, HT_LFILT + fx * 8, HF_PS, sw, HF_PT, w, w, h + 7, sh1)
  hv_filt8_v(cf, tb, HT_LFILT + fy * 8, HF_PT, w, dst, w, w, h, 6)
  0

# 8-tap horizontal filter: src rows at s0 (stride ss), taps over src[x .. x+7]
-> hv_filt8_h(cf, tb, fo, s0, ss, d0, ds, w, h, sh) (i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  c0 = (tb[fo]) ## i64
  c1 = (tb[fo + 1]) ## i64
  c2 = (tb[fo + 2]) ## i64
  c3 = (tb[fo + 3]) ## i64
  c4 = (tb[fo + 4]) ## i64
  c5 = (tb[fo + 5]) ## i64
  c6 = (tb[fo + 6]) ## i64
  c7 = (tb[fo + 7]) ## i64
  y = 0 ## i64
  while y < h
    q = (s0 + y * ss) ## i64
    o = (d0 + y * ds) ## i64
    x = 0 ## i64
    while x < w
      p = (q + x) ## i64
      cf[o + x] = (c0 * cf[p] + c1 * cf[p + 1] + c2 * cf[p + 2] + c3 * cf[p + 3] + c4 * cf[p + 4] + c5 * cf[p + 5] + c6 * cf[p + 6] + c7 * cf[p + 7]) >> sh
      x += 1
    y += 1
  0

# 8-tap vertical filter: taps over src rows y .. y+7
-> hv_filt8_v(cf, tb, fo, s0, ss, d0, ds, w, h, sh) (i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  c0 = (tb[fo]) ## i64
  c1 = (tb[fo + 1]) ## i64
  c2 = (tb[fo + 2]) ## i64
  c3 = (tb[fo + 3]) ## i64
  c4 = (tb[fo + 4]) ## i64
  c5 = (tb[fo + 5]) ## i64
  c6 = (tb[fo + 6]) ## i64
  c7 = (tb[fo + 7]) ## i64
  y = 0 ## i64
  while y < h
    q = (s0 + y * ss) ## i64
    o = (d0 + y * ds) ## i64
    x = 0 ## i64
    while x < w
      p = (q + x) ## i64
      cf[o + x] = (c0 * cf[p] + c1 * cf[p + ss] + c2 * cf[p + 2 * ss] + c3 * cf[p + 3 * ss] + c4 * cf[p + 4 * ss] + c5 * cf[p + 5 * ss] + c6 * cf[p + 6 * ss] + c7 * cf[p + 7 * ss]) >> sh
      x += 1
    y += 1
  0

-> hv_filt4_h(cf, tb, fo, s0, ss, d0, ds, w, h, sh) (i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  c0 = (tb[fo]) ## i64
  c1 = (tb[fo + 1]) ## i64
  c2 = (tb[fo + 2]) ## i64
  c3 = (tb[fo + 3]) ## i64
  y = 0 ## i64
  while y < h
    q = (s0 + y * ss) ## i64
    o = (d0 + y * ds) ## i64
    x = 0 ## i64
    while x < w
      p = (q + x) ## i64
      cf[o + x] = (c0 * cf[p] + c1 * cf[p + 1] + c2 * cf[p + 2] + c3 * cf[p + 3]) >> sh
      x += 1
    y += 1
  0

-> hv_filt4_v(cf, tb, fo, s0, ss, d0, ds, w, h, sh) (i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  c0 = (tb[fo]) ## i64
  c1 = (tb[fo + 1]) ## i64
  c2 = (tb[fo + 2]) ## i64
  c3 = (tb[fo + 3]) ## i64
  y = 0 ## i64
  while y < h
    q = (s0 + y * ss) ## i64
    o = (d0 + y * ds) ## i64
    x = 0 ## i64
    while x < w
      p = (q + x) ## i64
      cf[o + x] = (c0 * cf[p] + c1 * cf[p + ss] + c2 * cf[p + 2 * ss] + c3 * cf[p + 3 * ss]) >> sh
      x += 1
    y += 1
  0

-> hv_mc_chroma(px, rb, pw, ph, tb, cf, xi, yi, fx, fy, w, h, bd, dst) (u16[] i64 i64 i64 i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  sh1 = (bd - 8) ## i64
  sh1 = 4 if sh1 > 4
  sh3 = (14 - bd) ## i64
  sh3 = 2 if sh3 < 2
  sw = (hv_mc_fetch(px, rb, pw, ph, cf, xi, yi, w, h, 2)) ## i64
  if fx == 0 && fy == 0
    y = 0 ## i64
    while y < h
      q = (HF_PS + (y + 1) * sw + 1) ## i64
      o = (dst + y * w) ## i64
      x = 0 ## i64
      while x < w
        cf[o + x] = cf[q + x] << sh3
        x += 1
      y += 1
    return 0
  if fy == 0
    hv_filt4_h(cf, tb, HT_CFILT + fx * 4, HF_PS + sw, sw, dst, w, w, h, sh1)
    return 0
  if fx == 0
    hv_filt4_v(cf, tb, HT_CFILT + fy * 4, HF_PS + 1, sw, dst, w, w, h, sh1)
    return 0
  hv_filt4_h(cf, tb, HT_CFILT + fx * 4, HF_PS, sw, HF_PT, w, w, h + 3, sh1)
  hv_filt4_v(cf, tb, HT_CFILT + fy * 4, HF_PT, w, dst, w, w, h, 6)
  0

# Weighted sample prediction (8.5.3.3.4) into the picture.
-> hv_weighted(st, px, cf, xp, yp, w0, h0, c, ri0, ri1) (i64[] u16[] i32[] i64 i64 i64 i64 i64 i64 i64) i64
  w = (w0) ## i64
  h = (h0) ## i64
  po = (st[HS_PY]) ## i64
  stride = (st[HS_W]) ## i64
  bd = (st[HS_BDY]) ## i64
  x0 = (xp) ## i64
  y0 = (yp) ## i64
  if c > 0
    w = w0 >> st[HS_SSX]
    h = h0 >> st[HS_SSY]
    x0 = xp >> st[HS_SSX]
    y0 = yp >> st[HS_SSY]
    po = c == 1 ? st[HS_PCB] : st[HS_PCR]
    stride = st[HS_CW]
    bd = st[HS_BDC]
  mx = ((1 << bd) - 1) ## i64
  sh1 = (14 - bd) ## i64
  sh1 = 2 if sh1 < 2
  bi = ((ri0 >= 0 && ri1 >= 0) ? 1 : 0) ## i64
  if st[HS_I_WP] == 0
    if bi != 0
      sh2 = (15 - bd) ## i64
      sh2 = 3 if sh2 < 3
      of2 = (1 << (sh2 - 1)) ## i64
      y = 0 ## i64
      while y < h
        r = (po + (y0 + y) * stride + x0) ## i64
        x = 0 ## i64
        while x < w
          v = ((cf[HF_P0 + y * w + x] + cf[HF_P1 + y * w + x] + of2) >> sh2) ## i64
          v = 0 if v < 0
          v = mx if v > mx
          px[r + x] = v
          x += 1
        y += 1
    else
      src = (ri0 >= 0 ? HF_P0 : HF_P1) ## i64
      of1 = (sh1 > 0 ? 1 << (sh1 - 1) : 0) ## i64
      y = 0
      while y < h
        r = po + (y0 + y) * stride + x0
        x = 0
        while x < w
          v = (cf[src + y * w + x] + of1) >> sh1
          v = 0 if v < 0
          v = mx if v > mx
          px[r + x] = v
          x += 1
        y += 1
    return 0
  # explicit weights
  ld = (c == 0 ? st[HS_I_LD] : st[HS_I_CD]) ## i64
  l2wd = (ld + sh1) ## i64
  w0v = 0 ## i64
  o0v = 0 ## i64
  w1v = 0 ## i64
  o1v = 0 ## i64
  if ri0 >= 0
    e = (HS_I_W + ri0 * 6 + c * 2) ## i64
    w0v = st[e]
    o0v = st[e + 1]
  if ri1 >= 0
    e = HS_I_W + (16 + ri1) * 6 + c * 2
    w1v = st[e]
    o1v = st[e + 1]
  y = 0
  while y < h
    r = po + (y0 + y) * stride + x0
    x = 0
    while x < w
      v = 0 ## i64
      if bi != 0
        v = (cf[HF_P0 + y * w + x] * w0v + cf[HF_P1 + y * w + x] * w1v + ((o0v + o1v + 1) << l2wd)) >> (l2wd + 1)
      else
        pv = 0 ## i64
        ww = (w0v) ## i64
        oo = (o0v) ## i64
        if ri0 >= 0
          pv = cf[HF_P0 + y * w + x]
        else
          pv = cf[HF_P1 + y * w + x]
          ww = w1v
          oo = o1v
        if l2wd >= 1
          v = ((pv * ww + (1 << (l2wd - 1))) >> l2wd) + oo
        else
          v = pv * ww + oo
      v = 0 if v < 0
      v = mx if v > mx
      px[r + x] = v
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- picture / slice setup

-> hv_inter_picture_setup(dec)
  nil

# Reference picture lists (8.3.4), weights, TMVP setup for a P/B slice.
-> hv_inter_slice_setup(dec, sh)
  st = dec.st
  lists = dec.rps_lists
  before = lists[0]
  after = lists[1]
  ltc = lists[2]
  total = before.size + after.size + ltc.size
  raise HevcError.new("hevc: P/B slice without reference pictures") if total == 0
  pic = dec.pic
  st[HS_I_POC] = pic.poc
  ss = dec.slot_size
  nl = sh[:type] == 0 ? 2 : 1
  rl = [[], []]
  l = 0
  while l < nl
    n = l == 0 ? sh[:nref0] : sh[:nref1]
    ntemp = n > total ? n : total
    temp = []
    tlt = []
    order = l == 0 ? [before, after, ltc] : [after, before, ltc]
    while temp.size < ntemp
      k = 0
      while k < 3
        order[k].each ->(p)
          if temp.size < ntemp
            temp.push(p)
            tlt.push(k == 2)
        k += 1
    mods = l == 0 ? sh[:mod0] : sh[:mod1]
    i = 0
    while i < n
      j = mods == nil ? i : mods[i]
      raise HevcError.new("hevc: bad list entry") if j >= temp.size
      p = temp[j]
      rl[l].push(p)
      e = HS_I_REF + (l * 16 + i) * 4
      st[e] = p.slot * ss
      st[e + 1] = p.poc
      st[e + 2] = p.id
      st[e + 3] = tlt[j] ? 1 : 0
      i += 1
    l += 1
  dec.ref_lists = rl
  pps = dec.pic_pps
  wp = (pps[:wp] && sh[:type] == 1) || (pps[:wbp] && sh[:type] == 0)
  st[HS_I_WP] = wp ? 1 : 0
  if wp
    st[HS_I_LD] = sh[:luma_denom]
    st[HS_I_CD] = sh[:chroma_denom]
    l = 0
    while l < nl
      ws = sh[:weights][l]
      i = 0
      while i < ws.size
        k = 0
        while k < 6
          st[HS_I_W + (l * 16 + i) * 6 + k] = ws[i][k]
          k += 1
        i += 1
      l += 1
  # TMVP
  st[HS_I_TMVP] = sh[:tmvp] ? 1 : 0
  st[HS_I_COLMV] = -1
  st[HS_I_COLL0] = sh[:col_l0] ? 1 : 0
  if sh[:tmvp]
    cl = (sh[:type] == 0 && !sh[:col_l0]) ? 1 : 0
    cp = rl[cl][sh[:col_ref]]
    if cp != nil
      st[HS_I_COLMV] = st[HS_MV_BASE] + cp.slot * dec.n4 * HMV_N
      st[HS_I_COLPOC] = cp.poc
  nb = 1
  rl.each ->(lst)
    lst.each ->(p) nb = 0 if p.poc > pic.poc
  st[HS_I_NOBWD] = nb
  nil

-> hv_inter_picture_done(dec, pic)
  nil
