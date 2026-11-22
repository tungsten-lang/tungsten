# core/codec/image/jxr_xform — JPEG XR reconstruction: dequantisation, the two-stage
# inverse photo core transform (PCT) and the photo overlap transform (POT),
# T.832 clause 9. A plane is rebuilt as whole-image i32 sample buffers, one per
# channel; chroma of YUV420 / YUV422 planes stays subsampled.
#
# Overlap filtering happens on two grids: the DC grid (one sample per 4x4
# block, overlap level 2) and the full-resolution grid (overlap level >= 1).
# Filter windows straddle block corners and partition the grid exactly, so
# they can run in any order. With hard tiles (DISABLE_TILE_OVERLAP) each tile
# is filtered as if it were its own image.

use jxr_mb

-> jxr_quant_map(scaled, x, shift) (i64 i64 i64) i64
  return 1 if x == 0
  man = 0 ## i64
  ex = 0 ## i64
  if scaled != 0
    if x < 16
      man = x
      ex = shift
    else
      man = 16 + (x % 16)
      ex = ((x >> 4) - 1) + shift
  else
    if x < 32
      man = (x + 3) >> 2
      ex = 0
    elsif x < 48
      man = (16 + (x % 16) + 1) >> 1
      ex = (x >> 4) - 2
    else
      man = 16 + (x % 16)
      ex = (x >> 4) - 3
  man << ex

# ---------------------------------------------------------------- PCT

-> jxr_t2x2h(a, ia, ib, ic, id, r) (i32[] i64 i64 i64 i64 i64) i64
  va = a[ia]
  vb = a[ib]
  vc = a[ic]
  vd = a[id]
  va += vd
  vb -= vc
  t1 = (va - vb + r) >> 1
  t2 = vc
  vc = t1 - vd
  vd = t1 - t2
  va -= vd
  vb += vc
  a[ia] = va
  a[ib] = vb
  a[ic] = vc
  a[id] = vd
  0

-> jxr_inv_todd(a, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = a[ia]
  vb = a[ib]
  vc = a[ic]
  vd = a[id]
  vb += vd
  va -= vc
  vd -= vb >> 1
  vc += (va + 1) >> 1
  va -= (vb * 3 + 4) >> 3
  vb += (va * 3 + 4) >> 3
  vc -= (vd * 3 + 4) >> 3
  vd += (vc * 3 + 4) >> 3
  vc -= (vb + 1) >> 1
  vd = ((va + 1) >> 1) - vd
  vb += vc
  va -= vd
  a[ia] = va
  a[ib] = vb
  a[ic] = vc
  a[id] = vd
  0

-> jxr_inv_todd_odd(a, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = a[ia]
  vb = a[ib]
  vc = a[ic]
  vd = a[id]
  vd += va
  vc -= vb
  t1 = vd >> 1
  t2 = vc >> 1
  va -= t1
  vb += t2
  va -= (vb * 3 + 3) >> 3
  vb += (va * 3 + 3) >> 2
  va -= (vb * 3 + 4) >> 3
  vb -= t2
  va += t1
  vc += vb
  vd -= va
  a[ia] = va
  a[ib] = 0 - vb
  a[ic] = 0 - vc
  a[id] = vd
  0

JXR_INV_PERM = jxr_t([0, 8, 4, 13, 2, 15, 3, 14, 1, 12, 5, 9, 7, 11, 6, 10])

# 4x4 inverse PCT on a[o .. o+15] (in place), via scratch t (i32[16]).
-> jxr_ipct4(a, o, t) (i32[] i64 i32[]) i64
  p = JXR_INV_PERM ## i64[]
  i = 0 ## i64
  while i < 16
    t[p[i]] = a[o + i]
    i += 1
  jxr_t2x2h(t, 0, 1, 4, 5, 1)
  jxr_inv_todd(t, 2, 3, 6, 7)
  jxr_inv_todd(t, 8, 12, 9, 13)
  jxr_inv_todd_odd(t, 10, 11, 14, 15)
  jxr_t2x2h(t, 0, 3, 12, 15, 0)
  jxr_t2x2h(t, 5, 6, 9, 10, 0)
  jxr_t2x2h(t, 1, 2, 13, 14, 0)
  jxr_t2x2h(t, 4, 7, 8, 11, 0)
  i = 0
  while i < 16
    a[o + i] = t[i]
    i += 1
  0

# ---------------------------------------------------------------- POT

-> jxr_inv_rotate(a, ia, ib) (i32[] i64 i64) i64
  va = a[ia]
  vb = a[ib]
  va -= (vb + 1) >> 1
  vb += (va + 1) >> 1
  a[ia] = va
  a[ib] = vb
  0

-> jxr_inv_scale(a, ia, ib) (i32[] i64 i64) i64
  va = a[ia]
  vb = a[ib]
  va += vb
  vb = (va >> 1) - vb
  va += (vb * 3) >> 3
  vb -= va >> 10
  vb += va >> 7
  vb += (va * 3) >> 4
  a[ia] = va
  a[ib] = vb
  0

-> jxr_t2x2h_post(a, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = a[ia]
  vb = a[ib]
  vc = a[ic]
  vd = a[id]
  vb -= vc
  va += (vd * 3 + 4) >> 3
  vd -= vb >> 1
  t1 = ((va - vb) >> 1) - vc
  vc = vd
  vd = t1
  va -= vd
  vb += vc
  a[ia] = va
  a[ib] = vb
  a[ic] = vc
  a[id] = vd
  0

-> jxr_inv_todd_odd_post(a, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = a[ia]
  vb = a[ib]
  vc = a[ic]
  vd = a[id]
  vd += va
  vc -= vb
  t1 = vd >> 1
  t2 = vc >> 1
  va -= t1
  vb += t2
  va -= (vb * 3 + 6) >> 3
  vb += (va * 3 + 2) >> 2
  va -= (vb * 3 + 4) >> 3
  vb -= t2
  va += t1
  vc += vb
  vd -= va
  a[ia] = va
  a[ib] = vb
  a[ic] = vc
  a[id] = vd
  0

# 4x4 overlap filter on the window whose top-left sample is at index o.
-> jxr_ovl4x4(p, o, s) (i32[] i64 i64) i64
  a = o
  b = o + 1
  c = o + 2
  d = o + 3
  e = o + s
  f = e + 1
  g = e + 2
  h = e + 3
  i = o + 2 * s
  j = i + 1
  k = i + 2
  l = i + 3
  m = o + 3 * s
  n = m + 1
  oo = m + 2
  pp = m + 3
  jxr_t2x2h(p, a, d, m, pp, 0)
  jxr_t2x2h(p, b, c, n, oo, 0)
  jxr_t2x2h(p, e, h, i, l, 0)
  jxr_t2x2h(p, f, g, j, k, 0)
  jxr_inv_rotate(p, n, m)
  jxr_inv_rotate(p, j, i)
  jxr_inv_rotate(p, h, d)
  jxr_inv_rotate(p, g, c)
  jxr_inv_todd_odd_post(p, k, l, oo, pp)
  jxr_inv_scale(p, a, pp)
  jxr_inv_scale(p, b, oo)
  jxr_inv_scale(p, e, l)
  jxr_inv_scale(p, f, k)
  jxr_t2x2h_post(p, a, d, m, pp)
  jxr_t2x2h_post(p, b, c, n, oo)
  jxr_t2x2h_post(p, e, h, i, l)
  jxr_t2x2h_post(p, f, g, j, k)
  0

-> jxr_ovl4(p, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vc = p[ic]
  vd = p[id]
  va += vd
  vb += vc
  vd -= (va + 1) >> 1
  vc -= (vb + 1) >> 1
  # InvScale(a, d)
  va += vd
  vd = (va >> 1) - vd
  va += (vd * 3) >> 3
  vd -= va >> 10
  vd += va >> 7
  vd += (va * 3) >> 4
  # InvScale(b, c)
  vb += vc
  vc = (vb >> 1) - vc
  vb += (vc * 3) >> 3
  vc -= vb >> 10
  vc += vb >> 7
  vc += (vb * 3) >> 4
  va += (vd * 3 + 4) >> 3
  vb += (vc * 3 + 4) >> 3
  vd -= va >> 1
  vc -= vb >> 1
  va += vd
  vb += vc
  vd = 0 - vd
  vc = 0 - vc
  # InvRotate(c, d)
  vc -= (vd + 1) >> 1
  vd += (vc + 1) >> 1
  vd += (va + 1) >> 1
  vc += (vb + 1) >> 1
  va -= vd
  vb -= vc
  p[ia] = va
  p[ib] = vb
  p[ic] = vc
  p[id] = vd
  0

-> jxr_ovl2x2(p, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vc = p[ic]
  vd = p[id]
  va += vd
  vb += vc
  vd -= (va + 1) >> 1
  vc -= (vb + 1) >> 1
  vb += (va + 2) >> 2
  va += (vb + 1) >> 1
  va += vb >> 5
  va += vb >> 9
  va += vb >> 13
  vb += (va + 2) >> 2
  vd += (va + 1) >> 1
  vc += (vb + 1) >> 1
  va -= vd
  vb -= vc
  p[ia] = va
  p[ib] = vb
  p[ic] = vc
  p[id] = vd
  0

-> jxr_ovl2(p, ia, ib) (i32[] i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vb += (va + 2) >> 2
  va += (vb + 1) >> 1
  va += vb >> 5
  va += vb >> 9
  va += vb >> 13
  vb += (va + 2) >> 2
  p[ia] = va
  p[ib] = vb
  0

# Overlap filtering with 4-sample windows on the region [x0, x0+w) × [y0, y0+h)
# of p (row stride s); block size 4.
-> jxr_ovl_region4(p, s, x0, y0, w, h) (i32[] i64 i64 i64 i64 i64) i64
  x1 = x0 + w
  y1 = y0 + h
  y = y0 + 4
  while y < y1
    x = x0 + 4
    while x < x1
      jxr_ovl4x4(p, (y - 2) * s + x - 2, s)
      x += 4
    y += 4
  x = x0 + 4
  while x < x1
    r = y0 * s + x
    jxr_ovl4(p, r - 2, r - 1, r, r + 1)
    r += s
    jxr_ovl4(p, r - 2, r - 1, r, r + 1)
    r = (y1 - 2) * s + x
    jxr_ovl4(p, r - 2, r - 1, r, r + 1)
    r += s
    jxr_ovl4(p, r - 2, r - 1, r, r + 1)
    x += 4
  y = y0 + 4
  while y < y1
    c = (y - 2) * s
    jxr_ovl4(p, c + x0, c + s + x0, c + 2 * s + x0, c + 3 * s + x0)
    jxr_ovl4(p, c + x0 + 1, c + s + x0 + 1, c + 2 * s + x0 + 1, c + 3 * s + x0 + 1)
    jxr_ovl4(p, c + x1 - 2, c + s + x1 - 2, c + 2 * s + x1 - 2, c + 3 * s + x1 - 2)
    jxr_ovl4(p, c + x1 - 1, c + s + x1 - 1, c + 2 * s + x1 - 1, c + 3 * s + x1 - 1)
    y += 4
  t = y0 * s
  jxr_ovl4(p, t + x0, t + x0 + 1, t + s + x0, t + s + x0 + 1)
  jxr_ovl4(p, t + x1 - 2, t + x1 - 1, t + s + x1 - 2, t + s + x1 - 1)
  t = (y1 - 2) * s
  jxr_ovl4(p, t + x0, t + x0 + 1, t + s + x0, t + s + x0 + 1)
  jxr_ovl4(p, t + x1 - 2, t + x1 - 1, t + s + x1 - 2, t + s + x1 - 1)
  0

# The same with 2-sample windows (DC grid of YUV420 / YUV422 chroma). Corner
# samples ride along with their horizontal neighbour (difference before the
# filters, sum after), as in the reference decoder.
-> jxr_ovl_region2(p, s, x0, y0, w, h) (i32[] i64 i64 i64 i64 i64) i64
  x1 = x0 + w - 1
  y1 = y0 + h - 1
  t = y0 * s
  b = y1 * s
  if w == 2
    # One macroblock wide: jxrlib's pipelined corner bookkeeping takes both
    # differences from the original values and adds them back after, which
    # leaves the left corners at zero and the right ones unchanged.
    p[t + x0] = 0
    p[b + x0] = 0
  else
    p[t + x0] = p[t + x0] - p[t + x0 + 1]
    p[t + x1] = p[t + x1] - p[t + x1 - 1]
    p[b + x0] = p[b + x0] - p[b + x0 + 1]
    p[b + x1] = p[b + x1] - p[b + x1 - 1]
  x = x0 + 2
  while x <= x1
    jxr_ovl2(p, t + x - 1, t + x)
    jxr_ovl2(p, b + x - 1, b + x)
    x += 2
  y = y0 + 2
  while y <= y1
    jxr_ovl2(p, (y - 1) * s + x0, y * s + x0)
    jxr_ovl2(p, (y - 1) * s + x1, y * s + x1)
    x = x0 + 2
    while x <= x1
      jxr_ovl2x2(p, (y - 1) * s + x - 1, (y - 1) * s + x, y * s + x - 1, y * s + x)
      x += 2
    y += 2
  if w != 2
    p[t + x0] = p[t + x0] + p[t + x0 + 1]
    p[t + x1] = p[t + x1] + p[t + x1 - 1]
    p[b + x0] = p[b + x0] + p[b + x0 + 1]
    p[b + x1] = p[b + x1] + p[b + x1 - 1]
  0

# ---------------------------------------------------------------- HD Photo (codec subversion 0) operators
#
# Codestreams with codec subversion 0 (the original HD Photo bitstreams; JPEG
# XR proper uses 1 or 9) use the earlier overlap operators: no corner filters,
# simpler scale steps, and the first-stage 4x4 filter followed by a DC
# compensation that depends on the HP quantiser (jxrlib's strPost*).

-> jxr_hst1_old(p, ia, id) (i32[] i64 i64) i64
  a = p[ia]
  d = p[id]
  a += d
  d = (a >> 1) - d
  a += (d * 3) >> 3
  d += (a * 3) >> 4
  p[ia] = a
  p[id] = d
  0

-> jxr_dc_comp(p, i1, i2, i3, i4, hqp, absent) (i32[] i64 i64 i64 i64 i64 i64) i64
  t = (p[i1] + p[i2] + p[i3] + p[i4]) >> 1
  dcl = (t * 595 + 65536) >> 17
  ad = dcl
  ad = 0 - dcl if dcl < 0
  if (ad < hqp && hqp > 20) || absent != 0
    alt = (p[i1] - p[i3] - p[i2] + p[i4]) >> 1
    c = 0 ## i64
    if dcl > 0
      if alt > 0
        c = dcl
        c = alt if alt < dcl
    elsif dcl < 0
      if alt < 0
        c = dcl
        c = alt if alt > dcl
    h = c >> 1
    p[i1] = p[i1] - h
    p[i4] = p[i4] - h
    p[i2] = p[i2] + h
    p[i3] = p[i3] + h
  0

-> jxr_ovl4x4_old(p, o, s, comp, hqp, absent) (i32[] i64 i64 i64 i64 i64) i64
  a = o
  b = o + 1
  c = o + 2
  d = o + 3
  e = o + s
  f = e + 1
  g = e + 2
  h = e + 3
  i = o + 2 * s
  j = i + 1
  k = i + 2
  l = i + 3
  m = o + 3 * s
  n = m + 1
  oo = m + 2
  pp = m + 3
  jxr_t2x2h(p, a, d, m, pp, 0)
  jxr_t2x2h(p, b, c, n, oo, 0)
  jxr_t2x2h(p, e, h, i, l, 0)
  jxr_t2x2h(p, f, g, j, k, 0)
  jxr_inv_todd_odd_post(p, k, l, oo, pp)
  jxr_inv_rotate(p, n, m)
  jxr_inv_rotate(p, j, i)
  jxr_inv_rotate(p, h, d)
  jxr_inv_rotate(p, g, c)
  jxr_hst1_old(p, a, pp)
  jxr_hst1_old(p, b, oo)
  jxr_hst1_old(p, e, l)
  jxr_hst1_old(p, f, k)
  jxr_t2x2h_post(p, a, d, m, pp)
  jxr_t2x2h_post(p, b, c, n, oo)
  jxr_t2x2h_post(p, e, h, i, l)
  jxr_t2x2h_post(p, f, g, j, k)
  if comp != 0
    jxr_dc_comp(p, a, d, m, pp, hqp, absent)
    jxr_dc_comp(p, b, c, n, oo, hqp, absent)
    jxr_dc_comp(p, e, h, i, l, hqp, absent)
    jxr_dc_comp(p, f, g, j, k, hqp, absent)
  0

-> jxr_ovl4_old(p, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vc = p[ic]
  vd = p[id]
  va += vd
  vb += vc
  vd -= (va + 1) >> 1
  vc -= (vb + 1) >> 1
  vc -= (vd + 1) >> 1
  vd += (vc + 1) >> 1
  vd += (va + 1) >> 1
  vc += (vb + 1) >> 1
  va -= vd - ((vd * 3 + 16) >> 5)
  vb -= vc - ((vc * 3 + 16) >> 5)
  vd += (va * 3 + 8) >> 4
  vc += (vb * 3 + 8) >> 4
  va += (vd * 3 + 16) >> 5
  vb += (vc * 3 + 16) >> 5
  p[ia] = va
  p[ib] = vb
  p[ic] = vc
  p[id] = vd
  0

-> jxr_ovl2x2_old(p, ia, ib, ic, id) (i32[] i64 i64 i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vc = p[ic]
  vd = p[id]
  va += vd
  vb += vc
  vd -= (va + 1) >> 1
  vc -= (vb + 1) >> 1
  vb += (va + 2) >> 2
  va += (vb + 1) >> 1
  vb += (va + 2) >> 2
  vd += (va + 1) >> 1
  vc += (vb + 1) >> 1
  va -= vd
  vb -= vc
  p[ia] = va
  p[ib] = vb
  p[ic] = vc
  p[id] = vd
  0

-> jxr_ovl2_old(p, ia, ib) (i32[] i64 i64) i64
  va = p[ia]
  vb = p[ib]
  vb += (va + 4) >> 3
  va += (vb + 2) >> 2
  vb += (va + 4) >> 3
  p[ia] = va
  p[ib] = vb
  0

-> jxr_ovl_region4_old(p, s, x0, y0, w, h, comp, wq, mw, mh, qs, absent) (i32[] i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64 i64) i64
  x1 = x0 + w
  y1 = y0 + h
  y = y0 + 4
  while y < y1
    x = x0 + 4
    while x < x1
      q = 0 ## i64
      q = wq[(y / mh) * qs + x / mw] if comp != 0
      jxr_ovl4x4_old(p, (y - 2) * s + x - 2, s, comp, q, absent)
      x += 4
    y += 4
  x = x0 + 4
  while x < x1
    r = y0 * s + x
    jxr_ovl4_old(p, r - 2, r - 1, r, r + 1)
    r += s
    jxr_ovl4_old(p, r - 2, r - 1, r, r + 1)
    r = (y1 - 2) * s + x
    jxr_ovl4_old(p, r - 2, r - 1, r, r + 1)
    r += s
    jxr_ovl4_old(p, r - 2, r - 1, r, r + 1)
    x += 4
  y = y0 + 4
  while y < y1
    c = (y - 2) * s
    jxr_ovl4_old(p, c + x0, c + s + x0, c + 2 * s + x0, c + 3 * s + x0)
    jxr_ovl4_old(p, c + x0 + 1, c + s + x0 + 1, c + 2 * s + x0 + 1, c + 3 * s + x0 + 1)
    jxr_ovl4_old(p, c + x1 - 2, c + s + x1 - 2, c + 2 * s + x1 - 2, c + 3 * s + x1 - 2)
    jxr_ovl4_old(p, c + x1 - 1, c + s + x1 - 1, c + 2 * s + x1 - 1, c + 3 * s + x1 - 1)
    y += 4
  0

-> jxr_ovl_region2_old(p, s, x0, y0, w, h) (i32[] i64 i64 i64 i64 i64) i64
  x1 = x0 + w - 1
  y1 = y0 + h - 1
  t = y0 * s
  b = y1 * s
  x = x0 + 2
  while x <= x1
    jxr_ovl2_old(p, t + x - 1, t + x)
    jxr_ovl2_old(p, b + x - 1, b + x)
    x += 2
  y = y0 + 2
  while y <= y1
    jxr_ovl2_old(p, (y - 1) * s + x0, y * s + x0)
    jxr_ovl2_old(p, (y - 1) * s + x1, y * s + x1)
    x = x0 + 2
    while x <= x1
      jxr_ovl2x2_old(p, (y - 1) * s + x - 1, (y - 1) * s + x, y * s + x - 1, y * s + x)
      x += 2
    y += 2
  0

# Region boundaries (in macroblocks) from tile offsets: 0, the offsets that
# fall strictly inside (0, limit), and limit.
-> jxr_cuts(offs, n, limit)
  r = [0]
  k = 1
  while k < n
    v = offs[k]
    r.push(v) if v > r.last && v < limit
    k += 1
  r.push(limit)
  r

# Apply an overlap pass over the whole grid or per hard tile. bw/bh: grid
# samples per macroblock; small = 1 for the 2-sample filters.
-> jxr_ovl_grid(im, p, s, bw, bh, small, comp, wq, absent)
  old = im.sub == 0
  if old
    if small == 1
      jxr_ovl_region2_old(p, s, 0, 0, s, im.mbh * bh)
    else
      jxr_ovl_region4_old(p, s, 0, 0, s, im.mbh * bh, comp, wq, bw, bh, im.mbw, absent)
  elsif im.no_tile_ovl == 1
    # Hard tiles: jxrlib (and so every encoder and decoder built on it)
    # places the filter-free boundaries with the tile axes swapped -- the
    # vertical boundaries at the tile *row* offsets and the horizontal ones
    # at the tile *column* offsets (invTransformMacroblock_alteredOperators_hard
    # compares cColumn with uiTileY and cRow with uiTileX). Match it, since
    # hard-tiled files in the wild come from that code.
    xs = jxr_cuts(im.trp, im.trows, im.mbw)
    ys = jxr_cuts(im.tcp, im.tcols, im.mbh)
    j = 0
    while j + 1 < ys.size
      i = 0
      while i + 1 < xs.size
        x0 = xs[i] * bw
        y0 = ys[j] * bh
        w = (xs[i + 1] - xs[i]) * bw
        h = (ys[j + 1] - ys[j]) * bh
        if small == 1
          jxr_ovl_region2(p, s, x0, y0, w, h)
        else
          jxr_ovl_region4(p, s, x0, y0, w, h)
        i += 1
      j += 1
  else
    if small == 1
      jxr_ovl_region2(p, s, 0, 0, s, im.mbh * bh)
    else
      jxr_ovl_region4(p, s, 0, 0, s, im.mbh * bh)

# ---------------------------------------------------------------- per channel

-> jxr_dequant_dclp(co, b, cnt, dq, lq) (i32[] i64 i64 i64 i64) i64
  co[b] = co[b] * dq
  k = 1 ## i64
  while k < cnt
    co[b + k] = co[b + k] * lq
    k += 1
  0

-> jxr_level1(co, b, kind, scaled, t) (i32[] i64 i64 i64 i32[]) i64
  if kind == 1
    jxr_t2x2h(co, b, b + 1, b + 2, b + 3, 0)
    v = co[b + 1]
    co[b + 1] = co[b + 2]
    co[b + 2] = v
    if scaled != 0
      k = 0 ## i64
      while k < 4
        co[b + k] = co[b + k] * 2
        k += 1
  elsif kind == 2
    va = co[b]
    vb = co[b + 4]
    va -= (vb + 1) >> 1
    vb += va
    co[b] = va
    co[b + 4] = vb
    jxr_t2x2h(co, b, b + 1, b + 2, b + 3, 0)
    # T.832 Table 151 feeds the lower pair as {4, 6, 5, 7}
    jxr_t2x2h(co, b + 4, b + 6, b + 5, b + 7, 0)
    v = co[b + 1]
    co[b + 1] = co[b + 2]
    co[b + 2] = v
    v = co[b + 5]
    co[b + 5] = co[b + 6]
    co[b + 6] = v
    if scaled != 0
      k = 0
      while k < 8
        co[b + k] = co[b + k] * 2
        k += 1
  else
    jxr_ipct4(co, b, t)
    if scaled != 0 && kind == 3
      k = 0
      while k < 16
        co[b + k] = co[b + k] * 2
        k += 1
  0

# Second stage for one macroblock: per 4x4 block, DC from the DC grid (dcg at
# gbase, stride gs, bw blocks per row) plus dequantised HP, inverse PCT, into
# plane pix (stride ps) at (px, py).
-> jxr_level2(co, b, nblk, bw, hq, dcg, gbase, gs, pix, ps, px, py, t, blk) (i32[] i64 i64 i64 i64 i32[] i64 i64 i32[] i64 i64 i64 i32[] i32[]) i64
  j = 0 ## i64
  while j < nblk
    bx = j % bw
    by = j / bw
    blk[0] = dcg[gbase + by * gs + bx]
    h = b + 16 + 15 * j
    k = 0 ## i64
    while k < 15
      blk[k + 1] = co[h + k] * hq
      k += 1
    jxr_ipct4(blk, 0, t)
    o = (py + by * 4) * ps + px + bx * 4
    r = 0 ## i64
    while r < 4
      pix[o] = blk[r * 4]
      pix[o + 1] = blk[r * 4 + 1]
      pix[o + 2] = blk[r * 4 + 2]
      pix[o + 3] = blk[r * 4 + 3]
      o += ps
      r += 1
    j += 1
  0

-> jxr_tile_index(starts, sizes, n, count)
  r = i64[count]
  t = 0
  i = 0
  while i < count
    while t + 1 < n && i >= starts[t] + sizes[t]
      t += 1
    r[i] = t
    i += 1
  r

# Rebuild every channel of a plane. Returns [buffers, widths, heights].
-> jxr_reconstruct(im, pl)
  co = pl.co ## i32[]
  nmb = im.nmb
  mbw = im.mbw
  mbh = im.mbh
  scaled = pl.scaled
  tcol = jxr_tile_index(im.tcp, im.tcw, im.tcols, mbw)
  trow = jxr_tile_index(im.trp, im.trh, im.trows, mbh)
  dcq = pl.dcq ## i64[]
  lpq = pl.lpq ## i64[]
  tdcq = pl.tdcq ## i64[]
  tlpq = pl.tlpq ## i64[]
  lpqi = pl.lpqi ## i64[]
  hpqv = pl.hpqv ## i64[]
  hpfl = pl.hpfl ## i64[]
  t = i32[16]
  blk = i32[16]
  bufs = []
  ws = []
  hs = []
  ovl = im.overlap
  ch = 0
  while ch < pl.nch
    kind = 0
    if ch > 0
      kind = 3
      kind = 1 if pl.clr == 1
      kind = 2 if pl.clr == 2
    bw = 4
    bh = 4
    if kind == 1
      bw = 2
      bh = 2
    elsif kind == 2
      bw = 2
      bh = 4
    cnt = bw * bh
    sh = 0
    sh = 1 if ch == 0
    # dequantise DC/LP and run the first inverse PCT stage
    gw = mbw * bw
    gh = mbh * bh
    dcg = i32[gw * gh]
    my = 0
    while my < mbh
      mx = 0
      while mx < mbw
        g = my * mbw + mx
        ti = trow[my] * im.tcols + tcol[mx]
        draw = dcq[ch]
        draw = tdcq[ti * 16 + ch] if pl.dc_uni == 0
        lraw = lpq[ch * 16 + lpqi[g]]
        lraw = tlpq[ti * 256 + ch * 16 + lpqi[g]] if pl.lp_uni == 0
        b = (ch * nmb + g) * 256
        jxr_dequant_dclp(co, b, cnt, jxr_quant_map(scaled, draw, sh), jxr_quant_map(scaled, lraw, sh))
        jxr_level1(co, b, kind, scaled, t)
        j = 0
        while j < cnt
          dcg[(my * bh + j / bw) * gw + mx * bw + j % bw] = co[b + j]
          j += 1
        mx += 1
      my += 1
    if ovl >= 2
      small = 0
      small = 1 if kind == 1 || kind == 2
      jxr_ovl_grid(im, dcg, gw, bw, bh, small, 0, i64[1], 0)
    pw = gw * 4
    ph = gh * 4
    pix = i32[pw * ph]
    my = 0
    while my < mbh
      mx = 0
      while mx < mbw
        g = my * mbw + mx
        b = (ch * nmb + g) * 256
        hsh = 1
        hsh = sh if hpfl[g] == 1
        hq = jxr_quant_map(scaled, hpqv[ch * nmb + g], hsh)
        jxr_level2(co, b, cnt, bw, hq, dcg, my * bh * gw + mx * bw, gw, pix, pw, mx * bw * 4, my * bh * 4, t, blk)
        mx += 1
      my += 1
    if ovl >= 1
      wq = i64[1]
      absent = 0
      if im.sub == 0
        # per-macroblock HP step for the HD Photo DC compensation
        wq = i64[nmb]
        g = 0
        while g < nmb
          hs2 = 1
          hs2 = sh if hpfl[g] == 1
          wq[g] = jxr_quant_map(scaled, hpqv[ch * nmb + g], hs2)
          g += 1
        absent = 1 if pl.bands == 2 || pl.bands == 3
      jxr_ovl_grid(im, pix, pw, bw * 4, bh * 4, 0, 1, wq, absent)
    bufs.push(pix)
    ws.push(pw)
    hs.push(ph)
    ch += 1
  [bufs, ws, hs]
