# Soundex

-> soundex_digit(c)
  if c == "B" || c == "F" || c == "P" || c == "V"
    "1"
  elsif c == "C" || c == "G" || c == "J" || c == "K" || c == "Q" || c == "S" || c == "X" || c == "Z"
    "2"
  elsif c == "D" || c == "T"
    "3"
  elsif c == "L"
    "4"
  elsif c == "M" || c == "N"
    "5"
  elsif c == "R"
    "6"
  elsif c == "H" || c == "W"
    "H"
  else
    "0"

-> soundex(name)
  chars = name.upcase.chars
  out = chars[0]
  prev = soundex_digit(chars[0])
  i = 1
  while i < chars.size && out.size < 4
    d = soundex_digit(chars[i])
    if d != "H"
      if d != "0" && d != prev
        out += d
      prev = d
    i += 1
  while out.size < 4
    out += "0"
  out

names = ["Robert", "Rupert", "Rubin", "Ashcraft", "Tymczak", "Pfister"]
names.each -> (n)
  << "[n]: [soundex(n)]"

## expect stdout
## Robert: R163
## Rupert: R163
## Rubin: R150
## Ashcraft: A261
## Tymczak: T522
## Pfister: P236
