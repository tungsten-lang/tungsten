# MCMC, HMC, SMC, variational inference, and diagnostic contracts.
# spec: compiled -- interpreter: memory limit exceeded at 8 GiB (passes at 24G, 20.5 GiB peak)

use probability

-> inference_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> inference_close?(got, want, tolerance = ~0.1)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

log_target = -> (x)
  (~-0.5*(x[0] - ~1.0)*(x[0] - ~1.0) -
   ~0.125*(x[1] + ~2.0)*(x[1] + ~2.0))

gradient = -> (x)
  [~0.0 - (x[0] - ~1.0), ~-0.25*(x[1] + ~2.0)]

# Random-walk Metropolis: deterministic replay and basic moment recovery.
metropolis = Probability.random_walk_metropolis(log_target, [~1.0, ~1.5])
rw_left = metropolis.run([~0.0, ~0.0], 3500, Probability.rng(101), 500, 2)
rw_right = metropolis.run([~0.0, ~0.0], 3500, Probability.rng(101), 500, 2)
inference_check("metropolis.shape",
  rw_left.sample_count == 1500 && rw_left.dimension == 2)
inference_check("metropolis.replay",
  rw_left.samples[0][0] == rw_right.samples[0][0] &&
  rw_left.samples[1499][1] == rw_right.samples[1499][1])
rw_mean = rw_left.mean
inference_check("metropolis.mean",
  inference_close?(rw_mean[0], ~1.0, ~0.13) &&
  inference_close?(rw_mean[1], ~-2.0, ~0.22))
inference_check("metropolis.acceptance",
  rw_left.acceptance_rate > ~0.2 && rw_left.acceptance_rate < ~0.8)

# Fixed-trajectory HMC uses the caller's analytic gradient.
hmc = Probability.hamiltonian_monte_carlo(log_target, gradient, ~0.18, 10)
hmc_chain = hmc.run([~0.0, ~0.0], 1800, Probability.rng(202), 300, 2)
hmc_mean = hmc_chain.mean
hmc_variance = hmc_chain.variance
inference_check("hmc.shape", hmc_chain.sample_count == 750)
inference_check("hmc.mean",
  inference_close?(hmc_mean[0], ~1.0, ~0.1) &&
  inference_close?(hmc_mean[1], ~-2.0, ~0.16))
inference_check("hmc.variance",
  inference_close?(hmc_variance[0], ~1.0, ~0.15) &&
  inference_close?(hmc_variance[1], ~4.0, ~0.35))
inference_check("hmc.acceptance",
  hmc_chain.acceptance_rate > ~0.9 && hmc_chain.divergences == 0)

ess = hmc_chain.effective_sample_size(0)
mcse = ProbabilityDiagnostics.monte_carlo_standard_error(
  hmc_chain.samples, 0)
inference_check("diagnostics.ess",
  ess >= ~1.0 && ess <= hmc_chain.sample_count)
inference_check("diagnostics.mcse", mcse > ~0.0)
hmc_second = hmc.run([~0.0, ~0.0], 1800, Probability.rng(203), 300, 2)
rhat = ProbabilityDiagnostics.split_rhat(
  [hmc_chain.samples, hmc_second.samples], 0)
inference_check("diagnostics.split_rhat", rhat > ~0.9 && rhat < ~1.1)

# Bootstrap particle filter over a scalar Gaussian state-space model.
initial_sampler = -> (rng)
  Probability.normal.sample(rng)
transition_sampler = -> (particle, rng)
  particle + Probability.normal(~0.0, ~0.5).sample(rng)
log_likelihood = -> (observation, particle)
  Probability.normal(particle, ~0.25).log_prob(observation)
filter = Probability.bootstrap_particle_filter(
  initial_sampler, transition_sampler, log_likelihood, 256, ~0.75)
observations = [~0.0, ~0.1, ~-0.1, ~0.15, ~0.0]
filter_left = filter.run(observations, Probability.rng(303))
filter_right = filter.run(observations, Probability.rng(303))
inference_check("smc.shape",
  filter_left.particles.size == observations.size &&
  filter_left.final_particles.size == 256 &&
  filter_left.effective_sample_sizes.size == observations.size)
inference_check("smc.weights",
  inference_close?(ProbabilityNumerics.sum(filter_left.final_weights),
                   ~1.0, ~1.0e-12))
inference_check("smc.replay",
  filter_left.log_evidence == filter_right.log_evidence &&
  filter_left.final_particles[0] == filter_right.final_particles[0])
inference_check("smc.resampling", filter_left.resampled_steps.size > 0)

# Reparameterized mean-field VI on a known diagonal Gaussian target.
vi_log_target = -> (x)
  (~-0.5*(x[0] - ~2.0)*(x[0] - ~2.0) / ~0.25 -
   ~0.5*(x[1] + ~1.0)*(x[1] + ~1.0) / ~4.0)
vi_gradient = -> (x)
  [~0.0 - (x[0] - ~2.0) / ~0.25,
   ~0.0 - (x[1] + ~1.0) / ~4.0]
vi = Probability.mean_field_variational(
  vi_log_target, vi_gradient, ~0.03, 12)
vi_result = vi.fit([~0.0, ~0.0], [~0.0, ~0.0],
                   500, Probability.rng(404))
approximation = vi_result.distribution
inference_check("variational.trace", vi_result.elbo_trace.size == 500)
inference_check("variational.mean",
  inference_close?(approximation.mean[0], ~2.0, ~0.12) &&
  inference_close?(approximation.mean[1], ~-1.0, ~0.18))
inference_check("variational.scale",
  inference_close?(approximation.scales[0], ~0.5, ~0.09) &&
  inference_close?(approximation.scales[1], ~2.0, ~0.2))

bad_gradient = false
begin
  Probability.hamiltonian_monte_carlo(
    log_target, -> (x) [~1.0], ~0.1, 2).run(
      [~0.0, ~0.0], 1, Probability.rng(1))
rescue error
  bad_gradient = error.to_s.include?("wrong dimension")
inference_check("failure.gradient.dimension", bad_gradient)

impossible_target = -> (x)
  ProbabilityNumerics.negative_infinity
bad_initial = false
begin
  Probability.random_walk_metropolis(impossible_target).run(
    [~0.0], 1, Probability.rng(2))
rescue error
  bad_initial = error.to_s.include?("initial state")
inference_check("failure.initial.support", bad_initial)

<< "probability_inference_spec: all checks passed"
