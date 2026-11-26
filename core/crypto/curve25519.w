# blade/curve25519 — X25519 and X448 Diffie-Hellman (RFC 7748) in typed Tungsten.
#
# X25519: GF(2^255 - 19) in radix 2^51 (5 limbs held in i64[5]); products are taken
# as 128-bit (`a * b` and `mulhi(a, b)`, one MUL + UMULH on arm64) and carried back into 51-bit
# limbs. Montgomery ladder over the 255 scalar bits with a constant-time conditional
# swap (mask arithmetic, no secret-dependent branch or index), inversion by Fermat
# (z^(p-2)) with the usual 254-squaring / 11-multiply addition chain. Nothing is
# allocated inside the ladder; all scratch is preallocated per call.
#
# X448: GF(2^448 - 2^224 - 1) in radix 2^56 (8 limbs in i64[8]), Karatsuba-free
# schoolbook products in u128 using the golden-ratio reduction
# 2^448 = 2^224 + 1. Same ladder structure, a24 = 39081, 448 scalar bits,
# inversion by z^(p-2).
#
# API (all byte strings are ByteArray, little-endian as in RFC 7748):
#   x25519_fast(k32, u32)       -> ByteArray(32)   scalar mult of u-coordinate u by k
#   x25519_base_fast(k32)       -> ByteArray(32)   k * 9 (public key from private key)
#   x448(k56, u56)              -> ByteArray(56)
#   x448_base(k56)              -> ByteArray(56)   k * 5
# Typed cores (no allocation besides their scratch; out must be preallocated):
#   x25519_into(out, k, u)  (u8[] u8[] u8[]) i64   writes 32 bytes to out
#   x448_into(out, k, u)    (u8[] u8[] u8[]) i64   writes 56 bytes to out
# The caller checks for the all-zero shared secret (RFC 7748 §6.1) if it needs to;
# `x25519_is_zero(b)` is provided for that.

# ---------------------------------------------------------------------------
# GF(2^255 - 19), radix 2^51

M51 = 2251799813685247

-> fe_copy(h, f) (i64[] i64[]) i64
  h[0] = f[0]
  h[1] = f[1]
  h[2] = f[2]
  h[3] = f[3]
  h[4] = f[4]
  0

-> fe_set(h, v) (i64[] i64) i64
  h[0] = v
  h[1] = 0
  h[2] = 0
  h[3] = 0
  h[4] = 0
  0

-> fe_add(h, f, g) (i64[] i64[] i64[]) i64
  h[0] = f[0] + g[0]
  h[1] = f[1] + g[1]
  h[2] = f[2] + g[2]
  h[3] = f[3] + g[3]
  h[4] = f[4] + g[4]
  0

# h = f - g + 2p (g limbs must be below 2^52 - 38, true for any carried value)
-> fe_sub(h, f, g) (i64[] i64[] i64[]) i64
  h[0] = f[0] + 4503599627370458 - g[0]
  h[1] = f[1] + 4503599627370494 - g[1]
  h[2] = f[2] + 4503599627370494 - g[2]
  h[3] = f[3] + 4503599627370494 - g[3]
  h[4] = f[4] + 4503599627370494 - g[4]
  0

# Products are 64x64->128 via `a * b` (low half) and `mulhi` (UMULH), summed as
# (lo, hi) u64 pairs with `addcarry`. (A `## u128` local is a boxed Integer on the
# current toolchain: each one allocated a BigInt, ~14 MB per X25519 call.)
# Inputs: limbs below 2^54. Output: limbs below 2^51 + 2^13.
-> fe_mul(h, f, g) (i64[] i64[] i64[]) i64
  f0 = f[0] ## u64
  f1 = f[1] ## u64
  f2 = f[2] ## u64
  f3 = f[3] ## u64
  f4 = f[4] ## u64
  g0 = g[0] ## u64
  g1 = g[1] ## u64
  g2 = g[2] ## u64
  g3 = g[3] ## u64
  g4 = g[4] ## u64
  g1_19 = g1 * 19 ## u64
  g2_19 = g2 * 19 ## u64
  g3_19 = g3 * 19 ## u64
  g4_19 = g4 * 19 ## u64
  l0 = f0 * g0 ## u64
  h0 = mulhi(f0, g0) ## u64
  p = f1 * g4_19 ## u64
  h0 = h0 + mulhi(f1, g4_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  p = f2 * g3_19 ## u64
  h0 = h0 + mulhi(f2, g3_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  p = f3 * g2_19 ## u64
  h0 = h0 + mulhi(f3, g2_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  p = f4 * g1_19 ## u64
  h0 = h0 + mulhi(f4, g1_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  l1 = f0 * g1 ## u64
  h1 = mulhi(f0, g1) ## u64
  p = f1 * g0 ## u64
  h1 = h1 + mulhi(f1, g0) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  p = f2 * g4_19 ## u64
  h1 = h1 + mulhi(f2, g4_19) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  p = f3 * g3_19 ## u64
  h1 = h1 + mulhi(f3, g3_19) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  p = f4 * g2_19 ## u64
  h1 = h1 + mulhi(f4, g2_19) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  l2 = f0 * g2 ## u64
  h2 = mulhi(f0, g2) ## u64
  p = f1 * g1 ## u64
  h2 = h2 + mulhi(f1, g1) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  p = f2 * g0 ## u64
  h2 = h2 + mulhi(f2, g0) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  p = f3 * g4_19 ## u64
  h2 = h2 + mulhi(f3, g4_19) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  p = f4 * g3_19 ## u64
  h2 = h2 + mulhi(f4, g3_19) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  l3 = f0 * g3 ## u64
  h3 = mulhi(f0, g3) ## u64
  p = f1 * g2 ## u64
  h3 = h3 + mulhi(f1, g2) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  p = f2 * g1 ## u64
  h3 = h3 + mulhi(f2, g1) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  p = f3 * g0 ## u64
  h3 = h3 + mulhi(f3, g0) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  p = f4 * g4_19 ## u64
  h3 = h3 + mulhi(f4, g4_19) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  l4 = f0 * g4 ## u64
  h4 = mulhi(f0, g4) ## u64
  p = f1 * g3 ## u64
  h4 = h4 + mulhi(f1, g3) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  p = f2 * g2 ## u64
  h4 = h4 + mulhi(f2, g2) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  p = f3 * g1 ## u64
  h4 = h4 + mulhi(f3, g1) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  p = f4 * g0 ## u64
  h4 = h4 + mulhi(f4, g0) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  c = (l0 >> 51) | (h0 << 13) ## u64
  r0 = l0 & M51 ## u64
  h1 = h1 + addcarry(l1, c) ## u64
  l1 = l1 + c ## u64
  c = (l1 >> 51) | (h1 << 13) ## u64
  r1 = l1 & M51 ## u64
  h2 = h2 + addcarry(l2, c) ## u64
  l2 = l2 + c ## u64
  c = (l2 >> 51) | (h2 << 13) ## u64
  r2 = l2 & M51 ## u64
  h3 = h3 + addcarry(l3, c) ## u64
  l3 = l3 + c ## u64
  c = (l3 >> 51) | (h3 << 13) ## u64
  r3 = l3 & M51 ## u64
  h4 = h4 + addcarry(l4, c) ## u64
  l4 = l4 + c ## u64
  c = (l4 >> 51) | (h4 << 13) ## u64
  r4 = l4 & M51 ## u64
  r0 = r0 + c * 19 ## u64
  r1 = r1 + (r0 >> 51) ## u64
  r0 = r0 & M51 ## u64
  h[0] = r0
  h[1] = r1
  h[2] = r2
  h[3] = r3
  h[4] = r4
  0

-> fe_sq(h, f) (i64[] i64[]) i64
  f0 = f[0] ## u64
  f1 = f[1] ## u64
  f2 = f[2] ## u64
  f3 = f[3] ## u64
  f4 = f[4] ## u64
  f0_2 = f0 * 2 ## u64
  f1_2 = f1 * 2 ## u64
  f2_2 = f2 * 2 ## u64
  f3_2 = f3 * 2 ## u64
  f3_19 = f3 * 19 ## u64
  f4_19 = f4 * 19 ## u64
  l0 = f0 * f0 ## u64
  h0 = mulhi(f0, f0) ## u64
  p = f1_2 * f4_19 ## u64
  h0 = h0 + mulhi(f1_2, f4_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  p = f2_2 * f3_19 ## u64
  h0 = h0 + mulhi(f2_2, f3_19) + addcarry(l0, p) ## u64
  l0 = l0 + p ## u64
  l1 = f0_2 * f1 ## u64
  h1 = mulhi(f0_2, f1) ## u64
  p = f2_2 * f4_19 ## u64
  h1 = h1 + mulhi(f2_2, f4_19) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  p = f3 * f3_19 ## u64
  h1 = h1 + mulhi(f3, f3_19) + addcarry(l1, p) ## u64
  l1 = l1 + p ## u64
  l2 = f0_2 * f2 ## u64
  h2 = mulhi(f0_2, f2) ## u64
  p = f1 * f1 ## u64
  h2 = h2 + mulhi(f1, f1) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  p = f3_2 * f4_19 ## u64
  h2 = h2 + mulhi(f3_2, f4_19) + addcarry(l2, p) ## u64
  l2 = l2 + p ## u64
  l3 = f0_2 * f3 ## u64
  h3 = mulhi(f0_2, f3) ## u64
  p = f1_2 * f2 ## u64
  h3 = h3 + mulhi(f1_2, f2) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  p = f4 * f4_19 ## u64
  h3 = h3 + mulhi(f4, f4_19) + addcarry(l3, p) ## u64
  l3 = l3 + p ## u64
  l4 = f0_2 * f4 ## u64
  h4 = mulhi(f0_2, f4) ## u64
  p = f1_2 * f3 ## u64
  h4 = h4 + mulhi(f1_2, f3) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  p = f2 * f2 ## u64
  h4 = h4 + mulhi(f2, f2) + addcarry(l4, p) ## u64
  l4 = l4 + p ## u64
  c = (l0 >> 51) | (h0 << 13) ## u64
  r0 = l0 & M51 ## u64
  h1 = h1 + addcarry(l1, c) ## u64
  l1 = l1 + c ## u64
  c = (l1 >> 51) | (h1 << 13) ## u64
  r1 = l1 & M51 ## u64
  h2 = h2 + addcarry(l2, c) ## u64
  l2 = l2 + c ## u64
  c = (l2 >> 51) | (h2 << 13) ## u64
  r2 = l2 & M51 ## u64
  h3 = h3 + addcarry(l3, c) ## u64
  l3 = l3 + c ## u64
  c = (l3 >> 51) | (h3 << 13) ## u64
  r3 = l3 & M51 ## u64
  h4 = h4 + addcarry(l4, c) ## u64
  l4 = l4 + c ## u64
  c = (l4 >> 51) | (h4 << 13) ## u64
  r4 = l4 & M51 ## u64
  r0 = r0 + c * 19 ## u64
  r1 = r1 + (r0 >> 51) ## u64
  r0 = r0 & M51 ## u64
  h[0] = r0
  h[1] = r1
  h[2] = r2
  h[3] = r3
  h[4] = r4
  0

# h = f * n for a small constant n (< 2^20)
-> fe_mul_small(h, f, n) (i64[] i64[] i64) i64
  m = n ## u64
  fk = f[0] ## u64
  l0 = fk * m ## u64
  h0 = mulhi(fk, m) ## u64
  fk = f[1] ## u64
  l1 = fk * m ## u64
  h1 = mulhi(fk, m) ## u64
  fk = f[2] ## u64
  l2 = fk * m ## u64
  h2 = mulhi(fk, m) ## u64
  fk = f[3] ## u64
  l3 = fk * m ## u64
  h3 = mulhi(fk, m) ## u64
  fk = f[4] ## u64
  l4 = fk * m ## u64
  h4 = mulhi(fk, m) ## u64
  c = (l0 >> 51) | (h0 << 13) ## u64
  r0 = l0 & M51 ## u64
  h1 = h1 + addcarry(l1, c) ## u64
  l1 = l1 + c ## u64
  c = (l1 >> 51) | (h1 << 13) ## u64
  r1 = l1 & M51 ## u64
  h2 = h2 + addcarry(l2, c) ## u64
  l2 = l2 + c ## u64
  c = (l2 >> 51) | (h2 << 13) ## u64
  r2 = l2 & M51 ## u64
  h3 = h3 + addcarry(l3, c) ## u64
  l3 = l3 + c ## u64
  c = (l3 >> 51) | (h3 << 13) ## u64
  r3 = l3 & M51 ## u64
  h4 = h4 + addcarry(l4, c) ## u64
  l4 = l4 + c ## u64
  c = (l4 >> 51) | (h4 << 13) ## u64
  r4 = l4 & M51 ## u64
  r0 = r0 + c * 19 ## u64
  r1 = r1 + (r0 >> 51) ## u64
  r0 = r0 & M51 ## u64
  h[0] = r0
  h[1] = r1
  h[2] = r2
  h[3] = r3
  h[4] = r4
  0

# h = f^(2^n)
-> fe_sqn(h, f, n) (i64[] i64[] i64) i64
  fe_sq(h, f)
  i = 1
  while i < n
    fe_sq(h, h)
    i += 1
  0

# h = z^(p-2) = z^(2^255 - 21); t0..t3 are scratch
-> fe_invert(h, z, t0, t1, t2, t3) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  fe_sq(t0, z)              # 2
  fe_sqn(t1, t0, 2)         # 8
  fe_mul(t1, z, t1)         # 9
  fe_mul(t0, t0, t1)        # 11
  fe_sq(t2, t0)             # 22
  fe_mul(t1, t1, t2)        # 2^5 - 1
  fe_sqn(t2, t1, 5)
  fe_mul(t1, t2, t1)        # 2^10 - 1
  fe_sqn(t2, t1, 10)
  fe_mul(t2, t2, t1)        # 2^20 - 1
  fe_sqn(t3, t2, 20)
  fe_mul(t2, t3, t2)        # 2^40 - 1
  fe_sqn(t2, t2, 10)
  fe_mul(t1, t2, t1)        # 2^50 - 1
  fe_sqn(t2, t1, 50)
  fe_mul(t2, t2, t1)        # 2^100 - 1
  fe_sqn(t3, t2, 100)
  fe_mul(t2, t3, t2)        # 2^200 - 1
  fe_sqn(t2, t2, 50)
  fe_mul(t1, t2, t1)        # 2^250 - 1
  fe_sqn(t1, t1, 5)         # 2^255 - 2^5
  fe_mul(h, t1, t0)         # 2^255 - 21
  0

# Constant-time swap of (a, b) when bit == 1.
-> fe_cswap(a, b, bit) (i64[] i64[] i64) i64
  mask = 0 - bit
  i = 0
  while i < 5
    x = (a[i] ^ b[i]) & mask
    a[i] = a[i] ^ x
    b[i] = b[i] ^ x
    i += 1
  0

# 32 little-endian bytes -> limbs (top bit ignored, per RFC 7748)
-> fe_from_bytes(h, s) (i64[] u8[]) i64
  h[0] = 0
  h[1] = 0
  h[2] = 0
  h[3] = 0
  h[4] = 0
  j = 0
  while j < 32
    b = s[j] ## i64
    b = b & 127 if j == 31
    pos = j * 8
    limb = pos / 51
    off = pos - limb * 51
    h[limb] = h[limb] | ((b << off) & M51)
    if off > 43 && limb < 4
      h[limb + 1] = h[limb + 1] | (b >> (51 - off))
    j += 1
  0

# Fully reduce mod p and write 32 little-endian bytes.
-> fe_to_bytes(s, f) (u8[] i64[]) i64
  h0 = f[0]
  h1 = f[1]
  h2 = f[2]
  h3 = f[3]
  h4 = f[4]
  # two carry passes bring every limb below 2^51 (value < 2^255 + small)
  k = 0
  while k < 2
    h1 = h1 + (h0 >> 51)
    h0 = h0 & M51
    h2 = h2 + (h1 >> 51)
    h1 = h1 & M51
    h3 = h3 + (h2 >> 51)
    h2 = h2 & M51
    h4 = h4 + (h3 >> 51)
    h3 = h3 & M51
    h0 = h0 + (h4 >> 51) * 19
    h4 = h4 & M51
    k += 1
  # q = 1 iff h >= p
  q = (h0 + 19) >> 51
  q = (h1 + q) >> 51
  q = (h2 + q) >> 51
  q = (h3 + q) >> 51
  q = (h4 + q) >> 51
  h0 = h0 + 19 * q
  h1 = h1 + (h0 >> 51)
  h0 = h0 & M51
  h2 = h2 + (h1 >> 51)
  h1 = h1 & M51
  h3 = h3 + (h2 >> 51)
  h2 = h2 & M51
  h4 = h4 + (h3 >> 51)
  h3 = h3 & M51
  h4 = h4 & M51
  s[0] = h0 & 255
  s[1] = (h0 >> 8) & 255
  s[2] = (h0 >> 16) & 255
  s[3] = (h0 >> 24) & 255
  s[4] = (h0 >> 32) & 255
  s[5] = (h0 >> 40) & 255
  s[6] = ((h0 >> 48) | (h1 << 3)) & 255
  s[7] = (h1 >> 5) & 255
  s[8] = (h1 >> 13) & 255
  s[9] = (h1 >> 21) & 255
  s[10] = (h1 >> 29) & 255
  s[11] = (h1 >> 37) & 255
  s[12] = ((h1 >> 45) | (h2 << 6)) & 255
  s[13] = (h2 >> 2) & 255
  s[14] = (h2 >> 10) & 255
  s[15] = (h2 >> 18) & 255
  s[16] = (h2 >> 26) & 255
  s[17] = (h2 >> 34) & 255
  s[18] = (h2 >> 42) & 255
  s[19] = ((h2 >> 50) | (h3 << 1)) & 255
  s[20] = (h3 >> 7) & 255
  s[21] = (h3 >> 15) & 255
  s[22] = (h3 >> 23) & 255
  s[23] = (h3 >> 31) & 255
  s[24] = (h3 >> 39) & 255
  s[25] = ((h3 >> 47) | (h4 << 4)) & 255
  s[26] = (h4 >> 4) & 255
  s[27] = (h4 >> 12) & 255
  s[28] = (h4 >> 20) & 255
  s[29] = (h4 >> 28) & 255
  s[30] = (h4 >> 36) & 255
  s[31] = (h4 >> 44) & 255
  0

# ---------------------------------------------------------------------------
# X25519 ladder

-> x25519_ladder(x1, x2, z2, x3, z3, a, aa, b, bb, e, c, d, da, cb, kc) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] u8[]) i64
  fe_set(x2, 1)
  fe_set(z2, 0)
  fe_copy(x3, x1)
  fe_set(z3, 1)
  swap = 0
  t = 254
  while t >= 0
    kt = ((kc[t >> 3] ## i64) >> (t & 7)) & 1
    swap = swap ^ kt
    fe_cswap(x2, x3, swap)
    fe_cswap(z2, z3, swap)
    swap = kt
    fe_add(a, x2, z2)
    fe_sq(aa, a)
    fe_sub(b, x2, z2)
    fe_sq(bb, b)
    fe_sub(e, aa, bb)
    fe_add(c, x3, z3)
    fe_sub(d, x3, z3)
    fe_mul(da, d, a)
    fe_mul(cb, c, b)
    fe_add(x3, da, cb)
    fe_sq(x3, x3)
    fe_sub(z3, da, cb)
    fe_sq(z3, z3)
    fe_mul(z3, z3, x1)
    fe_mul(x2, aa, bb)
    fe_mul_small(z2, e, 121665)
    fe_add(z2, z2, aa)
    fe_mul(z2, z2, e)
    t -= 1
  fe_cswap(x2, x3, swap)
  fe_cswap(z2, z3, swap)
  0

-> x25519_into(out, k, u) (u8[] u8[] u8[]) i64
  kc = u8[32]
  i = 0
  while i < 32
    kc[i] = k[i]
    i += 1
  kc[0] = kc[0] & 248
  kc[31] = (kc[31] & 127) | 64
  x1 = i64[5]
  x2 = i64[5]
  z2 = i64[5]
  x3 = i64[5]
  z3 = i64[5]
  a = i64[5]
  aa = i64[5]
  b = i64[5]
  bb = i64[5]
  e = i64[5]
  c = i64[5]
  d = i64[5]
  da = i64[5]
  cb = i64[5]
  fe_from_bytes(x1, u)
  x25519_ladder(x1, x2, z2, x3, z3, a, aa, b, bb, e, c, d, da, cb, kc)
  fe_invert(a, z2, b, c, d, e)
  fe_mul(x2, x2, a)
  fe_to_bytes(out, x2)
  0

-> x25519_fast(k32, u32)
  out = ByteArray.new(32)
  x25519_into(out, k32, u32)
  out

-> x25519_base_fast(k32)
  nine = ByteArray.new(32)
  nine[0] = 9
  out = ByteArray.new(32)
  x25519_into(out, k32, nine)
  out

-> x25519_is_zero(b)
  acc = 0
  i = 0
  while i < b.size
    acc = acc | b[i]
    i += 1
  acc == 0
