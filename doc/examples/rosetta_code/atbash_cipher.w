# Atbash cipher

-> atbash(text)
  chars = text.chars
  out = ""
  i = 0
  while i < chars.size
    c = chars[i]
    code = c.ord
    if code >= 97 && code <= 122
      out += (122 - (code - 97)).chr
    elsif code >= 65 && code <= 90
      out += (90 - (code - 65)).chr
    else
      out += c
    i += 1
  out

plain = "abcdefghijklmnopqrstuvwxyz"
cipher = atbash(plain)
<< cipher
<< atbash(cipher)

## expect stdout
## zyxwvutsrqponmlkjihgfedcba
## abcdefghijklmnopqrstuvwxyz
