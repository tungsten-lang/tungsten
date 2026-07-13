# GPU meet-in-the-middle surgery scout

> Historical prototype note: this document describes the earlier Python
> adapter around `gpu_mitm_worker.w`. The pure-Tungsten fleet implementation is
> now `flipfleet_mitm_lane.w` / `flipfleet_mitm_lane_lib.w`; it builds candidate
> fingerprints, reconstructs hits, and performs the exhaustive acceptance gate
> without Python. See `FLIPFLEET_MITM_NATIVE.md` for the native ABI and tests.

`gpu_mitm_surgery.py` is a bounded 5-term to 4-term local-surgery role for
FlipFleet.  Its generated `gpu_mitm_worker.w` executable supports square
matrix-multiplication tensors from 3x3 through 7x7.

## Search boundary and exactness

For each guided five-term subset, the scout builds the same finite candidate
family as `mitm_surgery.py`: selected factors, pairwise factor XORs, and a
bounded number of nearby factors.  It then:

1. expands every candidate rank-one tensor and computes a linear 128-bit
   fingerprint on the CPU;
2. enumerates every unordered candidate-pair fingerprint on Metal;
3. builds a collision-preserving, load-at-most-one-half hash table in native
   Tungsten host code;
4. probes target-complement pair fingerprints on Metal; and
5. checks every reported hit using complete tensor signatures, splices it into
   the original scheme, and reconstructs the full matrix-multiplication tensor
   in Python.

Consequently a reported output is exact, but a miss is **not** a lower-bound
certificate.  The candidate family is finite, and each query retains at most
four equal-fingerprint matches.  Fingerprint compression can only cause a
miss; it cannot cause a false accepted scheme because steps 5 gates output.

Tungsten's current `@gpu` subset does not expose device atomic
compare-exchange.  This prevents a safe concurrent on-device hash-table build;
table construction therefore remains on the Tungsten host while both regular
quadratic phases run on Metal.  No compiler extension is required for this
version.  A separate compiler edge narrows a parsed BigInt assigned to an
`i64[]` through the inline-i48 path, so the 128-bit fingerprint is carried as
four lossless `u32` words.  That representation is also faster on Metal.

## FlipFleet adapter

```python
from gpu_mitm_surgery import GpuMitmFleetAdapter

role = GpuMitmFleetAdapter(6, max_pool=700, workdir=fleet_dir)
role.build()
plan = role.launch(seed_path, exact_output_path, lane_budget=490_000)
status = role.poll()
role.terminate()
```

`lane_budget` means logical Metal invocations.  A pool-P subset dispatches
exactly P^2 threads; by default the budget planner divides work across four
guided subsets for approach diversity.  Successive launches from an unchanged
seed advance through the deterministic guided-subset beam (with a bounded
wraparound) and cycle nearby-factor depth, rather than repeating the same
first four subsets.  `poll()` reports the chosen plan and only marks a hit when
a nonempty, fully verified bare scheme exists.

The unified `flipfleet.py --gpu-policy adaptive` includes this adapter by
default.  Its tensor-specific fraction is deliberately small because host hash
construction competes with the CPU walkers; adaptive rewards can expand the
role if it produces an exact rank drop or useful frontier candidate.

## M5 Max smoke results

Measured July 11, 2026, after the one-time approximately six-second Tungsten
compile:

- planted four-term identity: exact Metal hit, full-signature acceptance;
- 4x4 rank-47/density-450, pool 700: 244,650 unordered pair sums, 1.56 s
  end-to-end (3 ms Metal enumeration, 1.42 s host table, 85 ms Metal probe),
  no hit for the first guided subset;
- 6x6 rank-153/density-2508, pool 180: 0.089 s cached in-process search, no hit
  for the first guided subset;
- asynchronous adapter, 4x4/pool 180/four subsets: 0.273 s campaign, clean
  miss and no stale output file.

These misses are bounded experiments, not proofs.
