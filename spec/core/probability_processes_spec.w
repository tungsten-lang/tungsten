# Finite-state Markov, Wiener, and Poisson process contracts.

use probability

-> process_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> process_close?(got, want, tolerance = ~1.0e-11)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

# --- finite-state Markov chains ------------------------------------------

alternating = Probability.markov_chain(
  [~1.0, ~0.0], [[~0.0, ~1.0], [~1.0, ~0.0]])
path = alternating.sample_path(7, Probability.rng(1))
process_check("markov.deterministic.path",
              path[0] == 0 && path[1] == 1 && path[2] == 0 &&
              path[3] == 1 && path[4] == 0 && path[5] == 1 && path[6] == 0)
process_check("markov.path.log_probability",
              alternating.path_log_probability(path) == ~0.0)
process_check("markov.transition",
              alternating.transition_probability(0, 1) == ~1.0 &&
              alternating.transition_probability(0, 0) == ~0.0)

chain = Probability.markov_chain(
  [~1.0, ~3.0], [[~9.0, ~1.0], [~2.0, ~8.0]])
process_check("markov.normalization",
              process_close?(chain.initial_probabilities[0], ~0.25) &&
              process_close?(chain.transition_matrix[0][1], ~0.1))
left_path = chain.sample_path(100, Probability.rng(31415))
right_path = chain.sample_path(100, Probability.rng(31415))
markov_replay = true
markov_supported = true
i = 0
while i < left_path.size
  markov_replay = false if left_path[i] != right_path[i]
  markov_supported = false if left_path[i] < 0 || left_path[i] >= 2
  i += 1
process_check("markov.replay", markov_replay)
process_check("markov.states", markov_supported)
known_log = Math.log(~0.25) + Math.log(~0.9) + Math.log(~0.1)
process_check("markov.path.measure",
              process_close?(chain.path_log_probability([0, 0, 1]), known_log))

# --- Wiener process -------------------------------------------------------

wiener = Probability.wiener(~2.0, ~3.0)
process_check("wiener.moments",
              wiener.mean(~4.0, ~1.0) == ~9.0 &&
              wiener.variance(~4.0) == ~36.0)
transition = wiener.transition_distribution(~1.0, ~5.0, ~3.0)
process_check("wiener.transition",
              transition.mean == ~9.0 &&
              process_close?(transition.variance, ~18.0))
grid = [~0.0, ~0.25, ~0.25, ~1.0, ~2.0]
left_values = wiener.sample_grid(grid, Probability.rng(2718), ~4.0)
right_values = wiener.sample_grid(grid, Probability.rng(2718), ~4.0)
wiener_replay = true
i = 0
while i < left_values.size
  wiener_replay = false if left_values[i] != right_values[i]
  i += 1
process_check("wiener.replay", wiener_replay)
process_check("wiener.initial", left_values[0] == ~4.0)
process_check("wiener.repeated.time", left_values[1] == left_values[2])
regular_path = Probability.wiener.sample_path(
  8, ~0.125, Probability.rng(4))
process_check("wiener.path.shape", regular_path.size == 9)
wiener_vector = Probability.wiener(~0.1, ~2.0).sample_grid(
  [~0.0, ~0.25, ~0.5, ~1.0], Probability.rng(4))
process_check("wiener.path.vector",
              process_close?(wiener_vector[0], ~0.0) &&
              process_close?(wiener_vector[1], ~-1.105524162579106) &&
              process_close?(wiener_vector[2], ~-0.4641228186745612) &&
              process_close?(wiener_vector[3], ~-1.4452589950910386))

# --- homogeneous Poisson process ----------------------------------------

poisson_process = Probability.poisson_process(~3.0)
process_check("poisson_process.moments",
              poisson_process.expected_count(~2.0) == ~6.0 &&
              poisson_process.variance(~2.0) == ~6.0)
increment = poisson_process.increment_distribution(~2.0)
process_check("poisson_process.increment",
              increment.class_name == "PoissonDistribution" &&
              increment.rate == ~6.0)
left_arrivals = poisson_process.sample_arrivals(100, Probability.rng(1618))
right_arrivals = poisson_process.sample_arrivals(100, Probability.rng(1618))
arrival_replay = true
arrival_ordered = true
i = 0
while i < left_arrivals.size
  arrival_replay = false if left_arrivals[i] != right_arrivals[i]
  if i > 0 && left_arrivals[i] < left_arrivals[i - 1]
    arrival_ordered = false
  i += 1
process_check("poisson_process.replay", arrival_replay)
process_check("poisson_process.arrivals.ordered", arrival_ordered)
counts = poisson_process.sample_grid(
  [~0.0, ~0.5, ~1.0, ~2.0, ~4.0], Probability.rng(55))
counts_ordered = counts[0] == 0
i = 1
while i < counts.size
  counts_ordered = false if counts[i] < counts[i - 1]
  i += 1
process_check("poisson_process.grid.counts", counts_ordered)
process_check("poisson_process.count.replay",
              poisson_process.count_until(~2.0, Probability.rng(91)) ==
              poisson_process.count_until(~2.0, Probability.rng(91)))

bad_markov_failed = false
begin
  Probability.markov_chain([~1.0, ~1.0], [[~1.0, ~0.0]])
rescue error
  bad_markov_failed = error.to_s.include?("must be square")
process_check("failure.markov.shape", bad_markov_failed)

bad_grid_failed = false
begin
  Probability.wiener.sample_grid(
    [~1.0, ~0.5], Probability.rng(1))
rescue error
  bad_grid_failed = error.to_s.include?("nondecreasing")
process_check("failure.wiener.grid", bad_grid_failed)
wiener_failed_rng = Probability.rng(77)
wiener_grid_rejected = false
begin
  Probability.wiener.sample_grid([~0.5, ~0.25], wiener_failed_rng)
rescue error
  wiener_grid_rejected = true
# Validation must finish before a path consumes randomness.
process_check("failure.wiener.grid.preserves_rng",
              wiener_grid_rejected &&
              wiener_failed_rng.next_u32 == Probability.rng(77).next_u32)

poisson_failed_rng = Probability.rng(78)
poisson_grid_rejected = false
begin
  poisson_process.sample_grid([~0.5, ~0.25], poisson_failed_rng)
rescue error
  poisson_grid_rejected = true
# The same transaction boundary applies to counting grids.
process_check("failure.poisson.grid.preserves_rng",
              poisson_grid_rejected &&
              poisson_failed_rng.next_u32 == Probability.rng(78).next_u32)

bad_horizon_failed = false
begin
  poisson_process.count_until(~1.0, Probability.rng(1), ~2.0)
rescue error
  bad_horizon_failed = error.to_s.include?("must not precede")
process_check("failure.poisson.horizon", bad_horizon_failed)

<< "probability_processes_spec: all checks passed"
