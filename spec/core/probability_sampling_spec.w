# Stable log weights and replayable Monte Carlo resampling primitives.

use probability

-> sampling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> sampling_close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

sampling_check("logaddexp.large",
               sampling_close?(Probability.logaddexp(~1000.0, ~1000.0),
                              ~1000.6931471805599))
sampling_check("logaddexp.positive_infinity",
               Probability.logaddexp(
                 ProbabilityNumerics.positive_infinity, ~1.0).infinite?)
sampling_check("logsumexp.shift",
               sampling_close?(Probability.logsumexp(
                 [~-1000.0, ~-1001.0, ~-1002.0]),
                 ~-999.5923940355556))
normalized = Probability.normalize_log_weights(
  [Math.log(~1.0), Math.log(~2.0), Math.log(~1.0)])
sampling_check("logweights.normalized",
               sampling_close?(ProbabilityNumerics.sum(normalized), ~1.0) &&
               sampling_close?(normalized[1], ~0.5))
sampling_check("log1mexp.near_zero",
               sampling_close?(
                 Math.exp(ProbabilityNumerics.log1mexp(~-1.0e-12)),
                 ~1.0e-12, ~1.0e-20))
sampling_check("ess.uniform",
               sampling_close?(Probability.effective_sample_size(
                 [~1.0, ~1.0, ~1.0, ~1.0]), ~4.0))
sampling_check("ess.concentrated",
               sampling_close?(Probability.effective_sample_size(
                 [~0.0, ~1.0, ~0.0]), ~1.0))
sampling_check("ess.log",
               sampling_close?(Probability.effective_sample_size_from_log([
                 Math.log(~0.5), Math.log(~0.5)]), ~2.0))

rng = Probability.rng(4242)
integers_in_range = true
i = 0
while i < 2000
  draw = rng.integer(7)
  integers_in_range = false if draw < 0 || draw >= 7
  i += 1
sampling_check("rng.integer.range", integers_in_range)
sampling_check("rng.capabilities", !rng.cryptographic? && !rng.splittable?)

left_rng = Probability.rng(17)
right_rng = Probability.rng(17)
left_order = Probability.permutation(32, left_rng)
right_order = Probability.permutation(32, right_rng)
same_order = true
seen = []
32.times -> seen.push(false)
i = 0
while i < left_order.size
  same_order = false if left_order[i] != right_order[i]
  seen[left_order[i]] = true
  i += 1
all_seen = true
i = 0
while i < seen.size
  all_seen = false if !seen[i]
  i += 1
sampling_check("permutation.replay", same_order)
sampling_check("permutation.invariant", all_seen)

selected = Probability.sample_without_replacement(
  ["a", "b", "c", "d"], 3, Probability.rng(5))
sampling_check("without_replacement.size", selected.size == 3)
sampling_check("weighted.degenerate",
               Probability.weighted_sample(
                 ["left", "center", "right"], [~0.0, ~1.0, ~0.0],
                 Probability.rng(1)) == "center")

systematic = Probability.systematic_resample(
  [~0.0, ~1.0, ~0.0], 20, Probability.rng(8))
stratified = Probability.stratified_resample(
  [~0.0, ~1.0, ~0.0], 20, Probability.rng(8))
resampling_degenerate = true
i = 0
while i < 20
  resampling_degenerate = false if systematic[i] != 1 || stratified[i] != 1
  i += 1
sampling_check("resampling.degenerate", resampling_degenerate)

left = Probability.systematic_resample(
  [~0.1, ~0.2, ~0.7], 50, Probability.rng(123))
right = Probability.systematic_resample(
  [~0.1, ~0.2, ~0.7], 50, Probability.rng(123))
resampling_replay = true
i = 0
while i < left.size
  resampling_replay = false if left[i] != right[i]
  i += 1
sampling_check("resampling.replay", resampling_replay)

all_log_zero_failed = false
begin
  negative_infinity = ProbabilityNumerics.negative_infinity
  Probability.normalize_log_weights([negative_infinity, negative_infinity])
rescue error
  all_log_zero_failed = error.to_s.include?("cannot all")
sampling_check("failure.logweights.all_zero", all_log_zero_failed)

negative_weight_failed = false
begin
  Probability.effective_sample_size([~1.0, ~-1.0])
rescue error
  negative_weight_failed = error.to_s.include?("nonnegative")
sampling_check("failure.weight.domain", negative_weight_failed)

oversample_failed = false
begin
  Probability.sample_without_replacement([1, 2], 3, Probability.rng(1))
rescue error
  oversample_failed = error.to_s.include?("exceeds population")
sampling_check("failure.without_replacement.count", oversample_failed)

<< "probability_sampling_spec: all checks passed"
