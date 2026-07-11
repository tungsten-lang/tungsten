# Measurement — a measured scalar and its standard uncertainty.
#
# `value ± uncertainty` is desugared by the compiled parser to
# `Measurement.new(value, uncertainty)`. Ordinary arithmetic assumes
# independent inputs; the *_correlated methods accept a Pearson correlation
# coefficient and apply first-order GUM propagation.
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

  -> new(@value, @uncertainty)
    @lower_uncertainty = Math.abs(uncertainty)
    @upper_uncertainty = Math.abs(uncertainty)
    @coverage_factor = ~1.0
    @confidence = nil
    @degrees_of_freedom = nil
    @provenance = []
    @random_uncertainty = ~0.0
    @systematic_uncertainty = ~0.0
    @correlation_peer = nil
    @correlation_coefficient = ~0.0

  -> new(@value, @uncertainty, @lower_uncertainty, @upper_uncertainty,
         @coverage_factor, @confidence, @degrees_of_freedom, @provenance)
    @random_uncertainty = ~0.0
    @systematic_uncertainty = ~0.0
    @correlation_peer = nil
    @correlation_coefficient = ~0.0

  -> new(@value, @uncertainty, @lower_uncertainty, @upper_uncertainty,
         @coverage_factor, @confidence, @degrees_of_freedom, @provenance,
         @random_uncertainty, @systematic_uncertainty,
         @correlation_peer, @correlation_coefficient)

  -> .asymmetric(value, lower, upper)
    standard = (Math.abs(lower) + Math.abs(upper)) / ~2.0
    Measurement.new(value, standard, Math.abs(lower), Math.abs(upper), ~1.0, nil, nil, [])

  -> .with_components(value, random, systematic)
    uncertainty = Math.sqrt(random * random + systematic * systematic)
    Measurement.new(value, uncertainty, uncertainty, uncertainty, ~1.0, nil,
                    nil, [], random, systematic, nil, ~0.0)

  -> components
    {:random => random_uncertainty, :systematic => systematic_uncertainty}

  -> correlate(other, coefficient)
    if coefficient < ~-1.0 || coefficient > ~1.0
      raise "correlation must be between -1 and 1"
    @correlation_peer = other
    @correlation_coefficient = coefficient
    other.correlate_back(self, coefficient)
    self

  -> correlate_back(other, coefficient)
    @correlation_peer = other
    @correlation_coefficient = coefficient
    self

  -> correlation_with(other)
    if correlation_peer == other
      correlation_coefficient
    else
      ~0.0

  -> expanded(k, confidence = nil)
    if confidence == nil
      confidence = @confidence
    Measurement.new(value, uncertainty, lower_uncertainty, upper_uncertainty,
                    k, confidence, degrees_of_freedom, provenance)

  -> interval
    [value - lower_uncertainty * coverage_factor,
     value + upper_uncertainty * coverage_factor]

  -> +(other)
    self.add_correlated(other, self.correlation_with(other))

  -> -(other)
    self.sub_correlated(other, self.correlation_with(other))

  -> *(other)
    self.mul_correlated(other, self.correlation_with(other))

  -> /(other)
    self.div_correlated(other, self.correlation_with(other))

  -> add_correlated(other, rho)
    variance = uncertainty * uncertainty + other.uncertainty * other.uncertainty + ~2.0 * rho * uncertainty * other.uncertainty
    Measurement.new(value + other.value, Math.sqrt(variance))

  -> sub_correlated(other, rho)
    variance = uncertainty * uncertainty + other.uncertainty * other.uncertainty - ~2.0 * rho * uncertainty * other.uncertainty
    Measurement.new(value - other.value, Math.sqrt(variance))

  -> mul_correlated(other, rho)
    dx = other.value
    dy = value
    covariance = rho * uncertainty * other.uncertainty
    variance = dx * dx * uncertainty * uncertainty + dy * dy * other.uncertainty * other.uncertainty + ~2.0 * dx * dy * covariance
    Measurement.new(value * other.value, Math.sqrt(variance))

  -> div_correlated(other, rho)
    dx = ~1.0 / other.value
    dy = (~0.0 - value) / (other.value * other.value)
    covariance = rho * uncertainty * other.uncertainty
    variance = dx * dx * uncertainty * uncertainty + dy * dy * other.uncertainty * other.uncertainty + ~2.0 * dx * dy * covariance
    Measurement.new(value / other.value, Math.sqrt(variance))

  -> calibrate(calibration)
    calibration.apply(self)

  -> to_s
    if lower_uncertainty != upper_uncertainty
      return value.to_s() + " +" + upper_uncertainty.to_s() + "/-" + lower_uncertainty.to_s()
    value.to_s() + " ± " + uncertainty.to_s()
