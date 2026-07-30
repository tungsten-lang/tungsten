# Polynomial-backed symbolic factorization and exact real solving.

use algebra

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

x, y = Expression.variables([:x, :y])

quadratic = x**2 - 1
factors = quadratic.factor_list(:x)
check("factor.count", factors.size == 2)
check("factor.product", Expression.product(factors).expand == quadratic)
check("factor.facade", Algebra.factor(quadratic, :x).expand == quadratic)

repeated = (x**2 + 1)**2
repeated_factors = repeated.factor_list(:x)
check("factor.repeated.count", repeated_factors.size == 2)
check("factor.repeated.value",
      repeated_factors[0] == x**2 + 1 && repeated_factors[1] == x**2 + 1)

linear_roots = (x*3 - 2).solve(:x)
check("solve.linear.count", linear_roots.size == 1)
check("solve.linear.exact",
      linear_roots[0] == Expression.constant(Rational.new(2, 3)))

rational_roots = (x**2 - x*5 + 6).real_roots(:x)
check("solve.quadratic.rational.count", rational_roots.size == 2)
check("solve.quadratic.rational.first",
      rational_roots[0] == Expression.constant(2))
check("solve.quadratic.rational.second",
      rational_roots[1] == Expression.constant(3))

radical_roots = (x**2 - 2).solve(:x)
check("solve.quadratic.radical.count", radical_roots.size == 2)
check("solve.quadratic.radical.negative",
      radical_roots[0] == -Expression.constant(2).sqrt)
check("solve.quadratic.radical.positive",
      radical_roots[1] == Expression.constant(2).sqrt)

check("solve.no_real_roots", (x**2 + 1).solve(:x).size == 0)
check("solve.high_degree_factored",
      (x**4 - 1).solve(:x).size == 2)
check("solve.repeated_root_is_distinct",
      ((x - 1)**3).solve(:x).size == 1)
check("solve.facade",
      Algebra.solve(x**2 - 1, :x).size == 2)

multivariate_raised = false
begin
  (x + y).factor(:x)
rescue error
  multivariate_raised = true
check("factor.multivariate_is_loud", multivariate_raised)

irreducible_cubic_roots = (x**3 - x + 1).solve(:x)
check("solve.irreducible_cubic.count",
      irreducible_cubic_roots.size == 1)
check("solve.irreducible_cubic.certified",
      irreducible_cubic_roots[0].constant_value.certified?)

zero_raised = false
begin
  Expression.constant(0).solve(:x)
rescue error
  zero_raised = true
check("solve.zero_is_loud", zero_raised)

<< "expression_solve_spec: all checks passed"
