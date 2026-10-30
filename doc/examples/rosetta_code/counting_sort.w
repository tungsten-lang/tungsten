# Sorting algorithms/Counting sort

-> counting_sort(arr, min_val, max_val)
  range = max_val - min_val + 1
  counts = []
  i = 0
  while i < range
    counts.push(0)
    i += 1
  i = 0
  while i < arr.size
    counts[arr[i] - min_val] += 1
    i += 1
  out = []
  v = 0
  while v < range
    c = counts[v]
    while c > 0
      out.push(v + min_val)
      c -= 1
    v += 1
  out

<< counting_sort([4, 2, 2, 8, 3, 3, 1], 1, 8)

## expect stdout
## [1, 2, 2, 3, 3, 4, 8]
