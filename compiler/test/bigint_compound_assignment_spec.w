-> check_and
  x = (1 << 509) + (1 << 257) + 0x123456789abcdef
  mask = (1 << 509) + (1 << 300) + 0xf0f0f0f0f0f0f0f
  expected = x & mask
  x &= mask
  x == expected

-> check_or
  x = (1 << 509) + (1 << 257) + 0x123456789abcdef
  mask = (1 << 509) + (1 << 300) + 0xf0f0f0f0f0f0f0f
  expected = x | mask
  x |= mask
  x == expected

-> check_xor
  x = (1 << 509) + (1 << 257) + 0x123456789abcdef
  mask = (1 << 509) + (1 << 300) + 0xf0f0f0f0f0f0f0f
  expected = x ^ mask
  x ^= mask
  x == expected

-> check_shifts
  original = (1 << 509) + (1 << 257) + 0x123456789abcdef
  x = (1 << 509) + (1 << 257) + 0x123456789abcdef
  x <<= 13
  x >>= 13
  x == original

-> check_wide_and_negative_shifts
  x = 0 - ((1 << 509) + 0x12345)
  expected = (x << 77) >> 91
  x <<= 77
  x >>= 91
  x == expected

-> check_alias_value_semantics
  original = (1 << 509) + (1 << 257) + 0x123456789abcdef
  x = (1 << 509) + (1 << 257) + 0x123456789abcdef
  alias = x
  x &= (1 << 509) + 0xff
  alias == original && x == (original & ((1 << 509) + 0xff))

-> check_parameter_value_semantics(x)
  x |= (1 << 400) + 0x55
  x

raise "compound &= result mismatch" if !check_and()
raise "compound |= result mismatch" if !check_or()
raise "compound ^= result mismatch" if !check_xor()
raise "compound shift result mismatch" if !check_shifts()
raise "wide/negative shift fallback mismatch" if !check_wide_and_negative_shifts()

raise "compound assignment mutated an alias" if !check_alias_value_semantics()
caller = (1 << 509) + 0x123
changed = check_parameter_value_semantics(caller)
raise "compound assignment mutated a caller argument" if caller != (1 << 509) + 0x123
raise "compound assignment returned wrong parameter result" if changed != (caller | ((1 << 400) + 0x55))

x = 3
x **= 5
raise "power compound assignment mismatch" if x != 243

<< "ok"
