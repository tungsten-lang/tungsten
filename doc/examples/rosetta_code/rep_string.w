# Rep-string

-> longest_rep(s)
  n = s.size
  best = ""
  len = 1
  while len <= n / 2
    unit = s.slice(0, len)
    ok = true
    i = 0
    while i < n
      if s.slice(i, 1) != unit.slice(i % len, 1)
        ok = false
        break
      i += 1
    if ok
      best = unit
    len += 1
  if best == ""
    "none"
  else
    best

inputs = [
  "1001110011",
  "1110111011",
  "0010010010",
  "1010101010",
  "1111111111",
  "0100101101",
  "0100100",
  "101",
  "11",
  "00",
  "1"
]

inputs.each -> (inp)
  << "[inp] -> [longest_rep(inp)]"

## expect stdout
## 1001110011 -> 10011
## 1110111011 -> 1110
## 0010010010 -> 001
## 1010101010 -> 1010
## 1111111111 -> 11111
## 0100101101 -> none
## 0100100 -> 010
## 101 -> none
## 11 -> 1
## 00 -> 0
## 1 -> none
