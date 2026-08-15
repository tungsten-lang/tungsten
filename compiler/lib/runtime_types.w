# NaN-boxing constants matching wvalue.h (v3 encoding)
# All values are i64 (signed representation of the uint64 bit patterns)

# Singletons (0x0000 space)
w_nil          = 0
w_false        = 1
w_true         = 2
w_undef        = 3
w_memo_miss    = 4

# Double bias: 0x0001000000000000 = 1 * 2^48 = 281474976710656
w_double_bias  = (1 << 48) ## i64

# Tag constants (signed i64 representation of uint64 bit patterns):
# 0xFFF8000000000000 = -(8 * 2^48) = -2251799813685248   instant (48-bit signed Unix ms)
# 0xFFF9000000000000 = -(7 * 2^48) = -1970324836974592   string/symbol
# 0xFFFA000000000000 = -(6 * 2^48) = -1688849860263936   int
# 0xFFFB000000000000 = -(5 * 2^48) = -1407374883553280   bigint (bit 47 of payload reserved for tag-sign)
# 0xFFFC000000000000 = -(4 * 2^48) = -1125899906842624   char/lexical
# 0xFFFD000000000000 = -(3 * 2^48) = -844424930131968    numeric (decimal/currency/quantity)
# 0xFFFE000000000000 = -(2 * 2^48) = -562949953421312    packed
# 0xFFFF000000000000 = -(1 * 2^48) = -281474976710656    duration
w_tag_instant   = ((0 - 8) << 48) ## i64
w_tag_stringsym = ((0 - 7) << 48) ## i64
w_tag_int       = ((0 - 6) << 48) ## i64
w_tag_bigint    = ((0 - 5) << 48) ## i64
w_tag_char      = ((0 - 4) << 48) ## i64
w_tag_decimal   = ((0 - 3) << 48) ## i64
w_tag_packed    = ((0 - 2) << 48) ## i64
w_tag_duration  = ((0 - 1) << 48) ## i64

# Masks:
# 0x0000FFFFFFFFFFFF = 2^48 - 1 = 281474976710655
# 0xFFFF000000000000 = -(2^48) = -281474976710656
w_payload_mask = ((1 << 48) - 1) ## i64
w_tag_mask     = ((0 - 1) << 48) ## i64

# These constants are raw LLVM bit patterns, but the compiler is itself a
# Tungsten program. Box only at the few boundaries that need ordinary numeric
# methods or container storage; interpreting a raw tag as a WValue would turn
# it into the value represented by those bits (String, Int, and so on).
-> machine_i64_box(value) (i64)
  ccall("w_int", value)

-> machine_i64_text(value) (i64)
  "u0x" + ccall("w_int_to_hex_str", value)
