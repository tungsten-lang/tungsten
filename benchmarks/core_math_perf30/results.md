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

Rejected or deferred experiments are recorded below with their reason; they
are not left in production source.
