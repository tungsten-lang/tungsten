# Native C3-preserving GPU bundle

This directory contains checked-in, dimension-specialized Tungsten and Metal
workers for square 3x3 through 7x7 matrix-multiplication tensors. A FlipFleet
campaign selects them through `flipfleet_c3_bundle.w`; Python is not involved
in compilation, dispatch, verification, or candidate adoption.

| tensor | capacity | factor storage | naive headroom |
|---|---:|---:|---:|
| 3x3 | 56 | i32 | 29 |
| 4x4 | 88 | i32 | 24 |
| 5x5 | 152 | i32 | 27 |
| 6x6 | 240 | i64 | 24 |
| 7x7 | 368 | i64 | 25 |

Every mutation in `c3_walk` is a complete orbit toggle for

`(u, v, w) -> (v, transpose(w), transpose(u))`.

That applies to ordinary quotient flips and to the periodic any-axis split.
The host checks the seed before dispatch and the copied-back winner before it
can rewrite the output. Both gates require:

- nonzero, in-range, duplicate-free factors;
- exhaustive reconstruction of every tensor coordinate over GF(2); and
- closure under the C3 action.

The output is cleared before Metal dispatch and remains empty if any candidate
gate fails. Runs are finite scheduling epochs: walkers, per-dispatch steps,
dispatch count, band, and split period have hard native limits.

This is an active `flipfleet_native.w` engine whenever the tensor profile has
an exact C3 seed. It keeps C3-only exploration separate from the ordinary
rank-then-density leader; a C3 candidate still passes the coordinator's second
exhaustive gate before adoption.

`c3_gpu_worker_gen.py` is a development-only source generator. It was used to
materialize these assets; a campaign must never invoke it. To refresh an asset,
generate its `.w` with the documented capacity, compile it once with
`TUNGSTEN_LL_PATH` targeting the matching path in this directory, retain only
the resulting `.w` and `.metal`, and compile all five variants before review.
