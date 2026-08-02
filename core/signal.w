# Signal — finite discrete signals, linear convolution/correlation, and
# one-sided spectra for uniformly sampled real data.
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
# `Signal.spectrum` is deliberately narrower: it accepts a nonempty,
# power-of-two real sequence and delegates to the existing radix-2 FFT. The
# forward transform is unnormalized and uses exp(-i 2*pi*k*n/N); the returned
# SignalSpectrum keeps bins 0 through Nyquist. No window or detrending is
# applied.

use core/fft

+ SignalSpectrum
  -> new(@frequencies, @real, @imaginary, @sample_rate, @sample_count)

  -> frequencies
    @frequencies

  -> real
    @real

  -> imaginary
    @imaginary

  -> sample_rate
    @sample_rate

  -> sample_count
    @sample_count

  -> bin_count
    @real.size()

  -> frequency_resolution
    @sample_rate / (@sample_count + ~0.0)

  # Raw magnitudes |X[k]| of the unnormalized forward FFT.
  -> magnitudes
    out = []
    i = 0
    while i < @real.size()
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
    while i < raw.size()
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
    while i < @real.size()
      out = out.push(Math.atan2(@imaginary[i], @real[i]))
      i += 1
    out

  -> to_a
    [@frequencies, @real, @imaginary]


+ Signal
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

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
    signal_size = signal.size()
    kernel_size = kernel.size()
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
    i = reference.size() - 1
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
    count = samples.size()
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
