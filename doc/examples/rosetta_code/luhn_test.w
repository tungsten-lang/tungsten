# Luhn test for credit card validation

-> luhn?(s)
  digits = s.chars
  sum = 0
  alt = false
  k = digits.size - 1
  while k >= 0
    n = digits[k].to_i
    if alt
      n *= 2
      if n > 9
        n -= 9
    sum += n
    alt = !alt
    k -= 1
  sum % 10 == 0

tests = ["49927398716", "49927398717", "1234567812345678", "1234567812345670"]
tests.each -> (t)
  << "[t]: [luhn?(t)]"

## expect stdout
## 49927398716: true
## 49927398717: false
## 1234567812345678: false
## 1234567812345670: true
