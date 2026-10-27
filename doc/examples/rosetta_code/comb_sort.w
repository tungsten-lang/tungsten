# Sorting algorithms/Comb sort

-> comb_sort(a)
  gap = a.size
  swapped = true
  while gap > 1 || swapped
    gap = (gap * 10) / 13
    if gap < 1
      gap = 1
    swapped = false
    i = 0
    while i + gap < a.size
      if a[i] > a[i + gap]
        t = a[i]
        a[i] = a[i + gap]
        a[i + gap] = t
        swapped = true
      i += 1
  a

<< comb_sort([8, 4, 1, 56, 3, -44, 23, -6, 28, 0])

## expect stdout
## [-44, -6, 0, 1, 3, 4, 8, 23, 28, 56]
