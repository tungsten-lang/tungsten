# Core Math Perf30 Results

Baseline commit: `43642a9de2dca0ab455cef7e49deb69b70d86066`

All timings are compiled native Tungsten wall-clock measurements on the same
local host. Each row records the median of repeated process runs unless noted.
Correctness is checked by the benchmark checksum and the focused Core spec.

| Item | Workload | Before | After | Result | Correctness |
|---|---|---:|---:|---|---|
| 13. Differential add accessor hoist | 120 additions, dimension 20, full Hessian | 262 ms | 5 ms | retained, 52.4x | checksum `844`; compiled `spec/core/calculus_spec.w` passed |
| 14. Sparse gap-Horner | 12 evaluations, degree 5000, 1001 terms over F_1000003 | 1701 ms | 1 ms | retained, >850x | checksum `575521`; compiled `spec/core/algebra_polynomial_spec.w` passed |
| 15a. Arithmetic-circuit evaluation tape | 2000 evaluations, 402-node reachable DAG | 150 ms | 27 ms | retained, 5.56x | checksum `814000`; compiled `spec/core/algebra_arithmetic_circuit_spec.w` passed |
| 15b. Caller-owned batched circuit evaluation | 49,920 evaluations of the same 402-node DAG, batch 128 | 718 ms | 300 ms | retained, 2.39x | identical checksum `20353320`; 43 focused checks passed in native and interpreter modes |
| 15c/18b. Atomic cache-pair publication | warmed 402-node circuit evaluation / 1152-term substitution | 13,355 / 32,343 ns per call | 13,168 / 31,660 ns per call | retained safety fix, 1.40% / 2.11% faster | identical checksums; synchronized old build failed, fixed build passed 11/11 concurrent runs |
| 16. Incremental approximate LLL | 8 rank-14 reductions, dense identity Gram | 925 ms | 10 ms | retained, 92.5x | checksum `1379`, 13 steps, swap parity; compiled `spec/core/algebra_lattice_reduction_spec.w` passed |
| 17. Damped Gauss-Newton/LM least squares | 5 dimension-16 linear solves to <1e-10 objective | 127 ms | 3 ms | retained, 42.3x and lower error | checksum near `374`; new FD/analytic/nonlinear spec and `spec/sci/smoke_spec.w` passed |
| 18. Polynomial substitution plan | 30 specializations, 1152 terms to 48 groups over F_65537 | 36 ms | 1 ms | retained, >36x | checksum `59040`; polynomial, modular-GCD, and specialization specs passed |
| 19. Direct finite-factor candidate construction | 10000 dense degree-20 candidates over F_2 | 94 ms | 15 ms | retained, 6.27x | checksum `211`; compiled `spec/core/algebra_finite_factor_spec.w` passed |
| 20a. Prepared inverse/Frobenius tables | 1000 complete nonzero sweeps of F_2^8 | 176 ms | 48 ms | retained, 3.67x | every inverse product and Frobenius round-trip checked; finite-field spec passed |
| 20b. Prefix/suffix batch inversion | 1000 batches of 512 nonzero elements over F_1000003 | 302.2 us | 36.8 us | retained, 8.21x | identical checksum `177900`; prime/extension/empty/zero-policy specs passed |
| 21. Reusable FFTPlan | 600 forward/inverse pairs, n=1024 | 705 ms | 829 ms | rejected, 17.6% slower | identical checksum `1150.5357900443466`; max round-trip error `3.21e-11`; Sci smoke passed |
| 22a. Coprime Rational multiplication finish | Repeated products of canonical 128/512/2048/8192-bit Rational operands | 964/4008/38313/454111 ns | 357/522/2414/8472 ns | retained, 2.70x/7.68x/15.9x/53.6x | identical checksums; compiled Rational spec plus 29,241 exhaustive signed small products passed |
| 22b. Fraction-free polynomial-matrix determinant | 12 determinants of dense 7x7 `zI + J` over F_1009 | 109 ms | 5 ms | retained, 21.8x | exact closed form `z^6(z+7)`, checksum `96`; compiled polynomial-matrix spec passed |

Rejected or deferred experiments are recorded below with their reason; they
are not left in production source.

## 15b. Caller-owned and batched arithmetic-circuit evaluation: retained

`evaluate_into` reuses one caller-owned node array. `evaluate_batch_into`
instead uses caller-owned column-major node storage, hoisting opcode dispatch
outside the point loop while preserving the cached tape's exact dynamic
arithmetic. The benchmark warms the tape and all workspaces before timing.

Five alternating matched process runs of `arithmetic_circuit_batch.w` used a
402-node reachable add DAG and approximately 50,000 evaluations per row. The
table reports median microseconds per evaluation; every lane checked the same
row checksum on every run.

| batch size | evaluations | `evaluate` | `evaluate_into` | `evaluate_batch_into` | batch speedup vs `evaluate` |
|---:|---:|---:|---:|---:|---:|
| 1 | 50,000 | 14.080 us | 14.700 us | 22.340 us | 0.630x |
| 2 | 50,000 | 14.320 us | 14.540 us | 14.020 us | 1.021x |
| 4 | 50,000 | 14.220 us | 14.800 us | 10.280 us | 1.383x |
| 8 | 50,000 | 14.420 us | 15.040 us | 8.300 us | 1.737x |
| 16 | 50,000 | 14.540 us | 14.980 us | 6.960 us | 2.089x |
| 32 | 49,984 | 14.265 us | 14.965 us | 6.402 us | 2.228x |
| 64 | 49,984 | 14.505 us | 15.285 us | 6.242 us | 2.324x |
| 128 | 49,920 | 14.383 us | 14.924 us | 6.010 us | 2.393x |

The first median win is batch 2, but its 2.1% margin is too small for a
stable policy boundary. Batch 4 is the practical crossover on this shape,
with a 27.7% elapsed-time reduction, growing to 58.2% at batch 128. The scalar
caller-owned lane is 1.5-5.5% slower on this compiler, so it is retained for
explicit allocation control rather than selected as a scalar fast path.

The focused circuit spec exercises every opcode through both new evaluators,
non-integral Rational results, division by zero, buffer reuse, empty batches,
and undersized outer, output, and inner-column workspaces. All 43 checks pass
in both compiled-native and tree-interpreter execution.

## 15c/18b. Thread-safe one-entry cache publication: retained

The polynomial substitution-plan MRU and arithmetic-circuit evaluation-tape
MRU previously published the selected key and value through two independent
instance-variable stores. A concurrent reader could therefore validate one
thread's key and then consume another thread's plan or tape. Each MRU now
publishes one immutable-by-convention `[key, value]` pair, reads that pair once,
and keeps the selected plan or tape in a local for the full calculation.

`cache_pair_single_thread.w` was compiled before and after the change with the
same compiler and `--no-lto` flags. Eleven alternating matched rounds retained
the exact checksums (`288000` polynomial terms and `20350000` circuit values).
Median cache-hit timings were:

| warmed workload | split cache | cache pair | change |
|---|---:|---:|---:|
| 1152-term polynomial substitution, 48 output groups | 32,343 ns/call | 31,660 ns/call | 2.11% faster |
| 402-node arithmetic-circuit evaluation | 13,355 ns/call | 13,168 ns/call | 1.40% faster |

The deterministic regression starts nine native threads behind one atomic
gate, assigns three distinct plan/tape keys, and performs 1,200 exact plan,
tape, substitution, and evaluation checks per worker. The old split-cache
binary failed its first synchronized run at worker 0. The fixed binary passed
11 consecutive runs (118,800 worker-iterations) with both cache families
checked independently.

## 20b. Prefix/suffix finite-field inversion: retained

`FiniteField#batch_inverse` stores inclusive prefix products in its output,
performs one field inversion, then overwrites the prefixes in reverse. For a
batch of size `n`, it replaces `n` exponentiations with one exponentiation and
`3(n-1)` multiplications; zero retains scalar `inverse`'s loud failure policy.

Five alternating 1,000-round samples over F_1000003 at batch size 512 had a
scalar median of 302.2 us and a batch median of 36.8 us (8.21x). Every checksum
was `177900`. A candidate-only size sweep found the expected fixed-cost
crossover: size 1 was 0.496 us scalar versus 0.527 us batch, while size 2 was
1.000 us versus 0.607 us and every tested size through 512 favored batching.
The finite-field spec now covers prime and extension fields, empty batches,
and zero rejection; all checks pass.

## 21. FFTPlan: rejected

A one-entry immutable plan cached the bit-reversal permutation and per-stage
twiddle data for repeated transforms of the same shape. The closest variant,
with every twiddle precomputed, still measured 829 ms versus the 705 ms
baseline (17.6% slower); retaining only per-stage steps measured 1119 ms
(58.7% slower). Both produced the identical checksum and `3.21e-11` maximum
round-trip error, and the compiled Sci smoke test passed. On the current
compiler, instance-method/field and list-lookup overhead dominates the saved
shape setup. No FFT production source from this experiment is retained; the
benchmark remains as a regression target for revisiting it after typed-call
specialization or a flat native-buffer plan exists.

## 22a. Rational multiplication: retained

Canonical Rational operands are reduced before arithmetic. Multiplication
already computes `gcd(an, bd)` and `gcd(bn, ad)` and divides those factors out
before forming its result, which proves the two output products coprime. The
old representation finalizer immediately repeated a full-width GCD over those
products. The retained path boxes this proven-coprime pair directly; general
construction and addition/subtraction still use the normalizing finalizer.

Five alternating matched runs of `rational_mul_coprime_finish.w` produced
these median nanoseconds per product:

| operand width | baseline | retained | speedup |
|---:|---:|---:|---:|
| 128 bits | 964 | 357 | 2.70x |
| 512 bits | 4,008 | 522 | 7.68x |
| 2,048 bits | 38,313 | 2,414 | 15.9x |
| 8,192 bits | 454,111 | 8,472 | 53.6x |

Every before/after checksum matched. The compiled Rational spec passes all 65
checks, including an exhaustive comparison of 29,241 signed small products
against independently normalized `Rational.new(an*bn, ad*bd)` values.

## Final focused validation

The final campaign tree compiled and ran all of the following successfully:
`calculus_spec`, `algebra_polynomial_spec`,
`algebra_arithmetic_circuit_spec`, `algebra_lattice_reduction_spec`,
`optim_spec`, the Sci smoke spec, `algebra_polynomial_gcd_modular_spec`,
`algebra_polynomial_specialize_spec`, `algebra_finite_factor_spec`,
`algebra_finite_field_spec`, `algebra_polynomial_matrix_spec`, and
`numeric/rational_spec`.
