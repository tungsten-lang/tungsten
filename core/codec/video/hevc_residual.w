# core/codec/video/hevc_residual — HEVC residual coding (7.3.8.11, 9.3.4.2.4-9.3.4.2.7),
# scaling (8.6.2-8.6.3), inverse transforms (8.6.4: 4x4 DST, DCT 4..32,
# transform skip, transquant bypass, rotation and RDPCM from the range
# extensions) and reconstruction into the picture.

use hevc_slice

HV_SF_BASE = [0, 96, 480, 2016]

-> hv_residual(d, cab, st, tb, mp, px, cf, x0, y0, log2, c, pmode) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64 i64) i64
  n = (1 << log2) ## i64
  tqb = (st[HS_CU_TQB]) ## i64
  intra = (st[HS_CU_PRED]) ## i64
  ts = 0 ## i64
  if st[HS_TS] != 0 && tqb == 0 && log2 <= st[HS_LOG2MAXTS]
    ts = hv_bin(cab, d, tb, HC_TS + (c > 0 ? 1 : 0))
  erd = 0 ## i64
  erdir = 0 ## i64
  if intra == 0 && st[HS_EXPL_RDPCM] != 0 && (ts != 0 || tqb != 0)
    erd = hv_bin(cab, d, tb, HC_RDPCM_F + (c > 0 ? 1 : 0))
    if erd != 0
      erdir = hv_bin(cab, d, tb, HC_RDPCM_D + (c > 0 ? 1 : 0))
  # last significant coefficient
  off = 15 ## i64
  shf = (log2 - 2) ## i64
  if c == 0
    off = 3 * (log2 - 2) + ((log2 - 1) >> 2)
    shf = (log2 + 1) >> 2
  cmax = ((log2 << 1) - 1) ## i64
  lxp = 0 ## i64
  while lxp < cmax && hv_bin(cab, d, tb, HC_LASTX + off + (lxp >> shf)) != 0
    lxp += 1
  lyp = 0 ## i64
  while lyp < cmax && hv_bin(cab, d, tb, HC_LASTY + off + (lyp >> shf)) != 0
    lyp += 1
  lx = (lxp) ## i64
  if lxp > 3
    nb = ((lxp >> 1) - 1) ## i64
    lx = (1 << nb) * (2 + (lxp & 1)) + hv_bypass_n(cab, d, nb)
  ly = (lyp) ## i64
  if lyp > 3
    nb = (lyp >> 1) - 1
    ly = (1 << nb) * (2 + (lyp & 1)) + hv_bypass_n(cab, d, nb)
  scan = 0 ## i64
  if intra != 0 && (log2 == 2 || (log2 == 3 && c == 0) || (log2 == 3 && st[HS_CT] == 3))
    if pmode >= 6 && pmode <= 14
      scan = 2
    elsif pmode >= 22 && pmode <= 30
      scan = 1
  if scan == 2
    t = (lx) ## i64
    lx = ly
    ly = t
  # clear coefficients
  i = 0 ## i64
  nn = (n * n) ## i64
  while i < nn
    cf[HF_COEF + i] = 0
    i += 1
  lsb = (log2 - 2) ## i64
  sbn = (1 << lsb) ## i64
  i = 0
  while i < sbn * sbn
    cf[HF_CSBF + i] = 0
    i += 1
  so = (HT_SCAN + (lsb * 3 + scan) * 128) ## i64
  po = (HT_SCAN + (2 * 3 + scan) * 128) ## i64
  # locate last sub-block / position
  lastsb = (sbn * sbn - 1) ## i64
  lastpos = 16 ## i64
  found = 0 ## i64
  while found == 0
    if lastpos == 0
      lastpos = 16
      lastsb -= 1
    lastpos -= 1
    xs = (tb[so + 2 * lastsb]) ## i64
    ys = (tb[so + 2 * lastsb + 1]) ## i64
    xc = ((xs << 2) + tb[po + 2 * lastpos]) ## i64
    yc = ((ys << 2) + tb[po + 2 * lastpos + 1]) ## i64
    if xc == lx && yc == ly
      found = 1
    if lastsb < 0
      return 0
  # scaling setup
  ctype = (st[HS_CT]) ## i64
  bd = (c == 0 ? st[HS_BDY] : st[HS_BDC]) ## i64
  qp = 0 ## i64
  if c == 0
    qp = st[HS_QPY] + 6 * (st[HS_BDY] - 8)
  else
    offc = (6 * (st[HS_BDC] - 8)) ## i64
    qpi = (st[HS_QPY] + (c == 1 ? st[HS_CBOFF] + st[HS_SCBOFF] + st[HS_CUQPO_CB] : st[HS_CROFF] + st[HS_SCROFF] + st[HS_CUQPO_CR])) ## i64
    qpi = 0 - offc if qpi < 0 - offc
    qpi = 57 if qpi > 57
    qpc = (qpi) ## i64
    if ctype == 1
      if qpi >= 0
        qpc = tb[HT_QPC + qpi]
    else
      qpc = 51 if qpi > 51
    qp = qpc + offc
  bdshift = (bd + log2 - 5) ## i64
  ls = (tb[HT_LEVELSCALE + qp % 6] << (qp / 6)) ## i64
  rnd = (1 << (bdshift - 1)) ## i64
  usesl = 0 ## i64
  if st[HS_SL] != 0 && !(ts != 0 && n > 4)
    usesl = 1
  sfo = (HF_SF + HV_SF_BASE[log2 - 2] + (c + (intra != 0 ? 0 : 3)) * nn) ## i64
  # sign hiding / context controls
  bypass_sbh = 0 ## i64
  if tqb != 0 || (intra != 0 && st[HS_IMPL_RDPCM] != 0 && ts != 0 && (pmode == 10 || pmode == 26)) || erd != 0
    bypass_sbh = 1
  tsctx = 0 ## i64
  tsctx = 1 if st[HS_TS_CTX] != 0 && (ts != 0 || tqb != 0)
  sbtype = ((c == 0 ? 2 : 0) + ((ts != 0 || tqb != 0) ? 1 : 0)) ## i64
  persist = (st[HS_PERSIST_RICE]) ## i64
  maxx = 0 ## i64
  maxy = 0 ## i64
  c1 = 1 ## i64
  sbi = (lastsb) ## i64
  while sbi >= 0
    xs = tb[so + 2 * sbi]
    ys = tb[so + 2 * sbi + 1]
    infer_dc = 0 ## i64
    csbf = 1 ## i64
    if sbi < lastsb && sbi > 0
      cc = 0 ## i64
      if xs < sbn - 1
        cc = cc | cf[HF_CSBF + ys * sbn + xs + 1]
      if ys < sbn - 1
        cc = cc | cf[HF_CSBF + (ys + 1) * sbn + xs]
      csbf = hv_bin(cab, d, tb, HC_CSB + cc + (c > 0 ? 2 : 0))
      infer_dc = 1
    cf[HF_CSBF + ys * sbn + xs] = csbf
    # significance
    k = 0 ## i64
    while k < 16
      cf[HF_SIG + k] = 0
      k += 1
    nsig = 0 ## i64
    start = 15 ## i64
    if sbi == lastsb
      start = lastpos - 1
      cf[HF_SIG + lastpos] = 1
      nsig = 1
    if csbf != 0
      prevcsbf = 0 ## i64
      if xs < sbn - 1
        prevcsbf += cf[HF_CSBF + ys * sbn + xs + 1]
      if ys < sbn - 1
        prevcsbf += cf[HF_CSBF + (ys + 1) * sbn + xs] << 1
      p = (start) ## i64
      while p >= 0
        xp = (tb[po + 2 * p]) ## i64
        yp = (tb[po + 2 * p + 1]) ## i64
        sig = 0 ## i64
        if p > 0 || infer_dc == 0
          # context
          sc = 0 ## i64
          if tsctx != 0
            sc = c == 0 ? 42 : 16
          elsif log2 == 2
            sc = tb[HT_CTXMAP + (yp << 2) + xp]
          elsif xs == 0 && ys == 0 && xp == 0 && yp == 0
            sc = 0
          else
            if prevcsbf == 0
              sc = (xp + yp == 0) ? 2 : ((xp + yp < 3) ? 1 : 0)
            elsif prevcsbf == 1
              sc = yp == 0 ? 2 : (yp == 1 ? 1 : 0)
            elsif prevcsbf == 2
              sc = xp == 0 ? 2 : (xp == 1 ? 1 : 0)
            else
              sc = 2
            if c == 0
              sc += 3 if xs + ys > 0
              if log2 == 3
                sc += scan == 0 ? 9 : 15
              else
                sc += 21
            else
              sc += log2 == 3 ? 9 : 12
          sig = hv_bin(cab, d, tb, HC_SIG + (c == 0 ? sc : 27 + sc))
          infer_dc = 0 if sig != 0
        else
          sig = 1
        if sig != 0
          cf[HF_SIG + p] = 1
          nsig += 1
        p -= 1
    if nsig > 0
      # greater1 / greater2 flags
      ctxset = ((sbi == 0 || c > 0) ? 0 : 2) ## i64
      ctxset += 1 if c1 == 0
      c1 = 1
      ng1 = 0 ## i64
      lastg1 = -1 ## i64
      firstsig = 16 ## i64
      lastsig = -1 ## i64
      g1o = (HC_G1 + (c > 0 ? 16 : 0) + ctxset * 4) ## i64
      p = 15
      while p >= 0
        if cf[HF_SIG + p] != 0
          if ng1 < 8
            g = (hv_bin(cab, d, tb, g1o + c1)) ## i64
            ng1 += 1
            if g != 0
              cf[HF_SIG + p] = 2
              c1 = 0
              lastg1 = p if lastg1 == -1
            elsif c1 > 0 && c1 < 3
              c1 += 1
          lastsig = p if lastsig == -1
          firstsig = p
        p -= 1
      hidden = 0 ## i64
      if bypass_sbh == 0 && st[HS_SIGNHIDE] != 0 && lastsig - firstsig > 3
        hidden = 1
      if lastg1 != -1
        if hv_bin(cab, d, tb, HC_G2 + (c > 0 ? 4 : 0) + ctxset) != 0
          cf[HF_SIG + lastg1] = 3
      # signs (bit 4 of the per-position value)
      p = 15
      while p >= 0
        if cf[HF_SIG + p] != 0 && (hidden == 0 || p != firstsig)
          if hv_bypass(cab, d) != 0
            cf[HF_SIG + p] = cf[HF_SIG + p] | 16
        p -= 1
      # remaining levels
      nsc = 0 ## i64
      sumabs = 0 ## i64
      rice = 0 ## i64
      if persist != 0
        rice = cab[HB_STAT + sbtype] >> 2
      first_rem = 1 ## i64
      p = 15
      while p >= 0
        v = (cf[HF_SIG + p]) ## i64
        if v != 0
          base = (v & 15) ## i64
          lev = (base) ## i64
          thr = 1 ## i64
          if nsc < 8
            thr = p == lastg1 ? 3 : 2
          if base == thr
            # coeff_abs_level_remaining
            pre = 0 ## i64
            while pre < 32 && hv_bypass(cab, d) != 0
              pre += 1
            rem = 0 ## i64
            if pre <= 3
              rem = (pre << rice) + hv_bypass_n(cab, d, rice)
            else
              rem = (((1 << (pre - 3)) + 2) << rice) + hv_bypass_n(cab, d, pre - 3 + rice)
            if persist != 0 && first_rem != 0
              sv = (cab[HB_STAT + sbtype]) ## i64
              if rem >= (3 << (sv >> 2))
                cab[HB_STAT + sbtype] = sv + 1
              elsif 2 * rem < (1 << (sv >> 2)) && sv > 0
                cab[HB_STAT + sbtype] = sv - 1
            first_rem = 0
            lev = base + rem
            if lev > 3 * (1 << rice)
              rice += 1
              # capped at 4 unless persistent Rice adaptation is on (HM / RExt)
              rice = 4 if rice > 4 && persist == 0
          xc = (xs << 2) + tb[po + 2 * p]
          yc = (ys << 2) + tb[po + 2 * p + 1]
          sl = (lev) ## i64
          sl = 0 - lev if (v & 16) != 0
          if hidden != 0
            sumabs += lev
            if p == firstsig && (sumabs & 1) == 1
              sl = 0 - sl
          # scale
          dv = (sl) ## i64
          if tqb == 0
            m = 16 ## i64
            if usesl != 0
              m = cf[sfo + yc * n + xc]
            dv = (sl * m * ls + rnd) >> bdshift
            dv = -32768 if dv < -32768
            dv = 32767 if dv > 32767
          cf[HF_COEF + yc * n + xc] = dv
          maxx = xc if xc > maxx
          maxy = yc if yc > maxy
          nsc += 1
        p -= 1
    sbi -= 1
  # reconstruct residual into HF_RES
  rot = 0 ## i64
  if st[HS_TS_ROT] != 0 && n == 4 && intra != 0 && (ts != 0 || tqb != 0)
    rot = 1
  rdpcm = 0 ## i64
  if ts != 0 || tqb != 0
    if intra != 0 && st[HS_IMPL_RDPCM] != 0
      rdpcm = 1 if pmode == 10
      rdpcm = 2 if pmode == 26
    if erd != 0
      rdpcm = erdir + 1
  if tqb != 0
    hv_res_copy(cf, n, rot)
  elsif ts != 0
    hv_res_ts(cf, n, rot, bd, log2)
  else
    dst = 0 ## i64
    dst = 1 if intra != 0 && n == 4 && c == 0
    if dst != 0
      hv_idst4(cf, bd)
    else
      hv_idct(cf, tb, n, log2, bd, maxx, maxy)
  if rdpcm != 0
    hv_rdpcm(cf, n, rdpcm)
  po2 = (st[HS_PY]) ## i64
  stride = (st[HS_W]) ## i64
  if c > 0
    po2 = c == 1 ? st[HS_PCB] : st[HS_PCR]
    stride = st[HS_CW]
  if st[HS_CROSS] != 0
    if c == 0
      hv_keep_resy(cf, n)
    elsif st[HS_RES_SCALE] != 0
      hv_ccp_add(cf, n, st[HS_RES_SCALE], st[HS_BDY], st[HS_BDC])
  hv_add_res(px, po2 + y0 * stride + x0, stride, cf, n, (1 << bd) - 1)
  0

-> hv_keep_resy(cf, n) (i32[] i64) i64
  i = 0 ## i64
  while i < n * n
    cf[HF_RESY + i] = cf[HF_RES + i]
    i += 1
  0

# cross-component prediction (7.3.8.12 / 8.6.6): chroma residual += scaled luma residual
-> hv_ccp_add(cf, n, rs, bdy, bdc) (i32[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < n * n
    cf[HF_RES + i] = cf[HF_RES + i] + ((rs * ((cf[HF_RESY + i] << bdc) >> bdy)) >> 3)
    i += 1
  0

# chroma block without coded residual but with a cross-component term
-> hv_ccp_only(st, px, cf, x0, y0, log2, c) (i64[] u16[] i32[] i64 i64 i64 i64) i64
  n = (1 << log2) ## i64
  i = 0 ## i64
  while i < n * n
    cf[HF_RES + i] = 0
    i += 1
  hv_ccp_add(cf, n, st[HS_RES_SCALE], st[HS_BDY], st[HS_BDC])
  po = (c == 1 ? st[HS_PCB] : st[HS_PCR]) ## i64
  hv_add_res(px, po + y0 * st[HS_CW] + x0, st[HS_CW], cf, n, (1 << st[HS_BDC]) - 1)
  0

-> hv_add_res(px, o, stride, cf, n, mx) (u16[] i64 i64 i32[] i64 i64) i64
  y = 0 ## i64
  while y < n
    r = (o + y * stride) ## i64
    q = (HF_RES + y * n) ## i64
    x = 0 ## i64
    while x < n
      v = (px[r + x] + cf[q + x]) ## i64
      v = 0 if v < 0
      v = mx if v > mx
      px[r + x] = v
      x += 1
    y += 1
  0

-> hv_res_copy(cf, n, rot) (i32[] i64 i64) i64
  nn = (n * n) ## i64
  i = 0 ## i64
  while i < nn
    if rot != 0
      cf[HF_RES + i] = cf[HF_COEF + nn - 1 - i]
    else
      cf[HF_RES + i] = cf[HF_COEF + i]
    i += 1
  0

-> hv_res_ts(cf, n, rot, bd, log2) (i32[] i64 i64 i64 i64) i64
  nn = (n * n) ## i64
  tsh = (5 + log2) ## i64
  bsh = (20 - bd) ## i64
  rnd = (1 << (bsh - 1)) ## i64
  i = 0 ## i64
  while i < nn
    v = 0 ## i64
    if rot != 0
      v = cf[HF_COEF + nn - 1 - i]
    else
      v = cf[HF_COEF + i]
    cf[HF_RES + i] = ((v << tsh) + rnd) >> bsh
    i += 1
  0

-> hv_rdpcm(cf, n, mode) (i32[] i64 i64) i64
  if mode == 1
    y = 0 ## i64
    while y < n
      x = 1 ## i64
      while x < n
        cf[HF_RES + y * n + x] = cf[HF_RES + y * n + x] + cf[HF_RES + y * n + x - 1]
        x += 1
      y += 1
  else
    y = 1
    while y < n
      x = 0
      while x < n
        cf[HF_RES + y * n + x] = cf[HF_RES + y * n + x] + cf[HF_RES + (y - 1) * n + x]
        x += 1
      y += 1
  0

# 4x4 inverse DST (8.6.4.2), coefficients cf[HF_COEF] → cf[HF_RES]
-> hv_idst4(cf, bd) (i32[] i64) i64
  # columns
  x = 0 ## i64
  while x < 4
    c0 = (cf[HF_COEF + x]) ## i64
    c1 = (cf[HF_COEF + 4 + x]) ## i64
    c2 = (cf[HF_COEF + 8 + x]) ## i64
    c3 = (cf[HF_COEF + 12 + x]) ## i64
    e0 = (29 * c0 + 74 * c1 + 84 * c2 + 55 * c3) ## i64
    e1 = (55 * c0 + 74 * c1 - 29 * c2 - 84 * c3) ## i64
    e2 = (74 * c0 - 74 * c2 + 74 * c3) ## i64
    e3 = (84 * c0 - 74 * c1 + 55 * c2 - 29 * c3) ## i64
    cf[HF_TMP + x] = hv_clip16((e0 + 64) >> 7)
    cf[HF_TMP + 4 + x] = hv_clip16((e1 + 64) >> 7)
    cf[HF_TMP + 8 + x] = hv_clip16((e2 + 64) >> 7)
    cf[HF_TMP + 12 + x] = hv_clip16((e3 + 64) >> 7)
    x += 1
  bsh = (20 - bd) ## i64
  rnd = (1 << (bsh - 1)) ## i64
  y = 0 ## i64
  while y < 4
    c0 = cf[HF_TMP + 4 * y]
    c1 = cf[HF_TMP + 4 * y + 1]
    c2 = cf[HF_TMP + 4 * y + 2]
    c3 = cf[HF_TMP + 4 * y + 3]
    cf[HF_RES + 4 * y] = (29 * c0 + 74 * c1 + 84 * c2 + 55 * c3 + rnd) >> bsh
    cf[HF_RES + 4 * y + 1] = (55 * c0 + 74 * c1 - 29 * c2 - 84 * c3 + rnd) >> bsh
    cf[HF_RES + 4 * y + 2] = (74 * c0 - 74 * c2 + 74 * c3 + rnd) >> bsh
    cf[HF_RES + 4 * y + 3] = (84 * c0 - 74 * c1 + 55 * c2 - 29 * c3 + rnd) >> bsh
    y += 1
  0

-> hv_clip16(v) (i64) i64
  if v < -32768
    return -32768
  if v > 32767
    return 32767
  v

# Inverse DCT of size n (direct matrix form, limited to the nonzero region).
-> hv_idct(cf, tb, n, log2, bd, maxx, maxy) (i32[] i32[] i64 i64 i64 i64 i64) i64
  fact = (32 >> log2) ## i64
  # columns: e[y][x] = sum_j M[j*fact][y] * c[j][x], j <= maxy
  x = 0 ## i64
  while x < n
    if x <= maxx
      y = 0 ## i64
      while y < n
        s = 0 ## i64
        j = 0 ## i64
        while j <= maxy
          s += tb[HT_DCT + j * fact * 32 + y] * cf[HF_COEF + j * n + x]
          j += 1
        cf[HF_TMP + y * n + x] = hv_clip16((s + 64) >> 7)
        y += 1
    else
      y = 0
      while y < n
        cf[HF_TMP + y * n + x] = 0
        y += 1
    x += 1
  bsh = (20 - bd) ## i64
  rnd = (1 << (bsh - 1)) ## i64
  y = 0
  while y < n
    x = 0
    while x < n
      s = 0 ## i64
      j = 0 ## i64
      while j <= maxx
        s += tb[HT_DCT + j * fact * 32 + x] * cf[HF_TMP + y * n + j]
        j += 1
      cf[HF_RES + y * n + x] = (s + rnd) >> bsh
      x += 1
    y += 1
  0
