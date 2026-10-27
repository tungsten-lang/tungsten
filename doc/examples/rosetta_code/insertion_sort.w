# Sorting algorithms/Insertion sort

-> insertion_sort(arr)
  n = arr.size
  i = 1
  while i < n
    key = arr[i]
    j = i - 1
    while j >= 0 && arr[j] > key
      arr[j + 1] = arr[j]
      j -= 1
    arr[j + 1] = key
    i += 1
  arr

<< insertion_sort([5, 3, 8, 4, 2, 7, 1, 6])

## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8]
