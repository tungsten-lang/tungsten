in Crypto

# PBKDF2 (RFC 2898 §5.2) with HMAC-SHA-256 as the PRF. This is also
# SCRAM's Hi() (RFC 5802 §2.2, where dklen = 32). Password and salt
# accept String or ByteArray.

+ PBKDF2
  -> .sha256(password, salt, iterations, dklen = 32)
    salt_b = Crypto:HMAC.__to_bytes(salt)
    nblocks = (dklen + 31) / 32
    out = u8[nblocks * 32]
    bi = 1
    while bi <= nblocks
      ib = u8[4]
      ib[0] = (bi >> 24) & 0xFF
      ib[1] = (bi >> 16) & 0xFF
      ib[2] = (bi >> 8) & 0xFF
      ib[3] = bi & 0xFF
      u = Crypto:HMAC.sha256(password, Crypto:HMAC.__concat(salt_b, ib))
      acc = u8[32]
      j = 0
      while j < 32
        acc[j] = u[j]
        j += 1
      iter = 1
      while iter < iterations
        u = Crypto:HMAC.sha256(password, u)
        j = 0
        while j < 32
          acc[j] = acc[j] ^ u[j]
          j += 1
        iter += 1
      base = (bi - 1) * 32
      j = 0
      while j < 32
        out[base + j] = acc[j]
        j += 1
      bi += 1
    return out if dklen == nblocks * 32
    out.slice(0, dklen)

  -> .sha256_hex(password, salt, iterations, dklen = 32)
    Crypto:HMAC.__hex(sha256(password, salt, iterations, dklen))
