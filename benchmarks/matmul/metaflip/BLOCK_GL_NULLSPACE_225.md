# Exhaustive block-GL nullspace audit for `<2,2,5>`

## Scope

The certified GF(2) interval for `<2,2,5>` is 17--18.  The production profile
has five exact rank-18 doors:

1. d84, the density leader;
2. the zero-overlap d88 door;
3. the independently transformed `3+2` block construction at d92;
4. the proper d84 splice between the first and third doors;
5. a second d84 block tunnel discovered by the corrected rectangular GPU
   engine and independently replayed by the host gate.

`flipfleet_225_block_nullspace_scan.w` tests whether the full deterministic
block-local GL family contains a rank-17 parent-difference hybrid or another
rank-18 presentation sufficiently independent to justify a sixth door.  It is
pure Tungsten and does not modify the fleet schedule or TUI.

The shared generator in `flipfleet_225_block_gl_parent_lib.w` uses exactly the
nonces, sparse-leaf move counts, rank-11 `<2,2,3>` leaf, rank-7 Strassen leaf,
and `3+2` block embedding of `flipfleet_225_block_gl_bank.w`.

## Complete enumeration

Build and replay:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_block_nullspace_scan_test.w \
  -o /tmp/ff225-block-nullspace-test
/tmp/ff225-block-nullspace-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_block_nullspace_scan.w \
  -o /tmp/ff225-block-nullspace-scan
/tmp/ff225-block-nullspace-scan 4096 \
  /tmp/ff225-block-nullspace-4096-best.txt
```

For every generated parent and each of the five doors, the scanner builds the
complete symmetric difference, expands every term into the 400 tensor
coefficients, and runs `ffran_build_nullspace`.  Nullity never exceeded four,
so every nonzero dependency combination was exhaustively enumerated; no pair
used a cap or sample.  Each relation was replayed against the complete tensor.
The `ffran_crossover` path independently selected and exact-gated the minimum
child of every union with a proper relation.

Measured July 14, 2026 totals:

| measurement | result |
|---|---:|
| exact block parents | 4,096 |
| parent/door pairs | 20,480 |
| identical pair | 1 |
| nonidentical pairs exhausted | 20,479 |
| difference size | 10--36; mean 35.269 |
| nullity histogram | 1: 4,539; 2: 15,904; 3: 27; 4: 9 |
| full-difference-only pairs | 4,539 |
| pairs with a proper hybrid | 15,940 |
| nonzero dependency combinations | 52,575 |
| proper relations | 32,096 |
| rank-18 proper relations | 32,096 |
| projected or exact rank-17 relations | **0** |
| `ffran_crossover` exact rank-18 children | 15,940 |
| relation or exact-gate failures | 0 |

Every proper pair had minimum hybrid rank 18.  The deterministic regression
test checks parent zero twice, obtains the expected five-door nullity vector
`2/1/2/2/2`, exhausts its thirteen nonzero relations, and independently gates
all eight proper rank-18 outcomes.

## Most novel rank-18 outcome

The most distant proper hybrid was exact rank 18/d105 with ten equal-factor
pairs.  It came from generated parent 1253 (d109, eleven pairs) and the block
d92 door through a nullity-three relation.  Its structural measurements were:

```text
distance to source parent:       4
distance to d84/d88/block/splice/GPU: 36 / 36 / 30 / 36 / 32
union nullities:                      2 / 1 / 2 / 2 / 2
nearest generated block parent:  parent 1253 at distance 4
```

The source parent itself is distance `36/36/34/36/34` from the doors, with
nullities `2/1/3/2/2`.  Thus the hybrid does not expose a new algebraic component:
it is a two-for-two step inside the same block family, is less distant than its
source parent from the retained block door, and has extra proper dependencies
with four of the five production doors.  Its d105 density is also well behind
d84.  This falls short of the conservative sixth-door gate (distance at least
18 from every door, full-difference-only nullity against all five, and distance
at least eight from the deterministic parent bank).

The provisional exact file was written only to
`/tmp/ff225-block-nullspace-4096-best.txt`, SHA-256
`1793b7fb26afac251bdfd60daf8afc0ed2f2899f73ee2db353202b3d764f9c18`.
It is intentionally not checked in as a fleet certificate.

## Decision

This is a useful complete negative.  It rules out rank 17 throughout all
parent-difference nullspaces formed by the 4,096 deterministic block parents
and the current five doors, rather than merely failing to sample a favorable
relation.  No sixth door is added by this deterministic bank scan.  A further search
needs a move outside these binary parent unions, such as a correlated relation
involving two independently generated block parents and a door, rather than a
larger budget on the same pairwise hull.

That correlated follow-up is now complete for a bounded but substantially
larger family. `MULTI_PARENT_NULLSPACE_225.md` exhausts the five-door affine
union with every single block parent and with every pair and triple from a
32-parent maximin archive. Its 11,942,176 affine masks also contain no rank-17
subset. The remaining scale step is low-weight SAT/MITM decoding over the full
archive union, not another pairwise nullspace pass.
