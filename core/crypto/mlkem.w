# blade/mlkem — ML-KEM-768 (FIPS 203, final), the post-quantum half of the TLS 1.3 hybrid key
# exchange group X25519MLKEM768 (codepoint 0x11EC, draft-ietf-tls-ecdhe-mlkem). The client sends
# the 1184-byte encapsulation key in its key_share, the server answers with a 1088-byte
# ciphertext, and the client decapsulates it to a 32-byte shared secret.
#
# API (all byte strings are ByteArray):
#   mlkem768_keygen()                     -> [ek (1184), dk (2400)]      fresh randomness
#   mlkem768_keygen_derand(d, z)          -> [ek, dk]                    d, z: 32 bytes each (Alg 16)
#   mlkem768_encaps(ek)                   -> [shared_secret (32), ct (1088)]   raises on a bad ek
#   mlkem768_encaps_derand(ek, m)         -> [shared_secret, ct]         m: 32 bytes (Alg 17)
#   mlkem768_decaps(dk, ct)               -> shared_secret (32)          implicit rejection (Alg 18)
#   mlkem768_ek_valid(ek)                 -> bool   length + modulus check (FIPS 203 §7.2)
#   mlkem768_dk_valid(dk)                 -> bool   length + hash check (FIPS 203 §7.3)
#
# Parameters (ML-KEM-768): n = 256, q = 3329, k = 3, eta1 = eta2 = 2, du = 10, dv = 4.
#
# Implementation: polynomials are 256 coefficients in typed i64[] buffers (a vector of k
# polynomials is one flat i64[256 * k], the matrix A one i64[256 * k * k]); coefficients are
# kept canonical in [0, q) and reduced with a Barrett reduction valid for 0 <= x < 2^32, so the
# matrix-vector products accumulate k base-case products unreduced and reduce once. The NTT
# follows FIPS 203 Algorithms 9-12 directly (zeta = 17, bit-reversed powers computed per call).
# Secret-dependent paths are branch-free: conditional subtraction by masks, constant-time
# ciphertext comparison and selection in decapsulation.
#
# SHA3-256 (H), SHA3-512 (G), SHAKE128 (XOF) and SHAKE256 (PRF, J) come from core Crypto.
# Core has only one-shot SHAKE (no incremental absorb/squeeze), so SampleNTT asks for three
# SHAKE128 blocks (504 bytes, enough for 256 coefficients with probability ~1 - 2^-38) and, if
# the rejection sampler runs dry, asks again for a longer output and resumes (the XOF is a
# prefix-stable stream, so the result is identical to an incremental squeeze).

# ---- arithmetic mod q ----

# Barrett: x mod q for 0 <= x < 2^32 (floor(2^32 / q) = 1290167).
-> mlk_red(x) (i64) i64
  r = x - ((x * 1290167) >> 32) * 3329
  r = r - 3329
  r + ((r >> 63) & 3329)

# x in [0, 2q) -> [0, q)
-> mlk_csub(x) (i64) i64
  r = x - 3329
  r + ((r >> 63) & 3329)

-> mlk_bitrev7(i) (i64) i64
  r = 0
  b = 0
  while b < 7
    r = r | (((i >> b) & 1) << (6 - b))
    b += 1
  r

# z[0..127] = 17^BitRev7(i) (NTT zetas); z[128..255] = 17^(2 BitRev7(i) + 1) (base-case gammas).
-> mlk_tables(z) (i64[]) i64
  pw = i64[256]
  p = 1
  i = 0
  while i < 256
    pw[i] = p
    p = (p * 17) % 3329
    i += 1
  i = 0
  while i < 128
    br = mlk_bitrev7(i)
    z[i] = pw[br]
    z[128 + i] = pw[2 * br + 1]
    i += 1
  0

# ---- NTT (Algorithms 9, 10) ----

-> mlk_ntt(f, o, z) (i64[] i64 i64[]) i64
  k = 1
  len = 128
  while len >= 2
    start = 0
    while start < 256
      zeta = z[k]
      k += 1
      j = o + start
      e = j + len
      while j < e
        t = f[j + len] * zeta
        t = t - ((t * 1290167) >> 32) * 3329 - 3329
        t = t + ((t >> 63) & 3329)
        a = f[j]
        u = a - t
        f[j + len] = u + ((u >> 63) & 3329)
        s = a + t - 3329
        f[j] = s + ((s >> 63) & 3329)
        j += 1
      start += 2 * len
    len = len >> 1
  0

-> mlk_invntt(f, o, z) (i64[] i64 i64[]) i64
  k = 127
  len = 2
  while len <= 128
    start = 0
    while start < 256
      zeta = z[k]
      k -= 1
      j = o + start
      e = j + len
      while j < e
        t = f[j]
        b = f[j + len]
        s = t + b - 3329
        f[j] = s + ((s >> 63) & 3329)
        d = (b - t + 3329) * zeta
        d = d - ((d * 1290167) >> 32) * 3329 - 3329
        f[j + len] = d + ((d >> 63) & 3329)
        j += 1
      start += 2 * len
    len = len << 1
  i = o
  e2 = o + 256
  while i < e2
    x = f[i] * 3303
    x = x - ((x * 1290167) >> 32) * 3329 - 3329
    f[i] = x + ((x >> 63) & 3329)
    i += 1
  0

# acc[ao..] += a[ao2..] (x) b[bo..] in the NTT domain (Algorithms 11, 12), unreduced.
# Inputs canonical: each call adds < 2 q^2 per coefficient, so up to 3 calls stay < 2^32.
-> mlk_basemul_acc(acc, ao, a, aoff, b, boff, z) (i64[] i64 i64[] i64 i64[] i64 i64[]) i64
  i = 0
  while i < 128
    a0 = a[aoff + 2 * i]
    a1 = a[aoff + 2 * i + 1]
    b0 = b[boff + 2 * i]
    b1 = b[boff + 2 * i + 1]
    x = a1 * b1
    x = x - ((x * 1290167) >> 32) * 3329 - 3329
    x = x + ((x >> 63) & 3329)
    acc[ao + 2 * i] = acc[ao + 2 * i] + a0 * b0 + x * z[128 + i]
    acc[ao + 2 * i + 1] = acc[ao + 2 * i + 1] + a0 * b1 + a1 * b0
    i += 1
  0

-> mlk_reduce(f, o, n) (i64[] i64 i64) i64
  i = o
  e = o + n
  while i < e
    x = f[i]
    x = x - ((x * 1290167) >> 32) * 3329 - 3329
    f[i] = x + ((x >> 63) & 3329)
    i += 1
  0

-> mlk_zero(f, o, n) (i64[] i64 i64) i64
  i = o
  e = o + n
  while i < e
    f[i] = 0
    i += 1
  0

# f[fo..] = (f[fo..] + g[gofs..]) mod q, n coefficients
-> mlk_add(f, fo, g, gofs, n) (i64[] i64 i64[] i64 i64) i64
  i = 0
  while i < n
    s = f[fo + i] + g[gofs + i] - 3329
    f[fo + i] = s + ((s >> 63) & 3329)
    i += 1
  0

# ---- sampling (Algorithms 7, 8) ----

# SampleNTT rejection loop over XOF output buf[0..blen). Returns how many coefficients it
# produced (256 unless the buffer ran dry).
-> mlk_parse(a, o, buf, blen) (i64[] i64 u8[] i64) i64
  j = 0
  p = 0
  while j < 256 && p + 3 <= blen
    c0 = buf[p]
    c1 = buf[p + 1]
    c2 = buf[p + 2]
    p += 3
    d1 = c0 + ((c1 & 15) << 8)
    d2 = (c1 >> 4) + (c2 << 4)
    if d1 < 3329
      a[o + j] = d1
      j += 1
    if d2 < 3329 && j < 256
      a[o + j] = d2
      j += 1
  j

# A_hat[i][j] = SampleNTT(rho || j || i), stored at a[(i * k + j) * 256]. With transpose = 1
# the matrix is stored transposed (A_hat^T), as K-PKE.Encrypt needs.
-> mlk_gen_matrix(a, rho, transpose) (i64[] u8[] i64) i64
  seed = u8[34]
  t = 0
  while t < 32
    seed[t] = rho[t]
    t += 1
  i = 0
  while i < 3
    j = 0
    while j < 3
      seed[32] = j
      seed[33] = i
      o = (i * 3 + j) * 256
      o = (j * 3 + i) * 256 if transpose == 1
      blen = 504
      got = 0
      while got < 256
        buf = Crypto.shake128(seed, blen) ## u8[]
        got = mlk_parse(a, o, buf, blen)
        blen += 168
      j += 1
    i += 1
  0

# SamplePolyCBD_2 over 128 PRF bytes into f[o..o+256)
-> mlk_cbd2(f, o, buf) (i64[] i64 u8[]) i64
  i = 0
  while i < 128
    b = buf[i]
    v = (b & 1) + ((b >> 1) & 1) - ((b >> 2) & 1) - ((b >> 3) & 1)
    f[o + 2 * i] = v + ((v >> 63) & 3329)
    w = ((b >> 4) & 1) + ((b >> 5) & 1) - ((b >> 6) & 1) - ((b >> 7) & 1)
    f[o + 2 * i + 1] = w + ((w >> 63) & 3329)
    i += 1
  0

# f[o..] = CBD_2(PRF_2(s, nonce)) where PRF_2 = SHAKE256(s || nonce, 128)
-> mlk_noise(f, o, s, nonce) (i64[] i64 u8[] i64) i64
  inp = u8[33]
  t = 0
  while t < 32
    inp[t] = s[t]
    t += 1
  inp[32] = nonce
  buf = Crypto.shake256(inp, 128) ## u8[]
  mlk_cbd2(f, o, buf)

# ---- encoding (Algorithms 3-6, compression §4.2.1) ----

# ByteEncode_d of n coefficients f[fo..] into out[oo..]
-> mlk_encode(out, oo, f, fo, n, d) (u8[] i64 i64[] i64 i64 i64) i64
  acc = 0
  bits = 0
  p = oo
  i = 0
  while i < n
    acc = acc | (f[fo + i] << bits)
    bits += d
    while bits >= 8
      out[p] = acc & 255
      p += 1
      acc = acc >> 8
      bits -= 8
    i += 1
  p

# ByteDecode_d of n coefficients from b[bo..] into f[fo..] (raw d-bit values, no reduction)
-> mlk_decode(f, fo, b, bo, n, d) (i64[] i64 u8[] i64 i64 i64) i64
  mask = (1 << d) - 1
  acc = 0
  bits = 0
  p = bo
  i = 0
  while i < n
    while bits < d
      acc = acc | (b[p] << bits)
      p += 1
      bits += 8
    f[fo + i] = acc & mask
    acc = acc >> d
    bits -= d
    i += 1
  p

# Compress_d in place (values canonical in [0, q))
-> mlk_compress(f, o, n, d) (i64[] i64 i64 i64) i64
  mask = (1 << d) - 1
  i = o
  e = o + n
  while i < e
    f[i] = (((f[i] << d) + 1664) / 3329) & mask
    i += 1
  0

-> mlk_decompress(f, o, n, d) (i64[] i64 i64 i64) i64
  half = 1 << (d - 1)
  i = o
  e = o + n
  while i < e
    f[i] = (f[i] * 3329 + half) >> d
    i += 1
  0

# ---- byte helpers ----

-> mlk_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  0

-> mlk_sub(src, off, n) (u8[] i64 i64) u8[]
  out = u8[n]
  mlk_copy(out, 0, src, off, n)
  out

-> mlk_cat(a, b) (u8[] u8[]) u8[]
  out = u8[a.size + b.size]
  mlk_copy(out, 0, a, 0, a.size)
  mlk_copy(out, a.size, b, 0, b.size)
  out

# 0 if a[ao..ao+n) == b[bo..bo+n), else nonzero (constant time)
-> mlk_diff(a, ao, b, bo, n) (u8[] i64 u8[] i64 i64) i64
  d = 0
  i = 0
  while i < n
    d = d | (a[ao + i] ^ b[bo + i])
    i += 1
  d

# ---- K-PKE (Algorithms 13-15) ----

# K-PKE.KeyGen(d): writes ByteEncode12(t_hat) || rho into ek[0..1184) and ByteEncode12(s_hat)
# into dk[0..1152).
-> mlk_pke_keygen(ek, dk, d, z) (u8[] u8[] u8[] i64[]) i64
  gin = u8[33]
  mlk_copy(gin, 0, d, 0, 32)
  gin[32] = 3
  g = Crypto.sha3_bytes(gin, 512) ## u8[]
  rho = mlk_sub(g, 0, 32)
  sigma = mlk_sub(g, 32, 32)
  a = i64[2304]
  mlk_gen_matrix(a, rho, 0)
  s = i64[768]
  e = i64[768]
  i = 0
  while i < 3
    mlk_noise(s, i * 256, sigma, i)
    i += 1
  i = 0
  while i < 3
    mlk_noise(e, i * 256, sigma, 3 + i)
    i += 1
  i = 0
  while i < 3
    mlk_ntt(s, i * 256, z)
    mlk_ntt(e, i * 256, z)
    i += 1
  t = i64[768]
  i = 0
  while i < 3
    j = 0
    while j < 3
      mlk_basemul_acc(t, i * 256, a, (i * 3 + j) * 256, s, j * 256, z)
      j += 1
    i += 1
  mlk_reduce(t, 0, 768)
  mlk_add(t, 0, e, 0, 768)
  mlk_encode(ek, 0, t, 0, 768, 12)
  mlk_copy(ek, 1152, rho, 0, 32)
  mlk_encode(dk, 0, s, 0, 768, 12)
  0

# K-PKE.Encrypt(ek, m, r) -> ct (1088 bytes) written into ct
-> mlk_pke_encrypt(ct, ek, m, r, z) (u8[] u8[] u8[] u8[] i64[]) i64
  th = i64[768]
  mlk_decode(th, 0, ek, 0, 768, 12)
  i = 0
  while i < 768
    th[i] = mlk_csub(th[i])
    i += 1
  rho = mlk_sub(ek, 1152, 32)
  at = i64[2304]
  mlk_gen_matrix(at, rho, 1)
  y = i64[768]
  e1 = i64[768]
  e2 = i64[256]
  i = 0
  while i < 3
    mlk_noise(y, i * 256, r, i)
    i += 1
  i = 0
  while i < 3
    mlk_noise(e1, i * 256, r, 3 + i)
    i += 1
  mlk_noise(e2, 0, r, 6)
  i = 0
  while i < 3
    mlk_ntt(y, i * 256, z)
    i += 1
  # u = NTT^-1(A_hat^T y_hat) + e1
  u = i64[768]
  i = 0
  while i < 3
    j = 0
    while j < 3
      mlk_basemul_acc(u, i * 256, at, (i * 3 + j) * 256, y, j * 256, z)
      j += 1
    mlk_reduce(u, i * 256, 256)
    mlk_invntt(u, i * 256, z)
    i += 1
  mlk_add(u, 0, e1, 0, 768)
  # v = NTT^-1(t_hat^T y_hat) + e2 + Decompress_1(m)
  v = i64[256]
  j = 0
  while j < 3
    mlk_basemul_acc(v, 0, th, j * 256, y, j * 256, z)
    j += 1
  mlk_reduce(v, 0, 256)
  mlk_invntt(v, 0, z)
  mlk_add(v, 0, e2, 0, 256)
  i = 0
  while i < 256
    bit = (m[i >> 3] >> (i & 7)) & 1
    s = v[i] + (bit * 1665) - 3329
    v[i] = s + ((s >> 63) & 3329)
    i += 1
  mlk_compress(u, 0, 768, 10)
  mlk_encode(ct, 0, u, 0, 768, 10)
  mlk_compress(v, 0, 256, 4)
  mlk_encode(ct, 960, v, 0, 256, 4)
  0

# K-PKE.Decrypt(dk_pke = dk[0..1152), c) -> m (32 bytes)
-> mlk_pke_decrypt(dk, ct, z) (u8[] u8[] i64[]) u8[]
  u = i64[768]
  mlk_decode(u, 0, ct, 0, 768, 10)
  mlk_decompress(u, 0, 768, 10)
  v = i64[256]
  mlk_decode(v, 0, ct, 960, 256, 4)
  mlk_decompress(v, 0, 256, 4)
  sh = i64[768]
  mlk_decode(sh, 0, dk, 0, 768, 12)
  i = 0
  while i < 768
    sh[i] = mlk_csub(sh[i])
    i += 1
  i = 0
  while i < 3
    mlk_ntt(u, i * 256, z)
    i += 1
  w = i64[256]
  j = 0
  while j < 3
    mlk_basemul_acc(w, 0, sh, j * 256, u, j * 256, z)
    j += 1
  mlk_reduce(w, 0, 256)
  mlk_invntt(w, 0, z)
  # w = v - w, then Compress_1 and ByteEncode_1
  m = u8[32]
  i = 0
  while i < 256
    x = v[i] - w[i]
    x = x + ((x >> 63) & 3329)
    bit = (((x << 1) + 1664) / 3329) & 1
    m[i >> 3] = m[i >> 3] | (bit << (i & 7))
    i += 1
  m

# ---- ML-KEM (Algorithms 16-21) ----

-> mlkem768_keygen_derand(d, z)
  raise "mlkem768: d and z must be 32 bytes" if d.size != 32 || z.size != 32
  tab = i64[256]
  mlk_tables(tab)
  ek = u8[1184]
  dk = u8[2400]
  mlk_pke_keygen(ek, dk, d, tab)
  mlk_copy(dk, 1152, ek, 0, 1184)
  h = Crypto.sha3_bytes(ek, 256) ## u8[]
  mlk_copy(dk, 2336, h, 0, 32)
  mlk_copy(dk, 2368, z, 0, 32)
  [ek, dk]

-> mlkem768_keygen
  mlkem768_keygen_derand(Crypto.random_bytes(32), Crypto.random_bytes(32))

# Encapsulation-key check (FIPS 203 §7.2): length, and every 12-bit coefficient < q
# (equivalently ByteEncode12(ByteDecode12(ek)) == ek).
-> mlk_ek_modulus_ok(ek) (u8[]) i64
  bad = 0
  i = 0
  while i < 1152
    b0 = ek[i]
    b1 = ek[i + 1]
    b2 = ek[i + 2]
    c0 = b0 + ((b1 & 15) << 8)
    c1 = (b1 >> 4) + (b2 << 4)
    bad = bad | ((3328 - c0) >> 63) | ((3328 - c1) >> 63)
    i += 3
  bad == 0 ? 1 : 0

-> mlkem768_ek_valid(ek)
  return false if ek.size != 1184
  mlk_ek_modulus_ok(ek) == 1

# Decapsulation-key check (FIPS 203 §7.3): length, and H(ek) stored in dk matches.
-> mlkem768_dk_valid(dk)
  return false if dk.size != 2400
  h = Crypto.sha3_bytes(mlk_sub(dk, 1152, 1184), 256) ## u8[]
  mlk_diff(h, 0, dk, 2336, 32) == 0

-> mlkem768_encaps_derand(ek, m)
  raise "mlkem768: invalid encapsulation key" if !mlkem768_ek_valid(ek)
  raise "mlkem768: m must be 32 bytes" if m.size != 32
  tab = i64[256]
  mlk_tables(tab)
  h = Crypto.sha3_bytes(ek, 256) ## u8[]
  kr = Crypto.sha3_bytes(mlk_cat(m, h), 512) ## u8[]
  ct = u8[1088]
  mlk_pke_encrypt(ct, ek, m, mlk_sub(kr, 32, 32), tab)
  [mlk_sub(kr, 0, 32), ct]

-> mlkem768_encaps(ek)
  mlkem768_encaps_derand(ek, Crypto.random_bytes(32))

# Selects a (flag 0) or b (flag nonzero), 32 bytes, without branching on flag.
-> mlk_select(a, b, flag) (u8[] u8[] i64) u8[]
  mask = (0 - (((flag | (0 - flag)) >> 63) & 1)) & 255
  out = u8[32]
  i = 0
  while i < 32
    out[i] = a[i] ^ ((a[i] ^ b[i]) & mask)
    i += 1
  out

-> mlkem768_decaps(dk, ct)
  raise "mlkem768: ciphertext must be 1088 bytes" if ct.size != 1088
  raise "mlkem768: invalid decapsulation key" if !mlkem768_dk_valid(dk)
  tab = i64[256]
  mlk_tables(tab)
  m2 = mlk_pke_decrypt(dk, ct, tab)
  kr = Crypto.sha3_bytes(mlk_cat(m2, mlk_sub(dk, 2336, 32)), 512) ## u8[]
  kbar = Crypto.shake256(mlk_cat(mlk_sub(dk, 2368, 32), ct), 32) ## u8[]
  ct2 = u8[1088]
  mlk_pke_encrypt(ct2, mlk_sub(dk, 1152, 1184), m2, mlk_sub(kr, 32, 32), tab)
  mlk_select(mlk_sub(kr, 0, 32), kbar, mlk_diff(ct, 0, ct2, 0, 1088))
