# Core Math Perf30 Results

Baseline commit: `43642a9de2dca0ab455cef7e49deb69b70d86066`

All timings are compiled native Tungsten wall-clock measurements on the same
local host. Each row records the median of repeated process runs unless noted.
Correctness is checked by the benchmark checksum and the focused Core spec.

| Item | Workload | Before | After | Result | Correctness |
|---|---|---:|---:|---|---|
| 13. Differential add accessor hoist | 120 additions, dimension 20, full Hessian | 262 ms | 5 ms | retained, 52.4x | checksum `844`; compiled `spec/core/calculus_spec.w` passed |
| 14. Sparse gap-Horner | 12 evaluations, degree 5000, 1001 terms over F_1000003 | 1701 ms | 1 ms | retained, >850x | checksum `575521`; compiled `spec/core/algebra_polynomial_spec.w` passed |
| 15. Arithmetic-circuit evaluation tape | 2000 evaluations, 402-node reachable DAG | 150 ms | 27 ms | retained, 5.56x | checksum `814000`; compiled `spec/core/algebra_arithmetic_circuit_spec.w` passed |
| 16. Incremental approximate LLL | 8 rank-14 reductions, dense identity Gram | 925 ms | 10 ms | retained, 92.5x | checksum `1379`, 13 steps, swap parity; compiled `spec/core/algebra_lattice_reduction_spec.w` passed |
| 17. Damped Gauss-Newton/LM least squares | 5 dimension-16 linear solves to <1e-10 objective | 127 ms | 3 ms | retained, 42.3x and lower error | checksum near `374`; new FD/analytic/nonlinear spec and `spec/sci/smoke_spec.w` passed |
| 18. Polynomial substitution plan | 30 specializations, 1152 terms to 48 groups over F_65537 | 36 ms | 1 ms | retained, >36x | checksum `59040`; polynomial, modular-GCD, and specialization specs passed |
| 19. Direct finite-factor candidate construction | 10000 dense degree-20 candidates over F_2 | 94 ms | 15 ms | retained, 6.27x | checksum `211`; compiled `spec/core/algebra_finite_factor_spec.w` passed |
| 20. Prepared inverse/Frobenius tables | 1000 complete nonzero sweeps of F_2^8 | 176 ms | 48 ms | retained, 3.67x | every inverse product and Frobenius round-trip checked; finite-field spec passed |
| 21. Reusable FFTPlan | 600 forward/inverse pairs, n=1024 | 705 ms | 829 ms | rejected, 17.6% slower | identical checksum `1150.5357900443466`; max round-trip error `3.21e-11`; Sci smoke passed |
| 22a. Coprime Rational multiplication finish | Repeated products of canonical 128/512/2048/8192-bit Rational operands | 964/4008/38313/454111 ns | 357/522/2414/8472 ns | retained, 2.70x/7.68x/15.9x/53.6x | identical checksums; compiled Rational spec plus 29,241 exhaustive signed small products passed |
| 22b. Fraction-free polynomial-matrix determinant | 12 determinants of dense 7x7 `zI + J` over F_1009 | 109 ms | 5 ms | retained, 21.8x | exact closed form `z^6(z+7)`, checksum `96`; compiled polynomial-matrix spec passed |

Rejected or deferred experiments are recorded below with their reason; they
are not left in production source.

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
