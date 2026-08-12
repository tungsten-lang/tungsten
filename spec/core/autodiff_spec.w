# Autodiff spec — forward-mode automatic differentiation.

use core/autodiff

# d/dx (x^2 + 3x + 5) = 2x + 3; at x = 4, derivative is 11
f = ->(x) x.pow(~2.0) + x * ~3.0 + ~5.0
df = Autodiff.grad(f, ~4.0)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("autodiff.grad", df == ~11.0)
