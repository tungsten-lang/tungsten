# TaylorJet (core/calculus/jet.w): truncated univariate Taylor algebra.
#
# Coefficient k is f^(k)(x0)/k!, so every assertion below is a *known Taylor
# series*, not a finite difference. The series checked here are the ones out
# of the back of the book:
#
#   exp      1, 1, 1/2, 1/6, 1/24, 1/120
#   sin      0, 1, 0, -1/6, 0, 1/120          cos  1, 0, -1/2, 0, 1/24, 0
#   tan      0, 1, 0, 1/3, 0, 2/15            tanh 0, 1, 0, -1/3, 0, 2/15
#   atan     0, 1, 0, -1/3, 0, 1/5            asin 0, 1, 0, 1/6, 0, 3/40
#   log(1+x) 0, 1, -1/2, 1/3, -1/4, 1/5
#   sqrt @4  2, 1/4, -1/64, 1/512             cbrt @8  2, 1/12, -1/288
#   erf      (2/sqrt(pi)) * (x - x^3/3 + x^5/10)
#   W(x)     sum (-n)^(n-1)/n! x^n = 0, 1, -1, 3/2, -8/3, 125/24
#   lgamma@1 0, -gamma, zeta(2)/2, -zeta(3)/3, zeta(4)/4
#   digamma@1  -gamma, zeta(2), -zeta(3), zeta(4), -zeta(5)
#
# plus the algebra (+ - * / ** reciprocal scale negate), the jet-level
# derivative/antiderivative pair, and closure identities (sin^2 + cos^2 = 1,
# exp(log(x)) = x, tan = sin/cos, cosh^2 - sinh^2 = 1) that have to hold
# coefficient by coefficient if the recurrences are right.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/calculus_jet_spec.w
#   bin/tungsten -o /tmp/calculus-jet-spec spec/core/calculus_jet_spec.w && /tmp/calculus-jet-spec

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> abs(v)
  v < ~0.0 ? ~0.0 - v : v

-> close?(got, want, tolerance = ~1.0e-12)
  abs(got - want) <= tolerance

# every coefficient of `jet` matches `wanted`, in order
-> series?(jet, wanted, tolerance = ~1.0e-12)
  return false if jet.order + 1 != wanted.size
  i = 0
  while i < wanted.size
    return false if !close?(jet.coefficient(i), wanted[i], tolerance)
    i += 1
  true

# every coefficient of `jet` matches `other`'s
-> agrees?(jet, other, tolerance = ~1.0e-12)
  return false if jet.order != other.order
  i = 0
  while i <= jet.order
    return false if !close?(jet.coefficient(i), other.coefficient(i), tolerance)
    i += 1
  true

SIXTH = ~1.0 / ~6.0
TWENTY_FOURTH = ~1.0 / ~24.0
HUNDRED_TWENTIETH = ~1.0 / ~120.0
THIRD = ~1.0 / ~3.0
TWO_FIFTEENTHS = ~2.0 / ~15.0
EULER_MASCHERONI = ~0.5772156649015329

# --- construction -----------------------------------------------------------

variable = TaylorJet.variable(~2.0, 2)
check("variable.order", variable.order == 2)
check("variable.value", variable.value == ~2.0)
check("variable.seed_series", series?(variable, [~2.0, ~1.0, ~0.0]))
check("variable.coefficients_is_a_copy", variable.coefficients.size == 3)
constant = TaylorJet.constant(~5.0, 3)
check("constant.order", constant.order == 3)
check("constant.series", series?(constant, [~5.0, ~0.0, ~0.0, ~0.0]))
check("constant.derivative_is_zero", constant.derivative_value(1) == ~0.0)
check("variable.order_zero_is_a_constant",
      series?(TaylorJet.variable(~7.0, 0), [~7.0]))
check("coefficient.below_range", variable.coefficient(-1) == ~0.0)
check("coefficient.above_range", variable.coefficient(9) == ~0.0)
check("raw.constructor", series?(TaylorJet.new([~1.0, ~2.0, ~3.0]), [~1.0, ~2.0, ~3.0]))
check("to_s", variable.to_s == "TaylorJet(2, 1, 0)")

# --- the algebra ------------------------------------------------------------

# (2 + e)^2 = 4 + 4e + e^2
check("multiply.square", series?(variable * variable, [~4.0, ~4.0, ~1.0]))
# (2 + e)^3 = 8 + 12e + 6e^2 (+ e^3, truncated away)
check("power.cube", series?(variable ** 3, [~8.0, ~12.0, ~6.0]))
check("pow.alias", agrees?(variable.pow(3), variable ** 3))
check("power.zero_is_one", series?(variable ** 0, [~1.0, ~0.0, ~0.0]))
check("power.one_is_identity", agrees?(variable ** 1, variable))
# 1/(2 + e) = 1/2 - e/4 + e^2/8
check("reciprocal", series?(variable.reciprocal, [~0.5, ~-0.25, ~0.125]))
check("divide.matches_reciprocal",
      agrees?(TaylorJet.constant(~1.0, 2) / variable, variable.reciprocal))
check("divide.self_is_one", series?(variable / variable, [~1.0, ~0.0, ~0.0]))
check("negate", series?(-variable, [~-2.0, ~-1.0, ~0.0]))
check("scale", series?(variable.scale(~3.0), [~6.0, ~3.0, ~0.0]))
check("add.scalar", series?(variable + ~5.0, [~7.0, ~1.0, ~0.0]))
check("subtract.scalar", series?(variable - ~5.0, [~-3.0, ~1.0, ~0.0]))
check("add.commutes", agrees?(variable + constant.coerce(~1.0), TaylorJet.constant(~1.0, 2) + variable))
check("subtract.inverse", series?(variable - variable, [~0.0, ~0.0, ~0.0]))
check("multiply.by_one", agrees?(variable * ~1.0, variable))
check("multiply.by_zero", series?(variable * ~0.0, [~0.0, ~0.0, ~0.0]))
check("coerce.scalar_becomes_constant",
      series?(variable.coerce(~9.0), [~9.0, ~0.0, ~0.0]))
check("coerce.jet_passes_through",
      agrees?(variable.coerce(variable), variable))
# distributivity, coefficient by coefficient
left = (variable + ~3.0) * variable
right = variable * variable + variable.scale(~3.0)
check("algebra.distributive", agrees?(left, right))

# --- jet-level calculus -----------------------------------------------------

quadratic = TaylorJet.new([~5.0, ~3.0, ~7.0, ~2.0])
# d/dx of sum c_k e^k drops one order: [3, 14, 6]
check("derivative.shifts_and_scales", series?(quadratic.derivative, [~3.0, ~14.0, ~6.0]))
check("derivative.of_a_constant",
      series?(TaylorJet.constant(~4.0, 2).derivative, [~0.0, ~0.0]))
check("antiderivative.inverts_derivative",
      series?(quadratic.derivative.antiderivative(~5.0), [~5.0, ~3.0, ~7.0, ~2.0]))
check("antiderivative.default_constant",
      TaylorJet.new([~1.0, ~1.0]).antiderivative.value == ~0.0)
# derivative_value(k) = k! * c_k
check("derivative_value.first", (variable * variable).derivative_value(1) == ~4.0)
check("derivative_value.second", (variable * variable).derivative_value(2) == ~2.0)
check("derivative_value.zero_is_the_value", quadratic.derivative_value(0) == ~5.0)
check("derivative_value.third", close?(quadratic.derivative_value(3), ~12.0))
check("derivatives.list", quadratic.derivatives.size == 4)
check("derivatives.match_coefficients",
      quadratic.derivatives[0] == ~5.0 && quadratic.derivatives[1] == ~3.0)

# --- elementary functions at 0 ----------------------------------------------

at_zero = TaylorJet.variable(~0.0, 5)
check("exp.series",
      series?(at_zero.exp,
              [~1.0, ~1.0, ~0.5, SIXTH, TWENTY_FOURTH, HUNDRED_TWENTIETH]))
check("expm1.series",
      series?(at_zero.expm1,
              [~0.0, ~1.0, ~0.5, SIXTH, TWENTY_FOURTH, HUNDRED_TWENTIETH]))
check("sin.series",
      series?(at_zero.sin,
              [~0.0, ~1.0, ~0.0, ~0.0 - SIXTH, ~0.0, HUNDRED_TWENTIETH]))
check("cos.series",
      series?(at_zero.cos,
              [~1.0, ~0.0, ~-0.5, ~0.0, TWENTY_FOURTH, ~0.0]))
check("tan.series",
      series?(at_zero.tan, [~0.0, ~1.0, ~0.0, THIRD, ~0.0, TWO_FIFTEENTHS]))
check("sinh.series",
      series?(at_zero.sinh,
              [~0.0, ~1.0, ~0.0, SIXTH, ~0.0, HUNDRED_TWENTIETH]))
check("cosh.series",
      series?(at_zero.cosh, [~1.0, ~0.0, ~0.5, ~0.0, TWENTY_FOURTH, ~0.0]))
check("tanh.series",
      series?(at_zero.tanh,
              [~0.0, ~1.0, ~0.0, ~0.0 - THIRD, ~0.0, TWO_FIFTEENTHS]))
check("atan.series",
      series?(at_zero.atan, [~0.0, ~1.0, ~0.0, ~0.0 - THIRD, ~0.0, ~0.2]))
check("asin.series",
      series?(at_zero.asin, [~0.0, ~1.0, ~0.0, SIXTH, ~0.0, ~0.075]))
check("asinh.series",
      series?(at_zero.asinh,
              [~0.0, ~1.0, ~0.0, ~0.0 - SIXTH, ~0.0, ~0.075]))
check("atanh.series",
      series?(at_zero.atanh, [~0.0, ~1.0, ~0.0, THIRD, ~0.0, ~0.2]))
check("log1p.series",
      series?(at_zero.log1p,
              [~0.0, ~1.0, ~-0.5, THIRD, ~-0.25, ~0.2]))
# erf(x) = (2/sqrt(pi)) (x - x^3/3 + x^5/10 - ...)
scale = ~2.0 / Math.sqrt(~3.141592653589793)
check("erf.series",
      series?(at_zero.erf,
              [~0.0, scale, ~0.0, ~0.0 - scale / ~3.0, ~0.0, scale / ~10.0]))
check("erfc.complements_erf",
      series?(at_zero.erfc,
              [~1.0, ~0.0 - scale, ~0.0, scale / ~3.0, ~0.0, ~0.0 - scale / ~10.0]))
# W(x) = sum_{n>=1} (-n)^(n-1) / n! x^n
check("lambert_w.series",
      series?(at_zero.lambert_w,
              [~0.0, ~1.0, ~-1.0, ~1.5, ~0.0 - ~8.0 / ~3.0, ~125.0 / ~24.0]))
check("lambertw.alias", agrees?(at_zero.lambertw, at_zero.lambert_w))
check("acos.at_zero",
      close?(at_zero.acos.value, ~1.5707963267948966) &&
      close?(at_zero.acos.coefficient(1), ~-1.0))

# --- elementary functions at other centres ----------------------------------

at_one = TaylorJet.variable(~1.0, 4)
check("log.series_at_one",
      series?(at_one.log, [~0.0, ~1.0, ~-0.5, THIRD, ~-0.25]))
# log Gamma(1+x) = -gamma x + sum_{k>=2} (-1)^k zeta(k)/k x^k
check("log_gamma.series_at_one",
      series?(at_one.log_gamma,
              [~0.0, ~0.0 - EULER_MASCHERONI,
               ~1.6449340668482264 / ~2.0,
               ~0.0 - ~1.2020569031595943 / ~3.0,
               ~1.0823232337111382 / ~4.0], ~1.0e-9))
check("lgamma.alias", agrees?(at_one.lgamma, at_one.log_gamma, ~1.0e-12))
check("gamma.value_at_one", close?(at_one.gamma.value, ~1.0, ~1.0e-9))
check("gamma.derivative_is_minus_euler",
      close?(at_one.gamma.coefficient(1), ~0.0 - EULER_MASCHERONI, ~1.0e-9))
# psi(1) = -gamma, psi'(1) = zeta(2), psi''(1) = -2 zeta(3)
check("digamma.value_at_one",
      close?(at_one.digamma.value, ~0.0 - EULER_MASCHERONI, ~1.0e-9))
check("digamma.first_derivative_is_zeta2",
      close?(at_one.digamma.coefficient(1), ~1.6449340668482264, ~1.0e-9))
check("trigamma.value_at_one",
      close?(at_one.trigamma.value, ~1.6449340668482264, ~1.0e-9))
check("polygamma.zero_is_digamma",
      close?(at_one.polygamma(0).value, at_one.digamma.value, ~1.0e-12))

# sqrt(4 + e) = 2 + e/4 - e^2/64 + e^3/512
at_four = TaylorJet.variable(~4.0, 3)
check("sqrt.series_at_four",
      series?(at_four.sqrt, [~2.0, ~0.25, ~-1.0 / ~64.0, ~1.0 / ~512.0]))
check("sqrt.squares_back",
      agrees?(at_four.sqrt * at_four.sqrt, at_four, ~1.0e-12))
# cbrt(8 + e) = 2 + e/12 - e^2/288
at_eight = TaylorJet.variable(~8.0, 2)
check("cbrt.series_at_eight",
      series?(at_eight.cbrt, [~2.0, ~1.0 / ~12.0, ~-1.0 / ~288.0], ~1.0e-14))
check("log2.at_eight",
      series?(at_eight.log2,
              [~3.0, ~1.0 / (~8.0 * Math.log(~2.0)),
               ~-1.0 / (~128.0 * Math.log(~2.0))], ~1.0e-14))
check("log10.at_hundred",
      close?(TaylorJet.variable(~100.0, 1).log10.value, ~2.0, ~1.0e-14))
# |x| near a negative point is -x: derivative -1
check("abs.negative_branch",
      series?(TaylorJet.variable(~-3.0, 2).abs, [~3.0, ~-1.0, ~0.0]))
check("abs.positive_branch",
      series?(TaylorJet.variable(~3.0, 2).abs, [~3.0, ~1.0, ~0.0]))
check("acosh.above_one",
      close?(TaylorJet.variable(~2.0, 1).acosh.value,
             Math.log(~2.0 + Math.sqrt(~3.0)), ~1.0e-12))
check("acosh.derivative",
      close?(TaylorJet.variable(~2.0, 1).acosh.coefficient(1),
             ~1.0 / Math.sqrt(~3.0), ~1.0e-12))

# --- closure identities -----------------------------------------------------

# these must hold coefficient by coefficient, not just at the value
angle = TaylorJet.variable(~0.7, 5)
pythagoras = angle.sin * angle.sin + angle.cos * angle.cos
check("identity.sin2_plus_cos2", series?(pythagoras, [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
hyperbolic = angle.cosh * angle.cosh - angle.sinh * angle.sinh
check("identity.cosh2_minus_sinh2",
      series?(hyperbolic, [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], ~1.0e-11))
check("identity.tan_is_sin_over_cos",
      agrees?(angle.tan, angle.sin / angle.cos))
check("identity.tanh_is_sinh_over_cosh",
      agrees?(angle.tanh, angle.sinh / angle.cosh))
positive = TaylorJet.variable(~1.7, 4)
check("identity.exp_of_log", agrees?(positive.log.exp, positive, ~1.0e-12))
check("identity.log_of_exp", agrees?(positive.exp.log, positive, ~1.0e-12))
check("identity.asin_of_sin",
      agrees?(TaylorJet.variable(~0.4, 4).sin.asin,
              TaylorJet.variable(~0.4, 4), ~1.0e-12))
check("identity.atan_of_tan",
      agrees?(TaylorJet.variable(~0.4, 4).tan.atan,
              TaylorJet.variable(~0.4, 4), ~1.0e-12))
check("identity.expm1_matches_exp_minus_one",
      agrees?(angle.expm1, angle.exp - ~1.0, ~1.0e-14))
check("identity.log1p_matches_log_of_one_plus",
      agrees?(angle.log1p, (angle + ~1.0).log, ~1.0e-14))
check("identity.erf_plus_erfc",
      series?(angle.erf + angle.erfc, [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], ~1.0e-14))
check("identity.gamma_is_exp_log_gamma",
      agrees?(positive.gamma, positive.log_gamma.exp, ~1.0e-9))
# W(x) e^{W(x)} = x
lambert_point = TaylorJet.variable(~1.3, 3)
lambert = lambert_point.lambert_w
check("identity.lambert_w_defining_equation",
      agrees?(lambert * lambert.exp, lambert_point, ~1.0e-10))

# --- the chain rule through composition -------------------------------------

# d/dx sin(x^2) at x = 1 is 2 cos(1); d2/dx2 is 2cos(1) - 4sin(1)
composed = (TaylorJet.variable(~1.0, 2) ** 2).sin
check("chain.value", close?(composed.value, Math.sin(~1.0)))
check("chain.first_derivative",
      close?(composed.derivative_value(1), ~2.0 * Math.cos(~1.0)))
check("chain.second_derivative",
      close?(composed.derivative_value(2),
             ~2.0 * Math.cos(~1.0) - ~4.0 * Math.sin(~1.0)))

# --- the Calculus facade ----------------------------------------------------

facade = Calculus.jet(-> (t) t.sin, ~0.0, 3)
check("facade.jet_is_a_taylorjet", facade.class_name == "TaylorJet")
check("facade.jet.series", series?(facade, [~0.0, ~1.0, ~0.0, ~0.0 - SIXTH]))
check("facade.jet.default_order", Calculus.jet(-> (t) t.exp, ~0.0).order == 1)
# d^4/dx^4 of x^5 at 2 is 5!/1! * 2 = 240
check("facade.derivative.fourth",
      close?(Calculus.derivative(-> (t) t ** 5, ~2.0, 4), ~240.0, ~1.0e-9))
check("facade.derivative.fifth",
      close?(Calculus.derivative(-> (t) t ** 5, ~2.0, 5), ~120.0, ~1.0e-9))
check("facade.derivative.sixth_is_zero",
      close?(Calculus.derivative(-> (t) t ** 5, ~2.0, 6), ~0.0, ~1.0e-9))
check("facade.derivative.default_is_first",
      close?(Calculus.derivative(-> (t) t * t, ~3.0), ~6.0, ~1.0e-12))
check("facade.taylor_matches_jet",
      agrees?(Calculus.taylor(-> (t) t.cos, ~0.5, 3),
              Calculus.jet(-> (t) t.cos, ~0.5, 3)))

# --- loud failures ----------------------------------------------------------

raised = false
begin
  TaylorJet.new([])
rescue e
  raised = true
check("error.empty_coefficients", raised)

raised = false
begin
  TaylorJet.variable(~1.0, 2) + TaylorJet.variable(~1.0, 3)
rescue e
  raised = true
check("error.order_mismatch", raised)

raised = false
begin
  TaylorJet.constant(~1.0, -1)
rescue e
  raised = true
check("error.negative_order", raised)

<< "calculus_jet_spec: all checks passed"
