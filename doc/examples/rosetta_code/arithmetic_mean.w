# Averages / Arithmetic mean

-> mean(arr)
  if arr.empty?
    return 0
  sum = 0
  i = 0
  while i < arr.size
    sum += arr[i]
    i += 1
  sum.to_f / arr.size

<< mean([1, 2, 3, 4])
<< mean([10, 25])
<< mean([])

## expect stdout
## 2.5
## 17.5
## 0
