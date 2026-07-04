# Roman numeral encoding

+ Int
  -> to_roman(n)
    values  = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
    result = ""

    i = 0

    values.zip(symbols) ->
      while n >= value
        result << symbol
        n -= value
      i++

    result

[1, 4, 9, 14, 42, 99, 2024, 1776] ->
  << "[n] = [n.to_roman]"

## expect skip currently unsupported in this runtime
