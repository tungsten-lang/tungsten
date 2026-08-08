# Dot-prefix elementwise operators under the TREE WALKER (`tungsten run`).
# The compiled path lowers `.+ .- .* ./ .| .& .^ .<< .>>` to w_array_*_elem
# runtime kernels (lowering/ops.w); the interpreter routes to the same kernels
# (apply_binary_op), so results must match the compiled engine exactly.
# Regression: these ops raised "Unknown operator: DOT_STAR" interpreted.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = f64[8]
b = f64[8]
i = 0 ## i64
while i < 8
  a[i] = ~1.5
  b[i] = ~2.0
  i = i + 1
c = a .* b
# Machine-float wants (~3.0, not 3.0): f64[] kernels return machine Floats,
# and the 8/7 exactness landing makes boxed Float == Decimal FALSE by design
# (same rule as 2.0 == 2). A bare 3.0 literal is an exact Decimal once it
# crosses the check() call boundary, so it can never equal the kernel result.
check("dot.f64_mul", c[7], ~3.0)
d = a .+ b
check("dot.f64_add", d[0], ~3.5)

x = i64[4]
j = 0 ## i64
while j < 4
  x[j] = j + 1
  j = j + 1
check("dot.i64_mul", (x .* x)[3], 16)
check("dot.i64_scalar_add", (x .+ 10)[0], 11)
check("dot.i64_xor", (x .^ x)[2], 0)
check("dot.i64_shl", (x .<< 2)[1], 8)
