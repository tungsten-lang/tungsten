# Raw machine-width arithmetic; this is not arbitrary-precision Int.
-> polynomial(x) (i64) i64
  x * x + 2 * x + 1

-> sum_to(n) (i64) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < n
    total += i
    i += 1
  total
