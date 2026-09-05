# Experimental observations, covariance validation, and constant GLS.

use physics

-> experiment_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> experiment_close?(got, want, tolerance = ~1.0e-12)
  difference = (got - want).abs
  scale = want.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

mass = Physics.observable("test mass", :kg, :m, "calibrated test article")
metadata = {:instrument => "balance-a"}
run_a = Physics.observation(
  mass, Measurement.new(~10.0, ~1.0), "balance-a/run-17", nil, metadata)
run_b = Physics.observation(
  mass, Measurement.new(~12.0, ~2.0), "balance-b/run-03")

metadata[:instrument] = "changed"
experiment_check("observation.metadata_input_copy",
  run_a.metadata[:instrument] == "balance-a")
returned_metadata = run_a.metadata
returned_metadata[:instrument] = "changed-again"
experiment_check("observation.metadata_output_copy",
  run_a.metadata[:instrument] == "balance-a")
experiment_check("observation.unit", run_a.unit == :kg)

dataset = Physics.dataset(mass, [run_a, run_b])
estimate = Physics.fit_constant(dataset)
experiment_check("dataset.size", dataset.size == 2)
experiment_check("dataset.covariance_source",
  dataset.covariance_source == :independent)
experiment_check("gls.value", experiment_close?(estimate.value, ~10.4))
experiment_check("gls.uncertainty",
  experiment_close?(estimate.uncertainty, Math.sqrt(~0.8)))
experiment_check("gls.chi_square",
  experiment_close?(estimate.chi_square, ~0.8))
experiment_check("gls.dof", estimate.degrees_of_freedom == 1)
experiment_check("gls.method",
  estimate.method == :generalized_least_squares)
experiment_check("gls.not_certified", !estimate.certified?)

correlated = Physics.dataset(
  mass, [run_a, run_b], [[~1.0, ~1.0], [~1.0, ~4.0]])
correlated_estimate = correlated.fit_constant
experiment_check("correlated.source",
  correlated_estimate.covariance_source == :supplied)
experiment_check("correlated.value",
  experiment_close?(correlated_estimate.value, ~10.0))
experiment_check("correlated.uncertainty",
  experiment_close?(correlated_estimate.uncertainty, ~1.0))

# An SPD covariance may legitimately give negative GLS weights. Do not clamp
# the estimate to the data range when stabilizing the solve.
negative_weight_fit = Physics.dataset(
  mass, [run_a, run_b], [[~1.0, ~1.5], [~1.5, ~4.0]]).fit_constant
experiment_check("correlated.negative_weight_mean",
  experiment_close?(negative_weight_fit.value, ~9.5))
experiment_check("correlated.negative_weight_uncertainty",
  experiment_close?(negative_weight_fit.uncertainty, Math.sqrt(~0.875)))
experiment_check("correlated.negative_weight_chi_square",
  experiment_close?(negative_weight_fit.chi_square, ~2.0))

bad_covariance_rejected = false
begin
  Physics.dataset(mass, [run_a, run_b], [[~1.0, ~0.1], [~0.2, ~4.0]])
rescue error
  bad_covariance_rejected = error.to_s.include?("symmetric")
experiment_check("covariance.asymmetry_rejected", bad_covariance_rejected)

nonfinite_covariance_rejected = false
begin
  infinity = Math.exp(~1000.0)
  not_a_number = infinity - infinity
  Physics.dataset(
    mass, [run_a, run_b], [[~1.0, not_a_number], [not_a_number, ~4.0]])
rescue error
  nonfinite_covariance_rejected = error.to_s.include?("finite numbers")
experiment_check("covariance.nonfinite_rejected",
  nonfinite_covariance_rejected)

small_observation = Physics.observation(
  mass, Measurement.new(~1.0, ~1.0e-9), "small/run-1")
small_diagonal_rejected = false
begin
  Physics.dataset(mass, [small_observation], [[~1.0e-13]])
rescue error
  small_diagonal_rejected = error.to_s.include?(
    "must match observation uncertainty")
experiment_check("covariance.small_scale_mismatch_rejected",
  small_diagonal_rejected)

small_run_b = Physics.observation(
  mass, Measurement.new(~1.1, ~1.0e-9), "small/run-2")
small_asymmetry_rejected = false
begin
  Physics.dataset(
    mass, [small_observation, small_run_b],
    [[~1.0e-18, ~1.0e-22], [~2.0e-22, ~1.0e-18]])
rescue error
  small_asymmetry_rejected = error.to_s.include?("symmetric")
experiment_check("covariance.small_scale_asymmetry_rejected",
  small_asymmetry_rejected)

wrong_unit_rejected = false
begin
  incompatible = Physics.observable("test mass", :m, :m)
  wrong = Physics.observation(
    incompatible, Measurement.new(~10.0, ~1.0), "run-3")
  Physics.dataset(mass, [run_a, wrong])
rescue error
  wrong_unit_rejected = error.to_s.include?("same observable and unit")
experiment_check("observable.mismatch_rejected", wrong_unit_rejected)

# A tolerated asymmetric input must never be solved as a nonsymmetric matrix.
zero_run = Physics.observation(mass, Measurement.new(~0.0, ~1.0), "zero")
one_run = Physics.observation(mass, Measurement.new(~1.0, ~1.0), "one")
near_singular_rejected = false
begin
  Physics.dataset(mass, [zero_run, one_run],
    [[~1.0, ~1.0000000000004], [~0.9999999999996, ~1.0]])
rescue error
  near_singular_rejected = true
experiment_check("covariance.canonical_singular_rejected", near_singular_rejected)
near_symmetric_input = [[~1.0, ~0.5000000000001], [~0.4999999999999, ~1.0]]
near_symmetric = Physics.dataset(mass, [zero_run, one_run], near_symmetric_input)
experiment_check("covariance.canonical_symmetric",
  near_symmetric.covariance[0][1] == near_symmetric.covariance[1][0])
experiment_check("covariance.input_unchanged",
  near_symmetric_input[0][1] != near_symmetric_input[1][0])
experiment_check("covariance.canonical_fit",
  experiment_close?(near_symmetric.fit_constant.value, ~0.5))

duplicate_rejected = false
begin
  Physics.dataset(mass, [run_a, run_a])
rescue error
  duplicate_rejected = error.to_s.include?("cannot repeat")
experiment_check("dataset.duplicate_rejected", duplicate_rejected)
shared_measurement_rejected = false
begin
  alias_run = Physics.observation(mass, run_a.measurement, "alias")
  Physics.dataset(mass, [run_a, alias_run], [[~1.0, ~0.0], [~0.0, ~1.0]])
rescue error
  shared_measurement_rejected = error.to_s.include?("cannot repeat")
experiment_check("dataset.shared_measurement_rejected", shared_measurement_rejected)
zero_run.measurement.correlate(one_run.measurement, ~0.5)
implicit_correlation_rejected = false
begin
  Physics.dataset(mass, [zero_run, one_run])
rescue error
  implicit_correlation_rejected = error.to_s.include?("explicit covariance")
experiment_check("dataset.declared_correlation_rejected", implicit_correlation_rejected)

tiny_run = Physics.observation(mass, Measurement.new(~3.0, ~1.0e-155), "tiny")
tiny_fit = Physics.dataset(mass, [tiny_run]).fit_constant
experiment_check("gls.subnormal_variance",
  tiny_fit.value == ~3.0 && (tiny_fit.uncertainty / ~1.0e-155 - ~1.0).abs < ~1.0e-12)
huge_a = Physics.observation(mass, Measurement.new(~1.0e308, ~1.0), "huge-a")
huge_b = Physics.observation(mass, Measurement.new(~1.0e308, ~1.0), "huge-b")
huge_fit = Physics.dataset(mass, [huge_a, huge_b]).fit_constant
experiment_check("gls.large_values",
  huge_fit.value == ~1.0e308 && huge_fit.chi_square == ~0.0)
experiment_check("gls.large_value_uncertainty",
  experiment_close?(huge_fit.uncertainty, ~1.0 / Math.sqrt(~2.0)))
wide_a = Physics.observation(mass, Measurement.new(~-1.0e154, ~1.0e154), "wide-a")
wide_b = Physics.observation(mass, Measurement.new(~1.0e154, ~1.0e154), "wide-b")
wide_fit = Physics.dataset(mass, [wide_a, wide_b]).fit_constant
experiment_check("gls.large_variance",
  wide_fit.value == ~0.0 && experiment_close?(wide_fit.chi_square, ~2.0) &&
  experiment_close?(wide_fit.uncertainty / ~1.0e154, ~1.0 / Math.sqrt(~2.0)))
unrepresentable_variance_rejected = false
begin
  microscopic = Physics.observation(mass, Measurement.new(~1.0, ~1.0e-200), "micro")
  Physics.dataset(mass, [microscopic])
rescue error
  unrepresentable_variance_rejected = true
experiment_check("gls.unrepresentable_variance_rejected", unrepresentable_variance_rejected)
experiment_check("observable.unit_rendering", mass.to_s == "m \[kg\]")
experiment_check("observation.rendering", run_a.to_s == "m \[kg\] = 10 ± 1")
experiment_check("estimate.rendering", estimate.to_s.include?("m \[kg\]"))

<< "physics_experiment_spec: all checks passed"
