# Prime decomposition

-> factorize(n)
  factors = []
  d = 2
  while d * d <= n
    while n % d == 0
      factors.push(d)
      n /= d
    d += 1
  if n > 1
    factors.push(n)
  factors

nums = [12, 60, 100, 1024, 2310, 65535]
nums.each -> (n)
  << "[n] = [factorize(n)]"

## expect stdout
## 12 = [2, 2, 3]
## 60 = [2, 2, 3, 5]
## 100 = [2, 2, 5, 5]
## 1024 = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
## 2310 = [2, 3, 5, 7, 11]
## 65535 = [3, 5, 17, 257]
