# Insertion sort

-> insertion_sort(arr)
  n = arr.size
  n ->
    key = arr[i]
    j = i - 1
    while j >= 0 && arr[j] > key
      arr[j + 1] = arr[j]
      j--
    arr[j + 1] = key
  arr

<< insertion_sort([5, 3, 8, 4, 2, 7, 1, 6])

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten insertion_sort.w`
## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8]
