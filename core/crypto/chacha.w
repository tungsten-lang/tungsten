# blade/chacha — symmetric primitives TLS 1.3 and QUIC need beyond core and
# blade/crypto:
#
#   * ChaCha20 (RFC 8439 §2.3/§2.4), Poly1305 (§2.5) and the
#     AEAD_CHACHA20_POLY1305 construction (§2.8), for
#     TLS_CHACHA20_POLY1305_SHA256 records, QUIC packet protection and HPKE.
#   * ChaCha20 QUIC header protection (RFC 9001 §5.4.4).
#   * AES-256 block encryption (FIPS-197), for QUIC header protection under
#     TLS_AES_256_GCM_SHA384 (blade/crypto has the AES-128 block).
#
# API (all bytes are ByteArray; key 32 bytes, nonce 12 bytes):
#   chacha20_poly1305_seal(key, nonce, pt, aad)          -> ciphertext || 16-byte tag
#   chacha20_poly1305_open(key, nonce, ct_and_tag, aad)  -> plaintext, or nil if the tag fails
#   chacha20_block(key, counter, nonce)                  -> 64-byte keystream block
#   chacha20_xor(key, counter, nonce, data)              -> data XOR keystream (counter = first block)
#   chacha_hp_mask(hp_key, sample)                       -> 16-byte mask (use the first 5 bytes)
#   poly1305_mac(key32, msg)                             -> 16-byte tag
#   aes256_expand(key32)                                 -> 240-byte expanded key
#   aes256_block(xk, in16)                               -> 16-byte ciphertext block
#
# Implementation: ChaCha20 holds 32-bit words in i64 locals with masking;
# Poly1305 uses five 26-bit limbs in i64 (products stay below 2^59), so no
# BigInt anywhere. The hot loops are typed functions over u8[] / i64[].
# Uses AES_SBOX and xtime from blade/crypto (load it first).

# ---- ChaCha20 ----

# st: i64[16] state with the counter word (12) ignored; the counter is `ctr`.
# XORs n bytes of src (from soff) with the keystream into dst (from doff).
# Returns the next counter value.
-> cc_xor(st, ctr, src, soff, dst, doff, n) (i64[] i64 u8[] i64 u8[] i64 i64) i64
  mk = 4294967295
  ks = i64[16]
  c = ctr
  s = soff
  d = doff
  rem = n
  while rem > 0
    x0 = st[0]
    x1 = st[1]
    x2 = st[2]
    x3 = st[3]
    x4 = st[4]
    x5 = st[5]
    x6 = st[6]
    x7 = st[7]
    x8 = st[8]
    x9 = st[9]
    x10 = st[10]
    x11 = st[11]
    x13 = st[13]
    x14 = st[14]
    x15 = st[15]
    x12 = c
    i = 0
    while i < 10
      x0 = (x0 + x4) & mk
      x12 = x12 ^ x0
      x12 = ((x12 << 16) | (x12 >> 16)) & mk
      x8 = (x8 + x12) & mk
      x4 = x4 ^ x8
      x4 = ((x4 << 12) | (x4 >> 20)) & mk
      x0 = (x0 + x4) & mk
      x12 = x12 ^ x0
      x12 = ((x12 << 8) | (x12 >> 24)) & mk
      x8 = (x8 + x12) & mk
      x4 = x4 ^ x8
      x4 = ((x4 << 7) | (x4 >> 25)) & mk
      x1 = (x1 + x5) & mk
      x13 = x13 ^ x1
      x13 = ((x13 << 16) | (x13 >> 16)) & mk
      x9 = (x9 + x13) & mk
      x5 = x5 ^ x9
      x5 = ((x5 << 12) | (x5 >> 20)) & mk
      x1 = (x1 + x5) & mk
      x13 = x13 ^ x1
      x13 = ((x13 << 8) | (x13 >> 24)) & mk
      x9 = (x9 + x13) & mk
      x5 = x5 ^ x9
      x5 = ((x5 << 7) | (x5 >> 25)) & mk
      x2 = (x2 + x6) & mk
      x14 = x14 ^ x2
      x14 = ((x14 << 16) | (x14 >> 16)) & mk
      x10 = (x10 + x14) & mk
      x6 = x6 ^ x10
      x6 = ((x6 << 12) | (x6 >> 20)) & mk
      x2 = (x2 + x6) & mk
      x14 = x14 ^ x2
      x14 = ((x14 << 8) | (x14 >> 24)) & mk
      x10 = (x10 + x14) & mk
      x6 = x6 ^ x10
      x6 = ((x6 << 7) | (x6 >> 25)) & mk
      x3 = (x3 + x7) & mk
      x15 = x15 ^ x3
      x15 = ((x15 << 16) | (x15 >> 16)) & mk
      x11 = (x11 + x15) & mk
      x7 = x7 ^ x11
      x7 = ((x7 << 12) | (x7 >> 20)) & mk
      x3 = (x3 + x7) & mk
      x15 = x15 ^ x3
      x15 = ((x15 << 8) | (x15 >> 24)) & mk
      x11 = (x11 + x15) & mk
      x7 = x7 ^ x11
      x7 = ((x7 << 7) | (x7 >> 25)) & mk
      x0 = (x0 + x5) & mk
      x15 = x15 ^ x0
      x15 = ((x15 << 16) | (x15 >> 16)) & mk
      x10 = (x10 + x15) & mk
      x5 = x5 ^ x10
      x5 = ((x5 << 12) | (x5 >> 20)) & mk
      x0 = (x0 + x5) & mk
      x15 = x15 ^ x0
      x15 = ((x15 << 8) | (x15 >> 24)) & mk
      x10 = (x10 + x15) & mk
      x5 = x5 ^ x10
      x5 = ((x5 << 7) | (x5 >> 25)) & mk
      x1 = (x1 + x6) & mk
      x12 = x12 ^ x1
      x12 = ((x12 << 16) | (x12 >> 16)) & mk
      x11 = (x11 + x12) & mk
      x6 = x6 ^ x11
      x6 = ((x6 << 12) | (x6 >> 20)) & mk
      x1 = (x1 + x6) & mk
      x12 = x12 ^ x1
      x12 = ((x12 << 8) | (x12 >> 24)) & mk
      x11 = (x11 + x12) & mk
      x6 = x6 ^ x11
      x6 = ((x6 << 7) | (x6 >> 25)) & mk
      x2 = (x2 + x7) & mk
      x13 = x13 ^ x2
      x13 = ((x13 << 16) | (x13 >> 16)) & mk
      x8 = (x8 + x13) & mk
      x7 = x7 ^ x8
      x7 = ((x7 << 12) | (x7 >> 20)) & mk
      x2 = (x2 + x7) & mk
      x13 = x13 ^ x2
      x13 = ((x13 << 8) | (x13 >> 24)) & mk
      x8 = (x8 + x13) & mk
      x7 = x7 ^ x8
      x7 = ((x7 << 7) | (x7 >> 25)) & mk
      x3 = (x3 + x4) & mk
      x14 = x14 ^ x3
      x14 = ((x14 << 16) | (x14 >> 16)) & mk
      x9 = (x9 + x14) & mk
      x4 = x4 ^ x9
      x4 = ((x4 << 12) | (x4 >> 20)) & mk
      x3 = (x3 + x4) & mk
      x14 = x14 ^ x3
      x14 = ((x14 << 8) | (x14 >> 24)) & mk
      x9 = (x9 + x14) & mk
      x4 = x4 ^ x9
      x4 = ((x4 << 7) | (x4 >> 25)) & mk
      i += 1
    if rem >= 64
      w = (x0 + st[0]) & mk
      dst[d + 0] = src[s + 0] ^ ((w) & 255)
      dst[d + 1] = src[s + 1] ^ ((w >> 8) & 255)
      dst[d + 2] = src[s + 2] ^ ((w >> 16) & 255)
      dst[d + 3] = src[s + 3] ^ ((w >> 24) & 255)
      w = (x1 + st[1]) & mk
      dst[d + 4] = src[s + 4] ^ ((w) & 255)
      dst[d + 5] = src[s + 5] ^ ((w >> 8) & 255)
      dst[d + 6] = src[s + 6] ^ ((w >> 16) & 255)
      dst[d + 7] = src[s + 7] ^ ((w >> 24) & 255)
      w = (x2 + st[2]) & mk
      dst[d + 8] = src[s + 8] ^ ((w) & 255)
      dst[d + 9] = src[s + 9] ^ ((w >> 8) & 255)
      dst[d + 10] = src[s + 10] ^ ((w >> 16) & 255)
      dst[d + 11] = src[s + 11] ^ ((w >> 24) & 255)
      w = (x3 + st[3]) & mk
      dst[d + 12] = src[s + 12] ^ ((w) & 255)
      dst[d + 13] = src[s + 13] ^ ((w >> 8) & 255)
      dst[d + 14] = src[s + 14] ^ ((w >> 16) & 255)
      dst[d + 15] = src[s + 15] ^ ((w >> 24) & 255)
      w = (x4 + st[4]) & mk
      dst[d + 16] = src[s + 16] ^ ((w) & 255)
      dst[d + 17] = src[s + 17] ^ ((w >> 8) & 255)
      dst[d + 18] = src[s + 18] ^ ((w >> 16) & 255)
      dst[d + 19] = src[s + 19] ^ ((w >> 24) & 255)
      w = (x5 + st[5]) & mk
      dst[d + 20] = src[s + 20] ^ ((w) & 255)
      dst[d + 21] = src[s + 21] ^ ((w >> 8) & 255)
      dst[d + 22] = src[s + 22] ^ ((w >> 16) & 255)
      dst[d + 23] = src[s + 23] ^ ((w >> 24) & 255)
      w = (x6 + st[6]) & mk
      dst[d + 24] = src[s + 24] ^ ((w) & 255)
      dst[d + 25] = src[s + 25] ^ ((w >> 8) & 255)
      dst[d + 26] = src[s + 26] ^ ((w >> 16) & 255)
      dst[d + 27] = src[s + 27] ^ ((w >> 24) & 255)
      w = (x7 + st[7]) & mk
      dst[d + 28] = src[s + 28] ^ ((w) & 255)
      dst[d + 29] = src[s + 29] ^ ((w >> 8) & 255)
      dst[d + 30] = src[s + 30] ^ ((w >> 16) & 255)
      dst[d + 31] = src[s + 31] ^ ((w >> 24) & 255)
      w = (x8 + st[8]) & mk
      dst[d + 32] = src[s + 32] ^ ((w) & 255)
      dst[d + 33] = src[s + 33] ^ ((w >> 8) & 255)
      dst[d + 34] = src[s + 34] ^ ((w >> 16) & 255)
      dst[d + 35] = src[s + 35] ^ ((w >> 24) & 255)
      w = (x9 + st[9]) & mk
      dst[d + 36] = src[s + 36] ^ ((w) & 255)
      dst[d + 37] = src[s + 37] ^ ((w >> 8) & 255)
      dst[d + 38] = src[s + 38] ^ ((w >> 16) & 255)
      dst[d + 39] = src[s + 39] ^ ((w >> 24) & 255)
      w = (x10 + st[10]) & mk
      dst[d + 40] = src[s + 40] ^ ((w) & 255)
      dst[d + 41] = src[s + 41] ^ ((w >> 8) & 255)
      dst[d + 42] = src[s + 42] ^ ((w >> 16) & 255)
      dst[d + 43] = src[s + 43] ^ ((w >> 24) & 255)
      w = (x11 + st[11]) & mk
      dst[d + 44] = src[s + 44] ^ ((w) & 255)
      dst[d + 45] = src[s + 45] ^ ((w >> 8) & 255)
      dst[d + 46] = src[s + 46] ^ ((w >> 16) & 255)
      dst[d + 47] = src[s + 47] ^ ((w >> 24) & 255)
      w = (x12 + c) & mk
      dst[d + 48] = src[s + 48] ^ ((w) & 255)
      dst[d + 49] = src[s + 49] ^ ((w >> 8) & 255)
      dst[d + 50] = src[s + 50] ^ ((w >> 16) & 255)
      dst[d + 51] = src[s + 51] ^ ((w >> 24) & 255)
      w = (x13 + st[13]) & mk
      dst[d + 52] = src[s + 52] ^ ((w) & 255)
      dst[d + 53] = src[s + 53] ^ ((w >> 8) & 255)
      dst[d + 54] = src[s + 54] ^ ((w >> 16) & 255)
      dst[d + 55] = src[s + 55] ^ ((w >> 24) & 255)
      w = (x14 + st[14]) & mk
      dst[d + 56] = src[s + 56] ^ ((w) & 255)
      dst[d + 57] = src[s + 57] ^ ((w >> 8) & 255)
      dst[d + 58] = src[s + 58] ^ ((w >> 16) & 255)
      dst[d + 59] = src[s + 59] ^ ((w >> 24) & 255)
      w = (x15 + st[15]) & mk
      dst[d + 60] = src[s + 60] ^ ((w) & 255)
      dst[d + 61] = src[s + 61] ^ ((w >> 8) & 255)
      dst[d + 62] = src[s + 62] ^ ((w >> 16) & 255)
      dst[d + 63] = src[s + 63] ^ ((w >> 24) & 255)
      s += 64
      d += 64
      rem -= 64
    else
      ks[0] = (x0 + st[0]) & mk
      ks[1] = (x1 + st[1]) & mk
      ks[2] = (x2 + st[2]) & mk
      ks[3] = (x3 + st[3]) & mk
      ks[4] = (x4 + st[4]) & mk
      ks[5] = (x5 + st[5]) & mk
      ks[6] = (x6 + st[6]) & mk
      ks[7] = (x7 + st[7]) & mk
      ks[8] = (x8 + st[8]) & mk
      ks[9] = (x9 + st[9]) & mk
      ks[10] = (x10 + st[10]) & mk
      ks[11] = (x11 + st[11]) & mk
      ks[12] = (x12 + c) & mk
      ks[13] = (x13 + st[13]) & mk
      ks[14] = (x14 + st[14]) & mk
      ks[15] = (x15 + st[15]) & mk
      j = 0
      while j < rem
        dst[d + j] = src[s + j] ^ ((ks[j >> 2] >> ((j & 3) * 8)) & 255)
        j += 1
      rem = 0
    c = (c + 1) & mk
  c

-> cc_le32(b, o) (u8[] i64) i64
  w0 = b[o] ## i64
  w1 = b[o + 1] ## i64
  w2 = b[o + 2] ## i64
  w3 = b[o + 3] ## i64
  w0 | (w1 << 8) | (w2 << 16) | (w3 << 24)

-> cc_setup(st, key, nonce) (i64[] u8[] u8[]) i64
  st[0] = 1634760805
  st[1] = 857760878
  st[2] = 2036477234
  st[3] = 1797285236
  i = 0
  while i < 8
    st[4 + i] = cc_le32(key, i * 4)
    i += 1
  st[12] = 0
  st[13] = cc_le32(nonce, 0)
  st[14] = cc_le32(nonce, 4)
  st[15] = cc_le32(nonce, 8)
  0

-> cc_state(key, nonce)
  raise "chacha20: key must be 32 bytes" if key.size != 32
  raise "chacha20: nonce must be 12 bytes" if nonce.size != 12
  st = i64[16]
  cc_setup(st, key, nonce)
  st

-> chacha20_xor(key, counter, nonce, data)
  st = cc_state(key, nonce)
  out = ByteArray.new(data.size)
  cc_xor(st, counter, data, 0, out, 0, data.size)
  out

-> chacha20_block(key, counter, nonce)
  chacha20_xor(key, counter, nonce, ByteArray.new(64))

# RFC 9001 §5.4.4: counter = sample[0..4] little-endian, nonce = sample[4..16].
-> chacha_hp_mask(hp_key, sample)
  ctr = cc_le32(sample, 0)
  nonce = ByteArray.new(12)
  i = 0
  while i < 12
    nonce[i] = sample[4 + i]
    i += 1
  st = cc_state(hp_key, nonce)
  out = ByteArray.new(16)
  cc_xor(st, ctr, ByteArray.new(16), 0, out, 0, 16)
  out

# ---- Poly1305 (five 26-bit limbs) ----
# p: i64[14] = r0..r4, h0..h4, pad0..pad3 (32-bit words of s).

-> poly_init(p, key, ko) (i64[] u8[] i64) i64
  p[0] = cc_le32(key, ko) & 67108863
  p[1] = (cc_le32(key, ko + 3) >> 2) & 67108611
  p[2] = (cc_le32(key, ko + 6) >> 4) & 67092735
  p[3] = (cc_le32(key, ko + 9) >> 6) & 66076671
  p[4] = (cc_le32(key, ko + 12) >> 8) & 1048575
  i = 5
  while i < 10
    p[i] = 0
    i += 1
  p[10] = cc_le32(key, ko + 16)
  p[11] = cc_le32(key, ko + 20)
  p[12] = cc_le32(key, ko + 24)
  p[13] = cc_le32(key, ko + 28)
  0

# Absorbs nb 16-byte blocks of m from off; hibit is 1<<24 for full blocks.
-> poly_blocks(p, m, off, nb, hibit) (i64[] u8[] i64 i64 i64) i64
  mk = 67108863
  r0 = p[0]
  r1 = p[1]
  r2 = p[2]
  r3 = p[3]
  r4 = p[4]
  s1 = r1 * 5
  s2 = r2 * 5
  s3 = r3 * 5
  s4 = r4 * 5
  h0 = p[5]
  h1 = p[6]
  h2 = p[7]
  h3 = p[8]
  h4 = p[9]
  o = off
  k = 0
  while k < nb
    h0 += cc_le32(m, o) & mk
    h1 += (cc_le32(m, o + 3) >> 2) & mk
    h2 += (cc_le32(m, o + 6) >> 4) & mk
    h3 += (cc_le32(m, o + 9) >> 6) & mk
    h4 += (cc_le32(m, o + 12) >> 8) | hibit
    d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
    d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
    d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
    d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
    d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0
    cy = d0 >> 26
    h0 = d0 & mk
    d1 += cy
    cy = d1 >> 26
    h1 = d1 & mk
    d2 += cy
    cy = d2 >> 26
    h2 = d2 & mk
    d3 += cy
    cy = d3 >> 26
    h3 = d3 & mk
    d4 += cy
    cy = d4 >> 26
    h4 = d4 & mk
    h0 += cy * 5
    cy = h0 >> 26
    h0 = h0 & mk
    h1 += cy
    o += 16
    k += 1
  p[5] = h0
  p[6] = h1
  p[7] = h2
  p[8] = h3
  p[9] = h4
  0

# Absorbs len bytes; a trailing partial block is zero-padded to 16 bytes
# (the AEAD's pad16) and treated as a full block.
-> poly_pad16(p, m, off, len) (i64[] u8[] i64 i64) i64
  nb = len >> 4
  poly_blocks(p, m, off, nb, 16777216) if nb > 0
  tail = len & 15
  if tail > 0
    t = u8[16]
    i = 0
    while i < tail
      t[i] = m[off + nb * 16 + i]
      i += 1
    poly_blocks(p, t, 0, 1, 16777216)
  0

# Writes the 16-byte tag to out[oo..].
-> poly_finish(p, out, oo) (i64[] u8[] i64) i64
  mk = 67108863
  m32 = 4294967295
  h0 = p[5]
  h1 = p[6]
  h2 = p[7]
  h3 = p[8]
  h4 = p[9]
  cy = h1 >> 26
  h1 = h1 & mk
  h2 += cy
  cy = h2 >> 26
  h2 = h2 & mk
  h3 += cy
  cy = h3 >> 26
  h3 = h3 & mk
  h4 += cy
  cy = h4 >> 26
  h4 = h4 & mk
  h0 += cy * 5
  cy = h0 >> 26
  h0 = h0 & mk
  h1 += cy
  # g = h + 5 - 2^130; select g when it is non-negative (h >= p).
  g0 = h0 + 5
  cy = g0 >> 26
  g0 = g0 & mk
  g1 = h1 + cy
  cy = g1 >> 26
  g1 = g1 & mk
  g2 = h2 + cy
  cy = g2 >> 26
  g2 = g2 & mk
  g3 = h3 + cy
  cy = g3 >> 26
  g3 = g3 & mk
  g4 = h4 + cy - 67108864
  sel = (g4 >> 63) ^ -1
  nsel = sel ^ -1
  h0 = (h0 & nsel) | (g0 & sel)
  h1 = (h1 & nsel) | (g1 & sel)
  h2 = (h2 & nsel) | (g2 & sel)
  h3 = (h3 & nsel) | (g3 & sel)
  h4 = (h4 & nsel) | (g4 & sel)
  # h mod 2^128 as four 32-bit words, plus s.
  w0 = (h0 | (h1 << 26)) & m32
  w1 = ((h1 >> 6) | (h2 << 20)) & m32
  w2 = ((h2 >> 12) | (h3 << 14)) & m32
  w3 = ((h3 >> 18) | (h4 << 8)) & m32
  f = w0 + p[10]
  w0 = f & m32
  f = w1 + p[11] + (f >> 32)
  w1 = f & m32
  f = w2 + p[12] + (f >> 32)
  w2 = f & m32
  f = w3 + p[13] + (f >> 32)
  w3 = f & m32
  cc_put32(out, oo, w0)
  cc_put32(out, oo + 4, w1)
  cc_put32(out, oo + 8, w2)
  cc_put32(out, oo + 12, w3)
  0

-> cc_put32(b, o, w) (u8[] i64 i64) i64
  b[o] = w & 255
  b[o + 1] = (w >> 8) & 255
  b[o + 2] = (w >> 16) & 255
  b[o + 3] = (w >> 24) & 255
  0

# Generic Poly1305 (RFC 8439 §2.5): a trailing partial block gets a 0x01
# byte appended and no 2^128 bit.
-> poly1305_mac(key, msg)
  raise "poly1305: key must be 32 bytes" if key.size != 32
  p = i64[14]
  poly_init(p, key, 0)
  n = msg.size
  nb = n >> 4
  poly_blocks(p, msg, 0, nb, 16777216) if nb > 0
  tail = n & 15
  if tail > 0
    t = ByteArray.new(16)
    i = 0
    while i < tail
      t[i] = msg[nb * 16 + i]
      i += 1
    t[tail] = 1
    poly_blocks(p, t, 0, 1, 0)
  tag = ByteArray.new(16)
  poly_finish(p, tag, 0)
  tag

# ---- AEAD_CHACHA20_POLY1305 (RFC 8439 §2.8) ----

# Tag over aad and ct[co, co+clen) into tag[to..].
-> cc_aead_tag(st, aad, ct, co, clen, tag, to) (i64[] u8[] u8[] i64 i64 u8[] i64) i64
  otk = u8[64]
  zero = u8[64]
  cc_xor(st, 0, zero, 0, otk, 0, 64)
  p = i64[14]
  poly_init(p, otk, 0)
  alen = aad.size
  poly_pad16(p, aad, 0, alen)
  poly_pad16(p, ct, co, clen)
  lens = u8[16]
  cc_put32(lens, 0, alen & 4294967295)
  cc_put32(lens, 4, alen >> 32)
  cc_put32(lens, 8, clen & 4294967295)
  cc_put32(lens, 12, clen >> 32)
  poly_blocks(p, lens, 0, 1, 16777216)
  poly_finish(p, tag, to)
  0

# Constant-time: 0 when equal.
-> cc_diff(a, ao, b, bo, n) (u8[] i64 u8[] i64 i64) i64
  d = 0
  i = 0
  while i < n
    d = d | (a[ao + i] ^ b[bo + i])
    i += 1
  d

-> chacha20_poly1305_seal(key, nonce, pt, aad)
  st = cc_state(key, nonce)
  n = pt.size
  out = ByteArray.new(n + 16)
  cc_xor(st, 1, pt, 0, out, 0, n)
  cc_aead_tag(st, aad, out, 0, n, out, n)
  out

-> chacha20_poly1305_open(key, nonce, ct, aad)
  return nil if ct.size < 16
  st = cc_state(key, nonce)
  n = ct.size - 16
  tag = ByteArray.new(16)
  cc_aead_tag(st, aad, ct, 0, n, tag, 0)
  return nil if cc_diff(tag, 0, ct, n, 16) != 0
  out = ByteArray.new(n)
  cc_xor(st, 1, ct, 0, out, 0, n)
  out

# ---- AES-256 block encryption (FIPS-197), for QUIC header protection ----

AES_SBOX_U8 = [nil]

-> aes_sbox_u8
  if AES_SBOX_U8[0] == nil
    sb = ByteArray.new(256)
    i = 0
    while i < 256
      sb[i] = AES_SBOX[i]
      i += 1
    AES_SBOX_U8[0] = sb
  AES_SBOX_U8[0]

# 240-byte expanded key (60 words).
-> aes256_expand(key)
  raise "aes256: key must be 32 bytes" if key.size != 32
  sb = aes_sbox_u8()
  w = ByteArray.new(240)
  i = 0
  while i < 32
    w[i] = key[i]
    i += 1
  rcon = 1
  i = 32
  while i < 240
    t0 = w[i - 4]
    t1 = w[i - 3]
    t2 = w[i - 2]
    t3 = w[i - 1]
    if i % 32 == 0
      u = t0
      t0 = sb[t1] ^ rcon
      t1 = sb[t2]
      t2 = sb[t3]
      t3 = sb[u]
      rcon = xtime(rcon)
    elsif i % 32 == 16
      t0 = sb[t0]
      t1 = sb[t1]
      t2 = sb[t2]
      t3 = sb[t3]
    w[i] = w[i - 32] ^ t0
    w[i + 1] = w[i - 31] ^ t1
    w[i + 2] = w[i - 30] ^ t2
    w[i + 3] = w[i - 29] ^ t3
    i += 4
  w

-> aes_xt(b) (i64) i64
  ((b << 1) ^ (((b >> 7) & 1) * 283)) & 255

# Encrypts inp[0..16] with an expanded key of `rounds` rounds into out.
-> aes_enc_block(xk, rounds, inp, out, sb) (u8[] i64 u8[] u8[] u8[]) i64
  s = u8[16]
  t = u8[16]
  i = 0
  while i < 16
    s[i] = inp[i] ^ xk[i]
    i += 1
  round = 1
  while round <= rounds
    c = 0
    while c < 4
      r = 0
      while r < 4
        t[c * 4 + r] = sb[s[((c + r) & 3) * 4 + r]]
        r += 1
      c += 1
    if round < rounds
      c = 0
      while c < 4
        a0 = t[c * 4] ## i64
        a1 = t[c * 4 + 1] ## i64
        a2 = t[c * 4 + 2] ## i64
        a3 = t[c * 4 + 3] ## i64
        t[c * 4] = aes_xt(a0) ^ aes_xt(a1) ^ a1 ^ a2 ^ a3
        t[c * 4 + 1] = a0 ^ aes_xt(a1) ^ aes_xt(a2) ^ a2 ^ a3
        t[c * 4 + 2] = a0 ^ a1 ^ aes_xt(a2) ^ aes_xt(a3) ^ a3
        t[c * 4 + 3] = aes_xt(a0) ^ a0 ^ a1 ^ a2 ^ aes_xt(a3)
        c += 1
    k = round * 16
    i = 0
    while i < 16
      s[i] = t[i] ^ xk[k + i]
      i += 1
    round += 1
  i = 0
  while i < 16
    out[i] = s[i]
    i += 1
  0

-> aes256_block(xk, inp)
  out = ByteArray.new(16)
  aes_enc_block(xk, 14, inp, out, aes_sbox_u8())
  out
