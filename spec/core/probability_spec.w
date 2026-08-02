# Focused distribution, support, normalization, and reproducibility checks.
# Run in both engines:
#   bin/tungsten run spec/core/probability_spec.w
#   bin/tungsten compile spec/core/probability_spec.w --out /tmp/probability-spec

use probability

-> probability_check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

-> probability_close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> midpoint_integral(distribution, lower, upper, count)
  width = (upper - lower) / (count + ~0.0)
  total = ~0.0
  i = 0
  while i < count
    x = lower + (i + ~0.5) * width
    total += distribution.pdf(x)
    i += 1
  total * width

# --- shared protocol and supports -----------------------------------------

coin = Probability.bernoulli(~0.25)
uniform = Probability.uniform(~-2.0, ~4.0)
normal = Probability.normal(~3.0, ~2.0)
exponential = Probability.exponential(~2.0)

probability_check("protocol.continuous", normal.continuous? && !normal.discrete?)
probability_check("protocol.discrete", coin.discrete? && !coin.continuous?)
probability_check("protocol.probability.pmf",
                  coin.probability(1) == coin.pmf(1))
probability_check("protocol.probability.pdf",
                  normal.probability(~3.0) == normal.pdf(~3.0))
probability_check("support.bernoulli.values",
                  coin.support.contains?(0) && coin.support.contains?(1) &&
                  !coin.support.contains?(~0.5) && !coin.support.contains?(2))
probability_check("support.uniform.closed",
                  uniform.support.contains?(~-2.0) &&
                  uniform.support.contains?(~4.0) &&
                  !uniform.support.contains?(~4.0001))
probability_check("support.normal.unbounded",
                  !normal.support.bounded? &&
                  normal.support.contains?(~-1.0e200) &&
                  normal.support.contains?(~1.0e200))
probability_check("support.exponential",
                  exponential.support.contains?(~0.0) &&
                  !exponential.support.contains?(~-1.0e-12))
not_a_number = ~0.0 / ~0.0
probability_check("support.nan.outside",
                  !normal.support.contains?(not_a_number))

# --- analytic values, moments, and normalization -------------------------

probability_check("bernoulli.mass.normalized",
                  probability_close?(coin.pmf(0) + coin.pmf(1), ~1.0))
probability_check("bernoulli.outside", coin.pmf(2) == ~0.0)
probability_check("bernoulli.cdf.step",
                  coin.cdf(~-0.5) == ~0.0 &&
                  coin.cdf(~0.5) == ~0.75 &&
                  coin.cdf(~1.0) == ~1.0)
probability_check("bernoulli.moments",
                  probability_close?(coin.mean, ~0.25) &&
                  probability_close?(coin.variance, ~0.1875))
probability_check("bernoulli.degenerate.endpoints",
                  Probability.bernoulli(~0.0).sample(Probability.rng(7)) == 0 &&
                  Probability.bernoulli(~1.0).sample(Probability.rng(7)) == 1)
zero_log_probability = Probability.bernoulli(~0.0).log_prob(1)
probability_check("bernoulli.log_zero",
                  zero_log_probability.infinite? &&
                  zero_log_probability < ~0.0)
probability_check("bernoulli.nan.cdf",
                  Probability.bernoulli.cdf(not_a_number) !=
                  Probability.bernoulli.cdf(not_a_number))

probability_check("uniform.pdf",
                  probability_close?(uniform.pdf(~0.0), ~1.0 / ~6.0) &&
                  uniform.pdf(~5.0) == ~0.0)
probability_check("uniform.cdf",
                  uniform.cdf(~-2.0) == ~0.0 &&
                  probability_close?(uniform.cdf(~1.0), ~0.5) &&
                  uniform.cdf(~4.0) == ~1.0)
probability_check("uniform.moments",
                  uniform.mean == ~1.0 && uniform.variance == ~3.0)
probability_check("uniform.normalized",
                  probability_close?(
                    midpoint_integral(uniform, ~-2.0, ~4.0, 1200),
                    ~1.0, ~1.0e-12))

standard_normal = Probability.normal
probability_check("normal.center",
                  probability_close?(standard_normal.pdf(~0.0),
                                     ~0.3989422804014327, ~1.0e-15) &&
                  probability_close?(standard_normal.cdf(~0.0), ~0.5,
                                     ~1.0e-15))
probability_check("normal.moments",
                  normal.mean == ~3.0 && normal.variance == ~4.0 &&
                  normal.standard_deviation == ~2.0)
probability_check("normal.symmetry",
                  probability_close?(standard_normal.pdf(~-1.75),
                                     standard_normal.pdf(~1.75), ~1.0e-15))
probability_check("normal.normalized.numeric",
                  probability_close?(
                    midpoint_integral(standard_normal, ~-8.0, ~8.0, 4000),
                    ~1.0, ~1.0e-12))
probability_check("normal.log_tail.stable",
                  probability_close?(standard_normal.log_prob(~100.0),
                                     ~-5000.918938533205, ~1.0e-10))

probability_check("exponential.boundary",
                  exponential.pdf(~-1.0) == ~0.0 &&
                  exponential.cdf(~-1.0) == ~0.0 &&
                  exponential.pdf(~0.0) == ~2.0)
probability_check("exponential.moments",
                  exponential.mean == ~0.5 && exponential.variance == ~0.25)
probability_check("exponential.cdf",
                  probability_close?(exponential.cdf(~1.0),
                                     ~0.8646647167633873, ~1.0e-15))
probability_check("exponential.normalized.numeric",
                  probability_close?(
                    midpoint_integral(exponential, ~0.0, ~12.0, 12000),
                    ~1.0, ~2.0e-7))

# --- seeded replay and sampled invariants ---------------------------------

rng = Probability.rng(42)
probability_check("rng.algorithm", rng.algorithm == "mulberry32")
probability_check("rng.not_crypto", !rng.cryptographic?)
probability_check("rng.vector.0", rng.next_u32 == 2581720956)
probability_check("rng.vector.1", rng.next_u32 == 1925393290)
probability_check("rng.vector.2", rng.next_u32 == 3661312704)
probability_check("rng.zero.normalized", Probability.rng(0).seed == 1)
probability_check("rng.low_32_bits",
                  Probability.rng(4294967297).next_u32 ==
                  Probability.rng(1).next_u32)

left_rng = Probability.rng(20260802)
right_rng = Probability.rng(20260802)
i = 0
same_stream = true
while i < 32
  same_stream = false if left_rng.random != right_rng.random
  i += 1
probability_check("rng.seeded.replay", same_stream)

left_rng = Probability.rng(1234)
right_rng = Probability.rng(1234)
left_draws = normal.samples(24, left_rng)
right_draws = normal.samples(24, right_rng)
i = 0
same_normal_draws = true
while i < left_draws.size
  same_normal_draws = false if left_draws[i] != right_draws[i]
  i += 1
probability_check("normal.seeded.replay", same_normal_draws)

sample_rng = Probability.rng(991)
coin_draws = coin.samples(128, sample_rng)
coin_supported = true
i = 0
while i < coin_draws.size
  coin_supported = false if !coin.support.contains?(coin_draws[i])
  i += 1
probability_check("bernoulli.samples.in_support", coin_supported)

uniform_draws = uniform.samples(128, sample_rng)
uniform_supported = true
i = 0
while i < uniform_draws.size
  uniform_supported = false if !uniform.support.contains?(uniform_draws[i])
  i += 1
probability_check("uniform.samples.in_support", uniform_supported)

exponential_draws = exponential.samples(128, sample_rng)
exponential_supported = true
i = 0
while i < exponential_draws.size
  exponential_supported = false if !exponential.support.contains?(
    exponential_draws[i])
  i += 1
probability_check("exponential.samples.in_support", exponential_supported)

probability_check("samples.zero", normal.samples(0, sample_rng).size == 0)

# --- invalid domains and RNG contract fail loudly -------------------------

bad_probability_failed = false
begin
  Probability.bernoulli(~-0.01)
rescue error
  bad_probability_failed = error.to_s.include?("between 0 and 1")
probability_check("failure.bernoulli.domain", bad_probability_failed)

nan_parameter_failed = false
begin
  Probability.bernoulli(not_a_number)
rescue error
  nan_parameter_failed = error.to_s.include?("must be finite")
probability_check("failure.nan.parameter", nan_parameter_failed)

bad_bounds_failed = false
begin
  Probability.uniform(~2.0, ~2.0)
rescue error
  bad_bounds_failed = error.to_s.include?("less than upper bound")
probability_check("failure.uniform.domain", bad_bounds_failed)

bad_normal_failed = false
begin
  Probability.normal(~0.0, ~0.0)
rescue error
  bad_normal_failed = error.to_s.include?("must be positive")
probability_check("failure.normal.domain", bad_normal_failed)

bad_rate_failed = false
begin
  Probability.exponential(~-1.0)
rescue error
  bad_rate_failed = error.to_s.include?("must be positive")
probability_check("failure.exponential.domain", bad_rate_failed)

infinite_parameter_failed = false
begin
  Probability.normal(Math.exp(~1000.0), ~1.0)
rescue error
  infinite_parameter_failed = error.to_s.include?("must be finite")
probability_check("failure.infinite.parameter", infinite_parameter_failed)

bad_seed_failed = false
begin
  Probability.rng(~1.5)
rescue error
  bad_seed_failed = error.to_s.include?("seed must be an integer")
probability_check("failure.seed.domain", bad_seed_failed)

missing_rng_failed = false
begin
  normal.sample
rescue error
  missing_rng_failed = error.to_s.include?("needs an RNG")
probability_check("failure.missing.rng", missing_rng_failed)

wrong_density_failed = false
begin
  coin.pdf(~0.0)
rescue error
  wrong_density_failed = error.to_s.include?("pdf is not implemented")
probability_check("failure.discrete.pdf", wrong_density_failed)

wrong_mass_failed = false
begin
  normal.pmf(0)
rescue error
  wrong_mass_failed = error.to_s.include?("pmf is not implemented")
probability_check("failure.continuous.pmf", wrong_mass_failed)

bad_count_failed = false
begin
  normal.samples(-1, Probability.rng(1))
rescue error
  bad_count_failed = error.to_s.include?("nonnegative integer")
probability_check("failure.sample.count", bad_count_failed)

+ ProbabilityBadRng
  -> random
    ~1.0

bad_rng_failed = false
begin
  uniform.sample(ProbabilityBadRng.new)
rescue error
  bad_rng_failed = error.to_s.include?("RNG draws")
probability_check("failure.rng.contract", bad_rng_failed)

<< "probability_spec: all checks passed"
