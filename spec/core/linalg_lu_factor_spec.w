use core/linalg

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  (actual - expected).abs < ~0.000000001

a = [[~4.0, ~1.0, ~2.0], [~0.0, ~3.0, ~-1.0], [~2.0, ~0.0, ~5.0]]
factor = LinAlg.factor_lu(a)
x1 = factor.solve([~7.0, ~2.0, ~9.0])
x2 = factor.solve([~1.0, ~4.0, ~-2.0])
expect("linalg.lu dimension", factor.dimension == 3)
expect("linalg.lu first residual", close?(a[0][0] * x1[0] + a[0][1] * x1[1] + a[0][2] * x1[2], ~7.0))
expect("linalg.lu second RHS residual", close?(a[2][0] * x2[0] + a[2][1] * x2[1] + a[2][2] * x2[2], ~-2.0))

rhs = f64[3]
out = f64[3]
rhs[0] = ~7.0
rhs[1] = ~2.0
rhs[2] = ~9.0
returned = factor.solve_into(rhs, out)
expect("linalg.lu solve_into value", close?(out[1], x1[1]))
expect("linalg.lu solve_into returns output", close?(returned[2], x1[2]))

singular_failed = false
begin
  LinAlg.factor_lu([[~1.0, ~2.0], [~2.0, ~4.0]])
rescue err
  singular_failed = true
expect("linalg.lu singular failure", singular_failed)

shape_failed = false
begin
  LinAlg.factor_lu([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]])
rescue err
  shape_failed = true
expect("linalg.lu shape failure", shape_failed)

rhs_failed = false
begin
  factor.solve([~1.0, ~2.0])
rescue err
  rhs_failed = true
expect("linalg.lu RHS failure", rhs_failed)
