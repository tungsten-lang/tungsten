# The IEEE 754-2008 standard specifies binary16 as having:
# * Sign bit: 1 bit
# * Exponent width: 5 bits (bias 15)
# * Significand precision: 11 bits (10 explicitly stored, 1 inferred from exponent)
#
# Commonly referred to as "half precision".
#
#     sign   exp       fraction
#        |    |        |
#       [0][01111][0100000000]
#       [1][<-5->][<---10--->]
#
#     0 01111 0000000000 = 1
#     0 01111 0000000001 = 1 + 2^-10 = 1.0009765625 (next smallest float after 1)
#     1 10000 0000000000 = -2
#
#     0 11110 1111111111 = 65504 (max half precision)
#
#     0 00001 0000000000 = 2⁻¹⁴        ≈ 6.10352 x 10⁻⁵ (minimum positive normal)
#     0 00000 1111111111 = 2⁻¹⁴ - 2⁻²⁴ ≈ 6.09756 x 10⁻⁵ (maximum subnormal)
#     0 00000 0000000001 = 2⁻²⁴        ≈ 5.96046 x 10⁻⁸ (minimum positive subnormal)
#
#     0 00000 0000000000 = 0
#     1 00000 0000000000 = -0
#
#     0 11111 0000000000 = Infinity
#     1 11111 0000000000 = -Infinity
+ Float16 < Float
  -> .bits 16
  -> .mantissa_bits 10
  -> .exponent_bits 5
