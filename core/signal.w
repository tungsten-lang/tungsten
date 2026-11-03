# Signal — finite discrete signals, linear convolution/correlation, and
# one-sided spectral analysis for uniformly sampled real data.
#
# Sequence convention: element `x[n]` is sample n, with n starting at zero.
# Convolution uses zero extension outside each finite sequence:
#
#   (x * h)[k] = sum_n x[n] h[k - n]
#
# Correlation conjugates the second (reference) sequence and reports increasing
# lag. In full mode, result index k has lag k - (reference.size - 1):
#
#   r_xy[lag] = sum_n x[n + lag] conjugate(y[n])
#
# `:full`, `:same`, and `:valid` modes are supported. `:same` has the length of
# the first sequence and uses start index floor((h.size - 1) / 2) in the full
# result (the earlier centering for an even kernel). `:valid` treats the second
# sequence as the kernel/reference and requires it to be no longer than the
# first. Empty input produces an empty result in every mode.
#
# `Signal.spectrum` is deliberately raw: it accepts a nonempty, power-of-two
# real sequence and delegates to the existing radix-2 FFT. The forward
# transform is unnormalized and uses exp(-i 2*pi*k*n/N); the returned
# SignalSpectrum keeps bins 0 through Nyquist.
#
# `Signal.periodogram` and `Signal.welch` are the normalized estimation layer.
# They accept finite real samples, apply an explicit boxcar or Hann window,
# optionally remove each frame mean, and return a one-sided
# SignalSpectralEstimate. FFT lengths are powers of two; an omitted `nfft`
# selects the smallest power of two at least as long as the frame. Welch uses
# complete frames only and reports the unconsumed trailing sample count.

use core/fft

# One-sided periodogram or Welch power estimate, with the frame, window, and
# normalization metadata that produced it. Signal.periodogram and Signal.welch
# build these; the public constructor validates the same invariants.
+ SignalSpectralEstimate
  ro :estimator, :sample_rate, :sample_count, :segment_length, :overlap
  ro :nfft, :segment_count, :window, :window_convention, :detrend, :scaling
  ro :dropped_samples, :coherent_gain, :window_energy
  ro :equivalent_noise_bandwidth

  # Metadata layout is private to Signal's estimators:
  # [estimator, sample_rate, sample_count, segment_length, overlap, nfft,
  #  segment_count, window, window_convention, detrend, scaling,
  #  dropped_samples, coherent_gain, window_energy, enbw]
  -> new(frequencies, values, metadata)
    Signal.validate_spectral_estimate(frequencies, values, metadata)

    @frequencies = SignalSpectralEstimate.float_copy(frequencies)
    @values = SignalSpectralEstimate.float_copy(values)
    @estimator = metadata[0]
    @sample_rate = metadata[1] + ~0.0
    @sample_count = metadata[2]
    @segment_length = metadata[3]
    @overlap = metadata[4]
    @nfft = metadata[5]
    @segment_count = metadata[6]
    @window = metadata[7]
    @window_convention = metadata[8]
    @detrend = metadata[9]
    @scaling = metadata[10]
    @dropped_samples = metadata[11]
    @coherent_gain = metadata[12] + ~0.0
    @window_energy = metadata[13] + ~0.0
    @equivalent_noise_bandwidth = metadata[14] + ~0.0

  -> .copy(values)
    out = []
    i = 0
    while i < values.size
      out = out.push(values[i])
      i += 1
    out

  -> .float_copy(values)
    out = []
    i = 0
    while i < values.size
      out = out.push(values[i] + ~0.0)
      i += 1
    out

  -> frequencies
    SignalSpectralEstimate.copy(@frequencies)

  # Power values. Their units are selected by `scaling`: power/unit-frequency
  # for `:density`, and power for `:spectrum`.
  -> values
    SignalSpectralEstimate.copy(@values)

  -> zero_padding
    @nfft - @segment_length

  -> sides
    :one_sided

  -> boundary
    :drop

  -> bin_count
    @values.size

  -> frequency_resolution
    @sample_rate / (@nfft + ~0.0)

  # Window-energy-normalized mean-square power represented by the retained
  # one-sided bins. `:spectrum` values differ from density by ENBW, so both
  # scaling choices integrate to the same result here.
  -> integrated_power
    scale = frequency_resolution
    if @scaling == :spectrum
      scale /= @equivalent_noise_bandwidth
    power = ~0.0
    i = 0
    while i < @values.size
      power += @values[i] * scale
      if power.nan? || power.infinite?
        raise "Signal integrated spectral power is non-finite"
      i += 1
    power

  -> certified?
    false

  -> to_a
    [frequencies, values]

# Raw one-sided view of the unnormalized forward FFT of a real record: bins 0
# through Nyquist, with their frequencies in sample_rate units.
+ SignalSpectrum
  ro :frequencies, :real, :imaginary, :sample_rate, :sample_count

  -> new(@frequencies, @real, @imaginary, @sample_rate, @sample_count)

  -> bin_count
    @real.size

  -> frequency_resolution
    @sample_rate / (@sample_count + ~0.0)

  # Raw magnitudes |X[k]| of the unnormalized forward FFT.
  -> magnitudes
    out = []
    i = 0
    while i < @real.size
      value = Math.sqrt(
        @real[i] * @real[i] + @imaginary[i] * @imaginary[i])
      out = out.push(value)
      i += 1
    out

  # Peak amplitudes for a one-sided real spectrum. Interior positive-frequency
  # bins are doubled; DC and an even-length Nyquist bin are not.
  -> amplitudes
    raw = magnitudes
    out = []
    i = 0
    while i < raw.size
      scale = ~1.0 / (@sample_count + ~0.0)
      interior = i > 0
      interior = false if @sample_count % 2 == 0 && i == @sample_count / 2
      scale *= ~2.0 if interior
      out = out.push(raw[i] * scale)
      i += 1
    out

  # Bin phase in radians, in the Math.atan2 principal range.
  -> phases
    out = []
    i = 0
    while i < @real.size
      out = out.push(Math.atan2(@imaginary[i], @real[i]))
      i += 1
    out

  -> to_a
    [@frequencies, @real, @imaginary]


# Signal — finite convolution/correlation, analysis windows, raw one-sided
# spectra, and normalized periodogram/Welch spectral estimation.
+ Signal
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .real_scalar?(value)
    name = value.class_name
    return true if name == "Integer" || name == "Int" || name == "BigInt"
    return true if name == "Rational" || name == "Decimal"
    name.starts_with?("Float") || name.starts_with?("Decimal")

  -> .numerically_equal?(left, right, tolerance = ~1.0e-12)
    difference = left - right
    difference = ~0.0 - difference if difference < ~0.0
    left_scale = left
    left_scale = ~0.0 - left_scale if left_scale < ~0.0
    right_scale = right
    right_scale = ~0.0 - right_scale if right_scale < ~0.0
    scale = left_scale
    scale = right_scale if right_scale > scale
    return difference == ~0.0 if scale == ~0.0
    difference <= tolerance * scale

  -> .coerce_sample_rate(sample_rate)
    if !Signal.real_scalar?(sample_rate)
      raise "Signal spectral sample_rate must be a finite real number"
    rate = sample_rate + ~0.0
    if rate.nan? || rate.infinite? || rate <= ~0.0
      raise "Signal spectral sample_rate must be finite and positive"
    rate

  -> .coerce_samples(samples)
    if samples.size == 0
      raise "Signal spectral samples must not be empty"
    out = []
    i = 0
    while i < samples.size
      value = samples[i]
      if !Signal.real_scalar?(value)
        raise "Signal spectral samples must contain only finite real numbers"
      value = value + ~0.0
      if value.nan? || value.infinite?
        raise "Signal spectral samples must contain only finite real numbers"
      out = out.push(value)
      i += 1
    out

  -> .validate_window(kind, convention)
    if kind != :boxcar && kind != :hann
      raise "Signal window must be :boxcar or :hann"
    if convention != :periodic && convention != :symmetric
      raise "Signal window convention must be :periodic or :symmetric"
    kind

  # Return a newly allocated real window. The periodic form is intended for
  # spectral analysis; the symmetric form includes both endpoints and is
  # useful for FIR design. Length one is defined as the unit window.
  -> .window(kind, length, convention = :periodic)
    if !Signal.integer?(length) || length < 1
      raise "Signal window length must be a positive integer"
    Signal.validate_window(kind, convention)

    return [~1.0] if length == 1
    out = []
    i = 0
    while i < length
      value = ~1.0
      if kind == :hann
        denominator = length
        denominator = length - 1 if convention == :symmetric
        angle = ~6.283185307179586 * i / (denominator + ~0.0)
        value = ~0.5 - ~0.5 * Math.cos(angle)
      out = out.push(value)
      i += 1
    out

  -> .validate_detrend(detrend)
    if detrend != :none && detrend != :mean
      raise "Signal detrend must be :none or :mean"
    detrend

  -> .validate_scaling(scaling)
    if scaling != :density && scaling != :spectrum
      raise "Signal spectral scaling must be :density or :spectrum"
    scaling

  -> .next_power_of_two(length)
    size = 1
    while size < length
      size *= 2
    size

  -> .resolve_nfft(nfft, frame_length)
    return Signal.next_power_of_two(frame_length) if nfft == nil
    if !Signal.integer?(nfft) || nfft < frame_length || !FFT.is_pow2(nfft)
      raise "Signal nfft must be a power-of-two integer no smaller than the frame length"
    nfft

  # [coherent gain, energy, equivalent noise bandwidth]
  -> .window_summary(weights, sample_rate)
    total = ~0.0
    energy = ~0.0
    i = 0
    while i < weights.size
      total += weights[i]
      energy += weights[i] * weights[i]
      i += 1
    if total.nan? || total.infinite? || energy.nan? || energy.infinite?
      raise "Signal window normalization is non-finite"
    if total == ~0.0 || energy <= ~0.0
      raise "Signal window must have nonzero coherent gain and energy"
    coherent_gain = total / (weights.size + ~0.0)
    enbw = energy / (total * total) * sample_rate
    if enbw.nan? || enbw.infinite? || enbw <= ~0.0
      raise "Signal window equivalent noise bandwidth must be finite and positive"
    [coherent_gain, energy, enbw, total]

  # Enforce the invariants of the publicly autoloaded result type as well as
  # the estimates constructed by Signal itself.
  -> .validate_spectral_estimate(frequencies, values, metadata)
    if metadata.size != 15
      raise "SignalSpectralEstimate metadata is invalid"
    if frequencies.size != values.size
      raise "SignalSpectralEstimate frequencies and values must have equal length"

    estimator = metadata[0]
    if estimator != :periodogram && estimator != :welch
      raise "SignalSpectralEstimate estimator must be :periodogram or :welch"
    rate = Signal.coerce_sample_rate(metadata[1])
    sample_count = metadata[2]
    segment_length = metadata[3]
    overlap = metadata[4]
    nfft = metadata[5]
    segment_count = metadata[6]
    dropped = metadata[11]
    if !Signal.integer?(sample_count) || sample_count < 1
      raise "SignalSpectralEstimate sample_count must be a positive integer"
    if !Signal.integer?(segment_length) || segment_length < 1 || (
        segment_length > sample_count)
      raise "SignalSpectralEstimate segment_length is invalid"
    if !Signal.integer?(overlap) || overlap < 0 || overlap >= segment_length
      raise "SignalSpectralEstimate overlap is invalid"
    if !Signal.integer?(nfft) || nfft < segment_length || !FFT.is_pow2(nfft)
      raise "SignalSpectralEstimate nfft is invalid"
    if !Signal.integer?(segment_count) || segment_count < 1
      raise "SignalSpectralEstimate segment_count must be positive"
    if !Signal.integer?(dropped) || dropped < 0
      raise "SignalSpectralEstimate dropped_samples is invalid"
    if frequencies.size != nfft / 2 + 1
      raise "SignalSpectralEstimate bin count does not match nfft"

    Signal.validate_window(metadata[7], metadata[8])
    Signal.validate_detrend(metadata[9])
    Signal.validate_scaling(metadata[10])
    if estimator == :periodogram
      if segment_length != sample_count || overlap != 0 || (
          segment_count != 1) || dropped != 0
        raise "SignalSpectralEstimate periodogram frame metadata is inconsistent"
    else
      if segment_length < 2
        raise "SignalSpectralEstimate Welch segment_length must be at least 2"
      step = segment_length - overlap
      expected_count = 1 + (sample_count - segment_length) / step
      expected_dropped = sample_count - (
        (expected_count - 1) * step + segment_length)
      if segment_count != expected_count || dropped != expected_dropped
        raise "SignalSpectralEstimate Welch frame metadata is inconsistent"

    weights = Signal.window(metadata[7], segment_length, metadata[8])
    summary = Signal.window_summary(weights, rate)
    i = 0
    while i < 3
      raw = metadata[12 + i]
      if !Signal.real_scalar?(raw)
        raise "SignalSpectralEstimate window metadata must be finite and positive"
      numeric = raw + ~0.0
      if numeric.nan? || numeric.infinite? || numeric <= ~0.0 || (
          !Signal.numerically_equal?(numeric, summary[i]))
        raise "SignalSpectralEstimate window metadata is inconsistent"
      i += 1

    step = rate / (nfft + ~0.0)
    if step.nan? || step.infinite? || step <= ~0.0
      raise "SignalSpectralEstimate frequency resolution must be finite and positive"
    i = 0
    while i < frequencies.size
      frequency = frequencies[i]
      value = values[i]
      if !Signal.real_scalar?(frequency) || !Signal.real_scalar?(value)
        raise "SignalSpectralEstimate bins must contain finite real numbers"
      frequency = frequency + ~0.0
      value = value + ~0.0
      if frequency.nan? || frequency.infinite? || frequency < ~0.0 || (
          !Signal.numerically_equal?(frequency, i * step))
        raise "SignalSpectralEstimate frequencies are inconsistent"
      if value.nan? || value.infinite? || value < ~0.0
        raise "SignalSpectralEstimate values must be finite and nonnegative"
      i += 1
    true

  -> .windowed_frame(samples, start, length, weights, detrend, nfft)
    mean = ~0.0
    if detrend == :mean
      i = 0
      while i < length
        mean += (samples[start + i] - mean) / (i + 1 + ~0.0)
        if mean.nan? || mean.infinite?
          raise "Signal frame mean is non-finite"
        i += 1

    frame = []
    i = 0
    while i < length
      value = (samples[start + i] - mean) * weights[i]
      if value.nan? || value.infinite?
        raise "Signal windowed frame is non-finite"
      frame = frame.push(value)
      i += 1
    while i < nfft
      frame = frame.push(~0.0)
      i += 1
    frame

  # One-sided power for one already validated frame. The FFT is unnormalized;
  # normalization therefore uses window energy (density) or coherent gain
  # (spectrum). DC and the even-length Nyquist bin are not doubled.
  -> .frame_power(samples, start, length, weights, detrend, nfft,
                  sample_rate, scaling, window_energy, window_total)
    frame = Signal.windowed_frame(
      samples, start, length, weights, detrend, nfft)
    transformed = FFT.rfft(frame)
    normalization = (~1.0 / window_energy) / sample_rate
    if scaling == :spectrum
      normalization = (~1.0 / window_total) / window_total
    if normalization.nan? || normalization.infinite? || normalization <= ~0.0
      raise "Signal spectral normalization is non-finite"

    values = []
    i = 0
    while i < nfft / 2 + 1
      factor = normalization
      interior = i > 0
      interior = false if nfft % 2 == 0 && i == nfft / 2
      factor *= ~2.0 if interior
      root_factor = Math.sqrt(factor)
      re = transformed[0][i] * root_factor
      im = transformed[1][i] * root_factor
      power = re * re + im * im
      if power.nan? || power.infinite?
        raise "Signal spectral power is non-finite"
      values = values.push(power)
      i += 1
    values

  -> .spectral_frequencies(sample_rate, nfft)
    frequencies = []
    step = sample_rate / (nfft + ~0.0)
    i = 0
    while i < nfft / 2 + 1
      frequencies = frequencies.push(i * step)
      i += 1
    frequencies

  # Modified periodogram of one finite, uniformly sampled real record.
  # `:density` uses power per unit frequency; `:spectrum` uses coherent-gain
  # power. Omitted nfft selects the next power of two and zero-pads explicitly
  # in the returned metadata.
  -> .periodogram(samples,
                  sample_rate: ~1.0,
                  window: :boxcar,
                  convention: :periodic,
                  detrend: :none,
                  scaling: :density,
                  nfft: nil)
    rate = Signal.coerce_sample_rate(sample_rate)
    data = Signal.coerce_samples(samples)
    Signal.validate_window(window, convention)
    Signal.validate_detrend(detrend)
    Signal.validate_scaling(scaling)
    fft_length = Signal.resolve_nfft(nfft, data.size)
    weights = Signal.window(window, data.size, convention)
    summary = Signal.window_summary(weights, rate)
    values = Signal.frame_power(
      data, 0, data.size, weights, detrend, fft_length, rate, scaling,
      summary[1], summary[3])
    frequencies = Signal.spectral_frequencies(rate, fft_length)
    metadata = [
      :periodogram, rate, data.size, data.size, 0, fft_length, 1,
      window, convention, detrend, scaling, 0,
      summary[0], summary[1], summary[2]
    ]
    SignalSpectralEstimate.new(frequencies, values, metadata)

  # Welch estimate: arithmetic mean of complete-frame periodograms. Detrending
  # is performed independently in every frame before windowing. The final
  # incomplete frame is not padded; its trailing sample count is reported.
  -> .welch(samples, segment_length,
            sample_rate: ~1.0,
            overlap: nil,
            window: :hann,
            convention: :periodic,
            detrend: :mean,
            scaling: :density,
            nfft: nil)
    rate = Signal.coerce_sample_rate(sample_rate)
    data = Signal.coerce_samples(samples)
    if !Signal.integer?(segment_length) || segment_length < 2
      raise "Signal Welch segment_length must be an integer at least 2"
    if segment_length > data.size
      raise "Signal Welch segment_length must not exceed the sample count"
    overlap = segment_length / 2 if overlap == nil
    if !Signal.integer?(overlap) || overlap < 0 || overlap >= segment_length
      raise "Signal Welch overlap must be an integer from 0 through segment_length - 1"
    Signal.validate_window(window, convention)
    Signal.validate_detrend(detrend)
    Signal.validate_scaling(scaling)

    fft_length = Signal.resolve_nfft(nfft, segment_length)
    weights = Signal.window(window, segment_length, convention)
    summary = Signal.window_summary(weights, rate)
    step = segment_length - overlap
    accumulated = []
    segment_count = 0
    start = 0
    last_start = 0
    while start + segment_length <= data.size
      values = Signal.frame_power(
        data, start, segment_length, weights, detrend, fft_length, rate,
        scaling, summary[1], summary[3])
      if segment_count == 0
        accumulated = values
      else
        count = segment_count + 1 + ~0.0
        i = 0
        while i < accumulated.size
          accumulated[i] += (values[i] - accumulated[i]) / count
          if accumulated[i].nan? || accumulated[i].infinite?
            raise "Signal Welch power average is non-finite"
          i += 1
      last_start = start
      segment_count += 1
      start += step

    dropped = data.size - (last_start + segment_length)
    frequencies = Signal.spectral_frequencies(rate, fft_length)
    metadata = [
      :welch, rate, data.size, segment_length, overlap, fft_length,
      segment_count, window, convention, detrend, scaling, dropped,
      summary[0], summary[1], summary[2]
    ]
    SignalSpectralEstimate.new(frequencies, accumulated, metadata)

  -> .validate_mode(mode)
    if mode != :full && mode != :same && mode != :valid
      raise "Signal mode must be :full, :same, or :valid"
    mode

  -> .selection(signal_size, kernel_size, mode)
    Signal.validate_mode(mode)
    return [0, 0] if signal_size == 0 || kernel_size == 0
    return [0, signal_size + kernel_size - 1] if mode == :full
    return [(kernel_size - 1) / 2, signal_size] if mode == :same
    if kernel_size > signal_size
      raise "Signal :valid mode requires the second sequence to be no longer than the first"
    [kernel_size - 1, signal_size - kernel_size + 1]

  -> .select(full, signal_size, kernel_size, mode)
    selection = Signal.selection(signal_size, kernel_size, mode)
    start = selection[0]
    count = selection[1]
    out = []
    i = 0
    while i < count
      out = out.push(full[start + i])
      i += 1
    out

  # Direct O(NM) linear convolution. Input sequences are not mutated. Element
  # multiplication is ordered as signal[n] * kernel[k-n], which is observable
  # for noncommutative element types.
  -> .convolve(signal, kernel, mode = :full)
    Signal.validate_mode(mode)
    signal_size = signal.size
    kernel_size = kernel.size
    return [] if signal_size == 0 || kernel_size == 0

    full = []
    k = 0
    while k < signal_size + kernel_size - 1
      first = k - (kernel_size - 1)
      first = 0 if first < 0
      last = k
      last = signal_size - 1 if last >= signal_size

      n = first
      sum = signal[n] * kernel[k - n]
      n += 1
      while n <= last
        sum += signal[n] * kernel[k - n]
        n += 1
      full = full.push(sum)
      k += 1
    Signal.select(full, signal_size, kernel_size, mode)

  -> .conjugate(value)
    return value.conjugate if value.respond_to?("conjugate")
    value

  # Cross-correlation of `signal` with `reference`. Real scalars are unchanged;
  # values exposing `conjugate` (including Complex) use it on the reference.
  -> .correlate(signal, reference, mode = :full)
    reversed = []
    i = reference.size - 1
    while i >= 0
      reversed = reversed.push(Signal.conjugate(reference[i]))
      i -= 1
    Signal.convolve(signal, reversed, mode)

  # Lag labels corresponding exactly to Signal.correlate's result order.
  -> .correlation_lags(signal_size, reference_size, mode = :full)
    if !Signal.integer?(signal_size) || !Signal.integer?(reference_size)
      raise "Signal correlation lengths must be nonnegative integers"
    if signal_size < 0 || reference_size < 0
      raise "Signal correlation lengths must be nonnegative integers"
    selection = Signal.selection(signal_size, reference_size, mode)
    start = selection[0] - (reference_size - 1)
    out = []
    i = 0
    while i < selection[1]
      out = out.push(start + i)
      i += 1
    out

  # One-sided spectrum for uniformly sampled real data. Frequencies use the
  # same units as sample_rate (Hz when sample_rate is samples/second).
  -> .spectrum(samples, sample_rate = ~1.0)
    count = samples.size
    raise "Signal.spectrum samples must not be empty" if count == 0
    raise "Signal.spectrum sample_rate must be positive" if sample_rate <= ~0.0
    if !FFT.is_pow2(count)
      raise "Signal.spectrum sample count must be a power of 2"

    transformed = FFT.rfft(samples)
    bin_count = count / 2 + 1
    frequencies = []
    real = []
    imaginary = []
    step = sample_rate / (count + ~0.0)
    i = 0
    while i < bin_count
      frequencies = frequencies.push(i * step)
      real = real.push(transformed[0][i])
      imaginary = imaginary.push(transformed[1][i])
      i += 1
    SignalSpectrum.new(frequencies, real, imaginary, sample_rate, count)
