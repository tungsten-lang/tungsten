# Bootstrap sequential Monte Carlo with adaptive systematic resampling.

use core/math
use core/probability/inference/mcmc
use core/probability/primitives
use core/probability/rng
use core/probability/sampling

+ ParticleFilterResult
  ro :log_evidence

  -> new(particles, weights, ess_history, log_evidence, resampled_steps)
    @particles = particles
    @weights = weights
    @ess_history = ProbabilityNumerics.copy_array(ess_history)
    @log_evidence = log_evidence
    @resampled_steps = ProbabilityNumerics.copy_array(resampled_steps)
    self

  -> particles
    history = []
    i = 0
    while i < @particles.size
      history.push(ProbabilityNumerics.copy_array(@particles[i]))
      i += 1
    history

  -> weights
    history = []
    i = 0
    while i < @weights.size
      history.push(ProbabilityNumerics.copy_array(@weights[i]))
      i += 1
    history

  -> effective_sample_sizes
    ProbabilityNumerics.copy_array(@ess_history)

  -> resampled_steps
    ProbabilityNumerics.copy_array(@resampled_steps)

  -> final_particles
    return [] if @particles.size == 0
    ProbabilityNumerics.copy_array(@particles[@particles.size - 1])

  -> final_weights
    return [] if @weights.size == 0
    ProbabilityNumerics.copy_array(@weights[@weights.size - 1])


+ BootstrapParticleFilter
  -> new(initial_sampler, transition_sampler, log_likelihood,
         particle_count, resample_threshold = ~0.5)
    @initial_sampler = initial_sampler
    @transition_sampler = transition_sampler
    @log_likelihood = log_likelihood
    @particle_count = ProbabilityInference.positive_integer(
      particle_count, "particle count")
    @resample_threshold = ProbabilityNumerics.unit_probability(
      resample_threshold, "resample threshold")
    self

  -> run(observations, rng)
    if observations.class_name != "Array" || observations.size == 0
      raise "probability particle filter observations must be nonempty"
    ProbabilityRandom.require_rng(rng)
    particles = []
    @particle_count.times -> particles.push(
      ProbabilityInference.sample_initial(@initial_sampler, rng))
    base_log_weight = ~0.0 - Math.log(@particle_count + ~0.0)
    log_weights = []
    @particle_count.times -> log_weights.push(base_log_weight)
    particle_history = []
    weight_history = []
    ess_history = []
    resampled_steps = []
    log_evidence = ~0.0
    time = 0
    while time < observations.size
      if time > 0
        previous_weights = ProbabilityNumerics.normalize_log_weights(log_weights)
        previous_ess = ProbabilityNumerics.effective_sample_size(previous_weights)
        if previous_ess < @resample_threshold*@particle_count
          indices = ProbabilitySampling.systematic_resample(
            previous_weights, @particle_count, rng)
          resampled = []
          i = 0
          while i < indices.size
            resampled.push(particles[indices[i]])
            i += 1
          particles = resampled
          log_weights = []
          @particle_count.times -> log_weights.push(base_log_weight)
          resampled_steps.push(time)
        propagated = []
        i = 0
        while i < particles.size
          propagated.push(ProbabilityInference.sample_transition(
            @transition_sampler, particles[i], rng))
          i += 1
        particles = propagated
      updated = []
      i = 0
      while i < particles.size
        likelihood = ProbabilityInference.particle_log_likelihood(
          @log_likelihood, observations[time], particles[i])
        updated.push(log_weights[i] + likelihood)
        i += 1
      increment = ProbabilityNumerics.logsumexp(updated)
      if increment.infinite?
        raise "probability particle filter assigned zero mass to an observation"
      log_evidence += increment
      log_weights = []
      i = 0
      while i < updated.size
        log_weights.push(updated[i] - increment)
        i += 1
      weights = ProbabilityNumerics.normalize_log_weights(log_weights)
      particle_history.push(ProbabilityNumerics.copy_array(particles))
      weight_history.push(weights)
      ess_history.push(ProbabilityNumerics.effective_sample_size(weights))
      time += 1
    ParticleFilterResult.new(
      particle_history, weight_history, ess_history,
      log_evidence, resampled_steps)
