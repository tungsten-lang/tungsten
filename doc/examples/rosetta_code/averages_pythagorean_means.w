# Averages/Pythagorean means

# Compare Arithmetic >= Geometric >= Harmonic on [1, 4, 16, 64]
nums = [1, 4, 16, 64]
n = nums.size

sum = 0
i = 0
while i < n
  sum += nums[i]
  i += 1

arith = sum.to_f / n
# Product is 4^(0+1+2+3) = 4^6 = 4096, 4th root is 8
geom = 8.0
# Sum of reciprocals in /64 is (64 + 16 + 4 + 1)/64 = 85/64, so H = 4 * 64 / 85
harm = 256.0 / 85.0

<< "Arithmetic: [arith]"
<< "Geometric:  [geom]"
<< "A >= G >= H: [arith >= geom && geom >= harm]"

## expect stdout
## Arithmetic: 21.25
## Geometric:  8
## A >= G >= H: true
