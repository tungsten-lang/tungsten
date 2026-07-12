in Crypto

# Produces a 160-bit (20-byte) hash.
# SHA-1 is collision-broken; it remains useful for legacy wire protocols such
# as the WebSocket accept hash and for UUID v5 name-based UUIDs.

+ SHA1
  -> .digest(data)
    ccall("w_crypto_sha1_bytes", data)

  -> .hexdigest(data)
    ccall("w_crypto_sha1_hex", data)

  -> .hex(data)
    hexdigest(data)

  -> .base64digest(data)
    Base64.encode(digest(data))
