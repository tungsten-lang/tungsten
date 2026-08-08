in Crypto

# SHAKE128 / SHAKE256 — FIPS 202 extendable-output functions (XOFs). Unlike a
# fixed digest, the caller chooses how many output bytes to produce. `bits` is
# the security level (128 or 256), not the output length.

+ SHAKE
  -> .digest(data, bits, outlen)
    ccall("w_crypto_shake_bytes", data, bits, outlen)

  -> .hexdigest(data, bits, outlen)
    ccall("w_crypto_shake_hex", data, bits, outlen)

  -> .shake128(data, outlen)
    ccall("w_crypto_shake_bytes", data, 128, outlen)

  -> .shake256(data, outlen)
    ccall("w_crypto_shake_bytes", data, 256, outlen)
