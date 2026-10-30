# ISBN13 check digit

-> isbn13_valid?(s)
  chars = s.chars
  digits = []
  i = 0
  while i < chars.size
    c = chars[i]
    if c >= "0" && c <= "9"
      digits.push(c.to_i)
    elsif c != "-" && c != " "
      return false
    i += 1
  if digits.size != 13
    return false
  sum = 0
  i = 0
  while i < 13
    if i % 2 == 0
      sum += digits[i]
    else
      sum += digits[i] * 3
    i += 1
  sum % 10 == 0

codes = ["978-1734314502", "978-1734314509", "978-1788399081", "978-1788399083"]
codes.each -> (code)
  << "[code]: [isbn13_valid?(code)]"

## expect stdout
## 978-1734314502: true
## 978-1734314509: false
## 978-1788399081: true
## 978-1788399083: false
