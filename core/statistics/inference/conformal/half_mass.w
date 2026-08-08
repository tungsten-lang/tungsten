# Half-mass-radius conformal candidate scoring after Cholaquidis et al. (2026).

+ StatisticsHalfMassConformalResult
  -> new(rank_result, candidate_score, scores, sample_size, dimension,
         neighbor_rank, status, assumptions, warnings)
    @rank_result = rank_result
    @candidate_score = candidate_score
    @scores = Statistics.copy_values(scores)
    @sample_size = sample_size
    @dimension = dimension
    @neighbor_rank = neighbor_rank
    @status = status
    @assumptions = Statistics.copy_values(assumptions)
    @warnings = Statistics.copy_values(warnings)

  -> p_value
    @rank_result.p_value

  -> included?
    @rank_result.included?

  -> rank_result
    @rank_result

  -> candidate_score
    @candidate_score

  -> scores
    Statistics.copy_values(@scores)

  -> sample_size
    @sample_size

  -> dimension
    @dimension

  -> neighbor_rank
    @neighbor_rank

  -> miscoverage
    @rank_result.miscoverage

  -> status
    @status

  -> assumptions
    Statistics.copy_values(@assumptions)

  -> warnings
    Statistics.copy_values(@warnings)


+ StatisticsHalfMassConformal
  -> .euclidean_distance(left, right)
    distance = ~0.0
    index = 0
    while index < left.size
      difference = Statistics.finite_result(
        left[index] - right[index], "half-mass conformal distance")
      distance = Math.hypot(distance, difference)
      index += 1
    Statistics.finite_result(distance, "half-mass conformal distance")

  -> .candidate(sample_rows, candidate_row, miscoverage)
    candidate = Statistics.finite_row(
      candidate_row, nil, "half-mass conformal score")
    dimension = candidate.size
    rows = []
    sample_rows.each -> (row)
      rows.push(Statistics.finite_row(
        row, dimension, "half-mass conformal score"))
    if rows.empty?
      raise "half-mass conformal score requires at least one sample row"

    n = rows.size
    augmented = Statistics.copy_values(rows)
    augmented.push(candidate)
    neighbor_rank = Math.floor((n + ~0.0) / ~2.0).to_i + 1
    scores = []
    index = 0
    while index < augmented.size
      distances = []
      other = 0
      while other < augmented.size
        if other != index
          distances.push(StatisticsHalfMassConformal.euclidean_distance(
            augmented[index], augmented[other]))
        other += 1
      distances = distances.sort
      scores.push(distances[neighbor_rank - 1])
      index += 1

    candidate_score = scores[scores.size - 1]
    calibration_scores = []
    index = 0
    while index < scores.size - 1
      calibration_scores.push(scores[index])
      index += 1
    rank_result = StatisticsConformal.rank(
      calibration_scores, candidate_score, miscoverage, :conservative)
    assumptions = [:exchangeable_rows, :euclidean_geometry,
                   :conservative_tie_handling]
    warnings = rank_result.warnings
    warnings.push(
      "quadratic reference implementation is unsuitable for large samples or dimensions")
    StatisticsHalfMassConformalResult.new(
      rank_result, candidate_score, scores, n, dimension, neighbor_rank,
      :ok_with_warnings, assumptions, warnings)
