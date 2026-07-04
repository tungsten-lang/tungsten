# BinReader — cursor-based little-endian binary reader.
#
# Backs onto a byte source that answers to `byte_at(pos)` / `length()`.
# Two backings are used in this project:
#
#   * ByteSlice (wraps a String obtained from `read_file`)
#   * Typed u8[] slab (future — for tensor data weights that need
#     structural indexing without codepoint decoding overhead).
#
# Reads are little-endian; GGUF pins that endianness in its spec.

in Tungsten:Llama

+ ByteSlice
  rw :data   # a String (bytes) or byte-indexable value
  rw :bytes  # cached integer array; populated lazily

  -> new(data)
    @data = data
    @bytes = nil

  # Length in bytes.
  -> length
    @data.bytesize

  # Byte at absolute offset.
  -> byte_at(pos)
    if @bytes == nil
      @bytes = @data.bytes
    @bytes[pos]

  # Expose the byte array for fast bulk access (e.g. quant dequant inner loops).
  -> bytes_array
    if @bytes == nil
      @bytes = @data.bytes
    @bytes


+ BinReader
  rw :src    # ByteSlice
  rw :pos    # current byte offset

  -> new(src)
    @src = src
    @pos = 0

  -> length
    @src.size()

  -> remaining
    @src.size() - @pos

  -> eof?
    @pos >= @src.size()

  -> seek(p)
    @pos = p

  -> skip(n)
    @pos += n

  # Align the cursor up to a multiple of `a` bytes.
  -> align_to(a)
    r = @pos % a
    if r != 0
      @pos += a - r

  # -- Unsigned little-endian integers --

  -> read_u8
    b = @src.byte_at(@pos)
    @pos += 1
    b

  -> read_u16
    b0 = read_u8
    b1 = read_u8
    b0 | (b1 << 8)

  -> read_u32
    b0 = read_u8
    b1 = read_u8
    b2 = read_u8
    b3 = read_u8
    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

  -> read_u64
    lo = read_u32
    hi = read_u32
    lo | (hi << 32)

  # -- Signed --

  -> read_i8
    u = read_u8
    if u >= 128
      u - 256
    else
      u

  -> read_i16
    u = read_u16
    if u >= 0x8000
      u - 0x10000
    else
      u

  -> read_i32
    u = read_u32
    if u >= 0x80000000
      u - 0x100000000
    else
      u

  -> read_i64
    u = read_u64
    if u >= 0x8000000000000000
      u - 0x10000000000000000
    else
      u

  # -- IEEE 754 floats (use the Float bit-cast helpers from runtime;
  # the manual-decode fallbacks below stay around as a reference and
  # for backing types Float doesn't expose yet, like f16). --

  -> read_f32
    Float.from_u32_bits(read_u32)

  -> read_f64
    Float.from_u64_bits(read_u64)

  # -- Bulk --

  # Read `n` bytes and return them as an integer array.
  -> read_bytes(n)
    out = []
    i = 0
    while i < n
      out.push(read_u8)
      i += 1
    out

  # Read `n` bytes as a UTF-8 string. Uses StringBuffer so the
  # concatenation is amortized. Same byte-by-byte loop as
  # read_gguf_string but with caller-supplied length.
  -> read_string(n)
    buf = StringBuffer(n)
    i = 0
    while i < n
      buf << read_u8.chr()
      i = i + 1
    buf.to_s()

  # Read a GGUF-framed UTF-8 string: u64 length + raw bytes.
  # Built byte-by-byte so it works over any byte source that exposes
  # byte_at(i) (in particular, Mmap — String slicing isn't available
  # there). One-time cost at metadata parse + tokenizer load.
  -> read_gguf_string
    len = read_u64
    buf = StringBuffer(len)
    i = 0
    while i < len
      buf << read_u8.chr()
      i = i + 1
    buf.to_s()

  # Read one GGUF metadata value of the given type tag. Recurses for
  # array values. Lives on BinReader so the recursive call dispatches
  # via `self` instead of trying to resolve a top-level fn name.
  -> read_gguf_value(type_tag)
    if type_tag == 0
      return read_u8                    # GGUF_TYPE_UINT8
    if type_tag == 1
      return read_i8                    # GGUF_TYPE_INT8
    if type_tag == 2
      return read_u16                   # GGUF_TYPE_UINT16
    if type_tag == 3
      return read_i16                   # GGUF_TYPE_INT16
    if type_tag == 4
      return read_u32                   # GGUF_TYPE_UINT32
    if type_tag == 5
      return read_i32                   # GGUF_TYPE_INT32
    if type_tag == 6
      return read_f32                   # GGUF_TYPE_FLOAT32
    if type_tag == 7
      return read_u8 != 0               # GGUF_TYPE_BOOL
    if type_tag == 8
      return read_gguf_string           # GGUF_TYPE_STRING
    if type_tag == 9                    # GGUF_TYPE_ARRAY
      elt_type = read_u32
      n = read_u64
      arr = []
      i = 0
      while i < n
        arr.push(read_gguf_value(elt_type))
        i = i + 1
      return arr
    if type_tag == 10
      return read_u64                   # GGUF_TYPE_UINT64
    if type_tag == 11
      return read_i64                   # GGUF_TYPE_INT64
    if type_tag == 12
      return read_f64                   # GGUF_TYPE_FLOAT64
    raise "BinReader: unknown GGUF metadata type " + type_tag.to_s


# Convert 32-bit IEEE-754 bit pattern to a Float.
-> f32_from_bits(bits)
  sign_bit = (bits >> 31) & 1
  exponent = (bits >> 23) & 0xFF
  mantissa = bits & 0x7FFFFF
  if exponent == 0xFF
    # Inf / NaN — treat NaN as 0.0 for now; loaders only hit this on bad data.
    value = 0.0
    if mantissa == 0
      # Infinity — return a large but finite sentinel.
      value = 3.4028234663852886e38
  elsif exponent == 0
    if mantissa == 0
      value = 0.0
    else
      # Subnormal: (-1)^s * mantissa * 2^-149
      value = mantissa.to_f * pow2(-149)
  else
    # Normal: (1 + mantissa/2^23) * 2^(exponent-127)
    frac = 1.0 + (mantissa.to_f / 8388608.0)
    value = frac * pow2(exponent - 127)
  if sign_bit == 1
    -value
  else
    value

# Convert 64-bit IEEE-754 bit pattern to a Float.
-> f64_from_bits(bits)
  sign_bit = (bits >> 63) & 1
  exponent = (bits >> 52) & 0x7FF
  mantissa = bits & 0xFFFFFFFFFFFFF
  if exponent == 0x7FF
    value = 0.0
    if mantissa == 0
      value = 1.7976931348623157e308
  elsif exponent == 0
    if mantissa == 0
      value = 0.0
    else
      value = mantissa.to_f * pow2(-1074)
  else
    frac = 1.0 + (mantissa.to_f / 4503599627370496.0)
    value = frac * pow2(exponent - 1023)
  if sign_bit == 1
    -value
  else
    value

# 2 raised to a (possibly negative) integer power. Keeps the hot loop
# branch-free on sign once inlined; Tungsten's `**` on integers would
# overflow for large exponents so we split by sign and multiply in a loop.
-> pow2(n)
  if n >= 0
    acc = 1.0
    i = 0
    while i < n
      acc = acc * 2.0
      i += 1
    acc
  else
    acc = 1.0
    i = 0
    k = -n
    while i < k
      acc = acc * 0.5
      i += 1
    acc

# 16-bit IEEE-754 half-precision -> Float. Useful for Q8_0 scale fields.
-> f16_from_bits(bits)
  sign_bit = (bits >> 15) & 1
  exponent = (bits >> 10) & 0x1F
  mantissa = bits & 0x3FF
  if exponent == 0x1F
    value = 0.0
    if mantissa == 0
      value = 65504.0
  elsif exponent == 0
    if mantissa == 0
      value = 0.0
    else
      value = mantissa.to_f * pow2(-24)
  else
    frac = 1.0 + (mantissa.to_f / 1024.0)
    value = frac * pow2(exponent - 15)
  if sign_bit == 1
    -value
  else
    value
