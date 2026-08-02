# Discrete signals

`Signal` is the finite-sequence layer above Tungsten's low-level split-array
`FFT`. It currently provides direct linear convolution, cross-correlation, and
a one-sided spectrum for uniformly sampled real data:

```w
use signal

y = Signal.convolve([1, 2, 3], [4, 5])
# [4, 13, 22, 15]

r = Signal.correlate([1, 2, 3], [4, 5])
lags = Signal.correlation_lags(3, 2)
# r = [5, 14, 23, 12], lags = [-1, 0, 1, 2]

s = Signal.spectrum(
  [~1.0, ~0.0, ~-1.0, ~0.0, ~1.0, ~0.0, ~-1.0, ~0.0],
  ~8.0)
# s.frequencies == [0, 1, 2, 3, 4] Hz
# s.amplitudes[2] == 1 for this bin-centered cosine
```

## Sequence and boundary conventions

Samples are indexed from zero. Linear convolution is

`y[k] = sum_n signal[n] * kernel[k - n]`,

with both finite sequences treated as zero outside their stored indices. The
implementation is direct `O(NM)` arithmetic, preserves exact integer results,
does not mutate its inputs, and orders each product as `signal * kernel`.

The optional mode is one of:

- `:full`: every nonempty overlap, length `N + M - 1`.
- `:same`: length `N`, where `N` is the first sequence's length. It begins at
  `floor((M - 1) / 2)` in the full result, so even kernels use the earlier of
  the two possible centers.
- `:valid`: only positions where the second sequence lies fully within the
  first, length `N - M + 1`. This mode requires `M <= N`.

If either sequence is empty, convolution and correlation return `[]`.

## Correlation convention

`Signal.correlate(signal, reference)` conjugates the reference and returns
increasing lags:

`r[lag] = sum_n signal[n + lag] * conjugate(reference[n])`.

In `:full` mode, lags range from `-(M - 1)` through `N - 1`.
`Signal.correlation_lags(N, M, mode)` returns the labels for any mode. Real
values are unchanged; values such as `Complex<f64>` that expose `conjugate`
use it.

## Spectrum convention and normalization

`Signal.spectrum(samples, sample_rate)` accepts nonempty, power-of-two real
input because it delegates to the existing radix-2 `FFT.rfft`. `sample_rate`
is samples per unit time (normally Hz) and must be positive. For `N` samples,
the result retains bins `0..N/2` at frequencies `k * sample_rate / N`.

The forward coefficient convention is unnormalized:

`X[k] = sum_n x[n] exp(-i 2 pi k n / N)`.

`SignalSpectrum#real` and `#imaginary` expose those coefficients;
`#magnitudes` returns raw `|X[k]|`. `#amplitudes` returns one-sided peak
amplitudes by dividing by `N` and doubling interior positive-frequency bins.
DC and the even-length Nyquist bin are not doubled. `#phases` uses
`Math.atan2(imaginary, real)` in radians; phase has no mathematical meaning at
a zero-magnitude bin.

No windowing, detrending, padding, resampling, streaming state, FFT convolution,
power spectral density, or non-power-of-two transform is implied. Non-finite
samples are not rejected. Those features should be added as explicit layers
with their own normalization and boundary contracts rather than folded into
this initial API.
