# Sorting algorithms/Cocktail sort

-> cocktail_sort(a)
  swapped = true
  start_idx = 0
  end_idx = a.size - 1
  while swapped
    swapped = false
    i = start_idx
    while i < end_idx
      if a[i] > a[i + 1]
        t = a[i]
        a[i] = a[i + 1]
        a[i + 1] = t
        swapped = true
      i += 1
    if !swapped
      break
    swapped = false
    end_idx -= 1
    i = end_idx - 1
    while i >= start_idx
      if a[i] > a[i + 1]
        t = a[i]
        a[i] = a[i + 1]
        a[i + 1] = t
        swapped = true
      i -= 1
    start_idx += 1
  a

<< cocktail_sort([5, 1, 4, 2, 8, 0, 2])

## expect stdout
## [0, 1, 2, 2, 4, 5, 8]
