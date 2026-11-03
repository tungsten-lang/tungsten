# Dense finite-state CTMC transition actions by Poisson uniformization.

use probability

-> ctmc_uniformization_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> ctmc_uniformization_close?(got, want, tolerance = ~1.0e-11)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance*scale

# --- analytic two-state chain and row convention ------------------------

alpha = ~1.7
beta = ~0.4
time = ~2.3
chain = Probability.continuous_time_markov_chain(
  [~1.0, ~0.0], [[~0.0 - alpha, alpha], [beta, ~0.0 - beta]])
result = chain.uniformize(time, ~1.0e-14)
decay = Math.exp((~0.0 - alpha - beta)*time)
expected_left = beta/(alpha + beta) + alpha/(alpha + beta)*decay
expected_right = alpha/(alpha + beta)*(~1.0 - decay)

ctmc_uniformization_check("two_state.reference",
  ctmc_uniformization_close?(
    result.probabilities[0], expected_left, ~3.0e-14) &&
  ctmc_uniformization_close?(
    result.probabilities[1], expected_right, ~3.0e-14))
ctmc_uniformization_check("two_state.metadata",
  result.class_name == "ContinuousTimeMarkovTransitionResult" &&
  result.time == time && result.rate == alpha &&
  ctmc_uniformization_close?(result.poisson_mean, alpha*time) &&
  result.terms > 1 && result.poisson_tail_bound <= ~1.0e-14 &&
  !result.certified? &&
  result.algorithm == "dense-poisson-uniformization-zero-origin")
ctmc_uniformization_check("two_state.mass.observable",
  ctmc_uniformization_close?(
    result.probability_mass, result.retained_poisson_mass, ~4.0e-15))
ctmc_uniformization_check("chain.metadata",
  chain.maximum_exit_rate == alpha &&
  chain.initial_probabilities[0] == ~1.0 &&
  chain.initial_probabilities[1] == ~0.0)

copied = result.probabilities
copied[0] = ~99.0
initial_copy = chain.initial_probabilities
initial_copy[0] = ~0.0
ctmc_uniformization_check("result.defensive_copy",
  result.probabilities[0] != ~99.0 &&
  chain.initial_probabilities[0] == ~1.0)

# --- absorbing, zero, explicit-rate, and arbitrary initial actions -------

absorbing = Probability.continuous_time_markov_chain(
  [~1.0, ~0.0], [[~-2.0, ~2.0], [~0.0, ~0.0]])
absorbing_result = absorbing.uniformize(~1.25, ~1.0e-13)
ctmc_uniformization_check("absorbing.reference",
  ctmc_uniformization_close?(
    absorbing_result.probabilities[0], Math.exp(~-2.5), ~2.0e-13) &&
  ctmc_uniformization_close?(
    absorbing_result.probabilities[1], ~1.0 - Math.exp(~-2.5), ~2.0e-13))

zero = Probability.continuous_time_markov_chain(
  [~0.25, ~0.75], [[~0.0, ~0.0], [~0.0, ~0.0]])
zero_result = zero.uniformize(~1000000000.0)
ctmc_uniformization_check("zero_generator.identity",
  zero_result.probabilities[0] == ~0.25 &&
  zero_result.probabilities[1] == ~0.75 &&
  zero_result.rate == ~0.0 && zero_result.terms == 1 &&
  zero_result.estimated_omitted_poisson_mass == ~0.0 &&
  zero_result.poisson_tail_bound == ~0.0)

zero_time = absorbing.uniformize(~0.0)
ctmc_uniformization_check("zero_time.identity",
  zero_time.probabilities[0] == ~1.0 &&
  zero_time.probabilities[1] == ~0.0 && zero_time.terms == 1)

explicit_rate = chain.uniformize(time, ~1.0e-14, 100000, ~3.0)
ctmc_uniformization_check("explicit_rate.invariant",
  ctmc_uniformization_close?(
    explicit_rate.probabilities[0], result.probabilities[0], ~5.0e-14) &&
  ctmc_uniformization_close?(
    explicit_rate.probabilities[1], result.probabilities[1], ~5.0e-14))

from_second = chain.uniformize_from(
  [~0.0, ~2.0], time, ~1.0e-14)
expected_from_second_left = beta/(alpha + beta)*(~1.0 - decay)
ctmc_uniformization_check("explicit_initial.normalized",
  ctmc_uniformization_close?(
    from_second.probabilities[0], expected_from_second_left, ~3.0e-14))

# A deliberately loose tolerance leaves visible, unnormalized Poisson mass.
loose = absorbing.uniformize(~0.8, ~1.0e-5)
ctmc_uniformization_check("truncation.not_renormalized",
  loose.estimated_omitted_poisson_mass > ~0.0 &&
  loose.poisson_tail_bound <= ~1.0e-5 &&
  loose.probability_mass < ~1.0 &&
  ctmc_uniformization_close?(
    loose.probability_mass, loose.retained_poisson_mass, ~2.0e-14))

tight = absorbing.uniformize(~0.8, ~1.0e-12)
ctmc_uniformization_check("truncation.tolerance.monotone",
  tight.terms >= loose.terms &&
  tight.poisson_tail_bound <= loose.poisson_tail_bound &&
  ctmc_uniformization_close?(
    tight.retained_poisson_mass + tight.estimated_omitted_poisson_mass,
    ~1.0, ~1.0e-15))

boundary = absorbing.uniformize(~250.0, ~1.0e-12)
ctmc_uniformization_check("poisson_mean.boundary",
  boundary.poisson_mean == ~500.0 && boundary.terms > 500 &&
  boundary.poisson_tail_bound <= ~1.0e-12 &&
  boundary.probabilities[0] > ~0.0 &&
  ctmc_uniformization_close?(
    boundary.probability_mass, boundary.retained_poisson_mass, ~2.0e-13))

# This catches cancellation in 1-retained_mass near the tolerance floor. The
# geometric tail criterion must continue beyond the earlier false stop.
floor_edge = absorbing.uniformize(~249.5, ~1.0e-15)
ctmc_uniformization_check("poisson_tail.floor_guard",
  floor_edge.poisson_mean == ~499.0 && floor_edge.terms > 684 &&
  floor_edge.poisson_tail_bound <= ~1.0e-15)

stationary = [beta/(alpha + beta), alpha/(alpha + beta)]
stationary_result = chain.uniformize_from(stationary, time, ~1.0e-14)
ctmc_uniformization_check("stationary.initial",
  ctmc_uniformization_close?(
    stationary_result.probabilities[0],
    stationary[0]*stationary_result.retained_poisson_mass, ~4.0e-14) &&
  ctmc_uniformization_close?(
    stationary_result.probabilities[1],
    stationary[1]*stationary_result.retained_poisson_mass, ~4.0e-14))

three_state = Probability.continuous_time_markov_chain(
  [~0.2, ~0.3, ~0.5],
  [[~-3.0, ~1.0, ~2.0],
   [~0.5, ~-1.0, ~0.5],
   [~0.25, ~0.75, ~-1.0]])
three_state_result = three_state.uniformize(~0.8, ~1.0e-14)
ctmc_uniformization_check("three_state.numpy.reference",
  ctmc_uniformization_close?(
    three_state_result.probabilities[0], ~0.11374376590160953, ~2.0e-13) &&
  ctmc_uniformization_close?(
    three_state_result.probabilities[1], ~0.41089706875887866, ~2.0e-13) &&
  ctmc_uniformization_close?(
    three_state_result.probabilities[2], ~0.47535916533951184, ~2.0e-13))

# --- semigroup check -----------------------------------------------------

half = chain.uniformize(~0.4, ~1.0e-14)
two_halves = chain.uniformize_from(
  half.probabilities, ~0.4, ~1.0e-14)
whole = chain.uniformize(~0.8, ~1.0e-14)
ctmc_uniformization_check("semigroup",
  ctmc_uniformization_close?(
    two_halves.probabilities[0], whole.probabilities[0], ~8.0e-14) &&
  ctmc_uniformization_close?(
    two_halves.probabilities[1], whole.probabilities[1], ~8.0e-14))

# --- numerical contract and explicit failure domains --------------------

contract = Probability.numerical_contract(:ctmc_uniformization)
ctmc_uniformization_check("contract.inspectable",
  contract.operation.include?("CTMC") && !contract.certified? &&
  contract.limitations.include?("rate*time <= 500") &&
  contract.limitations.include?("tail bound") &&
  contract.limitations.include?("truncation-only"))

bad_rate = false
begin
  absorbing.uniformize(~1.0, ~1.0e-12, 100000, ~1.0)
rescue error
  bad_rate = error.to_s.include?("dominate")
ctmc_uniformization_check("failure.rate", bad_rate)

zero_tolerance = false
begin
  absorbing.uniformize(~1.0, ~0.0)
rescue error
  zero_tolerance = error.to_s.include?("must be positive")
ctmc_uniformization_check("failure.tolerance.zero", zero_tolerance)

below_floor = false
begin
  absorbing.uniformize(~1.0, ~1.0e-16)
rescue error
  below_floor = error.to_s.include?("binary64 floor")
ctmc_uniformization_check("failure.tolerance.floor", below_floor)

unit_tolerance = false
begin
  absorbing.uniformize(~1.0, ~1.0)
rescue error
  unit_tolerance = error.to_s.include?("less than one")
ctmc_uniformization_check("failure.tolerance.one", unit_tolerance)

negative_time = false
begin
  absorbing.uniformize(~-1.0)
rescue error
  negative_time = error.to_s.include?("must be nonnegative")
ctmc_uniformization_check("failure.time.negative", negative_time)

infinite_time = false
begin
  absorbing.uniformize(Math.exp(~1000.0))
rescue error
  infinite_time = error.to_s.include?("must be finite")
ctmc_uniformization_check("failure.time.infinite", infinite_time)

bad_term_limit = false
begin
  zero.uniformize(~0.0, ~1.0e-12, 0)
rescue error
  bad_term_limit = error.to_s.include?("positive integer")
ctmc_uniformization_check("failure.term_limit.domain", bad_term_limit)

short_term_limit = false
begin
  absorbing.uniformize(~1.0, ~1.0e-12, 1)
rescue error
  short_term_limit = error.to_s.include?("term limit exceeded")
ctmc_uniformization_check("failure.term_limit", short_term_limit)

large_poisson_mean = false
begin
  absorbing.uniformize(~251.0)
rescue error
  large_poisson_mean = error.to_s.include?("limit of 500")
ctmc_uniformization_check("failure.poisson_mean", large_poisson_mean)

bad_initial_dimension = false
begin
  absorbing.uniformize_from([~1.0], ~1.0)
rescue error
  bad_initial_dimension = error.to_s.include?("wrong dimension")
ctmc_uniformization_check("failure.initial_dimension", bad_initial_dimension)

small_generator_residual = false
begin
  Probability.continuous_time_markov_chain(
    [~1.0, ~0.0], [[~-1.0e-13, ~5.0e-14], [~0.0, ~0.0]])
rescue error
  small_generator_residual = error.to_s.include?("sum to zero")
ctmc_uniformization_check(
  "failure.generator.small_residual", small_generator_residual)

huge_generator_residual = false
begin
  Probability.continuous_time_markov_chain(
    [~1.0, ~0.0], [[~-1.0e308, ~9.0e307], [~0.0, ~0.0]])
rescue error
  huge_generator_residual = error.to_s.include?("sum to zero")
ctmc_uniformization_check(
  "failure.generator.overflow_scale", huge_generator_residual)

extreme_valid = Probability.continuous_time_markov_chain(
  [~1.0, ~0.0], [[~-1.0e308, ~1.0e308], [~0.0, ~0.0]])
ctmc_uniformization_check("generator.extreme_valid",
  extreme_valid.maximum_exit_rate > ~9.0e307)

<< "probability_ctmc_uniformization_spec: all checks passed"
