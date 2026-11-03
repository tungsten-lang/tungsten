# Gradient-norm safeguarded globalized L-BFGS: formulas, diagnostics, normal
# cases, and explicit binary64/callback failure behavior.
#
# Run in both engines:
#   bin/tungsten spec/core/optimization_globalized_lbfgs_spec.w
#   bin/tungsten run --interpret spec/core/optimization_globalized_lbfgs_spec.w

use optimization

-> globalized_check(name, got, want = true)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> globalized_close?(got, want, tolerance = ~1.0e-8)
  (got - want).abs <= tolerance

-> globalized_vector_close?(got, want, tolerance = ~1.0e-8)
  return false if got.size != want.size
  i = 0
  while i < got.size
    return false if !globalized_close?(got[i], want[i], tolerance)
    i += 1
  true

# --- paper-specific criteria and safeguard formulas ----------------------

default_settings = OptimizationGlobalizedLBFGSCriteria.new
globalized_check("criteria.class", default_settings.class_name,
                 "OptimizationGlobalizedLBFGSCriteria")
globalized_check("criteria.safeguard_parameters",
                 default_settings.safeguard_cap == ~1.0e-4 &&
                 default_settings.safeguard_scale == ~1.0)
globalized_check("criteria.default_safeguard_exponent",
                 globalized_close?(default_settings.safeguard_exponent,
                                   ~1.0 / ~13.0, ~1.0e-15))
globalized_check("criteria.armijo_rate_parameter_condition",
                 default_settings.armijo_rate_parameter_condition?)

memoryless_settings = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-8, 100, 40, 0)
globalized_check("criteria.zero_history", memoryless_settings.history_size, 0)
globalized_check("criteria.zero_history_default_exponent",
                 globalized_close?(memoryless_settings.safeguard_exponent,
                                   ~1.0 / ~3.0, ~1.0e-15))
globalized_check("criteria.zero_history_armijo_condition",
                 memoryless_settings.armijo_rate_parameter_condition?)

uncalibrated = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-8, 10, 20, 2, ~1.0, ~1.0, ~0.25)
globalized_check("criteria.armijo_rate_parameter_condition_false",
                 uncalibrated.armijo_rate_parameter_condition?, false)

negative_history_raised = false
begin
  OptimizationGlobalizedLBFGSCriteria.new(~1.0e-8, 10, 20, -1)
rescue error
  negative_history_raised = true
globalized_check("criteria.negative_history", negative_history_raised)

zero_line_limit_raised = false
begin
  OptimizationGlobalizedLBFGSCriteria.new(~1.0e-8, 10, 0, 2)
rescue error
  zero_line_limit_raised = true
globalized_check("criteria.zero_line_limit", zero_line_limit_raised)

invalid_c0_raised = false
begin
  OptimizationGlobalizedLBFGSCriteria.new(
    ~1.0e-8, 10, 20, 2, ~1.1)
rescue error
  invalid_c0_raised = true
globalized_check("criteria.invalid_c0", invalid_c0_raised)

quality = Optimization.globalized_lbfgs_pair_quality(
  [~1.0, ~0.0], [~2.0, ~0.0])
globalized_check("safeguard.pair_quality",
                 globalized_close?(quality, ~0.5, ~1.0e-15))
globalized_check("safeguard.negative_curvature",
                 Optimization.globalized_lbfgs_pair_quality(
                   [~1.0], [~-1.0]), ~0.0)
globalized_check("safeguard.degenerate_pair",
                 Optimization.globalized_lbfgs_pair_quality(
                   [~0.0], [~1.0]), ~0.0)
globalized_check("safeguard.overflow_safe_quality",
                 globalized_close?(
                   Optimization.globalized_lbfgs_pair_quality(
                     [~1.0e200], [~1.0e200]),
                   ~1.0, ~1.0e-15))
globalized_check("safeguard.underflow_safe_quality",
                 globalized_close?(
                   Optimization.globalized_lbfgs_pair_quality(
                     [~1.0e-200], [~1.0e-200]),
                   ~1.0, ~1.0e-15))
unusable_large_pair = Optimization.globalized_lbfgs_pair_data(
  [~1.0e200], [~1.0e200])
globalized_check("safeguard.unrepresentable_curvature_classification",
                 !unusable_large_pair["ok"] &&
                 unusable_large_pair["bb_usable"] &&
                 unusable_large_pair["reason"] == :numerical &&
                 globalized_close?(unusable_large_pair["quality"],
                                   ~1.0, ~1.0e-15) &&
                 globalized_close?(unusable_large_pair["gamma_lower"],
                                   ~1.0, ~1.0e-15) &&
                 globalized_close?(unusable_large_pair["gamma_upper"],
                                   ~1.0, ~1.0e-15))
globalized_check("safeguard.memoryless_large_pair_seed",
                 Optimization.globalized_lbfgs_seed_scale(
                   unusable_large_pair["gamma_lower"],
                   unusable_large_pair["gamma_upper"], ~1.0e-4),
                 ~1.0)

threshold_settings = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-8, 10, 20, 2, ~0.5, ~0.25, ~0.5)
threshold = Optimization.globalized_lbfgs_threshold(
  ~1.0, threshold_settings)
globalized_check("safeguard.threshold",
                 globalized_close?(threshold, ~0.25, ~1.0e-15))

seed = Optimization.globalized_lbfgs_seed_scale(~0.5, ~2.0, ~0.1)
globalized_check("safeguard.seed_intersection",
                 globalized_close?(seed, ~0.5, ~1.0e-15))
fallback_seed = Optimization.globalized_lbfgs_seed_scale(
  ~1.0e-4, ~1.0e-3, ~0.1)
globalized_check("safeguard.seed_empty_intersection",
                 globalized_close?(fallback_seed, ~0.1, ~1.0e-15))

selection = Optimization.globalized_lbfgs_selected_history(
  [[~1.0, ~0.0], [~1.0, ~0.0]],
  [[~1.0, ~0.0], [~1.0e-6, ~0.0]],
  [~1.0, ~1.0e-6], [~1.0, ~1.0e6], ~1.0e-3)
globalized_check("safeguard.retrospective_filter", selection["steps"].size, 1)
globalized_check("safeguard.filter_rho",
                 globalized_close?(selection["rhos"][0], ~1.0,
                                   ~1.0e-15))
reactivated = Optimization.globalized_lbfgs_selected_history(
  [[~1.0, ~0.0], [~1.0, ~0.0]],
  [[~1.0, ~0.0], [~1.0e-6, ~0.0]],
  [~1.0, ~1.0e-6], [~1.0, ~1.0e6], ~1.0e-7)
globalized_check("safeguard.retrospective_reactivation",
                 reactivated["steps"].size, 2)

plain_direction = Optimization.globalized_lbfgs_two_loop_direction(
  [~2.0, ~-3.0], [], [], [], ~0.5)
globalized_check("safeguard.seeded_direction",
                 globalized_vector_close?(plain_direction,
                                          [~-1.0, ~1.5], ~1.0e-15))

# The solver's omega geometry is Euclidean: ||[3,4]||=5, so an uncapped
# c1*||g||^c2 safeguard is 0.5 rather than the infinity-norm value 0.4.
norm_geometry = Optimization.globalized_lbfgs(
  -> (x) ~0.0, [~0.0, ~0.0], -> (x) [~3.0, ~4.0],
  OptimizationGlobalizedLBFGSCriteria.new(
    ~0.0, 1, 1, 0, ~1.0, ~0.1, ~1.0))
globalized_check("safeguard.euclidean_gradient_geometry",
                 globalized_close?(norm_geometry.safeguard_gradient_norm,
                                   ~5.0, ~1.0e-15) &&
                 globalized_close?(norm_geometry.safeguard_threshold,
                                   ~0.5, ~1.0e-15))

# --- nominal solver behavior and result diagnostics ----------------------

quadratic = -> (x)
  (x[0] - ~3.0) ** 2 + ~2.0 * (x[1] + ~2.0) ** 2
quadratic_gradient = -> (x)
  [~2.0 * (x[0] - ~3.0), ~4.0 * (x[1] + ~2.0)]
quadratic_settings = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-10, 100, 40, 5, ~1.0e-4, ~1.0, ~0.05)
quadratic_result = Optimization.globalized_lbfgs(
  quadratic, [~0.0, ~0.0], quadratic_gradient, quadratic_settings)
globalized_check("quadratic.converged", quadratic_result.converged?)
globalized_check("quadratic.result_class", quadratic_result.class_name,
                 "OptimizationGlobalizedLBFGSResult")
globalized_check("quadratic.method", quadratic_result.method,
                 :globalized_lbfgs)
globalized_check("quadratic.parameters",
                 globalized_vector_close?(quadratic_result.parameters,
                                          [~3.0, ~-2.0], ~1.0e-7))
globalized_check("quadratic.objective", quadratic_result.value < ~1.0e-14)
globalized_check("quadratic.reason", quadratic_result.convergence_reason,
                 :gradient)
globalized_check("quadratic.euclidean_gradient",
                 quadratic_result.euclidean_gradient_norm <= ~1.0e-10)
globalized_check("quadratic.norm_compatibility",
                 quadratic_result.gradient_norm <=
                   quadratic_result.euclidean_gradient_norm)
globalized_check("quadratic.counts",
                 quadratic_result.gradient_evaluations ==
                   quadratic_result.iterations + 1 &&
                 quadratic_result.accepted_steps ==
                   quadratic_result.iterations &&
                 quadratic_result.function_evaluations ==
                   quadratic_result.line_search_evaluations + 1)
globalized_check("quadratic.curvature_history",
                 quadratic_result.accepted_curvature_pairs > 0 &&
                 quadratic_result.bb_scale_updates > 0 &&
                 quadratic_result.stored_pairs <= 5 &&
                 quadratic_result.maximum_pairs_used > 0 &&
                 quadratic_result.last_pairs_used <=
                   quadratic_result.stored_pairs &&
                 quadratic_result.filtered_pair_uses >= 0 &&
                 quadratic_result.history_restarts >= 0 &&
                 quadratic_result.rejected_curvature_pairs ==
                   quadratic_result.nonpositive_curvature_pairs +
                   quadratic_result.numerically_unusable_pairs)
globalized_check("quadratic.safeguard_diagnostics",
                 quadratic_result.safeguard_threshold > ~0.0 &&
                 Optimization.finite_value?(quadratic_result.seed_scale))
globalized_check("quadratic.armijo_rate_parameter_condition",
                 quadratic_result.armijo_rate_parameter_condition?)
globalized_check("quadratic.uncertified", quadratic_result.certified?, false)

memoryless_result = Optimization.globalized_lbfgs(
  quadratic, [~0.0, ~0.0], quadratic_gradient,
  OptimizationGlobalizedLBFGSCriteria.new(
    ~1.0e-9, 200, 40, 0, ~1.0, ~1.0, ~0.1))
globalized_check("memoryless.converged", memoryless_result.converged?)
globalized_check("memoryless.curvature_diagnostics",
                 memoryless_result.accepted_curvature_pairs > 0 &&
                 memoryless_result.stored_pairs == 0 &&
                 memoryless_result.maximum_pairs_used == 0)

# Rosenbrock starts in a nonconvex level set, matching the paper's canonical
# small example while keeping this check purely numerical.
rosenbrock = -> (x)
  (~1.0 - x[0]) ** 2 + ~100.0 * (x[1] - x[0] * x[0]) ** 2
rosenbrock_gradient = -> (x)
  [~-2.0 * (~1.0 - x[0]) -
     ~400.0 * x[0] * (x[1] - x[0] * x[0]),
   ~200.0 * (x[1] - x[0] * x[0])]
rosenbrock_settings = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-6, 1000, 50, 5, ~1.0e-4, ~1.0, ~0.05)
rosenbrock_result = Optimization.globalized_lbfgs(
  rosenbrock, [~-1.2, ~1.0], rosenbrock_gradient,
  rosenbrock_settings)
globalized_check("rosenbrock.converged", rosenbrock_result.converged?)
globalized_check("rosenbrock.parameters",
                 globalized_vector_close?(rosenbrock_result.parameters,
                                          [~1.0, ~1.0], ~2.0e-4))
globalized_check("rosenbrock.gradient",
                 rosenbrock_result.euclidean_gradient_norm <= ~1.0e-6)
globalized_check("rosenbrock.history_used",
                 rosenbrock_result.maximum_pairs_used > 0)

# --- explicit failures and edge behavior ---------------------------------

zero_iterations = OptimizationGlobalizedLBFGSCriteria.new(
  ~1.0e-12, 0, 10, 3, ~1.0, ~1.0, ~0.1)
limited = Optimization.globalized_lbfgs(
  quadratic, [~0.0, ~0.0], quadratic_gradient, zero_iterations)
globalized_check("failure.iteration_limit", limited.status_code,
                 :iteration_limit)
globalized_check("failure.iteration_counts",
                 limited.function_evaluations == 1 &&
                 limited.gradient_evaluations == 1 &&
                 limited.iterations == 0)

raising_objective = -> (x)
  raise "objective failed"
objective_failure = Optimization.globalized_lbfgs(
  raising_objective, [~0.0], -> (x) [~1.0])
globalized_check("failure.objective_callback", objective_failure.status_code,
                 :callback_error)
globalized_check("failure.objective_count",
                 objective_failure.function_evaluations, 1)

raising_gradient = -> (x)
  raise "gradient failed"
gradient_failure = Optimization.globalized_lbfgs(
  -> (x) x[0] * x[0], [~1.0], raising_gradient)
globalized_check("failure.gradient_callback", gradient_failure.status_code,
                 :callback_error)
globalized_check("failure.gradient_count",
                 gradient_failure.gradient_evaluations, 1)

wrong_gradient = Optimization.globalized_lbfgs(
  -> (x) x[0] * x[0], [~1.0], -> (x) [~1.0, ~2.0])
globalized_check("failure.gradient_shape", wrong_gradient.status_code,
                 :invalid_gradient)

nonfinite_gradient = Optimization.globalized_lbfgs(
  -> (x) x[0] * x[0], [~1.0],
  -> (x) [Math.exp(~10000.0)])
globalized_check("failure.nonfinite_gradient",
                 nonfinite_gradient.status_code, :non_finite_value)

# A deliberately inconsistent objective/gradient pair cannot satisfy Armijo.
short_line_search = OptimizationGlobalizedLBFGSCriteria.new(
  ~0.0, 5, 3, 2, ~1.0, ~1.0, ~0.1)
line_failure = Optimization.globalized_lbfgs(
  -> (x) ~0.0, [~0.0], -> (x) [~1.0], short_line_search)
globalized_check("failure.line_search", line_failure.status_code,
                 :line_search_failed)
globalized_check("failure.line_search_count",
                 line_failure.line_search_evaluations, 3)

# Exhaustion reports the terminal trial, even when an earlier trial was a
# valid finite Armijo rejection.
mixed_trial = Optimization.globalized_lbfgs_line_search(
  -> (x) x[0] > ~-0.75 ? Math.exp(~10000.0) : ~0.0,
  [~0.0], ~0.0, [~1.0], [~-1.0], 2)
globalized_check("failure.terminal_nonfinite_trial", mixed_trial["code"],
                 :non_finite_value)
globalized_check("failure.terminal_nonfinite_count",
                 mixed_trial["evaluations"], 2)

valid_then_stagnant = Optimization.globalized_lbfgs_line_search(
  -> (x) ~0.0, [~1.0e308], ~0.0, [~1.0], [~-2.0e292], 3)
globalized_check("failure.terminal_precision_trial",
                 valid_then_stagnant["code"], :precision_limit)

# Negative curvature is counted and never enters inverse-Hessian history.
one_iteration = OptimizationGlobalizedLBFGSCriteria.new(
  ~0.0, 1, 10, 2, ~1.0, ~1.0, ~0.1)
concave = Optimization.globalized_lbfgs(
  -> (x) ~0.0 - x[0] * x[0], [~1.0],
  -> (x) [~-2.0 * x[0]], one_iteration)
globalized_check("edge.negative_curvature_status", concave.status_code,
                 :iteration_limit)
globalized_check("edge.negative_curvature_rejected",
                 concave.rejected_curvature_pairs == 1 &&
                 concave.nonpositive_curvature_pairs == 1 &&
                 concave.numerically_unusable_pairs == 0)
globalized_check("edge.negative_curvature_not_stored", concave.stored_pairs, 0)

underflow_settings = OptimizationGlobalizedLBFGSCriteria.new(
  ~0.0, 2, 10, 2, ~1.0, ~1.0e-300, ~2.0)
underflow = Optimization.globalized_lbfgs(
  -> (x) x[0] * x[0], [~5.0e-101],
  -> (x) [~2.0 * x[0]], underflow_settings)
globalized_check("edge.safeguard_underflow", underflow.status_code,
                 :precision_limit)

unchanged_trial = Optimization.globalized_lbfgs(
  -> (x) x[0], [~1.0e308], -> (x) [~1.0],
  OptimizationGlobalizedLBFGSCriteria.new(
    ~0.0, 1, 2, 0, ~1.0e-4, ~1.0, ~0.1))
globalized_check("edge.unrepresentable_trial", unchanged_trial.status_code,
                 :precision_limit)
globalized_check("edge.unrepresentable_trial_count",
                 unchanged_trial.line_search_evaluations, 0)

analytic_gradient_raised = false
begin
  Optimization.globalized_lbfgs(quadratic, [~0.0, ~0.0], nil)
rescue error
  analytic_gradient_raised = true
globalized_check("contract.analytic_gradient_required",
                 analytic_gradient_raised)

<< "optimization_globalized_lbfgs_spec: all checks passed"
