# Additional scalar roots — safeguarded Brent-Dekker, Newton, and secant.

+ Optimization
  -> .ordered_pair(left, right)
    left <= right ? [left, right] : [right, left]

  -> .root_residual_met?(value, criteria)
    return true if value == ~0.0
    criteria.residual_tol > ~0.0 && value.abs <= criteria.residual_tol

  -> .root_step_met?(step, point, criteria)
    step.abs <= Optimization.x_tolerance(criteria, point)

  -> .root_bracket(value)
    return nil if value == nil
    if value.class_name != "Array" || value.size != 2
      raise "root safeguard bracket must be [lower, upper]"
    Optimization.finite_bounds(value[0], value[1])

  # Brent-Dekker interpolation with bisection safeguards. The bracket is
  # maintained at every accepted iteration; interpolation is discarded when
  # it is not safely inside the current bracket or is not shrinking fast enough.
  -> .brent(function, lower, upper, criteria = nil)
    settings = Optimization.criteria(criteria)
    bounds = Optimization.finite_bounds(lower, upper)
    a = bounds[0]
    b = bounds[1]
    fa = Optimization.evaluate(function, a)
    evaluations = 1
    if !Optimization.finite_value?(fa)
      return Optimization.result(
        :root, a, fa, a, b, 0, evaluations, :non_finite_value,
        "function returned a non-finite value at the lower bound", :brent)
    if Optimization.root_residual_met?(fa, settings)
      return Optimization.result(
        :root, a, fa, a, a, 0, evaluations, :converged,
        "lower bound met the root residual tolerance", :brent)
    fb = Optimization.evaluate(function, b)
    evaluations += 1
    if !Optimization.finite_value?(fb)
      return Optimization.result(
        :root, b, fb, a, b, 0, evaluations, :non_finite_value,
        "function returned a non-finite value at the upper bound", :brent)
    if Optimization.root_residual_met?(fb, settings)
      return Optimization.result(
        :root, b, fb, b, b, 0, evaluations, :converged,
        "upper bound met the root residual tolerance", :brent)
    if !Optimization.opposite_signs?(fa, fb)
      best = Optimization.best_root_point(a, b, fa, fb)
      return Optimization.result(
        :root, best[0], best[1], a, b, 0, evaluations,
        :invalid_bracket, "endpoint values must have opposite signs", :brent)
    if fa.abs < fb.abs
      temporary = a
      a = b
      b = temporary
      temporary = fa
      fa = fb
      fb = temporary
    c = a
    fc = fa
    d = c
    used_bisection = true
    iterations = 0
    while iterations < settings.max_iterations
      interval = Optimization.ordered_pair(a, b)
      half_width = Optimization.half_width(interval[0], interval[1])
      if half_width <= Optimization.x_tolerance(settings, b)
        return Optimization.result(
          :root, b, fb, interval[0], interval[1], iterations,
          evaluations, :converged,
          "Brent bracket met the x tolerance", :brent)

      s = nil
      distinct_values = fa != fc && fb != fc
      if distinct_values
        first = a * fb * fc / ((fa - fb) * (fa - fc))
        second = b * fa * fc / ((fb - fa) * (fb - fc))
        third = c * fa * fb / ((fc - fa) * (fc - fb))
        s = first + second + third
      elsif fa != fb
        s = b - fb * (b - a) / (fb - fa)
      else
        s = Optimization.midpoint(interval[0], interval[1])

      guarded_edge = ~0.75 * a + ~0.25 * b
      safe = Optimization.ordered_pair(guarded_edge, b)
      outside = s <= safe[0] || s >= safe[1]
      insufficient = false
      if used_bisection
        insufficient = (s - b).abs >= ~0.5 * (b - c).abs
        insufficient = true if ((b - c).abs <=
          Optimization.x_tolerance(settings, b))
      else
        insufficient = (s - b).abs >= ~0.5 * (c - d).abs
        insufficient = true if ((c - d).abs <=
          Optimization.x_tolerance(settings, b))
      if !Optimization.finite_value?(s) || outside || insufficient
        s = Optimization.midpoint(interval[0], interval[1])
        used_bisection = true
      else
        used_bisection = false
      if s == a || s == b
        return Optimization.result(
          :root, b, fb, interval[0], interval[1], iterations,
          evaluations, :precision_limit,
          "Brent search has no representable interior point", :brent)

      fs = Optimization.evaluate(function, s)
      evaluations += 1
      iterations += 1
      if !Optimization.finite_value?(fs)
        return Optimization.result(
          :root, s, fs, interval[0], interval[1], iterations,
          evaluations, :non_finite_value,
          "function returned a non-finite value inside the bracket", :brent)
      if Optimization.root_residual_met?(fs, settings)
        return Optimization.result(
          :root, s, fs, s, s, iterations, evaluations, :converged,
          "Brent iterate met the root residual tolerance", :brent)
      d = c
      c = b
      fc = fb
      if Optimization.opposite_signs?(fa, fs)
        b = s
        fb = fs
      else
        a = s
        fa = fs
      if fa.abs < fb.abs
        temporary = a
        a = b
        b = temporary
        temporary = fa
        fa = fb
        fb = temporary

    interval = Optimization.ordered_pair(a, b)
    Optimization.result(
      :root, b, fb, interval[0], interval[1], iterations, evaluations,
      :iteration_limit, "Brent search reached max_iterations", :brent)

  -> .brentq(function, lower, upper, criteria = nil)
    Optimization.brent(function, lower, upper, criteria)

  -> .newton(function, derivative, initial, criteria = nil, bracket = nil)
    settings = Optimization.criteria(criteria)
    safeguard = Optimization.root_bracket(bracket)
    evaluations = 0
    derivative_evaluations = 0
    lo = nil
    hi = nil
    f_lo = nil
    f_hi = nil
    if safeguard != nil
      lo = safeguard[0]
      hi = safeguard[1]
      f_lo = Optimization.evaluate(function, lo)
      evaluations += 1
      f_hi = Optimization.evaluate(function, hi)
      evaluations += 1
      finite = Optimization.finite_value?(f_lo)
      finite = finite && Optimization.finite_value?(f_hi)
      if !finite
        return Optimization.result(
          :root, lo, f_lo, lo, hi, 0, evaluations,
          :non_finite_value,
          "function returned a non-finite safeguard endpoint", :newton)
      if Optimization.root_residual_met?(f_lo, settings)
        return Optimization.result(
          :root, lo, f_lo, lo, lo, 0, evaluations, :converged,
          "safeguard lower bound met the residual tolerance", :newton)
      if Optimization.root_residual_met?(f_hi, settings)
        return Optimization.result(
          :root, hi, f_hi, hi, hi, 0, evaluations, :converged,
          "safeguard upper bound met the residual tolerance", :newton)
      if !Optimization.opposite_signs?(f_lo, f_hi)
        best = Optimization.best_root_point(lo, hi, f_lo, f_hi)
        return Optimization.result(
          :root, best[0], best[1], lo, hi, 0, evaluations,
          :invalid_bracket,
          "safeguard endpoint values must have opposite signs", :newton)
    x = initial + ~0.0
    if !Optimization.finite_value?(x)
      raise "Newton initial point must be finite"
    if safeguard != nil && (x <= lo || x >= hi)
      x = Optimization.midpoint(lo, hi)
    fx = Optimization.evaluate(function, x)
    evaluations += 1
    if !Optimization.finite_value?(fx)
      lower = safeguard == nil ? x : lo
      upper = safeguard == nil ? x : hi
      return Optimization.result(
        :root, x, fx, lower, upper, 0, evaluations,
        :non_finite_value,
        "function returned a non-finite initial value", :newton)
    iterations = 0
    while true
      if Optimization.root_residual_met?(fx, settings)
        return Optimization.result(
          :root, x, fx, x, x, iterations, evaluations, :converged,
          "Newton iterate met the root residual tolerance", :newton)
      if safeguard != nil
        if Optimization.opposite_signs?(f_lo, fx)
          hi = x
          f_hi = fx
        else
          lo = x
          f_lo = fx
        if (Optimization.half_width(lo, hi) <=
            Optimization.x_tolerance(settings, x))
          return Optimization.result(
            :root, x, fx, lo, hi, iterations, evaluations, :converged,
            "safeguarded Newton bracket met the x tolerance", :newton)
      break if iterations >= settings.max_iterations

      slope = nil
      if derivative == nil
        h = Optimization.representable_difference_step(x)
        if h == nil
          lower = safeguard == nil ? x : lo
          upper = safeguard == nil ? x : hi
          return Optimization.result(
            :root, x, fx, lower, upper, iterations, evaluations,
            :precision_limit,
            "finite-difference step is not representable", :newton)
        upper_value = Optimization.evaluate(function, x + h)
        lower_value = Optimization.evaluate(function, x - h)
        evaluations += 2
        slope = (upper_value - lower_value) / (~2.0 * h)
      else
        slope = derivative(x) + ~0.0
        derivative_evaluations += 1
      if !Optimization.finite_value?(slope)
        lower = safeguard == nil ? x : lo
        upper = safeguard == nil ? x : hi
        return Optimization.result(
          :root, x, fx, lower, upper, iterations, evaluations,
          :non_finite_value, "Newton derivative is non-finite", :newton)
      candidate = nil
      if slope == ~0.0
        if safeguard == nil
          return Optimization.result(
            :root, x, fx, x, x, iterations, evaluations,
            :zero_derivative, "Newton derivative is zero", :newton)
        candidate = Optimization.midpoint(lo, hi)
      else
        candidate = x - fx / slope
        if safeguard != nil
          if (!Optimization.finite_value?(candidate) ||
              candidate <= lo || candidate >= hi)
            candidate = Optimization.midpoint(lo, hi)
      if !Optimization.finite_value?(candidate)
        return Optimization.result(
          :root, x, fx, x, x, iterations, evaluations,
          :non_finite_value, "Newton step is non-finite", :newton)
      if candidate == x
        lower = safeguard == nil ? x : lo
        upper = safeguard == nil ? x : hi
        return Optimization.result(
          :root, x, fx, lower, upper, iterations, evaluations,
          :precision_limit, "Newton step cannot change the iterate", :newton)
      next_value = Optimization.evaluate(function, candidate)
      evaluations += 1
      iterations += 1
      if !Optimization.finite_value?(next_value)
        lower = safeguard == nil ? candidate : lo
        upper = safeguard == nil ? candidate : hi
        return Optimization.result(
          :root, candidate, next_value, lower, upper, iterations,
          evaluations, :non_finite_value,
          "function returned a non-finite Newton iterate", :newton)
      step = candidate - x
      x = candidate
      fx = next_value
      if Optimization.root_step_met?(step, x, settings)
        lower = safeguard == nil ? x : lo
        upper = safeguard == nil ? x : hi
        return Optimization.result(
          :root, x, fx, lower, upper, iterations, evaluations,
          :converged, "Newton step met the x tolerance", :newton)
    lower = safeguard == nil ? x : lo
    upper = safeguard == nil ? x : hi
    message = "Newton search reached max_iterations; derivative evaluations="
    message += derivative_evaluations.to_s
    Optimization.result(
      :root, x, fx, lower, upper, iterations, evaluations,
      :iteration_limit, message, :newton)

  -> .secant(function, first, second, criteria = nil, bracket = nil)
    settings = Optimization.criteria(criteria)
    safeguard = Optimization.root_bracket(bracket)
    x_previous = first + ~0.0
    x = second + ~0.0
    if (!Optimization.finite_value?(x_previous) ||
        !Optimization.finite_value?(x) || x_previous == x)
      raise "secant needs two distinct finite initial points"
    lo = nil
    hi = nil
    f_lo = nil
    f_hi = nil
    evaluations = 0
    if safeguard != nil
      lo = safeguard[0]
      hi = safeguard[1]
      f_lo = Optimization.evaluate(function, lo)
      f_hi = Optimization.evaluate(function, hi)
      evaluations += 2
      finite = Optimization.finite_value?(f_lo)
      finite = finite && Optimization.finite_value?(f_hi)
      if !finite
        return Optimization.result(
          :root, lo, f_lo, lo, hi, 0, evaluations,
          :non_finite_value,
          "function returned a non-finite safeguard endpoint", :secant)
      if Optimization.root_residual_met?(f_lo, settings)
        return Optimization.result(
          :root, lo, f_lo, lo, lo, 0, evaluations, :converged,
          "safeguard lower bound met the residual tolerance", :secant)
      if Optimization.root_residual_met?(f_hi, settings)
        return Optimization.result(
          :root, hi, f_hi, hi, hi, 0, evaluations, :converged,
          "safeguard upper bound met the residual tolerance", :secant)
      if !Optimization.opposite_signs?(f_lo, f_hi)
        best = Optimization.best_root_point(lo, hi, f_lo, f_hi)
        return Optimization.result(
          :root, best[0], best[1], lo, hi, 0, evaluations,
          :invalid_bracket,
          "safeguard endpoint values must have opposite signs", :secant)
      if x_previous <= lo || x_previous >= hi
        x_previous = lo
      if x <= lo || x >= hi || x == x_previous
        x = hi
    f_previous = Optimization.evaluate(function, x_previous)
    fx = Optimization.evaluate(function, x)
    evaluations += 2
    if (!Optimization.finite_value?(f_previous) ||
        !Optimization.finite_value?(fx))
      return Optimization.result(
        :root, x, fx, x_previous, x, 0, evaluations,
        :non_finite_value, "function returned a non-finite secant value",
        :secant)
    iterations = 0
    while true
      if Optimization.root_residual_met?(fx, settings)
        return Optimization.result(
          :root, x, fx, x, x, iterations, evaluations, :converged,
          "secant iterate met the root residual tolerance", :secant)
      break if iterations >= settings.max_iterations
      denominator = fx - f_previous
      candidate = nil
      if denominator == ~0.0
        if safeguard == nil
          return Optimization.result(
            :root, x, fx, x_previous, x, iterations, evaluations,
            :zero_secant_slope, "secant values are identical", :secant)
        candidate = Optimization.midpoint(lo, hi)
      else
        candidate = x - fx * (x - x_previous) / denominator
        if safeguard != nil
          if (!Optimization.finite_value?(candidate) ||
              candidate <= lo || candidate >= hi)
            candidate = Optimization.midpoint(lo, hi)
      if !Optimization.finite_value?(candidate)
        return Optimization.result(
          :root, x, fx, x_previous, x, iterations, evaluations,
          :non_finite_value, "secant step is non-finite", :secant)
      if candidate == x
        lower = safeguard == nil ? x_previous : lo
        upper = safeguard == nil ? x : hi
        ordered = Optimization.ordered_pair(lower, upper)
        return Optimization.result(
          :root, x, fx, ordered[0], ordered[1], iterations,
          evaluations, :precision_limit,
          "secant step cannot change the iterate", :secant)
      candidate_value = Optimization.evaluate(function, candidate)
      evaluations += 1
      iterations += 1
      if !Optimization.finite_value?(candidate_value)
        return Optimization.result(
          :root, candidate, candidate_value, candidate, candidate,
          iterations, evaluations, :non_finite_value,
          "function returned a non-finite secant iterate", :secant)
      if safeguard != nil
        if Optimization.opposite_signs?(f_lo, candidate_value)
          hi = candidate
          f_hi = candidate_value
        else
          lo = candidate
          f_lo = candidate_value
      step = candidate - x
      x_previous = x
      f_previous = fx
      x = candidate
      fx = candidate_value
      if Optimization.root_step_met?(step, x, settings)
        lower = safeguard == nil ? x_previous : lo
        upper = safeguard == nil ? x : hi
        ordered = Optimization.ordered_pair(lower, upper)
        return Optimization.result(
          :root, x, fx, ordered[0], ordered[1], iterations,
          evaluations, :converged,
          "secant step met the x tolerance", :secant)
    lower = safeguard == nil ? x_previous : lo
    upper = safeguard == nil ? x : hi
    ordered = Optimization.ordered_pair(lower, upper)
    Optimization.result(
      :root, x, fx, ordered[0], ordered[1], iterations, evaluations,
      :iteration_limit, "secant search reached max_iterations", :secant)
