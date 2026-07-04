# Base64 — RFC 4648 base64 encoding/decoding.
#
# Standard alphabet (`+`, `/`, `=` padding):
#   Base64.encode(data)         → String
#   Base64.decode(s)            → bytes
#
# URL-safe alphabet (`-`, `_`, no padding):
#   Base64.url_encode(data)     → String
#   Base64.url_decode(s)        → bytes
#
# `encode` / `url_encode` accept a String or ByteArray; bytes are taken
# as-is, Strings are read as UTF-8.
# `decode` / `url_decode` return raw bytes; invalid input raises.
#
# The compiler-side wiring lives at runtime in `__w_base64_*` (when the
# C runtime grows them); the Ruby interpreter ships builtins today.
# The lexer's `0b64-...` literal is a separate compile-time primitive.

+ Base64

  -> .encode(data)
    base64_encode(data)

  -> .decode(s)
    base64_decode(s)

  -> .url_encode(data)
    base64url_encode(data)

  -> .url_decode(s)
    base64url_decode(s)
