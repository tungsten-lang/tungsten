# FFT

## Native (`core/fft.w`)

Radix-2 iterative Cooley–Tukey on split real/imag arrays:

```
use core/sci/fft
re = [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
im = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
ft = FFT.fft(re, im)     # [re_out, im_out]
back = FFT.ifft(ft[0], ft[1])
mag = FFT.abs(ft[0], ft[1])
```

Also: `rfft`, `fft2` (row-column).

Length must be a power of 2. Non-pow2 / Bluestein is a follow-up.

## Accelerated path

`fft_f32(re, im, n, inverse)` in `core/blas.w` → `w_blas_fft_f32` →
vDSP on macOS when the BLAS bridge is linked.

## Benchmarks

`benchmarks/fft/` compares Tungsten pure FFT against NumPy and (when
present) FFTW / SciPy. See that directory's `run.sh`.
