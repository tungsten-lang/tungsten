# Roman numerals/Decode

-> roman_val(c)
  if c == "M"
    1000
  elsif c == "D"
    500
  elsif c == "C"
    100
  elsif c == "L"
    50
  elsif c == "X"
    10
  elsif c == "V"
    5
  elsif c == "I"
    1
  else
    0

-> from_roman(s)
  chars = s.chars
  total = 0
  i = 0
  while i < chars.size
    v = roman_val(chars[i])
    if i + 1 < chars.size && roman_val(chars[i + 1]) > v
      total -= v
    else
      total += v
    i += 1
  total

romans = ["MCMXC", "MMVIII", "MDCLXVI", "MMXXVI"]
romans.each -> (r)
  << "[r] = [from_roman(r)]"

## expect stdout
## MCMXC = 1990
## MMVIII = 2008
## MDCLXVI = 1666
## MMXXVI = 2026
