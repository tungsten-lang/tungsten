# Adaptive Simpson quadrature for finite real intervals.
#
# The result exposes the corrected estimate, accumulated local error estimate,
# evaluation/interval counts, and whether every branch met tolerance before
# the explicit recursion limit.  A nonconverged result is never silently
# presented as certified.

+ QuadratureResult
  -> new(@value, @error_estimate, @evaluations, @intervals, @converged,
         status = nil, algorithm = :adaptive_simpson,
         error_model = :richardson_difference,
         absolute_integral_estimate = nil,
         worst_interval = nil, worst_error = nil,
         companion_value = nil, estimate_available = true,
         complete_coverage = true)
    @status = status
    if @status == nil
      @status = @converged ? :converged : :max_depth
    @converged = @status == :converged
    @algorithm = algorithm
    @error_model = error_model
    @absolute_integral_estimate = absolute_integral_estimate
    @worst_interval = nil
    if worst_interval != nil
      @worst_interval = [worst_interval[0], worst_interval[1]]
    @worst_error = worst_error
    @companion_value = companion_value
    @estimate_available = estimate_available
    @complete_coverage = complete_coverage
    if @estimate_available
      if !Calculus.finite_scalar?(@value) || !Calculus.finite_f64?(@error_estimate) || @error_estimate < ~0.0
        raise "quadrature estimate must have a finite value and nonnegative error"
    elsif @value != nil || @error_estimate != nil || @complete_coverage
      raise "quadrature result has inconsistent estimate availability"
    if @converged && (!@estimate_available || !@complete_coverage)
      raise "converged quadrature requires a complete estimate"

  -> value
    @value

  -> error_estimate
    @error_estimate

  -> evaluations
    @evaluations

  -> intervals
    @intervals

  -> converged?
    @converged

  -> status
    @status

  -> algorithm
    @algorithm

  -> error_model
    @error_model

  -> absolute_integral_estimate
    @absolute_integral_estimate

  -> worst_interval
    return nil if @worst_interval == nil
    [@worst_interval[0], @worst_interval[1]]

  -> worst_error
    @worst_error

  -> companion_value
    @companion_value

  -> estimate_available?
    @estimate_available

  -> complete_coverage?
    @complete_coverage

  -> certified?
    false

  -> to_a
    [@value, @error_estimate]

  -> to_s
    if !@estimate_available
      return "QuadratureResult(no estimate, " + @status.to_s + ")"
    state = @converged ? "converged" : "not converged: " + @status.to_s
    "QuadratureResult(" + @value.to_s + " ± " + @error_estimate.to_s + ", " + state + ")"

  -> inspect
    self.to_s


+ Calculus
  -> .simpson(a, b, fa, fm, fb)
    sixth_width = b / ~6.0 - a / ~6.0
    Calculus.scale_value(fa, sixth_width) + Calculus.scale_value(fm, ~4.0*sixth_width) + Calculus.scale_value(fb, sixth_width)

  # Internal return tuple:
  # [corrected value, error estimate, new evaluations, leaf intervals, status]
  -> .adaptive_simpson(f, a, b, fa, fm, fb, whole, tolerance, depth)
    middle = Calculus.midpoint(a, b)
    left_middle = Calculus.midpoint(a, middle)
    right_middle = Calculus.midpoint(middle, b)
    if left_middle == a || left_middle == middle || right_middle == middle || right_middle == b
      return [whole, ~1.7976931348623157e308, 0, 1, :precision_limit]
    fl = f(left_middle)
    if !Calculus.finite_scalar?(fl)
      return [whole, ~1.7976931348623157e308, 1, 1, :nonfinite_integrand]
    fr = f(right_middle)
    if !Calculus.finite_scalar?(fr)
      return [whole, ~1.7976931348623157e308, 2, 1, :nonfinite_integrand]
    left = Calculus.simpson(a, middle, fa, fl, fm)
    right = Calculus.simpson(middle, b, fm, fr, fb)
    if !Calculus.finite_scalar?(left) || !Calculus.finite_scalar?(right)
      return [whole, ~1.7976931348623157e308, 2, 1, :nonfinite_arithmetic]
    delta = left + right - whole
    error = Calculus.magnitude(delta) / ~15.0
    corrected = left + right + Calculus.scale_value(delta, ~1.0 / ~15.0)
    if !Calculus.finite_scalar?(corrected) || !Calculus.finite_f64?(error)
      return [whole, ~1.7976931348623157e308, 2, 1, :nonfinite_arithmetic]

    if error <= tolerance
      return [corrected, error, 2, 2, :converged]
    if depth <= 0
      return [corrected, error, 2, 2, :max_depth]

    left_result = Calculus.adaptive_simpson(
      f, a, middle, fa, fl, fm, left, tolerance / ~2.0, depth - 1)
    if left_result[4] != :converged && left_result[4] != :max_depth
      return [corrected, error, 2 + left_result[2], 2, left_result[4]]
    right_result = Calculus.adaptive_simpson(
      f, middle, b, fm, fr, fb, right, tolerance / ~2.0, depth - 1)
    if right_result[4] != :converged && right_result[4] != :max_depth
      return [corrected, error, 2 + left_result[2] + right_result[2], 2, right_result[4]]
    combined = left_result[0] + right_result[0]
    combined_error = left_result[1] + right_result[1]
    if !Calculus.finite_scalar?(combined) || !Calculus.finite_f64?(combined_error)
      return [corrected, error, 2 + left_result[2] + right_result[2], 2, :nonfinite_arithmetic]
    [
      combined,
      combined_error,
      2 + left_result[2] + right_result[2],
      left_result[3] + right_result[3],
      left_result[4] == :converged && right_result[4] == :converged ? :converged : :max_depth
    ]

  -> .integrate(f, lower, upper,
                abs_tol = ~1.0e-10, rel_tol = ~1.0e-10, max_depth = 20)
    if !Calculus.finite_f64?(lower) || !Calculus.finite_f64?(upper)
      raise "quadrature bounds must be finite f64"
    if !Calculus.finite_f64?(abs_tol) || !Calculus.finite_f64?(rel_tol) || abs_tol <= ~0.0 || rel_tol < ~0.0
      raise "quadrature tolerances must be finite and positive"
    if !Calculus.integer?(max_depth) || max_depth < 0
      raise "quadrature max_depth must be a nonnegative integer"
    if lower == upper
      return QuadratureResult.new(~0.0, ~0.0, 0, 0, true)

    sign = ~1.0
    a = lower
    b = upper
    if b < a
      temporary = a
      a = b
      b = temporary
      sign = ~-1.0

    middle = Calculus.midpoint(a, b)
    if middle == a || middle == b
      return Calculus.simpson_failure(:precision_limit, 0)
    fa = f(a)
    return Calculus.simpson_failure(:nonfinite_integrand, 1) if !Calculus.finite_scalar?(fa)
    fm = f(middle)
    return Calculus.simpson_failure(:nonfinite_integrand, 2) if !Calculus.finite_scalar?(fm)
    fb = f(b)
    return Calculus.simpson_failure(:nonfinite_integrand, 3) if !Calculus.finite_scalar?(fb)
    whole = Calculus.simpson(a, b, fa, fm, fb)
    return Calculus.simpson_failure(:nonfinite_arithmetic, 3) if !Calculus.finite_scalar?(whole)
    tolerance = abs_tol
    relative = Calculus.bounded_error(rel_tol * Calculus.magnitude(whole))
    tolerance = relative if relative > tolerance
    result = Calculus.adaptive_simpson(
      f, a, b, fa, fm, fb, whole, tolerance, max_depth)
    status = result[4]
    if status == :converged && !Calculus.within_tolerance?(result[1], Calculus.magnitude(result[0]), abs_tol, rel_tol)
      status = :tolerance_not_met
    QuadratureResult.new(
      Calculus.scale_value(result[0], sign),
      result[1],
      3 + result[2],
      result[3],
      status == :converged, status)

  -> .simpson_failure(status, evaluations)
    QuadratureResult.new(nil, nil, evaluations, 0, false, status,
      :adaptive_simpson, :richardson_difference, nil, nil, nil, nil, false, false)

  -> .quad(f, lower, upper,
           abs_tol = ~1.0e-10, rel_tol = ~1.0e-10, max_depth = 20)
    Calculus.integrate(f, lower, upper, abs_tol, rel_tol, max_depth)
