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
    if provenance == nil
      @provenance = []
    elsif provenance.class_name == "Array"
      @provenance = provenance.dup
    else
      raise "Measurement provenance must be an Array"

  # Explicit readers are intentional: `rw` data declarations describe the
  # layout but are not accessor generation in every Tungsten engine.
  -> value
    @value

  -> uncertainty
    @uncertainty

  -> standard_uncertainty
    @uncertainty

  -> lower_uncertainty
    @lower_uncertainty

  -> upper_uncertainty
    @upper_uncertainty

  -> coverage_factor
    @coverage_factor

  -> confidence
    @confidence

  -> degrees_of_freedom
    @degrees_of_freedom

  -> provenance
    @provenance.dup

  -> random_uncertainty
    @random_uncertainty

  -> systematic_uncertainty
    @systematic_uncertainty

  -> correlation_peer
    @correlation_peer

  -> correlation_coefficient
    @correlation_coefficient

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
    other.correlate_back(self, coefficient)
    self

  -> correlate_back(other, coefficient)
    @correlation_peer = other
    @correlation_coefficient = coefficient
    self

  -> clear_correlation_from(other)
    if (@correlation_peer != nil &&
        Measurement.same_object?(@correlation_peer, other))
      @correlation_peer = nil
      @correlation_coefficient = ~0.0
    self

  -> correlation_with(other)
    return ~0.0 if !Measurement.measurement?(other)
    return ~1.0 if Measurement.same_object?(self, other)
    return ~0.0 if correlation_peer == nil
    return ~0.0 if !Measurement.same_object?(correlation_peer, other)
    return ~0.0 if other.correlation_peer == nil
    return ~0.0 if !Measurement.same_object?(other.correlation_peer, self)
    return ~0.0 if other.correlation_coefficient != correlation_coefficient
    correlation_coefficient

  -> expanded(k = ~2.0, confidence = nil)
    confidence = @confidence if confidence == nil
    Measurement.new(
      value, uncertainty, lower_uncertainty, upper_uncertainty,
      k, confidence, degrees_of_freedom, provenance,
      random_uncertainty, systematic_uncertainty, nil, ~0.0)

  -> interval
    [value - lower_uncertainty * coverage_factor,
     value + upper_uncertainty * coverage_factor]

  -> combined_provenance(other = nil)
    result = provenance
    if other != nil && Measurement.measurement?(other)
      other.provenance.each -> (source) result.push(source)
    result

  # General two-input first-order propagation:
  #   var(f) = fx^2 ux^2 + fy^2 uy^2 + 2 fx fy rho ux uy.
  -> binary_result(other, result_value, derivative_self, derivative_other, rho)
    Measurement.validate_correlation(rho)
    covariance = rho * uncertainty * other.uncertainty
    self_variance = (
      derivative_self * derivative_self * uncertainty * uncertainty)
    other_variance = (
      derivative_other * derivative_other * other.uncertainty * other.uncertainty)
    cross_variance = ~2.0 * derivative_self * derivative_other * covariance
    variance = self_variance + other_variance + cross_variance
    variance = Measurement.nonnegative_variance(
      variance,
      self_variance.abs + other_variance.abs + cross_variance.abs)

    random_covariance = (
      rho * random_uncertainty * other.random_uncertainty)
    random_self = (
      derivative_self * derivative_self * random_uncertainty * random_uncertainty)
    random_other = (
      derivative_other * derivative_other * other.random_uncertainty * other.random_uncertainty)
    random_cross = (
      ~2.0 * derivative_self * derivative_other * random_covariance)
    random_variance = random_self + random_other + random_cross
    random_variance = Measurement.nonnegative_variance(
      random_variance,
      random_self.abs + random_other.abs + random_cross.abs)

    systematic_covariance = (
      rho * systematic_uncertainty * other.systematic_uncertainty)
    systematic_self = (
      derivative_self * derivative_self * systematic_uncertainty * systematic_uncertainty)
    systematic_other = (
      derivative_other * derivative_other * other.systematic_uncertainty * other.systematic_uncertainty)
    systematic_cross = (
      ~2.0 * derivative_self * derivative_other * systematic_covariance)
    systematic_variance = systematic_self + systematic_other + systematic_cross
    systematic_variance = Measurement.nonnegative_variance(
      systematic_variance,
      systematic_self.abs + systematic_other.abs + systematic_cross.abs)

    result_uncertainty = Math.sqrt(variance)
    Measurement.new(
      result_value, result_uncertainty, result_uncertainty,
      result_uncertainty, ~1.0, nil, nil,
      combined_provenance(other), Math.sqrt(random_variance),
      Math.sqrt(systematic_variance), nil, ~0.0)

  -> unary_result(result_value, derivative)
    scale = derivative.abs
    result_uncertainty = scale * uncertainty
    Measurement.new(
      result_value, result_uncertainty, result_uncertainty,
      result_uncertainty, ~1.0, nil, nil, provenance,
      scale * random_uncertainty, scale * systematic_uncertainty,
      nil, ~0.0)

  -> shifted(scalar, sign)
    Measurement.new(
      value + sign * scalar, uncertainty,
      lower_uncertainty, upper_uncertainty,
      coverage_factor, confidence, degrees_of_freedom, provenance,
      random_uncertainty, systematic_uncertainty, nil, ~0.0)

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
      systematic_uncertainty * magnitude, nil, ~0.0)

  -> +(other)
    if Measurement.measurement?(other)
      return self.add_correlated(other, correlation_with(other))
    shifted(other, ~1.0)

  -> -(other)
    if Measurement.measurement?(other)
      return self.sub_correlated(other, correlation_with(other))
    shifted(other, ~-1.0)

  -> -@
    scaled(~-1.0)

  -> *(other)
    if Measurement.measurement?(other)
      return self.mul_correlated(other, correlation_with(other))
    scaled(other)

  -> /(other)
    if Measurement.measurement?(other)
      return self.div_correlated(other, correlation_with(other))
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
      suffix = " (k=" + coverage_factor.to_s + ")"
    if lower_uncertainty != upper_uncertainty
      return (value.to_s + " +" + upper_uncertainty.to_s +
              "/-" + lower_uncertainty.to_s + suffix)
    value.to_s + " ± " + uncertainty.to_s + suffix

  -> inspect
    to_s
