# core/codec/audio/flac — a FLAC (RFC 9639) decoder for Blade's media pipeline.
#
#   acodec_register("flac", …): cfg.extra is the 34-byte STREAMINFO body; one
#   FLAC frame per MediaSample; decode(sample) -> AudioBlock (f32 interleaved,
#   s / 2^(bps-1)), in FLAC channel order (which is already WAVE order).
#   flac_es_parse(bytes) splits a native .flac file into samples:
#   {cfg:, samples:, duration:}.
#
# Everything RFC 9639 allows: CONSTANT / VERBATIM / FIXED / LPC (orders 1..32)
# subframes, Rice and Rice2 residuals with escape partitions, wasted bits,
# independent / left-side / side-right / mid-side channels, 4..32 bits per
# sample, fixed and variable block sizes. Samples are 64-bit integers while
# decoding (a 32-bit stream's side channel needs 33 bits, its LPC sums ~53).
# A frame whose CRC-8 / CRC-16 does not match, or whose subframes are
# malformed, decodes as silence of its block size (the stream keeps timing);
# a sample without a parsable frame header raises MediaError.
#
# Bit reader state is an i64[] st: st[0] bit position, st[1] byte limit,
# st[2] error flag (set when a read runs past the limit).

use core/codec/media

-> fl_mk_crc(poly, width) (i64 i64) i64[]
  t = i64[256]
  top = 1 << (width - 1)
  mask = (1 << width) - 1
  i = 0 ## i64
  while i < 256
    c = i << (width - 8)
    j = 0 ## i64
    while j < 8
      if (c & top) != 0
        c = ((c << 1) ^ poly) & mask
      else
        c = (c << 1) & mask
      j += 1
    t[i] = c
    i += 1
  t

# leading zero bits of an 8-bit value (8 for 0)
-> fl_mk_clz
  t = i64[256]
  i = 0
  while i < 256
    z = 0
    while z < 8 && (i & (128 >> z)) == 0
      z += 1
    t[i] = z
    i += 1
  t

FL_CRC8 = fl_mk_crc(7, 8)
FL_CRC16 = fl_mk_crc(32773, 16)
FL_CLZ = fl_mk_clz()

-> fl_crc8(b, a, e, t) (u8[] i64 i64 i64[]) i64
  c = 0 ## i64
  i = a
  while i < e
    c = t[c ^ b[i]]
    i += 1
  c

-> fl_crc16(b, a, e, t) (u8[] i64 i64 i64[]) i64
  c = 0 ## i64
  i = a
  while i < e
    c = ((c << 8) & 65535) ^ t[((c >> 8) ^ b[i]) & 255]
    i += 1
  c

# n (0..57) bits, most significant first.
-> fl_bits(b, st, n) (u8[] i64[] i64) i64
  if n <= 0
    return 0
  pos = st[0]
  nb = st[1]
  q = pos >> 3
  w = 0 ## i64
  if q + 8 <= nb
    w = (b[q] << 56) | (b[q + 1] << 48) | (b[q + 2] << 40) | (b[q + 3] << 32) | (b[q + 4] << 24) | (b[q + 5] << 16) | (b[q + 6] << 8) | b[q + 7]
  else
    j = 0 ## i64
    while j < 8
      w = w << 8
      if q + j < nb
        w = w | b[q + j]
      j += 1
  st[0] = pos + n
  if pos + n > nb * 8
    st[2] = 1
  ((w << (pos & 7)) >> (64 - n)) & ((1 << n) - 1)

-> fl_sbits(b, st, n) (u8[] i64[] i64) i64
  if n <= 0
    return 0
  v = fl_bits(b, st, n)
  if v >= (1 << (n - 1))
    v = v - (1 << n)
  v

# number of 0 bits before the next 1 bit (the 1 is consumed)
-> fl_unary(b, st, clz) (u8[] i64[] i64[]) i64
  pos = st[0]
  nb = st[1]
  q = 0 ## i64
  going = true
  while going
    by = pos >> 3
    if by >= nb
      st[2] = 1
      st[0] = pos
      return q
    x = (b[by] << (pos & 7)) & 255
    if x == 0
      adv = 8 - (pos & 7)
      q += adv
      pos += adv
    else
      z = clz[x]
      q += z
      pos += z + 1
      going = false
  st[0] = pos
  q

# cnt Rice-coded residuals with parameter k into out[o ..]
-> fl_rice(b, st, k, out, o, cnt, clz) (u8[] i64[] i64 i64[] i64 i64 i64[]) i64
  pos = st[0]
  nb = st[1]
  kmask = (1 << k) - 1
  i = 0 ## i64
  while i < cnt
    q = 0 ## i64
    going = true
    while going
      by = pos >> 3
      if by >= nb
        st[2] = 1
        st[0] = pos
        return -1
      x = (b[by] << (pos & 7)) & 255
      if x == 0
        adv = 8 - (pos & 7)
        q += adv
        pos += adv
      else
        z = clz[x]
        q += z
        pos += z + 1
        going = false
    low = 0 ## i64
    if k > 0
      qb = pos >> 3
      w = 0 ## i64
      if qb + 8 <= nb
        w = (b[qb] << 56) | (b[qb + 1] << 48) | (b[qb + 2] << 40) | (b[qb + 3] << 32) | (b[qb + 4] << 24) | (b[qb + 5] << 16) | (b[qb + 6] << 8) | b[qb + 7]
      else
        j = 0 ## i64
        while j < 8
          w = w << 8
          if qb + j < nb
            w = w | b[qb + j]
          j += 1
      low = ((w << (pos & 7)) >> (64 - k)) & kmask
      pos += k
    v = (q << k) | low
    out[o + i] = (v >> 1) ^ (0 - (v & 1))
    i += 1
  st[0] = pos
  if pos > nb * 8
    st[2] = 1
    return -1
  0

-> fl_residual(b, st, bs, order, s, s0, clz) (u8[] i64[] i64 i64 i64[] i64 i64[]) i64
  method = fl_bits(b, st, 2)
  if method > 1
    return -1
  pbits = 4 + method
  esc = (1 << pbits) - 1
  porder = fl_bits(b, st, 4)
  psz = bs >> porder
  if (psz << porder) != bs || psz < order
    return -1
  np = 1 << porder
  idx = s0 + order
  p = 0 ## i64
  while p < np
    n = psz
    n = psz - order if p == 0
    k = fl_bits(b, st, pbits)
    if k == esc
      w = fl_bits(b, st, 5)
      i = 0 ## i64
      while i < n
        s[idx + i] = fl_sbits(b, st, w)
        i += 1
    else
      return -1 if fl_rice(b, st, k, s, idx, n, clz) < 0
    if st[2] != 0
      return -1
    idx += n
    p += 1
  0

-> fl_fixed(s, s0, bs, order) (i64[] i64 i64 i64) i64
  i = s0 + order
  e = s0 + bs
  if order == 1
    while i < e
      s[i] = s[i] + s[i - 1]
      i += 1
  elsif order == 2
    while i < e
      s[i] = s[i] + 2 * s[i - 1] - s[i - 2]
      i += 1
  elsif order == 3
    while i < e
      s[i] = s[i] + 3 * s[i - 1] - 3 * s[i - 2] + s[i - 3]
      i += 1
  elsif order == 4
    while i < e
      s[i] = s[i] + 4 * s[i - 1] - 6 * s[i - 2] + 4 * s[i - 3] - s[i - 4]
      i += 1
  0

-> fl_lpc(s, s0, bs, order, coef, shift) (i64[] i64 i64 i64 i64[] i64) i64
  i = s0 + order
  e = s0 + bs
  if order == 8
    c0 = coef[0]
    c1 = coef[1]
    c2 = coef[2]
    c3 = coef[3]
    c4 = coef[4]
    c5 = coef[5]
    c6 = coef[6]
    c7 = coef[7]
    while i < e
      sum = c0 * s[i - 1] + c1 * s[i - 2] + c2 * s[i - 3] + c3 * s[i - 4] + c4 * s[i - 5] + c5 * s[i - 6] + c6 * s[i - 7] + c7 * s[i - 8]
      s[i] = s[i] + (sum >> shift)
      i += 1
    return 0
  while i < e
    sum = 0 ## i64
    j = 0 ## i64
    while j < order
      sum += coef[j] * s[i - 1 - j]
      j += 1
    s[i] = s[i] + (sum >> shift)
    i += 1
  0

# One subframe of bs samples, sbps bits, into s[s0 ..]. 0 ok, -1 malformed.
-> fl_subframe(b, st, sbps, bs, s, s0, coef, clz) (u8[] i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  if fl_bits(b, st, 1) != 0
    return -1
  typ = fl_bits(b, st, 6)
  wasted = 0 ## i64
  if fl_bits(b, st, 1) == 1
    wasted = fl_unary(b, st, clz) + 1
    if wasted >= sbps
      return -1
    sbps -= wasted
  if typ == 0
    v = fl_sbits(b, st, sbps)
    i = 0 ## i64
    while i < bs
      s[s0 + i] = v
      i += 1
  elsif typ == 1
    i = 0 ## i64
    while i < bs
      s[s0 + i] = fl_sbits(b, st, sbps)
      i += 1
  elsif typ >= 8 && typ <= 12
    order = typ - 8
    return -1 if order > bs
    i = 0 ## i64
    while i < order
      s[s0 + i] = fl_sbits(b, st, sbps)
      i += 1
    return -1 if fl_residual(b, st, bs, order, s, s0, clz) < 0
    fl_fixed(s, s0, bs, order)
  elsif typ >= 32
    order = typ - 31
    return -1 if order > bs
    i = 0 ## i64
    while i < order
      s[s0 + i] = fl_sbits(b, st, sbps)
      i += 1
    prec = fl_bits(b, st, 4) + 1
    return -1 if prec == 16
    shift = fl_sbits(b, st, 5)
    return -1 if shift < 0
    i = 0
    while i < order
      coef[i] = fl_sbits(b, st, prec)
      i += 1
    return -1 if fl_residual(b, st, bs, order, s, s0, clz) < 0
    fl_lpc(s, s0, bs, order, coef, shift)
  else
    return -1
  if st[2] != 0
    return -1
  if wasted > 0
    i = 0 ## i64
    while i < bs
      s[s0 + i] = s[s0 + i] << wasted
      i += 1
  0

FL_RATES = [0, 88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000]
FL_BPS = [0, 8, 12, 0, 16, 20, 24, 32]

-> fl_rate_code(c) (i64) i64
  return 88200 if c == 1
  return 176400 if c == 2
  return 192000 if c == 3
  return 8000 if c == 4
  return 16000 if c == 5
  return 22050 if c == 6
  return 24000 if c == 7
  return 32000 if c == 8
  return 44100 if c == 9
  return 48000 if c == 10
  return 96000 if c == 11
  0

# Frame header at b[at] (nb = byte limit). hi gets: 0 block size, 1 sample
# rate (0 = STREAMINFO's), 2 channel assignment, 3 bits per sample (0 =
# STREAMINFO's), 4 frame/sample number, 5 blocking strategy, 6 header end
# (byte offset after CRC-8), 7 channels. Returns 0, or -1 when invalid
# (including a CRC-8 mismatch: -2).
-> fl_header(b, at, nb, hi, crc8) (u8[] i64 i64 i64[] i64[]) i64
  return -1 if at + 6 > nb
  return -1 if b[at] != 255 || (b[at + 1] & 254) != 248
  strat = b[at + 1] & 1
  bsc = b[at + 2] >> 4
  rc = b[at + 2] & 15
  ca = b[at + 3] >> 4
  ssc = (b[at + 3] >> 1) & 7
  return -1 if (b[at + 3] & 1) != 0
  return -1 if bsc == 0 || rc == 15 || ca > 10 || ssc == 3
  p = at + 4
  c0 = b[p]
  p += 1
  num = 0 ## i64
  extra = 0 ## i64
  if c0 < 128
    num = c0
  elsif c0 >= 192 && c0 < 224
    num = c0 & 31
    extra = 1
  elsif c0 >= 224 && c0 < 240
    num = c0 & 15
    extra = 2
  elsif c0 >= 240 && c0 < 248
    num = c0 & 7
    extra = 3
  elsif c0 >= 248 && c0 < 252
    num = c0 & 3
    extra = 4
  elsif c0 >= 252 && c0 < 254
    num = c0 & 1
    extra = 5
  elsif c0 == 254
    num = 0
    extra = 6
  else
    return -1
  return -1 if strat == 0 && extra > 5
  return -1 if p + extra + 5 > nb
  k = 0 ## i64
  while k < extra
    cb = b[p]
    return -1 if (cb & 192) != 128
    num = (num << 6) | (cb & 63)
    p += 1
    k += 1
  bs = 0 ## i64
  if bsc == 1
    bs = 192
  elsif bsc <= 5
    bs = 576 << (bsc - 2)
  elsif bsc == 6
    bs = b[p] + 1
    p += 1
  elsif bsc == 7
    bs = ((b[p] << 8) | b[p + 1]) + 1
    p += 2
  else
    bs = 256 << (bsc - 8)
  rate = 0 ## i64
  if rc == 12
    rate = b[p] * 1000
    p += 1
  elsif rc == 13
    rate = (b[p] << 8) | b[p + 1]
    p += 2
  elsif rc == 14
    rate = ((b[p] << 8) | b[p + 1]) * 10
    p += 2
  else
    rate = fl_rate_code(rc)
  bps = 0 ## i64
  if ssc == 1
    bps = 8
  elsif ssc == 2
    bps = 12
  elsif ssc == 4
    bps = 16
  elsif ssc == 5
    bps = 20
  elsif ssc == 6
    bps = 24
  elsif ssc == 7
    bps = 32
  return -1 if p >= nb
  crc = fl_crc8(b, at, p, crc8)
  ch = ca + 1
  ch = 2 if ca >= 8
  hi[0] = bs
  hi[1] = rate
  hi[2] = ca
  hi[3] = bps
  hi[4] = num
  hi[5] = strat
  hi[6] = p + 1
  hi[7] = ch
  return -2 if crc != b[p]
  0

# Decode the subframes of the frame whose header is in hi into s (channel c at
# c * stride), decorrelated. Returns the byte offset of the frame end (after
# CRC-16) or -1 when malformed / -2 on a CRC-16 mismatch.
-> fl_frame(b, at, nb, hi, bps, s, stride, coef, st, clz, crc16) (u8[] i64 i64 i64[] i64 i64[] i64 i64[] i64[] i64[] i64[]) i64
  bs = hi[0]
  ca = hi[2]
  ch = hi[7]
  st[0] = hi[6] * 8
  st[1] = nb
  st[2] = 0
  c = 0 ## i64
  while c < ch
    sb = bps
    if (ca == 8 && c == 1) || (ca == 9 && c == 0) || (ca == 10 && c == 1)
      sb = bps + 1
    return -1 if fl_subframe(b, st, sb, bs, s, c * stride, coef, clz) < 0
    c += 1
  pos = (st[0] + 7) >> 3
  return -1 if pos + 2 > nb
  if fl_crc16(b, at, pos + 2, crc16) != 0
    return -2
  i = 0 ## i64
  if ca == 8
    while i < bs
      s[stride + i] = s[i] - s[stride + i]
      i += 1
  elsif ca == 9
    while i < bs
      s[i] = s[i] + s[stride + i]
      i += 1
  elsif ca == 10
    while i < bs
      sd = s[stride + i]
      m = (s[i] << 1) | (sd & 1)
      s[i] = (m + sd) >> 1
      s[stride + i] = (m - sd) >> 1
      i += 1
  pos + 2

-> fl_to_f32(s, stride, ch, bs, out, scale) (i64[] i64 i64 i64 f32[] f64) i64
  c = 0 ## i64
  while c < ch
    i = 0 ## i64
    o = c
    base = c * stride
    while i < bs
      out[o] = (s[base + i] * scale) ## f32
      o += ch
      i += 1
    c += 1
  0

-> fl_copy(src, a, dst, n) (u8[] i64 u8[] i64) i64
  i = 0 ## i64
  while i < n
    dst[i] = src[a + i]
    i += 1
  n

-> fl_err(msg)
  raise MediaError.new("flac: " + msg)

-> fl_bytes(d)
  if d.is_a?(String)
    return ccall("w_string_bytes_view", d) ## u8[]
  d

# STREAMINFO body -> {min_bs, max_bs, rate, channels, bps, total}
-> flac_streaminfo(x)
  b = fl_bytes(x)
  fl_err("STREAMINFO too short") if b == nil || b.size < 18
  {min_bs: (b[0] << 8) | b[1], max_bs: (b[2] << 8) | b[3],
   rate: (b[10] << 12) | (b[11] << 4) | (b[12] >> 4),
   channels: ((b[12] >> 1) & 7) + 1,
   bps: (((b[12] & 1) << 4) | (b[13] >> 4)) + 1,
   total: ((b[13] & 15) << 32) | (b[14] << 24) | (b[15] << 16) | (b[16] << 8) | b[17]}

+ FlacDec
  ro :rate, :channels, :bps, :last_ints, :last_stride, :last_frames, :last_channels, :crc_errors

  -> new(cfg)
    @reuse = cfg.is_a?(CodecConfig) && cfg.reuse_output == true
    @obuf = nil
    @si = nil
    @rate = cfg.sample_rate
    @channels = cfg.channels
    @bps = 16
    if cfg.extra != nil
      @si = flac_streaminfo(cfg.extra)
      @rate = @si[:rate]
      @channels = @si[:channels]
      @bps = @si[:bps]
    @stride = 4608
    @stride = @si[:max_bs] if @si != nil && @si[:max_bs] > @stride
    @s = i64[@stride * 8]
    @coef = i64[32]
    @st = i64[4]
    @hi = i64[8]
    @last_ints = @s
    @last_stride = @stride
    @last_frames = 0
    @last_channels = 0
    @crc_errors = 0

  -> reset
    nil

  -> flush
    nil

  -> decode(sample)
    b = fl_bytes(sample.data)
    nb = b.size
    hi = @hi
    r = fl_header(b, 0, nb, hi, FL_CRC8)
    fl_err("bad frame header") if r == -1
    bs = hi[0]
    ch = hi[7]
    rate = hi[1]
    rate = @rate if rate == 0
    bps = hi[3]
    bps = @bps if bps == 0
    fl_err("bad sample rate") if rate <= 0
    if bs > @stride
      @stride = bs
      @s = i64[@stride * 8]
    @obuf = audio_out(@obuf, @reuse, bs * ch)
    out = @obuf ## f32[]
    ok = false
    if r == 0
      e = fl_frame(b, 0, nb, hi, bps, @s, @stride, @coef, @st, FL_CLZ, FL_CRC16)
      ok = e > 0
    if ok
      scale = ~1.0 / ((1 << (bps - 1)) ## f64)
      fl_to_f32(@s, @stride, ch, bs, out, scale)
      @last_frames = bs
    else
      @crc_errors += 1
      @last_frames = 0
      fl_zero_f32(out, bs * ch) if @reuse
    @last_ints = @s
    @last_stride = @stride
    @last_channels = ch
    blk = AudioBlock.new(out, bs, ch, rate, sample.pts)
    blk.owned = !@reuse
    blk

-> fl_zero_f32(a, n) (f32[] i64) i64
  i = 0
  while i < n
    a[i] = (~0.0 ## f32)
    i += 1
  n

acodec_register("flac", ->(cfg) FlacDec.new(cfg))

# Scan forward from p for the end of the frame starting at `start`: the first
# offset q (> p) where the CRC-16 of [start, q) is 0 and either q == nb or a
# valid frame header with the same blocking strategy begins at q. Returns q,
# or -1 when no such point exists.
-> fl_frame_end(b, start, p, nb, strat, ch, hi, crc8, crc16) (u8[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  c = 0 ## i64
  i = start
  while i < p
    c = ((c << 8) & 65535) ^ crc16[((c >> 8) ^ b[i]) & 255]
    i += 1
  while i < nb
    c = ((c << 8) & 65535) ^ crc16[((c >> 8) ^ b[i]) & 255]
    i += 1
    if c == 0
      if i == nb
        return i
      if b[i] == 255 && i + 1 < nb && (b[i + 1] & 254) == 248
        if fl_header(b, i, nb, hi, crc8) == 0 && hi[5] == strat
          return i
  -1

# A STREAMINFO body for the given parameters (block sizes both bs, no total).
-> flac_make_streaminfo(bs, rate, ch, bps)
  d = u8[34]
  d[0] = (bs >> 8) & 255
  d[1] = bs & 255
  d[2] = d[0]
  d[3] = d[1]
  d[10] = (rate >> 12) & 255
  d[11] = (rate >> 4) & 255
  d[12] = ((rate & 15) << 4) | (((ch - 1) & 7) << 1) | (((bps - 1) >> 4) & 1)
  d[13] = ((bps - 1) & 15) << 4
  d

# Native .flac file -> {cfg:, samples:, duration:}
-> flac_es_parse(bytes)
  b = fl_bytes(bytes)
  nb = b.size
  p = 0
  # ID3v2 tags (possibly several)
  while p + 10 <= nb && b[p] == 73 && b[p + 1] == 68 && b[p + 2] == 51
    sz = ((b[p + 6] & 127) << 21) | ((b[p + 7] & 127) << 14) | ((b[p + 8] & 127) << 7) | (b[p + 9] & 127)
    foot = 0
    foot = 10 if (b[p + 5] & 16) != 0
    p += 10 + sz + foot
  si_body = nil
  last = true
  if p + 4 <= nb && b[p] == 102 && b[p + 1] == 76 && b[p + 2] == 97 && b[p + 3] == 67
    p += 4
    last = false
  while !last
    fl_err("truncated metadata") if p + 4 > nb
    last = (b[p] & 128) != 0
    typ = b[p] & 127
    len = (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]
    p += 4
    if p + len > nb || typ == 127
      # a broken block: stop reading metadata and resync on frame headers
      last = true
    else
      if typ == 0 && si_body == nil && len >= 34
        si_body = u8[34]
        fl_copy(b, p, si_body, 34)
      p += len
  hi = i64[8]
  if si_body == nil
    # no fLaC marker / STREAMINFO: describe the stream from its first frame header
    q = p
    while q < nb && fl_header(b, q, nb, hi, FL_CRC8) != 0
      q += 1
    fl_err("no STREAMINFO and no frame") if q >= nb || hi[1] == 0 || hi[3] == 0
    si_body = flac_make_streaminfo(hi[0], hi[1], hi[7], hi[3])
  si = flac_streaminfo(si_body)
  rate = si[:rate]
  fl_err("bad sample rate") if rate <= 0
  cfg = CodecConfig.new("flac", si_body)
  cfg.sample_rate = rate
  cfg.channels = si[:channels]
  samples = []
  # first frame
  while p < nb && fl_header(b, p, nb, hi, FL_CRC8) != 0
    p += 1
  strat = hi[5]
  ch = si[:channels]
  fixed_bs = si[:min_bs]
  fixed_bs = 0 if si[:min_bs] != si[:max_bs]
  acc = 0
  while p < nb
    if fl_header(b, p, nb, hi, FL_CRC8) != 0
      p += 1
    else
      bs = hi[0]
      num = hi[4]
      fstrat = hi[5]
      e = fl_frame_end(b, p, hi[6] + 2, nb, strat, ch, hi, FL_CRC8, FL_CRC16)
      e = nb if e < 0
      n = e - p
      d = u8[n]
      fl_copy(b, p, d, n)
      first = acc
      if fstrat == 1
        first = num
      elsif fixed_bs > 0
        first = num * fixed_bs
      samples.push(MediaSample.new(d, first / (rate * ~1.0), first / (rate * ~1.0), bs / (rate * ~1.0), true))
      acc = first + bs
      p = e
  total = si[:total]
  total = acc if total == 0
  {cfg: cfg, samples: samples, duration: total / (rate * ~1.0)}

# Raw elementary-stream files (.mp3 / .aac ADTS / .flac) go through this parser.
es_parser_register(:flac, ->(b) flac_es_parse(b))
