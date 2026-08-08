# Tungsten Core scientific-computing audit

This audit records the committed Core surface at `8bbbf16` plus the focused
`core/sparse` work developed with it. It is based on implementation, specs,
benchmarks, generated Core documentation, and Koala call sites. "Present"
below means a reachable implementation, not merely a declaration in an API
scaffold. Comparisons with Python, Julia, Rust, C, and Zig are practical gap
tests, not checklists that Tungsten must copy.

## Executive result

Tungsten does not need another dense array or matrix hierarchy. It already has
a genuine N-dimensional `Tensor`, a packed one-dimensional `Array` runtime,
small fixed `Vector`/`Matrix` values, and nested-row `LinAlg`. The main problem
is coherence between those layers, followed by missing robust dense
factorizations and a sparse layer that previously densified its only portable
solve.

The first justified implementation tranche therefore stays in `core/sparse`:

- validated, copied, canonical CSR storage (sorted columns, duplicate
  coalescing, explicit zeros removed);
- transpose, scaling, addition, sparse matrix multiplication, and shape checks;
- non-densifying conjugate-gradient and BiCGSTAB solves with explicit criteria,
  status, iteration count, and residuals;
- structural rank, named honestly as a sparsity-pattern diagnostic rather than
  numerical rank.

This is a portable correctness foundation. It is not yet a claim of
SciPy/Julia throughput or breadth.

## What already exists

### Dense storage and linear algebra

| Surface | Direct evidence | Consequence |
|---|---|---|
| `core/tensor.w` | N-dimensional shape and strides, dtype/unit metadata, CPU and Metal faces, reshape/permute/transpose/slice/contiguous, elementwise broadcasting, reductions, softmax, and rank-2 matmul | Keep this as the dense multi-D type. Do not create `NdArray`, `Grid`, or a Koala tensor substitute. |
| `WTensor` | Runtime header with rank, offset, inline/heap shape and strides, borrowed views, and storage pointer | The runtime already has the memory-layout vocabulary for views; remaining work is consolidation and coverage. |
| `core/vector.w`, `core/matrix.w` | Fixed small generic vectors/matrices, column-major, including `Vec2/3/4` and `Mat2/3/4` | Useful for geometry/graphics and small algebra; not a dynamic scientific matrix container. |
| `core/linalg.w` | Nested row arrays with zeros/identity, matmul, dot/norm, partial-pivot solve, determinant, and Cholesky | A portable baseline exists, but the decomposition surface is small and uses boxed nested arrays. |
| `core/blas.w` and runtime bridges | BLAS/LAPACK and vDSP paths, including GEMM and selected solves/factorizations | Dense throughput should extend these bridges and Tensor adapters, not fork storage. |
| dense benchmarks | `benchmarks/linalg` includes cross-language GEMM results; the documented Accelerate result is a raw BLAS-path result | Evidence supports a fast backend, not end-to-end Tensor/Koala parity. |

The highest-value dense gaps are pivoted QR, an explicit reusable LU result,
SVD, symmetric/general eigensystems, least squares built on QR/SVD rather than
normal equations, numerical rank/condition estimates, and coherent adapters
between nested rows, typed arrays, and Tensor. Tensor itself still needs
broader dtype promotion, robust f64 and batched matmul, and more complete
indexing/reduction coverage. These are extensions to existing types.

### Sparse linear algebra before this tranche

`SparseMatrix` already provided CSR and COO construction, dense conversion,
pure SpMV, opt-in Apple SparseBLAS SpMV, and opt-in Apple sparse QR/Cholesky.
The only portable solve called `to_dense` and `LinAlg.solve`. Constructors
accepted unsorted or duplicate storage without a shared canonical invariant.
There were no sparse-preserving matrix operators, iterative solvers, rank
diagnostics, portable sparse eigensystems, or sparse performance benchmark.

The new implementation addresses the storage boundary and the smallest useful
portable Krylov/operator tranche. Important gaps remain:

- CSC and block formats, efficient format conversion, typed/unboxed canonical
  storage (iterative solves now make typed solve-local copies), and
  symbolic/numeric factorization separation;
- public triangular solves, sparse LU/QR/Cholesky on non-Apple systems, and
  reusable factors;
- reusable preconditioner/factor protocols and ILU (strict IC(0) is now
  available for exactly symmetric inputs with positive pivots);
- MINRES, GMRES, LSQR/LSMR, multiple right-hand sides, and sparse-dense
  products;
- numerical rank, nullspace and condition estimation (structural rank is only
  a pattern upper bound);
- Lanczos/Arnoldi eigensystems, shifts, convergence diagnostics, and restart;
- backend-sensitive benchmarks against the same matrices and tolerances.

The initial native regression benchmark exposed the boxed hot path: on an
Apple M5 Max, the 1-D Laplacian took a five-run median 718 ms at `n=1,000` (500
CG iterations) and 18,100 ms at `n=5,000` (2,500 iterations). Typed solve-local
CSR and f64 work buffers reduce those measurements to 9 ms and 241 ms without
changing iteration counts. Strict IC(0) is exact for this tridiagonal pattern
and reduces them further to one iteration (6 ms and 30 ms, setup included).
That matrix-specific result is not evidence of SciPy/Julia parity; the
benchmark README records residuals, solution error, and measurement scope.

### How Koala actually consumes Core

Koala deliberately owns dynamic ML-facing `Matrix`, `Vector`, and `LinAlg`
classes. Its `LinAlg` includes Householder QR and least squares with a rank
tolerance; linear regression uses those paths, while PCA owns a separate
iterative eigensolver. Koala's matrix acceleration calls Core BLAS.

Sparse integration is thinner: `SparseFrame` converts rows/DataFrames to Core
`SparseMatrix` and converts back to dense rows/DataFrames. No shipped estimator
directly fits a `SparseMatrix`; estimator input normalization targets row
arrays, DataFrame, or `to_matrix`. The richer Koala sparse file is under
`attic/drafts`, so it is not an available competing implementation.

The right integration direction is to migrate proven general-purpose QR,
least-squares, rank, and eigensystem machinery into Core and let Koala adapt to
it. Sparse-aware estimators should accept Core `SparseMatrix` without an
intermediate dense conversion. Model objectives, training policy, feature
semantics, and estimator-specific stopping remain Koala-owned.

## Module ownership proposal

| Home | Owns | Does not own |
|---|---|---|
| `core/sparse/` | sparse storage invariants/formats, sparse-preserving operators, preconditioners, iterative/direct sparse solves, sparse numerical diagnostics, sparse eigensystems | estimator training, dense Tensor storage, domain physics |
| existing `core/linalg` modules | dense decompositions/solve/eigen/SVD/rank/condition and adapters for nested rows, typed buffers, and Tensor | sparse format policy, optimization objectives |
| Core Optimization | objective/root/nonlinear least-squares/constrained algorithms, convergence criteria/results; consumes Core dense/sparse LA | QR/SVD/LU implementations and Koala model loss policy |
| Core Physics | domain equations, constitutive models, discretization semantics, and physical diagnostics; consumes math/LA/units | generic solvers or array storage |
| `core/io` | format codecs, datasets, dtype/shape/schema metadata, chunking, streaming, mmap/lazy reads | numerical algorithms and notebook protocol |
| proposed `core/science` | optional discoverability facade and shared dataset/provenance vocabulary only | a second Tensor, Matrix, solver, or I/O implementation |

There is no current `core/science` or `core/physics` module. Physics-oriented
types are mainly under `core/geometry`. Creating namespaces solely to imitate
another ecosystem would add churn; use them when a coherent facade or domain
surface exists.

## Scientific I/O and notebook workflow

`core/io.w` (`SciIO`) and `runtime/sci_io_native.c` are substantial existing
work, not an empty placeholder. Current paths include CSV, FITS primary image,
minimal Zarr metadata/uncompressed float data, NetCDF classic float data, MAT
header handling, custom/plain Parquet work, and TH5 plus a deliberately narrow
foreign-HDF5 contiguous dataset walker.

The HDF5 code itself documents its subset: selected superblocks/object
headers, simple links, contiguous numeric datasets, and a limited dtype set.
It does not provide the groups/attributes/links/named types, chunk/filter
pipeline, strings/compound/variable-length types, virtual datasets, or broad
fixture interoperability expected of general HDF5. Results also do not yet
form a coherent lazy n-dimensional Tensor/dataset object with shape, dtype,
strides, chunking, and selection preserved throughout.

Practical high-impact I/O gaps are:

1. NPY/NPZ and exact dtype/shape/endian round trips to Tensor.
2. Golden external fixtures for HDF5, Zarr, NetCDF, and Parquet, with explicit
   supported-subset failures rather than format-looking custom success.
3. Chunked/compressed selection and lazy or mmap-backed reads.
4. Table schema, missing values, strings/categories, Arrow interchange, and
   standard Parquet pages.
5. Streaming CSV/table readers and bounded-memory writers.

These should be separate, fixture-driven `core/io` tranches. A full HDF5 or
Arrow rewrite is not justified inside the sparse task.

Tungsten has a REPL/console and text plotting, but no Jupyter kernel, cell
protocol, rich MIME display, notebook document, or rich Tensor/DataFrame
renderer. That integration belongs in a bit/tooling layer consuming Core
display/data protocols. It should not be the reason to introduce
`core/science` or another table/tensor type.

## Fundamental data structures versus Rust, C, and Zig

The comparison here asks whether Tungsten exposes similarly predictable
storage and safety tradeoffs, not whether it copies ownership syntax.

### Arrays

Direct evidence:

- `WArray` has a locked 24-byte header: flags and element-width code, 32-bit
  start/size/capacity, and a storage pointer. Typed widths include packed
  booleans/nibbles and raw integer/float arrays; polymorphic arrays store boxed
  WValues. `WBigArray` uses a 40-byte header with 64-bit extents, and
  `SmallArray` covers short fixed inline storage.
- Allocation starts with zeroed storage, normally capacity eight, and growth
  doubles into a new buffer. An uninitialized result allocator avoids redundant
  zeroing where a kernel overwrites every element. Page-aligned mmap allocation
  exists for zero-copy Metal/BLAS use.
- `shift` advances the start offset in O(1); `unshift` reuses front space,
  moves in-place, or grows. Typed argument guards reject element-width stride
  mismatches at native boundaries. The compiler has proved-bounds unchecked
  operations and typed raw-index lowering.
- `slice_view` is a mutable zero-copy alias. A parent/view registry rebases
  views when the parent reallocates; views cannot themselves grow. Ordinary
  slicing/copying APIs still allocate. There is no copy-on-write ownership
  model.
- Checked reads support negative indices and return `nil` out of bounds.
  Checked writes silently no-op outside capacity and may extend logical size
  inside capacity. This is permissive but weaker at catching scientific index
  errors than Rust/Zig checked slices or an explicit C unchecked contract.
- `W_FLAG_FROZEN` is defined, but current `freeze_recursive` only recurses
  through a polymorphic array and does not set that flag; array mutators do not
  test it. Array freezing is therefore not presently an enforced ownership
  boundary.

Inference and priorities:

1. **High impact, bounded:** make freeze behavior real and mirrored in every
   runtime engine, with mutation/view tests. Decide explicitly whether a view
   freezes its owner or only itself. This is a separate runtime tranche.
2. **High impact, bounded:** add strict indexing operations (or a strict mode)
   and use them by default in scientific containers. Keep explicit `get?` or
   unchecked forms for current permissive/performance needs.
3. **Medium:** formalize `reserve`, `shrink_to_fit`, owned/borrowed view
   lifetimes, and page-aligned buffer pinning. The current registry solves
   relocation but not a Rust/Zig-like explicit alias contract.
4. **Medium:** audit collection methods that turn typed arrays back into boxed
   polymorphic arrays and provide typed-preserving kernels where measured.
5. **Lower/measure first:** replace quadratic helpers such as `uniq`; workload
   benchmarks should determine whether hashing or sort-based paths win.

### Strings

Direct evidence:

- Strings are immutable UTF-8 bytes with three storage strata: up to five
  bytes inline in the WValue, interned slab strings through 61 bytes, and heap
  strings beyond that or after slab freeze. Ropes are flattened at relevant
  dispatch boundaries. The slab interner uses an open-addressed wyhash table
  and preserves lookup of existing canonical strings after freeze.
- The active `core/string_native.w` defines `size` and `length` as stored byte
  length; the runtime benchmark fixtures explicitly require `"é".size == 2`.
  `chars` and `reverse` walk UTF-8 codepoint boundaries. `bytes` exposes raw
  bytes and `valid_utf8?` validates input.
- Case conversion is ASCII-only; bytes at or above `0x80` pass through.
  Two-argument slicing uses byte offsets, copies, and can split a UTF-8
  sequence. The long `core/string.w` contains Unicode/grapheme declarations,
  but `Grapheme` is empty and those declarations are not evidence of a
  complete normalization or grapheme implementation.
- String microbenchmarks and cross-language string build/scan benchmarks are
  extensive; the representation-aware length audit covers inline, slab, heap,
  rope, NUL, String, and Symbol cases.

Rust's `String`, C strings, and Zig byte slices also make bytes and UTF-8
boundaries explicit, so byte indexing itself is not a missing feature. The
genuine gap is API coherence: Tungsten's long-form comments promise Unicode
semantics that the active native surface does not provide.

Priorities are to document byte/codepoint/grapheme units in every operation,
make byte slicing explicit and offer validated codepoint boundaries, then add
modern Unicode normalization/casefold/grapheme support only with generated
Unicode data and conformance tests. A borrowed `StringView` is worth proposing
after lifetime/ownership semantics are clear; it should not expose dangling
bytes merely to imitate Rust/Zig.

### Numeric representations

Direct evidence:

- Small integers are immediate; arbitrary integers use 64-bit limbs and a
  large runtime implementation with capacity recycling, schoolbook,
  Karatsuba, multiple Toom tiers, transform multiplication, single-limb,
  Knuth/Burnikel-Ziegler/cached-reciprocal division, and extensive fuzz and
  GMP/cross-language benchmarks. This is not a missing BigInt foundation.
- `Rational` is implemented: a reduced signed-22/unsigned-22 packed tier
  promotes to `WBigRational` backed by the arbitrary Integer tower. Exact
  arithmetic and algebra/calculus specs already consume it.
- Decimal is a fixed significand/scale representation centered on an `int64`
  significand (with packed and heap encodings). `core/numeric/decimal.w` and
  `big_decimal.w` are mostly declarations. There is no explicit decimal
  context carrying precision, exponent limits, rounding mode, traps, or
  operation status, and `BigDecimal` is not evidence of an arbitrary-precision
  decimal engine.

The active BigNum review owns BigInt/Rational performance and representation
changes; this sparse tranche intentionally does not touch them. The largest
independent numeric gap is Decimal correctness/coherence for finance,
measurement, and scientific interchange. A future `core/numeric/decimal`
tranche should first specify contexts and rounding/status behavior, then decide
whether arbitrary precision reuses BigInt limbs. It needs differential tests
against a pinned decimal specification, not merely more class declarations.

## Prioritized follow-on tranches

1. **Sparse canonical typed storage and solver breadth:** make typed CSR
   reusable rather than solve-local, add CSC, public triangular operations,
   reusable factor/preconditioner protocols, GMRES/LSQR, and matrix-family
   benchmarks. Keep in `core/sparse/`.
2. **Dense decomposition contract:** explicit factor/result objects for
   pivoted QR, LU, SVD, least squares, eigensystems, rank and condition, with
   Tensor/nested-row adapters. Keep in `core/linalg` and migrate Koala callers
   only after differential validation.
3. **Array safety contract:** enforced freeze, strict indexing, pinned/view
   lifetime rules, and typed-preserving collection operations. Runtime and
   Core Array ownership; mirror native engines.
4. **Scientific I/O interoperability:** NPY first, then golden subset expansion
   for HDF5/Zarr/NetCDF/Parquet and Tensor-backed dataset selections. `core/io`.
5. **Decimal specification:** contexts, rounding, status/traps, range and
   arbitrary precision decision. `core/numeric/decimal`, coordinated with but
   separate from BigNum optimization.
6. **Koala integration:** sparse estimator input protocol and migration from
   private general-purpose dense LA to stable Core factors. Koala owns only
   adapters and model/training behavior.
7. **Notebook tooling:** Jupyter/rich-display bit after display and dataset
   protocols stabilize; no Core storage fork.

The implementation order should remain evidence-led: add focused interpreted
and native correctness gates first, measure representative matrix/data shapes,
and only then select accelerated algorithms or storage rewrites.
