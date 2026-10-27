# Miller-Rabin primality test

-> mod_pow(base, exp, mod)
  result = 1
  b = base % mod
  e = exp
  while e > 0
    if e % 2 == 1
      result = (result * b) % mod
    b = (b * b) % mod
    e /= 2
  result

-> miller_rabin?(n)
  if n < 2
    return false
  if n == 2 || n == 3
    return true
  if n % 2 == 0
    return false
  d = n - 1
  s = 0
  while d % 2 == 0
    d /= 2
    s += 1
  bases = [2, 3, 5, 7, 11, 13, 17, 19, 23]
  i = 0
  while i < bases.size
    a = bases[i]
    if a < n
      x = mod_pow(a, d, n)
      if x != 1 && x != n - 1
        composite = true
        r = 1
        while r < s
          x = (x * x) % n
          if x == n - 1
            composite = false
            break
          r += 1
        if composite
          return false
    i += 1
  true

primes = []
(2..100).each -> (n)
  if miller_rabin?(n)
    primes.push(n)

<< primes

## expect stdout
## [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]
