# Probability — distributions, sampling, and stochastic processes.
#
# `use probability` is the feature boundary.  The implementation is split by
# mathematical role so probability laws, stable probability numerics, random
# streams, resampling, and path-valued processes can evolve independently.
# Estimation, regression, hypothesis tests, and fitted-model reporting belong
# to Stats; target-driven Monte Carlo algorithms remain probability primitives.

use core/probability/primitives
use core/probability/special
use core/probability/accuracy
use core/probability/support
use core/probability/rng
use core/probability/streams
use core/probability/random_tests
use core/probability/distribution
use core/probability/sampling
use core/probability/distributions/elementary
use core/probability/distributions/gamma_beta
use core/probability/distributions/discrete
use core/probability/distributions/mixture
use core/probability/linear_algebra
use core/probability/multivariate
use core/probability/process
use core/probability/processes
use core/probability/processes/advanced
use core/probability/dependence/copulas
use core/probability/transforms
use core/probability/inference/diagnostics
use core/probability/inference/mcmc
use core/probability/inference/smc
use core/probability/inference/variational

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

  -> .counter_rng(seed = 1, stream = 0)
    ProbabilityCounterRng.new(seed, stream)

  -> .stream_pool(seed, count)
    ProbabilityNumerics.validate_count(count, "stream count")
    streams = []
    i = 0
    while i < count
      streams.push(ProbabilityCounterRng.new(seed, i))
      i += 1
    streams

  -> .numerical_contract(name)
    ProbabilityAccuracy.contract(name)

  -> .random_battery(rng, sample_count = 10000, bin_count = 16)
    ProbabilityRandomTests.basic(rng, sample_count, bin_count)

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

  -> .multivariate_normal(mean, covariance)
    MultivariateNormalDistribution.new(mean, covariance)

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

  -> .continuous_time_markov_chain(initial, generator)
    ContinuousTimeMarkovChain.new(initial, generator)

  -> .hidden_markov_model(initial, transitions, emissions)
    HiddenMarkovModel.new(initial, transitions, emissions)

  -> .euler_maruyama(drift, diffusion)
    EulerMaruyamaProcess.new(drift, diffusion)

  -> .renewal_process(interarrival_distribution)
    RenewalProcess.new(interarrival_distribution)

  -> .gaussian_copula(correlation)
    GaussianCopula.new(correlation)

  -> .copula_distribution(copula, marginals)
    CopulaDistribution.new(copula, marginals)

  -> .affine_distribution(base, shift, scale)
    AffineDistribution.new(base, shift, scale)

  -> .truncate(base, lower, upper)
    TruncatedDistribution.new(base, lower, upper)

  -> .condition_on_values(base, allowed_values)
    FiniteConditionedDistribution.new(base, allowed_values)

  # Inference algorithms operate on caller-supplied log densities and remain
  # separate from statistical estimation/model-fitting APIs.
  -> .random_walk_metropolis(log_density, proposal_scale = ~1.0)
    RandomWalkMetropolis.new(log_density, proposal_scale)

  -> .hamiltonian_monte_carlo(log_density, gradient,
                              step_size = ~0.1, leapfrog_steps = 10)
    HamiltonianMonteCarlo.new(
      log_density, gradient, step_size, leapfrog_steps)

  -> .bootstrap_particle_filter(initial_sampler, transition_sampler,
                                log_likelihood, particle_count,
                                resample_threshold = ~0.5)
    BootstrapParticleFilter.new(
      initial_sampler, transition_sampler, log_likelihood,
      particle_count, resample_threshold)

  -> .mean_field_variational(log_density, gradient,
                             learning_rate = ~0.02,
                             monte_carlo_samples = 8)
    MeanFieldVariationalInference.new(
      log_density, gradient, learning_rate, monte_carlo_samples)
