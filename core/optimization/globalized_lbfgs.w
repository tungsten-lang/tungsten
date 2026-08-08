# Gradient-norm safeguarded L-BFGS for finite-dimensional unconstrained
# optimization. Stored positive-curvature pairs are reconsidered against the
# current gradient norm at every iteration; the two-loop seed scale is clipped
# to a matching finite interval. Existing Optimization.lbfgs remains unchanged.

+ OptimizationGlobalizedLBFGSCriteria
  -> new(gradient_tol = ~1.0e-8, max_iterations = 300,
         line_search_iterations = 40, history_size = 5,
         c0 = ~1.0e-4, c1 = ~1.0, c2 = nil)
    @gradient_tol = gradient_tol + ~0.0
    @max_iterations = max_iterations
    @line_search_iterations = line_search_iterations
    @history_size = history_size
    @c0 = c0 + ~0.0
    @c1 = c1 + ~0.0
    if (!Optimization.finite_value?(@gradient_tol) ||
        @gradient_tol < ~0.0)
      raise "globalized L-BFGS gradient_tol must be finite and nonnegative"
    limits = [@max_iterations, @line_search_iterations, @history_size]
    limits.each ->
      if !Optimization.integer_value?(item) || item < 0
        raise "globalized L-BFGS limits must be nonnegative integers"
    if @line_search_iterations == 0
      raise "globalized L-BFGS line_search_iterations must be positive"
    if (!Optimization.finite_value?(@c0) || @c0 <= ~0.0 || @c0 > ~1.0)
      raise "globalized L-BFGS c0 must be finite and in (0, 1]"
    if !Optimization.finite_value?(@c1) || @c1 <= ~0.0
      raise "globalized L-BFGS c1 must be finite and positive"
    @c2 = c2
    if @c2 == nil
      @c2 = ~1.0 / (~2.0 * @history_size + ~3.0)
    else
      @c2 = @c2 + ~0.0
    if !Optimization.finite_value?(@c2) || @c2 <= ~0.0
      raise "globalized L-BFGS c2 must be finite and positive"

  -> gradient_tol
    @gradient_tol
  -> max_iterations
    @max_iterations
  -> line_search_iterations
    @line_search_iterations
  -> history_size
    @history_size
  -> c0
    @c0
  -> safeguard_cap
    @c0
  -> c1
    @c1
  -> safeguard_scale
    @c1
  -> c2
    @c2
  -> safeguard_exponent
    @c2

  # This is only the paper's exponent inequality for the local Armijo rate;
  # the other analytic assumptions cannot be checked from solver inputs.
  -> armijo_rate_parameter_limit
    ~1.0 / (~2.0 * @history_size + ~1.0)

  -> armijo_rate_parameter_condition?
    @c2 < armijo_rate_parameter_limit


+ OptimizationGlobalizedLBFGSResult < OptimizationMultivariateResult
  -> new(@data)

  # Keep the common result accessors explicit so this directly autoloadable
  # subtype has the same surface in interpreted and self-hosted programs.
  -> parameters
    @data["parameters"]
  -> x
    parameters
  -> value
    @data["value"]
  -> objective
    value
  -> minimum
    value
  -> initial_value
    @data["initial_value"]
  -> gradient
    @data["gradient"]
  -> gradient_norm
    @data["gradient_norm"]
  -> projected_gradient_norm
    @data["projected_gradient_norm"]
  -> step_norm
    @data["step_norm"]
  -> iterations
    @data["iterations"]
  -> evaluations
    function_evaluations + gradient_evaluations
  -> function_evaluations
    @data["function_evaluations"]
  -> gradient_evaluations
    @data["gradient_evaluations"]
  -> line_search_evaluations
    @data["line_search_evaluations"]
  -> accepted_steps
    @data["accepted_steps"]
  -> skipped_updates
    @data["skipped_updates"]
  -> active_bounds
    @data["active_bounds"]
  -> constraint_violation
    @data["constraint_violation"]
  -> outer_iterations
    @data["outer_iterations"]
  -> penalty
    @data["penalty"]
  -> convergence_reason
    @data["convergence_reason"]
  -> method
    @data["method"]
  -> status
    @data["status"]
  -> status_code
    status.code
  -> message
    status.message
  -> converged?
    status.converged?
  -> success?
    converged?
  -> certified?
    false

  # The safeguard and its convergence test use the Euclidean gradient norm.
  # The inherited gradient_norm remains the multivariate infinity norm.
  -> safeguard_gradient_norm
    @data["safeguard_gradient_norm"]
  -> euclidean_gradient_norm
    safeguard_gradient_norm
  -> stored_pairs
    @data["stored_pairs"]
  -> last_pairs_used
    @data["last_pairs_used"]
  -> maximum_pairs_used
    @data["maximum_pairs_used"]
  # Counts pair/iteration occurrences, not distinct stored pairs.
  -> filtered_pair_uses
    @data["filtered_pair_uses"]
  -> accepted_curvature_pairs
    @data["accepted_curvature_pairs"]
  -> bb_scale_updates
    @data["bb_scale_updates"]
  -> rejected_curvature_pairs
    @data["rejected_curvature_pairs"]
  -> nonpositive_curvature_pairs
    @data["nonpositive_curvature_pairs"]
  -> numerically_unusable_pairs
    @data["numerically_unusable_pairs"]
  -> history_restarts
    @data["history_restarts"]
  -> descent_fallbacks
    history_restarts
  -> safeguard_threshold
    @data["safeguard_threshold"]
  -> omega
    safeguard_threshold
  -> seed_scale
    @data["seed_scale"]
  -> armijo_rate_parameter_condition?
    @data["armijo_rate_parameter_condition"]

  -> inspect
    text = "OptimizationGlobalizedLBFGSResult(value=" + value.to_s
    text += ", gradient_norm=" + safeguard_gradient_norm.to_s
    text + ", " + status.to_s + ")"

  -> to_s
    inspect


+ Optimization
  -> .globalized_lbfgs_criteria(value)
    return OptimizationGlobalizedLBFGSCriteria.new if value == nil
    if value.class_name != "OptimizationGlobalizedLBFGSCriteria"
      raise "criteria must be an OptimizationGlobalizedLBFGSCriteria"
    value

  -> .globalized_lbfgs_counters
    counters = Optimization.multivariate_counters
    counters["accepted_curvature_pairs"] = 0
    counters["bb_scale_updates"] = 0
    counters["rejected_curvature_pairs"] = 0
    counters["last_pairs_used"] = 0
    counters["maximum_pairs_used"] = 0
    counters["filtered_pair_uses"] = 0
    counters["nonpositive_curvature_pairs"] = 0
    counters["numerically_unusable_pairs"] = 0
    counters["history_restarts"] = 0
    counters

  -> .globalized_lbfgs_diagnostics
    {"initial_value": nil, "stored_pairs": 0,
     "safeguard_threshold": nil, "seed_scale": nil}

  -> .globalized_lbfgs_result(point, value, gradient, counters,
                               diagnostics, outcome, settings)
    OptimizationGlobalizedLBFGSResult.new({
      "parameters": Optimization.copy_vector(point),
      "value": value,
      "initial_value": diagnostics["initial_value"],
      "gradient": Optimization.copy_vector(gradient),
      "gradient_norm": Optimization.infinity_norm(gradient),
      "projected_gradient_norm": Optimization.infinity_norm(gradient),
      "safeguard_gradient_norm": Optimization.euclidean_norm(gradient),
      "step_norm": counters["step_norm"],
      "iterations": counters["iterations"],
      "function_evaluations": counters["function_evaluations"],
      "gradient_evaluations": counters["gradient_evaluations"],
      "line_search_evaluations": counters["line_search_evaluations"],
      "accepted_steps": counters["accepted_steps"],
      "skipped_updates": counters["rejected_curvature_pairs"],
      "active_bounds": 0,
      "constraint_violation": nil,
      "outer_iterations": nil,
      "penalty": nil,
      "convergence_reason": outcome["reason"],
      "method": :globalized_lbfgs,
      "stored_pairs": diagnostics["stored_pairs"],
      "last_pairs_used": counters["last_pairs_used"],
      "maximum_pairs_used": counters["maximum_pairs_used"],
      "filtered_pair_uses": counters["filtered_pair_uses"],
      "accepted_curvature_pairs": counters["accepted_curvature_pairs"],
      "bb_scale_updates": counters["bb_scale_updates"],
      "rejected_curvature_pairs": counters["rejected_curvature_pairs"],
      "nonpositive_curvature_pairs":
        counters["nonpositive_curvature_pairs"],
      "numerically_unusable_pairs":
        counters["numerically_unusable_pairs"],
      "history_restarts": counters["history_restarts"],
      "safeguard_threshold": diagnostics["safeguard_threshold"],
      "seed_scale": diagnostics["seed_scale"],
      "armijo_rate_parameter_condition":
        settings.armijo_rate_parameter_condition?,
      "status": Optimization.status(outcome["code"], outcome["message"])
    })

  # Return the cosine and norm ratio used by
  # q(s,y) = min(y's / ||s||^2, y's / ||y||^2). Normalizing first avoids
  # needless overflow and underflow from squaring the vector norms.
  -> .globalized_lbfgs_pair_geometry(step, gradient_change)
    return nil if step.size == 0 || step.size != gradient_change.size
    step_norm = Optimization.euclidean_norm(step)
    change_norm = Optimization.euclidean_norm(gradient_change)
    if (!Optimization.finite_value?(step_norm) ||
        !Optimization.finite_value?(change_norm))
      return nil
    return nil if step_norm <= ~0.0 || change_norm <= ~0.0
    normalized_step = []
    normalized_change = []
    i = 0
    while i < step.size
      normalized_step.push(step[i] / step_norm)
      normalized_change.push(gradient_change[i] / change_norm)
      i += 1
    cosine = Optimization.dot(normalized_step, normalized_change)
    return nil if !Optimization.finite_value?(cosine)
    cosine = ~1.0 if cosine > ~1.0
    ratio = change_norm / step_norm
    ratio = step_norm / change_norm if step_norm < change_norm
    return nil if !Optimization.finite_value?(ratio) || ratio <= ~0.0
    {"cosine": cosine, "step_norm": step_norm,
     "change_norm": change_norm, "symmetric_ratio": ratio}

  -> .globalized_lbfgs_pair_quality(step, gradient_change)
    geometry = Optimization.globalized_lbfgs_pair_geometry(
      step, gradient_change)
    return ~0.0 if geometry == nil || geometry["cosine"] <= ~0.0
    quality = geometry["cosine"] * geometry["symmetric_ratio"]
    return ~0.0 if !Optimization.finite_value?(quality) || quality <= ~0.0
    quality

  # A pair can have a representable quality while y's or its reciprocal is
  # outside binary64. Such a pair is diagnostically numerical, not a claim of
  # nonpositive mathematical curvature.
  -> .globalized_lbfgs_pair_data(step, gradient_change)
    geometry = Optimization.globalized_lbfgs_pair_geometry(
      step, gradient_change)
    if geometry == nil
      return {"ok": false, "bb_usable": false,
              "reason": :numerical, "quality": ~0.0}
    cosine = geometry["cosine"]
    if cosine <= ~0.0
      return {"ok": false, "bb_usable": false,
              "reason": :nonpositive, "quality": ~0.0}
    quality = cosine * geometry["symmetric_ratio"]
    if !Optimization.finite_value?(quality) || quality <= ~0.0
      return {"ok": false, "bb_usable": false,
              "reason": :numerical, "quality": ~0.0}
    scale_ratio = geometry["step_norm"] / geometry["change_norm"]
    gamma_lower = cosine * scale_ratio
    gamma_upper = scale_ratio / cosine
    bb_usable = Optimization.finite_value?(gamma_lower)
    bb_usable = bb_usable && Optimization.finite_value?(gamma_upper)
    bb_usable = false if gamma_lower <= ~0.0
    bb_usable = false if gamma_upper < gamma_lower
    if !bb_usable
      return {"ok": false, "bb_usable": false,
              "reason": :numerical, "quality": quality}
    curvature_scale = geometry["step_norm"] * geometry["change_norm"]
    curvature = cosine * curvature_scale
    if !Optimization.finite_value?(curvature) || curvature <= ~0.0
      return {"ok": false, "bb_usable": true, "reason": :numerical,
              "quality": quality, "gamma_lower": gamma_lower,
              "gamma_upper": gamma_upper}
    rho = ~1.0 / curvature
    if !Optimization.finite_value?(rho) || rho <= ~0.0
      return {"ok": false, "bb_usable": true, "reason": :numerical,
              "quality": quality, "gamma_lower": gamma_lower,
              "gamma_upper": gamma_upper}
    {"ok": true, "bb_usable": true, "reason": nil,
     "quality": quality, "rho": rho, "gamma_lower": gamma_lower,
     "gamma_upper": gamma_upper}

  -> .globalized_lbfgs_threshold(gradient_norm, settings)
    candidate = settings.c1 * gradient_norm ** settings.c2
    return settings.c0 if candidate.infinite?
    return nil if candidate.nan? || candidate <= ~0.0
    candidate < settings.c0 ? candidate : settings.c0

  -> .globalized_lbfgs_clamp(value, lower, upper)
    return lower if value < lower
    return upper if value > upper
    value

  # The lower BB scale is the deterministic preferred value. If its BB
  # interval does not intersect the safeguard, project it into the latter.
  -> .globalized_lbfgs_seed_scale(gamma_lower, gamma_upper, threshold)
    safeguard_upper = ~1.0 / threshold
    return nil if !Optimization.finite_value?(safeguard_upper)
    preferred = gamma_lower
    preferred = ~1.0 if preferred == nil || preferred <= ~0.0
    if (gamma_lower != nil && gamma_lower > ~0.0 &&
        gamma_upper != nil && gamma_upper >= gamma_lower)
      lower = gamma_lower > threshold ? gamma_lower : threshold
      upper = gamma_upper < safeguard_upper ? gamma_upper : safeguard_upper
      if lower <= upper
        return Optimization.globalized_lbfgs_clamp(preferred, lower, upper)
    Optimization.globalized_lbfgs_clamp(
      preferred, threshold, safeguard_upper)

  # Retrospective filtering does not destroy a pair that is skipped now.
  -> .globalized_lbfgs_selected_history(steps, changes, qualities, rhos,
                                         threshold)
    selected_steps = []
    selected_changes = []
    selected_rhos = []
    i = 0
    while i < steps.size
      if qualities[i] >= threshold
        if Optimization.finite_value?(rhos[i]) && rhos[i] > ~0.0
          selected_steps.push(steps[i])
          selected_changes.push(changes[i])
          selected_rhos.push(rhos[i])
      i += 1
    {"steps": selected_steps, "changes": selected_changes,
     "rhos": selected_rhos}

  -> .globalized_lbfgs_two_loop_direction(gradient, steps, changes, rhos,
                                           seed_scale)
    count = steps.size
    q = Optimization.copy_vector(gradient)
    alphas = Optimization.zero_vector(count)
    i = count - 1
    while i >= 0
      alphas[i] = rhos[i] * Optimization.dot(steps[i], q)
      j = 0
      while j < q.size
        q[j] -= alphas[i] * changes[i][j]
        j += 1
      i -= 1
    r = []
    q.each -> r.push(seed_scale * item)
    i = 0
    while i < count
      beta = rhos[i] * Optimization.dot(changes[i], r)
      j = 0
      while j < r.size
        r[j] += steps[i][j] * (alphas[i] - beta)
        j += 1
      i += 1
    Optimization.negative_vector(r)

  # This is Core's fixed Armijo policy (sigma=1e-4, halving from alpha=1),
  # with explicit classification when no representable decreasing model or
  # trial point remains. Objective exceptions and non-finite values retain the
  # common callback statuses.
  -> .globalized_lbfgs_line_search(objective, point, value, gradient,
                                    direction, limit)
    alpha = ~1.0
    evaluations = 0
    terminal_failure = nil
    attempts = 0
    while attempts < limit
      candidate = []
      finite_candidate = true
      changed = false
      i = 0
      while i < point.size
        next_value = point[i] + alpha * direction[i]
        finite_candidate = false if !Optimization.finite_value?(next_value)
        changed = true if next_value != point[i]
        candidate.push(next_value)
        i += 1
      if finite_candidate && changed
        step = Optimization.subtract_vectors(candidate, point)
        directional_change = Optimization.dot(gradient, step)
        if (Optimization.finite_value?(directional_change) &&
            directional_change < ~0.0)
          evaluation = Optimization.evaluate_objective_callback(
            objective, candidate)
          evaluations += 1
          if evaluation["ok"]
            threshold = value + ~1.0e-4 * directional_change
            if evaluation["value"] <= threshold
              if evaluation["value"] < value || threshold < value
                return {"ok": true, "point": candidate,
                        "value": evaluation["value"], "step": step,
                        "evaluations": evaluations, "alpha": alpha}
              terminal_failure = {
                "code": :precision_limit,
                "message": "Armijo decrease rounded away in binary64"}
            else
              terminal_failure = {
                "code": :line_search_failed,
                "message": "Armijo trial did not provide sufficient decrease"}
          else
            terminal_failure = evaluation
        else
          terminal_failure = {
            "code": :precision_limit,
            "message": "Armijo directional decrease is not representable"}
      else
        terminal_failure = {
          "code": :precision_limit,
          "message": "Armijo trial step is not representable"}
      alpha *= ~0.5
      attempts += 1
    if terminal_failure != nil
      return {"ok": false, "evaluations": evaluations,
              "code": terminal_failure["code"],
              "message": terminal_failure["message"]}
    {"ok": false, "evaluations": evaluations,
     "code": :line_search_failed,
     "message": "Armijo line search could not find a decreasing step"}

  -> .globalized_lbfgs(objective, initial, gradient_function,
                        criteria = nil)
    if gradient_function == nil
      raise "globalized L-BFGS requires an analytic gradient callback"
    settings = Optimization.globalized_lbfgs_criteria(criteria)
    point = Optimization.copy_numeric_vector(
      initial, "globalized L-BFGS initial point")
    counters = Optimization.globalized_lbfgs_counters
    diagnostics = Optimization.globalized_lbfgs_diagnostics

    evaluation = Optimization.evaluate_objective_callback(objective, point)
    counters["function_evaluations"] += 1
    if !evaluation["ok"]
      return Optimization.globalized_lbfgs_result(
        point, nil, Optimization.zero_vector(point.size), counters,
        diagnostics, {"code": evaluation["code"],
        "message": evaluation["message"], "reason": nil}, settings)
    value = evaluation["value"]
    diagnostics["initial_value"] = value
    gradient_result = Optimization.evaluate_gradient_callback(
      gradient_function, objective, point)
    counters["gradient_evaluations"] += 1
    counters["function_evaluations"] += gradient_result[
      "function_evaluations"]
    if !gradient_result["ok"]
      return Optimization.globalized_lbfgs_result(
        point, value, Optimization.zero_vector(point.size), counters,
        diagnostics, {"code": gradient_result["code"],
        "message": gradient_result["message"], "reason": nil}, settings)
    gradient = gradient_result["gradient"]

    steps = []
    changes = []
    qualities = []
    rhos = []
    gamma_lower = ~0.0
    gamma_upper = nil

    while true
      safeguard_gradient_norm = Optimization.euclidean_norm(gradient)
      if !Optimization.finite_value?(safeguard_gradient_norm)
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": :precision_limit,
           "message": "Euclidean gradient norm overflowed binary64",
           "reason": nil}, settings)
      if safeguard_gradient_norm <= settings.gradient_tol
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": :converged,
           "message": "Euclidean gradient norm met gradient_tol",
           "reason": :gradient}, settings)
      if counters["iterations"] >= settings.max_iterations
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": :iteration_limit,
           "message": "globalized L-BFGS reached max_iterations",
           "reason": nil}, settings)

      threshold = Optimization.globalized_lbfgs_threshold(
        safeguard_gradient_norm, settings)
      if threshold == nil
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": :precision_limit,
           "message": "gradient-dependent safeguard underflowed",
           "reason": nil}, settings)
      seed = Optimization.globalized_lbfgs_seed_scale(
        gamma_lower, gamma_upper, threshold)
      if seed == nil
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": :precision_limit,
           "message": "inverse safeguard scale overflowed",
           "reason": nil}, settings)
      selected = Optimization.globalized_lbfgs_selected_history(
        steps, changes, qualities, rhos, threshold)
      used = selected["steps"].size
      counters["last_pairs_used"] = used
      if used > counters["maximum_pairs_used"]
        counters["maximum_pairs_used"] = used
      counters["filtered_pair_uses"] += steps.size - used
      diagnostics["safeguard_threshold"] = threshold
      diagnostics["seed_scale"] = seed

      direction = Optimization.globalized_lbfgs_two_loop_direction(
        gradient, selected["steps"], selected["changes"],
        selected["rhos"], seed)
      descent = Optimization.dot(gradient, direction)
      if (!Optimization.finite_vector?(direction) ||
          !Optimization.finite_value?(descent) || descent >= ~0.0 ||
          Optimization.euclidean_norm(direction) == ~0.0)
        direction = []
        gradient.each -> direction.push(~0.0 - seed * item)
        steps = []
        changes = []
        qualities = []
        rhos = []
        gamma_lower = ~0.0
        gamma_upper = nil
        counters["history_restarts"] += 1
        descent = Optimization.dot(gradient, direction)
        if (!Optimization.finite_vector?(direction) ||
            !Optimization.finite_value?(descent) || descent >= ~0.0 ||
            Optimization.euclidean_norm(direction) == ~0.0)
          diagnostics["stored_pairs"] = 0
          return Optimization.globalized_lbfgs_result(
            point, value, gradient, counters, diagnostics,
            {"code": :precision_limit,
             "message": "safeguarded descent direction is not representable",
             "reason": nil}, settings)

      line = Optimization.globalized_lbfgs_line_search(
        objective, point, value, gradient, direction,
        settings.line_search_iterations)
      counters["line_search_evaluations"] += line["evaluations"]
      counters["function_evaluations"] += line["evaluations"]
      if !line["ok"]
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": line["code"], "message": line["message"],
           "reason": nil}, settings)

      next_gradient_result = Optimization.evaluate_gradient_callback(
        gradient_function, objective, line["point"])
      counters["gradient_evaluations"] += 1
      counters["function_evaluations"] += next_gradient_result[
        "function_evaluations"]
      if !next_gradient_result["ok"]
        diagnostics["stored_pairs"] = steps.size
        return Optimization.globalized_lbfgs_result(
          point, value, gradient, counters, diagnostics,
          {"code": next_gradient_result["code"],
           "message": next_gradient_result["message"], "reason": nil},
          settings)

      counters["iterations"] += 1
      next_gradient = next_gradient_result["gradient"]
      step = line["step"]
      counters["step_norm"] = Optimization.euclidean_norm(step)
      change = Optimization.subtract_vectors(next_gradient, gradient)
      pair = Optimization.globalized_lbfgs_pair_data(step, change)
      if pair["bb_usable"]
        gamma_lower = pair["gamma_lower"]
        gamma_upper = pair["gamma_upper"]
        counters["bb_scale_updates"] += 1
      else
        gamma_lower = ~0.0
        gamma_upper = nil
      if pair["ok"]
        if settings.history_size > 0
          if steps.size >= settings.history_size
            steps.delete_at(0)
            changes.delete_at(0)
            qualities.delete_at(0)
            rhos.delete_at(0)
          steps.push(step)
          changes.push(change)
          qualities.push(pair["quality"])
          rhos.push(pair["rho"])
        counters["accepted_curvature_pairs"] += 1
      else
        counters["rejected_curvature_pairs"] += 1
        if pair["reason"] == :nonpositive
          counters["nonpositive_curvature_pairs"] += 1
        else
          counters["numerically_unusable_pairs"] += 1

      point = line["point"]
      value = line["value"]
      gradient = next_gradient
      counters["accepted_steps"] += 1
      diagnostics["stored_pairs"] = steps.size
