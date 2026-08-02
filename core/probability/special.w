# Probability-specific special functions and inverse-CDF numerics.

use core/math
use core/special
use core/probability/primitives

+ ProbabilitySpecial
  -> .standard_normal_pdf(value)
    Math.exp(~-0.5 * value * value) / ~2.5066282746310005

  -> .standard_normal_cdf(value)
    if value < ~0.0
      return ~0.5 * Special.erfc((~0.0 - value) / ~1.4142135623730951)
    ~1.0 - ~0.5 * Special.erfc(value / ~1.4142135623730951)

  -> .standard_normal_survival(value)
    if value < ~0.0
      return ~1.0 - ~0.5 * Special.erfc((~0.0 - value) / ~1.4142135623730951)
    ~0.5 * Special.erfc(value / ~1.4142135623730951)

  # Peter J. Acklam's binary64 inverse-normal approximation, followed by one
  # Newton correction through the tail-stable CDF above.
  -> .normal_quantile(probability)
    p = ProbabilityNumerics.unit_probability(
      probability, "Normal quantile probability")
    return ProbabilityNumerics.negative_infinity if p == ~0.0
    return ProbabilityNumerics.positive_infinity if p == ~1.0

    a = [
      ~-39.69683028665376, ~220.9460984245205,
      ~-275.9285104469687, ~138.3577518672690,
      ~-30.66479806614716, ~2.506628277459239
    ]
    b = [
      ~-54.47609879822406, ~161.5858368580409,
      ~-155.6989798598866, ~66.80131188771972,
      ~-13.28068155288572
    ]
    c = [
      ~-0.007784894002430293, ~-0.3223964580411365,
      ~-2.400758277161838, ~-2.549732539343734,
      ~4.374664141464968, ~2.938163982698783
    ]
    d = [
      ~0.007784695709041462, ~0.3224671290700398,
      ~2.445134137142996, ~3.754408661907416
    ]

    low = ~0.02425
    high = ~1.0 - low
    if p < low
      q = Math.sqrt(~-2.0 * Math.log(p))
      numerator = (((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5])
      denominator = ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + ~1.0)
      estimate = numerator / denominator
    elsif p > high
      q = Math.sqrt(~-2.0 * Math.log1p(~0.0 - p))
      numerator = (((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5])
      denominator = ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + ~1.0)
      estimate = ~0.0 - numerator / denominator
    else
      q = p - ~0.5
      r = q*q
      numerator = (((((a[0]*r + a[1])*r + a[2])*r + a[3])*r + a[4])*r + a[5]) * q
      denominator = (((((b[0]*r + b[1])*r + b[2])*r + b[3])*r + b[4])*r + ~1.0)
      estimate = numerator / denominator

    density = ProbabilitySpecial.standard_normal_pdf(estimate)
    if density > ~0.0
      estimate -= (
        ProbabilitySpecial.standard_normal_cdf(estimate) - p) / density
    estimate

  -> .log_factorial(value)
    if !ProbabilityNumerics.integer?(value) || value < 0
      raise "probability factorial argument must be a nonnegative integer"
    Special.lgamma(value + ~1.0)
