# Scalar Measurement uncertainty propagation.
# Inputs are independent unless a direct pair correlation is declared.

use measurement

-> measurement_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> measurement_close?(got, want, tolerance = ~1.0e-12)
  difference = (got - want).abs
  scale = want.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

literal = ~5.0 ± ~0.2
measurement_check("literal.value", literal.value == ~5.0)
measurement_check("literal.uncertainty", literal.uncertainty == ~0.2)

x = Measurement.new(~10.0, ~1.0, nil, nil, ~1.0, nil, nil, ["x"])
y = Measurement.new(~2.0, ~0.2, nil, nil, ~1.0, nil, nil, ["y"])

source_provenance = ["source"]
provenance_copy = Measurement.new(
  ~1.0, ~0.1, nil, nil, ~1.0, nil, nil, source_provenance)
source_provenance.push("changed")
measurement_check("provenance.input_copy", provenance_copy.provenance.size == 1)

sum = x + y
measurement_check("add.value", sum.value == ~12.0)
measurement_check("add.uncertainty",
  measurement_close?(sum.uncertainty, Math.sqrt(~1.04)))

difference = x - y
measurement_check("subtract.value", difference.value == ~8.0)
measurement_check("subtract.uncertainty",
  measurement_close?(difference.uncertainty, Math.sqrt(~1.04)))

product = x * y
measurement_check("multiply.value", product.value == ~20.0)
measurement_check("multiply.uncertainty",
  measurement_close?(product.uncertainty, Math.sqrt(~8.0)))
measurement_check("multiply.provenance", product.provenance.size == 2)

quotient = x / y
measurement_check("divide.value", quotient.value == ~5.0)
measurement_check("divide.uncertainty",
  measurement_close?(quotient.uncertainty, Math.sqrt(~0.5)))

square = x ** 2
measurement_check("power.value", square.value == ~100.0)
measurement_check("power.uncertainty", square.uncertainty == ~20.0)

same_product = x * x
measurement_check("identical.multiply_matches_power",
  measurement_close?(same_product.uncertainty, square.uncertainty))
measurement_check("identical.subtract_cancels",
  (x - x).uncertainty == ~0.0)
measurement_check("identical.divide_cancels",
  (x / x).uncertainty == ~0.0)

root = x.sqrt
measurement_check("sqrt.value",
  measurement_close?(root.value, Math.sqrt(~10.0)))
measurement_check("sqrt.uncertainty",
  measurement_close?(
    root.uncertainty, ~1.0 / (~2.0 * Math.sqrt(~10.0))))

uncertain_zero = Measurement.new(~0.0, ~0.25)
measurement_check("power.zero_linear",
  (uncertain_zero ** 1).uncertainty == ~0.25)
measurement_check("power.zero_quadratic",
  (uncertain_zero ** 2).uncertainty == ~0.0)
singular_power_rejected = false
begin
  uncertain_zero ** ~0.5
rescue error
  singular_power_rejected = error.to_s.include?("uncertain zero")
measurement_check("power.zero_fractional_rejected", singular_power_rejected)

components = Measurement.with_components(~4.0, ~0.3, ~0.4)
measurement_check("components.total",
  measurement_close?(components.uncertainty, ~0.5))
scaled = components.scaled(~2.0)
measurement_check("components.random",
  measurement_close?(scaled.random_uncertainty, ~0.6))
measurement_check("components.systematic",
  measurement_close?(scaled.systematic_uncertainty, ~0.8))

correlated_x = Measurement.new(~10.0, ~1.0)
correlated_y = Measurement.new(~2.0, ~0.2)
correlated_x.correlate(correlated_y, ~1.0)
measurement_check("correlated.multiply",
  measurement_close?((correlated_x * correlated_y).uncertainty, ~4.0))
measurement_check("correlated.subtract",
  measurement_close?((correlated_x - correlated_y).uncertainty, ~0.8))

same_a = Measurement.new(~3.0, ~0.5)
same_b = Measurement.new(~3.0, ~0.5)
measurement_check("correlation.distinct_object_identity",
  !Measurement.same_object?(same_a, same_b))
same_a.correlate(same_b, ~1.0)
measurement_check("correlated.cancellation",
  (same_a - same_b).uncertainty == ~0.0)

# Rebinding the single correlation slot detaches the old reciprocal link.
# Arithmetic must remain commutative and derived values drop the link.
rebind_a = Measurement.new(~1.0, ~0.1)
rebind_b = Measurement.new(~2.0, ~0.2)
rebind_c = Measurement.new(~3.0, ~0.3)
rebind_a.correlate(rebind_b, ~1.0)
rebind_a.correlate(rebind_c, ~1.0)
rebind_ab = rebind_a + rebind_b
rebind_ba = rebind_b + rebind_a
measurement_check("correlation.rebind_commutative",
  measurement_close?(rebind_ab.uncertainty, rebind_ba.uncertainty))
measurement_check("correlation.old_pair_detached",
  measurement_close?(rebind_ab.uncertainty, Math.sqrt(~0.05)))
measurement_check("correlation.new_pair_active",
  measurement_close?((rebind_a + rebind_c).uncertainty, ~0.4))
shifted_a = rebind_a + ~1.0
measurement_check("correlation.derived_result_cleared",
  shifted_a.correlation_with(rebind_c) == ~0.0 &&
  rebind_c.correlation_with(shifted_a) == ~0.0)

bad_correlation_rejected = false
begin
  correlated_x.mul_correlated(correlated_y, ~1.01)
rescue error
  bad_correlation_rejected = error.to_s.include?("between -1 and 1")
measurement_check("correlation.range_rejected", bad_correlation_rejected)

division_by_zero_rejected = false
begin
  x / Measurement.new(~0.0, ~0.1)
rescue error
  division_by_zero_rejected = error.to_s.include?("division by zero")
measurement_check("division.zero_rejected", division_by_zero_rejected)

scalar_division_by_zero_rejected = false
begin
  x / 0
rescue error
  scalar_division_by_zero_rejected = error.to_s.include?("division by zero")
measurement_check("division.scalar_zero_rejected",
  scalar_division_by_zero_rejected)

invalid_variance_rejected = false
begin
  Measurement.nonnegative_variance(~-1.0, ~1.0)
rescue error
  invalid_variance_rejected = error.to_s.include?("covariance model")
measurement_check("variance.invalid_rejected", invalid_variance_rejected)

nonfinite_variance_rejected = false
begin
  not_a_number = ~1.0e999 - ~1.0e999
  Measurement.nonnegative_variance(not_a_number, ~1.0)
rescue error
  nonfinite_variance_rejected = error.to_s.include?("must be finite")
measurement_check("variance.nonfinite_rejected", nonfinite_variance_rejected)

nonfinite_measurement_rejected = false
begin
  Measurement.new(not_a_number, ~0.1)
rescue error
  nonfinite_measurement_rejected = error.to_s.include?("value must be")
measurement_check("measurement.nonfinite_rejected",
  nonfinite_measurement_rejected)

<< "physics_measurement_spec: all checks passed"
