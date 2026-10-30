# Recaman's sequence

-> recaman(count)
  seq = [0]
  seen = [0]
  n = 1
  while n < count
    prev = seq[n - 1]
    cand = prev - n
    if cand > 0 && !seen.include?(cand)
      seq.push(cand)
      seen.push(cand)
    else
      cand = prev + n
      seq.push(cand)
      seen.push(cand)
    n += 1
  seq

<< recaman(15)

## expect stdout
## [0, 1, 3, 6, 2, 7, 13, 20, 12, 21, 11, 22, 10, 23, 9]
