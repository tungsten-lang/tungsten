in Crypto

# SHA-2, 256-bit variant.
# http://en.wikipedia.org/wiki/SHA-2
#
# The compression constants are the first 32 bits of the fractional parts of
# the cube roots of the first 64 primes; the initial hash values are the first
# 32 bits of the fractional parts of the square roots of the first 8 primes.
# The runtime owns the implementation so compiled programs and the interpreter
# share the same callable surface.

+ SHA256
  -> .digest(data)
    ccall("w_crypto_sha256_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_sha256_hex", data)

  -> .hex(data)
    hexdigest(data)
