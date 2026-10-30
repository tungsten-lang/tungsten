# Longest increasing subsequence

-> lis(arr)
  n = arr.size
  if n == 0
    return []
  lengths = []
  prev = []
  i = 0
  while i < n
    lengths.push(1)
    prev.push(-1)
    i += 1
  best_len = 1
  best_idx = 0
  i = 1
  while i < n
    j = 0
    while j < i
      if arr[j] < arr[i] && lengths[j] + 1 > lengths[i]
        lengths[i] = lengths[j] + 1
        prev[i] = j
      j += 1
    if lengths[i] > best_len
      best_len = lengths[i]
      best_idx = i
    i += 1
  out = []
  curr = best_idx
  while curr != -1
    out.push(arr[curr])
    curr = prev[curr]
  out.reverse

<< lis([3, 2, 6, 4, 5, 1])
<< lis([0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15])

## expect stdout
## [3, 4, 5]
## [0, 4, 6, 9, 13, 15]
