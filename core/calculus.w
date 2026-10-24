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
    t = type(value)
    t == "Int" || t == "Integer" || t == "BigInt"

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

  -> .copy_vector(values_in)
    values = values_in ## Array
    values.dup

  -> .copy_matrix(values_in)
    values = values_in ## Array
    n = values.size
    out = []
    i = 0
    while i < n
      row = values[i] ## Array
      out.push(row.dup)
      i += 1
    out

  -> .zero_vector(size)
    out = []
    i = 0
    while i < size
      out.push(~0.0)
      i += 1
    out

  -> .zero_matrix(size)
    out = []
    i = 0
    while i < size
      out.push(Calculus.zero_vector(size))
      i += 1
    out

  -> .abs(value)
    if type(value) == "Float"
      v = value ## f64
      return v < ~0.0 ? ~0.0 - v : v
    value < ~0.0 ? ~0.0 - value : value

  -> .finite_f64?(value)
    return false if type(value) != "Float"
    f = value ## f64
    f - f == ~0.0

  -> .within_tolerance?(error, magnitude, abs_tol, rel_tol)
    return false if !Calculus.finite_f64?(error)
    err = error ## f64
    return false if err < ~0.0
    atol = abs_tol ## f64
    return true if err <= atol
    mag = magnitude ## f64
    rtol = rel_tol ## f64
    return false if mag == ~0.0 || rtol == ~0.0
    err / mag <= rtol

  -> .midpoint(a_in, b_in)
    a = a_in ## f64
    b = b_in ## f64
    ~0.5 * a + ~0.5 * b

  # Saturation is used only for diagnostic bounds, never computed values.
  -> .bounded_error(value)
    return ~1.7976931348623157e308 if !Calculus.finite_f64?(value)
    value

  -> .scalar_value?(value)
    return true if Expression.scalar_value?(value)
    value.respond_to?("components") && value.respond_to?("abs")

  -> .finite_scalar?(value)
    if type(value) == "Float"
      f = value ## f64
      return f - f == ~0.0
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
    if type(value) == "Float"
      v = value ## f64
      return v < ~0.0 ? ~0.0 - v : v
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
    if type(value) == "Float" && type(scalar) == "Float"
      v = value ## f64
      s = scalar ## f64
      return v * s
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
