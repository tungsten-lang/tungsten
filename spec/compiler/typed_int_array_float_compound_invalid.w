# spec: compiled-rejects -- expected int, got double
# spec: interpreter-rejects -- expected int, got double
# `a[i] = a[i] + f` with a float f stores a float into an integer typed array.
# The fused compiled load-op-store added the boxed double's bits instead of
# raising like the interpreter.

-> tiac_bump(out, f) (i64[] f64) i64
  out[0] = out[0] + f
  0

xs = i64[1]
xs[0] = 5
tiac_bump(xs, ~0.5)
<< "stored " + xs[0].to_s
