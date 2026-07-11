# Linear algebra

## Surface (`core/sci/linalg.w`)

| Op | Notes |
|----|--------|
| `matmul` | via `Grid.matmul` (triple loop v0) |
| `solve` | GE with partial pivoting |
| `lu` / `cholesky` / `qr` | pure Tungsten |
| `det` / `inv` | via GE |
| `lstsq` | normal equations |
| `eig_power` | power iteration |
| `norm` / `dot` / `outer` | |

## BLAS / LAPACK bridges

| Symbol | Backend |
|--------|---------|
| `sgemm` / `dgemm` | Accelerate (macOS) / OpenBLAS (Linux) |
| `dgesv` / `dpotrf` | Accelerate clapack |
| `fft_f32` | vDSP (macOS) |
| vDSP sum/dot/sin/… | Accelerate |

Portable Linux: `runtime/openblas_bridge.c` linked when IR has `@w_blas_`
and host is Linux (`-lopenblas`). Install `libopenblas-dev`.

Pure `LinAlg.solve` needs **no** BLAS link — always available.

## No device placement

Buffers on Apple Silicon are unified. Hot paths already auto-dispatch
(sgemm → AMX, Metal kernels when Tensor is used). Explicit
`device: :cpu|:gpu` is intentionally **not** required.
