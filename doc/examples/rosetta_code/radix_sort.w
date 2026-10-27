# Sorting algorithms/Radix sort

-> radix_sort(arr)
  max_val = arr[0]
  i = 1
  while i < arr.size
    if arr[i] > max_val
      max_val = arr[i]
    i += 1
  exp = 1
  while max_val / exp > 0
    buckets = []
    b = 0
    while b < 10
      buckets.push([])
      b += 1
    i = 0
    while i < arr.size
      digit = (arr[i] / exp) % 10
      buckets[digit].push(arr[i])
      i += 1
    out = []
    b = 0
    while b < 10
      j = 0
      while j < buckets[b].size
        out.push(buckets[b][j])
        j += 1
      b += 1
    arr = out
    exp *= 10
  arr

<< radix_sort([170, 45, 75, 90, 802, 24, 2, 66])

## expect stdout
## [2, 24, 45, 66, 75, 90, 170, 802]
