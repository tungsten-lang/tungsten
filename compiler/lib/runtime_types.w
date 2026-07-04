# NaN-boxing constants matching wvalue.h (v3 encoding)
# All values are i64 (signed representation of the uint64 bit patterns)

# Singletons (0x0000 space)
w_nil          = 0
w_false        = 1
w_true         = 2
w_undef        = 3
w_memo_miss    = 4

# Double bias: 0x0001000000000000 = 1 * 2^48 = 281474976710656
w_double_bias  = 281474976710656

# Tag constants (signed i64 representation of uint64 bit patterns):
# 0xFFF9000000000000 = -(7 * 2^48) = -1970324836974592   string/symbol
# 0xFFFA000000000000 = -(6 * 2^48) = -1688849860263936   int
# 0xFFFB000000000000 = -(5 * 2^48) = -1407374883553280   instant
# 0xFFFC000000000000 = -(4 * 2^48) = -1125899906842624   char/lexical
# 0xFFFD000000000000 = -(3 * 2^48) = -844424930131968    numeric (decimal/currency/quantity)
# 0xFFFE000000000000 = -(2 * 2^48) = -562949953421312    packed
# 0xFFFF000000000000 = -(1 * 2^48) = -281474976710656    duration
w_tag_stringsym = -1970324836974592
w_tag_int       = -1688849860263936
w_tag_instant   = -1407374883553280
w_tag_char      = -1125899906842624
w_tag_decimal   = -844424930131968
w_tag_packed    = -562949953421312
w_tag_duration  = -281474976710656

# Masks:
# 0x0000FFFFFFFFFFFF = 2^48 - 1 = 281474976710655
# 0xFFFF000000000000 = -(2^48) = -281474976710656
w_payload_mask = 281474976710655
w_tag_mask     = -281474976710656
