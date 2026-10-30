# Horner's rule for polynomial evaluation

-> horner(coeffs, x)
  acc = 0
  i = coeffs.size - 1
  while i >= 0
    acc = acc * x + coeffs[i]
    i -= 1
  acc

<< horner([-19, 7, -4, 6], 3)

## expect stdout
## 128
