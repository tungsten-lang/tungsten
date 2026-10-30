# Sorting algorithms/Stooge sort

-> stooge_sort(a, i, j)
  if a[j] < a[i]
    t = a[i]
    a[i] = a[j]
    a[j] = t
  if j - i > 1
    t = (j - i + 1) / 3
    stooge_sort(a, i, j - t)
    stooge_sort(a, i + t, j)
    stooge_sort(a, i, j - t)
  a

arr = [1, 4, 5, 3, -6, 3, 7, 10, -2, -5]
<< stooge_sort(arr, 0, arr.size - 1)

## expect stdout
## [-6, -5, -2, 1, 3, 3, 4, 5, 7, 10]
