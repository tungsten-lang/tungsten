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
bin/tungsten -o /tmp/spmv spec/sci/sparse_accel_spec.w && /tmp/spmv
bin/tungsten -o /tmp/ssol spec/sci/sparse_solve_spec.w && /tmp/ssol
```
