# The IEEE 754-2008 standard specifies decimal64 as having:
# * Sign bit: 1 bit
# * Combination: 5 bits
# * Exponent continuation: 8 bits
# * Coefficient continuation: 50 bits
#
# Supports 16 decimal digits of significand and an exponent range of -383 to +384.
# _i.e._ ±0.000_000_000_000_000 × 10⁻³⁸³ to ±9.999_999_999_999_999 × 10³⁸⁴.
+ Decimal64 < Decimal
