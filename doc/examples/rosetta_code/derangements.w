# Permutations/Derangements

-> subfactorial(n)
  if n == 0
    return 1
  if n == 1
    return 0
  a = 1
  b = 0
  i = 2
  while i <= n
    c = (i - 1) * (a + b)
    a = b
    b = c
    i += 1
  b

(0..9).each -> (n)
  << "![n] = [subfactorial(n)]"

## expect stdout
## !0 = 1
## !1 = 0
## !2 = 1
## !3 = 2
## !4 = 9
## !5 = 44
## !6 = 265
## !7 = 1854
## !8 = 14833
## !9 = 133496
