# Run-length encoding

-> rle_encode(s)
  chars = s.chars
  out = ""
  i = 0
  while i < chars.size
    c = chars[i]
    count = 1
    while i + count < chars.size && chars[i + count] == c
      count += 1
    out += "[count][c]"
    i += count
  out

-> rle_decode(s)
  chars = s.chars
  out = ""
  count = 0
  i = 0
  while i < chars.size
    c = chars[i]
    if c >= "0" && c <= "9"
      count = count * 10 + c.to_i
    else
      k = 0
      while k < count
        out += c
        k += 1
      count = 0
    i += 1
  out

input = "WWWWWWWWWWWWBWWWWWWWWWWWWBBBWWWWWWWWWWWWWWWWWWWWWWWWBWWWWWWWWWWWWWW"
enc = rle_encode(input)
<< enc
<< rle_decode(enc)

## expect stdout
## 12W1B12W3B24W1B14W
## WWWWWWWWWWWWBWWWWWWWWWWWWBBBWWWWWWWWWWWWWWWWWWWWWWWWBWWWWWWWWWWWWWW
