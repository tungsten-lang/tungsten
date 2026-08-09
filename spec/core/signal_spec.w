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

# Window samples distinguish the periodic analysis convention from the
# symmetric endpoint convention. Length one is explicitly the unit window.
signal_check("window.boxcar",
             array_close?(Signal.window(:boxcar, 4),
                          [~1.0, ~1.0, ~1.0, ~1.0]))
signal_check("window.hann.periodic",
             array_close?(Signal.window(:hann, 4),
                          [~0.0, ~0.5, ~1.0, ~0.5]))
signal_check("window.hann.symmetric",
             array_close?(Signal.window(:hann, 5, :symmetric),
                          [~0.0, ~0.5, ~1.0, ~0.5, ~0.0]))
signal_check("window.hann.symmetric_length_two_is_degenerate",
             array_close?(Signal.window(:hann, 2, :symmetric),
                          [~0.0, ~0.0]))
signal_check("window.length_one_is_unit",
             array_close?(Signal.window(:hann, 1, :symmetric), [~1.0]))
invalid_window_raised = false
begin
  Signal.window(:triangle, 4)
rescue error
  invalid_window_raised = true
invalid_window_length_raised = false
begin
  Signal.window(:hann, 0)
rescue error
  invalid_window_length_raised = true
invalid_window_convention_raised = false
begin
  Signal.window(:hann, 4, :centered)
rescue error
  invalid_window_convention_raised = true
signal_check("window.invalid_configuration_is_loud",
             invalid_window_raised && invalid_window_length_raised &&
             invalid_window_convention_raised)

# For an eight-sample impulse at fs=8, the one-sided density has undoubled DC
# and Nyquist endpoints. Its integral is the record mean square, 1/8.
periodogram_input = [
  ~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
periodogram = Signal.periodogram(periodogram_input, sample_rate: ~8.0)
signal_check("periodogram.impulse.density",
             array_close?(periodogram.values,
                          [~0.015625, ~0.03125, ~0.03125,
                           ~0.03125, ~0.015625]))
signal_check("periodogram.frequencies",
             array_close?(periodogram.frequencies,
                          [~0.0, ~1.0, ~2.0, ~3.0, ~4.0]))
signal_check("periodogram.integrated_power",
             close?(periodogram.integrated_power, ~0.125))
signal_check("periodogram.metadata",
             periodogram.estimator == :periodogram &&
             periodogram.scaling == :density &&
             periodogram.sides == :one_sided &&
             periodogram.boundary == :drop &&
             periodogram.sample_count == 8 &&
             periodogram.segment_length == 8 &&
             periodogram.segment_count == 1 &&
             periodogram.overlap == 0 && periodogram.nfft == 8 &&
             periodogram.zero_padding == 0 &&
             close?(periodogram.frequency_resolution, ~1.0) &&
             !periodogram.certified?)
signal_check("periodogram.does_not_mutate_input",
             array_close?(periodogram_input,
                          [~1.0, ~0.0, ~0.0, ~0.0,
                           ~0.0, ~0.0, ~0.0, ~0.0]))

# Returned arrays are snapshots: callers cannot invalidate bin metadata by
# mutating a getter result.
mutable_values = periodogram.values
mutable_frequencies = periodogram.frequencies
mutable_values[0] = ~99.0
mutable_frequencies[0] = ~99.0
signal_check("periodogram.result_arrays_are_defensive",
             close?(periodogram.values[0], ~0.015625) &&
             close?(periodogram.frequencies[0], ~0.0))
malformed_result_raised = false
begin
  SignalSpectralEstimate.new(
    [~0.0, ~1.0], [~0.0, ~-1.0],
    [:periodogram, ~2.0, 2, 2, 0, 2, 1,
     :boxcar, :periodic, :none, :density, 0,
     ~1.0, ~2.0, ~1.0])
rescue error
  malformed_result_raised = true
signal_check("periodogram.public_result_constructor_validates",
             malformed_result_raised)

# A sample rate different from the record length pins the physical-frequency
# divisor independently of FFT length. Spectrum scaling is sample-rate
# invariant while density changes by ENBW.
half_rate_density = Signal.periodogram(
  periodogram_input, sample_rate: ~4.0)
half_rate_spectrum = Signal.periodogram(
  periodogram_input, sample_rate: ~4.0, scaling: :spectrum)
signal_check("periodogram.sample_rate_density_normalization",
             array_close?(half_rate_density.values,
                          [~0.03125, ~0.0625, ~0.0625,
                           ~0.0625, ~0.03125]))
signal_check("periodogram.spectrum_is_sample_rate_invariant",
             array_close?(half_rate_spectrum.values, periodogram.values) &&
             close?(half_rate_density.equivalent_noise_bandwidth, ~0.5) &&
             close?(half_rate_density.integrated_power, ~0.125) &&
             close?(half_rate_spectrum.integrated_power, ~0.125))

# A periodic Hann window at N=8 has coherent gain 1/2, energy 3, and ENBW
# 1.5 Hz at fs=8. The bin-2 cosine makes density/spectrum normalization and
# leakage into neighboring bins analytic.
hann_cosine = [
  ~1.0, ~0.0, ~-1.0, ~0.0, ~1.0, ~0.0, ~-1.0, ~0.0]
hann_density = Signal.periodogram(
  hann_cosine, sample_rate: ~8.0, window: :hann)
hann_spectrum = Signal.periodogram(
  hann_cosine, sample_rate: ~8.0, window: :hann, scaling: :spectrum)
signal_check("periodogram.hann.density",
             array_close?(hann_density.values,
                          [~0.0, ~1.0 / ~12.0, ~1.0 / ~3.0,
                           ~1.0 / ~12.0, ~0.0]))
signal_check("periodogram.hann.spectrum",
             array_close?(hann_spectrum.values,
                          [~0.0, ~0.125, ~0.5, ~0.125, ~0.0]))
signal_check("periodogram.hann.window_metadata",
             close?(hann_density.coherent_gain, ~0.5) &&
             close?(hann_density.window_energy, ~3.0) &&
             close?(hann_density.equivalent_noise_bandwidth, ~1.5) &&
             close?(hann_density.integrated_power, ~0.5) &&
             close?(hann_spectrum.integrated_power, ~0.5))

# Explicit zero padding refines bin spacing without changing normalization.
padded = Signal.periodogram(periodogram_input,
                            sample_rate: ~8.0, nfft: 16)
signal_check("periodogram.zero_padding.metadata",
             padded.nfft == 16 && padded.zero_padding == 8 &&
             padded.bin_count == 9 &&
             close?(padded.frequency_resolution, ~0.5))
signal_check("periodogram.zero_padding.preserves_power",
             array_close?(padded.values,
                          [~0.015625, ~0.03125, ~0.03125, ~0.03125,
                           ~0.03125, ~0.03125, ~0.03125, ~0.03125,
                           ~0.015625]) &&
             close?(padded.integrated_power, ~0.125))
padded_spectrum = Signal.periodogram(
  periodogram_input, sample_rate: ~4.0, scaling: :spectrum, nfft: 16)
signal_check("periodogram.spectrum_zero_padding_preserves_power",
             array_close?(padded_spectrum.values, padded.values) &&
             close?(padded_spectrum.integrated_power, ~0.125))

# Default nfft is the next radix-2 length and is reported rather than hidden.
unpadded_length = Signal.periodogram(
  [~1.0, ~0.0, ~0.0, ~0.0, ~0.0], sample_rate: ~8.0)
signal_check("periodogram.default_next_power_of_two",
             unpadded_length.nfft == 8 && unpadded_length.zero_padding == 3)

singleton = Signal.periodogram([2], sample_rate: 4, window: :hann)
signal_check("periodogram.singleton_integer_input",
             singleton.nfft == 1 && singleton.bin_count == 1 &&
             array_close?(singleton.values, [~1.0]) &&
             close?(singleton.integrated_power, ~4.0) &&
             close?(singleton.coherent_gain, ~1.0))

# Welch averages powers from complete frames. These two nonoverlapping impulse
# frames have powers 1 and 9, so their average gives [5, 10, 5]/16 at fs=4.
welch_input = [~1.0, ~0.0, ~0.0, ~0.0,
               ~3.0, ~0.0, ~0.0, ~0.0]
welch = Signal.welch(
  welch_input, 4, sample_rate: ~4.0, overlap: 0,
  window: :boxcar, detrend: :none)
signal_check("welch.averages_frame_power",
             array_close?(welch.values, [~0.3125, ~0.625, ~0.3125]))
signal_check("welch.metadata",
             welch.estimator == :welch && welch.sample_count == 8 &&
             welch.segment_length == 4 && welch.overlap == 0 &&
             welch.segment_count == 2 && welch.dropped_samples == 0 &&
             close?(welch.integrated_power, ~1.25))

# The incremental Welch mean avoids overflowing an intermediate sum when each
# finite frame power and their final mean are still representable.
large_welch = Signal.welch(
  [~1.8e154, ~0.0, ~1.8e154, ~0.0], 2,
  sample_rate: ~1.0, overlap: 0, window: :boxcar, detrend: :none)
large_welch_values = large_welch.values
signal_check("welch.power_average_avoids_intermediate_overflow",
             !large_welch_values[0].nan? &&
             !large_welch_values[0].infinite? &&
             !large_welch_values[1].nan? &&
             !large_welch_values[1].infinite? &&
             !large_welch.integrated_power.infinite?)

# Mean removal is per complete frame, and an incomplete tail is dropped.
constant = []
i = 0
while i < 21
  constant = constant.push(~3.0)
  i += 1
detrended = Signal.welch(constant, 8, sample_rate: ~10.0, overlap: 4)
signal_check("welch.mean_detrend_is_per_frame",
             array_close?(detrended.values,
                          [~0.0, ~0.0, ~0.0, ~0.0, ~0.0]))
signal_check("welch.complete_frames_drop_tail",
             detrended.segment_count == 4 &&
             detrended.dropped_samples == 1 &&
             detrended.window == :hann &&
             detrended.window_convention == :periodic &&
             detrended.detrend == :mean)

level_frames = [~1.0, ~1.0, ~1.0, ~1.0,
                ~3.0, ~3.0, ~3.0, ~3.0]
per_frame_detrended = Signal.welch(
  level_frames, 4, sample_rate: ~4.0, overlap: 0, window: :boxcar)
signal_check("welch.detrends_each_frame_not_the_record",
             array_close?(per_frame_detrended.values,
                          [~0.0, ~0.0, ~0.0]))

# A one-frame Welch estimate is exactly the corresponding periodogram.
one_frame_welch = Signal.welch(
  periodogram_input, 8, sample_rate: ~8.0, overlap: 0,
  window: :boxcar, detrend: :none)
signal_check("welch.one_frame_matches_periodogram",
             array_close?(one_frame_welch.values, periodogram.values) &&
             array_close?(one_frame_welch.frequencies,
                          periodogram.frequencies))

empty_periodogram_raised = false
begin
  Signal.periodogram([])
rescue error
  empty_periodogram_raised = true
periodogram_rate_raised = false
begin
  Signal.periodogram([~1.0], sample_rate: ~0.0)
rescue error
  periodogram_rate_raised = true
periodogram_detrend_raised = false
begin
  Signal.periodogram([~1.0, ~0.0], detrend: :linear)
rescue error
  periodogram_detrend_raised = true
periodogram_scaling_raised = false
begin
  Signal.periodogram([~1.0, ~0.0], scaling: :amplitude)
rescue error
  periodogram_scaling_raised = true
periodogram_nfft_raised = false
begin
  Signal.periodogram([~1.0, ~0.0], nfft: 3)
rescue error
  periodogram_nfft_raised = true
periodogram_zero_window_raised = false
begin
  Signal.periodogram(
    [~1.0, ~0.0], window: :hann, convention: :symmetric)
rescue error
  periodogram_zero_window_raised = true
signal_check("periodogram.invalid_configuration_is_loud",
             empty_periodogram_raised && periodogram_rate_raised &&
             periodogram_detrend_raised && periodogram_scaling_raised &&
             periodogram_nfft_raised && periodogram_zero_window_raised)

welch_short_segment_raised = false
begin
  Signal.welch([~1.0], 1)
rescue error
  welch_short_segment_raised = true
welch_long_segment_raised = false
begin
  Signal.welch([~1.0, ~2.0], 3)
rescue error
  welch_long_segment_raised = true
welch_overlap_raised = false
begin
  Signal.welch([~1.0, ~2.0], 2, overlap: 2)
rescue error
  welch_overlap_raised = true
welch_nfft_raised = false
begin
  Signal.welch([~1.0, ~2.0], 2, nfft: 1)
rescue error
  welch_nfft_raised = true
signal_check("welch.invalid_configuration_is_loud",
             welch_short_segment_raised && welch_long_segment_raised &&
             welch_overlap_raised && welch_nfft_raised)

not_a_number = Math.sqrt(~-1.0)
infinity = Math.exp(~10000.0)
nonfinite_sample_raised = false
begin
  Signal.periodogram([not_a_number])
rescue error
  nonfinite_sample_raised = true
nonfinite_rate_raised = false
begin
  Signal.periodogram([~1.0], sample_rate: infinity)
rescue error
  nonfinite_rate_raised = true
underflowed_bandwidth_raised = false
begin
  Signal.periodogram(
    [~1.0, ~0.0], sample_rate: ~5.0e-324, scaling: :spectrum)
rescue error
  underflowed_bandwidth_raised = true
underflowed_resolution_raised = false
begin
  Signal.periodogram(
    [~1.0], sample_rate: ~5.0e-324, scaling: :spectrum, nfft: 2)
rescue error
  underflowed_resolution_raised = true
signal_check("spectral.nonfinite_values_are_loud",
             nonfinite_sample_raised && nonfinite_rate_raised &&
             underflowed_bandwidth_raised &&
             underflowed_resolution_raised)

<< "signal_spec: all checks passed"
