# Digital root

-> digital_root(n)
  persistence = 0
  while n >= 10
    sum = 0
    while n > 0
      sum += n % 10
      n = n / 10
    n = sum
    persistence += 1
  [n, persistence]

nums = [627615, 39390, 588225, 393900588225]
nums.each -> (n)
  result = digital_root(n)
  << "[n]: root=[result[0]] persistence=[result[1]]"

## expect stdout
## 627615: root=9 persistence=2
## 39390: root=6 persistence=2
## 588225: root=3 persistence=2
## 393900588225: root=9 persistence=2
