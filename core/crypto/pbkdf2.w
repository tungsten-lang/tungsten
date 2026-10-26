# PBKDF2 (RFC 2898 §5.2) with HMAC-SHA-256 as the PRF. This is also
# SCRAM's Hi() (RFC 5802 §2.2, where dklen = 32). Password and salt
# accept String or ByteArray.

in Crypto

+ PBKDF2
  -> .sha256(password, salt, iterations, dklen = 32)
    salt_b = Crypto:HMAC.__to_bytes(salt)
    pw_b = Crypto:HMAC.__to_bytes(password)
    if pw_b.size > 64
      pw_b = ccall("w_crypto_sha256_bytes", pw_b) ## u8[]
    pws = pw_b.size ## i64
    ss = salt_b.size ## i64
    ipad_buf = u8[96]
    opad_buf = u8[96]
    first_in = u8[64 + ss + 4]
    pbkdf2_init_buffers(pw_b, pws, salt_b, ss, ipad_buf, opad_buf, first_in)
    nblocks = (dklen + 31) / 32
    out = u8[nblocks * 32]
    acc = u8[32]
    bi = 1 ## i64
    iters = iterations ## i64
    while bi <= nblocks
      pbkdf2_set_block_be32(first_in, 64 + ss, bi)
      inner = ccall("w_crypto_sha256_bytes", first_in) ## u8[]
      pbkdf2_copy32(opad_buf, 64, inner)
      u = ccall("w_crypto_sha256_bytes", opad_buf) ## u8[]
      pbkdf2_copy32(acc, 0, u)
      pbkdf2_copy32(ipad_buf, 64, u)
      iter = 1 ## i64
      while iter < iters
        inner = ccall("w_crypto_sha256_bytes", ipad_buf) ## u8[]
        pbkdf2_copy32(opad_buf, 64, inner)
        u = ccall("w_crypto_sha256_bytes", opad_buf) ## u8[]
        pbkdf2_xor32_and_stage(acc, ipad_buf, u)
        iter += 1
      pbkdf2_copy32(out, (bi - 1) * 32, acc)
      bi += 1
    return out if dklen == nblocks * 32
    out.slice(0, dklen)

  -> .sha256_hex(password, salt, iterations, dklen = 32)
    Crypto:HMAC.__hex(sha256(password, salt, iterations, dklen))

-> pbkdf2_init_buffers(pw_b, pws, salt_b, ss, ipad_buf, opad_buf, first_in) (u8[] i64 u8[] i64 u8[] u8[] u8[]) i64
  i = 0
  while i < 64
    kb = 0
    if i < pws
      kb = pw_b[i]
    iv = kb ^ 0x36
    ipad_buf[i] = iv
    opad_buf[i] = kb ^ 0x5C
    first_in[i] = iv
    i += 1
  i = 0
  while i < ss
    first_in[64 + i] = salt_b[i]
    i += 1
  0

-> pbkdf2_set_block_be32(buf, off, bi) (u8[] i64 i64) i64
  buf[off] = (bi >> 24) & 0xFF
  buf[off + 1] = (bi >> 16) & 0xFF
  buf[off + 2] = (bi >> 8) & 0xFF
  buf[off + 3] = bi & 0xFF
  0

-> pbkdf2_copy32(dst, off, src) (u8[] i64 u8[]) i64
  j = 0
  while j < 32
    dst[off + j] = src[j]
    j += 1
  0

-> pbkdf2_xor32_and_stage(acc, ipad_buf, u) (u8[] u8[] u8[]) i64
  j = 0
  while j < 32
    v = u[j]
    acc[j] = acc[j] ^ v
    ipad_buf[64 + j] = v
    j += 1
  0
