# Immutable regression diagnostics. Arrays are copied on construction and read.

+ StatisticsRegressionDiagnostics
  -> new(rank, parameter_count, residual_degrees_of_freedom,
         condition_estimate, permutation, leverage,
         standardized_residuals, cooks_distance, warnings, weighted)
    @rank = rank
    @parameter_count = parameter_count
    @residual_degrees_of_freedom = residual_degrees_of_freedom
    @condition_estimate = condition_estimate
    @permutation = StatisticsRegressionDiagnostics.copy_values(permutation)
    @leverage = StatisticsRegressionDiagnostics.copy_values(leverage)
    @standardized_residuals = StatisticsRegressionDiagnostics.copy_values(
      standardized_residuals)
    @cooks_distance = StatisticsRegressionDiagnostics.copy_values(cooks_distance)
    @warnings = StatisticsRegressionDiagnostics.copy_values(warnings)
    @weighted = weighted

  -> .copy_values(values)
    copy = []
    values.each -> (value)
      copy.push(value)
    copy

  -> rank
    @rank

  -> parameter_count
    @parameter_count

  -> residual_degrees_of_freedom
    @residual_degrees_of_freedom

  -> condition_estimate
    @condition_estimate

  -> permutation
    StatisticsRegressionDiagnostics.copy_values(@permutation)

  -> leverage
    StatisticsRegressionDiagnostics.copy_values(@leverage)

  -> standardized_residuals
    StatisticsRegressionDiagnostics.copy_values(@standardized_residuals)

  -> cooks_distance
    StatisticsRegressionDiagnostics.copy_values(@cooks_distance)

  -> warnings
    StatisticsRegressionDiagnostics.copy_values(@warnings)

  -> weighted?
    @weighted

  -> max_leverage
    maximum = ~0.0
    @leverage.each -> (value)
      maximum = value if value > maximum
    maximum

  -> max_cooks_distance
    maximum = ~0.0
    found = false
    @cooks_distance.each -> (value)
      if value != nil
        maximum = value if value > maximum
        found = true
    return nil if !found
    maximum

  -> to_s
    text = "StatisticsRegressionDiagnostics(rank=" + @rank.to_s
    text += ", df=" + @residual_degrees_of_freedom.to_s
    text + ", condition_estimate=" + @condition_estimate.to_s + ")"

  -> inspect
    to_s
