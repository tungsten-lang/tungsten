# Sorting algorithms/Cycle sort

-> cycle_sort(a)
  n = a.size
  cycle_start = 0
  while cycle_start <= n - 2
    item = a[cycle_start]
    pos = cycle_start
    i = cycle_start + 1
    while i < n
      if a[i] < item
        pos += 1
      i += 1
    if pos != cycle_start
      while item == a[pos]
        pos += 1
      tmp = a[pos]
      a[pos] = item
      item = tmp
      while pos != cycle_start
        pos = cycle_start
        i = cycle_start + 1
        while i < n
          if a[i] < item
            pos += 1
          i += 1
        while item == a[pos]
          pos += 1
        tmp = a[pos]
        a[pos] = item
        item = tmp
    cycle_start += 1
  a

<< cycle_sort([0, 1, 2, 2, 2, 2, 1, 9, 3, 5, 5, 8, 4, 7, 0, 6])

## expect stdout
## [0, 0, 1, 1, 2, 2, 2, 2, 3, 4, 5, 5, 6, 7, 8, 9]
