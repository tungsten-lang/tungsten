# Native FlipFleet GPU MITM lane

`flipfleet_mitm_lane.w` is the pure-Tungsten 5-to-4 local-surgery lane. It
loads an exact scheme, chooses bounded five-term neighborhoods, constructs the
candidate factors and 128-bit linear tensor fingerprints in Tungsten,
dispatches pair enumeration and complementary probes to Metal, reconstructs
reported joins, and exhaustively verifies the complete spliced scheme before
writing an output. No Python process participates in build planning, request
construction, hit reconstruction, or acceptance.

The implementation is runtime-generic for square matrix tensors 3x3 through
7x7. `flipfleet_mitm_lane_lib.w` is the coordinator-facing API:

```
ffm_search(seed, out, n, subsets, pool, nearby, subset_offset, metal_path)
ffm_search_exact_subset(seed, out, n, pool, nearby, indices, metal_path)
ffm_build(root, binary)
ffm_epoch_command(root, binary, seed, out, n, subsets, pool, nearby, offset)
```

An importing binary must pass its own generated `.metal` sidecar. The
standalone wrapper passes
`benchmarks/matmul/metaflip/flipfleet_mitm_lane.metal`; an importing native
coordinator passes its corresponding `flipfleet_native.metal` path.
`ffm_build` and `ffm_epoch_command` provide the alternative child-process
lifecycle used by the current native GPU scheduler; both commands are native
and contain no Python adapter.

This engine is integrated into rotating pool role 10 in `flipfleet_native.w`.
Each finite epoch advances the subset offset, exact-gates any reported splice,
and feeds the same native reward/reallocation accounting as the generic, C3,
and SIMD engines. A build or launch failure removes its lanes and is visible
as degraded GPU coverage.

The child-process lifecycle is preferred for repeated fleet epochs. The
current Metal bridge retains buffer handles until process exit, while one
maximum-pool subset owns roughly 50 MiB of shared arrays. Direct in-process
`ffm_search` is therefore intended for a bounded one-shot call unless the
coordinator supplies a resident buffer-reuse layer.

The standalone ABI is:

```
flipfleet_mitm_lane seed out n [subsets=4] [pool=180] [nearby=2]
                    [subset_offset=0] [i0,i1,i2,i3,i4]
```

The final comma-separated argument selects one explicit five-term set for a
reproducible diagnostic. Campaign launches omit it and advance the subset
offset.

## Boundedness and exactness

- dimensions: 3 through 7;
- subsets per process: 1 through 16;
- candidate pool: 4 through 700;
- nearby factors per axis: 0 through 8;
- logical Metal work: `subsets * pool * pool` threads;
- pair table: the next power of two holding all unordered pairs at load at
  most one half; and
- at most 16 equal-fingerprint complementary pairs retained per query.

The last bound makes a miss a bounded experiment, not a lower-bound proof.
It cannot create a false result. Every fingerprint hit first passes a complete
coefficient check on the five-term target versus the four-term replacement.
The spliced full scheme then passes `ffw_init_terms_cap`'s exhaustive n^6 gate,
and `ffw_dump_best` repeats that exhaustive gate immediately before the file
write. A miss leaves an empty output file.

The 128-bit projection exactly matches the reference XOR-fold: each 128-bit
tensor chunk is rotated left by 29 bits per chunk before folding. It is
computed directly from rank-one support, so Tungsten never needs an n^6-bit
boxed integer.

No compiler extension is required for this lane. Device atomic compare/exchange
would allow a future on-device table build. In the July 12 fleet profile, a
362-candidate/65,341-pair subset spent about 4 ms enumerating on Metal, 343 ms
building the collision-preserving table on the host, and 22 ms probing on
Metal. The host build is therefore the dominant per-subset cost at practical
pool sizes; keep epochs bounded so this experimental mode rotates promptly.

## Native verification

```
TUNGSTEN_GPU_DIALECTS=none bin/tungsten -o /tmp/ffm-test \
  benchmarks/matmul/metaflip/flipfleet_mitm_lane_test.w \
  --release --native --fast
/tmp/ffm-test
```

The test covers plan limits for every dimension, cross-language fingerprint
vectors including a 7x7 high-bit vector, bounded candidate construction, local
exact reconstruction, and a full exhaustive 3x3 splice/reload.

The deterministic Metal smoke uses the checked-in rank-28 planted scheme:

```
TUNGSTEN_GPU_DIALECTS=none bin/tungsten -o /tmp/ffm \
  benchmarks/matmul/metaflip/flipfleet_mitm_lane.w \
  --release --native --fast
/tmp/ffm benchmarks/matmul/metaflip/mitm_planted_3x3_rank28_gf2.txt \
  /tmp/ffm-hit.txt 3 1 64 2 0 0,1,2,3,4
```

On the M5 Max this produced one fingerprint hit, one exact check, and an
exhaustively verified rank-27 output (4 ms pair enumeration and 1 ms probe in
the measured run).
