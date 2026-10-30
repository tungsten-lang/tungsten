# Evaluate binomial coefficients

-> binomial(n, k)
  if k < 0 || k > n
    return 0
  if k == 0 || k == n
    return 1
  if k > n - k
    k = n - k
  result = 1
  i = 1
  while i <= k
    result = result * (n - i + 1) / i
    i += 1
  result

<< binomial(5, 3)
<< binomial(20, 10)
<< binomial(60, 30)

## expect stdout
## 10
## 184756
## 118264581564861424
