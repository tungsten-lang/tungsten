# blade/pkfast — fixed-width public-key arithmetic for the TLS handshake, on raw
# machine words (no BigInt anywhere on these paths).
#
# Tungsten has no GC; every BigInt intermediate of the old Integer-based ECDSA and
# RSA code (blade/x509) stayed allocated, ~100 MB per handshake. Everything here
# works in one preallocated u64[] workspace per operation and allocates nothing
# inside its loops.
#
# Representation: a multi-precision number is n little-endian 64-bit limbs living
# at an offset of a shared u64[] workspace `w`. Modular arithmetic is Montgomery
# (R = 2^(64n)): CIOS multiplication with 64x64->128 products from `mulhi` (one
# UMULH on arm64) and carries from `addcarry`. A modulus context is an i64[8]:
#   c[0] n        limbs
#   c[1] mo       offset of the modulus m (odd)
#   c[2] to       offset of n+2 limbs of multiplication scratch
#   c[3] io       offset of the one-limb -m^-1 mod 2^64
#   c[4] oneo     offset of R mod m          (Montgomery 1)
#   c[5] r2o      offset of R^2 mod m        (to-Montgomery factor)
#   c[6] xo       offset of n limbs of extra scratch (inversion exponent)
#
# Public API (byte strings are big-endian ByteArrays):
#   pk_ecdsa_verify(bits, hash, r, s, qx, qy) -> bool    bits 256 (P-256) or 384 (P-384)
#   pk_ec_mul_x(bits, k, px, py)              -> x(k*P) bytes, or nil (ECDH helper; variable time)
#   pk_rsa_public(n, e, sig)                  -> sig^e mod n as len(n) bytes, or nil if sig >= n
#
# Final subtractions in mm_mul/mm_add/mm_sub are branch-free (mask selects). The EC
# scalar multiplication is double-and-add (variable time): it is used for signature
# verification, where every input is public. TLS key exchange is X25519
# (blade/curve25519, constant-time ladder).

# ---- limb helpers ----

-> mp_zero(w, r, n) (u64[] i64 i64) i64
  i = 0
  while i < n
    w[r + i] = 0
    i += 1
  0

-> mp_copy(w, r, a, n) (u64[] i64 i64 i64) i64
  i = 0
  while i < n
    w[r + i] = w[a + i]
    i += 1
  0

-> mp_is_zero(w, a, n) (u64[] i64 i64) i64
  acc = 0 ## u64
  i = 0
  while i < n
    acc = acc | w[a + i]
    i += 1
  acc == 0 ? 1 : 0

# -1, 0, 1 for a <, ==, > b
-> mp_cmp(w, a, b, n) (u64[] i64 i64 i64) i64
  i = n - 1
  while i >= 0
    x = w[a + i]
    y = w[b + i]
    return 1 if x > y
    return 0 - 1 if x < y
    i -= 1
  0

# Bit length of the n-limb number at a.
-> mp_bitlen(w, a, n) (u64[] i64 i64) i64
  i = n - 1
  while i >= 0
    x = w[a + i]
    if x != 0
      b = 0
      while x != 0
        x = x >> 1
        b += 1
      return i * 64 + b
    i -= 1
  0

# Bit length of a non-negative i64.
-> mp_bitlen1(v) (i64) i64
  b = 0
  while v != 0
    v = v >> 1
    b += 1
  b

-> mp_bit(w, a, i) (u64[] i64 i64) i64
  ((w[a + (i >> 6)] >> (i & 63)) & 1) ## i64

# Load len big-endian bytes b[off..] into n limbs at r (zero-extended; extra high bytes dropped).
-> mp_from_be(w, r, n, b, off, len) (u64[] i64 i64 u8[] i64 i64) i64
  mp_zero(w, r, n)
  k = 0
  while k < len
    limb = k >> 3
    if limb < n
      v = b[off + len - 1 - k] ## u64
      w[r + limb] = w[r + limb] | (v << ((k & 7) * 8))
    k += 1
  0

# Store the n limbs at a as len big-endian bytes into out[off..].
-> mp_to_be(out, off, len, w, a, n) (u8[] i64 i64 u64[] i64 i64) i64
  k = 0
  while k < len
    limb = k >> 3
    v = 0 ## u64
    v = (w[a + limb] >> ((k & 7) * 8)) & 255 if limb < n
    out[off + len - 1 - k] = v
    k += 1
  0

# -m0^-1 mod 2^64 (m0 odd), Newton iteration.
-> mp_ninv(m0) (u64) u64
  x = m0 ## u64
  i = 0
  while i < 6
    x = x * (2 - m0 * x) ## u64
    i += 1
  0 - x ## u64

# ---- Montgomery arithmetic mod m (n limbs at mo) ----

# w[r] = w[a] * w[b] / R mod m. Inputs: a < 2^(64n), b < m (or both < m). r may alias a or b.
-> mm_mul(w, r, a, b, mo, to, n, ninv) (u64[] i64 i64 i64 i64 i64 i64 u64) i64
  i = 0
  while i < n + 2
    w[to + i] = 0
    i += 1
  i = 0
  while i < n
    ai = w[a + i]
    c = 0 ## u64
    j = 0
    while j < n
      bj = w[b + j]
      lo = ai * bj ## u64
      hi = mulhi(ai, bj) ## u64
      tj = w[to + j]
      s = tj + lo ## u64
      hi = hi + addcarry(tj, lo) ## u64
      s2 = s + c ## u64
      hi = hi + addcarry(s, c) ## u64
      w[to + j] = s2
      c = hi
      j += 1
    # (every wrapping sum goes through a `## u64` local: an unhinted u64 + u64 that
    # overflows promotes to an Integer, and storing that into u64[] writes garbage)
    tn = w[to + n]
    sm = tn + c ## u64
    cm = w[to + n + 1] + addcarry(tn, c) ## u64
    w[to + n] = sm
    w[to + n + 1] = cm
    # reduce: add q*m so the low limb vanishes, then shift down one limb
    # (distinct local names per phase: reusing lo/hi/c here miscompiled on blade-ui)
    t0 = w[to]
    q = t0 * ninv ## u64
    m0 = w[mo]
    qlo = q * m0 ## u64
    rc = mulhi(q, m0) + addcarry(t0, qlo) ## u64
    k = 1
    while k < n
      mk = w[mo + k]
      plo = q * mk ## u64
      phi = mulhi(q, mk) ## u64
      tk = w[to + k]
      ps = tk + plo ## u64
      phi = phi + addcarry(tk, plo) ## u64
      ps2 = ps + rc ## u64
      phi = phi + addcarry(ps, rc) ## u64
      w[to + k - 1] = ps2
      rc = phi
      k += 1
    tm = w[to + n]
    sn = tm + rc ## u64
    cn = w[to + n + 1] + addcarry(tm, rc) ## u64
    w[to + n - 1] = sn
    w[to + n] = cn
    w[to + n + 1] = 0
    i += 1
  # t < 2m: r = t - m unless that borrows (and t has no carry limb)
  borrow = 0 ## u64
  j = 0
  while j < n
    tj = w[to + j]
    mj = w[mo + j]
    d = tj - mj ## u64
    b1 = subborrow(tj, mj) ## u64
    d2 = d - borrow ## u64
    b2 = subborrow(d, borrow) ## u64
    w[r + j] = d2
    borrow = b1 | b2
    j += 1
  # keep the subtraction when t[n] == 1 or no borrow
  keep = w[to + n] | (borrow ^ 1) ## u64
  mask = 0 - (keep & 1) ## u64
  j = 0
  while j < n
    tj = w[to + j]
    w[r + j] = tj ^ ((tj ^ w[r + j]) & mask)
    j += 1
  0

# w[r] = w[a] + w[b] mod m (a, b < m).
-> mm_add(w, r, a, b, mo, n) (u64[] i64 i64 i64 i64 i64) i64
  c = 0 ## u64
  j = 0
  while j < n
    x = w[a + j]
    y = w[b + j]
    s = x + y ## u64
    c1 = addcarry(x, y) ## u64
    s2 = s + c ## u64
    c2 = addcarry(s, c) ## u64
    w[r + j] = s2
    c = c1 | c2
    j += 1
  # borrow of (sum - m)
  borrow = 0 ## u64
  j = 0
  while j < n
    x = w[r + j]
    y = w[mo + j]
    d = x - y ## u64
    b1 = subborrow(x, y) ## u64
    b2 = subborrow(d, borrow) ## u64
    borrow = b1 | b2
    j += 1
  keep = c | (borrow ^ 1) ## u64
  mask = 0 - (keep & 1) ## u64
  borrow = 0 ## u64
  j = 0
  while j < n
    x = w[r + j]
    y = w[mo + j] & mask
    d = x - y ## u64
    b1 = subborrow(x, y) ## u64
    d2 = d - borrow ## u64
    b2 = subborrow(d, borrow) ## u64
    w[r + j] = d2
    borrow = b1 | b2
    j += 1
  0

# w[r] = w[a] - w[b] mod m (a, b < m).
-> mm_sub(w, r, a, b, mo, n) (u64[] i64 i64 i64 i64 i64) i64
  borrow = 0 ## u64
  j = 0
  while j < n
    x = w[a + j]
    y = w[b + j]
    d = x - y ## u64
    b1 = subborrow(x, y) ## u64
    d2 = d - borrow ## u64
    b2 = subborrow(d, borrow) ## u64
    w[r + j] = d2
    borrow = b1 | b2
    j += 1
  mask = 0 - borrow ## u64
  c = 0 ## u64
  j = 0
  while j < n
    x = w[r + j]
    y = w[mo + j] & mask
    s = x + y ## u64
    c1 = addcarry(x, y) ## u64
    s2 = s + c ## u64
    c2 = addcarry(s, c) ## u64
    w[r + j] = s2
    c = c1 | c2
    j += 1
  0

# Context-based wrappers.
-> fm(w, c, r, a, b) (u64[] i64[] i64 i64 i64) i64
  mm_mul(w, r, a, b, c[1], c[2], c[0], w[c[3]])

-> fa(w, c, r, a, b) (u64[] i64[] i64 i64 i64) i64
  mm_add(w, r, a, b, c[1], c[0])

-> fs(w, c, r, a, b) (u64[] i64[] i64 i64 i64) i64
  mm_sub(w, r, a, b, c[1], c[0])

# r = base^e (Montgomery domain) where e is the ebits-bit number at eo. r must not alias base or e.
-> fpow(w, c, r, base, eo, ebits) (u64[] i64[] i64 i64 i64 i64) i64
  mp_copy(w, r, c[4], c[0])
  i = ebits - 1
  while i >= 0
    fm(w, c, r, r, r)
    fm(w, c, r, r, base) if mp_bit(w, eo, i) == 1
    i -= 1
  0

# Fill in -m^-1, R mod m and R^2 mod m for the modulus already loaded at c[1].
# Uses c[6] as scratch.
-> mm_setup(w, c) (u64[] i64[]) i64
  n = c[0]
  mo = c[1]
  ninv = mp_ninv(w[mo]) ## u64
  w[c[3]] = ninv
  bits = mp_bitlen(w, mo, n)
  one = c[4]
  # 2^(bits-1) < m, then double up to 2^(64n) mod m = R mod m
  mp_zero(w, one, n)
  top = bits - 1
  bit = 1 ## u64
  topbit = bit << (top & 63) ## u64
  w[one + (top >> 6)] = topbit
  k = 64 * n - top
  while k > 0
    mm_add(w, one, one, one, mo, n)
    k -= 1
  # 2R mod m = Montgomery(2); Montgomery(2)^(64n) = Montgomery(2^(64n)) = R^2 mod m
  x = c[6]
  mm_add(w, x, one, one, mo, n)
  r2 = c[5]
  t = c[2]
  mp_copy(w, r2, one, n)
  ev = 64 * n
  i = mp_bitlen1(ev) - 1
  while i >= 0
    mm_mul(w, r2, r2, r2, mo, t, n, ninv)
    mm_mul(w, r2, r2, x, mo, t, n, ninv) if ((ev >> i) & 1) == 1
    i -= 1
  0

# r = Montgomery form of the plain number at a (a < m).
-> to_mont(w, c, r, a) (u64[] i64[] i64 i64) i64
  fm(w, c, r, a, c[5])

# r = plain number from Montgomery form at a. Uses c[6] as scratch.
-> from_mont(w, c, r, a) (u64[] i64[] i64 i64) i64
  x = c[6]
  mp_zero(w, x, c[0])
  w[x] = 1
  fm(w, c, r, a, x)

# r = a^-1 (Montgomery domain) for prime m, by Fermat. Uses c[6]; r must not alias a.
-> finv(w, c, r, a) (u64[] i64[] i64 i64) i64
  n = c[0]
  e = c[6]
  mp_copy(w, e, c[1], n)
  # m - 2 (m odd and > 2: no borrow past limb 0 unless m0 < 2)
  m0 = w[e]
  e0 = m0 - 2 ## u64
  w[e] = e0
  if m0 < 2
    k = 1
    while k < n
      v = w[e + k]
      v1 = v - 1 ## u64
      w[e + k] = v1
      break if v != 0
      k += 1
  fpow(w, c, r, a, e, mp_bitlen(w, e, n))

# ---- short Weierstrass curves with a = -3, Jacobian coordinates ----
#
# Workspace layout for one curve operation (S = slot size n limbs):
#   field ctx cp: m=p, t, ninv, one, r2, x       mod-n ctx cn: m=n, t, ninv, one, r2, x
#   slots: B (curve b, Montgomery), points and temporaries (see ec_layout)
#
# A point is three slot offsets (X, Y, Z), Montgomery coordinates; Z == 0 is infinity.

# out = 2*in (a = -3, dbl-2001-b). in and out may be the same point. T = temp base (6 slots).
-> ec_dbl(w, c, ox, oy, oz, ix, iy, iz, tb) (u64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  n = c[0]
  if mp_is_zero(w, iz, n) == 1 || mp_is_zero(w, iy, n) == 1
    mp_copy(w, ox, ix, n)
    mp_copy(w, oy, iy, n)
    mp_zero(w, oz, n)
    return 0
  delta = tb
  gamma = tb + n
  beta = tb + 2 * n
  alpha = tb + 3 * n
  t1 = tb + 4 * n
  t2 = tb + 5 * n
  fm(w, c, delta, iz, iz)
  fm(w, c, gamma, iy, iy)
  fm(w, c, beta, ix, gamma)
  fs(w, c, t1, ix, delta)
  fa(w, c, t2, ix, delta)
  fm(w, c, alpha, t1, t2)
  fa(w, c, t1, alpha, alpha)
  fa(w, c, alpha, t1, alpha)
  # Z3 = (Y + Z)^2 - gamma - delta
  fa(w, c, t1, iy, iz)
  fm(w, c, t1, t1, t1)
  fs(w, c, t1, t1, gamma)
  fs(w, c, oz, t1, delta)
  # X3 = alpha^2 - 8 beta
  fa(w, c, beta, beta, beta)
  fa(w, c, beta, beta, beta)
  fa(w, c, t2, beta, beta)
  fm(w, c, t1, alpha, alpha)
  fs(w, c, ox, t1, t2)
  # Y3 = alpha (4 beta - X3) - 8 gamma^2
  fs(w, c, t1, beta, ox)
  fm(w, c, t1, alpha, t1)
  fm(w, c, gamma, gamma, gamma)
  fa(w, c, gamma, gamma, gamma)
  fa(w, c, gamma, gamma, gamma)
  fa(w, c, gamma, gamma, gamma)
  fs(w, c, oy, t1, gamma)
  0

# out = A + B (general Jacobian addition). out may alias A. tb = temp base (12 slots).
-> ec_add(w, c, ox, oy, oz, ax, ay, az, bx, by, bz, tb) (u64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  n = c[0]
  if mp_is_zero(w, bz, n) == 1
    return 0 if ox == ax
    mp_copy(w, ox, ax, n)
    mp_copy(w, oy, ay, n)
    mp_copy(w, oz, az, n)
    return 0
  if mp_is_zero(w, az, n) == 1
    mp_copy(w, ox, bx, n)
    mp_copy(w, oy, by, n)
    mp_copy(w, oz, bz, n)
    return 0
  z1z1 = tb
  z2z2 = tb + n
  u1 = tb + 2 * n
  u2 = tb + 3 * n
  s1 = tb + 4 * n
  s2 = tb + 5 * n
  h = tb + 6 * n
  rr = tb + 7 * n
  hh = tb + 8 * n
  hhh = tb + 9 * n
  v = tb + 10 * n
  t1 = tb + 11 * n
  fm(w, c, z1z1, az, az)
  fm(w, c, z2z2, bz, bz)
  fm(w, c, u1, ax, z2z2)
  fm(w, c, u2, bx, z1z1)
  fm(w, c, s1, ay, bz)
  fm(w, c, s1, s1, z2z2)
  fm(w, c, s2, by, az)
  fm(w, c, s2, s2, z1z1)
  fs(w, c, h, u2, u1)
  fs(w, c, rr, s2, s1)
  if mp_is_zero(w, h, n) == 1
    if mp_is_zero(w, rr, n) == 1
      # A == B: double (into temps beyond ours, then copy)
      ec_dbl(w, c, ox, oy, oz, ax, ay, az, tb)
      return 0
    mp_copy(w, ox, c[4], n)
    mp_copy(w, oy, c[4], n)
    mp_zero(w, oz, n)
    return 0
  fm(w, c, hh, h, h)
  fm(w, c, hhh, h, hh)
  fm(w, c, v, u1, hh)
  # Z3 = Z1 Z2 H (before ox/oy overwrite az when aliased)
  fm(w, c, t1, az, bz)
  fm(w, c, oz, t1, h)
  # X3 = r^2 - HHH - 2V
  fm(w, c, t1, rr, rr)
  fs(w, c, t1, t1, hhh)
  fs(w, c, t1, t1, v)
  fs(w, c, ox, t1, v)
  # Y3 = r (V - X3) - S1 HHH
  fs(w, c, t1, v, ox)
  fm(w, c, t1, rr, t1)
  fm(w, c, s1, s1, hhh)
  fs(w, c, oy, t1, s1)
  0

# Curve constants (hex, big-endian): p, b, Gx, Gy, n.
-> pk_curve_hex(bits)
  if bits == 256
    return ["ffffffff00000001000000000000000000000000ffffffffffffffffffffffff",
      "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b",
      "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296",
      "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
      "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"]
  if bits == 384
    return ["fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff",
      "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef",
      "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7",
      "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f",
      "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"]
  nil

-> pk_hexbytes(s)
  b = ByteArray.new(s.size / 2)
  i = 0
  while i < b.size
    b[i] = s.slice(2 * i, 2).to_i(16)
    i += 1
  b

# Slot map (in units of n limbs, after the two contexts):
EC_SLOTS = 64

# The workspace for one curve: two contexts + EC_SLOTS slots. Returns [w, cp, cn].
-> ec_workspace(bits)
  hx = pk_curve_hex(bits)
  return nil if hx == nil
  n = bits / 64
  w = u64[(EC_SLOTS + 16) * n + 16]
  cp = i64[8]
  cn = i64[8]
  # field context: slots 0..4 (m, one, r2, x) + t (n+2) + ninv
  base = 0
  cp[0] = n
  cp[1] = base
  cp[4] = base + n
  cp[5] = base + 2 * n
  cp[6] = base + 3 * n
  cp[2] = base + 4 * n
  cp[3] = base + 5 * n + 2
  base = 5 * n + 3
  cn[0] = n
  cn[1] = base
  cn[4] = base + n
  cn[5] = base + 2 * n
  cn[6] = base + 3 * n
  cn[2] = base + 4 * n
  cn[3] = base + 5 * n + 2
  pb = pk_hexbytes(hx[0])
  mp_from_be(w, cp[1], n, pb, 0, pb.size)
  mm_setup(w, cp)
  nb = pk_hexbytes(hx[4])
  mp_from_be(w, cn[1], n, nb, 0, nb.size)
  mm_setup(w, cn)
  [w, cp, cn, hx]

# Offset of general slot k (after the contexts).
-> ec_slot(n, k) (i64 i64) i64
  (10 * n + 6) + k * n

# Load big-endian bytes as a field element < m (plain) into slot r; 1 if in range.
-> ec_load(w, c, r, b, off, len) (u64[] i64[] i64 u8[] i64 i64) i64
  n = c[0]
  mp_from_be(w, r, n, b, off, len)
  return 0 if len > n * 8 && b[off] != 0
  mp_cmp(w, r, c[1], n) < 0 ? 1 : 0

# Is the plain point (slots x, y) on the curve? b_m = Montgomery b. Uses 3 temp slots at tb.
-> ec_on_curve(w, c, x, y, bm, tb) (u64[] i64[] i64 i64 i64 i64) i64
  n = c[0]
  xm = tb
  ym = tb + n
  t1 = tb + 2 * n
  t2 = tb + 3 * n
  to_mont(w, c, xm, x)
  to_mont(w, c, ym, y)
  fm(w, c, t1, xm, xm)
  fm(w, c, t1, t1, xm)
  fs(w, c, t1, t1, xm)
  fs(w, c, t1, t1, xm)
  fs(w, c, t1, t1, xm)
  fa(w, c, t1, t1, bm)
  fm(w, c, t2, ym, ym)
  mp_cmp(w, t1, t2, n) == 0 ? 1 : 0

# Pure-typed ECDSA verify core. Slots (k): 0 r, 1 s, 2 e, 3 qx, 4 qy, 5 b, 6 gx, 7 gy,
# then the rest is computed here. Returns 1 when the signature verifies.
-> ec_verify_core(w, cp, cn) (u64[] i64[] i64[]) i64
  n = cp[0]
  r = ec_slot(n, 0)
  s = ec_slot(n, 1)
  e = ec_slot(n, 2)
  qx = ec_slot(n, 3)
  qy = ec_slot(n, 4)
  bm = ec_slot(n, 5)
  gx = ec_slot(n, 6)
  gy = ec_slot(n, 7)
  tb = ec_slot(n, 40)
  # 1 <= r, s < n
  return 0 if mp_is_zero(w, r, n) == 1 || mp_is_zero(w, s, n) == 1
  return 0 if mp_cmp(w, r, cn[1], n) >= 0 || mp_cmp(w, s, cn[1], n) >= 0
  to_mont(w, cp, bm, bm)
  return 0 if ec_on_curve(w, cp, qx, qy, bm, tb) == 0
  # e mod n (e < 2^bits < 2n)
  zero = ec_slot(n, 8)
  mp_zero(w, zero, n)
  mm_add(w, e, e, zero, cn[1], n)
  # w = s^-1, u1 = e w, u2 = r w (mod n)
  sm = ec_slot(n, 9)
  si = ec_slot(n, 10)
  u1 = ec_slot(n, 11)
  u2 = ec_slot(n, 12)
  to_mont(w, cn, sm, s)
  finv(w, cn, si, sm)
  to_mont(w, cn, u1, e)
  fm(w, cn, u1, u1, si)
  from_mont(w, cn, u1, u1)
  to_mont(w, cn, u2, r)
  fm(w, cn, u2, u2, si)
  from_mont(w, cn, u2, u2)
  # points in Montgomery Jacobian: G (13..15), Q (16..18), G+Q (19..21), acc (22..24)
  g0 = ec_slot(n, 13)
  g1 = ec_slot(n, 14)
  g2 = ec_slot(n, 15)
  q0 = ec_slot(n, 16)
  q1 = ec_slot(n, 17)
  q2 = ec_slot(n, 18)
  h0 = ec_slot(n, 19)
  h1 = ec_slot(n, 20)
  h2 = ec_slot(n, 21)
  a0 = ec_slot(n, 22)
  a1 = ec_slot(n, 23)
  a2 = ec_slot(n, 24)
  to_mont(w, cp, g0, gx)
  to_mont(w, cp, g1, gy)
  mp_copy(w, g2, cp[4], n)
  to_mont(w, cp, q0, qx)
  to_mont(w, cp, q1, qy)
  mp_copy(w, q2, cp[4], n)
  ec_add(w, cp, h0, h1, h2, g0, g1, g2, q0, q1, q2, tb)
  mp_copy(w, a0, cp[4], n)
  mp_copy(w, a1, cp[4], n)
  mp_zero(w, a2, n)
  i = 64 * n - 1
  while i >= 0
    ec_dbl(w, cp, a0, a1, a2, a0, a1, a2, tb)
    b1 = mp_bit(w, u1, i)
    b2 = mp_bit(w, u2, i)
    if b1 == 1 && b2 == 1
      ec_add(w, cp, a0, a1, a2, a0, a1, a2, h0, h1, h2, tb)
    elsif b1 == 1
      ec_add(w, cp, a0, a1, a2, a0, a1, a2, g0, g1, g2, tb)
    elsif b2 == 1
      ec_add(w, cp, a0, a1, a2, a0, a1, a2, q0, q1, q2, tb)
    i -= 1
  return 0 if mp_is_zero(w, a2, n) == 1
  # affine x = X / Z^2, then x mod n == r
  zi = ec_slot(n, 25)
  x = ec_slot(n, 26)
  finv(w, cp, zi, a2)
  fm(w, cp, x, zi, zi)
  fm(w, cp, x, x, a0)
  from_mont(w, cp, x, x)
  # x < p < 2n
  if mp_cmp(w, x, cn[1], n) >= 0
    mp_zero(w, zero, n)
    mm_sub(w, x, x, cn[1], zero, n)
    # mm_sub(x, n) with modulus 0 adds nothing on borrow; x >= n so no borrow
  mp_cmp(w, x, r, n) == 0 ? 1 : 0

# ECDSA verify: hash bytes, r/s/qx/qy big-endian bytes. bits = 256 or 384.
-> pk_ecdsa_verify(bits, hash, r, s, qx, qy)
  ws = ec_workspace(bits)
  return false if ws == nil
  w = ws[0]
  cp = ws[1]
  cn = ws[2]
  hx = ws[3]
  n = bits / 64
  nb = bits / 8
  return false if r.size > nb + 1 || s.size > nb + 1 || qx.size > nb + 1 || qy.size > nb + 1
  mp_from_be(w, ec_slot(n, 0), n, r, 0, r.size)
  return false if r.size == nb + 1 && r[0] != 0
  mp_from_be(w, ec_slot(n, 1), n, s, 0, s.size)
  return false if s.size == nb + 1 && s[0] != 0
  # e = leftmost bits of the hash
  hl = hash.size
  hl = nb if hl > nb
  mp_from_be(w, ec_slot(n, 2), n, hash, 0, hl)
  return false if ec_load(w, cp, ec_slot(n, 3), qx, 0, qx.size) == 0
  return false if ec_load(w, cp, ec_slot(n, 4), qy, 0, qy.size) == 0
  b = pk_hexbytes(hx[1])
  mp_from_be(w, ec_slot(n, 5), n, b, 0, b.size)
  b = pk_hexbytes(hx[2])
  mp_from_be(w, ec_slot(n, 6), n, b, 0, b.size)
  b = pk_hexbytes(hx[3])
  mp_from_be(w, ec_slot(n, 7), n, b, 0, b.size)
  ec_verify_core(w, cp, cn) == 1

# k*P core: k plain at slot 0, P plain at 1, 2. Result affine x (plain) in slot 3; 0 if infinity.
-> ec_mul_core(w, cp) (u64[] i64[]) i64
  n = cp[0]
  k = ec_slot(n, 0)
  tb = ec_slot(n, 40)
  p0 = ec_slot(n, 13)
  p1 = ec_slot(n, 14)
  p2 = ec_slot(n, 15)
  a0 = ec_slot(n, 22)
  a1 = ec_slot(n, 23)
  a2 = ec_slot(n, 24)
  to_mont(w, cp, p0, ec_slot(n, 1))
  to_mont(w, cp, p1, ec_slot(n, 2))
  mp_copy(w, p2, cp[4], n)
  mp_copy(w, a0, cp[4], n)
  mp_copy(w, a1, cp[4], n)
  mp_zero(w, a2, n)
  i = 64 * n - 1
  while i >= 0
    ec_dbl(w, cp, a0, a1, a2, a0, a1, a2, tb)
    ec_add(w, cp, a0, a1, a2, a0, a1, a2, p0, p1, p2, tb) if mp_bit(w, k, i) == 1
    i -= 1
  return 0 if mp_is_zero(w, a2, n) == 1
  zi = ec_slot(n, 25)
  x = ec_slot(n, 3)
  finv(w, cp, zi, a2)
  fm(w, cp, x, zi, zi)
  fm(w, cp, x, x, a0)
  from_mont(w, cp, x, x)
  1

# x-coordinate of k*P (ECDH shared secret), nb bytes; nil for a bad point or infinity.
-> pk_ec_mul_x(bits, k, px, py)
  ws = ec_workspace(bits)
  return nil if ws == nil
  w = ws[0]
  cp = ws[1]
  hx = ws[3]
  n = bits / 64
  nb = bits / 8
  return nil if k.size > nb
  mp_from_be(w, ec_slot(n, 0), n, k, 0, k.size)
  return nil if ec_load(w, cp, ec_slot(n, 1), px, 0, px.size) == 0
  return nil if ec_load(w, cp, ec_slot(n, 2), py, 0, py.size) == 0
  b = pk_hexbytes(hx[1])
  mp_from_be(w, ec_slot(n, 5), n, b, 0, b.size)
  to_mont(w, cp, ec_slot(n, 5), ec_slot(n, 5))
  return nil if ec_on_curve(w, cp, ec_slot(n, 1), ec_slot(n, 2), ec_slot(n, 5), ec_slot(n, 40)) == 0
  return nil if ec_mul_core(w, cp) == 0
  out = ByteArray.new(nb)
  mp_to_be(out, 0, nb, w, ec_slot(n, 3), n)
  out

# ---- RSA public operation ----

# Core: modulus at c[1] (setup done), s plain at so, e at eo (ebits bits). Result plain at ro.
-> rsa_core(w, c, ro, so, eo, ebits, xo) (u64[] i64[] i64 i64 i64 i64 i64) i64
  to_mont(w, c, xo, so)
  fpow(w, c, ro, xo, eo, ebits)
  from_mont(w, c, ro, ro)
  0

# sig^e mod n as a k-byte big-endian string (k = byte length of n); nil when sig >= n.
-> pk_rsa_public(nb, eb, sig)
  # strip leading zero bytes of the modulus
  off = 0
  while off < nb.size && nb[off] == 0
    off += 1
  k = nb.size - off
  return nil if k == 0 || k > 1024 || eb.size > k || eb.size == 0
  return nil if (nb[nb.size - 1] & 1) == 0
  n = (k + 7) / 8
  w = u64[9 * n + 16]
  c = i64[8]
  c[0] = n
  c[1] = 0
  c[4] = n
  c[5] = 2 * n
  c[6] = 3 * n
  c[2] = 4 * n
  c[3] = 5 * n + 2
  so = 5 * n + 3
  eo = 6 * n + 3
  ro = 7 * n + 3
  xo = 8 * n + 3
  mp_from_be(w, 0, n, nb, off, k)
  # signature: at most k significant bytes
  soff = 0
  while soff < sig.size - k && sig[soff] == 0
    soff += 1
  return nil if sig.size - soff > k
  mp_from_be(w, so, n, sig, soff, sig.size - soff)
  return nil if mp_cmp(w, so, 0, n) >= 0
  mp_from_be(w, eo, n, eb, 0, eb.size)
  ebits = mp_bitlen(w, eo, n)
  return nil if ebits == 0
  mm_setup(w, c)
  rsa_core(w, c, ro, so, eo, ebits, xo)
  out = ByteArray.new(k)
  mp_to_be(out, 0, k, w, ro, n)
  out
