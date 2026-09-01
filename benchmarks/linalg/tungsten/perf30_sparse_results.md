# Perf30 sparse ordering and block-factor results

Baseline: `43642a9d`

Host: Apple M5 Max, macOS 26.6.2

Compiler: release build from the same baseline

Correctness: `spec/core/sparse_factor_spec.w`, including exact scan/heap order
and forced-parallel `solve_into` agreement with the whole factor.

## Exact minimum-degree ordering

The candidate replaces the O(n) live-vertex minimum scan with a lazy binary
heap keyed by `(degree, vertex)`, preserving the baseline's exact deterministic
tie-break. `SparseAnalysis` also retains one canonical symmetric adjacency.

Matched ABBA runs of `sparse_bench.w`, grid n=900:

| lane | samples (ms/order) | median |
|---|---:|---:|
| baseline scan | 6, 6, 6, 6 | 6 |
| candidate heap | 4, 4, 4, 4 | 4 |

Result: **33% lower ordering time**, identical order and predicted fill 10,351.

The direct crossover harness `sparse_ordering_bench.w` showed scan ahead at
n=64 and n=144, near parity around n=256-324, heap 18% ahead at n=400, 24% at
n=576, 40% at n=900, and 46% at n=1600. Production conservatively selects
the heap at n>=384.

## Component-blocked factor/solve

The retained candidate caches each component's f64 RHS/result buffers, adds a
caller-owned `solve_into`, joins workers directly instead of allocating a
Channel per phase, caps automatic fan-out at eight components, and routes by
measured total nnz.

Matched ABBA public `solve` runs, eight disconnected 20x20 grids, 50 solves:

| lane | samples (ms/50) | median |
|---|---:|---:|
| baseline | 13, 13, 13, 13 | 13 |
| candidate | 10, 9, 9, 9 | 9 |

Result: **31% lower repeated-solve time**, identical solution.

`sparse_block_bench.w` isolates caller-owned output and scheduling:

| shape | sequential us/solve | parallel us/solve | parallel gain |
|---|---:|---:|---:|
| 8 x 20x20, nnz=9,280 | 229-234 | 147-180 | 29% median |
| 8 x 30x30, nnz=21,120 | 504-505 | 210-216 | 58% |
| 8 x 40x40, nnz=37,760 | 877-893 | 323-325 | 63% |

Parallel lost at nnz=5,160, was noisy/near parity at 5,888, and won above the
next tested band. The automatic policy therefore uses 2-8 components and
`nnz >= 8192`; callers can force either lane for calibrated deployments.

## Rejected experiment

A literal persistent Tungsten `Thread`/`Channel` worker per component reused
scratch but took 14-16 ms for the 50-solve workload versus 11-12 ms for the
baseline. Channel handoff dominated these small solves, so that implementation
was removed rather than promoted. A future native runtime task descriptor over
the existing arithmetic pool may still be worthwhile for substantially larger
components.
