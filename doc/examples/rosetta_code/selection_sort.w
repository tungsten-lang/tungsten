# Selection sort

-> selection_sort(arr)
  n = arr.size
  n ->
    min = i
    (i + 1)...n ->(j)
      min = j if arr[j] < arr[min]
    if min != i
      t = arr[i]
      arr[i] = arr[min]
      arr[min] = t
  arr

<< selection_sort([64, 25, 12, 22, 11])

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten selection_sort.w`
## expect stdout
## [11, 12, 22, 25, 64]
