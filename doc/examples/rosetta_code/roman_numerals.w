# Roman numerals/Encode

-> to_roman(n)
  values  = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
  result = ""
  i = 0
  while i < values.size
    while n >= values[i]
      result += symbols[i]
      n -= values[i]
    i += 1
  result

nums = [1, 4, 9, 14, 42, 99, 2024, 1776]
nums.each -> (n)
  << "[n] = [to_roman(n)]"

## expect stdout
## 1 = I
## 4 = IV
## 9 = IX
## 14 = XIV
## 42 = XLII
## 99 = XCIX
## 2024 = MMXXIV
## 1776 = MDCCLXXVI
