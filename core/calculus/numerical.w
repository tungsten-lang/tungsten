# Status-aware scalar numerical differentiation for opaque f64 callbacks.
#
# This complements `Calculus.derivative`, which remains TaylorJet automatic
# differentiation.  Richardson differences are empirical consistency
# estimates, never interval certificates.  Callbacks are assumed pure,
# deterministic, and smooth near the query point.

+ NumericalDerivativeResult
  -> new(@value, @error_estimate, @step, @evaluations, @levels,
         @order, @scheme, @status, @cancellation_indicator,
         @estimate_available, attempts = nil)
    @attempts = attempts == nil ? @levels : attempts

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

  -> estimate_available?
    @estimate_available

  -> converged?
    @status == :converged

  -> algorithm
    :richardson_extrapolation

  -> error_model
    :successive_extrapolation_consistency

  -> certified?
    false

  -> to_a
    [@value, @error_estimate]

  -> to_s
    if !@estimate_available
      return "NumericalDerivativeResult(no estimate, " + @status.to_s + ")"
    text = "NumericalDerivativeResult(" + @value.to_s + " ± "
    text += @error_estimate.to_s + ", " + @status.to_s + ")"
    text

  -> inspect
    self.to_s


+ Calculus
  -> .numerical_abscissae_failure(points)
    i = 0
    while i < points.size
      if !Calculus.finite_f64?(points[i])
        return :nonfinite_abscissa
      j = 0
      while j < i
        return :step_unrepresentable if points[i] == points[j]
        j += 1
      i += 1
    :ok

  -> .numerical_cancellation(scale, numerator)
    limit = ~1.0e308
    denominator = Calculus.abs(numerator)
    return limit if denominator == ~0.0 && scale != ~0.0
    return ~1.0 if denominator == ~0.0
    ratio = scale / denominator
    return limit if !Calculus.finite_f64?(ratio) || ratio > limit
    ratio

  -> .numerical_indicator_scale(values, weights)
    limit = ~1.0e308
    total = ~0.0
    i = 0
    while i < values.size
      magnitude = Calculus.abs(values[i])
      weight = weights[i]
      return limit if magnitude >= limit / weight
      term = weight * magnitude
      return limit if total >= limit - term
      total += term
      i += 1
    total

  -> .numerical_smaller_step(h, contraction)
    next_h = h / contraction
    return nil if !Calculus.finite_f64?(next_h)
    return nil if next_h <= ~0.0 || next_h >= h
    next_h

  # Internal tuple:
  # [value, evaluations, failure, cancellation indicator]
  -> .numerical_stencil(f, x, h, order, scheme)
    value = ~0.0
    evaluations = 0
    indicator = ~1.0
    valid = true

    if scheme == :central
      xp = x + h
      xm = x - h
      points = order == 1 ? [xp, xm] : [xp, x, xm]
      failure = Calculus.numerical_abscissae_failure(points)
      return [nil, 0, failure, nil] if failure != :ok

      fp = f(xp)
      fm = f(xm)
      evaluations = 2
      valid = Calculus.finite_f64?(fp)
      valid = false if !Calculus.finite_f64?(fm)
      if order == 1
        if valid
          numerator = fp - fm
          scale = Calculus.numerical_indicator_scale(
            [fp, fm], [~1.0, ~1.0])
          value = (numerator / ~2.0) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0
      else
        f0 = f(x)
        evaluations = 3
        valid = false if !Calculus.finite_f64?(f0)
        if valid
          numerator = (fp - f0) + (fm - f0)
          scale = Calculus.numerical_indicator_scale(
            [fp, f0, fm], [~1.0, ~2.0, ~1.0])
          value = (numerator / h) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0
    elsif scheme == :forward
      x1 = x + h
      x2 = x + ~2.0 * h
      points = [x, x1, x2]
      x3 = x + ~3.0 * h
      points.push(x3) if order == 2
      failure = Calculus.numerical_abscissae_failure(points)
      return [nil, 0, failure, nil] if failure != :ok

      f0 = f(x)
      f1 = f(x1)
      f2 = f(x2)
      evaluations = 3
      valid = Calculus.finite_f64?(f0)
      valid = false if !Calculus.finite_f64?(f1)
      valid = false if !Calculus.finite_f64?(f2)
      if order == 1
        if valid
          numerator = ~4.0 * (f1 - f0) - (f2 - f0)
          scale = Calculus.numerical_indicator_scale(
            [f0, f1, f2], [~3.0, ~4.0, ~1.0])
          value = (numerator / ~2.0) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0
      else
        f3 = f(x3)
        evaluations = 4
        valid = false if !Calculus.finite_f64?(f3)
        if valid
          d1 = f1 - f0
          d2 = f2 - f1
          d3 = f3 - f2
          second_difference = d2 - d1
          third_difference = (d3 - d2) - (d2 - d1)
          numerator = second_difference - third_difference
          scale = Calculus.numerical_indicator_scale(
            [f0, f1, f2, f3], [~2.0, ~5.0, ~4.0, ~1.0])
          value = (numerator / h) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0
    else
      x1 = x - h
      x2 = x - ~2.0 * h
      points = [x, x1, x2]
      x3 = x - ~3.0 * h
      points.push(x3) if order == 2
      failure = Calculus.numerical_abscissae_failure(points)
      return [nil, 0, failure, nil] if failure != :ok

      f0 = f(x)
      f1 = f(x1)
      f2 = f(x2)
      evaluations = 3
      valid = Calculus.finite_f64?(f0)
      valid = false if !Calculus.finite_f64?(f1)
      valid = false if !Calculus.finite_f64?(f2)
      if order == 1
        if valid
          numerator = ~4.0 * (f0 - f1) - (f0 - f2)
          scale = Calculus.numerical_indicator_scale(
            [f0, f1, f2], [~3.0, ~4.0, ~1.0])
          value = (numerator / ~2.0) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0
      else
        f3 = f(x3)
        evaluations = 4
        valid = false if !Calculus.finite_f64?(f3)
        if valid
          d1 = f1 - f0
          d2 = f2 - f1
          d3 = f3 - f2
          second_difference = d2 - d1
          third_difference = (d3 - d2) - (d2 - d1)
          numerator = second_difference - third_difference
          scale = Calculus.numerical_indicator_scale(
            [f0, f1, f2, f3], [~2.0, ~5.0, ~4.0, ~1.0])
          value = (numerator / h) / h
          indicator = Calculus.numerical_cancellation(scale, numerator)
        else
          numerator = ~0.0
          scale = ~0.0

    return [nil, evaluations, :nonfinite_sample, nil] if !valid
    arithmetic_valid = Calculus.finite_f64?(numerator)
    arithmetic_valid = false if !Calculus.finite_f64?(scale)
    arithmetic_valid = false if !Calculus.finite_f64?(value)
    arithmetic_valid = false if !Calculus.finite_f64?(indicator)
    if !arithmetic_valid
      return [nil, evaluations, :nonfinite_arithmetic, nil]
    [value, evaluations, :ok, indicator]

  -> .numerical_derivative(f, x, order = 1, scheme = :central,
                           initial_step = nil,
                           abs_tol = ~1.0e-10, rel_tol = ~1.0e-8,
                           max_levels = 10, contraction = ~1.4)
    if order != 1 && order != 2
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

    h = initial_step
    if h == nil
      scale = Calculus.abs(x)
      scale = ~1.0 if scale < ~1.0
      h = ~0.1 * scale
    if !Calculus.finite_f64?(h) || h <= ~0.0
      raise "numerical derivative initial_step must be positive finite f64"

    table = []
    evaluations = 0
    best_value = nil
    best_error = nil
    best_step = nil
    best_indicator = nil
    selected_indicator = ~1.0
    previous_level_value = nil
    previous_level_error = nil
    previous_level_stable = false
    non_improving_streak = 0
    status = :working
    attempts = 0
    coarse_shrinks = 0

    while table.size < max_levels && status == :working
      sample = Calculus.numerical_stencil(f, x, h, order, scheme)
      attempts += 1
      evaluations += sample[1]
      failure = sample[2]
      if failure != :ok
        # A coarse stencil can cross a callback domain or overflow even though
        # a smaller one is usable. Keep this recovery bounded independently
        # of the valid Richardson-row budget.
        shrink_coarse = failure == :nonfinite_abscissa
        shrink_coarse = true if failure == :nonfinite_sample
        shrink_coarse = true if failure == :nonfinite_arithmetic
        shrink_coarse = false if table.size != 0
        shrink_coarse = false if coarse_shrinks >= max_levels
        if shrink_coarse
          next_h = Calculus.numerical_smaller_step(h, contraction)
          if next_h == nil
            status = :step_unrepresentable
          else
            h = next_h
            coarse_shrinks += 1
        else
          status = failure
      else
        indicator = sample[3]
        selected_indicator = indicator if indicator > selected_indicator
        row = [sample[0]]
        table.push(row)
        row_index = table.size - 1

        if row_index == 0
          next_h = Calculus.numerical_smaller_step(h, contraction)
          if next_h == nil
            status = :step_unrepresentable
          else
            h = next_h
        else
          level_value = sample[0]
          level_error = nil
          factor = contraction * contraction
          j = 1
          while j <= row_index && status == :working
            current = table[row_index][j - 1]
            previous = table[row_index - 1][j - 1]
            denominator = factor - ~1.0
            difference = current - previous
            arithmetic_valid = Calculus.finite_f64?(denominator)
            arithmetic_valid = false if denominator <= ~0.0
            arithmetic_valid = false if !Calculus.finite_f64?(difference)
            extrapolated = ~0.0
            candidate_error = ~0.0
            if arithmetic_valid
              correction = difference / denominator
              extrapolated = current + correction
              err_current = Calculus.abs(extrapolated - current)
              err_previous = Calculus.abs(extrapolated - previous)
              candidate_error = err_current
              candidate_error = err_previous if err_previous > candidate_error
              arithmetic_valid = false if !Calculus.finite_f64?(correction)
              arithmetic_valid = false if !Calculus.finite_f64?(extrapolated)
              arithmetic_valid = false if !Calculus.finite_f64?(candidate_error)
            if !arithmetic_valid
              status = :nonfinite_arithmetic
            else
              table[row_index].push(extrapolated)
              if level_error == nil || candidate_error < level_error
                level_error = candidate_error
                level_value = extrapolated
              if best_error == nil || candidate_error < best_error
                best_value = extrapolated
                best_error = candidate_error
                best_step = h
                best_indicator = selected_indicator
              if scheme == :central
                factor *= contraction * contraction
              else
                factor *= contraction
            j += 1

          if status == :working
            target = abs_tol
            relative_target = rel_tol * Calculus.abs(level_value)
            target = relative_target if relative_target > target
            if !Calculus.finite_f64?(target)
              status = :nonfinite_arithmetic
            else
              level_stable = level_error != nil && level_error <= target
              if previous_level_stable && level_stable
                continuity_error = Calculus.abs(
                  level_value - previous_level_value)
                if !Calculus.finite_f64?(continuity_error)
                  status = :nonfinite_arithmetic
                elsif continuity_error <= target
                  evidence_error = level_error
                  evidence_error = continuity_error if continuity_error > evidence_error
                  best_value = level_value
                  best_error = evidence_error
                  best_step = h
                  best_indicator = selected_indicator
                  status = :converged

              if previous_level_error != nil && level_error != nil
                threshold = ~0.99 * previous_level_error
                if level_error >= threshold
                  non_improving_streak += 1
                else
                  non_improving_streak = 0
              previous_level_value = level_value
              previous_level_error = level_error
              previous_level_stable = level_stable
            if status == :working
              next_h = Calculus.numerical_smaller_step(h, contraction)
              if next_h == nil
                status = :step_unrepresentable
              else
                h = next_h
    if status == :working
      if non_improving_streak >= 3
        status = :roundoff_or_noise_limited
      else
        status = :max_levels

    available = best_error != nil
    value_out = available ? best_value : nil
    error_out = available ? best_error : nil
    step_out = available ? best_step : nil
    indicator_out = available ? best_indicator : nil
    NumericalDerivativeResult.new(
      value_out, error_out, step_out, evaluations, table.size,
      order, scheme, status, indicator_out, available, attempts)
