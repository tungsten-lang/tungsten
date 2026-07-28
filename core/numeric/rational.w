# Rational — exact fractions stored as a reduced numerator/denominator pair.
#
# Small values use a signed 22-bit numerator and unsigned 22-bit denominator
# directly in the WValue. Larger values transparently promote to a heap object
# whose numerator and denominator use the arbitrary-precision Integer tower.
# Both representations have the same public class and dispatch surface.
+ Rational < Real

  # Constructors are runtime-backed so they can return the packed value
  # or its heap-backed overflow tier instead of an ordinary class instance.
  -> new(numerator, denominator = 1)

  -> .coerce(value)
    return value if value.class_name == "Rational"
    Rational.new(value, 1)

  -> numerator
    ccall("w_rational_numerator", self)

  -> denominator
    ccall("w_rational_denominator", self)

  -> to_r
    self

  -> to_a
    [numerator, denominator]

  -> to_i
    numerator / denominator

  -> truncate
    to_i

  -> floor
    n = numerator
    d = denominator
    q = n / d
    n < 0 && n % d != 0 ? q - 1 : q

  -> ceil
    n = numerator
    d = denominator
    q = n / d
    n > 0 && n % d != 0 ? q + 1 : q

  # Half values round away from zero, matching the runtime's other scalar
  # round operations.
  -> round
    n = numerator
    d = denominator
    q = n / d
    r = n % d
    if r < 0
      return (0 - r) * 2 >= d ? q - 1 : q
    r * 2 >= d ? q + 1 : q

  -> to_f
    self + ~0.0

  -> zero?
    numerator == 0

  -> one?
    numerator == denominator

  -> negative?
    numerator < 0

  -> positive?
    numerator > 0

  -> abs
    negative? ? 0 - self : self

  -> negate
    0 - self

  -> reciprocal
    1 / self

  -> inv
    reciprocal

  # Re-run the runtime reducer. This is useful for values decoded from an
  # older artifact; new literals, constructors, and arithmetic are already
  # canonical.
  -> normalize
    self + 0

  -> reduced?
    numerator.abs.gcd(denominator) == 1

  -> integer?
    numerator % denominator == 0

  -> proper?
    numerator.abs < denominator

  -> unit_fraction?
    numerator.abs == 1

  -> fractional_part
    self - truncate

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    to_s
