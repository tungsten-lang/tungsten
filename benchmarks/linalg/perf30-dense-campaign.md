# Perf30 dense / Tensor / LinAlg campaign

Baseline revision: `43642a9de2dca0ab455cef7e49deb69b70d86066`

Branch: `codex/perf30-dense`

Host: Apple Silicon macOS; release builds; wall-clock samples are matched within each item.

This journal is append-only by campaign item. Each retained change has a focused correctness oracle, alternating or multi-sample timings, and its own commit. Millisecond-resolution results are reported as directional when the measured interval is too short for a reliable ratio.

## Original item 1 — CPU Tensor result allocation

Source finding: CPU-capable `scale`, unary, axis-reduction, and softmax methods allocated with the three-argument Metal constructor. A CPU receiver therefore passed `:cpu` where an MTLDevice was required.

Oracle and command:

```sh
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile \
  benchmarks/linalg/tungsten/dense_tensor_campaign.w \
  --out /tmp/perf30_dense --release
/tmp/perf30_dense cpu-ops
```

- Baseline `43642a9d`: fails immediately with `Metal.buffer_new: first arg must be a Metal device`.
- Candidate: `CPU_OPS_OK`; five process timings were at or below the shell timer's 10 ms resolution after one 50 ms cold launch.
- Focused regression `spec/core/tensor_cpu_ops_spec.w`: 10/10 checks pass.
- Existing `spec/sci/tensor_cpu_spec.w`: `TENSOR_CPU_OK`.

Retained as a correctness fix. It changes result construction to the existing backend-aware `Tensor.zeros_like` path; no performance ratio is claimed because the baseline operation cannot complete.

## Original item 2 — view-aware CPU GEMM

Source finding: `Tensor.matmul` treated a packed nonzero-offset slice as
contiguous but passed the typed array's base address to the NN-only bridge,
producing a wrong result. A transpose view took the opposite path and was
materialized element-by-element before every GEMM.

Correctness oracle:

```sh
/tmp/perf30_dense_view_base view-oracle
/tmp/perf30_dense_view_candidate view-oracle
```

- Parent `060146b8`: `offset matmul 00: got 1, expected 3`.
- Candidate: `VIEW_ORACLE_OK`; the focused CPU Tensor spec passes 13/13,
  including offset and transpose GEMM, and the existing Tensor CPU smoke still
  prints `TENSOR_CPU_OK`.

Matched performance workload: 200 multiplies of logical `[192,128] x
[128,160]` f64 matrices. The left operand is a zero-copy transpose view of a
packed `[128,192]` allocation. Alternating whole-process `time -p` samples:

| sample | parent | candidate |
| --- | ---: | ---: |
| 1 | 1.02 s | 0.05 s |
| 2 | 1.03 s | 0.04 s |
| 3 | 1.03 s | 0.04 s |

Retained. The bridge now accepts element offsets and NoTrans/Trans layout
flags on both inputs. Packed, offset-packed, and simple transpose views enter
CBLAS directly; general strided views retain the materialization fallback.

## Original item 3 — allocation-free Tensor layout metadata

Source finding: every `contiguous?` call rebuilt an Array of packed strides,
and `packed_strides` itself used a nested suffix-product loop. `to_rows` then
called `contiguous?` once per element. The public `shape` and `strides` Arrays
are mutable, so persisting a cached answer would be observably stale after an
in-place metadata edit; this tranche keeps mutation semantics and computes the
answer in one reverse walk.

Matched workload: five million repetitions of `size` plus `contiguous?` on a
packed rank-2 f64 CPU Tensor. Alternating samples in ns/iteration:

| sample | parent `61f4ab49` | candidate |
| --- | ---: | ---: |
| 1 | 112 | 75 |
| 2 | 106 | 77 |
| 3 | 110 | 79 |
| 4 | 111 | 75 |
| 5 | 103 | 75 |

Median: 110 ns to 75 ns, a 31.8% reduction. The focused Tensor spec passes
16/16, including rank-3 packed strides, malformed-stride rejection, and an
offset `to_rows` oracle; CPU ops and view-GEMM campaign oracles still pass.

Retained. `packed_strides` is now O(rank), `contiguous?` is allocation-free,
and `to_rows` hoists the layout decision and includes the storage offset.
Object-level caching remains inappropriate until Tensor metadata becomes
immutable or mutations are routed through coherent setters.

## Original item 4 — packed CPU reductions

Source finding: whole-Tensor `sum`/`max` and axis reductions called `unravel`
and constructed coordinate Arrays for every input element. Even the common
packed last-axis case therefore spent almost all of its time in object and
index machinery rather than arithmetic.

Correctness: the focused CPU Tensor spec passes 23/23. It covers f32/f64,
whole and last-axis fast paths, a non-last-axis fallback, a nonzero-offset
slice, and a transposed fallback. The existing CPU Tensor smoke still prints
`TENSOR_CPU_OK`; the campaign's CPU-op and view-GEMM oracles still pass.

Alternating whole-process samples:

| workload | parent `9cf57471` | candidate |
| --- | ---: | ---: |
| 200 whole f64 sums, sample 1 | 1.91 s | 0.06 s |
| sample 2 | 1.77 s | <0.01 s |
| sample 3 | 1.88 s | <0.01 s |
| 100 last-axis sum+max pairs, sample 1 | 1.20 s | <0.01 s |
| sample 2 | 1.21 s | <0.01 s |
| sample 3 | 1.13 s | <0.01 s |

The initial candidate used vDSP for f64 sums, but its reassociation changed the
reference API's observable cancellation result. The final retained bridge uses
one ordered native C loop, avoiding Tungsten coordinate allocation while
preserving the exact left fold. Five final-integration process samples for
10,000 operations were 0.37–0.38 s for whole sums and 0.56–0.58 s for
last-axis sum+max pairs: 37–38 us/sum and 56–58 us/pair including launch. The
matched parent's medians are 9.4 ms/sum and 12.0 ms/pair respectively, roughly
250x and 210x slower.

Retained. Packed CPU reductions use ordered native loops over the existing
buffer and offset; f32 sum preserves the prior double accumulator. A single
bridge call handles all rows of a packed last-axis reduction. General strided
and non-last-axis reductions retain the reference path. Sum and max retain the
prior evaluation/comparison semantics, including cancellation, first-element
NaN, and signed-zero behavior.

## Additional Tensor tranche — packed CPU unary vector path

Source finding: Tensor already shipped native f32/f64 vForce entry points, but
its unary methods always took the coordinate-Array reference loop. Each
element of a packed `exp`, `sqrt`, `abs`, `square`, `neg`, or `relu` therefore
paid unravel, indexed method dispatch, and coordinate-based output writes.

Matched workload: 100 `exp` operations over a packed 256x256 f64 Tensor.
Alternating whole-process samples:

| sample | parent `74879194` | candidate |
| --- | ---: | ---: |
| 1 | 1.30 s | 0.04 s |
| 2 | 1.31 s | 0.04 s |
| 3 | 1.30 s | 0.05 s |
| 4 | 1.31 s | 0.04 s |
| 5 | 1.27 s | 0.05 s |

A 1,000-operation candidate run takes 0.42 s, or 0.42 ms/op including fresh
result allocation, versus a parent median of 13.0 ms/op: 31x faster. The
focused Tensor spec passes 31/31, covering all six operations, f32/f64,
nonzero offsets, and the general-stride fallback; other campaign oracles pass.

Retained. One offset-aware native call handles a packed unary operation;
vForce/vDSP provide the vector kernels on macOS and portable scalar loops back
the same API elsewhere. ReLU remains an ordered scalar comparison to preserve
NaN and signed-zero behavior. General strided tensors retain the reference
implementation.

## Original item 7 — double-precision BLAS level 1/2

Source finding: Core exposed f32 `dot`/`axpy`/`gemv`, while the scientific
stack and Tensor CPU storage are predominantly f64. Flat f64 callers either
wrote Tungsten scalar loops or escalated matrix-vector products to GEMM.

Correctness: new focused `spec/core/blas_f64_spec.w` passes 4/4 for `ddot`,
`dnrm2`, in-place `daxpy`, and row-major `dgemv`; the spec-lane manifest
classifies it. Checksums from scalar and native campaign modes agree.

Alternating whole-process samples:

| workload | scalar parent `201c2a43` | native candidate |
| --- | ---: | ---: |
| 200 dot products, sample 1 | 0.28 s | 0.05 s |
| samples 2-5 | 0.23-0.24 s | <0.01 s |
| 100 512x512 matrix-vector products, sample 1 | 0.50 s | 0.01 s |
| samples 2-5 | 0.47-0.48 s | 0.01 s |

Long native runs take 0.02 s for 10,000 length-65,536 dots (at most 2 us/op)
and 0.06 s for 10,000 512x512 GEMVs (6 us/op). Parent medians are 1.2 ms/dot
and 4.7 ms/GEMV.

Retained as flat typed-storage APIs in `core/blas.w`, backed by CBLAS on both
Accelerate and OpenBLAS. This intentionally does not add another nested-list
staging route to `LinAlg`; boundary conversion policy is a separate active
campaign item.

## Original item 8 — LAPACK thin QR tranche

Source finding: `LinAlg.qr` used modified Gram-Schmidt for every shape. Core
already stages nested rows for LAPACK solve/Cholesky, so the same boundary can
feed `dgeqrf` + `dorgqr` and return the existing `[q, r]` contract.

Correctness: `spec/core/linalg_qr_lapack_spec.w` passes 3/3 for orthogonality,
reconstruction, and the documented dependent-column fallback. On the 128x64
campaign matrix, max `Q^TQ-I` error is `1.78e-15` and max reconstruction error
is `3.89e-15`. The reference path now explicitly zeros a numerically dependent
column, matching its pre-existing documentation rather than normalizing roundoff.

Matched 20-operation 128x64 QR samples:

| sample | parent `07b0a4c8` | candidate |
| --- | ---: | ---: |
| 1 | 0.48 s | 0.04 s |
| 2 | 0.39 s | 0.04 s |
| 3 | 0.41 s | 0.04 s |
| 4 | 0.40 s | 0.04 s |
| 5 | 0.41 s | 0.04 s |

Shape crossover probes on the candidate compare the same reference and LAPACK
entry points. Square 4x4 favors reference (10,000 calls: 0.04 s vs 0.07 s),
while square 8x8 favors LAPACK (5,000 calls: 0.11 s vs 0.05 s). For 16x8,
reference/LAPACK are 0.21/0.06 s over 5,000 calls, with the gap widening at
larger shapes. The retained column cutoff is therefore 8.

Retained. Full-rank `m>=n` QR at `n>=8` routes through LAPACK; smaller and
rank-deficient inputs keep the reference semantics. A least-squares API is
deferred: Core currently has no contract for underdetermined systems,
multi-RHS shape, rank reporting, or `rcond`, and silently choosing those here
would be an API change rather than a complete performance tranche.

## Original item 9 — symmetric eigenvalues and singular values

Source finding: Core used the general nonsymmetric `dgeev` path even for real
symmetric matrices and had no SVD entry point. Callers needing singular values
had to form `A^T A`, square the condition number, and eigendecompose the normal
matrix.

Correctness: `spec/core/linalg_spectral_spec.w` passes 5/5 for a known
symmetric spectrum, tall and wide SVD, rank deficiency, and empty inputs.
`eigh_values` is ascending and `singular_values` descending, matching LAPACK.
The 96x96 benchmark trace and 128x64 singular-value checksum agree with the
general/normal-equation workarounds.

Alternating whole-process samples:

| workload | prior workaround | native values API |
| --- | ---: | ---: |
| 200 symmetric 96x96 spectra | 0.23-0.29 s | 0.08-0.09 s |
| 100 singular spectra of 128x64 | 0.10 s | 0.05 s |

Retained. `eigh_values` uses `dsyev`; `singular_values` uses direct `dgesdd`
and therefore improves numerical conditioning as well as halving this matched
workload. This tranche is deliberately values-only: eigenvector and full SVD
APIs need stable orientation, reduced/full shape, and rank-reporting contracts
before Core can expose them without later incompatibility.

## Original item 8 follow-up — full-rank overdetermined least squares

The earlier QR tranche deferred least squares pending an explicit contract.
This follow-up closes the narrow safe case: f64 `m>=n`, one RHS, full column
rank. Underdetermined shapes, RHS mismatches, LAPACK failure, and numerical
rank deficiency all raise distinct errors; pivoted QR (`dgelsy`) reports rank
using `DBL_EPSILON * max(m,n)`.

Correctness: `spec/core/linalg_least_squares_spec.w` passes 4/4 for a known
noisy fit, rank failure, underdetermined failure, and RHS-shape failure.

Matched 100-operation 512x64 samples compare the previous normal-equation
workaround (`solve(A^T A, A^T b)`) to the direct API:

| sample | normal equations | `least_squares` |
| --- | ---: | ---: |
| 1 | 0.41 s | 0.21 s |
| 2 | 0.38 s | 0.15 s |
| 3 | 0.39 s | 0.16 s |
| 4 | 0.37 s | 0.17 s |
| 5 | 0.36 s | 0.16 s |

Retained. The median improves from 3.8 ms to 1.6 ms per fit (2.4x), while
avoiding condition-number squaring and making rank failure observable.

## Original item 5 follow-up — reusable dense LU factor

Source finding: `LinAlg.solve` stages and factors the same matrix on every
call. This is the correct one-shot contract, but workloads with several
right-hand sides duplicated the O(n^3) factorization and allocated its pivot
workspace each time. The sparse stack already made analysis/factor lifetime
explicit; dense had no equivalent ownership boundary.

Correctness: `spec/core/linalg_lu_factor_spec.w` passes 8/8 for two distinct
right-hand sides against one retained factor, residuals, typed `solve_into`,
returned-output identity, singular failure, nonsquare failure, and RHS-shape
failure. The staged source matrix is copied before factorization. LAPACK
`dgetrs` only reads the retained LU/pivots, so callers may share the factor
read-only as long as each owns its RHS/output.

Matched 1,000-operation samples at 256x256 compare refactoring through the
existing `LinAlg.solve`, list-returning factor solves, and a caller-owned f64
output. Times are internal microseconds per solve:

| sample | refactor each RHS | retained factor, list | retained factor, `solve_into` |
| --- | ---: | ---: | ---: |
| 1 | 1288 | 40 | 28 |
| 2 | 1231 | 32 | 29 |
| 3 | 1206 | 28 | 25 |
| 4 | 1271 | 32 | 27 |
| 5 | 1329 | 28 | 27 |

Retained. Median time falls from 1,271 us to 32 us (39.7x) through the list
API and to 27 us (47.1x) with caller-owned storage. The narrow API is
`LinAlg.factor_lu(a) -> DenseLUFactor`, with `solve` and `solve_into`; it
rejects empty, nonsquare, and singular matrices explicitly. Accelerate and
OpenBLAS bridges keep the same row-major/no-transpose-copy convention.

## Supporting Metal tranche — cached MTLTensor descriptor face

Source finding: every `Tensor.metal_tensor` access rebuilt an MTLTensor
descriptor, even when the backing MTLBuffer, dtype, shape, strides, and offset
were unchanged. `Tensor.linear` performs these lookups on every dispatch.

Matched one-million-lookup samples in ns/call:

| sample | parent `3ebee592` | candidate |
| --- | ---: | ---: |
| 1 | 925 | 107 |
| 2 | 896 | 106 |
| 3 | 808 | 105 |
| 4 | 911 | 97 |
| 5 | 888 | 104 |

Median: 896 ns to 105 ns, 8.5x faster. The Metal campaign oracle confirms
repeated access returns the same descriptor and an in-place shape mutation
invalidates the snapshot. The CPU Tensor spec remains green.

Retained. One cache record occupies Tensor's eighth object slot (the runtime
already allocates a minimum of eight, so the object footprint does not grow).
It snapshots buffer/layout metadata and compares shape/stride contents, which
keeps the cache coherent despite today's mutable Arrays. Argument-table reuse
is not retained here: `linear` binds a fresh output Tensor each call, so a safe
plan cache first needs an explicit `linear_into`/workspace lifetime contract.

## Original item 6 prerequisite — Unicode method-name lowering and fixed objects

Source finding: every generic fixed-width Vec/Mat program failed during class
registration before it could be benchmarked. `mangle_method_name` compared a
Unicode String's UTF-8 byte size with character indexing. The single-character
operator `⊙` therefore produced `nil` on its second byte index and raised
`TypeError: no implicit conversion of Nil into String`. The fix iterates the
already-supported `String#chars` representation; ASCII mangling is unchanged.

Correctness gates using the compiler rebuilt from this source:

- `spec/numeric/operator_overload_spec.w`: 28/28 pass, including `⊙`.
- `spec/numeric/vector_spec.w`: 19/19 pass.
- `spec/numeric/matrix_spec.w`: 20/20 pass.
- The parent compiler cannot compile the matched benchmark; the candidate
  compiles and runs it. The integration worktree must still repeat the
  stage-1/stage-2 and fast-parser/canonical LLVM identity gates after this
  prerequisite is cherry-picked.

Five release samples of the existing fixed-size benchmark (ns/op):

| path | sample range | median |
| --- | ---: | ---: |
| Mat3 value-returning `*` | 84.3-103.3 | 88.9 |
| Mat3 caller-owned `mul_into` | 27.9-31.8 | 29.6 |
| Mat3 raw typed-array kernel | 18.8-22.5 | 19.9 |
| Mat4 value-returning `*` | 90.9-104.8 | 94.2 |
| Mat4 caller-owned `mul_into` | 34.1-37.9 | 35.3 |
| Mat4 raw typed-array kernel | 19.7-23.5 | 20.2 |

Retained as a compiler correctness prerequisite, not as scalar replacement.
LLVM IR confirms why the API split matters: value-returning Mat3/Mat4 products
each contain one inline-array allocation and one object allocation, while
`mul_into` contains neither. Existing caller-owned paths are 2.7-3.0x faster;
the remaining 1.5-1.75x gap to raw kernels includes object field loads and
exact-class guards. Full aggregate/vector scalar replacement is deferred: it
requires an escape/identity-aware representation change, and this narrow
campaign produced no safe compiler optimization with matched evidence.

## Original item 1 follow-up — demand-zero CPU Tensor allocation

Source finding: `Tensor.cpu_zeros` allocates with `w_array_new_aligned`, whose
runtime contract is a private anonymous `mmap`, `size = cap = n`, and
kernel-provided zero pages. It nevertheless wrote `0.0` to all `n` elements.
That loop did not establish length or semantics; it eagerly faulted and dirtied
every page, including outputs that GEMM and native unary kernels fully replace.

Correctness: a fresh 2048x2048 f64 Tensor reads zero at both the first and last
element without the loop. The CPU operation and view-GEMM campaign oracles pass;
`spec/core/tensor_cpu_ops_spec.w` passes 31/31 and the existing scientific Tensor
smoke prints `TENSOR_CPU_OK`.

Five alternating release samples:

| workload | parent `0eadd238` | candidate |
| --- | ---: | ---: |
| first 2048x2048 f64 zero allocation, internal | 24-28 ms | <0.5 ms |
| 2,000 256x256 f64 zero allocations, process | 0.82-0.87 s | 0.00-0.01 s |
| 1,000 256x256 f64 GEMMs, process | 0.57-0.61 s | 0.17-0.25 s |
| 1,000 256x256 f64 `exp`, process | 0.50-0.54 s | 0.12-0.14 s |

The internal repeated-allocation probe reports 393-420 us/allocation before and
1 us/allocation after. Retained. This is not a general uninitialized allocator:
the public zeros contract remains true because anonymous mmap pages are
demand-zero. Full-overwrite kernels simply stop paying for an earlier redundant
page touch.

## Original item 7 follow-up — remaining f64 structured BLAS

Source finding: the flat f64 API had `ddot`, `dnrm2`, `daxpy`, and `dgemv`, but
still forced scalar Tungsten loops or a general GEMM for scaling, symmetric
matrix-vector/rank-k operations, and triangular solves. The retained additions
are `dscal`, upper-triangle `dsymv`/`dsyrk`, and left/lower/non-unit `dtrsm`,
with matching Accelerate and OpenBLAS bridges.

Correctness: `spec/core/blas_f64_spec.w` passes 8/8, including full known-value
oracles for every new operation. The Accelerate bridge passes focused C syntax.
`dsyrk` deliberately follows the BLAS structured-storage contract: it writes
only the upper triangle. An initial full-result prototype mirrored upper to
lower and measured 114 us versus 92 us for general GEMM, so that convenience
contract was rejected before retention.

Five matched release samples (microseconds per operation; medians):

| operation and shape | previous route | new structured route | change |
| --- | ---: | ---: | ---: |
| `dscal`, 65,536 values | scalar 1,185 | 2.44 | 486x |
| `dsymv`, 512x512 | scalar 4,801 | 16.99 | 283x |
| `dsyrk`, 256x256 by 256 | `dgemm` 132.83 | 94.24 | 1.41x |
| `dtrsm`, lower 256x256, 32 RHS | scalar 28,776 | 160.90 | 179x |

Retained. Scalar-route ratios include Tungsten loop/index overhead and are not
presented as CBLAS-vs-C kernel ratios; the `dsyrk` comparison is the stricter
same-bridge control and still wins while doing roughly half the multiply work.

## Original item 2 follow-up — scaled caller-owned Tensor GEMM

Source finding: the view-aware GEMM tranche still always allocated a result and
hard-coded `alpha=1`, `beta=0`. Iterative kernels therefore could not retain an
accumulator, reuse storage, or express a fused scaled update even though CBLAS
already supports all three.

Retained API: `left.matmul_into(right, out, alpha, beta)` for CPU f32/f64. Packed
slices and zero-copy transpose inputs retain their offsets/transpose flags; a
packed row-major output may also have a nonzero offset. The output may not alias
either input. General-stride inputs materialize once through the existing
fallback, while unsupported output layouts fail explicitly.

Correctness: `spec/core/tensor_cpu_ops_spec.w` passes 36/36, covering f64
alpha/beta, an offset output with untouched guards, returned output identity,
transpose input, and f32. The CPU operation and view-GEMM campaign oracles pass,
and the Accelerate bridge passes focused C syntax.

Five release samples at transposed-view 64x64 GEMM, 10,000 calls each:

| path | range | median |
| --- | ---: | ---: |
| fresh result per `matmul` | 5.15-6.67 us | 5.93 us |
| caller-owned `matmul_into` | 1.92-4.99 us | 2.87 us |

Retained: 2.1x at the median. Large GEMMs naturally amortize allocation and
object setup; this API targets repeated small/medium products and, unlike a
private empty allocator, gives callers an explicit ownership contract.

## Original item 5 follow-up — Cholesky factor and batched RHS

This tranche extends the retained dense-factor lifetime beyond single-RHS LU.
`DenseLUFactor.solve_many[_into]` calls one `dgetrs` with all right-hand sides;
`LinAlg.factor_cholesky` returns a read-only `DenseCholeskyFactor` with matching
single- and batched-RHS methods backed by `dpotrf`/`dpotrs`. The caller-owned
forms copy only the RHS into output storage; factor storage is shared read-only
and never rebuilt during a solve.

Correctness: `spec/core/linalg_lu_factor_spec.w` passes 15/15, including LU and
Cholesky list/typed-array batches, residuals, returned-output identity, singular
LU, nonsquare input, RHS shape, and non-SPD Cholesky failures. The spec remains
classified in its focused lane. The Accelerate bridge passes focused C syntax;
the portable bridge mirrors the Fortran ABI but cannot be syntax-checked on this
host because OpenBLAS headers/libraries are not installed.

Five matched release samples at dimension 256, 32 RHS, and 100 solve batches
(microseconds per operation):

| sample | LU build | Cholesky build | LU sequential | LU batch | Cholesky sequential | Cholesky batch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1441.81 | 1127.67 | 801.80 | 165.71 | 868.23 | 204.04 |
| 2 | 1348.11 | 1258.01 | 787.08 | 182.14 | 924.64 | 199.64 |
| 3 | 1419.24 | 1210.21 | 856.42 | 212.99 | 910.82 | 202.40 |
| 4 | 1365.75 | 1340.36 | 879.15 | 201.97 | 915.27 | 198.05 |
| 5 | 1489.29 | 1211.05 | 859.78 | 200.93 | 886.82 | 176.32 |

Median LU batching improves 856.42 to 200.93 us (4.26x); Cholesky batching
improves 910.82 to 199.64 us (4.56x). On this SPD workload, Cholesky factor
construction is 1419.24 to 1211.05 us (1.17x). Retained. This explicitly closes
the Cholesky and batched-RHS portions of original item 5; compact reusable QR
reflectors are measured in the separate QR-factor tranche below.

## Original items 5 and 8 follow-up — compact reusable QR factor

`LinAlg.factor_qr` now retains `dgeqrf`'s column-major Householder vectors,
upper-triangular R, and tau without forming Q. `DenseQRFactor.solve[_into]`
applies Q-transpose with `dormqr` and solves R with `dtrtrs`; the batched form
does both operations over all RHS columns in one LAPACK call. Factors remain
read-only and caller-owned output provides the m-element LAPACK workspace.
Rank-deficient and underdetermined matrices fail explicitly.

Correctness: `spec/core/linalg_least_squares_spec.w` passes 10/10 for the known
least-squares oracle, dimensions, list and caller-owned solves, list and typed
batches, rank failure, underdetermined failure, and RHS mismatch. The
Accelerate bridge passes focused C syntax.

Five matched release samples at 512x64, with 100 single solves and 32 RHS per
batch (microseconds per operation):

| sample | factor build | refactor with `dgelsy` | retained `solve_into` | 32 sequential solves | 32-RHS LAPACK batch |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 1132.34 | 1192.21 | 69.71 | 1921.35 | 422.67 |
| 2 | 976.62 | 1187.25 | 58.85 | 1888.68 | 385.46 |
| 3 | 984.69 | 1165.92 | 56.45 | 1943.54 | 371.87 |
| 4 | 994.61 | 1154.79 | 60.29 | 1917.87 | 421.92 |
| 5 | 958.97 | 1154.37 | 62.74 | 1941.95 | 392.92 |

Retained. Median repeated single-RHS time improves from 1165.92 to 60.29 us
(19.3x) by hoisting factorization; one 32-RHS solve improves 1921.35 to 392.92
us (4.89x) over repeated `dormqr`/`dtrtrs`. This closes original item 5's
QRFactor and batched-RHS requirements and original item 8's compact-reflector
requirement; the existing one-shot `least_squares` keeps pivoted `dgelsy` for
rank-revealing behavior.

## Original item 4 closeout — cooperative GPU row softmax

Source finding: `softmax_rows_f32` assigned one GPU thread to an entire row.
That thread made three serial passes over all columns (maximum, exponent/sum,
normalization). Row parallelism hid this at short widths, but attention-like
wide rows left each row's reduction and transcendental work serial.

The retained kernel assigns one threadgroup to a row. Threads stride over the
columns, use `simd_max`/`simd_sum`, combine SIMD-group partials through 32
threadgroup floats, and normalize cooperatively. The old kernel remains the
short-row lane. A five-sample paired sweep calibrated the policy to serial for
fewer than 256 columns, 128 threads at 256 columns, 256 threads through 4096,
and 512 above 4096. The parallel pipeline is built lazily so elementwise-only
and short-row workloads do not pay its construction cost.

Representative medians from the matched Tensor workload (fresh result
allocation and synchronous dispatch included, pipeline compilation warmed):

| shape | original serial row | cooperative policy | speedup |
| --- | ---: | ---: | ---: |
| 1x256 | 216 us | 184 us | 1.17x |
| 16x1024 | 334 us | 178 us | 1.88x |
| 256x2048 | 737 us | 391 us | 1.88x |
| 1024x8192 | 4,968 us | 3,156 us | 1.57x |
| 4096x256 | 607 us | 539 us | 1.13x |
| 16384x256 | 1,927 us | 1,548 us | 1.25x |

The sweep also covered 1, 16, 256, and 1024 rows at widths 64 through 8192,
plus 4096/16384-row saturation probes. Gains below 256 columns narrowed to
1-10% and varied with dispatch noise, so those shapes deliberately preserve
the existing serial route rather than claiming a fragile crossover.

Correctness compares both GPU kernels with a double-precision stable-softmax
reference. Across 3x33, 7x1537, 128x1024, and 4x8192 probes, the cooperative
maximum absolute error was at most 2.65e-8 and row-sum error at most 1.45e-7;
serial/cooperative disagreement was at most 2.98e-8. The new focused GPU spec
passes 4/4 at both sides of the selector, and the CPU Tensor spec remains
36/36. Retained.
