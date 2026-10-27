# Sorting algorithms/Pancake sort

-> flip(a, k)
  lo = 0
  hi = k
  while lo < hi
    t = a[lo]
    a[lo] = a[hi]
    a[hi] = t
    lo += 1
    hi -= 1

-> pancake_sort(a)
  curr_size = a.size
  while curr_size > 1
    max_idx = 0
    i = 1
    while i < curr_size
      if a[i] > a[max_idx]
        max_idx = i
      i += 1
    if max_idx != curr_size - 1
      if max_idx > 0
        flip(a, max_idx)
      flip(a, curr_size - 1)
    curr_size -= 1
  a

<< pancake_sort([6, 7, 8, 9, 2, 5, 3, 4, 1])

## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8, 9]
