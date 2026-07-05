-> mod_mul(a, b, mod) (i64 i64 i64) i64
  result = 0
  x = a % mod
  y = b

  while y > 0
    if y % 2 == 1
      result = (result + x) % mod
    x = (x * 2) % mod
    y = y / 2

  result

-> mod_pow(base, exp, mod) (i64 i64 i64)  i64
  result = 1
  value = base % mod
  power = exp

  while power > 0
    if power % 2 == 1
      result = mod_mul(result, value, mod)
    value = mod_mul(value, value, mod)
    power = power / 2

  result

-> mr_pass?(n, d, s, a) (i64 i64 i64 i64) bool
  base = a % n
  if base == 0
    return true

  x = mod_pow(base, d, n)
  if x == 1 || x == n - 1
    return true

  r = 1
  while r < s
    x = mod_mul(x, x, n)
    if x == n - 1
      return true
    r += 1

  false

-> prime?(n) (i64) bool
  if n >= 33_000_000_000
    mr_prime?(n)
  else
    fast_prime?(n)

BASES = [2, 325, 9375, 28178, 450775, 9780504, 1795265022]
SMALL_PRIMES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]

# Miller-Rabin primality test for 64-bit integers
-> mr_prime?(n) (i64) bool
  return false if n < 2

  divisor = SMALL_PRIMES.find -> (p) n % p == 0

  return n == divisor if divisor

  d = n - 1
  s = 0
  while d % 2 == 0
    d = d / 2
    s += 1

  BASES.all? -> (base)
    mr_pass?(n, d, s, base)

-> fast_prime?(n) (i64) bool
  return false if n < 2
  return true  if n == 2 || n == 3
  return false if (n % 2 == 0) || (n % 3 == 0)

  limit = n.sqrt.to_i
  i = 5
  while i <= limit
    return false if (n % i == 0) || (n % (i + 2) == 0)
    i += 6

  return true


-> count_primes
  count = 1
  3..120000000 -> (n)
    count++ if prime?(n)

  count

<< count_primes
