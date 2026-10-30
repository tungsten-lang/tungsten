# Set

-> set_union(a, b)
  out = []
  a.each -> (x)
    if !out.include?(x)
      out.push(x)
  b.each -> (x)
    if !out.include?(x)
      out.push(x)
  out

-> set_intersection(a, b)
  out = []
  a.each -> (x)
    if b.include?(x) && !out.include?(x)
      out.push(x)
  out

-> set_difference(a, b)
  out = []
  a.each -> (x)
    if !b.include?(x) && !out.include?(x)
      out.push(x)
  out

-> set_subset?(a, b)
  i = 0
  while i < a.size
    if !b.include?(a[i])
      return false
    i += 1
  true

a = [1, 2, 3, 4]
b = [3, 4, 5, 6]

<< "A union B: [set_union(a, b)]"
<< "A intersect B: [set_intersection(a, b)]"
<< "A - B: [set_difference(a, b)]"
<< "{1, 2} subset of A: [set_subset?([1, 2], a)]"
<< "{1, 5} subset of A: [set_subset?([1, 5], a)]"

## expect stdout
## A union B: [1, 2, 3, 4, 5, 6]
## A intersect B: [3, 4]
## A - B: [1, 2]
## {1, 2} subset of A: true
## {1, 5} subset of A: false
