# Combinations

-> combinations(n, k)
  idx = []
  i = 0
  while i < k
    idx.push(i)
    i += 1
  result = []
  while true
    comb = []
    i = 0
    while i < k
      comb.push(idx[i])
      i += 1
    result.push(comb)
    i = k - 1
    while i >= 0 && idx[i] == i + n - k
      i -= 1
    if i < 0
      break
    idx[i] += 1
    j = i + 1
    while j < k
      idx[j] = idx[j - 1] + 1
      j += 1
  result

combs = combinations(5, 3)
combs.each -> (c)
  << c

## expect stdout
## [0, 1, 2]
## [0, 1, 3]
## [0, 1, 4]
## [0, 2, 3]
## [0, 2, 4]
## [0, 3, 4]
## [1, 2, 3]
## [1, 2, 4]
## [1, 3, 4]
## [2, 3, 4]
