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
use core/calculus/jet
use core/calculus/differential
use core/calculus/quadrature

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
