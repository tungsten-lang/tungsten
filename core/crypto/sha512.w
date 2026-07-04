in Crypto

# SHA-2, 512-bit variant.
# This uses the 64-bit SHA-512 compression function. SHA-512/224 and
# SHA-512/256 are exposed through Crypto:SHA2 and the top-level convenience
# methods because their names are algorithm selectors rather than class names.

+ SHA512
  -> .digest(data)
    ccall("w_crypto_sha512_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_sha512_hex", data)

  -> .hex(data)
    hexdigest(data)
