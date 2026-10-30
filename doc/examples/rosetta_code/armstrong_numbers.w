# Narcissistic decimal number (Armstrong numbers)

-> pow_int(base, exp)
  r = 1
  i = 0
  while i < exp
    r *= base
    i += 1
  r

-> armstrong?(n)
  if n == 0
    return true
  digits = []
  tmp = n
  while tmp > 0
    digits.push(tmp % 10)
    tmp /= 10
  k = digits.size
  sum = 0
  i = 0
  while i < k
    sum += pow_int(digits[i], k)
    i += 1
  sum == n

found = []
n = 0
while found.size < 20
  if armstrong?(n)
    found.push(n)
  n += 1

<< found

## expect stdout
## [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 153, 370, 371, 407, 1634, 8208, 9474, 54748, 92727, 93084]
