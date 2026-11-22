# core/codec/image/webp_vp8 — VP8 keyframe (WebP lossy) decoder.
#
# vp8_decode(a, off, len) → Bitmap (RGBA, alpha 255).
#
# Bit-exact with libwebp's default decode (RFC 6386 plus libwebp's choices):
# boolean entropy decoder, segment/quantiser headers, per-row intra-mode
# parsing (16x16, 4x4 B_PRED, chroma), token partitions, dequantisation,
# inverse WHT/DCT, intra prediction in a 32-byte-stride work block exactly as
# libwebp (borders 127/129, the top-right replication for 4x4 blocks), then
# the loop filter (simple or normal, with sharpness and per-segment / mode
# deltas) over the reconstructed frame in macroblock order, and finally
# YUV 4:2:0 → RGB with libwebp's "fancy" upsampler and fixed-point
# conversion. Dithering is off, as in libwebp's default.

use core/codec/video/vp8_core
use core/codec/image
use webp_vp8l
use core/codec/video/vp8_core_tables

VP8_BPS = 32
VP8_YOFF = 40
VP8_UOFF = 584
VP8_VOFF = 600

-> vp8_fail(msg)
  raise ImageError, "webp lossy: " + msg

-> vp8bd_svalue(a, s, n) (u8[] i64[] i64) i64
  v = vp8bd_value(a, s, n)
  vp8bd_bit(a, s, 128) == 1 ? 0 - v : v

-> vp8bd_signed(a, s, v) (u8[] i64[] i64) i64
  if s[2] < 0
    vp8bd_load(a, s)
  pos = s[2]
  split = s[1] >> 1
  s[2] = pos - 1
  if (s[0] >> pos) > split
    s[1] = (s[1] - 1) | 1
    s[0] = s[0] - ((split + 1) << pos)
    return 0 - v
  s[1] = s[1] | 1
  v

# ---- coefficients ----

-> vp8_large(a, s, prob, p, tb) (u8[] i64[] i64[] i64 i64[]) i64
  if vp8bd_bit(a, s, prob[p + 3]) == 0
    if vp8bd_bit(a, s, prob[p + 4]) == 0
      return 2
    return 3 + vp8bd_bit(a, s, prob[p + 5])
  if vp8bd_bit(a, s, prob[p + 6]) == 0
    if vp8bd_bit(a, s, prob[p + 7]) == 0
      return 5 + vp8bd_bit(a, s, 159)
    v = 7 + 2 * vp8bd_bit(a, s, 165)
    return v + vp8bd_bit(a, s, 145)
  b1 = vp8bd_bit(a, s, prob[p + 8])
  b0 = vp8bd_bit(a, s, prob[p + 9 + b1])
  cat = 2 * b1 + b0
  v = 0 ## i64
  k = tb[36 + cat]
  while tb[k] != 0
    v = v + v + vp8bd_bit(a, s, tb[k])
    k += 1
  v + 3 + (8 << cat)

# Residuals of one macroblock. ctx: [0, mbw) top nz, [mbw, 2mbw) top nz_dc,
# [2mbw] left nz, [2mbw + 1] left nz_dc. q: per segment y1dc y1ac y2dc y2ac
# uvdc uvac. info[0] / info[1] receive non_zero_y / non_zero_uv. Returns 1
# when the macroblock has no non-zero coefficient.
-> vp8_residuals(a, s, prob, q, qo, is4, co, coff, ctx, mbx, mbw, info, tb, dc, tmp) (u8[] i64[] i64[] i64[] i64 i64 i64[] i64 i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  k = 0 ## i64
  while k < 384
    co[coff + k] = 0
    k += 1
  first = 0 ## i64
  t = 3 ## i64
  if is4 == 0
    k = 0
    while k < 16
      dc[k] = 0
      k += 1
    c = ctx[mbw + mbx] + ctx[2 * mbw + 1]
    nz = vp8_coeffs(a, s, prob, 1, c, q[qo + 2], q[qo + 3], 0, dc, 0, tb)
    f = nz > 0 ? 1 : 0
    ctx[mbw + mbx] = f
    ctx[2 * mbw + 1] = f
    if nz > 1
      vp8_wht(dc, co, coff, tmp)
    else
      dc0 = (dc[0] + 3) >> 3
      k = 0
      while k < 16
        co[coff + k * 16] = dc0
        k += 1
    first = 1
    t = 0
  tall = ctx[mbx]
  lall = ctx[2 * mbw]
  tnz = tall & 15
  lnz = lall & 15
  nzy = 0 ## i64
  y = 0 ## i64
  while y < 4
    l = lnz & 1
    nzc = 0 ## i64
    x = 0 ## i64
    while x < 4
      bo = coff + (y * 4 + x) * 16
      nz = vp8_coeffs(a, s, prob, t, l + (tnz & 1), q[qo], q[qo + 1], first, co, bo, tb)
      l = nz > first ? 1 : 0
      tnz = (tnz >> 1) | (l << 7)
      code = co[bo] != 0 ? 1 : 0
      code = 2 if nz > 1
      code = 3 if nz > 3
      nzc = (nzc << 2) | code
      x += 1
    tnz = tnz >> 4
    lnz = (lnz >> 1) | (l << 7)
    nzy = (nzy << 8) | nzc
    y += 1
  out_t = tnz
  out_l = lnz >> 4
  nzuv = 0 ## i64
  ch = 0 ## i64
  while ch < 4
    nzc = 0
    tnz = (tall >> (4 + ch)) & 255
    lnz = (lall >> (4 + ch)) & 255
    y = 0
    while y < 2
      l = lnz & 1
      x = 0
      while x < 2
        bo = coff + (16 + ch * 2 + y * 2 + x) * 16
        nz = vp8_coeffs(a, s, prob, 2, l + (tnz & 1), q[qo + 4], q[qo + 5], 0, co, bo, tb)
        l = nz > 0 ? 1 : 0
        tnz = (tnz >> 1) | (l << 3)
        code = co[bo] != 0 ? 1 : 0
        code = 2 if nz > 1
        code = 3 if nz > 3
        nzc = (nzc << 2) | code
        x += 1
      tnz = tnz >> 2
      lnz = (lnz >> 1) | (l << 5)
      y += 1
    nzuv = nzuv | (nzc << (4 * ch))
    out_t = out_t | ((tnz << 4) << ch)
    out_l = out_l | ((lnz & 0xf0) << ch)
    ch += 2
  ctx[mbx] = out_t
  ctx[2 * mbw] = out_l
  info[0] = nzy
  info[1] = nzuv
  (nzy | nzuv) == 0 ? 1 : 0

# ---- intra modes (partition 0) ----
# modes: per macroblock of the row, 21 entries at mbx * 21: [0] is4,
# [1] ymode (16x16) , [2] uvmode, [3] segment, [4..20) the 4x4 modes, [20] skip.
# st: [use_segment_map, use_skip, skip_p, seg_p0, seg_p1, seg_p2]
# it: top 4x4 modes per column (4 * mbw), il: left 4x4 modes (4).
-> vp8_intra(a, s, st, modes, mo, it, mbx, il, bm) (u8[] i64[] i64[] i64[] i64 i64[] i64 i64[] i64[]) i64
  seg = 0 ## i64
  if st[0] == 1
    if vp8bd_bit(a, s, st[3]) == 0
      seg = vp8bd_bit(a, s, st[4])
    else
      seg = vp8bd_bit(a, s, st[5]) + 2
  skip = 0 ## i64
  if st[1] == 1
    skip = vp8bd_bit(a, s, st[2])
  is4 = vp8bd_bit(a, s, 145) == 0 ? 1 : 0
  modes[mo] = is4
  modes[mo + 3] = seg
  modes[mo + 20] = skip
  if is4 == 0
    ym = 0 ## i64
    if vp8bd_bit(a, s, 156) == 1
      ym = vp8bd_bit(a, s, 128) == 1 ? 1 : 3
    else
      ym = vp8bd_bit(a, s, 163) == 1 ? 2 : 0
    modes[mo + 1] = ym
    k = 0 ## i64
    while k < 4
      it[mbx * 4 + k] = ym
      il[k] = ym
      k += 1
  else
    y = 0 ## i64
    while y < 4
      ym = il[y]
      x = 0 ## i64
      while x < 4
        pb = (it[mbx * 4 + x] * 10 + ym) * 9
        if vp8bd_bit(a, s, bm[pb]) == 0
          ym = 0
        elsif vp8bd_bit(a, s, bm[pb + 1]) == 0
          ym = 1
        elsif vp8bd_bit(a, s, bm[pb + 2]) == 0
          ym = 2
        elsif vp8bd_bit(a, s, bm[pb + 3]) == 0
          if vp8bd_bit(a, s, bm[pb + 4]) == 0
            ym = 3
          elsif vp8bd_bit(a, s, bm[pb + 5]) == 0
            ym = 4
          else
            ym = 5
        elsif vp8bd_bit(a, s, bm[pb + 6]) == 0
          ym = 6
        elsif vp8bd_bit(a, s, bm[pb + 7]) == 0
          ym = 7
        elsif vp8bd_bit(a, s, bm[pb + 8]) == 0
          ym = 8
        else
          ym = 9
        it[mbx * 4 + x] = ym
        modes[mo + 4 + y * 4 + x] = ym
        x += 1
      il[y] = ym
      y += 1
  uv = 0 ## i64
  if vp8bd_bit(a, s, 142) == 1
    if vp8bd_bit(a, s, 114) == 0
      uv = 2
    else
      uv = vp8bd_bit(a, s, 183) == 1 ? 1 : 3
  modes[mo + 2] = uv
  0

# ---- prediction (work block b, BPS 32) ----

-> vp8_clip(v) (i64) i64
  return 0 if v < 0
  return 255 if v > 255
  v

-> vp8_fill(b, d, size, v) (u8[] i64 i64 i64) i64
  j = 0 ## i64
  while j < size
    i = 0 ## i64
    while i < size
      b[d + j * 32 + i] = v
      i += 1
    j += 1
  0

# 16x16 / 8x8 modes: 0 DC, 1 TM, 2 V, 3 H; dcmode 4 no top, 5 no left, 6 none.
-> vp8_pred_block(b, d, size, mode) (u8[] i64 i64 i64) i64
  if mode == 1
    tl = b[d - 33]
    j = 0 ## i64
    while j < size
      l = b[d + j * 32 - 1] - tl
      i = 0 ## i64
      while i < size
        b[d + j * 32 + i] = ((b[d - 32 + i] + l) < 0 ? 0 : ((b[d - 32 + i] + l) > 255 ? 255 : (b[d - 32 + i] + l)))
        i += 1
      j += 1
    return 0
  if mode == 2
    j = 0
    while j < size
      i = 0
      while i < size
        b[d + j * 32 + i] = b[d - 32 + i]
        i += 1
      j += 1
    return 0
  if mode == 3
    j = 0
    while j < size
      l = b[d + j * 32 - 1]
      i = 0
      while i < size
        b[d + j * 32 + i] = l
        i += 1
      j += 1
    return 0
  sh = size == 16 ? 4 : 3
  if mode == 0
    dc = size ## i64
    j = 0
    while j < size
      dc += b[d + j * 32 - 1] + b[d - 32 + j]
      j += 1
    return vp8_fill(b, d, size, dc >> (sh + 1))
  if mode == 4
    dc = size >> 1
    j = 0
    while j < size
      dc += b[d + j * 32 - 1]
      j += 1
    return vp8_fill(b, d, size, dc >> sh)
  if mode == 5
    dc = size >> 1
    j = 0
    while j < size
      dc += b[d - 32 + j]
      j += 1
    return vp8_fill(b, d, size, dc >> sh)
  vp8_fill(b, d, size, 128)

-> vp8_avg3(x, y, z) (i64 i64 i64) i64
  (x + 2 * y + z + 2) >> 2

-> vp8_avg2(x, y) (i64 i64) i64
  (x + y + 1) >> 1

-> vp8_put(b, d, x, y, v) (u8[] i64 i64 i64 i64) i64
  b[d + y * 32 + x] = v
  0

# 4x4 modes: 0 DC 1 TM 2 VE 3 HE 4 RD 5 VR 6 LD 7 VL 8 HD 9 HU.
-> vp8_pred4(b, d, mode) (u8[] i64 i64) i64
  if mode == 0
    dc = 4 ## i64
    i = 0 ## i64
    while i < 4
      dc += b[d - 32 + i] + b[d - 1 + i * 32]
      i += 1
    return vp8_fill(b, d, 4, dc >> 3)
  if mode == 1
    return vp8_pred_block(b, d, 4, 1)
  ti = b[d - 33] ## i64
  ta = b[d - 32] ## i64
  tb = b[d - 31] ## i64
  tc = b[d - 30] ## i64
  td = b[d - 29] ## i64
  li = b[d - 1] ## i64
  lj = b[d + 31] ## i64
  lk = b[d + 63] ## i64
  ll = b[d + 95] ## i64
  if mode == 2
    v0 = vp8_avg3(ti, ta, tb)
    v1 = vp8_avg3(ta, tb, tc)
    v2 = vp8_avg3(tb, tc, td)
    v3 = vp8_avg3(tc, td, (b[d - 28] ## i64))
    j = 0 ## i64
    while j < 4
      b[d + j * 32] = v0
      b[d + j * 32 + 1] = v1
      b[d + j * 32 + 2] = v2
      b[d + j * 32 + 3] = v3
      j += 1
    return 0
  if mode == 3
    r0 = vp8_avg3(ti, li, lj)
    r1 = vp8_avg3(li, lj, lk)
    r2 = vp8_avg3(lj, lk, ll)
    r3 = vp8_avg3(lk, ll, ll)
    i = 0
    while i < 4
      b[d + i] = r0
      b[d + 32 + i] = r1
      b[d + 64 + i] = r2
      b[d + 96 + i] = r3
      i += 1
    return 0
  if mode == 4
    vp8_put(b, d, 0, 3, vp8_avg3(lj, lk, ll))
    v = vp8_avg3(li, lj, lk)
    vp8_put(b, d, 1, 3, v)
    vp8_put(b, d, 0, 2, v)
    v = vp8_avg3(ti, li, lj)
    vp8_put(b, d, 2, 3, v)
    vp8_put(b, d, 1, 2, v)
    vp8_put(b, d, 0, 1, v)
    v = vp8_avg3(ta, ti, li)
    vp8_put(b, d, 3, 3, v)
    vp8_put(b, d, 2, 2, v)
    vp8_put(b, d, 1, 1, v)
    vp8_put(b, d, 0, 0, v)
    v = vp8_avg3(tb, ta, ti)
    vp8_put(b, d, 3, 2, v)
    vp8_put(b, d, 2, 1, v)
    vp8_put(b, d, 1, 0, v)
    v = vp8_avg3(tc, tb, ta)
    vp8_put(b, d, 3, 1, v)
    vp8_put(b, d, 2, 0, v)
    vp8_put(b, d, 3, 0, vp8_avg3(td, tc, tb))
    return 0
  if mode == 5
    v = vp8_avg2(ti, ta)
    vp8_put(b, d, 0, 0, v)
    vp8_put(b, d, 1, 2, v)
    v = vp8_avg2(ta, tb)
    vp8_put(b, d, 1, 0, v)
    vp8_put(b, d, 2, 2, v)
    v = vp8_avg2(tb, tc)
    vp8_put(b, d, 2, 0, v)
    vp8_put(b, d, 3, 2, v)
    vp8_put(b, d, 3, 0, vp8_avg2(tc, td))
    vp8_put(b, d, 0, 3, vp8_avg3(lk, lj, li))
    vp8_put(b, d, 0, 2, vp8_avg3(lj, li, ti))
    v = vp8_avg3(li, ti, ta)
    vp8_put(b, d, 0, 1, v)
    vp8_put(b, d, 1, 3, v)
    v = vp8_avg3(ti, ta, tb)
    vp8_put(b, d, 1, 1, v)
    vp8_put(b, d, 2, 3, v)
    v = vp8_avg3(ta, tb, tc)
    vp8_put(b, d, 2, 1, v)
    vp8_put(b, d, 3, 3, v)
    vp8_put(b, d, 3, 1, vp8_avg3(tb, tc, td))
    return 0
  te = b[d - 28] ## i64
  tf = b[d - 27] ## i64
  tg = b[d - 26] ## i64
  th = b[d - 25] ## i64
  if mode == 6
    vp8_put(b, d, 0, 0, vp8_avg3(ta, tb, tc))
    v = vp8_avg3(tb, tc, td)
    vp8_put(b, d, 1, 0, v)
    vp8_put(b, d, 0, 1, v)
    v = vp8_avg3(tc, td, te)
    vp8_put(b, d, 2, 0, v)
    vp8_put(b, d, 1, 1, v)
    vp8_put(b, d, 0, 2, v)
    v = vp8_avg3(td, te, tf)
    vp8_put(b, d, 3, 0, v)
    vp8_put(b, d, 2, 1, v)
    vp8_put(b, d, 1, 2, v)
    vp8_put(b, d, 0, 3, v)
    v = vp8_avg3(te, tf, tg)
    vp8_put(b, d, 3, 1, v)
    vp8_put(b, d, 2, 2, v)
    vp8_put(b, d, 1, 3, v)
    v = vp8_avg3(tf, tg, th)
    vp8_put(b, d, 3, 2, v)
    vp8_put(b, d, 2, 3, v)
    vp8_put(b, d, 3, 3, vp8_avg3(tg, th, th))
    return 0
  if mode == 7
    vp8_put(b, d, 0, 0, vp8_avg2(ta, tb))
    v = vp8_avg2(tb, tc)
    vp8_put(b, d, 1, 0, v)
    vp8_put(b, d, 0, 2, v)
    v = vp8_avg2(tc, td)
    vp8_put(b, d, 2, 0, v)
    vp8_put(b, d, 1, 2, v)
    v = vp8_avg2(td, te)
    vp8_put(b, d, 3, 0, v)
    vp8_put(b, d, 2, 2, v)
    vp8_put(b, d, 0, 1, vp8_avg3(ta, tb, tc))
    v = vp8_avg3(tb, tc, td)
    vp8_put(b, d, 1, 1, v)
    vp8_put(b, d, 0, 3, v)
    v = vp8_avg3(tc, td, te)
    vp8_put(b, d, 2, 1, v)
    vp8_put(b, d, 1, 3, v)
    v = vp8_avg3(td, te, tf)
    vp8_put(b, d, 3, 1, v)
    vp8_put(b, d, 2, 3, v)
    vp8_put(b, d, 3, 2, vp8_avg3(te, tf, tg))
    vp8_put(b, d, 3, 3, vp8_avg3(tf, tg, th))
    return 0
  if mode == 8
    v = vp8_avg2(li, ti)
    vp8_put(b, d, 0, 0, v)
    vp8_put(b, d, 2, 1, v)
    v = vp8_avg2(lj, li)
    vp8_put(b, d, 0, 1, v)
    vp8_put(b, d, 2, 2, v)
    v = vp8_avg2(lk, lj)
    vp8_put(b, d, 0, 2, v)
    vp8_put(b, d, 2, 3, v)
    vp8_put(b, d, 0, 3, vp8_avg2(ll, lk))
    vp8_put(b, d, 3, 0, vp8_avg3(ta, tb, tc))
    vp8_put(b, d, 2, 0, vp8_avg3(ti, ta, tb))
    v = vp8_avg3(li, ti, ta)
    vp8_put(b, d, 1, 0, v)
    vp8_put(b, d, 3, 1, v)
    v = vp8_avg3(lj, li, ti)
    vp8_put(b, d, 1, 1, v)
    vp8_put(b, d, 3, 2, v)
    v = vp8_avg3(lk, lj, li)
    vp8_put(b, d, 1, 2, v)
    vp8_put(b, d, 3, 3, v)
    vp8_put(b, d, 1, 3, vp8_avg3(ll, lk, lj))
    return 0
  # HU
  vp8_put(b, d, 0, 0, vp8_avg2(li, lj))
  v = vp8_avg2(lj, lk)
  vp8_put(b, d, 2, 0, v)
  vp8_put(b, d, 0, 1, v)
  v = vp8_avg2(lk, ll)
  vp8_put(b, d, 2, 1, v)
  vp8_put(b, d, 0, 2, v)
  vp8_put(b, d, 1, 0, vp8_avg3(li, lj, lk))
  v = vp8_avg3(lj, lk, ll)
  vp8_put(b, d, 3, 0, v)
  vp8_put(b, d, 1, 1, v)
  v = vp8_avg3(lk, ll, ll)
  vp8_put(b, d, 3, 1, v)
  vp8_put(b, d, 1, 2, v)
  vp8_put(b, d, 3, 2, ll)
  vp8_put(b, d, 2, 2, ll)
  vp8_put(b, d, 0, 3, ll)
  vp8_put(b, d, 1, 3, ll)
  vp8_put(b, d, 2, 3, ll)
  vp8_put(b, d, 3, 3, ll)
  0

# ---- inverse transforms (add to the prediction in b at d) ----

-> vp8_mul1(x) (i64) i64
  ((x * 20091) >> 16) + x

-> vp8_mul2(x) (i64) i64
  (x * 35468) >> 16

-> vp8_store(b, o, v) (u8[] i64 i64) i64
  b[o] = ((b[o] + (v >> 3)) < 0 ? 0 : ((b[o] + (v >> 3)) > 255 ? 255 : (b[o] + (v >> 3))))
  0

-> vp8_idct(co, ci, b, d, tmp) (i64[] i64 u8[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    i0 = co[ci + i]
    i4 = co[ci + 4 + i]
    i8 = co[ci + 8 + i]
    i12 = co[ci + 12 + i]
    a = i0 + i8
    bb = i0 - i8
    c = (((i4) * 35468) >> 16) - ((((i12) * 20091) >> 16) + (i12))
    dd = ((((i4) * 20091) >> 16) + (i4)) + (((i12) * 35468) >> 16)
    tmp[i * 4] = a + dd
    tmp[i * 4 + 1] = bb + c
    tmp[i * 4 + 2] = bb - c
    tmp[i * 4 + 3] = a - dd
    i += 1
  i = 0
  while i < 4
    dc = tmp[i] + 4
    a = dc + tmp[8 + i]
    bb = dc - tmp[8 + i]
    c = (((tmp[4 + i]) * 35468) >> 16) - ((((tmp[12 + i]) * 20091) >> 16) + (tmp[12 + i]))
    dd = ((((tmp[4 + i]) * 20091) >> 16) + (tmp[4 + i])) + (((tmp[12 + i]) * 35468) >> 16)
    o = d + i * 32
    b[o] = ((b[o] + ((a + dd) >> 3)) < 0 ? 0 : ((b[o] + ((a + dd) >> 3)) > 255 ? 255 : (b[o] + ((a + dd) >> 3))))
    b[o + 1] = ((b[o + 1] + ((bb + c) >> 3)) < 0 ? 0 : ((b[o + 1] + ((bb + c) >> 3)) > 255 ? 255 : (b[o + 1] + ((bb + c) >> 3))))
    b[o + 2] = ((b[o + 2] + ((bb - c) >> 3)) < 0 ? 0 : ((b[o + 2] + ((bb - c) >> 3)) > 255 ? 255 : (b[o + 2] + ((bb - c) >> 3))))
    b[o + 3] = ((b[o + 3] + ((a - dd) >> 3)) < 0 ? 0 : ((b[o + 3] + ((a - dd) >> 3)) > 255 ? 255 : (b[o + 3] + ((a - dd) >> 3))))
    i += 1
  0

-> vp8_idct_ac3(co, ci, b, d) (i64[] i64 u8[] i64) i64
  a = co[ci] + 4
  c4 = (((co[ci + 4]) * 35468) >> 16)
  d4 = ((((co[ci + 4]) * 20091) >> 16) + (co[ci + 4]))
  c1 = (((co[ci + 1]) * 35468) >> 16)
  d1 = ((((co[ci + 1]) * 20091) >> 16) + (co[ci + 1]))
  vp8_store2(b, d, a + d4, d1, c1)
  vp8_store2(b, d + 32, a + c4, d1, c1)
  vp8_store2(b, d + 64, a - c4, d1, c1)
  vp8_store2(b, d + 96, a - d4, d1, c1)
  0

-> vp8_store2(b, o, dc, dd, c) (u8[] i64 i64 i64 i64) i64
  b[o] = ((b[o] + ((dc + dd) >> 3)) < 0 ? 0 : ((b[o] + ((dc + dd) >> 3)) > 255 ? 255 : (b[o] + ((dc + dd) >> 3))))
  b[o + 1] = ((b[o + 1] + ((dc + c) >> 3)) < 0 ? 0 : ((b[o + 1] + ((dc + c) >> 3)) > 255 ? 255 : (b[o + 1] + ((dc + c) >> 3))))
  b[o + 2] = ((b[o + 2] + ((dc - c) >> 3)) < 0 ? 0 : ((b[o + 2] + ((dc - c) >> 3)) > 255 ? 255 : (b[o + 2] + ((dc - c) >> 3))))
  b[o + 3] = ((b[o + 3] + ((dc - dd) >> 3)) < 0 ? 0 : ((b[o + 3] + ((dc - dd) >> 3)) > 255 ? 255 : (b[o + 3] + ((dc - dd) >> 3))))
  0

-> vp8_idct_dc(co, ci, b, d) (i64[] i64 u8[] i64) i64
  dc = co[ci] + 4
  j = 0 ## i64
  while j < 4
    i = 0 ## i64
    while i < 4
      b[d + j * 32 + i] = ((b[d + j * 32 + i] + ((dc) >> 3)) < 0 ? 0 : ((b[d + j * 32 + i] + ((dc) >> 3)) > 255 ? 255 : (b[d + j * 32 + i] + ((dc) >> 3))))
      i += 1
    j += 1
  0

-> vp8_transform(bits, co, ci, b, d, tmp) (i64 i64[] i64 u8[] i64 i64[]) i64
  k = (bits >> 30) & 3
  if k == 3
    vp8_idct(co, ci, b, d, tmp)
  elsif k == 2
    vp8_idct_ac3(co, ci, b, d)
  elsif k == 1
    vp8_idct_dc(co, ci, b, d)
  0

-> vp8_uv_transform(bits, co, ci, b, d, tmp) (i64 i64[] i64 u8[] i64 i64[]) i64
  if (bits & 255) != 0
    if (bits & 0xaa) != 0
      vp8_idct(co, ci, b, d, tmp)
      vp8_idct(co, ci + 16, b, d + 4, tmp)
      vp8_idct(co, ci + 32, b, d + 128, tmp)
      vp8_idct(co, ci + 48, b, d + 132, tmp)
    else
      vp8_idct_dc(co, ci, b, d) if co[ci] != 0
      vp8_idct_dc(co, ci + 16, b, d + 4) if co[ci + 16] != 0
      vp8_idct_dc(co, ci + 32, b, d + 128) if co[ci + 32] != 0
      vp8_idct_dc(co, ci + 48, b, d + 132) if co[ci + 48] != 0
  0

-> vp8_check_mode(mbx, mby, mode) (i64 i64 i64) i64
  return mode if mode != 0
  if mbx == 0
    return mby == 0 ? 6 : 5
  mby == 0 ? 4 : 0

# Reconstruct one row of macroblocks into the planes. modes/co/nzs hold the
# row's parse results (nzs: non_zero_y, non_zero_uv per mbx).
-> vp8_recon_row(b, mby, mbw, mbh, modes, co, nzs, ty, tu, tv, yp, up, vp, tmp) (u8[] i64 i64 i64 i64[] i64[] i64[] u8[] u8[] u8[] u8[] u8[] u8[] i64[]) i64
  ys = mbw * 16
  uvs = mbw * 8
  j = 0 ## i64
  while j < 16
    b[40 + j * 32 - 1] = 129
    j += 1
  j = 0
  while j < 8
    b[584 + j * 32 - 1] = 129
    b[600 + j * 32 - 1] = 129
    j += 1
  if mby > 0
    b[40 - 33] = 129
    b[584 - 33] = 129
    b[600 - 33] = 129
  else
    j = 0
    while j < 21
      b[40 - 33 + j] = 127
      j += 1
    j = 0
    while j < 9
      b[584 - 33 + j] = 127
      b[600 - 33 + j] = 127
      j += 1
  mbx = 0 ## i64
  while mbx < mbw
    mo = mbx * 21
    if mbx > 0
      j = -1
      while j < 16
        k = 0 ## i64
        while k < 4
          b[40 + j * 32 - 4 + k] = b[40 + j * 32 + 12 + k]
          k += 1
        j += 1
      j = -1
      while j < 8
        k = 0
        while k < 4
          b[584 + j * 32 - 4 + k] = b[584 + j * 32 + 4 + k]
          b[600 + j * 32 - 4 + k] = b[600 + j * 32 + 4 + k]
          k += 1
        j += 1
    if mby > 0
      k = 0
      while k < 16
        b[8 + k] = ty[mbx * 16 + k]
        k += 1
      k = 0
      while k < 8
        b[552 + k] = tu[mbx * 8 + k]
        b[568 + k] = tv[mbx * 8 + k]
        k += 1
    ci = mbx * 384
    bits = nzs[mbx * 2]
    if modes[mo] == 1
      # top-right samples (cols 16..19 of row -1), replicated down for the
      # right column of 4x4 blocks
      if mby > 0
        k = 0
        while k < 4
          if mbx >= mbw - 1
            b[24 + k] = ty[mbx * 16 + 15]
          else
            b[24 + k] = ty[mbx * 16 + 16 + k]
          k += 1
      k = 0
      while k < 4
        b[24 + 128 + k] = b[24 + k]
        b[24 + 256 + k] = b[24 + k]
        b[24 + 384 + k] = b[24 + k]
        k += 1
      n = 0 ## i64
      while n < 16
        d = 40 + (n & 3) * 4 + (n >> 2) * 128
        vp8_pred4(b, d, modes[mo + 4 + n])
        vp8_transform(bits, co, ci + n * 16, b, d, tmp)
        bits = (bits << 2) & 0xFFFFFFFF
        n += 1
    else
      vp8_pred_block(b, 40, 16, vp8_check_mode(mbx, mby, modes[mo + 1]))
      if bits != 0
        n = 0
        while n < 16
          d = 40 + (n & 3) * 4 + (n >> 2) * 128
          vp8_transform(bits, co, ci + n * 16, b, d, tmp)
          bits = (bits << 2) & 0xFFFFFFFF
          n += 1
    uvm = vp8_check_mode(mbx, mby, modes[mo + 2])
    vp8_pred_block(b, 584, 8, uvm)
    vp8_pred_block(b, 600, 8, uvm)
    buv = nzs[mbx * 2 + 1]
    vp8_uv_transform(buv, co, ci + 256, b, 584, tmp)
    vp8_uv_transform(buv >> 8, co, ci + 320, b, 600, tmp)
    if mby < mbh - 1
      k = 0
      while k < 16
        ty[mbx * 16 + k] = b[40 + 15 * 32 + k]
        k += 1
      k = 0
      while k < 8
        tu[mbx * 8 + k] = b[584 + 7 * 32 + k]
        tv[mbx * 8 + k] = b[600 + 7 * 32 + k]
        k += 1
    # copy out
    yo = mby * 16 * ys + mbx * 16
    j = 0
    while j < 16
      k = 0
      while k < 16
        yp[yo + j * ys + k] = b[40 + j * 32 + k]
        k += 1
      j += 1
    uo = mby * 8 * uvs + mbx * 8
    j = 0
    while j < 8
      k = 0
      while k < 8
        up[uo + j * uvs + k] = b[584 + j * 32 + k]
        vp[uo + j * uvs + k] = b[600 + j * 32 + k]
        k += 1
      j += 1
    mbx += 1
  0

# ---- loop filter ----

-> vp8_sclip2(v) (i64) i64
  return -16 if v < -16
  return 15 if v > 15
  v

-> vp8_abs(v) (i64) i64
  v < 0 ? 0 - v : v

-> vp8_clip8(v) (i64) i64
  return v >> 6 if (v & -16384) == 0
  v < 0 ? 0 : 255

-> vp8_rgb(y, u, v, out, o) (i64 i64 i64 u8[] i64) i64
  yy = (y * 19077) >> 8
  r = yy + ((v * 26149) >> 8) - 14234
  g = yy - ((u * 6419) >> 8) - ((v * 13320) >> 8) + 8708
  b = yy + ((u * 33050) >> 8) - 17685
  out[o] = (r & -16384) == 0 ? r >> 6 : (r < 0 ? 0 : 255)
  out[o + 1] = (g & -16384) == 0 ? g >> 6 : (g < 0 ? 0 : 255)
  out[o + 2] = (b & -16384) == 0 ? b >> 6 : (b < 0 ? 0 : 255)
  out[o + 3] = 255
  0

# One pair of output rows (bottom row optional: bo < 0).
-> vp8_upsample(yp, ty, by, up, vp, tuv, cuv, out, to, bo, len) (u8[] i64 i64 u8[] u8[] i64 i64 u8[] i64 i64 i64) i64
  last = (len - 1) >> 1
  tlu = up[tuv]
  tlv = vp[tuv]
  lu = up[cuv]
  lv = vp[cuv]
  vp8_rgb((yp[ty] ## i64), (3 * tlu + lu + 2) >> 2, (3 * tlv + lv + 2) >> 2, out, to)
  if bo >= 0
    vp8_rgb((yp[by] ## i64), (3 * lu + tlu + 2) >> 2, (3 * lv + tlv + 2) >> 2, out, bo)
  x = 1 ## i64
  while x <= last
    tu = up[tuv + x]
    tv = vp[tuv + x]
    cu = up[cuv + x]
    cv = vp[cuv + x]
    au = tlu + tu + lu + cu + 8
    av = tlv + tv + lv + cv + 8
    d12u = (au + 2 * (tu + lu)) >> 3
    d12v = (av + 2 * (tv + lv)) >> 3
    d03u = (au + 2 * (tlu + cu)) >> 3
    d03v = (av + 2 * (tlv + cv)) >> 3
    vp8_rgb((yp[ty + 2 * x - 1] ## i64), (d12u + tlu) >> 1, (d12v + tlv) >> 1, out, to + (2 * x - 1) * 4)
    vp8_rgb((yp[ty + 2 * x] ## i64), (d03u + tu) >> 1, (d03v + tv) >> 1, out, to + 2 * x * 4)
    if bo >= 0
      vp8_rgb((yp[by + 2 * x - 1] ## i64), (d03u + lu) >> 1, (d03v + lv) >> 1, out, bo + (2 * x - 1) * 4)
      vp8_rgb((yp[by + 2 * x] ## i64), (d12u + cu) >> 1, (d12v + cv) >> 1, out, bo + 2 * x * 4)
    tlu = tu
    tlv = tv
    lu = cu
    lv = cv
    x += 1
  if (len & 1) == 0
    vp8_rgb((yp[ty + len - 1] ## i64), (3 * tlu + lu + 2) >> 2, (3 * tlv + lv + 2) >> 2, out, to + (len - 1) * 4)
    if bo >= 0
      vp8_rgb((yp[by + len - 1] ## i64), (3 * lu + tlu + 2) >> 2, (3 * lv + tlv + 2) >> 2, out, bo + (len - 1) * 4)
  0

-> vp8_to_rgba(yp, up, vp, ys, uvs, w, h, out) (u8[] u8[] u8[] i64 i64 i64 i64 u8[]) i64
  os = w * 4
  vp8_upsample(yp, 0, 0, up, vp, 0, 0, out, 0, -1, w)
  y = 0 ## i64
  cuv = 0 ## i64
  while y + 2 < h
    tuv = cuv
    cuv += uvs
    vp8_upsample(yp, (y + 1) * ys, (y + 2) * ys, up, vp, tuv, cuv, out, (y + 1) * os, (y + 2) * os, w)
    y += 2
  if (h & 1) == 0
    vp8_upsample(yp, (h - 1) * ys, 0, up, vp, cuv, cuv, out, (h - 1) * os, -1, w)
  0

# ---- frame ----

-> vp8_decode(a, off, len)
  vp8_fail("truncated frame") if len < 10 || off + len > a.size
  bits = a[off] | (a[off + 1] << 8) | (a[off + 2] << 16)
  vp8_fail("not a keyframe") if (bits & 1) != 0
  vp8_fail("bad profile") if ((bits >> 1) & 7) > 3
  vp8_fail("invisible frame") if ((bits >> 4) & 1) == 0
  plen = bits >> 5
  vp8_fail("bad start code") if a[off + 3] != 0x9d || a[off + 4] != 0x01 || a[off + 5] != 0x2a
  w = (a[off + 6] | (a[off + 7] << 8)) & 0x3fff
  h = (a[off + 8] | (a[off + 9] << 8)) & 0x3fff
  img_check_size(w, h)
  mbw = (w + 15) >> 4
  mbh = (h + 15) >> 4
  p0 = off + 10
  rest = len - 10
  vp8_fail("bad partition length") if plen > rest
  br = i64[6]
  vp8bd_init(a, br, p0, plen)
  vp8bd_bit(a, br, 128)
  vp8bd_bit(a, br, 128)
  # segment header
  st = i64[6]
  st[3] = 255
  st[4] = 255
  st[5] = 255
  use_seg = vp8bd_bit(a, br, 128)
  seg_abs = 1
  seg_q = [0, 0, 0, 0]
  seg_f = [0, 0, 0, 0]
  if use_seg == 1
    st[0] = vp8bd_bit(a, br, 128)
    if vp8bd_bit(a, br, 128) == 1
      seg_abs = vp8bd_bit(a, br, 128)
      k = 0
      while k < 4
        seg_q[k] = vp8bd_bit(a, br, 128) == 1 ? vp8bd_svalue(a, br, 7) : 0
        k += 1
      k = 0
      while k < 4
        seg_f[k] = vp8bd_bit(a, br, 128) == 1 ? vp8bd_svalue(a, br, 6) : 0
        k += 1
    if st[0] == 1
      k = 0
      while k < 3
        st[3 + k] = vp8bd_bit(a, br, 128) == 1 ? vp8bd_value(a, br, 8) : 255
        k += 1
  # filter header
  simple = vp8bd_bit(a, br, 128)
  level = vp8bd_value(a, br, 6)
  sharp = vp8bd_value(a, br, 3)
  use_lf = vp8bd_bit(a, br, 128)
  ref_lf = [0, 0, 0, 0]
  mode_lf = [0, 0, 0, 0]
  if use_lf == 1 && vp8bd_bit(a, br, 128) == 1
    k = 0
    while k < 4
      ref_lf[k] = vp8bd_svalue(a, br, 6) if vp8bd_bit(a, br, 128) == 1
      k += 1
    k = 0
    while k < 4
      mode_lf[k] = vp8bd_svalue(a, br, 6) if vp8bd_bit(a, br, 128) == 1
      k += 1
  ftype = level == 0 ? 0 : (simple == 1 ? 1 : 2)
  # partitions
  nparts = 1 << vp8bd_value(a, br, 2)
  pstart = p0 + plen
  psize = rest - plen
  vp8_fail("truncated partitions") if psize < 3 * (nparts - 1)
  parts = []
  pp = pstart + 3 * (nparts - 1)
  left = psize - 3 * (nparts - 1)
  k = 0
  while k < nparts - 1
    sz = a[pstart + k * 3] | (a[pstart + k * 3 + 1] << 8) | (a[pstart + k * 3 + 2] << 16)
    sz = left if sz > left
    s = i64[6]
    vp8bd_init(a, s, pp, sz)
    parts.push(s)
    pp += sz
    left -= sz
    k += 1
  s = i64[6]
  vp8bd_init(a, s, pp, left)
  parts.push(s)
  # quantisers
  base_q = vp8bd_value(a, br, 7)
  dq = [0, 0, 0, 0, 0]
  k = 0
  while k < 5
    dq[k] = vp8bd_bit(a, br, 128) == 1 ? vp8bd_svalue(a, br, 4) : 0
    k += 1
  q = i64[24]
  k = 0
  while k < 4
    qq = base_q
    if use_seg == 1
      qq = seg_q[k]
      qq += base_q if seg_abs == 0
    q[k * 6] = VP8_KDC[vp8_qclip(qq + dq[0], 127)]
    q[k * 6 + 1] = VP8_KAC[vp8_qclip(qq, 127)]
    q[k * 6 + 2] = VP8_KDC[vp8_qclip(qq + dq[1], 127)] * 2
    y2ac = (VP8_KAC[vp8_qclip(qq + dq[2], 127)] * 101581) >> 16
    q[k * 6 + 3] = y2ac < 8 ? 8 : y2ac
    q[k * 6 + 4] = VP8_KDC[vp8_qclip(qq + dq[3], 117)]
    q[k * 6 + 5] = VP8_KAC[vp8_qclip(qq + dq[4], 127)]
    k += 1
  # probabilities
  vp8bd_bit(a, br, 128)
  prob = vp8_read_proba(a, br)
  st[1] = vp8bd_bit(a, br, 128)
  st[2] = vp8bd_value(a, br, 8) if st[1] == 1
  # filter strengths per segment x is4: limit, ilevel, hev
  fs = i64[24]
  k = 0
  while k < 4
    base = level
    if use_seg == 1
      base = seg_f[k]
      base += level if seg_abs == 0
    i4 = 0
    while i4 < 2
      lv = base
      if use_lf == 1
        lv += ref_lf[0]
        lv += mode_lf[0] if i4 == 1
      lv = 0 if lv < 0
      lv = 63 if lv > 63
      o = (k * 2 + i4) * 3
      if lv > 0
        il = lv
        if sharp > 0
          il = sharp > 4 ? il >> 2 : il >> 1
          il = 9 - sharp if il > 9 - sharp
        il = 1 if il < 1
        fs[o] = 2 * lv + il
        fs[o + 1] = il
        fs[o + 2] = lv >= 40 ? 2 : (lv >= 15 ? 1 : 0)
      i4 += 1
    k += 1
  # decode
  tb = vp8_tables()
  bm = vp8_bmodes()
  ys = mbw * 16
  uvs = mbw * 8
  yp = u8[ys * mbh * 16]
  up = u8[uvs * mbh * 8]
  vp = u8[uvs * mbh * 8]
  ty = u8[ys + 4]
  tu = u8[uvs]
  tv = u8[uvs]
  blk = u8[832]
  modes = i64[mbw * 21]
  co = i64[mbw * 384]
  nzs = i64[mbw * 2]
  ctx = i64[mbw * 2 + 2]
  it = i64[mbw * 4]
  il4 = i64[4]
  info = i64[2]
  dcb = i64[16]
  tmp = i64[16]
  fi = i64[mbw * mbh * 4]
  mby = 0
  while mby < mbh
    tok = parts[mby & (nparts - 1)]
    ctx[2 * mbw] = 0
    ctx[2 * mbw + 1] = 0
    k = 0
    while k < 4
      il4[k] = 0
      k += 1
    mbx = 0
    while mbx < mbw
      mo = mbx * 21
      vp8_intra(a, br, st, modes, mo, it, mbx, il4, bm)
      seg = modes[mo + 3]
      is4 = modes[mo]
      skip = st[1] == 1 ? modes[mo + 20] : 0
      if skip == 0
        skip = vp8_residuals(a, tok, prob, q, seg * 6, is4, co, mbx * 384, ctx, mbx, mbw, info, tb, dcb, tmp)
        nzs[mbx * 2] = info[0]
        nzs[mbx * 2 + 1] = info[1]
        vp8_fail("premature end of data") if tok[5] == 1
      else
        ctx[mbx] = 0
        ctx[2 * mbw] = 0
        if is4 == 0
          ctx[mbw + mbx] = 0
          ctx[2 * mbw + 1] = 0
        nzs[mbx * 2] = 0
        nzs[mbx * 2 + 1] = 0
      if ftype > 0
        o = (seg * 2 + is4) * 3
        f = (mby * mbw + mbx) * 4
        fi[f] = fs[o]
        fi[f + 1] = fs[o + 1]
        fi[f + 2] = (is4 == 1 || skip == 0) ? 1 : 0
        fi[f + 3] = fs[o + 2]
      mbx += 1
    vp8_fail("premature end of partition 0") if br[5] == 1
    vp8_recon_row(blk, mby, mbw, mbh, modes, co, nzs, ty, tu, tv, yp, up, vp, tmp)
    mby += 1
  vp8_filter_frame(yp, up, vp, mbw, mbh, fi, ftype) if ftype > 0
  bmp = Bitmap.new(w, h)
  vp8_to_rgba(yp, up, vp, ys, uvs, w, h, bmp.rgba)
  vp8_free_all([yp, up, vp, ty, tu, tv, blk, modes, co, nzs, ctx, it, il4, info, dcb, tmp, fi, prob, tb, bm, q, fs, br])
  parts.each ->(x) vl_free(x)
  bmp

-> vp8_free_all(list)
  list.each ->(x) vl_free(x)
  nil

-> vp8_read_proba(a, br)
  prob = i64[1056]
  p0 = VP8_COEFFS_PROBA0
  up = VP8_COEFFS_UPDATE
  k = 0
  while k < 1056
    if vp8bd_bit(a, br, up[k]) == 1
      prob[k] = vp8bd_value(a, br, 8)
    else
      prob[k] = p0[k]
    k += 1
  prob

-> vp8_bmodes
  vp8_arr(VP8_BMODES_PROBA)
