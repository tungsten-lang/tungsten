# Cardinality bookkeeping for an affine-line alignment theorem contract.
# This object records only the numerical thresholds a caller must establish:
# it is not a proof, proof witness, certificate, or theorem checker.

+ AffineLineAlignmentThresholds
  -> new(block_length, error_budget, exceptional_limit)
    @block_length = CodingTheorySupport.require_positive_integer(
      block_length, "alignment block length")
    @error_budget = CodingTheorySupport.require_nonnegative_integer(
      error_budget, "alignment error budget")
    if @error_budget > @block_length
      raise "alignment error budget cannot exceed the block length"
    @exceptional_limit = CodingTheorySupport.require_nonnegative_integer(
      exceptional_limit, "alignment exceptional limit")
    self

  ro :block_length, :error_budget, :exceptional_limit

  # Strict premise a < |S|.
  -> minimum_challenge_count
    @exceptional_limit + 1

  # Per-challenge agreement premise |A_z| >= n-e.
  -> minimum_projection_size
    @block_length - @error_budget

  # Strict conclusion-side threshold e+1 < |T|.
  -> minimum_aligned_challenge_count
    @error_budget + 2

  -> challenge_count_met?(count)
    CodingTheorySupport.require_nonnegative_integer(count, "challenge count")
    count >= minimum_challenge_count

  -> projection_size_met?(count)
    CodingTheorySupport.require_nonnegative_integer(count, "projection size")
    count >= minimum_projection_size && count <= @block_length

  -> aligned_challenge_count_met?(count)
    CodingTheorySupport.require_nonnegative_integer(
      count, "aligned challenge count")
    count >= minimum_aligned_challenge_count

  # Convenience validation for already-computed cardinalities. It does not
  # check code membership, affine equalities, or universally quantified
  # hypotheses from any theorem statement.
  -> premise_cardinalities_met?(challenge_count, projection_sizes)
    challenge_ok = challenge_count_met?(challenge_count)
    CodingTheorySupport.require_array(
      projection_sizes, "projection cardinalities")
    return false if projection_sizes.size != challenge_count
    projections_ok = true
    i = 0
    while i < projection_sizes.size
      if !projection_size_met?(projection_sizes[i])
        projections_ok = false
      i += 1
    challenge_ok && projections_ok

  -> to_s
    text = "AffineLineAlignmentThresholds(n=" + @block_length.to_s
    text += ", e=" + @error_budget.to_s
    text += ", a=" + @exceptional_limit.to_s + ")"
    text

  -> inspect
    to_s
