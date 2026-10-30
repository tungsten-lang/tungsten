# Floyd's triangle

-> floyd(rows)
  n = 1
  r = 1
  while r <= rows
    line = []
    c = 1
    while c <= r
      line.push(n.to_s)
      n += 1
      c += 1
    << line.join(" ")
    r += 1

floyd(5)

## expect stdout
## 1
## 2 3
## 4 5 6
## 7 8 9 10
## 11 12 13 14 15
