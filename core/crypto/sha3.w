in Crypto

# SHA-3 (Keccak) family — FIPS 202. Distinct construction from SHA-2 (a sponge,
# not a Merkle–Damgård chain), so it is a useful second, independent hash.
# `bits` selects the digest length: 224, 256 (default), 384, or 512.

+ SHA3
  -> .digest(data, bits = 256)
    ccall("w_crypto_sha3_bytes", data, bits)

  -> .hexdigest(data, bits = 256)
    ccall("w_crypto_sha3_hex", data, bits)

  -> .hex(data, bits = 256)
    hexdigest(data, bits)
