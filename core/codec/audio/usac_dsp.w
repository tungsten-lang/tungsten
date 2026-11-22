# core/codec/audio/usac_dsp — transforms and windows for the USAC decoder
# (core/codec/audio/usac): a complex FFT for every length the codec uses
# (2^k and 3 * 2^k: 1024- and 768-sample frames, their short blocks, TCX
# and FAC), the DCT-IV built on it, the IMDCT of ISO/IEC 23003-3 (the AAC
# definition, 2/N scaled) and the sine / KBD windows of any length.
#
#   usac_imdct(coef, co, out, oo, m)      m coefficients -> 2m samples
#   usac_dct4(x, xo, m)                   in place, unscaled
#   usac_window(len, kbd)                 rising half, len samples (cached)
#
# All DSP is f64. Plans (twiddles, bit reversal) are built once per length
# and cached; the caches are only written while a decoder is created
# (usac_dsp_prepare), so decoding may run on a worker thread.

USAC_PI = ~3.141592653589793

# ---- FFT ----
# Plan for length n = 2^k or 3 * 2^k: [n, n3 (1 or 3), p2 (n / n3),
# rev i64[p2], tw f64[2 * n] (cos at 2j, -sin at 2j + 1 of 2 pi j / n)].
USAC_FFT_PLANS = {}

-> usac_fft_plan(n)
  p = USAC_FFT_PLANS[n]
  return p if p != nil
  n3 = n % 3 == 0 ? 3 : 1
  p2 = n / n3
  bits = 0
  while (1 << bits) < p2
    bits += 1
  rev = i64[p2]
  i = 0
  while i < p2
    r = 0
    v = i
    b = 0
    while b < bits
      r = (r << 1) | (v & 1)
      v = v >> 1
      b += 1
    rev[i] = r
    i += 1
  tw = f64[2 * n]
  j = 0
  while j < n
    a = 2.0 * USAC_PI * j / n
    tw[2 * j] = Math.cos(a)
    tw[2 * j + 1] = 0.0 - Math.sin(a)
    j += 1
  p = [n, n3, p2, rev, tw, f64[n], f64[n]]
  USAC_FFT_PLANS[n] = p
  p

# radix-2 DIT over p2 points, input re/im already bit-reversed at offset o,
# twiddles of the full length n with stride n / p2
-> usac_fft2(re, im, o, p2, tw, stride) (f64[] f64[] i64 i64 f64[] i64) i64
  size = 2
  while size <= p2
    half = size >> 1
    step = (p2 / size) * stride
    i = 0
    while i < p2
      j = 0
      k = 0
      while j < half
        wr = tw[2 * k]
        wi = tw[2 * k + 1]
        a = o + i + j
        b = a + half
        xr = re[b]
        xi = im[b]
        tr = xr * wr - xi * wi
        ti = xr * wi + xi * wr
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] = re[a] + tr
        im[a] = im[a] + ti
        j += 1
        k += step
      i += size
    size = size << 1
  0

# forward complex FFT (exp(-2 pi i jk / n)) of re/im[0..n), in place
-> usac_fft_run(re, im, n, n3, p2, rev, tw, tr, ti) (f64[] f64[] i64 i64 i64 i64[] f64[] f64[] f64[]) i64
  if n3 == 1
    i = 0
    while i < n
      r = rev[i]
      if r > i
        t = re[i]
        re[i] = re[r]
        re[r] = t
        t = im[i]
        im[i] = im[r]
        im[r] = t
      i += 1
    usac_fft2(re, im, 0, n, tw, 1)
    return 0
  # three interleaved sub-FFTs of p2 points, then radix-3 butterflies
  s = 0
  while s < 3
    i = 0
    while i < p2
      src = 3 * rev[i] + s
      tr[s * p2 + i] = re[src]
      ti[s * p2 + i] = im[src]
      i += 1
    usac_fft2(tr, ti, s * p2, p2, tw, 3)
    s += 1
  c3 = ~-0.5
  s3 = ~-0.8660254037844386
  k = 0
  while k < p2
    ar = tr[k]
    ai = ti[k]
    w1r = tw[2 * k]
    w1i = tw[2 * k + 1]
    w2r = tw[(4 * k) % (2 * n)]
    w2i = tw[(4 * k) % (2 * n) + 1]
    br = tr[p2 + k] * w1r - ti[p2 + k] * w1i
    bi = tr[p2 + k] * w1i + ti[p2 + k] * w1r
    cr = tr[2 * p2 + k] * w2r - ti[2 * p2 + k] * w2i
    ci = tr[2 * p2 + k] * w2i + ti[2 * p2 + k] * w2r
    sr = br + cr
    si = bi + ci
    dr = br - cr
    di = bi - ci
    re[k] = ar + sr
    im[k] = ai + si
    mr = ar + c3 * sr
    mi = ai + c3 * si
    # (b - c) * (-i sin(2 pi / 3)) for the second output, conjugate for the third
    ur = 0.0 - s3 * di
    ui = s3 * dr
    re[k + p2] = mr + ur
    im[k + p2] = mi + ui
    re[k + 2 * p2] = mr - ur
    im[k + 2 * p2] = mi - ui
    k += 1
  0

-> usac_fft(re, im, n)
  p = usac_fft_plan(n)
  usac_fft_run(re, im, n, p[1], p[2], p[3], p[4], p[5], p[6])

# ---- DCT-IV ----
# y[k] = sum_n x[n] cos(pi / m (n + 1/2)(k + 1/2)), m even, via an
# m/2-point complex FFT. Plan: [m, fft plan, pre/post twiddles f64[m], re, im].
USAC_DCT_PLANS = {}

-> usac_dct4_plan(m)
  p = USAC_DCT_PLANS[m]
  return p if p != nil
  h = m / 2
  tw = f64[m]
  i = 0
  while i < h
    a = USAC_PI * (8 * i + 1) / (8.0 * m)
    tw[2 * i] = Math.cos(a)
    tw[2 * i + 1] = 0.0 - Math.sin(a)
    i += 1
  p = [m, usac_fft_plan(h), tw, f64[h], f64[h]]
  USAC_DCT_PLANS[m] = p
  p

-> usac_dct4_run(x, xo, m, tw, re, im, n3, p2, rev, ftw, tr, ti) (f64[] i64 i64 f64[] f64[] f64[] i64 i64 i64[] f64[] f64[] f64[]) i64
  h = m >> 1
  i = 0
  while i < h
    a = x[xo + 2 * i]
    b = x[xo + m - 1 - 2 * i]
    c = tw[2 * i]
    s = tw[2 * i + 1]
    re[i] = a * c - b * s
    im[i] = a * s + b * c
    i += 1
  usac_fft_run(re, im, h, n3, p2, rev, ftw, tr, ti)
  i = 0
  while i < h
    c = tw[2 * i]
    s = tw[2 * i + 1]
    yr = re[i] * c - im[i] * s
    yi = re[i] * s + im[i] * c
    x[xo + 2 * i] = yr
    x[xo + m - 1 - 2 * i] = 0.0 - yi
    i += 1
  0

-> usac_dct4(x, xo, m)
  p = usac_dct4_plan(m)
  f = p[1]
  usac_dct4_run(x, xo, m, p[2], p[3], p[4], f[1], f[2], f[3], f[4], f[5], f[6])

# ---- IMDCT ----
# out[oo .. oo + 2m) = (2 / 2m) sum_k coef[co + k] cos(pi / m (n + n0)(k + 1/2)),
# n0 = (m + 1) / 2 (ISO/IEC 14496-3 / 23003-3 IMDCT of window length 2m).
-> usac_imdct_unfold(t, out, oo, m, sc) (f64[] f64[] i64 i64 f64) i64
  h = m >> 1
  i = 0
  while i < h
    a = t[h + i] * sc
    b = t[i] * sc
    out[oo + i] = a
    out[oo + m - 1 - i] = 0.0 - a
    out[oo + m + h + i] = 0.0 - b
    out[oo + m + h - 1 - i] = 0.0 - b
    i += 1
  0

-> usac_copy(dst, d, src, s, n) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < n
    dst[d + i] = src[s + i]
    i += 1
  0

USAC_IMDCT_TMP = {}

-> usac_imdct(coef, co, out, oo, m)
  t = USAC_IMDCT_TMP[m]
  if t == nil
    t = f64[m]
    USAC_IMDCT_TMP[m] = t
  usac_copy(t, 0, coef, co, m)
  usac_dct4(t, 0, m)
  usac_imdct_unfold(t, out, oo, m, 1.0 / m)

# ---- windows ----
# Rising half of the sine or KBD window for a transform of 2 * len samples
# (len values). KBD: alpha 4 for long windows (>= 512), 6 otherwise.
USAC_WINDOWS = {}

-> usac_bessel_i0(x)
  s = 1.0
  u = 1.0
  h = x / 2.0
  n = 1
  more = true
  while more
    t = h / n
    n += 1
    u = u * t * t
    s += u
    more = u >= 1.0e-41 * s
  s

-> usac_window(len, kbd)
  key = len * 2 + (kbd ? 1 : 0)
  w = USAC_WINDOWS[key]
  return w if w != nil
  w = f64[len]
  if kbd
    alpha = len >= 512 ? 4.0 : 6.0
    a = alpha * USAC_PI
    ib = 1.0 / usac_bessel_i0(a)
    n = 2 * len
    tmp = f64[len]
    sum = 0.0
    i = 0
    while i < len
      t = 4.0 * i / n - 1.0
      tmp[i] = usac_bessel_i0(a * Math.sqrt(1.0 - t * t)) * ib
      sum += tmp[i]
      i += 1
    acc = 0.0
    i = 0
    while i < len
      acc += tmp[i]
      w[i] = Math.sqrt(acc / sum)
      i += 1
  else
    i = 0
    while i < len
      w[i] = Math.sin((i + 0.5) * USAC_PI / (2.0 * len))
      i += 1
  USAC_WINDOWS[key] = w
  w

# Build every plan and window a decoder with this core frame length needs,
# so decoding never writes the shared caches.
-> usac_dsp_prepare(frame)
  [frame, frame / 8, frame / 2, frame / 4, frame / 16, 64, 128, 256, 512, 1024, 96, 192, 384, 768, 48].each ->(m)
    if m >= 8 && m % 2 == 0
      usac_dct4_plan(m)
      usac_imdct(f64[m], 0, f64[2 * m], 0, m)
  [frame, frame / 8, frame / 4, frame / 16, 2 * (frame / 8), 64, 48, 128, 96, 256, 192].each ->(l)
    usac_window(l, false)
    usac_window(l, true)
  0
