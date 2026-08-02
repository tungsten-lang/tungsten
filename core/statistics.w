# Statistics — numerically responsible statistical estimation and inference.
#
# This is a focused foundation rather than an attempt to cover all statistics.
# It accepts finite real scalar observations, exposes mergeable estimators,
# and makes weighting and inferential assumptions explicit. Probability owns
# distributions, random sampling, and stochastic processes; Statistics only
# consumes stable numerical integration points needed for inference.

use core/math
use core/measurement
use core/special
use core/linalg
use core/statistics/univariate
use core/statistics/bivariate
use core/statistics/estimation/weighted
use core/statistics/estimation/multivariate
use core/statistics/inference/student_t
use core/statistics/regression/solver
use core/statistics/regression/diagnostics
use core/statistics/regression/linear_model

+ Statistics
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt" || (
      name == "Int4") || name == "Int4U" || name == "Int8" || (
      name == "Int8U") || name == "Int16" || name == "Int16U" || (
      name == "Int32") || name == "Int32U" || name == "Int48" || (
      name == "Int64") || name == "Int64U" || name == "Int128" || (
      name == "Int128U")

  -> .real_scalar?(value)
    return true if Statistics.integer?(value)
    name = value.class_name
    name == "Float" || name == "BF16" || name == "Float16" || (
      name == "Float32") || name == "Float64" || name == "Float80" || (
      name == "Float128") || name == "Float256" || name == "Rational" || (
      name == "Decimal") || name == "Decimal32" || name == "Decimal64" || (
      name == "Decimal128")

  # Convert supported real scalar values to the Float arithmetic used by the
  # numerical algorithms. `+ 0.0` is intentional: compiled Int#to_f does not
  # yet reliably cross the boxed intrinsic boundary.
  -> .scalar(value)
    if !Statistics.real_scalar?(value)
      raise "statistics observations must be real numeric scalars; got " + value.class_name
    numeric = value + ~0.0
    # `nan?` and `infinite?` are the cross-engine IEEE classification leaves;
    # the abstract `finite?` declaration is not yet wired in compiled code.
    if numeric.nan? || numeric.infinite?
      raise "statistics observations must be finite"
    numeric

  -> .validate_correction(correction, count, operation)
    if !Statistics.integer?(correction) || correction < 0
      raise operation + " correction must be a nonnegative integer"
    if count <= correction
      raise operation + " requires count greater than correction"
    correction

  -> .finite_result(value, operation)
    if value.nan? || value.infinite?
      raise operation + " exceeded the finite floating-point range"
    value

  -> .nonnegative_moment(value, operation)
    Statistics.finite_result(value, operation)
    if value < ~0.0
      raise operation + " became negative through floating-point loss"
    value

  -> .weight(value)
    weight = Statistics.scalar(value)
    if weight < ~0.0
      raise "statistics weights must be nonnegative"
    weight

  -> .copy_vector(values)
    copy = []
    values.each -> (value)
      copy.push(value + ~0.0)
    copy

  -> .copy_matrix(matrix)
    LinAlg.copy_mat(matrix)

  # One Neumaier compensated-summation update, returned as [sum, correction].
  -> .compensated_add(sum, compensation, value)
    next_sum = sum + value
    if sum.abs >= value.abs
      compensation += (sum - next_sum) + value
    else
      compensation += (value - next_sum) + sum
    [next_sum, compensation]

  -> .accumulator
    StatisticsAccumulator.new

  -> .bivariate_accumulator
    StatisticsBivariateAccumulator.new

  -> .weighted_accumulator
    StatisticsWeightedAccumulator.new

  -> .multivariate_accumulator(dimension)
    StatisticsMultivariateAccumulator.new(dimension)

  -> .summarize(values)
    accumulator = Statistics.accumulator
    values.each -> (value)
      accumulator.push(value)
    accumulator.snapshot

  -> .sum(values)
    Statistics.summarize(values).sum

  -> .mean(values)
    Statistics.summarize(values).mean

  -> .variance(values, correction = 1)
    Statistics.summarize(values).variance(correction)

  -> .population_variance(values)
    Statistics.variance(values, 0)

  -> .sample_variance(values)
    Statistics.variance(values, 1)

  -> .standard_deviation(values, correction = 1)
    Statistics.summarize(values).standard_deviation(correction)

  -> .population_standard_deviation(values)
    Statistics.standard_deviation(values, 0)

  -> .sample_standard_deviation(values)
    Statistics.standard_deviation(values, 1)

  -> .standard_error(values)
    Statistics.summarize(values).standard_error

  # Standard uncertainty is the standard error of the sample mean. This is an
  # IID finite-variance estimate, not propagation of instrument uncertainty.
  -> .mean_measurement(values)
    Statistics.summarize(values).mean_measurement

  # Hyndman-Fan type 7 quantile (the common linear interpolation convention).
  -> .quantile(values, probability)
    p = Statistics.scalar(probability)
    if p < ~0.0 || p > ~1.0
      raise "quantile probability must be between 0 and 1"

    sorted = []
    values.each -> (value)
      sorted.push(Statistics.scalar(value))
    if sorted.empty?
      raise "quantile requires at least one observation"
    sorted = sorted.sort

    n = sorted.size
    return sorted[0] if n == 1 || p == ~0.0
    return sorted[n - 1] if p == ~1.0

    rank = p * (n - 1 + ~0.0)
    lower = Math.floor(rank).to_i
    upper = Math.ceil(rank).to_i
    return sorted[lower] if lower == upper
    weight = rank - lower
    interpolated = (~1.0 - weight) * sorted[lower] + weight * sorted[upper]
    Statistics.finite_result(interpolated, "quantile")

  -> .median(values)
    Statistics.quantile(values, ~0.5)

  -> .summarize_pairs(xs, ys)
    size = xs.size
    if size != ys.size
      raise "paired statistics require equal-length inputs"
    accumulator = Statistics.bivariate_accumulator
    i = 0
    while i < size
      accumulator.push(xs[i], ys[i])
      i += 1
    accumulator.snapshot

  -> .covariance(xs, ys, correction = 1)
    Statistics.summarize_pairs(xs, ys).covariance(correction)

  -> .population_covariance(xs, ys)
    Statistics.covariance(xs, ys, 0)

  -> .sample_covariance(xs, ys)
    Statistics.covariance(xs, ys, 1)

  -> .correlation(xs, ys)
    Statistics.summarize_pairs(xs, ys).correlation

  -> .weighted_summarize(values, weights)
    if values.size != weights.size
      raise "weighted statistics require equal-length values and weights"
    accumulator = Statistics.weighted_accumulator
    i = 0
    while i < values.size
      accumulator.push(values[i], weights[i])
      i += 1
    accumulator.snapshot

  -> .weighted_mean(values, weights)
    Statistics.weighted_summarize(values, weights).mean

  -> .weighted_population_variance(values, weights)
    Statistics.weighted_summarize(values, weights).population_variance

  -> .weighted_reliability_variance(values, weights)
    Statistics.weighted_summarize(values, weights).reliability_variance

  -> .weighted_frequency_variance(values, weights)
    Statistics.weighted_summarize(values, weights).frequency_variance

  -> .multivariate_summarize(rows, weights = nil)
    if rows.empty?
      raise "multivariate statistics require at least one observation"
    accumulator = Statistics.multivariate_accumulator(rows[0].size)
    if weights == nil
      rows.each -> (row)
        accumulator.push(row)
    else
      if rows.size != weights.size
        raise "multivariate statistics require equal-length rows and weights"
      i = 0
      while i < rows.size
        accumulator.push(rows[i], weights[i])
        i += 1
    accumulator.snapshot

  -> .linear_regression(predictors, response, intercept = true,
                        weights = nil, tolerance = ~1.0e-12)
    StatisticsLinearRegression.fit(
      predictors, response, intercept, weights, tolerance)
