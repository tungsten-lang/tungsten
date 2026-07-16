# http://www.jhauser.us/arithmetic/SoftFloat.html
# http://en.wikipedia.org/wiki/IEEE_floating_point
#
# Supports rounding-direction attributes mandated by the IEEE 754-2008 standard
# * round_ties_to_even
# * round_toward_positive
# * round_toward_negative
# * round_toward_zero
+ Float < Real

  # Conversion to Float is receiver identity. Preserve every valid Float
  # WValue bit pattern, including signed zero and dispatch-safe raw NaNs.
  -> to_f
    self

  # Float WValues store the IEEE-754 word plus 2^48. Work on the unbiased
  # magnitude so signed zero, infinities, and every NaN payload retain the
  # runtime handlers' exact semantics.
  -> abs
    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64
    if magnitude > (0x7FF0000000000000 ## i64)
      return wvalue_from_bits(0x7FF9000000000000 ## i64)
    wvalue_from_bits((magnitude + (0x0001000000000000 ## i64)) ## i64)

  ## Rounding — concrete IEEE-aware via the Math runtime primitives.

  # Math's libm wrappers deliberately return Float. The historical Float
  # instance handlers return Integer, including the target's established
  # int64 conversion for NaN, infinities, and values outside int64 range.
  # Keep that exact boundary explicit: raw conversion followed by checked
  # w_int boxing also preserves promotion of INT64_MIN/MAX beyond i48.

  -> floor
    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.floor(self)))

  -> ceil
    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.ceil(self)))

  -> round
    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.round(self)))

  # Preserve libm sqrt behavior, including -0, infinities, and canonical
  # NaN boxing, through the same direct Math primitive used elsewhere.
  -> sqrt
    Math.sqrt(self)

  # Float's native Numeric#sq handler is exactly the universal product.
  # Defining the override here avoids loading the full Number hierarchy for
  # a primitive receiver and gives lowering the shortest source body.
  -> sq
    self * self

  -> truncate
    Math.trunc(self)

  ## IEEE-754 classification (runtime intrinsics).

  # True for NaN values (the IEEE 754 not-a-number bit pattern).
  -> nan?
    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64
    magnitude > (0x7FF0000000000000 ## i64)

  # True for ±∞.
  -> infinite?
    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64
    magnitude == (0x7FF0000000000000 ## i64)

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
