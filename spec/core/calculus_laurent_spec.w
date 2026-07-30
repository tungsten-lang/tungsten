# Exact Laurent series, poles, residues, and meromorphic arithmetic.

use calculus

-> laurent_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

x = Calculus.symbol(:x)
one = Expression.constant(1)

simple_pole = (one / x).laurent_series(:x, 0, 5)
laurent_check("simple_pole.minimum_power",
              simple_pole.minimum_power == -1)
laurent_check("simple_pole.maximum_power",
              simple_pole.maximum_power == 5)
laurent_check("simple_pole.order",
              simple_pole.pole_order == 1)
laurent_check("simple_pole.residue",
              simple_pole.residue == one)

double_pole = (one / x**2).laurent_series(:x, 0, 5)
laurent_check("double_pole.order",
              double_pole.pole_order == 2)
laurent_check("double_pole.residue",
              Expression.zero_expression?(double_pole.residue))

sine_pole = (x.sin / (x*x)).laurent_series(:x, 0, 5)
laurent_check("sine_pole.residue",
              sine_pole.residue == one)
laurent_check("sine_pole.linear",
              sine_pole.coefficient(1) ==
              Expression.constant(Rational.new(-1, 6)))
laurent_check("sine_pole.cubic",
              sine_pole.coefficient(3) ==
              Expression.constant(Rational.new(1, 120)))
laurent_check("sine_pole.principal",
              sine_pole.principal_part == simple_pole.truncate(-1))
laurent_check("sine_pole.regular",
              sine_pole.regular_part.regular?)

geometric = (
  one / (x*(one - x))).laurent_series(:x, 0, 5)
power = -1
while power <= 5
  laurent_check(
    "geometric.coefficient." + power.to_s,
    geometric.coefficient(power) == one)
  power += 1

nested = (
  one / x + one / (one - x)).laurent_series(:x, 0, 4)
laurent_check("nested.residue", nested.residue == one)
laurent_check("nested.constant",
              nested.coefficient(0) == one)
laurent_check("nested.quartic",
              nested.coefficient(4) == one)

cancelled = (
  FormalLaurentSeries.new([1, 1], -1) +
  FormalLaurentSeries.new([-1, 2], -1))
laurent_check("arithmetic.leading_cancellation",
              cancelled.minimum_power == 0 &&
              cancelled.coefficient(0) == Expression.constant(3))
unit_product = (
  FormalLaurentSeries.new([1, 1, 1, 1], -1) *
  FormalLaurentSeries.new([1, -1, 0, 0], 1))
laurent_check("arithmetic.product",
              unit_product.coefficient(0) == one &&
              Expression.zero_expression?(
                unit_product.coefficient(1)))

derivative = simple_pole.derivative
laurent_check("derivative.minimum_power",
              derivative.minimum_power == -2)
laurent_check("derivative.leading",
              derivative.coefficient(-2) == Expression.constant(-1))
laurent_check("derivative.residue_zero",
              Expression.zero_expression?(derivative.residue))

integrated_double = double_pole.antiderivative
laurent_check("antiderivative.leading",
              integrated_double.coefficient(-1) ==
              Expression.constant(-1))
logarithm_needed = false
begin
  simple_pole.antiderivative
rescue error
  logarithm_needed = true
laurent_check("antiderivative.logarithm_rejected",
              logarithm_needed)

shifted = (
  one / (x - 2)).laurent_series(:x, 2, 3)
laurent_check("shifted.center",
              shifted.center == Expression.constant(2))
laurent_check("shifted.residue",
              shifted.residue == one)

essential = false
begin
  (one / x).exp.laurent_series(:x, 0, 4)
rescue error
  essential = true
laurent_check("essential_singularity.rejected", essential)

puiseux = false
begin
  x.sqrt.laurent_series(:x, 0, 4)
rescue error
  puiseux = true
laurent_check("fractional_power.rejected", puiseux)

facade = Calculus.laurent_series(
  x.sin / (x*x), :x, 0, 3)
laurent_check("facade.residue", facade.residue == one)
laurent_check("facade.direct_residue",
              Calculus.residue(
                x.sin / (x*x), :x, 0) == one)
laurent_check("facade.pole_order",
              Calculus.pole_order(one / x**2, :x, 0) == 2)
