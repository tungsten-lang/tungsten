# Sorting algorithms/Heapsort

-> sift_down(a, start_idx, end_idx)
  root = start_idx
  while root * 2 + 1 <= end_idx
    child = root * 2 + 1
    if child + 1 <= end_idx && a[child] < a[child + 1]
      child += 1
    if a[root] < a[child]
      t = a[root]
      a[root] = a[child]
      a[child] = t
      root = child
    else
      return

-> heapsort(a)
  n = a.size
  start_idx = (n - 2) / 2
  while start_idx >= 0
    sift_down(a, start_idx, n - 1)
    start_idx -= 1
  end_idx = n - 1
  while end_idx > 0
    t = a[end_idx]
    a[end_idx] = a[0]
    a[0] = t
    end_idx -= 1
    sift_down(a, 0, end_idx)
  a

<< heapsort([12, 11, 13, 5, 6, 7, 1, 9])

## expect stdout
## [1, 5, 6, 7, 9, 11, 12, 13]
