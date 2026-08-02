# Calculus — differentiation, Taylor expansion, and numerical integration.
#
# `use calculus` is the feature flag.  Exact polynomial differentiation and
# integration remain methods on Polynomial; this module covers smooth numeric
# functions with replayable coefficient propagation rather than finite
# differences:
#
#   Calculus.derivative(f, x, order)
#   Calculus.taylor(f, x, order)
#   Calculus.gradient(f, point)
#   Calculus.jacobian(f, point)
#   Calculus.hessian(f, point)
#   Calculus.integrate(f, a, b, abs_tol, rel_tol, max_depth)

use core/math
use core/numeric/rational
use core/expression
use core/calculus/certified_transcendentals
use core/calculus/series
use core/calculus/laurent
use core/calculus/puiseux
use core/calculus/jet
use core/calculus/differential
use core/calculus/quadrature
use core/calculus/radial_mellin

+ Calculus
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

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
