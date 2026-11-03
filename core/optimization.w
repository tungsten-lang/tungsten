# Optimization — deterministic numerical root finding and minimization.
#
# The bounded scalar layer remains the compatibility foundation:
#
#   Optimization.bisection(f, lower, upper, criteria)
#   Optimization.golden_section(f, lower, upper, criteria)
#
# Additional factored layers provide finite differences and explicit Calculus
# adapters, safeguarded Brent/Newton/secant roots, small dense nonlinear least
# squares, BFGS/L-BFGS with Armijo line search and projected box bounds, a
# gradient-norm safeguarded globalized L-BFGS variant, and a deliberately
# limited quadratic-penalty constrained wrapper.
#
# Inputs and callback values are coerced to Float, so the numerical contract is
# finite IEEE-754 binary64 arithmetic. Bisection assumes a continuous function
# with opposite endpoint signs. Golden-section search assumes a unimodal
# objective on the closed interval. Neither result is a proof certificate.
#
# The public support types intentionally retain their Optimization prefix.
# Their status codes, scalar bracket, estimate/value aliases, and stopping
# criteria are optimization contracts, not a generic numerical-solver model.
# In particular, integration needs error estimates and subdivision depth, ODE
# solvers need trajectories and step-control state, and fitting needs parameter
# and diagnostic data. A shared abstraction should wait for concrete common
# semantics instead of occupying broad global names such as Result or Status.

use core/math
use core/calculus
use core/optimization/derivatives
use core/optimization/dense_qr
use core/optimization/root_methods
use core/optimization/least_squares
use core/optimization/multivariate
use core/optimization/globalized_lbfgs

+ OptimizationStatus
  -> new(@code, @message)

  ro :code, :message

  -> converged?
    @code == :converged

  -> success?
    converged?

  -> to_s
    @code.to_s + ": " + @message

  -> inspect
    to_s


+ OptimizationCriteria
  -> new(abs_tol = ~1.0e-12, rel_tol = ~1.0e-12,
         residual_tol = ~0.0, max_iterations = 100)
    @abs_tol = abs_tol + ~0.0
    @rel_tol = rel_tol + ~0.0
    @residual_tol = residual_tol + ~0.0
    @max_iterations = max_iterations

    finite_tolerances = Optimization.finite_value?(@abs_tol)
    relative_finite = Optimization.finite_value?(@rel_tol)
    finite_tolerances = finite_tolerances && relative_finite
    residual_finite = Optimization.finite_value?(@residual_tol)
    finite_tolerances = finite_tolerances && residual_finite
    if !finite_tolerances
      raise "optimization tolerances must be finite"
    negative_x_tolerance = @abs_tol < ~0.0 || @rel_tol < ~0.0
    zero_x_tolerance = @abs_tol == ~0.0 && @rel_tol == ~0.0
    if negative_x_tolerance || zero_x_tolerance
      raise "optimization needs a nonnegative absolute or relative tolerance"
    if @residual_tol < ~0.0
      raise "optimization residual tolerance must be nonnegative"
    name = @max_iterations.class_name
    integer = name == "Integer" || name == "Int" || name == "BigInt"
    if !integer || @max_iterations < 0
      raise "optimization max_iterations must be a nonnegative integer"

  ro :abs_tol, :rel_tol

  # Used by root finding only. Zero means that only an exact zero may stop
  # before the interval-width condition is met.
  ro :residual_tol

  ro :max_iterations


+ OptimizationResult
  -> new(@kind, @estimate, @value, @lower_bound, @upper_bound,
         @iterations, @evaluations, @status, @method)

  ro :kind, :estimate

  -> x
    @estimate

  -> root
    @estimate

  -> argmin
    @estimate

  ro :value

  -> residual
    @value

  -> objective
    @value

  -> minimum
    @value

  ro :lower_bound, :upper_bound

  -> interval
    [@lower_bound, @upper_bound]

  -> interval_width
    @upper_bound - @lower_bound

  ro :iterations, :evaluations, :status

  -> status_code
    @status.code

  -> message
    @status.message

  ro :method

  -> converged?
    @status.converged?

  -> success?
    converged?

  # Width-based stopping and floating callback evaluations are numerical
  # evidence, not interval arithmetic or a mathematical certificate.
  -> certified?
    false

  -> to_s
    text = "OptimizationResult(" + @kind.to_s + ", x=" + @estimate.to_s
    text + ", value=" + @value.to_s + ", " + @status.to_s + ")"

  -> inspect
    to_s


+ Optimization
  # Float#nan? and #infinite? are the portable classification primitives in
  # both engines; Float#finite? is not available in every compiler stage.
  -> .finite_value?(value)
    !value.nan? && !value.infinite?

  -> .criteria(value)
    return OptimizationCriteria.new if value == nil
    if value.class_name != "OptimizationCriteria"
      raise "optimization criteria must be an OptimizationCriteria"
    value

  -> .finite_bounds(lower, upper)
    left = lower + ~0.0
    right = upper + ~0.0
    finite = Optimization.finite_value?(left)
    finite = finite && Optimization.finite_value?(right)
    if !finite
      raise "optimization bounds must be finite"
    if left >= right
      raise "optimization bounds need lower < upper"
    [left, right]

  -> .evaluate(function, point)
    function(point) + ~0.0

  # Overflow-safe for finite endpoints, including intervals spanning nearly
  # the full binary64 range.
  -> .midpoint(lower, upper)
    ~0.5 * lower + ~0.5 * upper

  -> .half_width(lower, upper)
    ~0.5 * upper - ~0.5 * lower

  -> .x_tolerance(criteria, point)
    criteria.abs_tol + criteria.rel_tol * point.abs

  -> .opposite_signs?(left, right)
    left_negative = left < ~0.0 && right > ~0.0
    left_negative || (left > ~0.0 && right < ~0.0)

  -> .status(code, message)
    OptimizationStatus.new(code, message)

  -> .result(kind, estimate, value, lower, upper, iterations,
             evaluations, code, message, method)
    OptimizationResult.new(
      kind, estimate, value, lower, upper, iterations, evaluations,
      Optimization.status(code, message), method)

  -> .best_root_point(lower, upper, f_lower, f_upper)
    if f_lower.abs <= f_upper.abs
      [lower, f_lower]
    else
      [upper, f_upper]

  -> .best_minimum_point(left, right, f_left, f_right)
    if f_left <= f_right
      [left, f_left]
    else
      [right, f_right]

  -> .root(function, lower, upper, criteria = nil)
    Optimization.bisection(function, lower, upper, criteria)

  -> .bisection(function, lower, upper, criteria = nil)
    settings = Optimization.criteria(criteria)
    bounds = Optimization.finite_bounds(lower, upper)
    lo = bounds[0]
    hi = bounds[1]
    evaluations = 0

    f_lo = Optimization.evaluate(function, lo)
    evaluations += 1
    if !Optimization.finite_value?(f_lo)
      return Optimization.result(
        :root, lo, f_lo, lo, hi, 0, evaluations, :non_finite_value,
        "function returned a non-finite value at the lower bound",
        :bisection)
    if f_lo == ~0.0
      return Optimization.result(
        :root, lo, f_lo, lo, lo, 0, evaluations, :converged,
        "lower bound is an exact root", :bisection)

    f_hi = Optimization.evaluate(function, hi)
    evaluations += 1
    if !Optimization.finite_value?(f_hi)
      return Optimization.result(
        :root, hi, f_hi, lo, hi, 0, evaluations, :non_finite_value,
        "function returned a non-finite value at the upper bound",
        :bisection)
    if f_hi == ~0.0
      return Optimization.result(
        :root, hi, f_hi, hi, hi, 0, evaluations, :converged,
        "upper bound is an exact root", :bisection)

    if !Optimization.opposite_signs?(f_lo, f_hi)
      best = Optimization.best_root_point(lo, hi, f_lo, f_hi)
      return Optimization.result(
        :root, best[0], best[1], lo, hi, 0, evaluations,
        :invalid_bracket,
        "endpoint values must have opposite signs", :bisection)

    iterations = 0
    while true
      middle = Optimization.midpoint(lo, hi)
      half_width = Optimization.half_width(lo, hi)

      if half_width <= Optimization.x_tolerance(settings, middle)
        f_middle = Optimization.evaluate(function, middle)
        evaluations += 1
        if !Optimization.finite_value?(f_middle)
          return Optimization.result(
            :root, middle, f_middle, lo, hi, iterations, evaluations,
            :non_finite_value,
            "function returned a non-finite value at the estimate",
            :bisection)
        return Optimization.result(
          :root, middle, f_middle, lo, hi, iterations, evaluations,
          :converged, "root bracket met the x tolerance", :bisection)
      if iterations >= settings.max_iterations
        break
      if middle == lo || middle == hi
        best = Optimization.best_root_point(lo, hi, f_lo, f_hi)
        return Optimization.result(
          :root, best[0], best[1], lo, hi, iterations, evaluations,
          :precision_limit,
          "binary64 has no representable interior point", :bisection)
      f_middle = Optimization.evaluate(function, middle)
      evaluations += 1
      iterations += 1
      if !Optimization.finite_value?(f_middle)
        return Optimization.result(
          :root, middle, f_middle, lo, hi, iterations, evaluations,
          :non_finite_value,
          "function returned a non-finite value inside the bracket",
          :bisection)
      if f_middle == ~0.0
        return Optimization.result(
          :root, middle, f_middle, middle, middle, iterations,
          evaluations, :converged,
          "bisection found an exact root", :bisection)
      residual_met = settings.residual_tol > ~0.0
      residual_met = residual_met && f_middle.abs <= settings.residual_tol
      if residual_met
        return Optimization.result(
          :root, middle, f_middle, lo, hi, iterations,
          evaluations, :converged,
          "function residual met the requested tolerance", :bisection)
      if Optimization.opposite_signs?(f_lo, f_middle)
        hi = middle
        f_hi = f_middle
      else
        lo = middle
        f_lo = f_middle

    best = Optimization.best_root_point(lo, hi, f_lo, f_hi)
    Optimization.result(
      :root, best[0], best[1], lo, hi, iterations, evaluations,
      :iteration_limit, "bisection reached max_iterations", :bisection)

  -> .minimize(function, lower, upper, criteria = nil)
    Optimization.golden_section(function, lower, upper, criteria)

  -> .minimize_scalar(function, lower, upper, criteria = nil)
    Optimization.golden_section(function, lower, upper, criteria)

  -> .golden_section(function, lower, upper, criteria = nil)
    settings = Optimization.criteria(criteria)
    bounds = Optimization.finite_bounds(lower, upper)
    lo = bounds[0]
    hi = bounds[1]
    evaluations = 0
    iterations = 0
    middle = Optimization.midpoint(lo, hi)

    initial_half_width = Optimization.half_width(lo, hi)
    initial_tolerance = Optimization.x_tolerance(settings, middle)
    if initial_half_width <= initial_tolerance
      f_middle = Optimization.evaluate(function, middle)
      evaluations += 1
      if !Optimization.finite_value?(f_middle)
        return Optimization.result(
          :minimum, middle, f_middle, lo, hi, 0, evaluations,
          :non_finite_value,
          "objective returned a non-finite value at the estimate",
          :golden_section)
      return Optimization.result(
        :minimum, middle, f_middle, lo, hi, 0, evaluations, :converged,
        "minimizer interval met the x tolerance", :golden_section)
    inner = ~0.3819660112501051
    outer = ~0.6180339887498949
    x_left = outer * lo + inner * hi
    x_right = inner * lo + outer * hi
    if x_left <= lo || x_right >= hi || x_left >= x_right
      f_middle = Optimization.evaluate(function, middle)
      evaluations += 1
      if !Optimization.finite_value?(f_middle)
        return Optimization.result(
          :minimum, middle, f_middle, lo, hi, 0, evaluations,
          :non_finite_value,
          "objective returned a non-finite value at the estimate",
          :golden_section)
      return Optimization.result(
        :minimum, middle, f_middle, lo, hi, 0, evaluations,
        :precision_limit,
        "binary64 cannot place two interior search points",
        :golden_section)
    f_left = Optimization.evaluate(function, x_left)
    evaluations += 1
    if !Optimization.finite_value?(f_left)
      return Optimization.result(
        :minimum, x_left, f_left, lo, hi, 0, evaluations,
        :non_finite_value,
        "objective returned a non-finite interior value", :golden_section)
    f_right = Optimization.evaluate(function, x_right)
    evaluations += 1
    if !Optimization.finite_value?(f_right)
      return Optimization.result(
        :minimum, x_right, f_right, lo, hi, 0, evaluations,
        :non_finite_value,
        "objective returned a non-finite interior value", :golden_section)
    while true
      middle = Optimization.midpoint(lo, hi)
      half_width = Optimization.half_width(lo, hi)
      tolerance = Optimization.x_tolerance(settings, middle)
      if half_width <= tolerance
        best = Optimization.best_minimum_point(
          x_left, x_right, f_left, f_right)
        return Optimization.result(
          :minimum, best[0], best[1], lo, hi, iterations, evaluations,
          :converged, "minimizer interval met the x tolerance",
          :golden_section)
      if iterations >= settings.max_iterations
        break
      if f_left <= f_right
        hi = x_right
        x_right = x_left
        f_right = f_left
        x_left = outer * lo + inner * hi
        iterations += 1
        if x_left <= lo || x_left >= x_right
          updated_middle = Optimization.midpoint(lo, hi)
          updated_width = Optimization.half_width(lo, hi)
          updated_tolerance = Optimization.x_tolerance(
            settings, updated_middle)
          if updated_width <= updated_tolerance
            return Optimization.result(
              :minimum, x_right, f_right, lo, hi, iterations, evaluations,
              :converged, "minimizer interval met the x tolerance",
              :golden_section)
          return Optimization.result(
            :minimum, x_right, f_right, lo, hi, iterations, evaluations,
            :precision_limit,
            "golden-section search stagnated at binary64 precision",
            :golden_section)
        f_left = Optimization.evaluate(function, x_left)
        evaluations += 1
        if !Optimization.finite_value?(f_left)
          return Optimization.result(
            :minimum, x_left, f_left, lo, hi, iterations, evaluations,
            :non_finite_value,
            "objective returned a non-finite interior value",
            :golden_section)
      else
        lo = x_left
        x_left = x_right
        f_left = f_right
        x_right = inner * lo + outer * hi
        iterations += 1
        if x_right <= x_left || x_right >= hi
          updated_middle = Optimization.midpoint(lo, hi)
          updated_width = Optimization.half_width(lo, hi)
          updated_tolerance = Optimization.x_tolerance(
            settings, updated_middle)
          if updated_width <= updated_tolerance
            return Optimization.result(
              :minimum, x_left, f_left, lo, hi, iterations, evaluations,
              :converged, "minimizer interval met the x tolerance",
              :golden_section)
          return Optimization.result(
            :minimum, x_left, f_left, lo, hi, iterations, evaluations,
            :precision_limit,
            "golden-section search stagnated at binary64 precision",
            :golden_section)
        f_right = Optimization.evaluate(function, x_right)
        evaluations += 1
        if !Optimization.finite_value?(f_right)
          return Optimization.result(
            :minimum, x_right, f_right, lo, hi, iterations, evaluations,
            :non_finite_value,
            "objective returned a non-finite interior value",
            :golden_section)

    best = Optimization.best_minimum_point(
      x_left, x_right, f_left, f_right)
    Optimization.result(
      :minimum, best[0], best[1], lo, hi, iterations, evaluations,
      :iteration_limit, "golden-section search reached max_iterations",
      :golden_section)
