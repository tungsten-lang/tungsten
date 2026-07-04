in Crypto

# SHA-2 family facade.
#
# The old lib/core/cryptic SHA-2 stub listed SHA-224, SHA-256, SHA-384,
# SHA-512, and the SHA-512/256 and SHA-512/224 truncation variants. The
# runtime-backed implementation exposes each of those variants.

+ SHA2
  -> .digest(data, bits = 256)
    if bits == 224
      return ccall("w_crypto_sha224_bytes", data)
    if bits == 256
      return Crypto:SHA256.digest(data)
    if bits == 384
      return ccall("w_crypto_sha384_bytes", data)
    if bits == 512
      return ccall("w_crypto_sha512_bytes", data)
    if bits == "512/224" || bits == "512-224" || bits == :sha512_224
      return ccall("w_crypto_sha512_224_bytes", data)
    if bits == "512/256" || bits == "512-256" || bits == :sha512_256
      return ccall("w_crypto_sha512_256_bytes", data)
    raise "unsupported SHA-2 variant: " + bits.to_s

  -> .hexdigest(data, bits = 256)
    if bits == 224
      return ccall("w_crypto_sha224_hex", data)
    if bits == 256
      return Crypto:SHA256.hexdigest(data)
    if bits == 384
      return ccall("w_crypto_sha384_hex", data)
    if bits == 512
      return ccall("w_crypto_sha512_hex", data)
    if bits == "512/224" || bits == "512-224" || bits == :sha512_224
      return ccall("w_crypto_sha512_224_hex", data)
    if bits == "512/256" || bits == "512-256" || bits == :sha512_256
      return ccall("w_crypto_sha512_256_hex", data)
    raise "unsupported SHA-2 variant: " + bits.to_s

  -> .hex(data, bits = 256)
    hexdigest(data, bits)
