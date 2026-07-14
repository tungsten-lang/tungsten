+ Int < Real
  # @todo other operators
  -> +/1

  -> digits
    to_s.split

  -> each_digit
    to_s.split.each_char

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

  -> next
    succ

  -> to_s(base = 10)

  # Promote to Float via `self + 0.0` (not `self * 1.0` — multiplying integer
  # zero by a float literal silently stays boxed Int 0 instead of promoting
  # to Float 0.0, dying later with "expected numeric type" on first use in a
  # division; addition promotes zero correctly).
  #
  # KNOWN GAP (compiled binaries only): calling `.to_f` on a runtime Int in a
  # COMPILED (`-o`) program does not reach this body or the correct C
  # intrinsic (`w_ic_int_to_f` in runtime.c, which IS implemented correctly —
  # `w_box_double((double)w_as_int(r))`). It silently returns the receiver
  # unconverted instead of erroring, unlike a genuinely undefined method
  # (`.even?` on a runtime Int correctly raises "undefined method"). Likely a
  # calling-convention/boxing mismatch between how compiled code invokes the
  # `w_ic_int_table` intrinsics and how the interpreter does — needs deeper
  # investigation in the compiled call-dispatch path (not found in
  # compiler/lib/wire.w or lowering/calls.w after an initial search; the
  # `w_ic_int_table` registration in runtime.c has zero referencing call
  # sites anywhere under compiler/, so the actual compiled invocation
  # mechanism is elsewhere). Interpreted (`bin/tungsten file.w`, no `-o`)
  # correctly uses `w_ic_int_to_f`. Workaround for compiled code until fixed:
  # write `self + 0.0` inline at the call site rather than call `.to_f`.
  -> to_f
    self + 0.0

  ## Parity / divisibility.

  -> even?
    self % 2 == 0

  -> odd?
    self % 2 != 0

  -> divisible_by?/1
    self % @1 == 0

  ## Number-theoretic.

  # n! — product of 1..n. 0! = 1! = 1.
  -> factorial 1
    (2..self).each -> acc *= item

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

  # Modular exponentiation: (self ** e) mod m, via square-and-multiply.
  # Operands stay reduced mod m, so cost is e.bit_length squarings — the
  # inner operation of Fermat/PRP screening and Proth proofs. Cost is
  # dominated by the underlying bignum multiply.
  -> modpow(e, m)
    r = 1
    b = self % m
    x = e
    while x > 0
      if x.odd?
        r = (r * b) % m
      b = (b * b) % m
      x = x / 2
    r

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
