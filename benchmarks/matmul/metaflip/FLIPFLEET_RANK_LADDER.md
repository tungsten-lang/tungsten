# Exact rank-debt ladder experiment

## Result

The k=2 ladder is implemented and exact, but the measured 4x4 strategy does
**not** merit a production GPU-pool slot yet.

On both checked-in rank-47 basins, a larger bounded CPU run opened 128 exact
R+2 shoulders and attempted 5,199 closure neighborhoods.  It admitted 265
nonincreasing states and reached rank 48, but produced no novel rank-47 return
and no rank-46 improvement.  A separate GPU audit sent the same construction
to the production 6->5, 7->6, 8->7, and 9->8 k-XOR joins.  All 64 GPU searches
returned an exact rank-48 result; every result was exactly one of the two
blocked single-opener reversals.

The useful conclusion is sharper than a generic search negative: without the
reversal gate, the GPU lane would report a 100% hit rate while doing no useful
work.  Rank reduction alone is therefore not sufficient reward for a debt
ladder.  A candidate must also differ from the origin and both one-opener
rollback states.

## Construction and safety rules

`flipfleet_rank_ladder.w` is a standalone pure-Tungsten controller.  It does
not modify `flipfleet_native.w` or the kernel-pool policy.

1. Two explicit `ffe_split_with_part` identities open a shoulder.
2. Rank is measured after every GF(2) parity toggle.  The opener is accepted
   only if the first split is actually +1 and the composition is actually +2.
3. The exact R+1 state obtained by reversing either individual opener is
   materialized and retained as a forbidden state.
4. Closing edges may preserve or reduce rank, but may never increase it or
   exceed the opened R+2 ceiling.
5. The exact origin, either one-opener rollback, no-ops, and duplicate beam
   states are rejected.
6. Every admitted state passes complete n^6 tensor reconstruction.
7. Telemetry separately counts frontier returns, novel same-rank returns,
   strict improvements, neutral/reducing edges, reversal/origin rejects, and
   exact-gate failures.

The host closing alphabet reuses complete 3->2 and 4->3 factor-span
refactoring, 3->3 neutral refactoring, and low-rank absorbed shear.  Direct
2->1 factor-line closure is the exact reverse of the split identity.  The
separate GPU benchmark reuses the existing production k-XOR implementation;
no duplicate shader was added.

## Regression coverage

`flipfleet_rank_ladder_test.w` checks:

- a measured, independently exact +2 opener;
- both exact R+1 rollback states;
- rejection of immediate reversal and the exact origin;
- rejection of a third exact split during closing;
- rejection of a deliberately inexact current view;
- correct return/novelty telemetry for a planted exact same-rank flip;
- a parity-collision fixture where a nominal split call is actually -1; and
- a bounded end-to-end 3x3 search.

The 3x3 smoke is a positive controller control: two openers, 39 closure
searches, and 22 admitted states produced five exact novel rank-27 returns.
The 4x4 failure to return is therefore not caused by a controller that can
only reject candidates.

Build and run:

```sh
TUNGSTEN_LL_PATH=/tmp/flipfleet_rank_ladder_test.ll \
  bin/tungsten compile --release --native --fast --lto \
  -o /tmp/flipfleet_rank_ladder_test \
  benchmarks/matmul/metaflip/flipfleet_rank_ladder_test.w
/tmp/flipfleet_rank_ladder_test
```

## 4x4 CPU benchmark

The larger recorded run was:

```sh
/tmp/flipfleet_rank_ladder_bench 32 3 12 12 2 6 1
```

Arguments are opener count, closure depth, beam width, 3-span budget, 4-span
budget, neutral 3-span budget, and absorbed-shear budget.  Each rank-47 basin
is tested with a reduction-only arm and a mixed arm.

| seed | arm | exact opens | searches | admitted | best | returns | improvements | time |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| d450 | down | 32/32 | 512 | 0 | none | 0 | 0 | 1.212 s |
| d450 | mixed | 32/32 | 2,303 | 157 | 48 | 0 | 0 | 6.025 s |
| d677 | down | 32/32 | 512 | 0 | none | 0 | 0 | 1.548 s |
| d677 | mixed | 32/32 | 1,872 | 108 | 48 | 0 | 0 | 5.849 s |

All 128 openers measured exactly +2.  Across the mixed arms, 94 neutral and
171 reducing states were admitted.  There were no exhaustive-verification
failures.  Reduction-only hits were exclusively trivial rollback states;
neutral rearrangement created nontrivial R+2/R+1 paths, but none paid the
second rank of debt.

## 4x4 GPU k-XOR benchmark

The recorded GPU audit was:

```sh
/tmp/flipfleet_rank_ladder_kxor_bench 8 16 9
```

This tested eight openers in each rank-47 basin, sixteen subsets per join, and
every production k-XOR cardinality from 6->5 through 9->8.

| metric | d450 | d677 | total |
|---|---:|---:|---:|
| exact R+2 openers | 8 | 8 | 16 |
| GPU searches | 32 | 32 | 64 |
| exact R+1 GPU hits | 32 | 32 | 64 |
| nontrivial admitted hits | 0 | 0 | 0 |
| rollback rejects | 32 | 32 | 64 |
| novel returns / improvements | 0 / 0 | 0 / 0 | 0 / 0 |

Every worker output passed its existing exact gate and the independent ladder
gate.  The negative is structural: the join always rediscovered a planted
split inverse before any deeper surgery.

## Integration decision

Do not add a rank-ladder mode to the rotating GPU pool from this evidence.
Keep the standalone implementation as a preflight and regression tool.  A
future tensor or opener family should earn integration only if a bounded host
preflight produces at least one exact, non-forbidden R+1 child or a novel
frontier return.  If that happens, the existing k-XOR pool kernels can consume
the admitted seeds directly; no new GPU algebra is required.
