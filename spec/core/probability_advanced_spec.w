# Advanced process, copula, transformation, and conditioning contracts.

use probability

-> advanced_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> advanced_close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance*scale

# --- richer stochastic processes -----------------------------------------

ctmc = Probability.continuous_time_markov_chain(
  [~1.0, ~0.0], [[~-2.0, ~2.0], [~0.0, ~0.0]])
left_path = ctmc.sample_path(~10.0, Probability.rng(11))
right_path = ctmc.sample_path(~10.0, Probability.rng(11))
advanced_check("ctmc.generator",
  ctmc.exit_rates[0] == ~2.0 && ctmc.exit_rates[1] == ~0.0)
advanced_check("ctmc.path",
  left_path.jump_count == 1 && left_path.states[0] == 0 &&
  left_path.states[1] == 1 && left_path.times[1] > ~0.0)
advanced_check("ctmc.replay",
  left_path.times[1] == right_path.times[1])
advanced_check("ctmc.state_at",
  left_path.state_at(~0.0) == 0 && left_path.state_at(~10.0) == 1)

hmm = Probability.hidden_markov_model(
  [~0.5, ~0.5], [[~0.9, ~0.1], [~0.1, ~0.9]],
  [Probability.bernoulli(~0.1), Probability.bernoulli(~0.9)])
observations = [0, 0, 1, 1]
advanced_check("hmm.forward.reference",
  advanced_close?(hmm.log_probability(observations),
                  ~-3.2389764965752033, ~2.0e-13))
filters = hmm.filtered_probabilities(observations)
advanced_check("hmm.filter",
  filters.size == 4 && advanced_close?(
    ProbabilityNumerics.sum(filters[3]), ~1.0, ~1.0e-13) &&
  filters[3][1] > filters[3][0])
viterbi = hmm.viterbi(observations)
advanced_check("hmm.viterbi",
  viterbi[0] == 0 && viterbi[1] == 0 &&
  viterbi[2] == 1 && viterbi[3] == 1)
hmm_left = hmm.sample_path(12, Probability.rng(12))
hmm_right = hmm.sample_path(12, Probability.rng(12))
advanced_check("hmm.replay",
  hmm_left.states.join(",") == hmm_right.states.join(",") &&
  hmm_left.observations.join(",") == hmm_right.observations.join(","))

unit_drift = -> (time, value) ~1.0
zero_diffusion = -> (time, value) ~0.0
deterministic_sde = Probability.euler_maruyama(unit_drift, zero_diffusion)
sde_deterministic_rng = Probability.rng(13)
sde_path = deterministic_sde.sample_grid(
  ~2.0, [~0.0, ~0.25, ~1.0], sde_deterministic_rng)
advanced_check("sde.deterministic",
  sde_path.values[0] == ~2.0 && sde_path.values[1] == ~2.25 &&
  sde_path.values[2] == ~3.0)
advanced_check("sde.zero_diffusion.preserves_rng",
  sde_deterministic_rng.next_u32 == Probability.rng(13).next_u32)
zero_drift = -> (time, value) ~0.0
unit_diffusion = -> (time, value) ~1.0
stochastic_sde = Probability.euler_maruyama(zero_drift, unit_diffusion)
sde_left = stochastic_sde.sample_path(
  ~0.0, ~0.0, ~0.1, 10, Probability.rng(14))
sde_right = stochastic_sde.sample_path(
  ~0.0, ~0.0, ~0.1, 10, Probability.rng(14))
advanced_check("sde.replay",
  sde_left.values.join(",") == sde_right.values.join(","))

unit_interarrival = Probability.condition_on_values(
  Probability.bernoulli(~1.0), [1])
renewal = Probability.renewal_process(unit_interarrival)
renewal_arrivals = renewal.sample_arrivals(4, Probability.rng(15))
advanced_check("renewal.arrivals",
  renewal_arrivals.size == 4 && renewal_arrivals[0] == ~1.0 &&
  renewal_arrivals[1] == ~2.0 && renewal_arrivals[2] == ~3.0 &&
  renewal_arrivals[3] == ~4.0)
advanced_check("renewal.count",
  renewal.count_until(~3.5, Probability.rng(15)) == 3)

# --- dependence and copulas ----------------------------------------------

independent_copula = Probability.gaussian_copula(
  [[~1.0, ~0.0], [~0.0, ~1.0]])
advanced_check("copula.independence",
  advanced_close?(independent_copula.density([~0.2, ~0.8]), ~1.0,
                  ~2.0e-13))
dependent_copula = Probability.gaussian_copula(
  [[~1.0, ~0.5], [~0.5, ~1.0]])
advanced_check("copula.center.reference",
  advanced_close?(dependent_copula.log_density([~0.5, ~0.5]),
                  ~0.14384103622589045, ~2.0e-13))
copula_left = dependent_copula.sample(Probability.rng(16))
copula_right = dependent_copula.sample(Probability.rng(16))
advanced_check("copula.replay",
  copula_left[0] == copula_right[0] && copula_left[1] == copula_right[1] &&
  copula_left[0] > ~0.0 && copula_left[0] < ~1.0)
joint = Probability.copula_distribution(
  dependent_copula, [Probability.normal, Probability.exponential])
joint_draw = joint.sample(Probability.rng(17))
advanced_check("copula.joint",
  joint.dimension == 2 && joint_draw[1] >= ~0.0 &&
  !joint.log_prob([~0.0, ~1.0]).infinite?)

# --- transformations and conditioning -----------------------------------

affine = Probability.affine_distribution(
  Probability.normal(~1.0, ~2.0), ~3.0, ~-4.0)
advanced_check("affine.moments",
  affine.mean == ~-1.0 && affine.variance == ~64.0)
advanced_check("affine.cdf",
  advanced_close?(affine.cdf(~-1.0), ~0.5, ~2.0e-14))
advanced_check("affine.logpdf",
  advanced_close?(affine.log_prob(~-1.0),
                  ~-2.9983800748845084, ~2.0e-13))

truncated = Probability.truncate(Probability.normal, ~-1.0, ~1.0)
advanced_check("truncated.cdf",
  advanced_close?(truncated.cdf(~0.0), ~0.5, ~2.0e-14))
advanced_check("truncated.quantile",
  advanced_close?(truncated.quantile(~0.5), ~0.0, ~2.0e-13))
truncated_draw = truncated.sample(Probability.rng(18))
advanced_check("truncated.sample.support",
  truncated.support.contains?(truncated_draw))

conditioned = Probability.condition_on_values(
  Probability.poisson(~4.0), [0, 2])
advanced_check("conditioning.mass",
  advanced_close?(conditioned.pmf(0), ~1.0 / ~9.0) &&
  advanced_close?(conditioned.pmf(2), ~8.0 / ~9.0) &&
  conditioned.pmf(1) == ~0.0)
advanced_check("conditioning.support",
  conditioned.support.contains?(0) && conditioned.support.contains?(2) &&
  !conditioned.support.contains?(1))

bad_generator = false
begin
  Probability.continuous_time_markov_chain(
    [~1.0, ~0.0], [[~-1.0, ~0.5], [~0.0, ~0.0]])
rescue error
  bad_generator = error.to_s.include?("sum to zero")
advanced_check("failure.generator", bad_generator)

bad_tail_truncation = false
begin
  Probability.truncate(Probability.normal, ~40.0, ~41.0)
rescue error
  bad_tail_truncation = error.to_s.include?("not representable")
advanced_check("failure.truncation.resolution", bad_tail_truncation)

impossible_hmm = Probability.hidden_markov_model(
  [~1.0], [[~1.0]], [Probability.bernoulli(~0.0)])
impossible_observation = false
begin
  impossible_hmm.log_probability([1])
rescue error
  impossible_observation = error.to_s.include?("zero probability")
advanced_check("failure.hmm.zero_probability", impossible_observation)

<< "probability_advanced_spec: all checks passed"
