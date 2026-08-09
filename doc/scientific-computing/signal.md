# Discrete signals

`Signal` is the finite-sequence layer above Tungsten's low-level split-array
`FFT`. It provides direct linear convolution, cross-correlation, a raw
one-sided transform view, and explicitly normalized periodogram/Welch spectral
estimates for uniformly sampled real data:

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

p = Signal.periodogram(
  [~1.0, ~0.0, ~-1.0, ~0.0, ~1.0, ~0.0, ~-1.0, ~0.0],
  sample_rate: ~8.0,
  window: :hann)
# p.scaling == :density
# p.integrated_power == 0.5 for this bin-centered unit cosine

w = Signal.welch(
  samples,
  256,
  sample_rate: ~48_000.0,
  overlap: 128,
  window: :hann,
  detrend: :mean)
# Only complete 256-sample frames contribute.
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

`Signal.spectrum` remains a raw transform view. It does not window, detrend,
pad, or reject non-finite samples, and its amplitudes are not a power spectral
density. Use the estimation APIs below when those semantics are required.

## Window definitions

`Signal.window(kind, length, convention)` returns a newly allocated real list.
The supported kinds are `:boxcar` and `:hann`; the convention is `:periodic`
by default and may be `:symmetric`.

For length `L > 1`, the Hann definitions are

`w[n] = 0.5 - 0.5 cos(2 pi n / L)` for `:periodic`, and

`w[n] = 0.5 - 0.5 cos(2 pi n / (L - 1))` for `:symmetric`.

The periodic form is intended for spectral analysis: it omits the duplicated
right endpoint of one period. The symmetric form includes both endpoints and
is commonly useful for FIR design. A length-one boxcar or Hann window is
defined as `[1.0]`. Length must be a positive integer.

The symmetric length-two Hann window is mathematically `[0.0, 0.0]` and is
therefore valid as a window value but invalid for spectral estimation, which
requires nonzero coherent gain and energy.

## Periodogram and Welch estimates

The public calls are:

```w
Signal.periodogram(
  samples,
  sample_rate: ~1.0,
  window: :boxcar,
  convention: :periodic,
  detrend: :none,
  scaling: :density,
  nfft: nil)

Signal.welch(
  samples,
  segment_length,
  sample_rate: ~1.0,
  overlap: nil,
  window: :hann,
  convention: :periodic,
  detrend: :mean,
  scaling: :density,
  nfft: nil)
```

Both require a nonempty list of finite real samples and a finite positive
sample rate. Samples are assumed uniformly spaced at `1 / sample_rate`, with
the first sample at index zero. Detrending is either `:none` or removal of the
arithmetic frame mean with `:mean`; Welch detrends each frame independently
before applying its window.

For one frame `x[n]`, window `w[n]`, and transform length `K`, define

`z[n] = w[n] (x[n] - frame_mean)`,

`U = sum_n w[n]^2`, `C = sum_n w[n]`, and

`X[k] = sum_(n=0)^(K-1) z[n] exp(-i 2 pi k n / K)`.

The frame is zero-padded from its stored length through `K`; it is never
truncated. Only bins `0..K/2` are returned. Let `d[k]` be 1 at DC and at the
even-length Nyquist bin, and 2 at interior positive-frequency bins. Then:

- `scaling: :density` returns
  `P[k] = d[k] |X[k]|^2 / (sample_rate * U)`, in power per unit frequency.
- `scaling: :spectrum` returns
  `P[k] = d[k] |X[k]|^2 / C^2`, in power.

The equivalent noise bandwidth is
`ENBW = sample_rate * U / C^2`, so `:spectrum` values equal `:density` values
times ENBW. This coherent-gain spectrum normalization is not the square of
`SignalSpectrum#amplitudes` at interior bins.

An omitted `nfft` selects the smallest power of two at least as long as the
frame. An explicit `nfft` must be a power-of-two integer no shorter than the
frame. This zero padding refines frequency spacing but does not change the
window normalization or total represented power. It is observable through
`result.nfft` and `result.zero_padding`.

Welch requires an integer `segment_length >= 2` no larger than the record. It
defaults to `floor(segment_length / 2)` overlap; an explicit overlap must be an
integer from zero through `segment_length - 1`. Frame starts are
`0, step, 2*step, ...`, where `step = segment_length - overlap`. Only starts
whose entire frame fits the record contribute; the incomplete trailing frame
is dropped rather than zero-padded. `result.dropped_samples` reports the
unconsumed tail after the last complete frame. Welch averages the normalized
power values from its frames, not their complex FFT coefficients.

## Spectral estimate results

`Signal.periodogram` and `Signal.welch` return a
`SignalSpectralEstimate`. Its array getters return defensive copies. The
result exposes:

- `frequencies`, `values`, `bin_count`, and `frequency_resolution`;
- `sample_rate`, `sample_count`, `segment_length`, `overlap`, `nfft`,
  `zero_padding`, and `segment_count`;
- `estimator`, `window`, `window_convention`, `detrend`, and `scaling`;
- `sides == :one_sided`, `boundary == :drop`, and `dropped_samples`;
- `coherent_gain`, `window_energy`, and `equivalent_noise_bandwidth`.

`integrated_power` converts either scaling back to the represented
window-energy-normalized mean-square power. For `:density` it is
`sum(values) * sample_rate / nfft`; for `:spectrum` the same expression is
also divided by ENBW. It is a numerical estimate, so `certified?` is false.

## Supported scope and limitations

This initial estimation layer is deliberately batch-oriented and real-only.
It supports boxcar/Hann windows, constant-mean detrending, one-sided output,
complete Welch frames, and radix-2 FFT lengths. It does not provide arbitrary
window arrays, linear detrending, two-sided or complex estimators, confidence
intervals/degrees of freedom, cross spectra/coherence, multitaper methods,
irregular sampling, streaming state, resampling, IIR/FIR filtering, or FFT
convolution. Inputs are converted to machine Float, and non-finite inputs or
invalid normalization/output caused by floating-point overflow or underflow
are rejected.
