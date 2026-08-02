# Probability — distributions, sampling, and stochastic processes.
#
# `use probability` is the feature boundary.  The implementation is split by
# mathematical role so probability laws, stable probability numerics, random
# streams, resampling, and path-valued processes can evolve independently.
# Estimation, hypothesis tests, and fitted-model inference belong to Stats.

use core/probability/primitives
use core/probability/special
use core/probability/support
use core/probability/rng
use core/probability/distribution
use core/probability/sampling
use core/probability/distributions/elementary
use core/probability/distributions/gamma_beta
use core/probability/distributions/discrete
use core/probability/distributions/mixture
use core/probability/process
use core/probability/processes

+ Probability
  # Compatibility validation surface retained from the initial module.
  -> .integer?(value)
    ProbabilityNumerics.integer?(value)

  -> .finite_float(value, parameter)
    ProbabilityNumerics.finite_float(value, parameter)

  -> .unit_probability(value, parameter = "probability")
    ProbabilityNumerics.unit_probability(value, parameter)

  -> .positive_finite(value, parameter)
    ProbabilityNumerics.positive_finite(value, parameter)

  -> .require_rng(rng)
    ProbabilityRandom.require_rng(rng)

  -> .random_unit(rng)
    ProbabilityRandom.random_unit(rng)

  # Stable probability-domain primitives.
  -> .logaddexp(left, right)
    ProbabilityNumerics.logaddexp(left, right)

  -> .logsumexp(values)
    ProbabilityNumerics.logsumexp(values)

  -> .normalize_log_weights(values)
    ProbabilityNumerics.normalize_log_weights(values)

  -> .effective_sample_size(weights)
    ProbabilityNumerics.effective_sample_size(weights)

  -> .effective_sample_size_from_log(log_weights)
    ProbabilityNumerics.effective_sample_size_from_log(log_weights)

  -> .log1mexp(value)
    ProbabilityNumerics.log1mexp(value)

  # Explicit seeded random stream.
  -> .rng(seed = 1)
    ProbabilityRng.new(seed)

  # Distribution factories.  Existing signatures remain unchanged.
  -> .bernoulli(p = ~0.5)
    BernoulliDistribution.new(p)

  -> .uniform(lower = ~0.0, upper = ~1.0)
    UniformDistribution.new(lower, upper)

  -> .normal(mean = ~0.0, standard_deviation = ~1.0)
    NormalDistribution.new(mean, standard_deviation)

  -> .exponential(rate = ~1.0)
    ExponentialDistribution.new(rate)

  -> .gamma(shape, scale = ~1.0)
    GammaDistribution.new(shape, scale)

  -> .beta(alpha, beta)
    BetaDistribution.new(alpha, beta)

  -> .categorical(weights)
    CategoricalDistribution.new(weights)

  -> .poisson(rate)
    PoissonDistribution.new(rate)

  -> .mixture(components, weights)
    MixtureDistribution.new(components, weights)

  # Sampling primitives used by particle and Monte Carlo algorithms.
  -> .weighted_sample(values, weights, rng)
    ProbabilitySampling.weighted_sample(values, weights, rng)

  -> .systematic_resample(weights, count, rng)
    ProbabilitySampling.systematic_resample(weights, count, rng)

  -> .stratified_resample(weights, count, rng)
    ProbabilitySampling.stratified_resample(weights, count, rng)

  -> .permutation(count, rng)
    ProbabilitySampling.permutation(count, rng)

  -> .sample_without_replacement(values, count, rng)
    ProbabilitySampling.without_replacement(values, count, rng)

  # Stochastic-process factories.
  -> .markov_chain(initial, transitions)
    FiniteMarkovChain.new(initial, transitions)

  -> .wiener(drift = ~0.0, volatility = ~1.0)
    WienerProcess.new(drift, volatility)

  -> .poisson_process(rate)
    PoissonProcess.new(rate)
