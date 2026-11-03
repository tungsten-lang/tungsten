# Dense nonlinear least squares — Gauss-Newton and Levenberg-Marquardt.
# Residuals are m-vectors and Jacobians are m-by-n row-major nested Arrays.

+ OptimizationLeastSquaresCriteria
  -> new(residual_tol = ~1.0e-10, gradient_tol = ~1.0e-10,
         step_tol = ~1.0e-10, max_iterations = 100,
         rank_tolerance = ~1.0e-12, condition_limit = ~1.0e12,
         initial_damping = ~1.0e-3)
    @residual_tol = residual_tol + ~0.0
    @gradient_tol = gradient_tol + ~0.0
    @step_tol = step_tol + ~0.0
    @max_iterations = max_iterations
    @rank_tolerance = rank_tolerance + ~0.0
    @condition_limit = condition_limit + ~0.0
    @initial_damping = initial_damping + ~0.0
    values = [@residual_tol, @gradient_tol, @step_tol,
              @rank_tolerance, @condition_limit, @initial_damping]
    values.each ->
      if !Optimization.finite_value?(item) || item < ~0.0
        raise "least-squares tolerances and damping must be finite and nonnegative"
    if @condition_limit <= ~1.0
      raise "least-squares condition_limit must be greater than one"
    if @rank_tolerance == ~0.0
      raise "least-squares rank_tolerance must be positive"
    if @initial_damping == ~0.0
      raise "least-squares initial_damping must be positive"
    if !Optimization.integer_value?(@max_iterations) || @max_iterations < 0
      raise "least-squares max_iterations must be a nonnegative integer"

  ro :residual_tol, :gradient_tol, :step_tol, :max_iterations, :rank_tolerance
  ro :condition_limit, :initial_damping


+ OptimizationLeastSquaresResult
  -> new(@data)

  -> parameters
    @data["parameters"]
  -> x
    parameters
  -> residuals
    @data["residuals"]
  -> residual
    residuals
  -> residual_norm
    @data["residual_norm"]
  -> objective
    @data["objective"]
  -> value
    objective
  -> minimum
    objective
  -> initial_objective
    @data["initial_objective"]
  -> gradient_norm
    @data["gradient_norm"]
  -> step_norm
    @data["step_norm"]
  -> iterations
    @data["iterations"]
  -> evaluations
    residual_evaluations + jacobian_evaluations
  -> residual_evaluations
    @data["residual_evaluations"]
  -> jacobian_evaluations
    @data["jacobian_evaluations"]
  -> linear_solves
    @data["linear_solves"]
  -> accepted_steps
    @data["accepted_steps"]
  -> rejected_steps
    @data["rejected_steps"]
  -> rank
    @data["rank"]
  -> parameter_count
    parameters.size
  -> residual_count
    residuals.size
  -> condition_estimate
    @data["condition_estimate"]
  -> damping
    @data["damping"]
  -> convergence_reason
    @data["convergence_reason"]
  -> status
    @data["status"]
  -> status_code
    status.code
  -> message
    status.message
  -> method
    @data["method"]
  -> converged?
    status.converged?
  -> success?
    converged?
  -> certified?
    false
  -> inspect
    text = "OptimizationLeastSquaresResult(method=" + method.to_s
    text += ", objective=" + objective.to_s + ", " + status.to_s + ")"
    text
  -> to_s
    inspect


+ Optimization
  -> .least_squares_criteria(value)
    return OptimizationLeastSquaresCriteria.new if value == nil
    if value.class_name != "OptimizationLeastSquaresCriteria"
      raise "least-squares criteria must be an OptimizationLeastSquaresCriteria"
    value

  -> .least_squares_result(parameters, residuals, counters, method,
                            reason, outcome)
    residual_norm = residuals.size == 0 ? nil : (
      Optimization.euclidean_norm(residuals))
    objective = residual_norm == nil ? nil : (
      ~0.5 * residual_norm * residual_norm)
    OptimizationLeastSquaresResult.new({
      "parameters": Optimization.copy_vector(parameters),
      "residuals": Optimization.copy_vector(residuals),
      "residual_norm": residual_norm,
      "objective": objective,
      "initial_objective": counters["initial_objective"],
      "gradient_norm": counters["gradient_norm"],
      "step_norm": counters["step_norm"],
      "iterations": counters["iterations"],
      "residual_evaluations": counters["residual_evaluations"],
      "jacobian_evaluations": counters["jacobian_evaluations"],
      "linear_solves": counters["linear_solves"],
      "accepted_steps": counters["accepted_steps"],
      "rejected_steps": counters["rejected_steps"],
      "rank": counters["rank"],
      "condition_estimate": counters["condition_estimate"],
      "damping": counters["damping"],
      "convergence_reason": reason,
      "method": method,
      "status": Optimization.status(outcome["code"], outcome["message"])
    })

  -> .least_squares_failure(parameters, residuals, counters, method,
                             code, message)
    Optimization.least_squares_result(
      parameters, residuals, counters, method, nil,
      {"code": code, "message": message})

  -> .least_squares_counters(damping = nil)
    {
      "initial_objective": nil,
      "gradient_norm": nil,
      "step_norm": ~0.0,
      "iterations": 0,
      "residual_evaluations": 0,
      "jacobian_evaluations": 0,
      "linear_solves": 0,
      "accepted_steps": 0,
      "rejected_steps": 0,
      "rank": nil,
      "condition_estimate": nil,
      "damping": damping
    }

  -> .evaluate_residual_callback(function, point, expected_size = nil)
    values = nil
    begin
      values = function(Optimization.copy_vector(point))
    rescue error
      return {"ok": false, "code": :callback_error,
              "message": "residual callback failed: " + error.to_s}
    if values.class_name != "Array" || values.size == 0
      return {"ok": false, "code": :invalid_residual,
              "message": "residual callback must return a nonempty Array"}
    if expected_size != nil && values.size != expected_size
      return {"ok": false, "code": :invalid_residual,
              "message": "residual callback changed output size"}
    answer = []
    i = 0
    while i < values.size
      value = nil
      begin
        value = values[i] + ~0.0
      rescue error
        return {"ok": false, "code": :invalid_residual,
                "message": "residual entries must be numeric"}
      if !Optimization.finite_value?(value)
        return {"ok": false, "code": :non_finite_value,
                "message": "residual callback returned a non-finite value"}
      answer.push(value)
      i += 1
    {"ok": true, "values": answer}

  -> .evaluate_jacobian_callback(function, residual_function, point,
                                  residual_count)
    parameters = point.size
    if function != nil
      values = nil
      begin
        values = function(Optimization.copy_vector(point))
      rescue error
        return {"ok": false, "code": :callback_error,
                "message": "Jacobian callback failed: " + error.to_s,
                "residual_evaluations": 0}
      begin
        matrix = Optimization.validate_dense_matrix(
          values, residual_count, parameters, "least-squares Jacobian")
      rescue error
        return {"ok": false, "code": :invalid_jacobian,
                "message": error.to_s, "residual_evaluations": 0}
      return {"ok": true, "matrix": matrix,
              "residual_evaluations": 0}

    columns = []
    residual_evaluations = 0
    parameter = 0
    while parameter < parameters
      h = Optimization.representable_difference_step(point[parameter])
      if h == nil
        return {"ok": false, "code": :precision_limit,
                "message": "finite-difference step is not representable",
                "residual_evaluations": residual_evaluations}
      upper_point = Optimization.copy_vector(point)
      lower_point = Optimization.copy_vector(point)
      upper_point[parameter] += h
      lower_point[parameter] -= h
      upper = Optimization.evaluate_residual_callback(
        residual_function, upper_point, residual_count)
      residual_evaluations += 1
      if !upper["ok"]
        upper["residual_evaluations"] = residual_evaluations
        return upper
      lower = Optimization.evaluate_residual_callback(
        residual_function, lower_point, residual_count)
      residual_evaluations += 1
      if !lower["ok"]
        lower["residual_evaluations"] = residual_evaluations
        return lower
      column = []
      row = 0
      while row < residual_count
        derivative = (
          (upper["values"][row] - lower["values"][row]) / (~2.0 * h))
        if !Optimization.finite_value?(derivative)
          return {"ok": false, "code": :non_finite_value,
                  "message": "finite-difference Jacobian is non-finite",
                  "residual_evaluations": residual_evaluations}
        column.push(derivative)
        row += 1
      columns.push(column)
      parameter += 1
    matrix = Optimization.zero_matrix(residual_count, parameters)
    parameter = 0
    while parameter < parameters
      row = 0
      while row < residual_count
        matrix[row][parameter] = columns[parameter][row]
        row += 1
      parameter += 1
    {"ok": true, "matrix": matrix,
     "residual_evaluations": residual_evaluations}

  -> .least_squares_diagnostic_status(rank, parameter_count,
                                      condition, criteria)
    if rank < parameter_count
      return {"code": :rank_deficient,
              "message": "Jacobian is rank deficient at the requested tolerance"}
    if condition == nil || !Optimization.finite_value?(condition)
      return {"code": :singular_system,
              "message": "Jacobian condition estimate is unavailable"}
    if condition > criteria.condition_limit
      return {"code": :ill_conditioned,
              "message": "Jacobian condition estimate exceeds condition_limit"}
    nil

  -> .least_squares_converged(parameters, residuals, counters, method,
                              reason, message)
    Optimization.least_squares_result(
      parameters, residuals, counters, method, reason,
      {"code": :converged, "message": message})

  -> .least_squares(residual, initial, jacobian = nil, criteria = nil,
                    method = :levenberg_marquardt)
    if method == :gauss_newton
      return Optimization.gauss_newton(
        residual, initial, jacobian, criteria)
    if method == :levenberg_marquardt || method == :lm
      return Optimization.levenberg_marquardt(
        residual, initial, jacobian, criteria)
    raise "least_squares method must be :gauss_newton or :levenberg_marquardt"

  -> .gauss_newton(residual_function, initial, jacobian = nil,
                    criteria = nil)
    settings = Optimization.least_squares_criteria(criteria)
    parameters = Optimization.copy_numeric_vector(
      initial, "least-squares initial parameters")
    counters = Optimization.least_squares_counters
    initial_residual = Optimization.evaluate_residual_callback(
      residual_function, parameters)
    counters["residual_evaluations"] += 1
    if !initial_residual["ok"]
      return Optimization.least_squares_failure(
        parameters, [], counters, :gauss_newton,
        initial_residual["code"], initial_residual["message"])
    residuals = initial_residual["values"]
    if residuals.size < parameters.size
      return Optimization.least_squares_failure(
        parameters, residuals, counters, :gauss_newton,
        :underdetermined,
        "Gauss-Newton needs at least as many residuals as parameters")
    norm = Optimization.euclidean_norm(residuals)
    objective = ~0.5 * norm * norm
    if !Optimization.finite_value?(objective)
      return Optimization.least_squares_failure(
        parameters, residuals, counters, :gauss_newton,
        :non_finite_value, "least-squares objective overflowed binary64")
    counters["initial_objective"] = objective

    while true
      jacobian_result = Optimization.evaluate_jacobian_callback(
        jacobian, residual_function, parameters, residuals.size)
      counters["jacobian_evaluations"] += 1
      counters["residual_evaluations"] += jacobian_result[
        "residual_evaluations"]
      if !jacobian_result["ok"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          jacobian_result["code"], jacobian_result["message"])
      matrix = jacobian_result["matrix"]
      right_hand_side = []
      residuals.each -> right_hand_side.push(~0.0 - item)
      qr = Optimization.pivoted_qr_least_squares(
        matrix, right_hand_side, settings.rank_tolerance)
      if !qr["finite"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          :non_finite_value,
          "pivoted QR overflowed or produced a non-finite value")
      counters["rank"] = qr["rank"]
      counters["condition_estimate"] = qr["condition_estimate"]
      gradient = Optimization.transpose_matrix_vector(matrix, residuals)
      if !Optimization.finite_vector?(gradient)
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          :non_finite_value,
          "J' residual produced a non-finite value")
      counters["gradient_norm"] = Optimization.infinity_norm(gradient)
      diagnostic = Optimization.least_squares_diagnostic_status(
        counters["rank"], parameters.size,
        counters["condition_estimate"], settings)
      if diagnostic != nil
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          diagnostic["code"], diagnostic["message"])
      if norm <= settings.residual_tol
        return Optimization.least_squares_converged(
          parameters, residuals, counters, :gauss_newton, :residual,
          "residual norm met residual_tol")
      if counters["gradient_norm"] <= settings.gradient_tol
        return Optimization.least_squares_converged(
          parameters, residuals, counters, :gauss_newton, :gradient,
          "J' residual infinity norm met gradient_tol")
      if counters["iterations"] >= settings.max_iterations
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          :iteration_limit, "Gauss-Newton reached max_iterations")
      step = qr["solution"]
      counters["linear_solves"] += 1
      counters["step_norm"] = Optimization.euclidean_norm(step)
      scale = settings.step_tol + Optimization.euclidean_norm(parameters)
      if counters["step_norm"] <= settings.step_tol * scale
        return Optimization.least_squares_converged(
          parameters, residuals, counters, :gauss_newton, :step,
          "Gauss-Newton step met step_tol")
      candidate = []
      i = 0
      while i < parameters.size
        candidate.push(parameters[i] + step[i])
        i += 1
      next_residual = Optimization.evaluate_residual_callback(
        residual_function, candidate, residuals.size)
      counters["residual_evaluations"] += 1
      counters["iterations"] += 1
      if !next_residual["ok"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          next_residual["code"], next_residual["message"])
      parameters = candidate
      residuals = next_residual["values"]
      norm = Optimization.euclidean_norm(residuals)
      objective = ~0.5 * norm * norm
      if !Optimization.finite_value?(objective)
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :gauss_newton,
          :non_finite_value, "least-squares objective overflowed binary64")
      counters["accepted_steps"] += 1

  -> .levenberg_marquardt(residual_function, initial, jacobian = nil,
                           criteria = nil)
    settings = Optimization.least_squares_criteria(criteria)
    parameters = Optimization.copy_numeric_vector(
      initial, "least-squares initial parameters")
    damping = settings.initial_damping
    counters = Optimization.least_squares_counters(damping)
    initial_residual = Optimization.evaluate_residual_callback(
      residual_function, parameters)
    counters["residual_evaluations"] += 1
    if !initial_residual["ok"]
      return Optimization.least_squares_failure(
        parameters, [], counters, :levenberg_marquardt,
        initial_residual["code"], initial_residual["message"])
    residuals = initial_residual["values"]
    if residuals.size < parameters.size
      return Optimization.least_squares_failure(
        parameters, residuals, counters, :levenberg_marquardt,
        :underdetermined,
        "Levenberg-Marquardt needs at least as many residuals as parameters")
    norm = Optimization.euclidean_norm(residuals)
    objective = ~0.5 * norm * norm
    if !Optimization.finite_value?(objective)
      return Optimization.least_squares_failure(
        parameters, residuals, counters, :levenberg_marquardt,
        :non_finite_value, "least-squares objective overflowed binary64")
    counters["initial_objective"] = objective

    while true
      jacobian_result = Optimization.evaluate_jacobian_callback(
        jacobian, residual_function, parameters, residuals.size)
      counters["jacobian_evaluations"] += 1
      counters["residual_evaluations"] += jacobian_result[
        "residual_evaluations"]
      if !jacobian_result["ok"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          jacobian_result["code"], jacobian_result["message"])
      matrix = jacobian_result["matrix"]
      diagnostic_qr = Optimization.pivoted_qr_least_squares(
        matrix, residuals, settings.rank_tolerance)
      if !diagnostic_qr["finite"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :non_finite_value,
          "pivoted QR overflowed or produced a non-finite value")
      counters["rank"] = diagnostic_qr["rank"]
      counters["condition_estimate"] = diagnostic_qr[
        "condition_estimate"]
      gradient = Optimization.transpose_matrix_vector(matrix, residuals)
      if !Optimization.finite_vector?(gradient)
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :non_finite_value,
          "J' residual produced a non-finite value")
      counters["gradient_norm"] = Optimization.infinity_norm(gradient)
      diagnostic = Optimization.least_squares_diagnostic_status(
        counters["rank"], parameters.size,
        counters["condition_estimate"], settings)
      convergence_reason = nil
      convergence_message = nil
      if norm <= settings.residual_tol
        convergence_reason = :residual
        convergence_message = "residual norm met residual_tol"
      elsif counters["gradient_norm"] <= settings.gradient_tol
        convergence_reason = :gradient
        convergence_message = "J' residual infinity norm met gradient_tol"
      if convergence_reason != nil
        if diagnostic != nil
          return Optimization.least_squares_failure(
            parameters, residuals, counters, :levenberg_marquardt,
            diagnostic["code"], diagnostic["message"])
        return Optimization.least_squares_converged(
          parameters, residuals, counters, :levenberg_marquardt,
          convergence_reason, convergence_message)
      if counters["iterations"] >= settings.max_iterations
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :iteration_limit,
          "Levenberg-Marquardt reached max_iterations")

      augmented = Optimization.augmented_lm_system(
        matrix, residuals, damping)
      qr = Optimization.pivoted_qr_least_squares(
        augmented["matrix"], augmented["rhs"],
        settings.rank_tolerance)
      counters["linear_solves"] += 1
      if !qr["finite"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :non_finite_value,
          "damped pivoted QR produced a non-finite value")
      if qr["rank"] < parameters.size || qr["solution"] == nil
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :singular_system,
          "damped least-squares system could not be solved")
      step = qr["solution"]
      counters["step_norm"] = Optimization.euclidean_norm(step)
      candidate = []
      i = 0
      while i < parameters.size
        candidate.push(parameters[i] + step[i])
        i += 1
      next_residual = Optimization.evaluate_residual_callback(
        residual_function, candidate, residuals.size)
      counters["residual_evaluations"] += 1
      counters["iterations"] += 1
      if !next_residual["ok"]
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          next_residual["code"], next_residual["message"])
      candidate_residuals = next_residual["values"]
      candidate_norm = Optimization.euclidean_norm(candidate_residuals)
      candidate_objective = ~0.5 * candidate_norm * candidate_norm
      if !Optimization.finite_value?(candidate_objective)
        return Optimization.least_squares_failure(
          parameters, residuals, counters, :levenberg_marquardt,
          :non_finite_value,
          "least-squares candidate objective overflowed binary64")
      j_step = Optimization.matrix_vector(matrix, step)
      predicted = ~0.0 - Optimization.dot(gradient, step)
      predicted -= ~0.5 * Optimization.dot(j_step, j_step)
      actual = objective - candidate_objective
      ratio = predicted > ~0.0 ? actual / predicted : ~0.0
      if actual > ~0.0
        parameters = candidate
        residuals = candidate_residuals
        norm = candidate_norm
        objective = candidate_objective
        counters["accepted_steps"] += 1
        if ratio > ~0.75
          damping *= ~0.3333333333333333
        elsif ratio < ~0.25
          damping *= ~2.0
        damping = ~1.0e-30 if damping < ~1.0e-30
        counters["damping"] = damping
        scale = settings.step_tol + Optimization.euclidean_norm(parameters)
        if counters["step_norm"] <= settings.step_tol * scale
          if diagnostic != nil
            return Optimization.least_squares_failure(
              parameters, residuals, counters, :levenberg_marquardt,
              diagnostic["code"], diagnostic["message"])
          return Optimization.least_squares_converged(
            parameters, residuals, counters, :levenberg_marquardt,
            :step, "accepted LM step met step_tol")
      else
        counters["rejected_steps"] += 1
        damping *= ~10.0
        counters["damping"] = damping
        if !Optimization.finite_value?(damping) || damping > ~1.0e30
          return Optimization.least_squares_failure(
            parameters, residuals, counters, :levenberg_marquardt,
            :damping_limit,
            "LM damping exceeded the supported binary64 range")
