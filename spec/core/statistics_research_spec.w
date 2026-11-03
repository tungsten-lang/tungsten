# Paper-derived deterministic Statistics foundations.
# Run in both engines:
#   bin/tungsten run --interpret spec/core/statistics_research_spec.w
#   bin/tungsten compile spec/core/statistics_research_spec.w --out /tmp/statistics-research-spec

use statistics

-> statistics_research_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> statistics_research_close?(left, right, tolerance = ~1.0e-10)
  difference = (left - right).abs
  scale = right.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

# Exact rank selection is intentionally different from type-7 interpolation.
rank_values = [~4.0, ~1.0, ~3.0, ~2.0]
statistics_research_check(
  "order_statistic.exact", Statistics.order_statistic(rank_values, 2) == ~2.0)
statistics_research_check(
  "order_statistic.does_not_mutate", rank_values[0] == ~4.0)

# Lee et al. all-purpose robust scalar mean.
constant = Statistics.all_purpose_mean([~7.0, ~7.0, ~7.0, ~7.0], ~0.2)
statistics_research_check("robust_mean.constant", constant.estimate == ~7.0)
statistics_research_check(
  "robust_mean.constant_status", constant.status == :exact_constant)

contaminated = [~0.0, ~1.0, ~2.0, ~3.0, ~4.0, ~5.0,
                ~6.0, ~7.0, ~8.0, ~9.0, ~10.0, ~100.0]
robust = Statistics.all_purpose_mean(contaminated, ~0.05)
statistics_research_check("robust_mean.group_count", robust.group_count == 3)
statistics_research_check("robust_mean.initial", robust.initial_estimate == ~5.5)
statistics_research_check(
  "robust_mean.reference",
  statistics_research_close?(robust.estimate, ~5.1524479066495275))
statistics_research_check(
  "robust_mean.influence_reference",
  statistics_research_close?(
    robust.scaled_influence_parameter, ~0.9861269540309456))
statistics_research_check(
  "robust_mean.root_residual", robust.equation_residual <= ~2.0e-12)
statistics_research_check(
  "robust_mean.assumptions",
  robust.assumptions.include?(:iid) && robust.status == :ok_with_warnings)

shifted_values = []
contaminated.each -> (value)
  shifted_values.push(value + ~11.0)
shifted = Statistics.all_purpose_mean(shifted_values, ~0.05)
statistics_research_check(
  "robust_mean.translation_equivariant",
  statistics_research_close?(shifted.estimate, robust.estimate + ~11.0))

robust_warning_copy = robust.warnings
robust_warning_copy.push("mutation")
statistics_research_check(
  "robust_mean.defensive_warnings", robust.warnings.size == 1)

small_robust_failed = false
begin
  Statistics.all_purpose_mean([~1.0, ~2.0], ~1.0e-6)
rescue error
  small_robust_failed = error.to_s.include?("ceil(log(1/delta))")
statistics_research_check("robust_mean.small_sample_failure", small_robust_failed)

nonconverged_robust_failed = false
begin
  Statistics.all_purpose_mean(contaminated, ~0.05, 1, ~1.0e-15)
rescue error
  nonconverged_robust_failed = error.to_s.include?("did not converge")
statistics_research_check(
  "robust_mean.nonconvergence_failure", nonconverged_robust_failed)

# Ohlendorff et al. deterministic cheap-subsampling postprocessing.
cheap = Statistics.cheap_subsampling_interval(
  ~10.0, [~9.0, ~11.0, ~10.5, ~9.5], 100, 50, ~0.95,
  :asymptotically_linear_iid)
statistics_research_check(
  "cheap_subsampling.deviation",
  statistics_research_close?(cheap.subsample_deviation,
                             ~0.7905694150420949))
statistics_research_check(
  "cheap_subsampling.scale", cheap.finite_population_scale == ~1.0)
statistics_research_check(
  "cheap_subsampling.critical",
  statistics_research_close?(cheap.critical_value,
                             ~2.7764451051977987, ~2.0e-10))
statistics_research_check(
  "cheap_subsampling.endpoints",
  statistics_research_close?(cheap.lower, ~7.805027417287288,
                             ~2.0e-10) &&
    statistics_research_close?(cheap.upper, ~12.194972582712712,
                               ~2.0e-10))
statistics_research_check(
  "cheap_subsampling.metadata",
  cheap.degrees_of_freedom == 4 && cheap.status == :ok_with_warnings)

degenerate = Statistics.cheap_subsampling_interval(
  ~10.0, [~10.0, ~10.0], 20, 10, ~0.95,
  :asymptotically_linear_iid)
statistics_research_check(
  "cheap_subsampling.degenerate",
  degenerate.numerically_degenerate? && degenerate.lower == ~10.0 &&
    degenerate.upper == ~10.0)

cheap_ack_failed = false
begin
  Statistics.cheap_subsampling_interval(~0.0, [~0.0], 10, 5)
rescue error
  cheap_ack_failed = error.to_s.include?("acknowledgement")
statistics_research_check("cheap_subsampling.ack_failure", cheap_ack_failed)

mean_estimator = -> (subset) Statistics.mean(subset)
planned = Statistics.cheap_subsampling_from_indices(
  [~1.0, ~2.0, ~3.0, ~4.0], mean_estimator,
  [[0, 1], [2, 3], [0, 2], [1, 3]], ~0.95,
  :asymptotically_linear_iid)
statistics_research_check(
  "cheap_subsampling.explicit_plan",
  planned.estimate == ~2.5 && planned.replicate_count == 4 &&
    statistics_research_close?(planned.subsample_deviation,
                               ~0.7905694150420949))

duplicate_subset_failed = false
begin
  Statistics.cheap_subsampling_from_indices(
    [~1.0, ~2.0, ~3.0], mean_estimator, [[0, 0]], ~0.95,
    :asymptotically_linear_iid)
rescue error
  duplicate_subset_failed = error.to_s.include?("must not repeat")
statistics_research_check(
  "cheap_subsampling.duplicate_index_failure", duplicate_subset_failed)

# Generic conformal rank and Cholaquidis et al. half-mass geometry.
rank = Statistics.conformal_rank([~2.0, ~1.0, ~2.0], ~2.0, ~0.75)
statistics_research_check(
  "conformal_rank.conservative_ties",
  rank.p_value == ~0.75 && rank.extreme_count == 3 && !rank.included?)
statistics_research_check(
  "conformal_rank.scope",
  rank.assumptions.include?(:exchangeable_scores) &&
    rank.tie_policy == :conservative)

unsupported_ties_failed = false
begin
  Statistics.conformal_rank([~1.0], ~1.0, ~0.05, :randomized)
rescue error
  unsupported_ties_failed = error.to_s.include?("only :conservative")
statistics_research_check(
  "conformal_rank.tie_policy_failure", unsupported_ties_failed)

sample = [[~0.0], [~1.0], [~2.0]]
half_mass = Statistics.conformal_half_mass_candidate(sample, [~10.0], ~0.25)
statistics_research_check(
  "half_mass.reference",
  half_mass.neighbor_rank == 2 && half_mass.candidate_score == ~9.0 &&
    half_mass.p_value == ~0.25 && !half_mass.included?)
statistics_research_check(
  "half_mass.lower_alpha_includes",
  Statistics.conformal_half_mass_candidate(
    sample, [~10.0], ~0.2).included?)
statistics_research_check(
  "half_mass.permutation_invariant",
  Statistics.conformal_half_mass_candidate(
    [[~2.0], [~0.0], [~1.0]], [~10.0], ~0.25).p_value == (
      half_mass.p_value))

ragged_half_mass_failed = false
begin
  Statistics.conformal_half_mass_candidate(
    [[~0.0, ~1.0], [~2.0]], [~3.0, ~4.0], ~0.1)
rescue error
  ragged_half_mass_failed = error.to_s.include?("rectangular")
statistics_research_check(
  "half_mass.shape_failure", ragged_half_mass_failed)

# Chugg-Ramdas scalar closed-form empirical-Bernstein sequence.
sequence = Statistics.empirical_bernstein_sequence(~0.05)
initial_sequence = sequence.snapshot
statistics_research_check(
  "empirical_bernstein.initial_support",
  initial_sequence.status == :warming_up &&
    initial_sequence.lower == ~0.0 && initial_sequence.upper == ~1.0 &&
    initial_sequence.center == nil)
statistics_research_check(
  "empirical_bernstein.not_mergeable", !sequence.mergeable?)

index = 0
while index < 20
  sequence.push(index % 2 == 0 ? ~0.0 : ~1.0)
  index += 1
statistics_research_check(
  "empirical_bernstein.hitting_not_early", !sequence.snapshot.active?)
sequence.push(~0.0)
index += 1
statistics_research_check(
  "empirical_bernstein.hitting_time",
  sequence.snapshot.active? && sequence.active_from == 21)
while index < 200
  sequence.push(index % 2 == 0 ? ~0.0 : ~1.0)
  index += 1
sequence_result = sequence.snapshot
statistics_research_check(
  "empirical_bernstein.center", sequence_result.center == ~0.5)
statistics_research_check(
  "empirical_bernstein.variance_reference",
  statistics_research_close?(sequence_result.variance_process,
                             ~40.208791763289696))
statistics_research_check(
  "empirical_bernstein.width_reference",
  statistics_research_close?(sequence_result.raw_half_width,
                             ~0.13700794243779177))
statistics_research_check(
  "empirical_bernstein.endpoint_reference",
  statistics_research_close?(sequence_result.lower,
                             ~0.3629920575622024) &&
    statistics_research_close?(sequence_result.upper,
                               ~0.6370079424377976))
statistics_research_check(
  "empirical_bernstein.target",
  sequence_result.target == :average_conditional_mean &&
    sequence_result.active_from == 21)

scaled_sequence = Statistics.empirical_bernstein_sequence(
  ~0.05, ~10.0, ~20.0)
index = 0
while index < 200
  scaled_sequence.push(index % 2 == 0 ? ~10.0 : ~20.0)
  index += 1
scaled_result = scaled_sequence.snapshot
statistics_research_check(
  "empirical_bernstein.support_rescaling",
  scaled_result.center == ~15.0 &&
    statistics_research_close?(scaled_result.raw_half_width,
                               ~10.0 * sequence_result.raw_half_width))

support_failed = false
begin
  sequence.push(~1.1)
rescue error
  support_failed = error.to_s.include?("outside the declared support")
statistics_research_check(
  "empirical_bernstein.support_failure", support_failed)

# Park et al. finite-candidate bounded KL relative-fit inversion.
relative_fit = Statistics.bounded_kl_relative_fit(
  [[~-0.2, ~-0.1, ~0.0], [~1.0, ~1.0, ~1.0]],
  ~1.0, ~0.05, :iid_bounded_log_ratio)
statistics_research_check(
  "relative_fit.threshold",
  statistics_research_close?(relative_fit.threshold,
                             ~0.7066036458008114))
statistics_research_check(
  "relative_fit.acceptance",
  relative_fit.accepted?(0) && !relative_fit.accepted?(1) &&
    relative_fit.accepted_indices.size == 1)
statistics_research_check(
  "relative_fit.metadata",
  relative_fit.target_divergence == :kl &&
    relative_fit.target_scope == :finite_candidate_family &&
    relative_fit.coverage_kind == :finite_sample_bounded_score)

accepted_copy = relative_fit.accepted_indices
accepted_copy.push(1)
statistics_research_check(
  "relative_fit.defensive_indices", relative_fit.accepted_indices.size == 1)

relative_ack_failed = false
begin
  Statistics.bounded_kl_relative_fit([[~0.0]], ~1.0)
rescue error
  relative_ack_failed = error.to_s.include?("acknowledgement")
statistics_research_check("relative_fit.ack_failure", relative_ack_failed)

relative_shape_failed = false
begin
  Statistics.bounded_kl_relative_fit(
    [[~0.0], [~0.0, ~1.0]], ~1.0, ~0.05, :iid_bounded_log_ratio)
rescue error
  relative_shape_failed = error.to_s.include?("equal holdout size")
statistics_research_check("relative_fit.shape_failure", relative_shape_failed)

<< "statistics_research_spec: all checks passed"
