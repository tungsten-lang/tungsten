# Polynomial long division

-> poly_div(num, den)
  rem = []
  i = 0
  while i < num.size
    rem.push(num[i])
    i += 1
  deg_n = rem.size - 1
  deg_d = den.size - 1
  if deg_n < deg_d
    return [[0], rem]
  quot = []
  i = 0
  while i <= deg_n - deg_d
    quot.push(0)
    i += 1
  k = 0
  while k <= deg_n - deg_d
    coeff = rem[k] / den[0]
    quot[k] = coeff
    j = 0
    while j <= deg_d
      rem[k + j] -= coeff * den[j]
      j += 1
    k += 1
  # Trim leading zeros from remainder
  trimmed = []
  started = false
  i = 0
  while i < rem.size
    if rem[i] != 0 || started
      trimmed.push(rem[i])
      started = true
    i += 1
  if trimmed.empty?
    trimmed.push(0)
  [quot, trimmed]

res = poly_div([1, -12, 0, -42], [1, -3])
<< "Quotient:  [res[0]]"
<< "Remainder: [res[1]]"

## expect stdout
## Quotient:  [1, -9, -27]
## Remainder: [-123]
