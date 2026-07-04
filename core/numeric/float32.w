# The IEEE 754-2008 standard specifies binary32 as having:
# * Sign bit: 1 bit
# * Exponent width: 8 bits (bias 127)
# * Significand precision: 24 bits (23 explicitly stored, 1 inferred from exponent)
#
# Commonly referred to as "single precision".
#
#     sign    exp               fraction
#        |     |                |
#       [0][01111100][01000000000000000000000]
#       [1][<--8--->][<---------23---------->]
#
#     3f80 0000 = 1
#     c000 0000 = -2
#
#     7f7f ffff ≈ 3.4028234 x 10³⁸ (max single precision)
#
#     0000 0000 = 0
#     8000 0000 = -0
#
#     7f80 0000 = Infinity
#     ff80 0000 = -Infinity
+ Float32 < Float
  -> .bits 32
  -> .mantissa_bits 23
  -> .exponent_bits 8
