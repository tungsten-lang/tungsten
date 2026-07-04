# string_buffer - mutable UTF-8 string builder
#
# Constructor: StringBuffer() or StringBuffer(capacity)
#
# Examples:
#   sb = StringBuffer()
#   sb.append("hello")
#   sb << " world"
#   sb.to_s  # "hello world" (frozen)

+ string_buffer
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
  -> size i64
  -> byte_size i64
  -> [](index)
  -> clear
  -> empty?
