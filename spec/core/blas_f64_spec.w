use core/blas

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  delta < ~0.00001

a = f64_array(6)
b = f64_array(3)
x = f64_array(3)
y = f64_array(3)
i = 0
while i < 6
  a[i] = (i + 1).to_f
  i += 1
b[0] = ~4.0
b[1] = ~5.0
b[2] = ~6.0
x[0] = ~1.0
x[1] = ~2.0
x[2] = ~3.0
y[0] = ~4.0
y[1] = ~5.0
y[2] = ~6.0

expect("blas.ddot", close?(ddot(a, b, 3), ~32.0))
expect("blas.dnrm2", close?(dnrm2(x, 3), Math.sqrt(~14.0)))
daxpy(~2.0, x, y, 3)
expect("blas.daxpy", close?(y[0], ~6.0) && close?(y[2], ~12.0))

out = f64_array(2)
dgemv(a, x, out, 2, 3)
expect("blas.dgemv", close?(out[0], ~14.0) && close?(out[1], ~32.0))
