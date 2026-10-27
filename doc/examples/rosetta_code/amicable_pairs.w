# Amicable pairs

-> sum_divisors(n)
  if n < 2
    return 0
  sum = 1
  i = 2
  while i * i <= n
    if n % i == 0
      sum += i
      if i != n / i
        sum += n / i
    i += 1
  sum

-> find_amicable(limit)
  n = 2
  while n < limit
    m = sum_divisors(n)
    if m > n && m < limit
      if sum_divisors(m) == n
        << "[n] and [m]"
    n += 1

find_amicable(20000)

## expect timeout 20
## expect stdout
## 220 and 284
## 1184 and 1210
## 2620 and 2924
## 5020 and 5564
## 6232 and 6368
## 10744 and 10856
## 12285 and 14595
## 17296 and 18416
