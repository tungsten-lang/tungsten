# Leonardo numbers

-> leonardo(l0, l1, add, count)
  seq = [l0, l1]
  while seq.size < count
    n = seq.size
    seq.push(seq[n - 1] + seq[n - 2] + add)
  seq

<< leonardo(1, 1, 1, 15)
<< leonardo(0, 1, 0, 15)

## expect stdout
## [1, 1, 3, 5, 9, 15, 25, 41, 67, 109, 177, 287, 465, 753, 1219]
## [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377]
