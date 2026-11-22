# core/codec/image/jp2_dwt — JPEG 2000 inverse discrete wavelet transforms (T.800
# Annex F): the reversible 5/3 integer lifting filter on i64 samples and the
# irreversible 9/7 filter on f64 samples, with whole-sample symmetric
# extension and arbitrary (odd or even) sub-band origins.
#
# A tile-component lives in one array with row stride `stride`. Before level
# r is synthesised, its region [0, w_r) x [0, h_r) holds the low band in the
# first ceil-split columns/rows and the high band after it (the layout tier 1
# writes); afterwards the region holds the interleaved resolution-r samples.

# 9/7 lifting constants (Table F.4): alpha -1.586134342059924, beta
# -0.052980118572961, gamma 0.882911075530934, delta 0.443506852043971,
# K 1.230174104914001 — written as literals inside j2_i97_line so they stay
# unboxed.

# Symmetric (period 2n-2) index into [0, n).
-> j2_pse(i, n) (i64 i64) i64
  return 0 if n == 1
  per = 2 * n - 2
  k = i % per
  k += per if k < 0
  k = per - k if k >= n
  k

# One 5/3 synthesis line: a[off + j*step], j in [0, n), first the low
# samples then the high ones; i0 is the absolute coordinate of sample 0.
-> j2_i53_line(a, off, step, n, i0, t) (i64[] i64 i64 i64 i64 i64[]) i64
  if n == 1
    a[off] = a[off] / 2 if (i0 & 1) == 1
    return 0
  e = 2 + (i0 & 1)
  len = e + n + 3
  i1 = i0 + n
  lo0 = (i0 + 1) >> 1
  hi0 = i0 >> 1
  nl = ((i1 + 1) >> 1) - lo0
  k = 0 ## i64
  while k < n
    i = i0 + k
    src = 0 ## i64
    if (i & 1) == 0
      src = (i >> 1) - lo0
    else
      src = nl + (i >> 1) - hi0
    t[e + k] = a[off + src * step]
    k += 1
  k = 0
  while k < e
    t[k] = t[e + j2_pse(k - e, n)]
    k += 1
  k = e + n
  while k < len
    t[k] = t[e + j2_pse(k - e, n)]
    k += 1
  # base = i0 - e is even, so position parity is coordinate parity
  p = 2 ## i64
  while p < len - 1
    t[p] = t[p] - ((t[p - 1] + t[p + 1] + 2) >> 2)
    p += 2
  p = 3
  while p < len - 2
    t[p] = t[p] + ((t[p - 1] + t[p + 1]) >> 1)
    p += 2
  k = 0
  while k < n
    a[off + k * step] = t[e + k]
    k += 1
  0

-> j2_i97_line(a, off, step, n, i0, t) (f64[] i64 i64 i64 i64 f64[]) i64
  if n == 1
    a[off] = a[off] * ~0.5 if (i0 & 1) == 1
    return 0
  e = 4 + (i0 & 1)
  len = e + n + 5
  i1 = i0 + n
  lo0 = (i0 + 1) >> 1
  hi0 = i0 >> 1
  nl = ((i1 + 1) >> 1) - lo0
  k = 0 ## i64
  while k < n
    i = i0 + k
    src = 0 ## i64
    if (i & 1) == 0
      src = (i >> 1) - lo0
    else
      src = nl + (i >> 1) - hi0
    t[e + k] = a[off + src * step]
    k += 1
  k = 0
  while k < e
    t[k] = t[e + j2_pse(k - e, n)]
    k += 1
  k = e + n
  while k < len
    t[k] = t[e + j2_pse(k - e, n)]
    k += 1
  kk = ~1.230174104914001
  ik = ~1.0 / kk
  p = 0 ## i64
  while p < len
    t[p] = t[p] * kk
    t[p + 1] = t[p + 1] * ik if p + 1 < len
    p += 2
  dl = ~0.443506852043971
  p = 2
  while p < len - 1
    t[p] = t[p] - dl * (t[p - 1] + t[p + 1])
    p += 2
  gm = ~0.882911075530934
  p = 3
  while p < len - 2
    t[p] = t[p] - gm * (t[p - 1] + t[p + 1])
    p += 2
  bt = ~-0.052980118572961
  p = 4
  while p < len - 3
    t[p] = t[p] - bt * (t[p - 1] + t[p + 1])
    p += 2
  al = ~-1.586134342059924
  p = 5
  while p < len - 4
    t[p] = t[p] - al * (t[p - 1] + t[p + 1])
    p += 2
  k = 0
  while k < n
    a[off + k * step] = t[e + k]
    k += 1
  0

# Synthesise levels 1..nl. rx0/ry0/rw/rh give each resolution's origin and
# size (index 0..nl).
-> j2_idwt53(a, stride, nl, rx0, ry0, rwa, rha) (i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  mx = rwa[nl]
  mx = rha[nl] if rha[nl] > mx
  t = i64[mx + 16]
  r = 1 ## i64
  while r <= nl
    w = rwa[r]
    h = rha[r]
    if w > 0 && h > 0
      y = 0 ## i64
      while y < h
        j2_i53_line(a, y * stride, 1, w, rx0[r], t)
        y += 1
      x = 0 ## i64
      while x < w
        j2_i53_line(a, x, stride, h, ry0[r], t)
        x += 1
    r += 1
  0

-> j2_idwt97(a, stride, nl, rx0, ry0, rwa, rha) (f64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  mx = rwa[nl]
  mx = rha[nl] if rha[nl] > mx
  t = f64[mx + 16]
  r = 1 ## i64
  while r <= nl
    w = rwa[r]
    h = rha[r]
    if w > 0 && h > 0
      y = 0 ## i64
      while y < h
        j2_i97_line(a, y * stride, 1, w, rx0[r], t)
        y += 1
      x = 0 ## i64
      while x < w
        j2_i97_line(a, x, stride, h, ry0[r], t)
        x += 1
    r += 1
  0
