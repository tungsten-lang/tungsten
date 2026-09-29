# CP and Tucker tensor decomposition

`TensorDecomposition` operates on the existing dense `Tensor` type. It accepts
finite CPU `f32`/`f64` tensors of order two or higher, with positive dimensions.
All work and returned tensors use `f64`. Views are copied in logical axis order;
input tensors and supplied initial factors are never overwritten.

```tungsten
use core/tensor/decomposition

x = Tensor.zeros_cpu(Tensor.f64, [3, 4, 5])
# Fill x with the data to approximate.
cp = TensorDecomposition.cpd(x, 2)
tk = TensorDecomposition.tucker(x, [2, 3, 3])
approximation = cp.reconstruct
<< cp.relative_error
<< tk.status
```

Compile Tensor programs with `bin/tungsten compile example.w -o /tmp/example`.
The classes are also registered for Core autoload, so explicit `use` is optional.
This initial implementation is CPU-only; it does not silently copy Metal tensors
to the host or use a GPU/Neural Engine backend.

## Canonical polyadic decomposition (CPD)

```text
TensorDecomposition.cpd(tensor, rank,
  max_iterations=100, tolerance=~1e-8, seed=1,
  rcond=~1e-12, initial_factors=nil)
```

Arguments are positional. CP-ALS alternately solves a least-squares problem for
each mode using a thin SVD, not normal equations. Singular values at or below
`rcond * largest_singular_value` are discarded. This supports rank-deficient and
wide Khatri-Rao systems, including component counts greater than a mode size.

The result is a `CPDecomposition` with:

- `weights`: one scalar per requested component.
- `factors`: one dimensionless matrix of shape `shape[mode] × rank` per mode;
  nonzero columns are normalized to unit Euclidean norm.
- `shape`, `rank`, `unit`, `iterations`, `relative_error`, `status`, `algorithm`.
- `reconstruct`: evaluates the weighted sum of outer products.
- `converged?` and `certified?` (the latter is always false).

The integer seed controls a local deterministic initializer, without changing
global random state. Optional `initial_factors` must contain one dimensionless
matrix per mode, with the specified component count. Their unweighted outer
product sum is interpreted in the original input scale; incorporate any initial
weights into one factor. They are copied before fitting.

`status` is `:converged` when the relative residual reaches tolerance, `:stalled`
when successive residuals change by no more than tolerance without meeting it,
or `:max_iterations` when the budget expires. Zero iterations returns the initial
fit and its diagnostics. The requested rank is a component budget, **not** an
estimated or proven minimal rank; zero/redundant components are retained.

## Tucker decomposition

```text
TensorDecomposition.tucker(tensor, ranks,
  max_iterations=25, tolerance=~1e-8)
TensorDecomposition.hosvd(tensor, ranks)
```

`ranks` has one integer per mode, from one through that mode's size. HOSVD takes
the leading left singular subspaces of the mode unfoldings. `tucker` initializes
that way and then runs higher-order orthogonal iteration (HOOI), optimizing one
mode subspace at a time. `hosvd` is the zero-refinement version.

The `TuckerDecomposition` contains `core`, orthonormal-column `factors`, `ranks`,
`iterations`, `relative_error`, `status`, and `algorithm` (`:hosvd` or
`:tucker_hooi`), plus `reconstruct`, `converged?`, and `certified?` (false).
The core carries the input unit; factors are dimensionless. Reconstruction
applies the mode factors to the core. Full mode ranks reconstruct the input up
to floating-point rounding, including modes larger than their unfolding's
column count.

For HOOI, `:converged` means either the residual reached tolerance **or** its
change fell below tolerance; this can be a stationary approximation with nonzero
error. Always inspect `relative_error`. Unrefined, non-exact HOSVD reports
`:hosvd`; exhausted HOOI reports `:max_iterations`.

## Supporting operations and limits

- `TensorDecomposition.unfold(tensor, mode)`: mode rows first; remaining axes
  appear in increasing original order, with row-major column ordering.
- `TensorDecomposition.mode_product(tensor, matrix, mode)`: multiplies that
  unfolding by a dimensionless `new_size × old_size` matrix and restores axes.
- `TensorDecomposition.cp_tensor(weights, factors)` and
  `tucker_tensor(core, factors)`: reconstruct user-supplied decompositions.
- `LinAlg.svd(rows)`: thin `[U, singular_values, Vt]` for a finite rectangular
  matrix of nested rows, backed by LAPACK. The input is copied.

Relative error is the Frobenius residual divided by the input Frobenius norm;
zero input uses the absolute residual. Solvers scale input before fitting and
use stable norm accumulation. Numerical overflow/nonfinite iterates raise an
error rather than returning a success status. Returned factors/core are mutable;
diagnostics describe the fit at return time, not subsequent caller edits.

These are bounded local numerical methods. CP can stagnate, depend on
initialization, or have degenerating components; Tucker/HOOI is not a global
optimality guarantee. Try multiple CP seeds if needed. Unfoldings, Khatri-Rao
products and reconstructions are materialized, so this is not a sparse or
streaming solver and temporary storage grows with the tensor and requested rank.

In particular, real-valued CP/Tucker fits are **not GF(2) tensor identities**.
MetaFlip candidates still need finite-field repair and independent exact tensor
verification before archive admission. Tucker multilinear ranks are not CP
rank or matrix-multiplication operation counts.

Algorithm references: [CP-ALS](https://www.tensortoolbox.org/cp_als_doc.html),
[Tucker HOOI](https://www.tensortoolbox.org/tucker_als_doc.html), and
[LAPACK thin SVD](https://www.netlib.org/lapack/explore-html/df/d22/group__gesdd_ga8941e5ff50de36580dae8940015e9cb0.html).
