# Quickselect algorithm

-> partition(a, left, right, pivot_idx)
  pivot_val = a[pivot_idx]
  t = a[pivot_idx]
  a[pivot_idx] = a[right]
  a[right] = t
  store_idx = left
  i = left
  while i < right
    if a[i] < pivot_val
      t = a[store_idx]
      a[store_idx] = a[i]
      a[i] = t
      store_idx += 1
    i += 1
  t = a[right]
  a[right] = a[store_idx]
  a[store_idx] = t
  store_idx

-> quickselect(arr, k)
  a = []
  i = 0
  while i < arr.size
    a.push(arr[i])
    i += 1
  left = 0
  right = a.size - 1
  while left < right
    pivot_idx = (left + right) / 2
    pivot_idx = partition(a, left, right, pivot_idx)
    if k == pivot_idx
      return a[k]
    elsif k < pivot_idx
      right = pivot_idx - 1
    else
      left = pivot_idx + 1
  a[left]

v = [9, 8, 7, 6, 5, 0, 1, 2, 3, 4]
out = []
(0...v.size).each -> (k)
  out.push(quickselect(v, k))

<< out

## expect stdout
## [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
