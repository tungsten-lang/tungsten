# Sparse linear algebra (`core/sparse`)

## Type

**`SparseMatrix`** — sparse *matrix* (CSR / COO), not a sparse N-D tensor.

| Method | Role |
|--------|------|
| `SparseMatrix.csr` / `.coo` / `.eye` / `.from_dense` | construct |
| `.matvec(x)` | pure SpMV |
| `.matvec_accel(x)` | Apple SparseBLAS SpMV (`@w_sparse_`) |
| `.solve(b)` | densify + pure `LinAlg.solve` (portable) |
| `.solve_qr(b)` | Apple Sparse Solvers **QR** factor + solve |
| `.solve_chol(b)` | Apple Sparse Solvers **Cholesky** (SPD) |

COO and CSR constructors validate dimensions, Array lengths, bounds, integer
indices, and finite real values. CSR row pointers must start at zero, be
monotone, and end at the input entry count. Construction copies storage,
sorts entries by row and column, sums duplicate entries in their input order,
and drops exact zeros. `nnz` therefore counts coalesced nonzero entries.
Both `matvec` and `to_dense` use these same canonical values.

Values are converted to binary64, including Integer/Rational/Decimal inputs;
large exact values can lose precision. Nonfinite conversions and overflow
during duplicate summation raise errors. The sum follows ordinary binary64
arithmetic, so changing duplicate input order can change rounding. Native
SpMV additionally converts values to f32; native solvers use f64. `solve`
still densifies, and these methods do not yet return residual/status objects.

## Apple Sparse Solvers

When IR references `@w_sparse_`, stage-1 links `runtime/sparse_bridge.c`:

```
COO (i32,i32,f64)
  → SparseConvertFromCoordinate
  → SparseFactor(SparseFactorizationQR | Cholesky)
  → SparseSolve
  → SparseCleanup
```

Headers: `Accelerate` / `vecLib/Sparse/Solve.h` (macOS).

```
use core/sparse
A = SparseMatrix.coo(3, 3,
  [0, 0, 1, 2, 2],
  [0, 2, 1, 0, 2],
  [~2.0, ~1.0, ~3.0, ~4.0, ~5.0]).to_csr
# Ax = [3,3,9] for x = [1,1,1]
x = A.solve_qr([~3.0, ~3.0, ~9.0])
```

## Koala

Richer SPA (BSR/ELL, GPU spmm, encoders) remains in **bits/tungsten-koala**.
Core keeps a minimal CSR/COO + SpMV + factor/solve surface.

## Specs

```
bin/tungsten run spec/core/sparse_canonical_spec.w
bin/tungsten compile spec/core/sparse_canonical_spec.w --out /tmp/sparse-canonical
/tmp/sparse-canonical
bin/tungsten -o /tmp/spmv spec/sci/sparse_accel_spec.w && /tmp/spmv
bin/tungsten -o /tmp/ssol spec/sci/sparse_solve_spec.w && /tmp/ssol
```
