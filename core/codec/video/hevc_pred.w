# core/codec/video/hevc_pred — HEVC intra sample prediction (8.4.4.2): neighbouring
# sample availability and substitution, reference filtering (including strong
# intra smoothing), planar, DC and the 33 angular modes with their boundary
# filters. Predicted samples are written straight into the picture.
#
# Reference samples live in cf[HF_REF ...] as one line A[0 .. 4N]:
#   A[k] = p[-1][2N-1-k] (k < 2N), A[2N] = p[-1][-1], A[2N+1+k] = p[k][-1].

use hevc_slice

HR_A = 3072
HR_F = 3204
HR_AV = 3336
HR_R = 3470

-> hv_intra_pred(st, mp, tb, px, cf, x0, y0, log2, c, mode) (i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64 i64) i64
  n = (1 << log2) ## i64
  n2 = (n << 1) ## i64
  ssx = 0 ## i64
  ssy = 0 ## i64
  po = (st[HS_PY]) ## i64
  stride = (st[HS_W]) ## i64
  bd = (st[HS_BDY]) ## i64
  if c > 0
    ssx = st[HS_SSX]
    ssy = st[HS_SSY]
    po = c == 1 ? st[HS_PCB] : st[HS_PCR]
    stride = st[HS_CW]
    bd = st[HS_BDC]
  xl = (x0 << ssx) ## i64
  yl = (y0 << ssy) ## i64
  cip = (st[HS_CIP]) ## i64
  w4 = (st[HS_W4]) ## i64
  fo = (st[HS_M_FLAGS]) ## i64
  nav = 0 ## i64
  # left column, bottom to top; availability is per 4x4 luma unit
  lastu = -1 ## i64
  a = 0 ## i64
  k = 0 ## i64
  while k < n2
    y = (n2 - 1 - k) ## i64
    yy = ((y0 + y) << ssy) ## i64
    u = (yy >> 2) ## i64
    if u != lastu
      lastu = u
      a = hv_avail(st, mp, xl, yl, xl - 1, yy)
      if a != 0 && cip != 0 && (mp[fo + (yy >> 2) * w4 + ((xl - 1) >> 2)] & HM_INTRA) == 0
        a = 0
    cf[HR_AV + k] = a
    if a != 0
      cf[HR_A + k] = px[po + (y0 + y) * stride + x0 - 1]
      nav += 1
    k += 1
  # corner
  a = hv_avail(st, mp, xl, yl, xl - 1, yl - 1)
  if a != 0 && cip != 0 && (mp[fo + ((yl - 1) >> 2) * w4 + ((xl - 1) >> 2)] & HM_INTRA) == 0
    a = 0
  cf[HR_AV + n2] = a
  if a != 0
    cf[HR_A + n2] = px[po + (y0 - 1) * stride + x0 - 1]
    nav += 1
  # top row, left to right
  lastu = -1
  x = 0 ## i64
  while x < n2
    xx = ((x0 + x) << ssx) ## i64
    u = xx >> 2
    if u != lastu
      lastu = u
      a = hv_avail(st, mp, xl, yl, xx, yl - 1)
      if a != 0 && cip != 0 && (mp[fo + ((yl - 1) >> 2) * w4 + (xx >> 2)] & HM_INTRA) == 0
        a = 0
    cf[HR_AV + n2 + 1 + x] = a
    if a != 0
      cf[HR_A + n2 + 1 + x] = px[po + (y0 - 1) * stride + x0 + x]
      nav += 1
    x += 1
  tot = (2 * n2 + 1) ## i64
  if nav == 0
    v = (1 << (bd - 1)) ## i64
    k = 0
    while k < tot
      cf[HR_A + k] = v
      k += 1
  elsif nav < tot
    if cf[HR_AV] == 0
      k = 1
      while k < tot && cf[HR_AV + k] == 0
        k += 1
      cf[HR_A] = cf[HR_A + k]
    k = 1
    while k < tot
      if cf[HR_AV + k] == 0
        cf[HR_A + k] = cf[HR_A + k - 1]
      k += 1
  # filtering (8.4.4.2.3)
  ref = (HR_A) ## i64
  if st[HS_SMOOTH_DIS] == 0 && (c == 0 || st[HS_CT] == 3) && mode != 1 && n != 4
    md = (mode - 26) ## i64
    md = 0 - md if md < 0
    m2 = (mode - 10) ## i64
    m2 = 0 - m2 if m2 < 0
    md = m2 if m2 < md
    thr = 0 ## i64
    thr = 7 if n == 8
    thr = 1 if n == 16
    if md > thr
      ref = HR_F
      cr = (cf[HR_A + n2]) ## i64
      bl = (cf[HR_A]) ## i64
      tr = (cf[HR_A + 2 * n2]) ## i64
      strong = 0 ## i64
      if st[HS_STRONG] != 0 && c == 0 && n == 32
        lim = (1 << (bd - 5)) ## i64
        d1 = (cr + tr - 2 * cf[HR_A + n2 + n]) ## i64
        d1 = 0 - d1 if d1 < 0
        d2 = (cr + bl - 2 * cf[HR_A + n2 - n]) ## i64
        d2 = 0 - d2 if d2 < 0
        strong = 1 if d1 < lim && d2 < lim
      if strong != 0
        cf[HR_F + n2] = cr
        cf[HR_F] = bl
        cf[HR_F + 2 * n2] = tr
        i = 0 ## i64
        while i < 63
          # left: p[-1][i] = A[2N-1-i]
          cf[HR_F + n2 - 1 - i] = ((63 - i) * cr + (i + 1) * bl + 32) >> 6
          cf[HR_F + n2 + 1 + i] = ((63 - i) * cr + (i + 1) * tr + 32) >> 6
          i += 1
      else
        cf[HR_F] = cf[HR_A]
        cf[HR_F + tot - 1] = cf[HR_A + tot - 1]
        k = 1
        while k < tot - 1
          cf[HR_F + k] = (cf[HR_A + k - 1] + 2 * cf[HR_A + k] + cf[HR_A + k + 1] + 2) >> 2
          k += 1
  o = (po + y0 * stride + x0) ## i64
  mx = ((1 << bd) - 1) ## i64
  edge = 0 ## i64
  edge = 1 if c == 0 && n < 32 && !(st[HS_IMPL_RDPCM] != 0 && st[HS_CU_TQB] != 0)
  if mode == 0
    hv_pred_planar(px, o, stride, cf, ref, n, log2)
  elsif mode == 1
    hv_pred_dc(px, o, stride, cf, ref, n, log2, edge)
  else
    hv_pred_angular(px, o, stride, cf, tb, ref, n, mode, edge, mx)
  0

-> hv_pred_planar(px, o, stride, cf, ref, n, log2) (u16[] i64 i64 i32[] i64 i64 i64) i64
  n2 = (n << 1) ## i64
  tr = (cf[ref + n2 + 1 + n]) ## i64
  bl = (cf[ref + n2 - 1 - n]) ## i64
  sh = (log2 + 1) ## i64
  y = 0 ## i64
  while y < n
    left = (cf[ref + n2 - 1 - y]) ## i64
    x = 0 ## i64
    while x < n
      top = (cf[ref + n2 + 1 + x]) ## i64
      px[o + y * stride + x] = ((n - 1 - x) * left + (x + 1) * tr + (n - 1 - y) * top + (y + 1) * bl + n) >> sh
      x += 1
    y += 1
  0

-> hv_pred_dc(px, o, stride, cf, ref, n, log2, edge) (u16[] i64 i64 i32[] i64 i64 i64 i64) i64
  n2 = (n << 1) ## i64
  s = n ## i64
  i = 0 ## i64
  while i < n
    s += cf[ref + n2 + 1 + i] + cf[ref + n2 - 1 - i]
    i += 1
  dc = (s >> (log2 + 1)) ## i64
  y = 0 ## i64
  while y < n
    x = 0 ## i64
    while x < n
      px[o + y * stride + x] = dc
      x += 1
    y += 1
  if edge != 0
    px[o] = (cf[ref + n2 - 1] + 2 * dc + cf[ref + n2 + 1] + 2) >> 2
    x = 1
    while x < n
      px[o + x] = (cf[ref + n2 + 1 + x] + 3 * dc + 2) >> 2
      x += 1
    y = 1
    while y < n
      px[o + y * stride] = (cf[ref + n2 - 1 - y] + 3 * dc + 2) >> 2
      y += 1
  0

-> hv_pred_angular(px, o, stride, cf, tb, ref, n, mode, edge, mx) (u16[] i64 i64 i32[] i32[] i64 i64 i64 i64 i64) i64
  n2 = (n << 1) ## i64
  ang = (tb[HT_ANGLE + mode]) ## i64
  inv = (tb[HT_INVANGLE + mode]) ## i64
  # ref line R[k] for k = -n .. 2n at cf[HR_R + n + k]
  rb = (HR_R + n) ## i64
  if mode >= 18
    k = 0 ## i64
    while k <= n
      cf[rb + k] = cf[ref + n2 + k]
      k += 1
    if ang < 0
      lo = ((n * ang) >> 5) ## i64
      if lo < -1
        k = lo
        while k <= -1
          # p[-1][-1 + ((k*inv + 128) >> 8)]
          yy = (-1 + ((k * inv + 128) >> 8)) ## i64
          cf[rb + k] = cf[ref + n2 - 1 - yy]
          k += 1
    else
      k = n + 1
      while k <= n2
        cf[rb + k] = cf[ref + n2 + k]
        k += 1
    y = 0 ## i64
    while y < n
      pos = ((y + 1) * ang) ## i64
      idx = (pos >> 5) ## i64
      fr = (pos & 31) ## i64
      r = (o + y * stride) ## i64
      x = 0 ## i64
      if fr != 0
        while x < n
          px[r + x] = ((32 - fr) * cf[rb + x + idx + 1] + fr * cf[rb + x + idx + 2] + 16) >> 5
          x += 1
      else
        while x < n
          px[r + x] = cf[rb + x + idx + 1]
          x += 1
      y += 1
    if mode == 26 && edge != 0
      y = 0
      while y < n
        v = (cf[ref + n2 + 1] + ((cf[ref + n2 - 1 - y] - cf[ref + n2]) >> 1)) ## i64
        v = 0 if v < 0
        v = mx if v > mx
        px[o + y * stride] = v
        y += 1
  else
    k = 0 ## i64
    while k <= n
      cf[rb + k] = cf[ref + n2 - k]
      k += 1
    if ang < 0
      lo = (n * ang) >> 5
      if lo < -1
        k = lo
        while k <= -1
          xx = (-1 + ((k * inv + 128) >> 8)) ## i64
          cf[rb + k] = cf[ref + n2 + 1 + xx]
          k += 1
    else
      k = n + 1
      while k <= n2
        cf[rb + k] = cf[ref + n2 - k]
        k += 1
    x = 0 ## i64
    while x < n
      pos = (x + 1) * ang
      idx = pos >> 5
      fr = pos & 31
      y = 0 ## i64
      if fr != 0
        while y < n
          px[o + y * stride + x] = ((32 - fr) * cf[rb + y + idx + 1] + fr * cf[rb + y + idx + 2] + 16) >> 5
          y += 1
      else
        while y < n
          px[o + y * stride + x] = cf[rb + y + idx + 1]
          y += 1
      x += 1
    if mode == 10 && edge != 0
      x = 0
      while x < n
        v = cf[ref + n2 - 1] + ((cf[ref + n2 + 1 + x] - cf[ref + n2]) >> 1)
        v = 0 if v < 0
        v = mx if v > mx
        px[o + x] = v
        x += 1
  0
