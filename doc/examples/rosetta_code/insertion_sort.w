# Insertion sort

-> insertion_sort(arr)
  arr.size ->
    key = arr[i]
    j = i - 1
    while j >= 0 && arr[j] > key
      arr[j + 1] = arr[j]
      j--
    arr[j + 1] = key
  arr

<< insertion_sort([5, 3, 8, 4, 2, 7, 1, 6])

## expect stdout
## [5, 3, 8, 4, 2, 7, 1, 6]
