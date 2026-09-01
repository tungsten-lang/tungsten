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
| 21. Reusable FFTPlan | 600 forward/inverse pairs, n=1024 | 705 ms | 1119 ms | rejected, 1.59x slower | identical checksum `1150.5357900443466`; max round-trip error `3.21e-11`; Sci smoke passed |

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
