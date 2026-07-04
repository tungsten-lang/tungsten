in Crypto

# SHA-2, 384-bit variant.
# This is the SHA-512 compression function with SHA-384 initial values and a
# 384-bit output.

+ SHA384
  -> .digest(data)
    ccall("w_crypto_sha384_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_sha384_hex", data)

  -> .hex(data)
    hexdigest(data)
