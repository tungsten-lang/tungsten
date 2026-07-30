# Exact Puiseux series and ramified local branches.

use calculus

-> puiseux_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

x = Calculus.symbol(:x)
zero = Expression.constant(0)
one = Expression.constant(1)
half = Rational.new(1, 2)
third = Rational.new(1, 3)

square_root = x.sqrt.puiseux_series(:x, 0, 4)
puiseux_check("sqrt.ramification",
              square_root.ramification_index == 2)
puiseux_check("sqrt.valuation",
              square_root.valuation == half)
puiseux_check("sqrt.leading",
              square_root.coefficient(half) == one)
puiseux_check("sqrt.off_lattice",
              square_root.coefficient(third) == zero)

two_thirds = Rational.new(2, 3)
rational_power = (
  x**Expression.constant(two_thirds)).puiseux_series(
    :x, 0, 3)
puiseux_check("rational_power.ramification",
              rational_power.ramification_index == 3)
puiseux_check("rational_power.leading",
              rational_power.coefficient(two_thirds) == one)

branched_unit = (
  x*(one + x)).sqrt.puiseux_series(:x, 0, 3)
puiseux_check("binomial.leading",
              branched_unit.coefficient(half) == one)
puiseux_check("binomial.linear_unit",
              branched_unit.coefficient(Rational.new(3, 2)) ==
              Expression.constant(half))
puiseux_check("binomial.quadratic_unit",
              branched_unit.coefficient(Rational.new(5, 2)) ==
              Expression.constant(Rational.new(-1, 8)))

exponential = x.sqrt.exp.puiseux_series(:x, 0, 3)
puiseux_check("unary.constant",
              exponential.coefficient(0) == one)
puiseux_check("unary.half",
              exponential.coefficient(half) == one)
puiseux_check("unary.one",
              exponential.coefficient(1) ==
              Expression.constant(half))
puiseux_check("unary.three_halves",
              exponential.coefficient(Rational.new(3, 2)) ==
              Expression.constant(Rational.new(1, 6)))

digamma = (one + x.sqrt).digamma.puiseux_series(:x, 0, 2)
puiseux_check("polygamma.constant",
              digamma.coefficient(0) == -Expression.euler_gamma)
puiseux_check("polygamma.ramified_argument",
              digamma.coefficient(half) == (Expression.pi**2)/6)

mixed = (
  square_root +
  x.cbrt.puiseux_series(:x, 0, 4))
puiseux_check("mixed.common_ramification",
              mixed.ramification_index == 6)
puiseux_check("mixed.sqrt_coefficient",
              mixed.coefficient(half) == one)
puiseux_check("mixed.cubert_coefficient",
              mixed.coefficient(third) == one)

quotient = (
  x.sqrt / x.cbrt).puiseux_series(:x, 0, 3)
puiseux_check("quotient.valuation",
              quotient.valuation == Rational.new(1, 6))
puiseux_check("quotient.leading",
              quotient.coefficient(Rational.new(1, 6)) == one)

derivative = square_root.derivative
puiseux_check("derivative.valuation",
              derivative.valuation == Rational.new(-1, 2))
puiseux_check("derivative.leading",
              derivative.coefficient(Rational.new(-1, 2)) ==
              Expression.constant(half))

square = square_root**2
puiseux_check("integer_power",
              square.coefficient(1) == one)

partial_window = FormalPuiseuxSeries.new([1, 2, 3], 1, 2)
scalar_sum = partial_window + 1
puiseux_check("scalar.preserve_fractional_window",
              scalar_sum.maximum_index == 3 &&
              scalar_sum.coefficient(Rational.new(3, 2)) ==
              Expression.constant(3))
identity = partial_window**0
puiseux_check("zero_power.preserve_fractional_window",
              identity.maximum_index == 3)

shifted = (x - 2).sqrt.puiseux_series(:x, 2, 3)
puiseux_check("shifted.center",
              shifted.center == Expression.constant(2))
puiseux_check("shifted.leading",
              shifted.coefficient(half) == one)

round_trip = branched_unit.to_expression
puiseux_check("to_expression.contains_branch",
              round_trip.depends_on?(:x))

logarithm_needed = false
begin
  x.sqrt.log.puiseux_series(:x, 0, 3)
rescue error
  logarithm_needed = true
puiseux_check("logarithmic_term.rejected",
              logarithm_needed)

facade = Calculus.puiseux_series(x.sqrt, :x, 0, 2)
puiseux_check("facade",
              facade.ramification_index == 2 &&
              facade.coefficient(half) == one)
