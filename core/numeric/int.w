# Int — Tungsten's inline, auto-promoting integer implementation.
#
# Int refines generic Integer with the default exact-promotion policy.
# Arithmetic that leaves the inline representation becomes a BigInt; results
# that fit again canonicalize back to the inline form. Methods here may rely on
# an inline-i48 receiver and must delegate overflow or BigInt operands to the
# promoting runtime operators.
+ Int < Integer

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

  -> abs
    payload = ($value & 0xFFFFFFFFFFFF) ## i64
    if (payload & 0x800000000000) == 0
      return self
    if payload == 0x800000000000
      return 0 - self
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    neg_payload = ((0 - payload) & 0xFFFFFFFFFFFF) ## i64
    wvalue_from_bits((tag | neg_payload) ## i64)

  -> to_f
    n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (n & 0x800000000000) != 0
      n -= 281_474_976_710_656
    n ## f64

  -> sqrt
    n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (n & 0x800000000000) != 0
      n -= 281_474_976_710_656
    Math.sqrt(n ## f64)

  -> prime?
    n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (n & 0x800000000000) != 0
      return false
    ccall_nobox("w_prime_test_i64", n) != 0

  -> prime_12k?
    n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (n & 0x800000000000) != 0
      return false
    ccall_nobox("w_prime_test_i64_12k", n) != 0

  -> prime_30k?
    n = ($value & 0xFFFFFFFFFFFF) ## i64
    if (n & 0x800000000000) != 0
      return false
    ccall_nobox("w_prime_test_i64_30k", n) != 0

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
  # Int receiver is always a NaN-boxed immediate (BigInt is its own
  # class), so when the argument is one too the loop runs on raw i64 at the
  # former C handler's cost. gcd(a, b) <= max(|a|, |b|), so the immediate
  # payload boxing of the result is exact. A BigInt argument falls through
  # to the generic promoting loop below.
  -> gcd(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (a & 0x800000000000) != 0
        a -= 281_474_976_710_656
      if a < 0
        a = 0 - a
      b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (b & 0x800000000000) != 0
        b -= 281_474_976_710_656
      if b < 0
        b = 0 - b
      while b > 0
        t = b
        b = a % b
        a = t
      if a <= 140_737_488_355_327
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | a) ## i64)
    ccall("w_bigint_gcd", self, other)

  # Least common multiple: |a/g * b| with g = gcd(a, b). When both operands
  # are immediates AND the product provably fits the immediate payload, the
  # whole computation runs on raw i64 (the gcd loop inlined — a dispatched
  # gcd call would cost more than the rest of the method). Anything bigger
  # falls through to the runtime's exact BigInt lcm. By convention any lcm
  # with zero is zero, including lcm(0, 0).
  -> lcm(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      aa = ($value & 0xFFFFFFFFFFFF) ## i64
      if (aa & 0x800000000000) != 0
        aa -= 281_474_976_710_656
      if aa < 0
        aa = 0 - aa
      bb = (other$value & 0xFFFFFFFFFFFF) ## i64
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
    ccall("w_bigint_lcm", self, other)

  # Modular exponentiation: (self ** exp) mod modulus. Routed to the runtime
  # intrinsic `bigint_powmod_any` (runtime/runtime.c): sliding-window
  # square-and-multiply through the Montgomery/Barrett modular-multiplication
  # machinery, walking the exponent's bits straight off its limbs — exact for
  # BigInt bases, exponents, and moduli, with the result in [0, |modulus|).
  # (The naive `(self ** exp) % modulus` would materialize the full power —
  # astronomically large for RSA / Diffie-Hellman / Miller-Rabin exponents.)
  # Under the Ruby tree-walker the ccall body raises and dispatch falls back
  # to Ruby's own Integer#pow, which has the same modular semantics.
  -> pow(exp, modulus)
    if exp < 0
      raise "Int#pow: negative exponent needs a modular inverse (unsupported)"
    ccall("bigint_powmod_any", self, exp, modulus)

  # Base-10 digits, least-significant first (Ruby Integer#digits): 1234 ->
  # [4, 3, 2, 1], 0 -> [0]. Rides raw i64 division for 48-bit Ints and the
  # promoting % / / for BigInt receivers. Negative receivers raise.
  -> digits
    if self < 0
      raise "Int#digits: negative receiver"
    if self == 0
      return [0]
    dg_out = []
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      dg_v = ($value & 0xFFFFFFFFFFFF) ## i64
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      while dg_v > 0
        dg_q = dg_v / 10
        dg_r = dg_v - dg_q * 10
        dg_out.push(wvalue_from_bits((tag | dg_r) ## i64))
        dg_v = dg_q
      return dg_out
    dg_n = self
    while dg_n > 0
      dg_out.push(dg_n % 10)
      dg_n = dg_n / 10
    dg_out

  # Digits in an arbitrary base, least-significant first.
  -> digits(base)
    if self < 0
      raise "Int#digits: negative receiver"
    if self == 0
      return [0]
    db_out = []
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((base$value >> 48) & 0xFFFF) == 0xFFFA
      db_v = ($value & 0xFFFFFFFFFFFF) ## i64
      db_b = (base$value & 0xFFFFFFFFFFFF) ## i64
      if db_b >= 2
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        while db_v > 0
          db_q = db_v / db_b
          db_r = db_v - db_q * db_b
          db_out.push(wvalue_from_bits((tag | db_r) ## i64))
          db_v = db_q
        return db_out
    db_n = self
    while db_n > 0
      db_out.push(db_n % base)
      db_n = db_n / base
    db_out

  # Integer square root: the largest k with k*k <= self (Ruby Integer#isqrt).
  # Hardware fsqrt for nonnegative 48-bit Ints (< 2^47 < 2^53, where f64 is
  # exact); delegates negative or BigInt receivers to `bigint_isqrt_any`.
  -> isqrt
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      n = ($value & 0xFFFFFFFFFFFF) ## i64
      if (n & 0x800000000000) == 0
        root = Math.sqrt(n ## f64) ## i64
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | root) ## i64)
    ccall("bigint_isqrt_any", self)

  # n! — product of 1..n; 0! == 1. Uses reduce (not a `while` loop) so the
  # accumulator keeps promoting to BigInt past the inline range — a while-loop
  # accumulator becomes an unboxed i64 loop var and silently wraps (25! then
  # comes out mod 2^64). This specialized body lives on Int for
  # `5.factorial`; generic Integer subclasses keep the shared fallback.
  # The n-th prime, 1-indexed: `Int.nth_prime(1)` is 2, `Int.nth_prime(1e6)`
  # is 15485863. Backed by the mod-30 wheel sieve in core/prime_sieve.w,
  # which starts from the nearest entry in a 175-rung table of (n, p_n)
  # checkpoints — an exact hit returns without sieving at all, and otherwise
  # only the primes above that checkpoint are sieved.
  -> .nth_prime(n)
    PrimeSieve.nth(n)

  # The first n primes, ascending, as an i64 typed array. Sieved in parallel:
  # one pass counts each chunk, the prefix sum turns those counts into write
  # offsets, and a second pass fills each chunk's slice directly.
  # Refuses above 200M primes (1.6 GB) — sieve a range instead.
  -> .primes(n)
    PrimeSieve.first(n)

  # π(x) — how many primes are ≤ x. Same checkpoint skip as nth_prime.
  # `(2..x)/prime?:count` fuses to the same sieve.
  -> .prime_pi(x)
    PrimeSieve.pi(x)

  # Finite right-associated power tower. Height zero is the empty tower 1.
  # The reduce accumulator remains a promoting integer (including BigInt).
  -> tetrate(height)
    if !height.is_a?(Integer) || height < 0
      raise "tetration height must be a nonnegative integer"
    if self < 0
      raise "tetration base must be a nonnegative integer"
    return 1 if height == 0 || self == 1
    if self == 0
      return height.even? ? 1 : 0
    (1..height).reduce(1) -> (acc, item) self ** acc

  -> factorial
    if self < 0
      raise "Int#factorial: negative receiver"
    (2..self).reduce(1) -> (acc, it) acc * it

  # n# — product of primes <= n; 0# == 1# == 1. Reduce preserves
  # automatic BigInt promotion, just like factorial.
  -> primorial
    if self < 0
      raise "Int#primorial: negative receiver"
    (2..self).reduce(1) -> (acc, item)
      item.prime? ? acc * item : acc

  # Exact prime-power factorization. The returned value is enumerable and
  # exposes `primes` for the distinct-prime projection used by algebra scripts.
  -> factor
    IntegerFactorization.new(self)

  # Ruby-style alias: modpow(e, m) == pow(e, m). Gives small ints the same
  # name Int/BigInt use, so `n.modpow(e, m)` works for any integer.
  -> modpow(e, m)
    pow(e, m)

  # Modular inverse: x with (self * x) ≡ 1 (mod modulus). Extended Euclidean,
  # so it works for any modulus coprime to self — not only primes (Fermat
  # a^(p-2) would restrict to prime moduli and waste a full modpow). Raises
  # when gcd(|self|, |modulus|) ≠ 1. Result is in [0, |modulus|).
  -> invmod(modulus)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((modulus$value >> 48) & 0xFFFF) == 0xFFFA
      im_m = (modulus$value & 0xFFFFFFFFFFFF) ## i64
      if (im_m & 0x800000000000) != 0
        im_m -= 281_474_976_710_656
      if im_m == 0
        raise "Int#invmod: modulus must be nonzero"
      if im_m < 0
        im_m = 0 - im_m
      if im_m == 1
        return 0
      if im_m <= 140_737_488_355_327
        im_a = ($value & 0xFFFFFFFFFFFF) ## i64
        if (im_a & 0x800000000000) != 0
          im_a -= 281_474_976_710_656
        im_a = im_a % im_m
        if im_a < 0
          im_a += im_m
        im_t = 0 ## i64
        im_newt = 1 ## i64
        im_r = im_m
        im_newr = im_a
        while im_newr != 0
          im_q = im_r / im_newr
          im_tt = im_newt
          im_newt = im_t - im_q * im_newt
          im_t = im_tt
          im_tr = im_newr
          im_newr = im_r - im_q * im_newr
          im_r = im_tr
        if im_r > 1
          raise "Int#invmod: not invertible"
        if im_t < 0
          im_t += im_m
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | im_t) ## i64)
    ccall("w_bigint_invmod", self, modulus)

  # Legendre symbol (a/p) for odd prime p: 0 if p|a, +1 if a is a nonzero
  # quadratic residue mod p, −1 if a is a nonresidue. Uses Euler's criterion
  # a^((p-1)/2) ≡ (a/p) (mod p). Not Jacobi: p must be an odd prime (caller
  # responsibility; an invalid p that still yields {0,1,p-1} is accepted).
  -> legendre(p)
    if p <= 2 || p.even?
      raise "Int#legendre: p must be an odd prime"
    a = self % p
    if a < 0
      a = a + p
    if a == 0
      return 0
    s = a.modpow((p - 1) / 2, p)
    if s == 1
      return 1
    if s == p - 1
      return -1
    raise "Int#legendre: Euler criterion returned an invalid value"

  # Number of bits in the two's-complement representation, excluding sign
  # (Ruby Integer#bit_length): 0.bit_length == 0, 255 -> 8, 256 -> 9,
  # -256 -> 8. Uses hardware clz for 48-bit immediates and delegates BigInt
  # receivers to the limb-native runtime implementation.
  -> bit_length
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      bl_v = ($value & 0xFFFFFFFFFFFF) ## i64
      if (bl_v & 0x800000000000) != 0
        bl_v = (0 - (bl_v - 281_474_976_710_656)) - 1
      if bl_v == 0
        return 0
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | (64 - ccall_nobox("__w_bit_ctlz_u64", bl_v ## u64))) ## i64)
    ccall("w_bigint_bit_length", self)

  # Number of 1 bits in the magnitude (Python int.bit_count): 0 -> 0,
  # 255 -> 8, -255 -> 8. Uses hardware ctpop for 48-bit immediates and
  # delegates BigInt receivers to the limb-native runtime implementation.
  -> popcount
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      pc_v = ($value & 0xFFFFFFFFFFFF) ## i64
      if (pc_v & 0x800000000000) != 0
        pc_v = 0 - (pc_v - 281_474_976_710_656)
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | ccall_nobox("__w_bit_ctpop_u64", pc_v ## u64)) ## i64)
    ccall("w_bigint_popcount", self)

  # Alias of popcount (Python spelling).
  -> bit_count
    self.popcount

  -> powmod(exponent, modulus)
    self.modpow(exponent, modulus)

  -> divmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      dm_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (dm_b & 0x800000000000) != 0
        dm_b -= 281_474_976_710_656
      dm_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (dm_a & 0x800000000000) != 0
        dm_a -= 281_474_976_710_656
      if dm_b != 0 && !(dm_a == -140_737_488_355_328 && dm_b == -1)
        dm_q = dm_a / dm_b
        dm_r = dm_a - dm_q * dm_b
        if dm_r != 0 && ((dm_r ^ dm_b) < 0)
          dm_q -= 1
          dm_r += dm_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return [wvalue_from_bits((tag | (dm_q & 0xFFFFFFFFFFFF)) ## i64), wvalue_from_bits((tag | (dm_r & 0xFFFFFFFFFFFF)) ## i64)]
    ccall("w_bigint_divmod", self, other)

  -> tdiv(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      td_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (td_b & 0x800000000000) != 0
        td_b -= 281_474_976_710_656
      td_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (td_a & 0x800000000000) != 0
        td_a -= 281_474_976_710_656
      if td_b != 0 && !(td_a == -140_737_488_355_328 && td_b == -1)
        td_q = td_a / td_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (td_q & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_tdiv", self, other)

  -> tmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      tm_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (tm_b & 0x800000000000) != 0
        tm_b -= 281_474_976_710_656
      if tm_b != 0
        tm_a = ($value & 0xFFFFFFFFFFFF) ## i64
        if (tm_a & 0x800000000000) != 0
          tm_a -= 281_474_976_710_656
        tm_r = tm_a % tm_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (tm_r & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_tmod", self, other)

  -> tdivmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      td_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (td_b & 0x800000000000) != 0
        td_b -= 281_474_976_710_656
      td_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (td_a & 0x800000000000) != 0
        td_a -= 281_474_976_710_656
      if td_b != 0 && !(td_a == -140_737_488_355_328 && td_b == -1)
        td_q = td_a / td_b
        td_r = td_a - td_q * td_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return [wvalue_from_bits((tag | (td_q & 0xFFFFFFFFFFFF)) ## i64), wvalue_from_bits((tag | (td_r & 0xFFFFFFFFFFFF)) ## i64)]
    ccall("w_bigint_tdivmod", self, other)

  -> fdiv(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      fd_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (fd_b & 0x800000000000) != 0
        fd_b -= 281_474_976_710_656
      fd_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (fd_a & 0x800000000000) != 0
        fd_a -= 281_474_976_710_656
      if fd_b != 0 && !(fd_a == -140_737_488_355_328 && fd_b == -1)
        fd_q = fd_a / fd_b
        fd_r = fd_a - fd_q * fd_b
        if fd_r != 0 && ((fd_r ^ fd_b) < 0)
          fd_q -= 1
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (fd_q & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_fdiv", self, other)

  -> fmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      fm_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (fm_b & 0x800000000000) != 0
        fm_b -= 281_474_976_710_656
      if fm_b != 0
        fm_a = ($value & 0xFFFFFFFFFFFF) ## i64
        if (fm_a & 0x800000000000) != 0
          fm_a -= 281_474_976_710_656
        fm_r = fm_a % fm_b
        if fm_r != 0 && ((fm_r ^ fm_b) < 0)
          fm_r += fm_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (fm_r & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_fmod", self, other)

  -> fdivmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      fd_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (fd_b & 0x800000000000) != 0
        fd_b -= 281_474_976_710_656
      fd_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (fd_a & 0x800000000000) != 0
        fd_a -= 281_474_976_710_656
      if fd_b != 0 && !(fd_a == -140_737_488_355_328 && fd_b == -1)
        fd_q = fd_a / fd_b
        fd_r = fd_a - fd_q * fd_b
        if fd_r != 0 && ((fd_r ^ fd_b) < 0)
          fd_q -= 1
          fd_r += fd_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return [wvalue_from_bits((tag | (fd_q & 0xFFFFFFFFFFFF)) ## i64), wvalue_from_bits((tag | (fd_r & 0xFFFFFFFFFFFF)) ## i64)]
    ccall("w_bigint_fdivmod", self, other)

  -> cdiv(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      cd_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (cd_b & 0x800000000000) != 0
        cd_b -= 281_474_976_710_656
      cd_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (cd_a & 0x800000000000) != 0
        cd_a -= 281_474_976_710_656
      if cd_b != 0 && !(cd_a == -140_737_488_355_328 && cd_b == -1)
        cd_q = cd_a / cd_b
        cd_r = cd_a - cd_q * cd_b
        if cd_r != 0 && ((cd_r ^ cd_b) >= 0)
          cd_q += 1
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (cd_q & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_cdiv", self, other)

  -> cmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      cm_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (cm_b & 0x800000000000) != 0
        cm_b -= 281_474_976_710_656
      if cm_b != 0
        cm_a = ($value & 0xFFFFFFFFFFFF) ## i64
        if (cm_a & 0x800000000000) != 0
          cm_a -= 281_474_976_710_656
        cm_r = cm_a % cm_b
        if cm_r != 0 && ((cm_r ^ cm_b) >= 0)
          cm_r -= cm_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (cm_r & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_cmod", self, other)

  -> cdivmod(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      cd_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (cd_b & 0x800000000000) != 0
        cd_b -= 281_474_976_710_656
      cd_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (cd_a & 0x800000000000) != 0
        cd_a -= 281_474_976_710_656
      if cd_b != 0 && !(cd_a == -140_737_488_355_328 && cd_b == -1)
        cd_q = cd_a / cd_b
        cd_r = cd_a - cd_q * cd_b
        if cd_r != 0 && ((cd_r ^ cd_b) >= 0)
          cd_q += 1
          cd_r -= cd_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return [wvalue_from_bits((tag | (cd_q & 0xFFFFFFFFFFFF)) ## i64), wvalue_from_bits((tag | (cd_r & 0xFFFFFFFFFFFF)) ## i64)]
    ccall("w_bigint_cdivmod", self, other)

  -> divexact(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      de_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (de_b & 0x800000000000) != 0
        de_b -= 281_474_976_710_656
      de_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (de_a & 0x800000000000) != 0
        de_a -= 281_474_976_710_656
      if de_b != 0 && !(de_a == -140_737_488_355_328 && de_b == -1)
        de_q = de_a / de_b
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return wvalue_from_bits((tag | (de_q & 0xFFFFFFFFFFFF)) ## i64)
    ccall("w_bigint_divexact", self, other)

  -> divisible?(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      dv_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (dv_a & 0x800000000000) != 0
        dv_a -= 281_474_976_710_656
      dv_d = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (dv_d & 0x800000000000) != 0
        dv_d -= 281_474_976_710_656
      if dv_d == 0
        return dv_a == 0
      return (dv_a % dv_d) == 0
    ccall("w_bigint_divisible_p", self, other)

  -> divisible_by?(other)
    self.divisible?(other)

  -> congruent?(c, d)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((c$value >> 48) & 0xFFFF) == 0xFFFA && ((d$value >> 48) & 0xFFFF) == 0xFFFA
      cg_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (cg_a & 0x800000000000) != 0
        cg_a -= 281_474_976_710_656
      cg_c = (c$value & 0xFFFFFFFFFFFF) ## i64
      if (cg_c & 0x800000000000) != 0
        cg_c -= 281_474_976_710_656
      cg_d = (d$value & 0xFFFFFFFFFFFF) ## i64
      if (cg_d & 0x800000000000) != 0
        cg_d -= 281_474_976_710_656
      cg_diff = cg_a - cg_c
      if cg_d == 0
        return cg_diff == 0
      return (cg_diff % cg_d) == 0
    ccall("w_bigint_congruent_p", self, c, d)

  -> isqrt_rem
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      ir_n = ($value & 0xFFFFFFFFFFFF) ## i64
      if (ir_n & 0x800000000000) == 0
        ir_r = Math.sqrt(ir_n ## f64) ## i64
        ir_rem = ir_n - ir_r * ir_r
        tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
        return [wvalue_from_bits((tag | (ir_r & 0xFFFFFFFFFFFF)) ## i64), wvalue_from_bits((tag | (ir_rem & 0xFFFFFFFFFFFF)) ## i64)]
    ccall("w_bigint_isqrt_rem", self)

  -> iroot(n)
    ccall("w_bigint_iroot", self, n)

  -> iroot_rem(n)
    ccall("w_bigint_iroot_rem", self, n)

  -> perfect_square?
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      ps_n = ($value & 0xFFFFFFFFFFFF) ## i64
      if (ps_n & 0x800000000000) != 0
        return false
      ps_r = Math.sqrt(ps_n ## f64) ## i64
      return ps_r * ps_r == ps_n
    ccall("w_bigint_perfect_square_p", self)

  -> perfect_power?
    ccall("w_bigint_perfect_power_p", self)

  -> gcdext(other)
    ccall("w_bigint_gcdext", self, other)

  -> kronecker(b)
    ccall("w_bigint_kronecker", self, b)

  -> nextprime
    ccall("w_bigint_nextprime", self)

  -> next_prime
    ccall("w_bigint_nextprime", self)

  -> prevprime
    ccall("w_bigint_prevprime", self)

  -> prev_prime
    ccall("w_bigint_prevprime", self)

  -> remove_factor(f)
    ccall("w_bigint_remove", self, f)

  -> factorial
    ccall("w_bigint_fac_ui", self)

  -> double_factorial
    ccall("w_bigint_2fac_ui", self)

  -> multifactorial(m)
    ccall("w_bigint_mfac_uiui", self, m)

  -> primorial
    ccall("w_bigint_primorial_ui", self)

  -> binomial(k)
    ccall("w_bigint_bin_ui", self, k)

  -> choose(k)
    ccall("w_bigint_bin_ui", self, k)

  -> fib
    ccall("w_bigint_fib_ui", self)

  -> fib2
    ccall("w_bigint_fib2_ui", self)

  -> lucas
    ccall("w_bigint_lucnum_ui", self)

  -> lucas2
    ccall("w_bigint_lucnum2_ui", self)

  -> sizeinbase(base = 10)
    ccall("w_bigint_sizeinbase", self, base)

  -> size_in_base(base = 10)
    ccall("w_bigint_sizeinbase", self, base)

  -> hamdist(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      hd_x = (($value ^ other$value) & 0xFFFFFFFFFFFF) ## i64
      if (hd_x & 0x800000000000) != 0
        return -1
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | ccall_nobox("__w_bit_ctpop_u64", hd_x ## u64)) ## i64)
    ccall("w_bigint_hamdist", self, other)

  -> hamming_distance(other)
    self.hamdist(other)

  -> scan1(start = 0)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((start$value >> 48) & 0xFFFF) == 0xFFFA
      s1_st = (start$value & 0xFFFFFFFFFFFF) ## i64
      if (s1_st & 0x800000000000) != 0
        s1_st = 0
      s1_v = ($value & 0xFFFFFFFFFFFF) ## i64
      if s1_st >= 48
        if (s1_v & 0x800000000000) != 0
          return start
        return -1
      s1_sh = s1_v >> s1_st
      if s1_sh == 0
        return -1
      s1_idx = s1_st + ccall_nobox("__w_bit_cttz_u64", s1_sh ## u64)
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | s1_idx) ## i64)
    ccall("w_bigint_scan1", self, start)

  -> scan0(start = 0)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((start$value >> 48) & 0xFFFF) == 0xFFFA
      s0_st = (start$value & 0xFFFFFFFFFFFF) ## i64
      if (s0_st & 0x800000000000) != 0
        s0_st = 0
      s0_v = (($value ^ 0xFFFFFFFFFFFF) & 0xFFFFFFFFFFFF) ## i64
      if s0_st >= 48
        if (s0_v & 0x800000000000) != 0
          return start
        return -1
      s0_sh = s0_v >> s0_st
      if s0_sh == 0
        return -1
      s0_idx = s0_st + ccall_nobox("__w_bit_cttz_u64", s0_sh ## u64)
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | s0_idx) ## i64)
    ccall("w_bigint_scan0", self, start)

  -> trailing_zeros
    if (($value >> 48) & 0xFFFF) == 0xFFFA
      tz_v = ($value & 0xFFFFFFFFFFFF) ## i64
      if tz_v == 0
        return 0
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | ccall_nobox("__w_bit_cttz_u64", tz_v ## u64)) ## i64)
    ccall("w_bigint_trailing_zeros", self)

  -> tstbit(idx)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((idx$value >> 48) & 0xFFFF) == 0xFFFA
      tb_idx = (idx$value & 0xFFFFFFFFFFFF) ## i64
      if (tb_idx & 0x800000000000) != 0
        return 0
      tb_shift = tb_idx > 47 ? 47 : tb_idx
      tb_bit = (($value >> tb_shift) & 1) ## i64
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | tb_bit) ## i64)
    ccall("w_bigint_tstbit", self, idx)

  -> bit_set?(idx)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((idx$value >> 48) & 0xFFFF) == 0xFFFA
      bs_idx = (idx$value & 0xFFFFFFFFFFFF) ## i64
      if (bs_idx & 0x800000000000) != 0
        return false
      bs_shift = bs_idx > 47 ? 47 : bs_idx
      return (($value >> bs_shift) & 1) != 0
    ccall("w_bigint_bit_set_p", self, idx)

  -> setbit(idx)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((idx$value >> 48) & 0xFFFF) == 0xFFFA
      sb_idx = (idx$value & 0xFFFFFFFFFFFF) ## i64
      if (sb_idx & 0x800000000000) == 0 && sb_idx < 47
        return wvalue_from_bits(($value | (1 << sb_idx)) ## i64)
    ccall("w_bigint_setbit", self, idx)

  -> clrbit(idx)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((idx$value >> 48) & 0xFFFF) == 0xFFFA
      cb_idx = (idx$value & 0xFFFFFFFFFFFF) ## i64
      if (cb_idx & 0x800000000000) == 0 && cb_idx < 47
        cb_mask = 1 << cb_idx
        return wvalue_from_bits((($value | cb_mask) ^ cb_mask) ## i64)
    ccall("w_bigint_clrbit", self, idx)

  -> combit(idx)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((idx$value >> 48) & 0xFFFF) == 0xFFFA
      xb_idx = (idx$value & 0xFFFFFFFFFFFF) ## i64
      if (xb_idx & 0x800000000000) == 0 && xb_idx < 47
        return wvalue_from_bits(($value ^ (1 << xb_idx)) ## i64)
    ccall("w_bigint_combit", self, idx)

  -> cmpabs(other)
    if (($value >> 48) & 0xFFFF) == 0xFFFA && ((other$value >> 48) & 0xFFFF) == 0xFFFA
      ca_a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (ca_a & 0x800000000000) != 0
        ca_a = 281_474_976_710_656 - ca_a
      ca_b = (other$value & 0xFFFFFFFFFFFF) ## i64
      if (ca_b & 0x800000000000) != 0
        ca_b = 281_474_976_710_656 - ca_b
      if ca_a == ca_b
        return 0
      return ca_a > ca_b ? 1 : -1
    ccall("w_bigint_cmpabs", self, other)

  -> to_bytes(order = :big)
    ccall("w_bigint_to_bytes", self, order)

  -> .from_bytes(bytes, order = :big)
    ccall("w_bigint_from_bytes", bytes, order)
