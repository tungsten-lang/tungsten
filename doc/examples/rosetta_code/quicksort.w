# Quicksort

-> append_all(dst, src)
  i = 0
  while i < src.size
    dst.push(src[i])
    i += 1
  dst

-> quicksort(a)
  if a.size <= 1
    return a
  pivot = a[0]
  left = []
  right = []
  i = 1
  while i < a.size
    if a[i] <= pivot
      left.push(a[i])
    else
      right.push(a[i])
    i += 1
  out = quicksort(left)
  out.push(pivot)
  append_all(out, quicksort(right))

<< quicksort([38, 27, 43, 3, 9, 82, 10])

## expect stdout
## [3, 9, 10, 27, 38, 43, 82]
