# Amicable pairs

-> sum_divisors(n)
  sum = 1
  i = 2
  while i * i <= n
    if n % i == 0
      sum += i
      if i != n / i
        sum += n / i
    i += 1
  sum

n = 2
while n < 20000
  m = sum_divisors(n)
  if m > n and sum_divisors(m) == n
    puts "[n] and [m]"
  n += 1

## expect skip currently unsupported in this runtime
