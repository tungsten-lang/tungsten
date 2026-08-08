in Crypto

# Produces a 160-bit (20-byte) hash.
# SHA-1 is collision-broken (practical chosen-prefix collisions since 2017);
# it remains useful for legacy wire protocols such as the WebSocket accept hash,
# for UUID v5 name-based UUIDs, and for interop with systems like git. It emits a
# one-time deprecation notice on first use — set TUNGSTEN_SHA1_OK=1 to silence.

SHA1_WARNED = {}

-> sha1_deprecation_notice
  if SHA1_WARNED[:done] != nil
    return nil
  SHA1_WARNED[:done] = true
  ok = env("TUNGSTEN_SHA1_OK")
  if ok == nil || ok == ""
    ccall("w_eputs", "warning: Crypto:SHA1 is collision-broken; prefer SHA256 (set TUNGSTEN_SHA1_OK=1 to silence)")
  nil

+ SHA1
  -> .digest(data)
    sha1_deprecation_notice
    ccall("w_crypto_sha1_bytes", data)

  -> .hexdigest(data)
    sha1_deprecation_notice
    ccall("w_crypto_sha1_hex", data)

  -> .hex(data)
    hexdigest(data)

  -> .base64digest(data)
    Base64.encode(digest(data))
