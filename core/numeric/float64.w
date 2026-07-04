# The IEEE 754-2008 standard specifies **binary64** as having:
# * Sign bit: 1 bit
# * Exponent width: 11 bits (bias 1023)
# * Significand precision: 53 bits (52 explicitly stored, 1 inferred from exponent)
#
# Commonly referred to as "double precision".
#
#     sign    exponent            fraction
#        |       |                |
#       [0][01111100000][0100000000000000000000000000000000000000000000000000]
#       [1][<----11--->][<--------52---------------------------------------->]
#
#     3ff0 0000 0000 0000 = 1
#     3ff0 0000 0000 0001 ≈ 1.0000000000000002, smallest number > 1
#     3ff0 0000 0000 0002 ≈ 1.0000000000000004
#     4000 0000 0000 0000 = 2
#     c000 0000 0000 0000 = -2
#
#     0000 0000 0000 0001 = 2⁻¹⁰²²⁻⁵² = 2⁻¹⁰⁷⁴
#                         ≈ 4.9406564584124654 × 10⁻³²⁴ (min subnormal positive double)
#
#     000f ffff ffff ffff = 2⁻¹⁰²² - 2⁻¹⁰⁷⁴
#                         ≈ 2.2250738585072009 × 10⁻³⁰⁸ (max subnormal double)
#
#     0010 0000 0000 0000 = 2⁻¹⁰²²
#                         ≈ 2.2250738585072014 × 10⁻³⁰⁸ (min normal positive double)
#
#     7fef ffff ffff ffff = (1 + (1 - 2⁻⁵²)) × 2¹⁰²³
#                         ≈ 1.7976931348623157 × 10³⁰⁸ (max double)
#
#     0000 0000 0000 0000 = 0
#     8000 0000 0000 0000 = -0
#
#     7ff0 0000 0000 0000 = Infinity
#     fff0 0000 0000 0000 = -Infinity
#     7fff ffff ffff ffff = NaN
+ Float64 < Float
  -> .bits 64
  -> .mantissa_bits 52
  -> .exponent_bits 11
