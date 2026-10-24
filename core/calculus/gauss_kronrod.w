# Globally adaptive Gauss-Kronrod 7/15 quadrature for finite f64 intervals.
#
# The local rule and error rescaling follow QUADPACK DQK15.  The embedded-rule
# error remains empirical: agreement can miss unresolved or adversarial
# integrands, and every result reports `certified? == false`.
# Source constants: https://www.netlib.org/quadpack/dqk15.f

+ Calculus
  -> .gk15_tolerance(value, abs_tol, rel_tol)
    target = abs_tol
    relative = Calculus.bounded_error(rel_tol * Calculus.abs(value))
    target = relative if relative > target
    target

  -> .gk15_compensated_values(values)
    vals = values ## Array
    n = vals.size
    total = ~0.0
    correction = ~0.0
    i = 0
    while i < n
      value = vals[i] ## f64
      return nil if value - value != ~0.0
      updated = total + value
      abs_total = total < ~0.0 ? ~0.0 - total : total
      abs_val = value < ~0.0 ? ~0.0 - value : value
      if abs_total >= abs_val
        correction += (total - updated) + value
      else
        correction += (value - updated) + total
      return nil if updated - updated != ~0.0
      return nil if correction - correction != ~0.0
      total = updated
      i += 1
    combined = total + correction
    return nil if combined - combined != ~0.0
    combined

  -> .gk15_safe_term(scale, sample)
    sc = scale ## f64
    sm = sample ## f64
    term = sc * sm
    if sc != ~0.0 && sm != ~0.0
      abs_term = term < ~0.0 ? ~0.0 - term : term
      return nil if abs_term < ~2.2250738585072014e-308
    term

  # Internal panel tuple:
  # [a, b, kronrod, gauss, error, resabs, resasc, status, evaluations]
  -> .gk15_rule
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
    [nodes, kronrod_weights, gauss_weights]

  -> .gk15_panel(f, a, b, rule = nil)
    rule = Calculus.gk15_rule if rule == nil
    rule_arr = rule ## Array
    nodes = rule_arr[0] ## Array
    kronrod_weights = rule_arr[1] ## Array
    gauss_weights = rule_arr[2] ## Array
    nodes_size = nodes.size

    af = a ## f64
    bf = b ## f64
    center = ~0.5 * af + ~0.5 * bf
    half = ~0.5 * bf - ~0.5 * af
    representable = center - center == ~0.0
    representable = false if half - half != ~0.0
    representable = false if half <= ~0.0
    representable = false if center == af || center == bf
    i = 0
    while i < nodes_size && representable
      nd = nodes[i] ## f64
      offset = half * nd
      left = center - offset
      right = center + offset
      representable = false if left - left != ~0.0
      representable = false if right - right != ~0.0
      representable = false if left <= af || right >= bf
      representable = false if left == center || right == center
      representable = false if left == right
      i += 1
    if !representable
      return [a, b, nil, nil, nil, nil, nil, :precision_limit, 0]

    # Scaling a sample by a subnormal mapped weight can quantize the Gauss and
    # Kronrod rules identically, hiding an error far above the requested
    # tolerance. A future normalized-sample kernel can recover this region;
    # the f64 rule must not claim convergence there today.
    kw0 = kronrod_weights[0] ## f64
    smallest_mapped_weight = half * kw0
    if smallest_mapped_weight < ~2.2250738585072014e-308
      return [a, b, nil, nil, nil, nil, nil, :precision_limit, 0]

    fc_raw = f(center)
    if type(fc_raw) != "Float"
      return [a, b, nil, nil, nil, nil, nil, :unsupported_sample_type, 1]
    fc = fc_raw ## f64
    if fc - fc != ~0.0
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_integrand, 1]

    abs_half = half < ~0.0 ? ~0.0 - half : half
    kw7 = kronrod_weights[7] ## f64
    gw3 = gauss_weights[3] ## f64
    abs_fc = fc < ~0.0 ? ~0.0 - fc : fc
    kronrod_center = Calculus.gk15_safe_term(
      half * kw7, fc)
    gauss_center = Calculus.gk15_safe_term(
      half * gw3, fc)
    mean_center = Calculus.gk15_safe_term(
      ~0.5 * kw7, fc)
    resabs_center = Calculus.gk15_safe_term(
      abs_half * kw7, abs_fc)
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
    while i < nodes_size
      nd = nodes[i] ## f64
      offset = half * nd
      fl_raw = f(center - offset)
      if type(fl_raw) != "Float"
        return [a, b, nil, nil, nil, nil, nil, :unsupported_sample_type, 2 + 2*i]
      fl = fl_raw ## f64
      if fl - fl != ~0.0
        return [a, b, nil, nil, nil, nil, nil, :nonfinite_integrand, 2 + 2*i]
      fr_raw = f(center + offset)
      if type(fr_raw) != "Float"
        return [a, b, nil, nil, nil, nil, nil, :unsupported_sample_type, 3 + 2*i]
      fr = fr_raw ## f64
      if fr - fr != ~0.0
        count = 1 + 2 * (i + 1)
        return [a, b, nil, nil, nil, nil, nil,
                :nonfinite_integrand, count]

      left_values.push(fl)
      right_values.push(fr)
      kwi = kronrod_weights[i] ## f64
      kronrod_scale = half * kwi
      mean_scale = ~0.5 * kwi
      resabs_scale = abs_half * kwi
      kronrod_left = Calculus.gk15_safe_term(kronrod_scale, fl)
      kronrod_right = Calculus.gk15_safe_term(kronrod_scale, fr)
      mean_left = Calculus.gk15_safe_term(mean_scale, fl)
      mean_right = Calculus.gk15_safe_term(mean_scale, fr)
      abs_fl = fl < ~0.0 ? ~0.0 - fl : fl
      abs_fr = fr < ~0.0 ? ~0.0 - fr : fr
      resabs_left = Calculus.gk15_safe_term(
        resabs_scale, abs_fl)
      resabs_right = Calculus.gk15_safe_term(
        resabs_scale, abs_fr)
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
        gw0 = gauss_weights[0] ## f64
        gauss_scale = half * gw0
        gauss_left = Calculus.gk15_safe_term(gauss_scale, fl)
        gauss_right = Calculus.gk15_safe_term(gauss_scale, fr)
      elsif i == 3
        gw1 = gauss_weights[1] ## f64
        gauss_scale = half * gw1
        gauss_left = Calculus.gk15_safe_term(gauss_scale, fl)
        gauss_right = Calculus.gk15_safe_term(gauss_scale, fr)
      elsif i == 5
        gw2 = gauss_weights[2] ## f64
        gauss_scale = half * gw2
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

    mean_f = mean ## f64
    resasc_center = Calculus.gk15_safe_term(
      abs_half * kw7, Calculus.abs(fc - mean_f))
    if resasc_center == nil
      return [a, b, nil, nil, nil, nil, nil,
              :precision_limit, 15]
    resasc_terms = [resasc_center]
    i = 0
    while i < nodes_size
      kwi = kronrod_weights[i] ## f64
      resasc_scale = abs_half * kwi
      lvi = left_values[i] ## f64
      rvi = right_values[i] ## f64
      resasc_left = Calculus.gk15_safe_term(
        resasc_scale, Calculus.abs(lvi - mean_f))
      resasc_right = Calculus.gk15_safe_term(
        resasc_scale, Calculus.abs(rvi - mean_f))
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

    kronrod_f = kronrod ## f64
    gauss_f = gauss ## f64
    resabs_f = resabs ## f64
    resasc_f = resasc ## f64
    error = Calculus.abs(kronrod_f - gauss_f)
    if resasc_f != ~0.0 && error != ~0.0
      ratio = error / resasc_f
      if ratio - ratio != ~0.0 || ratio >= ~0.005
        scaled = ~1.0
      else
        scaled = Math.pow(~200.0 * ratio, ~1.5)
      error = resasc_f * scaled
    roundoff_floor = ~1.1102230246251565e-14 * resabs_f
    error = roundoff_floor if roundoff_floor > error

    arithmetic_valid = kronrod_f - kronrod_f == ~0.0
    arithmetic_valid = false if gauss_f - gauss_f != ~0.0
    arithmetic_valid = false if resabs_f - resabs_f != ~0.0
    arithmetic_valid = false if resasc_f - resasc_f != ~0.0
    arithmetic_valid = false if error - error != ~0.0
    if !arithmetic_valid
      return [a, b, nil, nil, nil, nil, nil,
              :nonfinite_arithmetic, 15]
    [a, b, kronrod_f, gauss_f, error, resabs_f, resasc_f, :ok, 15]

  -> .gk15_largest_error_index(panels)
    p_arr = panels ## Array
    n = p_arr.size
    best = 0
    p_best = p_arr[0] ## Array
    best_err = p_best[4] ## f64
    i = 1
    while i < n
      pi = p_arr[i] ## Array
      ei = pi[4] ## f64
      if ei > best_err
        best = i
        best_err = ei
      i += 1
    best

  -> .gk15_compensated_total(panels, field)
    p_arr = panels ## Array
    n = p_arr.size
    total = ~0.0
    correction = ~0.0
    i = 0
    while i < n
      pi = p_arr[i] ## Array
      value = pi[field] ## f64
      return nil if value - value != ~0.0
      updated = total + value
      abs_total = total < ~0.0 ? ~0.0 - total : total
      abs_val = value < ~0.0 ? ~0.0 - value : value
      if abs_total >= abs_val
        correction += (total - updated) + value
      else
        correction += (value - updated) + total
      return nil if updated - updated != ~0.0
      return nil if correction - correction != ~0.0
      total = updated
      i += 1
    combined = total + correction
    return nil if combined - combined != ~0.0
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

  -> .gk15_accumulate(state, value)
    st = state ## Array
    total = st[0] ## f64
    val = value ## f64
    updated = total + val
    correction = st[1] ## f64
    abs_total = total < ~0.0 ? ~0.0 - total : total
    abs_val = val < ~0.0 ? ~0.0 - val : val
    if abs_total >= abs_val
      correction += (total - updated) + val
    else
      correction += (val - updated) + total
    st[0] = updated
    st[1] = correction
    updated - updated == ~0.0 && correction - correction == ~0.0

  -> .gk15_rebuild(panels)
    totals = []
    field = 2
    while field <= 5
      value = Calculus.gk15_compensated_total(panels, field)
      return nil if value == nil
      totals.push([value, ~0.0])
      field += 1
    totals

  -> .gk15_totals_values(totals)
    t_arr = totals ## Array
    out = []
    i = 0
    while i < 4
      ti = t_arr[i] ## Array
      t0 = ti[0] ## f64
      t1 = ti[1] ## f64
      value = t0 + t1
      return nil if value - value != ~0.0
      return nil if i >= 2 && value < ~0.0
      out.push(value)
      i += 1
    out

  # Stable priority: largest error, then lowest original active-array slot.
  # Left children retain the parent's slot, exactly matching the old scan.
  -> .gk15_precedes?(panels, a, b)
    p_arr = panels ## Array
    pa = p_arr[a] ## Array
    pb = p_arr[b] ## Array
    ea = pa[4] ## f64
    eb = pb[4] ## f64
    ea > eb || (ea == eb && a < b)

  -> .gk15_heap_push(heap, panels, index)
    hp = heap ## Array
    hp.push(index)
    child = hp.size - 1
    while child > 0
      parent = (child - 1) / 2
      return hp if !Calculus.gk15_precedes?(panels, hp[child], hp[parent])
      temporary = hp[parent]
      hp[parent] = hp[child]
      hp[child] = temporary
      child = parent
    hp

  -> .gk15_heap_down(heap, panels)
    hp = heap ## Array
    n = hp.size
    parent = 0
    while 2*parent + 1 < n
      child = 2*parent + 1
      if child + 1 < n && Calculus.gk15_precedes?(panels, hp[child + 1], hp[child])
        child += 1
      return hp if !Calculus.gk15_precedes?(panels, hp[child], hp[parent])
      temporary = hp[parent]
      hp[parent] = hp[child]
      hp[child] = temporary
      parent = child
    hp

  -> .integrate_gk15(f, lower, upper,
                      abs_tol = ~1.0e-10, rel_tol = ~1.0e-10,
                      max_intervals = 1024, max_evaluations = 30_705)
    Calculus.integrate_with_points(f, lower, upper, [],
      abs_tol, rel_tol, max_intervals, max_evaluations)

  # One global tolerance and work budget, including the initial partition.
  # Breakpoints are ascending even when the integration direction is reversed.
  -> .integrate_with_points(f, lower, upper, points,
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
    if points.class_name != "Array"
      raise "quadrature breakpoints must be an Array"
    sign = lower <= upper ? ~1.0 : ~-1.0
    a = lower <= upper ? lower : upper
    b = lower <= upper ? upper : lower
    boundaries = [a]
    previous = a
    points.each ->
      if !Calculus.finite_f64?(item) || item <= previous || item >= b
        raise "quadrature breakpoints must be finite, ascending, unique, and interior"
      boundaries.push(item)
      previous = item
    boundaries.push(b)
    if max_intervals < points.size + 1 || max_evaluations < 15*(points.size + 1)
      raise "quadrature budgets must cover the initial breakpoint partition"
    if a == b
      return QuadratureResult.new(~0.0, ~0.0, 0, 0, true, :converged,
        :adaptive_gk15, :embedded_gauss_kronrod, ~0.0, nil, nil, ~0.0, true, true)

    rule = Calculus.gk15_rule
    panels = []
    heap = []
    evaluations = 0
    i = 0
    while i + 1 < boundaries.size
      panel = Calculus.gk15_panel(f, boundaries[i], boundaries[i + 1], rule)
      evaluations += panel[8]
      if panel[7] != :ok
        return Calculus.gk15_result(sign, [], nil, nil, nil, nil,
          evaluations, panel[7], false, false)
      panels.push(panel)
      Calculus.gk15_heap_push(heap, panels, i)
      i += 1
    totals = Calculus.gk15_rebuild(panels)
    if totals == nil
      return Calculus.gk15_result(sign, [], nil, nil, nil, nil,
        evaluations, :nonfinite_arithmetic, false, false)
    values = Calculus.gk15_totals_values(totals)
    status = :working
    roundoff_streak = 0
    rebuild_at = 2*panels.size

    while status == :working
      if Calculus.within_tolerance?(values[2], Calculus.abs(values[0]), abs_tol, rel_tol)
        # Recheck the full active partition before accepting incremental sums.
        totals = Calculus.gk15_rebuild(panels)
        if totals == nil
          status = :nonfinite_arithmetic
        else
          values = Calculus.gk15_totals_values(totals)
          if Calculus.within_tolerance?(values[2], Calculus.abs(values[0]), abs_tol, rel_tol)
            status = :converged
      if status == :working
        if panels.size >= max_intervals
          status = :max_intervals
        elsif evaluations + 30 > max_evaluations
          status = :max_evaluations
        elsif roundoff_streak >= 8
          status = :roundoff_limited
        else
          index = heap[0]
          old = panels[index]
          middle = Calculus.midpoint(old[0], old[1])
          left = Calculus.gk15_panel(f, old[0], middle, rule)
          evaluations += left[8]
          if left[7] != :ok
            status = left[7]
          else
            right = Calculus.gk15_panel(f, middle, old[1], rule)
            evaluations += right[8]
            if right[7] != :ok
              status = right[7]
            else
              previous_values = values
              panels[index] = left
              panels.push(right)
              field = 0
              incremental_ok = true
              while field < 4
                incremental_ok = Calculus.gk15_accumulate(totals[field], ~0.0 - old[field + 2]) && incremental_ok
                incremental_ok = Calculus.gk15_accumulate(totals[field], left[field + 2]) && incremental_ok
                incremental_ok = Calculus.gk15_accumulate(totals[field], right[field + 2]) && incremental_ok
                field += 1
              values = Calculus.gk15_totals_values(totals)
              if !incremental_ok || values == nil || panels.size >= rebuild_at
                totals = Calculus.gk15_rebuild(panels)
                values = totals == nil ? nil : Calculus.gk15_totals_values(totals)
                rebuild_at = 2*panels.size
              if values == nil
                # Restore the last full partition; the heap is not changed yet.
                panels.pop
                panels[index] = old
                values = previous_values
                status = :nonfinite_arithmetic
              else
                Calculus.gk15_heap_down(heap, panels)
                Calculus.gk15_heap_push(heap, panels, panels.size - 1)
                child_error = left[4] + right[4]
                child_value = left[2] + right[2]
                value_change = Calculus.abs(child_value - old[2])
                value_scale = Calculus.abs(old[2])
                value_scale = ~1.0 if value_scale < ~1.0
                stalled = child_error >= ~0.99*old[4] && value_change <= ~1.1102230246251565e-14*value_scale
                roundoff_streak = stalled ? roundoff_streak + 1 : 0

    final_totals = Calculus.gk15_rebuild(panels)
    if final_totals != nil
      values = Calculus.gk15_totals_values(final_totals)
    else
      status = :nonfinite_arithmetic
    Calculus.gk15_result(sign, panels, values[0], values[1], values[2],
      values[3], evaluations, status, true, true)
