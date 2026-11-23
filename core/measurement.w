# MeasurementSource — identity of one independent uncertainty contribution.
+ MeasurementSource
  -> new
    nil

# MeasurementSources — signed total, random and systematic contributions by source.
+ MeasurementSources
  -> new
    @terms = []

  -> add(source, total, random, systematic)
    i = 0
    while i < @terms.size
      term = @terms[i]
      if term[0] == source
        term[1] += total
        term[2] += random
        term[3] += systematic
        return self
      i += 1
    @terms.push([source, total, random, systematic])
    self

  -> accumulate(target, scale)
    @terms.each ->(term)
      target.add(term[0], scale * term[1], scale * term[2], scale * term[3])
    target

  -> coefficient(source)
    i = 0
    while i < @terms.size
      term = @terms[i]
      return term[1] if term[0] == source
      i += 1
    ~0.0

  -> covariance(other, left_scale = ~1.0, right_scale = ~1.0)
    total = ~0.0
    @terms.each ->(term)
      total += (term[1] / left_scale) * (other.coefficient(term[0]) / right_scale)
    total

  -> norm(column)
    length = ~0.0
    @terms.each ->(term)
      length = Math.hypot(length, term[column])
    length

# Measurement — a scalar estimate and its standard uncertainty.
#
# `value ± uncertainty` is desugared by the parser to
# `Measurement.new(value, uncertainty)`. Arithmetic uses first-order (linear)
# uncertainty propagation. Distinct inputs are independent unless `correlate`
# declares a Pearson coefficient for that pair; repeated use of the identical
# object has correlation one. This is a propagation model, not an interval
# proof or a distributional guarantee.
+ Measurement
  - data
    rw value
    rw uncertainty
    rw lower_uncertainty
    rw upper_uncertainty
    rw coverage_factor
    rw confidence
    rw degrees_of_freedom
    rw provenance
    rw random_uncertainty
    rw systematic_uncertainty
    rw correlation_peer
    rw correlation_coefficient

  # One defaulted constructor preserves the two-, eight-, and twelve-argument
  # call surfaces without relying on constructor-overload resolution.
  -> new(@value, @uncertainty,
         @lower_uncertainty = nil, @upper_uncertainty = nil,
         @coverage_factor = ~1.0, @confidence = nil,
         @degrees_of_freedom = nil, @provenance = nil,
         @random_uncertainty = ~0.0, @systematic_uncertainty = ~0.0,
         @correlation_peer = nil, @correlation_coefficient = ~0.0)
    if !Measurement.finite_number?(@value)
      raise "Measurement value must be a finite number"
    if !Measurement.finite_number?(@uncertainty)
      raise "Measurement uncertainty must be a finite number"
    @uncertainty = uncertainty.abs
    if lower_uncertainty == nil
      @lower_uncertainty = @uncertainty
    else
      if !Measurement.finite_number?(lower_uncertainty)
        raise "Measurement lower uncertainty must be finite"
      @lower_uncertainty = lower_uncertainty.abs
    if upper_uncertainty == nil
      @upper_uncertainty = @uncertainty
    else
      if !Measurement.finite_number?(upper_uncertainty)
        raise "Measurement upper uncertainty must be finite"
      @upper_uncertainty = upper_uncertainty.abs
    if (!Measurement.finite_number?(@coverage_factor) ||
        @coverage_factor <= ~0.0)
      raise "Measurement coverage factor must be positive and finite"
    if (!Measurement.finite_number?(@random_uncertainty) ||
        !Measurement.finite_number?(@systematic_uncertainty))
      raise "Measurement uncertainty components must be finite"
    @random_uncertainty = @random_uncertainty.abs
    @systematic_uncertainty = @systematic_uncertainty.abs
    Measurement.validate_correlation(@correlation_coefficient)
    if (@correlation_peer != nil &&
        !Measurement.measurement?(@correlation_peer))
      raise "Measurement correlation peer must be a Measurement"
    reset_sources
    if provenance == nil
      @provenance = []
    elsif provenance.class_name == "Array"
      @provenance = provenance.dup
    else
      raise "Measurement provenance must be an Array"

  # Explicit readers are intentional: `rw` data declarations describe the
  # layout but are not accessor generation in every Tungsten engine.
  ro :value

  ro :uncertainty

  -> standard_uncertainty
    @uncertainty

  ro :lower_uncertainty, :upper_uncertainty, :coverage_factor, :confidence, :degrees_of_freedom

  -> provenance
    @provenance.dup

  ro :random_uncertainty, :systematic_uncertainty, :correlation_peer, :correlation_coefficient

  -> .measurement?(value)
    value.class_name == "Measurement"

  -> .same_object?(left, right)
    left == right

  -> .finite_number?(value)
    name = value.class_name
    numeric = name == "Float" || name == "Integer" || name == "Int"
    numeric = true if name == "BigInt" || name == "Decimal"
    return false if !numeric
    number = value.to_f()
    !number.nan? && !number.infinite?

  -> .nonnegative_variance(variance, contribution_scale)
    if !Measurement.finite_number?(variance)
      raise "propagated variance must be finite"
    return variance if variance >= ~0.0
    # A valid covariance model is nonnegative; roundoff can leave a tiny
    # negative residual after cancellation at |rho| = 1.
    tolerance = ~1.0e-12 * contribution_scale.abs
    return ~0.0 if variance >= ~0.0 - tolerance
    raise "propagated variance is negative; check the covariance model"

  -> .validate_correlation(coefficient)
    if (!Measurement.finite_number?(coefficient) ||
        coefficient < ~-1.0 || coefficient > ~1.0)
      raise "correlation must be between -1 and 1"
    coefficient

  -> .asymmetric(value, lower, upper)
    standard = (lower.abs + upper.abs) / ~2.0
    Measurement.new(
      value, standard, lower.abs, upper.abs, ~1.0, nil, nil, [])

  -> .with_components(value, random, systematic)
    random = random.abs
    systematic = systematic.abs
    uncertainty = Math.sqrt(
      random * random + systematic * systematic)
    Measurement.new(
      value, uncertainty, uncertainty, uncertainty, ~1.0, nil,
      nil, [], random, systematic, nil, ~0.0)

  -> components
    {:random => random_uncertainty, :systematic => systematic_uncertainty}

  -> reset_sources
    @sources = MeasurementSources.new
    @sources.add(MeasurementSource.new, uncertainty, random_uncertainty, systematic_uncertainty)
    self

  -> contribute_to(terms, scale)
    @sources.accumulate(terms, scale)

  -> covariance_with(other)
    other.covariance_from(@sources)

  -> covariance_from(terms)
    @sources.covariance(terms)

  -> with_sources(terms)
    @sources = terms
    self

  -> correlate(other, coefficient)
    if !Measurement.measurement?(other)
      raise "correlation needs another Measurement"
    if Measurement.same_object?(other, self)
      raise "correlation needs a distinct Measurement"
    Measurement.validate_correlation(coefficient)
    if (@correlation_peer != nil &&
        !Measurement.same_object?(@correlation_peer, other))
      @correlation_peer.clear_correlation_from(self)
    if (other.correlation_peer != nil &&
        !Measurement.same_object?(other.correlation_peer, self))
      other.correlation_peer.clear_correlation_from(other)
    @correlation_peer = other
    @correlation_coefficient = coefficient
    # Declare a new joint error model for this pair. Earlier results retain
    # the basis they used, including after a later correlation rebind.
    shared = MeasurementSource.new
    @sources = MeasurementSources.new
    @sources.add(shared, uncertainty, random_uncertainty, systematic_uncertainty)
    other.set_pair_sources(shared, coefficient)
    other.correlate_back(self, coefficient)
    self

  -> set_pair_sources(shared, rho)
    residual = Math.sqrt((~1.0 - rho) * (~1.0 + rho))
    @sources = MeasurementSources.new
    @sources.add(shared, rho * uncertainty, rho * random_uncertainty, rho * systematic_uncertainty)
    @sources.add(MeasurementSource.new, residual * uncertainty,
                 residual * random_uncertainty, residual * systematic_uncertainty)

  -> correlate_back(other, coefficient)
    @correlation_peer = other
    @correlation_coefficient = coefficient
    self

  -> clear_correlation_from(other)
    if (@correlation_peer != nil &&
        Measurement.same_object?(@correlation_peer, other))
      @correlation_peer = nil
      @correlation_coefficient = ~0.0
      reset_sources
    self

  -> correlation_with(other)
    return ~0.0 if !Measurement.measurement?(other)
    return ~1.0 if Measurement.same_object?(self, other)
    if (correlation_peer != nil && Measurement.same_object?(correlation_peer, other) &&
        other.correlation_peer != nil && Measurement.same_object?(other.correlation_peer, self) &&
        other.correlation_coefficient == correlation_coefficient)
      return correlation_coefficient
    return ~0.0 if uncertainty == ~0.0 || other.uncertainty == ~0.0
    rho = other.normalized_covariance_from(@sources, uncertainty)
    return ~1.0 if rho > ~1.0
    return ~-1.0 if rho < ~-1.0
    rho

  -> normalized_covariance_from(terms, sigma)
    @sources.covariance(terms, uncertainty, sigma)

  -> expanded(k = ~2.0, confidence = nil)
    confidence = @confidence if confidence == nil
    Measurement.new(
      value, uncertainty, lower_uncertainty, upper_uncertainty,
      k, confidence, degrees_of_freedom, provenance,
      random_uncertainty, systematic_uncertainty, nil, ~0.0).with_sources(@sources)

  -> interval
    [value - lower_uncertainty * coverage_factor,
     value + upper_uncertainty * coverage_factor]

  -> combined_provenance(other = nil)
    result = provenance
    if other != nil && Measurement.measurement?(other)
      other.provenance.each -> (source) result.push(source)
    result

  -> propagated(other, result_value, dx, dy)
    terms = contribute_to(MeasurementSources.new, dx)
    other.contribute_to(terms, dy)
    sigma = terms.norm(1)
    Measurement.new(result_value, sigma, sigma, sigma, ~1.0, nil, nil,
                    combined_provenance(other), terms.norm(2), terms.norm(3)).with_sources(terms)

  # General two-input first-order propagation:
  #   var(f) = fx^2 ux^2 + fy^2 uy^2 + 2 fx fy rho ux uy.
  -> binary_result(other, result_value, derivative_self, derivative_other, rho)
    Measurement.validate_correlation(rho)
    if rho == correlation_with(other)
      return propagated(other, result_value, derivative_self, derivative_other)
    # An explicit override defines a local two-input error model. Resolve
    # the second contribution along and perpendicular to the first.
    residual = Math.sqrt((~1.0 - rho) * (~1.0 + rho))
    left = derivative_self * uncertainty
    right = derivative_other * other.uncertainty
    sigma = Math.hypot(left + rho * right, residual * right)
    left = derivative_self * random_uncertainty
    right = derivative_other * other.random_uncertainty
    random = Math.hypot(left + rho * right, residual * right)
    left = derivative_self * systematic_uncertainty
    right = derivative_other * other.systematic_uncertainty
    systematic = Math.hypot(left + rho * right, residual * right)
    Measurement.new(result_value, sigma, sigma, sigma, ~1.0, nil, nil,
                    combined_provenance(other), random, systematic)

  -> unary_result(result_value, derivative)
    scale = derivative.abs
    result_uncertainty = scale * uncertainty
    Measurement.new(
      result_value, result_uncertainty, result_uncertainty,
      result_uncertainty, ~1.0, nil, nil, provenance,
      scale * random_uncertainty, scale * systematic_uncertainty,
      nil, ~0.0).with_sources(contribute_to(MeasurementSources.new, derivative))

  -> shifted(scalar, sign)
    Measurement.new(
      value + sign * scalar, uncertainty,
      lower_uncertainty, upper_uncertainty,
      coverage_factor, confidence, degrees_of_freedom, provenance,
      random_uncertainty, systematic_uncertainty, nil, ~0.0).with_sources(@sources)

  -> scaled(scalar)
    magnitude = scalar.abs
    lower = lower_uncertainty * magnitude
    upper = upper_uncertainty * magnitude
    if scalar < ~0.0
      temporary = lower
      lower = upper
      upper = temporary
    Measurement.new(
      value * scalar, uncertainty * magnitude, lower, upper,
      coverage_factor, confidence, degrees_of_freedom, provenance,
      random_uncertainty * magnitude,
      systematic_uncertainty * magnitude, nil, ~0.0).with_sources(contribute_to(MeasurementSources.new, scalar))

  -> +(other)
    if Measurement.measurement?(other)
      return propagated(other, value + other.value, ~1.0, ~1.0)
    shifted(other, ~1.0)

  -> -(other)
    if Measurement.measurement?(other)
      return propagated(other, value - other.value, ~1.0, ~-1.0)
    shifted(other, ~-1.0)

  -> -@
    scaled(~-1.0)

  -> *(other)
    if Measurement.measurement?(other)
      return propagated(other, value * other.value, other.value, value)
    scaled(other)

  -> /(other)
    if Measurement.measurement?(other)
      raise "Measurement division by zero" if other.value == ~0.0
      return propagated(other, value / other.value, ~1.0 / other.value, (~0.0 - value) / (other.value * other.value))
    raise "Measurement division by zero" if other == 0
    scaled(~1.0 / other)

  -> **(exponent)
    result_value = value ** exponent
    if value == ~0.0
      if exponent == 1
        return unary_result(result_value, ~1.0)
      if exponent > 1 || exponent == 0
        return unary_result(result_value, ~0.0)
      raise "uncertain zero cannot be raised to this exponent"
    derivative = exponent * (value ** (exponent - 1))
    unary_result(result_value, derivative)

  -> pow(exponent)
    self ** exponent

  -> sqrt
    raise "Measurement.sqrt needs a nonnegative value" if value < ~0.0
    if value == ~0.0
      if uncertainty == ~0.0
        return Measurement.new(~0.0, ~0.0)
      raise "Measurement.sqrt is singular at uncertain zero"
    root = Math.sqrt(value)
    unary_result(root, ~1.0 / (~2.0 * root))

  -> add_correlated(other, rho)
    binary_result(other, value + other.value, ~1.0, ~1.0, rho)

  -> sub_correlated(other, rho)
    binary_result(other, value - other.value, ~1.0, ~-1.0, rho)

  -> mul_correlated(other, rho)
    binary_result(other, value * other.value, other.value, value, rho)

  -> div_correlated(other, rho)
    raise "Measurement division by zero" if other.value == ~0.0
    derivative_self = ~1.0 / other.value
    derivative_other = (~0.0 - value) / (other.value * other.value)
    binary_result(
      other, value / other.value,
      derivative_self, derivative_other, rho)

  -> calibrate(calibration)
    calibration.apply(self)

  -> to_s
    suffix = ""
    if coverage_factor != ~1.0
      suffix = " (k=[coverage_factor])"
    if lower_uncertainty != upper_uncertainty
      return "[value] +[upper_uncertainty]/-[lower_uncertainty][suffix]"
    "[value] ± [uncertainty][suffix]"

  -> inspect
    to_s
