# Ordinary and weighted least squares with explicit inferential products.
#
# WLS weights are analytic/relative-precision weights. Zero-weight rows are
# retained in fitted/residual output but do not affect estimation or residual
# degrees of freedom. They are not interpreted as replicated frequency rows.

+ StatisticsLinearModelResult
  -> new(coefficients, fitted_values, residuals, rank,
         residual_degrees_of_freedom, rss, residual_variance,
         r_squared, adjusted_r_squared, classical_covariance,
         hc0_covariance, hc1_covariance, hc2_covariance, hc3_covariance,
         diagnostics)
    @coefficients = Statistics.copy_vector(coefficients)
    @fitted_values = Statistics.copy_vector(fitted_values)
    @residuals = Statistics.copy_vector(residuals)
    @rank = rank
    @residual_degrees_of_freedom = residual_degrees_of_freedom
    @rss = rss
    @residual_variance = residual_variance
    @r_squared = r_squared
    @adjusted_r_squared = adjusted_r_squared
    @classical_covariance = Statistics.copy_matrix(classical_covariance)
    @hc0_covariance = Statistics.copy_matrix(hc0_covariance)
    @hc1_covariance = Statistics.copy_matrix(hc1_covariance)
    @hc2_covariance = hc2_covariance == nil ? nil : Statistics.copy_matrix(hc2_covariance)
    @hc3_covariance = hc3_covariance == nil ? nil : Statistics.copy_matrix(hc3_covariance)
    @diagnostics = diagnostics

  -> coefficients
    Statistics.copy_vector(@coefficients)

  -> fitted_values
    Statistics.copy_vector(@fitted_values)

  -> residuals
    Statistics.copy_vector(@residuals)

  -> rank
    @rank

  -> parameter_count
    @coefficients.size

  -> residual_degrees_of_freedom
    @residual_degrees_of_freedom

  -> df
    @residual_degrees_of_freedom

  -> rss
    @rss

  -> residual_variance
    @residual_variance

  -> r_squared
    @r_squared

  -> adjusted_r_squared
    @adjusted_r_squared

  -> diagnostics
    @diagnostics

  -> status
    @diagnostics.warnings.empty? ? :ok : :ok_with_warnings

  -> successful?
    true

  -> covariance(kind = :classical)
    return Statistics.copy_matrix(@classical_covariance) if kind == :classical
    return Statistics.copy_matrix(@hc0_covariance) if kind == :hc0
    return Statistics.copy_matrix(@hc1_covariance) if kind == :hc1
    if kind == :hc2
      if @hc2_covariance == nil
        raise "HC2 covariance is unavailable because leverage is numerically one"
      return Statistics.copy_matrix(@hc2_covariance)
    if kind == :hc3
      if @hc3_covariance == nil
        raise "HC3 covariance is unavailable because leverage is numerically one"
      return Statistics.copy_matrix(@hc3_covariance)
    raise "unknown regression covariance kind " + kind.to_s

  -> inference_ready!
    if @residual_variance <= ~0.0
      raise "regression inference requires positive residual variance"
    true

  -> standard_errors(kind = :classical)
    inference_ready!
    matrix = covariance(kind)
    errors = []
    index = 0
    while index < parameter_count
      variance = matrix[index][index]
      if variance < ~0.0
        raise "regression coefficient variance became negative"
      errors.push(Math.sqrt(variance))
      index += 1
    errors

  -> t_statistics(kind = :classical)
    errors = standard_errors(kind)
    statistics = []
    index = 0
    while index < parameter_count
      if errors[index] == ~0.0
        raise "regression t statistic is undefined for zero standard error"
      statistics.push(@coefficients[index] / errors[index])
      index += 1
    statistics

  -> p_values(kind = :classical)
    values = []
    t_statistics(kind).each -> (value)
      values.push(StatisticsInference.two_sided_t_p(
        value, @residual_degrees_of_freedom))
    values

  -> confidence_intervals(level = ~0.95, kind = :classical)
    errors = standard_errors(kind)
    critical = StatisticsInference.critical_t(
      level, @residual_degrees_of_freedom)
    intervals = []
    index = 0
    while index < parameter_count
      radius = critical * errors[index]
      intervals.push([
        @coefficients[index] - radius,
        @coefficients[index] + radius])
      index += 1
    intervals

  -> to_s
    text = "StatisticsLinearModelResult(parameters=" + parameter_count.to_s
    text += ", df=" + @residual_degrees_of_freedom.to_s
    text + ", status=" + status.to_s + ")"

  -> inspect
    to_s


+ StatisticsLinearRegression
  -> .scaled_matrix(matrix, factor)
    scaled = LinAlg.zeros(matrix.size, matrix[0].size)
    row = 0
    while row < matrix.size
      column = 0
      while column < matrix[0].size
        scaled[row][column] = matrix[row][column] * factor
        column += 1
      row += 1
    scaled

  -> .symmetric_product(bread, meat)
    product = LinAlg.matmul(LinAlg.matmul(bread, meat), bread)
    dimension = product.size
    row = 0
    while row < dimension
      column = row + 1
      while column < dimension
        average = (product[row][column] + product[column][row]) / ~2.0
        product[row][column] = average
        product[column][row] = average
        column += 1
      row += 1
    product

  -> .meat(design, residuals, weights, leverage, power)
    parameter_count = design[0].size
    meat = LinAlg.zeros(parameter_count, parameter_count)
    row = 0
    while row < design.size
      weight = weights[row]
      if weight > ~0.0
        denominator = ~1.0 - leverage[row]
        adjustment = ~1.0
        if power == 1
          adjustment = ~1.0 / denominator
        else
          adjustment = ~1.0 / (denominator * denominator) if power == 2
        scale = weight * weight * residuals[row] * residuals[row] * adjustment
        left = 0
        while left < parameter_count
          right = 0
          while right < parameter_count
            meat[left][right] += scale * design[row][left] * design[row][right]
            right += 1
          left += 1
      row += 1
    meat

  -> .fit(predictors, response, intercept, weights, tolerance)
    if predictors.empty?
      raise "linear regression requires at least one observation"
    if predictors.size != response.size
      raise "linear regression predictors and response must have equal length"
    weighted = weights != nil
    if weighted && weights.size != predictors.size
      raise "linear regression predictors and weights must have equal length"
    if intercept != true && intercept != false
      raise "linear regression intercept option must be boolean"
    tolerance = Statistics.scalar(tolerance)
    if tolerance <= ~0.0 || tolerance >= ~1.0
      raise "linear regression tolerance must be strictly between zero and one"

    first = predictors[0]
    if first.class_name != "Array"
      raise "linear regression predictors must be rows of real numeric scalars"
    predictor_count = first.size
    parameter_count = predictor_count + (intercept ? 1 : 0)
    if parameter_count == 0
      raise "linear regression requires at least one parameter"

    design = []
    response_values = []
    weight_values = []
    row = 0
    while row < predictors.size
      predictor_row = predictors[row]
      if predictor_row.class_name != "Array" || predictor_row.size != predictor_count
        raise "linear regression predictor rows must have consistent dimensions"
      design_row = []
      design_row.push(~1.0) if intercept
      predictor_row.each -> (value)
        design_row.push(Statistics.scalar(value))
      design.push(design_row)
      response_values.push(Statistics.scalar(response[row]))
      weight_value = weighted ? Statistics.weight(weights[row]) : ~1.0
      weight_values.push(weight_value)
      row += 1

    positive_count = 0
    scaled_design = []
    scaled_response = []
    row = 0
    while row < design.size
      weight = weight_values[row]
      if weight > ~0.0
        positive_count += 1
        root_weight = Math.sqrt(weight)
        scaled_row = []
        design[row].each -> (value)
          scaled_row.push(root_weight * value)
        scaled_design.push(scaled_row)
        scaled_response.push(root_weight * response_values[row])
      row += 1
    if positive_count <= parameter_count
      raise "linear regression requires more positive-weight observations than parameters"

    solution = StatisticsRegressionSolver.solve(
      scaled_design, scaled_response, tolerance)
    coefficients = solution.coefficients
    bread = solution.bread

    fitted = []
    residuals = []
    rss = ~0.0
    response_square_sum = ~0.0
    row = 0
    while row < design.size
      prediction = ~0.0
      column = 0
      while column < parameter_count
        prediction += design[row][column] * coefficients[column]
        column += 1
      fitted.push(Statistics.finite_result(prediction, "linear regression fitted value"))
      residual = response_values[row] - prediction
      residuals.push(residual)
      rss += weight_values[row] * residual * residual
      response_square_sum += (
        weight_values[row] * response_values[row] * response_values[row])
      row += 1
    rss = Statistics.nonnegative_moment(rss, "linear regression residual sum of squares")
    numerical_zero = tolerance * tolerance * (~1.0 + response_square_sum)
    rss = ~0.0 if rss <= numerical_zero
    degrees_of_freedom = positive_count - solution.rank
    residual_variance = rss / (degrees_of_freedom + ~0.0)
    Statistics.finite_result(residual_variance, "linear regression residual variance")

    response_accumulator = Statistics.weighted_accumulator
    row = 0
    while row < response_values.size
      response_accumulator.push(response_values[row], weight_values[row])
      row += 1
    response_mean = response_accumulator.snapshot.mean
    tss = ~0.0
    row = 0
    while row < response_values.size
      baseline = intercept ? response_mean : ~0.0
      difference = response_values[row] - baseline
      tss += weight_values[row] * difference * difference
      row += 1

    warnings = []
    r_squared = nil
    adjusted_r_squared = nil
    if tss == ~0.0
      warnings.push("R-squared is undefined for a constant response")
    else
      r_squared = ~1.0 - rss / tss
      null_degrees = intercept ? positive_count - 1 : positive_count
      adjusted_r_squared = ~1.0 - (
        (rss / (degrees_of_freedom + ~0.0)) /
        (tss / (null_degrees + ~0.0)))

    classical_covariance = StatisticsLinearRegression.scaled_matrix(
      bread, residual_variance)
    leverage = []
    row = 0
    while row < design.size
      value = ~0.0
      left = 0
      while left < parameter_count
        right = 0
        while right < parameter_count
          value += weight_values[row] * design[row][left] * (
            bread[left][right] * design[row][right])
          right += 1
        left += 1
      if value < ~-1.0e-10 || value > ~1.0000000001
        raise "linear regression leverage escaped the valid interval"
      value = ~0.0 if value < ~0.0
      value = ~1.0 if value > ~1.0
      leverage.push(value)
      row += 1

    hc0_meat = StatisticsLinearRegression.meat(
      design, residuals, weight_values, leverage, 0)
    hc0_covariance = StatisticsLinearRegression.symmetric_product(
      bread, hc0_meat)
    hc1_covariance = StatisticsLinearRegression.scaled_matrix(
      hc0_covariance, (positive_count + ~0.0) / (degrees_of_freedom + ~0.0))

    leverage_singular = false
    row = 0
    while row < leverage.size
      if weight_values[row] > ~0.0 && ~1.0 - leverage[row] <= tolerance
        leverage_singular = true
      row += 1
    hc2_covariance = nil
    hc3_covariance = nil
    if leverage_singular
      warnings.push("HC2 and HC3 are unavailable because leverage is numerically one")
    else
      hc2_covariance = StatisticsLinearRegression.symmetric_product(
        bread, StatisticsLinearRegression.meat(
          design, residuals, weight_values, leverage, 1))
      hc3_covariance = StatisticsLinearRegression.symmetric_product(
        bread, StatisticsLinearRegression.meat(
          design, residuals, weight_values, leverage, 2))

    standardized = []
    cooks = []
    if residual_variance == ~0.0
      warnings.push("coefficient inference and residual scaling require positive residual variance")
      row = 0
      while row < design.size
        standardized.push(nil)
        cooks.push(nil)
        row += 1
    else
      row = 0
      while row < design.size
        remaining = ~1.0 - leverage[row]
        if remaining <= tolerance
          standardized.push(nil)
          cooks.push(nil)
        else
          standardized.push(
            Math.sqrt(weight_values[row]) * residuals[row] /
            Math.sqrt(residual_variance * remaining))
          cooks.push(
            weight_values[row] * residuals[row] * residuals[row] /
            ((parameter_count + ~0.0) * residual_variance) *
            leverage[row] / (remaining * remaining))
        row += 1

    diagnostics = StatisticsRegressionDiagnostics.new(
      solution.rank, parameter_count, degrees_of_freedom,
      solution.condition_estimate, solution.permutation, leverage,
      standardized, cooks, warnings, weighted)
    StatisticsLinearModelResult.new(
      coefficients, fitted, residuals, solution.rank, degrees_of_freedom,
      rss, residual_variance, r_squared, adjusted_r_squared,
      classical_covariance, hc0_covariance, hc1_covariance,
      hc2_covariance, hc3_covariance, diagnostics)
