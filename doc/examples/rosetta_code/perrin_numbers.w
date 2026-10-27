# Perrin sequence

-> perrin(count)
  seq = [3, 0, 2]
  while seq.size < count
    n = seq.size
    seq.push(seq[n - 2] + seq[n - 3])
  seq

<< perrin(15)

## expect stdout
## [3, 0, 2, 3, 2, 5, 5, 7, 10, 12, 17, 22, 29, 39, 51]
