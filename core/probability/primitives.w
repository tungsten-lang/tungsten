# Stable scalar and log-weight primitives shared across Core Probability.

use core/math

+ ProbabilityNumerics
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .finite_float(value, parameter)
    converted = value.to_f
    if converted != converted || converted.infinite?
      raise "probability " + parameter + " must be finite"
    converted

  -> .unit_probability(value, parameter = "probability")
    converted = ProbabilityNumerics.finite_float(value, parameter)
    if converted < ~0.0 || converted > ~1.0
      raise "probability " + parameter + " must be between 0 and 1"
    converted

  -> .positive_finite(value, parameter)
    converted = ProbabilityNumerics.finite_float(value, parameter)
    if converted <= ~0.0
      raise "probability " + parameter + " must be positive"
    converted

  -> .nonnegative_finite(value, parameter)
    converted = ProbabilityNumerics.finite_float(value, parameter)
    if converted < ~0.0
      raise "probability " + parameter + " must be nonnegative"
    converted

  -> .validate_count(value, parameter = "sample count")
    if !ProbabilityNumerics.integer?(value) || value < 0
      raise "probability " + parameter + " must be a nonnegative integer"
    value

  -> .positive_infinity
    Math.exp(~1000.0)

  -> .negative_infinity
    ~0.0 - ProbabilityNumerics.positive_infinity

  -> .copy_array(values)
    if values.class_name != "Array"
      raise "probability values must be an Array"
    copy = []
    i = 0
    while i < values.size
      copy.push(values[i])
      i += 1
    copy

  # Kahan summation keeps normalization stable for heterogeneous weights.
  -> .sum(values)
    total = ~0.0
    correction = ~0.0
    i = 0
    while i < values.size
      value = values[i]
      adjusted = value - correction
      next_total = total + adjusted
      correction = (next_total - total) - adjusted
      total = next_total
      i += 1
    total

  -> .normalized_weights(values, parameter = "weights")
    if values.class_name != "Array" || values.size == 0
      raise "probability " + parameter + " must be a nonempty Array"
    weights = []
    i = 0
    while i < values.size
      weights.push(ProbabilityNumerics.nonnegative_finite(
        values[i], parameter + " entry"))
      i += 1
    total = ProbabilityNumerics.sum(weights)
    if total <= ~0.0 || total.infinite?
      raise "probability " + parameter + " must have a finite positive total"
    normalized = []
    i = 0
    while i < weights.size
      normalized.push(weights[i] / total)
      i += 1
    normalized

  -> .cumulative_probabilities(weights)
    cumulative = []
    total = ~0.0
    i = 0
    while i < weights.size
      total += weights[i]
      cumulative.push(total)
      i += 1
    cumulative[cumulative.size - 1] = ~1.0
    cumulative

  -> .logaddexp(left, right)
    a = left.to_f
    b = right.to_f
    raise "probability log weight must not be NaN" if a != a || b != b
    return a if a.infinite? && a > ~0.0
    return b if b.infinite? && b > ~0.0
    return a if b == ProbabilityNumerics.negative_infinity
    return b if a == ProbabilityNumerics.negative_infinity
    maximum = a > b ? a : b
    minimum = a > b ? b : a
    maximum + Math.log1p(Math.exp(minimum - maximum))

  -> .logsumexp(values)
    if values.class_name != "Array" || values.size == 0
      raise "probability log weights must be a nonempty Array"
    logs = []
    maximum = ProbabilityNumerics.negative_infinity
    i = 0
    while i < values.size
      value = values[i].to_f
      raise "probability log weight must not be NaN" if value != value
      if value.infinite? && value > ~0.0
        raise "probability log weight must not be positive infinity"
      maximum = value if value > maximum
      logs.push(value)
      i += 1
    return maximum if maximum.infinite?
    exponentials = []
    i = 0
    while i < logs.size
      exponentials.push(Math.exp(logs[i] - maximum))
      i += 1
    maximum + Math.log(ProbabilityNumerics.sum(exponentials))

  -> .normalize_log_weights(values)
    logs = ProbabilityNumerics.copy_array(values)
    normalizer = ProbabilityNumerics.logsumexp(logs)
    if normalizer.infinite?
      raise "probability log weights cannot all be negative infinity"
    normalized = []
    i = 0
    while i < logs.size
      normalized.push(Math.exp(logs[i].to_f - normalizer))
      i += 1
    normalized

  -> .effective_sample_size(weights)
    normalized = ProbabilityNumerics.normalized_weights(weights)
    square_sum = ~0.0
    i = 0
    while i < normalized.size
      square_sum += normalized[i] * normalized[i]
      i += 1
    ~1.0 / square_sum

  -> .effective_sample_size_from_log(log_weights)
    ProbabilityNumerics.effective_sample_size(
      ProbabilityNumerics.normalize_log_weights(log_weights))

  -> .xlogx(value)
    return ~0.0 if value == ~0.0
    value * Math.log(value)

  # log(1-exp(x)) for x <= 0 without cancellation near zero.
  -> .log1mexp(value)
    x = value.to_f
    raise "probability log1mexp needs x <= 0" if x > ~0.0 || x != x
    if x < ~-0.6931471805599453
      return Math.log1p(~0.0 - Math.exp(x))
    Math.log(~0.0 - Math.expm1(x))
