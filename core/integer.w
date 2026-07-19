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

  # UTF-8 encode of the receiver's codepoint. The result is at most four
  # bytes, so it is BUILT IN REGISTERS as an inline-mode String (length in
  # bits 1..3, byte i at bits 4+8i) — no allocation at all, where the
  # former C handler malloc'd via w_string. Its w_string(strlen) quirks are
  # kept exactly: chr(0), and any negative whose low byte is zero, yield ""
  # (the NUL lead byte read as an empty C string), and out-of-range lead
  # bytes truncate to 8 bits like the C char store did.
  -> chr
    ch_c = ($value & 0xFFFFFFFFFFFF) ## i64
    if (ch_c & 0x800000000000) != 0
      ch_c -= 281_474_976_710_656
    ch_tag = -1_970_324_836_974_592 ## i64  # 0xFFF9000000000000
    if ch_c < 128
      ch_b = ch_c & 0xFF
      if ch_b == 0
        return ""
      return wvalue_from_bits((ch_tag | 2 | (ch_b << 4)) ## i64)
    if ch_c < 2048
      ch_b0 = 192 | (ch_c >> 6)
      ch_b1 = 128 | (ch_c & 63)
      return wvalue_from_bits((ch_tag | 4 | (ch_b0 << 4) | (ch_b1 << 12)) ## i64)
    if ch_c < 65536
      ch_b0 = 224 | (ch_c >> 12)
      ch_b1 = 128 | ((ch_c >> 6) & 63)
      ch_b2 = 128 | (ch_c & 63)
      return wvalue_from_bits((ch_tag | 6 | (ch_b0 << 4) | (ch_b1 << 12) | (ch_b2 << 20)) ## i64)
    ch_b0 = (240 | (ch_c >> 18)) & 0xFF
    ch_b1 = 128 | ((ch_c >> 12) & 63)
    ch_b2 = 128 | ((ch_c >> 6) & 63)
    ch_b3 = 128 | (ch_c & 63)
    wvalue_from_bits((ch_tag | 8 | (ch_b0 << 4) | (ch_b1 << 12) | (ch_b2 << 20) | (ch_b3 << 28)) ## i64)

  # Decimal digits. Results of up to five characters (all |n| < 100_000
  # positives, |n| < 10_000 negatives) build inline in registers with no
  # allocation; anything longer writes one u8 buffer whose storage the
  # result String steals. BigInt receivers keep their own IC handler.
  -> to_s
    ts_n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (ts_n & 0x800000000000) != 0
      ts_n -= 281_474_976_710_656
    ts_tag = -1_970_324_836_974_592 ## i64  # 0xFFF9000000000000
    if ts_n >= 0 && ts_n < 100_000
      ts_len = 1
      if ts_n >= 10
        ts_len += 1
      if ts_n >= 100
        ts_len += 1
      if ts_n >= 1000
        ts_len += 1
      if ts_n >= 10_000
        ts_len += 1
      ts_v = (ts_tag | (ts_len << 1)) ## i64
      ts_m = ts_n
      ts_i = ts_len - 1
      while ts_i >= 0
        ts_v = ts_v | ((ts_m % 10 + 48) << (4 + 8 * ts_i))
        ts_m = ts_m / 10
        ts_i -= 1
      return wvalue_from_bits(ts_v)
    if ts_n < 0 && ts_n > (0 - 10_000)
      ts_a = 0 - ts_n
      ts_len = 2
      if ts_a >= 10
        ts_len += 1
      if ts_a >= 100
        ts_len += 1
      if ts_a >= 1000
        ts_len += 1
      ts_v = (ts_tag | (ts_len << 1) | (45 << 4)) ## i64
      ts_i = ts_len - 1
      while ts_i >= 1
        ts_v = ts_v | ((ts_a % 10 + 48) << (4 + 8 * ts_i))
        ts_a = ts_a / 10
        ts_i -= 1
      return wvalue_from_bits(ts_v)
    # Longer results (6..15 digits): format on a C stack buffer and intern
    # once, exactly as the former IC handler's w_int_to_str did — cheaper
    # than allocating a Tungsten u8 buffer to steal.
    ccall("w_int_to_str_boxed", self)

  # Base-N digits, 2..36, lowercase letters past 9 — the former C handler's
  # exact loop (including its argument validation message). Base 10 shares
  # the buffer path rather than duplicating the inline fast case: explicit
  # to_s(10) is rare.
  # Base-N digits, 2..36. The digit loop and stack-buffer formatting stay in
  # C (w_int_to_str_base_boxed) — base conversion is rare and the native loop
  # is already allocation-lean — but the arity-2 dispatch and validation live
  # here in the class, so the method is source-defined like its siblings.
  -> to_s(base)
    if base < 2 || base > 36
      raise "to_s base must be between 2 and 36"
    ccall("w_int_to_str_base_boxed", self, base)

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

  # Modular exponentiation: (self ** exp) mod modulus, via square-and-multiply
  # in O(log exp) modular multiplications. The naive `(self ** exp) % modulus`
  # first materializes the full self**exp -- astronomically large for the
  # exponents used in RSA / Diffie-Hellman / Miller-Rabin -- so this is the
  # only tractable route. Every step rides the promoting *, %, / operators, so
  # it stays exact for BigInt bases, exponents, and moduli; the exponent is
  # bit-walked with % 2 / / 2 (not bitwise &/>>) so a BigInt exponent works too.
  -> pow(exp, modulus)
    if exp < 0
      raise "Integer#pow: negative exponent needs a modular inverse (unsupported)"
    if modulus == 1
      return 0
    result = 1
    base = self % modulus
    if base < 0
      base = base + modulus
    e = exp
    while e > 0
      if e % 2 == 1
        result = (result * base) % modulus
      e = e / 2
      if e > 0
        base = (base * base) % modulus
    result

  # Base-10 digits, least-significant first (Ruby Integer#digits): 1234 ->
  # [4, 3, 2, 1], 0 -> [0]. Rides the promoting % / / so it is exact for
  # BigInt receivers. Negative receivers raise (Ruby does too).
  -> digits
    if self < 0
      raise "Integer#digits: negative receiver"
    if self == 0
      return [0]
    dg_out = []
    dg_n = self
    while dg_n > 0
      dg_out.push(dg_n % 10)
      dg_n = dg_n / 10
    dg_out

  # Digits in an arbitrary base, least-significant first.
  -> digits(base)
    if self < 0
      raise "Integer#digits: negative receiver"
    if self == 0
      return [0]
    db_out = []
    db_n = self
    while db_n > 0
      db_out.push(db_n % base)
      db_n = db_n / base
    db_out

  # Integer square root: the largest k with k*k <= self (Ruby Integer#isqrt).
  # Newton's method from an overestimate (10^ceil(digits/2) >= sqrt), so it
  # descends monotonically to the floor; exact for BigInt via the promoting
  # / and ** operators.
  -> isqrt
    if self < 0
      raise "Integer#isqrt: negative receiver"
    if self < 2
      return self
    sq_x = 10 ** ((self.to_s.size + 1) / 2)
    sq_y = (sq_x + self / sq_x) / 2
    while sq_y < sq_x
      sq_x = sq_y
      sq_y = (sq_x + self / sq_x) / 2
    sq_x

  # n! — product of 1..n; 0! == 1. Uses reduce (not a `while` loop) so the
  # accumulator keeps promoting to BigInt past the inline range — a while-loop
  # accumulator becomes an unboxed i64 loop var and silently wraps (25! then
  # comes out mod 2^64). Small ints are class Integer (separate from Int,
  # which has its own factorial), so this must live here for `5.factorial`.
  -> factorial
    if self < 0
      raise "Integer#factorial: negative receiver"
    (2..self).reduce(1) -> (acc, it) acc * it

  # Ruby-style alias: modpow(e, m) == pow(e, m). Gives small ints the same
  # name Int/BigInt use, so `n.modpow(e, m)` works for any integer.
  -> modpow(e, m)
    pow(e, m)
