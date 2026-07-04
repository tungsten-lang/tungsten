in Crypto

# SHA-2, 224-bit variant.
# This is the SHA-256 compression function with SHA-224 initial values and a
# 224-bit output.

+ SHA224
  -> .digest(data)
    ccall("w_crypto_sha224_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_sha224_hex", data)

  -> .hex(data)
    hexdigest(data)
