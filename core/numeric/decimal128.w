# The IEEE 754-2008 standard specifies **decimal128** as having:
# * Sign bit: 1 bit
# * Combination: 5 bits
# * Exponent continuation: 12 bits
# * Coefficient continuation: 110 bits
#
# Supports 34 decimal digits of significand and an exponent range of -6143 to +6144.
# _i.e._ ±0.000_000_000_000_000_000_000_000_000_000_000 × 10⁻⁶¹⁴³
#     to ±9.999_999_999_999_999_999_999_999_999_999_999 × 10⁶¹⁴⁴.
+ Decimal128 < Decimal
