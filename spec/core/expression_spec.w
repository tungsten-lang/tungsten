# Canonical symbolic expressions, exact differentiation, active-value
# evaluation, and the exact PolynomialRing bridge.
#
# Run in both engines:
#   bin/tungsten run spec/core/expression_spec.w
#   bin/tungsten compile spec/core/expression_spec.w \
#     --out /tmp/tungsten-expression-spec

use calculus
use algebra

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

x, y = Calculus.symbols([:x, :y])

# --- canonical construction and simplification ---------------------------

check("symbol.class", x.class_name == "Expression")
check("symbol.name", x.name == :x)
check("symbol.facade", Calculus.symbol(:x) == x)
check("simplify.like_terms", (x + x).to_s == "2*x")
check("simplify.cancel_terms", x - x == Expression.constant(0))
check("simplify.repeated_factors", x * x * x == x**3)
check("simplify.commutative_add", x + y == y + x)
check("simplify.commutative_mul", x * y == y * x)
check("simplify.collect_coefficients",
      x*2 + x*3 - x == x*4)
check("simplify.collect_rational_coefficients",
      x + x*Rational.new(1, 2) == x*Rational.new(3, 2))
check("simplify.flatten_add",
      (x + y) + (x + y) == x*2 + y*2)
check("simplify.flatten_mul",
      (x * y) * (x**2) == x**3 * y)
check("simplify.power_of_power", (x**2)**3 == x**6)
check("simplify.zero_product", x * 0 * y == Expression.constant(0))
check("simplify.unit_product", x * 1 == x)
check("simplify.unit_power", x**1 == x)
check("simplify.zero_power", x**0 == Expression.constant(1))
check("simplify.quotient", x / x == Expression.constant(1))
check("simplify.log_exp", x.exp.log == x)
check("simplify.sqrt_square", (x**2).sqrt == x.abs)
check("simplify.absolute_idempotent", x.abs.abs == x.abs)
check("simplify.exact_fraction",
      (Expression.constant(1) / 2).constant_value == Rational.new(1, 2))
check("simplify.negative_power_exact",
      (Expression.constant(2)**-3).constant_value == Rational.new(1, 8))
check("simplify.acos_zero_exact",
      Expression.constant(0).acos == Expression.pi / 2)
check("simplify.acos_zero_value",
      close?(Expression.constant(0).acos.evaluate({}),
             ~1.5707963267948966))

free = (x.sin + y**2).free_variables
check("variables.free",
      free.size == 2 && free[0] == :x && free[1] == :y)
check("variables.depends.true", (x + y).depends_on?(:x))
check("variables.depends.false", !x.depends_on?(:z))
check("complexity.visible", (x.sin + y**2).complexity == 6)

# --- substitution and evaluation -----------------------------------------

formula = x**2 + y**2 + (x * y).sin
substituted = formula.substitute({y: x + 1})
substituted_free = substituted.free_variables
check("substitute.removes_variable",
      substituted_free.size == 1 && substituted_free[0] == :x)
check("substitute.value",
      close?(substituted.evaluate({x: ~2.0}),
             ~4.0 + ~9.0 + Math.sin(~6.0)))
check("evaluate.symbol_keys",
      close?(formula.evaluate({x: ~1.0, y: ~2.0}),
             ~5.0 + Math.sin(~2.0)))
check("evaluate.string_keys",
      close?(formula.evaluate({"x": ~1.0, "y": ~2.0}),
             ~5.0 + Math.sin(~2.0)))

missing_binding_raised = false
begin
  formula.evaluate({x: ~1.0})
rescue error
  missing_binding_raised = true
check("evaluate.missing_binding_is_loud", missing_binding_raised)

<< "expression_spec: all checks passed"
