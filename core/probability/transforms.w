# Scalar affine images, interval truncation, and finite discrete conditioning.

use core/math
use core/probability/distribution
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/rng
use core/probability/sampling
use core/probability/support

+ AffineDistribution < ProbabilityDistribution
  ro :base, :shift, :scale, :support

  -> new(base, shift, scale)
    if !base.continuous?
      raise "probability affine distribution currently requires a continuous base"
    @base = base
    @shift = ProbabilityNumerics.finite_float(shift, "affine shift")
    @scale = ProbabilityNumerics.finite_float(scale, "affine scale")
    if @scale == ~0.0
      raise "probability affine scale must be nonzero"
    source = base.support
    if @scale > ~0.0
      lower = source.lower == nil ? nil : @shift + @scale*source.lower
      upper = source.upper == nil ? nil : @shift + @scale*source.upper
      lower_closed = source.lower_closed?
      upper_closed = source.upper_closed?
    else
      lower = source.upper == nil ? nil : @shift + @scale*source.upper
      upper = source.lower == nil ? nil : @shift + @scale*source.lower
      lower_closed = source.upper_closed?
      upper_closed = source.lower_closed?
    @support = ProbabilitySupport.new(
      lower, upper, lower_closed, upper_closed)
    self

  -> source_value(value)
    (value - @shift) / @scale

  -> log_probability(value)
    @base.log_prob(source_value(value)) - Math.log(
      ProbabilityLinearAlgebra.absolute(@scale))

  -> pdf(value)
    Math.exp(log_probability(value))

  -> cdf(value)
    source = source_value(value)
    return @base.cdf(source) if @scale > ~0.0
    @base.survival(source)

  -> survival(value)
    source = source_value(value)
    return @base.survival(source) if @scale > ~0.0
    @base.cdf(source)

  -> mean
    @shift + @scale*@base.mean

  -> variance
    @scale*@scale*@base.variance

  -> entropy
    @base.entropy + Math.log(ProbabilityLinearAlgebra.absolute(@scale))

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "affine quantile probability")
    source_probability = @scale > ~0.0 ? q : ~1.0 - q
    @shift + @scale*@base.quantile(source_probability)

  -> sample(rng = nil)
    @shift + @scale*@base.sample(rng)


+ TruncatedDistribution < ProbabilityDistribution
  ro :base, :support

  -> new(base, lower, upper)
    if !base.continuous?
      raise "probability truncation currently requires a continuous base"
    @base = base
    @lower = ProbabilityNumerics.finite_float(lower, "truncation lower bound")
    @upper = ProbabilityNumerics.finite_float(upper, "truncation upper bound")
    if @lower >= @upper
      raise "probability truncation lower bound must be less than upper bound"
    @lower_cdf = base.cdf(@lower)
    @upper_cdf = base.cdf(@upper)
    @normalizer = @upper_cdf - @lower_cdf
    if @normalizer <= ~0.0 || @normalizer != @normalizer
      raise "probability truncation mass is not representable in binary64"
    @log_normalizer = Math.log(@normalizer)
    @support = ProbabilitySupport.new(@lower, @upper)
    self

  -> log_probability(value)
    return ProbabilityNumerics.negative_infinity if (
      value < @lower || value > @upper)
    @base.log_prob(value) - @log_normalizer

  -> pdf(value)
    Math.exp(log_probability(value))

  -> cdf(value)
    return ~0.0 if value <= @lower
    return ~1.0 if value >= @upper
    (@base.cdf(value) - @lower_cdf) / @normalizer

  -> survival(value)
    return ~1.0 if value <= @lower
    return ~0.0 if value >= @upper
    (@upper_cdf - @base.cdf(value)) / @normalizer

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "truncated quantile probability")
    @base.quantile(@lower_cdf + q*@normalizer)

  -> sample(rng = nil)
    quantile(ProbabilityRandom.random_unit(rng))


+ FiniteConditionedDistribution < ProbabilityDistribution
  ro :support

  -> new(base, allowed_values)
    if !base.discrete? || allowed_values.class_name != "Array" || (
       allowed_values.size == 0)
      raise "probability finite conditioning needs a discrete base and values"
    @base = base
    @values = ProbabilityNumerics.copy_array(allowed_values)
    masses = []
    i = 0
    while i < @values.size
      j = 0
      while j < i
        if @values[i] == @values[j]
          raise "probability conditioning values must be unique"
        j += 1
      masses.push(base.pmf(@values[i]))
      i += 1
    @probabilities = ProbabilityNumerics.normalized_weights(
      masses, "conditioning masses")
    @cumulative = ProbabilityNumerics.cumulative_probabilities(@probabilities)
    @support = ProbabilityFiniteSupport.new(@values)
    self

  -> discrete?
    true

  -> values
    ProbabilityNumerics.copy_array(@values)

  -> probabilities
    ProbabilityNumerics.copy_array(@probabilities)

  -> index_of(value)
    i = 0
    while i < @values.size
      return i if @values[i] == value
      i += 1
    nil

  -> pmf(value)
    index = index_of(value)
    return ~0.0 if index == nil
    @probabilities[index]

  -> log_probability(value)
    mass = pmf(value)
    return ProbabilityNumerics.negative_infinity if mass == ~0.0
    Math.log(mass)

  -> mean
    total = ~0.0
    i = 0
    while i < @values.size
      total += @values[i].to_f*@probabilities[i]
      i += 1
    total

  -> variance
    center = mean
    total = ~0.0
    i = 0
    while i < @values.size
      difference = @values[i].to_f - center
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

  -> sample(rng = nil)
    @values[ProbabilitySampling.categorical_from_cumulative(
      @cumulative, rng)]
