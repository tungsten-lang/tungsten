# Error functions across numeric evaluation, exact symbolic calculus, formal
# series, and automatic differentiation. Run in interpreter and native engines.

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~2.0e-15)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

x = Calculus.symbol(:x)
pi_root = Expression.pi.sqrt

check("numeric.erf_zero", Special.erf(~0.0) == ~0.0)
check("numeric.erf_half",
      close?(Special.erf(~0.5), ~0.5204998778130465))
check("numeric.erf_one",
      close?(Special.erf(~1.0), ~0.8427007929497149))
check("numeric.erfc_two",
      close?(Special.erfc(~2.0), ~0.004677734981047266))
check("numeric.erfc_tail",
      close?(Special.erfc(~6.0), ~2.1519736712498916e-17, ~1.0e-30))
check("numeric.complement",
      close?(Special.erf(~1.25) + Special.erfc(~1.25), ~1.0))
check("numeric.symmetry",
      close?(Special.erf(~-0.75), ~0.0 - Special.erf(~0.75)))

check("exact.erf_zero", Expression.constant(0).erf == Expression.constant(0))
check("exact.erfc_zero", Expression.constant(0).erfc == Expression.constant(1))
check("symbolic.render", x.erf.to_s == "erf(x)" && x.erfc.to_s == "erfc(x)")
check("symbolic.erf_parity", (-x).erf == -x.erf)
check("symbolic.erfc_reflection", (-x).erfc == Expression.constant(2) - x.erfc)
check("symbolic.evaluate",
      close?(x.erf.evaluate({x: ~0.5}), Special.erf(~0.5)))

erf_derivative = Expression.product([
  Expression.constant(2),
  Expression.constant(1) / pi_root,
  (-(x**2)).exp
])
check("differentiate.erf", x.erf.derivative(:x) == erf_derivative)
check("differentiate.erfc", x.erfc.derivative(:x) == -erf_derivative)
check("integrate.erf_round_trip",
      x.erf.antiderivative(:x).derivative(:x) == x.erf)
check("integrate.erfc_round_trip",
      x.erfc.antiderivative(:x).derivative(:x) == x.erfc)

erf_series = x.erf.series(:x, 0, 7)
check("series.erf.c0", erf_series.coefficient(0) == Expression.constant(0))
check("series.erf.c1",
      erf_series.coefficient(1) == Expression.constant(2) / pi_root)
check("series.erf.c3",
      erf_series.coefficient(3) ==
        Expression.constant(Rational.new(-2, 3)) / pi_root)
check("series.erf.c5",
      erf_series.coefficient(5) ==
        Expression.constant(Rational.new(1, 5)) / pi_root)
check("series.erfc.c0",
      x.erfc.series(:x, 0, 5).coefficient(0) == Expression.constant(1))
check("limit.erf_over_x",
      (x.erf / x).limit(:x, 0) == Expression.constant(2) / pi_root)

jet_derivative = Calculus.derivative(-> (value) value.erf, ~0.5)
expected_first = ~2.0 * Math.exp(~-0.25) / Math.sqrt(~3.141592653589793)
check("jet.derivative", close?(jet_derivative, expected_first))

differential = Calculus.value_gradient_hessian(
  -> (values) values[0].erf, [~0.5])
check("differential.value",
      close?(differential["value"], Special.erf(~0.5)))
check("differential.gradient",
      close?(differential["gradient"][0], expected_first))
check("differential.hessian",
      close?(differential["hessian"][0][0], ~-1.0 * expected_first))

active = FormalPowerSeries.variable(:x, 0, 5)
check("active.series_evaluation",
      x.erf.evaluate({x: active}) == x.erf.series(:x, 0, 5))

<< "expression_special_spec: all checks passed"
