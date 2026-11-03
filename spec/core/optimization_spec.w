# Bounded scalar optimization results, convergence, and failure behavior.
#
# Run in both engines:
#   bin/tungsten spec/core/optimization_spec.w
#   bin/tungsten run --interpret spec/core/optimization_spec.w

use optimization

-> optimization_check(name, got, want = true)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> optimization_close?(got, want, tolerance = ~1.0e-10)
  (got - want).abs <= tolerance

# These names are deliberately domain-qualified. The current contracts include
# optimization-specific status codes, scalar brackets, and root/minimum aliases;
# they are not generic containers for integration, ODE, or fitting results.
naming_criteria = OptimizationCriteria.new
optimization_check("naming.criteria", naming_criteria.class_name,
                   "OptimizationCriteria")
naming_status = OptimizationStatus.new(:converged, "done")
optimization_check("naming.status", naming_status.class_name,
                   "OptimizationStatus")

# --- bisection ------------------------------------------------------------

square_root = Optimization.bisection(
  -> (x) x * x - ~2.0, ~0.0, ~2.0)
optimization_check("naming.result", square_root.class_name,
                   "OptimizationResult")
optimization_check("bisection.kind", square_root.kind, :root)
optimization_check("bisection.converged", square_root.converged?)
optimization_check("bisection.status", square_root.status_code, :converged)
optimization_check("bisection.root",
                   optimization_close?(square_root.root,
                                       ~1.4142135623730951))
optimization_check("bisection.residual",
                   square_root.residual.abs < ~1.0e-10)
root_in_bracket = square_root.lower_bound <= square_root.root
below_upper = square_root.root <= square_root.upper_bound
root_in_bracket = root_in_bracket && below_upper
optimization_check("bisection.bracket", root_in_bracket)
root_metadata = square_root.iterations > 0
evaluation_count_ok = square_root.evaluations >= square_root.iterations + 2
root_metadata = root_metadata && evaluation_count_ok
optimization_check("bisection.metadata", root_metadata)
optimization_check("bisection.not_certified", square_root.certified?, false)

endpoint = Optimization.root(-> (x) x - ~3.0, ~3.0, ~8.0)
optimization_check("bisection.endpoint", endpoint.root, ~3.0)
optimization_check("bisection.endpoint_iterations", endpoint.iterations, 0)
optimization_check("bisection.endpoint_evaluations", endpoint.evaluations, 1)

residual_criteria = OptimizationCriteria.new(
  ~1.0e-30, ~0.0, ~1.0e-6, 100)
residual_stop = Optimization.bisection(
  -> (x) x * x - ~2.0, ~0.0, ~2.0, residual_criteria)
optimization_check("bisection.residual_tolerance",
                   residual_stop.residual.abs <= ~1.0e-6)
optimization_check("bisection.residual_stops_early",
                   residual_stop.iterations < square_root.iterations)

bad_bracket = Optimization.bisection(
  -> (x) x * x + ~1.0, ~-1.0, ~1.0)
optimization_check("bisection.bad_bracket", bad_bracket.converged?, false)
optimization_check("bisection.bad_bracket_status",
                   bad_bracket.status_code, :invalid_bracket)
optimization_check("bisection.bad_bracket_evaluations",
                   bad_bracket.evaluations, 2)

no_root_iterations = OptimizationCriteria.new(
  ~1.0e-12, ~1.0e-12, ~0.0, 0)
limited_root = Optimization.bisection(
  -> (x) x * x - ~2.0, ~0.0, ~2.0, no_root_iterations)
optimization_check("bisection.iteration_limit",
                   limited_root.status_code, :iteration_limit)
optimization_check("bisection.iteration_limit_count",
                   limited_root.iterations, 0)

zero_iteration_convergence = OptimizationCriteria.new(
  ~1.0, ~0.0, ~0.0, 0)
narrow_root = Optimization.bisection(
  -> (x) x, ~-0.5, ~0.5, zero_iteration_convergence)
optimization_check("bisection.zero_iteration_convergence",
                   narrow_root.status_code, :converged)
optimization_check("bisection.zero_iteration_count",
                   narrow_root.iterations, 0)

last_root_iteration = OptimizationCriteria.new(
  ~0.26, ~0.0, ~0.0, 1)
last_step_root = Optimization.bisection(
  -> (x) x - ~0.25, ~0.0, ~1.0, last_root_iteration)
optimization_check("bisection.last_iteration_converges",
                   last_step_root.status_code, :converged)
optimization_check("bisection.last_iteration_count",
                   last_step_root.iterations, 1)

non_finite_root = Optimization.bisection(
  -> (x) Math.exp(~10000.0), ~0.0, ~1.0)
optimization_check("bisection.non_finite",
                   non_finite_root.status_code, :non_finite_value)
optimization_check("bisection.non_finite_visible",
                   !Optimization.finite_value?(non_finite_root.value))

precision_criteria = OptimizationCriteria.new(
  ~1.0e-30, ~0.0, ~0.0, 100)
large_lo = ~10000000000000000.0
large_hi = ~10000000000000002.0
precision_root = Optimization.bisection(
  -> (x) x == large_lo ? ~-1.0 : ~1.0,
  large_lo, large_hi, precision_criteria)
optimization_check("bisection.precision_limit",
                   precision_root.status_code, :precision_limit)

# --- golden-section minimization -----------------------------------------

quadratic = Optimization.golden_section(
  -> (x) (x - ~2.5) * (x - ~2.5), ~-4.0, ~7.0)
optimization_check("golden.kind", quadratic.kind, :minimum)
optimization_check("golden.converged", quadratic.converged?)
optimization_check("golden.status", quadratic.status_code, :converged)
optimization_check("golden.argmin",
                   optimization_close?(quadratic.argmin, ~2.5, ~1.0e-9))
optimization_check("golden.minimum",
                   quadratic.minimum < ~1.0e-18)
optimization_check("golden.method", quadratic.method, :golden_section)
optimization_check("golden.metadata",
                   quadratic.evaluations == quadratic.iterations + 2)

# residual_tol belongs to the root-finding part of OptimizationCriteria. It
# must not accidentally become a generic value/objective tolerance for search.
root_only_residual = OptimizationCriteria.new(
  ~1.0e-8, ~0.0, ~1.0e100, 100)
residual_ignored_by_minimum = Optimization.golden_section(
  -> (x) (x - ~0.25) * (x - ~0.25), ~-1.0, ~1.0,
  root_only_residual)
optimization_check("golden.residual_tolerance_is_root_only",
                   residual_ignored_by_minimum.iterations > 0)
optimization_check("golden.residual_tolerance_still_converges",
                   residual_ignored_by_minimum.converged?)

boundary = Optimization.minimize_scalar(-> (x) x, ~-2.0, ~3.0)
optimization_check("golden.boundary",
                   optimization_close?(boundary.argmin, ~-2.0, ~1.0e-9))

flat = Optimization.minimize(-> (x) ~4.0, ~-1.0, ~1.0)
optimization_check("golden.flat_converges", flat.converged?)
optimization_check("golden.flat_value", flat.minimum, ~4.0)

limited_minimum = Optimization.golden_section(
  -> (x) x * x, ~-1.0, ~2.0, no_root_iterations)
optimization_check("golden.iteration_limit",
                   limited_minimum.status_code, :iteration_limit)
optimization_check("golden.iteration_limit_evaluations",
                   limited_minimum.evaluations, 2)

last_minimum_iteration = OptimizationCriteria.new(
  ~0.31, ~0.0, ~0.0, 1)
last_step_minimum = Optimization.golden_section(
  -> (x) (x - ~0.4) * (x - ~0.4),
  ~0.0, ~1.0, last_minimum_iteration)
optimization_check("golden.last_iteration_converges",
                   last_step_minimum.status_code, :converged)
optimization_check("golden.last_iteration_count",
                   last_step_minimum.iterations, 1)

non_finite_minimum = Optimization.golden_section(
  -> (x) Math.exp(~10000.0), ~0.0, ~1.0)
optimization_check("golden.non_finite",
                   non_finite_minimum.status_code, :non_finite_value)

precision_minimum = Optimization.golden_section(
  -> (x) x * x, large_lo, large_hi, precision_criteria)
optimization_check("golden.precision_limit",
                   precision_minimum.status_code, :precision_limit)

# Invalid API configuration is distinct from a numerical failure result.
bad_bounds_raised = false
begin
  Optimization.bisection(-> (x) x, ~1.0, ~1.0)
rescue error
  bad_bounds_raised = true
optimization_check("validation.bounds_raise", bad_bounds_raised)

bad_tolerance_raised = false
begin
  OptimizationCriteria.new(~-1.0, ~0.0, ~0.0, 10)
rescue error
  bad_tolerance_raised = true
optimization_check("validation.tolerance_raises", bad_tolerance_raised)

bad_limit_raised = false
begin
  OptimizationCriteria.new(~1.0e-12, ~0.0, ~0.0, ~3.5)
rescue error
  bad_limit_raised = true
optimization_check("validation.iteration_limit_raises", bad_limit_raised)

non_finite_bound_raised = false
begin
  Optimization.minimize(-> (x) x, ~0.0, Math.exp(~10000.0))
rescue error
  non_finite_bound_raised = true
optimization_check("validation.non_finite_bound_raises",
                   non_finite_bound_raised)

callback_raised = false
raising_callback = -> (x)
  raise "callback failure"
begin
  Optimization.bisection(raising_callback, ~0.0, ~1.0)
rescue error
  callback_raised = true
optimization_check("validation.callback_error_propagates", callback_raised)

# The historical bare-value root API delegates to the supported method, while
# callers can opt into the result object during migration.
legacy_root = Optim.root_bisection(
  -> (x) x * x - ~2.0, ~0.0, ~2.0)
optimization_check("legacy.root_bisection",
                   optimization_close?(legacy_root,
                                       ~1.4142135623730951))
legacy_result = Optim.root_bisection_result(
  -> (x) x - ~1.0, ~0.0, ~2.0)
optimization_check("legacy.result", legacy_result.converged?)

legacy_failure_raised = false
begin
  Optim.root_bisection(-> (x) x * x + ~1.0, ~-1.0, ~1.0)
rescue error
  legacy_failure_raised = true
optimization_check("legacy.failure_is_loud", legacy_failure_raised)

<< "optimization_spec: all checks passed"
