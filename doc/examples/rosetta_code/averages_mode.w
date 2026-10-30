# Averages/Mode

-> mode(arr)
  counts = {}
  unique = []
  max_count = 0
  i = 0
  while i < arr.size
    x = arr[i]
    if counts[x] == nil
      counts[x] = 0
      unique.push(x)
    counts[x] += 1
    if counts[x] > max_count
      max_count = counts[x]
    i += 1
  modes = []
  i = 0
  while i < unique.size
    u = unique[i]
    if counts[u] == max_count
      modes.push(u)
    i += 1
  modes

<< mode([1, 3, 6, 6, 6, 6, 7, 7, 12, 12, 17])
<< mode([1, 1, 2, 4, 4])

## expect stdout
## [6]
## [1, 4]
