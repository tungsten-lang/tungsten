# Integer — 48-bit NaN-boxed signed integer with exact BigInt promotion.
# Arithmetic that leaves the inline range promotes transparently in runtime
# operators, so these methods stay exact at both i48 boundaries.
+ Integer < Real

  -> prev
    payload = ($value & 0xFFFFFFFFFFFF) ## i64
    if payload == 0x800000000000
      return self - 1
    tag = ($value & -281474976710656) ## i64
    mask = 0xFFFFFFFFFFFF ## i64
    next_payload = ((payload - 1) & mask) ## i64
    bits = (tag | next_payload) ## i64
    wvalue_from_bits(bits)

  -> succ
    payload = ($value & 0xFFFFFFFFFFFF) ## i64
    if payload == 0x7FFFFFFFFFFF
      return self + 1
    tag = ($value & -281474976710656) ## i64
    mask = 0xFFFFFFFFFFFF ## i64
    next_payload = ((payload + 1) & mask) ## i64
    bits = (tag | next_payload) ## i64
    wvalue_from_bits(bits)

  -> next
    payload = ($value & 0xFFFFFFFFFFFF) ## i64
    if payload == 0x7FFFFFFFFFFF
      return self + 1
    tag = ($value & -281474976710656) ## i64
    mask = 0xFFFFFFFFFFFF ## i64
    next_payload = ((payload + 1) & mask) ## i64
    bits = (tag | next_payload) ## i64
    wvalue_from_bits(bits)

  # `$value` is the raw NaN-boxed word in compiled methods. The payload's
  # low bit and sign bit make the Integer overrides single native bit tests;
  # Number and Real keep the generic definitions for other numeric classes.
  -> even?
    ($value & 1) == 0

  -> odd?
    ($value & 1) != 0

  -> zero?
    ($value & 0xFFFFFFFFFFFF) == 0

  -> negative?
    ($value & 0x800000000000) != 0

  -> positive?
    payload = ($value & 0xFFFFFFFFFFFF) ## i64
    payload != 0 && (payload & 0x800000000000) == 0

  -> sq
    self * self
