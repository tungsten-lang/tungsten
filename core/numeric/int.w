# Int — the exact, arbitrary-precision integer family.
#
# Integer is its inline-i48 representation and BigInt is its heap-backed
# representation. Public arithmetic may move between those concrete classes;
# shared algorithms here must therefore remain representation-independent.
+ Int < Real
  # @todo other operators. NB: the bodyless `-> +/1` arity-suffix form does
  # NOT parse for an operator name (only `-> name/N` on identifiers does), so
  # it silently failed to load this whole file — leaving Int undefined and
  # BigInt (< Int) without any of its inherited methods. Use the param form.
  -> +(other)

  # Base-10 digits, least-significant first (Ruby Integer#digits): 1234 ->
  # [4,3,2,1], 0 -> [0]. The former `to_s.split` returned nil (split needs a
  # separator). Rides the promoting % / / so it is exact for BigInt (Int is
  # BigInt's base), which now reaches this after the dispatch fix.
  -> digits
    if self < 0
      raise "Int#digits: negative receiver"
    if self == 0
      return [0]
    dg_out = []
    dg_n = self
    while dg_n > 0
      dg_out.push(dg_n % 10)
      dg_n = dg_n / 10
    dg_out

  -> digits(base)
    if self < 0
      raise "Int#digits: negative receiver"
    if self == 0
      return [0]
    db_out = []
    db_n = self
    while db_n > 0
      db_out.push(db_n % base)
      db_n = db_n / base
    db_out

  # Yield each base-10 digit (least-significant first), returning self.
  -> each_digit(&)
    digits.each -> (d)
      &(d)
    self

  ## Small-integer predicates. Universal `zero?` and `one?` live on Number;
  ## these are integer-only because they're only meaningful for discrete
  ## values (no float-rounding surprises).

  -> two?
    self == 2

  -> three?
    self == 3

  -> four?
    self == 4

  -> prev
    self - 1

  -> succ
    self + 1

  # Alias of succ with a direct body: a bare `succ` call would cost a second
  # dynamic dispatch on every `.next`, which the BigInt runtime-to-core port
  # measured as a 6-8% public regression.
  -> next
    self + 1

  -> to_s(base = 10)

  # Convert through the shared numeric boundary. A bare `0.0` is an exact
  # Decimal in Tungsten, so implementing this as `self + 0.0` would return the
  # wrong class under the source interpreter even though native IC dispatch
  # correctly produces a machine Float.
  -> to_f
    ccall("w_num_to_float", self)

  ## Parity / divisibility.

  -> even?
    self % 2 == 0

  -> odd?
    self % 2 != 0

  -> divisible_by?/1
    self % @1 == 0

  ## Number-theoretic.

  # n! — product of 1..n. 0! = 1! = 1.
  -> factorial() 1
    (2..self).each -> acc *= item

  # Mirrors Integer#factor for heap BigInt values (BigInt < Int). Keeping the
  # implementation in the shared value object gives both integer towers the
  # same exact semantics and presentation.
  -> factor
    IntegerFactorization.new(self)

  # Greatest common divisor — iterative Euclidean.
  -> gcd/1
    a = abs
    b = @1.abs
    while b > 0
      t = b
      b = a % b
      a = t
    a

  # Least common multiple. Divide out the gcd before multiplying so common
  # factors do not create a needlessly large intermediate. By convention any
  # lcm with zero is zero, including lcm(0, 0).
  -> lcm/1
    return 0 if self == 0 || @1 == 0
    ((self / gcd(@1)) * @1).abs

  # Modular exponentiation: (self ** e) mod m — the inner operation of
  # Fermat/PRP screening and Proth proofs. Routed to the runtime intrinsic
  # `bigint_powmod_any` (runtime/runtime.c): sliding-window square-and-multiply
  # through the Montgomery/Barrett modular-multiplication machinery, walking
  # e's bits straight off its limbs. Result is in [0, |m|). A negative
  # exponent keeps the former .w loop's behavior exactly: the ladder never
  # ran, so the result is 1 (after the `self % m` step, preserving its
  # division error for m == 0).
  -> modpow(e, m)
    if e < 0
      mp_b = self % m
      return 1
    ccall("bigint_powmod_any", self, e, m)

  # Ruby-style Integer#pow: pow(e) == self ** e; pow(e, m) == modpow(e, m).
  # Matches Integer#pow on small ints so `n.pow(e, m)` works for any integer.
  -> pow(e)
    self ** e

  -> pow(e, m)
    modpow(e, m)

  # Modular inverse via extended Euclidean. Mirrors Integer#invmod so the
  # same call works on any integer class. Raises when not invertible.
  -> invmod(modulus)
    if modulus == 0
      raise "Int#invmod: modulus must be nonzero"
    m = modulus < 0 ? 0 - modulus : modulus
    if m == 1
      return 0
    a = self % m
    if a < 0
      a = a + m
    t = 0
    newt = 1
    r = m
    newr = a
    while newr != 0
      q = r / newr
      tmp_t = newt
      newt = t - q * newt
      t = tmp_t
      tmp_r = newr
      newr = r - q * newr
      r = tmp_r
    if r > 1
      raise "Int#invmod: not invertible"
    if t < 0
      t = t + m
    t

  # Legendre symbol (self/p). Mirrors Integer#legendre.
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
  # (Ruby Integer#bit_length): 0 -> 0, 255 -> 8, 256 -> 9, -256 -> 8. Halving
  # `/ 2` (not `>>`, which is i64-only) keeps it exact for BigInt receivers.
  -> bit_length
    bl_n = self < 0 ? self.abs - 1 : self
    bl = 0
    while bl_n > 0
      bl_n = bl_n / 2
      bl += 1
    bl

  # Integer square root: largest k with k*k <= self (Ruby Integer#isqrt).
  # Newton's method from a digit-count overestimate; exact for BigInt via the
  # promoting / and ** operators. Mirrors Integer#isqrt so it works for any
  # integer (Integer and BigInt are the two concrete Int representations).
  -> isqrt
    if self < 0
      raise "Int#isqrt: negative receiver"
    if self < 2
      return self
    # 2^ceil(b/2) >= sqrt(self) for b = bit_length: a tight overestimate that
    # costs one shift.  (The former 10^(digits/2) guess paid a full decimal
    # conversion just to count digits.)
    sq_x = 1 << ((self.bit_length + 1) / 2)
    sq_y = (sq_x + self / sq_x) / 2
    while sq_y < sq_x
      sq_x = sq_y
      sq_y = (sq_x + self / sq_x) / 2
    sq_x

  # Is this a prime number? Tiered by magnitude in the runtime intrinsic
  # `w_ic_int_prime_q` (runtime/runtime.c): a small-prime screen for tiny n,
  # prime trial division for moderate n, deterministic Miller-Rabin for
  # large n, and an exact Lucas-Lehmer proof for Mersenne numbers 2^p-1.
  # Bodyless because integer literals are NaN-boxed primitives with no class
  # pointer — they dispatch C intrinsics, not .w method bodies, the same way
  # `gcd`/`sqrt` do.
  -> prime?

  # Like `prime?` but assumes the receiver is coprime to 6 (a 12m+{1,5,7,11}
  # wheel candidate); it skips the redundant ÷2/÷3 screen, then runs the shared
  # inner test (division-free prime-factor scan for n ≤ 1e6, Montgomery Miller-Rabin
  # above). ONLY valid for coprime-to-6 inputs — a multiple of 2 or 3 would be
  # misreported prime. u64-only. Same NaN-boxed-intrinsic story as `prime?`.
  -> prime_12k?

  # Like `prime_12k?` but assumes coprimality to 30 (a mod-30 wheel candidate:
  # residues 1,7,11,13,17,19,23,29); skips the ÷2/÷3/÷5 screen, then the shared
  # inner test. ONLY valid for such inputs — a multiple of 2, 3, or 5 would be
  # misreported. u64.
  -> prime_30k?
