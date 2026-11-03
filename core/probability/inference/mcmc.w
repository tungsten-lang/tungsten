# Random-walk Metropolis and fixed-trajectory Hamiltonian Monte Carlo.
#
# HMC accepts an explicit analytic gradient callback.  Core Autodiff cannot yet
# trace arbitrary vector-valued Tungsten closures, so this module does not fake
# automatic gradients or claim to implement NUTS.

use core/math
use core/probability/inference/diagnostics
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/rng

+ ProbabilityInference
  -> .log_density_value(log_density, position)
    value = log_density(position).to_f
    if value != value || (value.infinite? && value > ~0.0)
      raise "probability log density must be finite or negative infinity"
    value

  -> .gradient_value(gradient, position)
    ProbabilityLinearAlgebra.vector_dimension(
      gradient(position), position.size, "log-density gradient")

  -> .sample_initial(sampler, rng)
    sampler(rng)

  -> .sample_transition(sampler, particle, rng)
    sampler(particle, rng)

  -> .particle_log_likelihood(log_likelihood, observation, particle)
    value = log_likelihood(observation, particle).to_f
    if value != value || (value.infinite? && value > ~0.0)
      raise "probability particle log likelihood must be finite or negative infinity"
    value

  -> .positive_integer(value, parameter)
    if !ProbabilityNumerics.integer?(value) || value <= 0
      raise "probability " + parameter + " must be a positive integer"
    value

  -> .scales(value, dimension, parameter)
    if value.class_name == "Array"
      scales = ProbabilityLinearAlgebra.vector_dimension(
        value, dimension, parameter)
      i = 0
      while i < scales.size
        if scales[i] <= ~0.0
          raise "probability " + parameter + " entries must be positive"
        i += 1
      return scales
    scalar = ProbabilityNumerics.positive_finite(value, parameter)
    scales = []
    dimension.times -> scales.push(scalar)
    scales


+ RandomWalkMetropolis
  -> new(log_density, proposal_scale = ~1.0)
    @log_density = log_density
    @proposal_scale = proposal_scale
    self

  -> run(initial, iterations, rng, burn_in = 0, thin = 1)
    current = ProbabilityLinearAlgebra.vector(initial, "MCMC initial state")
    ProbabilityNumerics.validate_count(iterations, "MCMC iteration count")
    ProbabilityNumerics.validate_count(burn_in, "MCMC burn-in")
    ProbabilityInference.positive_integer(thin, "MCMC thinning interval")
    if burn_in > iterations
      raise "probability MCMC burn-in exceeds iteration count"
    ProbabilityRandom.require_rng(rng)
    scales = ProbabilityInference.scales(
      @proposal_scale, current.size, "MCMC proposal scale")
    current_log = ProbabilityInference.log_density_value(
      @log_density, current)
    if current_log.infinite?
      raise "probability MCMC initial state must have finite log density"
    samples = []
    log_probabilities = []
    accepted = 0
    iteration = 0
    while iteration < iterations
      proposal = []
      i = 0
      while i < current.size
        proposal.push(current[i] + scales[i]*
          ProbabilityRandom.standard_normal(rng))
        i += 1
      proposal_log = ProbabilityInference.log_density_value(
        @log_density, proposal)
      log_ratio = proposal_log - current_log
      log_uniform = Math.log(ProbabilityRandom.random_unit(rng))
      if log_ratio >= ~0.0 || log_uniform < log_ratio
        current = proposal
        current_log = proposal_log
        accepted += 1
      if iteration >= burn_in && (iteration - burn_in) % thin == 0
        samples.push(ProbabilityNumerics.copy_array(current))
        log_probabilities.push(current_log)
      iteration += 1
    MonteCarloChain.new(
      samples, log_probabilities, accepted, iterations)


+ HamiltonianMonteCarlo
  -> new(log_density, gradient, step_size = ~0.1, leapfrog_steps = 10)
    @log_density = log_density
    @gradient = gradient
    @step_size = ProbabilityNumerics.positive_finite(
      step_size, "HMC step size")
    @leapfrog_steps = ProbabilityInference.positive_integer(
      leapfrog_steps, "HMC leapfrog step count")
    self

  -> run(initial, iterations, rng, burn_in = 0, thin = 1)
    current = ProbabilityLinearAlgebra.vector(initial, "HMC initial state")
    ProbabilityNumerics.validate_count(iterations, "HMC iteration count")
    ProbabilityNumerics.validate_count(burn_in, "HMC burn-in")
    ProbabilityInference.positive_integer(thin, "HMC thinning interval")
    if burn_in > iterations
      raise "probability HMC burn-in exceeds iteration count"
    ProbabilityRandom.require_rng(rng)
    current_log = ProbabilityInference.log_density_value(
      @log_density, current)
    if current_log.infinite?
      raise "probability HMC initial state must have finite log density"
    ProbabilityInference.gradient_value(@gradient, current)
    samples = []
    log_probabilities = []
    accepted = 0
    divergences = 0
    iteration = 0
    while iteration < iterations
      momentum = []
      current.size.times -> momentum.push(
        ProbabilityRandom.standard_normal(rng))
      proposed_position = ProbabilityNumerics.copy_array(current)
      proposed_momentum = ProbabilityNumerics.copy_array(momentum)
      gradient = ProbabilityInference.gradient_value(
        @gradient, proposed_position)
      i = 0
      while i < proposed_momentum.size
        proposed_momentum[i] = (proposed_momentum[i] +
          ~0.5*@step_size*gradient[i])
        i += 1
      step = 0
      while step < @leapfrog_steps
        i = 0
        while i < proposed_position.size
          proposed_position[i] = (proposed_position[i] +
            @step_size*proposed_momentum[i])
          i += 1
        gradient = ProbabilityInference.gradient_value(
          @gradient, proposed_position)
        if step + 1 < @leapfrog_steps
          i = 0
          while i < proposed_momentum.size
            proposed_momentum[i] = (proposed_momentum[i] +
              @step_size*gradient[i])
            i += 1
        step += 1
      i = 0
      while i < proposed_momentum.size
        proposed_momentum[i] = (proposed_momentum[i] +
          ~0.5*@step_size*gradient[i])
        i += 1
      proposed_log = ProbabilityInference.log_density_value(
        @log_density, proposed_position)
      current_energy = (~0.0 - current_log +
        ~0.5*ProbabilityLinearAlgebra.dot(momentum, momentum))
      proposed_energy = (~0.0 - proposed_log +
        ~0.5*ProbabilityLinearAlgebra.dot(
          proposed_momentum, proposed_momentum))
      energy_error = proposed_energy - current_energy
      absolute_error = energy_error < ~0.0 ? ~0.0 - energy_error : energy_error
      divergent = (energy_error != energy_error || energy_error.infinite? ||
                   absolute_error > ~1000.0)
      divergences += 1 if divergent
      log_uniform = Math.log(ProbabilityRandom.random_unit(rng))
      if !divergent && (energy_error <= ~0.0 || log_uniform < ~0.0 - energy_error)
        current = proposed_position
        current_log = proposed_log
        accepted += 1
      if iteration >= burn_in && (iteration - burn_in) % thin == 0
        samples.push(ProbabilityNumerics.copy_array(current))
        log_probabilities.push(current_log)
      iteration += 1
    HamiltonianMonteCarloChain.new(
      samples, log_probabilities, accepted, iterations,
      divergences, @step_size)
