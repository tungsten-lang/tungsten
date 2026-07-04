# The IEEE 754-2008 standard specifies **binary128** as having:
# * Sign bit: 1 bit
# * Exponent width: 15 bits (bias 16383)
# * Significant precision: 113 bits (112 explicitly stored, 1 inferred from exponent)
#
# Commonly referred to as "quad precision".
#
#     sign      exp               fraction
#        |       |                |
#       [0][011111000000000][0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000]
#       [1][<----15------->][<----112------------------------------------------------------------------------------------------------------->]
+ Float128 < Float
  -> .bits 128
  -> .mantissa_bits 112
  -> .exponent_bits 15
