# Rot-13

-> rot13(s)
  result = ""
  chars = s.chars
  i = 0
  while i < chars.size
    c = chars[i]
    code = c.ord
    if code >= 97 && code <= 122
      result += (((code - 97 + 13) % 26) + 97).chr
    elsif code >= 65 && code <= 90
      result += (((code - 65 + 13) % 26) + 65).chr
    else
      result += c
    i += 1
  result

<< rot13("Hello, World!")
<< rot13("Uryyb, Jbeyq!")

## expect stdout
## Uryyb, Jbeyq!
## Hello, World!
