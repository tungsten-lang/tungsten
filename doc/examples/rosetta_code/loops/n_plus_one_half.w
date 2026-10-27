# Loops/N plus one half

-> loop_half(n)
  out = ""
  i = 1
  while true
    out += i.to_s
    if i == n
      break
    out += ", "
    i += 1
  << out

loop_half(10)

## expect stdout
## 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
