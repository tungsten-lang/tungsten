# Globally adaptive Gauss-Kronrod 7/15 quadrature for finite f64 intervals.
#
# The local rule and error rescaling follow QUADPACK DQK15.  The embedded-rule
# error remains empirical: agreement can miss unresolved or adversarial
# integrands, and every result reports `certified? == false`.
# Source constants: https://www.netlib.org/quadpack/dqk15.f

+ Calculus
  -> .gk15_tolerance(value, abs_tol, rel_tol)
    target = abs_tol
    relative = rel_tol * Calculus.abs(value)
    target = relative if relative > target
    target

  -> .gk15_compensated_values(values)
    total = ~0.0
    correction = ~0.0
    i = 0
    while i < values.size
      value = values[i]
      return nil if !Calculus.finite_f64?(value)
      updated = total + value
      if Calculus.abs(total) >= Calculus.abs(value)
        correction += (total - updated) + value
      else
        correction += (value - updated) + total
      return nil if !Calculus.finite_f64?(updated)
      return nil if !Calculus.finite_f64?(correction)
      total = updated
      i += 1
    combined = total + correction
    return nil if !Calculus.finite_f64?(combined)
    combined

  -> .gk15_safe_term(scale, sample)
    term = scale * sample
    if scale != ~0.0 && sample != ~0.0
      return nil if Calculus.abs(term) < ~2.2250738585072014e-308
    term

  # Internal panel tuple:
  # [a, b, kronrod, gauss, error, resabs, resasc, status, evaluations]
  -> .gk15_panel(f, a, b)
    nodes = [
      ~0.9914553711208126,
      ~0.9491079123427585,
      ~0.8648644233597691,
      ~0.7415311855993945,
      ~0.5860872354676911,
      ~0.4058451513773972,
      ~0.2077849550078985
    ]
    kronrod_weights = [
      ~0.02293532201052922,
      ~0.06309209262997855,
      ~0.1047900103222502,
      ~0.1406532597155259,
      ~0.1690047266392679,
      ~0.1903505780647854,
      ~0.2044329400752989,
      ~0.2094821410847278
    ]
    gauss_weights = [
      ~0.1294849661688697,
      ~0.2797053914892767,
      ~0.3818300505051189,
      ~0.4179591836734694
    ]

    center = ~0.5 * a + ~0.5 * b
    half = ~0.5 * b - ~0.5 * a
    representable = Calculus.finite_f64?(center)
    representable = false if !Calculus.finite_f64?(half)
    representable = false if half <= ~0.0
    representable = false if center == a || center == b
    i = 0
    while i < nodes.size && representable
      offset = half * nodes[i]
      left = center - offset
      right = center + offset
      representable = false if !Calculus.finite_f64?(left)
      representable = false if !Calculus.finite_f64?(right)
      representable = false if left <= a || right >= b
      representable = false if left == center || right == center
      representable = false if left == right
      i += 1
    if !representable
      return [a, b, nil, nil, nil, nil, nil, :precision_limit, 0]

    # Scaling a sample by a subnormal mapped weight can quantize the Gauss and
    # Kronrod rules identically, hiding an error far above the requested
    # tolerance. A future normalized-sample kernel can recover this region;
    # the f64 rule must not claim convergence there today.
    smallest_mapped_weight = half * kronrod_weights[0]
    if smallest_mapped_weight < ~2.2250738585072014e-308
      return [a, b, nil, nil, nil, nil, nil, :precision_limit, 0]

    fc = f(center)
    if !Calculus.finite_f64?(fc)
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_integrand, 1]

    abs_half = Calculus.abs(half)
    kronrod_center = Calculus.gk15_safe_term(
      half * kronrod_weights[7], fc)
    gauss_center = Calculus.gk15_safe_term(
      half * gauss_weights[3], fc)
    mean_center = Calculus.gk15_safe_term(
      ~0.5 * kronrod_weights[7], fc)
    resabs_center = Calculus.gk15_safe_term(
      abs_half * kronrod_weights[7], Calculus.abs(fc))
    center_terms_valid = kronrod_center != nil && gauss_center != nil
    center_terms_valid = false if mean_center == nil || resabs_center == nil
    if !center_terms_valid
      return [a, b, nil, nil, nil, nil, nil, :precision_limit, 1]

    kronrod_terms = [kronrod_center]
    gauss_terms = [gauss_center]
    mean_terms = [mean_center]
    resabs_terms = [resabs_center]
    left_values = []
    right_values = []

    i = 0
    while i < nodes.size
      offset = half * nodes[i]
      fl = f(center - offset)
      fr = f(center + offset)
      samples_finite = Calculus.finite_f64?(fl)
      samples_finite = false if !Calculus.finite_f64?(fr)
      if !samples_finite
        count = 1 + 2 * (i + 1)
        return [a, b, nil, nil, nil, nil, nil,
                :nonfinite_integrand, count]

      left_values.push(fl)
      right_values.push(fr)
      kronrod_scale = half * kronrod_weights[i]
      mean_scale = ~0.5 * kronrod_weights[i]
      resabs_scale = abs_half * kronrod_weights[i]
      kronrod_left = Calculus.gk15_safe_term(kronrod_scale, fl)
      kronrod_right = Calculus.gk15_safe_term(kronrod_scale, fr)
      mean_left = Calculus.gk15_safe_term(mean_scale, fl)
      mean_right = Calculus.gk15_safe_term(mean_scale, fr)
      resabs_left = Calculus.gk15_safe_term(
        resabs_scale, Calculus.abs(fl))
      resabs_right = Calculus.gk15_safe_term(
        resabs_scale, Calculus.abs(fr))
      terms_valid = kronrod_left != nil && kronrod_right != nil
      terms_valid = false if mean_left == nil || mean_right == nil
      terms_valid = false if resabs_left == nil || resabs_right == nil
      if !terms_valid
        count = 1 + 2 * (i + 1)
        return [a, b, nil, nil, nil, nil, nil,
                :precision_limit, count]
      kronrod_terms.push(kronrod_left)
      kronrod_terms.push(kronrod_right)
      mean_terms.push(mean_left)
      mean_terms.push(mean_right)
      resabs_terms.push(resabs_left)
      resabs_terms.push(resabs_right)
      if i == 1
        gauss_scale = half * gauss_weights[0]
        gauss_left = Calculus.gk15_safe_term(gauss_scale, fl)
        gauss_right = Calculus.gk15_safe_term(gauss_scale, fr)
      elsif i == 3
        gauss_scale = half * gauss_weights[1]
        gauss_left = Calculus.gk15_safe_term(gauss_scale, fl)
        gauss_right = Calculus.gk15_safe_term(gauss_scale, fr)
      elsif i == 5
        gauss_scale = half * gauss_weights[2]
        gauss_left = Calculus.gk15_safe_term(gauss_scale, fl)
        gauss_right = Calculus.gk15_safe_term(gauss_scale, fr)
      else
        gauss_left = ~0.0
        gauss_right = ~0.0
      if i == 1 || i == 3 || i == 5
        if gauss_left == nil || gauss_right == nil
          count = 1 + 2 * (i + 1)
          return [a, b, nil, nil, nil, nil, nil,
                  :precision_limit, count]
        gauss_terms.push(gauss_left)
        gauss_terms.push(gauss_right)
      i += 1

    kronrod = Calculus.gk15_compensated_values(kronrod_terms)
    gauss = Calculus.gk15_compensated_values(gauss_terms)
    mean = Calculus.gk15_compensated_values(mean_terms)
    resabs = Calculus.gk15_compensated_values(resabs_terms)
    totals_valid = kronrod != nil && gauss != nil
    totals_valid = false if mean == nil || resabs == nil
    if !totals_valid
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_arithmetic, 15]

    resasc_center = Calculus.gk15_safe_term(
      abs_half * kronrod_weights[7], Calculus.abs(fc - mean))
    if resasc_center == nil
      return [a, b, nil, nil, nil, nil, nil,
              :precision_limit, 15]
    resasc_terms = [resasc_center]
    i = 0
    while i < nodes.size
      resasc_scale = abs_half * kronrod_weights[i]
      resasc_left = Calculus.gk15_safe_term(
        resasc_scale, Calculus.abs(left_values[i] - mean))
      resasc_right = Calculus.gk15_safe_term(
        resasc_scale, Calculus.abs(right_values[i] - mean))
      if resasc_left == nil || resasc_right == nil
        return [a, b, nil, nil, nil, nil, nil,
                :precision_limit, 15]
      resasc_terms.push(resasc_left)
      resasc_terms.push(resasc_right)
      i += 1
    resasc = Calculus.gk15_compensated_values(resasc_terms)
    if resasc == nil
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_arithmetic, 15]

    error = Calculus.abs(kronrod - gauss)
    if resasc != ~0.0 && error != ~0.0
      ratio = error / resasc
      if !Calculus.finite_f64?(ratio) || ratio >= ~0.005
        scaled = ~1.0
      else
        scaled = Math.pow(~200.0 * ratio, ~1.5)
      error = resasc * scaled
    roundoff_floor = ~1.1102230246251565e-14 * resabs
    error = roundoff_floor if roundoff_floor > error

    arithmetic_valid = Calculus.finite_f64?(kronrod)
    arithmetic_valid = false if !Calculus.finite_f64?(gauss)
    arithmetic_valid = false if !Calculus.finite_f64?(resabs)
    arithmetic_valid = false if !Calculus.finite_f64?(resasc)
    arithmetic_valid = false if !Calculus.finite_f64?(error)
    if !arithmetic_valid
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_arithmetic, 15]
    [a, b, kronrod, gauss, error, resabs, resasc, :ok, 15]

  -> .gk15_largest_error_index(panels)
    best = 0
    i = 1
    while i < panels.size
      best = i if panels[i][4] > panels[best][4]
      i += 1
    best

  -> .gk15_compensated_total(panels, field)
    total = ~0.0
    correction = ~0.0
    i = 0
    while i < panels.size
      value = panels[i][field]
      return nil if !Calculus.finite_f64?(value)
      updated = total + value
      if Calculus.abs(total) >= Calculus.abs(value)
        correction += (total - updated) + value
      else
        correction += (value - updated) + total
      return nil if !Calculus.finite_f64?(updated)
      return nil if !Calculus.finite_f64?(correction)
      total = updated
      i += 1
    combined = total + correction
    return nil if !Calculus.finite_f64?(combined)
    combined

  -> .gk15_result(sign, panels, value, companion, error, resabs,
                   evaluations, status, estimate_available,
                   complete_coverage)
    worst_interval = nil
    worst_error = nil
    if estimate_available && panels.size > 0
      worst_index = Calculus.gk15_largest_error_index(panels)
      worst_interval = [panels[worst_index][0], panels[worst_index][1]]
      worst_error = panels[worst_index][4]

    value_out = estimate_available ? sign * value : nil
    companion_out = estimate_available ? sign * companion : nil
    error_out = estimate_available ? error : nil
    resabs_out = estimate_available ? resabs : nil
    interval_count = estimate_available ? panels.size : 0
    QuadratureResult.new(
      value_out, error_out, evaluations, interval_count,
      status == :converged, status, :adaptive_gk15,
      :embedded_gauss_kronrod, resabs_out,
      worst_interval, worst_error, companion_out,
      estimate_available, complete_coverage)

  -> .integrate_gk15(f, lower, upper,
                      abs_tol = ~1.0e-10, rel_tol = ~1.0e-10,
                      max_intervals = 1024, max_evaluations = 30_705)
    if !Calculus.finite_f64?(lower)
      raise "Gauss-Kronrod lower bound must be finite f64"
    if !Calculus.finite_f64?(upper)
      raise "Gauss-Kronrod upper bound must be finite f64"
    if !Calculus.finite_f64?(abs_tol) || abs_tol <= ~0.0
      raise "Gauss-Kronrod absolute tolerance must be positive finite f64"
    if !Calculus.finite_f64?(rel_tol) || rel_tol < ~0.0
      raise "Gauss-Kronrod relative tolerance must be nonnegative finite f64"
    if !Calculus.integer?(max_intervals) || max_intervals < 1
      raise "Gauss-Kronrod max_intervals must be a positive integer"
    if !Calculus.integer?(max_evaluations) || max_evaluations < 15
      raise "Gauss-Kronrod max_evaluations must be at least fifteen"

    if lower == upper
      return QuadratureResult.new(
        ~0.0, ~0.0, 0, 0, true, :converged,
        :adaptive_gk15, :embedded_gauss_kronrod,
        ~0.0, nil, nil, ~0.0, true, true)

    sign = ~1.0
    a = lower
    b = upper
    if b < a
      temporary = a
      a = b
      b = temporary
      sign = ~-1.0

    first = Calculus.gk15_panel(f, a, b)
    evaluations = first[8]
    if first[7] != :ok
      return Calculus.gk15_result(
        sign, [], nil, nil, nil, nil, evaluations,
        first[7], false, false)

    panels = [first]
    value = first[2]
    companion = first[3]
    error = first[4]
    resabs = first[5]
    status = :working
    roundoff_streak = 0

    while status == :working
      target = Calculus.gk15_tolerance(value, abs_tol, rel_tol)
      if !Calculus.finite_f64?(target)
        status = :nonfinite_arithmetic
      elsif error <= target
        status = :converged
      elsif panels.size >= max_intervals
        status = :max_intervals
      elsif evaluations + 30 > max_evaluations
        status = :max_evaluations
      else
        index = Calculus.gk15_largest_error_index(panels)
        old = panels[index]
        middle = ~0.5 * old[0] + ~0.5 * old[1]
        if middle == old[0] || middle == old[1]
          status = :precision_limit
        else
          left = Calculus.gk15_panel(f, old[0], middle)
          right = Calculus.gk15_panel(f, middle, old[1])
          evaluations += left[8] + right[8]
          if left[7] != :ok
            status = left[7]
          elsif right[7] != :ok
            status = right[7]
          else
            candidate_panels = Calculus.copy_vector(panels)
            candidate_panels[index] = left
            candidate_panels.push(right)
            candidate_value = Calculus.gk15_compensated_total(
              candidate_panels, 2)
            candidate_companion = Calculus.gk15_compensated_total(
              candidate_panels, 3)
            candidate_error = Calculus.gk15_compensated_total(
              candidate_panels, 4)
            candidate_resabs = Calculus.gk15_compensated_total(
              candidate_panels, 5)
            totals_valid = candidate_value != nil
            totals_valid = false if candidate_companion == nil
            totals_valid = false if candidate_error == nil
            totals_valid = false if candidate_resabs == nil
            if !totals_valid
              status = :nonfinite_arithmetic
            else
              child_error = left[4] + right[4]
              child_value = left[2] + right[2]
              value_change = Calculus.abs(child_value - old[2])
              value_scale = Calculus.abs(old[2])
              value_scale = ~1.0 if value_scale < ~1.0
              value_floor = ~1.1102230246251565e-14 * value_scale
              stalled = child_error >= ~0.99 * old[4]
              stalled = false if value_change > value_floor
              if stalled
                roundoff_streak += 1
              else
                roundoff_streak = 0

              panels = candidate_panels
              value = candidate_value
              companion = candidate_companion
              error = candidate_error
              resabs = candidate_resabs
              candidate_target = Calculus.gk15_tolerance(
                value, abs_tol, rel_tol)
              if !Calculus.finite_f64?(candidate_target)
                status = :nonfinite_arithmetic
              elsif error <= candidate_target
                status = :converged
              elsif roundoff_streak >= 8
                status = :roundoff_limited

    Calculus.gk15_result(
      sign, panels, value, companion, error, resabs,
      evaluations, status, true, true)
