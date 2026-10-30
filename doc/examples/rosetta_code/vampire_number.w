# Vampire number

-> sort_digits(n)
  digits = []
  while n > 0
    digits.push(n % 10)
    n /= 10
  i = 1
  while i < digits.size
    key = digits[i]
    j = i - 1
    while j >= 0 && digits[j] > key
      digits[j + 1] = digits[j]
      j -= 1
    digits[j + 1] = key
    i += 1
  digits

-> fangs_4digit(n)
  target = sort_digits(n)
  fangs = []
  x = 10
  while x < 100
    if n % x == 0
      y = n / x
      if y >= x && y < 100
        if !(x % 10 == 0 && y % 10 == 0)
          if sort_digits(x * 100 + y) == target
            fangs.push("[x]*[y]")
    x += 1
  fangs

candidates = [1260, 1395, 1435, 1530, 1827, 2187, 6880]
candidates.each -> (n)
  f = fangs_4digit(n)
  joined = f.join(", ")
  << "[n]: [joined]"

## expect stdout
## 1260: 21*60
## 1395: 15*93
## 1435: 35*41
## 1530: 30*51
## 1827: 21*87
## 2187: 27*81
## 6880: 80*86
