# Native cal2zone bundle

These are checked-in, dimension-specialized Tungsten/Metal workers for the
generic FlipFleet GPU roles. A campaign selects them through
`flipfleet_gpu_bundle.w`; it does not run a Python generator.

| Tensor | CAP | WPG | mask | threadgroup memory |
|---|---:|---:|---:|---:|
| 3x3 | 59 | 16 | i32 | 11,328 B |
| 4x4 | 96 | 16 | i32 | 18,432 B |
| 5x5 | 157 | 16 | i32 | 30,144 B |
| 6x6 | 248 | 4 | i64 | 23,808 B |
| 7x7 | 375 | 2 | i64 | 18,000 B |

CAP holds the naive decomposition plus 32 excursion terms. Every WPG divides
the fleet scheduler's 32-lane allocation quantum. The 6x6 and 7x7 workers use
i64 masks; 7x7 additionally keeps decimal parsing and Metal transfers on raw
i64 views to avoid boxed-integer truncation.

Candidate adoption is deterministic: the host copies the candidate once,
rejects zero or out-of-range factors, and reconstructs every tensor coordinate
over GF(2). The old 40-random-evaluation check is not used by these assets.

The final positional argument bounds the number of dispatch rounds in one
adaptive epoch. Generic roles may use distinct exact seed files and schedules;
C3-preserving, cooperative-SIMD, and MITM roles remain separate engines.
`flipfleet_native.w` builds this bundle on demand and uses it for the active
rank, density, split, fixed-cube, orbit, polarization, composition, and novelty
roles. Its coordinator repeats the exhaustive gate before adoption.

The assets are regenerated deliberately at development time with
`benchmarks/matmul/zoo/gpu_cal2zone_gen.py`. Native campaigns only compile the
checked-in `.w` source (when a cached binary is absent) and load its checked-in
`.metal` sidecar.
