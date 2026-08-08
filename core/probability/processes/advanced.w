# Continuous-time chains, hidden Markov models, scalar SDE integration, and
# renewal processes.

use core/math
use core/probability/distribution
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/process
use core/probability/processes
use core/probability/rng
use core/probability/sampling

+ ContinuousTimeMarkovPath
  -> new(times, states)
    @times = ProbabilityNumerics.copy_array(times)
    @states = ProbabilityNumerics.copy_array(states)
    self

  -> times
    ProbabilityNumerics.copy_array(@times)

  -> states
    ProbabilityNumerics.copy_array(@states)

  -> jump_count
    @states.size == 0 ? 0 : @states.size - 1

  -> state_at(time)
    query = ProbabilityNumerics.nonnegative_finite(time, "path query time")
    if @times.size == 0 || query < @times[0]
      raise "probability path query precedes path start"
    index = 0
    while index + 1 < @times.size && @times[index + 1] <= query
      index += 1
    @states[index]


+ ContinuousTimeMarkovChain < StochasticProcess
  -> new(initial, generator)
    @initial = ProbabilityNumerics.normalized_weights(
      initial, "continuous-time Markov initial weights")
    @generator = ProbabilityLinearAlgebra.square_matrix(
      generator, @initial.size, "continuous-time Markov generator")
    @exit_rates = []
    @jump_cumulative = []
    row = 0
    while row < @generator.size
      magnitudes = []
      maximum_magnitude = ~0.0
      column = 0
      while column < @generator.size
        value = @generator[row][column]
        if row != column && value < ~0.0
          raise "probability Markov generator off-diagonal entries must be nonnegative"
        if row == column && value > ~0.0
          raise "probability Markov generator diagonal entries must be nonpositive"
        magnitude = ProbabilityLinearAlgebra.absolute(value)
        magnitudes.push(magnitude)
        maximum_magnitude = magnitude if magnitude > maximum_magnitude
        column += 1
      scaled_entries = []
      scaled_magnitudes = []
      column = 0
      while column < @generator.size
        if maximum_magnitude == ~0.0
          scaled_entries.push(~0.0)
          scaled_magnitudes.push(~0.0)
        else
          scaled_entries.push(@generator[row][column] / maximum_magnitude)
          scaled_magnitudes.push(magnitudes[column] / maximum_magnitude)
        column += 1
      total = ProbabilityNumerics.sum(scaled_entries)
      scale = ProbabilityNumerics.sum(scaled_magnitudes)
      # Thirty-two binary64 epsilons relative to the row's actual L1 scale.
      # Scaling by the largest entry avoids row-scale overflow in this
      # comparison. There is deliberately no absolute floor: a tiny
      # nonconservative row is still not a CTMC generator.
      row_tolerance = ~7.105427357601002e-15*scale
      if ProbabilityLinearAlgebra.absolute(total) > row_tolerance
        raise "probability Markov generator rows must sum to zero"
      rate = ~0.0 - @generator[row][row]
      @exit_rates.push(rate)
      if rate > ~0.0
        weights = []
        column = 0
        while column < @generator.size
          weights.push(row == column ? ~0.0 : @generator[row][column])
          column += 1
        probabilities = ProbabilityNumerics.normalized_weights(
          weights, "continuous-time Markov jump rates")
        @jump_cumulative.push(
          ProbabilityNumerics.cumulative_probabilities(probabilities))
      else
        @jump_cumulative.push([])
      row += 1
    @initial_cumulative = ProbabilityNumerics.cumulative_probabilities(@initial)
    self

  -> state_count
    @initial.size

  -> generator
    ProbabilityLinearAlgebra.copy_matrix(@generator)

  -> exit_rates
    ProbabilityNumerics.copy_array(@exit_rates)

  -> sample_path(horizon, rng, initial_state = nil, max_events = 1000000)
    limit = ProbabilityNumerics.nonnegative_finite(
      horizon, "continuous-time Markov horizon")
    ProbabilityNumerics.validate_count(max_events, "continuous-time event limit")
    ProbabilityRandom.require_rng(rng)
    state = initial_state
    if state == nil
      state = ProbabilitySampling.categorical_from_cumulative(
        @initial_cumulative, rng)
    elsif !ProbabilityNumerics.integer?(state) || state < 0 || state >= state_count
      raise "probability continuous-time Markov state is out of range"
    times = [~0.0]
    states = [state]
    time = ~0.0
    events = 0
    while time < limit && @exit_rates[state] > ~0.0
      waiting = (~0.0 - Math.log1p(
        ~0.0 - ProbabilityRandom.random_unit(rng))) / @exit_rates[state]
      break if time + waiting > limit
      if events >= max_events
        raise "probability continuous-time Markov event limit exceeded"
      time += waiting
      state = ProbabilitySampling.categorical_from_cumulative(
        @jump_cumulative[state], rng)
      times.push(time)
      states.push(state)
      events += 1
    ContinuousTimeMarkovPath.new(times, states)


+ HiddenMarkovSequence
  -> new(states, observations)
    @states = ProbabilityNumerics.copy_array(states)
    @observations = ProbabilityNumerics.copy_array(observations)
    self

  -> states
    ProbabilityNumerics.copy_array(@states)

  -> observations
    ProbabilityNumerics.copy_array(@observations)


+ HiddenMarkovModel < StochasticProcess
  -> new(initial, transitions, emissions)
    @chain = FiniteMarkovChain.new(initial, transitions)
    if emissions.class_name != "Array" || emissions.size != @chain.state_count
      raise "probability hidden Markov emissions must match state count"
    @emissions = ProbabilityNumerics.copy_array(emissions)
    i = 0
    while i < @emissions.size
      if !@emissions[i].respond_to?("log_prob") || !@emissions[i].respond_to?("sample")
        raise "probability hidden Markov emissions must be distributions"
      i += 1
    @initial = @chain.initial_probabilities
    @transitions = @chain.transition_matrix
    self

  -> state_count
    @chain.state_count

  -> sample_path(length, rng)
    states = @chain.sample_path(length, rng)
    observations = []
    i = 0
    while i < states.size
      observations.push(@emissions[states[i]].sample(rng))
      i += 1
    HiddenMarkovSequence.new(states, observations)

  -> forward(observations)
    if observations.class_name != "Array" || observations.size == 0
      raise "probability hidden Markov observations must be nonempty"
    log_alpha = []
    state = 0
    while state < state_count
      initial_log = @initial[state] == ~0.0 ? (
        ProbabilityNumerics.negative_infinity) : Math.log(@initial[state])
      log_alpha.push(initial_log + @emissions[state].log_prob(observations[0]))
      state += 1
    normalizer = ProbabilityNumerics.logsumexp(log_alpha)
    if normalizer.infinite?
      raise "probability hidden Markov observation has zero probability"
    log_likelihood = normalizer
    state = 0
    while state < state_count
      log_alpha[state] = log_alpha[state] - normalizer
      state += 1
    filters = [ProbabilityNumerics.normalize_log_weights(log_alpha)]
    time = 1
    while time < observations.size
      next_alpha = []
      to_state = 0
      while to_state < state_count
        terms = []
        from_state = 0
        while from_state < state_count
          transition = @transitions[from_state][to_state]
          term = ProbabilityNumerics.negative_infinity
          if transition > ~0.0
            term = log_alpha[from_state] + Math.log(transition)
          terms.push(term)
          from_state += 1
        predicted = ProbabilityNumerics.logsumexp(terms)
        next_alpha.push(
          predicted + @emissions[to_state].log_prob(observations[time]))
        to_state += 1
      normalizer = ProbabilityNumerics.logsumexp(next_alpha)
      if normalizer.infinite?
        raise "probability hidden Markov observation has zero probability"
      log_likelihood += normalizer
      state = 0
      while state < state_count
        next_alpha[state] = next_alpha[state] - normalizer
        state += 1
      log_alpha = next_alpha
      filters.push(ProbabilityNumerics.normalize_log_weights(log_alpha))
      time += 1
    [log_likelihood, filters]

  -> log_probability(observations)
    forward(observations)[0]

  -> filtered_probabilities(observations)
    forward(observations)[1]

  -> viterbi(observations)
    if observations.class_name != "Array" || observations.size == 0
      raise "probability hidden Markov observations must be nonempty"
    scores = []
    state = 0
    while state < state_count
      initial_log = @initial[state] == ~0.0 ? (
        ProbabilityNumerics.negative_infinity) : Math.log(@initial[state])
      scores.push(initial_log + @emissions[state].log_prob(observations[0]))
      state += 1
    backpointers = []
    time = 1
    while time < observations.size
      next_scores = []
      pointers = []
      to_state = 0
      while to_state < state_count
        best_state = 0
        best_score = ProbabilityNumerics.negative_infinity
        from_state = 0
        while from_state < state_count
          transition = @transitions[from_state][to_state]
          score = ProbabilityNumerics.negative_infinity
          if transition > ~0.0
            score = scores[from_state] + Math.log(transition)
          if score > best_score
            best_score = score
            best_state = from_state
          from_state += 1
        next_scores.push(
          best_score + @emissions[to_state].log_prob(observations[time]))
        pointers.push(best_state)
        to_state += 1
      scores = next_scores
      backpointers.push(pointers)
      time += 1
    final_state = 0
    state = 1
    while state < state_count
      final_state = state if scores[state] > scores[final_state]
      state += 1
    if scores[final_state].infinite?
      raise "probability hidden Markov observation has zero probability"
    path = []
    observations.size.times -> path.push(0)
    path[observations.size - 1] = final_state
    time = observations.size - 2
    while time >= 0
      path[time] = backpointers[time][path[time + 1]]
      time -= 1
    path


+ ScalarSdePath
  -> new(times, values)
    @times = ProbabilityNumerics.copy_array(times)
    @values = ProbabilityNumerics.copy_array(values)
    self

  -> times
    ProbabilityNumerics.copy_array(@times)

  -> values
    ProbabilityNumerics.copy_array(@values)


+ StochasticNumerics
  -> .coefficient(callback, time, value, parameter)
    ProbabilityNumerics.finite_float(callback(time, value), parameter)


+ EulerMaruyamaProcess < StochasticProcess
  -> new(drift, diffusion)
    @drift = drift
    @diffusion = diffusion
    self

  -> sample_grid(initial, times, rng)
    origin = ProbabilityNumerics.finite_float(initial, "SDE initial value")
    if times.class_name != "Array" || times.size == 0
      raise "probability SDE times must be a nonempty Array"
    ProbabilityRandom.require_rng(rng)
    validated = []
    previous = nil
    i = 0
    while i < times.size
      time = ProbabilityNumerics.finite_float(times[i], "SDE time")
      if previous != nil && time <= previous
        raise "probability SDE times must be strictly increasing"
      validated.push(time)
      previous = time
      i += 1
    values = [origin]
    current = origin
    i = 1
    while i < validated.size
      dt = validated[i] - validated[i - 1]
      drift = StochasticNumerics.coefficient(
        @drift, validated[i - 1], current, "SDE drift")
      diffusion = StochasticNumerics.coefficient(
        @diffusion, validated[i - 1], current, "SDE diffusion")
      increment = drift*dt
      if diffusion != ~0.0
        increment = (increment + diffusion*Math.sqrt(dt)*
          ProbabilityRandom.standard_normal(rng))
      current += increment
      if current != current || current.infinite?
        raise "probability SDE path became nonfinite"
      values.push(current)
      i += 1
    ScalarSdePath.new(validated, values)

  -> sample_path(initial, start, step_size, steps, rng)
    begin_time = ProbabilityNumerics.finite_float(start, "SDE start time")
    dt = ProbabilityNumerics.positive_finite(step_size, "SDE step size")
    ProbabilityNumerics.validate_count(steps, "SDE step count")
    times = []
    i = 0
    while i <= steps
      times.push(begin_time + (i + ~0.0)*dt)
      i += 1
    sample_grid(initial, times, rng)


+ RenewalProcess < StochasticProcess
  -> new(interarrival_distribution)
    if !interarrival_distribution.respond_to?("sample")
      raise "probability renewal interarrival must be a distribution"
    @interarrival = interarrival_distribution
    self

  -> interarrival_distribution
    @interarrival

  -> next_waiting_time(rng)
    waiting = @interarrival.sample(rng).to_f
    if waiting <= ~0.0 || waiting != waiting || waiting.infinite?
      raise "probability renewal interarrival draw must be finite and positive"
    waiting

  -> sample_arrivals(count, rng, start = ~0.0)
    ProbabilityNumerics.validate_count(count, "renewal arrival count")
    ProbabilityRandom.require_rng(rng)
    time = ProbabilityNumerics.finite_float(start, "renewal start")
    arrivals = []
    count.times ->
      time += next_waiting_time(rng)
      arrivals.push(time)
    arrivals

  -> count_until(horizon, rng, start = ~0.0, max_events = 1000000)
    limit = ProbabilityNumerics.finite_float(horizon, "renewal horizon")
    time = ProbabilityNumerics.finite_float(start, "renewal start")
    if limit < time
      raise "probability renewal horizon must not precede start"
    ProbabilityNumerics.validate_count(max_events, "renewal event limit")
    ProbabilityRandom.require_rng(rng)
    count = 0
    next_time = time + next_waiting_time(rng)
    while next_time <= limit
      if count >= max_events
        raise "probability renewal event limit exceeded"
      count += 1
      next_time += next_waiting_time(rng)
    count
