# Perfect numbers

-> perfect?(n)
  if n < 2
    return false
  sum = 1
  i = 2
  while i * i <= n
    if n % i == 0
      sum += i
      if i != n / i
        sum += n / i
    i += 1
  sum == n

found = []
(2..10000).each -> (n)
  if perfect?(n)
    found.push(n)

<< found

## expect stdout
## [6, 28, 496, 8128]
