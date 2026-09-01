# Perf30 dense / Tensor / LinAlg campaign

Baseline revision: `43642a9de2dca0ab455cef7e49deb69b70d86066`

Branch: `codex/perf30-dense`

Host: Apple Silicon macOS; release builds; wall-clock samples are matched within each item.

This journal is append-only by campaign item. Each retained change has a focused correctness oracle, alternating or multi-sample timings, and its own commit. Millisecond-resolution results are reported as directional when the measured interval is too short for a reliable ratio.

## Item 9 — CPU Tensor result allocation

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

## Item 2 — view-aware CPU GEMM

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

## Item 3 — allocation-free Tensor layout metadata

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

## Item 7 — packed CPU reductions

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

Long candidate-only runs make the sub-centisecond cells measurable: 10,000
whole sums take 0.04 s (at most 4 us/sum including launch) and 10,000
last-axis sum+max pairs take 0.37 s (37 us/pair). The matched parent's medians
are 9.4 ms/sum and 12.0 ms/pair respectively.

Retained. Packed CPU f64 reductions use vDSP over the existing buffer and
offset; f32 sum preserves the prior double accumulator. A single bridge call
handles all rows of a packed last-axis reduction. General strided and
non-last-axis reductions retain the reference path. Max retains the prior
ordered comparison semantics (including first-element NaN and signed-zero
behavior) rather than substituting a differently specified vector max.

## Item 8 — packed CPU unary vector path

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

## Item 4 — double-precision BLAS level 1/2

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
