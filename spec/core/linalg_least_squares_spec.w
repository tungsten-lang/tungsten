use core/linalg

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  (actual - expected).abs < ~0.000000001

a = [[~1.0, ~0.0], [~0.0, ~1.0], [~1.0, ~1.0]]
solution = LinAlg.least_squares(a, [~1.0, ~2.0, ~2.9])
expect("linalg.least_squares solution", close?(solution[0], ~0.9666666666666667) && close?(solution[1], ~1.9666666666666667))

factor = LinAlg.factor_qr(a)
factor_solution = factor.solve([~1.0, ~2.0, ~2.9])
expect("linalg.qr factor dimensions", factor.rows == 3 && factor.columns == 2)
expect("linalg.qr factor solution", close?(factor_solution[0], solution[0]) && close?(factor_solution[1], solution[1]))
rhs_into = f64[3]
out_into = f64[3]
rhs_into[0] = ~1.0
rhs_into[1] = ~2.0
rhs_into[2] = ~2.9
returned = factor.solve_into(rhs_into, out_into)
expect("linalg.qr factor solve_into", close?(out_into[0], solution[0]) && close?(returned[1], solution[1]))
qr_overlap = f64[4]
qr_overlap[0] = ~1.0
qr_overlap[1] = ~2.0
qr_overlap[2] = ~2.9
qr_overlap[3] = ~0.0
factor.solve_into(qr_overlap.slice(0, 3), qr_overlap.slice(1, 3))
expect("linalg.qr factor solve_into overlap-safe",
       close?(qr_overlap[1], solution[0]) && close?(qr_overlap[2], solution[1]))
many = factor.solve_many([[~1.0, ~2.0, ~2.9], [~3.0, ~4.0, ~7.1]])
expected_many = LinAlg.least_squares(a, [~3.0, ~4.0, ~7.1])
expect("linalg.qr factor batched RHS", close?(many[0][1], solution[1]) && close?(many[1][0], expected_many[0]))
many_rhs = f64[6]
many_out = f64[6]
i = 0
while i < 3
  many_rhs[i] = rhs_into[i]
  many_rhs[3 + i] = [~3.0, ~4.0, ~7.1][i]
  i += 1
factor.solve_many_into(many_rhs, many_out, 2)
expect("linalg.qr factor batched into", close?(many_out[1], solution[1]) && close?(many_out[3], expected_many[0]))
qr_many_overlap = f64[7]
i = 0
while i < 6
  qr_many_overlap[i] = many_rhs[i]
  i += 1
factor.solve_many_into(qr_many_overlap.slice(0, 6), qr_many_overlap.slice(1, 6), 2)
expect("linalg.qr factor batched overlap-safe",
       close?(qr_many_overlap[1], solution[0]) && close?(qr_many_overlap[5], expected_many[1]))

rank_failed = false
begin
  LinAlg.least_squares([[~1.0, ~2.0], [~2.0, ~4.0], [~3.0, ~6.0]], [~1.0, ~2.0, ~3.0])
rescue err
  rank_failed = true
expect("linalg.least_squares rank failure", rank_failed)

factor_rank_failed = false
begin
  LinAlg.factor_qr([[~1.0, ~2.0], [~2.0, ~4.0], [~3.0, ~6.0]])
rescue err
  factor_rank_failed = true
expect("linalg.qr factor rank failure", factor_rank_failed)

shape_failed = false
begin
  LinAlg.least_squares([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]], [~1.0, ~2.0])
rescue err
  shape_failed = true
expect("linalg.least_squares underdetermined failure", shape_failed)

rhs_failed = false
begin
  LinAlg.least_squares(a, [~1.0, ~2.0])
rescue err
  rhs_failed = true
expect("linalg.least_squares RHS failure", rhs_failed)
