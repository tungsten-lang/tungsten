# Public numerical calculus types are directly discoverable without `use`.

-> autoload_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

direct = NumericalDerivativeResult.new(
  ~1.0, ~0.1, ~0.01, 4, 2, 1, :central,
  :converged, ~1.0, true)
autoload_check("numerical_derivative_result.class",
               direct.class_name == "NumericalDerivativeResult")
autoload_check("numerical_derivative_result.metadata",
               direct.converged? && direct.estimate_available?)

computed = Calculus.numerical_derivative(
  -> (x) x*x, ~2.0)
autoload_check("calculus.numerical_derivative",
               computed.converged? && Calculus.abs(computed.value - ~4.0) < ~1.0e-8)

integral = Calculus.integrate_gk15(
  -> (x) x*x, ~0.0, ~1.0)
integral_ok = integral.converged?
integral_ok = false if Calculus.abs(
  integral.value - ~0.3333333333333333) >= ~1.0e-10
autoload_check("calculus.integrate_gk15", integral_ok)
autoload_check("quadrature_result.reused",
               integral.class_name == "QuadratureResult")

<< "calculus_autoload_spec: all checks passed"
