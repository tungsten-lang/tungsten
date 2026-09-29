# Linear algebra

## Thin SVD (`core/linalg.w`)

`LinAlg.svd(rows)` returns `[U, singular_values, Vt]`, with thin shapes
`m × k`, `k`, `k × n`, where `k = min(m,n)`. It copies finite rectangular input
and calls LAPACK directly; rank-deficient and wide matrices are supported.
Singular values are nonnegative and descending; vectors in repeated/zero
singular subspaces have no unique orientation. Empty input returns empty factors.

This is the numerical backend for [CP and Tucker decomposition](tensor-decomposition.md).

## Tensor layout helpers (`core/tensor.w`)

Dense Tensor is the matrix type. `.T` / `.H` / `.diag` / `Tensor.diag` are
methods on that type, not extra classes — see [tensor-vs-array.md](tensor-vs-array.md).

## Surface (`core/sci/linalg.w`)

| Op | Notes |
|----|--------|
| `matmul` | nested-list GE / staged dgemm; no Grid type |
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
