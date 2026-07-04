# Denormalized float64
#
# * Sign bit: 1 bit
# * Exponent width: 15 bits (bias 16383)
# * Integer part: 1 bit
# * Significand precision: 63 bits
#
# Commonly referred to as "double extended precision".
#
#     sign      exp         int   fraction
#        |       |           |    |
#       [0][011111000000000][1][010000000000000000000000000000000000000000000000000000000000000]
#       [1][<----15------->][1][<----63------------------------------------------------------->]
+ Float80 < Float
  # Float80 carries an explicit integer bit (unlike IEEE binaryN); the total
  # width is 1 (sign) + 15 (exp) + 1 (explicit integer) + 63 (fraction) = 80.
  # `.mantissa_bits` reports the explicit *fraction* (63), matching the
  # file's significand-precision convention.
  -> .bits 80
  -> .mantissa_bits 63
  -> .exponent_bits 15
