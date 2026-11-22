# core/codec/video/hevc_cabac — bitstream access for the HEVC decoder: emulation
# prevention removal, an Exp-Golomb bit reader for parameter sets and slice
# headers, and the CABAC arithmetic decoding engine (9.3.4.3).
#
# CABAC state lives in an i64[] (HB_*): range (9 bits, 256..510), value
# (scaled by 7 bits), bits_needed (-8..0) and the read position / end in the
# slice data u8[]. Context variables follow at HB_CTX as (state << 1) | MPS;
# HB_WPP / HB_DS hold the WPP and dependent-slice storage copies, HB_STAT the
# persistent Rice statistics.

use hevc_tables

HB_RANGE = 0
HB_VALUE = 1
HB_BITS = 2
HB_POS = 3
HB_END = 4
HB_STAT = 8
HB_STAT_WPP = 12
HB_STAT_DS = 16
HB_CTX = 32
HB_WPP = 256
HB_DS = 480
HB_SIZE = 704

+ HevcError < StandardError

# ---------------------------------------------------------------- NAL payloads

# Remove emulation prevention bytes from src[o, o+n). Returns [u8[] rbsp, size,
# positions (in the escaped stream, relative to o) of each removed byte].
-> hv_unescape(src, o, n)
  out = u8[n + 8]
  eps = i64[n / 3 + 2]
  r = hv_unesc(src, o, n, out, eps)
  m = r >> 32
  k = r & 0xffffffff
  epl = []
  i = 0
  while i < k
    epl.push(eps[i])
    i += 1
  [out, m, epl]

-> hv_unesc(src, o, n, out, eps) (u8[] i64 i64 u8[] i64[]) i64
  i = 0 ## i64
  m = 0 ## i64
  zeros = 0 ## i64
  k = 0 ## i64
  while i < n
    b = (src[o + i]) ## i64
    if zeros >= 2 && b == 3
      eps[k] = i
      k += 1
      zeros = 0
    else
      out[m] = b
      m += 1
      if b == 0
        zeros += 1
      else
        zeros = 0
    i += 1
  (m << 32) | k

# ---------------------------------------------------------------- header bit reader

+ HevcBits
  rw :d, :pos, :size

  -> new(@d, @size)
    @pos = 0

  -> u(n)
    v = hv_getbits(@d, @size, @pos, n)
    @pos += n
    v

  -> flag
    u(1) == 1

  -> ue
    z = 0
    while u(1) == 0
      z += 1
      raise HevcError.new("hevc: bad exp-golomb code") if z > 32
    return 0 if z == 0
    (1 << z) - 1 + u(z)

  -> se
    k = ue()
    (k & 1) == 1 ? (k + 1) >> 1 : 0 - (k >> 1)

  -> skip(n)
    @pos += n

  -> byte_align
    @pos = ((@pos + 7) >> 3) << 3

  -> more_rbsp?
    # true while data remains before the rbsp_stop_one_bit
    return false if @pos >= @size * 8
    last = @size - 1
    while last >= 0 && @d[last] == 0
      last -= 1
    return false if last < 0
    b = @d[last]
    tz = 0
    while ((b >> tz) & 1) == 0
      tz += 1
    stop = last * 8 + (7 - tz)
    @pos < stop

  -> left
    @size * 8 - @pos

-> hv_getbits(d, size, pos, n) (u8[] i64 i64 i64) i64
  v = 0 ## i64
  i = 0 ## i64
  while i < n
    p = (pos + i) ## i64
    by = (p >> 3) ## i64
    bit = 0 ## i64
    if by < size
      bit = (d[by] >> (7 - (p & 7))) & 1
    v = (v << 1) | bit
    i += 1
  v

# ---------------------------------------------------------------- CABAC engine

-> hv_cabac_start(cab, d, pos, last) (i64[] u8[] i64 i64) i64
  cab[HB_RANGE] = 510
  cab[HB_END] = last
  bits = 8 ## i64
  v = 0 ## i64
  p = (pos) ## i64
  if p < last
    v = d[p] << 8
    p += 1
    bits -= 8
  if p < last
    v = v | d[p]
    p += 1
    bits -= 8
  cab[HB_VALUE] = v
  cab[HB_BITS] = bits
  cab[HB_POS] = p
  0

# Initialise all contexts for initType at slice QP (9.3.2.2).
-> hv_ctx_init(cab, tb, init_type, qp) (i64[] i32[] i64 i64) i64
  q = (qp) ## i64
  q = 0 if q < 0
  q = 51 if q > 51
  i = 0 ## i64
  while i < HC_N
    iv = (tb[HT_CTXINIT + init_type * HC_N + i]) ## i64
    m = ((iv >> 4) * 5 - 45) ## i64
    n = (((iv & 15) << 3) - 16) ## i64
    pre = (((m * q) >> 4) + n) ## i64
    pre = 1 if pre < 1
    pre = 126 if pre > 126
    if pre <= 63
      cab[HB_CTX + i] = (63 - pre) << 1
    else
      cab[HB_CTX + i] = ((pre - 64) << 1) | 1
    i += 1
  k = 0 ## i64
  while k < 4
    cab[HB_STAT + k] = 0
    k += 1
  0

# copy contexts + stats: from region a to region b (HB_CTX / HB_WPP / HB_DS)
-> hv_ctx_copy(cab, a, b, sa, sb) (i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < HC_N
    cab[b + i] = cab[a + i]
    i += 1
  k = 0 ## i64
  while k < 4
    cab[sb + k] = cab[sa + k]
    k += 1
  0

# One context-coded bin; c is the context index (without HB_CTX).
-> hv_bin(cab, d, tb, c) (i64[] u8[] i32[] i64) i64
  ci = (HB_CTX + c) ## i64
  s = (cab[ci]) ## i64
  r = (cab[HB_RANGE]) ## i64
  lps = (tb[HT_LPS + ((s >> 1) << 2) + ((r >> 6) - 4)]) ## i64
  r -= lps
  v = (cab[HB_VALUE]) ## i64
  scaled = (r << 7) ## i64
  if v < scaled
    cab[ci] = tb[HT_MPS + s]
    if scaled < 32768
      cab[HB_RANGE] = scaled >> 6
      v = v << 1
      bn = (cab[HB_BITS] + 1) ## i64
      if bn == 0
        bn = -8
        p = (cab[HB_POS]) ## i64
        if p < cab[HB_END]
          v = v | d[p]
          cab[HB_POS] = p + 1
      cab[HB_BITS] = bn
      cab[HB_VALUE] = v
    else
      cab[HB_RANGE] = r
    return s & 1
  v = v - scaled
  nb = (tb[HT_RENORM + (lps >> 3)]) ## i64
  v = v << nb
  cab[HB_RANGE] = lps << nb
  cab[ci] = tb[HT_LPST + s]
  bn = cab[HB_BITS] + nb
  if bn >= 0
    p = cab[HB_POS]
    if p < cab[HB_END]
      v = v | (d[p] << bn)
      cab[HB_POS] = p + 1
    bn -= 8
  cab[HB_BITS] = bn
  cab[HB_VALUE] = v
  1 - (s & 1)

-> hv_bypass(cab, d) (i64[] u8[]) i64
  v = (cab[HB_VALUE] << 1) ## i64
  bn = (cab[HB_BITS] + 1) ## i64
  if bn >= 0
    p = (cab[HB_POS]) ## i64
    if p < cab[HB_END]
      v = v | d[p]
      cab[HB_POS] = p + 1
    bn = -8
  cab[HB_BITS] = bn
  scaled = (cab[HB_RANGE] << 7) ## i64
  if v >= scaled
    cab[HB_VALUE] = v - scaled
    return 1
  cab[HB_VALUE] = v
  0

-> hv_bypass_n(cab, d, n) (i64[] u8[] i64) i64
  r = 0 ## i64
  i = 0 ## i64
  while i < n
    r = (r << 1) | hv_bypass(cab, d)
    i += 1
  r

-> hv_term(cab, d) (i64[] u8[]) i64
  r = (cab[HB_RANGE] - 2) ## i64
  scaled = (r << 7) ## i64
  v = (cab[HB_VALUE]) ## i64
  if v >= scaled
    cab[HB_RANGE] = r
    return 1
  if scaled < 32768
    cab[HB_RANGE] = scaled >> 6
    v = v << 1
    bn = (cab[HB_BITS] + 1) ## i64
    if bn == 0
      bn = -8
      p = (cab[HB_POS]) ## i64
      if p < cab[HB_END]
        v = v + d[p]
        cab[HB_POS] = p + 1
    cab[HB_BITS] = bn
    cab[HB_VALUE] = v
  else
    cab[HB_RANGE] = r
  0
