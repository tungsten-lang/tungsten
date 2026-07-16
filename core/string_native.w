# Native String methods that are safe to express over the WValue itself.
#
# The legacy core/string.w file remains the long-form API/design scaffold.
# Keep this file deliberately small and parseable so primitive String values
# can register their 0xF9 type-class dispatch without loading that scaffold.

+ String
  # Strings and Symbols share runtime dispatch key 0xF9. String WValues
  # already have bit 0 clear; Symbol WValues use that bit as their only type
  # distinction. This is identity for every String storage mode and the exact
  # historical Symbol -> String conversion. Rope receivers are flattened at
  # the established dispatch boundary before this body runs.
  -> to_s
    wvalue_from_bits($value & -2)

  # String modes 0..5 store their byte count directly in bits 1..3. Modes 6
  # and 7 are slab/heap strings and are only constructed for non-empty data;
  # rope receivers are flattened before String type-class dispatch. Therefore
  # mode 0 is exactly the canonical empty string (and empty symbol) encoding.
  -> empty?
    ($value & 14) == 0

  # Preserve the runtime's canonical byte-count boundary, then reproduce
  # w_int exactly. The current result is u32-sized, but the full signed-i48
  # check keeps this source body correct if String storage grows later.
  -> size
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # Keep both aliases independently dispatchable. Forwarding length to size
  # would add another public method lookup to this leaf operation.
  -> length
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)
