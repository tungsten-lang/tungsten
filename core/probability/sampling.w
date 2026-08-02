# Weighted, without-replacement, and particle-resampling primitives.

use core/probability/primitives
use core/probability/rng

+ ProbabilitySampling
  -> .random_index(limit, rng)
    if !ProbabilityNumerics.integer?(limit) || limit <= 0
      raise "probability random index limit must be positive"
    if rng.respond_to?("integer") && limit <= 4294967296
      return rng.integer(limit)
    (ProbabilityRandom.random_unit(rng) * (limit + ~0.0)).to_i

  -> .categorical_from_cumulative(cumulative, rng)
    unit = ProbabilityRandom.random_unit(rng)
    index = 0
    while index < cumulative.size - 1 && unit >= cumulative[index]
      index += 1
    index

  -> .categorical_index(weights, rng)
    normalized = ProbabilityNumerics.normalized_weights(weights)
    ProbabilitySampling.categorical_from_cumulative(
      ProbabilityNumerics.cumulative_probabilities(normalized), rng)

  -> .weighted_sample(values, weights, rng)
    if values.class_name != "Array" || weights.class_name != "Array" || (
       values.size != weights.size) || values.size == 0
      raise "probability weighted sample needs equally sized nonempty Arrays"
    values[ProbabilitySampling.categorical_index(weights, rng)]

  -> .permutation(count, rng)
    ProbabilityNumerics.validate_count(count, "permutation size")
    indices = []
    i = 0
    while i < count
      indices.push(i)
      i += 1
    i = count - 1
    while i > 0
      j = ProbabilitySampling.random_index(i + 1, rng)
      temporary = indices[i]
      indices[i] = indices[j]
      indices[j] = temporary
      i -= 1
    indices

  -> .without_replacement(values, count, rng)
    if values.class_name != "Array"
      raise "probability without-replacement values must be an Array"
    ProbabilityNumerics.validate_count(count)
    if count > values.size
      raise "probability sample count exceeds population size"
    order = ProbabilitySampling.permutation(values.size, rng)
    selected = []
    i = 0
    while i < count
      selected.push(values[order[i]])
      i += 1
    selected

  -> .systematic_resample(weights, count, rng)
    ProbabilityNumerics.validate_count(count, "resample count")
    return [] if count == 0
    normalized = ProbabilityNumerics.normalized_weights(weights)
    cumulative = ProbabilityNumerics.cumulative_probabilities(normalized)
    offset = ProbabilityRandom.random_unit(rng)
    indices = []
    source = 0
    i = 0
    while i < count
      target = (i + offset) / (count + ~0.0)
      while source < cumulative.size - 1 && target >= cumulative[source]
        source += 1
      indices.push(source)
      i += 1
    indices

  -> .systematic_resample_default(weights, rng)
    ProbabilitySampling.systematic_resample(weights, weights.size, rng)

  -> .stratified_resample(weights, count, rng)
    ProbabilityNumerics.validate_count(count, "resample count")
    return [] if count == 0
    normalized = ProbabilityNumerics.normalized_weights(weights)
    cumulative = ProbabilityNumerics.cumulative_probabilities(normalized)
    indices = []
    source = 0
    i = 0
    while i < count
      target = (i + ProbabilityRandom.random_unit(rng)) / (count + ~0.0)
      while source < cumulative.size - 1 && target >= cumulative[source]
        source += 1
      indices.push(source)
      i += 1
    indices

  -> .stratified_resample_default(weights, rng)
    ProbabilitySampling.stratified_resample(weights, weights.size, rng)
