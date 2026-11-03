# Exact conformal rank calibration.  This is deliberately distinct from the
# facade's interpolated Hyndman-Fan quantile implementation.

+ StatisticsConformalRankResult
  -> new(p_value, included, candidate_score, extreme_count, calibration_size,
         miscoverage, tie_policy, status, assumptions, warnings)
    @p_value = p_value
    @included = included
    @candidate_score = candidate_score
    @extreme_count = extreme_count
    @calibration_size = calibration_size
    @miscoverage = miscoverage
    @tie_policy = tie_policy
    @status = status
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  ro :p_value, :candidate_score, :extreme_count, :calibration_size
  ro :miscoverage, :tie_policy, :status

  -> included?
    @included

  -> augmented_size
    @calibration_size + 1

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsConformal
  -> .rank(calibration_scores, candidate_score, miscoverage, tie_policy)
    if tie_policy != :conservative
      raise "conformal rank currently supports only :conservative ties"
    scores = Statistics.finite_values(
      calibration_scores, "conformal rank calibration")
    candidate = Statistics.scalar(candidate_score)
    alpha = Statistics.open_probability(
      miscoverage, "conformal rank miscoverage")

    extreme = 1
    scores.each -> (score)
      extreme += 1 if score >= candidate
    p_value = (extreme + ~0.0) / (scores.size + 1 + ~0.0)
    included = p_value > alpha
    assumptions = [:exchangeable_scores, :frozen_score_function,
                   :conservative_tie_handling]
    warnings = [
      "finite-sample validity is marginal under exchangeability, not conditional"]
    StatisticsConformalRankResult.new(
      p_value, included, candidate, extreme, scores.size, alpha, tie_policy,
      :ok_with_warnings, assumptions, warnings)
