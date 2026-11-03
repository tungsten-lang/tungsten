# Finite-candidate bounded KL relative-fit inversion after Park et al. (2025).
#
# Callers fit the pilot on an independent split and evaluate held-out
# log(pilot_density / candidate_density) scores.  Probability remains the owner
# of density models; this module owns only deterministic test inversion.

+ StatisticsRelativeFitResult
  -> new(accepted_indices, mean_scores, threshold, score_bound,
         holdout_size, candidate_count, miscoverage, status,
         assumptions, warnings)
    @accepted_indices = Statistics.copy_values(accepted_indices)
    @mean_scores = Statistics.copy_values(mean_scores)
    @threshold = threshold
    @score_bound = score_bound
    @holdout_size = holdout_size
    @candidate_count = candidate_count
    @miscoverage = miscoverage
    @status = status
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  -> accepted_indices
    Statistics.copy_values(@accepted_indices)

  -> accepted?(candidate_index)
    @accepted_indices.include?(candidate_index)

  -> mean_scores
    Statistics.copy_values(@mean_scores)

  ro :threshold, :score_bound, :holdout_size, :candidate_count, :miscoverage
  ro :status

  -> target_divergence
    :kl

  -> target_scope
    :finite_candidate_family

  -> coverage_kind
    :finite_sample_bounded_score

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsRelativeFit
  -> .bounded_kl(score_rows, score_bound, miscoverage,
                 assumption_acknowledgement)
    if assumption_acknowledgement != :iid_bounded_log_ratio
      raise "bounded KL relative fit requires :iid_bounded_log_ratio acknowledgement"
    if score_rows.empty?
      raise "bounded KL relative fit requires at least one candidate"
    bound = Statistics.positive_scalar(
      score_bound, "bounded KL relative-fit score bound")
    alpha = Statistics.open_probability(
      miscoverage, "bounded KL relative-fit miscoverage")

    holdout_size = nil
    converted_rows = []
    score_rows.each -> (row)
      converted = Statistics.finite_values(row, "bounded KL relative-fit scores")
      holdout_size = converted.size if holdout_size == nil
      if converted.size != holdout_size
        raise "bounded KL relative fit requires equal holdout size for every candidate"
      converted_rows.push(converted)

    threshold = bound * Math.sqrt(
      (~0.0 - Math.log(alpha)) / (~2.0 * holdout_size))
    threshold = Statistics.finite_result(
      threshold, "bounded KL relative-fit threshold")
    means = []
    accepted = []
    index = 0
    while index < converted_rows.size
      average = Statistics.mean(converted_rows[index])
      means.push(average)
      accepted.push(index) if average <= threshold
      index += 1

    assumptions = [:iid_holdout, :independent_pilot_split,
                   :theoretical_centered_log_ratio_bound,
                   :common_dominating_measure]
    warnings = [
      "theoretical score bound and split independence are acknowledged, not verified",
      "the target is the KL projection onto the supplied finite candidate family"]
    StatisticsRelativeFitResult.new(
      accepted, means, threshold, bound, holdout_size, converted_rows.size,
      alpha, :ok_with_warnings, assumptions, warnings)
