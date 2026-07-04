# Selection sort

-> selection_sort(arr)
  arr.size ->
    min = i
    (i + 1)...arr.size ->(j)
      min = j if arr[j] < arr[min]
    arr[i] <> arr[min] if min != i
  arr

<< selection_sort [64, 25, 12, 22, 11]

## expect skip currently unsupported in this runtime
