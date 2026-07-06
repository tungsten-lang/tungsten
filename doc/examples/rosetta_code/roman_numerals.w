# Roman numeral encoding

+ Integer
  -> to_roman
    values  = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
    result = ""
    n = self

    count = values.size
    count ->
      while n >= values[i]
        result << symbols[i]
        n -= values[i]

    result

[1, 4, 9, 14, 42, 99, 2024, 1776] ->
  << "[n] = [n.to_roman]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten roman_numerals.w`
## expect stdout
## 1 = I
## 4 = IV
## 9 = IX
## 14 = XIV
## 42 = XLII
## 99 = XCIX
## 2024 = MMXXIV
## 1776 = MDCCLXXVI
