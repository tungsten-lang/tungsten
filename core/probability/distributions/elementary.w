# Bernoulli, Uniform, Normal, and Exponential distributions.

use core/math
use core/probability/distribution
use core/probability/primitives
use core/probability/rng
use core/probability/special
use core/probability/support

+ BernoulliDistribution < ProbabilityDistribution
  -> new(p = ~0.5)
    @p = ProbabilityNumerics.unit_probability(p, "Bernoulli p")
    @support = ProbabilitySupport.new(0, 1, true, true, true)
    self

  -> p
    @p

  -> success_probability
    @p

  -> discrete?
    true

  -> support
    @support

  -> pmf(value)
    return ~1.0 - @p if value == 0
    return @p if value == 1
    ~0.0

  -> cdf(value)
    return value if value != value
    return ~0.0 if value < 0
    return ~1.0 - @p if value < 1
    ~1.0

  -> survival(value)
    return value if value != value
    return ~1.0 if value < 0
    return @p if value < 1
    ~0.0

  -> log_probability(value)
    return Math.log1p(~0.0 - @p) if value == 0
    return Math.log(@p) if value == 1
    ProbabilityNumerics.negative_infinity

  -> mean
    @p

  -> variance
    @p * (~1.0 - @p)

  -> entropy
    (~0.0 - ProbabilityNumerics.xlogx(@p) -
     ProbabilityNumerics.xlogx(~1.0 - @p))

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Bernoulli quantile probability")
    return 0 if q <= ~1.0 - @p
    1

  -> sample(rng = nil)
    ProbabilityRandom.random_unit(rng) < @p ? 1 : 0

  -> to_s
    "Bernoulli(p=" + @p.to_s + ")"


+ UniformDistribution < ProbabilityDistribution
  -> new(lower = ~0.0, upper = ~1.0)
    @lower = ProbabilityNumerics.finite_float(lower, "Uniform lower bound")
    @upper = ProbabilityNumerics.finite_float(upper, "Uniform upper bound")
    if @lower >= @upper
      raise "probability Uniform lower bound must be less than upper bound"
    @width = @upper - @lower
    @support = ProbabilitySupport.new(@lower, @upper)
    self

  -> lower
    @lower

  -> upper
    @upper

  -> support
    @support

  -> pdf(value)
    return value if value != value
    return ~0.0 if value < @lower || value > @upper
    ~1.0 / @width

  -> cdf(value)
    return value if value != value
    return ~0.0 if value <= @lower
    return ~1.0 if value >= @upper
    (value - @lower) / @width

  -> survival(value)
    return value if value != value
    return ~1.0 if value <= @lower
    return ~0.0 if value >= @upper
    (@upper - value) / @width

  -> log_probability(value)
    return value if value != value
    return ProbabilityNumerics.negative_infinity if (
      value < @lower || value > @upper)
    ~0.0 - Math.log(@width)

  -> log_survival(value)
    return ProbabilityNumerics.negative_infinity if value >= @upper
    return ~0.0 if value <= @lower
    Math.log(@upper - value) - Math.log(@width)

  -> mean
    (@lower + @upper) / ~2.0

  -> variance
    @width * @width / ~12.0

  -> entropy
    Math.log(@width)

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Uniform quantile probability")
    @lower + @width*q

  -> sample(rng = nil)
    @lower + @width * ProbabilityRandom.random_unit(rng)

  -> to_s
    "Uniform(lower=" + @lower.to_s + ", upper=" + @upper.to_s + ")"


+ NormalDistribution < ProbabilityDistribution
  -> new(mean = ~0.0, standard_deviation = ~1.0)
    @mean = ProbabilityNumerics.finite_float(mean, "Normal mean")
    @standard_deviation = ProbabilityNumerics.positive_finite(
      standard_deviation, "Normal standard deviation")
    @variance = @standard_deviation * @standard_deviation
    @support = ProbabilitySupport.new(nil, nil, false, false)
    self

  -> mean
    @mean

  -> standard_deviation
    @standard_deviation

  -> variance
    @variance

  -> support
    @support

  -> standardized(value)
    (value - @mean) / @standard_deviation

  -> pdf(value)
    (ProbabilitySpecial.standard_normal_pdf(standardized(value)) /
     @standard_deviation)

  -> cdf(value)
    ProbabilitySpecial.standard_normal_cdf(standardized(value))

  -> survival(value)
    ProbabilitySpecial.standard_normal_survival(standardized(value))

  -> log_probability(value)
    z = standardized(value)
    ~-0.5 * z * z - Math.log(@standard_deviation) - ~0.9189385332046727

  -> log_survival(value)
    Math.log(survival(value))

  -> entropy
    ~0.5 * Math.log(~17.079468445347132 * @variance)

  -> quantile(probability)
    @mean + @standard_deviation * ProbabilitySpecial.normal_quantile(probability)

  -> sample(rng = nil)
    @mean + @standard_deviation * ProbabilityRandom.standard_normal(rng)

  -> to_s
    ("Normal(mean=" + @mean.to_s + ", standard_deviation=" +
     @standard_deviation.to_s + ")")


+ ExponentialDistribution < ProbabilityDistribution
  -> new(rate = ~1.0)
    @rate = ProbabilityNumerics.positive_finite(rate, "Exponential rate")
    @support = ProbabilitySupport.new(~0.0, nil)
    self

  -> rate
    @rate

  -> support
    @support

  -> pdf(value)
    return ~0.0 if value < ~0.0
    @rate * Math.exp(~0.0 - @rate * value)

  -> cdf(value)
    return ~0.0 if value < ~0.0
    ~0.0 - Math.expm1(~0.0 - @rate * value)

  -> survival(value)
    return ~1.0 if value < ~0.0
    Math.exp(~0.0 - @rate * value)

  -> log_probability(value)
    return ProbabilityNumerics.negative_infinity if value < ~0.0
    Math.log(@rate) - @rate * value

  -> log_survival(value)
    return ~0.0 if value < ~0.0
    ~0.0 - @rate * value

  -> mean
    ~1.0 / @rate

  -> variance
    ~1.0 / (@rate * @rate)

  -> entropy
    ~1.0 - Math.log(@rate)

  -> quantile(probability)
    q = ProbabilityNumerics.unit_probability(
      probability, "Exponential quantile probability")
    (~0.0 - Math.log1p(~0.0 - q)) / @rate

  -> sample(rng = nil)
    unit = ProbabilityRandom.random_unit(rng)
    (~0.0 - Math.log1p(~0.0 - unit)) / @rate

  -> to_s
    "Exponential(rate=" + @rate.to_s + ")"
