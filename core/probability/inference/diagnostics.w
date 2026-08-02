# Monte Carlo chain containers and convergence diagnostics.

use core/math
use core/probability/linear_algebra
use core/probability/primitives

+ MonteCarloChain
  -> new(samples, log_probabilities, accepted, proposed)
    if samples.class_name != "Array" || log_probabilities.class_name != "Array" || (
       samples.size != log_probabilities.size)
      raise "probability chain samples and log probabilities must align"
    @samples = []
    i = 0
    while i < samples.size
      @samples.push(ProbabilityNumerics.copy_array(samples[i]))
      i += 1
    @log_probabilities = ProbabilityNumerics.copy_array(log_probabilities)
    @accepted = accepted
    @proposed = proposed
    self

  -> samples
    copy = []
    i = 0
    while i < @samples.size
      copy.push(ProbabilityNumerics.copy_array(@samples[i]))
      i += 1
    copy

  -> log_probabilities
    ProbabilityNumerics.copy_array(@log_probabilities)

  -> sample_count
    @samples.size

  -> dimension
    @samples.size == 0 ? 0 : @samples[0].size

  -> accepted
    @accepted

  -> proposed
    @proposed

  -> acceptance_rate
    return ~0.0 if @proposed == 0
    @accepted / (@proposed + ~0.0)

  -> mean
    ProbabilityDiagnostics.mean_vector(@samples)

  -> variance
    ProbabilityDiagnostics.variance_vector(@samples)

  -> effective_sample_size(coordinate = 0)
    ProbabilityDiagnostics.effective_sample_size(@samples, coordinate)


+ HamiltonianMonteCarloChain < MonteCarloChain
  -> new(samples, log_probabilities, accepted, proposed, divergences, step_size)
    if samples.class_name != "Array" || log_probabilities.class_name != "Array" || (
       samples.size != log_probabilities.size)
      raise "probability chain samples and log probabilities must align"
    @samples = []
    i = 0
    while i < samples.size
      @samples.push(ProbabilityNumerics.copy_array(samples[i]))
      i += 1
    @log_probabilities = ProbabilityNumerics.copy_array(log_probabilities)
    @accepted = accepted
    @proposed = proposed
    @divergences = divergences
    @step_size = step_size
    self

  -> divergences
    @divergences

  -> step_size
    @step_size


+ ProbabilityDiagnostics
  -> .validate_samples(samples)
    if samples.class_name != "Array" || samples.size == 0
      raise "probability diagnostics need nonempty samples"
    dimension = nil
    validated = []
    i = 0
    while i < samples.size
      vector = ProbabilityLinearAlgebra.vector(samples[i], "chain sample")
      dimension = vector.size if dimension == nil
      if vector.size != dimension
        raise "probability chain samples must share a dimension"
      validated.push(vector)
      i += 1
    validated

  -> .validate_coordinate(samples, coordinate)
    if !ProbabilityNumerics.integer?(coordinate) || coordinate < 0 || (
       coordinate >= samples[0].size)
      raise "probability diagnostic coordinate is out of range"
    coordinate

  -> .mean_vector(samples)
    validated = ProbabilityDiagnostics.validate_samples(samples)
    dimension = validated[0].size
    result = []
    j = 0
    while j < dimension
      values = []
      i = 0
      while i < validated.size
        values.push(validated[i][j])
        i += 1
      result.push(ProbabilityNumerics.sum(values) / (validated.size + ~0.0))
      j += 1
    result

  -> .variance_vector(samples)
    validated = ProbabilityDiagnostics.validate_samples(samples)
    if validated.size < 2
      raise "probability variance diagnostic needs at least two samples"
    means = ProbabilityDiagnostics.mean_vector(validated)
    result = []
    j = 0
    while j < means.size
      squares = []
      i = 0
      while i < validated.size
        difference = validated[i][j] - means[j]
        squares.push(difference*difference)
        i += 1
      result.push(ProbabilityNumerics.sum(squares) / (validated.size - ~1.0))
      j += 1
    result

  -> .autocorrelation(samples, coordinate, lag)
    validated = ProbabilityDiagnostics.validate_samples(samples)
    ProbabilityDiagnostics.validate_coordinate(validated, coordinate)
    if !ProbabilityNumerics.integer?(lag) || lag < 0 || lag >= validated.size
      raise "probability autocorrelation lag is out of range"
    mean = ProbabilityDiagnostics.mean_vector(validated)[coordinate]
    denominator_terms = []
    i = 0
    while i < validated.size
      difference = validated[i][coordinate] - mean
      denominator_terms.push(difference*difference)
      i += 1
    denominator = ProbabilityNumerics.sum(denominator_terms)
    return ~1.0 if lag == 0
    return ~0.0 if denominator == ~0.0
    numerator_terms = []
    i = 0
    while i + lag < validated.size
      numerator_terms.push(
        (validated[i][coordinate] - mean)*
        (validated[i + lag][coordinate] - mean))
      i += 1
    ProbabilityNumerics.sum(numerator_terms) / denominator

  # Geyer's initial-positive-pair truncation of the autocorrelation sum.
  -> .effective_sample_size(samples, coordinate = 0)
    validated = ProbabilityDiagnostics.validate_samples(samples)
    ProbabilityDiagnostics.validate_coordinate(validated, coordinate)
    return ~1.0 if validated.size == 1
    values = []
    i = 0
    while i < validated.size
      values.push(validated[i][coordinate])
      i += 1
    mean = ProbabilityNumerics.sum(values) / (values.size + ~0.0)
    denominator_terms = []
    i = 0
    while i < values.size
      difference = values[i] - mean
      denominator_terms.push(difference*difference)
      i += 1
    denominator = ProbabilityNumerics.sum(denominator_terms)
    return validated.size + ~0.0 if denominator == ~0.0
    total = ~0.0
    lag = 1
    while lag < values.size
      first_terms = []
      i = 0
      while i + lag < values.size
        first_terms.push((values[i] - mean)*(values[i + lag] - mean))
        i += 1
      first = ProbabilityNumerics.sum(first_terms) / denominator
      second = ~0.0
      if lag + 1 < values.size
        second_terms = []
        i = 0
        while i + lag + 1 < values.size
          second_terms.push(
            (values[i] - mean)*(values[i + lag + 1] - mean))
          i += 1
        second = ProbabilityNumerics.sum(second_terms) / denominator
      pair = first + second
      break if pair <= ~0.0
      total += pair
      lag += 2
    estimate = validated.size / (~1.0 + ~2.0*total)
    estimate = ~1.0 if estimate < ~1.0
    estimate = validated.size + ~0.0 if estimate > validated.size
    estimate

  -> .monte_carlo_standard_error(samples, coordinate = 0)
    validated = ProbabilityDiagnostics.validate_samples(samples)
    variance = ProbabilityDiagnostics.variance_vector(validated)[coordinate]
    ess = ProbabilityDiagnostics.effective_sample_size(validated, coordinate)
    Math.sqrt(variance / ess)

  # Rank normalization and folding are not yet implemented.  This is the
  # classical split R-hat and is labeled accordingly.
  -> .split_rhat(chains, coordinate = 0)
    if chains.class_name != "Array" || chains.size < 2
      raise "probability split R-hat needs at least two chains"
    validated_chains = []
    minimum = nil
    i = 0
    while i < chains.size
      chain = ProbabilityDiagnostics.validate_samples(chains[i])
      ProbabilityDiagnostics.validate_coordinate(chain, coordinate)
      minimum = chain.size if minimum == nil || chain.size < minimum
      validated_chains.push(chain)
      i += 1
    half = minimum / 2
    if half < 2
      raise "probability split R-hat needs at least four samples per chain"
    split_means = []
    split_variances = []
    i = 0
    while i < validated_chains.size
      part = 0
      while part < 2
        start = part*half
        values = []
        j = 0
        while j < half
          values.push(validated_chains[i][start + j][coordinate])
          j += 1
        mean = ProbabilityNumerics.sum(values) / (half + ~0.0)
        squares = []
        j = 0
        while j < values.size
          difference = values[j] - mean
          squares.push(difference*difference)
          j += 1
        split_means.push(mean)
        split_variances.push(
          ProbabilityNumerics.sum(squares) / (half - ~1.0))
        part += 1
      i += 1
    chain_count = split_means.size
    overall = ProbabilityNumerics.sum(split_means) / (chain_count + ~0.0)
    between_terms = []
    i = 0
    while i < chain_count
      difference = split_means[i] - overall
      between_terms.push(difference*difference)
      i += 1
    between = half*ProbabilityNumerics.sum(between_terms) / (
      chain_count - ~1.0)
    within = ProbabilityNumerics.sum(split_variances) / (chain_count + ~0.0)
    return ~1.0 if within == ~0.0 && between == ~0.0
    return ProbabilityNumerics.positive_infinity if within == ~0.0
    variance_estimate = ((half - ~1.0) / (half + ~0.0))*within + (
      between / (half + ~0.0))
    Math.sqrt(variance_estimate / within)
