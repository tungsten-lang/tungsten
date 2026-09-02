# Tungsten performance

Performance changes in Tungsten are accepted on measured workloads, not on
instruction-count intuition alone. A production optimization must preserve the
public contract, beat the incumbent on the shape where it is selected, and
remain neutral outside that shape. Narrow kernel wins do not override an
end-to-end regression.

## Measurement contract

- Compare the baseline and candidate on the same machine, build profile, input,
  warmup, and sampling protocol. Record every sample, not only the minimum.
- Run a correctness oracle before trusting timing. Exact arithmetic, generated
  token IDs, aliasing behavior, signed zero, NaNs, failure modes, and mutation
  semantics are part of performance correctness.
- Calibrate shape thresholds with an alternating sweep around the crossover.
  Keep the incumbent on ties, noisy margins, and unmeasured shapes.
- Profile the whole workload. Assembly and kernel timings explain a result, but
  the end-to-end workload decides whether it ships.
- Rebuild the self-hosted compiler after compiler/runtime changes and require
  stage-1/stage-2 LLVM identity. Keep native and interpreted lanes aligned.
- Revert prototypes that lose or change semantics. Preserve their measurements
  so the same dead end is not rediscovered without a new prerequisite.

The repository's performance CI methodology is documented in
[`benchmarks/performance/README.md`](../benchmarks/performance/README.md). A worked
example of profile-led optimization is
[`articles/tungsten-performance-engineering.md`](articles/tungsten-performance-engineering.md).

## 2026-09-01 perf30 campaign

The perf30 campaign evaluated thirty changes across Tensor, dense and sparse
linear algebra, Core mathematics, the compiler/runtime boundary, and
`bits/tungsten-llama`. Every item has a matched benchmark and an explicit
retained, partial, rejected, deferred, or already-present disposition in the
[`perf30 closeout ledger`](../benchmarks/perf30-results-2026-09-01.md).

Representative retained results:

| Area | Change | Matched result |
|---|---|---:|
| Tensor | View-aware GEMM and caller-owned output | 20-25x for a transpose-view workload; 2.1x for `matmul_into` at 64x64 |
| Tensor | Packed CPU reductions | about 210-250x |
| Tensor | Cooperative GPU row softmax | 1.17-1.88x on selected wide rows |
| Dense linear algebra | Reusable LU factors | 39.7-47.1x versus refactoring each solve |
| Dense linear algebra | Batched LU, Cholesky, and QR solves | 4.26-4.89x |
| Dense linear algebra | Shape-aware nested-list GEMM routing | 1.56-3.92x on every newly selected band |
| BLAS | f64 level 1/2 and structured level 3 bridge | 1.41-486x on the measured kernels |
| Sparse linear algebra | Heap minimum-degree ordering | 33% at grid n=900; selected from n>=384 |
| Sparse linear algebra | Reused analysis/buffers and component parallelism | 31% end-to-end; 29-63% on selected larger solves |
| Calculus | Copy-free `Differential#+` | 52.4x |
| Algebra | Gap-Horner sparse polynomial evaluation | more than 850x |
| Algebra | Incremental approximate LLL | 92.5x |
| Optimization | Damped Gauss-Newton/Levenberg-Marquardt | 42.3x |
| Algebra | Polynomial substitution plans | more than 36x |
| Algebra | Prepared finite fields and batch inversion | 3.67x and 8.21x |
| Exact arithmetic | Reduced-gcd Rational multiply | 2.70-53.6x across 128-8192-bit inputs |
| Exact linear algebra | Polynomial Bareiss determinant | 21.8x |
| FlashNext | Bulk FP8 PLE gather | 26-33x after sentinel correction and width-N integration |

Detailed workload construction and raw samples are in:

- [`benchmarks/linalg/perf30-dense-campaign.md`](../benchmarks/linalg/perf30-dense-campaign.md)
- [`benchmarks/linalg/tungsten/perf30_sparse_results.md`](../benchmarks/linalg/tungsten/perf30_sparse_results.md)
- [`benchmarks/core_math_perf30/results.md`](../benchmarks/core_math_perf30/results.md)
- [`bits/tungsten-llama/docs/perf30-campaign-2026-09-01.md`](../bits/tungsten-llama/docs/perf30-campaign-2026-09-01.md)

The campaign also hardened optimized boundaries: integer BLAS scalars are
coerced once, overlapping outputs are rejected or copied safely, mutating
native calls propagate impurity through direct helper graphs, concurrent Core
caches publish key/value pairs atomically, FP8 sentinel bytes match the
canonical decoder, and `Nil` has a usable nonzero dynamic-dispatch key.

## Negative results and prerequisites

These results should be treated as routing constraints, not unfinished wins:

- The public `FFTPlan` prototype was 17.6% slower at n=1024. Revisit only after
  the dynamic-to-typed call boundary and flat-buffer ownership make reuse
  cheaper than dispatch.
- `dsyevr` produced an unstable 1.9-4.3% favorable margin and lost at other
  sizes; `dsyev` remains the symmetric-values driver.
- A partial GPU sampler was 7-8x faster but omitted repetition and no-repeat
  semantics. It was removed rather than changing generation behavior.
- Synthetic tiled SDPA was numerically sound but regressed exact-ID Qwen3.8
  prefill by 2.18% end to end.
- The tested Qwen Mamba fusion changed sign across sequence lengths. FlashNext
  already contains the useful fused kernels.
- A reusable Metal dispatch plan failed the model parity/lifecycle gate.
- The tested fused router/top-k implementation ran at 0.306x because one large
  threadgroup destroyed router-matvec occupancy.
- A persistent sparse Thread/Channel pool was slower than calibrated static
  fan-out. Reuse becomes interesting only with a lower-overhead executor.
- Persistent Tensor metadata caching is unsafe while public shape and stride
  arrays remain mutable.

## Follow-on queue

Follow-ons should introduce a new enabling mechanism rather than merely raising
the budget of a rejected experiment.

1. **Offset-aware bulk PLE gather.** Bulk FP8 gathering currently handles only
   destination offset zero; every later width-N row falls back to 2,560 scalar
   Metal writes. Extend the native helper with a checked destination offset.
   Gate on all 256 FP8 encodings at several offsets, width 2/4/8 exact IDs,
   width 64/512 hidden and logit parity, and 32k/100k prefill ABBA.
2. **Native Tensor stride kernels.** Replace the remaining coordinate-Array
   loops for common broadcasts and non-last-axis reductions with offset/stride-
   aware f32/f64 kernels. Benchmark packed scale/add-mut, `[1024,4096] + [4096]`,
   and axis-0 sum/max separately; require view, alias, NaN, signed-zero, and
   interpreter parity before promoting each lane.
3. **Generated runtime-kind AST field lookup.** Each AST field read still does
   runtime-kind discovery, schema lookup, and the final arena read. Generate one
   `field-id × runtime-kind` offset table and matching native/C-VM helper.
   Benchmark parser/lowering-heavy self-compiles and require exact LLVM,
   sidemaps, parser parity, and compiler fixed-point identity.
4. **Bulk WIRE constructors with exact capacity.** Generated instruction
   constructors allocate and cross a checked boundary once per field, while all
   opcodes reserve six spare pairs. Generate opcode-specific bulk builders and
   conservative capacity. Measure bootstrap/self-compile time, retired
   instructions, RSS, and arena words; require graph round trips, batch-vs-solo
   identity, sidemaps, and fixed point.
5. **Leading-dimension-aware Tensor GEMM.** Extend the BLAS bridge with
   `lda`/`ldb`/`ldc` so padded rank-2 slices do not materialize through
   `contiguous`. Sweep repeated 64/128/256 products from padded parents,
   including offset and transpose views, with sentinel and overlap checks.
6. **Fused lm-head and greedy argmax.** Greedy decode currently materializes
   all 248,320 logits and then reduces them in two more dispatches. Emit exact
   `(value,id)` partial winners directly, retaining full logits for sampling and
   debug. Gate lowest-ID ties, NaNs, 119/500 exact IDs, plain/MTP ABBA, and
   dispatch/bandwidth traces.
7. **Tensor-native reusable factors.** Keep Tensor as the aligned-storage owner
   and add direct Tensor/raw-storage LU, Cholesky, and QR entry points plus
   factor-derived `slogdet`. Compare one factorization plus 1/2/4/16/32 RHS
   against `Tensor.to_rows` and separate factor/log-determinant calls.
8. **Prepared sparse SpMV.** Add an explicitly owned f32/f64
   `SparseMatvecPlan` with caller-owned output; the current accelerated path
   rebuilds and destroys its native sparse matrix on every call. Benchmark
   1,000 repeated grid, banded, empty-row, and irregular rectangular SpMVs;
   require randomized CSR parity, mutation isolation, and idempotent release.
9. **Width-N GPU RoPE setup.** `forward_multi` still computes trigonometry on
   the host and performs two bridge writes per table element. Build `(pos0,n)`
   tables in one GPU kernel. Require table parity through position 262k,
   width-N exact IDs, 512-token setup timing, and long-context ABBA.
10. **Shared WIRE edge index and SCC-wave hashing.** Escape analysis, content
    hashing, and reachability independently rebuild related graphs. Construct
    one immutable post-lowering index, expose consumer-specific edge classes,
    and hash independent SCC waves concurrently with deterministic commit.
    Require identical escape/live/hash results across 1/2/4/8 jobs, recursive
    SCC coverage, batch-vs-solo identity, and fixed point.
11. **Sparse time-stepping operations.** Add `SparseFactor.solve_many_into` and
    `SparseBlockFactor.refactor`, retaining the global-to-component value map.
    Measure 1/2/8/32 RHS and fifty value-update/refactor/solve rounds against
    rebuilding the block factor; preserve residual, release, and single-flight
    scratch contracts.
12. **Offline consolidated metallib and pipeline archive.** The model runner
    compiles more than twenty Metal sources per process despite existing
    metallib/archive support. Key an offline artifact by source hash, GPU,
    OS/SDK, and math mode, with source fallback. Measure ten cold/warm process
    starts to first token and require exact IDs plus stale/corrupt recovery.

Longer-range bets are content-addressed copy-on-write prompt-prefix snapshots,
full-semantics GPU sampling state, batched Polynomial evaluation plans, and
fail-closed stack/scalar promotion for non-escaping Mat3/Mat4 values. Each needs
an ownership or semantic prerequisite before timing alone can justify it.

## Closeout validation

The perf30 closeout used a freshly bootstrapped compiler with byte-identical
stage-1/stage-2 LLVM, fast/canonical parser parity, native and interpreted
focused suites, 351 registered C-call declarations covering 714 foreign
targets, exhaustive 256-byte FP8 decoding, and exact Qwen width-N token parity.
The Ruby integration suite reported 4,139 examples, 0 failures, and 34 pending.

The broader native spec battery retained twelve failures already present at the
campaign baseline and introduced no candidate-only failure; the candidate
removed four baseline-only compile failures. The root command therefore was
not globally green at that historical closeout, but its remaining failure set
was a strict subset of the exact baseline. See the closeout ledger for the
failure-set comparison and platform caveats, including unavailable local
OpenBLAS headers.

Before landing, the campaign was merged with the later FlashNext MTP/QSA main
line and revalidated: compiler stage-1/stage-2 LLVM identity, fast/canonical
parser parity, acid, 351/714 C-call contracts, all 581 spec classifications,
tokenizer round trips, exhaustive FP8 decoding, and the 119-token width-2 mixed
PLE path all passed with zero token mismatches.

## 2026-09-02 SSI sparse-ordering transfer

The SSI transfer campaign added allocation-free symbolic rescoring, immutable
typed COO reuse, exact small-window search, optional deterministic ordering
families, and boundary-aware elimination-tree subtree refinement. The strongest
algorithmic result came from keeping a subtree's active separator vertices as
read-only terminals: exact flops fell 3.23-5.19% on the tested grid, bridge,
and disconnected-block shapes. The lane is still globally rescored before
acceptance and has a hard cap on its per-worker dense bitsets.

The lower-level changes also moved end-to-end search: reusable score buffers
removed more than 99% of allocations in annealing, the exact native u32 reducer
was 4.5-5.5x faster than the Tungsten reduction at 100k counts, and typed COO
reuse improved individual ordering lanes by 0.5-9.5%. A 64 MiB core-lift guard
saved 69.02 MiB peak RSS on a 24k-vertex band without changing the order or
score.

Follow-on profiling found that RGSUB's coordinator spent 97.2% of sampled
ticks waiting for useful worker computation, but four-job waves launched more
than 105 short-lived workers per second. Phase-wide immutable job sharing plus
a CPU-scaled, 128 MiB scratch-capped executor reduced structured-shape RGSUB
time by 24-30% across 2.5M-20M word budgets. Raw-i64 bitset count returns
removed boxed call results (2.54-4.59x in the kernel benchmark and 0.55-2.24%
end to end across RGSUB shapes), while etree-postorder relabeling removed a
duplicate symbolic traversal and cut isolated setup by 8-15% on the principal
shapes. The ordinary portfolio now uses one concentrated RGSUB round; the
quality-focused direct lane keeps the independently useful macro round. Exact
proposal acceptance also mutates the coordinator-owned order in place with a
reusable undo segment; this removed 1-8% of allocation bytes and improved the
copy-heavy tested shapes by up to 3.61% without changing any exact result.
Directly allocating proposal-local identity seeds as typed u32 buffers removed
another 61-64 allocations on grid-55/blocks-22 and improved the principal
structured cases by 2.31-3.57%; 15-run neutral-shape checks stayed within
0.11%, and 44 shape/stream comparisons retained identical exact results.
The reusable scoring workspace is protected by a per-analysis mutex for
shared callers; nine-run RGSUB deltas stayed between -0.41% and +0.69%, while
an eight-thread interleaving regression verified owned and scalar score views.

An exact watcher-MINL lane is also available as `best_watch`. Its fill-edge
witness queue found small additional flop wins on bridge-30 and random-750,
but remains opt-in because matched time was neutral. The watcher candidate is
merged at the end of the historical pipeline, preventing its alternate basin
from perturbing later descents unless the final exact score is better.

RCM, Sloan, structural-pool diversity, broad threaded relabeling, and an
in-core native bitset-call substitution did not pass their matched gates and
remain opt-in or reverted. Full commands, shape-by-shape measurements, exact
fixtures, and the keep/reject ledger are in the
[`SSI ordering transfer results`](../benchmarks/linalg/tungsten/ssi_ordering_results_2026-09-02.md).
