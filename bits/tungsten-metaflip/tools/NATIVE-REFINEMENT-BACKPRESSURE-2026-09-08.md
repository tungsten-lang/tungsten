# Bounded composition backlog and useful-parent screen — 2026-09-08

Follow-up to `fcdc25d8`. This adds backpressure to automatic refinement, not
a rank record or a complete disk quota. Every submitted source keeps its
durable ticket; a deferred job has no completion manifest and is not counted
as a verification failure.

## Admission reservation

Before writing derived objects, the native worker checks space for the entire
bounded refinement family. A source can produce one matrix-cleaned image,
six basis images and two coordinate sweeps, plus the original parent. Every
parent can add at most nine pair-composition recipes. The reservation is

```text
9 * (8 + 2 * sum(d for each original dimension d > 1)).
```

Deduplication can only reduce this amount. The worker also checks the actual
output count against its reservation before submitting any composition
recipes. The shape gate and a focused exhaustive dimension check establish
that all supported narrow inputs reserve at most 1,269 slots. The longest
singleton-axis shape, 1x1x63, actually reserves 1,206; 5x5x5 reserves 342.

The default limit is 4,096 pending composition jobs. Environment variable
`METAFLIP_COMPOSITION_PENDING` accepts 1,269..1,000,000, or zero for an unlimited
control. Invalid values use the default. The setting is inherited by the
native child; there is no new runtime dependency or external quota scan.

If the reservation cannot fit, the worker atomically records the source ticket
and required capacity in `MFR_PRESSURE1`, then returns without expanding it.
The coordinator recognizes this as backpressure, prioritizes composition
even with source jobs waiting, and retries once capacity becomes available.
It reads fresh completion counters when the child exits. Status fields
`refine_blocked` and `compose_limit`, plus the TUI's `blocked` indicator, make
this state visible. Existing over-limit queues drain without deleting work.

A two-source batch may finish one job and defer the next. A restart also
honors the marker. Up to nine task records committed before a lost submission
cursor count against the reservation, even before that cursor is repaired.
A real input error clears the old pause marker and reports failure; it must
not be hidden as a successful deferral.

The pending limit applies to automatic/source-job expansion, not manual spool
edits or unrelated offline tools. It does not bound the number of original
source tickets, completed objects, elapsed work or total disk bytes. If
composition encounters an invalid/over-budget recipe, its visible error can
also keep new source expansion paused. Ordinary CPU/GPU flipping remains
independent. No same-rank candidate is discarded by this policy.

## Focused checks

- Enumerate every narrow dimension triple through 63, checking the source
  gate and reservation bound, including singleton axes and invalid shapes.
- Seed 927 exact pending recipes; defer the r94 projection source twice with
  no derived writes, no result manifest, no counter advance and no lost input.
- Recover occupancy from eight task records beyond a lost submitted cursor:
  the apparent capacity fits but true occupancy exceeds the limit by one,
  so the job must remain deferred.
- Distinguish a corrupt source from a resource pause and preserve both source
  tickets when only the first job of a two-source batch completes.
- Restart the actual coordinator with that source still pending, drain
  composition, resume expansion, and independently verify every completed
  tensor. Verify that no child survives shutdown.
- Run the explicit unlimited control. Existing queue/migration/repricing,
  packed composition and priority behavior remain covered by their focused
  tests. Public square/rectangular restart, disabled refinement, interrupt
  and raw-TUI reset checks pass.
- Runtime inventory checks cover all 318 file digests and 169 source entries;
  generated GPU sidecars remain excluded.

Replay the focused admission test from the repository root:

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/refinement_backpressure_test.w \
  --out /tmp/metaflip-backpressure-test --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/refinement_backpressure_test.py \
  /tmp/metaflip-backpressure-test /path/to/4x8x4-r94.txt
python3 -B bits/tungsten-metaflip/spec/refinement_backpressure_canary.py \
  bits/tungsten-metaflip/bin/metaflip
```

The external fixture is the same hash-pinned r94 parent used by the preceding
[priority audit](NATIVE-COMPOSITION-PRIORITY-2026-09-08.md).

## Short public canary

Rebuilt release/native binary SHA-256:
`838314cf71f820f2fe63d47b7f561d9a27c33301ba67933ffe2772c0596f08d0`.
With a 1,269 pending limit, one low-priority CPU worker, no GPU, 65,536-step
epochs and a 15-second bound, the run reported 1,139,408,896 moves. It completed
5/12 source jobs and 70/1,116 composition jobs, using three feedback seeds.
All 134 narrow objects and all 70 completed compositions verified exactly;
there were no failures or leftover owned children.

At 50ms sampling intervals, 309 samples observed a peak of 1,098 pending
composition jobs and an active backpressure marker. At shutdown, seven
originals and 1,046 compositions were still pending, not completed. The
temporary spool held 614 files / 4,717,977 logical bytes and was removed after
the audit. Different candidate trajectories and work counts prevent treating
this as a matched speed or storage comparison with earlier canaries.

## Bounded search results: no new best-known shape

A 3x4x5/r47 parent was walked under a 3x3x1 composition objective. Ordinary,
greedy and annealed controls each used 16 trials of 64 x 16,384 attempts,
observing every 256 moves, with seed 81,743, rank debt 2 and density slack 8.
All three improved their starting price 420 to 419. One 9x12x5/r419 product
was fully materialized and independently checked (419 terms, 3,426 support
pair XORs). Its raw SHA-256 is
`6fd8e7a69320604c97470966563aff3e356f7bb4a644e017a4c4ed1be13409cc`.
The retained comparison for the dimension-sorted shape is already 377, so
this is not an improvement to the local best-known table.

A subsequent packaged-parent screen ranked pair opportunities by their gap
to the retained composition table. Two near-bound families received bounded
ordinary walks, each 32 trials of 128 x 16,384 attempts, observing every 256,
with debt 2 and density slack 8:

| Parent | Seed | Target | Starting price | Retained comparator | Final price |
| --- | ---: | --- | ---: | ---: | ---: |
| 3x5x7/r79 | 92,381 | 3x20x28 | 1,240 | 1,240 | 1,240 |
| 3x4x6/r54 | 92,817 | 3x12x18 | 486 | 485 | 486 |

Only the second-factor grouping received pair discounts; the other two
axes retained the same target's naive expansion cost. These are exact
constructible prices, not rank lower bounds. Together the two walks attempted
134,217,728 moves. Across all three parent families and controls, the total
was 184,549,376 attempts, with no new best-known result.

The latter walks' 34 distinct endpoints/retained tensors then underwent
native cleanup, basis refinement and coordinate projection. All 1,009 narrow
objects passed an independent full tensor check. Neither target price nor
any projected primitive minimum improved its retained bound. These are
bounded negative results, not search-exhaustion or optimality claims. No
unbounded search, GPU job, seed promotion, publication or push was performed.
