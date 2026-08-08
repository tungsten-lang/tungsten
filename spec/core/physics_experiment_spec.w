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

bad_covariance_rejected = false
begin
  Physics.dataset(mass, [run_a, run_b], [[~1.0, ~0.1], [~0.2, ~4.0]])
rescue error
  bad_covariance_rejected = error.to_s.include?("symmetric")
experiment_check("covariance.asymmetry_rejected", bad_covariance_rejected)

nonfinite_covariance_rejected = false
begin
  not_a_number = ~1.0e999 - ~1.0e999
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

<< "physics_experiment_spec: all checks passed"
