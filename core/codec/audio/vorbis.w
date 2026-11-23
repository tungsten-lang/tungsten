# core/codec/audio/vorbis — a Vorbis I decoder for Blade's media pipeline.
#
#   acodec_register("vorb", …): cfg.extra = [identification, comment, setup]
#   header packets (ByteArrays); one audio packet per MediaSample.
#   decode(sample) -> AudioBlock (f32 interleaved, WAVE/SMPTE channel order)
#   or nil (the first packet after start / reset only primes the overlap).
#
# Everything in the Vorbis I specification: codebooks (canonical Huffman
# from the length list, ordered / sparse; VQ lookup types 1 and 2), floor 0
# (LSP) and floor 1 (piecewise linear), residue 0/1/2, mappings with
# square-polar coupling and submaps, short/long block switching with the
# transition windows, IMDCT (a DCT-IV through an N/4-point complex FFT) and
# overlap-add. Channels > 2 are reordered from Vorbis order to WAVE order
# (L R C LFE …), as ffmpeg does.
#
# Codebooks are concatenated into flat typed arrays so the hot loops are
# typed functions: a 10-bit fast lookup per book (LSB-first peek), a binary
# tree for longer codewords, and the dequantised VQ vectors.
# Robustness: malformed headers raise MediaError; a malformed audio packet
# decodes as far as the spec allows (end-of-packet in a floor zeroes that
# channel, in a residue ends the residue) and never reads out of bounds.

use core/codec/media

VB_FB = 10

-> vb_err(msg)
  raise MediaError.new("vorbis: " + msg)

-> vb_mk_db
  a = [~1.0649863e-07, ~1.1341951e-07, ~1.2079015e-07, ~1.2863978e-07, ~1.3699951e-07, ~1.4590251e-07, ~1.5538408e-07, ~1.6548181e-07,
    ~1.7623575e-07, ~1.8768855e-07, ~1.9988561e-07, ~2.1287530e-07, ~2.2670913e-07, ~2.4144197e-07, ~2.5713223e-07, ~2.7384213e-07,
    ~2.9163793e-07, ~3.1059021e-07, ~3.3077411e-07, ~3.5226968e-07, ~3.7516214e-07, ~3.9954229e-07, ~4.2550680e-07, ~4.5315863e-07,
    ~4.8260743e-07, ~5.1396998e-07, ~5.4737065e-07, ~5.8294187e-07, ~6.2082472e-07, ~6.6116941e-07, ~7.0413592e-07, ~7.4989464e-07,
    ~7.9862701e-07, ~8.5052630e-07, ~9.0579828e-07, ~9.6466216e-07, ~1.0273513e-06, ~1.0941144e-06, ~1.1652161e-06, ~1.2409384e-06,
    ~1.3215816e-06, ~1.4074654e-06, ~1.4989305e-06, ~1.5963394e-06, ~1.7000785e-06, ~1.8105592e-06, ~1.9282195e-06, ~2.0535261e-06,
    ~2.1869758e-06, ~2.3290978e-06, ~2.4804557e-06, ~2.6416497e-06, ~2.8133190e-06, ~2.9961443e-06, ~3.1908506e-06, ~3.3982101e-06,
    ~3.6190449e-06, ~3.8542308e-06, ~4.1047004e-06, ~4.3714470e-06, ~4.6555282e-06, ~4.9580707e-06, ~5.2802740e-06, ~5.6234160e-06,
    ~5.9888572e-06, ~6.3780469e-06, ~6.7925283e-06, ~7.2339451e-06, ~7.7040476e-06, ~8.2047000e-06, ~8.7378876e-06, ~9.3057248e-06,
    ~9.9104632e-06, ~1.0554501e-05, ~1.1240392e-05, ~1.1970856e-05, ~1.2748789e-05, ~1.3577278e-05, ~1.4459606e-05, ~1.5399272e-05,
    ~1.6400004e-05, ~1.7465768e-05, ~1.8600792e-05, ~1.9809576e-05, ~2.1096914e-05, ~2.2467911e-05, ~2.3928002e-05, ~2.5482978e-05,
    ~2.7139006e-05, ~2.8902651e-05, ~3.0780908e-05, ~3.2781225e-05, ~3.4911534e-05, ~3.7180282e-05, ~3.9596466e-05, ~4.2169667e-05,
    ~4.4910090e-05, ~4.7828601e-05, ~5.0936773e-05, ~5.4246931e-05, ~5.7772202e-05, ~6.1526565e-05, ~6.5524908e-05, ~6.9783085e-05,
    ~7.4317983e-05, ~7.9147585e-05, ~8.4291040e-05, ~8.9768747e-05, ~9.5602426e-05, ~0.00010181521, ~0.00010843174, ~0.00011547824,
    ~0.00012298267, ~0.00013097477, ~0.00013948625, ~0.00014855085, ~0.00015820453, ~0.00016848555, ~0.00017943469, ~0.00019109536,
    ~0.00020351382, ~0.00021673929, ~0.00023082423, ~0.00024582449, ~0.00026179955, ~0.00027881276, ~0.00029693158, ~0.00031622787,
    ~0.00033677814, ~0.00035866388, ~0.00038197188, ~0.00040679456, ~0.00043323036, ~0.00046138411, ~0.00049136745, ~0.00052329927,
    ~0.00055730621, ~0.00059352311, ~0.00063209358, ~0.00067317058, ~0.00071691700, ~0.00076350630, ~0.00081312324, ~0.00086596457,
    ~0.00092223983, ~0.00098217216, ~0.0010459992, ~0.0011139742, ~0.0011863665, ~0.0012634633, ~0.0013455702, ~0.0014330129,
    ~0.0015261382, ~0.0016253153, ~0.0017309374, ~0.0018434235, ~0.0019632195, ~0.0020908006, ~0.0022266726, ~0.0023713743,
    ~0.0025254795, ~0.0026895994, ~0.0028643847, ~0.0030505286, ~0.0032487691, ~0.0034598925, ~0.0036847358, ~0.0039241906,
    ~0.0041792066, ~0.0044507950, ~0.0047400328, ~0.0050480668, ~0.0053761186, ~0.0057254891, ~0.0060975636, ~0.0064938176,
    ~0.0069158225, ~0.0073652516, ~0.0078438871, ~0.0083536271, ~0.0088964928, ~0.009474637, ~0.010090352, ~0.010746080,
    ~0.011444421, ~0.012188144, ~0.012980198, ~0.013823725, ~0.014722068, ~0.015678791, ~0.016697687, ~0.017782797,
    ~0.018938423, ~0.020169149, ~0.021479854, ~0.022875735, ~0.024362330, ~0.025945531, ~0.027631618, ~0.029427276,
    ~0.031339626, ~0.033376252, ~0.035545228, ~0.037855157, ~0.040315199, ~0.042935108, ~0.045725273, ~0.048696758,
    ~0.051861348, ~0.055231591, ~0.058820850, ~0.062643361, ~0.066714279, ~0.071049749, ~0.075666962, ~0.080584227,
    ~0.085821044, ~0.091398179, ~0.097337747, ~0.10366330, ~0.11039993, ~0.11757434, ~0.12521498, ~0.13335215,
    ~0.14201813, ~0.15124727, ~0.16107617, ~0.17154380, ~0.18269168, ~0.19456402, ~0.20720788, ~0.22067342,
    ~0.23501402, ~0.25028656, ~0.26655159, ~0.28387361, ~0.30232132, ~0.32196786, ~0.34289114, ~0.36517414,
    ~0.38890521, ~0.41417847, ~0.44109412, ~0.46975890, ~0.50028648, ~0.53279791, ~0.56742212, ~0.60429640,
    ~0.64356699, ~0.68538959, ~0.72993007, ~0.77736504, ~0.82788260, ~0.88168307, ~0.9389798, ~1.0]
  t = f64[256]
  i = 0
  while i < 256
    t[i] = a[i]
    i += 1
  t

VB_DB = vb_mk_db()

# Vorbis channel order -> WAVE order: out channel i takes Vorbis channel map[i]
VB_CHMAP = [[0], [0, 1], [0, 2, 1], [0, 1, 2, 3], [0, 2, 1, 3, 4], [0, 2, 1, 5, 3, 4], [0, 2, 1, 6, 5, 3, 4], [0, 2, 1, 7, 5, 6, 3, 4]]

-> vb_ilog(v) (i64) i64
  n = 0 ## i64
  x = v
  while x > 0
    n += 1
    x = x >> 1
  n

# ---- bit reader: LSB first; st[0] bit position, st[1] limit (bits), st[2] end-of-packet flag ----

-> vb_bits(b, st, n) (u8[] i64[] i64) i64
  return 0 if n <= 0
  pos = st[0]
  lim = st[1]
  if pos + n > lim
    st[2] = 1
    st[0] = lim
    return 0
  p = pos >> 3
  nb = lim >> 3
  w = 0 ## i64
  k = 0 ## i64
  while k < 5 && p + k < nb
    w = w | (b[p + k] << (8 * k))
    k += 1
  st[0] = pos + n
  (w >> (pos & 7)) & ((1 << n) - 1)

-> vb_float32(x) (i64) f64
  mant = x & 2097151
  ex = (x >> 21) & 1023
  v = mant * ~1.0
  e = ex - 788
  while e > 0
    v = v * ~2.0
    e -= 1
  while e < 0
    v = v * ~0.5
    e += 1
  v = ~0.0 - v if (x & 2147483648) != 0
  v

# ---- codebooks ----
# binfo per book (8 i64): 0 dims, 1 entries, 2 lookup type, 3 tree offset, 4 vq offset, 5 fast offset, 6 single entry (or -1)

# decode one entry number; -1 at end of packet / invalid codeword
-> vb_decode(b, st, fast, tree, binfo, c) (u8[] i64[] i64[] i64[] i64[] i64) i64
  bi = c * 8
  single = binfo[bi + 6]
  pos = st[0]
  lim = st[1]
  if single >= 0
    # a one-entry book: its codeword is all zero bits
    ln = binfo[bi + 7]
    if pos + ln > lim
      st[2] = 1
      st[0] = lim
      return -1
    st[0] = pos + ln
    return single
  fo = binfo[bi + 5]
  p = pos >> 3
  nb = lim >> 3
  w = 0 ## i64
  k = 0 ## i64
  while k < 3 && p + k < nb
    w = w | (b[p + k] << (8 * k))
    k += 1
  peek = (w >> (pos & 7)) & 1023
  e = fast[fo + peek]
  if e >= 0
    ln = e & 63
    if pos + ln <= lim
      st[0] = pos + ln
      return e >> 6
  to = binfo[bi + 3]
  node = 0 ## i64
  while true
    if pos >= lim
      st[2] = 1
      st[0] = lim
      return -1
    bit = (b[pos >> 3] >> (pos & 7)) & 1
    pos += 1
    nx = tree[to + node * 2 + bit]
    if nx == 0
      st[0] = pos
      return -1
    if nx < 0
      st[0] = pos
      return -1 - nx
    node = nx
  -1

# Build the codewords for a book (lengths in lens[0..entries), 0 = unused) into
# the fast table at fo and the tree at to (2 * entries nodes). Returns the
# number of tree slots used, -1 when the lengths over-specify the tree.
-> vb_build(lens, entries, fast, fo, tree, to) (i64[] i64 i64[] i64 i64[] i64) i64
  i = 0 ## i64
  while i < 1024
    fast[fo + i] = -1
    i += 1
  avail = i64[33]
  first = true
  nodes = 1 ## i64
  tree[to] = 0
  tree[to + 1] = 0
  i = 0
  while i < entries
    ln = lens[i]
    if ln > 0
      code = 0 ## i64
      if first
        code = 0
        j = 1 ## i64
        while j <= ln
          avail[j] = 1 << (32 - j)
          j += 1
        first = false
      else
        z = ln
        while z > 0 && avail[z] == 0
          z -= 1
        return -1 if z == 0
        res = avail[z]
        avail[z] = 0
        y = ln
        while y > z
          avail[y] = res + (1 << (32 - y))
          y -= 1
        code = res >> (32 - ln)
      # tree insert, most significant bit first
      node = 0 ## i64
      d = ln - 1
      while d >= 0
        bit = (code >> d) & 1
        slot = to + node * 2 + bit
        if d == 0
          tree[slot] = -1 - i
        else
          nx = tree[slot]
          if nx <= 0
            nx = nodes
            nodes += 1
            tree[to + nx * 2] = 0
            tree[to + nx * 2 + 1] = 0
            tree[slot] = nx
          node = nx
        d -= 1
      # fast table: reversed codeword in the low bits
      if ln <= 10
        rev = 0 ## i64
        j = 0
        while j < ln
          rev = rev | (((code >> j) & 1) << (ln - 1 - j))
          j += 1
        step = 1 << ln
        idx = rev
        while idx < 1024
          fast[fo + idx] = (i << 6) | ln
          idx += step
    i += 1
  nodes * 2

-> vb_lookup1_values(entries, dims)
  r = 1
  r = (Math.exp(Math.log(entries * ~1.0) / dims) ## i64) if entries > 0
  r = 0 if r < 0
  while vb_pow_le(r + 1, dims, entries)
    r += 1
  while r > 0 && !vb_pow_le(r, dims, entries)
    r -= 1
  r

-> vb_pow_le(r, d, lim)
  acc = 1
  k = 0
  while k < d
    acc = acc * r
    return false if acc > lim
    k += 1
  true

# ---- residue partition decode ----

-> vb_res_part(b, st, fast, tree, binfo, vq, c, v, off, psize, fmt, vlen) (u8[] i64[] i64[] i64[] i64[] f64[] i64 f64[] i64 i64 i64 i64) i64
  bi = c * 8
  dims = binfo[bi]
  vo = binfo[bi + 4]
  return -1 if binfo[bi + 2] == 0 || dims <= 0
  if fmt == 0
    step = psize / dims
    i = 0 ## i64
    while i < step
      e = vb_decode(b, st, fast, tree, binfo, c)
      return -1 if e < 0
      j = 0 ## i64
      while j < dims
        x = off + i + j * step
        v[x] = v[x] + vq[vo + e * dims + j] if x < vlen
        j += 1
      i += 1
  else
    i = 0 ## i64
    while i < psize
      e = vb_decode(b, st, fast, tree, binfo, c)
      return -1 if e < 0
      j = 0 ## i64
      while j < dims
        x = off + i
        v[x] = v[x] + vq[vo + e * dims + j] if x < vlen
        i += 1
        j += 1
  0

# ---- floor 1 ----
# floor conf (stride 512) at fo: 0 partitions, 1 multiplier, 2 rangebits, 3 values, then
# 8.. partition class list (32), 40.. class dims (16), 56.. class subclass bits (16),
# 72.. class masterbook (16), 88.. subclass books (16 x 8), 216.. X (65), 284.. sorted (65),
# 352.. low neighbour (65), 420.. high neighbour (65)

-> vb_floor1_decode(b, st, fast, tree, binfo, fc, fo, y) (u8[] i64[] i64[] i64[] i64[] i64[] i64 i64[]) i64
  return 0 if vb_bits(b, st, 1) == 0
  mult = fc[fo + 1]
  rng = 256 ## i64
  rng = 128 if mult == 2
  rng = 86 if mult == 3
  rng = 64 if mult == 4
  yb = vb_ilog(rng - 1)
  y[0] = vb_bits(b, st, yb)
  y[1] = vb_bits(b, st, yb)
  off = 2 ## i64
  np = fc[fo]
  i = 0 ## i64
  while i < np
    cls = fc[fo + 8 + i]
    cdim = fc[fo + 40 + cls]
    cbits = fc[fo + 56 + cls]
    csub = (1 << cbits) - 1
    cval = 0 ## i64
    if cbits > 0
      cval = vb_decode(b, st, fast, tree, binfo, fc[fo + 72 + cls])
      return 0 if cval < 0
    j = 0 ## i64
    while j < cdim
      book = fc[fo + 88 + cls * 8 + (cval & csub)]
      cval = cval >> cbits
      if book >= 0
        t = vb_decode(b, st, fast, tree, binfo, book)
        return 0 if t < 0
        y[off + j] = t
      else
        y[off + j] = 0
      j += 1
    off += cdim
    i += 1
  return 0 if st[2] != 0
  1

-> vb_render_line(x0, y0, x1, y1, n, iv) (i64 i64 i64 i64 i64 i64[]) i64
  dy = y1 - y0
  adx = x1 - x0
  ady = dy
  ady = 0 - dy if dy < 0
  return 0 if adx <= 0
  base = dy / adx
  sy = base + 1
  sy = base - 1 if dy < 0
  ab = base
  ab = 0 - base if base < 0
  ady -= ab * adx
  x = x0
  yv = y0
  err = 0 ## i64
  e = x1
  e = n if e > n
  if x < e
    iv[x] = yv
    x += 1
    while x < e
      err += ady
      if err >= adx
        err -= adx
        yv += sy
      else
        yv += base
      iv[x] = yv
      x += 1
  0

# final Y + rendering into iv[0..n2), then v[i] *= dB(iv[i])
-> vb_floor1_apply(fc, fo, y, fy, flag, n2, iv, v, db) (i64[] i64 i64[] i64[] i64[] i64 i64[] f64[] f64[]) i64
  mult = fc[fo + 1]
  rng = 256 ## i64
  rng = 128 if mult == 2
  rng = 86 if mult == 3
  rng = 64 if mult == 4
  nv = fc[fo + 3]
  fy[0] = y[0]
  fy[1] = y[1]
  flag[0] = 1
  flag[1] = 1
  i = 2 ## i64
  while i < nv
    lo = fc[fo + 352 + i]
    hi = fc[fo + 420 + i]
    x0 = fc[fo + 216 + lo]
    x1 = fc[fo + 216 + hi]
    y0 = fy[lo]
    y1 = fy[hi]
    dy = y1 - y0
    adx = x1 - x0
    ady = dy
    ady = 0 - dy if dy < 0
    pred = y0
    if adx > 0
      off = ady * (fc[fo + 216 + i] - x0) / adx
      if dy < 0
        pred = y0 - off
      else
        pred = y0 + off
    val = y[i]
    highroom = rng - pred
    lowroom = pred
    room = lowroom * 2
    room = highroom * 2 if highroom < lowroom
    if val != 0
      flag[lo] = 1
      flag[hi] = 1
      flag[i] = 1
      if val >= room
        if highroom > lowroom
          fy[i] = val - lowroom + pred
        else
          fy[i] = pred - val + highroom - 1
      elsif (val & 1) != 0
        fy[i] = pred - ((val + 1) >> 1)
      else
        fy[i] = pred + (val >> 1)
    else
      flag[i] = 0
      fy[i] = pred
    i += 1
  lx = 0 ## i64
  ly = fy[fc[fo + 284]] * mult
  i = 1
  while i < nv
    j = fc[fo + 284 + i]
    if flag[j] != 0
      hy = fy[j] * mult
      hx = fc[fo + 216 + j]
      vb_render_line(lx, ly, hx, hy, n2, iv)
      lx = hx
      ly = hy
    i += 1
  k = lx
  while k < n2
    iv[k] = ly
    k += 1
  k = 0
  while k < n2
    q = iv[k]
    q = 0 if q < 0
    q = 255 if q > 255
    v[k] = v[k] * db[q]
    k += 1
  0

# ---- IMDCT: y[0..n) from X[0..n/2) through a DCT-IV of size n/2 = an n/4 complex FFT ----
# tables per block size (on the decoder): br (bit reverse n/4), twc/tws (n/8 FFT twiddles),
# pc/ps (n/4 pre/post twiddles exp(-i pi (8k+1) / (8 M)), M = n/2)

-> vb_fft(re, im, m, br, twc, tws) (f64[] f64[] i64 i64[] f64[] f64[]) i64
  i = 0 ## i64
  while i < m
    j = br[i]
    if j > i
      t = re[i]
      re[i] = re[j]
      re[j] = t
      t = im[i]
      im[i] = im[j]
      im[j] = t
    i += 1
  len = 2 ## i64
  while len <= m
    half = len >> 1
    tstep = m / len
    s = 0 ## i64
    while s < m
      k = 0 ## i64
      while k < half
        wr = twc[k * tstep]
        wi = tws[k * tstep]
        a = s + k
        bq = a + half
        xr = re[bq] * wr - im[bq] * wi
        xi = re[bq] * wi + im[bq] * wr
        re[bq] = re[a] - xr
        im[bq] = im[a] - xi
        re[a] = re[a] + xr
        im[a] = im[a] + xi
        k += 1
      s += len
    len = len << 1
  0

-> vb_imdct(x, xo, y, n, br, twc, tws, pc, ps, re, im, u) (f64[] i64 f64[] i64 i64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[]) i64
  mm = n >> 1
  q = n >> 2
  k = 0 ## i64
  while k < q
    a = x[xo + 2 * k]
    bb = x[xo + mm - 1 - 2 * k]
    c = pc[k]
    s = ps[k]
    re[k] = a * c + bb * s
    im[k] = bb * c - a * s
    k += 1
  vb_fft(re, im, q, br, twc, tws)
  k = 0
  while k < q
    c = pc[k]
    s = ps[k]
    zr = re[k] * c + im[k] * s
    zi = im[k] * c - re[k] * s
    u[2 * k] = zr
    u[mm - 1 - 2 * k] = ~0.0 - zi
    k += 1
  n4 = q
  i = 0 ## i64
  while i < n4
    y[i] = u[i + n4]
    i += 1
  while i < 3 * n4
    y[i] = ~0.0 - u[3 * n4 - 1 - i]
    i += 1
  while i < n
    y[i] = ~0.0 - u[i - 3 * n4]
    i += 1
  0

# window the block in y[0..n): slopes of half-length ln / rn (ws: slope tables, short at 0, long at so)
-> vb_window(y, n, lstart, ln, rstart, rn, ws0, ws1, sh0, sh1) (f64[] i64 i64 i64 i64 i64 f64[] f64[] i64 i64) i64
  i = 0 ## i64
  while i < lstart
    y[i] = ~0.0
    i += 1
  k = 0 ## i64
  while k < ln
    if ln == sh0
      y[lstart + k] = y[lstart + k] * ws0[k]
    else
      y[lstart + k] = y[lstart + k] * ws1[k]
    k += 1
  k = 0
  while k < rn
    if rn == sh0
      y[rstart + k] = y[rstart + k] * ws0[rn - 1 - k]
    else
      y[rstart + k] = y[rstart + k] * ws1[rn - 1 - k]
    k += 1
  i = rstart + rn
  while i < n
    y[i] = ~0.0
    i += 1
  0

-> vb_coupling(m, mo, a, ao, n) (f64[] i64 f64[] i64 i64) i64
  j = 0 ## i64
  while j < n
    mv = m[mo + j]
    av = a[ao + j]
    nm = mv
    na = av
    if mv > ~0.0
      if av > ~0.0
        nm = mv
        na = mv - av
      else
        na = mv
        nm = mv + av
    else
      if av > ~0.0
        nm = mv
        na = mv + av
      else
        na = mv
        nm = mv - av
    m[mo + j] = nm
    a[ao + j] = na
    j += 1
  0

# out[f * nch + oc] = prev[pn/2 + f] + cur[f - pn/4 + cn/4]
-> vb_overlap(prev, po, pn, cur, co, cn, out, oc, nch, cnt) (f64[] i64 i64 f64[] i64 i64 f32[] i64 i64 i64) i64
  f = 0 ## i64
  d = cn / 4 - pn / 4
  while f < cnt
    s = ~0.0
    pi = pn / 2 + f
    s = prev[po + pi] if pi < pn
    ci = f + d
    s = s + cur[co + ci] if ci >= 0 && ci < cn
    out[f * nch + oc] = s ## f32
    f += 1
  0

-> vb_zero(a, o, n) (f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    a[o + i] = ~0.0
    i += 1
  0

-> vb_bytes(d)
  if d.is_a?(String)
    return ccall("w_string_bytes_view", d) ## u8[]
  d

+ VorbDec
  ro :rate, :channels

  -> new(cfg)
    @reuse = cfg.is_a?(CodecConfig) && cfg.reuse_output == true
    @obuf = nil
    hs = cfg.extra
    vb_err("need 3 header packets") if hs == nil || hs.size < 3
    @st = i64[3]
    parse_ident(vb_bytes(hs[0]))
    parse_setup(vb_bytes(hs[2]))
    setup_dsp()
    @first = true

  -> reset
    @first = true
    vb_zero(@prev, 0, @prev.size)

  -> flush
    nil

  -> rd(b, n)
    vb_bits(b, @st, n)

  -> start(b)
    @st[0] = 0
    @st[1] = b.size * 8
    @st[2] = 0

  -> check_magic(b, typ)
    vb_err("bad header") if b.size < 7 || b[0] != typ || b[1] != 118 || b[2] != 111 || b[3] != 114 || b[4] != 98 || b[5] != 105 || b[6] != 115

  -> parse_ident(b)
    check_magic(b, 1)
    vb_err("short id header") if b.size < 30
    start(b)
    @st[0] = 56
    ver = rd(b, 32)
    vb_err("version") if ver != 0
    @channels = rd(b, 8)
    @rate = rd(b, 32)
    rd(b, 32)
    rd(b, 32)
    rd(b, 32)
    b0 = rd(b, 4)
    b1 = rd(b, 4)
    vb_err("channels") if @channels < 1 || @channels > 255
    vb_err("rate") if @rate <= 0
    vb_err("block sizes") if b0 < 6 || b1 > 13 || b0 > b1
    @bs0 = 1 << b0
    @bs1 = 1 << b1

  -> parse_setup(b)
    check_magic(b, 5)
    start(b)
    @st[0] = 56
    ncb = rd(b, 8) + 1
    # pass 1: read books into Ruby-side lists, then flatten
    books = []
    tot_vq = 0
    tot_tree = 0
    ncb.times ->(ci)
      bk = read_book(b)
      books.push(bk)
      tot_vq += bk[:vqn]
      tot_tree += bk[:tslots]
    @binfo = i64[ncb * 8 + 8]
    @fast = i64[ncb * 1024 + 1]
    @tree = i64[tot_tree + 2]
    @vq = f64[tot_vq + 1]
    to = 0
    vo = 0
    ci = 0
    while ci < ncb
      bk = books[ci]
      bi = ci * 8
      @binfo[bi] = bk[:dims]
      @binfo[bi + 1] = bk[:entries]
      @binfo[bi + 2] = bk[:lookup]
      @binfo[bi + 3] = to
      @binfo[bi + 4] = vo
      @binfo[bi + 5] = ci * 1024
      @binfo[bi + 6] = -1
      used = 0
      last = -1
      lens = bk[:lens]
      e = 0
      while e < bk[:entries]
        if lens[e] > 0
          used += 1
          last = e
        e += 1
      if used == 1
        @binfo[bi + 6] = last
        @binfo[bi + 7] = lens[last]
      else
        r = vb_build(lens, bk[:entries], @fast, ci * 1024, @tree, to)
        vb_err("bad huffman lengths") if r < 0
      to += bk[:tslots]
      if bk[:lookup] != 0
        fill_vq(bk, @vq, vo)
      vo += bk[:vqn]
      ci += 1
    # time domain transforms
    nt = rd(b, 6) + 1
    nt.times ->(i)
      vb_err("time type") if rd(b, 16) != 0
    # floors
    nf = rd(b, 6) + 1
    @floor_type = []
    @fc = i64[nf * 512]
    @floor0 = []
    nf.times ->(fi)
      ft = rd(b, 16)
      @floor_type.push(ft)
      if ft == 0
        @floor0.push(read_floor0(b, ncb))
      elsif ft == 1
        @floor0.push(nil)
        read_floor1(b, fi * 512, ncb)
      else
        vb_err("floor type")
    # residues
    nr = rd(b, 6) + 1
    @residues = []
    nr.times ->(ri)
      rt = rd(b, 16)
      vb_err("residue type") if rt > 2
      rbeg = rd(b, 24)
      rend = rd(b, 24)
      psz = rd(b, 24) + 1
      ncls = rd(b, 6) + 1
      cbk = rd(b, 8)
      vb_err("residue book") if cbk >= ncb
      casc = []
      ncls.times ->(k)
        lo = rd(b, 3)
        hi = 0
        hi = rd(b, 5) if rd(b, 1) == 1
        casc.push(hi * 8 + lo)
      rb = i64[ncls * 8]
      k = 0
      while k < ncls
        j = 0
        while j < 8
          if (casc[k] & (1 << j)) != 0
            bn = rd(b, 8)
            vb_err("residue vq book") if bn >= ncb || books[bn][:lookup] == 0
            rb[k * 8 + j] = bn
          else
            rb[k * 8 + j] = -1
          j += 1
        k += 1
      vb_err("residue classbook dims") if books[cbk][:dims] <= 0
      @residues.push({type: rt, rbeg: rbeg, rend: rend, psize: psz, ncls: ncls, classbook: cbk, books: rb})
    # mappings
    nm = rd(b, 6) + 1
    @mappings = []
    nm.times ->(mi)
      vb_err("mapping type") if rd(b, 16) != 0
      subs = 1
      subs = rd(b, 4) + 1 if rd(b, 1) == 1
      cm = []
      ca = []
      if rd(b, 1) == 1
        steps = rd(b, 8) + 1
        bits = vb_ilog(@channels - 1)
        steps.times ->(s)
          m = rd(b, bits)
          a = rd(b, bits)
          vb_err("coupling") if m == a || m >= @channels || a >= @channels
          cm.push(m)
          ca.push(a)
      vb_err("mapping reserved") if rd(b, 2) != 0
      mux = []
      if subs > 1
        @channels.times ->(c)
          mx = rd(b, 4)
          vb_err("mux") if mx >= subs
          mux.push(mx)
      else
        @channels.times ->(c)
          mux.push(0)
      sf = []
      sr = []
      subs.times ->(s)
        rd(b, 8)
        f = rd(b, 8)
        r = rd(b, 8)
        vb_err("submap floor") if f >= nf
        vb_err("submap residue") if r >= nr
        sf.push(f)
        sr.push(r)
      @mappings.push({cm: cm, ca: ca, mux: mux, sf: sf, sr: sr, subs: subs})
    # modes
    nmo = rd(b, 6) + 1
    @modes = []
    nmo.times ->(i)
      bf = rd(b, 1)
      wt = rd(b, 16)
      tt = rd(b, 16)
      mp = rd(b, 8)
      vb_err("mode") if wt != 0 || tt != 0 || mp >= nm
      @modes.push([bf, mp])
    vb_err("framing") if rd(b, 1) != 1 || @st[2] != 0
    @mode_bits = vb_ilog(nmo - 1)

  -> read_book(b)
    vb_err("codebook sync") if rd(b, 24) != 5653314
    dims = rd(b, 16)
    entries = rd(b, 24)
    vb_err("codebook size") if entries > 1048576 || dims > 65535
    lens = i64[entries + 1]
    if rd(b, 1) == 0
      sparse = rd(b, 1)
      e = 0
      while e < entries
        if sparse == 0 || rd(b, 1) == 1
          lens[e] = rd(b, 5) + 1
        e += 1
    else
      cur = rd(b, 5) + 1
      e = 0
      while e < entries
        num = rd(b, vb_ilog(entries - e))
        vb_err("ordered lengths") if cur > 32 || e + num > entries
        k = 0
        while k < num
          lens[e + k] = cur
          k += 1
        e += num
        cur += 1
    vb_err("codebook eop") if @st[2] != 0
    # tree slots: at most one node per codeword bit (+ root)
    sumlen = 0
    e = 0
    while e < entries
      sumlen += lens[e]
      e += 1
    tslots = 2 * (sumlen + 1) + 2
    lt = rd(b, 4)
    vqn = 0
    bk = {dims: dims, entries: entries, lens: lens, lookup: lt, vqn: 0, tslots: tslots}
    if lt == 1 || lt == 2
      bk[:min] = vb_float32(rd(b, 32))
      bk[:delta] = vb_float32(rd(b, 32))
      vbits = rd(b, 4) + 1
      bk[:seq] = rd(b, 1)
      nvals = 0
      if lt == 1
        nvals = vb_lookup1_values(entries, dims)
      else
        nvals = entries * dims
      vb_err("lookup size") if nvals > 4194304 || entries * dims > 4194304
      mults = i64[nvals + 1]
      k = 0
      while k < nvals
        mults[k] = rd(b, vbits)
        k += 1
      bk[:mults] = mults
      bk[:nvals] = nvals
      bk[:vqn] = entries * dims
      vb_err("dims") if dims == 0
    elsif lt != 0
      vb_err("lookup type")
    vb_err("codebook eop") if @st[2] != 0
    bk

  -> fill_vq(bk, vq, vo)
    dims = bk[:dims]
    entries = bk[:entries]
    mults = bk[:mults]
    mn = bk[:min]
    dl = bk[:delta]
    seq = bk[:seq]
    nv = bk[:nvals]
    e = 0
    while e < entries
      last = ~0.0
      div = 1
      j = 0
      while j < dims
        off = 0
        if bk[:lookup] == 1
          off = (e / div) % nv
        else
          off = e * dims + j
        v = mults[off] * dl + mn + last
        last = v if seq == 1
        vq[vo + e * dims + j] = v
        div = div * nv if bk[:lookup] == 1
        j += 1
      e += 1

  -> read_floor0(b, ncb)
    order = rd(b, 8)
    rate = rd(b, 16)
    bms = rd(b, 16)
    ab = rd(b, 6)
    ao = rd(b, 8)
    nbk = rd(b, 4) + 1
    bl = []
    nbk.times ->(i)
      bn = rd(b, 8)
      vb_err("floor0 book") if bn >= ncb
      bl.push(bn)
    vb_err("floor0") if order < 1 || rate < 1 || bms < 1
    {order: order, rate: rate, bark: bms, abits: ab, aoff: ao, books: bl, maps: {}}

  -> read_floor1(b, fo, ncb)
    fc = @fc
    np = rd(b, 5)
    fc[fo] = np
    maxc = -1
    i = 0
    while i < np
      c = rd(b, 4)
      fc[fo + 8 + i] = c
      maxc = c if c > maxc
      i += 1
    c = 0
    while c <= maxc
      fc[fo + 40 + c] = rd(b, 3) + 1
      sb = rd(b, 2)
      fc[fo + 56 + c] = sb
      fc[fo + 72 + c] = 0
      if sb > 0
        mb = rd(b, 8)
        vb_err("floor1 master") if mb >= ncb
        fc[fo + 72 + c] = mb
      j = 0
      while j < 8
        fc[fo + 88 + c * 8 + j] = -1
        j += 1
      j = 0
      while j < (1 << sb)
        bn = rd(b, 8) - 1
        vb_err("floor1 sub book") if bn >= ncb
        fc[fo + 88 + c * 8 + j] = bn
        j += 1
      c += 1
    fc[fo + 1] = rd(b, 2) + 1
    rb = rd(b, 4)
    fc[fo + 2] = rb
    fc[fo + 216] = 0
    fc[fo + 217] = 1 << rb
    nv = 2
    i = 0
    while i < np
      c = fc[fo + 8 + i]
      j = 0
      while j < fc[fo + 40 + c]
        vb_err("floor1 values") if nv >= 65
        fc[fo + 216 + nv] = rd(b, rb)
        nv += 1
        j += 1
      i += 1
    fc[fo + 3] = nv
    # sorted order, neighbours; X values must be distinct
    xs = []
    i = 0
    while i < nv
      xs.push([fc[fo + 216 + i], i])
      i += 1
    xs = xs.sort_by ->(p) p[0]
    i = 0
    while i < nv
      fc[fo + 284 + i] = xs[i][1]
      vb_err("floor1 duplicate X") if i > 0 && xs[i][0] == xs[i - 1][0]
      i += 1
    i = 2
    while i < nv
      xi = fc[fo + 216 + i]
      lo = 0
      hi = 1
      lx = -1
      hx = 1 << 30
      j = 0
      while j < i
        xj = fc[fo + 216 + j]
        if xj < xi && xj > lx
          lx = xj
          lo = j
        if xj > xi && xj < hx
          hx = xj
          hi = j
        j += 1
      fc[fo + 352 + i] = lo
      fc[fo + 420 + i] = hi
      i += 1

  -> setup_dsp
    nch = @channels
    @prev = f64[nch * @bs1]
    @cur = f64[nch * @bs1]
    @res = f64[nch * (@bs1 / 2)]
    @res2 = f64[nch * (@bs1 / 2)]
    @prev_n = 0
    @fy = i64[72]
    @flag = i64[72]
    @ys = i64[nch * 72]
    @iv = i64[@bs1 / 2 + 1]
    @nonzero = Array.new(nch, false)
    @t0 = dsp_tables(@bs0)
    @t1 = dsp_tables(@bs1)
    @ws0 = slope(@bs0 / 2)
    @ws1 = slope(@bs1 / 2)
    m = @bs1 / 4
    @re = f64[m]
    @im = f64[m]
    @u = f64[@bs1 / 2]

  -> slope(n)
    w = f64[n]
    pi = ~3.14159265358979323846
    i = 0
    while i < n
      s = Math.sin((i + ~0.5) / n * pi / ~2.0)
      w[i] = Math.sin(pi / ~2.0 * s * s)
      i += 1
    w

  -> dsp_tables(n)
    pi = ~3.14159265358979323846
    q = n / 4
    mm = n / 2
    br = i64[q]
    bits = vb_ilog(q) - 1
    i = 0
    while i < q
      r = 0
      j = 0
      while j < bits
        r = r | (((i >> j) & 1) << (bits - 1 - j))
        j += 1
      br[i] = r
      i += 1
    twc = f64[q]
    tws = f64[q]
    i = 0
    while i < q
      a = ~-2.0 * pi * i / q
      twc[i] = Math.cos(a)
      tws[i] = Math.sin(a)
      i += 1
    pc = f64[q]
    ps = f64[q]
    i = 0
    while i < q
      a = pi * (8 * i + 1) / (~8.0 * mm)
      pc[i] = Math.cos(a)
      ps[i] = Math.sin(a)
      i += 1
    {br: br, twc: twc, tws: tws, pc: pc, ps: ps}

  # ---- audio packets ----

  -> decode(sample)
    b = vb_bytes(sample.data)
    return nil if b == nil || b.size == 0
    st = @st
    start(b)
    return nil if rd(b, 1) != 0
    mode = rd(b, @mode_bits)
    return nil if mode >= @modes.size || st[2] != 0
    bf = @modes[mode][0]
    mp = @mappings[@modes[mode][1]]
    n = @bs0
    n = @bs1 if bf == 1
    pw = 0
    nw = 0
    if bf == 1
      pw = rd(b, 1)
      nw = rd(b, 1)
    return nil if st[2] != 0
    n2 = n / 2
    nch = @channels
    # floors
    c = 0
    while c < nch
      fi = mp[:sf][mp[:mux][c]]
      if @floor_type[fi] == 1
        nz = vb_floor1_decode_into(b, fi, c)
        @nonzero[c] = nz
      else
        @nonzero[c] = floor0_decode(b, fi, c)
      c += 1
    st[2] = 0
    # coupling keeps both channels of a pair alive
    nzr = @nonzero.dup
    k = 0
    while k < mp[:cm].size
      if nzr[mp[:cm][k]] || nzr[mp[:ca][k]]
        nzr[mp[:cm][k]] = true
        nzr[mp[:ca][k]] = true
      k += 1
    # residues
    vb_zero(@res, 0, nch * n2)
    s = 0
    while s < mp[:subs]
      chs = []
      c = 0
      while c < nch
        chs.push(c) if mp[:mux][c] == s
        c += 1
      decode_residue(b, @residues[mp[:sr][s]], chs, nzr, n2)
      s += 1
    # inverse coupling
    k = mp[:cm].size - 1
    while k >= 0
      vb_coupling(@res, mp[:cm][k] * n2, @res, mp[:ca][k] * n2, n2)
      k -= 1
    # floor curves, IMDCT, windows
    t = @t0
    t = @t1 if bf == 1
    ln = n / 2
    lstart = 0
    rn = n / 2
    rstart = n / 2
    if bf == 1
      if pw == 0
        ln = @bs0 / 2
        lstart = n / 4 - @bs0 / 4
      if nw == 0
        rn = @bs0 / 2
        rstart = 3 * n / 4 - @bs0 / 4
    c = 0
    while c < nch
      ro = c * n2
      if @nonzero[c]
        fi = mp[:sf][mp[:mux][c]]
        if @floor_type[fi] == 1
          floor1_apply(fi, c, n2)
        else
          floor0_apply(fi, c, n, n2)
      else
        vb_zero(@res, ro, n2)
      c += 1
    out = nil
    cnt = 0
    if !@first
      cnt = @prev_n / 4 + n / 4
      @obuf = audio_out(@obuf, @reuse, cnt * nch)
      out = @obuf ## f32[]
    cmap = nil
    cmap = VB_CHMAP[nch - 1] if nch <= 8
    c = 0
    while c < nch
      imdct_into(c, n, t)
      window_ch(c, n, lstart, ln, rstart, rn)
      if out != nil
        oc = c
        if cmap != nil
          k = 0
          while k < nch
            oc = k if cmap[k] == c
            k += 1
        vb_overlap(@prev, c * @bs1, @prev_n, @cur, c * @bs1, n, out, oc, nch, cnt)
      c += 1
    # current block becomes the previous one
    tmp = @prev
    @prev = @cur
    @cur = tmp
    @prev_n = n
    was_first = @first
    @first = false
    return nil if was_first
    blk = AudioBlock.new(out, cnt, nch, @rate, sample.pts)
    blk.owned = !@reuse
    blk

  -> vb_floor1_decode_into(b, fi, c)
    y = @ys_ch
    if y == nil
      @ys_ch = []
      @channels.times ->(i)
        @ys_ch.push(i64[72])
      y = @ys_ch
    vb_floor1_decode(b, @st, @fast, @tree, @binfo, @fc, fi * 512, y[c]) == 1

  -> floor1_apply(fi, c, n2)
    tmpv = res_view(c, n2)
    vb_floor1_apply(@fc, fi * 512, @ys_ch[c], @fy, @flag, n2, @iv, tmpv, VB_DB)
    res_store(c, n2, tmpv)

  # channel c's residue as its own f64[] (vb_floor1_apply works from index 0)
  -> res_view(c, n2)
    @rv = f64[@bs1 / 2] if @rv == nil
    vb_copy_f64(@res, c * n2, @rv, 0, n2)
    @rv

  -> res_store(c, n2, v)
    vb_copy_f64(v, 0, @res, c * n2, n2)

  -> imdct_into(c, n, t)
    @yb = f64[@bs1] if @yb == nil
    vb_imdct(@res, c * (n / 2), @yb, n, t[:br], t[:twc], t[:tws], t[:pc], t[:ps], @re, @im, @u)
    vb_copy_f64(@yb, 0, @cur, c * @bs1, n)

  -> window_ch(c, n, lstart, ln, rstart, rn)
    vb_copy_f64(@cur, c * @bs1, @yb, 0, n)
    vb_window(@yb, n, lstart, ln, rstart, rn, @ws0, @ws1, @bs0 / 2, @bs1 / 2)
    vb_copy_f64(@yb, 0, @cur, c * @bs1, n)

  -> decode_residue(b, r, chs, nzr, n2)
    nch = chs.size
    return nil if nch == 0
    rt = r[:type]
    if rt == 2
      any = false
      chs.each ->(c)
        any = true if nzr[c]
      return nil if !any
      len = n2 * nch
      v = f64[len]
      decode_res_vectors(b, r, [v], [true], len)
      # deinterleave
      vb_deinterleave(v, @res, chs.size, n2, vb_i64_list(chs))
    else
      vs = []
      dec = []
      chs.each ->(c)
        vs.push(f64[n2])
        dec.push(nzr[c])
      decode_res_vectors(b, r, vs, dec, n2)
      i = 0
      while i < nch
        vb_add_f64(vs[i], 0, @res, chs[i] * n2, n2)
        i += 1

  -> decode_res_vectors(b, r, vs, dec, size)
    st = @st
    cb = r[:classbook]
    cw = @binfo[cb * 8]
    ncls = r[:ncls]
    psz = r[:psize]
    lb = r[:rbeg]
    lb = size if lb > size
    le = r[:rend]
    le = size if le > size
    nread = le - lb
    return nil if nread <= 0
    nparts = nread / psz
    return nil if nparts <= 0
    nv = vs.size
    cls = []
    nv.times ->(i)
      cls.push(i64[nparts + cw + 1])
    fmt = 1
    fmt = 0 if r[:type] == 0
    rbooks = r[:books]
    st[2] = 0
    pass = 0
    while pass < 8
      pc = 0
      while pc < nparts
        if pass == 0
          j = 0
          while j < nv
            if dec[j]
              temp = vb_decode(b, st, @fast, @tree, @binfo, cb)
              return nil if temp < 0
              i = cw - 1
              while i >= 0
                cls[j][i + pc] = temp % ncls if i + pc < nparts + cw
                temp = temp / ncls
                i -= 1
            j += 1
        i = 0
        while i < cw && pc < nparts
          j = 0
          while j < nv
            if dec[j]
              vqc = cls[j][pc]
              bk = rbooks[vqc * 8 + pass]
              if bk >= 0
                r2 = vb_res_part(b, st, @fast, @tree, @binfo, @vq, bk, vs[j], lb + pc * psz, psz, fmt, size)
                return nil if r2 < 0
            j += 1
          i += 1
          pc += 1
      pass += 1
    nil

  # ---- floor 0 ----

  -> floor0_decode(b, fi, c)
    f = @floor0[fi]
    @f0c = Array.new(@channels, nil) if @f0c == nil
    amp = rd(b, f[:abits])
    return false if amp <= 0 || @st[2] != 0
    bn = rd(b, vb_ilog(f[:books].size))
    return false if bn >= f[:books].size || @st[2] != 0
    book = f[:books][bn]
    dims = @binfo[book * 8]
    return false if @binfo[book * 8 + 2] == 0 || dims <= 0
    vo = @binfo[book * 8 + 4]
    coefs = []
    last = ~0.0
    while coefs.size < f[:order]
      e = vb_decode(b, @st, @fast, @tree, @binfo, book)
      return false if e < 0
      j = 0
      while j < dims
        coefs.push(@vq[vo + e * dims + j] + last)
        j += 1
      last = coefs.last
    @f0c[c] = [amp, coefs]
    true

  -> floor0_apply(fi, c, n, n2)
    f = @floor0[fi]
    amp = @f0c[c][0]
    coefs = @f0c[c][1]
    map = f[:maps][n]
    if map == nil
      map = i64[n2 + 1]
      bark = ->(x) ~13.1 * Math.atan(~0.00074 * x) + ~2.24 * Math.atan(~0.0000000185 * x * x) + ~0.0001 * x
      top = bark.call(~0.5 * f[:rate])
      i = 0
      while i < n2
        fo = (bark.call((f[:rate] * ~1.0 * i) / (~2.0 * n2)) * f[:bark] / top)
        v = fo.floor
        v = f[:bark] - 1 if v > f[:bark] - 1
        map[i] = v
        i += 1
      map[n2] = -1
      f[:maps][n] = map
    order = f[:order]
    cosc = []
    k = 0
    while k < order
      cosc.push(Math.cos(coefs[k]))
      k += 1
    pi = ~3.14159265358979323846
    lin = f64[n2]
    i = 0
    while i < n2
      om = pi * map[i] / f[:bark]
      cw = Math.cos(om)
      p = ~1.0
      q = ~1.0
      if order % 2 == 1
        j = 0
        while j <= (order - 3) / 2
          d = cosc[2 * j + 1] - cw
          p = p * ~4.0 * d * d
          j += 1
        j = 0
        while j <= (order - 1) / 2
          d = cosc[2 * j] - cw
          q = q * ~4.0 * d * d
          j += 1
        p = p * (~1.0 - cw * cw)
        q = q / ~4.0
      else
        j = 0
        while j <= (order - 2) / 2
          d = cosc[2 * j + 1] - cw
          p = p * ~4.0 * d * d
          d = cosc[2 * j] - cw
          q = q * ~4.0 * d * d
          j += 1
        p = p * (~1.0 - cw) / ~2.0
        q = q * (~1.0 + cw) / ~2.0
      val = Math.exp(~0.11512925 * (amp * f[:aoff] / (((1 << f[:abits]) - 1) * Math.sqrt(p + q)) - f[:aoff]))
      cond = map[i]
      while i < n2 && map[i] == cond
        lin[i] = val
        i += 1
    vb_mul_f64(@res, c * n2, lin, n2)

-> vb_copy_f64(src, so, dst, d0, n) (f64[] i64 f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  n

-> vb_add_f64(src, so, dst, d0, n) (f64[] i64 f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = dst[d0 + i] + src[so + i]
    i += 1
  n

-> vb_mul_f64(dst, d0, m, n) (f64[] i64 f64[] i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = dst[d0 + i] * m[i]
    i += 1
  n

-> vb_i64_list(a)
  t = i64[a.size + 1]
  i = 0
  while i < a.size
    t[i] = a[i]
    i += 1
  t

-> vb_deinterleave(v, res, nch, n2, chs) (f64[] f64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < n2
    j = 0 ## i64
    while j < nch
      res[chs[j] * n2 + i] = res[chs[j] * n2 + i] + v[i * nch + j]
      j += 1
    i += 1
  0

acodec_register("vorb", ->(cfg) VorbDec.new(cfg))
