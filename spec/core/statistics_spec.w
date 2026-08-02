# Numerically responsible descriptive-statistics and streaming regressions.
# Run in both engines:
#   bin/tungsten run spec/core/statistics_spec.w
#   bin/tungsten compile spec/core/statistics_spec.w --out /tmp/statistics-spec

use statistics

-> statistics_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> statistics_close?(left, right, tolerance = ~1.0e-12)
  difference = (left - right).abs
  scale = right.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

# Neumaier compensation preserves the small residual in severe cancellation.
cancelling = [~1.0e16, ~1.0, ~-1.0e16]
statistics_check("sum.compensated", Statistics.sum(cancelling) == ~1.0)
statistics_check("mean.compensated",
                 statistics_close?(Statistics.mean(cancelling), ~1.0 / ~3.0))
statistics_check("sum.empty", Statistics.sum([]) == ~0.0)
statistics_check("mean.rational",
                 Statistics.mean([Rational.new(1, 2), Rational.new(3, 2)]) ==
                   ~1.0)

summary = Statistics.summarize([1, 2, 3, 4, 5])
statistics_check("summary.count", summary.count == 5)
statistics_check("summary.sum", summary.sum == ~15.0)
statistics_check("summary.mean", summary.mean == ~3.0)
statistics_check("summary.minimum", summary.minimum == ~1.0)
statistics_check("summary.maximum", summary.maximum == ~5.0)
statistics_check("summary.range", summary.range == ~4.0)
statistics_check("variance.population", summary.population_variance == ~2.0)
statistics_check("variance.sample", summary.sample_variance == ~2.5)
statistics_check("std.sample",
                 statistics_close?(summary.sample_standard_deviation,
                                   Math.sqrt(~2.5)))
statistics_check("standard_error",
                 statistics_close?(summary.standard_error,
                                   Math.sqrt(~0.5)))

# Welford moments retain variance at a large offset where x*x - mean*mean is
# unusable due to cancellation.
offset = [~1.0e14, ~1.00000000000001e14, ~1.00000000000002e14,
          ~1.00000000000003e14, ~1.00000000000004e14]
statistics_check("variance.large_offset",
                 Statistics.sample_variance(offset) == ~2.5)

left = Statistics.accumulator
left.push(1).push(2)
right = Statistics.accumulator
right.push(3).push(4)
left.merge(right)
merged = left.snapshot
statistics_check("merge.count", merged.count == 4)
statistics_check("merge.mean", merged.mean == ~2.5)
statistics_check("merge.variance",
                 statistics_close?(merged.sample_variance, ~5.0 / ~3.0))

values = [~4.0, ~1.0, ~3.0, ~2.0]
statistics_check("quantile.type7.lower",
                 Statistics.quantile(values, ~0.25) == ~1.75)
statistics_check("quantile.type7.upper",
                 Statistics.quantile(values, ~0.75) == ~3.25)
statistics_check("quantile.endpoints",
                 Statistics.quantile(values, ~0.0) == ~1.0 &&
                   Statistics.quantile(values, ~1.0) == ~4.0)
statistics_check("quantile.does_not_mutate", values[0] == ~4.0)
statistics_check("median.even", Statistics.median(values) == ~2.5)

xs = [~1.0, ~2.0, ~3.0, ~4.0]
ys = [~2.0, ~4.0, ~6.0, ~8.0]
paired = Statistics.summarize_pairs(xs, ys)
statistics_check("paired.mean_x", paired.mean_x == ~2.5)
statistics_check("paired.mean_y", paired.mean_y == ~5.0)
statistics_check("covariance.sample",
                 statistics_close?(paired.sample_covariance,
                                   ~10.0 / ~3.0))
statistics_check("covariance.population", paired.population_covariance == ~2.5)
statistics_check("correlation.positive", paired.correlation == ~1.0)
statistics_check("correlation.negative",
                 Statistics.correlation(xs, [~8.0, ~6.0, ~4.0, ~2.0]) == ~-1.0)

pair_left = Statistics.bivariate_accumulator
pair_left.push(~1.0, ~2.0).push(~2.0, ~4.0)
pair_right = Statistics.bivariate_accumulator
pair_right.push(~3.0, ~6.0).push(~4.0, ~8.0)
pair_left.merge(pair_right)
statistics_check("paired.merge", pair_left.snapshot.correlation == ~1.0)

estimate = Statistics.mean_measurement([~1.0, ~2.0, ~3.0])
statistics_check("measurement.class", estimate.class_name == "Measurement")
statistics_check("measurement.value", estimate.value == ~2.0)
statistics_check("measurement.standard_error",
                 statistics_close?(estimate.uncertainty,
                                   Math.sqrt(~1.0 / ~3.0)))

empty_mean_raised = false
begin
  Statistics.mean([])
rescue error
  empty_mean_raised = error.to_s.include?("at least one observation")
statistics_check("failure.empty_mean", empty_mean_raised)

singleton_sample_raised = false
begin
  Statistics.sample_variance([~1.0])
rescue error
  singleton_sample_raised = error.to_s.include?("count greater than correction")
statistics_check("failure.singleton_sample_variance", singleton_sample_raised)
statistics_check("population.singleton",
                 Statistics.population_variance([~7.0]) == ~0.0)

bad_probability_raised = false
begin
  Statistics.quantile([~1.0], ~1.1)
rescue error
  bad_probability_raised = error.to_s.include?("between 0 and 1")
statistics_check("failure.quantile_probability", bad_probability_raised)

mismatch_raised = false
begin
  Statistics.covariance([~1.0], [~1.0, ~2.0])
rescue error
  mismatch_raised = error.to_s.include?("equal-length")
statistics_check("failure.pair_length", mismatch_raised)

constant_raised = false
begin
  Statistics.correlation([~1.0, ~1.0], [~2.0, ~3.0])
rescue error
  constant_raised = error.to_s.include?("zero-variance")
statistics_check("failure.constant_correlation", constant_raised)

nonnumeric_raised = false
begin
  Statistics.mean(["1.0"])
rescue error
  nonnumeric_raised = error.to_s.include?("real numeric scalars")
statistics_check("failure.nonnumeric", nonnumeric_raised)

measurement_input_raised = false
begin
  Statistics.mean([~1.0 ± ~0.1])
rescue error
  measurement_input_raised = error.to_s.include?("real numeric scalars")
statistics_check("failure.measurement_input", measurement_input_raised)

nonfinite_raised = false
begin
  Statistics.mean([Math.exp(~10000.0)])
rescue error
  nonfinite_raised = error.to_s.include?("finite")
statistics_check("failure.nonfinite", nonfinite_raised)

statistics_check("mean.avoids_sum_overflow",
                 Statistics.mean([~1.0e308, ~1.0e308]) == ~1.0e308)
sum_overflow_raised = false
begin
  Statistics.sum([~1.0e308, ~1.0e308])
rescue error
  sum_overflow_raised = error.to_s.include?("finite floating-point range")
statistics_check("failure.sum_overflow", sum_overflow_raised)

variance_overflow_raised = false
begin
  Statistics.sample_variance([~1.0e308, ~-1.0e308])
rescue error
  variance_overflow_raised = error.to_s.include?("finite floating-point range")
statistics_check("failure.variance_overflow", variance_overflow_raised)

<< "statistics_spec: all checks passed"
