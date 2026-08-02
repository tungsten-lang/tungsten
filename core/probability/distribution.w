# Executable protocol shared by scalar probability distributions.

use core/math
use core/probability/primitives
use core/probability/rng

+ ProbabilityDistribution
  -> discrete?
    false

  -> continuous?
    !discrete?

  -> probability(value)
    return pmf(value) if discrete?
    pdf(value)

  -> pdf(value)
    raise "pdf is not implemented for " + self.class_name

  -> pmf(value)
    raise "pmf is not implemented for " + self.class_name

  -> cdf(value)
    raise "cdf is not implemented for " + self.class_name

  -> survival(value)
    ~1.0 - cdf(value)

  -> log_probability(value)
    Math.log(probability(value))

  -> log_prob(value)
    log_probability(value)

  -> log_cdf(value)
    Math.log(cdf(value))

  -> log_survival(value)
    Math.log(survival(value))

  -> mean
    raise "mean is not implemented for " + self.class_name

  -> variance
    raise "variance is not implemented for " + self.class_name

  -> standard_deviation
    Math.sqrt(variance)

  -> entropy
    raise "entropy is not implemented for " + self.class_name

  -> quantile(probability)
    raise "quantile is not implemented for " + self.class_name

  -> support
    raise "support is not implemented for " + self.class_name

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    raise "sample is not implemented for " + self.class_name

  -> samples(count, rng = nil)
    ProbabilityNumerics.validate_count(count)
    ProbabilityRandom.require_rng(rng)
    values = []
    count.times -> values.push(sample(rng))
    values

  -> probabilities(values)
    if values.class_name != "Array"
      raise "probability evaluation batch must be an Array"
    result = []
    i = 0
    while i < values.size
      result.push(probability(values[i]))
      i += 1
    result

  -> log_probabilities(values)
    if values.class_name != "Array"
      raise "probability evaluation batch must be an Array"
    result = []
    i = 0
    while i < values.size
      result.push(log_probability(values[i]))
      i += 1
    result
