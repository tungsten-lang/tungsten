# Small dense unconstrained, box-constrained, and quadratic-penalty
# optimization. BFGS and limited-memory BFGS use an Armijo backtracking line
# search; box constraints use projected steps rather than claiming L-BFGS-B.

+ OptimizationMultivariateCriteria
  -> new(gradient_tol = ~1.0e-8, step_tol = ~1.0e-10,
         objective_tol = ~1.0e-12, max_iterations = 200,
         line_search_iterations = 30, curvature_tol = ~1.0e-12,
         history_size = 10)
    @gradient_tol = gradient_tol + ~0.0
    @step_tol = step_tol + ~0.0
    @objective_tol = objective_tol + ~0.0
    @max_iterations = max_iterations
    @line_search_iterations = line_search_iterations
    @curvature_tol = curvature_tol + ~0.0
    @history_size = history_size
    values = [@gradient_tol, @step_tol, @objective_tol, @curvature_tol]
    values.each ->
      if !Optimization.finite_value?(item) || item < ~0.0
        raise "multivariate tolerances must be finite and nonnegative"
    limits = [@max_iterations, @line_search_iterations, @history_size]
    limits.each ->
      if !Optimization.integer_value?(item) || item < 0
        raise "multivariate iteration and history limits must be nonnegative integers"
    if @line_search_iterations == 0
      raise "multivariate line_search_iterations must be positive"
    if @history_size == 0
      raise "L-BFGS history_size must be positive"

  -> gradient_tol
    @gradient_tol
  -> step_tol
    @step_tol
  -> objective_tol
    @objective_tol
  -> max_iterations
    @max_iterations
  -> line_search_iterations
    @line_search_iterations
  -> curvature_tol
    @curvature_tol
  -> history_size
    @history_size


+ OptimizationBounds
  -> new(lower, upper)
    if lower.class_name != "Array" || upper.class_name != "Array"
      raise "optimization bounds must be Arrays"
    if lower.size == 0 || lower.size != upper.size
      raise "optimization bounds must be nonempty and have matching sizes"
    @lower = []
    @upper = []
    i = 0
    while i < lower.size
      lo = lower[i]
      hi = upper[i]
      lo = lo + ~0.0 if lo != nil
      hi = hi + ~0.0 if hi != nil
      if lo != nil && !Optimization.finite_value?(lo)
        raise "lower bounds must be finite or nil"
      if hi != nil && !Optimization.finite_value?(hi)
        raise "upper bounds must be finite or nil"
      if lo != nil && hi != nil && lo > hi
        raise "optimization lower bounds must not exceed upper bounds"
      @lower.push(lo)
      @upper.push(hi)
      i += 1

  -> lower
    @lower
  -> upper
    @upper
  -> size
    @lower.size

  -> validate_dimension(dimension)
    if dimension != size
      raise "optimization bounds dimension does not match the initial point"
    self

  -> project(point)
    validate_dimension(point.size)
    answer = []
    i = 0
    while i < point.size
      value = point[i]
      value = @lower[i] if @lower[i] != nil && value < @lower[i]
      value = @upper[i] if @upper[i] != nil && value > @upper[i]
      answer.push(value)
      i += 1
    answer

  -> projected_direction(point, direction)
    answer = []
    i = 0
    while i < point.size
      value = direction[i]
      value = ~0.0 if @lower[i] != nil && point[i] <= @lower[i] && value < ~0.0
      value = ~0.0 if @upper[i] != nil && point[i] >= @upper[i] && value > ~0.0
      answer.push(value)
      i += 1
    answer

  -> projected_gradient(point, gradient)
    answer = []
    i = 0
    while i < point.size
      value = gradient[i]
      value = ~0.0 if @lower[i] != nil && point[i] <= @lower[i] && value > ~0.0
      value = ~0.0 if @upper[i] != nil && point[i] >= @upper[i] && value < ~0.0
      answer.push(value)
      i += 1
    answer

  -> active_count(point)
    count = 0
    i = 0
    while i < point.size
      count += 1 if @lower[i] != nil && point[i] == @lower[i]
      count += 1 if (@upper[i] != nil && point[i] == @upper[i] &&
        (@lower[i] == nil || @upper[i] != @lower[i]))
      i += 1
    count


+ OptimizationConstraints
  # Equality callbacks use c(x)=0; inequality callbacks use g(x)<=0.
  -> new(equalities = [], inequalities = [], feasibility_tol = ~1.0e-6,
         initial_penalty = ~10.0, penalty_growth = ~10.0,
         max_outer_iterations = 8)
    if (equalities.class_name != "Array" ||
        inequalities.class_name != "Array")
      raise "optimization constraints must be callback Arrays"
    if equalities.size == 0 && inequalities.size == 0
      raise "optimization constraints need at least one callback"
    @equalities = equalities
    @inequalities = inequalities
    @feasibility_tol = feasibility_tol + ~0.0
    @initial_penalty = initial_penalty + ~0.0
    @penalty_growth = penalty_growth + ~0.0
    @max_outer_iterations = max_outer_iterations
    if (!Optimization.finite_value?(@feasibility_tol) ||
        @feasibility_tol < ~0.0)
      raise "constraint feasibility_tol must be finite and nonnegative"
    if (!Optimization.finite_value?(@initial_penalty) ||
        @initial_penalty <= ~0.0)
      raise "constraint initial_penalty must be finite and positive"
    if (!Optimization.finite_value?(@penalty_growth) ||
        @penalty_growth <= ~1.0)
      raise "constraint penalty_growth must be finite and greater than one"
    if (!Optimization.integer_value?(@max_outer_iterations) ||
        @max_outer_iterations <= 0)
      raise "constraint max_outer_iterations must be a positive integer"

  -> equalities
    @equalities
  -> inequalities
    @inequalities
  -> feasibility_tol
    @feasibility_tol
  -> initial_penalty
    @initial_penalty
  -> penalty_growth
    @penalty_growth
  -> max_outer_iterations
    @max_outer_iterations


+ OptimizationMultivariateResult
  -> new(@data)
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
  -> inspect
    text = "OptimizationMultivariateResult(method=" + method.to_s
    text += ", value=" + value.to_s + ", " + status.to_s + ")"
    text
  -> to_s
    inspect


+ Optimization
  -> .multivariate_criteria(value)
    return OptimizationMultivariateCriteria.new if value == nil
    if value.class_name != "OptimizationMultivariateCriteria"
      raise "multivariate criteria must be an OptimizationMultivariateCriteria"
    value

  -> .multivariate_counters
    {
      "iterations": 0,
      "function_evaluations": 0,
      "gradient_evaluations": 0,
      "line_search_evaluations": 0,
      "accepted_steps": 0,
      "skipped_updates": 0,
      "step_norm": ~0.0
    }

  -> .multivariate_result(point, value, gradient, counters, bounds,
                           metadata, outcome)
    projected = gradient
    active = 0
    if bounds != nil
      projected = bounds.projected_gradient(point, gradient)
      active = bounds.active_count(point)
    OptimizationMultivariateResult.new({
      "parameters": Optimization.copy_vector(point),
      "value": value,
      "initial_value": metadata["initial_value"],
      "gradient": Optimization.copy_vector(gradient),
      "gradient_norm": Optimization.infinity_norm(gradient),
      "projected_gradient_norm": Optimization.infinity_norm(projected),
      "step_norm": counters["step_norm"],
      "iterations": counters["iterations"],
      "function_evaluations": counters["function_evaluations"],
      "gradient_evaluations": counters["gradient_evaluations"],
      "line_search_evaluations": counters["line_search_evaluations"],
      "accepted_steps": counters["accepted_steps"],
      "skipped_updates": counters["skipped_updates"],
      "active_bounds": active,
      "constraint_violation": metadata["constraint_violation"],
      "outer_iterations": metadata["outer_iterations"],
      "penalty": metadata["penalty"],
      "convergence_reason": outcome["reason"],
      "method": metadata["method"],
      "status": Optimization.status(outcome["code"], outcome["message"])
    })

  -> .multivariate_metadata(method, initial_value = nil)
    {"method": method, "initial_value": initial_value,
     "constraint_violation": nil, "outer_iterations": nil,
     "penalty": nil}

  -> .evaluate_objective_callback(function, point)
    value = nil
    begin
      value = function(Optimization.copy_vector(point)) + ~0.0
    rescue error
      return {"ok": false, "code": :callback_error,
              "message": "objective callback failed: " + error.to_s}
    if !Optimization.finite_value?(value)
      return {"ok": false, "code": :non_finite_value,
              "message": "objective callback returned a non-finite value"}
    {"ok": true, "value": value}

  -> .evaluate_gradient_callback(function, objective, point)
    if function != nil
      values = nil
      begin
        values = function(Optimization.copy_vector(point))
      rescue error
        return {"ok": false, "code": :callback_error,
                "message": "gradient callback failed: " + error.to_s,
                "function_evaluations": 0}
      if values.class_name != "Array" || values.size != point.size
        return {"ok": false, "code": :invalid_gradient,
                "message": "gradient callback returned the wrong shape",
                "function_evaluations": 0}
      answer = []
      i = 0
      while i < values.size
        value = nil
        begin
          value = values[i] + ~0.0
        rescue error
          return {"ok": false, "code": :invalid_gradient,
                  "message": "gradient entries must be numeric",
                  "function_evaluations": 0}
        if !Optimization.finite_value?(value)
          return {"ok": false, "code": :non_finite_value,
                  "message": "gradient callback returned a non-finite value",
                  "function_evaluations": 0}
        answer.push(value)
        i += 1
      return {"ok": true, "gradient": answer,
              "function_evaluations": 0}

    answer = []
    function_evaluations = 0
    i = 0
    while i < point.size
      h = Optimization.representable_difference_step(point[i])
      if h == nil
        return {"ok": false, "code": :precision_limit,
                "message": "finite-difference step is not representable",
                "function_evaluations": function_evaluations}
      upper_point = Optimization.copy_vector(point)
      lower_point = Optimization.copy_vector(point)
      upper_point[i] += h
      lower_point[i] -= h
      upper = Optimization.evaluate_objective_callback(objective, upper_point)
      function_evaluations += 1
      if !upper["ok"]
        upper["function_evaluations"] = function_evaluations
        return upper
      lower = Optimization.evaluate_objective_callback(objective, lower_point)
      function_evaluations += 1
      if !lower["ok"]
        lower["function_evaluations"] = function_evaluations
        return lower
      derivative = (upper["value"] - lower["value"]) / (~2.0 * h)
      if !Optimization.finite_value?(derivative)
        return {"ok": false, "code": :non_finite_value,
                "message": "finite-difference gradient is non-finite",
                "function_evaluations": function_evaluations}
      answer.push(derivative)
      i += 1
    {"ok": true, "gradient": answer,
     "function_evaluations": function_evaluations}

  -> .negative_vector(values)
    answer = []
    values.each -> answer.push(~0.0 - item)
    answer

  -> .subtract_vectors(left, right)
    answer = []
    i = 0
    while i < left.size
      answer.push(left[i] - right[i])
      i += 1
    answer

  -> .matrix_times_vector(matrix, vector)
    Optimization.matrix_vector(matrix, vector)

  -> .bfgs_inverse_update(inverse, step, gradient_change,
                          curvature_tolerance)
    curvature = Optimization.dot(step, gradient_change)
    scale = (Optimization.euclidean_norm(step) *
      Optimization.euclidean_norm(gradient_change))
    if curvature <= curvature_tolerance * scale || curvature <= ~0.0
      return nil
    rho = ~1.0 / curvature
    size = step.size
    left = Optimization.identity_matrix(size)
    right = Optimization.identity_matrix(size)
    i = 0
    while i < size
      j = 0
      while j < size
        left[i][j] -= rho * step[i] * gradient_change[j]
        right[i][j] -= rho * gradient_change[i] * step[j]
        j += 1
      i += 1
    temporary = Optimization.zero_matrix(size, size)
    i = 0
    while i < size
      j = 0
      while j < size
        k = 0
        while k < size
          temporary[i][j] += left[i][k] * inverse[k][j]
          k += 1
        j += 1
      i += 1
    answer = Optimization.zero_matrix(size, size)
    i = 0
    while i < size
      j = 0
      while j < size
        k = 0
        while k < size
          answer[i][j] += temporary[i][k] * right[k][j]
          k += 1
        answer[i][j] += rho * step[i] * step[j]
        j += 1
      i += 1
    answer

  -> .lbfgs_direction(gradient, steps, gradient_changes, rhos)
    count = steps.size
    q = Optimization.copy_vector(gradient)
    alphas = Optimization.zero_vector(count)
    i = count - 1
    while i >= 0
      alphas[i] = rhos[i] * Optimization.dot(steps[i], q)
      j = 0
      while j < q.size
        q[j] -= alphas[i] * gradient_changes[i][j]
        j += 1
      i -= 1
    scale = ~1.0
    if count > 0
      last_step = steps[count - 1]
      last_change = gradient_changes[count - 1]
      denominator = Optimization.dot(last_change, last_change)
      if denominator > ~0.0
        scale = Optimization.dot(last_step, last_change) / denominator
    r = []
    q.each -> r.push(scale * item)
    i = 0
    while i < count
      beta = rhos[i] * Optimization.dot(gradient_changes[i], r)
      j = 0
      while j < r.size
        r[j] += steps[i][j] * (alphas[i] - beta)
        j += 1
      i += 1
    Optimization.negative_vector(r)

  -> .armijo_line_search(objective, point, value, gradient, direction,
                          bounds, limit)
    alpha = ~1.0
    evaluations = 0
    valid_evaluations = 0
    failed_evaluation = nil
    attempts = 0
    while attempts < limit
      candidate = []
      i = 0
      while i < point.size
        candidate.push(point[i] + alpha * direction[i])
        i += 1
      candidate = bounds.project(candidate) if bounds != nil
      step = Optimization.subtract_vectors(candidate, point)
      directional_change = Optimization.dot(gradient, step)
      if (Optimization.euclidean_norm(step) > ~0.0 &&
          directional_change < ~0.0)
        evaluation = Optimization.evaluate_objective_callback(
          objective, candidate)
        evaluations += 1
        if evaluation["ok"]
          valid_evaluations += 1
          threshold = value + ~1.0e-4 * directional_change
          if evaluation["value"] <= threshold
            return {"ok": true, "point": candidate,
                    "value": evaluation["value"], "step": step,
                    "evaluations": evaluations, "alpha": alpha}
        else
          failed_evaluation = evaluation
      alpha *= ~0.5
      attempts += 1
    if valid_evaluations == 0 && failed_evaluation != nil
      return {"ok": false, "evaluations": evaluations,
              "code": failed_evaluation["code"],
              "message": failed_evaluation["message"]}
    {"ok": false, "evaluations": evaluations,
     "code": :line_search_failed,
     "message": "Armijo line search could not find a decreasing step"}

  -> .quasi_newton(objective, initial, gradient_function, criteria,
                    bounds, method)
    settings = Optimization.multivariate_criteria(criteria)
    point = Optimization.copy_numeric_vector(
      initial, "multivariate initial point")
    if bounds != nil
      if bounds.class_name != "OptimizationBounds"
        raise "bounds must be an OptimizationBounds"
      point = bounds.validate_dimension(point.size).project(point)
    counters = Optimization.multivariate_counters
    metadata = Optimization.multivariate_metadata(method)
    evaluation = Optimization.evaluate_objective_callback(objective, point)
    counters["function_evaluations"] += 1
    if !evaluation["ok"]
      return Optimization.multivariate_result(
        point, nil, Optimization.zero_vector(point.size), counters, bounds,
        metadata, {"code": evaluation["code"],
                   "message": evaluation["message"], "reason": nil})
    value = evaluation["value"]
    metadata["initial_value"] = value
    gradient_result = Optimization.evaluate_gradient_callback(
      gradient_function, objective, point)
    counters["gradient_evaluations"] += 1
    counters["function_evaluations"] += gradient_result[
      "function_evaluations"]
    if !gradient_result["ok"]
      return Optimization.multivariate_result(
        point, value, Optimization.zero_vector(point.size), counters, bounds,
        metadata, {"code": gradient_result["code"],
                   "message": gradient_result["message"], "reason": nil})
    gradient = gradient_result["gradient"]
    inverse = Optimization.identity_matrix(point.size)
    steps = []
    changes = []
    rhos = []

    while true
      projected = gradient
      projected = bounds.projected_gradient(point, gradient) if bounds != nil
      projected_norm = Optimization.infinity_norm(projected)
      if projected_norm <= settings.gradient_tol
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": :converged, "message":
           "projected gradient infinity norm met gradient_tol",
           "reason": :gradient})
      if counters["iterations"] >= settings.max_iterations
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": :iteration_limit,
           "message": "quasi-Newton method reached max_iterations",
           "reason": nil})

      direction = nil
      if method == :bfgs
        direction = Optimization.negative_vector(
          Optimization.matrix_times_vector(inverse, gradient))
      else
        direction = Optimization.lbfgs_direction(
          gradient, steps, changes, rhos)
      direction = bounds.projected_direction(point, direction) if bounds != nil
      if (Optimization.dot(gradient, direction) >= ~0.0 ||
          Optimization.euclidean_norm(direction) == ~0.0)
        direction = Optimization.negative_vector(projected)
      line = Optimization.armijo_line_search(
        objective, point, value, gradient, direction, bounds,
        settings.line_search_iterations)
      counters["line_search_evaluations"] += line["evaluations"]
      counters["function_evaluations"] += line["evaluations"]
      if !line["ok"]
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": line["code"], "message": line["message"],
           "reason": nil})
      next_point = line["point"]
      next_value = line["value"]
      step = line["step"]
      counters["step_norm"] = Optimization.euclidean_norm(step)
      next_gradient_result = Optimization.evaluate_gradient_callback(
        gradient_function, objective, next_point)
      counters["gradient_evaluations"] += 1
      counters["function_evaluations"] += next_gradient_result[
        "function_evaluations"]
      counters["iterations"] += 1
      if !next_gradient_result["ok"]
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": next_gradient_result["code"],
           "message": next_gradient_result["message"], "reason": nil})
      next_gradient = next_gradient_result["gradient"]
      change = Optimization.subtract_vectors(next_gradient, gradient)
      curvature = Optimization.dot(step, change)
      curvature_scale = (Optimization.euclidean_norm(step) *
        Optimization.euclidean_norm(change))
      if (curvature > settings.curvature_tol * curvature_scale &&
          curvature > ~0.0)
        if method == :bfgs
          updated = Optimization.bfgs_inverse_update(
            inverse, step, change, settings.curvature_tol)
          if updated == nil
            counters["skipped_updates"] += 1
          else
            inverse = updated
        else
          if steps.size >= settings.history_size
            steps.delete_at(0)
            changes.delete_at(0)
            rhos.delete_at(0)
          steps.push(step)
          changes.push(change)
          rhos.push(~1.0 / curvature)
      else
        counters["skipped_updates"] += 1
      objective_change = (value - next_value).abs
      point = next_point
      value = next_value
      gradient = next_gradient
      counters["accepted_steps"] += 1
      if (counters["step_norm"] <= settings.step_tol *
          (settings.step_tol + Optimization.euclidean_norm(point)))
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": :converged, "message":
           "quasi-Newton step met step_tol", "reason": :step})
      if (objective_change <= settings.objective_tol *
          (~1.0 + value.abs))
        return Optimization.multivariate_result(
          point, value, gradient, counters, bounds, metadata,
          {"code": :converged, "message":
           "objective change met objective_tol", "reason": :objective})

  -> .bfgs(objective, initial, gradient = nil, criteria = nil, bounds = nil)
    Optimization.quasi_newton(
      objective, initial, gradient, criteria, bounds, :bfgs)

  -> .lbfgs(objective, initial, gradient = nil, criteria = nil, bounds = nil)
    Optimization.quasi_newton(
      objective, initial, gradient, criteria, bounds, :lbfgs)

  -> .constraint_values(constraints, point)
    equalities = []
    inequalities = []
    begin
      constraints.equalities.each -> (constraint)
        equalities.push(constraint(point) + ~0.0)
      constraints.inequalities.each -> (constraint)
        inequalities.push(constraint(point) + ~0.0)
    rescue error
      return {"ok": false, "code": :callback_error,
              "message": "constraint callback failed: " + error.to_s}
    if (!Optimization.finite_vector?(equalities) ||
        !Optimization.finite_vector?(inequalities))
      return {"ok": false, "code": :non_finite_value,
              "message": "constraint callback returned a non-finite value"}
    {"ok": true, "equalities": equalities,
     "inequalities": inequalities}

  -> .constraint_violation(values)
    violation = ~0.0
    values["equalities"].each ->
      magnitude = item.abs
      violation = magnitude if magnitude > violation
    values["inequalities"].each ->
      violation = item if item > violation
    violation

  -> .penalized_objective(objective, constraints, penalty)
    -> (point)
      value = objective(point) + ~0.0
      constraint_data = Optimization.constraint_values(constraints, point)
      if !constraint_data["ok"]
        raise constraint_data["message"]
      total = ~0.0
      constraint_data["equalities"].each -> total += item * item
      constraint_data["inequalities"].each ->
        total += item * item if item > ~0.0
      value + ~0.5 * penalty * total

  -> .minimize_constrained(objective, initial, constraints, criteria = nil,
                            bounds = nil, method = :bfgs)
    if constraints.class_name != "OptimizationConstraints"
      raise "constraints must be an OptimizationConstraints"
    if method != :bfgs && method != :lbfgs
      raise "constrained method must be :bfgs or :lbfgs"
    settings = Optimization.multivariate_criteria(criteria)
    point = Optimization.copy_numeric_vector(
      initial, "constrained initial point")
    if bounds != nil
      if bounds.class_name != "OptimizationBounds"
        raise "bounds must be an OptimizationBounds"
      point = bounds.validate_dimension(point.size).project(point)
    penalty = constraints.initial_penalty
    total = Optimization.multivariate_counters
    initial_evaluation = Optimization.evaluate_objective_callback(
      objective, point)
    total["function_evaluations"] += 1
    initial_value = nil
    if initial_evaluation["ok"]
      initial_value = initial_evaluation["value"]
    else
      metadata = Optimization.multivariate_metadata(
        method == :bfgs ? :penalty_bfgs : :penalty_lbfgs)
      return Optimization.multivariate_result(
        point, nil, Optimization.zero_vector(point.size), total, bounds,
        metadata, {"code": initial_evaluation["code"],
                   "message": initial_evaluation["message"],
                   "reason": nil})
    final_gradient = Optimization.zero_vector(point.size)
    final_value = nil
    outer = 0
    while outer < constraints.max_outer_iterations
      composite = Optimization.penalized_objective(
        objective, constraints, penalty)
      result = nil
      if method == :bfgs
        result = Optimization.bfgs(
          composite, point, nil, settings, bounds)
      else
        result = Optimization.lbfgs(
          composite, point, nil, settings, bounds)
      total["iterations"] += result.iterations
      total["function_evaluations"] += result.function_evaluations
      total["gradient_evaluations"] += result.gradient_evaluations
      total["line_search_evaluations"] += result.line_search_evaluations
      total["accepted_steps"] += result.accepted_steps
      total["skipped_updates"] += result.skipped_updates
      total["step_norm"] = result.step_norm
      point = result.parameters
      final_gradient = result.gradient
      outer += 1
      constraint_data = Optimization.constraint_values(constraints, point)
      if !constraint_data["ok"]
        metadata = Optimization.multivariate_metadata(
          method == :bfgs ? :penalty_bfgs : :penalty_lbfgs,
          initial_value)
        metadata["outer_iterations"] = outer
        metadata["penalty"] = penalty
        return Optimization.multivariate_result(
          point, result.value, final_gradient, total, bounds, metadata,
          {"code": constraint_data["code"],
           "message": constraint_data["message"], "reason": nil})
      violation = Optimization.constraint_violation(constraint_data)
      raw = Optimization.evaluate_objective_callback(objective, point)
      total["function_evaluations"] += 1
      if !raw["ok"]
        metadata = Optimization.multivariate_metadata(
          method == :bfgs ? :penalty_bfgs : :penalty_lbfgs,
          initial_value)
        metadata["constraint_violation"] = violation
        metadata["outer_iterations"] = outer
        metadata["penalty"] = penalty
        return Optimization.multivariate_result(
          point, result.value, final_gradient, total, bounds, metadata,
          {"code": raw["code"], "message": raw["message"],
           "reason": nil})
      final_value = raw["value"]
      if violation <= constraints.feasibility_tol && result.converged?
        raw_gradient = Optimization.evaluate_gradient_callback(
          nil, objective, point)
        total["gradient_evaluations"] += 1
        total["function_evaluations"] += raw_gradient[
          "function_evaluations"]
        if !raw_gradient["ok"]
          metadata = Optimization.multivariate_metadata(
            method == :bfgs ? :penalty_bfgs : :penalty_lbfgs,
            initial_value)
          metadata["constraint_violation"] = violation
          metadata["outer_iterations"] = outer
          metadata["penalty"] = penalty
          return Optimization.multivariate_result(
            point, final_value, final_gradient, total, bounds, metadata,
            {"code": raw_gradient["code"],
             "message": raw_gradient["message"], "reason": nil})
        final_gradient = raw_gradient["gradient"]
        metadata = Optimization.multivariate_metadata(
          method == :bfgs ? :penalty_bfgs : :penalty_lbfgs,
          initial_value)
        metadata["constraint_violation"] = violation
        metadata["outer_iterations"] = outer
        metadata["penalty"] = penalty
        return Optimization.multivariate_result(
          point, final_value, final_gradient, total, bounds, metadata,
          {"code": :converged,
           "message": "quadratic-penalty iterate met feasibility_tol",
           "reason": :constraint_feasibility})
      if !result.converged? && result.status_code != :iteration_limit
        metadata = Optimization.multivariate_metadata(
          method == :bfgs ? :penalty_bfgs : :penalty_lbfgs,
          initial_value)
        metadata["constraint_violation"] = violation
        metadata["outer_iterations"] = outer
        metadata["penalty"] = penalty
        return Optimization.multivariate_result(
          point, final_value, final_gradient, total, bounds, metadata,
          {"code": result.status_code, "message": result.message,
           "reason": nil})
      penalty *= constraints.penalty_growth

    final_constraints = Optimization.constraint_values(constraints, point)
    violation = nil
    if final_constraints["ok"]
      violation = Optimization.constraint_violation(final_constraints)
    raw_gradient = Optimization.evaluate_gradient_callback(
      nil, objective, point)
    total["gradient_evaluations"] += 1
    total["function_evaluations"] += raw_gradient[
      "function_evaluations"]
    final_gradient = raw_gradient["gradient"] if raw_gradient["ok"]
    metadata = Optimization.multivariate_metadata(
      method == :bfgs ? :penalty_bfgs : :penalty_lbfgs, initial_value)
    metadata["constraint_violation"] = violation
    metadata["outer_iterations"] = outer
    metadata["penalty"] = penalty
    Optimization.multivariate_result(
      point, final_value, final_gradient, total, bounds, metadata,
      {"code": :constraint_violation,
       "message": "quadratic-penalty outer loop did not reach feasibility_tol",
       "reason": nil})
