# Bubble sort

-> bubble_sort(a)
  n = a.size
  swapped = true
  while swapped
    swapped = false
    i = 1
    while i < n
      if a[i - 1] > a[i]
        t = a[i - 1]
        a[i - 1] = a[i]
        a[i] = t
        swapped = true
      i += 1
    n -= 1
  a

<< bubble_sort([5, 1, 4, 2, 8])

## expect stdout
## [1, 2, 4, 5, 8]
