# blade/crypto — byte buffers and the primitives TLS 1.3 and QUIC need beyond core:
# HKDF (RFC 5869) with the TLS 1.3 labels, X25519 (RFC 7748), and an AES-128 block
# cipher (FIPS-197) for QUIC header protection. SHA-2, HMAC, AES-GCM and randomness
# come from core.
#
# Bytes are ByteArray (u8[]) throughout.

-> bnew(n)
  ByteArray.new(n)

# perf: bulk byte copies go through bmove, a typed loop LLVM vectorizes (32-byte loads and
# stores); the untyped per-byte loops cost ~15 ns a byte. Only u8[] operands may take it
# (typed parameters are unchecked), so callers test is_a?(ByteArray) first.
-> bmove(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> bytes_of(s)
  n = s.size
  b = ByteArray.new(n)
  if n > 0 && s.is_a?(String)
    v = ccall("w_string_bytes_view", s) ## u8[]
    bmove(b, 0, v, 0, n)
    return b
  i = 0
  while i < n
    b[i] = s.byte_at(i)
    i += 1
  b

-> str_of(b)
  return "" if b.size == 0
  ccall("w_string_from_byte_array", b)

-> bslice(b, off, len)
  len = b.size - off if off + len > b.size
  return ByteArray.new(0) if len <= 0
  out = ByteArray.new(len)
  if b.is_a?(ByteArray) && off >= 0
    bmove(out, 0, b, off, len)
    return out
  i = 0
  while i < len
    out[i] = b[off + i]
    i += 1
  out

-> bcat(a, b)
  out = ByteArray.new(a.size + b.size)
  if a.is_a?(ByteArray) && b.is_a?(ByteArray)
    bmove(out, 0, a, 0, a.size)
    bmove(out, a.size, b, 0, b.size)
    return out
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  j = 0
  while j < b.size
    out[i + j] = b[j]
    j += 1
  out

-> bappend(dst, src)
  i = 0
  n = src.size
  while i < n
    dst.push(src[i])
    i += 1
  dst

# Join an array of ByteArray chunks into one ByteArray using vectorized bmove (zero per-byte push).
-> bjoin(chunks, total = -1)
  if total < 0
    total = 0
    i = 0
    while i < chunks.size
      total += chunks[i].size
      i += 1
  return ByteArray.new(0) if total == 0
  return chunks[0] if chunks.size == 1 && chunks[0].size == total
  out = ByteArray.new(total)
  off = 0
  i = 0
  while i < chunks.size
    c = chunks[i]
    n = c.size
    if n > 0
      bmove(out, off, c, 0, n)
      off += n
    i += 1
  out

-> bpush16(b, v)
  b.push((v >> 8) & 255)
  b.push(v & 255)
  b

-> bpush24(b, v)
  b.push((v >> 16) & 255)
  b.push((v >> 8) & 255)
  b.push(v & 255)
  b

-> bpush32(b, v)
  b.push((v >> 24) & 255)
  b.push((v >> 16) & 255)
  b.push((v >> 8) & 255)
  b.push(v & 255)
  b

-> bget16(b, o)
  (b[o] << 8) + b[o + 1]

-> bget24(b, o)
  (b[o] << 16) + (b[o + 1] << 8) + b[o + 2]

-> bget32(b, o)
  (b[o] << 24) + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3]

-> beq(a, b)
  return false if a.size != b.size
  d = 0
  i = 0
  while i < a.size
    d = d + (a[i] ^ b[i])
    i += 1
  d == 0

-> bhex(b)
  hx = "0123456789abcdef"
  sb = StringBuffer()
  i = 0
  while i < b.size
    sb.append(hx.slice(b[i] >> 4, 1))
    sb.append(hx.slice(b[i] & 15, 1))
    i += 1
  sb.to_s

-> unhex(s)
  b = ByteArray.new(0)
  i = 0
  while i + 1 < s.size
    b.push(s.slice(i, 2).to_i(16))
    i += 2
  b

-> brand(n)
  r = Crypto.random_bytes(n)
  return r if !r.is_a?(String)
  bytes_of(r)

-> sha256(b)
  Crypto.sha256_bytes(b)

-> hmac256(k, d)
  Crypto.hmac_sha256_bytes(k, d)

# ---- HKDF / TLS 1.3 key schedule helpers (SHA-256) ----

-> hkdf_extract(salt, ikm)
  salt = ByteArray.new(32) if salt.size == 0
  hmac256(salt, ikm)

-> hkdf_expand(prk, info, len)
  out = ByteArray.new(0)
  t = ByteArray.new(0)
  i = 1
  while out.size < len
    m = bcat(t, info)
    m.push(i)
    t = hmac256(prk, m)
    bappend(out, t)
    i += 1
  bslice(out, 0, len)

-> hkdf_label(secret, label, context, len)
  info = ByteArray.new(0)
  bpush16(info, len)
  full = "tls13 " + label
  info.push(full.size)
  bappend(info, bytes_of(full))
  info.push(context.size)
  bappend(info, context)
  hkdf_expand(secret, info, len)

-> derive_secret(secret, label, transcript_hash)
  hkdf_label(secret, label, transcript_hash, 32)

# ---- TLS 1.3 cipher suites (RFC 8446 §B.4) ----
#
# 0x1301 TLS_AES_128_GCM_SHA256, 0x1302 TLS_AES_256_GCM_SHA384, 0x1303 TLS_CHACHA20_POLY1305_SHA256.
# The suite fixes the AEAD, its key length and the key-schedule hash; the *_h helpers take the suite.

-> suite_hash_len(cs)
  cs == 0x1302 ? 48 : 32

-> suite_key_len(cs)
  cs == 0x1301 ? 16 : 32

-> suite_name(cs)
  return "TLS_AES_128_GCM_SHA256" if cs == 0x1301
  return "TLS_AES_256_GCM_SHA384" if cs == 0x1302
  return "TLS_CHACHA20_POLY1305_SHA256" if cs == 0x1303
  "0x" + cs.to_s(16)

-> sha384(b)
  Crypto.sha384_bytes(b)

-> hmac384(k, d)
  Crypto:HMAC.sha384(k, d)

-> tls_hash(cs, b)
  cs == 0x1302 ? sha384(b) : sha256(b)

-> tls_hmac(cs, k, d)
  cs == 0x1302 ? hmac384(k, d) : hmac256(k, d)

-> hkdf_extract_h(cs, salt, ikm)
  salt = ByteArray.new(suite_hash_len(cs)) if salt.size == 0
  tls_hmac(cs, salt, ikm)

-> hkdf_expand_h(cs, prk, info, len)
  out = ByteArray.new(0)
  t = ByteArray.new(0)
  i = 1
  while out.size < len
    m = bcat(t, info)
    m.push(i)
    t = tls_hmac(cs, prk, m)
    bappend(out, t)
    i += 1
  bslice(out, 0, len)

-> hkdf_label_h(cs, secret, label, context, len)
  info = ByteArray.new(0)
  bpush16(info, len)
  full = "tls13 " + label
  info.push(full.size)
  bappend(info, bytes_of(full))
  info.push(context.size)
  bappend(info, context)
  hkdf_expand_h(cs, secret, info, len)

-> derive_secret_h(cs, secret, label, transcript_hash)
  hkdf_label_h(cs, secret, label, transcript_hash, suite_hash_len(cs))

# The suite's AEAD. seal → ciphertext||tag; open → plaintext, or nil when authentication fails.
-> aead_seal(cs, key, nonce, pt, aad)
  return chacha20_poly1305_seal(key, nonce, pt, aad) if cs == 0x1303
  aes_gcm_seal(key, nonce, pt, aad)

-> aead_open(cs, key, nonce, ct, aad)
  return chacha20_poly1305_open(key, nonce, ct, aad) if cs == 0x1303
  aes_gcm_open(key, nonce, ct, aad)

# ---- X25519 (RFC 7748) ----

X25519_P = [nil]

-> x25519_p
  X25519_P[0] = 2 ** 255 - 19 if X25519_P[0] == nil
  X25519_P[0]

-> le_to_int(b)
  n = 0 ## int
  i = b.size - 1
  while i >= 0
    n = n * 256 + b[i]
    i -= 1
  n

-> int_to_le(n, len)
  out = ByteArray.new(len)
  v = n
  i = 0
  while i < len
    out[i] = (v % 256).to_i
    v = v / 256
    i += 1
  out

-> int_to_be(n, len)
  out = ByteArray.new(len)
  v = n
  i = len - 1
  while i >= 0
    out[i] = (v % 256).to_i
    v = v / 256
    i -= 1
  out

-> be_to_int(b)
  n = 0 ## int
  i = 0
  while i < b.size
    n = n * 256 + b[i]
    i += 1
  n

# X25519 runs on blade/curve25519 (radix-2^51 limbs, constant-time ladder, no
# allocation in the ladder). The Integer version below is the reference for tests:
# every BigInt intermediate it makes is retained (no GC), ~1 MB per call.
-> x25519(k_bytes, u_bytes)
  return x25519_ref(k_bytes, u_bytes) if k_bytes.size < 32 || u_bytes.size < 32
  x25519_fast(k_bytes, u_bytes)

-> x25519_ref(k_bytes, u_bytes)
  p = x25519_p()
  k = bslice(k_bytes, 0, 32)
  k[0] = k[0] & 248
  k[31] = (k[31] & 127) | 64
  kn = le_to_int(k)
  ub = bslice(u_bytes, 0, 32)
  ub[31] = ub[31] & 127
  x1 = le_to_int(ub) % p
  x2 = 1 ## int
  z2 = 0 ## int
  x3 = x1
  z3 = 1 ## int
  swap = 0
  a24 = 121665 ## int
  t = 254
  while t >= 0
    kt = ((kn >> t) & 1).to_i
    swap = swap ^ kt
    if swap == 1
      tmp = x2
      x2 = x3
      x3 = tmp
      tmp = z2
      z2 = z3
      z3 = tmp
    swap = kt
    a = (x2 + z2) % p
    aa = (a * a) % p
    b = (x2 - z2 + p) % p
    bb = (b * b) % p
    e = (aa - bb + p) % p
    c = (x3 + z3) % p
    d = (x3 - z3 + p) % p
    da = (d * a) % p
    cb = (c * b) % p
    s1 = (da + cb) % p
    x3 = (s1 * s1) % p
    s2 = (da - cb + p) % p
    z3 = (x1 * ((s2 * s2) % p)) % p
    x2 = (aa * bb) % p
    z2 = (e * ((aa + a24 * e) % p)) % p
    t -= 1
  if swap == 1
    tmp = x2
    x2 = x3
    x3 = tmp
    tmp = z2
    z2 = z3
    z3 = tmp
  r = (x2 * z2.pow(p - 2, p)) % p
  int_to_le(r, 32)

-> x25519_base(k)
  return x25519_base_fast(k) if k.size >= 32
  nine = ByteArray.new(32)
  nine[0] = 9
  x25519_ref(k, nine)

# ---- AES-128 block encryption (FIPS-197), for QUIC header protection ----

AES_SBOX = [0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16]

-> xtime(b)
  r = b << 1
  r = r ^ 0x11b if r >= 256
  r

# 176-byte expanded key.
-> aes128_expand(key)
  w = ByteArray.new(176)
  i = 0
  while i < 16
    w[i] = key[i]
    i += 1
  rcon = 1
  i = 16
  while i < 176
    t0 = w[i - 4]
    t1 = w[i - 3]
    t2 = w[i - 2]
    t3 = w[i - 1]
    if i % 16 == 0
      u = t0
      t0 = AES_SBOX[t1] ^ rcon
      t1 = AES_SBOX[t2]
      t2 = AES_SBOX[t3]
      t3 = AES_SBOX[u]
      rcon = xtime(rcon)
    w[i] = w[i - 16] ^ t0
    w[i + 1] = w[i - 15] ^ t1
    w[i + 2] = w[i - 14] ^ t2
    w[i + 3] = w[i - 13] ^ t3
    i += 4
  w

-> aes128_block(xk, inp)
  s = bslice(inp, 0, 16)
  i = 0
  while i < 16
    s[i] = s[i] ^ xk[i]
    i += 1
  round = 1
  while round <= 10
    # SubBytes + ShiftRows
    t = ByteArray.new(16)
    c = 0
    while c < 4
      r = 0
      while r < 4
        t[c * 4 + r] = AES_SBOX[s[((c + r) % 4) * 4 + r]]
        r += 1
      c += 1
    # MixColumns (not in the last round)
    if round < 10
      c = 0
      while c < 4
        a0 = t[c * 4]
        a1 = t[c * 4 + 1]
        a2 = t[c * 4 + 2]
        a3 = t[c * 4 + 3]
        t[c * 4] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3
        t[c * 4 + 1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3
        t[c * 4 + 2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3)
        t[c * 4 + 3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3)
        c += 1
    k = round * 16
    i = 0
    while i < 16
      s[i] = t[i] ^ xk[k + i]
      i += 1
    round += 1
  s

-> aes_gcm_seal(key, nonce, pt, aad)
  Crypto.aes_gcm_encrypt(key, nonce, pt, aad)

# nil when authentication fails.
-> aes_gcm_open(key, nonce, ct, aad)
  begin
    Crypto.aes_gcm_decrypt(key, nonce, ct, aad)
  rescue e
    nil
