# Gamma, log-gamma, polygamma, zeta constants, formal series, and AD.
# Run in both interpreter and native engines.

use calculus

-> gamma_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> gamma_close?(got, want, tolerance = ~2.0e-13)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

x = Calculus.symbol(:x)
half = Expression.constant(Rational.new(1, 2))
minus_half = Expression.constant(Rational.new(-1, 2))
gamma_constant = Expression.euler_gamma

# Exact values remain symbolic and canonical.
gamma_check("exact.gamma_one",
            Expression.constant(1).gamma == Expression.constant(1))
gamma_check("exact.gamma_five",
            Expression.constant(5).gamma == Expression.constant(24))
gamma_check("exact.gamma_half",
            half.gamma == Expression.pi.sqrt)
gamma_check("exact.gamma_minus_half",
            minus_half.gamma == -Expression.constant(2)*Expression.pi.sqrt)
gamma_check("exact.log_gamma_one",
            Expression.constant(1).log_gamma == Expression.constant(0))
gamma_check("exact.digamma_one",
            Expression.constant(1).digamma == -gamma_constant)
gamma_check("exact.digamma_three",
            Expression.constant(3).digamma ==
              Expression.constant(Rational.new(3, 2)) - gamma_constant)
gamma_check("exact.trigamma_one",
            Expression.constant(1).trigamma == (Expression.pi**2)/6)
gamma_check("exact.polygamma_two_one",
            Expression.constant(1).polygamma(2) ==
              -Expression.constant(2)*Expression.zeta(3))
gamma_check("exact.zeta_two", Expression.zeta(2) == (Expression.pi**2)/6)
gamma_check("symbolic.render",
            x.gamma.to_s == "Γ(x)" &&
              x.log_gamma.to_s == "logΓ(x)" &&
              x.digamma.to_s == "polygamma(0, x)")

# The derivative tower closes under polygamma, and affine antiderivatives
# reverse it without invoking numerical quadrature.
gamma_check("differentiate.gamma",
            x.gamma.derivative(:x) == x.gamma*x.digamma)
gamma_check("differentiate.log_gamma",
            x.log_gamma.derivative(:x) == x.digamma)
gamma_check("differentiate.polygamma",
            x.polygamma(4).derivative(:x) == x.polygamma(5))
gamma_check("integrate.digamma",
            x.digamma.antiderivative(:x) == x.log_gamma)
gamma_check("integrate.trigamma",
            x.trigamma.antiderivative(:x) == x.digamma)

# Exact Taylor coefficients at one expose Euler's constant and zeta values.
gamma_series = x.gamma.series(:x, 1, 3)
gamma_check("series.gamma.c0",
            gamma_series.coefficient(0) == Expression.constant(1))
gamma_check("series.gamma.c1",
            gamma_series.coefficient(1) == -gamma_constant)
gamma_check("series.gamma.c2",
            gamma_series.coefficient(2) ==
              (gamma_constant**2 + (Expression.pi**2)/6)/2)

log_gamma_series = x.log_gamma.series(:x, 1, 3)
gamma_check("series.log_gamma.c0",
            log_gamma_series.coefficient(0) == Expression.constant(0))
gamma_check("series.log_gamma.c1",
            log_gamma_series.coefficient(1) == -gamma_constant)
gamma_check("series.log_gamma.c2",
            log_gamma_series.coefficient(2) == (Expression.pi**2)/12)
gamma_check("series.log_gamma.c3",
            log_gamma_series.coefficient(3) == -Expression.zeta(3)/3)

digamma_series = x.digamma.series(:x, 1, 3)
gamma_check("series.digamma.c0",
            digamma_series.coefficient(0) == -gamma_constant)
gamma_check("series.digamma.c1",
            digamma_series.coefficient(1) == (Expression.pi**2)/6)
gamma_check("series.digamma.c2",
            digamma_series.coefficient(2) == -Expression.zeta(3))

# Numeric functions agree with standard high-precision reference values.
gamma_check("numeric.gamma_tenth",
            gamma_close?(Special.gamma(~0.1),
                         ~9.5135076986687318363, ~5.0e-15))
gamma_check("numeric.gamma_twenty",
            gamma_close?(Special.gamma(~20.0),
                         ~121645100408832000.0, ~5.0e-15))
gamma_check("numeric.digamma_tenth",
            gamma_close?(Special.digamma(~0.1),
                         ~-10.423754940411076795168))
gamma_check("numeric.trigamma_tenth",
            gamma_close?(Special.trigamma(~0.1),
                         ~101.43329915079275881722))
gamma_check("numeric.polygamma",
            gamma_close?(Special.polygamma(2, ~2.5),
                         ~-0.23620405164172740300))
gamma_check("numeric.zeta_three",
            gamma_close?(Special.zeta(3),
                         ~1.2020569031595942854))
gamma_check("numeric.zeta_expression",
            gamma_close?(Expression.zeta(3).evaluate({}),
                         Special.zeta(3)))
gamma_check("numeric.euler_gamma_expression",
            gamma_close?(Expression.euler_gamma.evaluate({}),
                         ~0.57721566490153286061))
gamma_check("numeric.symbolic_evaluate",
            gamma_close?(x.gamma.evaluate({x: ~2.5}),
                         Special.gamma(~2.5)))

# Taylor jets and multivariate differentials propagate the same derivative
# formulas rather than finite-differencing the special function.
point = ~2.5
expected_first = Special.gamma(point) * Special.digamma(point)
expected_second = (Special.gamma(point) *
  (Special.digamma(point)**2 + Special.trigamma(point)))
gamma_jet = Calculus.taylor(-> (value) value.gamma, point, 3)
gamma_check("jet.gamma.value",
            gamma_close?(gamma_jet.value, Special.gamma(point)))
gamma_check("jet.gamma.first",
            gamma_close?(gamma_jet.derivative_value(1), expected_first))
gamma_check("jet.gamma.second",
            gamma_close?(gamma_jet.derivative_value(2), expected_second))

bundle = Calculus.value_gradient_hessian(
  -> (values) values[0].gamma, [point])
gamma_check("differential.gamma.value",
            gamma_close?(bundle["value"], Special.gamma(point)))
gamma_check("differential.gamma.gradient",
            gamma_close?(bundle["gradient"][0], expected_first))
gamma_check("differential.gamma.hessian",
            gamma_close?(bundle["hessian"][0][0], expected_second))

active = FormalPowerSeries.variable(:x, 1, 3)
gamma_check("active.series_evaluation",
            x.gamma.evaluate({x: active}) == gamma_series)

domain_rejected = false
begin
  Special.polygamma(1, ~0.0)
rescue error
  domain_rejected = error.to_s.include?("x must be > 0")
gamma_check("numeric.domain_is_loud", domain_rejected)

<< "expression_gamma_spec: all checks passed"
