# Sieve of Eratosthenes

-> sieve(limit)
  is_prime = []
  i = 0
  while i <= limit
    is_prime.push(true)
    i += 1
  is_prime[0] = false
  is_prime[1] = false

  i = 2
  while i * i <= limit
    if is_prime[i]
      j = i * i
      while j <= limit
        is_prime[j] = false
        j += i
    i += 1

  primes = []
  i = 2
  while i <= limit
    if is_prime[i]
      primes.push(i)
    i += 1
  primes

<< sieve(100)

## expect stdout
## [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]
