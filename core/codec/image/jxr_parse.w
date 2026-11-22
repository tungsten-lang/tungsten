# core/codec/image/jxr_parse — JPEG XR (ITU-T T.832) codestream parsing and entropy decoding.
#
# The bit reader is MSB-first over a u8[] with the absolute bit position in
# br[0] (br[1] = byte offset of the tile data, the base for index-table seeks;
# br[2] = 1 once a read ran past the end of the data).
#
# Adaptive state for one image plane lives in st (i64[JXR_ST_SIZE]):
#   0..99    20 adaptive VLC tables × (table, deltatable, delta2table, disc, disc2)
#   100..111 DC / LP / HP models (bits0, bits1, state0, state1)
#   112..117 HP CBP model (state0, state1, count0[2], count1[2])
#   118, 119 CBPLP zero/max counters
#   120..209 adaptive scan orders + totals (LP, HP horizontal, HP vertical)
#   210      TRIM_FLEXBITS
#
# Coefficients for a plane are stored per macroblock and channel in an i32[]
# of 256 entries, the layout the reference decoder uses: [0] DC, [1..15] LP in
# raster order of the 4x4 DC/LP block, [16 + 15*blk + k] HP of block blk
# (raster block index inside the macroblock) at raster position k + 1.

-> jxr_t(a)
  r = i64[a.size]
  i = 0
  while i < a.size
    r[i] = a[i]
    i += 1
  r

JXR_ST_SIZE = 220

# ABSLEVEL_INDEX code tables (Table 63)
JXR_ABS0B = jxr_t([5, 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_ABS0V = jxr_t([5, 5, 6, 6, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_ABS1B = jxr_t([6, 6, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
JXR_ABS1V = jxr_t([5, 6, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
JXR_ABS_DELTA = jxr_t([1, 0, -1, -1, -1, -1, -1])
JXR_ABS_REMAP = jxr_t([2, 3, 4, 6, 10, 14])
JXR_ABS_FIXED = jxr_t([0, 0, 1, 2, 2, 2])

# FIRST_INDEX code tables (Table 59), indexed by the bits after any prefix
JXR_FI0B = jxr_t([6, 6, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_FI0V = jxr_t([2, 3, 1, 1, 0, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9, 4, 4, 4, 4, 6, 6, 6, 6, 8, 8, 8, 8, 10, 10, 10, 10, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11])
JXR_FI1B = jxr_t([6, 6, 5, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_FI1V = jxr_t([2, 3, 10, 10, 1, 1, 6, 6, 0, 0, 0, 0, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11, 11, 11, 11, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7])
JXR_FI2B = jxr_t([7, 7, 7, 7, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_FI2V = jxr_t([2, 3, 6, 10, 4, 4, 4, 4, 11, 11, 11, 11, 11, 11, 11, 11, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
JXR_FI3B = jxr_t([7, 7, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_FI3V = jxr_t([2, 6, 10, 10, 3, 3, 3, 3, 4, 4, 4, 4, 8, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
JXR_FI4B = jxr_t([7, 7, 6, 6, 6, 6, 6, 6, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
JXR_FI4V = jxr_t([6, 10, 2, 2, 4, 4, 8, 8, 11, 11, 11, 11, 11, 11, 11, 11, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5])
JXR_FI_DELTA = jxr_t([1, 1, 1, 1, 1, 0, 0, -1, 2, 1, 0, 0, 2, 2, -1, -1, -1, 0, -2, -1, 0, 0, -2, -1, -1, 1, 0, 2, 0, 0, 0, 0, -2, 0, 1, 1, 0, 1, 0, 1, -2, 0, -1, -1, -2, -1, -2, -2])
JXR_IX_DELTA = jxr_t([-1, 1, 1, 1, 0, 1, -2, 0, 0, 2, 0, 0, -1, -1, 0, 1, -2, 0])
JXR_RUN_BIN = jxr_t([-1, -1, -1, -1, 2, 2, 2, 1, 1, 1, 1, 0, 0, 0, 0])
JXR_RUN_FIXED = jxr_t([0, 0, 1, 1, 3, 0, 0, 1, 1, 2, 0, 0, 0, 0, 1])
JXR_RUN_REMAP = jxr_t([1, 2, 3, 5, 7, 1, 2, 3, 5, 7, 1, 2, 3, 4, 5])
JXR_BLK0B = jxr_t([5, 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
JXR_BLK0V = jxr_t([1, 3, 4, 7, 2, 2, 8, 8, 0, 0, 0, 0, 6, 6, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5])
JXR_BLK1B = jxr_t([6, 6, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
JXR_BLK1V = jxr_t([7, 4, 6, 6, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
JXR_CBPLP_B = jxr_t([1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 4, 4, 4, 4, 4, 4])
JXR_CBPLP_V = jxr_t([0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7])
JXR_SCAN_TOTALS = jxr_t([32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4])
JXR_SCAN_LP = jxr_t([4, 1, 5, 8, 2, 9, 6, 12, 3, 10, 13, 7, 14, 11, 15])
JXR_SCAN_VER = jxr_t([1, 2, 5, 4, 3, 6, 9, 8, 7, 12, 15, 13, 10, 11, 14])
JXR_HP_SCAN_MAP = jxr_t([0, 1, 4, 5, 2, 3, 6, 7, 8, 9, 12, 13, 10, 11, 14, 15])
JXR_TRANSPOSE444 = jxr_t([0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15])
JXR_TRANSPOSE420 = jxr_t([0, 2, 1, 3])
JXR_TRANSPOSE422 = jxr_t([0, 2, 1, 3, 4, 6, 5, 7])
JXR_LPCHR_REMAP = jxr_t([4, 1, 2, 3, 5, 6, 7])
JXR_CBP_FLC = jxr_t([0, 2, 1, 2, 2, 0])
JXR_CBP_OFF = jxr_t([0, 4, 2, 8, 12, 1])
JXR_CBP_OUT = jxr_t([0, 15, 3, 12, 1, 2, 4, 8, 5, 6, 9, 10, 7, 11, 13, 14])
JXR_BLKCBP_D5 = jxr_t([0, -1, 0, 1, 1])
JXR_BLKCBP_D9 = jxr_t([2, 2, 1, 1, -1, -2, -2, -2, -3])
JXR_W1 = jxr_t([0, 240, 120, 80, 60, 48, 40, 34, 30, 27, 24, 22, 20, 18, 17, 16, 0, 12, 6, 4, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 0, 16, 8, 5, 4, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1])

# ---------------------------------------------------------------- bit reader

-> jxr_get(src, br, n) (u8[] i64[] i64) i64
  if n <= 0
    return 0
  p = br[0]
  b = p >> 3
  sz = src.size
  v = 0 ## i64
  if b + 5 <= sz
    v = (src[b] << 32) | (src[b + 1] << 24) | (src[b + 2] << 16) | (src[b + 3] << 8) | src[b + 4]
  else
    k = 0 ## i64
    while k < 5
      v = v << 8
      if b + k < sz
        v = v | src[b + k]
      k += 1
    br[2] = 1 if b + ((p & 7) + n + 7) / 8 > sz
  br[0] = p + n
  one = 1 ## i64
  (v >> (40 - (p & 7) - n)) & ((one << n) - 1)

-> jxr_bit(src, br) (u8[] i64[]) i64
  p = br[0]
  br[0] = p + 1
  b = p >> 3
  if b >= src.size
    br[2] = 1
    return 0
  (src[b] >> (7 - (p & 7))) & 1

-> jxr_sync(br) (i64[]) i64
  br[0] = (br[0] + 7) & (0 - 8)
  0

# Table-driven prefix decode (the reference's intE): cb[i] gives the code
# length of the prefix whose bits, left-aligned to cs bits, equal i.
-> jxr_inte(src, br, cs, cb, cv) (u8[] i64[] i64 i64[] i64[]) i64
  bits = 0 ## i64
  val = 0 ## i64
  while cb[val << (cs - bits)] != bits
    val = (val << 1) | jxr_bit(src, br)
    bits += 1
    if bits > cs
      br[2] = 1
      return 0
  cv[val << (cs - bits)]

-> jxr_vlw(src, br) (u8[] i64[]) i64
  v = jxr_get(src, br, 8)
  if v < 0xFB
    return v * 256 + jxr_get(src, br, 8)
  if v == 0xFB
    return jxr_get(src, br, 32)
  if v == 0xFC
    hi = jxr_get(src, br, 32)
    return (hi << 32) + jxr_get(src, br, 32)
  0

# ---------------------------------------------------------------- adaptive VLC state

-> jxr_init_vlc(st, i) (i64[] i64) i64
  o = i * 5
  st[o] = 0
  st[o + 1] = 0
  st[o + 3] = 0
  0

-> jxr_init_vlc2(st, i) (i64[] i64) i64
  o = i * 5
  st[o] = 1
  st[o + 1] = 0
  st[o + 2] = 1
  st[o + 3] = 0
  st[o + 4] = 0
  0

-> jxr_adapt_vlc(st, i) (i64[] i64) i64
  o = i * 5
  st[o + 1] = 0
  d = st[o + 3]
  if d < -8 && st[o] != 0
    st[o] = st[o] - 1
    st[o + 3] = 0
  elsif d > 8 && st[o] != 1
    st[o] = st[o] + 1
    st[o + 3] = 0
  else
    st[o + 3] = -64 if d < -64
    st[o + 3] = 64 if d > 64
  0

-> jxr_adapt_vlc2(st, i, max_index) (i64[] i64 i64) i64
  o = i * 5
  lo = st[o + 3]
  hi = st[o + 4]
  changed = 0 ## i64
  if lo < -8 && st[o] > 0
    st[o] = st[o] - 1
    changed = 1
  elsif hi > 8 && st[o] < max_index
    st[o] = st[o] + 1
    changed = 1
  if changed == 1
    st[o + 3] = 0
    st[o + 4] = 0
    t = st[o]
    if t == max_index
      st[o + 1] = t - 1
      st[o + 2] = t - 1
    elsif t == 0
      st[o + 1] = 0
      st[o + 2] = 0
    else
      st[o + 1] = t - 1
      st[o + 2] = t
  else
    st[o + 3] = -64 if lo < -64
    st[o + 3] = 64 if lo > 64
    st[o + 4] = -64 if hi < -64
    st[o + 4] = 64 if hi > 64
  0

-> jxr_adapt_lp(st) (i64[]) i64
  jxr_adapt_vlc2(st, 2, 4)
  jxr_adapt_vlc2(st, 7, 3)
  jxr_adapt_vlc2(st, 8, 3)
  jxr_adapt_vlc2(st, 9, 4)
  jxr_adapt_vlc2(st, 10, 3)
  jxr_adapt_vlc2(st, 11, 3)
  jxr_adapt_vlc(st, 3)
  jxr_adapt_vlc(st, 4)
  0

-> jxr_adapt_hp(st) (i64[]) i64
  jxr_adapt_vlc2(st, 16, 4)
  jxr_adapt_vlc2(st, 14, 3)
  jxr_adapt_vlc2(st, 15, 3)
  jxr_adapt_vlc2(st, 17, 4)
  jxr_adapt_vlc2(st, 18, 3)
  jxr_adapt_vlc2(st, 19, 3)
  jxr_adapt_vlc(st, 5)
  jxr_adapt_vlc(st, 6)
  jxr_adapt_vlc(st, 12)
  jxr_adapt_vlc(st, 13)
  0

-> jxr_init_model(st, o, band) (i64[] i64 i64) i64
  st[o] = (2 - band) * 4
  st[o + 1] = (2 - band) * 4
  st[o + 2] = 0
  st[o + 3] = 0
  0

-> jxr_update_model(st, o, lap0, lap1, band, clr, nch) (i64[] i64 i64 i64 i64 i64 i64) i64
  w1 = JXR_W1 ## i64[]
  l0 = lap0
  l1 = lap1
  if band == 0
    l0 = l0 * 240
  elsif band == 1
    l0 = l0 * 12
  if clr == 1
    if band == 0
      l1 = l1 * 120
    elsif band == 1
      l1 = l1 * 37
    else
      l1 = l1 * 2
  elsif clr == 2
    if band == 0
      l1 = l1 * 120
    elsif band == 1
      l1 = l1 * 18
  else
    l1 = l1 * w1[band * 16 + nch - 1]
    l1 = l1 >> 4 if band == 2
  j = 0 ## i64
  while j < 2
    lm = l0
    lm = l1 if j == 1
    ms = st[o + 2 + j]
    delta = (lm - 70) >> 2
    if delta <= -8
      delta += 4
      delta = -16 if delta < -16
      ms += delta
      if ms < -8
        if st[o + j] == 0
          ms = -8
        else
          ms = 0
          st[o + j] = st[o + j] - 1
    elsif delta >= 8
      delta -= 4
      delta = 15 if delta > 15
      ms += delta
      if ms > 8
        if st[o + j] >= 15
          st[o + j] = 15
          ms = 8
        else
          ms = 0
          st[o + j] = st[o + j] + 1
    st[o + 2 + j] = ms
    j += 1
    j = 2 if clr == 0
  0

-> jxr_init_scan_lp(st) (i64[]) i64
  so = JXR_SCAN_LP ## i64[]
  tt = JXR_SCAN_TOTALS ## i64[]
  i = 0 ## i64
  while i < 15
    st[120 + i] = so[i]
    st[135 + i] = tt[i]
    i += 1
  0

-> jxr_init_scan_hp(st) (i64[]) i64
  so = JXR_SCAN_LP ## i64[]
  sv = JXR_SCAN_VER ## i64[]
  tt = JXR_SCAN_TOTALS ## i64[]
  i = 0 ## i64
  while i < 15
    st[150 + i] = so[i]
    st[165 + i] = tt[i]
    st[180 + i] = sv[i]
    st[195 + i] = tt[i]
    i += 1
  0

-> jxr_reset_totals(st, o) (i64[] i64) i64
  tt = JXR_SCAN_TOTALS ## i64[]
  i = 0 ## i64
  while i < 15
    st[o + i] = tt[i]
    i += 1
  0

# Adaptive scan: place value at the position the scan order maps i to, then
# bubble the position forward when it became more frequent than its predecessor.
-> jxr_scan_put(st, so, out, oo, i, value) (i64[] i64 i64[] i64 i64 i64) i64
  k = st[so + i - 1]
  out[oo + k] = value
  tot = so + 15
  st[tot + i - 1] = st[tot + i - 1] + 1
  if i > 1 && st[tot + i - 1] > st[tot + i - 2]
    t = st[tot + i - 1]
    st[tot + i - 1] = st[tot + i - 2]
    st[tot + i - 2] = t
    t = st[so + i - 1]
    st[so + i - 1] = st[so + i - 2]
    st[so + i - 2] = t
  0

# ---------------------------------------------------------------- coefficient codes

-> jxr_abs_level(src, br, st, vsel) (u8[] i64[] i64[] i64) i64
  o = vsel * 5
  idx = 0 ## i64
  if st[o] == 0
    idx = jxr_inte(src, br, 6, JXR_ABS0B ## i64[], JXR_ABS0V ## i64[])
  else
    idx = jxr_inte(src, br, 6, JXR_ABS1B ## i64[], JXR_ABS1V ## i64[])
  dl = JXR_ABS_DELTA ## i64[]
  st[o + 3] = st[o + 3] + dl[idx]
  if idx < 6
    rm = JXR_ABS_REMAP ## i64[]
    fx = JXR_ABS_FIXED ## i64[]
    return rm[idx] + jxr_get(src, br, fx[idx])
  fixed = 4 + jxr_get(src, br, 4)
  if fixed == 19
    fixed += jxr_get(src, br, 2)
    if fixed == 22
      fixed += jxr_get(src, br, 3)
  one = 1 ## i64
  2 + (one << fixed) + jxr_get(src, br, fixed)

-> jxr_first_index(src, br, st, chroma, band) (u8[] i64[] i64[] i64 i64) i64
  vsel = 2
  if band == 1
    vsel = 9 if chroma != 0
  else
    vsel = 16
    vsel = 17 if chroma != 0
  o = vsel * 5
  t = st[o]
  fi = 0 ## i64
  if t == 0
    if jxr_bit(src, br) == 1
      fi = 7
    else
      fi = jxr_inte(src, br, 6, JXR_FI0B ## i64[], JXR_FI0V ## i64[])
  elsif t == 1
    fi = jxr_inte(src, br, 6, JXR_FI1B ## i64[], JXR_FI1V ## i64[])
  elsif t == 2
    fi = jxr_inte(src, br, 7, JXR_FI2B ## i64[], JXR_FI2V ## i64[])
  elsif t == 3
    fi = jxr_inte(src, br, 7, JXR_FI3B ## i64[], JXR_FI3V ## i64[])
  else
    if jxr_bit(src, br) == 1
      fi = 1
    else
      fi = jxr_inte(src, br, 7, JXR_FI4B ## i64[], JXR_FI4V ## i64[])
  dt = JXR_FI_DELTA ## i64[]
  st[o + 3] = st[o + 3] + dt[st[o + 1] * 12 + fi]
  st[o + 4] = st[o + 4] + dt[st[o + 2] * 12 + fi]
  fi

-> jxr_index(src, br, st, location, chroma, band, ctx) (u8[] i64[] i64[] i64 i64 i64 i64) i64
  if location > 15
    return jxr_bit(src, br)
  if location == 15
    return 0 if jxr_bit(src, br) == 0
    return 2 if jxr_bit(src, br) == 0
    return 1 if jxr_bit(src, br) == 0
    return 3
  vsel = 0 ## i64
  if band == 1
    if chroma != 0
      vsel = 10 + ctx
    else
      vsel = 7 + ctx
  else
    if chroma != 0
      vsel = 18 + ctx
    else
      vsel = 14 + ctx
  o = vsel * 5
  t = st[o]
  ix = 0 ## i64
  if t == 0
    if jxr_bit(src, br) == 1
      ix = 0
    elsif jxr_bit(src, br) == 1
      ix = 4
    elsif jxr_bit(src, br) == 1
      ix = 2
    elsif jxr_bit(src, br) == 1
      ix = 5
    elsif jxr_bit(src, br) == 1
      ix = 3
    else
      ix = 1
  elsif t == 1
    c = jxr_get(src, br, 2)
    if c == 1
      ix = 0
    elsif c == 2
      ix = 2
    elsif c == 3
      ix = 4
    elsif jxr_bit(src, br) == 1
      ix = 5
    elsif jxr_bit(src, br) == 1
      ix = 3
    else
      ix = 1
  elsif t == 2
    c = jxr_get(src, br, 2)
    if c == 1
      ix = 2
    elsif c == 2
      ix = 3
    elsif c == 3
      ix = 4
    elsif jxr_bit(src, br) == 1
      ix = 5
    elsif jxr_bit(src, br) == 1
      ix = 1
    else
      ix = 0
  else
    if jxr_bit(src, br) == 1
      ix = 3
    elsif jxr_bit(src, br) == 1
      ix = 2
    elsif jxr_bit(src, br) == 1
      ix = 5
    elsif jxr_bit(src, br) == 1
      ix = 4
    elsif jxr_bit(src, br) == 1
      ix = 1
    else
      ix = 0
  dt = JXR_IX_DELTA ## i64[]
  st[o + 3] = st[o + 3] + dt[st[o + 1] * 6 + ix]
  st[o + 4] = st[o + 4] + dt[st[o + 2] * 6 + ix]
  ix

-> jxr_run(src, br, max_run) (u8[] i64[] i64) i64
  if max_run < 5
    return 1 if max_run <= 1
    return 1 if jxr_bit(src, br) == 1
    return 2 if max_run == 2
    return 2 if jxr_bit(src, br) == 1
    return 3 if max_run == 3
    return 3 if jxr_bit(src, br) == 1
    return 4
  ri = 0 ## i64
  if jxr_bit(src, br) == 1
    ri = 0
  elsif jxr_bit(src, br) == 1
    ri = 1
  elsif jxr_bit(src, br) == 1
    ri = 2
  elsif jxr_bit(src, br) == 1
    ri = 4
  else
    ri = 3
  if max_run > 14
    br[2] = 1
    return 1
  rb = JXR_RUN_BIN ## i64[]
  rf = JXR_RUN_FIXED ## i64[]
  rr = JXR_RUN_REMAP ## i64[]
  index = ri + 5 * rb[max_run]
  rr[index] + jxr_get(src, br, rf[index])

# DECODE_BLOCK: run/level pairs into coeff[2k] (run), coeff[2k+1] (level).
-> jxr_decode_block(src, br, st, chroma, band, location, coeff) (u8[] i64[] i64[] i64 i64 i64 i64[]) i64
  num_nz = 1 ## i64
  index = jxr_first_index(src, br, st, chroma, band)
  sr = index & 1
  srn = index >> 2
  ctx = sr & srn
  vabs = 3
  if band == 2
    vabs = 5
  sign = jxr_bit(src, br)
  lv = 1 ## i64
  if (index & 2) != 0
    lv = jxr_abs_level(src, br, st, vabs + ctx)
  lv = 0 - lv if sign == 1
  coeff[1] = lv
  loc = location
  if (index & 1) != 0
    coeff[0] = 0
  else
    if loc >= 15
      br[2] = 1
      return 0
    coeff[0] = jxr_run(src, br, 15 - loc)
  loc += coeff[0] + 1
  while srn != 0
    if num_nz >= 16
      br[2] = 1
      return num_nz
    r = 0 ## i64
    if (srn & 1) == 0
      if loc >= 15
        br[2] = 1
        return num_nz
      r = jxr_run(src, br, 15 - loc)
    coeff[num_nz * 2] = r
    loc += r + 1
    index = jxr_index(src, br, st, loc, chroma, band, ctx)
    srn = index >> 1
    ctx = ctx & srn
    sign = jxr_bit(src, br)
    lv = 1
    if (index & 1) != 0
      lv = jxr_abs_level(src, br, st, vabs + ctx)
    lv = 0 - lv if sign == 1
    coeff[num_nz * 2 + 1] = lv
    num_nz += 1
  num_nz

-> jxr_refine_lp(src, br, coeff, mb) (u8[] i64[] i64 i64) i64
  r = jxr_get(src, br, mb)
  if coeff > 0
    return (coeff << mb) + r
  if coeff < 0
    return (coeff << mb) - r
  if r != 0 && jxr_bit(src, br) == 1
    return 0 - r
  r

-> jxr_refine_cbp(src, br, num) (u8[] i64[] i64) i64
  if num == 1
    return 1 << jxr_get(src, br, 2)
  if num == 2
    if jxr_bit(src, br) == 0
      return 3 if jxr_bit(src, br) == 0
      return 5
    if jxr_bit(src, br) == 0
      return 6 if jxr_bit(src, br) == 0
      return 9
    return 10 if jxr_bit(src, br) == 0
    return 12
  if num == 3
    return 15 ^ (1 << jxr_get(src, br, 2))
  return 15 if num == 4
  0

-> jxr_num_cbp(src, br, table) (u8[] i64[] i64) i64
  return 0 if jxr_bit(src, br) == 1
  if table == 0
    return 1 if jxr_bit(src, br) == 1
    return 2 if jxr_bit(src, br) == 1
    return 4 if jxr_bit(src, br) == 1
    return 3
  jxr_get(src, br, 2) + 1

-> jxr_value012(src, br) (u8[] i64[]) i64
  return 0 if jxr_bit(src, br) == 1
  return 1 if jxr_bit(src, br) == 1
  2

-> jxr_num_ch_blk(src, br) (u8[] i64[]) i64
  return 0 if jxr_bit(src, br) == 1
  return 1 if jxr_bit(src, br) == 1
  return 3 if jxr_bit(src, br) == 1
  2

-> jxr_is_dc_yuv(src, br) (u8[] i64[]) i64
  if jxr_bit(src, br) == 1
    return 4 if jxr_bit(src, br) == 1
    return 0
  c = jxr_get(src, br, 2)
  if c == 0
    return 3 if jxr_bit(src, br) == 1
    return 2 if jxr_bit(src, br) == 1
    return 6
  return 1 if c == 1
  return 5 if c == 2
  7

-> jxr_dec_dc(src, br, st, model_bits, chroma, is_dc) (u8[] i64[] i64[] i64 i64 i64) i64
  v = 0 ## i64
  if is_dc != 0
    v = jxr_abs_level(src, br, st, chroma) - 1
  k = 0 ## i64
  while k < model_bits
    v = (v << 1) | jxr_bit(src, br)
    k += 1
  if v != 0 && jxr_bit(src, br) == 1
    v = 0 - v
  v

-> jxr_qp_index(src, br, count) (u8[] i64[] i64) i64
  return 0 if jxr_bit(src, br) == 0
  nb = 4
  if count <= 3
    nb = 1
  elsif count <= 5
    nb = 2
  elsif count <= 9
    nb = 3
  jxr_get(src, br, nb) + 1

-> jxr_popcount(v) (i64) i64
  c = 0 ## i64
  x = v
  while x > 0
    c += x & 1
    x = x >> 1
  c
