# Symmetric difference

-> diff(a, b)
  out = []
  i = 0
  while i < a.size
    if !b.include?(a[i]) && !out.include?(a[i])
      out.push(a[i])
    i += 1
  out

-> sym_diff(a, b)
  out = diff(a, b)
  rhs = diff(b, a)
  i = 0
  while i < rhs.size
    out.push(rhs[i])
    i += 1
  out

a = ["John", "Bob", "Mary", "Serena"]
b = ["Jim", "Mary", "John", "Bob"]

<< "A \\ B: [diff(a, b)]"
<< "B \\ A: [diff(b, a)]"
<< "A Δ B: [sym_diff(a, b)]"

## expect stdout
## A \ B: [Serena]
## B \ A: [Jim]
## A Δ B: [Serena, Jim]
