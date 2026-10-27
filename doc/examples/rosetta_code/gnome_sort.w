# Sorting algorithms/Gnome sort

-> gnome_sort(a)
  i = 1
  j = 2
  while i < a.size
    if a[i - 1] <= a[i]
      i = j
      j += 1
    else
      t = a[i - 1]
      a[i - 1] = a[i]
      a[i] = t
      i -= 1
      if i == 0
        i = j
        j += 1
  a

<< gnome_sort([34, 2, 10, -9, 7, 3, 0])

## expect stdout
## [-9, 0, 2, 3, 7, 10, 34]
