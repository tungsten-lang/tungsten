use core/tensor

measurement = 10.0 ± 0.2
<< measurement
<< Measurement.asymmetric(~10.0, ~0.1, ~0.3).expanded(~2.0)
component_measurement = Measurement.with_components(~10.0, ~0.3, ~0.4)
peer_measurement = Measurement.new(~2.0, ~0.2)
component_measurement.correlate(peer_measurement, ~1.0)
<< component_measurement + peer_measurement
<< component_measurement.components

calibration = Calibration.linear(~2.0, ~1.0, nil, nil, ~0.1, "CAL-42")
<< calibration.apply(Measurement.new(~3.0, ~0.2))

location = (10 m).point(:map) + (2 m).delta(:map)
<< location
<< location.point?

velocity = Tensor<f64, m/s>.zeros([2, 3])
<< velocity.dtype
<< velocity.unit
<< velocity.shape
<< (velocity + Tensor<f64, m/s>.zeros([2, 3])).unit

<< (1 kg).equivalent("J", :mass_energy)
<< 1 PB + 1 J
