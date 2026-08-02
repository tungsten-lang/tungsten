# Finite categorical and Poisson count distributions.

use core/math
use core/special
use core/probability/distribution
use core/probability/primitives
use core/probability/rng
use core/probability/sampling
use core/probability/special
use core/probability/support

+ CategoricalDistribution < ProbabilityDistribution
  -> new(weights)
    @probabilities = ProbabilityNumerics.normalized_weights(
      weights, "Categorical weights")
    @cumulative = ProbabilityNumerics.cumulative_probabilities(@probabilities)
    @support = ProbabilitySupport.new(
      0, @probabilities.size - 1, true, true, true)
    self

  -> discrete?
    true

  -> probabilities
    ProbabilityNumerics.copy_array(@probabilities)

  -> category_count
    @probabilities.size

  -> support
    @support

  -> pmf(value)
    return ~0.0 if !ProbabilityNumerics.integer?(value)
    return ~0.0 if value < 0 || value >= @probabilities.size
    @probabilities[value]

  -> log_probability(value)
    probability = pmf(value)
    return ProbabilityNumerics.negative_infinity if probability == ~0.0
    Math.log(probability)

  -> cdf(value)
    return value if value != value
    return ~0.0 if value < 0
    return ~1.0 if value >= @probabilities.size - 1
    index = Math.floor(value).to_i
    @cumulative[index]

  -> mean
    total = ~0.0
    i = 0
    while i < @probabilities.size
      total += (i + ~0.0)*@probabilities[i]
      i += 1
    total

  -> variance
    center = mean
    total = ~0.0
    i = 0
    while i < @probabilities.size
      difference = (i + ~0.0) - center
      total += @probabilities[i]*difference*difference
      i += 1
    total

  -> entropy
    total = ~0.0
    i = 0
    while i < @probabilities.size
      total -= ProbabilityNumerics.xlogx(@probabilities[i])
      i += 1
    total

  -> mode
    best = 0
    i = 1
    while i < @probabilities.size
      best = i if @probabilities[i] > @probabilities[best]
      i += 1
    best

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Categorical quantile probability")
    return 0 if q == ~0.0
    index = 0
    while index < @cumulative.size - 1 && q > @cumulative[index]
      index += 1
    index

  -> sample(rng = nil)
    ProbabilitySampling.categorical_from_cumulative(@cumulative, rng)

  -> to_s
    "Categorical(probabilities=" + @probabilities.to_s + ")"


+ PoissonDistribution < ProbabilityDistribution
  -> new(rate)
    @rate = ProbabilityNumerics.positive_finite(rate, "Poisson rate")
    @support = ProbabilitySupport.new(0, nil, true, false, true)
    self

  -> rate
    @rate

  -> discrete?
    true

  -> support
    @support

  -> log_probability(value)
    return ProbabilityNumerics.negative_infinity if (
      !ProbabilityNumerics.integer?(value) || value < 0)
    value*Math.log(@rate) - @rate - ProbabilitySpecial.log_factorial(value)

  -> pmf(value)
    Math.exp(log_probability(value))

  -> cdf(value)
    return value if value != value
    return ~0.0 if value < 0
    count = Math.floor(value).to_i
    Special.gammaincc(count + ~1.0, @rate)

  -> survival(value)
    return value if value != value
    return ~1.0 if value < 0
    count = Math.floor(value).to_i
    Special.gammainc(count + ~1.0, @rate)

  -> mean
    @rate

  -> variance
    @rate

  -> mode
    Math.floor(@rate).to_i

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Poisson quantile probability")
    return 0 if q == ~0.0
    return ProbabilityNumerics.positive_infinity if q == ~1.0
    upper = (@rate + ~10.0*Math.sqrt(@rate) + ~10.0).to_i
    upper = 1 if upper < 1
    while cdf(upper) < q
      upper *= 2
    lower = 0
    while lower < upper
      middle = (lower + upper) / 2
      if cdf(middle) < q
        lower = middle + 1
      else
        upper = middle
    lower

  -> sample_small(rng)
    threshold = Math.exp(~0.0 - @rate)
    product = ~1.0
    count = 0
    while product > threshold
      product *= ProbabilityRandom.random_unit(rng)
      count += 1
    count - 1

  # Hoermann PTRS transformed rejection for large rates.
  -> sample_large(rng)
    root = Math.sqrt(@rate)
    b = ~0.931 + ~2.53*root
    a = ~-0.059 + ~0.02483*b
    inverse_alpha = ~1.1239 + ~1.1328 / (b - ~3.4)
    squeeze = ~0.9277 - ~3.6224 / (b - ~2.0)
    attempts = 0
    while attempts < 100000
      u = ProbabilityRandom.random_unit(rng) - ~0.5
      v = ProbabilityRandom.random_unit(rng)
      magnitude = u < ~0.0 ? ~0.0 - u : u
      us = ~0.5 - magnitude
      if us > ~0.0
        candidate = Math.floor(
          (~2.0*a / us + b)*u + @rate + ~0.43).to_i
        return candidate if us >= ~0.07 && v <= squeeze
        if candidate >= 0 && !(us < ~0.013 && v > us)
          left = Math.log(
            v*inverse_alpha / (a / (us*us) + b))
          right = (~0.0 - @rate + candidate*Math.log(@rate) -
                   ProbabilitySpecial.log_factorial(candidate))
          return candidate if left <= right
      attempts += 1
    raise "probability Poisson sampler rejection limit exceeded"

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    return sample_small(rng) if @rate < ~30.0
    sample_large(rng)

  -> to_s
    "Poisson(rate=" + @rate.to_s + ")"
