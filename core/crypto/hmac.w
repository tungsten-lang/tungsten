# HMAC (RFC 2104) over the SHA-2 family, pure Tungsten on top of the
# runtime digest primitives. Block size is 64 bytes for SHA-224/256 and
# 128 bytes for SHA-384/512; keys longer than the block are hashed first.
# Key and data accept String or ByteArray.

in Crypto

+ HMAC
  -> .sha256(key, data)
    k = __to_bytes(key)
    m = __to_bytes(data)
    ks = k.size ## i64
    ms = m.size ## i64
    if ks > 64
      k = ccall("w_crypto_sha256_bytes", k) ## u8[]
      ks = 32
    inner_in = u8[64 + ms]
    outer_in = u8[96]
    hmac_prep_pads(k, ks, m, ms, inner_in, outer_in, 64)
    inner = ccall("w_crypto_sha256_bytes", inner_in) ## u8[]
    hmac_copy_tail(outer_in, 64, inner, 32)
    ccall("w_crypto_sha256_bytes", outer_in)

  -> .sha256_hex(key, data)
    k = __to_bytes(key)
    m = __to_bytes(data)
    ks = k.size ## i64
    ms = m.size ## i64
    if ks > 64
      k = ccall("w_crypto_sha256_bytes", k) ## u8[]
      ks = 32
    inner_in = u8[64 + ms]
    outer_in = u8[96]
    hmac_prep_pads(k, ks, m, ms, inner_in, outer_in, 64)
    inner = ccall("w_crypto_sha256_bytes", inner_in) ## u8[]
    hmac_copy_tail(outer_in, 64, inner, 32)
    ccall("w_crypto_sha256_hex", outer_in)

  -> .sha384(key, data)
    __compute(key, data, 128, ->(d) Crypto:SHA384.digest(d))

  -> .sha384_hex(key, data)
    __hex(sha384(key, data))

  -> .sha512(key, data)
    __compute(key, data, 128, ->(d) Crypto:SHA512.digest(d))

  -> .sha512_hex(key, data)
    __hex(sha512(key, data))

  -> .__compute(key, data, block, h)
    k = __to_bytes(key)
    m = __to_bytes(data)
    ks = k.size ## i64
    ms = m.size ## i64
    blk = block ## i64
    if ks > blk
      k = h.call(k)
      ks = k.size ## i64
    inner_in = u8[blk + ms]
    outer_in = u8[blk + 64]
    hmac_prep_pads(k, ks, m, ms, inner_in, outer_in, blk)
    inner = h.call(inner_in)
    ins = inner.size ## i64
    hmac_copy_tail(outer_in, blk, inner, ins)
    h.call(outer_in.slice(0, blk + ins))

  -> .__to_bytes(x)
    if type(x) == "String"
      return ccall("w_string_bytes_view", x) ## u8[]
    x

  -> .__concat(a, b)
    as = a.size ## i64
    bs = b.size ## i64
    out = u8[as + bs]
    hmac_copy_tail(out, 0, a, as)
    hmac_copy_tail(out, as, b, bs)
    out

  -> .__hex_digit(n)
    if n < 10
      (48 + n).chr
    else
      (87 + n).chr

  -> .__hex(b)
    n = b.size ## i64
    if n == 0
      return ""
    out = u8[n * 2]
    hmac_bytes_to_hex(b, out, n)
    ccall("w_string_take_byte_array", out, n * 2)

-> hmac_prep_pads(k, ks, m, ms, inner_in, outer_in, blk) (u8[] i64 u8[] i64 u8[] u8[] i64) i64
  i = 0
  while i < blk
    kb = 0
    if i < ks
      kb = k[i]
    inner_in[i] = kb ^ 0x36
    outer_in[i] = kb ^ 0x5C
    i += 1
  j = 0
  while j < ms
    inner_in[blk + j] = m[j]
    j += 1
  0

-> hmac_copy_tail(dst, off, src, n) (u8[] i64 u8[] i64) i64
  j = 0
  while j < n
    dst[off + j] = src[j]
    j += 1
  0

-> hmac_bytes_to_hex(b, out, n) (u8[] u8[] i64) i64
  i = 0
  while i < n
    v = b[i]
    hi = (v >> 4) & 15
    lo = v & 15
    out[i * 2] = hi < 10 ? 48 + hi : 87 + hi
    out[i * 2 + 1] = lo < 10 ? 48 + lo : 87 + lo
    i += 1
  0
