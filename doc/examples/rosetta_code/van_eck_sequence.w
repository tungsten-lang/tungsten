# Van Eck sequence

-> van_eck(count)
  seq = [0]
  n = 0
  while seq.size < count
    last = seq[n]
    found = -1
    i = n - 1
    while i >= 0
      if seq[i] == last
        found = i
        break
      i -= 1
    if found == -1
      seq.push(0)
    else
      seq.push(n - found)
    n += 1
  seq

<< van_eck(20)

## expect stdout
## [0, 0, 1, 0, 2, 0, 2, 2, 1, 6, 0, 5, 0, 2, 6, 5, 4, 0, 5, 3]
