# Catalan numbers

-> factorial(n)
  if n <= 1
    1
  else
    n * factorial(n - 1)

-> catalan(n)
  factorial(2 * n) / (factorial(n + 1) * factorial(n))

(0..15).each -> (n)
  << "C([n]) = [catalan(n)]"

## expect stdout
## C(0) = 1
## C(1) = 1
## C(2) = 2
## C(3) = 5
## C(4) = 14
## C(5) = 42
## C(6) = 132
## C(7) = 429
## C(8) = 1430
## C(9) = 4862
## C(10) = 16796
## C(11) = 58786
## C(12) = 208012
## C(13) = 742900
## C(14) = 2674440
## C(15) = 9694845
