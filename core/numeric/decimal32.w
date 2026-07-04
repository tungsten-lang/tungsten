# The IEEE 754-2008 standard specifies decimal32 as having:
# * Sign bit: 1 bit
# * Combination: 5 bits
# * Exponent continuation: 6 bits
# * Coefficient continuation: 20 bits
#
# Supports 7 decimal digits of significand and an exponent range of -95 to +96.
# _i.e._ ±0.000_000 × 10⁻⁹⁵ to ±9.999_999 × 10⁹⁶.
+ Decimal32 < Decimal
