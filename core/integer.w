# Integer — 48-bit NaN-boxed signed integer with exact BigInt promotion.
# Arithmetic that leaves the inline range promotes transparently in runtime
# operators, so these methods stay exact at both i48 boundaries.
+ Integer < Real

  -> to_i
    self

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

  # Greatest common divisor — iterative Euclidean, exact for negatives. An
  # Integer receiver is always a NaN-boxed immediate (BigInt is its own
  # class), so when the argument is one too the loop runs on raw i64 at the
  # former C handler's cost. gcd(a, b) <= max(|a|, |b|), so the immediate
  # payload boxing of the result is exact. A BigInt argument falls through
  # to the generic promoting loop below.
  -> gcd(other)
    if ((wvalue_bits(other) >> 48) & 0xFFFF) == 0xFFFA
      a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (a & 0x800000000000) != 0
        a -= 281_474_976_710_656
      if a < 0
        a = 0 - a
      b = (wvalue_bits(other) & 0xFFFFFFFFFFFF) ## i64
      if (b & 0x800000000000) != 0
        b -= 281_474_976_710_656
      if b < 0
        b = 0 - b
      while b > 0
        t = b
        b = a % b
        a = t
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | a) ## i64)
    ga = self < 0 ? 0 - self : self
    gb = other < 0 ? 0 - other : other
    while gb > 0
      gt = gb
      gb = ga % gb
      ga = gt
    ga

  # Least common multiple: |a/g * b| with g = gcd(a, b). When both operands
  # are immediates AND the product provably fits the immediate payload, the
  # whole computation runs on raw i64 (the gcd loop inlined — a dispatched
  # gcd call would cost more than the rest of the method). Anything bigger
  # falls through to the generic promoting path, so results beyond the
  # 48-bit payload still become exact BigInts. By convention any lcm with
  # zero is zero, including lcm(0, 0).
  -> lcm(other)
    if ((wvalue_bits(other) >> 48) & 0xFFFF) == 0xFFFA
      aa = ($value & 0xFFFFFFFFFFFF) ## i64
      if (aa & 0x800000000000) != 0
        aa -= 281_474_976_710_656
      if aa < 0
        aa = 0 - aa
      bb = (wvalue_bits(other) & 0xFFFFFFFFFFFF) ## i64
      if (bb & 0x800000000000) != 0
        bb -= 281_474_976_710_656
      if bb < 0
        bb = 0 - bb
      if aa == 0 || bb == 0
        return 0
      ga = aa
      gb = bb
      while gb > 0
        gt = gb
        gb = ga % gb
        ga = gt
      qa = aa / ga
      # lcm = qa * bb, both positive. Guard the raw multiply against the
      # signed-48 immediate ceiling; oversized results take the boxed path.
      if bb <= 140_737_488_355_327 / qa
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (qa * bb)) ## i64)
    return 0 if self == 0 || other == 0
    r = (self / gcd(other)) * other
    r < 0 ? 0 - r : r
