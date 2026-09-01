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

lu_overlap_storage = f64[4]
lu_overlap_storage[0] = ~7.0
lu_overlap_storage[1] = ~2.0
lu_overlap_storage[2] = ~9.0
lu_overlap_storage[3] = ~0.0
factor.solve_into(lu_overlap_storage.slice(0, 3), lu_overlap_storage.slice(1, 3))
expect("linalg.lu solve_into overlap-safe",
       close?(lu_overlap_storage[1], x1[0]) && close?(lu_overlap_storage[3], x1[2]))

many = factor.solve_many([[~7.0, ~2.0, ~9.0], [~1.0, ~4.0, ~-2.0]])
expect("linalg.lu batched RHS", close?(many[0][1], x1[1]) && close?(many[1][2], x2[2]))
many_rhs = f64[6]
many_out = f64[6]
many_rhs[0] = ~7.0
many_rhs[1] = ~2.0
many_rhs[2] = ~9.0
many_rhs[3] = ~1.0
many_rhs[4] = ~4.0
many_rhs[5] = ~-2.0
factor.solve_many_into(many_rhs, many_out, 2)
expect("linalg.lu batched into", close?(many_out[1], x1[1]) && close?(many_out[5], x2[2]))
lu_many_overlap = f64[7]
i = 0
while i < 6
  lu_many_overlap[i] = many_rhs[i]
  i += 1
factor.solve_many_into(lu_many_overlap.slice(0, 6), lu_many_overlap.slice(1, 6), 2)
expect("linalg.lu batched overlap-safe",
       close?(lu_many_overlap[2], many[0][1]) && close?(lu_many_overlap[6], many[1][2]))

spd = [[~4.0, ~1.0, ~1.0], [~1.0, ~3.0, ~0.0], [~1.0, ~0.0, ~2.0]]
chol = LinAlg.factor_cholesky(spd)
chol_x = chol.solve([~6.0, ~7.0, ~5.0])
expect("linalg.cholesky dimension", chol.dimension == 3)
expect("linalg.cholesky residual", close?(spd[0][0] * chol_x[0] + spd[0][1] * chol_x[1] + spd[0][2] * chol_x[2], ~6.0))
chol_overlap = f64[4]
chol_overlap[0] = ~6.0
chol_overlap[1] = ~7.0
chol_overlap[2] = ~5.0
chol_overlap[3] = ~0.0
chol.solve_into(chol_overlap.slice(0, 3), chol_overlap.slice(1, 3))
expect("linalg.cholesky solve_into overlap-safe",
       close?(chol_overlap[1], chol_x[0]) && close?(chol_overlap[3], chol_x[2]))
chol_many = chol.solve_many([[~6.0, ~7.0, ~5.0], [~1.0, ~2.0, ~3.0]])
expect("linalg.cholesky batched RHS", close?(spd[2][0] * chol_many[1][0] + spd[2][1] * chol_many[1][1] + spd[2][2] * chol_many[1][2], ~3.0))
chol_rhs = f64[6]
chol_out = f64[6]
i = 0
while i < 6
  chol_rhs[i] = many_rhs[i]
  i += 1
chol.solve_many_into(chol_rhs, chol_out, 2)
expect("linalg.cholesky batched into", close?(spd[1][0] * chol_out[3] + spd[1][1] * chol_out[4] + spd[1][2] * chol_out[5], ~4.0))
chol_many_overlap = f64[7]
i = 0
while i < 6
  chol_many_overlap[i] = chol_rhs[i]
  i += 1
chol.solve_many_into(chol_many_overlap.slice(0, 6), chol_many_overlap.slice(1, 6), 2)
expect("linalg.cholesky batched overlap-safe",
       close?(spd[1][0] * chol_many_overlap[4] + spd[1][1] * chol_many_overlap[5] + spd[1][2] * chol_many_overlap[6], ~4.0))

not_spd_failed = false
begin
  LinAlg.factor_cholesky([[~1.0, ~2.0], [~2.0, ~1.0]])
rescue err
  not_spd_failed = true
expect("linalg.cholesky SPD failure", not_spd_failed)

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
