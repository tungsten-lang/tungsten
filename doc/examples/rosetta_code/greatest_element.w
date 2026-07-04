# Greatest element of a list

-> max(arr)
  best = arr[0]
  i = 1
  while i < arr.size
    if arr[i] > best
      best = arr[i]
    i += 1
  best

<< max([1, 5, 3, 9, 2, 8])

## expect stdout
## 9
