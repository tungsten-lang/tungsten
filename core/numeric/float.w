# http://www.jhauser.us/arithmetic/SoftFloat.html
# http://en.wikipedia.org/wiki/IEEE_floating_point
#
# Supports rounding-direction attributes mandated by the IEEE 754-2008 standard
# * round_ties_to_even
# * round_toward_positive
# * round_toward_negative
# * round_toward_zero
+ Float < Real

  ## Rounding — concrete IEEE-aware via the Math runtime primitives.

  -> floor
    Math.floor(self)

  -> ceil
    Math.ceil(self)

  -> round
    Math.round(self)

  -> truncate
    Math.trunc(self)

  ## IEEE-754 classification (runtime intrinsics).

  # True for NaN values (the IEEE 754 not-a-number bit pattern).
  -> nan?

  # True for ±∞.
  -> infinite?

  # True iff finite (not NaN, not ±∞).
  -> finite?

  ## Format metadata — concrete subclasses supply concrete values.

  # Total bits in the format (16 / 32 / 64 / 80 / 128 / 256).
  -> .bits

  # Explicitly-stored mantissa bits (the implicit leading 1 is *not*
  # counted; for Float80 this is the explicit fraction beyond the
  # integer bit).
  -> .mantissa_bits

  # Exponent bits.
  -> .exponent_bits

  # Exponent bias for IEEE 754 binaryN: 2^(exponent_bits − 1) − 1.
  -> .bias
    2 ** (self.exponent_bits - 1) - 1
