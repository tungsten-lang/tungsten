# core/codec/audio/opus_celt — the CELT layer of the Opus decoder (RFC 6716 §4.3 with the
# RFC 8251 updates), a port of the libopus 1.5 float decoder: energy
# decoding, bit allocation, PVQ band decoding (theta splits, folding, TF
# changes, spreading, intensity / dual stereo), anti-collapse, the inverse
# MDCT (own mixed-radix FFT), the pitch post-filter and de-emphasis.
#
# Hot paths are typed functions over typed arrays. Pointers into the band
# buffers become (array, offset) pairs; the band workspace `w` (f64) holds
#   X at 0, Y at N (stereo), norm at CW_NORM (2 x 1024).
# The static mode (48 kHz, 960-sample frames) lives in CELT_MI (i32), whose
# regions are addressed with literal offsets:
#   0 eBands(22)  22 logN(21)  43 cache.index(105)  148 cache.bits(392)
#   540 cache.caps(168)  708 allocVectors(231)

use opus_rangedec
use opus_tables

-> celt_build_mi
  r = i64[939]
  parts = [CELT_EBAND5MS, CELT_LOGN400, CELT_CACHE_INDEX50, CELT_CACHE_BITS50, CELT_CACHE_CAPS50, CELT_BAND_ALLOCATION]
  o = 0
  parts.each ->(p)
    j = 0
    while j < p.size
      r[o + j] = p[j]
      j += 1
    o += p.size
  r

CELT_MI = celt_build_mi()
CELT_PVQ_ROW = op_tab_i64([0, 176, 351, 525, 698, 870, 1041, 1131, 1178, 1207, 1226, 1240, 1248, 1254, 1257])
CELT_EMEANS = %f64[6.437500 6.250000 5.750000 5.312500 5.062500 4.812500 4.500000 4.375000 4.875000 4.687500 4.562500 4.437500 4.875000 4.625000 4.312500 4.500000 4.375000 4.625000 4.750000 4.437500 3.750000 3.750000 3.750000 3.750000 3.750000]
CELT_TF_SELECT = op_tab_i64([0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, -2, 1, 0, 1, -1, 0, -2, 0, -3, 2, 0, 1, -1, 0, -2, 0, -3, 3, 0, 1, -1])
CELT_TRIM_ICDF = op_tab_u8([126, 124, 119, 109, 87, 41, 19, 9, 4, 2, 0])
CELT_SPREAD_ICDF = op_tab_u8([25, 23, 2, 0])
CELT_TAPSET_ICDF = op_tab_u8([2, 1, 0])
CELT_SMALL_ENERGY_ICDF = op_tab_u8([2, 1, 0])
CELT_PRED_COEF = %f64[0.8984375 0.796875 0.6484375 0.5]
CELT_BETA_COEF = %f64[0.920013427734375 0.679992675781250 0.369995117187500 0.200012207031250]
# misc small integer tables: ordery (0..29), bit_interleave (30..45),
# bit_deinterleave (46..61), exp2_table8 (62..69), spread factor (70..72),
# LOG2_FRAC_TABLE (73..96)
CELT_SMALL = op_tab_i64([1, 0, 3, 0, 2, 1, 7, 0, 4, 3, 6, 1, 5, 2, 15, 0, 8, 7, 12, 3, 11, 4, 14, 1, 9, 6, 13, 2, 10, 5, 0, 1, 1, 1, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 0, 3, 12, 15, 48, 51, 60, 63, 192, 195, 204, 207, 240, 243, 252, 255, 16384, 17866, 19483, 21247, 23170, 25267, 27554, 30048, 15, 10, 5, 0, 8, 13, 16, 19, 21, 23, 24, 26, 27, 28, 29, 30, 31, 32, 32, 33, 34, 34, 35, 36, 36, 37, 37])

# ---------------------------------------------------------------- FFT / MDCT

# window, mdct trig tables (per shift at offsets 0, 960, 1440, 1680) and the
# 480-point FFT twiddles (interleaved re, im).
-> celt_build_window
  w = f64[120]
  i = 0
  while i < 120
    s = Math.sin(~0.5 * ~3.141592653589793 * ((i ## f64) + ~0.5) / ~120.0)
    w[i] = Math.sin(~0.5 * ~3.141592653589793 * s * s) ## f64
    i += 1
  w

-> celt_build_trig
  t = f64[1800]
  o = 0
  n = 1920
  sh = 0
  while sh <= 3
    n2 = n >> 1
    i = 0
    while i < n2
      t[o + i] = Math.cos(~2.0 * ~3.141592653589793 * ((i ## f64) + ~0.125) / (n ## f64)) ## f64
      i += 1
    o += n2
    n = n >> 1
    sh += 1
  t

-> celt_build_twiddles
  t = f64[960]
  i = 0
  while i < 480
    ph = (~-2.0 * ~3.141592653589793 / ~480.0) * (i ## f64)
    t[2 * i] = Math.cos(ph) ## f64
    t[2 * i + 1] = Math.sin(ph) ## f64
    i += 1
  t

# kf_factor: returns [p0, m0, p1, m1, ...]
-> celt_kf_factor(n0)
  fac = []
  n = n0
  p = 4
  stages = 0
  while true
    while n % p != 0
      if p == 4
        p = 2
      elsif p == 2
        p = 3
      else
        p += 2
      p = n if p * p > n
    n = n / p
    fac.push(p)
    fac.push(0)
    if p == 2 && stages > 1
      fac[2 * stages] = 4
      fac[2] = 2
    stages += 1
    break if n <= 1
  i = 0
  while i < stages / 2
    tmp = fac[2 * i]
    fac[2 * i] = fac[2 * (stages - i - 1)]
    fac[2 * (stages - i - 1)] = tmp
    i += 1
  n = n0
  i = 0
  while i < stages
    n = n / fac[2 * i]
    fac[2 * i + 1] = n
    i += 1
  fac

-> celt_bitrev_rec(fout, f, foff, fstride, factors, fi)
  p = factors[fi]
  m = factors[fi + 1]
  fo = fout
  off = foff
  if m == 1
    j = 0
    while j < p
      f[off] = fo + j
      off += fstride
      j += 1
  else
    j = 0
    while j < p
      celt_bitrev_rec(fo, f, off, fstride * p, factors, fi + 2)
      off += fstride
      fo += m
      j += 1
  0

-> celt_build_fft(n)
  fac = celt_kf_factor(n)
  br = i64[n]
  celt_bitrev_rec(0, br, 0, 1, fac, 0)
  f = i64[fac.size + 2]
  i = 0
  while i < fac.size
    f[i] = fac[i]
    i += 1
  [f, br]

CELT_WINDOW = celt_build_window()
CELT_TRIG = celt_build_trig()
CELT_TWID = celt_build_twiddles()
CELT_FFT = [celt_build_fft(480), celt_build_fft(240), celt_build_fft(120), celt_build_fft(60)]

-> celt_bfly2(a, fo, n) (f64[] i64 i64) i64
  tw = ~0.7071067812 ## f64
  i = 0 ## i64
  p = fo
  while i < n
    q = p + 8
    tr = (a[q]) ## f64
    ti = (a[q + 1]) ## f64
    a[q] = a[p] - tr
    a[q + 1] = a[p + 1] - ti
    a[p] = a[p] + tr
    a[p + 1] = a[p + 1] + ti
    tr = ((a[q + 2] + a[q + 3]) * tw) ## f64
    ti = ((a[q + 3] - a[q + 2]) * tw) ## f64
    a[q + 2] = a[p + 2] - tr
    a[q + 3] = a[p + 3] - ti
    a[p + 2] = a[p + 2] + tr
    a[p + 3] = a[p + 3] + ti
    tr = (a[q + 5]) ## f64
    ti = ((~0.0 ## f64) - a[q + 4]) ## f64
    a[q + 4] = a[p + 4] - tr
    a[q + 5] = a[p + 5] - ti
    a[p + 4] = a[p + 4] + tr
    a[p + 5] = a[p + 5] + ti
    tr = ((a[q + 7] - a[q + 6]) * tw) ## f64
    ti = (((~0.0 ## f64) - (a[q + 7] + a[q + 6])) * tw) ## f64
    a[q + 6] = a[p + 6] - tr
    a[q + 7] = a[p + 7] - ti
    a[p + 6] = a[p + 6] + tr
    a[p + 7] = a[p + 7] + ti
    p += 16
    i += 1
  0

-> celt_bfly4(a, fo, fstride, tw, m, n, mm) (f64[] i64 i64 f64[] i64 i64 i64) i64
  if m == 1
    i = 0 ## i64
    p = fo
    while i < n
      s0r = (a[p] - a[p + 4]) ## f64
      s0i = (a[p + 1] - a[p + 5]) ## f64
      a[p] = a[p] + a[p + 4]
      a[p + 1] = a[p + 1] + a[p + 5]
      s1r = (a[p + 2] + a[p + 6]) ## f64
      s1i = (a[p + 3] + a[p + 7]) ## f64
      a[p + 4] = a[p] - s1r
      a[p + 5] = a[p + 1] - s1i
      a[p] = a[p] + s1r
      a[p + 1] = a[p + 1] + s1i
      s1r = (a[p + 2] - a[p + 6]) ## f64
      s1i = (a[p + 3] - a[p + 7]) ## f64
      a[p + 2] = s0r + s1i
      a[p + 3] = s0i - s1r
      a[p + 6] = s0r - s1i
      a[p + 7] = s0i + s1r
      p += 8
      i += 1
    return 0
  m2 = 2 * m
  m3 = 3 * m
  i = 0 ## i64
  while i < n
    p = fo + 2 * i * mm
    t1 = 0 ## i64
    t2 = 0 ## i64
    t3 = 0 ## i64
    j = 0 ## i64
    while j < m
      qa = p + 2 * m
      qb = p + 2 * m2
      qc = p + 2 * m3
      ar = (a[qa]) ## f64
      ai = (a[qa + 1]) ## f64
      s0r = (ar * tw[2 * t1] - ai * tw[2 * t1 + 1]) ## f64
      s0i = (ar * tw[2 * t1 + 1] + ai * tw[2 * t1]) ## f64
      ar = (a[qb]) ## f64
      ai = (a[qb + 1]) ## f64
      s1r = (ar * tw[2 * t2] - ai * tw[2 * t2 + 1]) ## f64
      s1i = (ar * tw[2 * t2 + 1] + ai * tw[2 * t2]) ## f64
      ar = (a[qc]) ## f64
      ai = (a[qc + 1]) ## f64
      s2r = ar * tw[2 * t3] - ai * tw[2 * t3 + 1]
      s2i = ar * tw[2 * t3 + 1] + ai * tw[2 * t3]
      s5r = a[p] - s1r
      s5i = a[p + 1] - s1i
      a[p] = a[p] + s1r
      a[p + 1] = a[p + 1] + s1i
      s3r = s0r + s2r
      s3i = s0i + s2i
      s4r = s0r - s2r
      s4i = s0i - s2i
      a[qb] = a[p] - s3r
      a[qb + 1] = a[p + 1] - s3i
      t1 += fstride
      t2 += fstride * 2
      t3 += fstride * 3
      a[p] = a[p] + s3r
      a[p + 1] = a[p + 1] + s3i
      a[qa] = s5r + s4i
      a[qa + 1] = s5i - s4r
      a[qc] = s5r - s4i
      a[qc + 1] = s5i + s4r
      p += 2
      j += 1
    i += 1
  0

-> celt_bfly3(a, fo, fstride, tw, m, n, mm) (f64[] i64 i64 f64[] i64 i64 i64) i64
  m2 = 2 * m
  epi = tw[2 * fstride * m + 1]
  i = 0 ## i64
  while i < n
    p = fo + 2 * i * mm
    t1 = 0 ## i64
    t2 = 0 ## i64
    k = m
    while k > 0
      qa = p + 2 * m
      qb = p + 2 * m2
      ar = (a[qa]) ## f64
      ai = (a[qa + 1]) ## f64
      s1r = ar * tw[2 * t1] - ai * tw[2 * t1 + 1]
      s1i = ar * tw[2 * t1 + 1] + ai * tw[2 * t1]
      ar = (a[qb]) ## f64
      ai = (a[qb + 1]) ## f64
      s2r = ar * tw[2 * t2] - ai * tw[2 * t2 + 1]
      s2i = ar * tw[2 * t2 + 1] + ai * tw[2 * t2]
      s3r = s1r + s2r
      s3i = s1i + s2i
      s0r = (s1r - s2r) ## f64
      s0i = (s1i - s2i) ## f64
      t1 += fstride
      t2 += fstride * 2
      a[qa] = a[p] - s3r * (~0.5 ## f64)
      a[qa + 1] = a[p + 1] - s3i * (~0.5 ## f64)
      s0r = (s0r * epi) ## f64
      s0i = (s0i * epi) ## f64
      a[p] = a[p] + s3r
      a[p + 1] = a[p + 1] + s3i
      a[qb] = a[qa] + s0i
      a[qb + 1] = a[qa + 1] - s0r
      a[qa] = a[qa] - s0i
      a[qa + 1] = a[qa + 1] + s0r
      p += 2
      k -= 1
    i += 1
  0

-> celt_bfly5(a, fo, fstride, tw, m, n, mm) (f64[] i64 i64 f64[] i64 i64 i64) i64
  yar = tw[2 * fstride * m]
  yai = tw[2 * fstride * m + 1]
  ybr = tw[4 * fstride * m]
  ybi = tw[4 * fstride * m + 1]
  i = 0 ## i64
  while i < n
    p0 = fo + 2 * i * mm
    p1 = p0 + 2 * m
    p2 = p0 + 4 * m
    p3 = p0 + 6 * m
    p4 = p0 + 8 * m
    u = 0 ## i64
    while u < m
      s0r = a[p0]
      s0i = a[p0 + 1]
      k1 = 2 * u * fstride
      k2 = 4 * u * fstride
      k3 = 6 * u * fstride
      k4 = 8 * u * fstride
      ar = (a[p1]) ## f64
      ai = (a[p1 + 1]) ## f64
      s1r = ar * tw[k1] - ai * tw[k1 + 1]
      s1i = ar * tw[k1 + 1] + ai * tw[k1]
      ar = (a[p2]) ## f64
      ai = (a[p2 + 1]) ## f64
      s2r = ar * tw[k2] - ai * tw[k2 + 1]
      s2i = ar * tw[k2 + 1] + ai * tw[k2]
      ar = (a[p3]) ## f64
      ai = (a[p3 + 1]) ## f64
      s3r = ar * tw[k3] - ai * tw[k3 + 1]
      s3i = ar * tw[k3 + 1] + ai * tw[k3]
      ar = (a[p4]) ## f64
      ai = (a[p4 + 1]) ## f64
      s4r = ar * tw[k4] - ai * tw[k4 + 1]
      s4i = ar * tw[k4 + 1] + ai * tw[k4]
      s7r = s1r + s4r
      s7i = s1i + s4i
      s10r = s1r - s4r
      s10i = s1i - s4i
      s8r = s2r + s3r
      s8i = s2i + s3i
      s9r = s2r - s3r
      s9i = s2i - s3i
      a[p0] = s0r + (s7r + s8r)
      a[p0 + 1] = s0i + (s7i + s8i)
      s5r = s0r + (s7r * yar + s8r * ybr)
      s5i = s0i + (s7i * yar + s8i * ybr)
      s6r = s10i * yai + s9i * ybi
      s6i = (~0.0 ## f64) - (s10r * yai + s9r * ybi)
      a[p1] = s5r - s6r
      a[p1 + 1] = s5i - s6i
      a[p4] = s5r + s6r
      a[p4 + 1] = s5i + s6i
      s11r = s0r + (s7r * ybr + s8r * yar)
      s11i = s0i + (s7i * ybr + s8i * yar)
      s12r = s9i * yai - s10i * ybi
      s12i = s10r * ybi - s9r * yai
      a[p2] = s11r + s12r
      a[p2 + 1] = s11i + s12i
      a[p3] = s11r - s12r
      a[p3 + 1] = s11i - s12i
      p0 += 2
      p1 += 2
      p2 += 2
      p3 += 2
      p4 += 2
      u += 1
    i += 1
  0

# In-place FFT of the complex data at a[fo..] (already bit-reversed).
-> celt_fft_impl(a, fo, fac, tw, shift) (f64[] i64 i64[] f64[] i64) i64
  fstride = i64[8]
  fstride[0] = 1
  l = 0 ## i64
  m = 0 ## i64
  while true
    p = fac[2 * l]
    m = fac[2 * l + 1]
    fstride[l + 1] = fstride[l] * p
    l += 1
    break if m == 1
  m = fac[2 * l - 1]
  i = l - 1
  while i >= 0
    m2 = 1 ## i64
    m2 = fac[2 * i - 1] if i != 0
    r = fac[2 * i]
    if r == 2
      celt_bfly2(a, fo, fstride[i])
    elsif r == 4
      celt_bfly4(a, fo, fstride[i] << shift, tw, m, fstride[i], m2)
    elsif r == 3
      celt_bfly3(a, fo, fstride[i] << shift, tw, m, fstride[i], m2)
    else
      celt_bfly5(a, fo, fstride[i] << shift, tw, m, fstride[i], m2)
    m = m2
    i -= 1
  0

# clt_mdct_backward: input coefficients inp[ioff + k*stride], output into
# out[ooff ..] (N/2 + overlap samples written, windowed overlap at the start).
-> celt_imdct(inp, ioff, out, ooff, win, shift, stride, trig, tw, fac, brev) (f64[] i64 f64[] i64 f64[] i64 i64 f64[] f64[] i64[] i64[]) i64
  n = 1920 >> shift
  toff = 0 ## i64
  if shift >= 1
    toff = 960
  if shift >= 2
    toff = 1440
  if shift >= 3
    toff = 1680
  n2 = n >> 1
  n4 = n >> 2
  overlap = 120
  yo = ooff + (overlap >> 1)
  x1 = ioff
  x2 = ioff + stride * (n2 - 1)
  i = 0 ## i64
  while i < n4
    rev = brev[i]
    t0 = (trig[toff + i]) ## f64
    t1 = (trig[toff + n4 + i]) ## f64
    a1 = inp[x1]
    a2 = inp[x2]
    out[yo + 2 * rev + 1] = a2 * t0 + a1 * t1
    out[yo + 2 * rev] = a1 * t0 - a2 * t1
    x1 += 2 * stride
    x2 -= 2 * stride
    i += 1
  celt_fft_impl(out, yo, fac, tw, shift)
  p0 = yo
  p1 = yo + n2 - 2
  i = 0
  while i < ((n4 + 1) >> 1)
    re = (out[p0 + 1]) ## f64
    im = (out[p0]) ## f64
    t0 = (trig[toff + i]) ## f64
    t1 = (trig[toff + n4 + i]) ## f64
    yr = (re * t0 + im * t1) ## f64
    yi = (re * t1 - im * t0) ## f64
    re = (out[p1 + 1]) ## f64
    im = (out[p1]) ## f64
    out[p0] = yr
    out[p1 + 1] = yi
    t0 = (trig[toff + n4 - i - 1]) ## f64
    t1 = (trig[toff + n2 - i - 1]) ## f64
    yr = (re * t0 + im * t1) ## f64
    yi = (re * t1 - im * t0) ## f64
    out[p1] = yr
    out[p0 + 1] = yi
    p0 += 2
    p1 -= 2
    i += 1
  xp1 = ooff + overlap - 1
  yp1 = ooff
  i = 0
  while i < (overlap >> 1)
    xa = out[xp1]
    xb = out[yp1]
    wa = win[i]
    wb = win[overlap - 1 - i]
    out[yp1] = wb * xb - wa * xa
    out[xp1] = wa * xb + wb * xa
    yp1 += 1
    xp1 -= 1
    i += 1
  0

# ---------------------------------------------------------------- helpers

-> celt_s16(x) (i64) i64
  ((x + 32768) & 65535) - 32768

-> celt_frac_mul16(a, b) (i64 i64) i64
  (16384 + celt_s16(a) * celt_s16(b)) >> 15

-> celt_bitexact_cos(x) (i64) i64
  tmp = (4096 + x * x) >> 13
  x2 = tmp
  x2 = (32767 - x2) + celt_frac_mul16(x2, (-7651 + celt_frac_mul16(x2, (8277 + celt_frac_mul16(-626, x2)))))
  1 + x2

-> celt_bitexact_log2tan(isin0, icos0) (i64 i64) i64
  lc = ec_ilog(icos0)
  ls = ec_ilog(isin0)
  icos = icos0 << (15 - lc)
  isin = isin0 << (15 - ls)
  (ls - lc) * 2048 + celt_frac_mul16(isin, celt_frac_mul16(isin, -2597) + 7932) - celt_frac_mul16(icos, celt_frac_mul16(icos, -2597) + 7932)

-> celt_isqrt32(v0) (i64) i64
  v = v0
  g = 0 ## i64
  bshift = (ec_ilog(v) - 1) >> 1
  b = 1 << bshift
  while bshift >= 0
    t = ((g << 1) + b) << bshift
    if t <= v
      g += b
      v -= t
    b = b >> 1
    bshift -= 1
  g

-> celt_lcg(seed) (i64) i64
  (1664525 * seed + 1013904223) & 4294967295

-> celt_seed_s20(seed) (i64) i64
  s = seed
  s = s - 4294967296 if s >= 2147483648
  s >> 20

-> celt_get_pulses(i) (i64) i64
  return i if i < 8
  (8 + (i & 7)) << ((i >> 3) - 1)

-> celt_bits2pulses(mi, band, lm, bits0) (i64[] i64 i64 i64) i64
  cache = 148 + mi[43 + (lm + 1) * 21 + band]
  lo = 0 ## i64
  hi = mi[cache] + 0
  bits = bits0 - 1
  k = 0 ## i64
  while k < 6
    mid = (lo + hi + 1) >> 1
    if mi[cache + mid] >= bits
      hi = mid
    else
      lo = mid
    k += 1
  lov = -1 ## i64
  lov = mi[cache + lo] if lo != 0
  if bits - lov <= mi[cache + hi] - bits
    return lo
  hi

-> celt_pulses2bits(mi, band, lm, q) (i64[] i64 i64 i64) i64
  return 0 if q == 0
  cache = 148 + mi[43 + (lm + 1) * 21 + band]
  mi[cache + q] + 1

-> celt_pvq_u(pvq, row, n, k) (i64[] i64[] i64 i64) i64
  a = n
  b = k
  if a > b
    a = k
    b = n
  pvq[row[a] + b]

-> celt_renormalise(w, xo, n, gain) (f64[] i64 i64 f64) i64
  e = (~1e-15) ## f64
  j = 0 ## i64
  while j < n
    v = w[xo + j]
    e = (e + v * v) ## f64
    j += 1
  g = gain / Math.sqrt(e)
  j = 0
  while j < n
    w[xo + j] = (w[xo + j] * g) ## f64
    j += 1
  0

# cwrsi: decodes codeword index i into y[0..n), returns sum of squares
-> celt_cwrsi(n0, k0in, i0, y, pvq, row) (i64 i64 i64 i64[] i64[] i64[]) i64
  n = n0
  k = k0in
  idx = i0
  yy = 0 ## i64
  yi = 0 ## i64
  while n > 2
    if k >= n
      p = pvq[row[n] + k + 1]
      s = 0 ## i64
      if idx >= p
        s = -1
        idx -= p
      k0 = k
      q = pvq[row[n] + n]
      if q > idx
        k = n
        while true
          k -= 1
          p = pvq[row[k] + n]
          break if p <= idx
      else
        p = pvq[row[n] + k]
        while p > idx
          k -= 1
          p = pvq[row[n] + k]
      idx -= p
      val = (k0 - k + s) ^ s
      y[yi] = val
      yi += 1
      yy += val * val
    else
      p = pvq[row[k] + n]
      q = pvq[row[k + 1] + n]
      if p <= idx && idx < q
        idx -= p
        y[yi] = 0
        yi += 1
      else
        s = 0 ## i64
        if idx >= q
          s = -1
          idx -= q
        k0 = k
        while true
          k -= 1
          p = pvq[row[k] + n]
          break if p <= idx
        idx -= p
        val = (k0 - k + s) ^ s
        y[yi] = val
        yi += 1
        yy += val * val
    n -= 1
  p = 2 * k + 1
  s = 0 ## i64
  if idx >= p
    s = -1
    idx -= p
  k0 = k
  k = (idx + 1) >> 1
  idx -= 2 * k - 1 if k != 0
  val = (k0 - k + s) ^ s
  y[yi] = val
  yy += val * val
  s = 0 - idx
  val = (k + s) ^ s
  y[yi + 1] = val
  yy += val * val
  yy

-> celt_exp_rotation1(w, xo, len, stride, c, s) (f64[] i64 i64 i64 f64 f64) i64
  ms = (~0.0 ## f64) - s
  p = xo
  i = 0 ## i64
  while i < len - stride
    x1 = (w[p]) ## f64
    x2 = (w[p + stride]) ## f64
    w[p + stride] = (c * x2 + s * x1) ## f64
    w[p] = (c * x1 + ms * x2) ## f64
    p += 1
    i += 1
  p = xo + len - 2 * stride - 1
  i = len - 2 * stride - 1
  while i >= 0
    x1 = (w[p]) ## f64
    x2 = (w[p + stride]) ## f64
    w[p + stride] = (c * x2 + s * x1) ## f64
    w[p] = (c * x1 + ms * x2) ## f64
    p -= 1
    i -= 1
  0

-> celt_exp_rotation(w, xo, len0, dir, stride, k, spread, sm) (f64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  return 0 if 2 * k >= len0 || spread == 0
  factor = sm[70 + spread - 1]
  gain = ((len0 ## f64) / ((len0 + factor * k) ## f64)) ## f64
  theta = (~0.5 * gain * gain) ## f64
  hp = (~0.5 ## f64) * (~3.141592653 ## f64)
  c = Math.cos((hp * theta) ## f64) ## f64
  s = Math.cos((hp * ((~1.0 ## f64) - theta)) ## f64) ## f64
  stride2 = 0 ## i64
  if len0 >= 8 * stride
    stride2 = 1
    while (stride2 * stride2 + stride2) * stride + (stride >> 2) < len0
      stride2 += 1
  len = len0 / stride
  i = 0 ## i64
  while i < stride
    o = xo + i * len
    if dir < 0
      celt_exp_rotation1(w, o, len, stride2, s, c) if stride2 != 0
      celt_exp_rotation1(w, o, len, 1, c, s)
    else
      celt_exp_rotation1(w, o, len, 1, c, (~0.0 ## f64) - s)
      celt_exp_rotation1(w, o, len, stride2, s, (~0.0 ## f64) - c) if stride2 != 0
    i += 1
  0

-> celt_alg_unquant(w, xo, n, k, spread, nbb, st, buf, gain, pvq, row, iy, sm) (f64[] i64 i64 i64 i64 i64 i64[] u8[] f64 i64[] i64[] i64[] i64[]) i64
  ft = celt_pvq_u(pvq, row, n, k) + celt_pvq_u(pvq, row, n, k + 1)
  idx = ec_dec_uint(st, buf, ft)
  ryy = celt_cwrsi(n, k, idx, iy, pvq, row)
  g = gain / Math.sqrt(ryy ## f64)
  j = 0 ## i64
  while j < n
    w[xo + j] = (g * (iy[j] ## f64)) ## f64
    j += 1
  celt_exp_rotation(w, xo, n, -1, nbb, k, spread, sm)
  return 1 if nbb <= 1
  n0 = n / nbb
  cm = 0 ## i64
  i = 0 ## i64
  while i < nbb
    t = 0 ## i64
    j = 0
    while j < n0
      t = t | iy[i * n0 + j]
      j += 1
    cm = cm | (1 << i) if t != 0
    i += 1
  cm

-> celt_haar1(w, xo, n0, stride) (f64[] i64 i64 i64) i64
  n = n0 >> 1
  c = ~0.70710678 ## f64
  i = 0 ## i64
  while i < stride
    j = 0 ## i64
    while j < n
      pa = xo + stride * 2 * j + i
      pb = xo + stride * (2 * j + 1) + i
      t1 = c * w[pa]
      t2 = c * w[pb]
      w[pa] = t1 + t2
      w[pb] = t1 - t2
      j += 1
    i += 1
  0

-> celt_deinterleave(w, xo, n0, stride, hadamard, tmp, sm) (f64[] i64 i64 i64 i64 f64[] i64[]) i64
  n = n0 * stride
  if hadamard != 0
    oo = stride - 2
    i = 0 ## i64
    while i < stride
      j = 0 ## i64
      while j < n0
        tmp[sm[oo + i] * n0 + j] = w[xo + j * stride + i]
        j += 1
      i += 1
  else
    i = 0 ## i64
    while i < stride
      j = 0 ## i64
      while j < n0
        tmp[i * n0 + j] = w[xo + j * stride + i]
        j += 1
      i += 1
  i = 0
  while i < n
    w[xo + i] = tmp[i]
    i += 1
  0

-> celt_interleave(w, xo, n0, stride, hadamard, tmp, sm) (f64[] i64 i64 i64 i64 f64[] i64[]) i64
  n = n0 * stride
  if hadamard != 0
    oo = stride - 2
    i = 0 ## i64
    while i < stride
      j = 0 ## i64
      while j < n0
        tmp[j * stride + i] = w[xo + sm[oo + i] * n0 + j]
        j += 1
      i += 1
  else
    i = 0 ## i64
    while i < stride
      j = 0 ## i64
      while j < n0
        tmp[j * stride + i] = w[xo + i * n0 + j]
        j += 1
      i += 1
  i = 0
  while i < n
    w[xo + i] = tmp[i]
    i += 1
  0

-> celt_compute_qn(n, b, offset, pulse_cap, stereo, sm) (i64 i64 i64 i64 i64 i64[]) i64
  n2 = 2 * n - 1
  n2 -= 1 if stereo != 0 && n == 2
  qb = (b + n2 * offset) / n2
  qb = b - pulse_cap - 32 if b - pulse_cap - 32 < qb
  qb = 64 if 64 < qb
  return 1 if qb < 4
  qn = sm[62 + (qb & 7)] >> (14 - (qb >> 3))
  ((qn + 1) >> 1) << 1

# bc: 0 band i, 1 intensity, 2 spread, 3 tf_change, 4 remaining_bits,
#     5 seed, 6 disable_inv
# sc (out): 0 inv 1 imid 2 iside 3 delta 4 itheta 5 qalloc 6 b 7 fill
-> celt_compute_theta(mi, st, buf, bc, sc, sm, n, b0, nbb, nbb0, lm, stereo, fill0) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  b = b0
  fill = fill0
  i = bc[0]
  pulse_cap = mi[22 + i] + lm * 8
  qo = 4 ## i64
  qo = 16 if stereo != 0 && n == 2
  offset = (pulse_cap >> 1) - qo
  qn = celt_compute_qn(n, b, offset, pulse_cap, stereo, sm)
  qn = 1 if stereo != 0 && i >= bc[1]
  tell = ec_tell_frac(st)
  itheta = 0 ## i64
  inv = 0 ## i64
  if qn != 1
    if stereo != 0 && n > 2
      p0 = 3 ## i64
      x0 = qn / 2
      ft = p0 * (x0 + 1) + x0
      fs = ec_decode(st, ft)
      x = 0 ## i64
      if fs < (x0 + 1) * p0
        x = fs / p0
      else
        x = x0 + 1 + (fs - (x0 + 1) * p0)
      fl = 0 ## i64
      fh = 0 ## i64
      if x <= x0
        fl = p0 * x
        fh = p0 * (x + 1)
      else
        fl = (x - 1 - x0) + (x0 + 1) * p0
        fh = (x - x0) + (x0 + 1) * p0
      ec_dec_update(st, buf, fl, fh, ft)
      itheta = x
    elsif nbb0 > 1 || stereo != 0
      itheta = ec_dec_uint(st, buf, qn + 1)
    else
      h = qn >> 1
      ft = (h + 1) * (h + 1)
      fm = ec_decode(st, ft)
      fs = 0 ## i64
      fl = 0 ## i64
      if fm < ((h * (h + 1)) >> 1)
        itheta = (celt_isqrt32(8 * fm + 1) - 1) >> 1
        fs = itheta + 1
        fl = (itheta * (itheta + 1)) >> 1
      else
        itheta = (2 * (qn + 1) - celt_isqrt32(8 * (ft - fm - 1) + 1)) >> 1
        fs = qn + 1 - itheta
        fl = ft - (((qn + 1 - itheta) * (qn + 2 - itheta)) >> 1)
      ec_dec_update(st, buf, fl, fl + fs, ft)
    itheta = (itheta * 16384) / qn
  elsif stereo != 0
    if b > 16 && bc[4] > 16
      inv = ec_dec_bit_logp(st, buf, 2)
    inv = 0 if bc[6] != 0
    itheta = 0
  qalloc = ec_tell_frac(st) - tell
  b -= qalloc
  imid = 0 ## i64
  iside = 0 ## i64
  delta = 0 ## i64
  if itheta == 0
    imid = 32767
    iside = 0
    fill = fill & ((1 << nbb) - 1)
    delta = -16384
  elsif itheta == 16384
    imid = 0
    iside = 32767
    fill = fill & (((1 << nbb) - 1) << nbb)
    delta = 16384
  else
    imid = celt_bitexact_cos(itheta)
    iside = celt_bitexact_cos(16384 - itheta)
    delta = celt_frac_mul16((n - 1) << 7, celt_bitexact_log2tan(iside, imid))
  sc[0] = inv
  sc[1] = imid
  sc[2] = iside
  sc[3] = delta
  sc[4] = itheta
  sc[5] = qalloc
  sc[6] = b
  sc[7] = fill
  0

-> celt_quant_band_n1(st, buf, bc, w, xo, yo, lboo) (i64[] u8[] i64[] f64[] i64 i64 i64) i64
  c = 0 ## i64
  x = xo
  nc = 1 ## i64
  nc = 2 if yo >= 0
  while c < nc
    sign = 0 ## i64
    if bc[4] >= 8
      sign = ec_dec_bits(st, buf, 1)
      bc[4] = bc[4] - 8
    if sign != 0
      w[x] = ~-1.0 ## f64
    else
      w[x] = ~1.0 ## f64
    x = yo
    c += 1
  w[lboo] = w[xo] if lboo >= 0
  1

-> celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n0, b0, nb0in, lbo, lm0, gain, fill0, iy) (i64[] i64[] i64[] i64[] i64[] u8[] i64[] i64[] f64[] i64 i64 i64 i64 i64 i64 f64 i64 i64[]) i64
  n = n0
  b = b0
  nbb = nb0in
  nbb0 = nb0in
  lm = lm0
  fill = fill0
  i = bc[0]
  cm = 0 ## i64
  cache = 148 + mi[43 + (lm + 1) * 21 + i]
  if lm != -1 && b > mi[cache + mi[cache]] + 12 && n > 2
    n = n >> 1
    yo = xo + n
    lm -= 1
    fill = (fill & 1) | (fill << 1) if nbb == 1
    nbb = (nbb + 1) >> 1
    celt_compute_theta(mi, st, buf, bc, sc, sm, n, b, nbb, nbb0, lm, 0, fill)
    imid = sc[1]
    iside = sc[2]
    delta = sc[3]
    itheta = sc[4]
    qalloc = sc[5]
    b = sc[6]
    fill = sc[7]
    mid = (imid ## f64) / ~32768.0
    side = (iside ## f64) / ~32768.0
    if nbb0 > 1 && (itheta & 16383) != 0
      if itheta > 8192
        delta -= delta >> (4 - lm)
      else
        delta = delta + ((n << 3) >> (5 - lm))
        delta = 0 if delta > 0
    mbits = (b - delta) / 2
    mbits = b if b < mbits
    mbits = 0 if mbits < 0
    sbits = b - mbits
    bc[4] = bc[4] - qalloc
    nlb2 = -1 ## i64
    nlb2 = lbo + n if lbo >= 0
    rebalance = bc[4]
    if mbits >= sbits
      cm = celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, mbits, nbb, lbo, lm, gain * mid, fill, iy)
      rebalance = mbits - (rebalance - bc[4])
      sbits += rebalance - 24 if rebalance > 24 && itheta != 0
      cm = cm | (celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, yo, n, sbits, nbb, nlb2, lm, gain * side, fill >> nbb, iy) << (nbb0 >> 1))
    else
      cm = celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, yo, n, sbits, nbb, nlb2, lm, gain * side, fill >> nbb, iy) << (nbb0 >> 1)
      rebalance = sbits - (rebalance - bc[4])
      mbits += rebalance - 24 if rebalance > 24 && itheta != 16384
      cm = cm | celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, mbits, nbb, lbo, lm, gain * mid, fill, iy)
    return cm
  q = celt_bits2pulses(mi, i, lm, b)
  curr = celt_pulses2bits(mi, i, lm, q)
  bc[4] = bc[4] - curr
  while bc[4] < 0 && q > 0
    bc[4] = bc[4] + curr
    q -= 1
    curr = celt_pulses2bits(mi, i, lm, q)
    bc[4] = bc[4] - curr
  if q != 0
    k = celt_get_pulses(q)
    return celt_alg_unquant(w, xo, n, k, bc[2], nbb, st, buf, gain, pvq, row, iy, sm)
  cm_mask = (1 << nbb) - 1
  fill = fill & cm_mask
  if fill == 0
    j = 0 ## i64
    while j < n
      w[xo + j] = ~0.0 ## f64
      j += 1
    return 0
  seed = bc[5]
  if lbo < 0
    j = 0 ## i64
    while j < n
      seed = celt_lcg(seed)
      w[xo + j] = celt_seed_s20(seed) ## f64
      j += 1
    cm = cm_mask
  else
    j = 0 ## i64
    while j < n
      seed = celt_lcg(seed)
      if (seed & 32768) != 0
        w[xo + j] = w[lbo + j] + (~0.00390625 ## f64)
      else
        w[xo + j] = w[lbo + j] - (~0.00390625 ## f64)
      j += 1
    cm = fill
  bc[5] = seed
  celt_renormalise(w, xo, n, gain)
  cm

-> celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, b, nbin, lbo0, lm, lboo, gain, scro, fill0, iy, tmp) (i64[] i64[] i64[] i64[] i64[] u8[] i64[] i64[] f64[] i64 i64 i64 i64 i64 i64 i64 f64 i64 i64 i64[] f64[]) i64
  n0 = n
  nbb = nbin
  nbb0 = nbin
  lbo = lbo0
  fill = fill0
  time_divide = 0 ## i64
  recombine = 0 ## i64
  long_blocks = 0 ## i64
  long_blocks = 1 if nbb0 == 1
  n_b = n / nbb
  if n == 1
    return celt_quant_band_n1(st, buf, bc, w, xo, -1, lboo)
  tf_change = bc[3]
  recombine = tf_change if tf_change > 0
  if scro >= 0 && lbo >= 0 && (recombine != 0 || ((n_b & 1) == 0 && tf_change < 0) || nbb0 > 1)
    j = 0 ## i64
    while j < n
      w[scro + j] = w[lbo + j]
      j += 1
    lbo = scro
  k = 0 ## i64
  while k < recombine
    celt_haar1(w, lbo, n >> k, 1 << k) if lbo >= 0
    fill = sm[30 + (fill & 15)] | (sm[30 + (fill >> 4)] << 2)
    k += 1
  nbb = nbb >> recombine
  n_b = n_b << recombine
  while (n_b & 1) == 0 && tf_change < 0
    celt_haar1(w, lbo, n_b, nbb) if lbo >= 0
    fill = fill | (fill << nbb)
    nbb = nbb << 1
    n_b = n_b >> 1
    time_divide += 1
    tf_change += 1
  nbb0 = nbb
  n_b0 = n_b
  if nbb0 > 1 && lbo >= 0
    celt_deinterleave(w, lbo, n_b >> recombine, nbb0 << recombine, long_blocks, tmp, sm)
  cm = celt_quant_partition(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, b, nbb, lbo, lm, gain, fill, iy)
  if nbb0 > 1
    celt_interleave(w, xo, n_b >> recombine, nbb0 << recombine, long_blocks, tmp, sm)
  n_b = n_b0
  nbb = nbb0
  k = 0
  while k < time_divide
    nbb = nbb >> 1
    n_b = n_b << 1
    cm = cm | (cm >> nbb)
    celt_haar1(w, xo, n_b, nbb)
    k += 1
  k = 0
  while k < recombine
    cm = sm[46 + cm]
    celt_haar1(w, xo, n0 >> k, 1 << k)
    k += 1
  nbb = nbb << recombine
  if lboo >= 0
    nn = Math.sqrt(n0 ## f64) ## f64
    j = 0 ## i64
    while j < n0
      w[lboo + j] = nn * w[xo + j]
      j += 1
  cm & ((1 << nbb) - 1)

-> celt_stereo_merge(w, xo, yo, mid, n) (f64[] i64 i64 f64 i64) i64
  xp = (~0.0) ## f64
  side = (~0.0) ## f64
  j = 0 ## i64
  while j < n
    yv = w[yo + j] ## f64
    xp = (xp + yv * w[xo + j]) ## f64
    side = (side + yv * yv) ## f64
    j += 1
  xp = (mid * xp) ## f64
  el = mid * mid + side - ~2.0 * xp
  er = mid * mid + side + ~2.0 * xp
  if er < ~6e-4 || el < ~6e-4
    j = 0
    while j < n
      w[yo + j] = w[xo + j]
      j += 1
    return 0
  lg = ~1.0 / Math.sqrt(el)
  rg = ~1.0 / Math.sqrt(er)
  j = 0
  while j < n
    l = mid * w[xo + j]
    r = w[yo + j] ## f64
    w[xo + j] = (lg * (l - r)) ## f64
    w[yo + j] = (rg * (l + r)) ## f64
    j += 1
  0

-> celt_quant_band_stereo(mi, pvq, row, sm, st, buf, bc, sc, w, xo, yo, n, b0, nbb, lbo, lm, lboo, scro, fill0, iy, tmp) (i64[] i64[] i64[] i64[] i64[] u8[] i64[] i64[] f64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] f64[]) i64
  if n == 1
    return celt_quant_band_n1(st, buf, bc, w, xo, yo, lboo)
  orig_fill = fill0
  celt_compute_theta(mi, st, buf, bc, sc, sm, n, b0, nbb, nbb, lm, 1, fill0)
  inv = sc[0]
  imid = sc[1]
  iside = sc[2]
  delta = sc[3]
  itheta = sc[4]
  qalloc = sc[5]
  b = sc[6]
  fill = sc[7]
  mid = (imid ## f64) / ~32768.0
  side = (iside ## f64) / ~32768.0
  cm = 0 ## i64
  if n == 2
    mbits = b
    sbits = 0 ## i64
    sbits = 8 if itheta != 0 && itheta != 16384
    mbits -= sbits
    c = 0 ## i64
    c = 1 if itheta > 8192
    bc[4] = bc[4] - (qalloc + sbits)
    x2 = xo
    y2 = yo
    if c != 0
      x2 = yo
      y2 = xo
    sign = 0 ## i64
    sign = ec_dec_bits(st, buf, 1) if sbits != 0
    sign = 1 - 2 * sign
    cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, x2, n, mbits, nbb, lbo, lm, lboo, ~1.0, scro, orig_fill, iy, tmp)
    w[y2] = ((0 - sign) ## f64) * w[x2 + 1]
    w[y2 + 1] = (sign ## f64) * w[x2]
    w[xo] = (mid * w[xo]) ## f64
    w[xo + 1] = (mid * w[xo + 1]) ## f64
    w[yo] = (side * w[yo]) ## f64
    w[yo + 1] = (side * w[yo + 1]) ## f64
    t = (w[xo]) ## f64
    w[xo] = t - w[yo]
    w[yo] = t + w[yo]
    t = (w[xo + 1]) ## f64
    w[xo + 1] = t - w[yo + 1]
    w[yo + 1] = t + w[yo + 1]
  else
    mbits = (b - delta) / 2
    mbits = b if b < mbits
    mbits = 0 if mbits < 0
    sbits = b - mbits
    bc[4] = bc[4] - qalloc
    rebalance = bc[4]
    if mbits >= sbits
      cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, mbits, nbb, lbo, lm, lboo, ~1.0, scro, fill, iy, tmp)
      rebalance = mbits - (rebalance - bc[4])
      sbits += rebalance - 24 if rebalance > 24 && itheta != 0
      cm = cm | celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, yo, n, sbits, nbb, -1, lm, -1, side, -1, fill >> nbb, iy, tmp)
    else
      cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, yo, n, sbits, nbb, -1, lm, -1, side, -1, fill >> nbb, iy, tmp)
      rebalance = sbits - (rebalance - bc[4])
      mbits += rebalance - 24 if rebalance > 24 && itheta != 16384
      cm = cm | celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, mbits, nbb, lbo, lm, lboo, ~1.0, scro, fill, iy, tmp)
  celt_stereo_merge(w, xo, yo, mid, n) if n != 2
  if inv != 0
    j = 0 ## i64
    while j < n
      w[yo + j] = (~0.0 ## f64) - w[yo + j]
      j += 1
  cm

CW_NORM = 2048

# quant_all_bands (decoder). w: X at 0, Y at nn (if stereo), norm at 2048.
# p: i64[] params 0 start 1 end 2 shortBlocks 3 spread 4 dual_stereo
#    5 intensity 6 total_bits 7 balance 8 LM 9 codedBands 10 seed(in/out)
#    11 disable_inv 12 C 13 nn
-> celt_quant_all_bands(mi, pvq, row, sm, st, buf, w, cmask, pulses, tf_res, p, iy, tmp) (i64[] i64[] i64[] i64[] i64[] u8[] f64[] i64[] i64[] i64[] i64[] i64[] f64[]) i64
  start = p[0]
  iend = p[1]
  lm = p[8]
  mm = 1 << lm
  nbb = 1 ## i64
  nbb = mm if p[2] != 0
  spread = p[3]
  dual_stereo = p[4]
  intensity = p[5]
  total_bits = p[6]
  balance = p[7]
  coded = p[9]
  cc = p[12]
  nn = p[13]
  norm_offset = mm * mi[start]
  normo = 2048
  norm2o = normo + mm * mi[20] - norm_offset
  lb_scratch = mm * mi[20]
  lowband_offset = 0 ## i64
  update_lowband = 1 ## i64
  bc = i64[8]
  sc = i64[8]
  bc[1] = intensity
  bc[2] = spread
  bc[5] = p[10]
  bc[6] = p[11]
  i = start
  while i < iend
    bc[0] = i
    last = 0 ## i64
    last = 1 if i == iend - 1
    xo = mm * mi[i]
    yo = -1 ## i64
    yo = nn + mm * mi[i] if cc == 2
    n = mm * mi[i + 1] - mm * mi[i]
    tell = ec_tell_frac(st)
    balance -= tell if i != start
    remaining = total_bits - tell - 1
    bc[4] = remaining
    b = 0 ## i64
    if i <= coded - 1
      d = coded - i
      d = 3 if d > 3
      curr_balance = balance / d
      b = pulses[i] + curr_balance
      b = remaining + 1 if remaining + 1 < b
      b = 16383 if b > 16383
      b = 0 if b < 0
    if (mm * mi[i] - n >= mm * mi[start] || i == start + 1) && (update_lowband != 0 || lowband_offset == 0)
      lowband_offset = i
    if i == start + 1
      n1 = mm * (mi[start + 1] - mi[start])
      n2 = mm * (mi[start + 2] - mi[start + 1])
      j = 0 ## i64
      while j < n2 - n1
        w[normo + n1 + j] = w[normo + 2 * n1 - n2 + j]
        w[norm2o + n1 + j] = w[norm2o + 2 * n1 - n2 + j] if dual_stereo != 0
        j += 1
    tf_change = tf_res[i]
    bc[3] = tf_change
    scr = lb_scratch
    scr = -1 if last != 0
    eff = -1 ## i64
    x_cm = 0 ## i64
    y_cm = 0 ## i64
    if lowband_offset != 0 && (spread != 3 || nbb > 1 || tf_change < 0)
      eff = mm * mi[lowband_offset] - norm_offset - n
      eff = 0 if eff < 0
      fold_start = lowband_offset
      while true
        fold_start -= 1
        break if mm * mi[fold_start] <= eff + norm_offset
      fold_end = lowband_offset - 1
      while true
        fold_end += 1
        break if !(fold_end < i && mm * mi[fold_end] < eff + norm_offset + n)
      fi = fold_start
      while true
        x_cm = x_cm | cmask[fi * cc]
        y_cm = y_cm | cmask[fi * cc + cc - 1]
        fi += 1
        break if fi >= fold_end
    else
      x_cm = (1 << nbb) - 1
      y_cm = x_cm
    if dual_stereo != 0 && i == intensity
      dual_stereo = 0
      j = 0 ## i64
      while j < mm * mi[i] - norm_offset
        w[normo + j] = (~0.5 ## f64) * (w[normo + j] + w[norm2o + j])
        j += 1
    lbx = -1 ## i64
    lby = -1 ## i64
    if eff != -1
      lbx = normo + eff
      lby = norm2o + eff
    outx = -1 ## i64
    outy = -1 ## i64
    if last == 0
      outx = normo + mm * mi[i] - norm_offset
      outy = norm2o + mm * mi[i] - norm_offset
    if dual_stereo != 0
      x_cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, b / 2, nbb, lbx, lm, outx, ~1.0, scr, x_cm, iy, tmp)
      y_cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, yo, n, b / 2, nbb, lby, lm, outy, ~1.0, scr, y_cm, iy, tmp)
    else
      if yo >= 0
        x_cm = celt_quant_band_stereo(mi, pvq, row, sm, st, buf, bc, sc, w, xo, yo, n, b, nbb, lbx, lm, outx, scr, x_cm | y_cm, iy, tmp)
      else
        x_cm = celt_quant_band(mi, pvq, row, sm, st, buf, bc, sc, w, xo, n, b, nbb, lbx, lm, outx, ~1.0, scr, x_cm | y_cm, iy, tmp)
      y_cm = x_cm
    cmask[i * cc] = x_cm & 255
    cmask[i * cc + cc - 1] = y_cm & 255
    balance += pulses[i] + tell
    update_lowband = 0
    update_lowband = 1 if b > (n << 3)
    i += 1
  p[10] = bc[5]
  0

# ---------------------------------------------------------------- allocation

-> celt_interp_bits2pulses(mi, sm, st, buf, start, iend, skip_start, bits1, bits2, thresh, cap, total0, skip_rsv, intensity_rsv0, dual_stereo_rsv0, bits, ebits, fine_priority, cc, lm, out) (i64[] i64[] i64[] u8[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64 i64[]) i64
  total = total0
  intensity_rsv = intensity_rsv0
  dual_stereo_rsv = dual_stereo_rsv0
  alloc_floor = cc << 3
  stereo = 0 ## i64
  stereo = 1 if cc > 1
  log_m = lm << 3
  lo = 0 ## i64
  hi = 64 ## i64
  k = 0 ## i64
  while k < 6
    mid = (lo + hi) >> 1
    psum = 0 ## i64
    done = 0 ## i64
    j = iend - 1
    while j >= start
      tmp = bits1[j] + ((mid * bits2[j]) >> 6)
      if tmp >= thresh[j] || done != 0
        done = 1
        if tmp < cap[j]
          psum += tmp
        else
          psum += cap[j]
      else
        psum += alloc_floor if tmp >= alloc_floor
      j -= 1
    if psum > total
      hi = mid
    else
      lo = mid
    k += 1
  psum = 0 ## i64
  done = 0 ## i64
  j = iend - 1
  while j >= start
    tmp = bits1[j] + ((lo * bits2[j]) >> 6)
    if tmp < thresh[j] && done == 0
      if tmp >= alloc_floor
        tmp = alloc_floor
      else
        tmp = 0
    else
      done = 1
    tmp = cap[j] if cap[j] < tmp
    bits[j] = tmp
    psum += tmp
    j -= 1
  coded = iend
  while true
    j = coded - 1
    if j <= skip_start
      total += skip_rsv
      break
    left = total - psum
    percoeff = left / (mi[coded] - mi[start])
    left -= (mi[coded] - mi[start]) * percoeff
    rem = left - (mi[j] - mi[start])
    rem = 0 if rem < 0
    band_width = mi[coded] - mi[j]
    band_bits = bits[j] + percoeff * band_width + rem
    th = thresh[j] + 0
    th = alloc_floor + 8 if alloc_floor + 8 > th
    if band_bits >= th
      if ec_dec_bit_logp(st, buf, 1) != 0
        break
      psum += 8
      band_bits -= 8
    psum -= bits[j] + intensity_rsv
    if intensity_rsv > 0
      intensity_rsv = sm[73 + j - start]
    psum += intensity_rsv
    if band_bits >= alloc_floor
      psum += alloc_floor
      bits[j] = alloc_floor
    else
      bits[j] = 0
    coded -= 1
  intensity = 0 ## i64
  dual_stereo = 0 ## i64
  if intensity_rsv > 0
    intensity = start + ec_dec_uint(st, buf, coded + 1 - start)
  if intensity <= start
    total += dual_stereo_rsv
    dual_stereo_rsv = 0
  if dual_stereo_rsv > 0
    dual_stereo = ec_dec_bit_logp(st, buf, 1)
  left = total - psum
  percoeff = left / (mi[coded] - mi[start])
  left -= (mi[coded] - mi[start]) * percoeff
  j = start
  while j < coded
    bits[j] = bits[j] + percoeff * (mi[j + 1] - mi[j])
    j += 1
  j = start
  while j < coded
    tmp = mi[j + 1] - mi[j]
    tmp = left if left < tmp
    bits[j] = bits[j] + tmp
    left -= tmp
    j += 1
  balance = 0 ## i64
  j = start
  while j < coded
    n0 = mi[j + 1] - mi[j]
    n = n0 << lm
    bit = bits[j] + balance
    excess = 0 ## i64
    if n > 1
      excess = bit - cap[j]
      excess = 0 if excess < 0
      bits[j] = bit - excess
      den = cc * n
      den += 1 if cc == 2 && n > 2 && dual_stereo == 0 && j < intensity
      nclogn = den * (mi[22 + j] + log_m)
      offset = (nclogn >> 1) - den * 21
      offset += (den << 3) >> 2 if n == 2
      if bits[j] + offset < (den * 2) << 3
        offset += nclogn >> 2
      elsif bits[j] + offset < (den * 3) << 3
        offset += nclogn >> 3
      eb = bits[j] + offset + (den << 2)
      eb = 0 if eb < 0
      eb = (eb / den) >> 3
      eb = (bits[j] >> stereo) >> 3 if cc * eb > (bits[j] >> 3)
      eb = 8 if eb > 8
      ebits[j] = eb
      fp = 0 ## i64
      fp = 1 if eb * (den << 3) >= bits[j] + offset
      fine_priority[j] = fp
      bits[j] = bits[j] - ((cc * eb) << 3)
    else
      excess = bit - (cc << 3)
      excess = 0 if excess < 0
      bits[j] = bit - excess
      ebits[j] = 0
      fine_priority[j] = 1
    if excess > 0
      extra_fine = excess >> (stereo + 3)
      extra_fine = 8 - ebits[j] if 8 - ebits[j] < extra_fine
      ebits[j] = ebits[j] + extra_fine
      extra_bits = (extra_fine * cc) << 3
      fp = 0 ## i64
      fp = 1 if extra_bits >= excess - balance
      fine_priority[j] = fp
      excess -= extra_bits
    balance = excess
    j += 1
  while j < iend
    ebits[j] = (bits[j] >> stereo) >> 3
    bits[j] = 0
    fp = 0 ## i64
    fp = 1 if ebits[j] < 1
    fine_priority[j] = fp
    j += 1
  out[0] = coded
  out[1] = balance
  out[2] = intensity
  out[3] = dual_stereo
  coded

-> celt_compute_allocation(mi, sm, st, buf, start, iend, offsets, cap, alloc_trim, total0, pulses, ebits, fine_priority, cc, lm, out) (i64[] i64[] i64[] u8[] i64 i64 i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64[]) i64
  total = total0
  total = 0 if total < 0
  skip_start = start
  skip_rsv = 0 ## i64
  skip_rsv = 8 if total >= 8
  total -= skip_rsv
  intensity_rsv = 0 ## i64
  dual_stereo_rsv = 0 ## i64
  if cc == 2
    intensity_rsv = sm[73 + iend - start]
    if intensity_rsv > total
      intensity_rsv = 0
    else
      total -= intensity_rsv
      dual_stereo_rsv = 8 if total >= 8
      total -= dual_stereo_rsv
  bits1 = i64[21]
  bits2 = i64[21]
  thresh = i64[21]
  trim_offset = i64[21]
  j = start
  while j < iend
    w = mi[j + 1] - mi[j]
    th = ((3 * w) << (lm + 3)) >> 4
    th = cc << 3 if (cc << 3) > th
    thresh[j] = th
    trim_offset[j] = (cc * w * (alloc_trim - 5 - lm) * (iend - j - 1) * (1 << (lm + 3))) >> 6
    trim_offset[j] = trim_offset[j] - (cc << 3) if (w << lm) == 1
    j += 1
  lo = 1 ## i64
  hi = 10 ## i64
  while true
    done = 0 ## i64
    psum = 0 ## i64
    mid = (lo + hi) >> 1
    j = iend - 1
    while j >= start
      w = mi[j + 1] - mi[j]
      bitsj = ((cc * w * mi[708 + mid * 21 + j]) << lm) >> 2
      if bitsj > 0
        bitsj = bitsj + trim_offset[j]
        bitsj = 0 if bitsj < 0
      bitsj += offsets[j]
      if bitsj >= thresh[j] || done != 0
        done = 1
        if bitsj < cap[j]
          psum += bitsj
        else
          psum += cap[j]
      else
        psum += cc << 3 if bitsj >= (cc << 3)
      j -= 1
    if psum > total
      hi = mid - 1
    else
      lo = mid + 1
    break if lo > hi
  hi = lo
  lo = lo - 1
  j = start
  while j < iend
    w = mi[j + 1] - mi[j]
    bits1j = ((cc * w * mi[708 + lo * 21 + j]) << lm) >> 2
    bits2j = 0 ## i64
    if hi >= 11
      bits2j = cap[j]
    else
      bits2j = ((cc * w * mi[708 + hi * 21 + j]) << lm) >> 2
    if bits1j > 0
      bits1j = bits1j + trim_offset[j]
      bits1j = 0 if bits1j < 0
    if bits2j > 0
      bits2j = bits2j + trim_offset[j]
      bits2j = 0 if bits2j < 0
    bits1j += offsets[j] if lo > 0
    bits2j += offsets[j]
    skip_start = j if offsets[j] > 0
    bits2j = bits2j - bits1j
    bits2j = 0 if bits2j < 0
    bits1[j] = bits1j
    bits2[j] = bits2j
    j += 1
  celt_interp_bits2pulses(mi, sm, st, buf, start, iend, skip_start, bits1, bits2, thresh, cap, total, skip_rsv, intensity_rsv, dual_stereo_rsv, pulses, ebits, fine_priority, cc, lm, out)

# ---------------------------------------------------------------- energy

-> celt_unquant_coarse(st, buf, eprob, sicdf, old, start, iend, intra, cc, lm, pred, betac) (i64[] u8[] u8[] u8[] f64[] i64 i64 i64 i64 i64 f64[] f64[]) i64
  off = (lm * 2 + intra) * 42
  prev = f64[2]
  coef = ~0.0 ## f64
  beta = (~4915.0 / ~32768.0) ## f64
  if intra == 0
    coef = (pred[lm]) ## f64
    beta = (betac[lm]) ## f64
  budget = st[9] * 8
  i = start
  while i < iend
    c = 0 ## i64
    while c < cc
      tell = ec_tell(st)
      qi = 0 ## i64
      if budget - tell >= 15
        pi = 2 * i
        pi = 40 if i > 20
        qi = ec_laplace_decode(st, buf, eprob[off + pi] << 7, eprob[off + pi + 1] << 6)
      elsif budget - tell >= 2
        qi = ec_dec_icdf(st, buf, sicdf, 0, 2)
        qi = (qi >> 1) ^ (0 - (qi & 1))
      elsif budget - tell >= 1
        qi = 0 - ec_dec_bit_logp(st, buf, 1)
      else
        qi = -1
      q = qi ## f64
      k = i + c * 21
      o = (old[k]) ## f64
      if o < (~-9.0 ## f64)
        o = ~-9.0 ## f64
      tmp = coef * o + prev[c] + q
      old[k] = tmp
      prev[c] = prev[c] + q - beta * q
      c += 1
    i += 1
  0

-> celt_unquant_fine(st, buf, old, start, iend, fine_quant, cc) (i64[] u8[] f64[] i64 i64 i64[] i64) i64
  i = start
  while i < iend
    fq = fine_quant[i]
    if fq > 0
      c = 0 ## i64
      while c < cc
        q2 = ec_dec_bits(st, buf, fq)
        offset = ((q2 ## f64) + (~0.5 ## f64)) * ((1 << (14 - fq)) ## f64) * (~0.00006103515625 ## f64) - (~0.5 ## f64)
        old[i + c * 21] = old[i + c * 21] + offset
        c += 1
    i += 1
  0

-> celt_unquant_finalise(st, buf, old, start, iend, fine_quant, fine_priority, bits_left0, cc) (i64[] u8[] f64[] i64 i64 i64[] i64[] i64 i64) i64
  bits_left = bits_left0
  prio = 0 ## i64
  while prio < 2
    i = start
    while i < iend && bits_left >= cc
      if fine_quant[i] < 8 && fine_priority[i] == prio
        c = 0 ## i64
        while c < cc
          q2 = ec_dec_bits(st, buf, 1)
          offset = ((q2 ## f64) - (~0.5 ## f64)) * ((1 << (14 - fine_quant[i] - 1)) ## f64) * (~0.00006103515625 ## f64)
          old[i + c * 21] = old[i + c * 21] + offset
          bits_left -= 1
          c += 1
      i += 1
    prio += 1
  0

-> celt_tf_decode(st, buf, start, iend, is_transient, tf_res, lm, tfsel) (i64[] u8[] i64 i64 i64 i64[] i64 i64[]) i64
  budget = st[9] * 8
  tell = ec_tell(st)
  logp = 4 ## i64
  logp = 2 if is_transient != 0
  rsv = 0 ## i64
  rsv = 1 if lm > 0 && tell + logp + 1 <= budget
  budget -= rsv
  changed = 0 ## i64
  curr = 0 ## i64
  i = start
  while i < iend
    if tell + logp <= budget
      curr = curr ^ ec_dec_bit_logp(st, buf, logp)
      tell = ec_tell(st)
      changed = changed | curr
    tf_res[i] = curr
    logp = 5
    logp = 4 if is_transient != 0
    i += 1
  sel = 0 ## i64
  base = lm * 8 + 4 * is_transient
  if rsv != 0 && tfsel[base + changed] != tfsel[base + 2 + changed]
    sel = ec_dec_bit_logp(st, buf, 1)
  i = start
  while i < iend
    tf_res[i] = tfsel[base + 2 * sel + tf_res[i]]
    i += 1
  0

-> celt_denormalise(mi, emeans, w, xo, freq, fo, old, oo, start0, end0, mm, silence) (i64[] f64[] f64[] i64 f64[] i64 f64[] i64 i64 i64 i64 i64) i64
  n = mm * 120
  start = start0
  iend = end0
  bound = mm * mi[iend]
  if silence != 0
    bound = 0
    start = 0
    iend = 0
  f = fo
  x = xo + mm * mi[start]
  i = 0 ## i64
  while i < mm * mi[start]
    freq[f] = ~0.0 ## f64
    f += 1
    i += 1
  i = start
  while i < iend
    j = mm * mi[i]
    band_end = mm * mi[i + 1]
    lg = (old[oo + i] + emeans[i]) ## f64
    if lg > ~32.0
      lg = (~32.0) ## f64
    g = Math.exp(~0.6931471805599453094 * lg) ## f64
    while j < band_end
      freq[f] = w[x] * g
      f += 1
      x += 1
      j += 1
    i += 1
  i = fo + bound
  while i < fo + n
    freq[i] = ~0.0 ## f64
    i += 1
  0

-> celt_anti_collapse(mi, w, cmask, lm, cc, size, start, iend, loge, prev1, prev2, pulses, seed0) (i64[] f64[] i64[] i64 i64 i64 i64 i64 f64[] f64[] f64[] i64[] i64) i64
  seed = seed0
  i = start
  while i < iend
    n0 = mi[i + 1] - mi[i]
    depth = ((1 + pulses[i]) / n0) >> lm
    thresh = ~0.5 * Math.exp(~0.6931471805599453094 * (~-0.125 * (depth ## f64)))
    sqrt_1 = ~1.0 / Math.sqrt((n0 << lm) ## f64)
    c = 0 ## i64
    while c < cc
      p1 = prev1[c * 21 + i] ## f64
      p2 = prev2[c * 21 + i] ## f64
      if cc == 1
        q1 = prev1[21 + i] ## f64
        q2 = prev2[21 + i] ## f64
        if q1 > p1
          p1 = (q1) ## f64
        if q2 > p2
          p2 = (q2) ## f64
      mn = (p1) ## f64
      if p2 < mn
        mn = (p2) ## f64
      ediff = ((loge[c * 21 + i] ## f64) - mn) ## f64
      if ediff < ~0.0
        ediff = (~0.0) ## f64
      r = (~2.0 * Math.exp(~0.6931471805599453094 * (~0.0 - ediff))) ## f64
      if lm == 3
        r = (r * ~1.41421356) ## f64
      if thresh < r
        r = (thresh) ## f64
      r = (r * sqrt_1) ## f64
      rf = r ## f64
      xo = c * size + (mi[i] << lm)
      renorm = 0 ## i64
      k = 0 ## i64
      while k < (1 << lm)
        if (cmask[i * cc + c] & (1 << k)) == 0
          j = 0 ## i64
          while j < n0
            seed = celt_lcg(seed)
            if (seed & 32768) != 0
              w[xo + (j << lm) + k] = rf
            else
              w[xo + (j << lm) + k] = (~0.0 ## f64) - rf
            j += 1
          renorm = 1
        k += 1
      celt_renormalise(w, xo, n0 << lm, ~1.0) if renorm != 0
      c += 1
    i += 1
  0

-> celt_comb_gain(tap, k) (i64 i64) f64
  if tap == 0
    return ~0.3066406250 if k == 0
    return ~0.2170410156 if k == 1
    return ~0.1296386719
  if tap == 1
    return ~0.4638671875 if k == 0
    return ~0.2680664062 if k == 1
    return ~0.0
  return ~0.7998046875 if k == 0
  return ~0.1000976562 if k == 1
  ~0.0

# comb_filter: y[yo..yo+n) from x[xo..] (x history before xo); y may alias x.
-> celt_comb_filter(y, yo, x, xo, t0in, t1in, n, g0, g1, tap0, tap1, win, overlap0, inplace) (f64[] i64 f64[] i64 i64 i64 i64 f64 f64 i64 i64 f64[] i64 i64) i64
  if g0 == ~0.0 && g1 == ~0.0
    if inplace == 0
      i = 0 ## i64
      while i < n
        y[yo + i] = x[xo + i]
        i += 1
    return 0
  t0 = t0in
  t0 = 15 if t0 < 15
  t1 = t1in
  t1 = 15 if t1 < 15
  g00 = (g0 * celt_comb_gain(tap0, 0)) ## f64
  g01 = (g0 * celt_comb_gain(tap0, 1)) ## f64
  g02 = (g0 * celt_comb_gain(tap0, 2)) ## f64
  g10 = (g1 * celt_comb_gain(tap1, 0)) ## f64
  g11 = (g1 * celt_comb_gain(tap1, 1)) ## f64
  g12 = (g1 * celt_comb_gain(tap1, 2)) ## f64
  x1 = (x[xo - t1 + 1]) ## f64
  x2 = (x[xo - t1]) ## f64
  x3 = (x[xo - t1 - 1]) ## f64
  x4 = (x[xo - t1 - 2]) ## f64
  overlap = overlap0
  overlap = 0 if g0 == g1 && t0 == t1 && tap0 == tap1
  one = ~1.0 ## f64
  i = 0 ## i64
  while i < overlap
    x0 = (x[xo + i - t1 + 2]) ## f64
    f = win[i] * win[i]
    nf = one - f
    v = x[xo + i] + (nf * g00) * x[xo + i - t0] + (nf * g01) * (x[xo + i - t0 + 1] + x[xo + i - t0 - 1]) + (nf * g02) * (x[xo + i - t0 + 2] + x[xo + i - t0 - 2]) + (f * g10) * x2 + (f * g11) * (x1 + x3) + (f * g12) * (x0 + x4)
    y[yo + i] = v
    x4 = (x3) ## f64
    x3 = (x2) ## f64
    x2 = (x1) ## f64
    x1 = (x0) ## f64
    i += 1
  if g1 == ~0.0
    if inplace == 0
      while i < n
        y[yo + i] = x[xo + i]
        i += 1
    return 0
  xb = xo + i
  yb = yo + i
  x4 = (x[xb - t1 - 2]) ## f64
  x3 = (x[xb - t1 - 1]) ## f64
  x2 = (x[xb - t1]) ## f64
  x1 = (x[xb - t1 + 1]) ## f64
  j = 0 ## i64
  m = n - i
  while j < m
    x0 = (x[xb + j - t1 + 2]) ## f64
    y[yb + j] = x[xb + j] + g10 * x2 + g11 * (x1 + x3) + g12 * (x0 + x4)
    x4 = (x3) ## f64
    x3 = (x2) ## f64
    x2 = (x1) ## f64
    x1 = (x0) ## f64
    j += 1
  0

-> celt_deemphasis(mem, ooff, pcm, po, n, c, cc, pmem) (f64[] i64 f64[] i64 i64 i64 i64 f64[]) i64
  coef = ~0.85000610 ## f64
  vs = ~1e-30 ## f64
  sc = ~0.000030517578125 ## f64
  m = (pmem[c]) ## f64
  j = 0 ## i64
  while j < n
    tmp = mem[ooff + j] + vs + m
    m = (coef * tmp) ## f64
    pcm[po + j * cc + c] = tmp * sc
    j += 1
  pmem[c] = m
  0

-> celt_arr_move(a, dst, src, n) (f64[] i64 i64 i64) i64
  i = 0 ## i64
  if dst < src
    while i < n
      a[dst + i] = a[src + i]
      i += 1
  else
    i = n - 1
    while i >= 0
      a[dst + i] = a[src + i]
      i -= 1
  0

# ---------------------------------------------------------------- decoder

CELT_DBUF = 2048
CELT_CHMEM = 2168

+ OpusCeltDec
  rw :start, :iend, :stream_channels, :rng, :error

  -> new(@channels)
    @mem = f64[@channels * 2168]
    @old_e = f64[42]
    @old_log = f64[42]
    @old_log2 = f64[42]
    @bg_log = f64[42]
    @preemph = f64[2]
    @w = f64[4096]
    @freq = f64[1920]
    @iy = i64[256]
    @tmp = f64[1024]
    @cmask = i64[42]
    @tf_res = i64[21]
    @cap = i64[21]
    @offsets = i64[21]
    @fine_quant = i64[21]
    @pulses = i64[21]
    @fine_priority = i64[21]
    @p = i64[16]
    @out4 = i64[4]
    @st = i64[EC_N]
    @start = 0
    @iend = 21
    @stream_channels = @channels
    @disable_inv = 0
    @disable_inv = 1 if @channels == 1
    reset()

  -> reset
    @rng = 0
    @error = 0
    @loss_duration = 0
    @skip_plc = 1
    @pf_period = 0
    @pf_period_old = 0
    @pf_gain = ~0.0
    @pf_gain_old = ~0.0
    @pf_tapset = 0
    @pf_tapset_old = 0
    @prefilter_and_fold = 0
    @last_pitch_index = 0
    i = 0
    while i < @mem.size
      @mem[i] = ~0.0 ## f64
      i += 1
    i = 0
    while i < 42
      @old_e[i] = ~0.0 ## f64
      @old_log[i] = ~-28.0 ## f64
      @old_log2[i] = ~-28.0 ## f64
      @bg_log[i] = ~0.0 ## f64
      i += 1
    @preemph[0] = ~0.0 ## f64
    @preemph[1] = ~0.0 ## f64

  # celt_synthesis
  -> synthesis(start, eff_end, c_s, is_transient, lm, silence, n)
    cc = @channels
    mm = 1 << lm
    bb = 1
    nb = 120 << lm
    shift = 3 - lm
    if is_transient != 0
      bb = mm
      nb = 120
      shift = 3
    fft = CELT_FFT[shift]
    fac = fft[0]
    brev = fft[1]
    out0 = CELT_DBUF - n
    out1 = CELT_CHMEM + CELT_DBUF - n
    if cc == 2 && c_s == 1
      celt_denormalise(CELT_MI, CELT_EMEANS, @w, 0, @freq, 0, @old_e, 0, start, eff_end, mm, silence)
      f2 = out1 + 60
      i = 0
      while i < n
        @mem[f2 + i] = @freq[i]
        i += 1
      b = 0
      while b < bb
        celt_imdct(@mem, f2 + b, @mem, out0 + nb * b, CELT_WINDOW, shift, bb, CELT_TRIG, CELT_TWID, fac, brev)
        b += 1
      b = 0
      while b < bb
        celt_imdct(@freq, b, @mem, out1 + nb * b, CELT_WINDOW, shift, bb, CELT_TRIG, CELT_TWID, fac, brev)
        b += 1
    elsif cc == 1 && c_s == 2
      f2 = out0 + 60
      celt_denormalise(CELT_MI, CELT_EMEANS, @w, 0, @freq, 0, @old_e, 0, start, eff_end, mm, silence)
      celt_denormalise(CELT_MI, CELT_EMEANS, @w, n, @mem, f2, @old_e, 21, start, eff_end, mm, silence)
      celt_mix_half(@freq, @mem, f2, n)
      b = 0
      while b < bb
        celt_imdct(@freq, b, @mem, out0 + nb * b, CELT_WINDOW, shift, bb, CELT_TRIG, CELT_TWID, fac, brev)
        b += 1
    else
      c = 0
      while c < cc
        celt_denormalise(CELT_MI, CELT_EMEANS, @w, c * n, @freq, 0, @old_e, c * 21, start, eff_end, mm, silence)
        oc = c * CELT_CHMEM + CELT_DBUF - n
        b = 0
        while b < bb
          celt_imdct(@freq, b, @mem, oc + nb * b, CELT_WINDOW, shift, bb, CELT_TRIG, CELT_TWID, fac, brev)
          b += 1
        c += 1

  -> prefilter_fold(n)
    etmp = f64[120]
    c = 0
    while c < @channels
      base = c * CELT_CHMEM + CELT_DBUF - n
      celt_comb_filter(etmp, 0, @mem, base, @pf_period_old, @pf_period, 120, ~0.0 - @pf_gain_old, ~0.0 - @pf_gain, @pf_tapset_old, @pf_tapset, CELT_WINDOW, 0, 0)
      celt_fold_overlap(@mem, base, etmp, CELT_WINDOW)
      c += 1

  # Packet loss: noise-based concealment (libopus' noise PLC branch).
  -> decode_lost(n, lm)
    cc = @channels
    eff_end = @iend
    eff_end = 21 if eff_end > 21
    eff_end = @start if eff_end < @start
    c = 0
    while c < cc
      celt_arr_move(@mem, c * CELT_CHMEM, c * CELT_CHMEM + n, CELT_DBUF - n + 120)
      c += 1
    prefilter_fold(n) if @prefilter_and_fold != 0
    decay = ~1.5
    decay = ~0.5 if @loss_duration != 0
    @rng = celt_noise_plc(CELT_MI, @old_e, @bg_log, @w, @start, @iend, eff_end, cc, n, lm, decay, @rng)
    synthesis(@start, eff_end, cc, 0, lm, 0, n)
    @prefilter_and_fold = 0
    @skip_plc = 1
    @loss_duration = [10000, @loss_duration + (1 << lm)].min

  # Decodes one CELT frame of n samples (per channel) into pcm (interleaved,
  # @channels wide, starting at frame po). st/buf: the range decoder (shared
  # with SILK in hybrid mode) or nil to start a fresh one over buf[0, len).
  -> decode(buf, len, pcm, po, n, st)
    cc = @channels
    c_s = @stream_channels
    lm = 0
    lm += 1 while (120 << lm) < n && lm < 3
    mm = 1 << lm
    start = @start
    iend = @iend
    eff_end = iend
    eff_end = 21 if eff_end > 21
    if buf == nil || len <= 1
      decode_lost(n, lm)
      c = 0
      while c < cc
        celt_deemphasis(@mem, c * CELT_CHMEM + CELT_DBUF - n, pcm, po * cc, n, c, cc, @preemph)
        c += 1
      return n
    @skip_plc = 0 if @loss_duration == 0
    if st == nil
      st = @st
      ec_dec_init(st, buf, len)
    if c_s == 1
      celt_max_bands(@old_e)
    total_bits = len * 8
    tell = ec_tell(st)
    silence = 0
    if tell >= total_bits
      silence = 1
    elsif tell == 1
      silence = ec_dec_bit_logp(st, buf, 15)
    if silence != 0
      tell = len * 8
      st[4] = st[4] + tell - ec_tell(st)
    pf_gain = ~0.0
    pf_pitch = 0
    pf_tapset = 0
    if start == 0 && tell + 16 <= total_bits
      if ec_dec_bit_logp(st, buf, 1) != 0
        octave = ec_dec_uint(st, buf, 6)
        pf_pitch = (16 << octave) + ec_dec_bits(st, buf, 4 + octave) - 1
        qg = ec_dec_bits(st, buf, 3)
        pf_tapset = ec_dec_icdf(st, buf, CELT_TAPSET_ICDF, 0, 2) if ec_tell(st) + 2 <= total_bits
        pf_gain = ~0.09375 * ((qg + 1) ## f64)
      tell = ec_tell(st)
    is_transient = 0
    if lm > 0 && tell + 3 <= total_bits
      is_transient = ec_dec_bit_logp(st, buf, 3)
      tell = ec_tell(st)
    short_blocks = 0
    short_blocks = mm if is_transient != 0
    intra = 0
    intra = ec_dec_bit_logp(st, buf, 3) if tell + 3 <= total_bits
    if intra == 0 && @loss_duration != 0
      missing = [10, @loss_duration >> lm].min
      safety = ~0.0
      safety = ~1.5 if lm == 0
      safety = ~0.5 if lm == 1
      celt_loss_energy_fix(@old_e, @old_log, @old_log2, start, iend, missing, safety)
    celt_unquant_coarse(st, buf, CELT_E_PROB_MODEL, CELT_SMALL_ENERGY_ICDF, @old_e, start, iend, intra, c_s, lm, CELT_PRED_COEF, CELT_BETA_COEF)
    celt_tf_decode(st, buf, start, iend, is_transient, @tf_res, lm, CELT_TF_SELECT)
    tell = ec_tell(st)
    spread = 2
    spread = ec_dec_icdf(st, buf, CELT_SPREAD_ICDF, 0, 5) if tell + 4 <= total_bits
    celt_init_caps(CELT_MI, @cap, lm, c_s)
    total_bits = total_bits << 3
    total_bits = celt_dynalloc(CELT_MI, st, buf, @offsets, @cap, start, iend, c_s, lm, total_bits)
    tell = ec_tell_frac(st)
    alloc_trim = 5
    alloc_trim = ec_dec_icdf(st, buf, CELT_TRIM_ICDF, 0, 7) if tell + 48 <= total_bits
    bits = ((len * 8) << 3) - ec_tell_frac(st) - 1
    acr = 0
    acr = 8 if is_transient != 0 && lm >= 2 && bits >= ((lm + 2) << 3)
    bits -= acr
    coded = celt_compute_allocation(CELT_MI, CELT_SMALL, st, buf, start, iend, @offsets, @cap, alloc_trim, bits, @pulses, @fine_quant, @fine_priority, c_s, lm, @out4)
    balance = @out4[1]
    intensity = @out4[2]
    dual_stereo = @out4[3]
    celt_unquant_fine(st, buf, @old_e, start, iend, @fine_quant, c_s)
    c = 0
    while c < cc
      celt_arr_move(@mem, c * CELT_CHMEM, c * CELT_CHMEM + n, CELT_DBUF - n + 120)
      c += 1
    p = @p
    p[0] = start
    p[1] = iend
    p[2] = short_blocks
    p[3] = spread
    p[4] = dual_stereo
    p[5] = intensity
    p[6] = len * 64 - acr
    p[7] = balance
    p[8] = lm
    p[9] = coded
    p[10] = @rng
    p[11] = @disable_inv
    p[12] = c_s
    p[13] = n
    celt_quant_all_bands(CELT_MI, CELT_PVQ_U_DATA, CELT_PVQ_ROW, CELT_SMALL, st, buf, @w, @cmask, @pulses, @tf_res, p, @iy, @tmp)
    @rng = p[10]
    anti_on = 0
    anti_on = ec_dec_bits(st, buf, 1) if acr > 0
    celt_unquant_finalise(st, buf, @old_e, start, iend, @fine_quant, @fine_priority, len * 8 - ec_tell(st), c_s)
    if anti_on != 0
      celt_anti_collapse(CELT_MI, @w, @cmask, lm, c_s, n, start, iend, @old_e, @old_log, @old_log2, @pulses, @rng)
    if silence != 0
      i = 0
      while i < c_s * 21
        @old_e[i] = ~-28.0 ## f64
        i += 1
    prefilter_fold(n) if @prefilter_and_fold != 0
    synthesis(start, eff_end, c_s, is_transient, lm, silence, n)
    c = 0
    while c < cc
      @pf_period = 15 if @pf_period < 15
      @pf_period_old = 15 if @pf_period_old < 15
      base = c * CELT_CHMEM + CELT_DBUF - n
      celt_comb_filter(@mem, base, @mem, base, @pf_period_old, @pf_period, 120, @pf_gain_old, @pf_gain, @pf_tapset_old, @pf_tapset, CELT_WINDOW, 120, 1)
      if lm != 0
        celt_comb_filter(@mem, base + 120, @mem, base + 120, @pf_period, pf_pitch, n - 120, @pf_gain, pf_gain, @pf_tapset, pf_tapset, CELT_WINDOW, 120, 1)
      c += 1
    @pf_period_old = @pf_period
    @pf_gain_old = @pf_gain
    @pf_tapset_old = @pf_tapset
    @pf_period = pf_pitch
    @pf_gain = pf_gain
    @pf_tapset = pf_tapset
    if lm != 0
      @pf_period_old = @pf_period
      @pf_gain_old = @pf_gain
      @pf_tapset_old = @pf_tapset
    celt_energy_history(@old_e, @old_log, @old_log2, @bg_log, c_s, is_transient, start, iend, [160, @loss_duration + mm].min)
    @rng = st[0]
    c = 0
    while c < cc
      celt_deemphasis(@mem, c * CELT_CHMEM + CELT_DBUF - n, pcm, po * cc, n, c, cc, @preemph)
      c += 1
    @loss_duration = 0
    @prefilter_and_fold = 0
    @error = 1 if st[10] != 0
    n

-> celt_mix_half(freq, mem, f2, n) (f64[] f64[] i64 i64) i64
  h = ~0.5 ## f64
  i = 0 ## i64
  while i < n
    freq[i] = h * freq[i] + h * mem[f2 + i]
    i += 1
  0

-> celt_fold_overlap(mem, base, etmp, win) (f64[] i64 f64[] f64[]) i64
  i = 0 ## i64
  while i < 60
    mem[base + i] = win[i] * etmp[119 - i] + win[119 - i] * etmp[i]
    i += 1
  0

-> celt_max_bands(old) (f64[]) i64
  i = 0 ## i64
  while i < 21
    old[i] = old[21 + i] if old[21 + i] > old[i]
    i += 1
  0

-> celt_init_caps(mi, cap, lm, c) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < 21
    n = (mi[i + 1] - mi[i]) << lm
    cap[i] = ((mi[540 + 21 * (2 * lm + c - 1) + i] + 64) * c * n) >> 2
    i += 1
  0

-> celt_dynalloc(mi, st, buf, offsets, cap, start, iend, c, lm, total0) (i64[] i64[] u8[] i64[] i64[] i64 i64 i64 i64 i64) i64
  total_bits = total0
  dynalloc_logp = 6 ## i64
  tell = ec_tell_frac(st)
  i = 0 ## i64
  while i < 21
    offsets[i] = 0
    i += 1
  i = start
  while i < iend
    width = (c * (mi[i + 1] - mi[i])) << lm
    quanta = 48 ## i64
    quanta = width if width > 48
    quanta = width << 3 if (width << 3) < quanta
    loop_logp = dynalloc_logp
    boost = 0 ## i64
    while tell + (loop_logp << 3) < total_bits && boost < cap[i]
      flag = ec_dec_bit_logp(st, buf, loop_logp)
      tell = ec_tell_frac(st)
      break if flag == 0
      boost += quanta
      total_bits -= quanta
      loop_logp = 1
    offsets[i] = boost
    if boost > 0
      dynalloc_logp = dynalloc_logp - 1
      dynalloc_logp = 2 if dynalloc_logp < 2
    i += 1
  total_bits

-> celt_loss_energy_fix(old, ol1, ol2, start, iend, missing, safety) (f64[] f64[] f64[] i64 i64 i64 f64) i64
  c = 0 ## i64
  while c < 2
    i = start
    while i < iend
      k = c * 21 + i
      e0 = old[k] ## f64
      e1 = ol1[k] ## f64
      e2 = ol2[k] ## f64
      mx = (e1) ## f64
      if e2 > mx
        mx = (e2) ## f64
      if e0 < mx
        slope = (e1 - e0) ## f64
        h = ~0.5 * (e2 - e0)
        if h > slope
          slope = (h) ## f64
        d = (((1 + missing) ## f64) * slope) ## f64
        if d < ~0.0
          d = (~0.0) ## f64
        e0 = (e0 - d) ## f64
        if e0 < ~-20.0
          e0 = (~-20.0) ## f64
        old[k] = e0 ## f64
      else
        mn = (e0) ## f64
        if e1 < mn
          mn = (e1) ## f64
        if e2 < mn
          mn = (e2) ## f64
        old[k] = mn ## f64
      old[k] = old[k] - (safety ## f64)
      i += 1
    c += 1
  0

-> celt_energy_history(old, ol1, ol2, bg, c_s, is_transient, start, iend, inc_steps) (f64[] f64[] f64[] f64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  if c_s == 1
    while i < 21
      old[21 + i] = old[i]
      i += 1
  if is_transient == 0
    i = 0
    while i < 42
      ol2[i] = ol1[i]
      ol1[i] = old[i]
      i += 1
  else
    i = 0
    while i < 42
      ol1[i] = old[i] if old[i] < ol1[i]
      i += 1
  inc = ((inc_steps ## f64) * ~0.001) ## f64
  i = 0
  while i < 42
    v = (bg[i] + inc) ## f64
    if old[i] < v
      v = (old[i]) ## f64
    bg[i] = v
    i += 1
  c = 0 ## i64
  while c < 2
    i = 0
    while i < start
      old[c * 21 + i] = ~0.0 ## f64
      ol1[c * 21 + i] = ~-28.0 ## f64
      ol2[c * 21 + i] = ~-28.0 ## f64
      i += 1
    i = iend
    while i < 21
      old[c * 21 + i] = ~0.0 ## f64
      ol1[c * 21 + i] = ~-28.0 ## f64
      ol2[c * 21 + i] = ~-28.0 ## f64
      i += 1
    c += 1
  0

-> celt_noise_plc(mi, old, bg, w, start, iend, eff_end, cc, n, lm, decay, seed0) (i64[] f64[] f64[] f64[] i64 i64 i64 i64 i64 i64 f64 i64) i64
  c = 0 ## i64
  while c < cc
    i = start
    while i < iend
      k = c * 21 + i
      v = (old[k] - (decay ## f64)) ## f64
      if bg[k] > v
        v = (bg[k]) ## f64
      old[k] = v
      i += 1
    c += 1
  seed = seed0
  c = 0
  while c < cc
    i = start
    while i < eff_end
      boffs = n * c + (mi[i] << lm)
      blen = (mi[i + 1] - mi[i]) << lm
      j = 0 ## i64
      while j < blen
        seed = celt_lcg(seed)
        w[boffs + j] = celt_seed_s20(seed) ## f64
        j += 1
      celt_renormalise(w, boffs, blen, ~1.0)
      i += 1
    c += 1
  seed
