# Finite-state Markov, Wiener, and homogeneous Poisson processes.

use core/math
use core/probability/process
use core/probability/primitives
use core/probability/rng
use core/probability/sampling
use core/probability/distributions/elementary
use core/probability/distributions/discrete

+ FiniteMarkovChain < StochasticProcess
  -> new(initial, transitions)
    @initial = ProbabilityNumerics.normalized_weights(
      initial, "Markov initial weights")
    if transitions.class_name != "Array" || (
       transitions.size != @initial.size)
      raise "probability Markov transition matrix must be square"
    @transitions = []
    @cumulative = []
    i = 0
    while i < transitions.size
      row = transitions[i]
      if row.class_name != "Array" || row.size != @initial.size
        raise "probability Markov transition matrix must be square"
      normalized = ProbabilityNumerics.normalized_weights(
        row, "Markov transition row")
      @transitions.push(normalized)
      @cumulative.push(
        ProbabilityNumerics.cumulative_probabilities(normalized))
      i += 1
    @initial_cumulative = ProbabilityNumerics.cumulative_probabilities(@initial)
    self

  -> state_count
    @initial.size

  -> initial_probabilities
    ProbabilityNumerics.copy_array(@initial)

  -> transition_matrix
    matrix = []
    i = 0
    while i < @transitions.size
      matrix.push(ProbabilityNumerics.copy_array(@transitions[i]))
      i += 1
    matrix

  -> validate_state(state)
    if !ProbabilityNumerics.integer?(state) || state < 0 || state >= state_count
      raise "probability Markov state is out of range"
    state

  -> transition_probability(from, to)
    validate_state(from)
    validate_state(to)
    @transitions[from][to]

  -> step(state, rng)
    validate_state(state)
    ProbabilitySampling.categorical_from_cumulative(@cumulative[state], rng)

  -> sample_path(length, rng, initial_state = nil)
    ProbabilityNumerics.validate_count(length, "Markov path length")
    ProbabilityRandom.require_rng(rng)
    return [] if length == 0
    state = initial_state
    if state == nil
      state = ProbabilitySampling.categorical_from_cumulative(
        @initial_cumulative, rng)
    else
      validate_state(state)
    path = [state]
    while path.size < length
      state = step(state, rng)
      path.push(state)
    path

  -> path_log_probability(path)
    if path.class_name != "Array"
      raise "probability Markov path must be an Array"
    return ~0.0 if path.size == 0
    validate_state(path[0])
    probability = @initial[path[0]]
    return ProbabilityNumerics.negative_infinity if probability == ~0.0
    total = Math.log(probability)
    i = 1
    while i < path.size
      validate_state(path[i])
      transition = @transitions[path[i - 1]][path[i]]
      return ProbabilityNumerics.negative_infinity if transition == ~0.0
      total += Math.log(transition)
      i += 1
    total

  -> to_s
    "FiniteMarkovChain(states=" + state_count.to_s + ")"


+ WienerProcess < StochasticProcess
  -> new(drift = ~0.0, volatility = ~1.0)
    @drift = ProbabilityNumerics.finite_float(drift, "Wiener drift")
    @volatility = ProbabilityNumerics.positive_finite(
      volatility, "Wiener volatility")
    self

  -> drift
    @drift

  -> volatility
    @volatility

  -> validate_time(time)
    value = ProbabilityNumerics.finite_float(time, "Wiener time")
    raise "probability Wiener time must be nonnegative" if value < ~0.0
    value

  -> mean(time, initial = ~0.0)
    t = validate_time(time)
    origin = ProbabilityNumerics.finite_float(initial, "Wiener initial value")
    origin + @drift*t

  -> variance(time)
    t = validate_time(time)
    @volatility*@volatility*t

  -> transition_distribution(from_time, from_value, to_time)
    left = validate_time(from_time)
    right = validate_time(to_time)
    if right <= left
      raise "probability Wiener transition needs increasing times"
    elapsed = right - left
    origin = ProbabilityNumerics.finite_float(
      from_value, "Wiener transition value")
    NormalDistribution.new(
      origin + @drift*elapsed,
      @volatility*Math.sqrt(elapsed))

  -> sample_grid(times, rng, initial = ~0.0)
    if times.class_name != "Array"
      raise "probability Wiener grid must be an Array"
    ProbabilityRandom.require_rng(rng)
    validated_times = []
    previous_time = ~0.0
    i = 0
    while i < times.size
      time = validate_time(times[i])
      if time < previous_time
        raise "probability Wiener grid must be nondecreasing"
      validated_times.push(time)
      previous_time = time
      i += 1
    values = []
    previous_time = ~0.0
    current = ProbabilityNumerics.finite_float(initial, "Wiener initial value")
    i = 0
    while i < validated_times.size
      elapsed = validated_times[i] - previous_time
      if elapsed > ~0.0
        current += (@drift*elapsed + @volatility*Math.sqrt(elapsed)*
                    ProbabilityRandom.standard_normal(rng))
      values.push(current)
      previous_time = validated_times[i]
      i += 1
    values

  # `steps` is the number of increments; the returned path has steps+1 values.
  -> sample_path(steps, step_size, rng, initial = ~0.0)
    ProbabilityNumerics.validate_count(steps, "Wiener step count")
    dt = ProbabilityNumerics.positive_finite(
      step_size, "Wiener step size")
    times = []
    i = 0
    while i <= steps
      times.push((i + ~0.0)*dt)
      i += 1
    sample_grid(times, rng, initial)

  -> to_s
    ("WienerProcess(drift=" + @drift.to_s +
     ", volatility=" + @volatility.to_s + ")")


+ PoissonProcess < StochasticProcess
  -> new(rate)
    @rate = ProbabilityNumerics.positive_finite(rate, "Poisson process rate")
    self

  -> rate
    @rate

  -> expected_count(duration)
    time = ProbabilityNumerics.nonnegative_finite(
      duration, "Poisson process duration")
    @rate*time

  -> variance(duration)
    expected_count(duration)

  -> increment_distribution(duration)
    time = ProbabilityNumerics.positive_finite(
      duration, "Poisson process increment duration")
    PoissonDistribution.new(@rate*time)

  -> sample_arrivals(count, rng, start = ~0.0)
    ProbabilityNumerics.validate_count(count, "Poisson arrival count")
    ProbabilityRandom.require_rng(rng)
    current = ProbabilityNumerics.finite_float(
      start, "Poisson process start")
    arrivals = []
    waiting = ExponentialDistribution.new(@rate)
    i = 0
    while i < count
      current += waiting.sample(rng)
      arrivals.push(current)
      i += 1
    arrivals

  -> sample_path(count, rng, start = ~0.0)
    sample_arrivals(count, rng, start)

  -> count_until(horizon, rng, start = ~0.0, max_events = 1000000)
    limit = ProbabilityNumerics.finite_float(
      horizon, "Poisson process horizon")
    origin = ProbabilityNumerics.finite_float(
      start, "Poisson process start")
    if limit < origin
      raise "probability Poisson horizon must not precede start"
    ProbabilityNumerics.validate_count(max_events, "Poisson event limit")
    ProbabilityRandom.require_rng(rng)
    waiting = ExponentialDistribution.new(@rate)
    next_arrival = origin + waiting.sample(rng)
    count = 0
    while next_arrival <= limit
      if count >= max_events
        raise "probability Poisson event limit exceeded"
      count += 1
      next_arrival += waiting.sample(rng)
    count

  -> sample_grid(times, rng, max_events = 1000000)
    if times.class_name != "Array"
      raise "probability Poisson grid must be an Array"
    ProbabilityNumerics.validate_count(max_events, "Poisson event limit")
    ProbabilityRandom.require_rng(rng)
    return [] if times.size == 0
    validated_times = []
    previous_time = ~0.0
    i = 0
    while i < times.size
      time = ProbabilityNumerics.nonnegative_finite(
        times[i], "Poisson grid time")
      if time < previous_time
        raise "probability Poisson grid must be nondecreasing"
      validated_times.push(time)
      previous_time = time
      i += 1
    waiting = ExponentialDistribution.new(@rate)
    next_arrival = waiting.sample(rng)
    previous_time = ~0.0
    count = 0
    counts = []
    i = 0
    while i < validated_times.size
      while next_arrival <= validated_times[i]
        if count >= max_events
          raise "probability Poisson event limit exceeded"
        count += 1
        next_arrival += waiting.sample(rng)
      counts.push(count)
      previous_time = validated_times[i]
      i += 1
    counts

  -> to_s
    "PoissonProcess(rate=" + @rate.to_s + ")"
