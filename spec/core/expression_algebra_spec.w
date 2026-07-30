# Symbolic expression interoperability with active calculus values, Complex,
# and exact PolynomialRing values.
#
# Run in both engines:
#   bin/tungsten run spec/core/expression_algebra_spec.w
#   bin/tungsten compile spec/core/expression_algebra_spec.w \
#     --out /tmp/tungsten-expression-algebra-spec

use calculus
use algebra

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> complex_close?(got, want)
  real_difference = got.real - want.real
  real_difference = ~0.0 - real_difference if real_difference < ~0.0
  imag_difference = got.imag - want.imag
  imag_difference = ~0.0 - imag_difference if imag_difference < ~0.0
  real_difference <= ~2.0e-12 && imag_difference <= ~2.0e-12

x, y = Calculus.symbols([:x, :y])

# --- evaluate one formula in every active numeric mode --------------------

transcendental = x.exp * x.sin
check("active.jet.first",
      close?(
        Calculus.derivative(
          -> (active) transcendental.evaluate({x: active}),
          ~0.0),
        ~1.0))
third_order_active = TaylorJet.variable(~0.0, 3)
third_order_result = transcendental.evaluate({x: third_order_active})
check("active.jet.third",
      close?(third_order_result.derivative_value(3), ~2.0))

complex_point = Complex<f64>.new([~0.2, ~0.3])
complex_symbolic = (x.exp + x.sin).evaluate({x: complex_point})
complex_direct = complex_point.exp + complex_point.sin
check("active.complex",
      complex_close?(complex_symbolic, complex_direct))

active_surface = x**2 * y + (x * y).sin
active_bundle = Calculus.value_gradient_hessian(
  -> (variables)
    active_surface.evaluate({x: variables[0], y: variables[1]}),
  [~0.5, ~-0.25])
symbolic_hessian = active_surface.hessian([:x, :y])
active_point = {x: ~0.5, y: ~-0.25}
check("active.differential.gradient",
      close?(active_surface.derivative(:x).evaluate(active_point),
             active_bundle["gradient"][0]))
check("active.differential.hessian",
      close?(symbolic_hessian[0][1].evaluate(active_point),
             active_bundle["hessian"][0][1]))

# --- exact polynomial bridge ---------------------------------------------

ring = PolynomialRing.new([:x, :y], RationalField.new)
px, py = ring.generators
polynomial_expression = x**3 * Rational.new(1, 2) + x*y*3 - y + Rational.new(5, 7)
polynomial = polynomial_expression.to_polynomial(ring)
expected_polynomial = px**3 * Rational.new(1, 2) + px*py*3 - py + Rational.new(5, 7)

check("polynomial.convert", polynomial == expected_polynomial)
check("polynomial.predicate", polynomial_expression.polynomial_expression?)
check("polynomial.transcendental_predicate", !x.sin.polynomial_expression?)
check("polynomial.round_trip",
      polynomial.to_expression == polynomial_expression)
symbolic_polynomial_derivative = polynomial_expression.derivative(:x).to_polynomial(ring)
check("polynomial.derivative_commutes",
      symbolic_polynomial_derivative == polynomial.derivative(:x))
check("polynomial.evaluate_active",
      (x**2 + x*2 + 1).evaluate({x: px}) == px**2 + px*2 + 1)
check("polynomial.constant_denominator",
      (x / 2).to_polynomial(ring) == px * Rational.new(1, 2))

transcendental_conversion_raised = false
begin
  x.sin.to_polynomial(ring)
rescue error
  transcendental_conversion_raised = true
check("polynomial.transcendental_is_loud",
      transcendental_conversion_raised)

rational_conversion_raised = false
begin
  (x / (y + 1)).to_polynomial(ring)
rescue error
  rational_conversion_raised = true
check("polynomial.denominator_is_loud", rational_conversion_raised)

unknown_variable_raised = false
begin
  Expression.variable(:z).to_polynomial(ring)
rescue error
  unknown_variable_raised = true
check("polynomial.unknown_variable_is_loud", unknown_variable_raised)

finite_ring = PolynomialRing.new([:t], FiniteField.new(5))
finite_t = finite_ring.generator(0)
finite_conversion_raised = false
begin
  (finite_t**2 + finite_t + 1).to_expression
rescue error
  finite_conversion_raised = true
check("polynomial.finite_field_boundary_is_loud",
      finite_conversion_raised)

<< "expression_algebra_spec: all checks passed"
