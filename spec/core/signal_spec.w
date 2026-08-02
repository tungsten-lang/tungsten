# Finite signal convolution/correlation and one-sided spectral conventions.
# Run in both engines:
#   bin/tungsten run spec/core/signal_spec.w
#   bin/tungsten compile spec/core/signal_spec.w --out /tmp/signal-spec

use signal

+ ConjugateProbe
  -> new(@value)

  -> value
    @value

  -> conjugate
    ConjugateProbe.new(0 - @value)

-> signal_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> array_close?(got, want, tolerance = ~1.0e-10)
  return false if got.size() != want.size()
  i = 0
  while i < got.size()
    return false if !close?(got[i], want[i], tolerance)
    i += 1
  true

# Exact analytic convolution and the centering/valid-boundary contract.
samples = [1, 2, 3]
kernel = [4, 5]
signal_check("convolve.full",
             array_close?(Signal.convolve(samples, kernel),
                          [4, 13, 22, 15]))
signal_check("convolve.same.even_kernel_is_early_centered",
             array_close?(Signal.convolve(samples, kernel, :same),
                          [4, 13, 22]))
signal_check("convolve.same.follows_first_sequence_length",
             array_close?(Signal.convolve([1, 2], [1, 1, 1, 1], :same),
                          [3, 3]))
signal_check("convolve.valid",
             array_close?(Signal.convolve(samples, kernel, :valid),
                          [13, 22]))
signal_check("convolve.does_not_mutate_inputs",
             array_close?(samples, [1, 2, 3]) &&
             array_close?(kernel, [4, 5]))
signal_check("convolve.empty",
             Signal.convolve([], kernel).size() == 0 &&
             Signal.convolve(samples, []).size() == 0)

invalid_mode_raised = false
begin
  Signal.convolve(samples, kernel, :circular)
rescue error
  invalid_mode_raised = true
signal_check("convolve.invalid_mode_is_loud", invalid_mode_raised)

long_kernel_raised = false
begin
  Signal.convolve([1], [1, 2], :valid)
rescue error
  long_kernel_raised = true
signal_check("convolve.valid_requires_kernel_fit", long_kernel_raised)

# Correlation uses increasing lags and conjugates the reference sequence.
signal_check("correlate.full",
             array_close?(Signal.correlate(samples, kernel),
                          [5, 14, 23, 12]))
signal_check("correlate.full.lags",
             array_close?(Signal.correlation_lags(3, 2),
                          [-1, 0, 1, 2]))
signal_check("correlate.same.lags",
             array_close?(Signal.correlation_lags(3, 2, :same),
                          [-1, 0, 1]))
signal_check("correlate.valid.lags",
             array_close?(Signal.correlation_lags(3, 2, :valid),
                          [0, 1]))

conjugated = Signal.conjugate(ConjugateProbe.new(3))
signal_check("correlate.conjugates_reference",
             conjugated.value == -3)

# An 8-sample cosine at bin 2 has one-sided peak amplitude 1. Frequencies are
# k*sample_rate/N, and forward FFT coefficients remain unnormalized.
cosine = [~1.0, ~0.0, ~-1.0, ~0.0, ~1.0, ~0.0, ~-1.0, ~0.0]
spectrum = Signal.spectrum(cosine, ~8.0)
signal_check("spectrum.metadata",
             spectrum.sample_count == 8 && spectrum.bin_count == 5 &&
             close?(spectrum.sample_rate, ~8.0) &&
             close?(spectrum.frequency_resolution, ~1.0))
signal_check("spectrum.frequencies",
             array_close?(spectrum.frequencies,
                          [~0.0, ~1.0, ~2.0, ~3.0, ~4.0]))
signal_check("spectrum.raw_coefficient",
             close?(spectrum.real[2], ~4.0) &&
             close?(spectrum.imaginary[2], ~0.0))
signal_check("spectrum.one_sided_amplitude",
             close?(spectrum.amplitudes[2], ~1.0))
signal_check("spectrum.phase",
             close?(spectrum.phases[2], ~0.0))
signal_check("spectrum.does_not_mutate_input",
             array_close?(cosine,
                          [~1.0, ~0.0, ~-1.0, ~0.0,
                           ~1.0, ~0.0, ~-1.0, ~0.0]))

# DC and Nyquist are not doubled by one-sided amplitude normalization.
impulse = Signal.spectrum(
  [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], ~8.0)
signal_check("spectrum.impulse.raw_magnitudes",
             array_close?(impulse.magnitudes,
                          [~1.0, ~1.0, ~1.0, ~1.0, ~1.0]))
signal_check("spectrum.amplitude.endpoint_normalization",
             array_close?(impulse.amplitudes,
                          [~0.125, ~0.25, ~0.25, ~0.25, ~0.125]))

empty_spectrum_raised = false
begin
  Signal.spectrum([])
rescue error
  empty_spectrum_raised = true
signal_check("spectrum.empty_is_loud", empty_spectrum_raised)

non_power_of_two_raised = false
begin
  Signal.spectrum([~1.0, ~2.0, ~3.0])
rescue error
  non_power_of_two_raised = true
signal_check("spectrum.radix2_limit_is_loud", non_power_of_two_raised)

invalid_rate_raised = false
begin
  Signal.spectrum([~1.0], ~0.0)
rescue error
  invalid_rate_raised = true
signal_check("spectrum.sample_rate_must_be_positive", invalid_rate_raised)

<< "signal_spec: all checks passed"
