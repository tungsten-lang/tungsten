# Sum digits of an integer

-> sum_digits(n, base)
  total = 0
  while n > 0
    total += n % base
    n /= base
  total

<< sum_digits(1, 10)
<< sum_digits(1234, 10)
<< sum_digits(254, 16)
<< sum_digits(3855, 16)

## expect stdout
## 1
## 10
## 29
## 30
