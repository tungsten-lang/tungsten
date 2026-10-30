# Ethiopian multiplication

-> halve(n)
  n / 2

-> double(n)
  n * 2

-> even?(n)
  n % 2 == 0

-> ethiopian(a, b)
  total = 0
  while a >= 1
    if !even?(a)
      total += b
    a = halve(a)
    b = double(b)
  total

<< ethiopian(17, 34)
<< ethiopian(99, 99)

## expect stdout
## 578
## 9801
