# Internal Student-t tail integration for regression inference.
#
# This is deliberately not a public probability-distribution API. Statistics
# consumes Special.betainc to report model p-values and confidence intervals;
# a future Probability module remains the owner of distributions and sampling.

+ StatisticsInference
  -> .degrees_of_freedom(value)
    if !Statistics.integer?(value) || value <= 0
      raise "Student-t inference requires positive integer degrees of freedom"
    value

  -> .two_sided_t_p(value, degrees_of_freedom)
    df = StatisticsInference.degrees_of_freedom(degrees_of_freedom)
    t = Statistics.scalar(value).abs
    ratio = t / Math.sqrt(df + ~0.0)
    x = ~1.0 / (~1.0 + ratio * ratio)
    probability = Special.betainc((df + ~0.0) / ~2.0, ~0.5, x)
    Statistics.finite_result(probability, "Student-t tail probability")
    probability = ~0.0 if probability < ~0.0
    probability = ~1.0 if probability > ~1.0
    probability

  -> .t_cdf(value, degrees_of_freedom)
    t = Statistics.scalar(value)
    half_tail = StatisticsInference.two_sided_t_p(
      t, degrees_of_freedom) / ~2.0
    t < ~0.0 ? half_tail : ~1.0 - half_tail

  # Central two-sided confidence level to positive t critical value.
  -> .critical_t(level, degrees_of_freedom)
    confidence = Statistics.scalar(level)
    if confidence <= ~0.0 || confidence >= ~1.0
      raise "confidence level must be strictly between zero and one"
    df = StatisticsInference.degrees_of_freedom(degrees_of_freedom)
    target = (~1.0 + confidence) / ~2.0
    lower = ~0.0
    upper = ~1.0
    while StatisticsInference.t_cdf(upper, df) < target
      upper *= ~2.0
      if upper > ~1.0e12
        raise "Student-t critical value search did not converge"
    iterations = 0
    while iterations < 100
      middle = (lower + upper) / ~2.0
      if StatisticsInference.t_cdf(middle, df) < target
        lower = middle
      else
        upper = middle
      iterations += 1
    (lower + upper) / ~2.0
