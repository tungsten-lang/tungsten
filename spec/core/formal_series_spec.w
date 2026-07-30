# Exact formal power series for symbolic algebra and transcendental calculus.
# Run in both interpreter and native engines.

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> coefficient_is(name, series, index, expected)
  check(name, series.coefficient(index) == Expression.wrap(expected))

-> same_coefficients?(left, right)
  return false if left.order != right.order
  i = 0
  while i <= left.order
    return false if left.coefficient(i) != right.coefficient(i)
    i += 1
  true

x, y = Calculus.symbols([:x, :y])

exp_series = x.exp.series(:x, 0, 6)
check("metadata.class", exp_series.class_name == "FormalPowerSeries")
check("metadata.variable", exp_series.variable == :x)
check("metadata.center", exp_series.center == Expression.constant(0))
check("metadata.order", exp_series.order == 6)
coefficient_is("exp.c0", exp_series, 0, 1)
coefficient_is("exp.c1", exp_series, 1, 1)
coefficient_is("exp.c2", exp_series, 2, Rational.new(1, 2))
coefficient_is("exp.c3", exp_series, 3, Rational.new(1, 6))
coefficient_is("exp.c6", exp_series, 6, Rational.new(1, 720))

sin_series = x.sin.series(:x, 0, 7)
coefficient_is("sin.c0", sin_series, 0, 0)
coefficient_is("sin.c1", sin_series, 1, 1)
coefficient_is("sin.c3", sin_series, 3, Rational.new(-1, 6))
coefficient_is("sin.c5", sin_series, 5, Rational.new(1, 120))
coefficient_is("sin.c7", sin_series, 7, Rational.new(-1, 5040))

log_one_plus = (x + 1).log.series(:x, 0, 5)
coefficient_is("log1p.c1", log_one_plus, 1, 1)
coefficient_is("log1p.c2", log_one_plus, 2, Rational.new(-1, 2))
coefficient_is("log1p.c3", log_one_plus, 3, Rational.new(1, 3))
coefficient_is("log1p.c5", log_one_plus, 5, Rational.new(1, 5))

log_at_one = x.log.series(:x, 1, 5)
check("center.log_matches_shift",
      same_coefficients?(log_at_one, log_one_plus))
coefficient_is("center.log.value", log_at_one, 0, 0)

sqrt_series = (x + 1).sqrt.series(:x, 0, 4)
coefficient_is("sqrt.c1", sqrt_series, 1, Rational.new(1, 2))
coefficient_is("sqrt.c2", sqrt_series, 2, Rational.new(-1, 8))
coefficient_is("sqrt.c4", sqrt_series, 4, Rational.new(-5, 128))

cbrt_series = (x + 1).cbrt.series(:x, 0, 4)
coefficient_is("cbrt.c1", cbrt_series, 1, Rational.new(1, 3))
coefficient_is("cbrt.c2", cbrt_series, 2, Rational.new(-1, 9))
coefficient_is("cbrt.c3", cbrt_series, 3, Rational.new(5, 81))

parameter_series = (x*y).exp.series(:x, 0, 4)
coefficient_is("parameter.c1", parameter_series, 1, y)
coefficient_is("parameter.c2", parameter_series, 2, y**2 * Rational.new(1, 2))
coefficient_is("parameter.c4", parameter_series, 4, y**4 * Rational.new(1, 24))

pi_series = (Expression.pi*x).sin.series(:x, 0, 3)
coefficient_is("named.pi.c1", pi_series, 1, Expression.pi)
coefficient_is("named.pi.c3",
               pi_series, 3, -(Expression.pi**3) * Rational.new(1, 6))

asin_series = x.asin.series(:x, 0, 5)
coefficient_is("inverse.asin.c1", asin_series, 1, 1)
coefficient_is("inverse.asin.c3", asin_series, 3, Rational.new(1, 6))
coefficient_is("inverse.asin.c5", asin_series, 5, Rational.new(3, 40))

exp_five = exp_series.truncate(5)
check("derivative.exact",
      exp_series.derivative.truncate(5) == exp_five)
integrated = exp_five.derivative.antiderivative(1)
check("antiderivative.exact",
      integrated.truncate(4) == exp_five.truncate(4))
check("derivative.values",
      exp_series.derivative_value(4) == Expression.constant(1))

outer = x.exp.series(:x, 0, 5)
inner = x.sin.series(:x, 0, 5)
composed = outer.compose(inner)
direct_composition = x.sin.exp.series(:x, 0, 5)
check("composition.exact", composed == direct_composition)

sinc = (x.sin / x).series(:x, 0, 6)
coefficient_is("removable.sinc.c0", sinc, 0, 1)
coefficient_is("removable.sinc.c2", sinc, 2, Rational.new(-1, 6))
coefficient_is("removable.sinc.c4", sinc, 4, Rational.new(1, 120))
cosine_limit = (Expression.constant(1) - x.cos) / x**2
coefficient_is("removable.cosine.c0",
               cosine_limit.series(:x, 0, 4), 0, Rational.new(1, 2))
check("limit.sinc",
      (x.sin / x).limit(:x, 0) == Expression.constant(1))
check("limit.log1p",
      ((x + 1).log / x).limit(:x, 0) == Expression.constant(1))
check("limit.facade",
      Calculus.limit(cosine_limit, :x, 0) ==
        Expression.constant(Rational.new(1, 2)))
high_valuation = (x**10).sin / x**10
coefficient_is("removable.high_valuation",
               high_valuation.series(:x, 0, 6), 0, 1)

symbolic_power = ((x + 1)**y).series(:x, 0, 2).expand_coefficients
coefficient_is("power.symbolic.c0", symbolic_power, 0, 1)
coefficient_is("power.symbolic.c1", symbolic_power, 1, y)
expected_power_two = ((y**2 - y) * Rational.new(1, 2)).expand
coefficient_is("power.symbolic.c2",
               symbolic_power, 2, expected_power_two)

facade = Calculus.series(x.cos, :x, 0, 4)
check("facade.series", facade == x.cos.series(:x, 0, 4))
check("facade.formal_series",
      Calculus.formal_series(x.cos, :x, 0, 4) == facade)

active_x = FormalPowerSeries.variable(:x, 0, 4)
active_result = (x.exp + x.sin).evaluate({x: active_x})
check("active.expression_evaluation",
      active_result == (x.exp + x.sin).series(:x, 0, 4))

elementary_cases = [
  ["exp", x.exp, 0],
  ["log", x.log, 1],
  ["sqrt", x.sqrt, 1],
  ["sin", x.sin, 0],
  ["cos", x.cos, 0],
  ["tan", x.tan, 0],
  ["sinh", x.sinh, 0],
  ["cosh", x.cosh, 0],
  ["tanh", x.tanh, 0],
  ["asin", x.asin, 0],
  ["acos", x.acos, 0],
  ["atan", x.atan, 0],
  ["asinh", x.asinh, 0],
  ["acosh", x.acosh, 2],
  ["atanh", x.atanh, 0],
  ["expm1", x.expm1, 0],
  ["log1p", x.log1p, 0],
  ["log2", x.log2, 1],
  ["log10", x.log10, 1],
  ["cbrt", x.cbrt, 1],
  ["abs", x.abs, 2]
]
elementary_cases.each -> (entry)
  from_series = entry[1].series(:x, entry[2], 5).derivative
  from_series = from_series.expand_coefficients
  direct = entry[1].derivative(:x).series(:x, entry[2], 4)
  direct = direct.expand_coefficients
  check("elementary." + entry[0], from_series == direct)

approximation = exp_series.at(Rational.new(1, 10)).evaluate({})
check("evaluate.truncation",
      close?(approximation, Math.exp(~0.1), ~2.0e-10))
check("render.big_o", exp_series.to_s.include?("O(x^7)"))

division_raised = false
begin
  active_x.reciprocal
rescue error
  division_raised = true
check("boundary.division_zero_constant", division_raised)

log_raised = false
begin
  active_x.log
rescue error
  log_raised = true
check("boundary.log_zero_constant", log_raised)

sqrt_raised = false
begin
  active_x.sqrt
rescue error
  sqrt_raised = true
check("boundary.sqrt_puiseux_needed", sqrt_raised)

pole_raised = false
begin
  (Expression.constant(1) / x).series(:x, 0, 4)
rescue error
  pole_raised = true
check("boundary.laurent_needed", pole_raised)

abs_raised = false
begin
  active_x.abs
rescue error
  abs_raised = true
check("boundary.abs_sign_needed", abs_raised)

mismatch_raised = false
begin
  active_x + FormalPowerSeries.variable(:x, 1, 4)
rescue error
  mismatch_raised = true
check("boundary.expansion_point_mismatch", mismatch_raised)

extension_raised = false
begin
  active_x.truncate(5)
rescue error
  extension_raised = true
check("boundary.truncate_cannot_extend", extension_raised)

<< "formal_series_spec: all checks passed"
