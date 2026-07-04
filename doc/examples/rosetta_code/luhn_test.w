# Luhn test for credit card validation

-> luhn?(s)
  sum = 0
  alt = false
  k = s.size - 1
  while k >= 0
    n = s[k].to_i
    if alt
      n *= 2
      if n > 9
        n -= 9
    sum += n
    alt = !alt
    k -= 1
  sum % 10 == 0

tests = ["49927398716", "49927398717", "1234567812345678", "1234567812345670"]
i = 0
while i < tests.size
  t = tests[i]
  << "[t]: [luhn?(t)]"
  i += 1

## expect stdout
## 49927398716: true
## 49927398717: false
## 1234567812345678: false
## 1234567812345670: true
