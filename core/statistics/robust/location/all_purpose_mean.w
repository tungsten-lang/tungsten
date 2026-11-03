# Scalar all-purpose robust mean estimation after Lee et al. (ICML 2025).
#
# This is a point estimator, not a confidence interval.  The contamination,
# low-moment, and sub-Gaussian claims depend on the paper's IID assumptions and
# initializer conditions; the result records rather than verifies them.

+ StatisticsRobustMeanResult
  -> new(estimate, initial_estimate, influence_parameter,
         scaled_influence_parameter, equation_target, equation_residual,
         group_count, iterations, status, assumptions, warnings)
    @estimate = estimate
    @initial_estimate = initial_estimate
    @influence_parameter = influence_parameter
    @scaled_influence_parameter = scaled_influence_parameter
    @equation_target = equation_target
    @equation_residual = equation_residual
    @group_count = group_count
    @iterations = iterations
    @status = status
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  ro :estimate, :initial_estimate, :influence_parameter
  ro :scaled_influence_parameter, :equation_target, :equation_residual
  ro :group_count, :iterations, :status

  -> converged?
    @status == :ok || @status == :ok_with_warnings || (
      @status == :exact_constant)

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsRobustMean
  -> .clipped_quadratic(beta, ratio)
    return ~0.0 if beta == ~0.0 || ratio == ~0.0
    threshold = ~1.0 / Math.sqrt(beta)
    return ~1.0 if ratio >= threshold
    beta * ratio * ratio

  -> .equation(beta, ratios)
    accumulator = Statistics.accumulator
    ratios.each -> (ratio)
      accumulator.push(StatisticsRobustMean.clipped_quadratic(beta, ratio))
    accumulator.sum

  -> .estimate(values, failure_probability, max_iterations, root_tolerance)
    sample = Statistics.finite_values(values, "all-purpose mean")
    delta = Statistics.open_probability(
      failure_probability, "all-purpose mean failure probability")
    Statistics.positive_integer(
      max_iterations, "all-purpose mean maximum iterations")
    tolerance = Statistics.positive_scalar(
      root_tolerance, "all-purpose mean root tolerance")

    log_inverse_delta = ~0.0 - Math.log(delta)
    group_count = Math.ceil(log_inverse_delta).to_i
    group_count = 1 if group_count < 1
    if group_count > sample.size
      raise "all-purpose mean requires at least ceil(log(1/delta)) observations"

    group_means = []
    group = 0
    while group < group_count
      start_index = Math.floor(
        (group + ~0.0) * sample.size / (group_count + ~0.0)).to_i
      stop_index = Math.floor(
        (group + 1 + ~0.0) * sample.size / (group_count + ~0.0)).to_i
      block = []
      index = start_index
      while index < stop_index
        block.push(sample[index])
        index += 1
      group_means.push(Statistics.mean(block))
      group += 1
    initial = Statistics.median(group_means)

    deviations = []
    scale = ~0.0
    sample.each -> (value)
      deviation = Statistics.finite_result(
        value - initial, "all-purpose mean deviation")
      deviations.push(deviation)
      magnitude = deviation.abs
      scale = magnitude if magnitude > scale

    assumptions = [:iid, :finite_variance_for_subgaussian_claim,
                   :ordering_independent_of_values,
                   :paper_initializer_conditions]
    warnings = [
      "paper assumptions are caller responsibilities; this result is a point estimate"]

    if scale == ~0.0
      return StatisticsRobustMeanResult.new(
        initial, initial, ~0.0, ~0.0, ~0.0, ~0.0, group_count, 0,
        :exact_constant, assumptions, warnings)

    ratios = []
    deviations.each -> (deviation)
      ratios.push(deviation.abs / scale)

    target = log_inverse_delta / ~3.0
    representable_nonzero = 0
    ratios.each -> (ratio)
      representable_nonzero += 1 if ratio > ~0.0
    if target >= representable_nonzero + ~0.0
      raise "all-purpose mean influence equation has no finite representable root"

    lower = ~0.0
    upper = ~1.0
    while StatisticsRobustMean.equation(upper, ratios) < target
      upper *= ~2.0
      if upper.infinite? || upper > ~1.0e300
        raise "all-purpose mean influence root is outside the finite search range"

    iterations = 0
    achieved = StatisticsRobustMean.equation(upper, ratios)
    residual = (achieved - target).abs
    while iterations < max_iterations && residual > tolerance * (~1.0 + target)
      middle = (lower + upper) / ~2.0
      achieved = StatisticsRobustMean.equation(middle, ratios)
      if achieved < target
        lower = middle
      else
        upper = middle
      residual = (achieved - target).abs
      iterations += 1

    beta = (lower + upper) / ~2.0
    achieved = StatisticsRobustMean.equation(beta, ratios)
    residual = (achieved - target).abs
    if residual > tolerance * (~1.0 + target)
      raise "all-purpose mean influence root did not converge"

    adjusted = []
    index = 0
    while index < deviations.size
      clipped = StatisticsRobustMean.clipped_quadratic(beta, ratios[index])
      adjusted.push(deviations[index] * (~1.0 - clipped))
      index += 1
    estimate = Statistics.finite_result(
      initial + Statistics.mean(adjusted), "all-purpose mean")

    alpha = beta / scale / scale
    if alpha == ~0.0 || alpha.nan? || alpha.infinite?
      alpha = nil
      warnings.push(
        "unscaled influence parameter is not representable; scaled value remains valid")

    StatisticsRobustMeanResult.new(
      estimate, initial, alpha, beta, target, residual, group_count,
      iterations, :ok_with_warnings, assumptions, warnings)
