# Compute kernel for the eval-backend benchmark: sum 1..5_000_000.
# Slow under the tree-walking interpreter, fast compiled — the gap is the point.
total = 0
i = 1
while i <= 5000000
  total = total + i
  i = i + 1
<< total
