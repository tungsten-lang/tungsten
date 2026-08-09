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
    state = @converged ? "converged" : "not converged"
    "QuadratureResult(" + @value.to_s + " ± " + @error_estimate.to_s + ", " + state + ")"

  -> inspect
    self.to_s


+ Calculus
  -> .simpson(a, b, fa, fm, fb)
    weighted = fa + Calculus.scale_value(fm, ~4.0) + fb
    Calculus.scale_value(weighted, (b - a) / ~6.0)

  # Internal return tuple:
  # [corrected value, error estimate, new evaluations, leaf intervals, ok]
  -> .adaptive_simpson(f, a, b, fa, fm, fb, whole, tolerance, depth)
    middle = (a + b) / ~2.0
    left_middle = (a + middle) / ~2.0
    right_middle = (middle + b) / ~2.0
    fl = f(left_middle)
    fr = f(right_middle)
    left = Calculus.simpson(a, middle, fa, fl, fm)
    right = Calculus.simpson(middle, b, fm, fr, fb)
    delta = left + right - whole
    error = Calculus.magnitude(delta) / ~15.0
    corrected = left + right + Calculus.scale_value(delta, ~1.0 / ~15.0)

    if error <= tolerance
      return [corrected, error, 2, 2, true]
    if depth <= 0
      return [corrected, error, 2, 2, false]

    left_result = Calculus.adaptive_simpson(
      f, a, middle, fa, fl, fm, left, tolerance / ~2.0, depth - 1)
    right_result = Calculus.adaptive_simpson(
      f, middle, b, fm, fr, fb, right, tolerance / ~2.0, depth - 1)
    [
      left_result[0] + right_result[0],
      left_result[1] + right_result[1],
      2 + left_result[2] + right_result[2],
      left_result[3] + right_result[3],
      left_result[4] && right_result[4]
    ]

  -> .integrate(f, lower, upper,
                abs_tol = ~1.0e-10, rel_tol = ~1.0e-10, max_depth = 20)
    if abs_tol <= ~0.0 || rel_tol < ~0.0
      raise "quadrature tolerances must be positive"
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

    middle = (a + b) / ~2.0
    fa = f(a)
    fm = f(middle)
    fb = f(b)
    whole = Calculus.simpson(a, b, fa, fm, fb)
    tolerance = abs_tol
    relative = rel_tol * Calculus.magnitude(whole)
    tolerance = relative if relative > tolerance
    result = Calculus.adaptive_simpson(
      f, a, b, fa, fm, fb, whole, tolerance, max_depth)
    QuadratureResult.new(
      Calculus.scale_value(result[0], sign),
      result[1],
      3 + result[2],
      result[3],
      result[4])

  -> .quad(f, lower, upper,
           abs_tol = ~1.0e-10, rel_tol = ~1.0e-10, max_depth = 20)
    Calculus.integrate(f, lower, upper, abs_tol, rel_tol, max_depth)
