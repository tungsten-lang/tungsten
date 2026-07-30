# Certified real-root isolation over Q, refinable algebraic real values, and
# the symbolic solve bridge. Run in interpreter and native engines.

use algebra

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

ring = PolynomialRing.new([:x], RationalField.new)
x = ring.generator(0)

endpoint_polynomial = x * (x - 1)
check("sturm.open.all",
      endpoint_polynomial.sturm_root_count(-1, 2) == 2)
check("sturm.open.excludes_endpoints",
      endpoint_polynomial.sturm_root_count(0, 1) == 0)
check("sturm.closed.includes_endpoints",
      endpoint_polynomial.sturm_root_count_closed(0, 1) == 2)
check("sturm.left_endpoint",
      endpoint_polynomial.sturm_root_count_closed(-1, 0) == 1)

repeated = (x + 2) * (x - 1)**3 * (x**2 + 1)
check("sturm.distinct_repeated", repeated.real_root_count == 2)
check("bound.strict",
      repeated.cauchy_root_bound > Rational.new(2))

one_real = x**3 - x + 1
isolation = one_real.real_root_isolation
check("isolation.class", isolation.class_name == "RealRootIsolation")
check("isolation.complete", isolation.roots.size == 1)
check("isolation.certified", isolation.certified?)

root = isolation.roots[0]
check("root.class", root.class_name == "AlgebraicRealRoot")
check("root.certified", root.certified?)
check("root.factor", root.defining_polynomial == one_real)
check("root.index", root.root_index == 0)
check("root.index.certified", root.certificate.root_index == 0)
check("root.interval.count",
      one_real.sturm_root_count(root.lower_bound, root.upper_bound) == 1)

old_width = root.width
refined = root.refined(8)
check("root.refine.narrower", refined.width < old_width)
check("root.refine.certified", refined.certified?)
check("root.refine.original_immutable", root.width == old_width)
check("root.approximation.rational",
      root.approximation(20).class_name == "Rational")
check("root.approximation.value",
      close?(root.to_f, ~-1.324717957244746, ~1.0e-14))
check("root.comparison.zero", (root <=> 0) < 0)

three_real = x**3 - x*3 + 1
three_isolation = three_real.real_root_isolation
three_roots = three_isolation.roots
check("three.complete", three_roots.size == 3)
check("three.certified", three_isolation.certified?)
check("three.sorted.first", (three_roots[0] <=> three_roots[1]) < 0)
check("three.sorted.second", (three_roots[1] <=> three_roots[2]) < 0)
indices_ok = three_roots[0].root_index == 0
indices_ok = indices_ok && three_roots[1].root_index == 1
indices_ok = indices_ok && three_roots[2].root_index == 2
check("three.indices", indices_ok)

bad_interval = RootIsolationCertificate.new(three_real, -3, 3)
check("certificate.rejects_multiple_roots", !bad_interval.verified?)
bad_index = RootIsolationCertificate.new(
  three_real,
  three_roots[0].lower_bound,
  three_roots[0].upper_bound,
  2)
check("certificate.rejects_wrong_index", !bad_index.verified?)
missing = RealRootIsolation.new(three_real, [three_roots[0]])
check("certificate.rejects_incomplete_list", !missing.certified?)

mixed = (x - 2) * (x**3 - x - 1) * (x**2 - 2)
mixed_roots = mixed.real_roots
check("mixed.count", mixed_roots.size == 4)
check("mixed.sorted.0", (mixed_roots[0] <=> mixed_roots[1]) < 0)
check("mixed.sorted.1", (mixed_roots[1] <=> mixed_roots[2]) < 0)
check("mixed.sorted.2",
      Polynomial.real_root_compare(mixed_roots[2], mixed_roots[3]) < 0)
check("mixed.rational_last",
      mixed_roots[3] == Rational.new(2))
check("mixed.certified", mixed.real_root_isolation.certified?)

repeated_irreducible = one_real**3
check("repeated.distinct", repeated_irreducible.real_roots.size == 1)
check("no_real_roots", (x**2 + 1).real_roots.size == 0)

symbol = Expression.variable(:x)
symbolic_cubic = (symbol**3 - symbol + 1).solve(:x)
check("symbolic.cubic.count", symbolic_cubic.size == 1)
check("symbolic.cubic.expression", symbolic_cubic[0].constant?)
symbolic_root = symbolic_cubic[0].constant_value
check("symbolic.cubic.root_object",
      symbolic_root.class_name == "AlgebraicRealRoot")
check("symbolic.cubic.certified", symbolic_root.certified?)
check("symbolic.cubic.value",
      close?(symbolic_root.to_f, ~-1.324717957244746, ~1.0e-14))

symbolic_three = (symbol**3 - symbol*3 + 1).solve(:x)
check("symbolic.three_roots", symbolic_three.size == 3)
check("symbolic.facade",
      Algebra.solve(symbol**3 - symbol + 1, :x).size == 1)

# Quadratics retain the readable exact radical surface.
quadratic_roots = (symbol**2 - 2).solve(:x)
check("symbolic.quadratic.negative",
      quadratic_roots[0] == -Expression.constant(2).sqrt)
check("symbolic.quadratic.positive",
      quadratic_roots[1] == Expression.constant(2).sqrt)

finite_ring = PolynomialRing.new([:t], FiniteField.new(5))
finite_t = finite_ring.generator(0)
finite_raised = false
begin
  (finite_t**2 + 1).real_roots
rescue error
  finite_raised = true
check("boundary.finite_field_is_loud", finite_raised)

zero_raised = false
begin
  ring.zero.real_roots
rescue error
  zero_raised = true
check("boundary.zero_is_loud", zero_raised)

<< "algebra_real_roots_spec: all checks passed"
