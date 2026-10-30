# AKS test for primes

-> aks_coeffs(p)
  c = [1]
  i = 0
  while i < p
    next_c = [1]
    j = 0
    while j < c.size - 1
      next_c.push(c[j + 1] - c[j])
      j += 1
    next_c.push(-c[c.size - 1])
    c = next_c
    i += 1
  c

-> aks_prime?(p)
  if p < 2
    return false
  c = aks_coeffs(p)
  i = 1
  while i < p
    if c[i] % p != 0
      return false
    i += 1
  true

primes = []
(2..50).each -> (n)
  if aks_prime?(n)
    primes.push(n)

<< primes

## expect stdout
## [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
