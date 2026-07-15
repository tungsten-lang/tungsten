# Exact archive-nullspace closure for 2x2x5

`flipfleet_rect_archive_nullspace.w` now exposes two bounded, pure-Tungsten
operations in addition to the single-best `ffran_crossover` selector:

- `ffran_enumerate_children` visits every nonzero kernel combination for a
  low-nullity parent pair, rejects the full parent difference, materializes
  every proper relation, independently verifies the complete rectangular
  tensor, and appends only permutation-invariant-distinct term sets.
- `ffran_archive_closure` runs that operation breadth first.  The first pass
  audits the initial archive; later passes audit only pairs touching the prior
  pass's frontier.  Pass, pair, nullity, per-pair relation, and total archive
  caps are independent and reported in metadata.

The implementation deliberately uses full term-set comparison for archive
deduplication.  No probabilistic fingerprint is allowed to suppress a rare
exact child.

## Regression controls

`flipfleet_rect_archive_nullspace_closure_test.w` uses the known 4x4x5
d655/d628 pair.  Its difference has nullity 6, hence 63 nonzero kernel
relations.  One is the full parent difference; the test materializes all 62
proper children, verifies all 62 exactly, proves all 64 archive term sets
(parents included) are distinct, and then reruns the hull to account for all
62 as duplicates.  Separate checks exercise relation, child, pair, and archive
caps.

Build and run:

```sh
tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_archive_nullspace_closure_test.w \
  -o /tmp/ffran-closure-test
/tmp/ffran-closure-test
```

## Complete five-door 2x2x5 result

The bounded benchmark starts from:

1. `matmul_2x2x5_rank18_d84_gf2.txt`
2. `matmul_2x2x5_rank18_d88_gf2.txt`
3. `matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt`
4. `matmul_2x2x5_rank18_d84_block_splice_gf2.txt`
5. `matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt`

The closure saturates after two breadth-first passes:

```text
initial=5 final=7 added=2 passes=2 pairs=21
relations=18 proper=12 exact=12 duplicates=10
minimum_rank=18 rank17=0 nullity_max=2 failures=0 elapsed_ms=2
```

The two children omitted by the old single-best interface are:

```text
rank18 d92 pairs16 distances=22/36/14/36/24
rank18 d84 pairs15 distances=14/36/24/28/14
```

Distances are in the five-door order above.  Pairing both children back
against the full seven-element archive produces only already-known term sets;
there is no third frontier layer and no rank-17 decomposition.

Run the complete closure with:

```sh
tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_archive_nullspace_closure_bench.w \
  -o /tmp/ff225-archive-closure
/tmp/ff225-archive-closure 8 4096 100000 16 65535 \
  /tmp/ff225-archive-nullspace-best.txt
```

## Continuation value

As a matched shallow continuation check, each of the five input doors and two
new children received eight independent 20,000,000-move rectangular CPU
campaigns: 1,120,000,000 total moves.  Every output remained rank 18 at its
starting density and at term-set distance zero from its seed.  There were zero
rank drops and zero density improvements.

The enumerator and closure remain useful offline audit tools, especially when
new archive doors appear, but this 2x2x5 result does not justify spending a
default CPU or GPU pool lane on the move.  Reconsider integration only when a
new pair yields a rank drop, a materially separated low-density child, or
measurable downstream continuation wins.
