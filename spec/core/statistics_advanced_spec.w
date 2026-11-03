# Weighted, multivariate, and linear-model Statistics foundations.
# Run in both engines:
#   bin/tungsten run --interpret spec/core/statistics_advanced_spec.w
#   bin/tungsten compile spec/core/statistics_advanced_spec.w --out /tmp/statistics-advanced-spec

use statistics

-> statistics_advanced_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> statistics_advanced_close?(left, right, tolerance = ~1.0e-10)
  difference = (left - right).abs
  scale = right.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

statistics_advanced_check("inference.student_t_df1_tail",
                          statistics_advanced_close?(
                            StatisticsInference.two_sided_t_p(~1.0, 1),
                            ~0.5))
statistics_advanced_check("inference.student_t_df1_critical",
                          statistics_advanced_close?(
                            StatisticsInference.critical_t(~0.5, 1),
                            ~1.0))

weighted = Statistics.weighted_summarize(
  [~1.0, ~2.0, ~5.0], [~1.0, ~2.0, ~1.0])
statistics_advanced_check("weighted.count", weighted.count == 3)
statistics_advanced_check("weighted.positive_count",
                          weighted.positive_weight_count == 3)
statistics_advanced_check("weighted.total_weight", weighted.total_weight == ~4.0)
statistics_advanced_check("weighted.squared_weight_sum",
                          weighted.squared_weight_sum == ~6.0)
statistics_advanced_check("weighted.mean", weighted.mean == ~2.5)
statistics_advanced_check("weighted.population_variance",
                          weighted.population_variance == ~2.25)
statistics_advanced_check("weighted.reliability_variance",
                          statistics_advanced_close?(
                            weighted.reliability_variance, ~3.6))
statistics_advanced_check("weighted.frequency_variance",
                          weighted.frequency_variance == ~3.0)
statistics_advanced_check("weighted.effective_sample_size",
                          statistics_advanced_close?(
                            weighted.effective_sample_size, ~8.0 / ~3.0))

zero_weight = Statistics.weighted_summarize(
  [~1.0, ~2.0, ~999.0], [~1.0, ~1.0, ~0.0])
statistics_advanced_check("weighted.zero_weight_count", zero_weight.count == 3)
statistics_advanced_check("weighted.zero_weight_ignored", zero_weight.mean == ~1.5)

weighted_left = Statistics.weighted_accumulator
weighted_left.push(~1.0, ~1.0).push(~2.0, ~2.0)
weighted_right = Statistics.weighted_accumulator
weighted_right.push(~5.0, ~1.0)
weighted_left.merge(weighted_right)
statistics_advanced_check("weighted.merge.mean",
                          weighted_left.snapshot.mean == weighted.mean)
statistics_advanced_check("weighted.merge.variance",
                          statistics_advanced_close?(
                            weighted_left.snapshot.reliability_variance,
                            weighted.reliability_variance))

frequency_failed = false
begin
  Statistics.weighted_summarize(
    [~1.0, ~2.0], [~0.5, ~1.5]).frequency_variance
rescue error
  frequency_failed = error.to_s.include?("integer frequency")
statistics_advanced_check("weighted.frequency_semantics", frequency_failed)

zero_total_failed = false
begin
  Statistics.weighted_mean([~1.0], [~0.0])
rescue error
  zero_total_failed = error.to_s.include?("positive total weight")
statistics_advanced_check("weighted.zero_total_failure", zero_total_failed)

negative_weight_failed = false
begin
  Statistics.weighted_mean([~1.0], [~-1.0])
rescue error
  negative_weight_failed = error.to_s.include?("nonnegative")
statistics_advanced_check("weighted.negative_failure", negative_weight_failed)

rows = [[~1.0, ~2.0], [~2.0, ~4.0], [~3.0, ~8.0]]
multivariate = Statistics.multivariate_summarize(
  rows, [~1.0, ~2.0, ~1.0])
multivariate_mean = multivariate.mean
statistics_advanced_check("multivariate.mean.0", multivariate_mean[0] == ~2.0)
statistics_advanced_check("multivariate.mean.1", multivariate_mean[1] == ~4.5)
scatter = multivariate.scatter_matrix
statistics_advanced_check("multivariate.scatter.00",
                          statistics_advanced_close?(scatter[0][0], ~2.0))
statistics_advanced_check("multivariate.scatter.01",
                          statistics_advanced_close?(scatter[0][1], ~6.0))
statistics_advanced_check("multivariate.scatter.11",
                          statistics_advanced_close?(scatter[1][1], ~19.0))
population_covariance = multivariate.population_covariance
statistics_advanced_check("multivariate.covariance.00",
                          statistics_advanced_close?(
                            population_covariance[0][0], ~0.5))
statistics_advanced_check("multivariate.covariance.01",
                          statistics_advanced_close?(
                            population_covariance[0][1], ~1.5))
statistics_advanced_check("multivariate.covariance.11",
                          statistics_advanced_close?(
                            population_covariance[1][1], ~4.75))
reliability_covariance = multivariate.reliability_covariance
statistics_advanced_check("multivariate.reliability.11",
                          statistics_advanced_close?(
                            reliability_covariance[1][1], ~7.6))
correlation = multivariate.correlation_matrix
statistics_advanced_check("multivariate.correlation.diagonal",
                          correlation[0][0] == ~1.0 &&
                            correlation[1][1] == ~1.0)
statistics_advanced_check("multivariate.correlation.off_diagonal",
                          statistics_advanced_close?(
                            correlation[0][1], ~6.0 / Math.sqrt(~38.0)))

multivariate_mean[0] = ~99.0
statistics_advanced_check("multivariate.defensive_mean",
                          multivariate.mean[0] == ~2.0)

multi_left = Statistics.multivariate_accumulator(2)
multi_left.push(rows[0], ~1.0).push(rows[1], ~2.0)
multi_right = Statistics.multivariate_accumulator(2)
multi_right.push(rows[2], ~1.0)
multi_left.merge(multi_right)
statistics_advanced_check("multivariate.merge",
                          statistics_advanced_close?(
                            multi_left.snapshot.scatter_matrix[1][1], ~19.0))

dimension_failed = false
begin
  Statistics.multivariate_accumulator(2).push([~1.0])
rescue error
  dimension_failed = error.to_s.include?("dimension")
statistics_advanced_check("multivariate.dimension_failure", dimension_failed)

predictors = [[~0.0], [~1.0], [~2.0], [~3.0], [~4.0]]
response = [~1.0, ~3.0, ~5.0, ~7.0, ~10.0]
model = Statistics.linear_regression(predictors, response)
coefficients = model.coefficients
statistics_advanced_check("regression.coefficient.intercept",
                          statistics_advanced_close?(coefficients[0], ~0.8))
statistics_advanced_check("regression.coefficient.slope",
                          statistics_advanced_close?(coefficients[1], ~2.2))
statistics_advanced_check("regression.rank", model.rank == 2)
statistics_advanced_check("regression.df", model.df == 3)
statistics_advanced_check("regression.rss",
                          statistics_advanced_close?(model.rss, ~0.4))
statistics_advanced_check("regression.residual_variance",
                          statistics_advanced_close?(
                            model.residual_variance, ~2.0 / ~15.0))
statistics_advanced_check("regression.r_squared",
                          statistics_advanced_close?(
                            model.r_squared, ~1.0 - ~0.4 / ~48.8))
statistics_advanced_check("regression.status", model.status == :ok)
statistics_advanced_check("regression.successful", model.successful?)

classical = model.covariance
statistics_advanced_check("regression.classical_covariance.00",
                          statistics_advanced_close?(classical[0][0], ~0.08))
statistics_advanced_check("regression.classical_covariance.01",
                          statistics_advanced_close?(
                            classical[0][1], ~-0.02666666666666667))
statistics_advanced_check("regression.classical_covariance.11",
                          statistics_advanced_close?(
                            classical[1][1], ~0.013333333333333334))
errors = model.standard_errors
statistics_advanced_check("regression.standard_error.intercept",
                          statistics_advanced_close?(
                            errors[0], Math.sqrt(~0.08)))
statistics_advanced_check("regression.standard_error.slope",
                          statistics_advanced_close?(
                            errors[1], Math.sqrt(~0.013333333333333334)))

leverage = model.diagnostics.leverage
statistics_advanced_check("regression.leverage.edges",
                          statistics_advanced_close?(leverage[0], ~0.6) &&
                            statistics_advanced_close?(leverage[4], ~0.6))
statistics_advanced_check("regression.leverage.middle",
                          statistics_advanced_close?(leverage[2], ~0.2))
statistics_advanced_check("regression.condition.finite",
                          model.diagnostics.condition_estimate >= ~1.0)

hc0 = model.covariance(:hc0)
hc3 = model.covariance(:hc3)
statistics_advanced_check("regression.hc0.symmetric",
                          statistics_advanced_close?(hc0[0][1], hc0[1][0]))
statistics_advanced_check("regression.hc3.symmetric",
                          statistics_advanced_close?(hc3[0][1], hc3[1][0]))
statistics_advanced_check("regression.hc0.reference",
                          statistics_advanced_close?(hc0[0][0], ~0.0224) &&
                            statistics_advanced_close?(hc0[0][1], ~-0.0112) &&
                            statistics_advanced_close?(hc0[1][1], ~0.0096))
statistics_advanced_check("regression.hc3.reference",
                          statistics_advanced_close?(hc3[0][0], ~0.1325) &&
                            statistics_advanced_close?(hc3[0][1], ~-0.07) &&
                            statistics_advanced_close?(
                              hc3[1][1], ~0.05326530612244898))
statistics_advanced_check("regression.hc.nonnegative_diagonal",
                          hc0[0][0] >= ~0.0 && hc0[1][1] >= ~0.0 &&
                            hc3[0][0] >= ~0.0 && hc3[1][1] >= ~0.0)

p_values = model.p_values
statistics_advanced_check("regression.p_values",
                          p_values.size == 2 &&
                            p_values[0] > ~0.0 && p_values[0] < ~1.0 &&
                            p_values[1] > ~0.0 && p_values[1] < ~1.0)
intervals = model.confidence_intervals
statistics_advanced_check("regression.confidence_interval",
                          intervals[1][0] < coefficients[1] &&
                            intervals[1][1] > coefficients[1])

coefficients[0] = ~100.0
statistics_advanced_check("regression.defensive_coefficients",
                          statistics_advanced_close?(model.coefficients[0], ~0.8))

weighted_model = Statistics.linear_regression(
  [[~0.0], [~1.0], [~2.0], [~3.0]],
  [~1.0, ~3.0, ~100.0, ~7.0], true,
  [~1.0, ~1.0, ~0.0, ~1.0])
statistics_advanced_check("regression.weighted.intercept",
                          statistics_advanced_close?(
                            weighted_model.coefficients[0], ~1.0))
statistics_advanced_check("regression.weighted.slope",
                          statistics_advanced_close?(
                            weighted_model.coefficients[1], ~2.0))
statistics_advanced_check("regression.weighted.diagnostic",
                          weighted_model.diagnostics.weighted?)
statistics_advanced_check("regression.perfect_fit.warning",
                          weighted_model.status == :ok_with_warnings)

perfect_inference_failed = false
begin
  weighted_model.standard_errors
rescue error
  perfect_inference_failed = error.to_s.include?("positive residual variance")
statistics_advanced_check("regression.perfect_fit.inference_failure",
                          perfect_inference_failed)

wls = Statistics.linear_regression(
  predictors, response, true, [~1.0, ~2.0, ~0.5, ~3.0, ~1.0])
statistics_advanced_check("regression.wls.reference.coefficients",
                          statistics_advanced_close?(
                            wls.coefficients[0], ~0.8238341968911922) &&
                            statistics_advanced_close?(
                              wls.coefficients[1], ~2.1450777202072535))
statistics_advanced_check("regression.wls.reference.rss",
                          statistics_advanced_close?(
                            wls.rss, ~0.5958549222797916))
statistics_advanced_check("regression.wls.reference.leverage",
                          statistics_advanced_close?(
                            wls.diagnostics.leverage[0],
                            ~0.4870466321243523) &&
                            statistics_advanced_close?(
                              wls.diagnostics.leverage[3],
                              ~0.5751295336787565))

high_leverage = Statistics.linear_regression(
  [[~0.0], [~0.0], [~1.0]], [~1.0, ~2.0, ~3.0])
statistics_advanced_check("regression.high_leverage.warning",
                          high_leverage.status == :ok_with_warnings)
hc2_failed = false
begin
  high_leverage.covariance(:hc2)
rescue error
  hc2_failed = error.to_s.include?("leverage")
statistics_advanced_check("regression.high_leverage.hc2_failure", hc2_failed)

multiple = Statistics.linear_regression(
  [[~0.0, ~0.0], [~1.0, ~0.0], [~0.0, ~1.0],
   [~1.0, ~1.0], [~2.0, ~-1.0], [~3.0, ~2.0]],
  [~1.1, ~2.9, ~-1.8, ~-0.2, ~8.3, ~0.7])
statistics_advanced_check("regression.multiple.reference",
                          statistics_advanced_close?(
                            multiple.coefficients[0],
                            ~1.1386792452830188) &&
                            statistics_advanced_close?(
                              multiple.coefficients[1],
                              ~1.9448113207547169) &&
                            statistics_advanced_close?(
                              multiple.coefficients[2],
                              ~-3.148584905660377))
statistics_advanced_check("regression.multiple.rss",
                          statistics_advanced_close?(
                            multiple.rss, ~0.11316037735849042))

rank_failed = false
begin
  Statistics.linear_regression(
    [[~1.0, ~2.0], [~2.0, ~4.0], [~3.0, ~6.0], [~4.0, ~8.0]],
    [~1.0, ~2.0, ~3.0, ~4.0])
rescue error
  rank_failed = error.to_s.include?("rank deficient")
statistics_advanced_check("regression.rank_failure", rank_failed)

<< "statistics_advanced_spec: all checks passed"
