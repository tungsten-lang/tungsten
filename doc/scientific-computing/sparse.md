# Sparse linear algebra (`core/sparse`)

## Type

**`SparseMatrix`** — sparse *matrix* (CSR / COO), not a sparse N-D tensor.

| Method | Role |
|--------|------|
| `SparseMatrix.csr` / `.coo` / `.eye` / `.from_dense` | validated construction; CSR is sorted, duplicate-coalesced, and zero-free |
| `.matvec(x)` / `.matvec_into(x, out)` | pure SpMV; reusable-output form avoids allocation |
| `.matvec_accel(x)` | Apple SparseBLAS SpMV (`@w_sparse_`) |
| `.transpose` / `.add(b)` / `.scale(s)` / `.matmul(b)` | portable sparse-preserving operators |
| `.cg(b, criteria)` | conjugate gradient for square SPD systems |
| `.bicgstab(b, criteria)` | BiCGSTAB for general square systems |
| `.structural_rank` | maximum-matching rank of the sparsity pattern |
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
still densifies, and the direct `solve*` methods do not return residual/status
objects; the iterative solvers below do.

`SparseSolveResult` reports `status`, `solution` (also `x`), iteration count,
residual norm, and relative residual. A result can be `:converged`,
`:max_iterations`, or `:breakdown`; `certified?` is deliberately false.
`SparseSolveCriteria` makes relative/absolute tolerances, the iteration limit,
and `:none`/`:jacobi`/`:ichol0` preconditioning explicit. CG with `:none` or
`:jacobi` does not check the SPD assumption for the caller.

The iterative solvers copy canonical CSR once per solve into raw `i64` index
and `f64` value buffers. SpMV, reductions, updates, and all reusable work
vectors are then typed and unboxed in native code. This costs O(rows + nnz)
temporary sparse storage per solve, but avoids boxed element dispatch without
changing the public `SparseMatrix` representation or result API.

`:ichol0` constructs zero-fill incomplete Cholesky and applies its two sparse
triangular factors. It requires exactly symmetric canonical values and a
finite positive pivot in every row. Missing diagonals, asymmetry, non-finite
factor entries, and nonpositive pivots produce `:breakdown` at iteration zero.
The factor keeps only the input lower-triangle pattern; it does not densify.
This strict setup contract is intentional: there is no diagonal shifting or
silent fallback to Jacobi.

The portable iterative paths do not densify. The older `.solve` method still
does, and should only be used for small systems.

Structural rank is not numerical rank: it is the maximum bipartite matching
size of the nonzero pattern. It is an upper bound on numerical rank and is
generically exact, but cannot detect value-dependent linear dependence.

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

Koala's `SparseFrame` is currently a thin row/DataFrame conversion bridge to
this Core type. The only richer sparse implementation under Koala is an attic
draft, not a shipped competing system. Estimators still consume Koala's dense
`Matrix`/row surface; direct sparse estimator fitting is future integration
work and should build on `core/sparse`, not revive the draft.

## Honest gaps

The canonical public matrix still uses ordinary Tungsten arrays; typed CSR is
a solve-local copy rather than a reusable storage format. The implementation
is a measured portable substrate, not a SciPy/Julia throughput-parity claim.
It has CSR/COO but not CSC/BSR, no ILU, no GMRES/MINRES/LSQR, no portable
sparse direct solver (`SparseFactor` retains Apple Accelerate factors only),
no numerical rank/condition estimate, and no Lanczos/Arnoldi eigensystem.
Those belong here incrementally; dense SVD/eigen/QR belong in `core/linalg`.

## Specs

```
bin/tungsten run spec/core/sparse_canonical_spec.w
bin/tungsten compile spec/core/sparse_canonical_spec.w --out /tmp/sparse-canonical
/tmp/sparse-canonical
bin/tungsten -o /tmp/spmv spec/sci/sparse_accel_spec.w && /tmp/spmv
bin/tungsten -o /tmp/ssol spec/sci/sparse_solve_spec.w && /tmp/ssol
bin/tungsten spec/sci/sparse_core_spec.w
bin/tungsten -o /tmp/score spec/sci/sparse_core_spec.w && /tmp/score
```
