# Tungsten perf30 closeout ledger

Baseline: `43642a9de2dca0ab455cef7e49deb69b70d86066`

All measurements are local, release-compiled, matched before/after runs on the
same Apple Silicon host. A production change is retained only when its focused
correctness oracle passes. “Rejected” means the tested implementation was
removed; “deferred” means the benchmark exposed a larger ownership or semantic
prerequisite and no speculative production code remains.

| # | Requested improvement | Outcome | Matched benchmark evidence | Correctness / disposition |
|---:|---|---|---|---|
| 1 | Correct CPU Tensor output allocation | **Retained** | The old CPU unary/reduction/scale path raised before timing. After backend-aware allocation it passes; removing the redundant demand-zero `mmap` touch changed 2,000 256x256 zero allocations from 0.82–0.87 s to 0.00–0.01 s, 1,000 GEMMs from 0.57–0.61 s to 0.17–0.25 s, and 1,000 `exp` calls from 0.50–0.54 s to 0.12–0.14 s. | CPU Tensor operation spec and scientific Tensor smoke pass. Public zero semantics are unchanged. |
| 2 | View-aware Tensor GEMM and caller-owned scaled output | **Retained** | A 200-call logical 192x128 by 128x160 transpose-view workload changed from 1.02–1.03 s to 0.04–0.05 s. For 10,000 transposed 64x64 calls, fresh output is 5.93 us median and `matmul_into` 2.87 us (2.1x). | Offset and transpose views, f32/f64, alpha/beta, offset outputs, guards, and alias rejection pass 36 focused checks. |
| 3 | Own/cache Tensor metadata and remove repeated layout work | **Partially retained** | Five million `size + contiguous?` iterations changed from 110 ns to 75 ns median (31.8%). | Packed strides are now O(rank), layout checks allocate no Array, and `to_rows` hoists the check. A persistent metadata cache was rejected while public shape/stride Arrays remain mutable. |
| 4 | Dedicated reductions and normalization kernels | **Retained** | Whole f64 sums change from 9.4 ms to 37–38 us each (about 250x); packed last-axis sum+max pairs change from 12.0 ms to 56–58 us (about 210x). Cooperative GPU row softmax changes 216→184 us at 1x256 (1.17x), 334→178 us at 16x1024 (1.88x), 737→391 us at 256x2048 (1.88x), and 4,968→3,156 us at 1024x8192 (1.57x). | CPU loops preserve exact left-fold cancellation, first-NaN, and signed-zero behavior. GPU max error is 2.65e-8, row-sum error 1.45e-7; 4 GPU and 36 CPU Tensor checks pass. Serial GPU remains selected below 256 columns. |
| 5 | Reusable dense LU/QR/Cholesky factors and batched RHS | **Retained** | Reusing LU at 256x256 changes 1,271 us/refactored solve to 32 us/list solve (39.7x) or 27 us/`solve_into` (47.1x). Across 32 RHS, one batched `dgetrs` changes 856.42 to 200.93 us (4.26x), and batched `dpotrs` changes 910.82 to 199.64 us (4.56x). At 512x64, retained compact QR changes one-shot `dgelsy` refactor 1,165.92 us to 60.29 us (19.3x); 32 sequential solves 1,921.35 us to one batched 392.92 us (4.89x). | Factors copy source storage, retain compact LAPACK data, are read-only during solves, and pass 15 LU/Cholesky plus 10 QR/least-squares focused checks. |
| 6 | Scalar-replace sealed fixed numeric values | **Measured; compiler-wide representation change deferred** | Mat3 value/into/raw medians are 88.9/29.6/19.9 ns; Mat4 are 94.2/35.3/20.2 ns. Existing caller-owned kernels are 2.7–3.0x faster. | LLVM confirms value-returning paths still allocate while `mul_into` does not. A Unicode method mangling bug that blocked all Vec/Mat probes was fixed; operator/vector/matrix specs and compiler fixed-point gates pass. |
| 7 | Complete f64 BLAS levels 1/2 and structured level 3 | **Retained** | `ddot` ~1.2 ms to <=2 us; `dgemv` 4.7 ms to 6 us; `dscal` 1,185 to 2.44 us (486x); `dsymv` 4,801 to 16.99 us (283x); `dsyrk` 132.83 to 94.24 us (1.41x); `dtrsm` 28,776 to 160.90 us (179x). | Eight known-value f64 BLAS checks pass on the new Accelerate/OpenBLAS bridge surface. `dsyrk` intentionally writes only its contracted triangle. |
| 8 | LAPACK QR and least squares | **Retained** | Twenty 128x64 QRs change from 0.39–0.48 s to 0.04 s. The measured crossover is n=8. One hundred 512x64 fits change from 3.8 ms to 1.6 ms each (2.4x). Repeated compact-reflector solves are 19.3x faster than refactoring. | Orthogonality/reconstruction and explicit rank/shape failure specs pass. Full-rank overdetermined least squares uses pivoted QR rather than normal equations; `DenseQRFactor` keeps Householder reflectors without constructing Q. |
| 9 | SVD and symmetric eigensolvers | **Retained; `dsyev` kept after driver sweep** | Two hundred 96x96 symmetric spectra change from 0.23–0.29 s to 0.08–0.09 s; one hundred 128x64 singular spectra change from 0.10 s to 0.05 s. Five fresh-process sweeps found `dsyevd` 1.38–2.61x slower; `dsyevr` was only 1.9–4.3% faster at favorable medians, flipped sign at every tested size, and was neutral/losing at 768/1024. | Known spectra, tall/wide/rank-deficient/empty cases pass; driver deltas are <=1.16e-11. Direct `dgesdd` avoids normal equations. The unstable `dsyevr` margin did not justify a shape branch, so the production values path remains `dsyev`. |
| 10 | Replace the universal nested-list GEMM gate with shape-aware routing | **Retained** | Source commit `b0caf199` (integration `dc1e47e7`) passes the 25/25 compiled policy spec and 14/14 exact-output oracle. Every changed route retained from the alternating crossover sweep wins by 1.56–3.92x; marginal/noisy outer, row, and two-wide bands remain scalar. | Square, outer, row, column, dot, skinny, tall, and short-wide outputs match exactly. Full LTO inlines the typed integer policy leaf into `LinAlg.matmul`; assembly has direct compares/branches and no policy symbol or indirect dispatch. |
| 11 | Sparse minimum-degree buckets/heap and canonical analysis | **Retained** | Grid n=900 exact ordering changes from 6 ms to 4 ms (33%). Sweep: scan wins at n=64/144, near parity 256–324, heap wins 18% at 400 through 46% at 1600; production crossover n>=384. | Scan and lazy-heap orders are identical on the focused spec and 720 randomized graphs. Canonical symmetric adjacency is built once. |
| 12 | Persistent sparse workers/shared immutable analysis/reusable buffers | **Reusable-buffer/block tranche retained; channel pool rejected** | Eight disconnected 20x20 grids, 50 public solves: 13 ms to 9 ms (31%). Parallel `solve_into` gains are 29%, 58%, and 63% at 9,280/21,120/37,760 nnz; it loses below the calibrated 8,192-nnz gate. A literal persistent Thread/Channel pool measured 14–16 ms versus 11–12 ms and was removed. | Immutable analysis is shared; outputs/scratch are private. Exact sequential/parallel solutions match. Automatic fan-out is 2–8 components only. |
| 13 | Remove O(d^4) `Differential#+` copies | **Retained** | 120 dimension-20 full-Hessian additions: 262 ms to 5 ms (52.4x). | Checksum 844 and compiled calculus spec pass. |
| 14 | Sparse gap-Horner evaluation | **Retained** | Twelve degree-5,000 / 1,001-term evaluations: 1,701 ms to 1 ms (>850x). | Checksum 575521 and polynomial spec pass. |
| 15 | Cached flat arithmetic-circuit tapes and caller-owned/batched evaluation | **Retained** | A 402-node DAG over 2,000 evaluations changes from 150 ms to 27 ms (5.56x). Column-major caller-owned batching crosses over at batch 2 (14.320→14.020 us/eval), reaches a practical 1.383x at batch 4, and 2.393x at batch 128 (14.383→6.010 us/eval). Scalar `evaluate_into` is 1.5–5.5% slower and remains an allocation-control API, not the selected scalar fast path. | Exact checksums match. All 43 native and tree-interpreter checks pass across every opcode, non-integral Rational arithmetic, zero division, reuse/empty batches, and workspace failures. |
| 16 | Incremental approximate LLL | **Retained** | Eight dense rank-14 reductions: 925 ms to 10 ms (92.5x). | Checksum 1379, 13 steps, swap parity, and lattice-reduction spec pass. |
| 17 | Real damped Gauss-Newton/LM least squares | **Retained** | Five dimension-16 solves to <1e-10 objective: 127 ms to 3 ms (42.3x) with lower error. | Finite-difference, analytic, nonlinear, and scientific smoke checks pass. |
| 18 | Polynomial substitution plans | **Retained** | Thirty specializations of 1,152 terms into 48 groups: 36 ms to 1 ms (>36x). | Checksum 59040 plus polynomial, modular-GCD, and specialization specs pass. |
| 19 | One-construction finite-factor candidates | **Retained** | Ten thousand dense degree-20 F2 candidates: 94 ms to 15 ms (6.27x). | Checksum 211 and finite-factor spec pass. |
| 20 | Prepared finite fields and batch inversion | **Retained** | F(2^8) inverse/Frobenius sweeps: 176 ms to 48 ms (3.67x). 1,000 batches of 512 elements over F1000003: 302.2 us scalar to 36.8 us batch (8.21x); crossover is n=2. | Every inverse product/Frobenius round trip, prime/extension field, empty batch, and zero policy pass. |
| 21 | Public typed FFTPlan, real half-spectrum, output-into, 2-D scratch | **Tested plan rejected** | Six hundred n=1,024 forward/inverse pairs: 705 ms baseline, 829 ms best cached plan (17.6% slower); a lighter plan was 1,119 ms. | Identical checksum and 3.21e-11 max round-trip error. Production source was reverted; benchmark remains. Typed-call specialization/native flat buffers are prerequisites for a profitable public plan. |
| 22 | Exact algebra cleanup: Rational multiplication and polynomial Bareiss | **Retained** | Rational multiply at 128/512/2,048/8,192 bits: 2.70/7.68/15.9/53.6x. Twelve 7x7 polynomial determinants: 109 ms to 5 ms (21.8x). | Rational spec plus 29,241 exhaustive signed products pass. Bareiss matches exact z^6(z+7) and polynomial-matrix spec. |
| 23 | GPU sampling | **Measured win; deferred for full semantics** | At V=151,936/K=40/T=0.7, CPU 90–95 ms versus GPU 11–12 ms wall (7–8x), same sampled token and RNG variate. | Production repetition penalties/no-repeat bans are still CPU-side. The partial sampler was removed rather than changing generation semantics. |
| 24 | Continuous batching and MoE grouping | **Existing kernels validated; scheduler deferred** | Exact production-shape synthetic MoE crosses over at B=2. At B=8 host gains are 2.94–3.79x shared-expert and 2.58–2.91x disjoint-expert; GPU gains 1.20–1.38x and 1.09–1.17x. | Outputs match exactly. Safe serving needs per-request recurrent/KV/RNG state; no single-state scheduler was promoted. |
| 25 | Reusable Metal dispatch plans | **Rejected** | Isolated dispatch-plan smoke passed, but the five-token FlashNext fixture produced token 220 instead of 11751 and left a driver-stuck control buffer. | Prototype fully reverted. Per-step differential taps and explicit lifecycle/error handling are prerequisites. |
| 26 | Tiled online-softmax SDPA | **Rejected after end-to-end gate** | Synthetic max error <=6.76e-9 and GPU micro neutral to ~5% faster; exact-ID 638-token Qwen3.8 prefill regressed median 26,218 to 26,790 ms (+2.18%). | Candidate removed because whole-model performance lost despite numerical parity. |
| 27 | Mamba fusion | **Already present in FlashNext; Qwen port rejected** | Qwen3.8 port preserves 128 exact IDs, but whole-model timing changes sign at 8/32/64 tokens; the apparent 128-token win is thermally throttled. | Port reverted. Shipping FlashNext already fuses conv+split and g+beta. |
| 28 | Bulk FlashNext PLE gather | **Retained** | Original 10,000-call 16x160 runs changed 286–288 ms scalar to 8–9 ms bulk (31–36x). Commit `c2a5cd1e` corrected sentinel decoding and measured 291/8 ms (36x), 290/11 ms (26x), and 290/9 ms (32x). After the upstream width-N merge, three fresh processes measured 302/9 ms (33x), 303/10 ms (30x), and 293/11 ms (26x). | Hidden/logit/debug dumps and generated IDs match byte-for-byte. The exhaustive smoke matches all 256 FP8 encodings, including `0x7f`/`0xff` as zero. The merged mixed path reproduced 119/119 oracle tokens at widths 2, 4, and 8, exercising bulk base-zero plus offset-aware later rows. |
| 29 | Persistent MTL4 prefill graph | **Winning submission shape already present** | Parity-checked 48-stage proxy: one command buffer 0.245/0.295 ms; four buffers 0.670/0.690 ms (2.34–2.73x slower); 48 buffers 7.10 ms (24–29x slower). | Optimized target paths already encode one target pass in one command buffer. Older host-readback path needs semantic restructuring first. |
| 30 | Fused router/top-k | **Rejected** | Exact packed top-8 IDs/weights, but 48 layers take 11.5785 ms fused versus 3.5404 ms separate (0.306x). | Prototype removed. One large threadgroup destroys router-matvec occupancy; a different inter-group algorithm is required. |

Detailed command lines, sample tables, and workload construction live in:

- `benchmarks/linalg/perf30-dense-campaign.md`
- `benchmarks/linalg/tungsten/perf30_sparse_results.md`
- `benchmarks/core_math_perf30/results.md`
- `bits/tungsten-llama/docs/perf30-campaign-2026-09-01.md`

## Correctness-hardening follow-up

A post-campaign integration audit found edge contracts that the focused
performance oracles did not cover. The responses below are integration
follow-ups, not evidence contained in the original retained performance
commits. All responses below are committed on the integration branch. The key
follow-up commits are `c2a5cd1e`, `49359070`, `008a0daf`, and `b051b18f`;
the final branch revision is reported by the landing handoff.

| Audit area | Integration response | Final evidence |
|---|---|---|
| Numeric scalar ABI | Coerce ordinary integer `alpha`/`beta` arguments once at the Core BLAS and Tensor boundaries before native f64 decoding. | Integer-scalar DAXPY, DSCAL, DSYRK, DTRSM, and f32/f64 `matmul_into` checks pass in both required lanes. |
| BLAS and factor aliasing | Reject byte-range overlap for GEMM, GEMV, SYMV, SYRK, and TRSM in both native bridges; use overlap-safe typed-array moves for LU, Cholesky, and QR `solve_into`/batched copies. | Same-buffer and shifted-slice checks pass on Accelerate. OpenBLAS headers are unavailable on this host, so equivalent OpenBLAS CI remains the only platform follow-up. |
| Compiler and interpreter registration | Mark the new mutating calls and their transitive callers impure, add tree-interpreter dispatch, and autoload all three dense-factor classes. | Native and interpreted BLAS/factor tests pass; the exact compiler fixed point, parser parity, acid test, and WIRE direct-call audit are green. |
| FP8 decoder contract | Match FlashNext/NVFP4 sentinel semantics and check all 256 encodings, including `0x7f` and `0xff` as zero. | The exact closeout compiler passes the exhaustive smoke; corrected throughput remains 26-33x in three fresh merged-tree processes, and width 2/4/8 each reproduces 119/119 oracle tokens. |
| CPU f32 backend selection | Require a non-CPU Metal device for wide elementwise and row-softmax GPU routing. This is baseline hardening, not a perf30 regression. | Large CPU-f32 binop and softmax backend/value checks pass. |
| Concurrent Core caches | Publish substitution plans and circuit tapes as one key/value cache pair and retain the chosen value locally. | Synchronized multithreaded plan/tape checks, single-thread checksums, and matched cache-hit timing pass. |

At compiler/runtime revision `b051b18f`, the freshly bootstrapped compiler is
9,622,928 bytes with SHA-256
`04a6c84eb3e0a4c85a0934e8a75cdb261d25b102e0ff483b78fb6d82cefdcf16`.
Its stage-1 and stage-2 LLVM are byte-identical with SHA-256
`86dd68dc665708ff4c0f7f00fc344f81ef01257541f7c79c1e51d868328a8475`.
Fast/canonical parser parity, acid, native/interpreted impurity tests,
Rational/operator/vector/matrix lanes, NaN-box tests, and the C-call verifier
(351 declarations, 714 foreign targets) all pass. The final Qwen smoke also
passes tokenizer round trips, all 256 FP8 encodings, and 119/119 width-2 mixed
bulk/offset oracle tokens.

The closeout `bundle exec rake` rebuild reaches a fixed point and its Ruby
suite reports 4,139 examples, 0 failures, and 34 pending. All 581 tracked
Tungsten specs are now classified. The default native/interpreted battery still
exits nonzero on 12 inherited failures. An exact `527930da` baseline run has the
same 12 plus four additional compile failures (`hypercomplex_mul`, `matrix`,
`operator_overload`, and `vector`); the candidate-only failure set is empty.
The root-only `mutex` and `http` failures also reproduce in focused exact-
baseline runs. Thus the full root command is not globally green, but its
remaining red set is a strict subset of the clean baseline rather than a
perf30 regression.
