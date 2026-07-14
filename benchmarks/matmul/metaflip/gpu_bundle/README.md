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
When that gate rejects a nominal improvement, the worker writes candidate,
seed, and metadata sidecars (metadata last as the commit marker). The metadata
contains the worker generation/round and the first exact syndrome coordinate;
`flipfleet_native.w` independently verifies and freezes strict-target failures
with its own launch nonce before reusing the physical slot.

The rounds argument bounds the number of dispatch rounds in one adaptive
epoch; the following optional argument names an offline-compiled `.metallib`.
Generic roles may use distinct exact seed files and schedules;
C3-preserving, cooperative-SIMD, and MITM roles remain separate engines.
`flipfleet_native.w` builds this bundle on demand and uses it for the active
rank, density, split, fixed-cube, orbit, polarization, composition, and novelty
roles. Its coordinator repeats the exhaustive gate before adoption.

The assets are regenerated deliberately at development time with
`benchmarks/matmul/zoo/gpu_cal2zone_gen.py`. Native campaigns compile the
checked-in `.w` source and `.metal` sidecar once, cache the latter beside the
worker as `worker.metallib`, and load that library in subsequent adaptive
children. Stable generic allocations may additionally keep one worker alive
through the generation-numbered mailbox protocol; lane or engine rotations
restart it, while other engines retain bounded-child isolation.
