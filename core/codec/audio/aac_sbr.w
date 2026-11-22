# core/codec/audio/aac_sbr — Spectral Band Replication (HE-AAC v1, ISO/IEC 14496-3
# 4.6.18) for core/codec/audio/aac. One AacSbr per SCE/CPE element (both channels of a
# pair share the header state); the HE-AAC v2 Parametric Stereo stage lives
# in core/codec/audio/aac_ps and runs on this module's QMF-domain output.
#
# The structure follows the reference decoder flow (and FFmpeg's float
# decoder, which the tests compare against): bitstream (header, grid,
# delta-coded envelopes / noise floors, inverse filtering modes, harmonics),
# frequency tables (master, high/low, noise, limiter, patches), 32-band QMF
# analysis, LPC-based HF generation with chirp factors, envelope adjustment
# (gain / limiter / boost, noise and sinusoid insertion, gain smoothing) and
# 64-band QMF synthesis. QMF banks use the direct complex-modulation
# definitions with precomputed kernels; samples run at +/-32768 scale inside.
#
# Integer parameters of an element are packed into an i64[] (indices
# SBP_*), per-channel integers into another (SBC_*), so the typed DSP
# functions can take them directly.

AAC_SBR_PI = ~3.141592653589793

# element parameter indices
SBP_KX0 = 0
SBP_KX1 = 1
SBP_M0 = 2
SBP_M1 = 3
SBP_K0 = 4
SBP_NLOW = 5
SBP_NHIGH = 6
SBP_NQ = 7
SBP_NPATCH = 8
SBP_NLIM = 9
SBP_LIMGAIN = 10
SBP_INTERP = 11
SBP_SMOOTH = 12
SBP_RESET = 13
SBP_NMASTER = 14
SBP_K2 = 15
SBP_K1 = 16
SBP_PNUM = 20
SBP_PSTART = 27
SBP_FHIGH = 40
SBP_FLOW = 90
SBP_FNOISE = 120
SBP_FLIM = 130
SBP_FMASTER = 160
SBP_SIZE = 220

# channel indices
SBC_NENV = 0
SBC_AMPRES = 1
SBC_TOLD = 2
SBC_CLASS = 3
SBC_NNOISE = 4
SBC_EA0 = 5
SBC_EA1 = 6
SBC_HARM = 7
SBC_INOISE = 8
SBC_ISINE = 9
SBC_YPOS = 10
SBC_FRES = 11
SBC_TENV = 20
SBC_TQ = 30
SBC_DFENV = 33
SBC_DFNOISE = 38
SBC_INVF = 40
SBC_ADDH = 50
SBC_ENVQ = 100
SBC_NOISEQ = 400
SBC_SIDX = 420
SBC_SIZE = 810

-> sbr_lrint(x)
  r = Math.floor(x)
  d = x - r
  ri = r.to_i
  return ri + 1 if d > ~0.5
  return ri if d < ~0.5
  return ri if ri % 2 == 0
  ri + 1

# (typed: an untyped `## f32` return trips the compiler, see report)
-> sbr_f32(x) (f64) f64
  ((x) ## f32) ## f64

# QMF kernels and window
-> sbr_build_kernels
  ac = f64[32 * 64]
  as = f64[32 * 64]
  k = 0
  while k < 32
    n = 0
    while n < 64
      a = AAC_SBR_PI * ((k ## f64) + ~0.5) * (((2 * n) ## f64) - ~0.5) / ~64.0
      ac[k * 64 + n] = ~2.0 * Math.cos(a)
      as[k * 64 + n] = ~2.0 * Math.sin(a)
      n += 1
    k += 1
  sc = f64[128 * 64]
  ss = f64[128 * 64]
  n = 0
  while n < 128
    k = 0
    while k < 64
      a = AAC_SBR_PI * ((k ## f64) + ~0.5) * ((2 * n - 255) ## f64) / ~128.0
      sc[n * 64 + k] = Math.cos(a) / ~64.0
      ss[n * 64 + k] = Math.sin(a) / ~64.0
      k += 1
    n += 1
  w = f64[640]
  i = 0
  while i < 640
    w[i] = SBR_QMF_WINDOW[i]
    i += 1
  nz = f64[1024]
  i = 0
  while i < 1024
    nz[i] = SBR_NOISE[i]
    i += 1
  [ac, as, sc, ss, w, nz]

SBR_K = sbr_build_kernels()
SBR_AC = SBR_K[0]
SBR_AS = SBR_K[1]
SBR_SC = SBR_K[2]
SBR_SS = SBR_K[3]
SBR_WIN = SBR_K[4]
SBR_NZ = SBR_K[5]

# ---- QMF banks ----

# 32-band analysis of 1024 core samples (pcm, +/-1 scale) into
# W[wo + slot * 32 + k] (32 slots).
-> sbr_qmf_ana(pcm, xb, wre, wim, wo, win, akc, aks) (f64[] f64[] f64[] f64[] i64 f64[] f64[] f64[]) i64
  i = 0
  while i < 288
    xb[i] = xb[i + 1024]
    i += 1
  i = 0
  while i < 1024
    xb[288 + i] = pcm[i] * ~32768.0
    i += 1
  u = f64[64]
  l = 0
  while l < 32
    base = l * 32 + 319
    n = 0
    while n < 64
      s = ~0.0
      j = 0
      while j < 5
        m = n + 64 * j
        s += xb[base - m] * win[2 * m]
        j += 1
      u[n] = s
      n += 1
    k = 0
    while k < 32
      re = ~0.0
      im = ~0.0
      ko = k * 64
      n = 0
      while n < 64
        re += u[n] * akc[ko + n]
        im += u[n] * aks[ko + n]
        n += 1
      wre[wo + l * 32 + k] = re
      wim[wo + l * 32 + k] = im
      k += 1
    l += 1
  0

# 64-band synthesis of 32 slots of X (slot * 64 + k) into 2048 samples.
# vb: ring buffer (5376), vs[0] = offset.
-> sbr_qmf_syn(xre, xim, vb, vs, out, win, sc, ss) (f64[] f64[] f64[] i64[] f64[] f64[] f64[] f64[]) i64
  vsz = 5376
  l = 0
  while l < 32
    off = vs[0]
    if off - 128 < 0
      i = 0
      while i < 1152
        vb[vsz - 1152 + i] = vb[off + i]
        i += 1
      off = vsz - 1152
    off -= 128
    vs[0] = off
    xo = l * 64
    n = 0
    while n < 128
      s = ~0.0
      no = n * 64
      k = 0
      while k < 64
        s += xre[xo + k] * sc[no + k] - xim[xo + k] * ss[no + k]
        k += 1
      vb[off + n] = s
      n += 1
    n = 0
    while n < 64
      s = ~0.0
      i = 0
      while i < 5
        s += vb[off + 256 * i + n] * win[128 * i + n] + vb[off + 256 * i + 192 + n] * win[128 * i + 64 + n]
        i += 1
      out[l * 64 + n] = s * ~0.000030517578125
      n += 1
    l += 1
  0

# ---- HF generation ----

-> sbr_lf_gen(xlr, xli, wre, wim, cur, prev, kx1, kx0) (f64[] f64[] f64[] f64[] i64 i64 i64 i64) i64
  i = 0
  while i < 32 * 40
    xlr[i] = ~0.0
    xli[i] = ~0.0
    i += 1
  k = 0
  while k < kx1
    i = 8
    while i < 40
      xlr[k * 40 + i] = wre[cur + (i - 8) * 32 + k]
      xli[k * 40 + i] = wim[cur + (i - 8) * 32 + k]
      i += 1
    k += 1
  k = 0
  while k < kx0
    i = 0
    while i < 8
      xlr[k * 40 + i] = wre[prev + (i + 24) * 32 + k]
      xli[k * 40 + i] = wim[prev + (i + 24) * 32 + k]
      i += 1
    k += 1
  0

# alpha0 / alpha1 (complex, a[k * 2], a[k * 2 + 1]) for k < k0
-> sbr_inv_filter(xlr, xli, a0, a1, k0) (f64[] f64[] f64[] f64[] i64) i64
  k = 0
  while k < k0
    o = k * 40
    rs2 = xlr[o] * xlr[o + 2] + xli[o] * xli[o + 2]
    is2 = xlr[o] * xli[o + 2] - xli[o] * xlr[o + 2]
    rs1 = ~0.0
    is1 = ~0.0
    rs0 = ~0.0
    i = 1
    while i < 38
      a = xlr[o + i]
      b = xli[o + i]
      rs0 += a * a + b * b
      rs1 += a * xlr[o + i + 1] + b * xli[o + i + 1]
      is1 += a * xli[o + i + 1] - b * xlr[o + i + 1]
      rs2 += a * xlr[o + i + 2] + b * xli[o + i + 2]
      is2 += a * xli[o + i + 2] - b * xlr[o + i + 2]
      i += 1
    p010 = rs2
    p011 = is2
    p210 = rs0 + xlr[o] * xlr[o] + xli[o] * xli[o]
    p100 = rs0 + xlr[o + 38] * xlr[o + 38] + xli[o + 38] * xli[o + 38]
    p110 = rs1 + xlr[o] * xlr[o + 1] + xli[o] * xli[o + 1]
    p111 = is1 + xlr[o] * xli[o + 1] - xli[o] * xlr[o + 1]
    p000 = rs1 + xlr[o + 38] * xlr[o + 39] + xli[o + 38] * xli[o + 39]
    p001 = is1 + xlr[o + 38] * xli[o + 39] - xli[o + 38] * xlr[o + 39]
    dk = p210 * p100 - (p110 * p110 + p111 * p111) / ~1.000001
    a1r = ~0.0
    a1i = ~0.0
    if dk != ~0.0
      a1r = (p000 * p110 - p001 * p111 - p010 * p100) / dk
      a1i = (p000 * p111 + p001 * p110 - p011 * p100) / dk
    a0r = ~0.0
    a0i = ~0.0
    if p100 != ~0.0
      a0r = ~0.0 - (p000 + a1r * p110 + a1i * p111) / p100
      a0i = ~0.0 - (p001 + a1i * p110 - a1r * p111) / p100
    if a1r * a1r + a1i * a1i >= ~16.0 || a0r * a0r + a0i * a0i >= ~16.0
      a1r = ~0.0
      a1i = ~0.0
      a0r = ~0.0
      a0i = ~0.0
    a0[k * 2] = a0r
    a0[k * 2 + 1] = a0i
    a1[k * 2] = a1r
    a1[k * 2 + 1] = a1i
    k += 1
  0

-> sbr_hf_gen(xhr, xhi, xlr, xli, a0, a1, bw, p, c) (f64[] f64[] f64[] f64[] f64[] f64[] f64[] i64[] i64[]) i64
  kx1 = p[1]
  m1 = p[3]
  nq = p[7]
  start = 2 * c[20] + 2
  en = 2 * c[20 + c[0]] + 2
  k = kx1
  g = 0
  j = 0
  while j < p[8]
    x = 0
    while x < p[20 + j]
      pp = p[27 + j] + x
      while g <= nq && k >= p[120 + g]
        g += 1
      g -= 1
      if g < 0
        return 1
      b = bw[g]
      ar0 = a1[pp * 2] * b * b
      ai0 = a1[pp * 2 + 1] * b * b
      ar1 = a0[pp * 2] * b
      ai1 = a0[pp * 2 + 1] * b
      ho = k * 40
      lo = pp * 40
      i = start
      while i < en
        xhr[ho + i] = xlr[lo + i - 2] * ar0 - xli[lo + i - 2] * ai0 + xlr[lo + i - 1] * ar1 - xli[lo + i - 1] * ai1 + xlr[lo + i]
        xhi[ho + i] = xli[lo + i - 2] * ar0 + xlr[lo + i - 2] * ai0 + xli[lo + i - 1] * ar1 + xlr[lo + i - 1] * ai1 + xli[lo + i]
        i += 1
      x += 1
      k += 1
    j += 1
  while k < m1 + kx1
    i = 0
    while i < 40
      xhr[k * 40 + i] = ~0.0
      xhi[k * 40 + i] = ~0.0
      i += 1
    k += 1
  0

# Mapping of envelope / noise / sinusoid data onto QMF bands (per envelope
# e: [e * 48 + m - kx1]).
-> sbr_mapping(p, c, ef, nf, eo, qm, sm) (i64[] i64[] f64[] f64[] f64[] f64[] f64[]) i64
  kx1 = p[1]
  nenv = c[0]
  m = 0
  while m < 48
    c[420 + 48 + m] = 0
    m += 1
  e = 1
  while e < 7
    m = 0
    while m < 48
      c[420 + 48 * (e + 1) + m] = 0 if e + 1 < 8
      m += 1
    e += 1
  e = 0
  while e < nenv
    fr = c[11 + e + 1]
    ilim = p[5 + fr]
    tb = 90
    tb = 40 if fr == 1
    if p[tb] != kx1
      return 1
    i = 0
    while i < ilim
      m = p[tb + i]
      while m < p[tb + i + 1]
        eo[e * 48 + m - kx1] = ef[(e + 1) * 48 + i]
        m += 1
      i += 1
    kq = 0
    kq = 1 if c[4] > 1 && c[20 + e] >= c[31]
    i = 0
    while i < p[7]
      m = p[120 + i]
      while m < p[120 + i + 1]
        qm[e * 48 + m - kx1] = nf[(kq + 1) * 5 + i]
        m += 1
      i += 1
    i = 0
    while i < p[6]
      if c[7] != 0
        mid = (p[40 + i] + p[40 + i + 1]) >> 1
        v = 0
        if e >= c[6] || c[420 + mid - kx1] == 1
          v = c[50 + i]
        c[420 + (e + 1) * 48 + mid - kx1] = v
      i += 1
    i = 0
    while i < ilim
      add = 0
      m = p[tb + i]
      while m < p[tb + i + 1]
        if c[420 + (e + 1) * 48 + m - kx1] != 0
          add = 1
        m += 1
      m = p[tb + i]
      while m < p[tb + i + 1]
        sm[e * 48 + m - kx1] = add ## f64
        m += 1
      i += 1
    e += 1
  m = 0
  while m < 48
    c[420 + m] = c[420 + nenv * 48 + m]
    m += 1
  0

-> sbr_env_estimate(ec, xhr, xhi, p, c) (f64[] f64[] f64[] i64[] i64[]) i64
  kx1 = p[1]
  nenv = c[0]
  if p[11] != 0
    e = 0
    while e < nenv
      rs = ~0.5 / ((c[20 + e + 1] - c[20 + e]) ## f64)
      ilb = c[20 + e] * 2 + 2
      iub = c[20 + e + 1] * 2 + 2
      if ilb >= 40
        return 0
      m = 0
      while m < p[3]
        o = (m + kx1) * 40
        s = ~0.0
        i = ilb
        while i < iub
          s += xhr[o + i] * xhr[o + i] + xhi[o + i] * xhi[o + i]
          i += 1
        ec[e * 48 + m] = s * rs
        m += 1
      e += 1
  else
    e = 0
    while e < nenv
      esz = 2 * (c[20 + e + 1] - c[20 + e])
      ilb = c[20 + e] * 2 + 2
      iub = c[20 + e + 1] * 2 + 2
      if ilb >= 40
        return 0
      fr = c[11 + e + 1]
      tb = 90
      tb = 40 if fr == 1
      pp = 0
      while pp < p[5 + fr]
        s = ~0.0
        k = p[tb + pp]
        while k < p[tb + pp + 1]
          o = k * 40
          i = ilb
          while i < iub
            s += xhr[o + i] * xhr[o + i] + xhi[o + i] * xhi[o + i]
            i += 1
          k += 1
        den = esz * (p[tb + pp + 1] - p[tb + pp])
        s = s / (den ## f64)
        k = p[tb + pp]
        while k < p[tb + pp + 1]
          ec[e * 48 + k - kx1] = s
          k += 1
        pp += 1
      e += 1
  0

-> sbr_gain_calc(p, c, eo, qm, sm, ec, qmo, smo, gain) (i64[] i64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[]) i64
  kx1 = p[1]
  lg = ~1.0
  lg = ~0.70795 if p[10] == 0
  lg = ~1.41254 if p[10] == 2
  lg = ~10000000000.0 if p[10] == 3
  eps = ~1.1920928955078125e-07
  e = 0
  while e < c[0]
    delta = 1
    delta = 0 if e == c[6] || e == c[5]
    k = 0
    while k < p[9]
      m0 = p[130 + k] - kx1
      m1 = p[130 + k + 1] - kx1
      m = m0
      while m < m1
        ix = e * 48 + m
        t = eo[ix] / (~1.0 + qm[ix])
        qmo[ix] = Math.sqrt(t * qm[ix])
        smo[ix] = Math.sqrt(t * (c[420 + (e + 1) * 48 + m] ## f64))
        if sm[ix] == ~0.0
          g = eo[ix] / ((~1.0 + ec[ix]) * (~1.0 + qm[ix] * (delta ## f64)))
        else
          g = eo[ix] * qm[ix] / ((~1.0 + ec[ix]) * (~1.0 + qm[ix]))
        gain[ix] = Math.sqrt(g) + ~1.1754943508222875e-38
        m += 1
      s0 = ~0.0
      s1 = ~0.0
      m = m0
      while m < m1
        s0 += eo[e * 48 + m]
        s1 += ec[e * 48 + m]
        m += 1
      gmax = lg * Math.sqrt((eps + s0) / (eps + s1))
      gmax = ~100000.0 if gmax > ~100000.0
      m = m0
      while m < m1
        ix = e * 48 + m
        qmax = qmo[ix] * gmax / gain[ix]
        qmo[ix] = qmax if qmax < qmo[ix]
        gain[ix] = gmax if gmax < gain[ix]
        m += 1
      s0 = ~0.0
      s1 = ~0.0
      m = m0
      while m < m1
        ix = e * 48 + m
        s0 += eo[ix]
        s1 += ec[ix] * gain[ix] * gain[ix] + smo[ix] * smo[ix]
        if delta != 0 && smo[ix] == ~0.0
          s1 += qmo[ix] * qmo[ix]
        m += 1
      gb = Math.sqrt((eps + s0) / (eps + s1))
      gb = ~1.584893192 if gb > ~1.584893192
      m = m0
      while m < m1
        ix = e * 48 + m
        gain[ix] = gain[ix] * gb
        qmo[ix] = qmo[ix] * gb
        smo[ix] = smo[ix] * gb
        m += 1
      k += 1
    e += 1
  0

# HF assembly into Y (yo = buffer offset; slot i at yo + i * 64 + k)
-> sbr_hf_assemble(yr, yi, yo, xhr, xhi, p, c, gt, qt, gain, qmo, smo, nz) (f64[] f64[] i64 f64[] f64[] i64[] i64[] f64[] f64[] f64[] f64[] f64[] f64[]) i64
  hsl = 0
  hsl = 4 if p[12] == 0
  kx = p[1]
  mmax = p[3]
  inoise = c[8]
  isine = c[9]
  t0 = c[20]
  told = c[2]
  if p[13] != 0
    i = 0
    while i < hsl
      m = 0
      while m < mmax
        gt[(i + 2 * t0) * 48 + m] = gain[m]
        qt[(i + 2 * t0) * 48 + m] = qmo[m]
        m += 1
      i += 1
  elsif hsl != 0
    i = 0
    while i < 4
      m = 0
      while m < 48
        gt[(i + 2 * t0) * 48 + m] = gt[(i + 2 * told) * 48 + m]
        qt[(i + 2 * t0) * 48 + m] = qt[(i + 2 * told) * 48 + m]
        m += 1
      i += 1
  e = 0
  while e < c[0]
    i = 2 * c[20 + e]
    while i < 2 * c[20 + e + 1]
      m = 0
      while m < mmax
        gt[(hsl + i) * 48 + m] = gain[e * 48 + m]
        qt[(hsl + i) * 48 + m] = qmo[e * 48 + m]
        m += 1
      i += 1
    e += 1
  gf = f64[48]
  qf = f64[48]
  e = 0
  while e < c[0]
    trans = e == c[5] || e == c[6]
    i = 2 * c[20 + e]
    while i < 2 * c[20 + e + 1]
      if hsl != 0 && !trans
        m = 0
        while m < mmax
          i1 = i + hsl
          g = gt[i1 * 48 + m] * ~0.33333333333333 + gt[(i1 - 1) * 48 + m] * ~0.30150283239582 + gt[(i1 - 2) * 48 + m] * ~0.21816949906249 + gt[(i1 - 3) * 48 + m] * ~0.11516383427084 + gt[(i1 - 4) * 48 + m] * ~0.03183050093751
          q = qt[i1 * 48 + m] * ~0.33333333333333 + qt[(i1 - 1) * 48 + m] * ~0.30150283239582 + qt[(i1 - 2) * 48 + m] * ~0.21816949906249 + qt[(i1 - 3) * 48 + m] * ~0.11516383427084 + qt[(i1 - 4) * 48 + m] * ~0.03183050093751
          gf[m] = g
          qf[m] = q
          m += 1
      else
        m = 0
        while m < mmax
          gf[m] = gt[(i + hsl) * 48 + m]
          qf[m] = qt[i * 48 + m]
          m += 1
      yb = yo + i * 64 + kx
      m = 0
      while m < mmax
        yr[yb + m] = xhr[(m + kx) * 40 + i + 2] * gf[m]
        yi[yb + m] = xhi[(m + kx) * 40 + i + 2] * gf[m]
        m += 1
      if !trans
        ps0 = ~0.0
        ps1 = ~0.0
        sg = ~1.0
        sg = ~-1.0 if (kx & 1) == 1
        if isine == 0
          ps0 = ~1.0
        elsif isine == 1
          ps1 = sg
        elsif isine == 2
          ps0 = ~-1.0
        else
          ps1 = ~0.0 - sg
        nidx = inoise
        m = 0
        while m < mmax
          nidx = (nidx + 1) & 511
          s = smo[e * 48 + m]
          if s != ~0.0
            yr[yb + m] = yr[yb + m] + s * ps0
            yi[yb + m] = yi[yb + m] + s * ps1
          else
            yr[yb + m] = yr[yb + m] + qf[m] * nz[nidx * 2]
            yi[yb + m] = yi[yb + m] + qf[m] * nz[nidx * 2 + 1]
          ps1 = ~0.0 - ps1
          m += 1
      else
        idx = isine & 1
        a = 1 - ((isine + (kx & 1)) & 2)
        bb = a
        bb = 0 - a if idx == 1
        m = 0
        while m < mmax
          s = smo[e * 48 + m]
          f = a
          f = bb if (m & 1) == 1
          if idx == 0
            yr[yb + m] = yr[yb + m] + s * (f ## f64)
          else
            yi[yb + m] = yi[yb + m] + s * (f ## f64)
          m += 1
      inoise = (inoise + mmax) & 511
      isine = (isine + 1) & 3
      i += 1
    e += 1
  c[8] = inoise
  c[9] = isine
  0

# Build the synthesis input X (slot * 64 + k, 38 slots).
-> sbr_x_gen(xr, xi, xlr, xli, yr, yi, y0, y1, p, told) (f64[] f64[] f64[] f64[] f64[] f64[] i64 i64 i64[] i64) i64
  i = 0
  while i < 38 * 64
    xr[i] = ~0.0
    xi[i] = ~0.0
    i += 1
  it = 2 * told - 32
  it = 0 if it < 0
  kx0 = p[0]
  m0 = p[2]
  kx1 = p[1]
  m1 = p[3]
  k = 0
  while k < kx0
    i = 0
    while i < it
      xr[i * 64 + k] = xlr[k * 40 + i + 2]
      xi[i * 64 + k] = xli[k * 40 + i + 2]
      i += 1
    k += 1
  while k < kx0 + m0
    i = 0
    while i < it
      xr[i * 64 + k] = yr[y0 + (i + 32) * 64 + k]
      xi[i * 64 + k] = yi[y0 + (i + 32) * 64 + k]
      i += 1
    k += 1
  k = 0
  while k < kx1
    i = it
    while i < 38
      xr[i * 64 + k] = xlr[k * 40 + i + 2]
      xi[i * 64 + k] = xli[k * 40 + i + 2]
      i += 1
    k += 1
  while k < kx1 + m1
    i = it
    while i < 32
      xr[i * 64 + k] = yr[y1 + i * 64 + k]
      xi[i * 64 + k] = yi[y1 + i * 64 + k]
      i += 1
    k += 1
  0

-> sbr_copy(dst, src, n) (f64[] f64[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

# ---- per-channel state ----

+ AacSbrCh
  ro :c, :ef, :nf, :bw, :gt, :qt, :xb, :wre, :wim, :yr, :yi, :xr, :xi, :vb, :vs

  -> new
    @c = i64[SBC_SIZE]
    @ef = f64[6 * 48]
    @nf = f64[3 * 5]
    @bw = f64[5]
    @gt = f64[42 * 48]
    @qt = f64[42 * 48]
    @xb = f64[288 + 1024]
    @wre = f64[2048]
    @wim = f64[2048]
    @yr = f64[2 * 38 * 64]
    @yi = f64[2 * 38 * 64]
    @xr = f64[38 * 64]
    @xi = f64[38 * 64]
    @vb = f64[5376]
    @vs = i64[1]
    @vs[0] = 5376 - 1152

# ---- element ----

+ AacSbr
  ro :p, :start, :chs, :ps

  -> new(@rate)
    @p = i64[SBP_SIZE]
    @chs = [AacSbrCh.new, AacSbrCh.new]
    @xlr = f64[32 * 40]
    @xli = f64[32 * 40]
    @xhr = f64[64 * 40]
    @xhi = f64[64 * 40]
    @a0 = f64[128]
    @a1 = f64[128]
    @eo = f64[7 * 48]
    @qm = f64[7 * 48]
    @sm = f64[7 * 48]
    @ec = f64[7 * 48]
    @qmo = f64[7 * 48]
    @smo = f64[7 * 48]
    @gain = f64[7 * 48]
    @sp = [-1, -1, -1, -1, -1, -1]
    @amp_res_hdr = 0
    @lim_bands = 0
    @coupling = 0
    @id = 0
    @ps = nil
    @pushed = false
    @ready = false
    turnoff

  -> ps=(v)
    @ps = v

  -> turnoff
    @start = false
    @ready = false
    @p[SBP_KX1] = 32
    @p[SBP_M1] = 0
    @chs[0].c[SBC_EA1] = -1
    @chs[1].c[SBC_EA1] = -1
    @sp = [-1, -1, -1, -1, -1, -1]

  -> reset
    @p = i64[SBP_SIZE]
    @chs = [AacSbrCh.new, AacSbrCh.new]
    @lim_bands = 0
    @coupling = 0
    @pushed = false
    turnoff
    @ps.reset if @ps != nil

  -> mark_bad
    turnoff

  # ---- bitstream ----

  -> gb(n)
    aac_bits(@bs, @st, n)

  -> huff(t)
    v = aac_huff(@bs, @st, AAC_HT, AAC_HROOT[12 + t])
    aac_fail("aac: bad SBR huffman code") if v < 0
    v + SBR_HUFF_DELTA[t]

  # Read sbr_extension_data (FIL payload after the 4-bit type).
  -> read_data(bs, st, endpos, stereo, dec)
    @bs = bs
    @st = st
    @dec = dec
    p = @p
    p[SBP_RESET] = 0
    p[SBP_KX0] = p[SBP_KX1]
    p[SBP_M0] = p[SBP_M1]
    @pushed = true
    ok = true
    begin
      read_header if gb(1) == 1
      if p[SBP_RESET] != 0
        if !make_tables
          turnoff
      if @start
        @id = 1
        @id = 2 if stereo
        @ready = true
        if stereo
          read_cpe
        else
          read_sce
        if gb(1) == 1
          nb = gb(4)
          nb += gb(8) if nb == 15
          nb = nb * 8
          while nb > 7
            nb -= 2
            ext = gb(2)
            if ext == 2 && !stereo
              ps = dec.ps_found
              if ps != nil
                used = ps.read(@bs, @st, nb)
                nb -= used
              else
                @st[0] = @st[0] + nb
                nb = 0
            else
              @st[0] = @st[0] + nb
              nb = 0
    rescue e
      ok = false
      turnoff
    ok = false if @st[0] > endpos || @st[2] != 0
    turnoff if !ok
    ok

  -> read_header
    p = @p
    @start = true
    @ready = false
    old = @sp
    @amp_res_hdr = gb(1)
    sp = [gb(4), gb(4), gb(3), 0, 0, 0]
    gb(2)
    x1 = gb(1)
    x2 = gb(1)
    if x1 == 1
      sp[3] = gb(2)
      sp[4] = gb(1)
      sp[5] = gb(2)
    else
      sp[3] = 2
      sp[4] = 1
      sp[5] = 2
    @sp = sp
    changed = false
    i = 0
    while i < 6
      changed = true if sp[i] != old[i]
      i += 1
    p[SBP_RESET] = 1 if changed
    oldlim = @lim_bands
    if x2 == 1
      @lim_bands = gb(2)
      p[SBP_LIMGAIN] = gb(2)
      p[SBP_INTERP] = gb(1)
      p[SBP_SMOOTH] = gb(1)
    else
      @lim_bands = 2
      p[SBP_LIMGAIN] = 2
      p[SBP_INTERP] = 1
      p[SBP_SMOOTH] = 1
    make_lim if @lim_bands != oldlim && p[SBP_RESET] == 0

  -> read_grid(ch)
    c = ch.c
    nold = c[SBC_NENV]
    c[SBC_FRES] = c[SBC_FRES + nold]
    c[SBC_AMPRES] = @amp_res_hdr
    c[SBC_TOLD] = c[SBC_TENV + nold]
    trail = 16
    ptr = 0
    cls = gb(2)
    if cls == 0
      ne = 1 << gb(2)
      aac_fail("aac: SBR envelopes") if ne > 5
      c[SBC_NENV] = ne
      c[SBC_AMPRES] = 0 if ne == 1
      c[SBC_TENV] = 0
      c[SBC_TENV + ne] = trail
      step = (trail + (ne >> 1)) / ne
      i = 0
      while i < ne - 1
        c[SBC_TENV + i + 1] = c[SBC_TENV + i] + step
        i += 1
      fr = gb(1)
      i = 1
      while i <= ne
        c[SBC_FRES + i] = fr
        i += 1
    elsif cls == 1
      trail += gb(2)
      nrt = gb(2)
      ne = nrt + 1
      c[SBC_NENV] = ne
      c[SBC_TENV] = 0
      c[SBC_TENV + ne] = trail
      i = nrt
      while i > 0
        c[SBC_TENV + i] = c[SBC_TENV + i + 1] - 2 * gb(2) - 2
        i -= 1
      ptr = gb(sbr_ceil_log2(ne))
      i = 0
      while i < ne
        c[SBC_FRES + ne - i] = gb(1)
        i += 1
    elsif cls == 2
      c[SBC_TENV] = gb(2)
      nrl = gb(2)
      ne = nrl + 1
      c[SBC_NENV] = ne
      c[SBC_TENV + ne] = trail
      i = 0
      while i < nrl
        c[SBC_TENV + i + 1] = c[SBC_TENV + i] + 2 * gb(2) + 2
        i += 1
      ptr = gb(sbr_ceil_log2(ne))
      i = 0
      while i < ne
        c[SBC_FRES + 1 + i] = gb(1)
        i += 1
    else
      c[SBC_TENV] = gb(2)
      trail += gb(2)
      nrl = gb(2)
      nrt = gb(2)
      ne = nrl + nrt + 1
      aac_fail("aac: SBR envelopes") if ne > 5
      c[SBC_NENV] = ne
      c[SBC_TENV + ne] = trail
      i = 0
      while i < nrl
        c[SBC_TENV + i + 1] = c[SBC_TENV + i] + 2 * gb(2) + 2
        i += 1
      i = ne - 1
      while i >= ne - nrt
        c[SBC_TENV + i] = c[SBC_TENV + i + 1] - 2 * gb(2) - 2
        i -= 1
      ptr = gb(sbr_ceil_log2(ne))
      i = 0
      while i < ne
        c[SBC_FRES + 1 + i] = gb(1)
        i += 1
    c[SBC_CLASS] = cls
    ne = c[SBC_NENV]
    aac_fail("aac: SBR bs_pointer") if ptr > ne + 1
    i = 1
    while i <= ne
      aac_fail("aac: SBR time borders") if c[SBC_TENV + i - 1] >= c[SBC_TENV + i]
      i += 1
    nn = 1
    nn = 2 if ne > 1
    c[SBC_NNOISE] = nn
    c[SBC_TQ] = c[SBC_TENV]
    c[SBC_TQ + nn] = c[SBC_TENV + ne]
    if nn > 1
      idx = 0
      if cls == 0
        idx = ne >> 1
      elsif (cls & 1) == 1
        pm = ptr - 1
        pm = 1 if pm < 1
        idx = ne - pm
      else
        if ptr == 0
          idx = 1
        elsif ptr == 1
          idx = ne - 1
        else
          idx = ptr - 1
      c[SBC_TQ + 1] = c[SBC_TENV + idx]
    ea1 = c[SBC_EA1]
    c[SBC_EA0] = 0
    c[SBC_EA0] = -1 if ea1 != nold
    c[SBC_EA1] = -1
    if (cls & 1) == 1 && ptr != 0
      c[SBC_EA1] = ne + 1 - ptr
    elsif cls == 2 && ptr > 1
      c[SBC_EA1] = ptr - 1

  -> copy_grid(dst, src)
    d = dst.c
    s = src.c
    d[SBC_FRES] = d[SBC_FRES + d[SBC_NENV]]
    d[SBC_TOLD] = d[SBC_TENV + d[SBC_NENV]]
    d[SBC_EA0] = 0
    d[SBC_EA0] = -1 if d[SBC_EA1] != d[SBC_NENV]
    i = 1
    while i < 7
      d[SBC_FRES + i] = s[SBC_FRES + i]
      i += 1
    i = 0
    while i < 8
      d[SBC_TENV + i] = s[SBC_TENV + i]
      i += 1
    i = 0
    while i < 3
      d[SBC_TQ + i] = s[SBC_TQ + i]
      i += 1
    d[SBC_NENV] = s[SBC_NENV]
    d[SBC_AMPRES] = s[SBC_AMPRES]
    d[SBC_NNOISE] = s[SBC_NNOISE]
    d[SBC_CLASS] = s[SBC_CLASS]
    d[SBC_EA1] = s[SBC_EA1]

  -> read_dtdf(ch)
    c = ch.c
    i = 0
    while i < c[SBC_NENV]
      c[SBC_DFENV + i] = gb(1)
      i += 1
    i = 0
    while i < c[SBC_NNOISE]
      c[SBC_DFNOISE + i] = gb(1)
      i += 1

  -> read_invf(ch)
    c = ch.c
    i = 0
    while i < 5
      c[SBC_INVF + 5 + i] = c[SBC_INVF + i]
      i += 1
    i = 0
    while i < @p[SBP_NQ]
      c[SBC_INVF + i] = gb(2)
      i += 1

  -> read_envelope(ch, chn)
    c = ch.c
    p = @p
    delta = 1
    delta = 2 if chn == 1 && @coupling == 1
    odd = p[SBP_NHIGH] & 1
    if @coupling == 1 && chn == 1
      if c[SBC_AMPRES] == 1
        bits = 5
        th = 6
        fh = 7
      else
        bits = 6
        th = 2
        fh = 3
    else
      if c[SBC_AMPRES] == 1
        bits = 6
        th = 4
        fh = 5
      else
        bits = 7
        th = 0
        fh = 1
    i = 0
    while i < c[SBC_NENV]
      fr1 = c[SBC_FRES + i + 1]
      fr0 = c[SBC_FRES + i]
      nb = p[SBP_NLOW + fr1]
      cur = SBC_ENVQ + (i + 1) * 48
      prv = SBC_ENVQ + i * 48
      if c[SBC_DFENV + i] == 1
        j = 0
        while j < nb
          k = j
          if fr1 != fr0
            if fr1 == 1
              k = (j + odd) >> 1
            else
              k = 0
              k = 2 * j - odd if j > 0
          v = c[prv + k] + delta * huff(th)
          aac_fail("aac: SBR envelope") if v < 0 || v > 127
          c[cur + j] = v
          j += 1
      else
        c[cur] = delta * gb(bits)
        j = 1
        while j < nb
          v = c[cur + j - 1] + delta * huff(fh)
          aac_fail("aac: SBR envelope") if v < 0 || v > 127
          c[cur + j] = v
          j += 1
      i += 1
    j = 0
    while j < 48
      c[SBC_ENVQ + j] = c[SBC_ENVQ + c[SBC_NENV] * 48 + j]
      j += 1

  -> read_noise(ch, chn)
    c = ch.c
    p = @p
    delta = 1
    delta = 2 if chn == 1 && @coupling == 1
    th = 8
    fh = 5
    if @coupling == 1 && chn == 1
      th = 9
      fh = 7
    i = 0
    while i < c[SBC_NNOISE]
      cur = SBC_NOISEQ + (i + 1) * 5
      prv = SBC_NOISEQ + i * 5
      if c[SBC_DFNOISE + i] == 1
        j = 0
        while j < p[SBP_NQ]
          v = c[prv + j] + delta * huff(th)
          aac_fail("aac: SBR noise") if v < 0 || v > 30
          c[cur + j] = v
          j += 1
      else
        c[cur] = delta * gb(5)
        j = 1
        while j < p[SBP_NQ]
          v = c[cur + j - 1] + delta * huff(fh)
          aac_fail("aac: SBR noise") if v < 0 || v > 30
          c[cur + j] = v
          j += 1
      i += 1
    j = 0
    while j < 5
      c[SBC_NOISEQ + j] = c[SBC_NOISEQ + c[SBC_NNOISE] * 5 + j]
      j += 1

  -> read_harmonic(ch)
    c = ch.c
    c[SBC_HARM] = gb(1)
    if c[SBC_HARM] == 1
      i = 0
      while i < @p[SBP_NHIGH]
        c[SBC_ADDH + i] = gb(1)
        i += 1

  -> read_sce
    gb(4) if gb(1) == 1
    c0 = @chs[0]
    read_grid(c0)
    read_dtdf(c0)
    read_invf(c0)
    read_envelope(c0, 0)
    read_noise(c0, 0)
    read_harmonic(c0)

  -> read_cpe
    gb(8) if gb(1) == 1
    c0 = @chs[0]
    c1 = @chs[1]
    @coupling = gb(1)
    if @coupling == 1
      read_grid(c0)
      copy_grid(c1, c0)
      read_dtdf(c0)
      read_dtdf(c1)
      read_invf(c0)
      i = 0
      while i < 5
        c1.c[SBC_INVF + 5 + i] = c1.c[SBC_INVF + i]
        c1.c[SBC_INVF + i] = c0.c[SBC_INVF + i]
        i += 1
      read_envelope(c0, 0)
      read_noise(c0, 0)
      read_envelope(c1, 1)
      read_noise(c1, 1)
    else
      read_grid(c0)
      read_grid(c1)
      read_dtdf(c0)
      read_dtdf(c1)
      read_invf(c0)
      read_invf(c1)
      read_envelope(c0, 0)
      read_envelope(c1, 1)
      read_noise(c0, 0)
      read_noise(c1, 1)
    read_harmonic(c0)
    read_harmonic(c1)

  # ---- frequency tables ----

  -> make_bands(start, stop, num)
    bands = []
    base = sbr_f32(Math.pow((stop ## f64) / (start ## f64), ~1.0 / (num ## f64)))
    prod = sbr_f32(start ## f64)
    prev = start
    k = 0
    while k < num - 1
      prod = sbr_f32(prod * base)
      pres = sbr_lrint(prod)
      bands.push(pres - prev)
      prev = pres
      k += 1
    bands.push(stop - prev)
    bands

  -> make_tables
    p = @p
    sp = @sp
    sr = @rate
    off = nil
    if sr == 16000
      oi = 0
    elsif sr == 22050
      oi = 1
    elsif sr == 24000
      oi = 2
    elsif sr == 32000
      oi = 3
    elsif sr == 44100 || sr == 48000 || sr == 64000
      oi = 4
    elsif sr == 88200 || sr == 96000 || sr == 128000 || sr == 176400 || sr == 192000
      oi = 5
    else
      return false
    temp = 5000
    temp = 4000 if sr < 64000
    temp = 3000 if sr < 32000
    smin = ((temp << 7) + (sr >> 1)) / sr
    tmin = ((temp << 8) + (sr >> 1)) / sr
    k0 = smin + SBR_OFFSET[oi * 16 + sp[0]]
    if sp[1] < 14
      k2 = tmin
      dk = make_bands(tmin, 64, 13).sort
      k = 0
      while k < sp[1]
        k2 += dk[k]
        k += 1
    elsif sp[1] == 14
      k2 = 2 * k0
    else
      k2 = 3 * k0
    k2 = 64 if k2 > 64
    maxq = 32
    maxq = 48 if sr <= 32000
    maxq = 35 if sr == 44100
    return false if k2 - k0 > maxq || k0 <= 0
    p[SBP_K0] = k0
    p[SBP_K2] = k2
    fm = []
    if sp[3] == 0
      dk = sp[4] + 1
      nm = ((k2 - k0 + (dk & 2)) >> dk) << 1
      return false if nm <= 0 || sp[2] >= nm
      v = [k0]
      k = 1
      while k <= nm
        v.push(dk)
        k += 1
      k2d = k2 - k0 - nm * dk
      if k2d < 0
        v[1] = v[1] - 1
        v[2] = v[2] - 1 if k2d < -1
      elsif k2d > 0
        v[nm] = v[nm] + 1
      k = 1
      while k <= nm
        v[k] = v[k] + v[k - 1]
        k += 1
      fm = v
    else
      hb = 7 - sp[3]
      two = 49 * k2 > 110 * k0
      k1 = k2
      k1 = 2 * k0 if two
      p[SBP_K1] = k1
      r0 = sbr_f32(sbr_f32(k1 ## f64) / sbr_f32(k0 ## f64))
      nb0 = sbr_lrint(sbr_f32((hb ## f64) * sbr_f32(Math.log2(r0)))) * 2
      return false if nb0 <= 0
      vk0 = make_bands(k0, k1, nb0).sort
      vdk0max = vk0[nb0 - 1]
      v = [k0]
      k = 0
      while k < nb0
        return false if vk0[k] <= 0
        v.push(v[k] + vk0[k])
        k += 1
      if two
        iw = ~1.0
        iw = sbr_f32(~0.76923076923076923077) if sp[4] == 1
        r1 = sbr_f32(sbr_f32(k2 ## f64) / sbr_f32(k1 ## f64))
        nb1 = sbr_lrint(sbr_f32(sbr_f32((hb ## f64) * iw) * sbr_f32(Math.log2(r1)))) * 2
        return false if nb1 <= 0
        vk1 = make_bands(k1, k2, nb1)
        mn = vk1.min
        if mn < vdk0max
          vk1 = vk1.sort
          ch = vdk0max - vk1[0]
          h = (vk1[nb1 - 1] - vk1[0]) >> 1
          ch = h if h < ch
          vk1[0] = vk1[0] + ch
          vk1[nb1 - 1] = vk1[nb1 - 1] - ch
        vk1 = vk1.sort
        k = 0
        while k < nb1
          return false if vk1[k] <= 0
          v.push(v[v.size - 1] + vk1[k])
          k += 1
      fm = v
      nm = fm.size - 1
      return false if nm <= 0 || sp[2] >= nm
    return false if nm > 48
    p[SBP_NMASTER] = nm
    k = 0
    while k <= nm
      p[SBP_FMASTER + k] = fm[k]
      k += 1
    # derived tables
    xo = sp[2]
    nh = nm - xo
    nl = (nh + 1) >> 1
    p[SBP_NHIGH] = nh
    p[SBP_NLOW] = nl
    k = 0
    while k <= nh
      p[SBP_FHIGH + k] = fm[xo + k]
      k += 1
    m1 = p[SBP_FHIGH + nh] - p[SBP_FHIGH]
    kx1 = p[SBP_FHIGH]
    return false if kx1 + m1 > 64 || kx1 > 32
    p[SBP_M1] = m1
    p[SBP_KX1] = kx1
    p[SBP_FLOW] = p[SBP_FHIGH]
    t = nh & 1
    k = 1
    while k <= nl
      p[SBP_FLOW + k] = p[SBP_FHIGH + 2 * k - t]
      k += 1
    rq = sbr_f32(sbr_f32(k2 ## f64) / sbr_f32(kx1 ## f64))
    nq = sbr_lrint(sbr_f32((sp[5] ## f64) * sbr_f32(Math.log2(rq))))
    nq = 1 if nq < 1
    if nq > 5
      p[SBP_NQ] = 1
      return false
    p[SBP_NQ] = nq
    p[SBP_FNOISE] = p[SBP_FLOW]
    t = 0
    k = 1
    while k <= nq
      t += (nl - t) / (nq + 1 - k)
      p[SBP_FNOISE + k] = p[SBP_FLOW + t]
      k += 1
    return false if !make_patches
    make_lim
    @chs[0].c[SBC_INOISE] = 0
    @chs[1].c[SBC_INOISE] = 0
    true

  -> make_patches
    p = @p
    lastk = -1
    lastmsb = -1
    sb = 0
    msb = p[SBP_K0]
    usb = p[SBP_KX1]
    goal = ((1000 << 11) + (@rate >> 1)) / @rate
    np = 0
    nm = p[SBP_NMASTER]
    k = nm
    if goal < p[SBP_KX1] + p[SBP_M1]
      k = 0
      k += 1 while p[SBP_FMASTER + k] < goal
    while true
      odd = 0
      return false if k == lastk && msb == lastmsb
      lastk = k
      lastmsb = msb
      i = k
      while i == k || sb > (p[SBP_K0] - 1 + msb - odd)
        sb = p[SBP_FMASTER + i]
        odd = (sb + p[SBP_K0]) & 1
        i -= 1
        break if i < 0
      return false if np > 5
      ns = sb - usb
      ns = 0 if ns < 0
      p[SBP_PNUM + np] = ns
      p[SBP_PSTART + np] = p[SBP_K0] - odd - ns
      if ns > 0
        usb = sb
        msb = sb
        np += 1
      else
        msb = p[SBP_KX1]
      k = nm if p[SBP_FMASTER + k] - sb < 3
      break if sb == p[SBP_KX1] + p[SBP_M1]
    np -= 1 if np > 1 && p[SBP_PNUM + np - 1] < 3
    p[SBP_NPATCH] = np
    true

  -> make_lim
    p = @p
    if @lim_bands > 0
      warped = [~1.32715174233856803909, ~1.18509277094158210129, ~1.11987160404675912501]
      lb = sbr_f32(warped[@lim_bands - 1])
      np = p[SBP_NPATCH]
      pb = [p[SBP_KX1]]
      k = 1
      while k <= np
        pb.push(pb[k - 1] + p[SBP_PNUM + k - 1])
        k += 1
      t = []
      k = 0
      while k <= p[SBP_NLOW]
        t.push(p[SBP_FLOW + k])
        k += 1
      k = 1
      while k < np
        t.push(pb[k])
        k += 1
      # FFmpeg sorts num_patches + n_low entries (leaving the last in place)
      cnt = np + p[SBP_NLOW]
      head = t.slice(0, cnt).sort
      t = head + t.slice(cnt, t.size - cnt)
      nlim = p[SBP_NLOW] + np - 1
      out = 0
      inp = 1
      while out < nlim
        a = t[inp]
        b = t[out]
        if sbr_f32(a ## f64) >= sbr_f32(sbr_f32(b ## f64) * lb)
          out += 1
          t[out] = a
          inp += 1
        elsif a == b || !pb.slice(0, np + 1).include?(a)
          inp += 1
          nlim -= 1
        elsif !pb.slice(0, np + 1).include?(b)
          t[out] = a
          inp += 1
          nlim -= 1
        else
          out += 1
          t[out] = a
          inp += 1
      p[SBP_NLIM] = nlim
      k = 0
      while k <= nlim
        p[SBP_FLIM + k] = t[k]
        k += 1
    else
      p[SBP_FLIM] = p[SBP_FLOW]
      p[SBP_FLIM + 1] = p[SBP_FLOW + p[SBP_NLOW]]
      p[SBP_NLIM] = 1

  # ---- dequantisation ----

  -> dequant
    p = @p
    if @id == 2 && @coupling == 1
      c0 = @chs[0]
      c1 = @chs[1]
      pan = 24
      pan = 12 if c0.c[SBC_AMPRES] == 1
      e = 1
      while e <= c0.c[SBC_NENV]
        nb = p[SBP_NLOW + c0.c[SBC_FRES + e]]
        k = 0
        while k < nb
          q0 = c0.c[SBC_ENVQ + e * 48 + k]
          q1 = c1.c[SBC_ENVQ + e * 48 + k]
          if c0.c[SBC_AMPRES] == 1
            t1 = sbr_exp2(q0 + 7)
            t2 = sbr_exp2(pan - q1)
          else
            t1 = sbr_exp2((q0 >> 1) + 7) * sbr_sq2(q0 & 1)
            t2 = sbr_exp2((pan - q1) >> 1) * sbr_sq2((pan - q1) & 1)
          t1 = ~1.0 if t1 > ~1.0e20
          fac = t1 / (~1.0 + t2)
          c0.ef[e * 48 + k] = fac
          c1.ef[e * 48 + k] = fac * t2
          k += 1
        e += 1
      e = 1
      while e <= c0.c[SBC_NNOISE]
        k = 0
        while k < p[SBP_NQ]
          t1 = sbr_exp2(6 - c0.c[SBC_NOISEQ + e * 5 + k] + 1)
          t2 = sbr_exp2(12 - c1.c[SBC_NOISEQ + e * 5 + k])
          fac = t1 / (~1.0 + t2)
          c0.nf[e * 5 + k] = fac
          c1.nf[e * 5 + k] = fac * t2
          k += 1
        e += 1
    else
      ch = 0
      while ch < @id
        cd = @chs[ch]
        c = cd.c
        e = 1
        while e <= c[SBC_NENV]
          nb = p[SBP_NLOW + c[SBC_FRES + e]]
          k = 0
          while k < nb
            q = c[SBC_ENVQ + e * 48 + k]
            if c[SBC_AMPRES] == 1
              v = sbr_exp2(q + 6)
            else
              v = sbr_exp2((q >> 1) + 6) * sbr_sq2(q & 1)
            v = ~1.0 if v > ~1.0e20
            cd.ef[e * 48 + k] = v
            k += 1
          e += 1
        e = 1
        while e <= c[SBC_NNOISE]
          k = 0
          while k < p[SBP_NQ]
            cd.nf[e * 5 + k] = sbr_exp2(6 - c[SBC_NOISEQ + e * 5 + k])
            k += 1
          e += 1
        ch += 1

  -> chirp(cd)
    c = cd.c
    tab = [~0.0, ~0.75, ~0.9, ~0.98]
    i = 0
    while i < @p[SBP_NQ]
      m0 = c[SBC_INVF + i]
      if m0 + c[SBC_INVF + 5 + i] == 1
        nb = ~0.6
      else
        nb = tab[m0]
      o = cd.bw[i]
      if nb < o
        nb = ~0.75 * nb + ~0.25 * o
      else
        nb = ~0.90625 * nb + ~0.09375 * o
      nb = ~0.0 if nb < ~0.015625
      cd.bw[i] = nb
      i += 1

  # ---- per-frame processing ----

  # pcm0 / pcm1: 1024 core samples in, 2048 output samples out (in place,
  # pcm arrays have room for 2048). nch: 1 or 2. With ps (mono element),
  # pcm1 receives the right channel.
  -> process(pcm0, pcm1, nch, ps)
    p = @p
    if @start && !@ready
      turnoff
    if !@pushed
      p[SBP_KX0] = p[SBP_KX1]
      p[SBP_M0] = p[SBP_M1]
    else
      @pushed = false
    if @start
      dequant
      @ready = false
    ch = 0
    while ch < nch
      cd = @chs[ch]
      c = cd.c
      pcm = pcm0
      pcm = pcm1 if ch == 1
      ypos = c[SBC_YPOS]
      sbr_qmf_ana(pcm, cd.xb, cd.wre, cd.wim, ypos * 1024, SBR_WIN, SBR_AC, SBR_AS)
      sbr_lf_gen(@xlr, @xli, cd.wre, cd.wim, ypos * 1024, (1 - ypos) * 1024, p[SBP_KX1], p[SBP_KX0])
      ypos = 1 - ypos
      c[SBC_YPOS] = ypos
      if @start
        sbr_inv_filter(@xlr, @xli, @a0, @a1, p[SBP_K0])
        chirp(cd)
        r = sbr_hf_gen(@xhr, @xhi, @xlr, @xli, @a0, @a1, cd.bw, p, c)
        if r == 0
          r = sbr_mapping(p, c, cd.ef, cd.nf, @eo, @qm, @sm)
          if r == 0
            sbr_env_estimate(@ec, @xhr, @xhi, p, c)
            sbr_gain_calc(p, c, @eo, @qm, @sm, @ec, @qmo, @smo, @gain)
            sbr_hf_assemble(cd.yr, cd.yi, ypos * 2432, @xhr, @xhi, p, c, cd.gt, cd.qt, @gain, @qmo, @smo, SBR_NZ)
          else
            turnoff
      sbr_x_gen(cd.xr, cd.xi, @xlr, @xli, cd.yr, cd.yi, (1 - ypos) * 2432, ypos * 2432, p, c[SBC_TOLD])
      ch += 1
    if ps != nil
      c1 = @chs[1]
      if ps.started
        ps.apply(@chs[0].xr, @chs[0].xi, c1.xr, c1.xi, p[SBP_KX1] + p[SBP_M1])
      else
        sbr_copy(c1.xr, @chs[0].xr, 38 * 64)
        sbr_copy(c1.xi, @chs[0].xi, 38 * 64)
      nch = 2
    sbr_qmf_syn(@chs[0].xr, @chs[0].xi, @chs[0].vb, @chs[0].vs, pcm0, SBR_WIN, SBR_SC, SBR_SS)
    if nch == 2
      sbr_qmf_syn(@chs[1].xr, @chs[1].xi, @chs[1].vb, @chs[1].vs, pcm1, SBR_WIN, SBR_SC, SBR_SS)

-> sbr_ceil_log2(n)
  [0, 1, 2, 2, 3, 3][n]

-> sbr_exp2(x)
  return ~0.0 if x < -149
  Math.pow(~2.0, x ## f64)

-> sbr_sq2(b)
  return ~1.4142135623730951 if b == 1
  ~1.0
