# Cheap subsampling interval postprocessing after Ohlendorff et al. (2025).
#
# Probability owns RNGs and uniform subset generation.  This deterministic
# Statistics kernel consumes scalar estimates from independent size-m subsets
# sampled without replacement and makes the inferential acknowledgement explicit.

+ StatisticsCheapSubsamplingResult
  -> new(estimate, lower, upper, subsample_deviation, finite_population_scale,
         standard_error, critical_value, sample_size, subsample_size,
         replicate_count, level, status, assumptions, warnings)
    @estimate = estimate
    @lower = lower
    @upper = upper
    @subsample_deviation = subsample_deviation
    @finite_population_scale = finite_population_scale
    @standard_error = standard_error
    @critical_value = critical_value
    @sample_size = sample_size
    @subsample_size = subsample_size
    @replicate_count = replicate_count
    @level = level
    @status = status
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  ro :estimate, :lower, :upper, :subsample_deviation, :finite_population_scale
  ro :standard_error, :critical_value, :sample_size, :subsample_size
  ro :replicate_count, :level, :status

  -> degrees_of_freedom
    @replicate_count

  -> numerically_degenerate?
    @status == :degenerate

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsResampling
  -> .root_mean_square_deviation(center, values, operation)
    scale = ~0.0
    sum_squares = ~1.0
    nonzero = false
    values.each -> (value)
      difference = Statistics.finite_result(value - center, operation)
      magnitude = difference.abs
      if magnitude > ~0.0
        nonzero = true
        if scale < magnitude
          ratio = scale / magnitude
          sum_squares = ~1.0 + sum_squares * ratio * ratio
          scale = magnitude
        else
          ratio = magnitude / scale
          sum_squares += ratio * ratio
    return ~0.0 if !nonzero
    rms = scale * Math.sqrt(sum_squares / (values.size + ~0.0))
    Statistics.finite_result(rms, operation)

  -> .cheap_subsampling_interval(point_estimate, subsample_estimates,
                                 sample_size, subsample_size, level,
                                 assumption_acknowledgement)
    if assumption_acknowledgement != :asymptotically_linear_iid
      raise "cheap subsampling requires :asymptotically_linear_iid acknowledgement"
    estimate = Statistics.scalar(point_estimate)
    replicates = Statistics.finite_values(
      subsample_estimates, "cheap subsampling interval")
    n = Statistics.positive_integer(sample_size, "cheap subsampling sample size")
    m = Statistics.positive_integer(
      subsample_size, "cheap subsampling subsample size")
    if m >= n
      raise "cheap subsampling requires subsample size smaller than sample size"
    confidence = Statistics.open_probability(
      level, "cheap subsampling confidence level")
    b = replicates.size

    deviation = StatisticsResampling.root_mean_square_deviation(
      estimate, replicates, "cheap subsampling deviation")
    scale = Math.sqrt((m + ~0.0) / (n - m + ~0.0))
    standard_error = Statistics.finite_result(
      deviation * scale, "cheap subsampling standard error")
    critical = StatisticsInference.critical_t(confidence, b)
    half_width = Statistics.finite_result(
      critical * standard_error, "cheap subsampling interval width")
    lower = Statistics.finite_result(
      estimate - half_width, "cheap subsampling lower endpoint")
    upper = Statistics.finite_result(
      estimate + half_width, "cheap subsampling upper endpoint")

    warnings = [
      "IID/asymptotic-linearity and subset-generation assumptions are acknowledged, not verified"]
    if b < 25
      warnings.push(
        "fewer than 25 replicates can have substantial Monte Carlo variability")
    status = :ok_with_warnings
    if standard_error == ~0.0
      warnings.push(
        "zero subsample deviation is degenerate; nominal coverage is unsupported")
      status = :degenerate
    assumptions = [:iid, :asymptotically_linear_scalar_estimator,
                   :independent_subsets_without_replacement,
                   :subsample_fraction_bounded_away_from_one]
    StatisticsCheapSubsamplingResult.new(
      estimate, lower, upper, deviation, scale, standard_error, critical,
      n, m, b, confidence, status, assumptions, warnings)

  -> .cheap_subsampling_from_indices(values, estimator, subset_indices,
                                     level, assumption_acknowledgement)
    if assumption_acknowledgement != :asymptotically_linear_iid
      raise "cheap subsampling requires :asymptotically_linear_iid acknowledgement"
    full_values = Statistics.copy_values(values)
    if full_values.size < 2
      raise "cheap subsampling requires at least two full-sample observations"
    if subset_indices.empty?
      raise "cheap subsampling requires at least one subset"

    subsample_size = nil
    estimates = []
    subset_number = 0
    subset_indices.each -> (indices)
      if indices.empty?
        raise "cheap subsampling subsets must not be empty"
      subsample_size = indices.size if subsample_size == nil
      if indices.size != subsample_size
        raise "cheap subsampling subsets must have equal size"
      if indices.size >= full_values.size
        raise "cheap subsampling subset size must be smaller than sample size"

      seen = []
      subset = []
      indices.each -> (index)
        if !Statistics.integer?(index)
          raise "cheap subsampling subset indices must be integers"
        if index < 0 || index >= full_values.size
          raise "cheap subsampling subset index is out of range"
        if seen.include?(index)
          raise "cheap subsampling subsets must not repeat an index"
        seen.push(index)
        subset.push(full_values[index])
      begin
        estimate = Statistics.scalar(estimator.call(subset))
      rescue error
        raise "cheap subsampling estimator failed for subset " + (
          subset_number.to_s) + ": " + error.to_s
      estimates.push(estimate)
      subset_number += 1

    begin
      point_estimate = Statistics.scalar(estimator.call(full_values))
    rescue error
      raise "cheap subsampling estimator failed for full sample: " + error.to_s
    StatisticsResampling.cheap_subsampling_interval(
      point_estimate, estimates, full_values.size, subsample_size, level,
      assumption_acknowledgement)
