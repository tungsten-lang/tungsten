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

rank_failed = false
begin
  LinAlg.least_squares([[~1.0, ~2.0], [~2.0, ~4.0], [~3.0, ~6.0]], [~1.0, ~2.0, ~3.0])
rescue err
  rank_failed = true
expect("linalg.least_squares rank failure", rank_failed)

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
