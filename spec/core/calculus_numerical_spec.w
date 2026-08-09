# Status-aware black-box differentiation and Gauss-Kronrod quadrature.
#
# Run in both engines:
#   bin/tungsten run spec/core/calculus_numerical_spec.w
#   bin/tungsten compile spec/core/calculus_numerical_spec.w \
#     --out /tmp/calculus-numerical-spec

use calculus

-> numerical_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> numerical_close?(got, want, tolerance = ~1.0e-8)
  difference = Calculus.abs(got - want)
  scale = Calculus.abs(want)
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

-> staged_slope(x)
  x.abs < ~0.06 ? ~2.0 * x : x

-> large_sign(x)
  x < ~0.0 ? ~-1.0e308 : ~1.0e308

-> large_linear(x)
  ~1.0e308 * x

-> tiny_step_quadratic(x)
  ~1.0e200 * x * x

-> large_constant(x)
  ~1.0e308

-> fourteenth_power(x)
  x2 = x*x
  x4 = x2*x2
  x8 = x4*x4
  x8*x4*x2

-> child_failure_integrand(x)
  return Math.log(~-1.0) if x == ~0.25
  (x - ~0.123456789).abs

-> callback_boom(x)
  raise "callback boom"

# --- scalar numerical derivatives ----------------------------------------

sine = Calculus.numerical_derivative(-> (x) Math.sin(x), ~1.0)
numerical_check("derivative.sine.status", sine.converged?)
numerical_check("derivative.sine.value",
                numerical_close?(sine.value, Math.cos(~1.0)))
numerical_check("derivative.sine.metadata",
                sine.order == 1 && sine.scheme == :central)
numerical_check("derivative.sine.evaluations",
                sine.evaluations == 2 * sine.levels)
numerical_check("derivative.sine.attempts", sine.attempts == sine.levels)
numerical_check("derivative.sine.estimate", sine.estimate_available?)
numerical_check("derivative.sine.algorithm",
                sine.algorithm == :richardson_extrapolation)
numerical_check("derivative.sine.error_model",
                sine.error_model == :successive_extrapolation_consistency)
numerical_check("derivative.sine.not_certified", !sine.certified?)

quartic_second = Calculus.numerical_derivative(
  -> (x) x*x*x*x, ~2.0, 2)
numerical_check("derivative.second.status", quartic_second.converged?)
numerical_check("derivative.second.value",
                numerical_close?(quartic_second.value, ~48.0))
numerical_check("derivative.second.evaluations",
                quartic_second.evaluations == 3 * quartic_second.levels)

forward = Calculus.numerical_derivative(
  -> (x) x*x*x, ~0.0, 1, :forward)
numerical_check("derivative.forward.status", forward.converged?)
numerical_check("derivative.forward.value",
                numerical_close?(forward.value, ~0.0))
numerical_check("derivative.forward.evaluations",
                forward.evaluations == 3 * forward.levels)

backward_second = Calculus.numerical_derivative(
  -> (x) x*x*x*x, ~1.0, 2, :backward)
numerical_check("derivative.backward_second.status",
                backward_second.converged?)
numerical_check("derivative.backward_second.value",
                numerical_close?(backward_second.value, ~12.0, ~1.0e-7))

# Coarse rows see slope one, but finer rows enter the true local slope-two
# neighborhood. The controller must not stop at a stale historical best.
recovered = Calculus.numerical_derivative(
  -> (x) staged_slope(x), ~0.0)
numerical_check("derivative.finer_scale_recovery.status", recovered.converged?)
numerical_check("derivative.finer_scale_recovery.value",
                numerical_close?(recovered.value, ~2.0))

domain_recovered = Calculus.numerical_derivative(
  -> (x) Math.log(x), ~0.05)
numerical_check("derivative.domain_recovery.status", domain_recovered.converged?)
numerical_check("derivative.domain_recovery.value",
                numerical_close?(domain_recovered.value, ~20.0, ~1.0e-6))
numerical_check("derivative.domain_recovery.attempts",
                domain_recovered.attempts > domain_recovered.levels)

arithmetic_recovered = Calculus.numerical_derivative(
  -> (x) x, ~0.0, 1, :central, ~1.0e308)
numerical_check("derivative.coarse_arithmetic_recovery.status",
                arithmetic_recovered.converged?)
numerical_check("derivative.coarse_arithmetic_recovery.value",
                arithmetic_recovered.value == ~1.0)

large_derivative = Calculus.numerical_derivative(
  -> (x) large_linear(x), ~0.0)
numerical_check("derivative.large_value.status", large_derivative.converged?)
numerical_check("derivative.large_value.value",
                numerical_close?(large_derivative.value, ~1.0e308))

tiny_step_second = Calculus.numerical_derivative(
  -> (x) tiny_step_quadratic(x), ~0.0, 2, :central, ~1.0e-200)
numerical_check("derivative.tiny_step_second.status",
                tiny_step_second.converged?)
numerical_check("derivative.tiny_step_second.value",
                numerical_close?(tiny_step_second.value, ~2.0e200, ~1.0e-6))

constant_central_first = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 1, :central)
constant_central_second = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 2, :central)
constant_forward_first = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 1, :forward)
constant_forward_second = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 2, :forward)
constant_backward_first = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 1, :backward)
constant_backward_second = Calculus.numerical_derivative(
  -> (x) large_constant(x), ~0.0, 2, :backward)
numerical_check("derivative.large_constant.all_stencils",
                constant_central_first.converged? &&
                constant_central_second.converged? &&
                constant_forward_first.converged? &&
                constant_forward_second.converged? &&
                constant_backward_first.converged? &&
                constant_backward_second.converged?)
numerical_check("derivative.large_constant.zero",
                constant_central_first.value == ~0.0 &&
                constant_central_second.value == ~0.0 &&
                constant_forward_first.value == ~0.0 &&
                constant_forward_second.value == ~0.0 &&
                constant_backward_first.value == ~0.0 &&
                constant_backward_second.value == ~0.0)

limited = Calculus.numerical_derivative(
  -> (x) Math.exp(x), ~0.5, 1, :central,
  ~0.1, ~1.0e-30, ~0.0, 2)
numerical_check("derivative.max_levels", limited.status == :max_levels)
numerical_check("derivative.max_levels.has_estimate",
                limited.estimate_available?)

roundoff_derivative = Calculus.numerical_derivative(
  -> (x) Math.sin(~100000000.0 * x),
  ~1.0, 1, :central, ~0.1, ~1.0e-30, ~0.0, 30)
numerical_check("derivative.roundoff_or_noise_limited",
                roundoff_derivative.status == :roundoff_or_noise_limited)

unrepresentable = Calculus.numerical_derivative(
  -> (x) x*x, ~1.0e300, 1, :central, ~1.0)
numerical_check("derivative.step_unrepresentable",
                unrepresentable.status == :step_unrepresentable)
numerical_check("derivative.step_unrepresentable.no_estimate",
                !unrepresentable.estimate_available?)
numerical_check("derivative.step_unrepresentable.nil_value",
                unrepresentable.value == nil)

duplicate_forward = Calculus.numerical_derivative(
  -> (x) x, ~1.0, 1, :forward, ~1.5e-16)
numerical_check("derivative.forward_duplicate",
                duplicate_forward.status == :step_unrepresentable)

overflowing_abscissa = Calculus.numerical_derivative(
  -> (x) ~0.0, ~1.0e308, 1, :forward,
  ~1.0e308, ~1.0e-10, ~1.0e-8, 2, ~1.1)
numerical_check("derivative.nonfinite_abscissa",
                overflowing_abscissa.status == :nonfinite_abscissa)
numerical_check("derivative.nonfinite_abscissa.no_estimate",
                !overflowing_abscissa.estimate_available?)
numerical_check("derivative.nonfinite_abscissa.attempts",
                overflowing_abscissa.attempts > overflowing_abscissa.levels)

nan_sample = Calculus.numerical_derivative(
  -> (x) Math.log(~-1.0), ~0.0)
numerical_check("derivative.nonfinite_sample",
                nan_sample.status == :nonfinite_sample)
numerical_check("derivative.nonfinite_sample.no_estimate",
                !nan_sample.estimate_available?)

overflowing_arithmetic = Calculus.numerical_derivative(
  -> (x) large_sign(x), ~0.0)
numerical_check("derivative.nonfinite_arithmetic",
                overflowing_arithmetic.status == :nonfinite_arithmetic)

zero_derivative = Calculus.numerical_derivative(
  -> (x) ~7.0, ~0.0)
numerical_check("derivative.zero.status", zero_derivative.converged?)
numerical_check("derivative.zero.cancellation",
                zero_derivative.cancellation_indicator == ~1.0e308)

bad_derivative_raised = false
begin
  Calculus.numerical_derivative(-> (x) x, ~0.0, 3)
rescue bad_derivative_error
  bad_derivative_raised = bad_derivative_error.to_s.include?("orders 1 and 2")
numerical_check("derivative.invalid_order_raises", bad_derivative_raised)

weak_contraction_raised = false
begin
  Calculus.numerical_derivative(
    -> (x) Math.exp(x), ~0.0, 1, :central,
    ~0.1, ~1.0e-10, ~1.0e-8, 10, ~1.0000000000000002)
rescue weak_contraction_error
  weak_contraction_raised = weak_contraction_error.to_s.include?("at least 1.1")
numerical_check("derivative.ill_conditioned_contraction_raises",
                weak_contraction_raised)

bad_scheme_raised = false
begin
  Calculus.numerical_derivative(-> (x) x, ~0.0, 1, :diagonal)
rescue bad_scheme_error
  bad_scheme_raised = bad_scheme_error.to_s.include?("scheme")
numerical_check("derivative.invalid_scheme_raises", bad_scheme_raised)

bad_point_raised = false
begin
  Calculus.numerical_derivative(-> (x) x, Math.log(~-1.0))
rescue bad_point_error
  bad_point_raised = bad_point_error.to_s.include?("point")
numerical_check("derivative.invalid_point_raises", bad_point_raised)

bad_step_raised = false
begin
  Calculus.numerical_derivative(
    -> (x) x, ~0.0, 1, :central, ~0.0)
rescue bad_step_error
  bad_step_raised = bad_step_error.to_s.include?("initial_step")
numerical_check("derivative.invalid_step_raises", bad_step_raised)

bad_relative_tolerance_raised = false
begin
  Calculus.numerical_derivative(
    -> (x) x, ~0.0, 1, :central, nil, ~1.0e-10, ~-1.0)
rescue bad_relative_tolerance_error
  bad_relative_tolerance_raised = bad_relative_tolerance_error.to_s.include?("relative tolerance")
numerical_check("derivative.invalid_relative_tolerance_raises",
                bad_relative_tolerance_raised)

bad_levels_raised = false
begin
  Calculus.numerical_derivative(
    -> (x) x, ~0.0, 1, :central,
    nil, ~1.0e-10, ~1.0e-8, 1)
rescue bad_levels_error
  bad_levels_raised = bad_levels_error.to_s.include?("max_levels")
numerical_check("derivative.invalid_max_levels_raises", bad_levels_raised)

callback_raised = false
begin
  Calculus.numerical_derivative(-> (x) callback_boom(x), ~0.0)
rescue callback_error
  callback_raised = callback_error.to_s.include?("callback boom")
numerical_check("derivative.callback_propagates", callback_raised)

# --- adaptive Gauss-Kronrod 7/15 -----------------------------------------

cancellation_panels = [
  [~0.0, ~1.0, ~1.0e16],
  [~1.0, ~2.0, ~1.0],
  [~2.0, ~3.0, ~-1.0e16]
]
numerical_check("gk.compensated_total.cancellation",
                Calculus.gk15_compensated_total(
                  cancellation_panels, 2) == ~1.0)

polynomial = Calculus.integrate_gk15(
  -> (x) x*x*x*x*x*x, ~0.0, ~1.0)
numerical_check("gk.polynomial.status", polynomial.converged?)
numerical_check("gk.polynomial.value",
                numerical_close?(polynomial.value,
                                 ~0.14285714285714285, ~1.0e-11))
numerical_check("gk.polynomial.one_panel", polynomial.intervals == 1)
numerical_check("gk.polynomial.evaluations", polynomial.evaluations == 15)
numerical_check("gk.polynomial.companion",
                numerical_close?(polynomial.companion_value,
                                 polynomial.value, ~1.0e-12))
numerical_check("gk.polynomial.resabs",
                polynomial.absolute_integral_estimate >= polynomial.value)
numerical_check("gk.polynomial.algorithm",
                polynomial.algorithm == :adaptive_gk15)
numerical_check("gk.polynomial.error_model",
                polynomial.error_model == :embedded_gauss_kronrod)
numerical_check("gk.polynomial.estimate", polynomial.estimate_available?)
numerical_check("gk.polynomial.coverage", polynomial.complete_coverage?)
numerical_check("gk.polynomial.not_certified", !polynomial.certified?)

degree_fourteen = Calculus.integrate_gk15(
  -> (x) fourteenth_power(x), ~0.0, ~1.0,
  ~1.0e-8, ~0.0, 1, 15)
numerical_check("gk.degree_fourteen.kronrod_exact",
                numerical_close?(degree_fourteen.value,
                                 ~0.06666666666666667, ~1.0e-12))
numerical_check("gk.degree_fourteen.embedded_pair_differs",
                Calculus.abs(degree_fourteen.value -
                             degree_fourteen.companion_value) > ~1.0e-10)

sine_integral = Calculus.integrate_gk15(
  -> (x) Math.sin(x), ~0.0, ~3.141592653589793)
numerical_check("gk.sine.status", sine_integral.converged?)
numerical_check("gk.sine.value",
                numerical_close?(sine_integral.value, ~2.0, ~1.0e-11))

reversed = Calculus.integrate_gk15(
  -> (x) x*x, ~1.0, ~0.0)
numerical_check("gk.reversed",
                numerical_close?(reversed.value,
                                 ~-0.3333333333333333, ~1.0e-11))
numerical_check("gk.reversed.companion_sign", reversed.companion_value < ~0.0)

zero_width = Calculus.integrate_gk15(-> (x) x, ~2.0, ~2.0)
numerical_check("gk.zero_width.status", zero_width.converged?)
numerical_check("gk.zero_width.value", zero_width.value == ~0.0)
numerical_check("gk.zero_width.evaluations", zero_width.evaluations == 0)

interval_limited = Calculus.integrate_gk15(
  -> (x) (x - ~0.123456789).abs,
  ~0.0, ~1.0, ~1.0e-16, ~0.0, 1, 15)
numerical_check("gk.max_intervals",
                interval_limited.status == :max_intervals)

evaluation_limited = Calculus.integrate_gk15(
  -> (x) (x - ~0.123456789).abs,
  ~0.0, ~1.0, ~1.0e-16, ~0.0, 128, 15)
numerical_check("gk.max_evaluations",
                evaluation_limited.status == :max_evaluations)

collapsed = Calculus.integrate_gk15(
  -> (x) x, ~1.0, ~1.0000000000000002)
numerical_check("gk.precision_limit", collapsed.status == :precision_limit)
numerical_check("gk.precision_limit.no_estimate", !collapsed.estimate_available?)
numerical_check("gk.precision_limit.no_coverage", !collapsed.complete_coverage?)
numerical_check("gk.precision_limit.nil_value", collapsed.value == nil)
numerical_check("gk.precision_limit.to_s",
                collapsed.to_s.include?("no estimate") &&
                collapsed.to_s.include?("precision_limit"))

subnormal_panel = Calculus.integrate_gk15(
  -> (x) large_constant(x), ~0.0, ~6.3734468313520804e-322,
  ~1.0e-20, ~0.0)
numerical_check("gk.subnormal_scaling.precision_limit",
                subnormal_panel.status == :precision_limit)
numerical_check("gk.subnormal_scaling.no_false_estimate",
                !subnormal_panel.estimate_available?)

subnormal_sample = Calculus.integrate_gk15(
  -> (x) ~9.8813129168249309e-324, ~0.0, ~1.0,
  ~4.9406564584124654e-324, ~0.0)
numerical_check("gk.subnormal_sample.precision_limit",
                subnormal_sample.status == :precision_limit)
numerical_check("gk.subnormal_sample.no_false_estimate",
                !subnormal_sample.estimate_available?)

nonfinite_integrand = Calculus.integrate_gk15(
  -> (x) Math.log(~-1.0), ~0.0, ~1.0)
numerical_check("gk.nonfinite_integrand",
                nonfinite_integrand.status == :nonfinite_integrand)
numerical_check("gk.nonfinite_integrand.no_estimate",
                !nonfinite_integrand.estimate_available?)

complex_integrand = Calculus.integrate_gk15(
  -> (x) Complex<f64>.real(x), ~0.0, ~1.0)
numerical_check("gk.complex_integrand_is_unsupported",
                complex_integrand.status == :nonfinite_integrand)

large_integral = Calculus.integrate_gk15(
  -> (x) large_constant(x), ~0.0, ~1.0)
numerical_check("gk.large_representable.status", large_integral.converged?)
numerical_check("gk.large_representable.value",
                numerical_close?(large_integral.value, ~1.0e308))

nonfinite_arithmetic = Calculus.integrate_gk15(
  -> (x) large_constant(x), ~0.0, ~2.0)
numerical_check("gk.nonfinite_arithmetic",
                nonfinite_arithmetic.status == :nonfinite_arithmetic)

child_failure = Calculus.integrate_gk15(
  -> (x) child_failure_integrand(x),
  ~0.0, ~1.0, ~1.0e-16, ~0.0, 128, 3825)
numerical_check("gk.child_failure.status",
                child_failure.status == :nonfinite_integrand)
numerical_check("gk.child_failure.retains_estimate",
                child_failure.estimate_available?)
numerical_check("gk.child_failure.coverage", child_failure.complete_coverage?)
numerical_check("gk.child_failure.old_partition",
                child_failure.intervals == 1)

roundoff_limited = Calculus.integrate_gk15(
  -> (x) ~1.0, ~0.0, ~1.0,
  ~1.0e-30, ~0.0, 128, 3825)
numerical_check("gk.roundoff_limited",
                roundoff_limited.status == :roundoff_limited)
numerical_check("gk.roundoff_limited.has_estimate",
                roundoff_limited.estimate_available?)

refined = Calculus.integrate_gk15(
  -> (x) (x - ~0.123456789).abs,
  ~0.0, ~1.0, ~1.0e-9, ~0.0, 128, 3825)
left_area = ~0.123456789 * ~0.123456789
right_width = ~1.0 - ~0.123456789
right_area = right_width * right_width
expected_abs = (left_area + right_area) / ~2.0
numerical_check("gk.refined.status", refined.converged?)
numerical_check("gk.refined.value",
                numerical_close?(refined.value, expected_abs, ~1.0e-8))
numerical_check("gk.refined.evaluation_invariant",
                refined.evaluations == 15 + 30 * (refined.intervals - 1))
numerical_check("gk.refined.worst_interval", refined.worst_interval != nil)

bad_gk_raised = false
begin
  Calculus.integrate_gk15(-> (x) x, ~0.0, ~1.0, ~-1.0)
rescue bad_gk_error
  bad_gk_raised = bad_gk_error.to_s.include?("absolute tolerance")
numerical_check("gk.invalid_tolerance_raises", bad_gk_raised)

bad_gk_bound_raised = false
begin
  Calculus.integrate_gk15(
    -> (x) x, ~0.0, Math.log(~-1.0))
rescue bad_gk_bound_error
  bad_gk_bound_raised = bad_gk_bound_error.to_s.include?("upper bound")
numerical_check("gk.invalid_bound_raises", bad_gk_bound_raised)

bad_gk_relative_raised = false
begin
  Calculus.integrate_gk15(
    -> (x) x, ~0.0, ~1.0, ~1.0e-10, ~-1.0)
rescue bad_gk_relative_error
  bad_gk_relative_raised = bad_gk_relative_error.to_s.include?("relative tolerance")
numerical_check("gk.invalid_relative_tolerance_raises",
                bad_gk_relative_raised)

bad_gk_intervals_raised = false
begin
  Calculus.integrate_gk15(
    -> (x) x, ~0.0, ~1.0, ~1.0e-10, ~1.0e-10, 0)
rescue bad_gk_intervals_error
  bad_gk_intervals_raised = bad_gk_intervals_error.to_s.include?("max_intervals")
numerical_check("gk.invalid_max_intervals_raises", bad_gk_intervals_raised)

bad_gk_evaluations_raised = false
begin
  Calculus.integrate_gk15(
    -> (x) x, ~0.0, ~1.0,
    ~1.0e-10, ~1.0e-10, 1024, 14)
rescue bad_gk_evaluations_error
  bad_gk_evaluations_raised = bad_gk_evaluations_error.to_s.include?("max_evaluations")
numerical_check("gk.invalid_max_evaluations_raises",
                bad_gk_evaluations_raised)

gk_callback_raised = false
begin
  Calculus.integrate_gk15(-> (x) callback_boom(x), ~0.0, ~1.0)
rescue gk_callback_error
  gk_callback_raised = gk_callback_error.to_s.include?("callback boom")
numerical_check("gk.callback_propagates", gk_callback_raised)

# --- adaptive Simpson compatibility --------------------------------------

legacy_result = QuadratureResult.new(~1.0, ~0.1, 3, 1, true)
numerical_check("simpson.constructor_compat", legacy_result.to_a == [~1.0, ~0.1])
numerical_check("simpson.to_s_compat",
                legacy_result.to_s ==
                "QuadratureResult(1 ± 0.10000000000000001, converged)")
numerical_check("simpson.status_compat", legacy_result.status == :converged)
numerical_check("simpson.algorithm_compat",
                legacy_result.algorithm == :adaptive_simpson)
numerical_check("simpson.error_model_compat",
                legacy_result.error_model == :richardson_difference)
numerical_check("simpson.coverage_compat", legacy_result.complete_coverage?)

legacy_failure = QuadratureResult.new(~1.0, ~0.1, 3, 1, false)
numerical_check("simpson.failure_status_compat",
                legacy_failure.status == :max_depth)
normalized_success = QuadratureResult.new(
  ~1.0, ~0.1, 3, 1, false, :converged)
numerical_check("quadrature.explicit_status_is_authoritative",
                normalized_success.converged?)
normalized_failure = QuadratureResult.new(
  ~1.0, ~0.1, 3, 1, true, :max_intervals)
numerical_check("quadrature.explicit_failure_status_is_authoritative",
                !normalized_failure.converged?)

simpson = Calculus.integrate(-> (x) x*x, ~0.0, ~1.0)
numerical_check("simpson.facade_unchanged",
                simpson.algorithm == :adaptive_simpson)
simpson_quad = Calculus.quad(-> (x) x*x, ~0.0, ~1.0)
numerical_check("simpson.quad_facade_unchanged",
                simpson_quad.algorithm == :adaptive_simpson)
simpson_limited = Calculus.integrate(
  -> (x) Math.exp(x), ~0.0, ~1.0, ~1.0e-16, ~0.0, 0)
numerical_check("simpson.max_depth_status",
                simpson_limited.status == :max_depth)

<< "calculus_numerical_spec: all checks passed"
