use core/blas

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# A mutating BLAS ccall inside a typed helper must execute on every call. If
# lowering misclassifies the bridge as pure, function memoization incorrectly
# elides the second scale and leaves 6 rather than 12.
fn scale_once(x)
  dscal(2, x, 1)

x = f64_array(1)
x[0] = ~3.0
scale_once(x)
scale_once(x)
expect("compiler mutating BLAS ccall is impure", x[0] == ~12.0)
