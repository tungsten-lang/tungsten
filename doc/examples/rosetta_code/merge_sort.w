# Merge sort
# See Haskell for ideas for an alternate implementation

-> merge(left, right)
  result = []
  li = 0
  ri = 0
  while li < left.size && ri < right.size
    if left[li] <= right[ri]
      result.push(left[li])
      li += 1
    else
      result.push(right[ri])
      ri += 1
  while li < left.size
    result.push(left[li])
    li += 1
  while ri < right.size
    result.push(right[ri])
    ri += 1
  result

-> merge_sort(arr)
  if arr.size <= 1
    arr
  else
    mid = arr.size / 2
    left_src = []
    right_src = []
    i = 0
    while i < mid
      left_src.push(arr[i])
      i += 1
    while i < arr.size
      right_src.push(arr[i])
      i += 1
    left = merge_sort(left_src)
    right = merge_sort(right_src)
    merge(left, right)

<< merge_sort [38, 27, 43, 3, 9, 82, 10]

## expect stdout
## [3, 9, 10, 27, 38, 43, 82]
