# Higher-order differentiation, multivariate AD, quadrature, and stable
# transcendental regressions.
#
# Run in both engines:
#   bin/tungsten run spec/core/calculus_spec.w
#   bin/tungsten compile spec/core/calculus_spec.w --out /tmp/calculus-spec

use calculus

-> calculus_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> relative_close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

# --- arbitrary-order univariate derivatives -------------------------------

poly = -> (x) x**5
calculus_check("jet.polynomial.fourth",
               close?(Calculus.derivative(poly, ~2.0, 4), ~240.0),
               true)
calculus_check("jet.polynomial.fifth",
               close?(Calculus.derivative(poly, ~2.0, 5), ~120.0),
               true)

transcendental = -> (x) x.exp * x.sin
jet = Calculus.taylor(transcendental, ~0.0, 5)
calculus_check("jet.value", close?(jet.value, ~0.0), true)
calculus_check("jet.first", close?(jet.derivative_value(1), ~1.0), true)
calculus_check("jet.second", close?(jet.derivative_value(2), ~2.0), true)
calculus_check("jet.third", close?(jet.derivative_value(3), ~2.0), true)
calculus_check("jet.fourth", close?(jet.derivative_value(4), ~0.0), true)
tanh_jet = Calculus.taylor(-> (x) x.tanh, ~0.0, 3)
calculus_check("jet.tanh.first",
               close?(tanh_jet.derivative_value(1), ~1.0), true)
calculus_check("jet.tanh.third",
               close?(tanh_jet.derivative_value(3), ~-2.0), true)

log_jet = Calculus.taylor(-> (x) x.log, ~1.0, 5)
calculus_check("jet.log.fifth",
               close?(log_jet.derivative_value(5), ~24.0),
               true)
sqrt_jet = Calculus.taylor(-> (x) x.sqrt, ~4.0, 2)
calculus_check("jet.sqrt.first",
               close?(sqrt_jet.derivative_value(1), ~0.25),
               true)
calculus_check("jet.sqrt.second",
               close?(sqrt_jet.derivative_value(2), ~-0.03125),
               true)

# --- one-pass multivariate gradient and Hessian ---------------------------

surface = -> (variables)
  x = variables[0]
  y = variables[1]
  x * x * y + (x * y).sin

point = [~1.0, ~2.0]
bundle = Calculus.value_gradient_hessian(surface, point)
sin2 = Math.sin(~2.0)
cos2 = Math.cos(~2.0)
calculus_check("differential.value",
               close?(bundle["value"], ~2.0 + sin2),
               true)
calculus_check("differential.gradient.x",
               close?(bundle["gradient"][0], ~4.0 + ~2.0 * cos2),
               true)
calculus_check("differential.gradient.y",
               close?(bundle["gradient"][1], ~1.0 + cos2),
               true)
calculus_check("differential.hessian.xx",
               close?(bundle["hessian"][0][0], ~4.0 - ~4.0 * sin2),
               true)
calculus_check("differential.hessian.xy",
               close?(bundle["hessian"][0][1],
                      ~2.0 + cos2 - ~2.0 * sin2),
               true)
calculus_check("differential.hessian.symmetric",
               close?(bundle["hessian"][0][1], bundle["hessian"][1][0]),
               true)
calculus_check("differential.hessian.yy",
               close?(bundle["hessian"][1][1], ~0.0 - sin2),
               true)

mapping = -> (variables)
  x = variables[0]
  y = variables[1]
  [x * y, x.sin + y.cos]

jacobian = Calculus.jacobian(mapping, [~2.0, ~3.0])
calculus_check("jacobian.product.x", close?(jacobian[0][0], ~3.0), true)
calculus_check("jacobian.product.y", close?(jacobian[0][1], ~2.0), true)
calculus_check("jacobian.transcendental.x",
               close?(jacobian[1][0], Math.cos(~2.0)),
               true)
calculus_check("jacobian.transcendental.y",
               close?(jacobian[1][1], ~0.0 - Math.sin(~3.0)),
               true)

# --- adaptive quadrature ---------------------------------------------------

quartic_integral = Calculus.integrate(
  -> (x) x * x * x * x, ~0.0, ~1.0)
calculus_check("quadrature.quartic.converged",
               quartic_integral.converged?, true)
calculus_check("quadrature.quartic.value",
               close?(quartic_integral.value, ~0.2, ~1.0e-10), true)
calculus_check("quadrature.quartic.error",
               quartic_integral.error_estimate < ~1.0e-9, true)
calculus_check("quadrature.metadata",
               quartic_integral.evaluations >= 5, true)

sine_integral = Calculus.quad(
  -> (x) Math.sin(x), ~0.0, ~3.141592653589793)
calculus_check("quadrature.sine",
               close?(sine_integral.value, ~2.0, ~1.0e-10), true)
reverse_integral = Calculus.integrate(
  -> (x) x * x, ~1.0, ~0.0)
calculus_check("quadrature.reversed",
               close?(reverse_integral.value, ~-0.3333333333333333,
                      ~1.0e-10),
               true)

limited = Calculus.integrate(
  -> (x) Math.exp(x), ~0.0, ~1.0, ~1.0e-16, ~0.0, 0)
calculus_check("quadrature.limit_visible", limited.converged?, false)
calculus_check("quadrature.not_certified", limited.certified?, false)

# --- stable derived transcendental edge cases -----------------------------

calculus_check("math.expm1.tiny",
               close?(Math.expm1(~1.0e-12), ~1.0e-12, ~1.0e-24),
               true)
calculus_check("math.log1p.tiny",
               close?(Math.log1p(~1.0e-12), ~1.0e-12, ~1.0e-24),
               true)
calculus_check("math.tanh.positive_saturation",
               Math.tanh(~1000.0), ~1.0)
calculus_check("math.tanh.negative_saturation",
               Math.tanh(~-1000.0), ~-1.0)
calculus_check("math.hypot.scaled",
               relative_close?(Math.hypot(~3.0e200, ~4.0e200), ~5.0e200),
               true)
calculus_check("math.asin.endpoint",
               close?(Math.asin(~1.0), ~1.5707963267948966), true)
calculus_check("math.acos.endpoint",
               close?(Math.acos(~-1.0), ~3.141592653589793), true)

<< "calculus_spec: all checks passed"
