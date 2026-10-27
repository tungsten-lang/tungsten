# Carmichael 3 strong pseudoprimes

-> prime?(n)
  if n < 2
    return false
  if n == 2
    return true
  if n % 2 == 0
    return false
  d = 3
  while d * d <= n
    if n % d == 0
      return false
    d += 2
  true

-> carmichael_for_p1(p1)
  if !prime?(p1)
    return
  h3 = 2
  while h3 < p1
    g = h3 + p1
    d = 1
    while d < g
      if ((h3 * p1) % g) == 1 % g
        break
      d += 1
    h3 += 1

# Direct check for 3-factor Carmichael numbers p * q * r up to 10000
-> find_carmichael()
  primes = []
  (3..100).each -> (n)
    if prime?(n)
      primes.push(n)
  i = 0
  while i < primes.size
    p = primes[i]
    j = i + 1
    while j < primes.size
      q = primes[j]
      k = j + 1
      while k < primes.size
        r = primes[k]
        n = p * q * r
        if (n - 1) % (p - 1) == 0 && (n - 1) % (q - 1) == 0 && (n - 1) % (r - 1) == 0
          if n <= 50000
            << "[p] * [q] * [r] = [n]"
        k += 1
      j += 1
    i += 1

find_carmichael()

## expect stdout
## 3 * 11 * 17 = 561
## 5 * 13 * 17 = 1105
## 5 * 17 * 29 = 2465
## 5 * 29 * 73 = 10585
## 7 * 13 * 19 = 1729
## 7 * 13 * 31 = 2821
## 7 * 19 * 67 = 8911
## 7 * 23 * 41 = 6601
## 7 * 31 * 73 = 15841
## 13 * 37 * 61 = 29341
## 13 * 37 * 97 = 46657
