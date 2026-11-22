# core/codec/video/av1_tx — AV1 dequantisation, inverse transforms and reconstruction
# (spec 7.12, 7.13): DCT 4-64, ADST 4/8/16, flipped ADST, identity 4-32,
# Walsh-Hadamard for lossless, quantizer matrices. The 1D transforms follow the
# spec's butterfly definitions exactly (bit-exact by construction).

use av1_tables

-> av1_tx_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_COS128 = av1_tx_i32(AV1_COS128_LOOKUP)
AV1_ROW_SHIFT = av1_tx_i32(AV1_TRANSFORM_ROW_SHIFT)
AV1_DCQ = av1_tx_i32(AV1_DC_QLOOKUP)
AV1_ACQ = av1_tx_i32(AV1_AC_QLOOKUP)
AV1_QM = av1_tx_i32(AV1_QUANTIZER_MATRIX)
AV1_QM_OFF = av1_tx_i32(AV1_QM_OFFSET)

+ Av1Decoder
  -> reconstruct(plane, x, y, tx_sz)
    dq_denom = 1
    if tx_sz == 3 || tx_sz == 9 || tx_sz == 10 || tx_sz == 17 || tx_sz == 18
      dq_denom = 2
    elsif tx_sz == 4 || tx_sz == 11 || tx_sz == 12
      dq_denom = 4
    log2w = AV1_TXWL[tx_sz]
    log2h = AV1_TXHL[tx_sz]
    w = 1 << log2w
    h = 1 << log2h
    tw = w > 32 ? 32 : w
    th = h > 32 ? 32 : h
    ptt = @plane_tx_type
    flip_ud = (ptt == 4 || ptt == 8 || ptt == 14 || ptt == 6) ? 1 : 0
    flip_lr = (ptt == 5 || ptt == 7 || ptt == 15 || ptt == 6) ? 1 : 0
    qi = get_qindex(false, @segment_id, @current_q_index)
    bdi = (@bit_depth - 8) >> 1
    dcd = plane == 0 ? @delta_q_y_dc : (plane == 1 ? @delta_q_u_dc : @delta_q_v_dc)
    acd = plane == 0 ? 0 : (plane == 1 ? @delta_q_u_ac : @delta_q_v_ac)
    dcq = AV1_DCQ[bdi * 256 + av1_clip3(0, 255, qi + dcd)]
    acq = AV1_ACQ[bdi * 256 + av1_clip3(0, 255, qi + acd)]
    qml = 15
    if @using_qmatrix == 1 && ptt < 9
      qml = @seg_qm_level[plane][@segment_id]
    qmoff = -1
    if qml < 15
      qmoff = (qml * 2 + (plane > 0 ? 1 : 0)) * 3344 + AV1_QM_OFF[tx_sz]
    fr = @cur
    av1_recon(@quant, @eob, tw, th, log2w, log2h, dcq, acq, AV1_QM, qmoff, dq_denom, @bit_depth,
              ptt, @lossless ? 1 : 0, AV1_ROW_SHIFT[tx_sz], fr.planes[plane], fr.strides[plane], x, y, flip_ud, flip_lr,
              @dequant_buf, AV1_COS128)
    nil

-> av1_recon(q, eob, tw, th, log2w, log2h, dcq, acq, qm, qmoff, denom, bd, ptt, lossless, rshift, pl, stride, x, y, fud, flr, res, cosl) (i32[] i64 i64 i64 i64 i64 i64 i64 i32[] i64 i64 i64 i64 i64 i64 u16[] i64 i64 i64 i64 i64 i32[] i32[]) i64
  w = (1 << log2w) ## i64
  h = (1 << log2h) ## i64
  lim = ((1 << (7 + bd))) ## i64
  # dequantise into res (stride w), zero elsewhere
  n = (w * h) ## i64
  i = 0 ## i64
  while i < n
    res[i] = 0
    i += 1
  i = 0
  while i < th
    j = 0 ## i64
    while j < tw
      v = (q[i * tw + j]) ## i64
      if v != 0
        qq = ((i == 0 && j == 0) ? dcq : acq) ## i64
        if qmoff >= 0
          qq = (qq * qm[qmoff + i * tw + j] + 16) >> 5
        dqv = (v * qq) ## i64
        neg = dqv < 0
        a = (neg ? 0 - dqv : dqv) ## i64
        a = (a & 0xFFFFFF) / denom
        dqv = neg ? 0 - a : a
        dqv = 0 - lim if dqv < 0 - lim
        dqv = lim - 1 if dqv > lim - 1
        res[i * w + j] = dqv
      j += 1
    i += 1
  av1_itx2d(res, log2w, log2h, ptt, lossless, rshift, bd, cosl)
  mx = ((1 << bd) - 1) ## i64
  i = 0
  while i < h
    yy = (fud == 1 ? h - i - 1 : i) ## i64
    r = ((y + yy) * stride + x) ## i64
    j = 0 ## i64
    while j < w
      xx = (flr == 1 ? w - j - 1 : j) ## i64
      v = pl[r + xx] + res[i * w + j]
      v = 0 if v < 0
      v = mx if v > mx
      pl[r + xx] = v
      j += 1
    i += 1
  0

# kind of 1D transform for rows (dir 0) / columns (dir 1): 0 DCT, 1 ADST, 2 identity
-> av1_row_kind(t) (i64) i64
  return 0 if t == 0 || t == 1 || t == 4 || t == 11
  return 1 if t == 2 || t == 3 || t == 5 || t == 6 || t == 7 || t == 8 || t == 13 || t == 15
  2

-> av1_col_kind(t) (i64) i64
  return 0 if t == 0 || t == 2 || t == 5 || t == 10
  return 1 if t == 1 || t == 3 || t == 4 || t == 6 || t == 7 || t == 8 || t == 12 || t == 14
  2

# In-place 2D inverse transform of res (h rows of w).
-> av1_itx2d(res, log2w, log2h, ptt, lossless, rshift, bd, cosl) (i32[] i64 i64 i64 i64 i64 i64 i32[]) i64
  w = (1 << log2w) ## i64
  h = (1 << log2h) ## i64
  t = i64[64]
  rk = (av1_row_kind(ptt)) ## i64
  ck = (av1_col_kind(ptt)) ## i64
  rr = (bd + 8) ## i64
  cr = (bd + 6) ## i64
  cr = 16 if cr < 16
  dl = (log2w - log2h) ## i64
  rect = dl == 1 || dl == -1
  sh = (lossless == 1 ? 0 : rshift) ## i64
  cmin = (0 - (1 << (cr - 1))) ## i64
  cmax = ((1 << (cr - 1)) - 1) ## i64
  i = 0 ## i64
  while i < h
    nz = 0 ## i64
    j = 0 ## i64
    while j < w
      v = 0 ## i64
      if i < 32 && j < 32
        v = res[i * w + j]
      t[j] = v
      nz = nz | v
      j += 1
    if nz != 0 || lossless == 1
      if rect
        j = 0
        while j < w
          t[j] = (t[j] * 2896 + 2048) >> 12
          j += 1
      if lossless == 1
        av1_iwht(t, 2)
      elsif rk == 0
        av1_idct(t, log2w, rr, cosl)
      elsif rk == 1
        av1_iadst(t, log2w, rr, cosl)
      else
        av1_iidt(t, log2w)
      j = 0
      while j < w
        v = t[j]
        if sh > 0
          v = (v + (1 << (sh - 1))) >> sh
        v = cmin if v < cmin
        v = cmax if v > cmax
        res[i * w + j] = v
        j += 1
    else
      j = 0
      while j < w
        res[i * w + j] = 0
        j += 1
    i += 1
  csh = (lossless == 1 ? 0 : 4) ## i64
  j = 0
  while j < w
    i = 0
    while i < h
      t[i] = res[i * w + j]
      i += 1
    if lossless == 1
      av1_iwht(t, 0)
    elsif ck == 0
      av1_idct(t, log2h, cr, cosl)
    elsif ck == 1
      av1_iadst(t, log2h, cr, cosl)
    else
      av1_iidt(t, log2h)
    i = 0
    while i < h
      v = t[i]
      if csh > 0
        v = (v + (1 << (csh - 1))) >> csh
      res[i * w + j] = v
      i += 1
    j += 1
  0

-> av1_cos128(cosl, angle) (i32[] i64) i64
  a = (angle & 255) ## i64
  if a <= 64
    return cosl[a]
  if a <= 128
    return 0 - cosl[128 - a]
  if a <= 192
    return 0 - cosl[a - 128]
  cosl[256 - a]

-> av1_bfly(t, a, b, angle, flip, cosl) (i64[] i64 i64 i64 i64 i32[]) i64
  c = (av1_cos128(cosl, angle)) ## i64
  s = (av1_cos128(cosl, angle - 64)) ## i64
  x = (t[a] * c - t[b] * s) ## i64
  y = (t[a] * s + t[b] * c) ## i64
  x = (x + 2048) >> 12
  y = (y + 2048) >> 12
  if flip == 1
    t[a] = y
    t[b] = x
  else
    t[a] = x
    t[b] = y
  0

-> av1_had(t, a, b, flip, r) (i64[] i64 i64 i64 i64) i64
  if flip == 1
    tmp = (a) ## i64
    a = b
    b = tmp
  x = (t[a]) ## i64
  y = (t[b]) ## i64
  lo = (0 - (1 << (r - 1))) ## i64
  hi = ((1 << (r - 1)) - 1) ## i64
  s = (x + y) ## i64
  d = (x - y) ## i64
  s = lo if s < lo
  s = hi if s > hi
  d = lo if d < lo
  d = hi if d > hi
  t[a] = s
  t[b] = d
  0

-> av1_brev(nb, x) (i64 i64) i64
  r = 0 ## i64
  i = 0 ## i64
  while i < nb
    r += ((x >> i) & 1) << (nb - 1 - i)
    i += 1
  r

-> av1_idct(t, n, r, cosl) (i64[] i64 i64 i32[]) i64
  n0 = (1 << n) ## i64
  cp = i64[64]
  i = 0 ## i64
  while i < n0
    cp[i] = t[i]
    i += 1
  i = 0
  while i < n0
    t[i] = cp[av1_brev(n, i)]
    i += 1
  if n == 6
    i = 0
    while i < 16
      av1_bfly(t, 32 + i, 63 - i, 63 - 4 * av1_brev(4, i), 0, cosl)
      i += 1
  if n >= 5
    i = 0
    while i < 8
      av1_bfly(t, 16 + i, 31 - i, 6 + (av1_brev(3, 7 - i) << 3), 0, cosl)
      i += 1
  if n == 6
    i = 0
    while i < 16
      av1_had(t, 32 + i * 2, 33 + i * 2, i & 1, r)
      i += 1
  if n >= 4
    i = 0
    while i < 4
      av1_bfly(t, 8 + i, 15 - i, 12 + (av1_brev(2, 3 - i) << 4), 0, cosl)
      i += 1
  if n >= 5
    i = 0
    while i < 8
      av1_had(t, 16 + 2 * i, 17 + 2 * i, i & 1, r)
      i += 1
  if n == 6
    i = 0
    while i < 4
      j = 0 ## i64
      while j < 2
        av1_bfly(t, 62 - i * 4 - j, 33 + i * 4 + j, 60 - 16 * av1_brev(2, i) + 64 * j, 1, cosl)
        j += 1
      i += 1
  if n >= 3
    i = 0
    while i < 2
      av1_bfly(t, 4 + i, 7 - i, 56 - 32 * i, 0, cosl)
      i += 1
  if n >= 4
    i = 0
    while i < 4
      av1_had(t, 8 + 2 * i, 9 + 2 * i, i & 1, r)
      i += 1
  if n >= 5
    i = 0
    while i < 2
      j = 0 ## i64
      while j < 2
        av1_bfly(t, 30 - 4 * i - j, 17 + 4 * i + j, 24 + (j << 6) + ((1 - i) << 5), 1, cosl)
        j += 1
      i += 1
  if n == 6
    i = 0
    while i < 8
      j = 0 ## i64
      while j < 2
        av1_had(t, 32 + i * 4 + j, 35 + i * 4 - j, i & 1, r)
        j += 1
      i += 1
  i = 0
  while i < 2
    av1_bfly(t, 2 * i, 2 * i + 1, 32 + 16 * i, 1 - i, cosl)
    i += 1
  if n >= 3
    i = 0
    while i < 2
      av1_had(t, 4 + 2 * i, 5 + 2 * i, i, r)
      i += 1
  if n >= 4
    i = 0
    while i < 2
      av1_bfly(t, 14 - i, 9 + i, 48 + 64 * i, 1, cosl)
      i += 1
  if n >= 5
    i = 0
    while i < 4
      j = 0 ## i64
      while j < 2
        av1_had(t, 16 + 4 * i + j, 19 + 4 * i - j, i & 1, r)
        j += 1
      i += 1
  if n == 6
    i = 0
    while i < 2
      j = 0 ## i64
      while j < 4
        av1_bfly(t, 61 - i * 8 - j, 34 + i * 8 + j, 56 - i * 32 + (j >> 1) * 64, 1, cosl)
        j += 1
      i += 1
  i = 0
  while i < 2
    av1_had(t, i, 3 - i, 0, r)
    i += 1
  if n >= 3
    av1_bfly(t, 6, 5, 32, 1, cosl)
  if n >= 4
    i = 0
    while i < 2
      j = 0 ## i64
      while j < 2
        av1_had(t, 8 + 4 * i + j, 11 + 4 * i - j, i, r)
        j += 1
      i += 1
  if n >= 5
    i = 0
    while i < 4
      av1_bfly(t, 29 - i, 18 + i, 48 + (i >> 1) * 64, 1, cosl)
      i += 1
  if n == 6
    i = 0
    while i < 4
      j = 0 ## i64
      while j < 4
        av1_had(t, 32 + 8 * i + j, 39 + 8 * i - j, i & 1, r)
        j += 1
      i += 1
  if n >= 3
    i = 0
    while i < 4
      av1_had(t, i, 7 - i, 0, r)
      i += 1
  if n >= 4
    i = 0
    while i < 2
      av1_bfly(t, 13 - i, 10 + i, 32, 1, cosl)
      i += 1
  if n >= 5
    i = 0
    while i < 2
      j = 0 ## i64
      while j < 4
        av1_had(t, 16 + i * 8 + j, 23 + i * 8 - j, i, r)
        j += 1
      i += 1
  if n == 6
    i = 0
    while i < 8
      av1_bfly(t, 59 - i, 36 + i, i < 4 ? 48 : 112, 1, cosl)
      i += 1
  if n >= 4
    i = 0
    while i < 8
      av1_had(t, i, 15 - i, 0, r)
      i += 1
  if n >= 5
    i = 0
    while i < 4
      av1_bfly(t, 27 - i, 20 + i, 32, 1, cosl)
      i += 1
  if n == 6
    i = 0
    while i < 8
      av1_had(t, 32 + i, 47 - i, 0, r)
      av1_had(t, 48 + i, 63 - i, 1, r)
      i += 1
  if n >= 5
    i = 0
    while i < 16
      av1_had(t, i, 31 - i, 0, r)
      i += 1
  if n == 6
    i = 0
    while i < 8
      av1_bfly(t, 55 - i, 40 + i, 32, 1, cosl)
      i += 1
  if n == 6
    i = 0
    while i < 32
      av1_had(t, i, 63 - i, 0, r)
      i += 1
  0

-> av1_iadst_in_perm(t, n) (i64[] i64) i64
  n0 = (1 << n) ## i64
  cp = i64[16]
  i = 0 ## i64
  while i < n0
    cp[i] = t[i]
    i += 1
  i = 0
  while i < n0
    idx = ((i & 1) == 1 ? i - 1 : n0 - i - 1) ## i64
    t[i] = cp[idx]
    i += 1
  0

-> av1_iadst_out_perm(t, n) (i64[] i64) i64
  n0 = (1 << n) ## i64
  cp = i64[16]
  i = 0 ## i64
  while i < n0
    cp[i] = t[i]
    i += 1
  i = 0
  while i < n0
    a = ((i >> 3) & 1) ## i64
    b = (((i >> 2) & 1) ^ ((i >> 3) & 1)) ## i64
    c = (((i >> 1) & 1) ^ ((i >> 2) & 1)) ## i64
    d = ((i & 1) ^ ((i >> 1) & 1)) ## i64
    idx = (((d << 3) | (c << 2) | (b << 1) | a) >> (4 - n)) ## i64
    t[i] = (i & 1) == 1 ? 0 - cp[idx] : cp[idx]
    i += 1
  0

-> av1_iadst(t, n, r, cosl) (i64[] i64 i64 i32[]) i64
  if n == 2
    s0 = (1321 * t[0]) ## i64
    s1 = (2482 * t[0]) ## i64
    s2 = (3344 * t[1]) ## i64
    s3 = (3803 * t[2]) ## i64
    s4 = (1321 * t[2]) ## i64
    s5 = (2482 * t[3]) ## i64
    s6 = (3803 * t[3]) ## i64
    a7 = (t[0] - t[2]) ## i64
    b7 = (a7 + t[3]) ## i64
    s0 = s0 + s3
    s1 = s1 - s4
    s3 = s2
    s2 = 3344 * b7
    s0 = s0 + s5
    s1 = s1 - s6
    x0 = (s0 + s3) ## i64
    x1 = (s1 + s3) ## i64
    x2 = (s2) ## i64
    x3 = (s0 + s1) ## i64
    x3 = x3 - s3
    t[0] = (x0 + 2048) >> 12
    t[1] = (x1 + 2048) >> 12
    t[2] = (x2 + 2048) >> 12
    t[3] = (x3 + 2048) >> 12
    return 0
  if n == 3
    av1_iadst_in_perm(t, 3)
    i = 0 ## i64
    while i < 4
      av1_bfly(t, 2 * i, 2 * i + 1, 60 - 16 * i, 1, cosl)
      i += 1
    i = 0
    while i < 4
      av1_had(t, i, 4 + i, 0, r)
      i += 1
    i = 0
    while i < 2
      av1_bfly(t, 4 + 3 * i, 5 + i, 48 - 32 * i, 1, cosl)
      i += 1
    i = 0
    while i < 2
      j = 0 ## i64
      while j < 2
        av1_had(t, 4 * j + i, 2 + 4 * j + i, 0, r)
        j += 1
      i += 1
    i = 0
    while i < 2
      av1_bfly(t, 2 + 4 * i, 3 + 4 * i, 32, 1, cosl)
      i += 1
    av1_iadst_out_perm(t, 3)
    return 0
  av1_iadst_in_perm(t, 4)
  i = 0 ## i64
  while i < 8
    av1_bfly(t, 2 * i, 2 * i + 1, 62 - 8 * i, 1, cosl)
    i += 1
  i = 0
  while i < 8
    av1_had(t, i, 8 + i, 0, r)
    i += 1
  i = 0
  while i < 2
    av1_bfly(t, 8 + 2 * i, 9 + 2 * i, 56 - 32 * i, 1, cosl)
    av1_bfly(t, 13 + 2 * i, 12 + 2 * i, 8 + 32 * i, 1, cosl)
    i += 1
  i = 0
  while i < 4
    j = 0 ## i64
    while j < 2
      av1_had(t, 8 * j + i, 4 + 8 * j + i, 0, r)
      j += 1
    i += 1
  i = 0
  while i < 2
    j = 0 ## i64
    while j < 2
      av1_bfly(t, 4 + 8 * j + 3 * i, 5 + 8 * j + i, 48 - 32 * i, 1, cosl)
      j += 1
    i += 1
  i = 0
  while i < 2
    j = 0 ## i64
    while j < 4
      av1_had(t, 4 * j + i, 2 + 4 * j + i, 0, r)
      j += 1
    i += 1
  i = 0
  while i < 4
    av1_bfly(t, 2 + 4 * i, 3 + 4 * i, 32, 1, cosl)
    i += 1
  av1_iadst_out_perm(t, 4)
  0

-> av1_iidt(t, n) (i64[] i64) i64
  n0 = (1 << n) ## i64
  i = 0 ## i64
  while i < n0
    if n == 2
      t[i] = (t[i] * 5793 + 2048) >> 12
    elsif n == 3
      t[i] = t[i] * 2
    elsif n == 4
      t[i] = (t[i] * 11586 + 2048) >> 12
    else
      t[i] = t[i] * 4
    i += 1
  0

-> av1_iwht(t, shift) (i64[] i64) i64
  a = (t[0] >> shift) ## i64
  c = (t[1] >> shift) ## i64
  d = (t[2] >> shift) ## i64
  b = (t[3] >> shift) ## i64
  a += c
  d -= b
  e = ((a - d) >> 1) ## i64
  b = e - b
  c = e - c
  a -= b
  d += c
  t[0] = a
  t[1] = b
  t[2] = c
  t[3] = d
  0
