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

Rejected or deferred experiments are recorded below with their reason; they
are not left in production source.
