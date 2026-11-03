# Dense finite-state CTMC transition actions by Poisson uniformization.
#
# ContinuousTimeMarkovChain uses the row-generator convention: Q[i][j] is the
# rate from state i to state j, rows sum to zero, and row probabilities evolve
# as p(t) = p(0) exp(t Q).  With gamma at least the maximum exit rate,
# P = I + Q/gamma is stochastic and
#
#   p(t) = sum(n >= 0) Poisson(n; gamma*t) p(0) P^n.
#
# This implementation accumulates nonnegative binary64 terms from n=0.  It
# deliberately caps gamma*time at 500 so the initial Poisson weight remains
# representable.  A post-mode geometric tail bound controls truncation without
# subtracting nearly equal retained mass from one.  It remains a guarded
# binary64 bound, not a certificate for all floating-point error.

use core/math
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/processes/advanced

+ ContinuousTimeMarkovTransitionResult
  -> new(probabilities, time, rate, poisson_mean, terms,
         retained_poisson_mass, poisson_tail_bound, requested_tolerance)
    @probabilities = ProbabilityNumerics.copy_array(probabilities)
    @time = time
    @rate = rate
    @poisson_mean = poisson_mean
    @terms = terms
    @retained_poisson_mass = retained_poisson_mass
    @estimated_omitted_poisson_mass = ~1.0 - retained_poisson_mass
    if @estimated_omitted_poisson_mass < ~0.0
      @estimated_omitted_poisson_mass = ~0.0
    @poisson_tail_bound = poisson_tail_bound
    @probability_mass = ProbabilityNumerics.sum(@probabilities)
    @requested_tolerance = requested_tolerance
    self

  -> probabilities
    ProbabilityNumerics.copy_array(@probabilities)

  ro :time, :rate, :poisson_mean

  # Includes the n=0 term.
  ro :terms, :retained_poisson_mass

  # Cancellation-prone diagnostic retained for transparency; not used as the
  # stopping criterion.
  ro :estimated_omitted_poisson_mass

  # Post-mode geometric bound for the uncomputed Poisson terms. A 1e-12
  # relative inflation guards the sequential binary64 recurrence, but
  # certified? remains false.
  ro :poisson_tail_bound

  # Kept separate from retained_poisson_mass so row-action rounding remains
  # observable rather than being hidden by normalization.
  ro :probability_mass, :requested_tolerance

  -> certified?
    false

  -> algorithm
    "dense-poisson-uniformization-zero-origin"

  -> to_s
    ("ContinuousTimeMarkovTransitionResult(terms=" + @terms.to_s +
     ", poisson_tail_bound=" + @poisson_tail_bound.to_s + ")")


+ ContinuousTimeMarkovChain
  -> initial_probabilities
    ProbabilityNumerics.copy_array(@initial)

  -> maximum_exit_rate
    maximum = ~0.0
    i = 0
    while i < @exit_rates.size
      maximum = @exit_rates[i] if @exit_rates[i] > maximum
      i += 1
    maximum

  # Propagate the constructor's initial distribution.
  -> uniformize(time, tolerance = ~1.0e-12,
                max_terms = 100000, rate = nil)
    uniformize_from(@initial, time, tolerance, max_terms, rate)

  # Propagate explicit nonnegative initial weights. Inputs are normalized in
  # the same way as the chain constructor; the returned output is not.
  -> uniformize_from(initial, time, tolerance = ~1.0e-12,
                     max_terms = 100000, rate = nil)
    duration = ProbabilityNumerics.nonnegative_finite(
      time, "continuous-time transition time")
    requested_tolerance = ProbabilityNumerics.positive_finite(
      tolerance, "continuous-time transition tolerance")
    if requested_tolerance >= ~1.0
      raise "probability continuous-time transition tolerance must be less than one"
    if requested_tolerance < ~1.0e-15
      raise "probability continuous-time transition tolerance is below the binary64 floor"
    if !ProbabilityNumerics.integer?(max_terms) || max_terms <= 0
      raise "probability continuous-time transition term limit must be a positive integer"

    initial_probabilities = ProbabilityNumerics.normalized_weights(
      initial, "continuous-time transition initial weights")
    if initial_probabilities.size != state_count
      raise "probability continuous-time transition initial weights have the wrong dimension"

    minimum_rate = maximum_exit_rate
    chosen_rate = minimum_rate
    if rate != nil
      chosen_rate = ProbabilityNumerics.nonnegative_finite(
        rate, "continuous-time uniformization rate")
      if chosen_rate < minimum_rate
        raise "probability continuous-time uniformization rate must dominate every exit rate"

    poisson_mean = chosen_rate*duration
    if poisson_mean != poisson_mean || poisson_mean.infinite? || (
       poisson_mean > ~500.0)
      raise ("probability continuous-time uniformization rate*time exceeds " +
             "the binary64 zero-origin limit of 500")

    if duration == ~0.0 || chosen_rate == ~0.0
      return ContinuousTimeMarkovTransitionResult.new(
        initial_probabilities, duration, chosen_rate, poisson_mean,
        1, ~1.0, ~0.0, requested_tolerance)

    transition = []
    row = 0
    while row < state_count
      transition_row = []
      column = 0
      while column < state_count
        value = @generator[row][column] / chosen_rate
        value += ~1.0 if row == column
        if value != value || value.infinite? || value < ~0.0
          raise "probability continuous-time uniformized transition is not stochastic"
        transition_row.push(value)
        column += 1
      row_mass = ProbabilityNumerics.sum(transition_row)
      if ProbabilityLinearAlgebra.absolute(row_mass - ~1.0) > ~1.0e-12
        raise "probability continuous-time uniformized transition row lost mass"
      transition.push(transition_row)
      row += 1

    weight = Math.exp(~0.0 - poisson_mean)
    state = ProbabilityNumerics.copy_array(initial_probabilities)
    probabilities = []
    probability_corrections = []
    i = 0
    while i < state_count
      probabilities.push(weight*state[i])
      probability_corrections.push(~0.0)
      i += 1

    retained_poisson_mass = weight
    retained_correction = ~0.0
    term_index = 0
    term_count = 1
    poisson_tail_bound = ~1.0
    if (term_index + ~2.0) > poisson_mean
      next_weight = weight*poisson_mean / (term_index + ~1.0)
      tail_ratio = poisson_mean / (term_index + ~2.0)
      poisson_tail_bound = (
        next_weight / (~1.0 - tail_ratio))*~1.000000000001
      poisson_tail_bound = ~1.0 if poisson_tail_bound > ~1.0
    while poisson_tail_bound > requested_tolerance
      if term_count >= max_terms
        raise "probability continuous-time uniformization term limit exceeded"

      next_state = []
      column = 0
      while column < state_count
        total = ~0.0
        correction = ~0.0
        row = 0
        while row < state_count
          product = state[row]*transition[row][column]
          adjusted = product - correction
          next_total = total + adjusted
          correction = (next_total - total) - adjusted
          total = next_total
          row += 1
        if total != total || total.infinite? || total < ~0.0
          raise "probability continuous-time uniformization state became invalid"
        next_state.push(total)
        column += 1
      state = next_state

      term_index += 1
      weight *= poisson_mean / (term_index + ~0.0)
      if weight != weight || weight.infinite? || weight == ~0.0
        raise "probability continuous-time uniformization Poisson recurrence failed"

      i = 0
      while i < state_count
        contribution = weight*state[i]
        adjusted = contribution - probability_corrections[i]
        next_probability = probabilities[i] + adjusted
        probability_corrections[i] = (
          (next_probability - probabilities[i]) - adjusted)
        probabilities[i] = next_probability
        i += 1

      adjusted_weight = weight - retained_correction
      next_retained = retained_poisson_mass + adjusted_weight
      retained_correction = (
        (next_retained - retained_poisson_mass) - adjusted_weight)
      retained_poisson_mass = next_retained
      if retained_poisson_mass > ~1.0 + ~1.0e-12
        raise "probability continuous-time uniformization Poisson mass exceeded one"
      term_count += 1
      if (term_index + ~2.0) > poisson_mean
        next_weight = weight*poisson_mean / (term_index + ~1.0)
        tail_ratio = poisson_mean / (term_index + ~2.0)
        poisson_tail_bound = (
          next_weight / (~1.0 - tail_ratio))*~1.000000000001
        poisson_tail_bound = ~1.0 if poisson_tail_bound > ~1.0

    ContinuousTimeMarkovTransitionResult.new(
      probabilities, duration, chosen_rate, poisson_mean, term_count,
      retained_poisson_mass, poisson_tail_bound, requested_tolerance)
