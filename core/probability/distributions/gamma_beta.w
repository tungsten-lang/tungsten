# Gamma-family continuous distributions and their replayable samplers.

use core/math
use core/special
use core/probability/distribution
use core/probability/primitives
use core/probability/rng
use core/probability/support

+ GammaDistribution < ProbabilityDistribution
  -> new(shape, scale = ~1.0)
    @shape = ProbabilityNumerics.positive_finite(shape, "Gamma shape")
    @scale = ProbabilityNumerics.positive_finite(scale, "Gamma scale")
    @support = ProbabilitySupport.new(~0.0, nil)
    self

  -> shape
    @shape

  -> scale
    @scale

  -> rate
    ~1.0 / @scale

  -> support
    @support

  -> log_probability(value)
    return ProbabilityNumerics.negative_infinity if value < ~0.0
    if value == ~0.0
      return ProbabilityNumerics.positive_infinity if @shape < ~1.0
      return ~0.0 - Math.log(@scale) if @shape == ~1.0
      return ProbabilityNumerics.negative_infinity
    ((@shape - ~1.0)*Math.log(value) - value / @scale -
     Special.lgamma(@shape) - @shape*Math.log(@scale))

  -> pdf(value)
    log_value = log_probability(value)
    return log_value if log_value.infinite? && log_value > ~0.0
    Math.exp(log_value)

  -> cdf(value)
    return ~0.0 if value <= ~0.0
    Special.gammainc(@shape, value / @scale)

  -> survival(value)
    return ~1.0 if value <= ~0.0
    Special.gammaincc(@shape, value / @scale)

  -> log_survival(value)
    Math.log(survival(value))

  -> mean
    @shape * @scale

  -> variance
    @shape * @scale * @scale

  -> entropy
    (@shape + Math.log(@scale) + Special.lgamma(@shape) +
     (~1.0 - @shape)*Special.digamma(@shape))

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Gamma quantile probability")
    return ~0.0 if q == ~0.0
    return ProbabilityNumerics.positive_infinity if q == ~1.0
    upper = mean + ~8.0*standard_deviation
    upper = @scale if upper <= ~0.0
    expansions = 0
    while cdf(upper) < q && expansions < 128
      upper *= ~2.0
      return upper if upper.infinite?
      expansions += 1
    lower = ~0.0
    iteration = 0
    while iteration < 100
      middle = (lower + upper) / ~2.0
      if cdf(middle) < q
        lower = middle
      else
        upper = middle
      iteration += 1
    (lower + upper) / ~2.0

  -> sample_shape(shape, rng)
    if shape < ~1.0
      boosted = sample_shape(shape + ~1.0, rng)
      unit = ProbabilityRandom.random_unit(rng)
      return boosted * Math.pow(unit, ~1.0 / shape)

    d = shape - ~0.3333333333333333
    c = ~1.0 / Math.sqrt(~9.0*d)
    attempts = 0
    while attempts < 100000
      z = ProbabilityRandom.standard_normal(rng)
      factor = ~1.0 + c*z
      if factor > ~0.0
        volume = factor*factor*factor
        unit = ProbabilityRandom.random_unit(rng)
        z2 = z*z
        if unit < ~1.0 - ~0.0331*z2*z2
          return d*volume
        if Math.log(unit) < ~0.5*z2 + d*(~1.0 - volume + Math.log(volume))
          return d*volume
      attempts += 1
    raise "probability Gamma sampler rejection limit exceeded"

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    @scale * sample_shape(@shape, rng)

  -> to_s
    "Gamma(shape=" + @shape.to_s + ", scale=" + @scale.to_s + ")"


+ BetaDistribution < ProbabilityDistribution
  -> new(alpha, beta)
    @alpha = ProbabilityNumerics.positive_finite(alpha, "Beta alpha")
    @beta = ProbabilityNumerics.positive_finite(beta, "Beta beta")
    @log_normalizer = Special.betaln(@alpha, @beta)
    @support = ProbabilitySupport.new(~0.0, ~1.0)
    self

  -> alpha
    @alpha

  -> beta
    @beta

  -> support
    @support

  -> log_probability(value)
    return ProbabilityNumerics.negative_infinity if (
      value < ~0.0 || value > ~1.0)
    if value == ~0.0
      return ProbabilityNumerics.positive_infinity if @alpha < ~1.0
      return ~0.0 - @log_normalizer if @alpha == ~1.0
      return ProbabilityNumerics.negative_infinity
    if value == ~1.0
      return ProbabilityNumerics.positive_infinity if @beta < ~1.0
      return ~0.0 - @log_normalizer if @beta == ~1.0
      return ProbabilityNumerics.negative_infinity
    ((@alpha - ~1.0)*Math.log(value) +
     (@beta - ~1.0)*Math.log1p(~0.0 - value) - @log_normalizer)

  -> pdf(value)
    log_value = log_probability(value)
    return log_value if log_value.infinite? && log_value > ~0.0
    Math.exp(log_value)

  -> cdf(value)
    return ~0.0 if value <= ~0.0
    return ~1.0 if value >= ~1.0
    Special.betainc(@alpha, @beta, value)

  -> survival(value)
    return ~1.0 if value <= ~0.0
    return ~0.0 if value >= ~1.0
    # Use the reflected incomplete beta rather than subtracting from one.
    Special.betainc(@beta, @alpha, ~1.0 - value)

  -> mean
    @alpha / (@alpha + @beta)

  -> variance
    total = @alpha + @beta
    @alpha*@beta / (total*total*(total + ~1.0))

  -> entropy
    (@log_normalizer - (@alpha - ~1.0)*Special.digamma(@alpha) -
     (@beta - ~1.0)*Special.digamma(@beta) +
     (@alpha + @beta - ~2.0)*Special.digamma(@alpha + @beta))

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Beta quantile probability")
    return ~0.0 if q == ~0.0
    return ~1.0 if q == ~1.0
    lower = ~0.0
    upper = ~1.0
    iteration = 0
    while iteration < 100
      middle = (lower + upper) / ~2.0
      if cdf(middle) < q
        lower = middle
      else
        upper = middle
      iteration += 1
    (lower + upper) / ~2.0

  -> sample(rng = nil)
    ProbabilityRandom.require_rng(rng)
    alpha_draw = GammaDistribution.new(@alpha).sample(rng)
    beta_draw = GammaDistribution.new(@beta).sample(rng)
    attempts = 0
    while alpha_draw + beta_draw == ~0.0 && attempts < 1000
      alpha_draw = GammaDistribution.new(@alpha).sample(rng)
      beta_draw = GammaDistribution.new(@beta).sample(rng)
      attempts += 1
    if alpha_draw + beta_draw == ~0.0
      raise "probability Beta sampler underflow retry limit exceeded"
    alpha_draw / (alpha_draw + beta_draw)

  -> to_s
    "Beta(alpha=" + @alpha.to_s + ", beta=" + @beta.to_s + ")"
