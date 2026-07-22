in Crypto

# HMAC (RFC 2104) over the SHA-2 family, pure Tungsten on top of the
# runtime digest primitives. Block size is 64 bytes for SHA-224/256 and
# 128 bytes for SHA-384/512; keys longer than the block are hashed first.
# Key and data accept String or ByteArray.

+ HMAC
  -> .sha256(key, data)
    __compute(key, data, 64, ->(d) Crypto:SHA256.digest(d))

  -> .sha256_hex(key, data)
    __hex(sha256(key, data))

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
    if k.size > block
      k = h.call(k)
    ipad = u8[block]
    opad = u8[block]
    i = 0
    while i < block
      kb = 0
      kb = k[i] if i < k.size
      ipad[i] = kb ^ 0x36
      opad[i] = kb ^ 0x5C
      i += 1
    inner = h.call(__concat(ipad, m))
    h.call(__concat(opad, inner))

  -> .__to_bytes(x)
    if type(x) == "String"
      bs = x.bytes
      out = u8[bs.size]
      i = 0
      while i < bs.size
        out[i] = bs[i]
        i += 1
      return out
    x

  -> .__concat(a, b)
    out = u8[a.size + b.size]
    i = 0
    while i < a.size
      out[i] = a[i]
      i += 1
    j = 0
    while j < b.size
      out[a.size + j] = b[j]
      j += 1
    out

  -> .__hex_digit(n)
    if n < 10
      (48 + n).chr
    else
      (87 + n).chr

  -> .__hex(b)
    hx = ""
    i = 0
    while i < b.size
      hx = hx + __hex_digit(b[i] >> 4) + __hex_digit(b[i] & 15)
      i += 1
    hx
