in Crypto

# MD5 produces a 128-bit hash.
# It is retained for checksums and legacy protocols only; use SHA-256 for new
# integrity work and never use MD5 for password storage or signatures.

+ MD5
  -> .digest(data)
    ccall("w_crypto_md5_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_md5_hex", data)

  -> .hex(data)
    hexdigest(data)
