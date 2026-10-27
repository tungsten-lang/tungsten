# Averages/Median

-> sort_copy(arr)
  a = []
  i = 0
  while i < arr.size
    a.push(arr[i])
    i += 1
  n = a.size
  i = 1
  while i < n
    key = a[i]
    j = i - 1
    while j >= 0 && a[j] > key
      a[j + 1] = a[j]
      j -= 1
    a[j + 1] = key
    i += 1
  a

-> median(arr)
  s = sort_copy(arr)
  n = s.size
  mid = n / 2
  if n % 2 == 1
    s[mid].to_f
  else
    (s[mid - 1] + s[mid]).to_f / 2.0

<< median([4, 1, 7])
<< median([4, 1, 2, 7])

## expect stdout
## 4
## 3
