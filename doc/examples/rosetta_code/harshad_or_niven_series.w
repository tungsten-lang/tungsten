# Harshad or Niven series

-> digit_sum(n)
  s = 0
  while n > 0
    s += n % 10
    n /= 10
  s

-> harshad?(n)
  n % digit_sum(n) == 0

first20 = []
n = 1
while first20.size < 20
  if harshad?(n)
    first20.push(n)
  n += 1

<< first20

above1000 = 1001
while !harshad?(above1000)
  above1000 += 1

<< above1000

## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 18, 20, 21, 24, 27, 30, 36, 40, 42]
## 1002
