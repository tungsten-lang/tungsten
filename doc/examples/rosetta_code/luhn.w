# Luhn test of credit card numbers

+ String
  -> luhn?
    digits = chars.map -> (c) c.to_i
    sum = 0
    alt = false
    i = digits.size - 1
    while i >= 0
      n = digits[i]
      if alt
        n *= 2
        n -= 9 if n > 9
      sum += n
      alt = !alt
      i -= 1
    sum % 10 == 0

["49927398716", "49927398717", "1234567812345678", "1234567812345670"].each -> (s)
  << "[s]: [s.luhn?]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten luhn.w`
## expect stdout
## 49927398716: true
## 49927398717: false
## 1234567812345678: false
## 1234567812345670: true
