# core/codec/audio/opus_rangedec — the Opus range decoder (RFC 6716 §4.1), a port of
# libopus celt/entdec.c + laplace.c.
#
# State lives in an i64[EC_N] array (all values are unsigned 32-bit quantities
# held in i64), the bytes in a u8[] with `storage` valid bytes:
#   0 rng  1 val  2 rem  3 ext  4 nbits_total  5 offs  6 end_offs
#   7 end_window  8 nend_bits  9 storage  10 error
# Every function is typed so the hot paths compile to machine code.

EC_N = 12

-> ec_ilog(v) (i64) i64
  r = 0 ## i64
  x = v
  if x >= 65536
    x = x >> 16
    r += 16
  if x >= 256
    x = x >> 8
    r += 8
  if x >= 16
    x = x >> 4
    r += 4
  if x >= 4
    x = x >> 2
    r += 2
  if x >= 2
    x = x >> 1
    r += 1
  if x >= 1
    r += 1
  r

-> ec_read_byte(st, buf) (i64[] u8[]) i64
  o = st[5]
  if o < st[9]
    st[5] = o + 1
    return buf[o]
  0

-> ec_read_byte_from_end(st, buf) (i64[] u8[]) i64
  e = st[6]
  if e < st[9]
    e += 1
    st[6] = e
    return buf[st[9] - e]
  0

-> ec_normalize(st, buf) (i64[] u8[]) i64
  while st[0] <= 8388608
    st[4] = st[4] + 8
    st[0] = (st[0] << 8) & 4294967295
    sym = st[2]
    o = st[5]
    r = 0 ## i64
    if o < st[9]
      r = buf[o]
      st[5] = o + 1
    st[2] = r
    sym = ((sym << 8) | r) >> 1
    st[1] = ((st[1] << 8) + (255 ^ (sym & 255))) & 2147483647
  0

# Initialises the decoder over buf[0, storage).
-> ec_dec_init(st, buf, storage) (i64[] u8[] i64) i64
  st[9] = storage
  st[6] = 0
  st[7] = 0
  st[8] = 0
  st[4] = 9
  st[5] = 0
  st[0] = 128
  st[3] = 0
  st[2] = ec_read_byte(st, buf)
  st[1] = 128 - 1 - (st[2] >> 1)
  st[10] = 0
  ec_normalize(st, buf)

-> ec_decode(st, ft) (i64[] i64) i64
  ext = st[0] / ft
  st[3] = ext
  s = st[1] / ext
  s1 = s + 1
  s1 = ft if s1 > ft
  ft - s1

-> ec_decode_bin(st, bits) (i64[] i64) i64
  ext = st[0] >> bits
  st[3] = ext
  s = st[1] / ext
  ft = 1 << bits
  s1 = s + 1
  s1 = ft if s1 > ft
  ft - s1

-> ec_dec_update(st, buf, fl, fh, ft) (i64[] u8[] i64 i64 i64) i64
  s = st[3] * (ft - fh)
  st[1] = st[1] - s
  if fl > 0
    st[0] = st[3] * (fh - fl)
  else
    st[0] = st[0] - s
  ec_normalize(st, buf)

-> ec_dec_bit_logp(st, buf, logp) (i64[] u8[] i64) i64
  r = st[0]
  d = st[1]
  s = r >> logp
  ret = 0 ## i64
  if d < s
    ret = 1
    st[0] = s
  else
    st[1] = d - s
    st[0] = r - s
  ec_normalize(st, buf)
  ret

# icdf table: u8 values starting at tab[off].
-> ec_dec_icdf(st, buf, tab, off, ftb) (i64[] u8[] u8[] i64 i64) i64
  s = st[0]
  d = st[1]
  r = s >> ftb
  ret = -1 ## i64
  t = s
  while true
    t = s
    ret += 1
    s = r * tab[off + ret]
    break if d >= s
  st[1] = d - s
  st[0] = t - s
  ec_normalize(st, buf)
  ret

-> ec_dec_icdf16(st, buf, tab, off, ftb) (i64[] u8[] i32[] i64 i64) i64
  s = st[0]
  d = st[1]
  r = s >> ftb
  ret = -1 ## i64
  t = s
  while true
    t = s
    ret += 1
    s = r * tab[off + ret]
    break if d >= s
  st[1] = d - s
  st[0] = t - s
  ec_normalize(st, buf)
  ret

-> ec_dec_bits(st, buf, bits) (i64[] u8[] i64) i64
  window = st[7]
  available = st[8]
  if available < bits
    while available <= 24
      window = window | (ec_read_byte_from_end(st, buf) << available)
      available += 8
  ret = window & ((1 << bits) - 1)
  window = window >> bits
  available -= bits
  st[7] = window
  st[8] = available
  st[4] = st[4] + bits
  ret

-> ec_dec_uint(st, buf, ftin) (i64[] u8[] i64) i64
  ft = ftin - 1
  ftb = ec_ilog(ft)
  if ftb > 8
    ftb -= 8
    ft2 = (ft >> ftb) + 1
    s = ec_decode(st, ft2)
    ec_dec_update(st, buf, s, s + 1, ft2)
    t = (s << ftb) | ec_dec_bits(st, buf, ftb)
    return t if t <= ft
    st[10] = 1
    return ft
  s = ec_decode(st, ftin)
  ec_dec_update(st, buf, s, s + 1, ftin)
  s

-> ec_tell(st) (i64[]) i64
  st[4] - ec_ilog(st[0])

-> ec_tell_frac(st) (i64[]) i64
  nbits = st[4] << 3
  l = ec_ilog(st[0])
  r = st[0] >> (l - 16)
  b = (r >> 12) - 8
  c = 65535 ## i64
  if b == 0
    c = 35733
  elsif b == 1
    c = 38967
  elsif b == 2
    c = 42495
  elsif b == 3
    c = 46340
  elsif b == 4
    c = 50535
  elsif b == 5
    c = 55109
  elsif b == 6
    c = 60097
  b += 1 if r > c
  l = (l << 3) + b
  nbits - l

-> ec_laplace_decode(st, buf, fsin, decay) (i64[] u8[] i64 i64) i64
  fs = fsin
  val = 0 ## i64
  fm = ec_decode_bin(st, 15)
  fl = 0 ## i64
  if fm >= fs
    val += 1
    fl = fs
    fs = (((32768 - 32 - fs) * (16384 - decay)) >> 15) + 1
    while fs > 1 && fm >= fl + 2 * fs
      fs *= 2
      fl += fs
      fs = ((fs - 2) * decay) >> 15
      fs += 1
      val += 1
    if fs <= 1
      di = (fm - fl) >> 1
      val += di
      fl += 2 * di
    if fm < fl + fs
      val = 0 - val
    else
      fl += fs
  fh = fl + fs
  fh = 32768 if fh > 32768
  ec_dec_update(st, buf, fl, fh, 32768)
  val
