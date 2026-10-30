# Sorting algorithms/Shell sort

-> shell_sort(a)
  n = a.size
  gap = n / 2
  while gap > 0
    i = gap
    while i < n
      temp = a[i]
      j = i
      while j >= gap && a[j - gap] > temp
        a[j] = a[j - gap]
        j -= gap
      a[j] = temp
      i += 1
    gap /= 2
  a

<< shell_sort([23, 29, 15, 19, 31, 7, 9, 5, 2])

## expect stdout
## [2, 5, 7, 9, 15, 19, 23, 29, 31]
