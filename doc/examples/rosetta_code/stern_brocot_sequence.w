# Stern-Brocot sequence

-> stern_brocot(count)
  seq = [1, 1]
  i = 1
  while seq.size < count
    seq.push(seq[i] + seq[i - 1])
    if seq.size < count
      seq.push(seq[i])
    i += 1
  seq

<< stern_brocot(15)

## expect stdout
## [1, 1, 2, 1, 3, 2, 3, 1, 4, 3, 5, 2, 5, 3, 4]
