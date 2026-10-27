# Fibonacci n-step number sequences

-> n_step(init, n, count)
  seq = []
  i = 0
  while i < init.size
    seq.push(init[i])
    i += 1
  while seq.size < count
    sum = 0
    j = seq.size - 1
    k = 0
    while j >= 0 && k < n
      sum += seq[j]
      j -= 1
      k += 1
    seq.push(sum)
  seq

<< "Fibonacci:  [n_step([1, 1], 2, 10)]"
<< "Tribonacci: [n_step([1, 1, 2], 3, 10)]"
<< "Tetranacci: [n_step([1, 1, 2, 4], 4, 10)]"
<< "Lucas:      [n_step([2, 1], 2, 10)]"

## expect stdout
## Fibonacci:  [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
## Tribonacci: [1, 1, 2, 4, 7, 13, 24, 44, 81, 149]
## Tetranacci: [1, 1, 2, 4, 8, 15, 29, 56, 108, 208]
## Lucas:      [2, 1, 3, 4, 7, 11, 18, 29, 47, 76]
