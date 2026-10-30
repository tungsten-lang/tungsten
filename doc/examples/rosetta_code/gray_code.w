# Gray code

-> gray_encode(n)
  n ^ (n >> 1)

-> gray_decode(g)
  n = g
  mask = g >> 1
  while mask > 0
    n = n ^ mask
    mask = mask >> 1
  n

-> to_bin5(n)
  out = ""
  i = 0
  while i < 5
    if (n & 1) == 1
      out = "1" + out
    else
      out = "0" + out
    n = n >> 1
    i += 1
  out

(0..15).each -> (n)
  g = gray_encode(n)
  d = gray_decode(g)
  << "[n] => [to_bin5(g)] => [d]"

## expect stdout
## 0 => 00000 => 0
## 1 => 00001 => 1
## 2 => 00011 => 2
## 3 => 00010 => 3
## 4 => 00110 => 4
## 5 => 00111 => 5
## 6 => 00101 => 6
## 7 => 00100 => 7
## 8 => 01100 => 8
## 9 => 01101 => 9
## 10 => 01111 => 10
## 11 => 01110 => 11
## 12 => 01010 => 12
## 13 => 01011 => 13
## 14 => 01001 => 14
## 15 => 01000 => 15
