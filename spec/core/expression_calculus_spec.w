# Exact symbolic derivatives, gradients, and Hessians checked against
# second-order automatic differentiation.
#
# Run in both engines:
#   bin/tungsten run spec/core/expression_calculus_spec.w
#   bin/tungsten compile spec/core/expression_calculus_spec.w \
#     --out /tmp/tungsten-expression-calculus-spec

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

x, y = Calculus.symbols([:x, :y])
smooth = x**3 * y + (x * y).sin + x.log1p
dx = smooth.derivative(:x)
dy = smooth.diff(:y)

expected_dx = x**2 * y * 3 + (x * y).cos * y
expected_dx += Expression.constant(1) / (x + 1)
expected_dy = x**3 + (x * y).cos * x
check("differentiate.dx.canonical", dx == expected_dx)
check("differentiate.dy.canonical", dy == expected_dy)

point = {x: ~0.25, y: ~-0.4}
expected_dx_value = ~3.0 * ~0.25 * ~0.25 * ~-0.4
expected_dx_value += Math.cos(~-0.1) * ~-0.4
expected_dx_value += ~1.0 / ~1.25
expected_dy_value = ~0.25 * ~0.25 * ~0.25
expected_dy_value += Math.cos(~-0.1) * ~0.25
check("differentiate.dx.value",
      close?(dx.evaluate(point), expected_dx_value))
check("differentiate.dy.value",
      close?(dy.evaluate(point), expected_dy_value))

gradient = Calculus.symbolic_gradient(smooth, [:x, :y])
hessian = Calculus.symbolic_hessian(smooth, [:x, :y])
check("symbolic.gradient",
      gradient.size == 2 && gradient[0] == dx && gradient[1] == dy)
check("symbolic.hessian.symmetric", hessian[0][1] == hessian[1][0])

bundle = Calculus.value_gradient_hessian(
  -> (variables)
    smooth.evaluate({x: variables[0], y: variables[1]}),
  [~0.25, ~-0.4])
check("symbolic.vs.ad.gradient.x",
      close?(dx.evaluate(point), bundle["gradient"][0]))
check("symbolic.vs.ad.gradient.y",
      close?(dy.evaluate(point), bundle["gradient"][1]))
check("symbolic.vs.ad.hessian.xx",
      close?(hessian[0][0].evaluate(point), bundle["hessian"][0][0]))
check("symbolic.vs.ad.hessian.xy",
      close?(hessian[0][1].evaluate(point), bundle["hessian"][0][1]))
check("symbolic.vs.ad.hessian.yy",
      close?(hessian[1][1].evaluate(point), bundle["hessian"][1][1]))

check("differentiate.log_exp", x.exp.log.derivative(:x) == Expression.constant(1))
check("differentiate.absolute",
      x.abs.derivative(:x) == x / x.abs)
check("differentiate.inverse_trig",
      x.asin.derivative(:x) ==
        Expression.constant(1) / (Expression.constant(1) - x**2).sqrt)
check("differentiate.inverse_hyperbolic",
      x.atanh.derivative(:x) ==
        Expression.constant(1) / (Expression.constant(1) - x**2))
check("differentiate.general_power",
      (x**x).derivative(:x) == x**x * (x.log + 1))
check("differentiate.quotient",
      (x / (x + 1)).derivative(:x) == Expression.constant(1) / (x + 1)**2)

# Every supported elementary function differentiates consistently with the
# independent TaylorJet propagation path.
derivative_cases = [
  ["exp", x.exp, ~0.2],
  ["log", x.log, ~1.3],
  ["sqrt", x.sqrt, ~1.3],
  ["sin", x.sin, ~0.2],
  ["cos", x.cos, ~0.2],
  ["tan", x.tan, ~0.2],
  ["sinh", x.sinh, ~0.2],
  ["cosh", x.cosh, ~0.2],
  ["tanh", x.tanh, ~0.2],
  ["asin", x.asin, ~0.2],
  ["acos", x.acos, ~0.2],
  ["atan", x.atan, ~0.2],
  ["asinh", x.asinh, ~0.2],
  ["acosh", x.acosh, ~1.3],
  ["atanh", x.atanh, ~0.2],
  ["expm1", x.expm1, ~0.2],
  ["log1p", x.log1p, ~0.2],
  ["log2", x.log2, ~1.3],
  ["log10", x.log10, ~1.3],
  ["cbrt", x.cbrt, ~1.3],
  ["abs", x.abs, ~-1.3]
]

derivative_cases.each -> (entry)
  active = TaylorJet.variable(entry[2], 1)
  active_derivative = entry[1].evaluate({x: active}).derivative_value(1)
  symbolic_derivative = entry[1].derivative(:x).evaluate({x: entry[2]})
  check("elementary." + entry[0],
        close?(symbolic_derivative, active_derivative, ~2.0e-10))

<< "expression_calculus_spec: all checks passed"
