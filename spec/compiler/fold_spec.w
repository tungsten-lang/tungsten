# Demanded compile-time fold: `expr ## fold`, `expr ## fold T`, and
# `-> ## fold` blocks.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit 1

n = 1 + 2 ## fold
check("arith", n, 3)

xs = [1, 2, 3] ## fold
check("array.0", xs[0], 1)
check("array.2", xs[2], 3)
check("array.size", xs.size, 3)

-> twice(x)
  x + x

t = twice(21) ## fold
check("pure.call", t, 42)

tables = -> ## fold
  a = 10
  b = a * a
  b + 1
check("block", tables, 101)

built = -> ## fold
  out = []
  i = 0
  while i < 4
    out.push(i)
    i += 1
  out
check("block.array", built.size, 4)
check("block.array.last", built[3], 3)

dr = [7, 8] ## fold i64[]
check("typed.0", dr[0], 7)
check("typed.1", dr[1], 8)

# `## fold` after `<<` ascribes the value, not puts. If it bound to `<<`
# this would be E_LOWER_FOLD "cannot fold puts".
folded_print = (40 + 2) ## fold
check("puts.value", folded_print, 42)
<< (1 + 2) ## fold

<< "PASS fold"
