# Sorting algorithms/Selection sort

-> selection_sort(arr)
  n = arr.size
  i = 0
  while i < n
    min = i
    j = i + 1
    while j < n
      if arr[j] < arr[min]
        min = j
      j += 1
    if min != i
      t = arr[i]
      arr[i] = arr[min]
      arr[min] = t
    i += 1
  arr

<< selection_sort([64, 25, 12, 22, 11])

## expect stdout
## [11, 12, 22, 25, 64]
