# Scalar f64 differences with empirical truncation and resolution diagnostics.
# Callbacks must be pure and deterministic; the center sample is cached.

+ NumericalDerivativeResult
  -> new(@value, @error_estimate, @step, @evaluations, @levels,
         @order, @scheme, @status, @cancellation_indicator,
         @estimate_available, attempts = nil, resolution_floor = nil)
    @attempts = attempts == nil ? @levels : attempts
    @resolution_floor = resolution_floor
    if !Calculus.integer?(@evaluations) || @evaluations < 0 || !Calculus.integer?(@levels) || @levels < 0
      raise "numerical derivative counts must be nonnegative integers"
    if !Calculus.integer?(@attempts) || @attempts < @levels
      raise "numerical derivative attempts must cover all valid levels"
    if @estimate_available
      if !Calculus.finite_f64?(@value) || !Calculus.finite_f64?(@error_estimate)
        raise "numerical derivative estimate must be finite"
      if @error_estimate < ~0.0 || !Calculus.finite_f64?(@step) || @step <= ~0.0
        raise "numerical derivative estimate has invalid error or step"
    elsif @status == :converged || @value != nil || @error_estimate != nil || @step != nil || @cancellation_indicator != nil
      raise "numerical derivative result has inconsistent estimate availability"

  -> derivative
    @value
  -> value
    @value
  -> error_estimate
    @error_estimate
  -> step
    @step
  -> evaluations
    @evaluations
  -> levels
    @levels
  -> attempts
    @attempts
  -> order
    @order
  -> scheme
    @scheme
  -> status
    @status
  -> cancellation_indicator
    @cancellation_indicator
  -> resolution_floor
    @resolution_floor
  -> estimate_available?
    @estimate_available
  -> converged?
    @status == :converged
  -> algorithm
    :richardson_extrapolation
  -> error_model
    :extrapolation_with_resolution_floor
  -> certified?
    false
  -> to_a
    [@value, @error_estimate]
  -> to_s
    if !@estimate_available
      return "NumericalDerivativeResult(no estimate, " + @status.to_s + ")"
    "NumericalDerivativeResult(" + @value.to_s + " ± " + @error_estimate.to_s + ", " + @status.to_s + ")"
  -> inspect
    self.to_s

+ Calculus
  -> .numerical_abscissae_failure(points)
    i = 0
    while i < points.size
      return :nonfinite_abscissa if !Calculus.finite_f64?(points[i])
      j = 0
      while j < i
        return :step_unrepresentable if points[i] == points[j]
        j += 1
      i += 1
    :ok

  -> .numerical_smaller_step(h, contraction)
    next_h = h / contraction
    return nil if !Calculus.finite_f64?(next_h)
    return nil if next_h <= ~0.0 || next_h >= h
    next_h

  # [value, evaluations, status, cancellation, resolution floor]. The floor
  # models coordinate rounding plus 16 binary64 roundoffs per weighted sample;
  # it is deliberately conservative, not a bound on an arbitrary callback.
  -> .numerical_stencil(f, x, h, order, scheme, center_cache = nil)
    offsets = scheme == :central ? [~1.0, ~-1.0] : [~1.0, ~2.0]
    offsets.push(~3.0) if scheme != :central && order == 2
    direction = scheme == :backward ? ~-1.0 : ~1.0
    points = [x]
    defect = ~0.0
    i = 0
    while i < offsets.size
      multiplier = (direction * offsets[i]) ## f64
      step64 = h ## f64
      point64 = x ## f64
      coordinate = fma(multiplier, step64, point64)
      points.push(coordinate)
      i += 1
    failure = Calculus.numerical_abscissae_failure(points)
    return [nil, 0, failure, nil, nil] if failure != :ok
    i = 0
    while i < offsets.size
      ratio = ((points[i + 1] - x) / h) / (direction*offsets[i])
      deviation = Calculus.bounded_error(Calculus.abs(ratio - ~1.0))
      defect = deviation if deviation > defect
      i += 1

    values = []
    evaluations = 0
    needs_center = order == 2 || scheme != :central
    if needs_center
      if center_cache != nil && center_cache.size > 0
        f0 = center_cache[0]
      else
        f0 = f(x)
        evaluations += 1
        center_cache.push(f0) if center_cache != nil
      return [nil, evaluations, :unsupported_sample_type, nil, nil] if f0.class_name != "Float"
      return [nil, evaluations, :nonfinite_sample, nil, nil] if !Calculus.finite_f64?(f0)
      values.push(f0)
    i = 1
    while i < points.size
      value = f(points[i])
      evaluations += 1
      return [nil, evaluations, :unsupported_sample_type, nil, nil] if value.class_name != "Float"
      return [nil, evaluations, :nonfinite_sample, nil, nil] if !Calculus.finite_f64?(value)
      values.push(value)
      i += 1

    if scheme == :central
      if order == 1
        numerator = values[0] - values[1]
        weights = [~1.0, ~1.0]
      else
        numerator = (values[1] - values[0]) + (values[2] - values[0])
        weights = [~2.0, ~1.0, ~1.0]
    elsif order == 1
      numerator = direction * (~4.0*(values[1] - values[0]) - (values[2] - values[0]))
      weights = [~3.0, ~4.0, ~1.0]
    else
      d1 = values[1] - values[0]
      d2 = values[2] - values[1]
      d3 = values[3] - values[2]
      numerator = (d2 - d1) - ((d3 - d2) - (d2 - d1))
      weights = [~2.0, ~5.0, ~4.0, ~1.0]
    value = order == 1 ? (numerator / ~2.0) / h : (numerator / h) / h
    if !Calculus.finite_f64?(numerator) || !Calculus.finite_f64?(value)
      return [nil, evaluations, :nonfinite_arithmetic, nil, nil]

    maximum = ~0.0
    values.each ->
      magnitude = Calculus.abs(item)
      maximum = magnitude if magnitude > maximum
    normalized = ~0.0
    if maximum != ~0.0
      i = 0
      while i < values.size
        normalized += weights[i] * (Calculus.abs(values[i]) / maximum)
        i += 1
    indicator = ~1.0
    if maximum != ~0.0
      indicator = numerator == ~0.0 ? ~1.0e308 : Calculus.bounded_error((maximum / Calculus.abs(numerator))*normalized)
      indicator = ~1.0e308 if indicator > ~1.0e308
    # Form the small uncertainty factor first, so large offsets do not
    # overflow before division by h. Include gradual-underflow uncertainty.
    uncertainty = defect + ~3.552713678800501e-15
    floor = Calculus.bounded_error(uncertainty * maximum)
    floor = Calculus.bounded_error(floor * normalized + ~4.9406564584124654e-324)
    floor = Calculus.bounded_error((floor / ~2.0) / h) if order == 1
    floor = Calculus.bounded_error(Calculus.bounded_error(floor / h) / h) if order == 2
    [value, evaluations, :ok, indicator, floor]

  # Shared validation also covers empty numerical gradients/Jacobians.
  -> .numerical_initial_step(x, order, scheme, initial_step,
                             abs_tol, rel_tol, max_levels,
                             contraction, max_coarse_shrinks)
    if !Calculus.integer?(order) || (order != 1 && order != 2)
      raise "numerical derivative supports orders 1 and 2"
    if scheme != :central && scheme != :forward && scheme != :backward
      raise "numerical derivative scheme must be central, forward, or backward"
    if !Calculus.finite_f64?(x)
      raise "numerical derivative point must be finite f64"
    if !Calculus.finite_f64?(abs_tol) || abs_tol <= ~0.0
      raise "numerical derivative absolute tolerance must be positive finite f64"
    if !Calculus.finite_f64?(rel_tol) || rel_tol < ~0.0
      raise "numerical derivative relative tolerance must be nonnegative finite f64"
    if !Calculus.finite_f64?(contraction) || contraction < ~1.1
      raise "numerical derivative contraction must be finite f64 at least 1.1"
    if !Calculus.integer?(max_levels) || max_levels < 2
      raise "numerical derivative max_levels must be an integer of at least two"
    if !Calculus.integer?(max_coarse_shrinks) || max_coarse_shrinks < 0
      raise "numerical derivative max_coarse_shrinks must be nonnegative"
    h = initial_step
    if h == nil
      scale = Calculus.abs(x)
      scale = ~1.0 if scale < ~1.0
      h = ~0.1 * scale
    if !Calculus.finite_f64?(h) || h <= ~0.0
      raise "numerical derivative initial_step must be positive finite f64"
    h

  -> .numerical_derivative(f, x, order = 1, scheme = :central,
                           initial_step = nil,
                           abs_tol = ~1.0e-10, rel_tol = ~1.0e-8,
                           max_levels = 10, contraction = ~1.4,
                           max_coarse_shrinks = 64)
    h = Calculus.numerical_initial_step(x, order, scheme, initial_step,
      abs_tol, rel_tol, max_levels, contraction, max_coarse_shrinks)

    previous_row = []
    previous_floors = []
    center_cache = []
    levels = 0
    evaluations = 0
    attempts = 0
    coarse_shrinks = 0
    best_value = nil
    best_error = nil
    best_floor = nil
    best_step = nil
    best_indicator = nil
    selected_indicator = ~1.0
    previous_level_value = nil
    previous_level_error = nil
    previous_level_stable = false
    non_improving_streak = 0
    resolution_limited = false
    status = :working
    while levels < max_levels && status == :working
      sample = Calculus.numerical_stencil(f, x, h, order, scheme, center_cache)
      attempts += 1
      evaluations += sample[1]
      failure = sample[2]
      if failure != :ok
        recoverable = failure == :nonfinite_abscissa || failure == :nonfinite_sample || failure == :nonfinite_arithmetic
        # A nonfinite cached center cannot recover through changing h.
        recoverable = false if center_cache.size > 0 && !Calculus.finite_f64?(center_cache[0])
        if recoverable && levels == 0 && coarse_shrinks < max_coarse_shrinks
          next_h = Calculus.numerical_smaller_step(h, contraction)
          if next_h == nil
            status = :step_unrepresentable
          else
            h = next_h
            coarse_shrinks += 1
        else
          status = failure
      else
        levels += 1
        selected_indicator = sample[3] if sample[3] > selected_indicator
        row = [sample[0]]
        floors = [sample[4]]
        level_value = sample[0]
        level_error = nil
        level_floor = sample[4]
        factor = contraction * contraction
        j = 1
        while j < levels && status == :working
          current = row[j - 1]
          previous = previous_row[j - 1]
          denominator = factor - ~1.0
          difference = current - previous
          if !Calculus.finite_f64?(denominator) || !Calculus.finite_f64?(difference)
            status = :nonfinite_arithmetic
          else
            extrapolated = current + difference / denominator
            if !Calculus.finite_f64?(extrapolated)
              status = :nonfinite_arithmetic
            else
              floor = Calculus.bounded_error(
                floors[j - 1] + (floors[j - 1] / denominator) + (previous_floors[j - 1] / denominator))
              floor = Calculus.bounded_error(floor + ~4.440892098500626e-16*Calculus.abs(extrapolated))
              err1 = Calculus.bounded_error(Calculus.abs(extrapolated - current))
              err2 = Calculus.bounded_error(Calculus.abs(extrapolated - previous))
              error = err1 > err2 ? err1 : err2
              error = floor if floor > error
              row.push(extrapolated)
              floors.push(floor)
              if level_error == nil || error < level_error
                level_value = extrapolated
                level_error = error
                level_floor = floor
              factor *= scheme == :central ? contraction*contraction : contraction
          j += 1

        if level_error != nil
          if best_error == nil || level_error < best_error
            best_value = level_value
            best_error = level_error
            best_floor = level_floor
            best_step = h
            best_indicator = selected_indicator
          if status == :working
            stable = Calculus.within_tolerance?(level_error, Calculus.abs(level_value), abs_tol, rel_tol)
            resolution_limited = level_floor >= ~0.99*level_error && !Calculus.within_tolerance?(level_floor, Calculus.abs(level_value), abs_tol, rel_tol)
            if previous_level_stable && stable
              continuity = Calculus.bounded_error(Calculus.abs(level_value - previous_level_value))
              if Calculus.within_tolerance?(continuity, Calculus.abs(level_value), abs_tol, rel_tol)
                best_value = level_value
                best_error = continuity > level_error ? continuity : level_error
                best_floor = level_floor
                best_step = h
                best_indicator = selected_indicator
                status = :converged
            if previous_level_error != nil
              if level_error >= ~0.99*previous_level_error
                non_improving_streak += 1
              else
                non_improving_streak = 0
            previous_level_value = level_value
            previous_level_error = level_error
            previous_level_stable = stable
        previous_row = row
        previous_floors = floors
        if status == :working && levels < max_levels
          next_h = Calculus.numerical_smaller_step(h, contraction)
          if next_h == nil
            status = :step_unrepresentable
          else
            h = next_h

    if status == :working
      status = resolution_limited || non_improving_streak >= 3 ? :roundoff_or_noise_limited : :max_levels
    available = best_error != nil
    if available && status != :converged && previous_level_value != nil
      disagreement = Calculus.bounded_error(Calculus.abs(best_value - previous_level_value))
      best_error = disagreement if disagreement > best_error
      best_error = previous_level_error if previous_level_error > best_error
    NumericalDerivativeResult.new(
      best_value, best_error, best_step, evaluations, levels, order, scheme,
      status, best_indicator, available, attempts, best_floor)
