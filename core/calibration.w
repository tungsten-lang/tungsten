# Calibration — polynomial measurement model with a standard-uncertainty
# contribution and traceability metadata.
#
# The representation follows VIM/GUM concepts: a model, validity interval,
# standard uncertainty, certificate/reference identity, and stated conditions.
# Carrying these fields supports a traceability claim; it does not create one.
+ Calibration
  - data
    rw coefficients
    rw coefficient_uncertainties
    rw input_unit
    rw output_unit
    rw standard_uncertainty
    rw valid_min
    rw valid_max
    rw certificate
    rw reference
    rw method
    rw conditions
    rw traceability_chain

  -> new(@coefficients, @coefficient_uncertainties, @input_unit, @output_unit, @standard_uncertainty, @valid_min, @valid_max, @certificate)
    @reference = nil
    @method = nil
    @conditions = nil
    @traceability_chain = []

  -> .linear(slope, intercept = ~0.0, input_unit = nil, output_unit = nil, standard_uncertainty = ~0.0, certificate = nil)
    Calibration.new([intercept, slope], [~0.0, ~0.0], input_unit, output_unit, standard_uncertainty, nil, nil, certificate)

  -> polynomial(x)
    result = ~0.0
    i = coefficients.size() - 1
    while i >= 0
      result = result * x + coefficients[i]
      i = i - 1
    result

  -> derivative(x)
    result = ~0.0
    i = coefficients.size() - 1
    while i >= 1
      result = result * x + coefficients[i] * i
      i = i - 1
    result

  -> coefficient_variance(x)
    variance = ~0.0
    power = ~1.0
    i = 0
    while i < coefficient_uncertainties.size()
      term = power * coefficient_uncertainties[i]
      variance = variance + term * term
      power = power * x
      i = i + 1
    variance

  -> apply(measurement)
    x = measurement.value
    if valid_min != nil && x < valid_min
      raise "calibration input below validity range"
    if valid_max != nil && x > valid_max
      raise "calibration input above validity range"
    sensitivity = self.derivative(x)
    input_u = sensitivity * measurement.uncertainty
    variance = input_u * input_u + self.coefficient_variance(x) + standard_uncertainty * standard_uncertainty
    result_value = self.polynomial(x)
    result_uncertainty = Math.sqrt(variance)
    if certificate != nil
      result_provenance = measurement.provenance.push("calibration " + certificate.to_s())
      return Measurement.new(result_value, result_uncertainty, result_uncertainty,
                             result_uncertainty, ~1.0, nil, nil, result_provenance)
    Measurement.new(result_value, result_uncertainty)
