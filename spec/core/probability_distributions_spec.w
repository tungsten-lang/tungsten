# Gamma/Beta/Categorical/Poisson/mixture distribution contracts.

use probability

-> distribution_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> distribution_close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance*scale

-> integrate_pdf(distribution, lower, upper, count)
  width = (upper - lower) / (count + ~0.0)
  total = ~0.0
  i = 0
  while i < count
    total += distribution.pdf(lower + (i + ~0.5)*width)
    i += 1
  total*width

# --- Gamma and Beta -------------------------------------------------------

gamma = Probability.gamma(~2.0, ~3.0)
distribution_check("gamma.parameters",
                   gamma.shape == ~2.0 && gamma.scale == ~3.0 &&
                   distribution_close?(gamma.rate, ~1.0 / ~3.0))
distribution_check("gamma.moments",
                   gamma.mean == ~6.0 && gamma.variance == ~18.0)
distribution_check("gamma.pdf",
                   distribution_close?(gamma.pdf(~3.0),
                                       ~0.12262648039048077, ~2.0e-14))
distribution_check("gamma.cdf",
                   distribution_close?(gamma.cdf(~3.0),
                                       ~0.26424111765711533, ~2.0e-14))
distribution_check("gamma.tail.complement",
                   distribution_close?(gamma.cdf(~9.0) + gamma.survival(~9.0),
                                       ~1.0, ~2.0e-14))
distribution_check("gamma.normalized.numeric",
                   distribution_close?(
                     integrate_pdf(gamma, ~0.0, ~90.0, 30000),
                     ~1.0, ~4.0e-7))
gamma_q = gamma.quantile(~0.73)
distribution_check("gamma.quantile.roundtrip",
                   distribution_close?(gamma.cdf(gamma_q), ~0.73, ~2.0e-13))

gamma_singular = Probability.gamma(~0.5)
distribution_check("gamma.boundary.singularity",
                   gamma_singular.pdf(~0.0).infinite?)

beta = Probability.beta(~2.0, ~3.0)
distribution_check("beta.moments",
                   distribution_close?(beta.mean, ~0.4) &&
                   distribution_close?(beta.variance, ~0.04))
distribution_check("beta.pdf", distribution_close?(beta.pdf(~0.5), ~1.5))
distribution_check("beta.cdf", distribution_close?(beta.cdf(~0.5), ~0.6875))
distribution_check("beta.tail.complement",
                   distribution_close?(beta.cdf(~0.9) + beta.survival(~0.9),
                                       ~1.0, ~1.0e-14))
distribution_check("beta.normalized.numeric",
                   distribution_close?(
                     integrate_pdf(beta, ~0.0, ~1.0, 12000),
                     ~1.0, ~2.0e-8))
beta_q = beta.quantile(~0.2)
distribution_check("beta.quantile.roundtrip",
                   distribution_close?(beta.cdf(beta_q), ~0.2, ~2.0e-13))
distribution_check("beta.support",
                   beta.support.contains?(~0.0) &&
                   beta.support.contains?(~1.0) &&
                   beta.pdf(~-0.1) == ~0.0)

# Samplers replay exactly and stay in mathematical support.
left_rng = Probability.rng(8128)
right_rng = Probability.rng(8128)
i = 0
gamma_replay = true
while i < 64
  gamma_replay = false if gamma.sample(left_rng) != gamma.sample(right_rng)
  i += 1
beta_rng = Probability.rng(8128)
beta_supported = true
i = 0
while i < 64
  draw = beta.sample(beta_rng)
  beta_supported = false if !beta.support.contains?(draw)
  i += 1
distribution_check("gamma.sample.replay", gamma_replay)
distribution_check("beta.sample.support", beta_supported)
gamma_vector_rng = Probability.rng(8128)
distribution_check("gamma.sample.vector",
                   distribution_close?(gamma.sample(gamma_vector_rng),
                                       ~0.4666351371568992, ~2.0e-14) &&
                   distribution_close?(gamma.sample(gamma_vector_rng),
                                       ~4.605037264584333, ~2.0e-14))

normal = Probability.normal(~2.0, ~3.0)
normal_q = normal.quantile(~0.975)
distribution_check("normal.quantile.value",
                   distribution_close?(normal_q,
                                       ~7.879891953620167, ~2.0e-13))
distribution_check("normal.quantile.roundtrip",
                   distribution_close?(normal.cdf(normal_q), ~0.975,
                                       ~2.0e-14))
distribution_check("normal.tail.stable",
                   Probability.normal.survival(~10.0) > ~0.0)

# --- Categorical and Poisson ---------------------------------------------

categorical = Probability.categorical([~1.0, ~2.0, ~1.0])
probabilities = categorical.probabilities
distribution_check("categorical.normalized",
                   probabilities[0] == ~0.25 &&
                   probabilities[1] == ~0.5 &&
                   probabilities[2] == ~0.25)
distribution_check("categorical.mass",
                   categorical.pmf(0) + categorical.pmf(1) +
                   categorical.pmf(2) == ~1.0)
distribution_check("categorical.moments",
                   categorical.mean == ~1.0 && categorical.variance == ~0.5)
distribution_check("categorical.cdf.quantile",
                   categorical.cdf(~1.2) == ~0.75 &&
                   categorical.quantile(~0.74) == 1 &&
                   categorical.mode == 1)
distribution_check("categorical.entropy",
                   distribution_close?(categorical.entropy,
                                       ~1.0397207708399179, ~2.0e-14))

poisson = Probability.poisson(~4.0)
distribution_check("poisson.moments",
                   poisson.mean == ~4.0 && poisson.variance == ~4.0)
distribution_check("poisson.pmf",
                   distribution_close?(poisson.pmf(2),
                                       ~0.14652511110987343, ~3.0e-14))
distribution_check("poisson.cdf",
                   distribution_close?(poisson.cdf(2),
                                       ~0.23810330555354436, ~3.0e-14))
distribution_check("poisson.tail.complement",
                   distribution_close?(poisson.cdf(7) + poisson.survival(7),
                                       ~1.0, ~3.0e-14))
mass = ~0.0
i = 0
while i <= 40
  mass += poisson.pmf(i)
  i += 1
distribution_check("poisson.normalized", distribution_close?(mass, ~1.0))
distribution_check("poisson.quantile",
                   poisson.quantile(poisson.cdf(6)) == 6)
distribution_check("poisson.quantile.one",
                   poisson.quantile(~1.0).infinite?)

small_rng = Probability.rng(99)
large_rng = Probability.rng(99)
small_supported = true
large_supported = true
i = 0
large_poisson = Probability.poisson(~1000.0)
while i < 128
  small_supported = false if !poisson.support.contains?(poisson.sample(small_rng))
  large_supported = false if !large_poisson.support.contains?(
    large_poisson.sample(large_rng))
  i += 1
distribution_check("poisson.sample.small.support", small_supported)
distribution_check("poisson.sample.large.support", large_supported)
poisson_vector_rng = Probability.rng(99)
distribution_check("poisson.sample.large.vector",
                   large_poisson.sample(poisson_vector_rng) == 977 &&
                   large_poisson.sample(poisson_vector_rng) == 1004 &&
                   large_poisson.sample(poisson_vector_rng) == 991)

# --- Finite mixtures ------------------------------------------------------

mixture = Probability.mixture(
  [Probability.normal(~-2.0, ~1.0), Probability.normal(~2.0, ~1.0)],
  [~1.0, ~3.0])
distribution_check("mixture.weights",
                   mixture.weights[0] == ~0.25 && mixture.weights[1] == ~0.75)
distribution_check("mixture.moments",
                   distribution_close?(mixture.mean, ~1.0) &&
                   distribution_close?(mixture.variance, ~4.0))
distribution_check("mixture.log_probability",
                   distribution_close?(Math.exp(mixture.log_prob(~0.5)),
                                       mixture.pdf(~0.5), ~2.0e-14))
distribution_check("mixture.cdf.bounds",
                   mixture.cdf(~-100.0) < ~1.0e-100 &&
                   mixture.cdf(~100.0) == ~1.0)

invalid_gamma_failed = false
begin
  Probability.gamma(~0.0)
rescue error
  invalid_gamma_failed = error.to_s.include?("must be positive")
distribution_check("failure.gamma.domain", invalid_gamma_failed)

invalid_categorical_failed = false
begin
  Probability.categorical([~0.0, ~0.0])
rescue error
  invalid_categorical_failed = error.to_s.include?("positive total")
distribution_check("failure.categorical.domain", invalid_categorical_failed)

mixed_measure_failed = false
begin
  Probability.mixture(
    [Probability.normal, Probability.bernoulli], [~1.0, ~1.0])
rescue error
  mixed_measure_failed = error.to_s.include?("measure type")
distribution_check("failure.mixture.measure", mixed_measure_failed)

<< "probability_distributions_spec: all checks passed"
