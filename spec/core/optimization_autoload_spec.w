# Optimization support types must remain independently autoloadable without an
# explicit `use optimization` in both interpreter and native builds.

-> optimization_autoload_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

optimization_autoload_check(
  "least_squares_criteria",
  OptimizationLeastSquaresCriteria.new.class_name,
  "OptimizationLeastSquaresCriteria")
optimization_autoload_check(
  "multivariate_criteria",
  OptimizationMultivariateCriteria.new.class_name,
  "OptimizationMultivariateCriteria")
optimization_autoload_check(
  "bounds",
  OptimizationBounds.new([~0.0], [~1.0]).class_name,
  "OptimizationBounds")
optimization_autoload_check(
  "constraints",
  OptimizationConstraints.new([-> (x) x[0]], []).class_name,
  "OptimizationConstraints")

autoload_result = Optimization.least_squares(
  -> (x) [x[0] - ~1.0], [~0.0])
optimization_autoload_check(
  "result", autoload_result.class_name,
  "OptimizationLeastSquaresResult")

<< "optimization_autoload_spec: all checks passed"
