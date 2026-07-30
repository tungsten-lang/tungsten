# Exact named constants, polynomial manipulation, and elementary symbolic
# integration. Run in both interpreter and native engines.

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

x, y = Calculus.symbols([:x, :y])

pi = Expression.pi
e = Expression.e
check("constant.pi.render", pi.to_s == "π")
check("constant.e.render", e.to_s == "e")
check("constant.pi.variables", pi.free_variables.size == 0)
check("constant.pi.derivative", pi.derivative(:x) == Expression.constant(0))
check("constant.pi.evaluate",
      close?(pi.evaluate({}), ~3.141592653589793))
check("constant.e.evaluate",
      close?(e.evaluate({}), Math.exp(~1.0)))
check("constant.exp_one_exact", Expression.constant(1).exp == e)
check("constant.log_e_exact", e.log == Expression.constant(1))
check("constant.log2_one_exact",
      Expression.constant(1).log2 == Expression.constant(0))
check("constant.acos_negative_one_exact",
      Expression.constant(-1).acos == pi)

sqrt_two = Expression.constant(2).sqrt
check("radical.sqrt_two.symbolic",
      sqrt_two.operation == "sqrt" && sqrt_two.arguments[0].constant_value == 2)
check("radical.sqrt_integer_exact",
      Expression.constant(144).sqrt == Expression.constant(12))
check("radical.sqrt_extracts_square",
      Expression.constant(8).sqrt == Expression.constant(2) * sqrt_two)
check("radical.sqrt_rational_exact",
      Expression.constant(Rational.new(9, 16)).sqrt ==
        Expression.constant(Rational.new(3, 4)))
check("radical.cube_integer_exact",
      Expression.constant(-125).cbrt == Expression.constant(-5))
check("radical.cube_extracts_cube",
      Expression.constant(16).cbrt ==
        Expression.constant(2) * Expression.constant(2).cbrt)
check("radical.cube_rational_exact",
      Expression.constant(Rational.new(8, 27)).cbrt ==
        Expression.constant(Rational.new(2, 3)))

check("trig.sin_pi", pi.sin == Expression.constant(0))
check("trig.sin_half_pi", (pi / 2).sin == Expression.constant(1))
check("trig.cos_pi", pi.cos == Expression.constant(-1))
check("trig.cos_half_pi", (pi / 2).cos == Expression.constant(0))
check("trig.tan_pi", pi.tan == Expression.constant(0))

log_two = Expression.constant(2).log
check("rational_form.cancel_factor",
      (Expression.constant(1) / log_two) * log_two ==
        Expression.constant(1))
check("rational_form.combine_scalar",
      (Expression.constant(1) / (Expression.constant(2) * log_two)) * 2 ==
        Expression.constant(1) / log_two)
check("rational_form.exact_denominator",
      (x + y) / 2 == (x + y) * Rational.new(1, 2))
check("rational_form.cancel_numerator_factor",
      (x*y) / x == y)
check("rational_form.cancel_scaled_factor",
      x / (x*2) == Expression.constant(Rational.new(1, 2)))

cube = (x + 1)**3
expanded_cube = cube.expand
expected_cube = x**3 + x**2*3 + x*3 + 1
check("expand.binomial", expanded_cube == expected_cube)
check("expand.idempotent", expanded_cube.expand == expanded_cube)

mixed = (x + y) * (x + 1)
check("collect.degree", mixed.degree_in(:x) == 2)
check("collect.coefficient.two",
      mixed.coefficient(:x, 2) == Expression.constant(1))
check("collect.coefficient.one", mixed.coefficient(:x, 1) == y + 1)
check("collect.coefficient.zero", mixed.coefficient(:x, 0) == y)
collected = mixed.collect(:x)
expected_collected = x**2 + x*(y + 1) + y
check("collect.expression", collected == expected_collected)
check("collect.expands_back", collected.expand == mixed.expand)

polynomial = x**3 + x*2 + 3
primitive = polynomial.antiderivative(:x)
check("integrate.polynomial.round_trip",
      primitive.derivative(:x) == polynomial)
linear_sine = (x*2 + 1).sin
linear_sine_primitive = Calculus.antiderivative(linear_sine, :x)
check("integrate.linear_sine.round_trip",
      linear_sine_primitive.derivative(:x) == linear_sine)
check("integrate.reciprocal",
      (Expression.constant(1) / x).antiderivative(:x) == x.abs.log)
check("integrate.definite.sin",
      x.sin.definite_integral(:x, 0, pi) == Expression.constant(2))
check("integrate.facade.definite",
      Calculus.symbolic_integrate(x, :x, 0, 2) == Expression.constant(2))

unsupported_raised = false
begin
  (x * x.sin).antiderivative(:x)
rescue error
  unsupported_raised = true
check("integrate.unsupported_is_loud", unsupported_raised)

<< "expression_exact_spec: all checks passed"
