# Middle three digits

-> middle_three(n)
  if n < 0
    n = -n
  s = n.to_s
  len = s.size
  if len < 3
    return "too short"
  if len % 2 == 0
    return "even number of digits"
  mid = (len - 3) / 2
  s.slice(mid, 3)

samples = [123, 12345, 1234567, 987654321, 10001, -10001, -123, -100, 100, -12345, 1, 2, -1, -10, 2002, -2002, 0]
samples.each -> (x)
  << "[x]: [middle_three(x)]"

## expect stdout
## 123: 123
## 12345: 234
## 1234567: 345
## 987654321: 654
## 10001: 000
## -10001: 000
## -123: 123
## -100: 100
## 100: 100
## -12345: 234
## 1: too short
## 2: too short
## -1: too short
## -10: too short
## 2002: even number of digits
## -2002: even number of digits
## 0: too short
