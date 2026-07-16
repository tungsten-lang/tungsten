# string_buffer - mutable UTF-8 string builder
#
# Constructor: StringBuffer() or StringBuffer(capacity)
#
# Examples:
#   sb = StringBuffer()
#   sb.append("hello")
#   sb << " world"
#   sb.to_s  # "hello world" (frozen)

+ StringBuffer
  - data
    # Phase 6i.2: type byte removed (StringBuffer promoted to W_SUBTAG_STRBUF).
    # Layout now starts directly with the flags byte.
    u8     flags
    u8[7]  _pad
    * u8[] data
    i64    length
    i64    capacity

  -> new(capacity = 0) (i64) string_buffer
  -> append(value)

  -> <<(value) (string) string_buffer

  -> to_s string
  -> length i64
  # Keep the signed header raw and construct the exact immediate-Integer word
  # for the overwhelmingly common i48 range. Sign-extending its low 48 bits
  # provides a one-compare exact range test; corrupt/native headers outside
  # that range take the canonical w_int fallback and become signed BigInts.
  -> size
    n = $length ## i64
    mask = 0xFFFFFFFFFFFF ## i64
    payload = (n & mask) ## i64
    roundtrip = ((payload << 16) >> 16) ## i64
    if roundtrip != n
      return ccall("w_int", n)
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    return wvalue_from_bits((tag | payload) ## i64)
  -> byte_size i64
  -> [](index)
  -> clear
  -> empty?
