# core/codec/audio/aac_ps — Parametric Stereo (HE-AAC v2, ISO/IEC 14496-3 8.6.4) for
# core/codec/audio/aac. Runs in the QMF domain of the SBR decoder: the mono SBR signal
# L (38 slots x 64 bands, slot * 64 + k) is split into hybrid sub-subbands
# (10/20 or 20/34 band layouts), decorrelated (fractional-delay all-pass
# chain with transient attenuation), mixed into L/R by the IID / ICC (and
# IPD / OPD) parameters with per-envelope interpolation, and recombined.
# Follows the reference decoder flow as FFmpeg implements it (non-baseline:
# IPD/OPD and the 34-band mode are supported).

AAC_PS_PI = ~3.141592653589793

PS_NUM_ENV_TAB = [[0, 1, 2, 4], [1, 2, 3, 4]]
PS_NR_IIDICC = [10, 20, 34, 10, 20, 34]
PS_NR_IPDOPD = [5, 11, 17, 5, 11, 17]
PS_HUFF_IID = [2, 0, 3, 1]
PS_NR_PAR_BANDS = [20, 34]
PS_NR_IPDOPD_BANDS = [11, 17]
PS_NR_BANDS = [71, 91]
PS_DECAY_CUTOFF = [10, 32]
PS_NR_ALLPASS = [30, 50]
PS_SHORT_DELAY = [42, 62]

-> ps_build_tables
  ipd_sin = [~0.0, ~0.7071067811865476, ~1.0, ~0.7071067811865476, ~0.0, ~-0.7071067811865476, ~-1.0, ~-0.7071067811865476]
  ipd_cos = [~1.0, ~0.7071067811865476, ~0.0, ~-0.7071067811865476, ~-1.0, ~-0.7071067811865476, ~0.0, ~0.7071067811865476]
  pdre = f64[512]
  pdim = f64[512]
  a = 0
  while a < 8
    b = 0
    while b < 8
      cc = 0
      while cc < 8
        re = ~0.25 * ipd_cos[a] + ~0.5 * ipd_cos[b] + ipd_cos[cc]
        im = ~0.25 * ipd_sin[a] + ~0.5 * ipd_sin[b] + ipd_sin[cc]
        mag = ~1.0 / Math.sqrt(re * re + im * im)
        pdre[a * 64 + b * 8 + cc] = re * mag
        pdim[a * 64 + b * 8 + cc] = im * mag
        cc += 1
      b += 1
    a += 1
  iidq = [~0.05623413251903, ~0.12589254117942, ~0.19952623149689, ~0.31622776601684, ~0.44668359215096, ~0.63095734448019, ~0.79432823472428, ~1.0, ~1.25892541179417, ~1.58489319246111, ~2.23872113856834, ~3.16227766016838, ~5.01187233627272, ~7.94328234724282, ~17.7827941003892, ~0.00316227766017, ~0.00562341325190, ~0.01, ~0.01778279410039, ~0.03162277660168, ~0.05623413251903, ~0.07943282347243, ~0.11220184543020, ~0.15848931924611, ~0.22387211385683, ~0.31622776601684, ~0.39810717055350, ~0.50118723362727, ~0.63095734448019, ~0.79432823472428, ~1.0, ~1.25892541179417, ~1.58489319246111, ~1.99526231496888, ~2.51188643150958, ~3.16227766016838, ~4.46683592150963, ~6.30957344480193, ~8.91250938133745, ~12.5892541179417, ~17.7827941003892, ~31.6227766016838, ~56.2341325190349, ~100.0, ~177.827941003892, ~316.227766016837]
  icc_invq = [~1.0, ~0.937, ~0.84118, ~0.60092, ~0.36764, ~0.0, ~-0.589, ~-1.0]
  acos_icc = [~0.0, ~0.35685527, ~0.57133466, ~0.92614472, ~1.1943263, AAC_PS_PI / ~2.0, ~2.2006171, AAC_PS_PI]
  ha = f64[46 * 8 * 4]
  hb = f64[46 * 8 * 4]
  sq2 = ~1.4142135623730951
  iid = 0
  while iid < 46
    c = iidq[iid]
    c1 = sq2 / Math.sqrt(~1.0 + c * c)
    c2 = c * c1
    icc = 0
    while icc < 8
      o = (iid * 8 + icc) * 4
      al = ~0.5 * acos_icc[icc]
      be = al * (c1 - c2) * ~0.7071067811865476
      ha[o] = c2 * Math.cos(be + al)
      ha[o + 1] = c1 * Math.cos(be - al)
      ha[o + 2] = c2 * Math.sin(be + al)
      ha[o + 3] = c1 * Math.sin(be - al)
      rho = icc_invq[icc]
      rho = ~0.05 if rho < ~0.05
      alpha = ~0.5 * Math.atan2(~2.0 * c * rho, c * c - ~1.0)
      mu = c + ~1.0 / c
      mu = Math.sqrt(~1.0 + (~4.0 * rho * rho - ~4.0) / (mu * mu))
      gamma = Math.atan(Math.sqrt((~1.0 - mu) / (~1.0 + mu)))
      alpha += AAC_PS_PI / ~2.0 if alpha < ~0.0
      hb[o] = sq2 * Math.cos(alpha) * Math.cos(gamma)
      hb[o + 1] = sq2 * Math.sin(alpha) * Math.cos(gamma)
      hb[o + 2] = ~0.0 - sq2 * Math.sin(alpha) * Math.sin(gamma)
      hb[o + 3] = sq2 * Math.cos(alpha) * Math.sin(gamma)
      icc += 1
    iid += 1
  fc20 = [-3, -1, 1, 3, 5, 7, 10, 14, 18, 22]
  fc34 = [2, 6, 10, 14, 18, 22, 26, 30, 34, -10, -6, -2, 51, 57, 15, 21, 27, 33, 39, 45, 54, 66, 78, 42, 102, 66, 78, 90, 102, 114, 126, 90]
  links = [~0.43, ~0.75, ~0.347]
  # qf: [is34][k][m] complex at ((is34 * 50 + k) * 3 + m) * 2; pf: (is34 * 50 + k) * 2
  qf = f64[2 * 50 * 3 * 2]
  pf = f64[2 * 50 * 2]
  s = 0
  while s < 2
    nk = 30
    nk = 50 if s == 1
    k = 0
    while k < nk
      if s == 0
        fcen = ~-6.5 + (k ## f64)
        fcen = (fc20[k] ## f64) * ~0.125 if k < 10
      else
        fcen = ~-26.5 + (k ## f64)
        fcen = (fc34[k] ## f64) / ~24.0 if k < 32
      m = 0
      while m < 3
        th = ~0.0 - AAC_PS_PI * sbr_f32(links[m]) * fcen
        qf[((s * 50 + k) * 3 + m) * 2] = Math.cos(th)
        qf[((s * 50 + k) * 3 + m) * 2 + 1] = Math.sin(th)
        m += 1
      th = ~0.0 - AAC_PS_PI * sbr_f32(~0.39) * fcen
      pf[(s * 50 + k) * 2] = Math.cos(th)
      pf[(s * 50 + k) * 2 + 1] = Math.sin(th)
      k += 1
    s += 1
  g0q8 = [~0.00746082949812, ~0.02270420949825, ~0.04546865930473, ~0.07266113929591, ~0.09885108575264, ~0.11793710567217, ~0.125]
  g0q12 = [~0.04081179924692, ~0.03812810994926, ~0.05144908135699, ~0.06399831151592, ~0.07428313801106, ~0.08100347892914, ~0.08333333333333]
  g1q8 = [~0.01565675600122, ~0.03752716391991, ~0.05417891378782, ~0.08417044116767, ~0.10307344158036, ~0.12222452249753, ~0.125]
  g2q4 = [~-0.05908211155639, ~-0.04871498374946, ~0.0, ~0.07778723915851, ~0.16486303567403, ~0.23279856662996, ~0.25]
  # filters [q][n] complex at (q * 8 + n) * 2
  f20 = ps_filters(g0q8, 8)
  f34a = ps_filters(g0q12, 12)
  f34b = ps_filters(g1q8, 8)
  f34c = ps_filters(g2q4, 4)
  [pdre, pdim, ha, hb, qf, pf, f20, f34a, f34b, f34c]

-> ps_filters(proto, bands)
  f = f64[bands * 16]
  q = 0
  while q < bands
    n = 0
    while n < 7
      th = ~2.0 * AAC_PS_PI * ((q ## f64) + ~0.5) * ((n - 6) ## f64) / (bands ## f64)
      p = sbr_f32(proto[n])
      f[(q * 8 + n) * 2] = p * Math.cos(th)
      f[(q * 8 + n) * 2 + 1] = p * (~0.0 - Math.sin(th))
      n += 1
    q += 1
  f

PS_T = ps_build_tables()
PS_PDRE = PS_T[0]
PS_PDIM = PS_T[1]
PS_HA = PS_T[2]
PS_HB = PS_T[3]
PS_QF = PS_T[4]
PS_PF = PS_T[5]
PS_F20 = PS_T[6]
PS_F34A = PS_T[7]
PS_F34B = PS_T[8]
PS_F34C = PS_T[9]
PS_G1Q2 = aac_f64s([~0.0, ~0.01899487526049, ~0.0, ~-0.07293139167538, ~0.0, ~0.30596630545168, ~0.5])
PS_KI20 = aac_i64s(PS_K_TO_I_20)
PS_KI34 = aac_i64s(PS_K_TO_I_34)

# ---- DSP ----

# Complex hybrid filter: input band (re/im) at ib (44 slots), n filters of
# table f; output out[(ob + q) * 32 + i] for i < 32.
-> ps_hyb_cx(inr, ini, ib, f, n, outr, outi, ob) (f64[] f64[] i64 f64[] i64 f64[] f64[] i64) i64
  i = 0
  while i < 32
    o = ib + i
    q = 0
    while q < n
      fo = q * 16
      sr = f[fo + 12] * inr[o + 6]
      si = f[fo + 12] * ini[o + 6]
      j = 0
      while j < 6
        re0 = inr[o + j] + inr[o + 12 - j]
        re1 = ini[o + j] - ini[o + 12 - j]
        im0 = ini[o + j] + ini[o + 12 - j]
        im1 = inr[o + j] - inr[o + 12 - j]
        sr += f[fo + j * 2] * re0 - f[fo + j * 2 + 1] * re1
        si += f[fo + j * 2] * im0 + f[fo + j * 2 + 1] * im1
        j += 1
      outr[(ob + q) * 32 + i] = sr
      outi[(ob + q) * 32 + i] = si
      q += 1
    i += 1
  0

# 20-band mode: first QMF band into 6 sub-subbands (8 filters combined).
-> ps_hyb6(inr, ini, f, outr, outi, tr, ti) (f64[] f64[] f64[] f64[] f64[] f64[] f64[]) i64
  ps_hyb_cx(inr, ini, 0, f, 8, tr, ti, 0)
  i = 0
  while i < 32
    outr[i] = tr[6 * 32 + i]
    outi[i] = ti[6 * 32 + i]
    outr[32 + i] = tr[7 * 32 + i]
    outi[32 + i] = ti[7 * 32 + i]
    outr[64 + i] = tr[i]
    outi[64 + i] = ti[i]
    outr[96 + i] = tr[32 + i]
    outi[96 + i] = ti[32 + i]
    outr[128 + i] = tr[64 + i] + tr[160 + i]
    outi[128 + i] = ti[64 + i] + ti[160 + i]
    outr[160 + i] = tr[96 + i] + tr[128 + i]
    outi[160 + i] = ti[96 + i] + ti[128 + i]
    i += 1
  0

-> ps_hyb2(inr, ini, ib, g, outr, outi, ob, rev) (f64[] f64[] i64 f64[] f64[] f64[] i64 i64) i64
  i = 0
  while i < 32
    o = ib + i
    rin = g[6] * inr[o + 6]
    iin = g[6] * ini[o + 6]
    rop = ~0.0
    iop = ~0.0
    j = 0
    while j < 6
      rop += g[j + 1] * (inr[o + j + 1] + inr[o + 12 - j - 1])
      iop += g[j + 1] * (ini[o + j + 1] + ini[o + 12 - j - 1])
      j += 2
    a = ob + rev
    b = ob + 1 - rev
    outr[a * 32 + i] = rin + rop
    outi[a * 32 + i] = iin + iop
    outr[b * 32 + i] = rin - rop
    outi[b * 32 + i] = iin - iop
    i += 1
  0

# Load in_buf from L and interleave the untouched QMF bands.
-> ps_hyb_in(lr, li, inr, ini, outr, outi, first, ob) (f64[] f64[] f64[] f64[] f64[] f64[] i64 i64) i64
  i = 0
  while i < 5
    j = 0
    while j < 38
      inr[i * 44 + j + 6] = lr[j * 64 + i]
      ini[i * 44 + j + 6] = li[j * 64 + i]
      j += 1
    i += 1
  i = first
  while i < 64
    j = 0
    while j < 32
      outr[(ob + i) * 32 + j] = lr[j * 64 + i]
      outi[(ob + i) * 32 + j] = li[j * 64 + i]
      j += 1
    i += 1
  0

-> ps_hyb_shift(inr, ini) (f64[] f64[]) i64
  i = 0
  while i < 5
    j = 0
    while j < 6
      inr[i * 44 + j] = inr[i * 44 + 32 + j]
      ini[i * 44 + j] = ini[i * 44 + 32 + j]
      j += 1
    i += 1
  0

-> ps_hyb_syn(outr, outi, inr, ini, is34) (f64[] f64[] f64[] f64[] i64) i64
  n = 0
  while n < 32
    o = n * 64
    if is34 == 1
      a = ~0.0
      b = ~0.0
      i = 0
      while i < 12
        a += inr[i * 32 + n]
        b += ini[i * 32 + n]
        i += 1
      outr[o] = a
      outi[o] = b
      a = ~0.0
      b = ~0.0
      i = 12
      while i < 20
        a += inr[i * 32 + n]
        b += ini[i * 32 + n]
        i += 1
      outr[o + 1] = a
      outi[o + 1] = b
      q = 0
      while q < 3
        a = ~0.0
        b = ~0.0
        i = 20 + q * 4
        while i < 24 + q * 4
          a += inr[i * 32 + n]
          b += ini[i * 32 + n]
          i += 1
        outr[o + 2 + q] = a
        outi[o + 2 + q] = b
        q += 1
      i = 5
      while i < 64
        outr[o + i] = inr[(27 + i) * 32 + n]
        outi[o + i] = ini[(27 + i) * 32 + n]
        i += 1
    else
      a = ~0.0
      b = ~0.0
      i = 0
      while i < 6
        a += inr[i * 32 + n]
        b += ini[i * 32 + n]
        i += 1
      outr[o] = a
      outi[o] = b
      outr[o + 1] = inr[6 * 32 + n] + inr[7 * 32 + n]
      outi[o + 1] = ini[6 * 32 + n] + ini[7 * 32 + n]
      outr[o + 2] = inr[8 * 32 + n] + inr[9 * 32 + n]
      outi[o + 2] = ini[8 * 32 + n] + ini[9 * 32 + n]
      i = 3
      while i < 64
        outr[o + i] = inr[(7 + i) * 32 + n]
        outi[o + i] = ini[(7 + i) * 32 + n]
        i += 1
    n += 1
  0

# Decorrelation: s (Lbuf) -> out (Rbuf). st: [peak_decay_nrg 34,
# power_smooth 34, peak_decay_diff_smooth 34]; dl: delay (91 x 46 complex
# re/im split), ap: all-pass delays (50 x 3 x 37).
-> ps_decorrelate(sr, si, outr, outi, is34, ki, st, dlr, dli, apr, api, qf, pf, pw, tg) (f64[] f64[] f64[] f64[] i64 i64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[]) i64
  nb = 71
  nb = 91 if is34 == 1
  npar = 20
  npar = 34 if is34 == 1
  nap = 30
  nap = 50 if is34 == 1
  cut = 10
  cut = 32 if is34 == 1
  sdb = 42
  sdb = 62 if is34 == 1
  i = 0
  while i < 34 * 32
    pw[i] = ~0.0
    i += 1
  k = 0
  while k < nb
    b = ki[k]
    n = 0
    while n < 32
      x = sr[k * 32 + n]
      y = si[k * 32 + n]
      pw[b * 32 + n] = pw[b * 32 + n] + x * x + y * y
      n += 1
    k += 1
  i = 0
  while i < npar
    n = 0
    while n < 32
      dp = ~0.76592833836465 * st[i]
      p = pw[i * 32 + n]
      st[i] = dp
      st[i] = p if p > dp
      st[34 + i] = st[34 + i] + ~0.25 * (p - st[34 + i])
      st[68 + i] = st[68 + i] + ~0.25 * (st[i] - p - st[68 + i])
      den = ~1.5 * st[68 + i]
      g = ~1.0
      g = st[34 + i] / den if den > st[34 + i]
      tg[i * 32 + n] = g
      n += 1
    i += 1
  k = 0
  while k < nb
    # shift the delay line and append this frame
    o = k * 46
    j = 0
    while j < 14
      dlr[o + j] = dlr[o + 32 + j]
      dli[o + j] = dli[o + 32 + j]
      j += 1
    j = 0
    while j < 32
      dlr[o + 14 + j] = sr[k * 32 + j]
      dli[o + 14 + j] = si[k * 32 + j]
      j += 1
    b = ki[k]
    if k < nap
      gds = ~1.0 - ~0.05 * ((k - cut) ## f64)
      gds = ~0.0 if gds < ~0.0
      gds = ~1.0 if gds > ~1.0
      m = 0
      while m < 3
        ao = (k * 3 + m) * 37
        j = 0
        while j < 5
          apr[ao + j] = apr[ao + 32 + j]
          api[ao + j] = api[ao + 32 + j]
          j += 1
        m += 1
      ag0 = ~0.65143905753106 * gds
      ag1 = ~0.56471812200776 * gds
      ag2 = ~0.48954165955695 * gds
      po = (is34 * 50 + k) * 2
      phr = pf[po]
      phi = pf[po + 1]
      qo = (is34 * 50 + k) * 6
      n = 0
      while n < 32
        dr = dlr[o + 12 + n]
        di = dli[o + 12 + n]
        inr = dr * phr - di * phi
        ini = dr * phi + di * phr
        m = 0
        while m < 3
          ag = ag0
          ag = ag1 if m == 1
          ag = ag2 if m == 2
          ao = (k * 3 + m) * 37
          ar = ag * inr
          ai = ag * ini
          lr = apr[ao + n + 2 - m]
          li = api[ao + n + 2 - m]
          fr = qf[qo + m * 2]
          fi = qf[qo + m * 2 + 1]
          pr = inr
          pi = ini
          inr = lr * fr - li * fi - ar
          ini = lr * fi + li * fr - ai
          apr[ao + n + 5] = pr + ag * inr
          api[ao + n + 5] = pi + ag * ini
          m += 1
        g = tg[b * 32 + n]
        outr[k * 32 + n] = g * inr
        outi[k * 32 + n] = g * ini
        n += 1
    else
      d = 1
      d = 14 if k < sdb
      n = 0
      while n < 32
        g = tg[b * 32 + n]
        outr[k * 32 + n] = dlr[o + 14 - d + n] * g
        outi[k * 32 + n] = dli[o + 14 - d + n] * g
        n += 1
    k += 1
  0

-> ps_interp(lr, li, rr, ri, k, start, stop, h, hs, ipd) (f64[] f64[] f64[] f64[] i64 i64 i64 f64[] f64[] i64) i64
  h0 = h[0]
  h1 = h[1]
  h2 = h[2]
  h3 = h[3]
  g0 = h[4]
  g1 = h[5]
  g2 = h[6]
  g3 = h[7]
  n = start + 1
  while n <= stop
    o = k * 32 + n
    a = lr[o]
    b = li[o]
    c = rr[o]
    d = ri[o]
    h0 += hs[0]
    h1 += hs[1]
    h2 += hs[2]
    h3 += hs[3]
    if ipd == 1
      g0 += hs[4]
      g1 += hs[5]
      g2 += hs[6]
      g3 += hs[7]
      lr[o] = h0 * a + h2 * c - g0 * b - g2 * d
      li[o] = h0 * b + h2 * d + g0 * a + g2 * c
      rr[o] = h1 * a + h3 * c - g1 * b - g3 * d
      ri[o] = h1 * b + h3 * d + g1 * a + g3 * c
    else
      lr[o] = h0 * a + h2 * c
      li[o] = h0 * b + h2 * d
      rr[o] = h1 * a + h3 * c
      ri[o] = h1 * b + h3 * d
    n += 1
  0

-> ps_zero(a, from, to) (f64[] i64 i64) i64
  i = from
  while i < to
    a[i] = ~0.0
    i += 1
  0

+ AacPs
  ro :started

  -> new
    @started = false
    @num_env = 0
    @num_env_old = 0
    @enable_iid = 0
    @enable_icc = 0
    @enable_ext = 0
    @enable_ipdopd = 0
    @iid_quant = 0
    @nr_iid = 0
    @nr_icc = 0
    @nr_ipdopd = 0
    @icc_mode = 0
    @is34 = 0
    @is34_old = 0
    @border = [0, 0, 0, 0, 0, 0, 0]
    @iid = i64[5 * 34]
    @icc = i64[5 * 34]
    @ipd = i64[5 * 34]
    @opd = i64[5 * 34]
    @inr = f64[5 * 44]
    @ini = f64[5 * 44]
    @dlr = f64[91 * 46]
    @dli = f64[91 * 46]
    @apr = f64[50 * 3 * 37]
    @api = f64[50 * 3 * 37]
    @st = f64[34 * 3]
    @h = f64[4 * 2 * 6 * 34]
    @lbr = f64[91 * 32]
    @lbi = f64[91 * 32]
    @rbr = f64[91 * 32]
    @rbi = f64[91 * 32]
    @tr = f64[8 * 32]
    @ti = f64[8 * 32]
    @pw = f64[34 * 32]
    @tg = f64[34 * 32]
    @opd_hist = i64[34]
    @ipd_hist = i64[34]
    @hh = f64[8]
    @hs = f64[8]

  -> reset
    initialize_state

  -> initialize_state
    @started = false
    @num_env = 0
    @num_env_old = 0
    @is34 = 0
    @is34_old = 0
    ps_zero(@inr, 0, @inr.size)
    ps_zero(@ini, 0, @ini.size)
    ps_zero(@dlr, 0, @dlr.size)
    ps_zero(@dli, 0, @dli.size)
    ps_zero(@apr, 0, @apr.size)
    ps_zero(@api, 0, @api.size)
    ps_zero(@st, 0, @st.size)
    ps_zero(@h, 0, @h.size)
    i = 0
    while i < 34
      @opd_hist[i] = 0
      @ipd_hist[i] = 0
      i += 1

  -> gb(n)
    aac_bits(@bs, @bst, n)

  -> huff(t)
    v = aac_huff(@bs, @bst, AAC_HT, AAC_HROOT[22 + t])
    aac_fail("aac: bad PS huffman code") if v < 0
    v + PS_HUFF_DELTA[t]

  -> read_par(par, num, table, e, dt, mask, kind)
    if dt == 1
      ep = @num_env_old - 1
      ep = e - 1 if e > 0
      ep = 0 if ep < 0
      b = 0
      while b < num
        v = par[ep * 34 + b] + huff(table)
        v = v & mask if mask != 0
        par[e * 34 + b] = v
        par_check(v, kind)
        b += 1
    else
      v = 0
      b = 0
      while b < num
        v += huff(table)
        v = v & mask if mask != 0
        par[e * 34 + b] = v
        par_check(v, kind)
        b += 1

  -> par_check(v, kind)
    if kind == 0
      lim = 7 + 8 * @iid_quant
      aac_fail("aac: PS iid") if v > lim || v < 0 - lim
    elsif kind == 1
      aac_fail("aac: PS icc") if v < 0 || v > 7

  -> read_ext(id)
    return 0 if id != 0
    p0 = @bst[0]
    @enable_ipdopd = gb(1)
    if @enable_ipdopd == 1
      e = 0
      while e < @num_env
        dt = gb(1)
        read_par(@ipd, @nr_ipdopd, 6 + dt, e, dt, 7, 2)
        dt = gb(1)
        read_par(@opd, @nr_ipdopd, 8 + dt, e, dt, 7, 2)
        e += 1
    gb(1)
    @bst[0] - p0

  # Parse ps_data; returns the bits consumed (bits_left on error).
  -> read(bs, st, bits_left)
    @bs = bs
    @bst = st
    p0 = st[0]
    begin
      header = gb(1)
      if header == 1
        @enable_iid = gb(1)
        if @enable_iid == 1
          mode = gb(3)
          aac_fail("aac: PS iid mode") if mode > 5
          @nr_iid = PS_NR_IIDICC[mode]
          @iid_quant = 0
          @iid_quant = 1 if mode > 2
          @nr_ipdopd = PS_NR_IPDOPD[mode]
        @enable_icc = gb(1)
        if @enable_icc == 1
          @icc_mode = gb(3)
          aac_fail("aac: PS icc mode") if @icc_mode > 5
          @nr_icc = PS_NR_IIDICC[@icc_mode]
        @enable_ext = gb(1)
      fc = gb(1)
      @num_env_old = @num_env
      @num_env = PS_NUM_ENV_TAB[fc][gb(2)]
      @border[0] = -1
      if fc == 1
        e = 1
        while e <= @num_env
          @border[e] = gb(5)
          aac_fail("aac: PS borders") if @border[e] < @border[e - 1]
          e += 1
      else
        lg = [0, 0, 1, 1, 2][@num_env]
        e = 1
        while e <= @num_env
          @border[e] = ((e * 32) >> lg) - 1
          e += 1
      if @enable_iid == 1
        e = 0
        while e < @num_env
          dt = gb(1)
          read_par(@iid, @nr_iid, PS_HUFF_IID[2 * dt + @iid_quant], e, dt, 0, 0)
          e += 1
      else
        ps_ifill(@iid, 0)
      if @enable_icc == 1
        e = 0
        while e < @num_env
          dt = gb(1)
          read_par(@icc, @nr_icc, 4 + dt, e, dt, 0, 1)
          e += 1
      else
        ps_ifill(@icc, 0)
      if @enable_ext == 1
        cnt = gb(4)
        cnt += gb(8) if cnt == 15
        cnt = cnt * 8
        while cnt > 7
          id = gb(2)
          cnt -= 2 + read_ext(id)
        aac_fail("aac: PS extension") if cnt < 0
        st[0] = st[0] + cnt
      ne = @num_env
      if ne == 0 || @border[ne] < 31
        src = @num_env_old - 1
        src = ne - 1 if ne > 0
        if src >= 0 && src != ne
          b = 0
          while b < 34
            @iid[ne * 34 + b] = @iid[src * 34 + b] if @enable_iid == 1
            @icc[ne * 34 + b] = @icc[src * 34 + b] if @enable_icc == 1
            if @enable_ipdopd == 1
              @ipd[ne * 34 + b] = @ipd[src * 34 + b]
              @opd[ne * 34 + b] = @opd[src * 34 + b]
            b += 1
        if @enable_iid == 1
          b = 0
          while b < @nr_iid
            par_check(@iid[ne * 34 + b], 0)
            b += 1
        if @enable_icc == 1
          b = 0
          while b < @nr_iid
            par_check(@icc[ne * 34 + b], 1)
            b += 1
        @num_env = ne + 1
        @border[@num_env] = 31
      @is34_old = @is34
      if @enable_iid == 1 || @enable_icc == 1
        @is34 = 0
        @is34 = 1 if (@enable_iid == 1 && @nr_iid == 34) || (@enable_icc == 1 && @nr_icc == 34)
      if @enable_ipdopd != 1
        ps_ifill(@ipd, 0)
        ps_ifill(@opd, 0)
      @started = true if header == 1
      used = st[0] - p0
      return used if used <= bits_left && st[2] == 0
    rescue e
      0
    @started = false
    st[0] = p0 + bits_left
    ps_ifill(@iid, 0)
    ps_ifill(@icc, 0)
    ps_ifill(@ipd, 0)
    ps_ifill(@opd, 0)
    bits_left

  # ---- parameter remapping (Tables 8.46 ff.) ----

  -> map_20(par, e, num, full)
    o = e * 34
    r = []
    34.times -> r.push(0)
    if num == 34 || num == 17
      p = ->(i) par[o + i]
      r[0] = (2 * p.call(0) + p.call(1)) / 3
      r[1] = (p.call(1) + 2 * p.call(2)) / 3
      r[2] = (2 * p.call(3) + p.call(4)) / 3
      r[3] = (p.call(4) + 2 * p.call(5)) / 3
      r[4] = (p.call(6) + p.call(7)) / 2
      r[5] = (p.call(8) + p.call(9)) / 2
      r[6] = p.call(10)
      r[7] = p.call(11)
      r[8] = (p.call(12) + p.call(13)) / 2
      r[9] = (p.call(14) + p.call(15)) / 2
      r[10] = p.call(16)
      if full
        r[11] = p.call(17)
        r[12] = p.call(18)
        r[13] = p.call(19)
        r[14] = (p.call(20) + p.call(21)) / 2
        r[15] = (p.call(22) + p.call(23)) / 2
        r[16] = (p.call(24) + p.call(25)) / 2
        r[17] = (p.call(26) + p.call(27)) / 2
        r[18] = (p.call(28) + p.call(29) + p.call(30) + p.call(31)) / 4
        r[19] = (p.call(32) + p.call(33)) / 2
    elsif num == 10 || num == 5
      b = 4
      b = 9 if full
      r[10] = 0 if !full
      while b >= 0
        r[2 * b] = par[o + b]
        r[2 * b + 1] = par[o + b]
        b -= 1
    else
      i = 0
      while i < 34
        r[i] = par[o + i]
        i += 1
    r

  -> map_34(par, e, num, full)
    o = e * 34
    r = []
    34.times -> r.push(0)
    if num == 20 || num == 11
      p = ->(i) par[o + i]
      if full
        r[33] = p.call(19)
        r[32] = p.call(19)
        r[31] = p.call(18)
        r[30] = p.call(18)
        r[29] = p.call(18)
        r[28] = p.call(18)
        r[27] = p.call(17)
        r[26] = p.call(17)
        r[25] = p.call(16)
        r[24] = p.call(16)
        r[23] = p.call(15)
        r[22] = p.call(15)
        r[21] = p.call(14)
        r[20] = p.call(14)
        r[19] = p.call(13)
        r[18] = p.call(12)
        r[17] = p.call(11)
      r[16] = p.call(10)
      r[15] = p.call(9)
      r[14] = p.call(9)
      r[13] = p.call(8)
      r[12] = p.call(8)
      r[11] = p.call(7)
      r[10] = p.call(6)
      r[9] = p.call(5)
      r[8] = p.call(5)
      r[7] = p.call(4)
      r[6] = p.call(4)
      r[5] = p.call(3)
      r[4] = (p.call(2) + p.call(3)) / 2
      r[3] = p.call(2)
      r[2] = p.call(1)
      r[1] = (p.call(0) + p.call(1)) / 2
      r[0] = p.call(0)
    elsif num == 10 || num == 5
      if full
        [33, 32, 31, 30, 29, 28].each ->(i) r[i] = par[o + 9]
        [27, 26, 25, 24].each ->(i) r[i] = par[o + 8]
        [23, 22, 21, 20].each ->(i) r[i] = par[o + 7]
        r[19] = par[o + 6]
        r[18] = par[o + 6]
        r[17] = par[o + 5]
        r[16] = par[o + 5]
      else
        r[16] = 0
      [15, 14, 13, 12].each ->(i) r[i] = par[o + 4]
      r[11] = par[o + 3]
      r[10] = par[o + 3]
      [9, 8, 7, 6].each ->(i) r[i] = par[o + 2]
      [5, 4, 3].each ->(i) r[i] = par[o + 1]
      [2, 1, 0].each ->(i) r[i] = par[o]
    else
      i = 0
      while i < 34
        r[i] = par[o + i]
        i += 1
    r

  # H arrays: index (((which * 2 + r) * 6) + e) * 34 + b, which 0..3 = H11 H12 H21 H22
  -> hidx(which, r, e, b)
    ((which * 2 + r) * 6 + e) * 34 + b

  -> map_val_20_to_34(base)
    h = @h
    v = []
    i = 0
    while i < 34
      v.push(h[base + i])
      i += 1
    m = [0, 0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 8, 9, 9, 10, 11, 12, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 18, 18, 19, 19]
    i = 0
    while i < 34
      h[base + i] = v[m[i]]
      i += 1
    h[base + 1] = (v[0] + v[1]) * ~0.5
    h[base + 4] = (v[2] + v[3]) * ~0.5

  -> map_val_34_to_20(base)
    h = @h
    v = []
    i = 0
    while i < 34
      v.push(h[base + i])
      i += 1
    t = ~0.33333333
    h[base] = (~2.0 * v[0] + v[1]) * sbr_f32(t)
    h[base + 1] = (v[1] + ~2.0 * v[2]) * sbr_f32(t)
    h[base + 2] = (~2.0 * v[3] + v[4]) * sbr_f32(t)
    h[base + 3] = (v[4] + ~2.0 * v[5]) * sbr_f32(t)
    h[base + 4] = (v[6] + v[7]) * ~0.5
    h[base + 5] = (v[8] + v[9]) * ~0.5
    h[base + 6] = v[10]
    h[base + 7] = v[11]
    h[base + 8] = (v[12] + v[13]) * ~0.5
    h[base + 9] = (v[14] + v[15]) * ~0.5
    h[base + 10] = v[16]
    h[base + 11] = v[17]
    h[base + 12] = v[18]
    h[base + 13] = v[19]
    h[base + 14] = (v[20] + v[21]) * ~0.5
    h[base + 15] = (v[22] + v[23]) * ~0.5
    h[base + 16] = (v[24] + v[25]) * ~0.5
    h[base + 17] = (v[26] + v[27]) * ~0.5
    h[base + 18] = (v[28] + v[29] + v[30] + v[31]) * ~0.25
    h[base + 19] = (v[32] + v[33]) * ~0.5

  -> stereo_processing
    is34 = @is34
    h = @h
    ki = PS_KI20
    ki = PS_KI34 if is34 == 1
    lut = PS_HA
    lut = PS_HB if @icc_mode >= 3
    if @num_env_old > 0
      w = 0
      while w < 4
        r = 0
        while r < 2
          b = 0
          while b < 34
            h[hidx(w, r, 0, b)] = h[hidx(w, r, @num_env_old, b)]
            b += 1
          r += 1
        w += 1
    iidm = []
    iccm = []
    ipdm = []
    opdm = []
    e = 0
    while e < @num_env
      if is34 == 1
        iidm.push(map_34(@iid, e, @nr_iid, true))
        iccm.push(map_34(@icc, e, @nr_icc, true))
        ipdm.push(map_34(@ipd, e, @nr_ipdopd, false))
        opdm.push(map_34(@opd, e, @nr_ipdopd, false))
      else
        iidm.push(map_20(@iid, e, @nr_iid, true))
        iccm.push(map_20(@icc, e, @nr_icc, true))
        ipdm.push(map_20(@ipd, e, @nr_ipdopd, false))
        opdm.push(map_20(@opd, e, @nr_ipdopd, false))
      e += 1
    if is34 == 1 && @is34_old == 0
      w = 0
      while w < 4
        map_val_20_to_34(hidx(w, 0, 0, 0))
        map_val_20_to_34(hidx(w, 1, 0, 0))
        w += 1
      ps_izero(@ipd_hist)
      ps_izero(@opd_hist)
    elsif is34 == 0 && @is34_old == 1
      w = 0
      while w < 4
        map_val_34_to_20(hidx(w, 0, 0, 0))
        map_val_34_to_20(hidx(w, 1, 0, 0))
        w += 1
      ps_izero(@ipd_hist)
      ps_izero(@opd_hist)
    npar = PS_NR_PAR_BANDS[is34]
    nipd = PS_NR_IPDOPD_BANDS[is34]
    nb = PS_NR_BANDS[is34]
    ipd = @enable_ipdopd
    e = 0
    while e < @num_env
      b = 0
      while b < npar
        li = (iidm[e][b] + 7 + 23 * @iid_quant) * 32 + iccm[e][b] * 4
        h11 = lut[li]
        h12 = lut[li + 1]
        h21 = lut[li + 2]
        h22 = lut[li + 3]
        if ipd == 1 && b < nipd
          oi = @opd_hist[b] * 8 + opdm[e][b]
          ii = @ipd_hist[b] * 8 + ipdm[e][b]
          ore = PS_PDRE[oi]
          oim = PS_PDIM[oi]
          ire = PS_PDRE[ii]
          iim = PS_PDIM[ii]
          @opd_hist[b] = oi & 63
          @ipd_hist[b] = ii & 63
          are = ore * ire + oim * iim
          aim = oim * ire - ore * iim
          h[hidx(0, 1, e + 1, b)] = h11 * oim
          h[hidx(1, 1, e + 1, b)] = h12 * aim
          h[hidx(2, 1, e + 1, b)] = h21 * oim
          h[hidx(3, 1, e + 1, b)] = h22 * aim
          h11 = h11 * ore
          h12 = h12 * are
          h21 = h21 * ore
          h22 = h22 * are
        h[hidx(0, 0, e + 1, b)] = h11
        h[hidx(1, 0, e + 1, b)] = h12
        h[hidx(2, 0, e + 1, b)] = h21
        h[hidx(3, 0, e + 1, b)] = h22
        b += 1
      start = @border[e]
      stop = @border[e + 1]
      wd = stop - start
      wd = 1 if wd == 0
      width = sbr_f32(~1.0 / (wd ## f64))
      hh = @hh
      hs = @hs
      k = 0
      while k < nb
        b = ki[k]
        w = 0
        while w < 4
          hh[w] = h[hidx(w, 0, e, b)]
          hh[4 + w] = ~0.0
          if ipd == 1
            neg = (is34 == 1 && k <= 13 && k >= 9) || (is34 == 0 && k <= 1)
            v = h[hidx(w, 1, e, b)]
            v = ~0.0 - v if neg
            hh[4 + w] = v
          hs[w] = (h[hidx(w, 0, e + 1, b)] - hh[w]) * width
          hs[4 + w] = ~0.0
          hs[4 + w] = (h[hidx(w, 1, e + 1, b)] - hh[4 + w]) * width if ipd == 1
          w += 1
        ps_interp(@lbr, @lbi, @rbr, @rbi, k, start, stop, hh, hs, ipd) if stop - start != 0
        k += 1
      e += 1

  # Apply PS to the QMF-domain mono signal: L (in/out, left) and R (out).
  -> apply(lr, li, rr, ri, top)
    is34 = @is34
    nb = PS_NR_BANDS[is34]
    nap = PS_NR_ALLPASS[is34]
    top += nb - 64
    top = 0 if top < 0
    if top < nb
      ps_zero(@dlr, top * 46, nb * 46)
      ps_zero(@dli, top * 46, nb * 46)
    if top < nap
      ps_zero(@apr, top * 111, nap * 111)
      ps_zero(@api, top * 111, nap * 111)
    if is34 != @is34_old
      ps_zero(@st, 0, 102)
      ps_zero(@dlr, 0, @dlr.size)
      ps_zero(@dli, 0, @dli.size)
      ps_zero(@apr, 0, @apr.size)
      ps_zero(@api, 0, @api.size)
    # hybrid analysis
    if is34 == 1
      ps_hyb_in(lr, li, @inr, @ini, @lbr, @lbi, 5, 27)
      ps_hyb_cx(@inr, @ini, 0, PS_F34A, 12, @lbr, @lbi, 0)
      ps_hyb_cx(@inr, @ini, 44, PS_F34B, 8, @lbr, @lbi, 12)
      ps_hyb_cx(@inr, @ini, 88, PS_F34C, 4, @lbr, @lbi, 20)
      ps_hyb_cx(@inr, @ini, 132, PS_F34C, 4, @lbr, @lbi, 24)
      ps_hyb_cx(@inr, @ini, 176, PS_F34C, 4, @lbr, @lbi, 28)
    else
      ps_hyb_in(lr, li, @inr, @ini, @lbr, @lbi, 3, 7)
      ps_hyb6(@inr, @ini, PS_F20, @lbr, @lbi, @tr, @ti)
      ps_hyb2(@inr, @ini, 44, PS_G1Q2, @lbr, @lbi, 6, 1)
      ps_hyb2(@inr, @ini, 88, PS_G1Q2, @lbr, @lbi, 8, 0)
    ps_hyb_shift(@inr, @ini)
    ki = PS_KI20
    ki = PS_KI34 if is34 == 1
    ps_decorrelate(@lbr, @lbi, @rbr, @rbi, is34, ki, @st, @dlr, @dli, @apr, @api, PS_QF, PS_PF, @pw, @tg)
    stereo_processing
    ps_hyb_syn(lr, li, @lbr, @lbi, is34)
    ps_hyb_syn(rr, ri, @rbr, @rbi, is34)

-> ps_ifill(a, v)
  i = 0
  while i < a.size
    a[i] = v
    i += 1

-> ps_izero(a)
  ps_ifill(a, 0)
