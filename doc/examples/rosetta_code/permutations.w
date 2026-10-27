# Permutations

-> next_permutation(a)
  n = a.size
  i = n - 2
  while i >= 0 && a[i] >= a[i + 1]
    i -= 1
  if i < 0
    return false
  j = n - 1
  while a[j] <= a[i]
    j -= 1
  t = a[i]
  a[i] = a[j]
  a[j] = t
  lo = i + 1
  hi = n - 1
  while lo < hi
    t = a[lo]
    a[lo] = a[hi]
    a[hi] = t
    lo += 1
    hi -= 1
  true

-> show_permutations()
  arr = [1, 2, 3]
  while true
    << arr.join(" ")
    if !next_permutation(arr)
      break

show_permutations()

## expect stdout
## 1 2 3
## 1 3 2
## 2 1 3
## 2 3 1
## 3 1 2
## 3 2 1
