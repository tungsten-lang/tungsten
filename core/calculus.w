# Calculus — differentiation, Taylor expansion, and numerical integration.
#
# `use calculus` is the feature flag.  Exact polynomial differentiation and
# integration remain methods on Polynomial; this module covers smooth numeric
# functions with replayable coefficient propagation, plus explicitly named
# black-box numerical estimates:
#
#   Calculus.derivative(f, x, order)
#   Calculus.taylor(f, x, order)
#   Calculus.gradient(f, point)
#   Calculus.jacobian(f, point)
#   Calculus.hessian(f, point)
#   Calculus.numerical_derivative(f, x, order, scheme)
#   Calculus.integrate(f, a, b, abs_tol, rel_tol, max_depth)
#   Calculus.integrate_gk15(f, a, b, abs_tol, rel_tol, max_intervals, max_evaluations)
#   Calculus.integrate_with_points(f, a, b, points)
#   Calculus.numerical_gradient(f, point)
#   Calculus.numerical_jacobian(f, point)
#   Calculus.jvp(f, point, tangent) / Calculus.vjp(f, point, cotangent)

use core/math
use core/numeric/rational
use core/expression
use core/calculus/certified_transcendentals
use core/calculus/series
use core/calculus/laurent
use core/calculus/puiseux
use core/calculus/jet
use core/calculus/differential
use core/calculus/numerical
use core/calculus/numerical_vector
use core/autodiff
use core/calculus/quadrature
use core/calculus/gauss_kronrod
use core/calculus/radial_mellin

+ Calculus
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .jvp(f, point, tangent)
    Autodiff.jvp(f, point, tangent)

  -> .vjp(f, point, cotangent)
    Autodiff.vjp(f, point, cotangent)

  -> .reverse_gradient(f, point)
    Autodiff.vjp(f, point, ~1.0)["vjp"]

  -> .validate_order(order)
    if !Calculus.integer?(order) || order < 0
      raise "calculus order must be a nonnegative integer"
    order

  -> .copy_vector(values)
    out = []
    values.each -> out.push(item)
    out

  -> .copy_matrix(values)
    out = []
    values.each -> out.push(Calculus.copy_vector(item))
    out

  -> .zero_vector(size)
    out = []
    size.times -> out.push(~0.0)
    out

  -> .zero_matrix(size)
    out = []
    size.times -> out.push(Calculus.zero_vector(size))
    out

  -> .abs(value)
    value < ~0.0 ? ~0.0 - value : value

  -> .finite_f64?(value)
    return false if value.class_name != "Float"
    !value.nan? && !value.infinite?

  -> .within_tolerance?(error, magnitude, abs_tol, rel_tol)
    return false if !Calculus.finite_f64?(error) || error < ~0.0
    return true if error <= abs_tol
    return false if magnitude == ~0.0 || rel_tol == ~0.0
    error / magnitude <= rel_tol

  -> .midpoint(a, b)
    ~0.5*a + ~0.5*b

  # Saturation is used only for diagnostic bounds, never computed values.
  -> .bounded_error(value)
    return ~1.7976931348623157e308 if !Calculus.finite_f64?(value)
    value

  -> .scalar_value?(value)
    return true if Expression.scalar_value?(value)
    value.respond_to?("components") && value.respond_to?("abs")

  -> .finite_scalar?(value)
    return Calculus.finite_f64?(value) if value.class_name == "Float"
    return false if !Calculus.scalar_value?(value)
    if value.respond_to?("components")
      values = value.components
      i = 0
      while i < values.size
        return false if !Calculus.finite_scalar?(values[i])
        i += 1
      return true
    if value.respond_to?("nan?")
      return false if value.nan?
    if value.respond_to?("infinite?")
      return false if value.infinite?
    true

  -> .require_real_domain(value, valid, operation)
    if !Calculus.finite_scalar?(value) || !valid
      raise operation + " outside its finite real differentiable domain"
    value

  # Norm used by numerical error estimators. Unlike `abs`, this also accepts
  # Complex and the normed Hypercomplex types.
  -> .magnitude(value)
    value.abs

  -> .certified_exp(value, tolerance = nil,
                     term_limit = 10_000)
    CertifiedTranscendentals.exp(
      value, tolerance, term_limit)

  -> .certified_log(value, tolerance = nil,
                     term_limit = 10_000)
    CertifiedTranscendentals.log(
      value, tolerance, term_limit)

  -> .certified_sin(value, tolerance = nil,
                     term_limit = 10_000)
    CertifiedTranscendentals.sin(
      value, tolerance, term_limit)

  -> .certified_cos(value, tolerance = nil,
                     term_limit = 10_000)
    CertifiedTranscendentals.cos(
      value, tolerance, term_limit)

  -> .certified_atan(value, tolerance = nil,
                      term_limit = 10_000)
    CertifiedTranscendentals.atan(
      value, tolerance, term_limit)

  -> .certified_pi(tolerance = nil,
                    term_limit = 10_000)
    CertifiedTranscendentals.pi(
      tolerance, term_limit)

  -> .certified_e(tolerance = nil,
                   term_limit = 10_000)
    CertifiedTranscendentals.e(
      tolerance, term_limit)

  -> .scale_value(value, scalar)
    return value.scale(scalar) if value.respond_to?("scale")
    value * scalar

  -> .symbol(name)
    Expression.variable(name)

  -> .symbols(names)
    Expression.variables(names)

  -> .simplify(expression)
    Expression.wrap(expression).simplify

  -> .symbolic_gradient(expression, variables)
    Expression.wrap(expression).gradient(variables)

  -> .symbolic_hessian(expression, variables)
    Expression.wrap(expression).hessian(variables)

  -> .antiderivative(expression, variable)
    Expression.wrap(expression).antiderivative(variable)

  -> .symbolic_integrate(expression, variable)
    Expression.wrap(expression).antiderivative(variable)

  -> .symbolic_integrate(expression, variable, lower, upper)
    Expression.wrap(expression).definite_integral(variable, lower, upper)

  -> .series(expression, variable, center = 0, order = 6)
    Expression.wrap(expression).series(variable, center, order)

  -> .formal_series(expression, variable, center = 0, order = 6)
    Expression.wrap(expression).series(variable, center, order)

  -> .laurent_series(expression, variable,
                      center = 0, order = 6,
                      search_margin = 8)
    Expression.wrap(expression).laurent_series(
      variable, center, order, search_margin)

  -> .residue(expression, variable,
               point = 0, search_margin = 8)
    Expression.wrap(expression).residue(
      variable, point, search_margin)

  -> .pole_order(expression, variable,
                  point = 0, search_margin = 8)
    Expression.wrap(expression).pole_order_at(
      variable, point, search_margin)

  -> .puiseux_series(expression, variable,
                      center = 0, order = 6,
                      search_margin = 8)
    Expression.wrap(expression).puiseux_series(
      variable, center, order, search_margin)

  -> .limit(expression, variable, point, order = 8)
    Expression.wrap(expression).limit(variable, point, order)

  -> .symbolic_limit(expression, variable, point, order = 8)
    Expression.wrap(expression).limit(variable, point, order)
