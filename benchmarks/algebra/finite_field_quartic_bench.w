# Hot-path benchmark for affine point evaluation of the shell-width quartic
# over F_(5^3). One sweep evaluates all 125^2 affine pairs.
#
#   bin/tungsten -o /tmp/finite_field_quartic_bench benchmarks/algebra/finite_field_quartic_bench.w
#   /tmp/finite_field_quartic_bench

use algebra

field = FiniteField.extension(5, 3)
c16 = field.coerce(16)
c48 = field.coerce(48)
cminus3 = field.coerce(-3)
c8 = field.coerce(8)
c162 = field.coerce(162)
c729 = field.coerce(729)

start = ccall("__w_clock_ms")
points = 0
x = 0
while x < field.order
  x2 = field.multiply(x, x)
  x3 = field.multiply(x2, x)
  y = 0
  while y < field.order
    y2 = field.multiply(y, y)
    y3 = field.multiply(y2, y)
    y4 = field.multiply(y2, y2)
    value = field.multiply(c16, x3)
    value = field.add(value, field.multiply(c48, field.multiply(x, y2)))
    value = field.add(value, field.multiply(cminus3, y4))
    value = field.add(value, field.multiply(c8, y3))
    value = field.add(value, field.multiply(c162, y2))
    value = field.add(value, c729)
    points += 1 if field.zero?(value)
    y += 1
  x += 1
elapsed = ccall("__w_clock_ms") - start

raise "quartic affine point count changed" if points != 121
<< "F_125 quartic affine_evaluations=15625 points=" + points.to_s + " elapsed_ms=" + elapsed.to_s
