# Padovan sequence

-> padovan(count)
  seq = [1, 1, 1]
  while seq.size < count
    n = seq.size
    seq.push(seq[n - 2] + seq[n - 3])
  seq

<< padovan(20)

## expect stdout
## [1, 1, 1, 2, 2, 3, 4, 5, 7, 9, 12, 16, 21, 28, 37, 49, 65, 86, 114, 151]
