# Binary search

-> binary_search(arr, target)
  lo = 0
  hi = arr.size - 1
  while lo <= hi
    mid = (lo + hi) / 2
    if arr[mid] == target
      return mid
    elsif arr[mid] < target
      lo = mid + 1
    else
      hi = mid - 1
  -1

sorted = [2, 5, 8, 12, 16, 23, 38, 56, 72, 91]
<< binary_search(sorted, 23)
<< binary_search(sorted, 4)

## expect stdout
## 5
## -1
