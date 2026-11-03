# Deterministic Core Optimization roadmap: derivatives, safeguarded roots,
# dense nonlinear least squares, quasi-Newton methods, bounds, and the scoped
# quadratic-penalty constraint wrapper.
#
# Run in both engines:
#   bin/tungsten spec/core/optimization_advanced_spec.w
#   bin/tungsten run --interpret spec/core/optimization_advanced_spec.w

use optimization

-> advanced_check(name, got, want = true)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> advanced_close?(got, want, tolerance = ~1.0e-8)
  (got - want).abs <= tolerance

-> advanced_vector_close?(got, want, tolerance = ~1.0e-8)
  return false if got.size != want.size
  i = 0
  while i < got.size
    return false if !advanced_close?(got[i], want[i], tolerance)
    i += 1
  true

advanced_check("naming.least_squares_criteria",
               OptimizationLeastSquaresCriteria.new.class_name,
               "OptimizationLeastSquaresCriteria")
advanced_check("naming.multivariate_criteria",
               OptimizationMultivariateCriteria.new.class_name,
               "OptimizationMultivariateCriteria")

# --- finite differences and explicit automatic-differentiation adapters ----

derivative = Optimization.finite_difference_derivative(
  -> (x) Math.sin(x), ~0.4)
advanced_check("derivative.central",
               advanced_close?(derivative, Math.cos(~0.4), ~1.0e-8))

gradient = Optimization.finite_difference_gradient(
  -> (x) x[0] * x[0] + ~3.0 * x[1] * x[1], [~2.0, ~-1.0])
advanced_check("derivative.gradient",
               advanced_vector_close?(gradient, [~4.0, ~-6.0], ~1.0e-7))

jacobian = Optimization.finite_difference_jacobian(
  -> (x) [x[0] + x[1], x[0] * x[1]], [~2.0, ~3.0])
advanced_check("derivative.jacobian.row0",
               advanced_vector_close?(jacobian[0], [~1.0, ~1.0], ~1.0e-7))
advanced_check("derivative.jacobian.row1",
               advanced_vector_close?(jacobian[1], [~3.0, ~2.0], ~1.0e-7))

autodiff_residual = -> (x)
  [x[0] * x[0] + x[1], x[0] * x[1]]
autodiff_adapter = Optimization.autodiff_jacobian_adapter(autodiff_residual)
autodiff_jacobian = autodiff_adapter([~2.0, ~3.0])
advanced_check("derivative.autodiff_adapter.row0",
               advanced_vector_close?(autodiff_jacobian[0],
                                      [~4.0, ~1.0]))
advanced_check("derivative.autodiff_adapter.row1",
               advanced_vector_close?(autodiff_jacobian[1],
                                      [~3.0, ~2.0]))
autodiff_gradient_adapter = Optimization.autodiff_gradient_adapter(
  -> (x) x[0] * x[0] + x[1] * x[1])
advanced_check("derivative.autodiff_gradient_adapter",
               advanced_vector_close?(
                 autodiff_gradient_adapter([~2.0, ~-1.0]),
                 [~4.0, ~-2.0]))

# --- safeguarded scalar roots ---------------------------------------------

root_function = -> (x) x * x - ~2.0
root_criteria = OptimizationCriteria.new(
  ~1.0e-12, ~1.0e-12, ~1.0e-12, 100)
brent = Optimization.brent(root_function, ~0.0, ~2.0, root_criteria)
advanced_check("brent.converged", brent.converged?)
advanced_check("brent.root",
               advanced_close?(brent.root, ~1.4142135623730951, ~1.0e-10))
advanced_check("brent.method", brent.method, :brent)
advanced_check("brent.evaluations", brent.evaluations >= 3)

bad_brent = Optimization.brent(
  -> (x) x * x + ~1.0, ~-1.0, ~1.0)
advanced_check("brent.invalid_bracket",
               bad_brent.status_code, :invalid_bracket)
advanced_check("brent.alias",
               Optimization.brentq(root_function, ~0.0, ~2.0).converged?)
nonfinite_brent = Optimization.brent(
  -> (x) Math.exp(~10000.0), ~0.0, ~1.0)
advanced_check("brent.non_finite",
               nonfinite_brent.status_code, :non_finite_value)

newton = Optimization.newton(
  root_function, -> (x) ~2.0 * x, ~1.0, root_criteria)
advanced_check("newton.analytic", newton.converged?)
advanced_check("newton.root",
               advanced_close?(newton.root, ~1.4142135623730951, ~1.0e-10))

finite_newton = Optimization.newton(
  root_function, nil, ~1.0, root_criteria)
advanced_check("newton.finite_difference", finite_newton.converged?)

safeguarded_newton = Optimization.newton(
  -> (x) x * x * x - ~1.0, -> (x) ~0.0, ~0.25,
  root_criteria, [~0.0, ~2.0])
advanced_check("newton.zero_derivative_safeguard",
               safeguarded_newton.converged?)
advanced_check("newton.safeguard_root",
               advanced_close?(safeguarded_newton.root, ~1.0, ~1.0e-10))

zero_derivative = Optimization.newton(
  -> (x) x * x + ~1.0, -> (x) ~2.0 * x, ~0.0)
advanced_check("newton.zero_derivative_failure",
               zero_derivative.status_code, :zero_derivative)

secant = Optimization.secant(
  root_function, ~1.0, ~2.0, root_criteria)
advanced_check("secant.converged", secant.converged?)
advanced_check("secant.root",
               advanced_close?(secant.root, ~1.4142135623730951, ~1.0e-10))

flat_secant = Optimization.secant(
  -> (x) ~1.0, ~0.0, ~1.0)
advanced_check("secant.zero_slope",
               flat_secant.status_code, :zero_secant_slope)
endpoint_secant = Optimization.secant(
  -> (x) x - ~1.0, ~0.25, ~1.5, root_criteria, [~1.0, ~2.0])
advanced_check("secant.safeguard_endpoint", endpoint_secant.root, ~1.0)

zero_root_iterations = OptimizationCriteria.new(
  ~1.0e-12, ~1.0e-12, ~0.0, 0)
limited_newton = Optimization.newton(
  root_function, -> (x) ~2.0 * x, ~1.0, zero_root_iterations)
advanced_check("newton.iteration_limit",
               limited_newton.status_code, :iteration_limit)

# --- dense nonlinear least squares ----------------------------------------

linear_residual = -> (x)
  [x[0] + ~2.0 * x[1] - ~5.0,
   ~2.0 * x[0] - x[1],
   x[0] - x[1] + ~1.0]
linear_jacobian = -> (x)
  [[~1.0, ~2.0], [~2.0, ~-1.0], [~1.0, ~-1.0]]

gauss_newton = Optimization.gauss_newton(
  linear_residual, [~0.0, ~0.0], linear_jacobian)
advanced_check("gauss_newton.converged", gauss_newton.converged?)
advanced_check("gauss_newton.parameters",
               advanced_vector_close?(gauss_newton.parameters,
                                      [~1.0, ~2.0], ~1.0e-10))
advanced_check("gauss_newton.residual_norm",
               gauss_newton.residual_norm < ~1.0e-10)
advanced_check("gauss_newton.objective",
               advanced_close?(gauss_newton.objective,
                 ~0.5 * gauss_newton.residual_norm *
                 gauss_newton.residual_norm, ~1.0e-18))
advanced_check("gauss_newton.rank", gauss_newton.rank, 2)
advanced_check("gauss_newton.counts",
               gauss_newton.residual_evaluations >= 2 &&
               gauss_newton.jacobian_evaluations >= 2 &&
               gauss_newton.linear_solves >= 1)

rosenbrock_residual = -> (x)
  [~10.0 * (x[1] - x[0] * x[0]), ~1.0 - x[0]]
rosenbrock_jacobian = -> (x)
  [[~-20.0 * x[0], ~10.0], [~-1.0, ~0.0]]
lm_criteria = OptimizationLeastSquaresCriteria.new(
  ~1.0e-9, ~1.0e-9, ~1.0e-10, 250,
  ~1.0e-12, ~1.0e12, ~1.0e-3)
lm = Optimization.levenberg_marquardt(
  rosenbrock_residual, [~-1.2, ~1.0], rosenbrock_jacobian, lm_criteria)
advanced_check("lm.converged", lm.converged?)
advanced_check("lm.parameters",
               advanced_vector_close?(lm.parameters, [~1.0, ~1.0], ~1.0e-6))
advanced_check("lm.damping", lm.damping > ~0.0)
advanced_check("lm.accepted_steps", lm.accepted_steps > 0)
advanced_check("lm.rejected_steps", lm.rejected_steps > 0)
advanced_check("lm.diagnostics", lm.rank == 2 &&
               lm.condition_estimate != nil)

finite_lm = Optimization.least_squares(
  linear_residual, [~0.0, ~0.0])
advanced_check("lm.finite_difference_default", finite_lm.converged?)
advanced_check("lm.finite_difference_counts",
               finite_lm.residual_evaluations > finite_lm.jacobian_evaluations)
advanced_check("naming.least_squares_result", finite_lm.class_name,
               "OptimizationLeastSquaresResult")
legacy_lm_result = Optim.least_squares_result(
  linear_residual, [~0.0, ~0.0], linear_jacobian)
advanced_check("legacy.least_squares_result", legacy_lm_result.converged?)

rank_deficient = Optimization.gauss_newton(
  -> (x) [x[0] + x[1] - ~1.0,
           ~2.0 * x[0] + ~2.0 * x[1] - ~2.0],
  [~0.0, ~0.0],
  -> (x) [[~1.0, ~1.0], [~2.0, ~2.0]])
advanced_check("least_squares.rank_deficient",
               rank_deficient.status_code, :rank_deficient)
advanced_check("least_squares.rank_diagnostic", rank_deficient.rank, 1)
rank_deficient_lm = Optimization.levenberg_marquardt(
  -> (x) [x[0] + x[1] - ~1.0,
           ~2.0 * x[0] + ~2.0 * x[1] - ~2.0],
  [~0.0, ~0.0],
  -> (x) [[~1.0, ~1.0], [~2.0, ~2.0]])
advanced_check("least_squares.lm_rank_diagnostic",
               rank_deficient_lm.status_code, :rank_deficient)
singular_criteria = OptimizationLeastSquaresCriteria.new(
  ~1.0e-10, ~1.0e-10, ~1.0e-10, 10,
  ~0.1, ~1.0e12, ~1.0e-3)
singular_lm = Optimization.levenberg_marquardt(
  -> (x) [x[0] - ~1.0, ~1.0], [~0.0, ~0.0],
  -> (x) [[~1.0, ~0.0], [~0.0, ~0.0]], singular_criteria)
advanced_check("least_squares.singular_damped_system",
               singular_lm.status_code, :singular_system)
underdetermined = Optimization.gauss_newton(
  -> (x) [x[0] + x[1]], [~0.0, ~0.0])
advanced_check("least_squares.underdetermined",
               underdetermined.status_code, :underdetermined)

strict_condition = OptimizationLeastSquaresCriteria.new(
  ~1.0e-12, ~1.0e-12, ~1.0e-12, 10,
  ~1.0e-14, ~1.0e6, ~1.0e-3)
ill_conditioned = Optimization.gauss_newton(
  -> (x) [x[0] - ~1.0, ~1.0e-8 * (x[1] - ~1.0)],
  [~0.0, ~0.0],
  -> (x) [[~1.0, ~0.0], [~0.0, ~1.0e-8]],
  strict_condition)
advanced_check("least_squares.ill_conditioned",
               ill_conditioned.status_code, :ill_conditioned)

invalid_jacobian = Optimization.gauss_newton(
  linear_residual, [~0.0, ~0.0], -> (x) [[~1.0]])
advanced_check("least_squares.invalid_jacobian",
               invalid_jacobian.status_code, :invalid_jacobian)
invalid_residual = Optimization.levenberg_marquardt(
  -> (x) ["not numeric"], [~0.0])
advanced_check("least_squares.invalid_residual",
               invalid_residual.status_code, :invalid_residual)
raising_jacobian = -> (x)
  raise "Jacobian failed"
jacobian_failure = Optimization.gauss_newton(
  linear_residual, [~0.0, ~0.0], raising_jacobian)
advanced_check("least_squares.jacobian_callback_failure",
               jacobian_failure.status_code, :callback_error)

nonfinite_residual = Optimization.levenberg_marquardt(
  -> (x) [Math.exp(~10000.0)], [~0.0])
advanced_check("least_squares.non_finite",
               nonfinite_residual.status_code, :non_finite_value)
overflowing_qr = Optimization.gauss_newton(
  -> (x) [~1.0e200 * x[0] - ~1.0], [~0.0],
  -> (x) [[~1.0e200]])
advanced_check("least_squares.qr_overflow",
               overflowing_qr.status_code, :non_finite_value)

raising_residual = -> (x)
  raise "model failed"
callback_failure = Optimization.levenberg_marquardt(
  raising_residual, [~0.0])
advanced_check("least_squares.callback_failure",
               callback_failure.status_code, :callback_error)

zero_ls_iterations = OptimizationLeastSquaresCriteria.new(
  ~0.0, ~0.0, ~0.0, 0, ~1.0e-12, ~1.0e12, ~1.0e-3)
limited_ls = Optimization.gauss_newton(
  linear_residual, [~0.0, ~0.0], linear_jacobian,
  zero_ls_iterations)
advanced_check("least_squares.iteration_limit",
               limited_ls.status_code, :iteration_limit)

# --- BFGS, L-BFGS, projected bounds, and scoped constraints ---------------

quadratic_objective = -> (x)
  first_term = (x[0] - ~1.0) * (x[0] - ~1.0)
  first_term + ~2.0 * (x[1] + ~2.0) * (x[1] + ~2.0)
quadratic_gradient = -> (x)
  [~2.0 * (x[0] - ~1.0), ~4.0 * (x[1] + ~2.0)]
multivariate_criteria = OptimizationMultivariateCriteria.new(
  ~1.0e-8, ~1.0e-10, ~1.0e-12, 200, 30, ~1.0e-12, 7)

bfgs = Optimization.bfgs(
  quadratic_objective, [~5.0, ~5.0], quadratic_gradient,
  multivariate_criteria)
advanced_check("bfgs.converged", bfgs.converged?)
advanced_check("bfgs.parameters",
               advanced_vector_close?(bfgs.parameters, [~1.0, ~-2.0],
                                      ~1.0e-7))
advanced_check("bfgs.line_search", bfgs.line_search_evaluations > 0)
advanced_check("bfgs.counts", bfgs.accepted_steps == bfgs.iterations)
advanced_check("naming.multivariate_result", bfgs.class_name,
               "OptimizationMultivariateResult")

lbfgs = Optimization.lbfgs(
  quadratic_objective, [~5.0, ~5.0], nil, multivariate_criteria)
advanced_check("lbfgs.converged", lbfgs.converged?)
advanced_check("lbfgs.parameters",
               advanced_vector_close?(lbfgs.parameters, [~1.0, ~-2.0],
                                      ~1.0e-6))
advanced_check("lbfgs.finite_difference_counts",
               lbfgs.function_evaluations > lbfgs.gradient_evaluations)

bounds = OptimizationBounds.new([~0.0], [~2.0])
bounded = Optimization.bfgs(
  -> (x) (x[0] - ~3.0) * (x[0] - ~3.0), [~0.5],
  -> (x) [~2.0 * (x[0] - ~3.0)], multivariate_criteria, bounds)
advanced_check("bounds.converged", bounded.converged?)
advanced_check("bounds.projected_solution",
               advanced_close?(bounded.parameters[0], ~2.0, ~1.0e-10))
advanced_check("bounds.active", bounded.active_bounds, 1)
advanced_check("bounds.projected_gradient",
               bounded.projected_gradient_norm, ~0.0)

line_failure = Optimization.bfgs(
  -> (x) ~0.0, [~0.0], -> (x) [~1.0], multivariate_criteria)
advanced_check("bfgs.line_search_failure",
               line_failure.status_code, :line_search_failed)

raising_objective = -> (x)
  raise "objective failed"
objective_failure = Optimization.bfgs(
  raising_objective, [~0.0])
advanced_check("bfgs.callback_failure",
               objective_failure.status_code, :callback_error)
invalid_gradient = Optimization.bfgs(
  quadratic_objective, [~0.0, ~0.0], -> (x) [~1.0],
  multivariate_criteria)
advanced_check("bfgs.invalid_gradient",
               invalid_gradient.status_code, :invalid_gradient)
domain_objective = -> (x)
  raise "outside domain" if x[0] != ~0.0
  ~0.0
domain_failure = Optimization.bfgs(
  domain_objective, [~0.0], -> (x) [~1.0], multivariate_criteria)
advanced_check("bfgs.line_search_callback_failure",
               domain_failure.status_code, :callback_error)

equality = OptimizationConstraints.new(
  [-> (x) x[0] - ~1.0], [], ~1.0e-5, ~10.0, ~10.0, 8)
equality_result = Optimization.minimize_constrained(
  -> (x) (x[0] - ~2.0) * (x[0] - ~2.0),
  [~0.0], equality, multivariate_criteria)
advanced_check("constraints.equality.converged", equality_result.converged?)
advanced_check("constraints.equality.feasible",
               equality_result.constraint_violation <= ~1.0e-5)
advanced_check("constraints.equality.solution",
               advanced_close?(equality_result.parameters[0], ~1.0, ~1.0e-4))

inequality = OptimizationConstraints.new(
  [], [-> (x) x[0] - ~1.0], ~1.0e-5, ~10.0, ~10.0, 8)
inequality_result = Optimization.minimize_constrained(
  -> (x) (x[0] - ~2.0) * (x[0] - ~2.0),
  [~0.0], inequality, multivariate_criteria, nil, :lbfgs)
advanced_check("constraints.inequality.converged",
               inequality_result.converged?)
advanced_check("constraints.inequality.feasible",
               inequality_result.parameters[0] <= ~1.00001)

infeasible = OptimizationConstraints.new(
  [], [-> (x) x[0], -> (x) ~1.0 - x[0]],
  ~1.0e-8, ~10.0, ~10.0, 3)
infeasible_result = Optimization.minimize_constrained(
  -> (x) x[0] * x[0], [~0.5], infeasible,
  multivariate_criteria)
advanced_check("constraints.infeasible",
               infeasible_result.status_code, :constraint_violation)
advanced_check("constraints.violation_visible",
               infeasible_result.constraint_violation > ~0.0)

<< "optimization_advanced_spec: all checks passed"
